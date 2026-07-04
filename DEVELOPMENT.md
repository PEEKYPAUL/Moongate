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
| **Flutter SDK** | ≥ 3.19 (stable) | <https://docs.flutter.dev/get-started/install> - install via the official installer, not Snap |
| **Android SDK** | API 34+ | Comes with Android Studio. Make sure SDK Platform-Tools and Build-Tools are installed |
| **JDK** | 17 | Android Studio bundles JDK 17 - use that one, not your system JDK |
| **ADB** | latest | Ships with platform-tools. Add `<sdk>/platform-tools/` to your `PATH` |
| **Git** | any modern | For cloning the repo |

Verify everything is reachable:

```bash
flutter doctor -v
adb --version
java -version          # should report 17.x
```

`flutter doctor` should be green on Flutter, Android toolchain, and at least one connected device or emulator before you proceed.

> Windows note: if the Java toolchain complains about `AF_UNIX` sockets, your `TEMP` path probably contains a short-name segment (e.g. `~1`). The repo includes [`run.ps1`](run.ps1) which sets `TEMP=C:\tmp` and pins JDK 17 - use that wrapper instead of plain `flutter` if you hit the issue.

---

## Connecting a phone for debugging

1. On the phone: **Settings → About phone → tap Build Number 7 times** to unlock Developer Options
2. **Settings → Developer options → enable USB debugging**
3. Plug in via USB-C
4. The phone prompts *"Allow USB debugging?"* - tap **Allow** and check *"Always allow from this computer"*
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

The app builds in two **distribution flavors** (added in #178 for the Play Store): `github` (the sideloaded APK for GitHub Releases + KIAUH, which keeps the in-app self-updater) and `play` (the App Bundle for Google Play, which ships **without** the self-updater or `REQUEST_INSTALL_PACKAGES`). Because flavors now exist, `--flavor` is **required** - a bare `flutter build apk` errors with "this app has flavors". Details in [`docs/design/play-flavor-plan.md`](docs/design/play-flavor-plan.md).

```bash
cd mobile
# Sideload / dev APK (self-updating) - this is what you install on a device
flutter build apk --release --flavor github --dart-define=MOONGATE_CHANNEL=github
# Output: build/app/outputs/flutter-apk/app-github-release.apk
adb install -r build/app/outputs/flutter-apk/app-github-release.apk

# Play App Bundle (no self-updater) - CI / work-box only, never sideload it
flutter build appbundle --release --flavor play --dart-define=MOONGATE_CHANNEL=play
# Output: build/app/outputs/bundle/playRelease/app-play-release.aab
```

Release builds are signed with the keystore configured in `mobile/android/key.properties` if present, otherwise they fall back to the debug key. Both flavors share the same key and `applicationId`, so a device moves between the sideload APK and the Play build in place with no wipe. CI uses GitHub Secrets - see [Release signing](#release-signing) below.

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
│   ├── auth/pairing_screen.dart        # /pair - QR scanner + manual code entry
│   ├── dashboard/dashboard_screen.dart # /dashboard - grid + drawer (incl. About section)
│   ├── dashboard/printer_tile.dart     # One card on the dashboard
│   ├── printer/printer_screen.dart     # /printer/:id - WebView with cookie/Bearer auth
│   ├── settings/settings_screen.dart   # /settings
│   ├── settings/custom_theme_screen.dart # /theme/custom - colour editor
│   └── splash/splash_screen.dart
├── models/
│   └── printer_config.dart             # PrinterConfig (persisted) + PrinterStatus (live)
├── providers/                          # Riverpod NotifierProviders
│   ├── settings_provider.dart          # AppThemeMode, app font (kAppFonts), font scale, grid cols, rotation
│   ├── custom_theme_provider.dart      # 5 user-picked colours
│   ├── update_provider.dart            # GitHub release check
│   └── version_provider.dart           # PackageInfo
└── services/                           # No UI; all I/O lives here
    ├── supabase_service.dart           # Cloud middleman - anonymous sign-in, claim/release printer, list-my-printers
    ├── printer_access_cache.dart       # In-memory cache of {tunnel_url, access_token} per printer
    ├── printer_registry.dart           # Persistent printer list + LAN URL / webcam / UI-type updaters
    ├── printer_status_service.dart     # Per-tile 4 s poll loop, LAN-first with reachability probe
    ├── printer_liveness_service.dart    # Realtime + RLS-scoped read of last_seen; gates polling of offline printers (v0.9.16)
    ├── printer_webview_cache.dart       # Keeps each printer's WebView warm; pre-warms all at startup (v0.9.8 / v0.9.15)
    ├── print_control_service.dart      # pause/resume/cancel/firmware_restart/emergency_stop
    ├── print_progress.dart             # shared Mainsail-matching (file-relative) progress calc (v0.9.17)
    ├── ota_installer.dart              # in-app updater: download APK + launch installer (v0.9.17)
    ├── update_service.dart             # /APK/latest_version.json poll
    ├── lan_discovery_service.dart      # mDNS browse for _moongate._tcp Pis (v0.5)
    ├── printer_status_registry.dart    # last live status + LAN-poll outcome per printer
    └── diagnostics_service.dart        # builds the bug-report payload (app/device/network/printers)
```

> **v0.6.3 services & deps.** `supabase_service.dart` also handles backup **restore grants** (`createRestoreGrant` / `redeemRestoreGrant`) and **bug reports** (`submitFeedback`); the report UI is `features/dashboard/feedback_sheet.dart`, reachable from the drawer **and** the pairing screen. New dependency: **`device_info_plus`** (device model + Android version for reports). To read submitted reports without the Supabase dashboard, POST to the **`read-feedback`** Edge Function with header `x-moongate-debug: <MOONGATE_DEBUG_KEY>` - the secret is a Supabase function secret (`supabase secrets set/unset`), never in the repo.

> **v0.6.4-v0.6.5.** `diagnostics_service.dart` now also captures the Pi's **plugin version** (from the `/status` reply, where `moongate_standalone.py` reports `MOONGATE_PLUGIN_VERSION`) and the **remote/tunnel** connection result, not just the LAN outcome. v0.6.5 adds the first-run **"How pairing works"** onboarding - `_maybeShowPairingHelp()` / `_showPairingHelp()` in `dashboard_screen.dart`, shown once on cold launch (a persisted "Don't show again" flag suppresses it) and always reachable from the drawer's **How pairing works** item.

> **v0.9.15-v0.9.16 services & deps.** `printer_webview_cache.dart` gained a **pre-warm** path that loads every printer's WebView in the background at startup (so the first open is instant), and a new `printer_liveness_service.dart` tracks each printer's online/offline state via **Supabase Realtime** on the `printers` table (plus a periodic RLS-scoped read) so the dashboard and the notification service stop requesting access for switched-off printers. A new `onMobileDataProvider` in `providers/settings_provider.dart` drives the connectivity-aware camera feed rate. New dependency: **`connectivity_plus`** (Wi-Fi vs. mobile-data detection). The liveness feature relies on the Realtime migration below being applied to the Supabase project.

> **v0.9.17 services & native.** Two new app services: `print_progress.dart` - a pure helper that computes Mainsail-matching *file position (relative)* progress, now the **single source** for both the dashboard tile and the print notification (they used to disagree) - and `ota_installer.dart`, the in-app updater that streams the release APK to the cache dir with progress then triggers the system installer. The updater adds a native `MethodChannel` (`com.moongate.app/install`) in `MainActivity.kt`, a `FileProvider` + `res/xml/file_paths.xml`, and the `REQUEST_INSTALL_PACKAGES` permission (all now in the **`github` flavor** manifest and gated by `BuildConfig.SELF_UPDATE`, so the Play flavor omits them - #178); it reuses the existing `http` / `path_provider` / `permission_handler` deps (no new package). The post-emergency-stop restart button keys off a new `klippyShutdown` flag on `PrinterStatus`, parsed from Moonraker's `webhooks.state`. Unit test: `mobile/test/print_progress_test.dart`.

For a guided tour of how these pieces fit together, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Running the Pi-side services

For mobile-only work you don't need a Pi - `flutter run` against any printer that already has v0.4 installed is enough.

If you're modifying the Pi side, there are now two parts to be aware of:

| File | What it is | How to reload after changes |
|---|---|---|
| `klipper-plugin/moongate_standalone.py` | The Moonraker plugin (pairing, status aggregation, control, heartbeat) | `sudo systemctl restart moonraker` |
| `klipper-plugin/moongate_authproxy.py` | The auth proxy that gates every tunnel-side request | `sudo systemctl restart moongate-authproxy` |

Both ship from the same repo and are deployed by `install.sh`:

```bash
# On your Pi
git clone https://github.com/PEEKYPAUL/Moongate.git
cd Moongate/klipper-plugin
./install.sh
```

Iteration loop:

```bash
# Edit on your dev machine
nano klipper-plugin/moongate_standalone.py        # or moongate_authproxy.py
git push

# On the Pi
cd ~/moongate && git pull
sudo systemctl restart moonraker                  # if you touched the plugin
sudo systemctl restart moongate-authproxy         # if you touched the proxy

# Tail the relevant log
journalctl -u moonraker -f | grep -i moongate
journalctl -u moongate-authproxy -f
```

To uninstall completely:

```bash
./klipper-plugin/uninstall.sh
```

The uninstaller restores the original `moonraker.conf` from the backup it took during install, removes both systemd units, and wipes `~/.config/moongate/`.

---

## Debugging tips

### App-side: logcat filters

Once an APK is installed and you've reproduced an issue:

```bash
# Get the running app's process ID
PID=$(adb shell pidof com.moongate.app.moongate)

# Stream logs from only the app process
adb logcat --pid=$PID

# Or filter by tag - Moongate uses the "MOONGATE" tag for its own dev.log() calls
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

The plugin logs under the `moonraker.moongate` logger - its messages are prefixed with `moongate` in the log.

### Auth-proxy logs (v0.4+)

```bash
journalctl -u moongate-authproxy -f
```

The proxy logs every request at INFO with the verdict (forwarded / 401), the path, and the cause when 401. Useful for distinguishing "the token is bad" from "the path doesn't match anything".

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
3. `flutter build apk --release --flavor github --dart-define=MOONGATE_CHANNEL=github` (the sideload APK) **and** `flutter build appbundle --release --flavor play --dart-define=MOONGATE_CHANNEL=play` (the Play `.aab`, kept as the `Moongate-play-aab` workflow artifact for a manual Play upload)
4. Publishes the signed github APK as a **GitHub Release asset** (`Moongate-vX.Y.Z.apk`) - it is **not** committed to the repo (the ~73 MB binary tripped GitHub's 50 MB push warning on every push)
5. Generates a fresh `APK/latest_version.json` whose `apk_url` points at that Release asset, for the in-app update banner
6. Commits **only the manifest** with `[skip ci]` and pushes back to `master`

So **the only thing you commit by hand is code + screenshots + docs**. The release APK lands as a Release asset 2-3 minutes after each push; the in-app updater downloads from there.

> **Merging a non-release PR? Quiet-merge it with `[skip ci]`.** The build above runs on *every* push to `master` and rebuilds the APK for whatever `version:` is in `mobile/pubspec.yaml`. Merging a PR that **doesn't** bump the version therefore rebuilds the *current* release and **clobbers its existing Release asset** (`gh release upload --clobber`) - silently replacing the published APK with a fresh build (the `latest_version.json` manifest is left untouched when the build number hasn't changed). For deps / config / Pi-side-only PRs, put `[skip ci]` in the **merge-commit subject** so nothing rebuilds; the changes ride into the next versioned release.

`ci.yml` runs `flutter analyze` and `flutter test` on PRs (unit tests live in `mobile/test/`).

> **The Supabase backend is not part of CI.** Database migrations under [`supabase/migrations/`](supabase/migrations/) and the Edge Functions under [`supabase/functions/`](supabase/functions/) are deployed **manually** against the live project - `supabase db push` for migrations and `supabase functions deploy <name>` for functions - never by GitHub Actions. So a PR that adds a migration (e.g. `20260619120000_printers_realtime.sql`, which enabled Realtime on the `printers` table for v0.9.16) or changes a function (e.g. the access-token TTL in `_shared/accessToken.ts`) only takes effect once it's pushed to Supabase by hand. Full backend setup / deploy flow: [`supabase/README.md`](supabase/README.md).

---

## Bumping a release

1. Edit `mobile/pubspec.yaml`:

   ```yaml
   version: 0.9.X+Y     # X = semver patch, Y = monotonic build number
   ```

2. Add a row to the changelog table in [CHANGELOG.md](CHANGELOG.md) (newest first). User-facing language only - see the existing entries for the tone.

3. Add the version's entry to [`mobile/assets/changelog.json`](mobile/assets/changelog.json) (newest first). This single file feeds **both** the in-app "What's new" dialog (bundled) **and** the update banner's "What's new" overlay (fetched from `master`, so users can preview a pending update's notes before installing). Keep it in step with the CHANGELOG.md row above.

4. Commit and push to `master`. CI does the rest - versioned APK + `latest_version.json` update + commit-back happens automatically.

In-app, users running an older version will see the update banner appear within ~30 s of the next launch.

> Feature branches (anything other than `master`) **do not** trigger CI APK builds. That's intentional - unreleased work doesn't get pulled into the in-app updater.

### Plugin version (Pi side)

The version shown in Mainsail's **Software Update** panel is derived from the repo's git **tags** - the same `vX.Y.Z` release tags CI creates - not from a number the plugin sets, so the panel tracks the project release with nothing extra to bump. (The plugin *does* define a `MOONGATE_PLUGIN_VERSION` constant, but it's reported only in **bug-report diagnostics** to pin down the exact plugin build; it doesn't drive the update panel.)

For this to work the Pi's clone must carry tags. `install.sh` uses a **blobless** clone (`git clone --filter=blob:none`) - full ref/tag history, but without the large historical APK blobs - and converts any old shallow (`--depth=1`) clone on re-run. A shallow clone shows `v0.0.0-…-inferred` instead; see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#software-update-panel-shows-an-inferred-version-for-moongate).

> The CI "keep last 3 releases" prune deletes old tags, but the most recent tag is always an ancestor of `master` HEAD, so version detection on an up-to-date Pi always resolves.

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

- [ARCHITECTURE.md](ARCHITECTURE.md) - how the pieces fit together, data flow diagrams, key design decisions
- [SECURITY.md](SECURITY.md) - auth, transport, threat model, audit references
- [docs/setup-guide.md](docs/setup-guide.md) - end-user setup walkthrough (the friendlier version of [README.md](README.md#quick-start))
