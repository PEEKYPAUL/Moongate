"""
Moongate Moonraker component.

Registers:
  POST /moongate/pair    — generate a pairing code (called by MOONGATE_PAIR macro)
  POST /moongate/auth    — exchange a pairing code for a JWT token
  GET  /moongate/status  — check plugin status (authenticated)
  GET  /moongate/tokens  — list active tokens (authenticated)
  POST /moongate/revoke  — revoke a token (authenticated)
"""

from __future__ import annotations

import logging
from typing import Any

from .auth_manager import AuthManager

logger = logging.getLogger("moonraker.moongate")


def load_component(config: Any) -> "MoongatePlugin":
    return MoongatePlugin(config)


class MoongatePlugin:
    def __init__(self, config: Any) -> None:
        self.server = config.get_server()
        self.auth = AuthManager()

        app: Any = self.server.get_app()
        app.register_route("/moongate/pair", ["POST"], self._handle_pair)
        app.register_route("/moongate/auth", ["POST"], self._handle_auth)
        app.register_route("/moongate/status", ["GET"], self._handle_status)
        app.register_route("/moongate/tokens", ["GET"], self._handle_list_tokens)
        app.register_route("/moongate/revoke", ["POST"], self._handle_revoke)

        logger.info("Moongate plugin loaded")

    # ------------------------------------------------------------------
    # Route handlers
    # ------------------------------------------------------------------

    async def _handle_pair(self, request: Any) -> dict:
        """
        Called by the MOONGATE_PAIR Klipper macro via Moonraker's proc_request.
        Returns the display code and QR payload so the macro can print them
        to the Klipper console.
        """
        display_code, qr_payload = self.auth.generate_pair_code()
        logger.info("Pair code requested: %s", display_code)
        return {
            "code": display_code,
            "qr_payload": qr_payload,
            "expires_in_seconds": 600,
        }

    async def _handle_auth(self, request: Any) -> dict:
        """Exchange a pairing code for a JWT."""
        body = await request.json()
        raw_code: str = body.get("code", "")
        device_name: str = body.get("device_name", "Unknown device")
        ttl_days = body.get("ttl_days")  # optional; None = use server default

        if not raw_code:
            request.set_status(400)
            return {"error": "code is required"}

        token = self.auth.exchange_code(
            raw_code=raw_code,
            device_name=device_name,
            requested_ttl_days=ttl_days,
        )

        if token is None:
            request.set_status(401)
            return {"error": "invalid or expired code"}

        return {"token": token}

    async def _handle_status(self, request: Any) -> dict:
        token_id = self._authenticate(request)
        if token_id is None:
            request.set_status(401)
            return {"error": "unauthorized"}
        return {"status": "ok", "token_id": token_id}

    async def _handle_list_tokens(self, request: Any) -> dict:
        token_id = self._authenticate(request)
        if token_id is None:
            request.set_status(401)
            return {"error": "unauthorized"}
        return {"tokens": self.auth.list_tokens()}

    async def _handle_revoke(self, request: Any) -> dict:
        token_id = self._authenticate(request)
        if token_id is None:
            request.set_status(401)
            return {"error": "unauthorized"}
        body = await request.json()
        target_id = body.get("token_id", token_id)
        success = self.auth.revoke_token(target_id)
        return {"revoked": success}

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _authenticate(self, request: Any) -> str | None:
        auth_header: str = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return None
        jwt = auth_header[7:]
        return self.auth.validate_token(jwt)
