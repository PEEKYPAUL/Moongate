# Moongate — Setup Guide

## Requirements

### On your Raspberry Pi
- Klipper + Moonraker + Mainsail already installed (KIAUH or MainsailOS)
- Internet access (needed to reach Cloudflare)
- Architecture: aarch64 (Pi 4/5), armv7l (Pi 3), or x86_64

### On your Android phone
- Android 8.0 (Oreo) or later
- "Install from unknown sources" enabled for your file manager or browser

### To build from source (optional)
- Flutter SDK ≥ 3.19 (stable channel)
- Android SDK + JDK 17

---

## Step 1 — Install the plugin on your Pi

SSH into your Pi and run:

```bash
curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/moongate/master/klipper-plugin/install.sh | bash
```

This installs:
- The Moongate Moonraker plugin (`moongate.py`)
- The `MOONGATE_PAIR` G-code macro (writes `moongate.cfg`, adds `[include moongate.cfg]` at the top of `printer.cfg`)
- The QR pairing page (`moongate-pair.html` → Mainsail web root)
- `cloudflared` and a `moongate-tunnel` systemd service (auto-starts on boot)
- Restarts Moonraker and Klipper

At the end you'll see:

```
  Pairing page : http://192.168.1.x/moongate-pair.html
  Remote access: https://xxxx-xxxx.trycloudflare.com ✓

  Next step: run MOONGATE_PAIR in Klipper console,
  open the pairing page above on your PC, and scan with the app.
```

---

## Step 2 — Install the app

Download the latest APK from the [APK folder](https://github.com/PEEKYPAUL/moongate/tree/master/APK) and install it on your phone.

---

## Step 3 — Pair

1. In Mainsail, type `MOONGATE_PAIR` in the G-code console
2. Open `http://<your-pi-ip>/moongate-pair.html` on your PC — a QR code appears
3. In the Moongate app, tap **+** → **Scan QR** and point your phone at the QR code
4. Done — your printer appears in the dashboard

No PC handy? The code is also shown in the Klipper console (`GATE-XXXX-XXXX`). Tap **+** → **Enter Code** in the app instead.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `Unknown command: MOONGATE_PAIR` | `[include moongate.cfg]` is missing from `printer.cfg` — re-run `install.sh` |
| Pairing page shows "run MOONGATE_PAIR first" | Run `MOONGATE_PAIR` in the Klipper console, then refresh the page |
| Tile shows Offline | Check Moonraker is running: `sudo systemctl status moonraker` |
| Remote tunnel not showing | Check tunnel service: `sudo systemctl status moongate-tunnel`; view log: `cat /run/moongate-tunnel.log` |
| Tunnel URL changed after Pi reboot | Re-scan the QR code — or the app will auto-update the URL on next status poll |
| Webcam not showing | Ensure your webcam is configured in Mainsail and that `http://<pi-ip>/webcam/?action=snapshot` works in a browser |

---

## Building from source

```bash
git clone https://github.com/PEEKYPAUL/moongate.git
cd moongate/mobile
flutter pub get
flutter build apk --release
# APK: build/app/outputs/flutter-apk/app-release.apk
```
