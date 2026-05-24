# Moongate

> One app. Your Klipper printer. Anywhere.

Moongate is a free, open-source Android app that gives you a **full remote control interface for your Klipper 3D printer** — live webcam, print controls, temperatures, and the complete Mainsail/Fluidd UI — over your local network and automatically over the internet when you're away from home. No Tailscale. No VPN setup. No subscriptions.

<table align="center">
  <tr>
    <td><img src="docs/screenshots/dashboard.png" width="190" alt="Dashboard with multiple printers"/></td>
    <td><img src="docs/screenshots/printer-mainsail.png" width="190" alt="Full Mainsail UI in-app"/></td>
    <td><img src="docs/screenshots/pairing.png" width="190" alt="Pairing screen"/></td>
    <td><img src="docs/screenshots/drawer.png" width="190" alt="Settings drawer"/></td>
  </tr>
</table>

---

## How it works

```
┌─────────────────────┐   local WiFi (fast)    ┌──────────────────────┐
│   Moongate App      │◄──────────────────────►│  Klipper Pi          │
│   (Android)         │                        │  Moonraker           │
│                     │   Cloudflare tunnel    │  + Moongate plugin   │
│                     │◄──────────────────────►│                      │
└─────────────────────┘   (auto, when away)    └──────────────────────┘
```

The Moongate plugin runs inside Moonraker on your Pi. It handles pairing, token auth, status polling, and print control — proxying commands to Klipper on your behalf. A Cloudflare Quick Tunnel is started automatically on the Pi so you can reach it from anywhere without opening ports on your router.

---

## Setup

### Step 1 — Install the plugin on your Raspberry Pi

SSH into your Pi and run:

```bash
curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/moongate/master/klipper-plugin/install.sh | bash
```

> **Non-standard HTTP port?** Stock KIAUH / MainsailOS serves Moonraker on port 80 — the installer's default. If your nginx is on a different port (e.g. port 80 is taken by another service, or you're running Moonraker on `8080`), tell the installer:
>
> ```bash
> # Piped install
> MOONGATE_PORT=8080 bash -c "$(curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/moongate/master/klipper-plugin/install.sh)"
>
> # Or locally:
> curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/moongate/master/klipper-plugin/install.sh -o install.sh
> bash install.sh --port 8080
> ```
>
> The cloudflared tunnel and the QR pair URL will both use that port. In the app's pair screen, the **Port** field next to the IP is the matching control — leave it blank for 80, fill it in if you used something else here.

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

**Current version: v0.2.29**

**[⬇ Download Moongate-v0.2.29.apk](https://github.com/PEEKYPAUL/Moongate/raw/master/APK/Moongate-v0.2.29.apk)** and install it on your Android phone.

> Android only for now. Tap the link above to download directly to your phone.
> Enable **Install from unknown sources** for your browser or file manager before installing.

All releases are in the [APK folder](https://github.com/PEEKYPAUL/Moongate/tree/master/APK).

On first launch the app will ask you to add a printer.

---

### Step 3 — Pair

1. In Klipper/Mainsail, run the macro `MOONGATE_PAIR` in the console
2. Open `http://<your-pi-ip>/moongate-pair.html` on your PC — a QR code will appear
3. In the Moongate app, tap **+** → **Scan QR** and point your camera at the QR code
4. Done — your printer appears in the dashboard

**No PC handy?** You can also type the code shown in the Klipper console (`GATE-XXXX-XXXX`) directly into the app.

> The QR code automatically includes both your local IP and the Cloudflare tunnel URL. The app stores both — it uses local when you're home and the tunnel when you're away. If you installed before the remote URL was available, re-run `MOONGATE_PAIR` and re-scan to pick it up.

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

## Screenshots

### Dashboard & printer view

| Dashboard | Mainsail in-app | Pairing |
|---|---|---|
| <img src="docs/screenshots/dashboard.png" alt="Dashboard"/> | <img src="docs/screenshots/printer-mainsail.png" alt="Mainsail UI"/> | <img src="docs/screenshots/pairing.png" alt="Pairing screen"/> |
| Live webcam tiles, real-time progress, temperatures, chamber sensor, connection badge per printer | Tap any tile to open the full Mainsail / Fluidd web UI inside the app, with auto local/remote switching | Scan the QR from `moongate-pair.html`, or type the `GATE-XXXX-XXXX` code by hand |

### Make it yours — Custom theme

| Colour editor | Picker sheet |
|---|---|
| <img src="docs/screenshots/custom-theme.png" alt="Custom theme editor"/> | <img src="docs/screenshots/custom-theme-picker.png" alt="Colour picker"/> |
| Five slots: Accent, Page background, Cards & tiles, Text, Error. Live preview tile at the top updates as you tweak | HEX input (validated as you type) plus a 24-colour palette of curated presets. Tap a swatch and the whole app re-themes instantly |

### Settings drawer

The drawer scrolls — two captures to show everything.

| Top of menu | Bottom of menu |
|---|---|
| <img src="docs/screenshots/drawer.png" alt="Drawer — top"/> | <img src="docs/screenshots/drawer-bottom.png" alt="Drawer — bottom"/> |
| Printer management, config import/export, theme selector (incl. the new **Custom** option which jumps straight into the colour editor) | Font scale slider, 1/2/3-column dashboard layout, landscape rotation toggle, Settings shortcut, current version |

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
| **Customisable** | System / Light / Dark / **Custom** themes (the Custom mode lets you pick HEX values for accent, page background, cards, text and error from a colour editor with a 24-swatch palette), 1–3 column dashboard grid, font scale slider, optional landscape rotation |
| **Import / export** | One-tap config backup to clipboard; restore after a reinstall |

---

## Repository structure

```
moongate/
├── APK/                    # Pre-built release APKs + version manifest
│   ├── Moongate-v0.2.29.apk
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

For the full developer workflow — connecting a phone, debug vs release builds, logcat patterns, release signing, CI behaviour, bumping a version — see **[DEVELOPMENT.md](DEVELOPMENT.md)**.

For a tour of the codebase — Riverpod providers, the service layer, data flows, key design decisions — see **[ARCHITECTURE.md](ARCHITECTURE.md)**.

---

## Documentation

| Document | What's in it |
|---|---|
| [DEVELOPMENT.md](DEVELOPMENT.md) | Prerequisites, running, building, debugging, release signing, CI |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Code structure, state management, data-flow walkthroughs, design decisions |
| [SECURITY.md](SECURITY.md) | Threat model, JWT internals, key management, URL-leakage exposure, audit references, vulnerability reporting |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common failure modes — Offline tiles, tunnel issues, camera errors, progress mismatch, in-app update banner not appearing — with diagnostics for each |
| [CHANGELOG.md](CHANGELOG.md) | Every release from v0.2.0 onwards with one-line summaries of what changed and why |
| [docs/setup-guide.md](docs/setup-guide.md) | End-user setup walkthrough (friendlier version of [Setup](#setup) above) |

---

## License

**PolyForm Noncommercial License 1.0.0** — see [LICENSE](LICENSE) for the full legal text.

**Plain English:**

- ✅ Read the source, build it yourself, run it on your own printers — free, no permission needed
- ✅ Modify it for your own use, share your fork for non-commercial purposes — free
- ✅ Use at a charity, school, public research org, public safety / health org, environmental org, or government institution — free regardless of funding source
- ❌ Selling Moongate, charging for access, including it in a paid product, or any other commercial use — **requires a separate written licence from me**

If you'd like to use Moongate commercially, [open a GitHub issue](https://github.com/PEEKYPAUL/Moongate/issues/new) or contact [@PEEKYPAUL](https://github.com/PEEKYPAUL) directly to discuss terms.

---

*Created by [Paul Sharman](https://github.com/PEEKYPAUL)*
