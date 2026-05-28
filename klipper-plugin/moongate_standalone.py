"""
Moongate v0.3.0 — single-file Moonraker component.

Replaces the v0.2.x Pi-issued HS256 JWT model with EdDSA tokens issued by
Supabase Edge Functions. The Pi:
  • Owns an Ed25519 device keypair (~/.config/moongate/device_ed25519)
  • Pre-registers enrollment-token hashes via /enroll-prepare
  • Heartbeats the current Cloudflare Quick Tunnel URL (signed) every 5 min
  • Verifies inbound EdDSA JWTs against Supabase's /jwks (cached, 1 h TTL)
  • Stores the bound owner_user_id after the first valid /status or /control
    call — that user is the printer's owner from then on

Deploy as ~/moonraker/moonraker/components/moongate.py (install.sh symlinks).

Endpoints registered:
  POST /server/moongate/pair          — start a pairing session (called by macro)
  GET  /server/moongate/qr            — return the current QR URL
  GET  /server/moongate/status        — printer state (EdDSA-authed)
  POST /server/moongate/control       — pause/resume/cancel/etc. (EdDSA-authed)
  POST /server/moongate/reset-owner   — wipe pairing (LAN-only)
  GET  /server/moongate/pair-page     — JSON metadata for the HTML pair page

Macros (in moongate.cfg via install.sh):
  MOONGATE_PAIR           — start a new pairing session
  MOONGATE_RESET_OWNER    — clear local owner state to allow re-pairing
"""
from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import logging
import random
import re
import string
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Dict, Optional

import jwt as pyjwt  # PyJWT
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)

logger = logging.getLogger("moonraker.moongate")


# ═══════════════════════════════════════════════════════════════════════════════
# Paths + defaults
# ═══════════════════════════════════════════════════════════════════════════════

CONFIG_DIR   = Path.home() / ".config" / "moongate"
DEVICE_KEY   = CONFIG_DIR / "device_ed25519"
OWNER_FILE   = CONFIG_DIR / "owner.json"
CONFIG_FILE  = CONFIG_DIR / "config.json"
JWKS_CACHE   = CONFIG_DIR / "jwks.json"

# v0.3.0 talks to one centrally-hosted Supabase project. Override via
# ~/.config/moongate/config.json if you ever want a self-hosted backend.
DEFAULT_SUPABASE_URL = "https://wlmmaoupmupbrrkcjglj.supabase.co"
DEFAULT_SUPABASE_ANON_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndsbW1hb3VwbXVwYnJya2NqZ2xqIiwicm9sZSI6"
    "ImFub24iLCJpYXQiOjE3Nzk2NTAyMzYsImV4cCI6MjA5NTIyNjIzNn0."
    "EnIxrykASzZCBBCJtDVJetiWBFKGgFTQDRdkyhBCasw"
)

DEFAULT_CONFIG = {
    "supabase_url":               DEFAULT_SUPABASE_URL,
    "supabase_anon_key":          DEFAULT_SUPABASE_ANON_KEY,
    "http_port":                  80,
    "heartbeat_interval_seconds": 300,   # 5 min
    "jwks_ttl_seconds":           3600,  # 1 hour
    "enrollment_ttl_seconds":     600,   # 10 min
}

ACCESS_TOKEN_AUDIENCE = "moongate-printer"
ACCESS_TOKEN_ISSUER   = "moongate"

# Enrollment-token format: GATE-XXXX-XXXX, digits only (easy to type on phone)
CODE_CHARS = string.digits


# ═══════════════════════════════════════════════════════════════════════════════
# Network helpers (kept from v0.2.x — same cloudflared URL detection logic)
# ═══════════════════════════════════════════════════════════════════════════════

def _get_local_ip() -> str:
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
    """Return the active Cloudflare Quick Tunnel URL or None."""
    pattern = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com")

    # 1. cloudflared local REST API — always-live URL
    for port in (20241, 2000):
        for path in ("/quicktunnel", "/metrics", "/"):
            try:
                with urllib.request.urlopen(f"http://localhost:{port}{path}", timeout=2) as resp:
                    body = resp.read().decode(errors="replace")
                    m = pattern.search(body)
                    if m:
                        return m.group(0)
            except Exception:
                pass

    # 2. log file — last match survives URL rotation
    for p in (Path("/run/moongate-tunnel.log"), Path("/tmp/moongate-tunnel.log")):
        if p.exists():
            try:
                matches = pattern.findall(p.read_text())
                if matches:
                    return matches[-1]
            except Exception:
                pass

    # 3. journalctl fallback
    for unit in ("moongate-tunnel", "cloudflared"):
        try:
            result = subprocess.run(
                ["journalctl", "-u", unit, "--no-pager", "-n", "500"],
                capture_output=True, text=True, timeout=5,
            )
            matches = pattern.findall(result.stdout)
            if matches:
                return matches[-1]
        except Exception:
            pass
    return None


def _get_tunnel_subdomain(tunnel_url: Optional[str]) -> Optional[str]:
    if not tunnel_url:
        return None
    m = re.search(r"https?://([a-z0-9-]+)\.trycloudflare\.com", tunnel_url)
    return m.group(1) if m else None


def _b64std(data: bytes) -> str:
    return base64.b64encode(data).decode()


def _b64url_pad(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


# ═══════════════════════════════════════════════════════════════════════════════
# DeviceKey — Ed25519 keypair persisted on disk
# ═══════════════════════════════════════════════════════════════════════════════

class DeviceKey:
    """Ed25519 device identity. Private key never leaves the Pi. Public key
    is shared via the QR (so the app can send it to Supabase /printer-claim)
    and embedded in heartbeats (so Supabase can verify Pi-signed payloads)."""

    def __init__(self, path: Path) -> None:
        self.path = path
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            self._priv = serialization.load_pem_private_key(path.read_bytes(), password=None)
            if not isinstance(self._priv, Ed25519PrivateKey):
                raise RuntimeError(f"Unexpected key type at {path}: {type(self._priv).__name__}")
        else:
            self._priv = Ed25519PrivateKey.generate()
            path.write_bytes(self._priv.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption(),
            ))
            path.chmod(0o600)
            logger.info("Generated new Ed25519 device key at %s", path)

    @property
    def public_bytes(self) -> bytes:
        return self._priv.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )

    @property
    def public_key_b64(self) -> str:
        return _b64std(self.public_bytes)

    def sign(self, message: bytes) -> bytes:
        return self._priv.sign(message)

    def sign_b64(self, message: bytes) -> str:
        return _b64std(self.sign(message))


# ═══════════════════════════════════════════════════════════════════════════════
# JwksCache — fetch + cache the EdDSA verification keys
# ═══════════════════════════════════════════════════════════════════════════════

class JwksCache:
    def __init__(self, supabase_url: str, anon_key: str, cache_path: Path, ttl: int) -> None:
        self.supabase_url = supabase_url.rstrip("/")
        self.anon_key     = anon_key
        self.cache_path   = cache_path
        self.ttl          = ttl
        self._keys:       Dict[str, Ed25519PublicKey] = {}
        self._fetched_at: float                       = 0.0
        self._load_from_disk()

    def _load_from_disk(self) -> None:
        if not self.cache_path.exists():
            return
        try:
            data = json.loads(self.cache_path.read_text())
            self._fetched_at = float(data.get("fetched_at", 0))
            for jwk in data.get("keys", []):
                self._add_jwk(jwk)
        except Exception as exc:
            logger.warning("Failed to load JWKS cache: %s", exc)

    def _add_jwk(self, jwk: dict) -> None:
        if jwk.get("kty") != "OKP" or jwk.get("crv") != "Ed25519":
            return
        kid = jwk.get("kid")
        x   = jwk.get("x")
        if not kid or not x:
            return
        try:
            self._keys[kid] = Ed25519PublicKey.from_public_bytes(_b64url_pad(x))
        except Exception as exc:
            logger.warning("Skipping unparseable JWK kid=%s: %s", kid, exc)

    def fetch_now(self) -> bool:
        """Synchronously fetch /jwks. Returns True iff at least one key landed."""
        url = f"{self.supabase_url}/functions/v1/jwks"
        req = urllib.request.Request(url, headers={"apikey": self.anon_key})
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                if resp.status != 200:
                    logger.warning("JWKS fetch returned HTTP %d", resp.status)
                    return False
                data = json.loads(resp.read().decode())
        except Exception as exc:
            logger.warning("JWKS fetch failed: %s", exc)
            return False

        prior = self._keys
        self._keys = {}
        for jwk in data.get("keys", []):
            self._add_jwk(jwk)

        if not self._keys:
            # Bad fetch — keep prior cache rather than going zero-key.
            self._keys = prior
            logger.warning("JWKS fetch returned no usable keys; keeping prior cache")
            return False

        self._fetched_at = time.time()
        try:
            self.cache_path.write_text(json.dumps({
                "fetched_at": self._fetched_at,
                "keys":       data.get("keys", []),
            }, indent=2))
        except OSError as exc:
            logger.warning("Could not persist JWKS cache: %s", exc)

        logger.info("JWKS refreshed; %d key(s) cached", len(self._keys))
        return True

    def get_key(self, kid: str) -> Optional[Ed25519PublicKey]:
        if time.time() - self._fetched_at > self.ttl:
            self.fetch_now()
        return self._keys.get(kid)


# ═══════════════════════════════════════════════════════════════════════════════
# AccessTokenVerifier
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class TokenClaims:
    sub:        str
    printer_id: str
    aud:        str
    iss:        str
    exp:        int
    iat:        int
    jti:        str


class AccessTokenVerifier:
    def __init__(self, jwks: JwksCache) -> None:
        self.jwks = jwks

    def verify(
        self,
        token: str,
        expected_printer_id: Optional[str],
        expected_owner: Optional[str],
    ) -> Optional[TokenClaims]:
        try:
            header = pyjwt.get_unverified_header(token)
        except pyjwt.PyJWTError as exc:
            logger.debug("Bad JWT header: %s", exc)
            return None

        kid = header.get("kid")
        if not kid:
            return None

        key = self.jwks.get_key(kid)
        if key is None:
            logger.debug("No JWKS entry for kid=%s", kid)
            return None

        pem = key.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )

        try:
            payload = pyjwt.decode(
                token, pem,
                algorithms=["EdDSA"],
                audience=ACCESS_TOKEN_AUDIENCE,
                issuer=ACCESS_TOKEN_ISSUER,
                options={"require": ["exp", "iat", "sub", "aud", "iss"]},
            )
        except pyjwt.PyJWTError as exc:
            logger.debug("JWT verify failed: %s", exc)
            return None

        printer_id = payload.get("printer_id")
        if not printer_id:
            return None
        if expected_printer_id and printer_id != expected_printer_id:
            logger.warning("printer_id mismatch (got %s, owner %s)",
                           printer_id, expected_printer_id)
            return None
        if expected_owner and payload.get("sub") != expected_owner:
            logger.warning("sub mismatch — refused")
            return None

        return TokenClaims(
            sub=payload["sub"], printer_id=printer_id,
            aud=payload["aud"], iss=payload["iss"],
            exp=int(payload["exp"]), iat=int(payload["iat"]),
            jti=str(payload.get("jti", "")),
        )


# ═══════════════════════════════════════════════════════════════════════════════
# OwnerState — persisted (printer_id, owner_user_id) after first claim
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class OwnerState:
    printer_id:    str
    owner_user_id: str
    paired_at:     str  # ISO8601

    @classmethod
    def load(cls, path: Path) -> Optional["OwnerState"]:
        if not path.exists():
            return None
        try:
            return cls(**json.loads(path.read_text()))
        except Exception as exc:
            logger.warning("Failed to load owner.json: %s", exc)
            return None

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(asdict(self), indent=2))
        path.chmod(0o600)


# ═══════════════════════════════════════════════════════════════════════════════
# SupabaseClient
# ═══════════════════════════════════════════════════════════════════════════════

class SupabaseClient:
    """Synchronous HTTP client for our Edge Function endpoints. Synchronous
    because these calls are rare (pairing + heartbeat) and Moonraker plugins
    can mix sync stdlib calls into async handlers cleanly."""

    def __init__(self, url: str, anon_key: str) -> None:
        self.url      = url.rstrip("/")
        self.anon_key = anon_key

    def _post(self, path: str, body: dict, timeout: float = 10.0) -> tuple[int, dict]:
        full_url = f"{self.url}/functions/v1{path}"
        data     = json.dumps(body).encode()
        req      = urllib.request.Request(
            full_url, data=data, method="POST",
            headers={"apikey": self.anon_key, "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read().decode() if resp.length != 0 else ""
                return resp.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as exc:
            try:
                body_dict = json.loads(exc.read().decode())
            except Exception:
                body_dict = {}
            return exc.code, body_dict
        except Exception as exc:
            logger.warning("Supabase request %s failed: %s", path, exc)
            return 0, {"error": str(exc)}

    def enroll_prepare(self, pi_public_key_b64: str, token_hash_b64: str) -> tuple[int, dict]:
        return self._post("/enroll-prepare", {
            "pi_public_key": pi_public_key_b64,
            "token_hash":    token_hash_b64,
        })

    def heartbeat(
        self,
        pi_public_key_b64: str,
        tunnel_url: str,
        timestamp: int,
        signature_b64: str,
    ) -> tuple[int, dict]:
        return self._post("/printer-heartbeat", {
            "pi_public_key": pi_public_key_b64,
            "tunnel_url":    tunnel_url,
            "timestamp":     timestamp,
            "signature":     signature_b64,
        })

    def release_pi_signed(
        self,
        pi_public_key_b64: str,
        timestamp: int,
        signature_b64: str,
    ) -> tuple[int, dict]:
        """Force-release the printer row in Supabase using a Pi-signed
        request. Server verifies the signature against pi_public_key and
        deletes the row regardless of owner. Used by MOONGATE_RESET_OWNER
        so a wiped-app user can re-pair from a fresh anon UID."""
        return self._post("/release-printer", {
            "pi_public_key": pi_public_key_b64,
            "timestamp":     timestamp,
            "signature":     signature_b64,
        })


# ═══════════════════════════════════════════════════════════════════════════════
# HeartbeatLoop
# ═══════════════════════════════════════════════════════════════════════════════

class HeartbeatLoop:
    """Periodically reports the current tunnel URL to Supabase. Signed with
    the Pi's Ed25519 device key. The server matches the public key to find
    the printer row and updates tunnel_url_enc + last_seen."""

    def __init__(
        self,
        device: DeviceKey,
        sb: SupabaseClient,
        interval: int,
        on_unpaired_cb=None,
    ) -> None:
        self.device      = device
        self.sb          = sb
        self.interval    = interval
        self.on_unpaired = on_unpaired_cb
        self._task: Optional[asyncio.Task] = None
        self._last_url_reported: Optional[str] = None
        # Created in _run() so it binds to the running loop. None until
        # the loop has started; request_immediate_send() is a no-op in
        # that window.
        self._poke_event: Optional[asyncio.Event] = None

    def start(self) -> None:
        if self._task is None or self._task.done():
            try:
                loop = asyncio.get_event_loop()
            except RuntimeError:
                logger.warning("No running event loop; heartbeat will be deferred")
                return
            self._task = loop.create_task(self._run())

    async def _run(self) -> None:
        # First heartbeat after a brief delay so cloudflared has time to come up
        await asyncio.sleep(5)
        self._poke_event = asyncio.Event()
        while True:
            try:
                self._send_one()
            except Exception as exc:
                logger.warning("Heartbeat iteration crashed: %s", exc)
            # Wait for either the scheduled interval OR a poke from
            # MOONGATE_PAIR. Poke wakes the loop early so the cloud sees
            # the current tunnel URL before the user's app calls
            # /printer-access, instead of the user waiting up to
            # `interval` seconds in "Starting up..." tile state.
            try:
                await asyncio.wait_for(self._poke_event.wait(), timeout=self.interval)
                self._poke_event.clear()
                logger.debug("Heartbeat poked — sending early")
            except asyncio.TimeoutError:
                pass  # Normal interval elapsed
            except asyncio.CancelledError:
                return

    def request_immediate_send(self) -> None:
        """Wake the heartbeat loop to send NOW instead of waiting for the
        next scheduled interval. Idempotent — calling repeatedly between
        sends collapses into a single early send. No-op until the loop
        has started (the first 5 s post-boot)."""
        if self._poke_event is not None:
            self._poke_event.set()

    def _send_one(self) -> None:
        tunnel = _get_tunnel_url()
        if not tunnel:
            logger.debug("Heartbeat skipped — tunnel URL not yet available")
            return

        ts        = int(time.time())
        pk_b64    = self.device.public_key_b64
        canonical = f"moongate-heartbeat\n{pk_b64}\n{tunnel}\n{ts}".encode()
        sig_b64   = self.device.sign_b64(canonical)

        status, body = self.sb.heartbeat(pk_b64, tunnel, ts, sig_b64)
        if status in (200, 204):
            if tunnel != self._last_url_reported:
                logger.info("Heartbeat: reported tunnel URL %s", tunnel)
                self._last_url_reported = tunnel
            return
        if status == 404:
            logger.warning("Heartbeat 404 — printer record gone server-side")
            if self.on_unpaired:
                try:
                    self.on_unpaired()
                except Exception as exc:
                    logger.warning("on_unpaired callback failed: %s", exc)
            return
        if status == 401:
            logger.warning("Heartbeat 401 — signature or replay window failure")
            return
        logger.warning("Heartbeat HTTP %s: %s", status, body)


# ═══════════════════════════════════════════════════════════════════════════════
# PendingPair — the active enrollment-token session
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class PendingPair:
    raw_token:  str
    expires_at: float
    qr_payload: str


# ═══════════════════════════════════════════════════════════════════════════════
# Plugin entry point
# ═══════════════════════════════════════════════════════════════════════════════

def load_component(config: Any) -> "MoongatePlugin":
    return MoongatePlugin(config)


class MoongatePlugin:
    def __init__(self, config: Any) -> None:
        self.server = config.get_server()

        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        self._config   = self._load_config()
        self.device    = DeviceKey(DEVICE_KEY)
        self.owner     = OwnerState.load(OWNER_FILE)
        self.jwks      = JwksCache(
            self._config["supabase_url"],
            self._config["supabase_anon_key"],
            JWKS_CACHE,
            int(self._config["jwks_ttl_seconds"]),
        )
        self.verifier  = AccessTokenVerifier(self.jwks)
        self.sb        = SupabaseClient(
            self._config["supabase_url"],
            self._config["supabase_anon_key"],
        )
        self.heartbeat = HeartbeatLoop(
            self.device, self.sb,
            int(self._config["heartbeat_interval_seconds"]),
            on_unpaired_cb=self._on_unpaired,
        )

        self._pending: Optional[PendingPair]   = None
        self._chamber_key: Optional[str]       = None
        self._chamber_key_checked: bool        = False

        # HTTP endpoints
        self.server.register_endpoint("/server/moongate/pair",        ["POST"], self._handle_pair)
        self.server.register_endpoint("/server/moongate/qr",          ["GET"],  self._handle_qr)
        self.server.register_endpoint("/server/moongate/status",      ["GET"],  self._handle_status)
        self.server.register_endpoint("/server/moongate/control",     ["POST"], self._handle_control)
        self.server.register_endpoint("/server/moongate/reset-owner", ["POST"], self._handle_reset_owner)
        self.server.register_endpoint("/server/moongate/pair-page",   ["GET"],  self._handle_pair_page)

        # Klipper macros
        self.server.register_remote_method("moongate_generate_pair_code", self._klipper_pair)
        self.server.register_remote_method("moongate_reset_owner",        self._klipper_reset_owner)

        # Bootstrap JWKS (best effort) and start the heartbeat loop
        self.jwks.fetch_now()
        self.heartbeat.start()

        owner_str = (
            f"{self.owner.owner_user_id[:8]}.../{self.owner.printer_id[:8]}..."
            if self.owner else "unpaired"
        )
        logger.info("Moongate v0.3 plugin loaded. Owner: %s. Tunnel: %s",
                    owner_str, _get_tunnel_url() or "not up")

    # ── Config ────────────────────────────────────────────────────────────────

    def _load_config(self) -> dict:
        cfg = DEFAULT_CONFIG.copy()
        if CONFIG_FILE.exists():
            try:
                user_cfg = json.loads(CONFIG_FILE.read_text())
                if isinstance(user_cfg, dict):
                    cfg.update(user_cfg)
            except Exception as exc:
                logger.warning("Bad config.json (%s); using defaults", exc)
        return cfg

    @property
    def http_port(self) -> int:
        try:
            return int(self._config.get("http_port", 80))
        except (TypeError, ValueError):
            return 80

    # ── Pairing ───────────────────────────────────────────────────────────────

    @staticmethod
    def _generate_enrollment_token() -> str:
        part1 = "".join(random.choices(CODE_CHARS, k=4))
        part2 = "".join(random.choices(CODE_CHARS, k=4))
        return f"GATE-{part1}-{part2}"

    def _start_pairing(self) -> Optional[PendingPair]:
        raw  = self._generate_enrollment_token()
        hash_b64 = _b64std(hashlib.sha256(raw.encode()).digest())

        status, body = self.sb.enroll_prepare(self.device.public_key_b64, hash_b64)
        if status not in (200, 204):
            logger.error("enroll-prepare failed: HTTP %s %s", status, body)
            return None

        qr = "moongate://pair?" + urllib.parse.urlencode({
            "v":  "3",
            "pk": self.device.public_key_b64,
            "et": raw,
        })
        pending = PendingPair(
            raw_token=raw,
            expires_at=time.time() + int(self._config["enrollment_ttl_seconds"]),
            qr_payload=qr,
        )
        self._pending = pending
        return pending

    async def _klipper_pair(self) -> None:
        """MOONGATE_PAIR macro entry point."""
        pending = self._start_pairing()
        await asyncio.sleep(0.3)

        if pending is not None:
            # User is now actively waiting to scan. Kick the heartbeat so
            # the cloud has a fresh tunnel URL by the time their app calls
            # /printer-access — saves up to `heartbeat_interval_seconds`
            # (5 min default) of "Starting up..." tile state.
            self.heartbeat.request_immediate_send()

        if pending is None:
            script = "\n".join([
                "M118 ============================================",
                "M118 Moongate: pair failed (Supabase unreachable).",
                "M118 Check internet and try MOONGATE_PAIR again.",
                "M118 ============================================",
            ])
        else:
            local_ip   = _get_local_ip()
            port_sfx   = "" if self.http_port == 80 else f":{self.http_port}"
            local_page = f"http://{local_ip}{port_sfx}/moongate-pair.html"

            logger.info("MOONGATE PAIR CODE: %s", pending.raw_token)
            logger.info("Pair page (LAN):  %s", local_page)

            # v0.4: the pair page is intentionally only reachable on LAN.
            # The tunnel-side moongate-pair.html sits behind the EdDSA
            # auth proxy and returns 401 to anyone without a valid token
            # — which a new user pairing for the first time doesn't have
            # yet. Initial pairing requires being on the same network as
            # the printer; after pairing, the app uses the tunnel for
            # remote access transparently and the user never sees the
            # pair URL again.
            ttl_min = int(self._config["enrollment_ttl_seconds"]) // 60
            lines = [
                "M118 ==========================================",
                f"M118 MOONGATE CODE: {pending.raw_token}",
                "M118 ==========================================",
                "M118 DO NOT SHARE the code above.",
                "M118 If shared by accident: MOONGATE_RESET_OWNER",
                "M118 ==========================================",
                "M118 Open this URL on a PC, tablet, or other phone:",
                f"M118   {local_page}",
                "M118 Then scan the QR with your phone's Moongate app",
                "M118 (Add Printer > Scan QR).",
                "M118 ==========================================",
                f"M118 Code expires in {ttl_min} minutes.",
            ]
            script = "\n".join(lines)

        try:
            klippy_apis: Any = self.server.lookup_component("klippy_apis")
            await klippy_apis.run_gcode(script)
        except Exception as exc:
            logger.error("run_gcode failed: %s", exc)

    async def _klipper_reset_owner(self) -> None:
        """MOONGATE_RESET_OWNER macro entry point. Wipes local owner binding
        AND attempts a Pi-signed force-release of the cloud row so a fresh
        app install (new anon UID) can re-pair without bouncing off
        'already_paired'. Closes the v0.3.1 un-pair gap."""
        prior_pid = self.owner.printer_id[:8] if self.owner else None
        had_owner, cloud_status = await self._do_factory_reset()

        await asyncio.sleep(0.3)
        if had_owner:
            local_msg = f"M118 Moongate: owner state wiped (was {prior_pid}…)"
        else:
            local_msg = "M118 Moongate: no owner state (already unpaired)"
        cloud_msg = self._cloud_status_m118(cloud_status)
        script = "\n".join([
            "M118 ============================================",
            local_msg,
            cloud_msg,
            "M118 Run MOONGATE_PAIR to re-pair.",
            "M118 ============================================",
        ])
        try:
            klippy_apis: Any = self.server.lookup_component("klippy_apis")
            await klippy_apis.run_gcode(script)
        except Exception as exc:
            logger.error("run_gcode failed: %s", exc)

    async def _do_factory_reset(self) -> tuple[bool, int]:
        """Shared reset path used by the macro and the HTTP endpoint:
        wipe local owner.json + try to release the cloud row. Returns
        (had_owner_before, cloud_release_status). cloud_status is the
        HTTP code from the Pi-signed POST, with 0 meaning "network
        error / no answer at all"."""
        had_owner = self.owner is not None
        self._wipe_owner()
        # urllib in SupabaseClient is sync; off-load to a thread so the
        # asyncio loop is free for other work (matters because the macro
        # runs inline on Moonraker's loop).
        loop = asyncio.get_event_loop()
        cloud_status = await loop.run_in_executor(None, self._release_in_cloud)
        return had_owner, cloud_status

    def _release_in_cloud(self) -> int:
        """Sign + POST a release request. Returns the HTTP status.
        0 means the request didn't reach Supabase at all (DNS, offline)."""
        ts        = int(time.time())
        pk_b64    = self.device.public_key_b64
        canonical = f"moongate-release\n{pk_b64}\n{ts}".encode()
        sig_b64   = self.device.sign_b64(canonical)

        status, body = self.sb.release_pi_signed(pk_b64, ts, sig_b64)
        if status == 200:
            logger.info("Cloud row released for pi_pubkey=%s...", pk_b64[:8])
        elif status == 0:
            logger.warning("Cloud release skipped: network unavailable (%s)", body)
        else:
            logger.warning("Cloud release returned HTTP %s: %s", status, body)
        return status

    @staticmethod
    def _cloud_status_m118(status: int) -> str:
        """Turn an HTTP status from _release_in_cloud into a one-line
        M118 message for the Mainsail console."""
        if status == 200:
            return "M118 Cloud row released."
        if status == 0:
            return "M118 Cloud release skipped — network unavailable."
        return f"M118 Cloud release failed — HTTP {status}."

    def _wipe_owner(self) -> None:
        self.owner = None
        try:
            if OWNER_FILE.exists():
                OWNER_FILE.unlink()
        except OSError as exc:
            logger.warning("Failed to delete %s: %s", OWNER_FILE, exc)

    def _on_unpaired(self) -> None:
        """Heartbeat callback: server says printer is gone."""
        if self.owner is not None:
            logger.warning("Server has no record of this printer — wiping local owner state")
            self._wipe_owner()

    # ── Auth ──────────────────────────────────────────────────────────────────

    def _authenticate(self, webrequest: Any) -> TokenClaims:
        """Verify EdDSA token from ?mg_token= query param. Raises 401 on any
        failure. On first valid call when no owner is recorded, locks in the
        caller as the printer's permanent owner."""
        args  = webrequest.get_args()
        token = args.get("mg_token", "")
        if not token:
            raise self.server.error("Authorization token required", 401)

        expected_pid = self.owner.printer_id    if self.owner else None
        expected_own = self.owner.owner_user_id if self.owner else None
        claims = self.verifier.verify(str(token), expected_pid, expected_own)
        if claims is None:
            raise self.server.error("Invalid or expired token", 401)

        if self.owner is None:
            self.owner = OwnerState(
                printer_id=claims.printer_id,
                owner_user_id=claims.sub,
                paired_at=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            )
            try:
                self.owner.save(OWNER_FILE)
                logger.info("Owner bound: user=%s..., printer=%s...",
                            claims.sub[:8], claims.printer_id[:8])
            except OSError as exc:
                logger.error("Failed to persist owner.json: %s", exc)
        return claims

    def _is_lan_request(self, webrequest: Any) -> bool:
        """Heuristic: True iff the requester appears to be on the local LAN."""
        ip = None
        for attr in ("ip_addr", "remote_ip", "_ip"):
            ip = getattr(webrequest, attr, None)
            if ip:
                break
        if not ip:
            return False  # fail closed

        ip_str = str(ip)
        if ip_str.startswith("::ffff:"):
            ip_str = ip_str[7:]

        if ip_str in ("127.0.0.1", "::1", "localhost"):
            return True
        if ip_str.startswith(("10.", "192.168.")):
            return True
        if ip_str.startswith("172."):
            try:
                octet2 = int(ip_str.split(".")[1])
                if 16 <= octet2 <= 31:
                    return True
            except (ValueError, IndexError):
                pass
        if ip_str.startswith("169.254."):
            return True
        if ip_str.lower().startswith(("fc", "fd")):
            return True
        return False

    # ── Endpoint handlers ─────────────────────────────────────────────────────

    async def _handle_pair(self, webrequest: Any) -> dict:
        pending = self._start_pairing()
        if pending is None:
            raise self.server.error("Supabase /enroll-prepare unreachable", 502)
        return {
            "code":               pending.raw_token,
            "qr_payload":         pending.qr_payload,
            "local_url":          f"http://{_get_local_ip()}:{self.http_port}",
            "tunnel_url":         _get_tunnel_url(),
            "expires_in_seconds": max(0, int(pending.expires_at - time.time())),
        }

    async def _handle_qr(self, webrequest: Any) -> dict:
        if self._pending is None or time.time() > self._pending.expires_at:
            raise self.server.error("No active pairing session. Run MOONGATE_PAIR first.", 404)
        return {
            "qr_url":     self._pending.qr_payload,
            "tunnel_url": _get_tunnel_url(),
        }

    async def _handle_pair_page(self, webrequest: Any) -> dict:
        tunnel_url = _get_tunnel_url()
        return {
            "qr_url":     self._pending.qr_payload if self._pending else None,
            "tunnel_url": tunnel_url,
            "subdomain":  _get_tunnel_subdomain(tunnel_url),
            "local_ip":   _get_local_ip(),
            "ready":      self._pending is not None,
        }

    async def _handle_status(self, webrequest: Any) -> dict:
        self._authenticate(webrequest)
        from tornado.httpclient import AsyncHTTPClient, HTTPRequest

        client = AsyncHTTPClient()
        if not self._chamber_key_checked:
            self._chamber_key = await self._discover_chamber_sensor(client)
            self._chamber_key_checked = True

        query = "print_stats&heater_bed&extruder"
        if self._chamber_key:
            query += "&" + urllib.parse.quote(self._chamber_key, safe="")

        req = HTTPRequest(
            f"http://127.0.0.1:7125/printer/objects/query?{query}",
            method="GET", request_timeout=5.0,
        )
        try:
            resp = await client.fetch(req, raise_error=False)
        except Exception as exc:
            raise self.server.error(f"Failed to reach Moonraker: {exc}", 500)
        if resp.code != 200:
            raise self.server.error(f"Moonraker query returned HTTP {resp.code}", 502)

        data   = json.loads(resp.body)
        result = data.get("result", data)
        result["tunnel_url"] = _get_tunnel_url()
        # Surface the Pi's LAN address so the app can prefer a direct LAN
        # call (with the same EdDSA token) when it's on the same network,
        # skipping the Cloudflare round-trip. Doesn't add port — app pairs
        # it with the configured http_port from its own knowledge.
        result["local_ip"]   = _get_local_ip()
        result["http_port"]  = self.http_port

        webcam = await self._get_webcam_info(client)
        result["webcam_snapshot_path"]   = webcam["snapshot_path"]
        result["webcam_flip_horizontal"] = webcam["flip_horizontal"]
        result["webcam_flip_vertical"]   = webcam["flip_vertical"]
        result["webcam_rotation"]        = webcam["rotation"]
        result["webcam_target_fps"]      = webcam["target_fps"]
        return result

    async def _handle_control(self, webrequest: Any) -> dict:
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

        client = AsyncHTTPClient()
        req    = HTTPRequest(
            f"http://127.0.0.1:7125{action_map[action]}",
            method="POST", body="{}",
            headers={"Content-Type": "application/json"},
            request_timeout=10.0,
        )
        try:
            resp = await client.fetch(req, raise_error=False)
        except Exception as exc:
            raise self.server.error(f"Failed to reach Moonraker: {exc}", 500)
        if resp.code not in (200, 204):
            raise self.server.error(
                f"Moonraker returned HTTP {resp.code} for '{action}'", 502
            )
        return {"action": action, "ok": True}

    async def _handle_reset_owner(self, webrequest: Any) -> dict:
        """LAN-only owner reset (no token required by design; LAN access is
        a stronger signal than a JWT for recovery). Same semantics as the
        MOONGATE_RESET_OWNER macro: wipes local owner.json AND attempts
        a Pi-signed force-release of the cloud row."""
        if not self._is_lan_request(webrequest):
            raise self.server.error("Reset must be triggered from the local LAN", 403)
        had_owner, cloud_status = await self._do_factory_reset()
        return {
            "ok":           True,
            "had_owner":    had_owner,
            "cloud_status": cloud_status,
        }

    # ── Webcam + chamber discovery (kept from v0.2.x) ─────────────────────────

    @staticmethod
    async def _get_webcam_info(client: Any) -> dict:
        from tornado.httpclient import HTTPRequest
        _default_path = "/webcam/?action=snapshot"
        _default_fps  = 15
        _defaults = {
            "snapshot_path":   _default_path,
            "flip_horizontal": False,
            "flip_vertical":   False,
            "rotation":        0,
            "target_fps":      _default_fps,
        }
        try:
            req = HTTPRequest(
                "http://127.0.0.1:7125/server/webcams/list",
                method="GET", request_timeout=2.0,
            )
            resp = await client.fetch(req, raise_error=False)
            if resp.code != 200:
                return _defaults
            data    = json.loads(resp.body)
            webcams = data.get("result", {}).get("webcams", [])
            if not webcams:
                return _defaults
            cam  = webcams[0]
            snap = (cam.get("snapshot_url") or "").strip()
            if not snap:
                return _defaults
            snap = re.sub(r"^https?://(localhost|127\.0\.0\.1)(:\d+)?", "", snap)
            raw_fps = cam.get("target_fps", _default_fps)
            try:
                tgt_fps = int(raw_fps)
                if tgt_fps < 1 or tgt_fps > 60:
                    tgt_fps = _default_fps
            except (TypeError, ValueError):
                tgt_fps = _default_fps
            return {
                "snapshot_path":   snap or _default_path,
                "flip_horizontal": bool(cam.get("flip_horizontal", False)),
                "flip_vertical":   bool(cam.get("flip_vertical",   False)),
                "rotation":        int(cam.get("rotation", 0)),
                "target_fps":      tgt_fps,
            }
        except Exception:
            return _defaults

    async def _discover_chamber_sensor(self, client: Any) -> Optional[str]:
        from tornado.httpclient import HTTPRequest
        try:
            req = HTTPRequest(
                "http://127.0.0.1:7125/printer/objects/list",
                method="GET", request_timeout=2.0,
            )
            resp = await client.fetch(req, raise_error=False)
            if resp.code != 200:
                return None
            objects = json.loads(resp.body).get("result", {}).get("objects", [])
            for obj in objects:
                if ("temperature_sensor" in obj or "heater_generic" in obj
                        or "temperature_fan" in obj) \
                        and "chamber" in obj.lower():
                    logger.info("Moongate: chamber sensor detected: '%s'", obj)
                    return obj
        except Exception:
            pass
        return None
