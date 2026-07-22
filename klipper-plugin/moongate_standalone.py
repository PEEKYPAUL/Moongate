"""
Moongate - single-file Moonraker component.

The version Mainsail's Software Update panel shows is derived from the repo's
git tags (the vX.Y.Z release tags), not from a version string in this file;
see install.sh for the clone settings that make tag-based detection work. The
MOONGATE_PLUGIN_VERSION constant below is separate - it is reported only in
bug-report diagnostics to identify the exact plugin build, and does not drive
the update panel.

Replaces the v0.2.x Pi-issued HS256 JWT model with EdDSA tokens issued by
Supabase Edge Functions. The Pi:
  • Owns an Ed25519 device keypair (~/.config/moongate/device_ed25519)
  • Pre-registers enrollment-token hashes via /enroll-prepare
  • Heartbeats the current Cloudflare Quick Tunnel URL (signed) every 5 min
  • Verifies inbound EdDSA JWTs against Supabase's /jwks (cached, 1 h TTL)
  • Stores the bound owner_user_id after the first valid /status or /control
    call - that user is the printer's owner from then on

Deploy as ~/moonraker/moonraker/components/moongate.py (install.sh symlinks).

Endpoints registered:
  POST /server/moongate/pair          - start a pairing session (called by macro)
  GET  /server/moongate/qr            - return the current QR URL
  GET  /server/moongate/status        - printer state (EdDSA-authed)
  POST /server/moongate/control       - pause/resume/cancel/etc. (EdDSA-authed)
  POST /server/moongate/reset-owner   - wipe pairing (LAN-only)
  GET  /server/moongate/pair-page     - JSON metadata for the HTML pair page

Macros (in moongate.cfg via install.sh):
  MOONGATE_PAIR           - start a new pairing session
  MOONGATE_RESET_OWNER    - clear local owner state to allow re-pairing
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
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Any, Dict, Optional

# v0.6.17: PyJWT + cryptography only power CLOUD mode (pairing, heartbeat
# signing, token verification). LAN-only installs never touch them, and the
# embedded hosts in docs/third-party-printers.md (no pip, no prebuilt wheels)
# can't install them at all - so their absence must not stop the module from
# loading. _CLOUD_DEPS_ERROR doubles as the "why" surfaced in the log, the
# MOONGATE_PAIR console output and error responses when a CLOUD-mode box is
# missing them.
try:
    import jwt as pyjwt  # PyJWT
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import (
        Ed25519PrivateKey,
        Ed25519PublicKey,
    )
    _CLOUD_DEPS_ERROR: Optional[str] = None
except ImportError as _deps_exc:
    pyjwt             = None  # type: ignore[assignment]
    serialization     = None  # type: ignore[assignment]
    Ed25519PrivateKey = None  # type: ignore[assignment]
    Ed25519PublicKey  = None  # type: ignore[assignment]
    _CLOUD_DEPS_ERROR = (
        f"cloud dependencies unavailable ({_deps_exc}); cloud pairing and "
        "heartbeats are disabled. Install PyJWT[crypto] + cryptography into "
        "Moonraker's Python, or run LAN-only (lan_only: true)."
    )

logger = logging.getLogger("moonraker.moongate")

# Bumped on each release; surfaced in the /status response so the app's bug
# reports show which plugin a Pi is actually running - the #1 triage blind spot
# (an old plugin explains most "works on LAN / fails over tunnel" reports).
MOONGATE_PLUGIN_VERSION = "0.6.18"


# ═══════════════════════════════════════════════════════════════════════════════
# Paths + defaults
# ═══════════════════════════════════════════════════════════════════════════════

CONFIG_DIR   = Path.home() / ".config" / "moongate"
DEVICE_KEY   = CONFIG_DIR / "device_ed25519"
OWNER_FILE   = CONFIG_DIR / "owner.json"
CONFIG_FILE  = CONFIG_DIR / "config.json"
JWKS_CACHE   = CONFIG_DIR / "jwks.json"

# v0.4.4 - Avahi mDNS advertisement for LAN discovery from the v0.5+ app.
# See docs/v0.5-lan-discovery-design.md §6 for the full design.
# AVAHI_SERVICE_TMP lives in the pi-owned config dir; the install-time
# sudoers entry at /etc/sudoers.d/moongate-avahi permits exactly one cp
# from AVAHI_SERVICE_TMP to AVAHI_SERVICE_FILE and one rm of the latter.
AVAHI_SERVICE_FILE = Path("/etc/avahi/services/moongate.service")
AVAHI_SERVICE_TMP  = CONFIG_DIR / "moongate-avahi.service.tmp"

AVAHI_SERVICE_TEMPLATE = """<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Moongate on %h</name>
  <service>
    <type>_moongate._tcp</type>
    <port>{http_port}</port>
    <txt-record>printer_id={printer_id}</txt-record>
    <txt-record>http_port={http_port}</txt-record>
    <txt-record>version=v0.5</txt-record>
  </service>
</service-group>
"""

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
    # LAN-only mode: no cloud, no tunnel. Set true by install.sh --lan-only.
    # Pairing becomes a cloud-free "add by LAN address" QR, and /status +
    # /control skip the EdDSA token (LAN is trusted by subnet, exactly as
    # Moonraker's own trusted_clients treats it). See _authenticate + _handle_qr.
    "lan_only":                   False,
}

ACCESS_TOKEN_AUDIENCE = "moongate-printer"
ACCESS_TOKEN_ISSUER   = "moongate"

# Enrollment-token format: GATE-XXXX-XXXX, digits only (easy to type on phone)
CODE_CHARS = string.digits


# ═══════════════════════════════════════════════════════════════════════════════
# Network helpers (kept from v0.2.x - same cloudflared URL detection logic)
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


# Cloudflare's tunnel-provisioning API lives on the same trycloudflare.com
# domain but is NOT a tunnel - cloudflared prints it in its own output/logs, and
# the loose regex below otherwise matches it (seen in the wild as a bogus
# reported URL, https://api.trycloudflare.com). Never treat it as our tunnel.
_NON_TUNNEL_URLS = {"https://api.trycloudflare.com"}


def _get_tunnel_url() -> Optional[str]:
    """Return the active Cloudflare Quick Tunnel URL or None."""
    pattern = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com")

    def _pick(text: str, *, last: bool) -> Optional[str]:
        urls = [u for u in pattern.findall(text) if u not in _NON_TUNNEL_URLS]
        if not urls:
            return None
        return urls[-1] if last else urls[0]

    # 1. cloudflared local REST API - always-live URL
    for port in (20241, 2000):
        for path in ("/quicktunnel", "/metrics", "/"):
            try:
                with urllib.request.urlopen(f"http://localhost:{port}{path}", timeout=2) as resp:
                    body = resp.read().decode(errors="replace")
                    url = _pick(body, last=False)
                    if url:
                        return url
            except Exception:
                pass

    # 2. log file - last match survives URL rotation
    for p in (Path("/run/moongate-tunnel.log"), Path("/tmp/moongate-tunnel.log")):
        if p.exists():
            try:
                url = _pick(p.read_text(), last=True)
                if url:
                    return url
            except Exception:
                pass

    # 3. journalctl fallback
    for unit in ("moongate-tunnel", "cloudflared"):
        try:
            result = subprocess.run(
                ["journalctl", "-u", unit, "--no-pager", "-n", "500"],
                capture_output=True, text=True, timeout=5,
            )
            url = _pick(result.stdout, last=True)
            if url:
                return url
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
# DeviceKey - Ed25519 keypair persisted on disk
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
# JwksCache - fetch + cache the EdDSA verification keys
# ═══════════════════════════════════════════════════════════════════════════════

class JwksCache:
    # Minimum spacing between /jwks fetch ATTEMPTS. A successful fetch is
    # naturally rate-limited by `ttl` (it updates _fetched_at), but a FAILED
    # one is not - fetch_now() leaves _fetched_at stale on failure, so before
    # this guard a Pi whose fetch never succeeds (no network, or a broken
    # cryptography lib yielding "no usable keys" from a 200) re-fetched on
    # EVERY token verification. One such Pi was ~245 calls/hr - nearly all
    # the jwks Edge Function invocations fleet-wide (2026-07-09 log audit).
    # Worst case this adds ~2 min of 401s after an outage before keys land.
    FETCH_RETRY_SECONDS = 120

    def __init__(self, supabase_url: str, anon_key: str, cache_path: Path, ttl: int) -> None:
        self.supabase_url = supabase_url.rstrip("/")
        self.anon_key     = anon_key
        self.cache_path   = cache_path
        self.ttl          = ttl
        self._keys:        Dict[str, Ed25519PublicKey] = {}
        self._fetched_at:  float                       = 0.0
        self._attempt_at:  float                       = 0.0
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
        self._attempt_at = time.time()
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
            # Bad fetch - keep prior cache rather than going zero-key.
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
        now = time.time()
        if (now - self._fetched_at > self.ttl
                and now - self._attempt_at > self.FETCH_RETRY_SECONDS):
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


# Placeholder claims returned by _authenticate in LAN-only mode. The status and
# control handlers only call _authenticate for its enforcement side-effect and
# ignore the return, so the field values are never read - they just satisfy the
# type. LAN-only has no owner/token concept.
_LAN_ONLY_CLAIMS = TokenClaims(
    sub="lan-only", printer_id="lan-only", aud=ACCESS_TOKEN_AUDIENCE,
    iss=ACCESS_TOKEN_ISSUER, exp=0, iat=0, jti="lan-only",
)


class AccessTokenVerifier:
    def __init__(self, jwks: JwksCache) -> None:
        self.jwks = jwks

    def verify(
        self,
        token: str,
        expected_printer_id: Optional[str],
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
        # No owner ("sub") pin here: a validly-signed, printer-scoped token is
        # only ever minted by the cloud to the printer's CURRENT owner, so
        # _authenticate honors a token bearing a new sub (a cloud ownership
        # transfer, e.g. a backup restore) by re-binding, rather than refusing.

        return TokenClaims(
            sub=payload["sub"], printer_id=printer_id,
            aud=payload["aud"], iss=payload["iss"],
            exp=int(payload["exp"]), iat=int(payload["iat"]),
            jti=str(payload.get("jti", "")),
        )


# ═══════════════════════════════════════════════════════════════════════════════
# OwnerState - persisted (printer_id, owner_user_id) after first claim
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
        # Clock delta (local − server) in seconds, taken from the most recent
        # response's Date header. Lets a 401 be explained as clock drift - the
        # usual cause of "everything's running but remote never connects" - rather
        # than a bald "signature or replay window failure". None until first seen.
        self._server_skew: Optional[float] = None

    def _post(self, path: str, body: dict, timeout: float = 10.0) -> tuple[int, dict]:
        full_url = f"{self.url}/functions/v1{path}"
        data     = json.dumps(body).encode()
        req      = urllib.request.Request(
            full_url, data=data, method="POST",
            headers={"apikey": self.anon_key, "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                self._note_server_date(resp.headers)
                raw = resp.read().decode() if resp.length != 0 else ""
                return resp.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as exc:
            self._note_server_date(exc.headers)
            try:
                body_dict = json.loads(exc.read().decode())
            except Exception:
                body_dict = {}
            return exc.code, body_dict
        except Exception as exc:
            logger.warning("Supabase request %s failed: %s", path, exc)
            return 0, {"error": str(exc)}

    def _note_server_date(self, headers: Any) -> None:
        """Record clock skew (local − server, seconds) from a response's Date
        header. Cheap and side-channel - every Edge Function response carries one,
        so a later 401 can be attributed to a wrong Pi clock with no extra call."""
        try:
            date_hdr = headers.get("Date") if headers is not None else None
            if not date_hdr:
                return
            server_epoch = parsedate_to_datetime(date_hdr).timestamp()
        except (TypeError, ValueError, AttributeError):
            return
        self._server_skew = time.time() - server_epoch

    def clock_skew_seconds(self) -> Optional[float]:
        """Most recent (local − server) clock delta in seconds, or None if no
        response has carried a parseable Date header yet."""
        return self._server_skew

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

    def send_push(
        self,
        pi_public_key_b64: str,
        event: str,
        detail: str,
        timestamp: int,
        signature_b64: str,
    ) -> tuple[int, dict]:
        """Tell the cloud a print changed state so it can push a notification
        to the owner's phone(s). Pi-signed, verified server-side against
        pi_public_key exactly like the heartbeat. Fires only on real events
        (start / finish / fail), so it's a trickle, not a poll."""
        return self._post("/send-push", {
            "pi_public_key": pi_public_key_b64,
            "event":         event,
            "detail":        detail,
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
        on_dormant_cb=None,
    ) -> None:
        self.device      = device
        self.sb          = sb
        self.interval    = interval
        self.on_unpaired = on_unpaired_cb
        self.on_dormant  = on_dormant_cb
        self._task: Optional[asyncio.Task] = None
        self._last_url_reported: Optional[str] = None
        # Orphan dormancy (v0.6.15). A Pi whose cloud row is gone for good
        # used to heartbeat forever - ~8.6k Edge Function calls/month each at
        # the steady cadence, and one pre-0.6.10 spinner ≈ the whole free
        # quota (2026-06-24 and 2026-07-13 log audits). Once the server has
        # answered "no such printer" for a full day with no pairing activity,
        # or has said outright that the owner released this printer (410),
        # the loop drops to a 6-hourly pulse. Any poke (MOONGATE_PAIR, an
        # owner bind) or an accepted heartbeat wakes it instantly, so every
        # recovery path is untouched. In-memory only: a Moonraker restart
        # buys one more day of steady-cadence probing before re-dorming,
        # which is self-limiting and makes a stuck-dormant state impossible.
        self._dormant:         bool            = False
        self._notfound_streak: int             = 0
        self._notfound_since:  Optional[float] = None
        # Wall-clock deadline until which we hold the fast bootstrap cadence
        # after a pairing poke, so a transient send failure (e.g. flaky WiFi)
        # doesn't drop us to the 5-minute interval mid-pair. 0 = not active.
        self._fast_deadline: float = 0.0
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

    # Quick-retry cadence used after Pi boot while cloudflared hasn't
    # published a URL yet (or while the cloud row hasn't been created).
    # ~20-25 s of cloudflared startup × 300 s heartbeat interval = up to
    # 5 minutes of "Starting up..." tile state for a user who pairs
    # right after a Pi reboot. With this we catch the URL within a few
    # seconds of cloudflared publishing it.
    _BOOTSTRAP_INTERVAL = 5

    # Upper bound on any fast-cadence window (bootstrap, post-poke, post-404).
    # Inside a window we keep the 5 s bootstrap cadence until a report succeeds,
    # but never longer than this, so a genuinely offline or orphaned Pi falls
    # back to the steady interval instead of retrying forever. It is also what
    # stops a one-off "No route to host" during pairing from costing a full
    # 5-minute heartbeat cycle (flaky-WiFi boards like the CB1).
    _FAST_WINDOW_SECONDS = 180

    # Dormancy trigger: this many CONSECUTIVE confirmed "not_found" answers
    # spanning at least _DORMANT_AFTER_SECONDS, with no pairing activity in
    # between. The count floor keeps a handful of stray 404s from qualifying;
    # the time floor keeps a legitimate "reset tonight, re-pair tomorrow" gap
    # from qualifying (waiting costs ~288 calls per orphan event - nothing
    # next to the ~8.6k/month an orphan burns forever). Only bodies carrying
    # the server's own {"error": "not_found"} marker count, so a proxy/CDN
    # 404 during an outage can never dorm the fleet.
    _DORMANT_MIN_STREAK    = 12
    _DORMANT_AFTER_SECONDS = 24 * 3600

    # Dormant pulse cadence. ~4 calls/day (vs ~288) keeps "the row came back"
    # recovery alive without the cost - and means dormant never equals dead.
    _DORMANT_INTERVAL = 6 * 3600

    async def _run(self) -> None:
        # First heartbeat after a brief delay so cloudflared has time to come up
        await asyncio.sleep(5)
        self._poke_event = asyncio.Event()
        # Arm the bootstrap fast window so we catch cloudflared's URL within a
        # few seconds of it publishing. Bounded by _FAST_WINDOW_SECONDS so a Pi
        # that never lands a cloud row (e.g. orphaned by reset-owner) does not
        # poll /printer-heartbeat every 5 s forever.
        self._fast_deadline = time.time() + self._FAST_WINDOW_SECONDS
        while True:
            try:
                self._send_one()
            except Exception as exc:
                logger.warning("Heartbeat iteration crashed: %s", exc)
            # Until we've successfully reported a URL once, poll fast
            # so the cloud picks up the tunnel within seconds of
            # cloudflared coming online. After the first successful
            # heartbeat, drop to the configured cadence.
            # Fast cadence only inside a bounded window: the bootstrap window
            # (armed above), the post-poke window (request_immediate_send), or
            # the post-404 re-pair window. Each is capped by _FAST_WINDOW_SECONDS
            # so a Pi that never lands a cloud row falls back to the steady
            # interval instead of polling every 5 s forever. A dormant orphan
            # sits below even the steady interval, on the 6-hourly pulse.
            fast = time.time() < self._fast_deadline
            if self._dormant:
                effective_interval = self._DORMANT_INTERVAL
            elif fast:
                effective_interval = self._BOOTSTRAP_INTERVAL
            else:
                effective_interval = self.interval
            # Wait for either the scheduled interval OR a poke from
            # MOONGATE_PAIR. Poke wakes the loop early so the cloud sees
            # the current tunnel URL before the user's app calls
            # /printer-access, instead of the user waiting up to
            # `interval` seconds in "Starting up..." tile state.
            try:
                await asyncio.wait_for(self._poke_event.wait(), timeout=effective_interval)
                self._poke_event.clear()
                logger.debug("Heartbeat poked - sending early")
            except asyncio.TimeoutError:
                pass  # Normal interval elapsed
            except asyncio.CancelledError:
                return

    def request_immediate_send(self) -> None:
        """Wake the heartbeat loop to send NOW, and hold the fast bootstrap
        cadence until the report succeeds (bounded by [_FAST_WINDOW_SECONDS]).

        This is what makes re-pairing resilient to a transient network blip: a
        single failed heartbeat (e.g. 'No route to host' on flaky WiFi) used to
        drop the loop back to the 5-minute interval, so the freshly-created cloud
        row didn't get its tunnel URL for minutes - a long "Starting up…" wait.
        Now we keep retrying every few seconds until the cloud accepts it.

        Idempotent; the poke itself is a no-op until the loop has started (the
        first 5 s post-boot), but the fast window is still armed.

        A poke is also what wakes a dormant orphan: every pairing path runs
        through here (MOONGATE_PAIR and the owner bind in _authenticate), so
        dormancy ends the instant a user starts pairing - no special recovery
        step to know about."""
        self._fast_deadline = time.time() + self._FAST_WINDOW_SECONDS
        self._clear_orphan_state("pairing activity")
        if self._poke_event is not None:
            self._poke_event.set()

    def _send_one(self) -> None:
        tunnel = _get_tunnel_url()
        if not tunnel:
            logger.debug("Heartbeat skipped - tunnel URL not yet available")
            return

        ts        = int(time.time())
        pk_b64    = self.device.public_key_b64
        canonical = f"moongate-heartbeat\n{pk_b64}\n{tunnel}\n{ts}".encode()
        sig_b64   = self.device.sign_b64(canonical)

        status, body = self.sb.heartbeat(pk_b64, tunnel, ts, sig_b64)
        if status in (200, 204):
            # Got through - drop out of the post-poke fast window and resume the
            # steady cadence.
            self._fast_deadline = 0.0
            self._clear_orphan_state("heartbeat accepted")
            if tunnel != self._last_url_reported:
                logger.info("Heartbeat: reported tunnel URL %s", tunnel)
                self._last_url_reported = tunnel
            return
        if status == 404:
            logger.warning("Heartbeat 404 - printer record gone server-side")
            # The cloud row we knew is gone, typically because a re-pair or
            # reset-owner created a NEW row. On the FIRST 404 after we were
            # healthy, hold the fast bootstrap cadence for a bounded window so we
            # report our tunnel URL into that new row within ~5 s, instead of
            # waiting up to a full heartbeat interval (5 min). Without this,
            # re-pairing on a network that blocks mDNS left the tile
            # "Starting up…" for minutes while the app waited.
            #
            # Crucially we only arm on that first 404 (while _last_url_reported
            # is still set). Repeated 404s mean the Pi is genuinely orphaned and
            # no new row is coming, so we must NOT keep re-arming or it would
            # spin at 5 s forever (~720 calls/hour). Left alone the window lapses
            # and the loop falls back to the steady cadence (~12 calls/hour).
            if self._last_url_reported is not None:
                self._fast_deadline = time.time() + self._FAST_WINDOW_SECONDS
            self._last_url_reported = None
            if self.on_unpaired:
                try:
                    self.on_unpaired()
                except Exception as exc:
                    logger.warning("on_unpaired callback failed: %s", exc)
            # Count only the server's own answer towards dormancy - a generic
            # gateway/CDN 404 (no marker body) stays a transient.
            if body.get("error") == "not_found":
                self._note_confirmed_notfound()
            return
        if status == 410:
            # Explicit, server-verified answer: the owner deliberately released
            # this printer (its tombstone row is still on the server). No
            # guessing needed - stop the cloud chatter right away. MOONGATE_PAIR
            # wakes us and pairs again as if nothing happened.
            logger.warning("Heartbeat 410 - the owner released this printer")
            self._last_url_reported = None
            if self.on_unpaired:
                try:
                    self.on_unpaired()
                except Exception as exc:
                    logger.warning("on_unpaired callback failed: %s", exc)
            if body.get("error") == "printer_released":
                self._enter_dormant("released by its owner")
            return
        if status == 401:
            skew = self.sb.clock_skew_seconds()
            if skew is not None and abs(skew) > 60:
                logger.warning(
                    "Heartbeat 401: Pi clock is ~%+ds vs server time (limit ±60s) - "
                    "remote access will keep failing until the clock is synced. A Pi "
                    "has no battery clock; if NTP is blocked, sync over HTTPS (htpdate). "
                    "Check with: timedatectl",
                    int(skew),
                )
            else:
                logger.warning("Heartbeat 401 - signature or replay window failure")
            return
        logger.warning("Heartbeat HTTP %s: %s", status, body)

    # ── Orphan dormancy (v0.6.15) ────────────────────────────────────────────

    @property
    def dormant(self) -> bool:
        return self._dormant

    def _note_confirmed_notfound(self) -> None:
        """Advance the orphan evidence: one more confirmed "no such printer"
        answer. Network errors and 401s neither count nor reset - only an
        accepted heartbeat or pairing activity clears the streak."""
        now = time.time()
        if self._notfound_since is None:
            self._notfound_since = now
        self._notfound_streak += 1
        if (not self._dormant
                and self._notfound_streak >= self._DORMANT_MIN_STREAK
                and now - self._notfound_since >= self._DORMANT_AFTER_SECONDS
                and now >= self._fast_deadline):
            self._enter_dormant("unknown to the cloud for a day")

    def _clear_orphan_state(self, reason: str) -> None:
        self._notfound_streak = 0
        self._notfound_since  = None
        if self._dormant:
            self._dormant = False
            logger.info("Heartbeat waking from dormant (%s)", reason)

    def _enter_dormant(self, why: str) -> None:
        if self._dormant:
            return
        self._dormant = True
        logger.warning(
            "Heartbeat going dormant (this printer was %s): dropping to one "
            "pulse every %d h. Run MOONGATE_PAIR to pair again at any time.",
            why, self._DORMANT_INTERVAL // 3600)
        if self.on_dormant:
            try:
                self.on_dormant(why)
            except Exception as exc:
                logger.warning("on_dormant callback failed: %s", exc)


# ═══════════════════════════════════════════════════════════════════════════════
# PrintEventWatcher - local print-state watch → push notifications
# ═══════════════════════════════════════════════════════════════════════════════

class PrintEventWatcher:
    """Polls Moonraker's print_stats locally and, on a meaningful state change
    (a print starting, finishing, or failing), sends a Pi-signed event to the
    send-push Edge Function so the printer owner's iPhone gets a background
    alert.

    Detection is entirely local - we poll our own Moonraker, never the cloud -
    so the only Supabase call is the one-shot send when an event actually fires
    (~2 per print, not a continuous stream). Signed with the same Ed25519
    device key as the heartbeat; the server verifies it identically.

    Unpaired / pre-APNs Pis degrade quietly: the send simply 404s (no printer
    row server-side), and we log at debug and carry on."""

    # Local poll cadence. A localhost call is cheap, so this is small enough to
    # catch a finished print promptly without being chatty.
    _POLL_INTERVAL = 20

    def __init__(self, device: DeviceKey, sb: SupabaseClient,
                 moonraker_port: int = 7125, is_dormant=None) -> None:
        self.device = device
        self.sb     = sb
        self.port   = moonraker_port
        # Callable answering "is cloud contact dormant?" (see HeartbeatLoop).
        # A dormant Pi's row is gone server-side, so a send could only 404 -
        # skip it and keep the orphan's cloud footprint at the pulse alone.
        self._is_dormant = is_dormant
        self._task: Optional[asyncio.Task] = None
        # Last print_stats.state we saw. None until the first poll, which only
        # establishes a baseline - we never fire an event for whatever state
        # the printer happens to be in when the plugin loads.
        self._last_state: Optional[str] = None

    def start(self) -> None:
        try:
            loop = asyncio.get_event_loop()
        except RuntimeError:
            logger.warning("No running event loop; print watcher will be deferred")
            return
        self._task = loop.create_task(self._run())

    async def _run(self) -> None:
        loop = asyncio.get_event_loop()
        while True:
            try:
                state, filename = await loop.run_in_executor(None, self._poll_print_state)
                if state is not None and state != self._last_state:
                    event = self._event_for(self._last_state, state)
                    self._last_state = state
                    if event and self._is_dormant is not None and self._is_dormant():
                        logger.debug(
                            "Push event '%s' skipped - cloud contact dormant", event)
                    elif event:
                        await loop.run_in_executor(None, self._send_event, event, filename)
            except asyncio.CancelledError:
                return
            except Exception as exc:
                logger.warning("Print watcher iteration crashed: %s", exc)
            try:
                await asyncio.sleep(self._POLL_INTERVAL)
            except asyncio.CancelledError:
                return

    @staticmethod
    def _event_for(prev: Optional[str], state: str) -> Optional[str]:
        """Map a print_stats transition to a push event, or None for the ones
        we don't alert on. prev is None on the first poll (baseline, no event).
        A user-initiated 'cancelled' is deliberately not alerted in v1, and a
        'paused' → 'printing' resume is not treated as a fresh start."""
        if prev is None:
            return None
        if state == "printing" and prev != "paused":
            return "started"
        if state == "complete":
            return "completed"
        if state == "error":
            return "failed"
        return None

    def _poll_print_state(self) -> tuple[Optional[str], str]:
        """Read print_stats.state and .filename from the local Moonraker.
        Returns (None, "") on any failure so the loop simply skips this tick
        without disturbing the baseline."""
        try:
            url = f"http://127.0.0.1:{self.port}/printer/objects/query?print_stats"
            with urllib.request.urlopen(url, timeout=5) as resp:
                data = json.loads(resp.read().decode())
            ps = data["result"]["status"]["print_stats"]
            return ps.get("state"), (ps.get("filename") or "")
        except Exception as exc:
            logger.debug("print_stats poll failed: %s", exc)
            return None, ""

    def _send_event(self, event: str, filename: str) -> None:
        ts        = int(time.time())
        pk_b64    = self.device.public_key_b64
        detail    = (filename or "")[:200]
        canonical = f"moongate-push\n{pk_b64}\n{event}\n{detail}\n{ts}".encode()
        sig_b64   = self.device.sign_b64(canonical)

        status, body = self.sb.send_push(pk_b64, event, detail, ts, sig_b64)
        if status in (200, 204):
            logger.info("Push event '%s' sent", event)
        elif status == 404:
            logger.debug("Push event '%s' skipped - printer not paired server-side", event)
        else:
            logger.warning("Push event '%s' failed: HTTP %s %s", event, status, body)


# ═══════════════════════════════════════════════════════════════════════════════
# PendingPair - the active enrollment-token session
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

        # ── v0.6.17: optional [moongate] options in moonraker.conf ───────────
        # Embedded hosts (docs/third-party-printers.md) often can't run
        # install.sh or write ~/.config, so the knobs that matter there live in
        # the one file they CAN edit. Everything defaults to the historic
        # behaviour: config.json keeps working, moonraker.conf wins when set.
        conf_lan_only  = None
        conf_data_path = None
        conf_mr_port   = None
        try:
            conf_lan_only  = config.getboolean("lan_only", None)
            conf_data_path = config.get("data_path", None)
            conf_mr_port   = config.getint("moonraker_port", None)
        except Exception:
            pass  # duck-typed/legacy config objects: historic defaults

        self._data_dir        = (Path(conf_data_path).expanduser()
                                 if conf_data_path else CONFIG_DIR)
        self._device_key_file = self._data_dir / "device_ed25519"
        self._owner_file      = self._data_dir / "owner.json"
        self._config_file     = self._data_dir / "config.json"
        self._jwks_cache_file = self._data_dir / "jwks.json"
        self._avahi_tmp_file  = self._data_dir / "moongate-avahi.service.tmp"
        try:
            self._data_dir.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            logger.error(
                "Moongate: cannot create data dir %s (%s). Set data_path in "
                "the [moongate] section to a writable location.",
                self._data_dir, exc)
            raise

        self._config            = self._load_config()
        self._lan_only_override = conf_lan_only

        # Where Moonraker itself listens: an explicit moonraker_port wins,
        # else ask the server (embedded builds bind :80, not :7125), else the
        # stock default.
        mr_port = conf_mr_port
        if not mr_port:
            try:
                mr_port = int(self.server.get_host_info().get("port") or 0)
            except Exception:
                mr_port = 0
        self._moonraker_port = mr_port or 7125

        # Cloud machinery only exists when cloud mode is both wanted and
        # possible. LAN-only skips it wholesale (no Ed25519 keygen, no key
        # file, zero extra deps); a CLOUD-mode box missing PyJWT/cryptography
        # still loads (the LAN endpoints keep working) and says exactly what
        # is wrong in the log and its error responses instead of crashing
        # Moonraker.
        self._plugin_error = None if self.lan_only else _CLOUD_DEPS_ERROR
        cloud_ready        = not self.lan_only and _CLOUD_DEPS_ERROR is None

        self.owner = OwnerState.load(self._owner_file)
        if cloud_ready:
            self.device    = DeviceKey(self._device_key_file)
            self.jwks      = JwksCache(
                self._config["supabase_url"],
                self._config["supabase_anon_key"],
                self._jwks_cache_file,
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
                on_dormant_cb=self._on_dormant,
            )
            self.watcher   = PrintEventWatcher(
                self.device, self.sb,
                moonraker_port=self._moonraker_port,
                is_dormant=lambda: self.heartbeat.dormant,
            )
        else:
            self.device    = None
            self.jwks      = None
            self.verifier  = None
            self.sb        = None
            self.heartbeat = None
            self.watcher   = None

        self._pending: Optional[PendingPair]   = None
        self._chamber_key: Optional[str]       = None
        self._chamber_key_checked: bool        = False
        self._extra_extruders                  = []     # extruder1, extruder2, ... (multi-toolhead)
        self._has_toolchanger                  = False  # klipper-toolchanger printer

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

        # Bootstrap JWKS (best effort) and start the heartbeat + print-watch loops.
        # LAN-only mode has no cloud: skip all of it so the plugin makes zero
        # outbound calls (no Supabase JWKS fetch, no heartbeat, no print-event push).
        if cloud_ready:
            self.jwks.fetch_now()
            self.heartbeat.start()
            self.watcher.start()
        elif self.lan_only:
            logger.info("Moongate LAN-only mode: cloud loops disabled (no tunnel, no Supabase).")
        else:
            logger.error("Moongate: %s", self._plugin_error)

        owner_str = (
            f"{self.owner.owner_user_id[:8]}.../{self.owner.printer_id[:8]}..."
            if self.owner else "unpaired"
        )
        logger.info("Moongate v0.3 plugin loaded. Owner: %s. Tunnel: %s",
                    owner_str, _get_tunnel_url() or "not up")

        # v0.4.4: defensive re-write of the Avahi service file if the Pi
        # is paired but the file isn't there. Covers (a) upgrade from
        # pre-v0.4.4, (b) manual deletion, (c) the file being lost during
        # a system update that wiped /etc/avahi/services/.
        # Cloud mode only: a LAN-only (or deps-missing) box never advertises -
        # a stale owner.json from an earlier cloud install must not trigger
        # sudo attempts on hosts that have neither sudo nor avahi.
        if (self.device is not None and self.owner is not None
                and not AVAHI_SERVICE_FILE.exists()):
            self._write_avahi_service()

    # ── Config ────────────────────────────────────────────────────────────────

    def _load_config(self) -> dict:
        cfg = DEFAULT_CONFIG.copy()
        if self._config_file.exists():
            try:
                user_cfg = json.loads(self._config_file.read_text())
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

    @property
    def lan_only(self) -> bool:
        # moonraker.conf's [moongate] lan_only (when present) beats config.json
        # - the embedded-host path, where config.json may not even exist.
        if self._lan_only_override is not None:
            return bool(self._lan_only_override)
        return bool(self._config.get("lan_only", False))

    # ── Pairing ───────────────────────────────────────────────────────────────

    @staticmethod
    def _generate_enrollment_token() -> str:
        part1 = "".join(random.choices(CODE_CHARS, k=4))
        part2 = "".join(random.choices(CODE_CHARS, k=4))
        return f"GATE-{part1}-{part2}"

    def _lan_qr_payload(self) -> Optional[str]:
        """LAN-only QR: ``moongate://lan?v=1&ip=<lan-ip>&port=<http-port>&name=<host>``.

        No cloud, no enrollment token - it just tells the app to add this
        printer by its LAN address and talk to Moonraker directly. Static (the
        IP/port), so it needs no pairing session and never expires. Returns
        None only if the Pi's LAN IP can't be determined."""
        import socket
        local_ip = _get_local_ip()
        if not local_ip or local_ip == "localhost":
            return None
        params = {"v": "1", "ip": local_ip, "port": str(self.http_port)}
        try:
            host = socket.gethostname()
        except Exception:
            host = ""
        if host:
            params["name"] = host
        return "moongate://lan?" + urllib.parse.urlencode(params)

    def _start_pairing(self) -> Optional[PendingPair]:
        if self.lan_only:
            # LAN-only: no Supabase enrollment. The QR carries only the LAN
            # address; the app adds the printer directly and talks to Moonraker
            # over the LAN (no owner binding, no tunnel).
            qr = self._lan_qr_payload()
            if qr is None:
                logger.error("LAN-only pair: could not determine the Pi's LAN IP")
                return None
            pending = PendingPair(
                raw_token="", expires_at=time.time() + 3600, qr_payload=qr,
            )
            self._pending = pending
            return pending

        if self.device is None:
            # Cloud mode without its deps: _plugin_error says how to fix it.
            logger.error("Moongate pair unavailable: %s", self._plugin_error)
            return None

        raw  = self._generate_enrollment_token()
        hash_b64 = _b64std(hashlib.sha256(raw.encode()).digest())

        status, body = self.sb.enroll_prepare(self.device.public_key_b64, hash_b64)
        if status not in (200, 204):
            logger.error("enroll-prepare failed: HTTP %s %s", status, body)
            return None

        # v0.5.1: embed the Pi's LAN address in the QR so the app can connect
        # Local the instant it scans - no mDNS round-trip, no waiting for the
        # cloud heartbeat. This is the key to "instant Local on pair": a fresh
        # pair has no mDNS advert yet (the Pi only advertises AFTER an owner
        # binds, and binding needs a LAN call first - a chicken-and-egg the
        # app can't break on its own). The QR is generated here (we know our
        # own IP) and scanned on the same network, so the private IP is a pure
        # LAN-local hand-off - it never travels through the cloud. After the
        # owner binds over this URL, mDNS takes over to keep Local alive across
        # IP changes. Older apps ignore unknown query params, so this is
        # backward-compatible.
        local_ip = _get_local_ip()
        qr_params = {
            "v":  "3",
            "pk": self.device.public_key_b64,
            "et": raw,
        }
        if local_ip and local_ip != "localhost":
            qr_params["ip"]   = local_ip
            qr_params["port"] = str(self.http_port)
        qr = "moongate://pair?" + urllib.parse.urlencode(qr_params)
        pending = PendingPair(
            raw_token=raw,
            expires_at=time.time() + int(self._config["enrollment_ttl_seconds"]),
            qr_payload=qr,
        )
        self._pending = pending
        return pending

    async def _klipper_pair(self) -> None:
        """MOONGATE_PAIR macro entry point."""
        if self.lan_only:
            await self._klipper_pair_lan()
            return

        if self.device is None:
            # Cloud mode but the crypto deps are missing (embedded host or a
            # broken venv): a generic "Supabase unreachable" would send the
            # user chasing their network, so say the real cause.
            script = "\n".join([
                "M118 ============================================",
                "M118 Moongate: cloud pairing unavailable.",
                "M118 Python deps missing (PyJWT + cryptography).",
                "M118 Install them into Moonraker's Python, or",
                "M118 reinstall Moongate in LAN-only mode.",
                "M118 ============================================",
            ])
            try:
                klippy_apis: Any = self.server.lookup_component("klippy_apis")
                await klippy_apis.run_gcode(script)
            except Exception as exc:
                logger.error("run_gcode failed: %s", exc)
            return

        pending = self._start_pairing()
        await asyncio.sleep(0.3)

        if pending is not None:
            # User is now actively waiting to scan. Kick the heartbeat so
            # the cloud has a fresh tunnel URL by the time their app calls
            # /printer-access - saves up to `heartbeat_interval_seconds`
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
            # - which a new user pairing for the first time doesn't have
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
                "M118 Option A - Scan the QR. Open this URL on a",
                "M118 PC, tablet, or other phone:",
                f"M118   {local_page}",
                "M118 then scan the QR with the Moongate app",
                "M118 (Add Printer > Scan QR code).",
                "M118 ==========================================",
                "M118 Option B - Type the code in the app:",
                "M118 Add Printer > GATE code field.",
                "M118 ==========================================",
                f"M118 Code expires in {ttl_min} minutes.",
            ]
            script = "\n".join(lines)

        try:
            klippy_apis: Any = self.server.lookup_component("klippy_apis")
            await klippy_apis.run_gcode(script)
        except Exception as exc:
            logger.error("run_gcode failed: %s", exc)

    async def _klipper_pair_lan(self) -> None:
        """MOONGATE_PAIR in LAN-only mode: no cloud, no GATE code. Print the
        pair-page URL (scan the QR) and the direct LAN address (manual add)."""
        local_ip = _get_local_ip()
        if not local_ip or local_ip == "localhost":
            script = "\n".join([
                "M118 ==========================================",
                "M118 Moongate LAN-only: could not find the Pi's LAN IP.",
                "M118 Check the network, then try MOONGATE_PAIR again.",
                "M118 ==========================================",
            ])
        else:
            port_sfx   = "" if self.http_port == 80 else f":{self.http_port}"
            local_page = f"http://{local_ip}{port_sfx}/moongate-pair.html"
            lan_addr   = f"http://{local_ip}{port_sfx}"
            logger.info("MOONGATE LAN-only pair page: %s", local_page)
            script = "\n".join([
                "M118 ==========================================",
                "M118 Moongate LAN-only (no tunnel, no cloud)",
                "M118 ==========================================",
                "M118 Option A - Scan the QR. Open this URL on a",
                "M118 PC, tablet, or other phone:",
                f"M118   {local_page}",
                "M118 then scan it with the Moongate app",
                "M118 (Add Printer > Scan QR code).",
                "M118 ==========================================",
                "M118 Option B - Add Printer > Direct (LAN/VPN),",
                "M118 enter this address:",
                f"M118   {lan_addr}",
                "M118 ==========================================",
                "M118 Your phone must be on this LAN / your VPN.",
            ])
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
        # No cloud machinery (LAN-only or missing deps) - nothing to release.
        # Also fixes a lan_only wart: 0.6.16 still fired one outbound release
        # POST here despite the mode's zero-outbound-calls promise.
        if self.device is None:
            return had_owner, 0
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
            return "M118 Cloud release skipped - network unavailable."
        return f"M118 Cloud release failed - HTTP {status}."

    def _wipe_owner(self) -> None:
        self.owner = None
        try:
            if self._owner_file.exists():
                self._owner_file.unlink()
        except OSError as exc:
            logger.warning("Failed to delete %s: %s", self._owner_file, exc)
        # v0.4.4: stop advertising on mDNS when we lose owner state - the Pi
        # is no longer paired so it shouldn't be discoverable.
        self._remove_avahi_service()

    def _on_unpaired(self) -> None:
        """Heartbeat callback: server says printer is gone."""
        if self.owner is not None:
            logger.warning("Server has no record of this printer - wiping local owner state")
            self._wipe_owner()

    def _on_dormant(self, why: str) -> None:
        """Heartbeat callback: cloud contact just went dormant. Put a notice in
        the Klipper console (best effort - Klipper may be down or mid-restart)
        so someone standing at the printer knows why the app can't see it and
        how to bring it back; moonraker.log always carries the same message."""
        async def _notify() -> None:
            script = "\n".join([
                "M118 ============================================",
                f"M118 Moongate: this printer was {why},",
                "M118 so cloud contact is paused.",
                "M118 The printer itself is unaffected.",
                "M118 Run MOONGATE_PAIR to pair again.",
                "M118 ============================================",
            ])
            try:
                klippy_apis: Any = self.server.lookup_component("klippy_apis")
                await klippy_apis.run_gcode(script)
            except Exception as exc:
                logger.info("Dormant console notice skipped: %s", exc)
        try:
            asyncio.get_event_loop().create_task(_notify())
        except RuntimeError:
            pass

    # ── v0.4.4: Avahi mDNS advertisement ──────────────────────────────────────
    # See docs/v0.5-lan-discovery-design.md §6. The plugin owns the lifecycle
    # of /etc/avahi/services/moongate.service: it writes it on successful
    # owner bind (in _authenticate), removes it on _wipe_owner, and re-writes
    # it defensively at startup if owner.json exists but the service file
    # has gone missing (e.g. manual deletion, upgrade from pre-v0.4.4).
    # All file operations to /etc/avahi/services/ go through sudo with a
    # tightly-scoped sudoers entry installed by install.sh.

    def _write_avahi_service(self) -> None:
        """Install the Avahi service file. Idempotent. Best-effort -
        failures are logged but never interrupt pairing or polling."""
        if self.owner is None:
            return
        try:
            content = AVAHI_SERVICE_TEMPLATE.format(
                printer_id=self.owner.printer_id,
                http_port=self.http_port,
            )
            self._avahi_tmp_file.write_text(content)
            # `sudo -n` fails fast if the sudoers entry isn't in place
            # (e.g. plugin updated from pre-v0.4.4 without re-running
            # install.sh). 5 s timeout because we never want to block
            # pairing on this.
            result = subprocess.run(
                ["sudo", "-n", "/bin/cp",
                 str(self._avahi_tmp_file), str(AVAHI_SERVICE_FILE)],
                check=False, capture_output=True, timeout=5,
            )
            if result.returncode == 0:
                logger.info(
                    "Avahi mDNS advertisement installed (printer_id=%s..., port=%s)",
                    self.owner.printer_id[:8], self.http_port,
                )
            else:
                # Most common cause: sudoers entry missing. Tell the user
                # how to fix without scaring them - pairing itself succeeded.
                logger.warning(
                    "Avahi mDNS advertisement skipped (re-run install.sh "
                    "to enable LAN discovery from the v0.5+ app): %s",
                    result.stderr.decode(errors="replace").strip()
                    or f"exit {result.returncode}",
                )
        except (OSError, subprocess.SubprocessError) as exc:
            logger.warning("Failed to write Avahi service file: %s", exc)
        finally:
            try:
                self._avahi_tmp_file.unlink(missing_ok=True)
            except OSError:
                pass

    def _remove_avahi_service(self) -> None:
        """Remove the Avahi service file (best-effort; no-op if absent)."""
        if not AVAHI_SERVICE_FILE.exists():
            return
        try:
            result = subprocess.run(
                ["sudo", "-n", "/bin/rm", "-f", str(AVAHI_SERVICE_FILE)],
                check=False, capture_output=True, timeout=5,
            )
            if result.returncode == 0:
                logger.info("Avahi mDNS advertisement removed")
            else:
                logger.warning(
                    "Failed to remove Avahi service file: %s",
                    result.stderr.decode(errors="replace").strip()
                    or f"exit {result.returncode}",
                )
        except (OSError, subprocess.SubprocessError) as exc:
            logger.warning("Failed to remove Avahi service file: %s", exc)

    # ── Auth ──────────────────────────────────────────────────────────────────

    def _authenticate(self, webrequest: Any) -> TokenClaims:
        """Verify EdDSA token from ?mg_token= query param. Raises 401 on any
        failure. On first valid call when no owner is recorded, locks in the
        caller as the printer's permanent owner."""
        # LAN-only mode: there is no cloud, so no EdDSA tokens exist. The plugin
        # trusts the LAN exactly as Moonraker does - a request only reaches this
        # endpoint after clearing Moonraker's own trusted_clients gate. No token,
        # no owner binding. (_handle_status/_handle_control ignore the return, and
        # _handle_reset_owner is already token-free by the same reasoning.)
        if self.lan_only:
            return _LAN_ONLY_CLAIMS

        if self.verifier is None:
            # Cloud mode configured but PyJWT/cryptography are missing: no
            # token can ever verify, so say why instead of a bare 401.
            raise self.server.error(
                f"Moongate cloud mode unavailable: {self._plugin_error}", 503)

        args  = webrequest.get_args()
        token = args.get("mg_token", "")
        if not token:
            raise self.server.error("Authorization token required", 401)

        # The stored owner's printer_id normally pins this Pi: a validly-signed
        # token for any OTHER printer_id is refused, so a token minted for a
        # different printer can never re-bind us. The one legitimate way a NEW
        # printer_id appears for this same Pi is a deliberate re-pair that
        # re-enrolled us under a fresh cloud row (the old row was released /
        # recreated, so the cloud id changed). That only happens while a pairing
        # session the user just started on the LAN/console is live - during that
        # window we drop the pin so the new id can first-bind below. Outside
        # pairing the pin stands and an id mismatch is a hard 401.
        pairing = (self._pending is not None
                   and time.time() <= self._pending.expires_at)
        if pairing:
            expected_pid = None
        else:
            expected_pid = self.owner.printer_id if self.owner else None
        claims = self.verifier.verify(str(token), expected_pid)
        if claims is None:
            raise self.server.error("Invalid or expired token", 401)

        # Bind the owner on first contact, AND re-bind if a validly-signed token
        # presents a new owner ("sub") - a cloud ownership transfer such as a
        # backup restore on a fresh install - or a new printer_id from the
        # re-pair described above. The cloud only ever mints a valid, printer-
        # scoped token to the current owner, so the Pi follows the cloud rather
        # than refusing.
        if (self.owner is None
                or self.owner.owner_user_id != claims.sub
                or self.owner.printer_id != claims.printer_id):
            first_bind = self.owner is None
            self.owner = OwnerState(
                printer_id=claims.printer_id,
                owner_user_id=claims.sub,
                paired_at=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            )
            try:
                self.owner.save(self._owner_file)
                logger.info("Owner %s: user=%s..., printer=%s...",
                            "bound" if first_bind else "re-bound",
                            claims.sub[:8], claims.printer_id[:8])
            except OSError as exc:
                logger.error("Failed to persist owner.json: %s", exc)
            # A pairing session (if one was active) has served its purpose now
            # that a valid token has bound - close it so the printer_id pin is
            # back in force on the very next poll.
            self._pending = None
            # The Pi is discoverable on the LAN only once it has a valid owner
            # (unpaired Pis are intentionally invisible on mDNS - see
            # docs/v0.5-lan-discovery-design.md §6.4). Idempotent on re-bind.
            self._write_avahi_service()
            # Poke a heartbeat so the cloud's last_seen / tunnel URL refresh
            # immediately: on first bind the app reached us over LAN before the
            # cloud knows our tunnel; on a transfer the new owner wants the
            # tunnel reported promptly too - instead of a "Starting up…" wait.
            self.heartbeat.request_immediate_send()
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
            if self.lan_only:
                msg = "Could not determine the Pi's LAN IP"
            elif self._plugin_error:
                msg = f"Moongate cloud mode unavailable: {self._plugin_error}"
            else:
                msg = "Supabase /enroll-prepare unreachable"
            raise self.server.error(msg, 502)
        return {
            "code":               pending.raw_token,
            "qr_payload":         pending.qr_payload,
            "local_url":          f"http://{_get_local_ip()}:{self.http_port}",
            "tunnel_url":         None if self.lan_only else _get_tunnel_url(),
            "lan_only":           self.lan_only,
            "expires_in_seconds": max(0, int(pending.expires_at - time.time())),
        }

    async def _handle_qr(self, webrequest: Any) -> dict:
        # LAN-only: the QR is static (LAN address), so serve it directly - no
        # pairing session required, the page shows it the moment it loads.
        if self.lan_only:
            qr = self._lan_qr_payload()
            if qr is None:
                raise self.server.error("Could not determine the Pi's LAN IP", 500)
            return {"qr_url": qr, "tunnel_url": None, "lan_only": True}
        if self._pending is None or time.time() > self._pending.expires_at:
            raise self.server.error("No active pairing session. Run MOONGATE_PAIR first.", 404)
        return {
            "qr_url":     self._pending.qr_payload,
            "tunnel_url": _get_tunnel_url(),
        }

    async def _handle_pair_page(self, webrequest: Any) -> dict:
        if self.lan_only:
            return {
                "qr_url":     self._lan_qr_payload(),
                "tunnel_url": None,
                "subdomain":  None,
                "local_ip":   _get_local_ip(),
                "ready":      True,
                "lan_only":   True,
            }
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
            # Only mark done on success: a poll during Moonraker's own boot
            # (Klippy routes not registered yet) must not burn the one-shot
            # scan, or a mid-boot poller loses chamber + multi-toolhead
            # detection until the next Moonraker restart.
            self._chamber_key_checked = await self._discover_objects(client)

        query = "print_stats&heater_bed&extruder"
        if self._chamber_key:
            query += "&" + urllib.parse.quote(self._chamber_key, safe="")
        # Multi-toolhead: fold every extra hotend + the active tool + the
        # toolchanger into this one authenticated query, so the app gets the
        # whole multi-toolhead picture straight from /status and never needs its
        # own (transport-fragile) object queries to fill it in.
        for key in self._extra_extruders:
            query += "&" + key
        if self._extra_extruders or self._has_toolchanger:
            query += "&toolhead"
        if self._has_toolchanger:
            query += "&toolchanger"

        req = HTTPRequest(
            f"http://127.0.0.1:{self._moonraker_port}/printer/objects/query?{query}",
            method="GET", request_timeout=5.0,
        )
        try:
            resp = await client.fetch(req, raise_error=False)
        except Exception as exc:
            raise self.server.error(f"Failed to reach Moonraker: {exc}", 500)
        if resp.code != 200:
            raise self.server.error(f"Moonraker query returned HTTP {resp.code}", 502)

        try:
            data = json.loads(resp.body)
        except (ValueError, TypeError):
            # Startup race, seen on COSMOS 2026-07-18: a file-serving
            # Moonraker can answer 200 with the web UI's HTML for a moment
            # before the Klippy API routes register. Retryable, so a clean
            # 503 instead of an uncaught-exception 500 in the log.
            raise self.server.error("Moonraker is still starting up", 503)
        result = data.get("result", data)
        result["tunnel_url"] = _get_tunnel_url()
        # Surface the Pi's LAN address so the app can prefer a direct LAN
        # call (with the same EdDSA token) when it's on the same network,
        # skipping the Cloudflare round-trip. Doesn't add port - app pairs
        # it with the configured http_port from its own knowledge.
        result["local_ip"]   = _get_local_ip()
        result["http_port"]  = self.http_port
        result["plugin_version"] = MOONGATE_PLUGIN_VERSION
        # v0.6.16: advertises the remote self-update action, so the app's
        # update dialog knows to offer one-tap "Update now" instead of the
        # Mainsail instructions it shows for older plugins.
        result["plugin_can_self_update"] = True

        webcam = await self._get_webcam_info(client)
        result["webcam_snapshot_path"]   = webcam["snapshot_path"]
        result["webcam_flip_horizontal"] = webcam["flip_horizontal"]
        result["webcam_flip_vertical"]   = webcam["flip_vertical"]
        result["webcam_rotation"]        = webcam["rotation"]
        result["webcam_target_fps"]      = webcam["target_fps"]
        # Absolute URL of a camera that lives on another device on the LAN
        # (e.g. an old phone used as a webcam), read from Mainsail's webcam
        # config; None for the normal Pi-served camera. The app auto-uses it
        # - directly on LAN, or through the /mg-extcam proxy when remote.
        result["webcam_stream_external"]   = webcam["stream_external"]
        result["webcam_snapshot_external"] = webcam["snapshot_external"]
        return result

    async def _handle_control(self, webrequest: Any) -> dict:
        self._authenticate(webrequest)
        from tornado.httpclient import AsyncHTTPClient, HTTPRequest

        args   = webrequest.get_args()
        action = str(args.get("action", "")).strip()
        # v0.6.16: one-tap plugin self-update (the app's dashboard badge).
        # Not part of the pass-through map below because it talks to the
        # update manager and must not wait for completion - Moonraker
        # restarts at the end of the update, which would kill a waited-on
        # response anyway.
        if action == "update_plugin":
            return await self._handle_update_plugin()
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
            f"http://127.0.0.1:{self._moonraker_port}{action_map[action]}",
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

    async def _handle_update_plugin(self) -> dict:
        """One-tap plugin self-update (v0.6.16, driven by the app's dashboard
        update badge; caller already authenticated by _handle_control).

        Refuses while a print is running or paused: the update ends in a
        Moonraker restart, and although Klipper keeps printing through one,
        there is no reason to gamble mid-print.

        Fires Moonraker's own update manager - POST
        /machine/update/client?name=moongate, the same route used to update
        the RatRig remotely on 2026-07-10 (the plain /machine/update/update
        404s on Moonraker v0.10) - and returns immediately: waiting would be
        pointless because the restart kills the connection anyway. The app
        watches plugin_version on its normal /status polls to see the update
        land, which is also what clears its badge."""
        from tornado.httpclient import AsyncHTTPClient, HTTPRequest

        state = None
        try:
            client = AsyncHTTPClient()
            resp = await client.fetch(HTTPRequest(
                f"http://127.0.0.1:{self._moonraker_port}/printer/objects/query?print_stats",
                method="GET", request_timeout=3.0,
            ), raise_error=False)
            if resp.code == 200:
                ps = json.loads(resp.body).get("result", {}).get("status", {})
                state = (ps.get("print_stats") or {}).get("state")
        except Exception as exc:
            # Klipper down or slow is fine - an update can't hurt an idle
            # stack, so only a POSITIVE "printing" answer blocks.
            logger.debug("update_plugin print-state check skipped: %s", exc)
        if state in ("printing", "paused"):
            raise self.server.error(
                "Printer is mid-print - update after it finishes", 409)

        async def _fire() -> None:
            try:
                resp = await AsyncHTTPClient().fetch(HTTPRequest(
                    f"http://127.0.0.1:{self._moonraker_port}/machine/update/client?name=moongate",
                    method="POST", body=b"", request_timeout=300.0,
                ), raise_error=False)
                logger.info("Plugin self-update finished: HTTP %s", resp.code)
            except Exception as exc:
                # Expected when the update restarts Moonraker mid-request.
                logger.info("Plugin self-update request ended: %s", exc)

        asyncio.get_event_loop().create_task(_fire())
        logger.info("Plugin self-update started from the app")
        return {"update": "started", "ok": True}

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

    async def _get_webcam_info(self, client: Any) -> dict:
        # Not a staticmethod since v0.6.17: the fetch below needs the
        # instance's resolved Moonraker port.
        from tornado.httpclient import HTTPRequest
        _default_path = "/webcam/?action=snapshot"
        _default_fps  = 15
        _defaults = {
            "snapshot_path":     _default_path,
            "flip_horizontal":   False,
            "flip_vertical":     False,
            "rotation":          0,
            "target_fps":        _default_fps,
            "stream_external":   None,
            "snapshot_external": None,
        }

        def _ext(raw: Any) -> Optional[str]:
            # An absolute http(s) URL whose host is some OTHER device on the
            # network (not localhost / 127.x) - i.e. a camera Moonraker can't
            # snapshot for us, e.g. an old phone running an IP-webcam app and
            # configured in Mainsail as a stream_url like
            # http://192.168.0.107:8080/video. Returns the URL, else None. The
            # app uses it directly on LAN, or via the /mg-extcam proxy remote.
            s = (raw or "").strip()
            m = re.match(r"^https?://([^/:]+)", s, re.IGNORECASE)
            if not m:
                return None
            host = m.group(1).lower()
            if host == "localhost" or host.startswith("127."):
                return None
            return s

        try:
            req = HTTPRequest(
                f"http://127.0.0.1:{self._moonraker_port}/server/webcams/list",
                method="GET", request_timeout=2.0,
            )
            resp = await client.fetch(req, raise_error=False)
            if resp.code != 200:
                return _defaults
            data    = json.loads(resp.body)
            webcams = data.get("result", {}).get("webcams", [])
            if not webcams:
                return _defaults
            cam = webcams[0]

            stream_external   = _ext(cam.get("stream_url"))
            snapshot_external = _ext(cam.get("snapshot_url"))

            # Relative Pi-served snapshot path for the normal (Crowsnest /
            # uv4l) case. An absolute EXTERNAL snapshot_url must NOT leak into
            # snapshot_path - the app would build tunnel_base + absolute_url
            # and get garbage - so fall back to the default and surface the
            # external URL separately via snapshot_external instead.
            snap_raw = (cam.get("snapshot_url") or "").strip()
            if snapshot_external:
                snap = _default_path
            elif snap_raw:
                snap = re.sub(
                    r"^https?://(localhost|127\.0\.0\.1)(:\d+)?", "", snap_raw)
            else:
                snap = _default_path

            raw_fps = cam.get("target_fps", _default_fps)
            try:
                tgt_fps = int(raw_fps)
                if tgt_fps < 1 or tgt_fps > 60:
                    tgt_fps = _default_fps
            except (TypeError, ValueError):
                tgt_fps = _default_fps
            return {
                "snapshot_path":     snap or _default_path,
                "flip_horizontal":   bool(cam.get("flip_horizontal", False)),
                "flip_vertical":     bool(cam.get("flip_vertical",   False)),
                "rotation":          int(cam.get("rotation", 0)),
                "target_fps":        tgt_fps,
                "stream_external":   stream_external,
                "snapshot_external": snapshot_external,
            }
        except Exception:
            return _defaults

    async def _discover_objects(self, client: Any) -> bool:
        """One-shot scan of Moonraker's object list for the chamber sensor,
        any extra hotends (extruder1, extruder2, ... on an IDEX / tool
        changer) and whether this is a klipper-toolchanger. The results are
        folded into the /status query so a multi-toolhead printer's extra
        hotends + active tool ride the single authenticated /status call,
        instead of the app having to make its own (transport-fragile) queries.

        Returns True when the scan actually ran (the caller then stops
        re-trying); False when Moonraker/Klippy wasn't ready to answer."""
        from tornado.httpclient import HTTPRequest
        try:
            req = HTTPRequest(
                f"http://127.0.0.1:{self._moonraker_port}/printer/objects/list",
                method="GET", request_timeout=2.0,
            )
            resp = await client.fetch(req, raise_error=False)
            if resp.code != 200:
                return False
            objects = json.loads(resp.body).get("result", {}).get("objects", [])
            for obj in objects:
                if ("temperature_sensor" in obj or "heater_generic" in obj
                        or "temperature_fan" in obj) \
                        and "chamber" in obj.lower():
                    self._chamber_key = obj
                    logger.info("Moongate: chamber sensor detected: '%s'", obj)
                    break
            # Extra hotends: Klipper names them extruder1, extruder2, ... (the
            # bare `extruder` is T0 and is always queried; an `extruder_stepper
            # <name>` helper carries a space, so the isdigit() check skips it).
            extra = [o for o in objects
                     if o.startswith("extruder") and o[8:].isdigit()]
            extra.sort(key=lambda o: int(o[8:]))
            self._extra_extruders = extra
            self._has_toolchanger = "toolchanger" in objects
            if extra or self._has_toolchanger:
                logger.info(
                    "Moongate: multi-toolhead detected (extras=%s toolchanger=%s)",
                    extra, self._has_toolchanger)
            return True
        except Exception:
            return False
