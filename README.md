# Moongate

> One app. Your Klipper printer. Anywhere.

Moongate is a free, open-source Android app that gives you a **full remote control interface for your Klipper 3D printer** — live webcam, print controls, temperatures, and the complete Mainsail UI — over your local network and automatically over the internet when you're away from home. No Tailscale. No VPN setup. No subscriptions.

---

## Download

**[⬇ Download latest APK](https://github.com/PEEKYPAUL/moongate/tree/master/APK)**

> Android only for now. Open the `APK` folder, click the `.apk` file, then click **View raw** to download.  
> Enable **Install from unknown sources** for your browser or file manager before installing.

---

## What it does

| Feature | Detail |
|---|---|
| **Dashboard** | See all your printers at a glance — live webcam thumbnails refreshing every second, print progress, temperatures, and status |
| **Print controls** | Pause, resume, and stop prints directly from the dashboard tile. Stop requires a second press to confirm |
| **Firmware restart** | When a printer is idle or in error state, the stop button becomes a one-tap firmware restart |
| **Full Mainsail UI** | Tap any tile to open the complete Mainsail/Fluidd interface in an embedded browser |
| **Auto local/remote** | Connects over your home WiFi first; if unreachable, automatically falls back to the Cloudflare tunnel within 3 seconds |
| **Secure pairing** | One Klipper console command generates a time-limited QR + code. No port forwarding, no static IP |

---

## How it works

```
┌─────────────────────┐   local WiFi (fast)    ┌──────────────────────┐
│   Moongate App      │◄──────────────────────►│  Klipper Pi          │
│   (Android)         │                         │  Moonraker           │
│                     │   Cloudflare tunnel     │  + Moongate plugin   │
│                     │◄──────────────────────►│                      │
└─────────────────────┘   (auto, when away)     └──────────────────────┘
```

The Moongate plugin runs inside Moonraker on your Pi. It handles pairing, token auth, status polling, and print control — proxying commands to Klipper on your behalf. A Cloudflare Quick Tunnel is started automatically on the Pi so you can reach it from anywhere without opening ports on your router.

---

## Setup

### Step 1 — Install the plugin on your Raspberry Pi

SSH into your Pi and run:

```bash
curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/moongate/master/klipper-plugin/install.sh | bash
```

This will:
- Install the Moongate Moonraker plugin
- Deploy the QR pairing page to Mainsail
- Install `cloudflared` and start the remote-access tunnel as a systemd service
- Restart Moonraker

At the end you'll see output like:

```
  Pairing page : http://192.168.1.x/moongate-pair.html
  Remote access: https://xxxx-xxxx.trycloudflare.com ✓

  Next step: run MOONGATE_PAIR in Klipper console,
  open the pairing page above on your PC, and scan with the app.
```

> **Requirements:** Raspberry Pi running Klipper + Moonraker + Mainsail (standard Kiauh/MainsailOS setup). Tested on aarch64 (Pi 4/5) and armv7l (Pi 3).

---

### Step 2 — Install the app

[Download the APK](https://github.com/PEEKYPAUL/moongate/tree/master/APK) and install it on your Android phone.

On first launch the app will ask you to add a printer.

---

### Step 3 — Pair

1. In Klipper/Mainsail, run the macro `MOONGATE_PAIR` in the console
2. Open `http://<your-pi-ip>/moongate-pair.html` on your PC — a QR code will appear
3. In the Moongate app, tap **+** → **Scan QR** and point your camera at the QR code
4. Done — your printer appears in the dashboard

**No PC handy?** You can also type the code shown in the Klipper console (`GATE-XXXX-XXXX`) directly into the app.

---

## Pairing the remote (Cloudflare) URL

The QR code from `moongate-pair.html` automatically includes both your local IP and the Cloudflare tunnel URL. When you scan it, the app stores both — it uses local when you're home and the tunnel when you're away.

If you installed before the remote URL was available, re-run `MOONGATE_PAIR` and re-scan to pick it up.

---

## Screenshots

| Dashboard | Printer controls | Full Mainsail UI |
|---|---|---|
| Live webcam tiles, progress, temps | Pause / Resume / Stop with confirm | Embedded WebView, auto local/remote |

---

## Repository structure

```
moongate/
├── mobile/             # Flutter app (Android)
│   ├── lib/
│   │   ├── features/   # UI screens (dashboard, printer, pairing, settings)
│   │   ├── models/     # Data models (PrinterConfig, etc.)
│   │   └── services/   # Status polling, print control, auth, registry
│   └── android/        # Android platform code
└── klipper-plugin/
    ├── moongate_standalone.py   # Moonraker plugin
    ├── install.sh               # One-line installer for the Pi
    └── moongate-pair.html       # QR pairing page (deployed to Mainsail)
```

---

## Building from source

Requirements: Flutter 3.19+ (stable channel), Android SDK, JDK 17.

```bash
git clone https://github.com/PEEKYPAUL/moongate.git
cd moongate/mobile
flutter pub get
flutter build apk --release
# APK: build/app/outputs/flutter-apk/app-release.apk
```

---

## Troubleshooting

**Printer shows Offline**
- Check that Moonraker is running: `sudo systemctl status moonraker`
- Confirm the plugin loaded: look for `[moongate]` in Moonraker logs (`~/printer_data/logs/moonraker.log`)

**Remote tunnel not connecting**
- Check the tunnel service: `sudo systemctl status moongate-tunnel`
- View the tunnel log: `cat /run/moongate-tunnel.log`
- The tunnel URL changes each restart — re-scan the QR to update the app

**Webcam not showing**
- The app fetches snapshots from `/webcam/?action=snapshot` on your Pi
- Make sure your webcam is configured in Mainsail and that URL works in a browser

**App says "Could not reach printer"**
- The app tries local first, then remote; if both fail it shows an error
- Check your phone's WiFi when on home network
- Check the tunnel status when remote

---

## License

MIT — see [LICENSE](LICENSE)

---

*Created by [Paul Sharman](https://github.com/PEEKYPAUL)*
