# Moongate — Setup Guide

## Requirements

### On your Raspberry Pi
- Klipper + Moonraker + Mainsail (or Fluidd) already installed via KIAUH / MainsailOS / FluiddPI
- Internet access (needed to reach the Cloudflare edge for the remote tunnel)
- Architecture: aarch64 (Pi 4/5), armv7l (Pi 3), or x86_64

### On your Android phone
- Android 8.0 (Oreo) or later
- "Install from unknown sources" enabled for the app you'll use to install the APK (browser or file manager)
- The phone needs to be on the same WiFi as the Pi for pairing — both sides of the QR exchange are LAN-only by design

### To build from source (optional)
- Flutter SDK ≥ 3.19 (stable channel)
- Android SDK + JDK 17

---

## Step 1 — Install the plugin on your Pi

SSH into your Pi and run:

```bash
curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/Moongate/master/klipper-plugin/install.sh | bash
```

This installs:
- The Moongate Moonraker plugin (`moongate.py`)
- The `MOONGATE_PAIR` G-code macro (writes `moongate.cfg`, adds `[include moongate.cfg]` at the top of `printer.cfg`)
- The QR pairing page (`moongate-pair.html` → Mainsail web root)
- The auth proxy systemd service (`moongate-authproxy.service`) — gates every tunnel-side request
- `cloudflared` and a `moongate-tunnel` systemd service (auto-starts on boot)
- Restarts Moonraker and Klipper

At the end you'll see:

```
  Pairing page : http://192.168.1.x/moongate-pair.html
  Remote access: active (Cloudflare tunnel URL is rotated each Pi reboot —
                 the app discovers it automatically)

  Next step: run MOONGATE_PAIR in Klipper console, open the pairing page
  above on a device on the same WiFi, and scan with the app.
```

---

## Step 2 — Install the app

Download the latest APK from the [APK folder](https://github.com/PEEKYPAUL/Moongate/tree/master/APK) and install it on your phone.

> Latest public release: v0.2.29. The v0.4.0 release described in the rest of this guide is in final testing and ships when [`v0.4-secure-remote`](https://github.com/PEEKYPAUL/Moongate/tree/v0.4-secure-remote) merges to master.

---

## Step 3 — Pair

1. In Mainsail, type `MOONGATE_PAIR` in the G-code console
2. **From a device on the same WiFi as the Pi** (a PC, tablet, or another phone — not the phone you're installing on, unless you want to do the manual-code path) open `http://<your-pi-ip>/moongate-pair.html`
3. A QR code appears
4. In the Moongate app, tap **+** → **Scan QR** and point your phone's camera at the QR
5. Done — your printer appears in the dashboard

> The pair page is **LAN-only** in v0.4 by design. Visiting the equivalent URL over the Cloudflare tunnel returns 401 — pairing intentionally requires being on the same network as the Pi, so leaking the tunnel URL can't be used to pair an attacker's device.

**No second device handy?** Type the code shown in the Klipper console (`GATE-XXXX-XXXX`) directly into the app. Tap **+** → **Enter Code** instead of **Scan QR**.

---

## Step 4 — That's it

The dashboard tile starts polling immediately. Tap the tile to open the full Mainsail / Fluidd UI in an embedded browser; the connection switches between LAN (when you're home) and the Cloudflare tunnel (when you're away) automatically — no setting to flip.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `Unknown command: MOONGATE_PAIR` | `[include moongate.cfg]` is missing from `printer.cfg` — re-run `install.sh` |
| Pairing page shows "run MOONGATE_PAIR first" | Run `MOONGATE_PAIR` in the Klipper console, then refresh the page |
| Tile shows "Connected — Printer idle" | Not an error — the Pi is up but Klipper isn't producing usable status. Common on the Creality K3 when the printer-power toggle inside Mainsail is off. Power the printer on; the tile flips to live status within a couple of polls |
| Tile shows "Offline — Printer unreachable" | Check Moonraker (`sudo systemctl status moonraker`), auth proxy (`sudo systemctl status moongate-authproxy`), and tunnel (`sudo systemctl status moongate-tunnel`) are all running |
| Remote tunnel not showing | `cat /run/moongate-tunnel.log` to see the cloudflared output. Restart with `sudo systemctl restart moongate-tunnel` if needed |
| Tunnel URL changed after Pi reboot | No action — the app discovers the new URL automatically on the next poll |
| Webcam not showing | Confirm Mainsail → Settings → Webcams is configured and `http://<pi-ip>/webcam/?action=snapshot` works in a browser on your LAN |

For anything else, see the full [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) at the repo root.

---

## Building from source

```bash
git clone https://github.com/PEEKYPAUL/Moongate.git
cd Moongate/mobile
flutter pub get
flutter build apk --release
# APK: build/app/outputs/flutter-apk/app-release.apk
```

See [DEVELOPMENT.md](../DEVELOPMENT.md) for the full developer workflow.
