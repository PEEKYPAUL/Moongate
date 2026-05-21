# Moongate — Security Model

## Threat model

| Threat | Mitigation |
|---|---|
| Attacker connects to printer over the internet | All traffic requires an active WireGuard tunnel; Moonraker never exposed publicly |
| Stolen phone with Moongate installed | Token expiry (configurable); manual token revocation via Pi config; app can require biometric unlock |
| Replay attack with captured pairing code | Codes are single-use and expire after 10 minutes |
| MITM on local network between app and Moonraker | Traffic travels over WireGuard (encrypted + authenticated at transport layer) |
| Brute-force the pairing code | Rate-limited to 5 attempts per code; lockout after failure |
| Stolen session token | Tokens are stored in encrypted storage on the phone (flutter_secure_storage); revocable server-side |
| Malicious app update | Distribution via GitHub Releases with signed APKs; checksums published |

## Token design

- Tokens are signed JWTs (HS256) with the secret key stored only on the Pi
- Payload: `{sub: device_id, iat, exp, jti (unique ID for revocation)}`
- The plugin validates `exp`, `jti` (not revoked), and signature on every request
- Token rotation: the app requests a new token when < 20% of TTL remains

## Pairing code design

- Format: `GATE-XXXX-XXXX` (8 random uppercase alphanumeric chars, ~47 bits of entropy)
- TTL: 10 minutes from generation
- Single use: code is invalidated immediately after a successful exchange
- Rate limit: 5 failed attempts locks the code; a new `MOONGATE_PAIR` run is required

## WireGuard / Tailscale

- The app uses Tailscale's Wireguard-based mesh — all traffic is end-to-end encrypted
- The coordination server (Tailscale SaaS or self-hosted headscale) only brokers key exchange; it never sees your traffic
- Auth keys have a configurable expiry; ephemeral keys are supported (node removed from tailnet when offline)

## What Moongate does NOT do

- No cloud relay of printer data
- No analytics or telemetry
- No account required beyond a Tailscale/headscale account for VPN mesh
