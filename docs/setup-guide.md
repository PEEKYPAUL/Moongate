# Moongate — Setup Guide

## Prerequisites

### On your Raspberry Pi (printer side)
- Klipper + Moonraker already installed (e.g. via KIAUH or MainsailOS)
- Tailscale installed and connected to your tailnet
- Python 3.9+

### On your development machine (to build the app)
- Windows 10/11, macOS 12+, or Ubuntu 20.04+
- Git
- Flutter SDK ≥ 3.19

### For iOS builds
- macOS with Xcode 15+
- Apple Developer account (free account works for local device testing)

---

## 1 — Install Flutter (Windows)

```powershell
# Download Flutter SDK
# Visit https://docs.flutter.dev/get-started/install/windows
# Or use winget:
winget install Flutter.Flutter

# Add to PATH (if not done automatically):
# C:\flutter\bin

# Verify
flutter doctor
```

Run `flutter doctor` and resolve any issues it lists (Android Studio, Android SDK, etc.).

---

## 2 — Install the Moonraker plugin on the Raspberry Pi

```bash
# SSH into your Pi
ssh pi@<your-pi-tailscale-ip>

# Clone the repo
cd ~
git clone https://github.com/PEEKYPAUL/moongate.git
cd moongate/klipper-plugin

# Run installer
bash install.sh
```

The installer will:
- Copy the `moongate/` Python package to your Moonraker extras folder
- Add `[moongate]` to `moonraker.conf`
- Add the `MOONGATE_PAIR` macro to your `printer.cfg`
- Restart Moonraker

---

## 3 — Configure token expiry (optional)

Edit `~/.config/moongate/config.json` on the Pi:

```json
{
  "default_ttl_days": 30,
  "allow_app_override": true
}
```

- `default_ttl_days`: 1, 7, 30, or `null` (never expire)
- `allow_app_override`: if `true`, the app can request a different TTL at pair time

---

## 4 — Build and run the app

```powershell
cd C:\Projects\moongate\mobile

# Get dependencies
flutter pub get

# Run on a connected Android device (USB debugging on)
flutter run

# Build release APK
flutter build apk --release
```

The APK will be at `mobile/build/app/outputs/flutter-apk/app-release.apk`.

---

## 5 — Pair your phone

1. In Mainsail or KlipperScreen, open the **Macros** panel and run `MOONGATE_PAIR`
   - Or type `MOONGATE_PAIR` in the G-code console
2. A code like `GATE-A3F2-9K1B` and a QR code appear in the console output
3. Open Moongate on your phone
4. Tap **Add Printer** → scan the QR or type the code
5. The app connects, stores the token, and opens the printer interface

---

## Tailscale setup

If Tailscale is not yet installed on your Pi:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

The Moongate app includes its own WireGuard/Tailscale client — you do **not** need to install the Tailscale app on your phone separately.

You will need to provide the app with your Tailscale auth key (generated at https://login.tailscale.com/admin/settings/keys) during first setup.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `MOONGATE_PAIR` not found | Check `printer.cfg` includes the macro block; restart Klipper |
| App says "invalid code" | Codes expire after 10 minutes; run `MOONGATE_PAIR` again |
| VPN won't connect | Check Tailscale auth key is valid; check Pi is online in Tailscale admin |
| Moonraker 403 | Plugin not loaded; check `moonraker.log` and re-run `install.sh` |
