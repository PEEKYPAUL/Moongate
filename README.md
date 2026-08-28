<div align="center">

<img src="docs/moongate-icon.png" width="96" alt="Moongate logo"/>

# Moongate

### One app. Your Klipper printer. Anywhere.

[![Latest release](https://img.shields.io/github/v/release/PEEKYPAUL/Moongate?label=latest%20release&color=6C63FF)](https://github.com/PEEKYPAUL/Moongate/releases/latest)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iPhone%20%7C%20Android-6C63FF)](#quick-start)
[![App Store](https://img.shields.io/badge/iPhone-on%20the%20App%20Store-0D96F6?logo=apple&logoColor=white)](https://apps.apple.com/gb/app/moongate-klipper-control/id6785038887)
[![Google Play](https://img.shields.io/badge/Android-on%20Google%20Play-34A853?logo=googleplay&logoColor=white)](https://play.google.com/store/apps/details?id=com.moongate.app.moongate)

<img src="docs/screenshots/generated/hero-ios.png" width="820" alt="Moongate on iPhone and Android - fleet dashboard with per-printer console and file tools, the full Mainsail UI in-app, and printing straight from stored G-code"/>

Free, source-available **iPhone and Android** control for your **Klipper 3D printer** - live webcam, print controls, temperatures, and the complete Mainsail/Fluidd UI - over home WiFi and **automatically over the internet** when you're away. Zero setup, no port forwarding, no subscriptions.

**Prefer your own infrastructure? Run it your way.** The cloud-free **Direct (LAN/VPN)** mode talks straight to your printer over your network - or your own **WireGuard / Tailscale VPN** when you're out - and never touches the internet. [See how the two modes compare ›](#run-it-your-way)

<a href="https://apps.apple.com/gb/app/moongate-klipper-control/id6785038887"><img src="https://img.shields.io/badge/Download%20on%20the%20App%20Store-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Download on the App Store"/></a>
<a href="https://play.google.com/store/apps/details?id=com.moongate.app.moongate"><img src="https://img.shields.io/badge/Get%20it%20on%20Google%20Play-34A853?style=for-the-badge&logo=googleplay&logoColor=white" alt="Get it on Google Play"/></a>
<a href="https://github.com/PEEKYPAUL/Moongate/releases/latest"><img src="https://img.shields.io/badge/%E2%AC%87%20APK%20%E2%80%A2%20early%20access-6C63FF?style=for-the-badge&logo=android&logoColor=white" alt="Download the APK - early access channel"/></a>

**📱 Now on both stores.** Moongate is live on the [App Store](https://apps.apple.com/gb/app/moongate-klipper-control/id6785038887) and [Google Play](https://play.google.com/store/apps/details?id=com.moongate.app.moongate), built from one codebase. The stores carry the **stable releases**; the [GitHub APK](https://github.com/PEEKYPAUL/Moongate/releases/latest) is the **early-access channel** - every release lands there first, and it updates itself in-app.

</div>

---

## Contents

- [Features](#features)
- [Screenshots](#screenshots)
- [Quick start](#quick-start)
- [Run it your way](#run-it-your-way)
- [How it works](#how-it-works)
- [Documentation](#documentation)
- [Buy me a coffee](#buy-me-a-coffee)
- [License](#license)

---

## Features

- 📊 **Fleet dashboard** - live webcam thumbnails (the feed rate follows your network automatically - smoother on Wi-Fi, throttled on mobile data to save it - with separate rates you can tune for each, or switch a feed off entirely), print progress that matches what Mainsail shows **with the time left right on the tile** (or the projected finish time - switch the format, or hide it, in menu → Dashboard Layout), temperatures, a chamber sensor, and a per-printer status badge. Tiles auto-sort by activity so whatever's printing floats to the top - or turn that off and **drag them into your own order**, which sticks and travels in your backups. **Hide a printer's webcam** to shrink it to a compact tile, and the grid packs full and compact tiles together so the printers you're not watching take up less room - compact tiles keep the full quick-action row (status, pause/stop, files, macros, lighting; v0.9.60+).
- 🧰 **Multi-toolhead & tool changers** - IDEX and tool-changer printers (klipper-toolchanger / StealthChanger) are fully supported. The dashboard shows **every hotend** as its own **T0 / T1 / …** chip with the **active tool highlighted**, **preheat** sets a target for each tool at once (plus the bed), and the print notification lists **all** their live hotend temperatures. The Pi plugin folds the whole toolhead set into the single secure status call the app already reads, so detection stays reliable on Wi-Fi, over the tunnel, and on a VPN.
- 📷 **External cameras** - point a tile at a camera that isn't wired into Klipper (an old phone as a webcam, a network IP cam, a **go2rtc** feed). Cameras already configured in Mainsail are auto-detected - including **go2rtc / WebRTC** cameras (v0.9.52+, shown as live stills) - or set one by hand with the tile's gear. Works on Wi-Fi and remotely through the tunnel (home-network cameras), and a menu toggle hides the gears. **Several cameras on one printer?** A switch button on the tile and in full-screen picks which one to show (v0.9.59+ with plugin 0.6.22+); the choice sticks per printer, and a hand-set gear camera still wins.
- 🎛️ **Print controls** - pause, resume, and stop from the tile, plus a one-tap firmware restart for idle or errored printers. An **emergency-stop** triangle on every online tile halts the machine instantly (Klipper `M112`) on a **double-tap** - and once it's stopped, the triangle turns into a one-tap **restart** to bring the printer back. If a printer has a Moonraker **power device**, a power button on its tile switches it **on or off** (with a confirm) - and it works even while the printer is off, so you can wake it remotely. No power device? Point the printer at its own **power macro** instead (Advanced Power Switch) and the same button drives that. There's also an optional **Power all machines** button for the top bar (switch it on in the menu) that powers your whole fleet on or off at once, driving each printer however it's set up (a power device or a power macro), showing exactly which ones will switch, and always leaving a printer that's currently printing on.
- 💡 **Lighting control** - drive your printer's lights from the dashboard. Set each printer's on/off (or single toggle) macro under the **Lighting** menu, then tap the bulb on its camera (on a compact, webcam-hidden tile it sits in the action row instead). Point it at the light's Klipper object and the bulb shows the **real** on/off state, even when you switch the light elsewhere.
- 📂 **Print files on the printer** - tap the folder button on a ready printer to browse the G-code already saved on it, shown with slicer **thumbnails**, newest first. Pick one and **Start print** with a confirm tap - no slicer, no re-upload.
- 🖥️ **Full Mainsail / Fluidd UI** - tap a tile to open the complete web UI in-app; whichever you run is auto-detected. Every printer's page is **warmed in the background the moment the app starts and then kept loaded, so even the first time you open a printer it's instant** - no "Initializing…" reload, a big difference over the tunnel. A built-in full-screen **camera view** - open it from the top-bar icon, the tile's eye button, or just **press and hold any tile's camera** - runs at the camera's **full frame rate** with pinch-to-zoom, and keeps the feed working when you're away - even for an external camera the embedded page can't load over mobile data.
- 📡 **Auto local ↔ remote** - tries home WiFi first every poll, falls back to the Cloudflare tunnel within ~2s when you're away, and flips back to "Local" the moment you're home. Printers that are **switched off cost almost nothing in the background** - the dashboard and the print notifications both stop reaching out to them until they're back online - so it's easy on mobile data and battery. Prefer to stay off the internet entirely? An optional **Local only** switch in the top bar (enable its button in the menu) turns remote connections off with one tap - only printers on your own network connect until you tap it again.
- 🔌 **Run it your way - Direct (LAN/VPN) mode** - a fully **cloud-free** way to run Moongate: install the Pi in LAN-only mode, add the printer by QR or address, and the app talks **straight to Moonraker** on your network - no account, no tunnel, nothing ever leaves your LAN. Away from home you connect over **your own VPN** (WireGuard, Tailscale). Existing printers **switch between cloud and Direct** from their edit dialog, no re-pairing. Honest trade-off: no print notifications in Direct mode, and remote access is your VPN's job. [Details ›](#run-it-your-way)
- 🔔 **Print notifications** - opt-in live fleet status in your notification shade - per-printer progress, the projected **finish time**, temperatures and heat-up - with start / finish / pause / error alerts and a configurable refresh interval. The alerts cover the machine itself too: if Klipper errors out or shuts down - mid-print or idle - you get the alert **with the reason** ("Heater extruder not heating at expected rate"), even though that's exactly when a printer normally goes quiet. On iPhone they arrive as push notifications; on Android (v0.9.61+) a paused, failed or errored printer buzzes through its own **"Printer alerts"** notification category, which you can mute on its own without touching the quiet status bar. There's also a **`MOONGATE_NOTIFY MSG="your text"`** macro (plugin 0.6.25+): call it from any gcode - slicer end-gcode, a filament-runout handler - and the text lands on your phone (iPhone today; Android support arrives with an upcoming plugin update). **Choose which details show and drag them into the order you want**, and the roster follows your dashboard's order (your **Auto-arrange by status** setting). A **pause/play button** in the top bar suspends the background checks with one tap when your printers will be off for a while (saving battery), then resumes them when you tap it again. Off by default.
- 🔒 **App lock** - optional PIN + biometric (fingerprint/face) on launch, with configurable auto-lock and screenshot protection. Off by default.
- 🎓 **Guided tour** - an optional in-app walkthrough, offered once you've added your first printer, that points out each part of the app live: the connection bars and what they mean (including the "tunnel still building" marker you see just after pairing), the temperatures and the double-tap emergency stop, the webcam and preheat, and the main options in the menu. Step forward or back, end it any time, and re-run it from the bottom of the menu.
- 🌍 **9 languages** - fully translated into English, German, French, Spanish, Italian, Simplified Chinese, Russian, Polish, and Brazilian Portuguese (community-contributed); choose on first launch or anytime from the menu.
- 🎨 **Themes & layout** - **Light / Dark / fully Custom** colours, plus **Phone colours** on **Android 12+** that follow your system **Material You** wallpaper palette and light/dark setting. Custom adds your own **dashboard background image** and adjustable **tile opacity**. Restyle the whole app's text with a **36-font picker** (grouped by style), and there's a 1-3 column grid, display-size scaling, optional landscape, and a switch to **hide the floating add / reorder buttons** at the bottom (menu → Dashboard Layout) when you have a lot of printers.
- 💾 **Backup & restore** - save your printers and settings to a file; restoring after a reinstall, or on a new phone, brings your printers **back online with no re-pairing**. Restoring **adds to** what's already on your dashboard - it never removes printers unless you choose to match the backup exactly.
- 🔄 **In-app updates** (early-access APK; store builds update through their store) - when a new version lands, update right inside the app: it downloads with a progress bar and installs in place - no browser detour, nothing re-paired. The dashboard also keeps the **printer side** current: a printer running an out-of-date Moongate plugin shows a small **update icon on its tile** until it's updated - tap it and (on recent plugins) **one tap updates the plugin straight from your phone**; older plugins get pointed at Mainsail's Software Updates panel.

> 🔐 **Hardened remote access** - every internet-facing request is gated by a short-lived signed token. Leaking the tunnel URL alone gives an attacker nothing but flat `401`s, with no Mainsail/Moonraker fingerprint. [How it works ›](#how-it-works)

---

## Screenshots

<div align="center">
  <img src="docs/screenshots/generated/framed-pairing.png" width="19%" alt="Secure LAN pairing"/>
  <img src="docs/screenshots/generated/framed-drawer.png" width="19%" alt="Menu"/>
  <img src="docs/screenshots/generated/framed-icon-guide.png" width="19%" alt="Icon guide - what every dashboard icon means"/>
  <img src="docs/screenshots/generated/framed-custom-theme.png" width="19%" alt="Custom theme editor"/>
  <img src="docs/screenshots/generated/framed-gcode-viewer.png" width="19%" alt="Print a stored G-code file"/>
</div>

<div align="center">
  <img src="docs/screenshots/generated/framed-console.png" width="19%" alt="Per-printer G-code console - history pre-filled, quick-command chips"/>
  <img src="docs/screenshots/generated/framed-file-system.png" width="19%" alt="File System - browse the printer's configuration folder"/>
  <img src="docs/screenshots/generated/framed-config-editor.png" width="19%" alt="Structured printer.cfg editor - names fixed, values editable, backup before the first change"/>
</div>

<div align="center">
<br/>
<img src="docs/screenshots/notification.png" width="640" alt="Print notifications in the Android notification shade"/>
<br/><sub><em>Optional print notifications - live fleet status &amp; start / finish / error alerts, right in your notification shade.</em></sub>
</div>

---

## Quick start

Three steps: install the Pi plugin, install the app, pair.

### 1. Install the Pi plugin

SSH into your Pi and run:

```bash
curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/Moongate/master/klipper-plugin/install.sh | bash
```

The installer asks how your phone will connect: **1) Moongate cloud** (the default - remote access from anywhere) or **2) Direct (LAN/VPN)** (cloud-free; [see how the two compare](#run-it-your-way)). With the default it installs the plugin, the `MOONGATE_PAIR` macro, the QR pairing page, the auth proxy, and the Cloudflare tunnel, then restarts Moonraker. Future updates appear in **Mainsail → Software Updates → Moongate**.

> **Using a 3rd-party printer instead?** (e.g. an Elegoo Centauri Carbon on OpenCentauri COSMOS) - this installer targets Raspberry-Pi-style machines and won't run on embedded vendor firmware. Follow [3rd-party printer support](docs/third-party-printers.md) instead: a one-file install, no installer needed.

<details>
<summary><b>Requirements &amp; custom HTTP port</b></summary>

<br>

**Requirements:** a Raspberry Pi running Klipper + Moonraker + Mainsail or Fluidd (standard KIAUH / MainsailOS / FluiddPI). Tested on aarch64 (Pi 4/5) and armv7l (Pi 3).

**Non-standard port?** Moonraker usually serves on port 80 (the installer's default). If yours is elsewhere, tell the installer:

```bash
MOONGATE_PORT=8080 bash -c "$(curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/Moongate/master/klipper-plugin/install.sh)"
```

In the app's pair screen, set the **Port** field to match (leave it blank for 80).

**Other things talk to Moonraker at this Pi's IP?** A cloud install moves Moonraker onto localhost so only Moongate's gated tunnel is exposed. An on-Pi client like KlipperScreen then needs pointing at `127.0.0.1`, and a central "farm" Mainsail/Fluidd on another machine should target port 80 (this Pi's nginx serves the full Moonraker API there) - see [Troubleshooting](TROUBLESHOOTING.md) for both. If something genuinely needs raw `<pi-ip>:7125`, keep the bind exactly as it is:

```bash
MOONGATE_KEEP_BIND=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/Moongate/master/klipper-plugin/install.sh)"
```

**LAN-only (own VPN, no tunnel)?** If you reach your printer over your own VPN / WireGuard and don't want an outbound Cloudflare tunnel or external exposure, install in LAN-only mode. It keeps Moonraker on the LAN (`0.0.0.0`) and skips cloudflared, the auth proxy, and the tunnel service. The plugin, `MOONGATE_PAIR` macro, and mDNS advertisement are still installed, and a later cloud re-install enables remote access.

**The installer asks.** Run it interactively (the normal `curl | bash` one-liner counts) and it offers the choice - answer `2` for Direct (LAN/VPN):

```
How will your phone connect to this printer?
    1) Moongate cloud   - remote access from anywhere (secure tunnel)
    2) Direct (LAN/VPN) - home network / your own VPN only, no cloud
```

On a box that already runs LAN-only the default keeps it LAN-only, so pressing Enter never converts your mode. To preselect an answer and skip the question (scripts, headless installs):

```bash
# LAN-only, piped
MOONGATE_LAN_ONLY=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/Moongate/master/klipper-plugin/install.sh)"
# LAN-only, from a local checkout
bash install.sh --lan-only
# cloud, never prompt (automation)
MOONGATE_LAN_ONLY=0 bash -c "$(curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/Moongate/master/klipper-plugin/install.sh)"
```

Choosing LAN-only on a box that already has the tunnel stack retires it (disables the tunnel + auth proxy) and converges to LAN-only.

In the app, add a LAN-only printer with **Add printer → Direct (LAN/VPN)** - scan the QR from `MOONGATE_PAIR` or type the printer's address. A LAN-only box can also be paired through the cloud as normal (while it has internet); Direct mode is for the fully cloud-free / internet-isolated case. Two networking notes:

- **`trusted_clients` must cover your phone.** The app talks to Moonraker directly, so the phone's subnet needs to be in Moonraker's `[authorization] trusted_clients`. Home WiFi and WireGuard's usual `10.x` range typically already are; **Tailscale's `100.64.0.0/10` usually is not** - add it or Moonraker answers 401 before Moongate ever runs.
- **Give the Pi a fixed address.** The app stores the address a Direct printer was added with, so use a DHCP reservation (or static IP) - if the Pi's IP changes you'd have to re-add it.

Direct-mode printers work fully offline, but skip everything cloud-backed: no print notifications, and away from home the app only reaches them through your own VPN.

</details>

### 2. Install the app

[![Download on the App Store](https://img.shields.io/badge/iPhone-App%20Store-0D96F6?style=for-the-badge&logo=apple&logoColor=white)](https://apps.apple.com/gb/app/moongate-klipper-control/id6785038887)
[![Get it on Google Play](https://img.shields.io/badge/Android-Google%20Play-34A853?style=for-the-badge&logo=googleplay&logoColor=white)](https://play.google.com/store/apps/details?id=com.moongate.app.moongate)
[![Download Moongate APK](https://img.shields.io/badge/%E2%AC%87%20APK-early%20access-6C63FF?style=for-the-badge&logo=android&logoColor=white)](https://github.com/PEEKYPAUL/Moongate/releases/latest)

**iPhone** - get it on the [App Store](https://apps.apple.com/gb/app/moongate-klipper-control/id6785038887).

**Android** - get it on [Google Play](https://play.google.com/store/apps/details?id=com.moongate.app.moongate) (recommended - stable releases, updated automatically by the store).

**Android early access** - want each release the day it ships? Grab the APK from the [Releases page](https://github.com/PEEKYPAUL/Moongate/releases) instead: enable **Install from unknown sources** for your browser or file manager, then open the APK. From then on it updates itself in-app. It's signed with the same key as the Play build, so you can move between the two channels later without losing your printers.

### 3. Pair

1. Run **`MOONGATE_PAIR`** in the Klipper / Mainsail console.
2. On a device on the **same WiFi as your Pi**, open `http://<your-pi-ip>/moongate-pair.html` - a QR appears.
3. In the app, tap **+ → Scan QR** and point the camera at it. Done - your printer lands on the dashboard.

No working camera? Type the **`GATE-XXXX-XXXX`** code shown in the console instead. And if you opened the pair page on the phone the app is on, just **tap the link under the QR** (v0.9.59+) - the app opens straight into pairing.

> **How quickly does it connect? Scanning the QR is instant.**
> - ✅ **Scan the QR (recommended)** - an **instant local connection**: your printer is on the dashboard in about a second, because the QR hands the app your Pi's local address directly. Remote access over the secure tunnel keeps **building in the background** - you never wait on it.
> - ⚠️ **GATE code** - there's no instant local hand-off, so the printer doesn't appear until the **Cloudflare tunnel** has finished building (that's what carries the connection). Usually under a minute - a little longer right after a Pi reboot. It isn't stuck; give it a moment, or scan the QR for an instant connection.

> Pairing is LAN-only by design: nothing to port-forward, no URL to share. Reinstalling or switching phones? **Back up your config first** - restoring it brings your printers back online without re-pairing. See **[Updating &amp; removing](docs/managing-moongate.md)**.

---

## Run it your way

Moongate gives every printer a choice of two connections - and you can mix them freely on one dashboard.

| | ☁️ Moongate cloud (default) | 🔌 Direct (LAN/VPN) |
|---|---|---|
| Setup | pair once with the QR / GATE code | pick **Direct** when the installer asks, add by QR or address |
| Away from home | automatic - secure tunnel, zero config | through **your own VPN** (WireGuard, Tailscale) |
| Print notifications | ✅ | ❌ (no cloud to send them) |
| What touches the cloud | pairing, a heartbeat, short-lived tokens | **nothing - zero calls, ever** |
| Needs internet | to pair and for the tunnel | **never - works fully offline** |
| Best for | most people - it just works | VPN owners, isolated networks, zero-cloud setups |

Switch an existing printer between modes anytime from its edit dialog - no re-pairing. If you later want a Direct printer on the cloud, re-run the installer normally and pair it; the app absorbs the old tile automatically. Networking notes for Direct mode (Moonraker's `trusted_clients`, give the Pi a fixed address) are in the [LAN-only install section](#quick-start) above.

Direct mode isn't picky about the host, either: from plugin 0.6.17 it needs **zero extra Python packages**, so machines that were never a Raspberry Pi - embedded boards, vendor printers on community firmware - can join the dashboard with a one-file install. See [3rd-party printer support](docs/third-party-printers.md).

---

## How it works

<div align="center">
<img src="docs/how-it-works.svg" width="820" alt="Moongate's two connection routes: route 1, Moongate cloud - the app gets a short-lived signed token from the access broker and reaches the Raspberry Pi over the LAN at home or through Cloudflare's tunnel away, with the Pi's auth proxy admitting only broker-signed requests so a leaked tunnel URL returns only 401s; route 2, Direct - the app talks straight to Moonraker over home WiFi or the user's own WireGuard/Tailscale VPN, gated by trusted_clients, with zero cloud involvement.">
</div>

**Route 1 - Moongate cloud.** Your Pi runs Klipper, Moonraker, the Moongate plugin, and an **auth proxy** that gates everything reachable from the internet. A minimal **access broker** handles anonymous sign-in (no email, no password) and tracks the current tunnel URL; the app fetches a fresh signed token before each request and tries home WiFi first, then the tunnel.

**The headline:** leaking the tunnel URL alone gives an attacker nothing - every path through it returns `401` without revealing what's underneath. Full threat model in [SECURITY.md](SECURITY.md); code-level detail in [ARCHITECTURE.md](ARCHITECTURE.md).

**Route 2 - Direct (LAN/VPN).** No broker, no tunnel, no heartbeats: the app talks straight to Moonraker on your network - or across your own VPN - gated by Moonraker's `trusted_clients`, exactly like Mainsail in a desktop browser. The Pi makes **zero outbound calls** and the whole thing works with no internet at all.

---

## Documentation

| Document | What's inside |
|---|---|
| [Updating &amp; removing](docs/managing-moongate.md) | Updating the app &amp; plugin, reinstalling / moving to a new phone, full uninstall |
| [3rd-party printer support](docs/third-party-printers.md) | Direct (LAN/VPN) mode on non-Pi hosts - the one-file install, supported machines, VPN notes |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Building from source, repo layout, debugging, release signing, CI |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Code structure, state management, data-flow walkthroughs, design decisions |
| [SECURITY.md](SECURITY.md) | Threat model, what the tunnel does and doesn't expose, the empirical verification, vulnerability reporting |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common failure modes - offline tiles, tunnel issues, pairing failures - each with copy-paste diagnostics |
| [CHANGELOG.md](CHANGELOG.md) | Every release with a one-line summary of what changed and why |
| [Privacy policy](https://peekypaul.github.io/Moongate/privacy-policy.html) | What data the app handles and why - anonymous, no analytics, no tracking, no data sold |

> **Building from source?** `cd mobile && flutter pub get && flutter build apk --release --flavor github --dart-define=MOONGATE_CHANNEL=github`. Full developer workflow in [DEVELOPMENT.md](DEVELOPMENT.md).

---

## Buy me a coffee

Moongate is free, source available, and built in my spare time for the Klipper community - no ads, no subscriptions, no data harvesting. If it's earned a spot on your phone, you can buy me a coffee to say thanks. Every contribution goes straight back into the project: test hardware, the cloud service that keeps remote access working, and the time to keep shipping features.

Thank you for being part of it 💜

<p align="center">
  <a href="https://www.paypal.com/donate/?hosted_button_id=WCWAZKQ7WKQB4">
    <img src="https://img.shields.io/badge/%E2%98%95%20Buy%20me%20a%20coffee-Donate-FFDD00?style=for-the-badge" alt="Buy me a coffee"/>
  </a>
</p>

---

## License

**PolyForm Noncommercial License 1.0.0** - see [LICENSE](LICENSE) for the full text.

- ✅ Free to read, build, self-host, modify, and share for **non-commercial** use - including charities, schools, and public / research / government institutions.
- ❌ Selling Moongate, charging for access, or bundling it in a paid product needs a **separate written licence**.

Want to use Moongate commercially? [Open an issue](https://github.com/PEEKYPAUL/Moongate/issues/new) or contact [@PEEKYPAUL](https://github.com/PEEKYPAUL) to discuss terms.

---

<div align="center">
<sub>Created by <a href="https://github.com/PEEKYPAUL">Paul Sharman</a></sub>
</div>
