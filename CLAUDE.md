# Moongate — Claude Code Project Guide

## What this project is
Moongate is a single mobile app (Flutter, Android + iOS) that combines:
- An embedded Tailscale/WireGuard VPN (connect on open, disconnect on close, no persistent notification beyond the OS VPN status bar icon)
- A Mainsail/Fluidd-equivalent interface for controlling a Klipper 3D printer over Moonraker's WebSocket API
- A secure pairing/handshake system with user-controlled token expiry

It replaces the two-app workflow of Mobileraker + Tailscale with a single integrated app.

## Repository layout
```
moongate/
├── mobile/                  # Flutter app (Dart)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart
│   │   ├── features/
│   │   │   ├── auth/        # Pairing handshake, token storage
│   │   │   ├── printer/     # Moonraker WebSocket, printer UI
│   │   │   ├── vpn/         # WireGuard/Tailscale platform channels
│   │   │   └── settings/    # App config, token expiry
│   │   ├── services/        # Moonraker, VPN, auth singletons
│   │   ├── models/          # Dart data classes
│   │   └── widgets/         # Shared UI components
│   └── pubspec.yaml
├── klipper-plugin/          # Moonraker plugin (Python 3)
│   ├── moongate/
│   │   ├── __init__.py
│   │   ├── moongate_plugin.py   # Moonraker component, REST endpoints
│   │   └── auth_manager.py      # Token generation, expiry, validation
│   └── install.sh
├── docs/
│   ├── architecture.md
│   ├── setup-guide.md
│   └── security.md
└── .github/workflows/ci.yml
```

## Key architecture decisions
- **VPN layer**: Android VpnService + WireGuard-Go via platform channel; iOS NetworkExtension + WireGuard-Go. App lifecycle hooks disconnect the tunnel when the app is backgrounded/closed.
- **Printer UI**: Phase 1 = WebView pointing at local Mainsail/Fluidd. Phase 2 = native Flutter widgets consuming Moonraker WebSocket directly.
- **Pairing flow**: Run `MOONGATE_PAIR` macro in Klipper → plugin generates a short-lived alphanumeric code + QR payload → printed to Moonraker console → user enters in app → app exchanges for a JWT with configurable TTL.
- **Token expiry**: Stored in `~/.config/moongate/tokens.json` on the Pi. Configurable 1 day / 7 days / 30 days / never (user sets in app settings).

## Development prerequisites
- Flutter SDK ≥ 3.19 (see docs/setup-guide.md for install instructions)
- Android Studio or VS Code with Flutter/Dart extensions
- Python 3.9+ on the Raspberry Pi for the Moonraker plugin
- `gh` CLI authenticated as PEEKYPAUL for GitHub operations

## Autonomy — when to ask vs just do it

**Never ask for confirmation on:**
- Editing or creating any source file (Dart, Python, YAML, JSON, etc.)
- Deploying files to the Pi via pscp/plink
- Restarting Moonraker or other Pi services
- Running `flutter run`, `flutter build`, `flutter pub get`
- Git commits, git push
- Any reversible code or config change

**Do ask before:**
- Deleting files permanently (`rm -rf`, `del /f`, etc.)
- Force-pushing to a branch that already has history (`git push --force`)
- Running `git reset --hard` that would discard local work
- Any command that physically can't be undone and could cause data loss
- Anything that costs real money or changes account credentials

Default mode: **make the change, then tell the user what was done.**
No "shall I proceed?", no "is that OK?", no listing steps then waiting for approval.
Just do it.

## Coding conventions
- Dart: follow `flutter_lints` rules, feature-first folder structure
- Python: PEP 8, type hints on all public functions, no external dependencies beyond what Moonraker already ships
- Commit often and push; CI runs `flutter analyze` and `flutter test` on every push

## GitHub
Repo: https://github.com/PEEKYPAUL/moongate
Push all changes to main unless working on a feature branch. Keep the remote in sync.
