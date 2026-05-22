"""
Moongate — single-file Moonraker component.

Deploy as:  ~/moonraker/moonraker/components/moongate.py

Registers:
  POST /server/moongate/pair    — generate a pairing code (called by MOONGATE_PAIR macro)
  POST /server/moongate/auth    — exchange a pairing code for a JWT + WireGuard config
  GET  /server/moongate/status  — check plugin status  (pass token= in args)
  GET  /server/moongate/tokens  — list active tokens   (pass token= in args)
  POST /server/moongate/revoke  — revoke a token       (pass token= in args)
"""
from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
import random
import re
import string
import subprocess
import time
import uuid
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Optional

logger = logging.getLogger("moonraker.moongate")

# ═══════════════════════════════════════════════════════════════════════════════
# Auth manager
# ═══════════════════════════════════════════════════════════════════════════════

CONFIG_DIR  = Path.home() / ".config" / "moongate"
TOKENS_FILE = CONFIG_DIR / "tokens.json"
SECRET_FILE = CONFIG_DIR / "secret.key"
CONFIG_FILE = CONFIG_DIR / "config.json"

DEFAULT_CONFIG = {
    "default_ttl_days":      30,
    "allow_app_override":    True,
    "pair_code_ttl_seconds": 600,
    "max_pair_attempts":     5,
}

CODE_CHARS = string.digits   # digits only → GATE-1234-5678, easy to type on phone


def _get_local_ip() -> str:
    """Return the Pi's primary LAN IP (used to embed host in the QR URL)."""
    import socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "localhost"


def _get_tunnel_url() -> Optional[str]:
    """
    Return the active Cloudflare quick-tunnel URL, or None if cloudflared
    is not running / not yet ready.  Checks the tunnel log file first,
    then falls back to journalctl.
    """
    import re
    import subprocess

    pattern = re.compile(r'https://[a-z0-9-]+\.trycloudflare\.com')

    # Primary: log file written by the moongate-tunnel systemd service
    log_paths = [
        Path("/run/moongate-tunnel.log"),
        Path("/tmp/moongate-tunnel.log"),
    ]
    for p in log_paths:
        if p.exists():
            try:
                m = pattern.search(p.read_text())
                if m:
                    return m.group(0)
            except Exception:
                pass

    # Fallback: scan journalctl output for the service
    try:
        result = subprocess.run(
            ["journalctl", "-u", "moongate-tunnel", "--no-pager", "-n", "200"],
            capture_output=True, text=True, timeout=5,
        )
        m = pattern.search(result.stdout)
        if m:
            return m.group(0)
    except Exception:
        pass

    return None


@dataclass
class DeviceToken:
    token_id:    str
    device_name: str
    issued_at:   float
    expires_at:  Optional[float]
    last_seen:   float
    revoked:     bool = False

    def is_valid(self) -> bool:
        if self.revoked:
            return False
        if self.expires_at is not None and time.time() > self.expires_at:
            return False
        return True


@dataclass
class PairingCode:
    code:       str
    created_at: float
    expires_at: float
    attempts:   int  = 0
    used:       bool = False

    def is_valid(self) -> bool:
        return not self.used and self.attempts < 5 and time.time() < self.expires_at


def _b64(data: bytes) -> str:
    import base64
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


class AuthManager:
    def __init__(self) -> None:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        self._config         = self._load_config()
        self._secret         = self._load_or_create_secret()
        self._tokens:        dict[str, DeviceToken] = {}
        self._pending_codes: dict[str, PairingCode] = {}
        self._load_tokens()

    def generate_pair_code(self) -> tuple[str, str]:
        """Return (display_code, qr_payload). Format: GATE-XXXX-XXXX."""
        self._sweep_expired_codes()
        part1   = "".join(random.choices(CODE_CHARS, k=4))
        part2   = "".join(random.choices(CODE_CHARS, k=4))
        display = f"GATE-{part1}-{part2}"
        raw     = f"{part1}{part2}"
        ttl     = self._config["pair_code_ttl_seconds"]
        now     = time.time()
        self._pending_codes[raw] = PairingCode(
            code=raw, created_at=now, expires_at=now + ttl
        )
        logger.info("Pairing code generated (expires in %ds)", ttl)
        return display, f"moongate://pair?code={display}"

    def issue_direct_token(
        self,
        device_name: str = "Paired via QR",
        ttl_days: Optional[int] = None,
    ) -> tuple[str, str]:
        """
        Pre-issue a JWT without requiring a code exchange.
        Used for QR-based pairing where the phone may not have direct
        network access to the Pi (e.g. WiFi AP isolation).
        Returns (jwt, token_id).
        """
        if ttl_days is None:
            ttl_days = self._config["default_ttl_days"]
        token_id   = str(uuid.uuid4())
        now        = time.time()
        expires_at = (now + ttl_days * 86400) if ttl_days else None
        token = DeviceToken(
            token_id=token_id, device_name=device_name,
            issued_at=now, expires_at=expires_at, last_seen=now,
        )
        self._tokens[token_id] = token
        self._save_tokens()
        jwt = self._sign_token(token_id, expires_at)
        logger.info("Direct (QR) token issued for '%s' (id=%s)", device_name, token_id)
        return jwt, token_id

    def exchange_code(
        self,
        raw_code: str,
        device_name: str,
        requested_ttl_days: Optional[int] = None,
    ) -> Optional[tuple[str, str]]:
        """Validate code → (jwt, token_id) or None."""
        # Accept "GATE-1234-5678", "1234-5678", or "12345678"
        normalized = raw_code.upper().replace("-", "").replace("GATE", "")
        entry = self._pending_codes.get(normalized)

        if entry is None or not entry.is_valid():
            if entry:
                entry.attempts += 1
                self._save_tokens()
            logger.warning("Invalid or expired pairing code attempt")
            return None

        entry.used = True
        token_id   = str(uuid.uuid4())
        ttl_days   = self._config["default_ttl_days"]
        if requested_ttl_days is not None and self._config["allow_app_override"]:
            ttl_days = requested_ttl_days

        now        = time.time()
        expires_at = (now + ttl_days * 86400) if ttl_days is not None else None

        token = DeviceToken(
            token_id=token_id, device_name=device_name,
            issued_at=now, expires_at=expires_at, last_seen=now,
        )
        self._tokens[token_id] = token
        self._save_tokens()

        jwt = self._sign_token(token_id, expires_at)
        logger.info("Token issued for '%s' (id=%s)", device_name, token_id)
        return jwt, token_id

    def validate_token(self, jwt: str) -> Optional[str]:
        token_id = self._verify_token(jwt)
        if token_id is None:
            return None
        token = self._tokens.get(token_id)
        if token is None or not token.is_valid():
            return None
        token.last_seen = time.time()
        self._save_tokens()
        return token_id

    def revoke_token(self, token_id: str) -> bool:
        token = self._tokens.get(token_id)
        if token is None:
            return False
        token.revoked = True
        self._save_tokens()
        logger.info("Token revoked: %s", token_id)
        return True

    def list_tokens(self) -> list[dict]:
        return [{**asdict(t), "valid": t.is_valid()} for t in self._tokens.values()]

    # ── JWT (minimal HS256, no external deps) ─────────────────────────────────

    def _sign_token(self, token_id: str, expires_at: Optional[float]) -> str:
        header  = _b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
        payload = _b64(json.dumps({
            "sub": token_id,
            "iat": int(time.time()),
            **({"exp": int(expires_at)} if expires_at else {}),
        }).encode())
        sig = _b64(
            hmac.new(
                self._secret,
                f"{header}.{payload}".encode(),
                hashlib.sha256,
            ).digest()
        )
        return f"{header}.{payload}.{sig}"

    def _verify_token(self, jwt: str) -> Optional[str]:
        import base64
        try:
            header, payload, sig = jwt.split(".")
            expected = _b64(
                hmac.new(
                    self._secret,
                    f"{header}.{payload}".encode(),
                    hashlib.sha256,
                ).digest()
            )
            if not hmac.compare_digest(sig, expected):
                return None
            claims = json.loads(base64.urlsafe_b64decode(payload + "=="))
            exp = claims.get("exp")
            if exp and time.time() > exp:
                return None
            return claims["sub"]
        except Exception:
            return None

    # ── Persistence ───────────────────────────────────────────────────────────

    def _load_config(self) -> dict:
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE) as f:
                    return {**DEFAULT_CONFIG, **json.load(f)}
            except Exception:
                pass
        return DEFAULT_CONFIG.copy()

    def _load_or_create_secret(self) -> bytes:
        if SECRET_FILE.exists():
            return SECRET_FILE.read_bytes()
        secret = os.urandom(32)
        SECRET_FILE.write_bytes(secret)
        SECRET_FILE.chmod(0o600)
        logger.info("New Moongate secret key created at %s", SECRET_FILE)
        return secret

    def _load_tokens(self) -> None:
        if not TOKENS_FILE.exists():
            return
        try:
            with open(TOKENS_FILE) as f:
                data = json.load(f)
            for raw in data.get("tokens", []):
                t = DeviceToken(**raw)
                self._tokens[t.token_id] = t
        except Exception as e:
            logger.error("Failed to load tokens: %s", e)

    def _save_tokens(self) -> None:
        try:
            with open(TOKENS_FILE, "w") as f:
                json.dump(
                    {"tokens": [asdict(t) for t in self._tokens.values()]},
                    f, indent=2,
                )
        except Exception as e:
            logger.error("Failed to save tokens: %s", e)

    def _sweep_expired_codes(self) -> None:
        now = time.time()
        self._pending_codes = {
            k: v for k, v in self._pending_codes.items() if now < v.expires_at
        }


# ═══════════════════════════════════════════════════════════════════════════════
# WireGuard manager
# ═══════════════════════════════════════════════════════════════════════════════

WG_IFACE      = "wg0"
WG_CONF       = f"/etc/wireguard/{WG_IFACE}.conf"
WG_PUB_KEY    = "/etc/wireguard/server_public.key"
VPN_SUBNET    = "10.13.13"
SERVER_VPN_IP = f"{VPN_SUBNET}.1"
PEERS_DB      = Path.home() / ".config" / "moongate" / "peers.json"


class WireGuardManager:
    def __init__(self) -> None:
        PEERS_DB.parent.mkdir(parents=True, exist_ok=True)
        self._peers: dict[str, dict] = self._load_peers()

    def server_public_key(self) -> Optional[str]:
        try:
            return Path(WG_PUB_KEY).read_text().strip()
        except FileNotFoundError:
            return None

    def endpoint(self, configured: Optional[str]) -> Optional[str]:
        if configured:
            ep = configured.strip()
            if ep and ":" not in ep:
                ep = f"{ep}:51820"
            return ep or None
        try:
            result = subprocess.run(
                ["hostname", "-I"], capture_output=True, text=True, timeout=5
            )
            ip = result.stdout.strip().split()[0]
            return f"{ip}:51820"
        except Exception:
            return None

    def add_peer(self, device_id: str, phone_pubkey: str) -> Optional[dict]:
        if self.server_public_key() is None:
            return None
        used   = {p["vpn_ip"] for p in self._peers.values()}
        vpn_ip = None
        for i in range(2, 255):
            candidate = f"{VPN_SUBNET}.{i}"
            if candidate not in used:
                vpn_ip = candidate
                break
        if vpn_ip is None:
            logger.error("No free VPN IPs")
            return None

        peer_block = (
            f"\n[Peer]\n"
            f"# device_id={device_id}\n"
            f"PublicKey  = {phone_pubkey}\n"
            f"AllowedIPs = {vpn_ip}/32\n"
        )
        try:
            with open(WG_CONF, "a") as f:
                f.write(peer_block)
            subprocess.run(
                ["sudo", "wg", "set", WG_IFACE,
                 "peer", phone_pubkey, "allowed-ips", f"{vpn_ip}/32"],
                check=True, timeout=10,
            )
        except Exception as exc:
            logger.warning("Could not add WireGuard peer: %s", exc)
            return None

        self._peers[device_id] = {"pubkey": phone_pubkey, "vpn_ip": vpn_ip}
        self._save_peers()
        logger.info("Added WireGuard peer %s → %s", device_id, vpn_ip)
        return {"vpn_ip": vpn_ip, "server_vpn_ip": SERVER_VPN_IP}

    def remove_peer(self, device_id: str) -> None:
        peer = self._peers.pop(device_id, None)
        if peer is None:
            return
        try:
            subprocess.run(
                ["sudo", "wg", "set", WG_IFACE, "peer", peer["pubkey"], "remove"],
                check=True, timeout=10,
            )
            self._rewrite_conf_without(peer["pubkey"])
        except Exception as exc:
            logger.warning("Could not remove WireGuard peer: %s", exc)
        self._save_peers()

    def _load_peers(self) -> dict:
        try:
            return json.loads(PEERS_DB.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return {}

    def _save_peers(self) -> None:
        PEERS_DB.write_text(json.dumps(self._peers, indent=2))

    def _rewrite_conf_without(self, pubkey: str) -> None:
        try:
            text    = Path(WG_CONF).read_text()
            pattern = rf"\n\[Peer\][^\[]*?PublicKey\s*=\s*{re.escape(pubkey)}[^\[]*"
            cleaned = re.sub(pattern, "", text, flags=re.DOTALL)
            Path(WG_CONF).write_text(cleaned)
        except Exception as exc:
            logger.warning("Could not rewrite wg conf: %s", exc)


# ═══════════════════════════════════════════════════════════════════════════════
# Plugin entry point
# ═══════════════════════════════════════════════════════════════════════════════

def load_component(config: Any) -> "MoongatePlugin":
    return MoongatePlugin(config)


class MoongatePlugin:
    def __init__(self, config: Any) -> None:
        self.server = config.get_server()
        self.auth   = AuthManager()
        self.wg     = WireGuardManager()

        self._wg_endpoint_override: Optional[str] = config.get(
            "wireguard_endpoint", None
        )
        # Most-recent QR URL (updated each time MOONGATE_PAIR is run)
        self._last_qr_url:      Optional[str] = None
        self._last_qr_token_id: Optional[str] = None

        # Register HTTP endpoints using Moonraker's correct API.
        # Moonraker requires paths to start with /server, /printer, /machine, etc.
        self.server.register_endpoint(
            "/server/moongate/pair",   ["POST"], self._handle_pair
        )
        self.server.register_endpoint(
            "/server/moongate/auth",   ["POST"], self._handle_auth
        )
        self.server.register_endpoint(
            "/server/moongate/qr",     ["GET"],  self._handle_qr
        )
        self.server.register_endpoint(
            "/server/moongate/status",  ["GET"],  self._handle_status
        )
        self.server.register_endpoint(
            "/server/moongate/control", ["POST"], self._handle_control
        )
        self.server.register_endpoint(
            "/server/moongate/tokens",  ["GET"],  self._handle_list_tokens
        )
        self.server.register_endpoint(
            "/server/moongate/revoke", ["POST"], self._handle_revoke
        )

        # Called by the MOONGATE_PAIR G-code macro via Klipper → Moonraker RPC
        self.server.register_remote_method(
            "moongate_generate_pair_code",
            self._klipper_generate_pair_code,
        )

        logger.info(
            "Moongate plugin loaded (WireGuard: %s)",
            "ready" if self.wg.server_public_key() else "not configured",
        )

    # ── Klipper remote method ─────────────────────────────────────────────────

    async def _klipper_generate_pair_code(self) -> None:
        """Called when the user runs MOONGATE_PAIR in the Klipper console."""
        import asyncio

        display_code, _qr = self.auth.generate_pair_code()

        # Pre-issue a JWT for QR-based pairing.
        # The QR embeds the token directly so no phone→Pi network request is
        # needed during pairing — works even with WiFi AP isolation.
        local_ip        = _get_local_ip()
        tunnel_url      = _get_tunnel_url()   # None if cloudflared not running
        direct_jwt, tid = self.auth.issue_direct_token(device_name="Paired via QR")

        # Build the QR URL — always includes local, adds remote if tunnel is up
        qr_params = f"local={local_ip}:80&token={direct_jwt}"
        if tunnel_url:
            qr_params += f"&remote={tunnel_url}"
        self._last_qr_url      = f"moongate://pair?{qr_params}"
        self._last_qr_token_id = tid

        qr_page_url = f"http://{local_ip}/moongate-pair.html"

        logger.info("MOONGATE PAIR CODE GENERATED: %s", display_code)
        logger.info("MOONGATE QR PAGE: %s", qr_page_url)
        if tunnel_url:
            logger.info("MOONGATE TUNNEL: %s", tunnel_url)
        else:
            logger.info("MOONGATE TUNNEL: not running (remote access unavailable)")

        # Let the RPC handshake complete before pushing G-code back
        await asyncio.sleep(0.3)

        remote_line = (
            f"M118 Remote access: {tunnel_url}\n" if tunnel_url
            else "M118 Remote access: not set up (run install.sh to enable)\n"
        )
        script = (
            f"M118 *** MOONGATE CODE: {display_code} ***\n"
            f"M118 Scan QR: open {qr_page_url} on your PC, then scan with the app.\n"
            f"{remote_line}"
            f"M118 Code expires in 10 minutes."
        )
        try:
            klippy_apis: Any = self.server.lookup_component("klippy_apis")
            await klippy_apis.run_gcode(script)
            logger.info("Pair code sent to Klipper console.")
        except Exception as exc:
            logger.error("run_gcode failed (%s) — code is: %s", exc, display_code)

        # Also push via WebSocket so Mainsail shows it
        try:
            self.server.send_event(
                "server:gcode_response",
                f"// MOONGATE CODE: {display_code} — QR: {qr_page_url}",
            )
        except Exception:
            pass

    # ── Route handlers ────────────────────────────────────────────────────────
    # Moonraker WebRequest: use webrequest.get_args() for body/query params.
    # Raise self.server.error("msg", status_code) for HTTP errors.

    async def _handle_pair(self, webrequest: Any) -> dict:
        display_code, qr_payload = self.auth.generate_pair_code()
        logger.info("Pair code requested via HTTP: %s", display_code)
        return {
            "code":               display_code,
            "qr_payload":         qr_payload,
            "expires_in_seconds": 600,
        }

    async def _handle_qr(self, webrequest: Any) -> dict:
        """
        Return the pre-issued QR URL for the most-recent MOONGATE_PAIR run.
        Format: moongate://pair?local=IP:80&remote=https://x.trycloudflare.com&token=JWT
        The app stores the token directly — no phone→Pi network request needed.
        Called by moongate-pair.html served on the printer's web UI.
        """
        if self._last_qr_url is None:
            raise self.server.error(
                "No pairing session active. Run MOONGATE_PAIR first.", 404
            )
        tunnel_url = _get_tunnel_url()
        return {
            "qr_url":     self._last_qr_url,
            "tunnel_url": tunnel_url,         # None if cloudflared not running
        }

    async def _handle_auth(self, webrequest: Any) -> dict:
        args         = webrequest.get_args()
        raw_code     = args.get("code", "")
        device_name  = args.get("device_name", "Unknown device")
        ttl_days     = args.get("ttl_days")
        phone_pubkey = args.get("wg_pubkey")

        if not raw_code:
            raise self.server.error("code is required", 400)

        result = self.auth.exchange_code(
            raw_code=raw_code,
            device_name=str(device_name),
            requested_ttl_days=int(ttl_days) if ttl_days is not None else None,
        )
        if result is None:
            raise self.server.error("invalid or expired code", 401)

        token, token_id = result
        response: dict  = {"token": token}

        if phone_pubkey:
            server_pubkey = self.wg.server_public_key()
            endpoint      = self.wg.endpoint(self._wg_endpoint_override)
            if server_pubkey and endpoint:
                peer_info = self.wg.add_peer(
                    device_id=token_id, phone_pubkey=str(phone_pubkey)
                )
                if peer_info:
                    wg_config = (
                        "[Interface]\n"
                        f"Address    = {peer_info['vpn_ip']}/32\n"
                        "DNS        = 1.1.1.1\n\n"
                        "[Peer]\n"
                        f"PublicKey           = {server_pubkey}\n"
                        f"Endpoint            = {endpoint}\n"
                        f"AllowedIPs          = {peer_info['server_vpn_ip']}/32\n"
                        "PersistentKeepalive = 25\n"
                    )
                    response["wg_config"]    = wg_config
                    response["wg_server_ip"] = peer_info["server_vpn_ip"]
                    response["wg_phone_ip"]  = peer_info["vpn_ip"]
                    logger.info(
                        "WireGuard peer created for '%s' → %s",
                        device_name, peer_info["vpn_ip"],
                    )
            else:
                logger.info("WireGuard not configured — skipping wg_config")

        return response

    @staticmethod
    async def _get_webcam_snapshot_path(client: Any) -> str:
        """
        Ask Moonraker for its webcam configuration and return the snapshot path
        that the app should use.  Normalises away localhost/127.0.0.1 prefixes
        so the returned value is always a plain path like:
          /webcam/?action=snapshot   (mjpeg-streamer default)
          /webcam/snapshot           (Crowsnest / uStreamer)
        Falls back to the mjpeg-streamer default if the API is unavailable.
        """
        import re as _re
        from tornado.httpclient import HTTPRequest
        _default = "/webcam/?action=snapshot"
        try:
            req = HTTPRequest(
                "http://127.0.0.1:7125/server/webcams/list",
                method="GET", request_timeout=2.0,
            )
            resp = await client.fetch(req, raise_error=False)
            if resp.code != 200:
                return _default
            data    = __import__("json").loads(resp.body)
            webcams = data.get("result", {}).get("webcams", [])
            if not webcams:
                return _default
            snap = (webcams[0].get("snapshot_url") or "").strip()
            if not snap:
                return _default
            # Strip any localhost/127.0.0.1 prefix so only the path survives.
            snap = _re.sub(r'^https?://(localhost|127\.0\.0\.1)(:\d+)?', '', snap)
            return snap or _default
        except Exception:
            return _default

    async def _handle_status(self, webrequest: Any) -> dict:
        """
        Authenticated proxy for Moonraker printer status.
        Validates the Moongate JWT, then fetches live printer data from
        Moonraker on localhost (trusted connection — no second auth needed).
        Uses tornado's built-in AsyncHTTPClient (no extra packages needed).
        """
        self._authenticate(webrequest)
        import json as _json
        from tornado.httpclient import AsyncHTTPClient, HTTPRequest

        client = AsyncHTTPClient()
        req = HTTPRequest(
            "http://127.0.0.1:7125/printer/objects/query"
            "?print_stats&heater_bed&extruder",
            method="GET",
            request_timeout=5.0,
        )
        try:
            # raise_error=False → HTTPError not thrown on non-200; we check manually
            resp = await client.fetch(req, raise_error=False)
        except Exception as e:
            raise self.server.error(
                f"Failed to reach Moonraker internally: {e}", 500
            )
        if resp.code != 200:
            raise self.server.error(
                f"Moonraker query returned HTTP {resp.code}", 502
            )
        data   = _json.loads(resp.body)
        result = data.get("result", data)

        # Inject the Pi's current tunnel URL so the app can detect staleness
        # and update its stored remoteHost without the user re-scanning the QR.
        result["tunnel_url"] = _get_tunnel_url()

        # Inject the webcam snapshot path as Moonraker has it configured.
        # This lets the app use the correct path regardless of whether the Pi
        # is running mjpeg-streamer (/webcam/?action=snapshot) or
        # Crowsnest/uStreamer (/webcam/snapshot), or any custom setup.
        result["webcam_snapshot_path"] = await self._get_webcam_snapshot_path(client)

        return result

    async def _handle_control(self, webrequest: Any) -> dict:
        """
        Authenticated proxy for Klipper print control actions.
        POST /server/moongate/control?mg_token=<jwt>&action=<action>

        Supported actions:
          pause          — pause the current print
          resume         — resume a paused print
          cancel         — cancel the current print (requires double-press in app)
          emergency_stop — immediately halt all motion (Klipper shutdown state)
        """
        self._authenticate(webrequest)
        from tornado.httpclient import AsyncHTTPClient, HTTPRequest

        args   = webrequest.get_args()
        action = str(args.get("action", "")).strip()

        action_map = {
            "pause":             "/printer/print/pause",
            "resume":            "/printer/print/resume",
            "cancel":            "/printer/print/cancel",
            "emergency_stop":    "/printer/emergency_stop",
            "firmware_restart":  "/printer/firmware_restart",
        }
        if action not in action_map:
            raise self.server.error(
                f"Unknown action '{action}'. Valid: {list(action_map)}", 400
            )

        path   = action_map[action]
        client = AsyncHTTPClient()
        req    = HTTPRequest(
            f"http://127.0.0.1:7125{path}",
            method="POST",
            body="{}",
            headers={"Content-Type": "application/json"},
            request_timeout=10.0,
        )
        try:
            resp = await client.fetch(req, raise_error=False)
        except Exception as e:
            raise self.server.error(
                f"Failed to reach Moonraker internally: {e}", 500
            )
        if resp.code not in (200, 204):
            raise self.server.error(
                f"Moonraker returned HTTP {resp.code} for action '{action}'", 502
            )
        return {"action": action, "ok": True}

    async def _handle_list_tokens(self, webrequest: Any) -> dict:
        self._authenticate(webrequest)
        return {"tokens": self.auth.list_tokens()}

    async def _handle_revoke(self, webrequest: Any) -> dict:
        token_id  = self._authenticate(webrequest)
        args      = webrequest.get_args()
        target_id = args.get("token_id", token_id)
        self.wg.remove_peer(str(target_id))
        success = self.auth.revoke_token(str(target_id))
        return {"revoked": success}

    # ── Helpers ───────────────────────────────────────────────────────────────

    def _authenticate(self, webrequest: Any) -> str:
        """
        Validate the Moongate JWT passed as ?mg_token=<jwt>.
        Note: Moonraker strips 'token' and 'access_token' from get_args()
        (they appear in EXCLUDED_ARGS in application.py), so we use the
        custom parameter name 'mg_token' which Moonraker leaves untouched.
        Raises 401 if missing or invalid. Returns token_id on success.
        """
        args  = webrequest.get_args()
        token = args.get("mg_token", "")
        if not token:
            raise self.server.error("Authorization token required", 401)
        token_id = self.auth.validate_token(str(token))
        if token_id is None:
            raise self.server.error("Invalid or expired token", 401)
        return token_id
