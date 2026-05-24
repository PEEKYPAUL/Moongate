# Development

> Start here if you want to build, run, modify, or debug Moongate.

Moongate has two halves and they're set up independently:

| Half | Language | Where | What it does |
|---|---|---|---|
| **Mobile app** | Flutter (Dart) | `mobile/` | The Android app you install on your phone |
| **Klipper plugin** | Python | `klipper-plugin/` | A single-file Moonraker component that runs on your Pi |

For most code changes you only need to touch the mobile app. The plugin is small and stable.

---

## Quick start (mobile app)

```bash
git clone https://github.com/PEEKYPAUL/Moongate.git
cd Moongate/mobile
flutter pub get
flutter run                # debug build on a connected device/emulator
```

That's it for the app. If your phone is connected via ADB the app installs and launches in ~30 seconds.

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| **Flutter SDK** | ≥ 3.19 (stable) | <https://docs.flutter.dev/get-started/install> — install via the official installer, not Snap |
| **Android SDK** | API 34+ | Comes with Android Studio. Make sure SDK Platform-Tools and Build-Tools are installed |
| **JDK** | 17 | Android Studio bundles JDK 17 — use that one, not your system JDK |
| **ADB** | latest | Ships with platform-tools. Add `<sdk>/platform-tools/` to your `PATH` |
| **Git** | any modern | For cloning the repo |

Verify everything is reachable:

```bash
flutter doctor -v
adb --version
java -version          # should report 17.x
```

`flutter doctor` should be green on Flutter, Android toolchain, and at least one connected device or emulator before you proceed.

> Windows note: if the Java toolchain complains about `AF_UNIX` sockets, your `TEMP` path probably contains a short-name segment (e.g. `~1`). The repo includes [`run.ps1`](run.ps1) which sets `TEMP=C:\tmp` and pins JDK 17 — use that wrapper instead of plain `flutter` if you hit the issue.

---

## Connecting a phone for debugging

1. On the phone: **Settings → About phone → tap Build Number 7 times** to unlock Developer Options
2. **Settings → Developer options → enable USB debugging**
3. Plug in via USB-C
4. The phone prompts *"Allow USB debugging?"* — tap **Allow** and check *"Always allow from this computer"*
5. Verify on the PC:

```bash
adb devices
# Should list your device ID, not "unauthorized"
```

If it says *unauthorized*, redo step 4. If it doesn't appear at all, install the OEM USB driver (Samsung / Google / etc.) on your PC.

---

## Running the app

### Debug build (fastest iteration)

```bash
cd mobile
flutter run                          # picks the first connected device
flutter run -d <device-id>           # if multiple devices are connected
```

Debug builds are unsigned, slower, and have hot-reload. Press `r` in the terminal to hot-reload after a code change, `R` to hot-restart.

### Release build (production-equivalent)

```bash
cd mobile
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Release builds are signed with the keystore configured in `mobile/android/key.properties` if present, otherwise they fall back to the debug key. CI uses GitHub Secrets — see [Release signing](#release-signing) below.

> The QR scanner only works in **release** builds with the ProGuard rules in [`mobile/android/app/proguard-rules.pro`](mobile/android/app/proguard-rules.pro). Debug builds work fine too; R8 doesn't run in debug.

### Specific entry points

The router lives in [`mobile/lib/app.dart`](mobile/lib/app.dart). Known routes:

| Route | Screen |
|---|---|
| `/splash` | App launch animation (2 s) |
| `/dashboard` | Printer grid (the home screen after splash) |
| `/pair` | Add-a-printer flow with QR scanner |
| `/printer/:id` | Embedded Mainsail / Fluidd WebView for one printer |
| `/settings` | Sign-out page |
| `/theme/custom` | Custom-theme colour editor |

---

## Where the code lives

```
mobile/lib/
├── main.dart                   # Bootstraps providers, loads persisted state, runApp()
├── app.dart                    # MoongateApp + GoRouter + theme builders
├── features/
│   ├── auth/pairing_screen.dart        # /pair — QR scanner + manual code entry
│   ├── dashboard/dashboard_screen.dart # /dashboard — grid + drawer
│   ├── dashboard/printer_tile.dart     # One card on the dashboard
│   ├── printer/printer_screen.dart     # /printer/:id — WebView
│   ├── settings/settings_screen.dart   # /settings — sign out
│   ├── settings/custom_theme_screen.dart # /theme/custom — colour editor
│   └── splash/splash_screen.dart
├── models/
│   └── printer_config.dart             # PrinterConfig (persisted) + PrinterStatus (live)
├── providers/                          # Riverpod NotifierProviders
│   ├── settings_provider.dart          # AppThemeMode, font scale, grid cols, rotation
│   ├── custom_theme_provider.dart      # 5 user-picked colours
│   ├── update_provider.dart            # GitHub release check
│   └── version_provider.dart           # PackageInfo
└── services/                           # No UI; all I/O lives here
    ├── auth_service.dart               # Pair-code exchange, JWT secure storage
    ├── printer_registry.dart           # Persistent printer list + session live state
    ├── printer_status_service.dart     # Per-tile 4 s poll loop (Moongate + native)
    ├── print_control_service.dart      # pause/resume/cancel/firmware_restart
    ├── network_discovery_service.dart  # Subnet check, LAN scan
    ├── moonraker_service.dart          # WebSocket client (not yet used in UI)
    ├── update_service.dart             # /APK/latest_version.json poll
    └── vpn_service.dart                # Stub — see SECURITY.md
```

For a guided tour of how these pieces fit together, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Running the Klipper plugin

For mobile-only work you don't need a Pi — `flutter run` against any printer that already has the plugin installed is enough.

If you're modifying the plugin itself:

```bash
# On your Pi
git clone https://github.com/PEEKYPAUL/Moongate.git
cd Moongate/klipper-plugin
./install.sh                          # one-line install (does everything: symlink + cloudflared + restart)

# After plugin changes, restart Moonraker to pick them up:
sudo systemctl restart moonraker
```

The plugin is single-file ([`moongate_standalone.py`](klipper-plugin/moongate_standalone.py)), so iteration is fast:

```bash
# Edit the plugin
nano klipper-plugin/moongate_standalone.py
# Push changes
git push
# On the Pi
cd ~/moongate && git pull && sudo systemctl restart moonraker
# Tail the log to see plugin logs
journalctl -u moonraker -f | grep -i moongate
```

To uninstall completely:

```bash
./klipper-plugin/uninstall.sh
```

---

## Debugging tips

### App-side: logcat filters

Once an APK is installed and you've reproduced an issue:

```bash
# Get the running app's process ID
PID=$(adb shell pidof com.moongate.app.moongate)

# Stream logs from only the app process
adb logcat --pid=$PID

# Or filter by tag — Moongate uses the "MOONGATE" tag for its own dev.log() calls
adb logcat -s MOONGATE

# Camera issues
adb logcat | grep -iE "(MobileScanner|CameraX|camera|bindToLifecycle)"
```

For non-fatal Flutter errors (red overlay in debug, console in release):

```bash
flutter logs                          # picks the connected device
```

### Plugin-side: Moonraker logs

```bash
journalctl -u moonraker -f
# Or directly:
tail -f ~/printer_data/logs/moonraker.log
```

The plugin logs under the `moonraker.moongate` logger — its messages are prefixed with `moongate` in the log.

### Tunnel-side: cloudflared logs

```bash
journalctl -u moongate-tunnel -f
# Plus the captured stdout (this is where the tunnel URL appears):
tail -f /run/moongate-tunnel.log
```

---

## Release signing

For local *debug* and *unsigned release* builds nothing is needed.

For builds that are install-compatible with the official APKs (same signing key), you need both files in `mobile/android/`:

```
mobile/android/key.properties       # path/passwords; gitignored
mobile/android/app/moongate-release.jks   # keystore; gitignored
```

The CI pipeline ([`.github/workflows/build-android.yml`](.github/workflows/build-android.yml)) reconstructs both from GitHub Secrets on every push and signs the APK consistently. Locally-built release APKs use the debug key by default, which means installing them over a CI-signed APK requires uninstalling first (signature mismatch). This is a one-time inconvenience while iterating; CI-signed builds always replace cleanly.

---

## CI / CD

`.github/workflows/build-android.yml` runs on every push to `master`:

1. Sets up Flutter stable + JDK 17
2. Decodes the keystore from Secrets and writes `key.properties`
3. `flutter build apk --release`
4. Copies the APK to `APK/Moongate-vX.Y.Z.apk` (versioned) and `APK/Moongate-latest.apk`
5. Generates a fresh `APK/latest_version.json` for the in-app update banner
6. Commits with `[skip ci]` to avoid recursion and pushes back to `master`

So **the only thing you commit by hand is code + screenshots + docs**. APKs land 2–3 minutes after each push.

`ci.yml` runs `flutter analyze` and `flutter test` on PRs.

---

## Bumping a release

1. Edit `mobile/pubspec.yaml`:

   ```yaml
   version: 0.2.X+Y     # X = semver patch, Y = monotonic build number
   ```

2. (Optional) Add a row to the changelog table in [README.md](README.md)

3. Commit and push. CI does the rest — versioned APK + `latest_version.json` update + commit-back happens automatically.

In-app, users running an older version will see the update banner appear within ~30 s of the next launch.

---

## Coding conventions

| Topic | Rule |
|---|---|
| **Dart lints** | `flutter_lints` (see `mobile/analysis_options.yaml`). `flutter analyze` must be clean before push |
| **Folder structure** | Feature-first: `lib/features/<area>/<screen>.dart`. Shared cross-feature code goes in `lib/services/` or `lib/providers/` |
| **State management** | Riverpod `NotifierProvider`. Avoid `StatefulWidget` for app-wide state |
| **Colour API** | `withValues(alpha: 0.5)`, **not** the deprecated `withOpacity()` |
| **Python** | PEP 8, type hints on public functions, zero runtime deps beyond what Moonraker already pulls in |
| **Commits** | Conventional prefixes: `feat:`, `fix:`, `docs:`, `release:`, `chore:`. Bodies wrap at ~72 cols |
| **Pushes** | Push often. CI is the source of truth for the released APK |

---

## Where to next

- [ARCHITECTURE.md](ARCHITECTURE.md) — how the pieces fit together, data flow diagrams, key design decisions
- [SECURITY.md](SECURITY.md) — auth, transport, threat model, audit references
- [docs/setup-guide.md](docs/setup-guide.md) — end-user setup walkthrough (the friendlier version of [README.md](README.md#setup))
