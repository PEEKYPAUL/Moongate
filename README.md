# Moongate

> One app. Your Klipper printer. Anywhere.

Moongate is a free, open-source Android app that gives you a **full remote control interface for your Klipper 3D printer** — live webcam, print controls, temperatures, and the complete Mainsail/Fluidd UI — over your local network and automatically over the internet when you're away from home. No Tailscale. No VPN setup. No subscriptions.

<p align="center">
  <img src="docs/screenshots/dashboard.png" width="220" alt="Dashboard with multiple printers"/>
  <img src="docs/screenshots/printer-mainsail.png" width="220" alt="Full Mainsail UI in-app"/>
  <img src="docs/screenshots/pairing.png" width="220" alt="Pairing screen"/>
  <img src="docs/screenshots/drawer.png" width="220" alt="Settings drawer"/>
</p>

---

## Download

**Current version: v0.2.20**

**[⬇ Download Moongate-v0.2.20.apk](https://github.com/PEEKYPAUL/Moongate/raw/master/APK/Moongate-v0.2.20.apk)**

> Android only for now. Tap the link above to download directly to your phone.
> Enable **Install from unknown sources** for your browser or file manager before installing.

All releases are in the [APK folder](https://github.com/PEEKYPAUL/Moongate/tree/master/APK).

---

## What it does

| Feature | Detail |
|---|---|
| **Dashboard** | See all your printers at a glance — live webcam thumbnails refreshing every second, print progress (matched to Mainsail's slicer-time calculation), temperatures, chamber sensor, and status |
| **Print controls** | Pause, resume, and stop prints directly from the dashboard tile. Stop requires a second press to confirm. Idle / errored printers get a one-tap firmware-restart button |
| **Full Mainsail / Fluidd UI** | Tap any tile to open the complete web UI in an embedded browser. Auto-detects whichever you run |
| **Auto local / remote** | Connects over your home WiFi first; if unreachable, automatically falls back to the Cloudflare tunnel within 3 seconds. Remembers which path works per session |
| **Network-aware** | At cold launch and on every resume, the app checks the phone's subnet against each printer's. On a different network it skips the local probe entirely — no 3-second timeout, no chance of latching onto an unrelated device on a stranger LAN |
| **Secure pairing** | One Klipper console command generates a time-limited QR + code. JWT-based auth, no port forwarding, no static IP |
| **Auto-discovery** | Chamber temperature sensors are auto-detected regardless of how they're named in `printer.cfg` (`[temperature_sensor chamber]`, `[heater_generic CHAMBER]`, `[temperature_fan Chamber_Temp]`, etc.) |
| **In-app updates** | The app checks for new versions on launch and offers a one-tap download when one is available |
| **Customisable** | Light / dark / system theme, 1–3 column dashboard grid, font scale slider, optional landscape rotation |
| **Import / export** | One-tap config backup to clipboard; restore after a reinstall |

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
- Clone the Moongate repo to `~/moongate` and symlink the plugin into Moonraker
- Register Moongate with Moonraker's update manager (visible in Mainsail → Software Updates)
- Deploy the QR pairing page to Mainsail
- Install `cloudflared` and start the remote-access tunnel as a systemd service
- Restart Moonraker and Klipper

At the end you'll see output like:

```
  Updates   : Mainsail → Software Updates → Moongate
  Pairing   : http://192.168.1.x/moongate-pair.html
  Tunnel    : https://racing-partly-mouse.trycloudflare.com ✓
  Subdomain : racing-partly-mouse  (paste into app tunnel field)
```

> **Requirements:** Raspberry Pi running Klipper + Moonraker + Mainsail or Fluidd (standard KIAUH / MainsailOS / FluiddPI setup). Tested on aarch64 (Pi 4/5) and armv7l (Pi 3).

> **Keeping it updated:** After the initial install, future plugin updates appear automatically in **Mainsail → Software Updates → Moongate** — no SSH needed.

---

### Step 2 — Install the app

[Download Moongate-v0.2.20.apk](https://github.com/PEEKYPAUL/Moongate/raw/master/APK/Moongate-v0.2.20.apk) and install it on your Android phone.

On first launch the app will ask you to add a printer.

---

### Step 3 — Pair

1. In Klipper/Mainsail, run the macro `MOONGATE_PAIR` in the console
2. Open `http://<your-pi-ip>/moongate-pair.html` on your PC — a QR code will appear
3. In the Moongate app, tap **+** → **Scan QR** and point your camera at the QR code
4. Done — your printer appears in the dashboard

**No PC handy?** You can also type the code shown in the Klipper console (`GATE-XXXX-XXXX`) directly into the app.

---

### Step 4 — Uninstall

To completely remove Moongate from your Pi, SSH in and run:

```bash
curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/moongate/master/klipper-plugin/uninstall.sh | bash
```

This removes:
- The `moongate-tunnel` systemd service
- The Moongate Moonraker plugin
- The `~/moongate` repository clone
- `~/.config/moongate` (tokens and secret key)
- The `[moongate]` and `[update_manager moongate]` entries from `moonraker.conf`
- The `MOONGATE_PAIR` macro from your Klipper config
- The `moongate-pair.html` page from Mainsail

`cloudflared` itself is left in place as it may be used by other services. To remove it too: `sudo apt remove cloudflared`

Don't forget to uninstall the Moongate app from your phone as well.

---

## Pairing the remote (Cloudflare) URL

The QR code from `moongate-pair.html` automatically includes both your local IP and the Cloudflare tunnel URL. When you scan it, the app stores both — it uses local when you're home and the tunnel when you're away.

If you installed before the remote URL was available, re-run `MOONGATE_PAIR` and re-scan to pick it up.

---

## Screenshots

| Dashboard | Mainsail in-app | Pairing | Settings drawer |
|---|---|---|---|
| <img src="docs/screenshots/dashboard.png" alt="Dashboard"/> | <img src="docs/screenshots/printer-mainsail.png" alt="Mainsail UI"/> | <img src="docs/screenshots/pairing.png" alt="Pairing screen"/> | <img src="docs/screenshots/drawer.png" alt="Settings drawer"/> |
| Live webcam tiles, real-time progress, temperatures, chamber sensor, connection badge per printer | Tap any tile to open the full Mainsail / Fluidd web UI inside the app, with auto local/remote switching | Scan the QR from `moongate-pair.html`, or type the `GATE-XXXX-XXXX` code by hand | Theme, font scale, dashboard column count, landscape rotation, config import/export |

---

## Repository structure

```
moongate/
├── APK/                    # Pre-built release APKs + version manifest
│   ├── Moongate-v0.2.20.apk
│   ├── Moongate-latest.apk
│   └── latest_version.json
├── docs/
│   ├── setup-guide.md      # Long-form setup walkthrough
│   └── screenshots/        # README screenshots
├── mobile/                 # Flutter app (Android)
│   ├── lib/
│   │   ├── features/       # UI screens (dashboard, printer, pairing, settings)
│   │   ├── models/         # Data models (PrinterConfig, etc.)
│   │   ├── providers/      # Riverpod providers (settings, updates, version)
│   │   └── services/       # Status polling, print control, auth, registry, network discovery
│   └── android/            # Android platform code (CameraX, WireGuard stub, ProGuard)
└── klipper-plugin/
    ├── moongate_standalone.py   # Moonraker plugin
    ├── install.sh               # One-line installer for the Pi
    ├── update.sh                # Post-pull hook called by Moonraker update manager
    ├── uninstall.sh             # Complete uninstaller (Step 4)
    └── moongate-pair.html       # QR pairing page (deployed to Mainsail)
```

---

## Building from source

Requirements: Flutter 3.19+ (stable channel), Android SDK, JDK 17.

```bash
git clone https://github.com/PEEKYPAUL/Moongate.git
cd Moongate/mobile
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
- The tunnel URL changes on each Pi restart — the app fetches the latest URL automatically via the status endpoint, so no re-pairing is needed

**Webcam not showing**
- The app fetches snapshots from `/webcam/?action=snapshot` on your Pi
- Make sure your webcam is configured in Mainsail and that URL works in a browser

**Dashboard tile shows the wrong printer when on a friend's network**
- Fixed in v0.2.18: the app now compares your phone's WiFi subnet against each printer's at cold launch and on resume. If they don't match it skips the local probe entirely and goes straight to the tunnel — no 3-second timeout, no false-positive from an unrelated device on the stranger LAN

**Camera error when scanning the QR code**
- Fixed in v0.2.19 (mobile_scanner bump) and v0.2.20 (ProGuard rules for ML Kit)
- Grant camera permission when prompted, or go to Settings → Apps → Moongate → Permissions and enable Camera

**Progress percentage on the tile doesn't match Mainsail**
- Fixed in v0.2.16: the app now uses `print_duration / estimated_time` from `/server/files/metadata` — the same formula Mainsail uses — instead of `display_status.progress` (which is 0 until the slicer emits `M73`) or `virtual_sdcard.progress` (which runs ahead of the toolhead due to look-ahead buffering)

---

## Changelog

| Version | Changes |
|---|---|
| **v0.2.20** | Camera scanner fix #2: add ProGuard rules for ML Kit + mobile_scanner so R8 doesn't strip the bundled barcode scanner classes (the mobile_scanner consumer rule had a single-dot wildcard bug that only matched the root package) |
| **v0.2.19** | Upgrade `mobile_scanner` 5.2.3 → 7.x — fixes the Samsung One UI `analysis.resolutionInfo!!` NPE. CameraX bumped to 1.5.3 |
| **v0.2.18** | Network-aware connection: subnet check at cold launch & on app resume pre-decides "use tunnel" for any printer whose LAN isn't reachable from the current WiFi. Symmetric `onHttpError` handling in the printer WebView so a 4xx from an unrelated device on a stranger LAN doesn't trigger the error overlay |
| **v0.2.17** | Printer screen now reads the dashboard tile's live network-path decision so tapping a tile on a foreign network jumps straight to the tunnel — no more "Printer unreachable" overlay |
| **v0.2.16** | Print progress now uses `print_duration / estimated_time` from `/server/files/metadata`, matching Mainsail/Fluidd exactly. Falls back to `display_status.progress` then `virtual_sdcard.progress` when slicer estimate is unavailable |
| **v0.2.15** | Supplementary progress query when the plugin endpoint omits `display_status` or `virtual_sdcard` |
| **v0.2.14** | QR scanner refactor: explicit `StreamSubscription` to `controller.barcodes` instead of `onDetect`, avoiding the `WidgetsBindingObserver` leak in `mobile_scanner` 5.x |
| **v0.2.13** | Force CameraX 1.4.0 to dodge a Samsung-specific NPE in `mobile_scanner` 5.x's CameraX 1.3.3 (later superseded by v0.2.19's package bump) |
| **v0.2.12** | Supplementary progress query, chamber sensor support refinements |
| **v0.2.11** | Chamber temperature on tile, supplementary chamber query for older plugin builds |
| **v0.2.10** | Silent offline retries + Mainsail/Fluidd webcam placeholder logo + grid column picker + Loading Local / Loading Tunnel / Offline labels in webcam area |
| **v0.2.9** | Always start local-first on launch; expand chamber discovery to include `temperature_fan` and `heater_generic` |
| **v0.2.8** | Dynamic chamber sensor discovery for any capitalisation / suffix |
| **v0.2.7** | Camera error diagnostic: show actual native error code/message so device-specific failures are readable |
| **v0.2.6** | Camera: explicit controller with autoStart=false + post-frame start; 700 ms delay on first permission grant |
| **v0.2.5** | Fix 5 bugs: app name capitalisation, import config crash, print controls now respect remote-first preference, router crash guard on missing printer, VPN disconnect safe on sign-out |
| **v0.2.4** | Fix camera `genericError` — switch `MainActivity` to `FlutterFragmentActivity` (required by CameraX / MobileScanner v5) |
| **v0.2.3** | Remove explicit `MobileScannerController` — let MobileScanner manage its own CameraX lifecycle |
| **v0.2.2** | Consistent release signing; fix update conflict on install; longer tunnel timeout (8 s); `startup` badge state |
| **v0.2.1** | In-app update banner; version bump process established |
| **v0.2.0** | Cloudflare Quick Tunnel remote access; auto local/remote fallback |

---

## License

MIT — see [LICENSE](LICENSE)

---

*Created by [Paul Sharman](https://github.com/PEEKYPAUL)*
