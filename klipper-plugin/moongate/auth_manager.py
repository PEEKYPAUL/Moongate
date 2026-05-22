"""
Token and pairing-code management for the Moongate plugin.

Tokens are JWTs signed with a secret stored in ~/.config/moongate/secret.key.
Pairing codes are short-lived, single-use alphanumeric strings.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
import random
import string
import time
import uuid
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional

logger = logging.getLogger("moonraker.moongate.auth")

CONFIG_DIR = Path.home() / ".config" / "moongate"
TOKENS_FILE = CONFIG_DIR / "tokens.json"
SECRET_FILE = CONFIG_DIR / "secret.key"
CONFIG_FILE = CONFIG_DIR / "config.json"

DEFAULT_CONFIG = {
    "default_ttl_days": 30,
    "allow_app_override": True,
    "pair_code_ttl_seconds": 600,
    "max_pair_attempts": 5,
}

CODE_CHARS = string.ascii_uppercase + string.digits


@dataclass
class DeviceToken:
    token_id: str
    device_name: str
    issued_at: float
    expires_at: Optional[float]  # None = never expires
    last_seen: float
    revoked: bool = False

    def is_valid(self) -> bool:
        if self.revoked:
            return False
        if self.expires_at is not None and time.time() > self.expires_at:
            return False
        return True


@dataclass
class PairingCode:
    code: str
    created_at: float
    expires_at: float
    attempts: int = 0
    used: bool = False

    def is_valid(self) -> bool:
        return not self.used and self.attempts < 5 and time.time() < self.expires_at


class AuthManager:
    def __init__(self) -> None:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        self._config = self._load_config()
        self._secret = self._load_or_create_secret()
        self._tokens: dict[str, DeviceToken] = {}
        self._pending_codes: dict[str, PairingCode] = {}
        self._load_tokens()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def generate_pair_code(self) -> tuple[str, str]:
        """Return (display_code, qr_payload). Code format: GATE-XXXX-XXXX."""
        self._sweep_expired_codes()
        part1 = "".join(random.choices(CODE_CHARS, k=4))
        part2 = "".join(random.choices(CODE_CHARS, k=4))
        display = f"GATE-{part1}-{part2}"
        raw = f"{part1}{part2}"

        ttl = self._config["pair_code_ttl_seconds"]
        now = time.time()
        self._pending_codes[raw] = PairingCode(
            code=raw,
            created_at=now,
            expires_at=now + ttl,
        )
        qr_payload = f"moongate://pair?code={display}"
        logger.info("Pairing code generated (expires in %ds)", ttl)
        return display, qr_payload

    def exchange_code(
        self,
        raw_code: str,
        device_name: str,
        requested_ttl_days: Optional[int] = None,
    ) -> Optional[str]:
        """
        Validate a pairing code and issue a JWT token string.
        Returns None if the code is invalid/expired.
        """
        normalized = raw_code.upper().replace("-", "").replace("GATE", "")
        entry = self._pending_codes.get(normalized)

        if entry is None or not entry.is_valid():
            if entry:
                entry.attempts += 1
                self._save_tokens()
            logger.warning("Invalid or expired pairing code attempt")
            return None

        entry.used = True
        token_id = str(uuid.uuid4())

        ttl_days = self._config["default_ttl_days"]
        if requested_ttl_days is not None and self._config["allow_app_override"]:
            ttl_days = requested_ttl_days

        now = time.time()
        expires_at = (now + ttl_days * 86400) if ttl_days is not None else None

        token = DeviceToken(
            token_id=token_id,
            device_name=device_name,
            issued_at=now,
            expires_at=expires_at,
            last_seen=now,
        )
        self._tokens[token_id] = token
        self._save_tokens()

        jwt = self._sign_token(token_id, expires_at)
        logger.info("Token issued for device '%s' (id=%s)", device_name, token_id)
        return jwt

    def validate_token(self, jwt: str) -> Optional[str]:
        """Validate a JWT. Returns token_id on success, None on failure."""
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
        return [
            {**asdict(t), "valid": t.is_valid()}
            for t in self._tokens.values()
        ]

    # ------------------------------------------------------------------
    # JWT (minimal HS256 without external deps)
    # ------------------------------------------------------------------

    def _sign_token(self, token_id: str, expires_at: Optional[float]) -> str:
        header = _b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
        payload = _b64(json.dumps({
            "sub": token_id,
            "iat": int(time.time()),
            **({"exp": int(expires_at)} if expires_at else {}),
        }).encode())
        sig = _b64(
            hmac.new(self._secret, f"{header}.{payload}".encode(), hashlib.sha256).digest()
        )
        return f"{header}.{payload}.{sig}"

    def _verify_token(self, jwt: str) -> Optional[str]:
        import base64
        try:
            header, payload, sig = jwt.split(".")
            expected = _b64(
                hmac.new(self._secret, f"{header}.{payload}".encode(), hashlib.sha256).digest()
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

    # ------------------------------------------------------------------
    # Persistence
    # ------------------------------------------------------------------

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
        logger.info("New Moongate secret key generated at %s", SECRET_FILE)
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
                json.dump({"tokens": [asdict(t) for t in self._tokens.values()]}, f, indent=2)
        except Exception as e:
            logger.error("Failed to save tokens: %s", e)

    def _sweep_expired_codes(self) -> None:
        now = time.time()
        self._pending_codes = {
            k: v for k, v in self._pending_codes.items()
            if now < v.expires_at
        }


def _b64(data: bytes) -> str:
    import base64
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()
