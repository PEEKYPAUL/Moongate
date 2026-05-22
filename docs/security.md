# Moongate — Security Model

## Threat model

| Threat | Mitigation |
|---|---|
| Attacker connects to printer from the internet | All API requests require a valid JWT (`mg_token`); unauthenticated requests return 401 |
| Stolen phone with Moongate installed | JWT expiry (default 30 days); tokens are revocable server-side by deleting `~/.config/moongate/tokens.json` on the Pi |
| Replay attack with captured pairing code | Codes are single-use and expire after 10 minutes |
| MITM on local network | Local traffic is HTTP (same as Mainsail normally is); tunnel traffic uses HTTPS via Cloudflare |
| Brute-force the pairing code | 8-char random alphanumeric code (~47 bits entropy); codes expire after 10 min |
| Stolen JWT | Tokens are stored in shared preferences on the phone; revocable server-side |
| Cloudflare tunnel URL leaked | URL alone is not enough — every request also requires the JWT; without a valid token the plugin returns 401 |

## Token design

- Tokens are signed JWTs (HS256) with the secret key stored only on the Pi at `~/.config/moongate/`
- Payload: `{sub: device_id, iat, exp, jti}` — `jti` allows per-token revocation
- The plugin validates signature, `exp`, and `jti` on every request
- Token is sent as a query parameter (`?mg_token=...`) — Moonraker's `WebRequest` API does not expose request headers

## Pairing code design

- Format: `GATE-XXXX-XXXX` (8 random uppercase alphanumeric characters, ~47 bits of entropy)
- TTL: 10 minutes from generation
- Single use: invalidated immediately after a successful exchange
- Codes are stored in memory only; a Pi restart clears all pending codes

## Cloudflare Quick Tunnel

- `cloudflared` opens an outbound tunnel to Cloudflare's edge — no inbound ports are opened on your router
- The tunnel URL (`https://xxxx.trycloudflare.com`) changes on each `cloudflared` restart; the app auto-updates the stored URL on the next status poll
- All traffic through the tunnel is TLS-encrypted between the phone and Cloudflare, and between Cloudflare and the Pi
- The `mg_token` JWT is still required on every request through the tunnel — the tunnel URL alone grants nothing

## What Moongate does NOT do

- No cloud relay or storage of printer data
- No analytics or telemetry
- No account required
- No inbound ports opened on your router
