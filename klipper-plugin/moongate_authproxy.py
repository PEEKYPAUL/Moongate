"""
Moongate v0.4 — auth proxy.

Sits in front of Moonraker (127.0.0.1:7125) and Mainsail/Fluidd nginx
(127.0.0.1:80). After v0.4 install, `cloudflared` targets this proxy
instead of Moonraker directly.

Every HTTP request and WebSocket upgrade reaching this proxy must carry a
valid EdDSA access token (issued by the Moongate Supabase backend for the
printer's verified owner). Without a token — or with a bad/expired one,
or with a token for a different owner — the response is always a constant
401 with no body content that could leak printer state, Moonraker version,
or Mainsail presence.

Verification logic is imported directly from `moongate_standalone.py` so the
proxy and the in-Moonraker plugin verify tokens identically. If the security
model ever changes (claim names, key handling, JWKS source), both update
together.

Environment variables (all optional):

    MG_LISTEN_HOST       default 127.0.0.1 (cloudflared is on the same host)
    MG_LISTEN_PORT       default 8443
    MG_MOONRAKER         default http://127.0.0.1:7125
    MG_MAINSAIL          default http://127.0.0.1:80
    MG_PLUGIN_DIR        default /home/pi/moongate/klipper-plugin
                         (where moongate_standalone.py lives — added to sys.path)
    MG_JWKS_TTL_SECONDS  default 3600
    MG_LOG_LEVEL         default INFO

Run standalone:
    python3 moongate_authproxy.py

Or as a systemd service — see moongate-authproxy.service.
"""

from __future__ import annotations

import asyncio
import logging
import os
import sys
from pathlib import Path
from typing import Optional, Tuple

from aiohttp import ClientSession, ClientTimeout, WSMsgType, web

# ─── Make moongate_standalone importable ────────────────────────────────────

PLUGIN_DIR = Path(os.environ.get(
    "MG_PLUGIN_DIR", "/home/pi/moongate/klipper-plugin"))
if str(PLUGIN_DIR) not in sys.path:
    sys.path.insert(0, str(PLUGIN_DIR))

from moongate_standalone import (  # noqa: E402  (import after path manipulation)
    DEFAULT_SUPABASE_ANON_KEY,
    DEFAULT_SUPABASE_URL,
    JWKS_CACHE,
    OWNER_FILE,
    AccessTokenVerifier,
    JwksCache,
    OwnerState,
)

# ─── Config ─────────────────────────────────────────────────────────────────

LISTEN_HOST   = os.environ.get("MG_LISTEN_HOST", "127.0.0.1")
LISTEN_PORT   = int(os.environ.get("MG_LISTEN_PORT", "8443"))
MOONRAKER_URL = os.environ.get("MG_MOONRAKER", "http://127.0.0.1:7125").rstrip("/")
MAINSAIL_URL  = os.environ.get("MG_MAINSAIL",  "http://127.0.0.1:80").rstrip("/")
JWKS_TTL      = int(os.environ.get("MG_JWKS_TTL_SECONDS", "3600"))
LOG_LEVEL     = os.environ.get("MG_LOG_LEVEL", "INFO").upper()

# Path prefixes routed to Moonraker. Everything else → Mainsail nginx
# (which serves Mainsail/Fluidd static assets and the pairing page).
MOONRAKER_PATH_PREFIXES: Tuple[str, ...] = (
    "/printer",
    "/server",
    "/access",
    "/machine",
    "/api",
    "/websocket",
)

# RFC 7230 hop-by-hop headers — never forwarded.
HOP_BY_HOP_HEADERS = frozenset({
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade",
})

# Constant 401 body. No version, no path echo, no detail. The only signal
# is "this URL exists and refuses you" — same for every reason it refuses.
UNAUTHORIZED_BODY = "unauthorized\n"

logger = logging.getLogger("moongate.authproxy")


# ─── OwnerWatcher ───────────────────────────────────────────────────────────
# Re-reads owner.json when its mtime changes so the proxy picks up the
# post-pairing owner binding written by moongate_standalone without a
# restart.

class OwnerWatcher:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._owner: Optional[OwnerState] = None
        self._mtime: float = 0.0
        self._poll()

    def _poll(self) -> Optional[OwnerState]:
        try:
            mtime = self.path.stat().st_mtime
        except FileNotFoundError:
            if self._owner is not None:
                logger.info("owner.json deleted — proxy now in unpaired mode")
                self._owner = None
                self._mtime = 0.0
            return None

        if mtime != self._mtime:
            new_owner = OwnerState.load(self.path)
            self._owner = new_owner
            self._mtime = mtime
            if new_owner:
                logger.info(
                    "owner loaded: user=%s..., printer=%s...",
                    new_owner.owner_user_id[:8], new_owner.printer_id[:8],
                )
            else:
                logger.warning("owner.json present but unparseable")
        return self._owner

    @property
    def current(self) -> Optional[OwnerState]:
        return self._poll()


# ─── Authentication ─────────────────────────────────────────────────────────

def _extract_token(request: web.Request) -> Optional[str]:
    """Pull EdDSA token from (in priority order):
      1. Authorization: Bearer <token>
      2. mg_token cookie
      3. ?mg_token=<token> query param
    """
    auth = request.headers.get("Authorization", "")
    if auth[:7].lower() == "bearer " and len(auth) > 7:
        return auth[7:].strip()

    cookie = request.cookies.get("mg_token")
    if cookie:
        return cookie.strip()

    qp = request.query.get("mg_token")
    if qp:
        return qp.strip()

    return None


def _unauthorized() -> web.Response:
    return web.Response(
        status=401,
        text=UNAUTHORIZED_BODY,
        headers={"Cache-Control": "no-store"},
    )


async def _authorize(request: web.Request) -> Optional[web.Response]:
    """Returns None if the request is authorized to proceed, otherwise
    returns a 401 Response to send back."""
    token = _extract_token(request)
    if not token:
        logger.debug("401: no token (%s %s)", request.method, request.path)
        return _unauthorized()

    owner: Optional[OwnerState] = request.app["owner"].current
    expected_pid = owner.printer_id    if owner else None
    expected_own = owner.owner_user_id if owner else None

    verifier: AccessTokenVerifier = request.app["verifier"]

    # AccessTokenVerifier.verify is sync and may perform a JWKS refetch
    # (network I/O) on cache miss. Run in the default thread pool so the
    # aiohttp event loop is never blocked.
    claims = await asyncio.to_thread(
        verifier.verify, token, expected_pid, expected_own,
    )
    if claims is None:
        logger.debug("401: bad token (%s %s)", request.method, request.path)
        return _unauthorized()

    # Hand the verified claims downstream in case any future handler needs
    # them. The current handler doesn't.
    request["mg_claims"] = claims
    return None


# ─── Routing + header sanitisation ──────────────────────────────────────────

def _backend_for(path: str) -> str:
    for prefix in MOONRAKER_PATH_PREFIXES:
        if path == prefix or path.startswith(prefix + "/"):
            return MOONRAKER_URL
    return MAINSAIL_URL


def _forward_request_headers(request: web.Request) -> dict[str, str]:
    """Copy request headers for the upstream call, stripping hop-by-hop
    headers, the inbound Host, our own Authorization header, the mg_token
    cookie, and any X-Forwarded-For from cloudflared.

    We intentionally do NOT forward X-Forwarded-For. Moonraker uses it to
    determine the source IP for its trusted_clients check; passing the
    real internet client IP causes Moonraker to reject the request (it's
    not in 10.0.0.0/8, 127.0.0.0/8, etc.). Dropping the header lets
    Moonraker see the request as coming from the auth proxy on 127.0.0.1,
    which is in the default trusted_clients range — so Moonraker trusts
    us. The actual access decision is made at our proxy *before* the
    request ever reaches Moonraker (EdDSA gate); Moonraker's own auth is
    a no-op when fronted by us.

    Bonus: real client IPs never end up in Moonraker / Mainsail logs."""
    out: dict[str, str] = {}
    for name, value in request.headers.items():
        lower = name.lower()
        if lower in HOP_BY_HOP_HEADERS:
            continue
        if lower in ("host", "authorization", "x-forwarded-for"):
            continue
        if lower == "cookie":
            kept = "; ".join(
                kv for kv in value.split(";")
                if not kv.strip().startswith("mg_token=")
            )
            if kept:
                out["Cookie"] = kept
            continue
        out[name] = value

    out["X-Forwarded-Proto"] = "https"
    return out


def _forward_response_headers(headers) -> dict[str, str]:
    # Preserve Content-Length when upstream sends one. Stripping it forces
    # aiohttp into Transfer-Encoding: chunked, which adds per-chunk
    # framing overhead and prevents the client from pre-allocating /
    # showing progress. For Mainsail's ~2MB JS bundle over Cloudflare +
    # cellular, the extra round-trips were enough to trip a WebView
    # cancel mid-stream (observed as "Cannot write to closing transport"
    # on the proxy side, ERR_INCOMPLETE_CHUNKED_ENCODING on the client).
    return {
        k: v for k, v in headers.items()
        if k.lower() not in HOP_BY_HOP_HEADERS
    }


# ─── HTTP proxy ─────────────────────────────────────────────────────────────

async def _proxy_http(
    request: web.Request, backend_base: str,
) -> web.StreamResponse:
    client: ClientSession = request.app["client"]
    target_url = backend_base + request.rel_url.path_qs
    headers = _forward_request_headers(request)

    # Streaming request body. aiohttp can take a StreamReader directly.
    body = request.content if request.body_exists else None

    try:
        async with client.request(
            request.method, target_url,
            headers=headers,
            data=body,
            allow_redirects=False,
        ) as upstream:
            response = web.StreamResponse(
                status=upstream.status,
                reason=upstream.reason,
                headers=_forward_response_headers(upstream.headers),
            )
            await response.prepare(request)
            # 256 KiB chunks: large enough that a ~2 MB Mainsail bundle is
            # ~8 await round-trips instead of ~32, small enough that
            # backpressure on cellular doesn't pile up. The actual TCP
            # write size on the wire is independent.
            async for chunk in upstream.content.iter_chunked(256 * 1024):
                await response.write(chunk)
            await response.write_eof()
            return response
    except asyncio.CancelledError:
        raise
    except (ConnectionResetError, ConnectionAbortedError) as exc:
        # Client (cloudflared / WebView) closed the connection mid-stream.
        # 499 is the de-facto "client closed request" code (nginx-ism);
        # aiohttp may not even get to send it because the client is gone,
        # but the empty Response is a valid return value either way.
        # Debug-only log because this is normal behaviour (back-button
        # mid-load, cellular handoff, WebView cancel for any reason).
        logger.debug("client disconnect during %s %s: %s",
                     request.method, target_url, exc)
        return web.Response(status=499, text="")
    except Exception as exc:
        logger.warning("upstream %s %s failed: %s",
                       request.method, target_url, exc)
        return web.Response(status=502, text="bad gateway\n")


# ─── WebSocket proxy ────────────────────────────────────────────────────────

async def _proxy_websocket(
    request: web.Request, backend_base: str,
) -> web.WebSocketResponse:
    # Auth is enforced on the upgrade request (already done by _authorize
    # before this is called). Subsequent frames inherit that trust until
    # close; standard pattern for token-auth'd WebSockets.
    client_ws = web.WebSocketResponse(autoping=True, heartbeat=30.0)
    await client_ws.prepare(request)

    target_url = backend_base + request.rel_url.path_qs
    if target_url.startswith("http://"):
        target_url = "ws://" + target_url[len("http://"):]
    elif target_url.startswith("https://"):
        target_url = "wss://" + target_url[len("https://"):]

    client: ClientSession = request.app["client"]
    try:
        async with client.ws_connect(
            target_url, autoping=True, heartbeat=30.0,
            timeout=ClientTimeout(total=None, connect=10),
        ) as backend_ws:

            async def relay(src, dst, label: str) -> None:
                try:
                    async for msg in src:
                        if msg.type == WSMsgType.TEXT:
                            await dst.send_str(msg.data)
                        elif msg.type == WSMsgType.BINARY:
                            await dst.send_bytes(msg.data)
                        elif msg.type in (WSMsgType.CLOSE,
                                          WSMsgType.CLOSED,
                                          WSMsgType.ERROR):
                            break
                except Exception as exc:
                    logger.debug("ws relay %s ended: %s", label, exc)

            await asyncio.gather(
                relay(client_ws,  backend_ws, "client→backend"),
                relay(backend_ws, client_ws, "backend→client"),
                return_exceptions=True,
            )
    except Exception as exc:
        logger.warning("ws connect to %s failed: %s", target_url, exc)

    if not client_ws.closed:
        await client_ws.close(code=1011, message=b"backend gone")
    return client_ws


# ─── Unified handler ────────────────────────────────────────────────────────

async def handle(request: web.Request) -> web.StreamResponse:
    deny = await _authorize(request)
    if deny is not None:
        return deny

    backend = _backend_for(request.path)

    if request.headers.get("Upgrade", "").lower() == "websocket":
        return await _proxy_websocket(request, backend)

    return await _proxy_http(request, backend)


# ─── Lifecycle ──────────────────────────────────────────────────────────────

async def _on_startup(app: web.Application) -> None:
    # auto_decompress=False is critical for transparent proxying. The
    # default decompresses gzipped upstream responses server-side, but we
    # forward Content-Encoding: gzip unchanged — so the client would try
    # to gunzip already-decompressed bytes and fail. Disabling means the
    # raw compressed bytes are relayed end-to-end, with Content-Encoding
    # and Content-Length intact and matching each other.
    app["client"] = ClientSession(
        timeout=ClientTimeout(total=None, connect=10),
        auto_decompress=False,
    )
    jwks = JwksCache(
        DEFAULT_SUPABASE_URL, DEFAULT_SUPABASE_ANON_KEY,
        JWKS_CACHE, JWKS_TTL,
    )
    await asyncio.to_thread(jwks.fetch_now)
    app["verifier"] = AccessTokenVerifier(jwks)
    app["owner"] = OwnerWatcher(OWNER_FILE)
    logger.info(
        "moongate-authproxy ready on %s:%d → Moonraker=%s, Mainsail=%s",
        LISTEN_HOST, LISTEN_PORT, MOONRAKER_URL, MAINSAIL_URL,
    )


async def _on_cleanup(app: web.Application) -> None:
    client: ClientSession = app["client"]
    await client.close()


def make_app() -> web.Application:
    app = web.Application()
    app.on_startup.append(_on_startup)
    app.on_cleanup.append(_on_cleanup)
    # One catch-all that handles every HTTP method on every path, including
    # WebSocket upgrades.
    app.router.add_route("*", "/{tail:.*}", handle)
    return app


def main() -> None:
    logging.basicConfig(
        level=getattr(logging, LOG_LEVEL, logging.INFO),
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    web.run_app(make_app(), host=LISTEN_HOST, port=LISTEN_PORT)


if __name__ == "__main__":
    main()
