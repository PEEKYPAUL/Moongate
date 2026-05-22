# Moongate — Flutter App

Android app for remotely controlling a Klipper 3D printer over local WiFi or Cloudflare tunnel.

## Building

```bash
flutter pub get
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

## Running in development

```bash
flutter pub get
flutter run   # connects to a USB-attached Android device
```

## Structure

```
lib/
├── main.dart
├── app.dart
├── features/
│   ├── auth/        # Pairing flow — QR scanner, manual code entry
│   ├── dashboard/   # Dashboard screen and PrinterTile widget
│   ├── printer/     # Full Mainsail WebView (per-printer screen)
│   └── settings/    # App settings
├── models/
│   └── printer_config.dart   # PrinterConfig, PrinterStatus, PrinterConnection
└── services/
    ├── printer_status_service.dart   # Per-tile status polling (local-first, tunnel fallback)
    ├── print_control_service.dart    # pause / resume / cancel / firmware_restart
    ├── printer_registry.dart         # Persistent list of paired printers
    └── moonraker_service.dart        # WebSocket client
```

See the root [README](../README.md) and [docs/](../docs/) for full setup instructions.
