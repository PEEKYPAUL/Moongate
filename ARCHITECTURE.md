# Architecture

> How the pieces fit together. Read [DEVELOPMENT.md](DEVELOPMENT.md) first if you haven't set up the project yet.

---

## 30-second overview

Moongate is two artefacts that talk to each other over HTTP:

```
┌─────────────────────┐    LAN HTTP (preferred)    ┌──────────────────────┐
│   Moongate App      │◄──────────────────────────►│  Klipper Pi          │
│   (Flutter/Android) │                            │  ├─ Moonraker        │
│                     │   Cloudflare HTTPS tunnel  │  ├─ Moongate plugin  │
│                     │◄──────────────────────────►│  └─ cloudflared      │
└─────────────────────┘     (fallback / remote)    └──────────────────────┘
```

The mobile app polls the Pi every 4 seconds, displays the status, and proxies print-control commands. The plugin authenticates each request with a JWT, talks to Klipper through Moonraker's existing APIs, and answers.

No Moongate server exists. Cloudflare provides only TLS termination and a public DNS name for your Pi.

---

## The mobile app

### Process tree

```
MoongateApp                    (lib/app.dart — root widget, lifecycle observer)
├─ ProviderContainer           (Riverpod — global app state)
│   ├─ themeModeProvider       (AppThemeMode: system/dark/light/custom)
│   ├─ customThemeProvider     (5 user-picked colours; persisted as JSON)
│   ├─ fontScaleProvider       (0.8 – 1.4)
│   ├─ gridColumnsProvider     (1 / 2 / 3)
│   ├─ allowRotationProvider   (bool; pins SystemChrome orientations)
│   ├─ updateProvider          (one-shot GitHub release check)
│   └─ appVersionProvider      (PackageInfo lookup)
└─ GoRouter
    ├─ /splash      → SplashScreen
    ├─ /dashboard   → DashboardScreen → many PrinterTile widgets
    ├─ /pair        → PairingScreen
    ├─ /printer/:id → PrinterScreen (WebView)
    ├─ /settings    → SettingsScreen
    └─ /theme/custom → CustomThemeScreen
```

### State and persistence

| State | Where it lives | Persisted? | How |
|---|---|---|---|
| Printer list | `PrinterRegistry` (singleton) | Yes | `SharedPreferences` key `moongate_printers` (JSON) |
| JWT tokens | `AuthService` | Yes | `flutter_secure_storage` → Android Keystore |
| Theme mode | `themeModeProvider` | Yes | `SharedPreferences` key `theme_mode` |
| Custom theme | `customThemeProvider` | Yes | `SharedPreferences` key `custom_theme` (JSON of 5 HEX strings) |
| Font scale / grid cols / rotation | `settings_provider.dart` | Yes | One `SharedPreferences` key each |
| Per-printer "live preferRemote" | `PrinterRegistry._livePreferRemote` | **No** (session only) | In-memory `Map<String, bool>` |
| Per-printer connection candidate order | `PrinterStatusService._preferRemote` | **No** (session only) | Field on the service instance |
| Probe phase (local/tunnel/offline) | `PrinterStatusService._probeController` | **No** | Stream consumed by the tile |
| Detected web UI type | `PrinterStatusService._uiType` | **No** (per session) | Field; cached after first successful page sniff |

The "session only" entries are intentional — see [Key design decisions](#key-design-decisions) below.

### The service layer

The `services/` directory has zero UI. Each file is a focused capability:

| File | Responsibility |
|---|---|
| `printer_status_service.dart` | The heart of the app. One instance per printer tile. Polls every 4 s. Tries the Moongate plugin endpoint first, falls back to native Moonraker, falls back to tunnel. Discovers the chamber sensor key once, detects whether the printer runs Mainsail or Fluidd, fetches slicer file metadata for accurate progress |
| `print_control_service.dart` | Sends `pause` / `resume` / `cancel` / `firmware_restart` actions. Same dual-endpoint strategy as the status service |
| `auth_service.dart` | Pair-code exchange (`POST /server/moongate/auth`), JWT storage, direct-token persistence for the QR pairing path |
| `printer_registry.dart` | Persistent printer list + the in-session `_livePreferRemote` map + `refreshNetworkLocality()` (called from `main` and on app resume) |
| `network_discovery_service.dart` | Two unrelated helpers: subnet check (`isOnSameSubnetAs`) used by the locality refresh, and the LAN scanner used by the "Find printer on this network" button in pairing |
| `update_service.dart` | One-shot GitHub `latest_version.json` fetch on app launch |
| `moonraker_service.dart` | WebSocket client — present but not yet wired into the UI; reserved for future real-time push of status events |
| `vpn_service.dart` | Phase-2 stub for WireGuard. Registers an Android `VpnService` so the OS shows the VPN icon, but does not establish a tunnel. See [SECURITY.md](SECURITY.md) |

### Android native side

Most of the app is pure Dart, but a few things need Kotlin:

```
mobile/android/app/src/main/
├── AndroidManifest.xml              # CAMERA, INTERNET, FOREGROUND_SERVICE, VPN service decl
├── kotlin/com/moongate/app/
│   ├── moongate/MainActivity.kt     # FlutterFragmentActivity + bindToWifi MethodChannel
│   ├── VpnPlugin.kt                 # Bridges Dart's VpnService → MoongateVpnService
│   └── MoongateVpnService.kt        # The stub — see SECURITY.md
└── app/proguard-rules.pro           # R8 keep-rules for ML Kit + mobile_scanner + CameraX
```

Two things to know:

- **`MainActivity` extends `FlutterFragmentActivity`** (not the default `FlutterActivity`). CameraX requires the activity to be a `LifecycleOwner` and `FragmentActivity` provides that. Switching this fixed an earlier camera-binding crash on first launch (see the changelog entry for v0.2.4).
- **`MainActivity` registers a `network` MethodChannel** that lets Dart bind the process's outgoing sockets to the WiFi network specifically (`bindProcessToNetwork`). This dodges Android's Smart Network Switch sending `192.168.x.x` requests over mobile data and getting `EHOSTUNREACH`. Used only by `AuthService` during pairing — the rest of the app routes naturally.

---

## The Klipper plugin

Single file: [`klipper-plugin/moongate_standalone.py`](klipper-plugin/moongate_standalone.py). It's deployed to `~/moonraker/moonraker/components/moongate.py` via a symlink so Moonraker's auto-discovery picks it up. Three top-level classes:

```python
class AuthManager:           # Pairing codes + JWT issuance/verification + token persistence
class WireGuardManager:      # Pi-side WireGuard peer add/remove + config generation (Phase 2)
class MoongatePlugin:        # Moonraker component — registers HTTP endpoints, glues the two together
```

### HTTP endpoints (all under `/server/moongate/`)

| Endpoint | Method | Auth | What it does |
|---|---|---|---|
| `/pair` | POST | none | Generate a pairing session; returns `{code, qr_payload, local_url, tunnel_url, expires_in_seconds}` |
| `/auth` | POST | code | Exchange a pairing code for a JWT. Body: `{code, device_name, ttl_days?, wg_pubkey?}` |
| `/qr` | GET | none | Return the most-recent QR URL for the pair page to render |
| `/status` | GET | JWT | Aggregate status: print_stats, extruder, heater_bed, chamber sensor, tunnel URL, webcam settings |
| `/control` | POST | JWT | Print control: `pause` / `resume` / `cancel` / `firmware_restart` |
| `/tokens` | GET | JWT | List all issued tokens for this device's owner |
| `/revoke` | POST | JWT | Revoke a token by `token_id` |
| `/pair-page` | GET | none | Serve `moongate-pair.html` directly (bypasses needing it in the web root) |

The pair-code endpoints (`/pair`, `/auth`, `/qr`) are intentionally unauthenticated — they *are* the auth bootstrap. They're protected by the pair-code's own short lifetime, single-use property, and attempt limit. See [SECURITY.md](SECURITY.md#pairing-flow) for the full guarantee.

### Where state lives on the Pi

```
~/.config/moongate/
├── secret.key       # 32 bytes from os.urandom(), mode 0600 — the JWT signing key
├── tokens.json      # List of DeviceToken records (id, device_name, issued_at, expires_at, revoked)
├── config.json      # Tunable values: pair_code_ttl_seconds, default_ttl_days, max_pair_attempts
└── peers.json       # Phase 2: WireGuard peer device_id → pubkey + vpn_ip
```

Plus a few system files:

```
/etc/systemd/system/moongate-tunnel.service   # cloudflared as a systemd unit
/etc/wireguard/wg0.conf                       # Phase 2 only; not used in current shipping path
/run/moongate-tunnel.log                      # cloudflared stdout — the tunnel URL appears here
```

### The QR pair page

[`klipper-plugin/moongate-pair.html`](klipper-plugin/moongate-pair.html) is rendered with an inlined copy of `qrcode.js` so it works with no internet at the moment of pairing. The page fetches `/server/moongate/qr` on load, draws the QR, and exposes an `Open in Moongate App` deep link button.

The page is auto-deployed by the installer to whichever of `~/printer_data/www`, `~/mainsail`, `~/fluidd`, or `/var/www/html` exists first.

---

## CI / build pipeline

`.github/workflows/build-android.yml`:

```
push to master
  ├─ checkout
  ├─ setup-java@v4 (Temurin 17)
  ├─ setup-flutter@v2 (stable channel)
  ├─ flutter pub get
  ├─ Decode the keystore from GitHub Secrets → key.properties
  ├─ flutter build apk --release
  ├─ Copy APK to APK/Moongate-v<X.Y.Z>.apk and APK/Moongate-latest.apk
  ├─ Regenerate APK/latest_version.json with current version + build_number
  └─ git commit + push  →  "Release Moongate-vX.Y.Z [skip ci]"
```

The `[skip ci]` suffix prevents the commit-back from re-triggering CI. The in-app update banner ([`UpdateService`](mobile/lib/services/update_service.dart)) polls `latest_version.json` on launch and shows the banner if the remote `build_number` exceeds the installed one.

---

## Data flow walkthroughs

### Pairing (QR path)

1. User runs `MOONGATE_PAIR` in Klipper console → registered as a Moonraker remote method → plugin's `_klipper_generate_pair_code()` fires
2. Plugin generates an 8-digit code (`GATE-1234-5678`), pre-issues a JWT, and builds a `moongate://pair?local=IP:80&remote=https://x.trycloudflare.com&token=JWT` URL
3. Plugin pushes the code + a clickable pair-page URL back to the console via `M118` commands
4. User opens the pair page on a PC; browser fetches `/server/moongate/qr` → renders the QR
5. User opens Moongate app → tap **+** → **Scan QR** → camera reads the URL → app extracts `token`, `local`, `remote` from the query params and calls `AuthService.persistDirect()` to store them
6. No round-trip to the Pi was needed during step 5. The first actual request happens when the dashboard tile starts polling

### Pairing (manual code path)

If the user can't scan the QR (no PC, no camera), they type the `GATE-XXXX-XXXX` code into the app:

1. Same `MOONGATE_PAIR` step as above
2. User enters the code in the app along with the local IP (or tunnel URL)
3. App `POST /server/moongate/auth` with `{code, device_name}`
4. Plugin verifies the code (TTL, attempts, not-yet-used) → issues a JWT → returns it
5. App stores the JWT in `flutter_secure_storage` and adds the printer to the registry

### Status poll (every 4 s per tile)

1. `PrinterStatusService._doPoll()` picks the candidate order based on `_preferRemote` (in-session) or the registry's `_livePreferRemote` (set by the subnet check)
2. For each candidate URL:
   - Try `GET /server/moongate/status?mg_token=...` (rich endpoint)
   - If that fails, fall back to the native Moonraker `GET /printer/objects/query?print_stats&extruder&heater_bed&display_status&virtual_sdcard&<chamber_key>` — progressively dropping objects until one returns 200, to cope with printers that don't have a heated bed, display, etc.
3. If `state == 'printing'` and the filename changed, fetch `/server/files/metadata?filename=...` once and cache `estimated_time` — used for the progress percentage (matches Mainsail's calculation)
4. Emit a `PrinterStatus` on the controller's stream
5. The tile widget rebuilds with new temps, progress, webcam tick

### Print control

1. Tile button → `PrintControlService.sendAction('pause')`
2. Same candidate ordering as the status service
3. Try `POST /server/moongate/control?mg_token=...&action=pause` first; fall back to native `POST /printer/print/pause`
4. Return `true` as soon as anything answers 200

### Tunnel URL rotation

`cloudflared` quick tunnels get a new URL on every restart. To make this transparent:

- The plugin's `/status` response always includes the *currently active* tunnel URL (read live from cloudflared's metrics endpoint or its log)
- The app compares the returned URL against the stored one on every successful poll. If different, it emits on `tunnelUrlUpdates`, the webcam image starts using the new URL within the same session, and `PrinterRegistry.updateRemoteHost()` persists it for next launch
- Result: no re-pairing needed when the Pi reboots

---

## Key design decisions

### Local-first, tunnel-fallback (with a subnet shortcut)

The status service tries the local IP first because LAN is faster and free. But on a foreign network the local IP is unreachable, so the 3 s timeout would be wasted.

The fix is two-layered:

1. **Subnet check at cold launch and on resume** (`PrinterRegistry.refreshNetworkLocality()`) — compares the phone's WiFi subnet to each printer's local IP subnet. If they don't match, set `_livePreferRemote = true` *before any HTTP request*, so the first poll goes straight to the tunnel.
2. **Per-poll feedback** — after every successful poll, the status service updates `_livePreferRemote` to whatever just worked. So the order self-corrects within seconds even if the subnet check was wrong.

### Session-only `preferRemote`, not persisted

Earlier versions persisted the "tunnel preferred" flag. This caused a frustrating bug: visit a friend → app correctly switches to tunnel → flag gets persisted → come home → app still tries tunnel first → wastes time on every poll until a tunnel timeout finally lets local win.

The current design is: cold-launch always assumes home, and the in-session preference adapts within the first poll cycle. The subnet bootstrap in `main.dart` short-circuits the foreign-network case so users don't see any cost.

### Custom theme builds a `ColorScheme` from a single seed + overrides

Instead of forcing users to pick 20+ Material 3 colour slots, the editor exposes 5 conceptual slots (accent, background, surface, text, error). The app builds a full `ColorScheme.fromSeed(accent)` to get harmonious tertiary/container colours, then overrides the 5 slots with the user's picks.

Brightness is auto-derived from the page-background luminance, so the user doesn't need to also pick "is this a light or dark theme".

### Per-tile, not per-app, status polling

Each `PrinterTile` owns its own `PrinterStatusService`. They poll independently. This means:
- Adding/removing a printer doesn't stall the others
- A timing-out printer doesn't slow the dashboard refresh of nearby ones
- One offline printer doesn't poison the connection state of the others

It costs N parallel HTTP loops where N is the number of printers, but that's fine — typical N is 1–3, and the polls are 4 seconds apart.

### Plugin is a single file, no external Python deps

The plugin runs inside Moonraker's process and has access to anything Moonraker depends on. By staying within that surface (stdlib + Moonraker's existing deps) installation reduces to "copy one file and restart Moonraker". No virtualenvs, no `pip install`, no breakage when Moonraker updates.

JWT signing is implemented directly (`hmac.new(secret, payload, sha256)`) for the same reason — would have needed `PyJWT` otherwise.

---

## Where to next

- [SECURITY.md](SECURITY.md) — auth, transport, threat model, what we defend and don't
- [DEVELOPMENT.md](DEVELOPMENT.md) — practical setup, running, building, debugging
- [docs/setup-guide.md](docs/setup-guide.md) — end-user perspective
