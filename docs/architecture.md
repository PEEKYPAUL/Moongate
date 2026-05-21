# Moongate — Architecture

## Overview

Moongate has two components that work together:

1. **Moongate Plugin** — a Python Moonraker component that runs on the Raspberry Pi alongside Klipper
2. **Moongate App** — a Flutter mobile app (Android + iOS)

Communication between them happens exclusively over a WireGuard VPN tunnel (Tailscale's mesh network or a self-hosted headscale server).

---

## Component diagram

```
┌──────────────────────────────────────────────────────────────────┐
│  Raspberry Pi                                                    │
│                                                                  │
│  ┌─────────────┐    Unix socket    ┌──────────────────────────┐  │
│  │   Klipper   │◄─────────────────►│      Moonraker           │  │
│  │  (printer   │                   │  (HTTP/WS API, :7125)    │  │
│  │   firmware) │                   │                          │  │
│  └─────────────┘                   │  ┌────────────────────┐  │  │
│                                    │  │  Moongate Plugin   │  │  │
│                                    │  │  (component)       │  │  │
│                                    │  │                    │  │  │
│                                    │  │ /moongate/pair     │  │  │
│                                    │  │ /moongate/auth     │  │  │
│                                    │  │ /moongate/status   │  │  │
│                                    │  └────────────────────┘  │  │
│                                    └──────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Tailscale daemon  (WireGuard mesh, :41641 UDP)          │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
                              │  WireGuard tunnel
                              │  (Tailscale mesh or headscale)
┌─────────────────────────────▼────────────────────────────────────┐
│  Moongate App (Flutter)                                          │
│                                                                  │
│  ┌──────────────┐  ┌───────────────────┐  ┌──────────────────┐  │
│  │  VPN Service │  │  Auth Service     │  │  Printer Service │  │
│  │              │  │                   │  │                  │  │
│  │ WireGuard-Go │  │ Pairing flow      │  │ Moonraker WS/    │  │
│  │ platform     │  │ JWT storage       │  │ REST client      │  │
│  │ channel      │  │ Token expiry      │  │                  │  │
│  └──────────────┘  └───────────────────┘  └──────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  UI Layer                                                  │  │
│  │  Phase 1: WebView → local Mainsail/Fluidd                 │  │
│  │  Phase 2: Native Flutter widgets (Moonraker WS direct)    │  │
│  └───────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Pairing / handshake flow

```
User                Klipper Console         Moongate Plugin        Moongate App
 │                        │                       │                      │
 │  Run MOONGATE_PAIR     │                       │                      │
 ├───────────────────────►│                       │                      │
 │                        │  HTTP POST /pair      │                      │
 │                        ├──────────────────────►│                      │
 │                        │                       │ Generate:            │
 │                        │                       │  - 8-char code       │
 │                        │                       │  - QR payload        │
 │                        │                       │  - TTL (configured)  │
 │                        │  code + QR in console │                      │
 │                        │◄──────────────────────┤                      │
 │  See code on screen    │                       │                      │
 │◄───────────────────────┤                       │                      │
 │                        │                       │                      │
 │  Enter/scan code       │                       │                      │
 ├────────────────────────┼───────────────────────┼─────────────────────►│
 │                        │                       │  POST /moongate/auth │
 │                        │                       │◄─────────────────────┤
 │                        │                       │ Validate code        │
 │                        │                       │ Issue JWT            │
 │                        │                       ├─────────────────────►│
 │                        │                       │  {token, expiry}     │
 │                        │                       │                      │ Store token
 │                        │                       │                      │ Connect VPN
 │                        │                       │  WS connect :7125    │
 │                        │                       │◄─────────────────────┤
```

---

## VPN lifecycle

### Android
- Uses `VpnService` (Android API) with a WireGuard-Go native library
- A foreground service is started when the app opens; the OS shows a silent VPN key icon in the status bar (no sound, no pop-up — Android requirement, cannot be removed)
- `onDestroy` / `onTaskRemoved` tear down the tunnel immediately
- No background wake-locks; the service stops when the app process is killed

### iOS
- Uses `NetworkExtension` framework with `NEPacketTunnelProvider`
- The extension runs in a separate process; it is stopped via `stopTunnel()` when the app enters background (configurable — default is disconnect on background)
- No VPN On Demand rules are set, so there is no auto-reconnect

---

## Token storage

Tokens are stored on the Pi at `~/.config/moongate/tokens.json`:

```json
{
  "tokens": [
    {
      "token_id": "uuid-v4",
      "device_name": "Paul's iPhone",
      "issued_at": "2026-05-21T10:00:00Z",
      "expires_at": "2026-06-21T10:00:00Z",
      "last_seen": "2026-05-21T14:32:00Z"
    }
  ],
  "default_ttl_days": 30
}
```

Expired tokens are rejected at auth middleware; the user sees a "session expired — re-pair to continue" screen in the app.

---

## Security notes

See [security.md](security.md) for threat model and mitigations.
