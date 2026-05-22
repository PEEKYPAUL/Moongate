# Moongate — Architecture

## Overview

Moongate has two components:

1. **Moongate Plugin** — a Python Moonraker component that runs on the Raspberry Pi alongside Klipper
2. **Moongate App** — a Flutter mobile app (Android)

Communication happens over your local WiFi when you're home, and automatically over a Cloudflare Quick Tunnel when you're away — no VPN, no port forwarding, no static IP required.

---

## Component diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  Raspberry Pi                                                   │
│                                                                 │
│  ┌─────────────┐    Unix socket    ┌─────────────────────────┐  │
│  │   Klipper   │◄─────────────────►│      Moonraker          │  │
│  │  (printer   │                   │  (HTTP API, :7125)      │  │
│  │   firmware) │                   │                         │  │
│  └─────────────┘                   │  ┌───────────────────┐  │  │
│                                    │  │  Moongate Plugin  │  │  │
│                                    │  │                   │  │  │
│                                    │  │ /moongate/status  │  │  │
│                                    │  │ /moongate/control │  │  │
│                                    │  │ /moongate/qr      │  │  │
│                                    │  └───────────────────┘  │  │
│                                    └─────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  cloudflared  (Cloudflare Quick Tunnel, systemd service)  │  │
│  │  Exposes port 80 → https://xxxx.trycloudflare.com        │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
         │ local WiFi (fast)          │ Cloudflare tunnel (remote)
         │ http://192.168.x.x         │ https://xxxx.trycloudflare.com
         ▼                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  Moongate App (Flutter / Android)                               │
│                                                                 │
│  ┌──────────────────────┐  ┌───────────────────────────────┐   │
│  │  PrinterStatusService│  │  PrintControlService          │   │
│  │  Polls /status every │  │  POST /control?action=...     │   │
│  │  4 s — local first,  │  │  local first, tunnel fallback │   │
│  │  tunnel fallback     │  │                               │   │
│  └──────────────────────┘  └───────────────────────────────┘   │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Dashboard — one tile per printer                         │  │
│  │  • webcam snapshot (1 s refresh, gapless)                 │  │
│  │  • progress bar, pause/resume/stop, firmware restart      │  │
│  │  • green bar = local, orange bar = tunnel                 │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Printer screen — full Mainsail/Fluidd WebView            │  │
│  │  Local URL tried first; auto-switches to tunnel after 3 s │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Pairing / handshake flow

```
User            Klipper Console       Moongate Plugin       Moongate App
 │                    │                     │                     │
 │  MOONGATE_PAIR     │                     │                     │
 ├───────────────────►│                     │                     │
 │                    │  remote method call │                     │
 │                    ├────────────────────►│                     │
 │                    │                     │ generate:           │
 │                    │                     │  GATE-XXXX-XXXX     │
 │                    │                     │  QR payload         │
 │                    │                     │  10 min TTL         │
 │                    │  code in console    │                     │
 │                    │◄────────────────────┤                     │
 │  See code + open   │                     │                     │
 │  moongate-pair.html│                     │                     │
 │                    │                     │                     │
 │  Scan QR           │                     │                     │
 ├────────────────────┼─────────────────────┼────────────────────►│
 │                    │                     │  POST /moongate/pair│
 │                    │                     │◄────────────────────┤
 │                    │                     │ validate code       │
 │                    │                     │ issue JWT           │
 │                    │                     ├────────────────────►│
 │                    │                     │  {token, local_ip,  │
 │                    │                     │   tunnel_url}       │
 │                    │                     │                     │ store & connect
```

---

## Network connection strategy

The app tries the **local IP first** on every poll.  If that fails (e.g. you're not on home WiFi) it automatically falls back to the **Cloudflare tunnel URL** stored at pairing time.  The status service detects when the Pi rotates the tunnel URL (each `cloudflared` restart generates a new hostname) and persists the fresh URL immediately.

Each printer tile on the dashboard is fully independent — it probes its own local IP and tunnel separately from every other tile.

When the Moongate plugin is not installed on a printer, the status and control services fall back to the native Moonraker REST API (`/printer/objects/query`, `/printer/print/pause`, etc.) so the tile still shows real status and controls still work.

---

## Token / auth design

- Tokens are signed JWTs (HS256), secret stored only on the Pi
- Payload: `{sub: device_id, iat, exp, jti}`
- The plugin validates signature + expiry + revocation on every request
- Token is passed as a query parameter (`?mg_token=...`) because Moonraker's WebRequest API has no `get_header()`

---

## Security notes

See [security.md](security.md) for the threat model and mitigations.
