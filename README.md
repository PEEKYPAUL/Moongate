# Moongate

> One app. Your 3D printer. Anywhere.

Moongate is a free, open-source mobile app for Android and iOS that gives you a **secure, remote interface to your Klipper 3D printer** — with no cloud dependency, no extra apps, and no subscription.

It replaces the two-app workflow of **Mobileraker + Tailscale** with a single integrated application.

---

## Features

| Feature | Detail |
|---|---|
| **Integrated VPN** | WireGuard tunnel starts when you open the app and is fully torn down when you close it. No background drain, no persistent notification beyond the OS VPN icon. |
| **Mainsail/Fluidd interface** | Full printer control — temperature, movement, macros, webcam, print status — identical to what you see in a browser. |
| **Secure pairing** | Run a single Klipper macro to generate a time-limited handshake code (alphanumeric + QR). No port forwarding, no static IPs. |
| **Configurable token expiry** | Choose how often you need to re-pair: 1 day, 7 days, 30 days, or never. |
| **No cloud** | All traffic goes directly over your Tailscale/WireGuard mesh. Nothing leaves your network except through the VPN tunnel you control. |

---

## How it works

```
┌─────────────────────┐        WireGuard tunnel        ┌──────────────────────────┐
│   Moongate App      │◄──────────────────────────────►│  Raspberry Pi (Klipper)  │
│  (Android / iOS)    │        (Tailscale mesh)         │  Moonraker + Moongate    │
│                     │                                 │        Plugin            │
│  • VPN lifecycle    │   Moonraker WebSocket/REST      │                          │
│  • Printer UI       │◄──────────────────────────────►│  Port 7125 (local only)  │
│  • Pairing flow     │                                 │                          │
└─────────────────────┘                                 └──────────────────────────┘
```

### Pairing flow

1. In Klipper/KlipperScreen, run the `MOONGATE_PAIR` macro
2. A short code (e.g. `GATE-A3F2-9K1B`) and QR code appear in the console
3. Enter the code in the Moongate app — it exchanges it for a session token
4. The app connects over the WireGuard tunnel automatically

---

## Repository structure

```
moongate/
├── mobile/             # Flutter app (Android + iOS)
├── klipper-plugin/     # Moonraker plugin for the Raspberry Pi
└── docs/               # Architecture, setup guide, security notes
```

---

## Getting started

### 1 — Install the Moonraker plugin on your Raspberry Pi

```bash
cd ~
git clone https://github.com/PEEKYPAUL/moongate.git
cd moongate/klipper-plugin
bash install.sh
```

### 2 — Install the Moongate app

> APK (Android sideload) and TestFlight (iOS) links will appear here once the first build is published.

### 3 — Pair

Run `MOONGATE_PAIR` in your Klipper console. Scan the QR or type the code into the app. Done.

---

## Development setup

See [docs/setup-guide.md](docs/setup-guide.md) for full Flutter SDK install instructions and how to build from source.

---

## Roadmap

- [x] Project scaffold & architecture
- [ ] Moonraker plugin — pairing endpoint & token management
- [ ] Flutter app — VPN lifecycle (Android)
- [ ] Flutter app — VPN lifecycle (iOS)
- [ ] Flutter app — pairing UI
- [ ] Flutter app — Moonraker WebSocket integration
- [ ] Flutter app — printer control UI (Phase 1: WebView)
- [ ] Flutter app — printer control UI (Phase 2: native widgets)
- [ ] GitHub Actions CI
- [ ] First Android APK release

---

## Contributing

PRs welcome. Please open an issue first for anything larger than a bug fix.

## License

MIT
