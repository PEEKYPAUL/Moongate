# Architecture

> How the pieces fit together. Read [DEVELOPMENT.md](DEVELOPMENT.md) first if you haven't set up the project yet.

---

## 30-second overview

Moongate is three layers that talk to each other over HTTP. The diagram in the [README's "How it works"](README.md#how-it-works) section shows the same thing in slightly more user-friendly language; this one labels the parts the way the code does.

```
                       ┌──────────────────────────┐
                       │   Cloud middleman        │   anonymous identity,
                       │   (identity & lookup)    │   per-request token issuance,
                       └─────────────┬────────────┘   "where is my printer right now"
                                     │
                                     │ short-lived access token
                                     ▼
   ┌────────────────────┐                   ┌──────────────────────────────┐
   │  Moongate App      │◄──── LAN ────────►│  Raspberry Pi                │
   │  (Flutter/Android) │      (preferred)  │   ┌─ Klipper + Moonraker     │
   │                    │◄── Cloudflare ───►│   ┌─ Moongate plugin         │
   │                    │   tunnel (away)   │   └─ Auth proxy ─── gates    │
   └────────────────────┘                   │      every tunnel-side       │
                                             │      request behind a token  │
                                             └──────────────────────────────┘
```

There is no Moongate-operated print server. The cloud middleman is intentionally minimal - it knows enough to tell the app where the printer is right now and to issue a signed access token, and nothing about your prints, your G-code, your camera, or what's on the bed.

---

## The mobile app

### Process tree

```
MoongateApp                    (lib/app.dart - root widget, lifecycle observer)
├─ ProviderContainer           (Riverpod - global app state)
│   ├─ themeModeProvider       (AppThemeMode: system/dark/light/custom)
│   ├─ customThemeProvider     (5 user-picked colours; persisted as JSON)
│   ├─ fontScaleProvider       (0.8 - 1.4)
│   ├─ appFontProvider         (selected bundled font id; 36-option picker)
│   ├─ gridColumnsProvider     (1 / 2 / 3)
│   ├─ allowRotationProvider   (bool; pins SystemChrome orientations)
│   ├─ updateProvider          (one-shot GitHub release check)
│   └─ appVersionProvider      (PackageInfo lookup)
└─ GoRouter
    ├─ /splash       → SplashScreen
    ├─ /dashboard    → DashboardScreen → many PrinterTile widgets
    ├─ /pair         → PairingScreen
    ├─ /printer/:id  → PrinterScreen (WebView, kept warm by PrinterWebViewCache)
    ├─ /lighting     → LightingScreen (per-printer light setup)
    ├─ /settings     → SettingsScreen
    └─ /theme/custom → CustomThemeScreen
```

### State and persistence

| State | Where it lives | Persisted? | How |
|---|---|---|---|
| Printer list | `PrinterRegistry` (singleton) | Yes | `SharedPreferences` key `moongate_printers` (JSON) |
| Anonymous identity | Cloud middleman + app | Yes | Identity handle stored at the cloud side; the app holds a session for it |
| Detected web UI type | `PrinterConfig.uiType` | Yes | Persisted with the rest of the printer config - so the right logo renders on cold launch even when the printer is offline |
| Cached LAN URL | `PrinterConfig.lanUrl` | Yes | Learned from the first successful status response; used for LAN-first routing |
| Webcam transforms (flip / rotate / fps) | `PrinterConfig.webcam*` | Yes | Server-driven from the plugin; persisted so the first frame after cold launch already renders correctly |
| Theme mode | `themeModeProvider` | Yes | `SharedPreferences` key `theme_mode` |
| Custom theme | `customThemeProvider` | Yes | `SharedPreferences` key `custom_theme` (JSON of 5 HEX strings) |
| Font scale / grid cols / rotation | `settings_provider.dart` | Yes | One `SharedPreferences` key each |
| App font | `appFontProvider` | Yes | `SharedPreferences` key `app_font` (bundled font id) |
| Current access token + tunnel URL | `PrinterAccessCache` | **No** (in-memory only) | Refreshed from the middleman every few minutes |
| Live `PrinterStatus` per tile | `PrinterStatusService.stream` | **No** | StreamController - last emission only |
| Dashboard buttons visibility | `dashboardButtonsProvider` | Yes | `SharedPreferences` key `show_dashboard_buttons` (v0.9.41) |

### The service layer

The `services/` directory has zero UI. Each file is a focused capability:

| File | Responsibility |
|---|---|
| `supabase_service.dart` | Talks to the cloud middleman. Anonymous sign-in, fetch the current access record for a printer, release a printer on un-pair, list-my-printers refresh |
| `printer_access_cache.dart` | In-memory cache of `{tunnel_url, access_token}` per printer. Reuses a token until ~30 s before its expiry, then refreshes via the middleman. Used by every outbound call to the Pi |
| `printer_status_service.dart` | The heart of the app. One instance per printer tile. Polls every 4 s. LAN-first when a cached LAN URL is known; falls back to the tunnel within a couple of seconds. Distinguishes Pi-up-but-printer-idle from totally-offline. Sniffs the printer's web UI (Mainsail / Fluidd) on first successful poll and persists it. Also reads a printer's configured light object - when lighting is enabled - so the dashboard bulb shows the light's real on/off state. Reads Moonraker's `webhooks.state` too, so the tile can tell a **shut-down** Klipper (e.g. after an emergency stop) from merely idle and offer a restart instead of the E-STOP triangle. **v0.9.39+:** builds the **multi-toolhead** temperature list. On the current Pi plugin (0.6.12+) every `extruder`/`extruderN`, the active `toolhead` and the `toolchanger` ride the one authenticated `/status` call and the app reads them straight from it (falling back to a direct per-object query for older plugins); the persistent-notification roster order follows the dashboard's **Auto-arrange by status** setting |
| `print_control_service.dart` | Sends `pause` / `resume` / `cancel` / `firmware_restart` / `emergency_stop`, lists and runs Klipper macros (the macro sheet and the lighting on/off/toggle), and starts a stored G-code. Also sets hotend/bed target temperatures for the **preheat** sheet - one `SET_HEATER_TEMPERATURE` request **per heater** (v0.9.45), so on a multi-toolhead machine a heater that rejects a target no longer stops the others and each result is logged. Same per-call token retrieval, same LAN-first routing |
| `printer_webview_cache.dart` | Keeps each printer's Mainsail/Fluidd `WebViewController` warm across visits to the dashboard, so re-opening a printer is instant (no reload). **Pre-warms every printer's page in the background at app startup, so even the *first* open is instant** (v0.9.15). Owns the per-session token-cookie refresh and evicts least-recently-used sessions under OS memory pressure |
| `printer_liveness_service.dart` | Tracks each printer's online/offline state from the cloud - subscribing to `last_seen` changes over **Supabase Realtime** plus a periodic RLS-scoped read as a fallback - so the dashboard and the notification service can mark a powered-off printer offline and **skip requesting access for it entirely** rather than polling it every cycle. Realtime delivery is scoped by the same "select own printers" RLS policy, so it widens nothing (v0.9.16). **On returning to the foreground it re-reads every printer's `last_seen` immediately** (a resume re-seed), so a printer powered back on while the app was frozen in the background is recognised as online before the next poll instead of staying stuck offline until a cold start (v0.9.45) |
| `printer_registry.dart` | Persistent printer list. `addClaimed` after a successful pair, `remove` plus middleman-release on un-pair, helpers to update individual fields like LAN URL, webcam transforms, and the detected UI type from a successful poll |
| `update_service.dart` | One-shot GitHub `latest_version.json` fetch on app launch |
| `print_progress.dart` | Pure helper that computes print progress as a 0-1 fraction matching Mainsail's default *file position (relative)* mode - the printed byte position mapped onto the slicer's gcode body. Shared by the status service and the notification so the tile, the notification, and Mainsail all show the same number (v0.9.17) |
| `ota_installer.dart` | In-app updater (Android): streams the new release APK to the cache dir with progress, then launches the system package installer through a `FileProvider` + a native `MethodChannel`. Browser fallback on failure (v0.9.17) |

### Android native side

Most of the app is pure Dart, but a few things need Kotlin:

```
mobile/android/app/src/main/
├── AndroidManifest.xml              # permissions (camera, biometric, notifications,
│                                    #   foreground-service, REQUEST_INSTALL_PACKAGES)
│                                    #   + a FileProvider for the in-app updater
├── kotlin/com/moongate/app/
│   └── moongate/MainActivity.kt     # FlutterFragmentActivity + two MethodChannels
├── res/xml/file_paths.xml           # FileProvider paths (the updater's APK cache dir)
└── app/proguard-rules.pro           # R8 keep-rules for ML Kit + mobile_scanner + CameraX
```

`MainActivity` extends `FlutterFragmentActivity` (not the default `FlutterActivity`) because CameraX requires the activity to be a `LifecycleOwner`. Switching this fixed an earlier camera-binding crash on first launch. It also hosts two small `MethodChannel`s: `com.moongate.app/secure` (toggles `FLAG_SECURE` for the app-lock screen) and `com.moongate.app/install` (v0.9.17 - launches the system package installer on the APK the in-app updater downloaded, shared as a `content://` URI via the `FileProvider`; compiled out of the Play flavor via `BuildConfig.SELF_UPDATE` - #178).

---

## The Pi side

Three independent processes running side-by-side on a stock KIAUH / MainsailOS setup:

```
systemd
├─ moonraker.service             ──┐
│   └─ moongate plugin             │  shipping single Python file:
│       (Moonraker component) ─────┤  klipper-plugin/moongate_standalone.py
│                                  │
├─ moongate-authproxy.service ─────┤  klipper-plugin/moongate_authproxy.py
│   (aiohttp HTTP+WS proxy)        │
│                                  │
└─ moongate-tunnel.service ────────┘  cloudflared - Cloudflare Quick Tunnel
```

### The Moongate plugin (Moonraker component)

[`klipper-plugin/moongate_standalone.py`](klipper-plugin/moongate_standalone.py) is symlinked into Moonraker so its auto-discovery picks it up. Single file, no external Python deps beyond what Moonraker already pulls in.

Responsibilities:
- **Pairing.** Generates the QR + `GATE-XXXX-XXXX` code, registers the printer with the cloud middleman on first successful pair.
- **Heartbeat.** Periodically tells the middleman the current Cloudflare tunnel URL (it rotates on each Pi reboot).
- **Status.** Aggregates Klipper / Moonraker objects into a single `/server/moongate/status` response - `print_stats`, temperatures, the discovered chamber sensor, webcam transforms, and the current tunnel URL.
- **Control.** A small whitelist of safe actions: `pause`, `resume`, `cancel`, `firmware_restart`, `emergency_stop`. There is no arbitrary G-code endpoint.
- **Owner state.** Knows the user this Pi is paired to, persisted at `~/.config/moongate/owner.json`. The `MOONGATE_RESET_OWNER` macro wipes it.

### The auth proxy (v0.4+)

[`klipper-plugin/moongate_authproxy.py`](klipper-plugin/moongate_authproxy.py) is a small aiohttp HTTP + WebSocket proxy. It sits in front of *everything* the Cloudflare tunnel can reach.

- The cloudflared service points at the auth proxy, not at nginx directly.
- Every request must carry a valid short-lived access token (via `Authorization: Bearer`, an `mg_token` cookie, or an `mg_token` query parameter - in that priority order).
- Without a valid token: a flat `401 Unauthorized`, constant 13-byte body, no `WWW-Authenticate` challenge, no `Server` header, no fingerprint of what's behind it.
- With a valid token: the request is forwarded to nginx (which then routes Mainsail / Moonraker / the webcam stream / the Moongate plugin endpoints exactly as it would on the LAN side).
- One exception to "forward to nginx" (v0.9.0+): a request to **`/mg-extcam?u=...`** relays a snapshot/stream from an **external LAN camera** (e.g. a phone webcam Klipper can't see) so it works remotely. The target is SSRF-validated to a literal **private IPv4** only - loopback, link-local/metadata, public addresses, and hostnames are all refused (`_extcam_target_ok`). See [SECURITY.md](SECURITY.md) for the full ruleset.

LAN traffic doesn't go through the proxy - nginx still listens on the LAN interface, so phones on the home network reach Moonraker the way they always have.

### The tunnel

`cloudflared` Quick Tunnel runs as `moongate-tunnel.service`. It makes an outbound connection to the Cloudflare edge - no inbound ports opened on your router. The URL rotates each time the Pi reboots; the Moongate plugin heartbeats the current one to the cloud middleman so the app always knows where to reach the Pi.

### Where state lives on the Pi

```
~/.config/moongate/
├── owner.json          # Which user this Pi is paired to + the printer's identity
├── device.key          # Per-device signing key, generated on first install
└── v0.4-backup/        # Original moonraker.conf / nginx vhost(s) so uninstall.sh can revert
```

Plus the systemd units:

```
/etc/systemd/system/moongate-tunnel.service
/etc/systemd/system/moongate-authproxy.service
```

---

## The cloud middleman (top level only)

The app and the Pi both talk to a small managed backend that handles three things:

1. **Anonymous sign-in.** The app creates an identity on first launch with no email and no password. The handle for that identity is what links the user to their printer(s).
2. **Per-request access token issuance.** When the app wants to talk to the printer, it asks the middleman for a fresh short-lived token; the middleman issues one bound to that user + printer pair. The Pi-side auth proxy verifies it.
3. **Lookup.** The middleman tracks the current tunnel URL for each Pi (heartbeats from the plugin) so the app always knows the right URL to call.

What the middleman intentionally does **not** see:
- Your G-code, slicer files, or print history (the app never sends print content to the middleman)
- Live print state (status calls go phone → Pi directly, not via the middleman)
- Anything from your webcam (snapshots go phone → Pi directly)
- Anything you'd consider personal (no email, no name, no contact info)

**v0.6.3 additions.** The middleman gained two small jobs. **(a) Backup restore** - a one-time, hashed *restore code* (table `restore_grants`; functions `create-restore-grant` / `redeem-restore-grant`) lets a reinstalled app reclaim its printers by re-assigning their ownership to the new identity, so a restored backup reconnects without re-pairing. **(b) Bug reports** - a locked-down `feedback` table (function `submit-feedback`) collects in-app reports with diagnostics, readable only via the dashboard or the secret-gated `read-feedback` function. Ownership is now **cloud-authoritative**: the Pi follows the cloud's owner - it re-binds when a validly-signed token presents a new identity - rather than pinning the first one, which is what makes restore reconnect (see [SECURITY.md](SECURITY.md)). App-side, `diagnostics_service.dart` + `printer_status_registry.dart` assemble the report payload (app / device / network / per-printer status incl. the last LAN-poll outcome).

**v0.6.4-v0.6.5.** v0.6.4 enriched those bug reports - they now also carry the **Pi's plugin version** (the plugin self-reports `MOONGATE_PLUGIN_VERSION` in its `/status` reply) and the **remote (tunnel) connection result** next to the LAN outcome, the two biggest triage blind spots - and fixed a v0.6.3 auth-proxy regression that had been failing every tunnel request closed (see [SECURITY.md](SECURITY.md)). v0.6.5 is app-only: a first-run **"How pairing works"** explainer, with no backend or cloud surface.

The deep design - schemas, token mechanics, key rotation, the specific cross-tenant isolation guarantees - lives in [`docs/v0.3-supabase-design.md`](docs/v0.3-supabase-design.md) and [`docs/v0.4-secure-remote-access-design.md`](docs/v0.4-secure-remote-access-design.md) alongside the alternative-architectures discussion that explains why we landed here.

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
  ├─ flutter build apk --release --flavor github --dart-define=MOONGATE_CHANNEL=github
  ├─ flutter build appbundle --release --flavor play --dart-define=MOONGATE_CHANNEL=play
  ├─ Publish the signed github APK as a GitHub Release asset (Moongate-v<X.Y.Z>.apk)
  ├─ Upload the play .aab as the "Moongate-play-aab" workflow artifact (manual Play upload)
  ├─ Regenerate APK/latest_version.json (apk_url → the Release asset)
  └─ git commit + push the manifest  →  "Release Moongate-vX.Y.Z [skip ci]"
```

The `[skip ci]` suffix prevents the commit-back from re-triggering CI. The in-app update banner ([`UpdateService`](mobile/lib/services/update_service.dart)) polls `latest_version.json` on launch and shows the banner if the remote `build_number` exceeds the installed one.

CI only fires on `master`. Feature branches (like `v0.4-secure-remote`) don't build APKs automatically - that's intentional, so unreleased branches stay out of the in-app updater.

**Build flavors (#178).** The Android build has two flavors on a `distribution` dimension: `github` (the sideload APK for GitHub Releases + KIAUH, keeps the self-updater) and `play` (the App Bundle for Google Play, no self-updater and no `REQUEST_INSTALL_PACKAGES`, since Play forbids self-install). Both keep the same `applicationId` and signing key, so users move between channels in place with no wipe. A Dart flag ([`config/build_channel.dart`](mobile/lib/config/build_channel.dart), fed by the `MOONGATE_CHANNEL` dart-define) plus `BuildConfig.SELF_UPDATE` gate the updater code; the permission + `FileProvider` live in `src/github/AndroidManifest.xml`. Full rationale in [`docs/design/play-flavor-plan.md`](docs/design/play-flavor-plan.md).

---

## Data flow walkthroughs

### Pairing (QR path)

1. User runs `MOONGATE_PAIR` in Klipper console → registered as a Moonraker remote method → plugin generates a `GATE-XXXX-XXXX` code and stashes a pending pair record.
2. Plugin pushes a clickable LAN pair URL to the console via `M118`. The QR page is **LAN-only by design** - the Cloudflare tunnel side returns 401 for everyone, including the pair page, because the user pairing doesn't have a token yet.
3. User opens `http://<pi-ip>/moongate-pair.html` on a PC / tablet / second phone on the same WiFi. The page fetches the current pending pair info from the Moongate plugin and renders the QR.
4. User opens the Moongate app on their phone → tap **+** → **Scan QR** → camera reads the payload.
5. App registers itself with the cloud middleman (anonymous sign-in if it's the first launch), then submits a claim for this printer using the code from the QR.
6. Plugin verifies the claim (next heartbeat to the middleman picks up the new owner) and writes `owner.json`. The app sees the printer in its registry; the dashboard tile spins up its status service.

### Pairing (manual code path)

If the phone's camera doesn't work (permission denied, hardware fault, can't focus on the QR), the `GATE-XXXX-XXXX` code shown in the Klipper console can be typed into the app's pair screen instead of scanning - two 4-digit boxes with a numpad. The rest of the flow is the same: code in (no `pi_public_key` sent - the server uses the one already on the enrollment row), claim out, owner.json written, tile spins up.

### Status poll (every 4 s per tile)

1. `PrinterStatusService._doPoll()` asks `PrinterAccessCache` for a `{tunnel_url, access_token}` pair. If the cached token is still fresh, returned instantly; otherwise the cache fetches a new one from the middleman.
2. If the printer has a known LAN URL (learned from a previous poll), try it first with the access token in the `Authorization: Bearer` header. 2 s fast-fail timeout.
3. If LAN fails (off-WiFi, slow LAN, etc.), try the tunnel URL with an 8 s timeout. The auth proxy verifies the token and forwards to Moonraker.
4. If both fail, drop the token cache (in case the middleman revoked it) and retry once with a fresh token.
5. If even that fails, do a quick HEAD probe to LAN + tunnel. ANY reply (auth proxy 401, nginx 200, upstream 502) proves the Pi is reachable on the network → emit a `PrinterStatus.waiting` ("Connected - Printer idle"). Only when nothing on either path answers does the tile go fully offline.
6. The tile widget rebuilds with the new temps, progress, webcam tick.

### Print control

1. Tile button → `PrintControlService.sendAction('pause')`.
2. Same access-token lookup and LAN-first routing as the status service.
3. Try `POST /server/moongate/control?mg_token=...&action=pause` first; the auth proxy + plugin both verify the token.
4. Return `true` as soon as the Pi answers 200.

### Tunnel URL rotation

`cloudflared` Quick Tunnels get a fresh URL every time `cloudflared` restarts (so every Pi reboot, plus any manual restart). To make this transparent:

- The Moongate plugin tails the cloudflared log for the current URL and heartbeats it to the cloud middleman.
- When the app polls, `PrinterAccessCache` fetches the *current* tunnel URL from the middleman alongside the access token.
- Result: no re-pairing, no QR re-scan, no user action of any kind needed when the Pi reboots and the URL changes.

---

## Key design decisions

### LAN-first on every poll, no skip backoff

Every poll tries LAN before the tunnel when a cached LAN URL is known. There used to be a "3 LAN failures → skip LAN for 5 minutes" backoff in v0.3, but it had a frustrating bug: once you went on cellular at any point, returning to home WiFi did not flip back to "Local" until the 5-min timer expired. The user-perceptible "stuck on Tunnel at home" was worse than the off-LAN polling overhead. v0.4.0 removed the skip.

The off-LAN cost is an extra ~2 s per poll cycle (LAN timeout fires before the tunnel attempt). Polls stretch from 4 s to ~6-10 s when away from home. That's the trade we explicitly accepted in exchange for predictable LAN-first behaviour.

### Connectivity-aware camera feed rate

The dashboard keeps two webcam refresh rates - a faster "Local" rate and a throttled "Tunnel" rate (v0.9.14). As of v0.9.15 the tile picks between them by the **phone's network type** rather than by which URL the status poll happened to win on: an `onMobileDataProvider` (backed by `connectivity_plus`) drives the choice, so the faster Local rate applies on **any Wi-Fi** - including when you're away and reaching the printer over the tunnel - and the throttled Tunnel rate applies only on **mobile data**, where cellular data actually costs something. Reaching a printer on the LAN is always Wi-Fi, so home behaviour is unchanged.

### Print progress matches Mainsail (file-relative, single source)

Progress used to be computed two different ways - the dashboard tile preferred elapsed-time ÷ the slicer's time estimate, while the notification used the raw file fraction - so the tile, the notification, and Mainsail could all disagree (the tile typically ran a few percent ahead, because slicer time estimates are routinely off). As of v0.9.17 a single helper, [`print_progress.dart`](mobile/lib/services/print_progress.dart), is the only place progress is derived, for **both** the tile and the notification. It matches Mainsail's default **"file position (relative)"** calculation - `(file_position − gcode_start_byte) / (gcode_end_byte − gcode_start_byte)`, the printed byte position mapped onto the slicer's gcode body (the start/end offsets come from the file metadata the status service already fetches) - and falls back to `display_status.progress`, then the raw `virtual_sdcard.progress`, until those offsets are known. The slicer time estimate still drives the notification's finish-time ETA, just not the progress bar.

### Liveness-gated polling for offline printers

Status polling a powered-off printer is wasted work: every cycle mints an access token from the middleman (an Edge Function call) only for the request to fail. As of v0.9.16 a `PrinterLivenessService` learns each printer's online/offline state from the cloud's `last_seen` (the Pi heartbeats it) over a **Supabase Realtime** subscription, with a periodic RLS-scoped `SELECT` as a fallback when the socket is down. While a printer reads as offline, both the dashboard and the background notification service **stop requesting access for it**, so an offline Pi costs zero Edge Function invocations and far less mobile data / battery. Reading `last_seen` over Realtime (or a plain RLS-scoped read) is **not** a billed Edge Function call, unlike `/printer-access`. Online printers behave exactly as before, and LAN polling still works even if the cloud is unreachable - liveness only *suppresses* remote token requests, it never gates the LAN path.

### Persistent UI type detection

When the dashboard tile can't render a webcam (camera off, printer powered off, etc.) it shows the printer's web-UI logo as a placeholder - Mainsail or Fluidd. Detection is a one-time HTML sniff of the root page. In v0.4 the result is persisted on `PrinterConfig`, so a fresh cold launch shows the correct logo immediately, even when the printer is currently offline. Before v0.4, detection had to re-run on every cold launch and the logo only appeared after the first successful poll.

### Pi-up-but-printer-idle as its own state

When the Pi is reachable but the moongate `/status` path keeps failing (e.g. on a Creality K3 where the printer-power toggle inside Mainsail is off, so Klipper isn't running), the tile emits `PrinterStatus.waiting` rather than `PrinterStatus.offline`. The tile shows the logo + "Connected - Printer idle" with no spinner, instead of looking dead. Distinguished by a HEAD reachability probe - any HTTP reply at all (auth proxy 401, nginx 200, upstream 502) proves the Pi is up.

### Per-tile, not per-app, status polling

Each `PrinterTile` owns its own `PrinterStatusService`. They poll independently. This means:
- Adding / removing a printer doesn't stall the others
- A timing-out printer doesn't slow the dashboard refresh of nearby ones
- One offline printer doesn't poison the connection state of the others

It costs N parallel HTTP loops where N is the number of printers, but that's fine - typical N is 1-3, and the polls are 4 seconds apart.

### Plugin is a single file, no external Python deps

The Moongate plugin runs inside Moonraker's process and has access to anything Moonraker depends on. Staying within that surface (stdlib + Moonraker's existing deps) reduces installation to "copy one file and restart Moonraker". No virtualenvs, no `pip install`, no breakage when Moonraker updates.

The auth proxy is the one exception - it pulls in `aiohttp` (`pip install` inside Moonraker's venv) because there's no Moonraker-native way to intercept everything *before* Moonraker. The verifier classes (token-signature checks, owner state) are imported from the plugin file rather than duplicated, so signature semantics stay single-source.

### Cloud middleman, not a Moongate-operated print server

The middleman is intentionally minimal - anonymous identity, per-request token issuance, lookup. It never sees your G-code, your prints, your webcam, your bed. All print-side data flows phone ↔ Pi directly. This is both a privacy decision and a scope decision: a print server is a much larger thing to operate than a lookup table.

---

## Where to next

- [SECURITY.md](SECURITY.md) - threat model, what the tunnel exposes and what it doesn't, how to audit
- [DEVELOPMENT.md](DEVELOPMENT.md) - practical setup, running, building, debugging
- [docs/setup-guide.md](docs/setup-guide.md) - end-user perspective
- [`docs/v0.3-supabase-design.md`](docs/v0.3-supabase-design.md) and [`docs/v0.4-secure-remote-access-design.md`](docs/v0.4-secure-remote-access-design.md) - the deep design rationale, alternatives discussion, and the specific guarantees the cloud middleman + auth proxy make
