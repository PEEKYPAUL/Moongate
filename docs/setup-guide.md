# Moongate - Setup Guide

> **This is the original v0.4-era guide, kept for reference.** The current, always-up-to-date setup lives in the **[README Quick start](../README.md#quick-start)** - and the app is now on the **[App Store](https://apps.apple.com/gb/app/moongate-klipper-control/id6785038887)** and **[Google Play](https://play.google.com/store/apps/details?id=com.moongate.app.moongate)** as well as the [early-access APK](https://github.com/PEEKYPAUL/Moongate/releases/latest).

## Requirements

### On your Raspberry Pi
- Klipper + Moonraker + Mainsail (or Fluidd) already installed via KIAUH / MainsailOS / FluiddPI
- Internet access (needed to reach the Cloudflare edge for the remote tunnel)
- Architecture: aarch64 (Pi 4/5), armv7l (Pi 3), or x86_64

### On your Android phone
- Android 8.0 (Oreo) or later
- Installing from [Google Play](https://play.google.com/store/apps/details?id=com.moongate.app.moongate) needs nothing extra; for the early-access APK, enable "Install from unknown sources" for the app you'll use to install it (browser or file manager)
- The phone needs to be on the same WiFi as the Pi for pairing - both sides of the QR exchange are LAN-only by design

### To build from source (optional)
- Flutter SDK ≥ 3.19 (stable channel)
- Android SDK + JDK 17

---

## Step 1 - Install the plugin on your Pi

SSH into your Pi and run:

```bash
curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/Moongate/master/klipper-plugin/install.sh | bash
```

This installs:
- The Moongate Moonraker plugin (`moongate.py`)
- The `MOONGATE_PAIR` G-code macro (writes `moongate.cfg`, adds `[include moongate.cfg]` at the top of `printer.cfg`)
- The QR pairing page (`moongate-pair.html` → Mainsail web root)
- The auth proxy systemd service (`moongate-authproxy.service`) - gates every tunnel-side request
- `cloudflared` and a `moongate-tunnel` systemd service (auto-starts on boot)
- Restarts Moonraker and Klipper

At the end you'll see:

```
  Pairing page : http://192.168.1.x/moongate-pair.html
  Remote access: active (Cloudflare tunnel URL is rotated each Pi reboot -
                 the app discovers it automatically)

  Next step: run MOONGATE_PAIR in Klipper console, open the pairing page
  above on a device on the same WiFi, and scan with the app.
```

---

## Step 2 - Install the app

Get Moongate on the [App Store](https://apps.apple.com/gb/app/moongate-klipper-control/id6785038887) (iPhone) or [Google Play](https://play.google.com/store/apps/details?id=com.moongate.app.moongate) (Android). Want each release the day it ships? Grab the Android **early-access APK** from the [Releases page](https://github.com/PEEKYPAUL/Moongate/releases/latest) instead - it updates itself in-app.

> This guide was written for **v0.4.2**; the flow it describes is unchanged, but see the [README Quick start](../README.md#quick-start) for the current version.

---

## Step 3 - Pair

1. In Mainsail, type `MOONGATE_PAIR` in the G-code console
2. **From a device on the same WiFi as the Pi** (a PC, tablet, or another phone - not the phone you're installing on, unless you want to do the manual-code path) open `http://<your-pi-ip>/moongate-pair.html`
3. A QR code appears
4. In the Moongate app, tap **+** → **Scan QR** and point your phone's camera at the QR
5. Done - your printer appears in the dashboard

> The pair page is **LAN-only** in v0.4 by design. Visiting the equivalent URL over the Cloudflare tunnel returns 401 - pairing intentionally requires being on the same network as the Pi, so leaking the tunnel URL can't be used to pair an attacker's device.

**No working camera on your phone?** Type the **GATE code** shown in the Klipper console (`GATE-XXXX-XXXX`) directly into the app. Tap **+** to open Add Printer - the GATE code section sits right below the Scan QR button with two 4-digit boxes and a numpad.

---

## Step 4 - That's it

The dashboard tile starts polling immediately. Tap the tile to open the full Mainsail / Fluidd UI in an embedded browser; the connection switches between LAN (when you're home) and the Cloudflare tunnel (when you're away) automatically - no setting to flip.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `Unknown command: MOONGATE_PAIR` | `[include moongate.cfg]` is missing from `printer.cfg` - re-run `install.sh` |
| Pairing page shows "run MOONGATE_PAIR first" | Run `MOONGATE_PAIR` in the Klipper console, then refresh the page |
| Tile shows "Connected - Printer idle" | Not an error - the Pi is up but Klipper isn't producing usable status. Common on the Creality K3 when the printer-power toggle inside Mainsail is off. Power the printer on; the tile flips to live status within a couple of polls |
| Tile shows "Offline - Printer unreachable" | Check Moonraker (`sudo systemctl status moonraker`), auth proxy (`sudo systemctl status moongate-authproxy`), and tunnel (`sudo systemctl status moongate-tunnel`) are all running |
| Remote tunnel not showing | `cat /run/moongate-tunnel.log` to see the cloudflared output. Restart with `sudo systemctl restart moongate-tunnel` if needed |
| Tunnel URL changed after Pi reboot | No action - the app discovers the new URL automatically on the next poll |
| Webcam not showing | Confirm Mainsail → Settings → Webcams is configured and `http://<pi-ip>/webcam/?action=snapshot` works in a browser on your LAN |

For anything else, see the full [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) at the repo root.

---

## Building from source

```bash
git clone https://github.com/PEEKYPAUL/Moongate.git
cd Moongate/mobile
flutter pub get
flutter build apk --release --flavor github --dart-define=MOONGATE_CHANNEL=github
# APK: build/app/outputs/flutter-apk/app-github-release.apk
```

See [DEVELOPMENT.md](../DEVELOPMENT.md) for the full developer workflow.
