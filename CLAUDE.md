# Moongate — Claude Code Project Guide

## What this project is

Moongate is a free, open-source Android app for remotely controlling a Klipper 3D printer over local WiFi or Cloudflare Quick Tunnel. No VPN, no Tailscale, no subscriptions.

It has two parts:
- **Moongate App** — Flutter/Android app (dashboard with webcam tiles, print controls, full Mainsail WebView)
- **Moongate Plugin** — Python Moonraker component that runs on the Pi (handles pairing, JWT auth, status/control proxy, Cloudflare tunnel management)

## Repository layout

```
moongate/
├── mobile/                  # Flutter app (Dart)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart
│   │   ├── features/
│   │   │   ├── auth/        # Pairing flow, QR scanner, code entry
│   │   │   ├── dashboard/   # Dashboard screen, PrinterTile widget
│   │   │   ├── printer/     # Printer screen (Mainsail WebView)
│   │   │   └── settings/    # App settings
│   │   ├── services/
│   │   │   ├── printer_status_service.dart   # Per-tile status polling
│   │   │   ├── print_control_service.dart    # pause/resume/cancel/firmware_restart
│   │   │   ├── printer_registry.dart         # Persistent printer list
│   │   │   └── moonraker_service.dart        # WebSocket client
│   │   └── models/
│   │       └── printer_config.dart           # PrinterConfig, PrinterStatus, PrinterConnection
│   └── pubspec.yaml
├── klipper-plugin/
│   ├── moongate_standalone.py   # Single-file Moonraker plugin (what install.sh deploys)
│   ├── moongate-pair.html       # QR pairing page (deployed to Mainsail web root)
│   ├── install.sh               # One-line installer for the Pi
│   └── moongate/                # Multi-file plugin variant (development)
├── APK/                         # Pre-built APKs for direct download
├── docs/
│   ├── architecture.md
│   ├── setup-guide.md
│   └── security.md
└── .github/workflows/
    ├── ci.yml             # flutter analyze + test on push to master
    └── build-android.yml  # builds debug APK artifact on push to master
```

## Key architecture decisions

- **Network strategy**: Local IP first (fast at home), automatic fallback to Cloudflare Quick Tunnel. Each printer tile is fully independent — probes its own IPs/tunnel separately.
- **Status polling**: `PrinterStatusService` polls every 4 s. Tries Moongate plugin endpoint first; falls back to native Moonraker object-query API so tiles work even without the plugin.
- **Print controls**: Same dual-endpoint strategy — Moongate control endpoint first, then native Moonraker (`/printer/print/pause` etc.).
- **Tunnel URL rotation**: `cloudflared` generates a new URL on each restart. The plugin injects the current URL into every status response; the app detects changes and persists the fresh URL.
- **Pairing**: `MOONGATE_PAIR` G-code macro → plugin generates `GATE-XXXX-XXXX` code + QR payload → shown in Klipper console and on `moongate-pair.html` → app scans and exchanges for a JWT.
- **Connection indicator**: Green bar + "Local" = local WiFi. Orange bar + "Tunnel" = Cloudflare tunnel.

## Development prerequisites

- Flutter SDK ≥ 3.19 (stable channel)
- Android Studio or VS Code with Flutter/Dart extensions
- `gh` CLI authenticated as PEEKYPAUL for GitHub operations

## Autonomy — when to ask vs just do it

**Never ask for confirmation on:**
- Editing or creating any source file (Dart, Python, YAML, JSON, shell, HTML, etc.)
- Running `flutter pub get`, `flutter analyze`, `flutter build`
- Git commits and `git push`
- Any reversible code or config change

**Do ask before:**
- Deleting files permanently (`rm -rf`, `del /f`, etc.)
- Force-pushing to a branch that already has history (`git push --force`)
- Running `git reset --hard` that would discard local work
- Any command that physically can't be undone and could cause data loss

Default mode: **make the change, then tell the user what was done.**

## Coding conventions

- Dart: follow `flutter_lints` rules, feature-first folder structure, `withValues(alpha:)` not `withOpacity()`
- Python: PEP 8, type hints on public functions, no external dependencies beyond what Moonraker ships
- Commit often and push; CI runs `flutter analyze` + `flutter test` on every push to `master`

## GitHub

Repo: https://github.com/PEEKYPAUL/moongate  
Branch: `master` (not `main`)  
Push all changes to `master` unless working on a feature branch. Keep the remote in sync.
