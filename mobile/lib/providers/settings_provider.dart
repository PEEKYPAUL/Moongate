import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notif_fields.dart';

// ---------------------------------------------------------------------------
// Theme mode
// ---------------------------------------------------------------------------

/// Moongate's theme selector.
///
/// `dark`/`light` map 1:1 onto Flutter's [ThemeMode].
/// `custom` is our own value - when selected, [app.dart] builds the
/// MaterialApp theme from user-picked colours stored in
/// [customThemeProvider] instead of the seeded purple defaults.
/// `system` follows the phone's wallpaper-derived "Material You" palette
/// (Android 12+) and the device light/dark setting; where that palette isn't
/// available (older Android, iOS) [app.dart] falls back to the seeded theme,
/// and the option itself is hidden (see [dynamicColorSupportedProvider]).
enum AppThemeMode { dark, light, custom, system }

class ThemeModeNotifier extends Notifier<AppThemeMode> {
  static const _key = 'theme_mode';

  @override
  AppThemeMode build() => AppThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    state = switch (raw) {
      'light'  => AppThemeMode.light,
      'custom' => AppThemeMode.custom,
      'system' => AppThemeMode.system,
      // Anything unknown falls back to Dark.
      _        => AppThemeMode.dark,
    };
  }

  Future<void> set(AppThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, AppThemeMode>(
  ThemeModeNotifier.new,
);

/// Whether the optional "Phone colours" (Material You) theme can actually be
/// applied on this device: true only on Android 12+, where the OS exposes a
/// wallpaper-derived palette. Drives whether the theme option is offered at all
/// - older Android and iOS have no such palette, so the option is hidden there
/// rather than shown as a no-op. Resolved once; treated as false until it
/// completes.
final dynamicColorSupportedProvider = FutureProvider<bool>((ref) async {
  if (!Platform.isAndroid) return false;
  try {
    return (await DynamicColorPlugin.getCorePalette()) != null;
  } catch (_) {
    return false;
  }
});

// ---------------------------------------------------------------------------
// App font  (the bundled typeface used across the app)
// ---------------------------------------------------------------------------

/// One selectable app typeface. The phone's own system font can't be read by a
/// Flutter app (Flutter renders text with its own engine, not Android's), so we
/// offer a bundled set instead. Font names are universal, so the name doubles as
/// the picker label (no per-font l10n).
class AppFontOption {
  /// Stable id persisted under the `app_font` key.
  final String id;

  /// The pubspec font family to apply, or null for the platform default.
  final String? family;

  /// Display name, also previewed in its own font in the picker.
  final String label;

  /// Groups the picker (see [kAppFontCategories]).
  final String category;

  const AppFontOption(this.id, this.family, this.label, this.category);
}

/// Every selectable font. `standard` applies no override; the rest map to
/// families declared in pubspec.yaml's `fonts:` block (bundled under
/// assets/fonts/). Ids for the original four are kept stable.
const List<AppFontOption> kAppFonts = [
  AppFontOption('standard', null, 'Default', 'System'),
  AppFontOption('rounded', 'Nunito', 'Nunito', 'Rounded'),
  AppFontOption('serif', 'Lora', 'Lora', 'Serif'),
  AppFontOption('readable', 'AtkinsonHyperlegible', 'Atkinson Hyperlegible', 'High-readability'),
  AppFontOption('poppins', 'Poppins', 'Poppins', 'Sans'),
  AppFontOption('lexend', 'Lexend', 'Lexend', 'Sans'),
  AppFontOption('rubik', 'Rubik', 'Rubik', 'Sans'),
  AppFontOption('manrope', 'Manrope', 'Manrope', 'Sans'),
  AppFontOption('worksans', 'Work Sans', 'Work Sans', 'Sans'),
  AppFontOption('mulish', 'Mulish', 'Mulish', 'Sans'),
  AppFontOption('outfit', 'Outfit', 'Outfit', 'Sans'),
  AppFontOption('montserrat', 'Montserrat', 'Montserrat', 'Sans'),
  AppFontOption('raleway', 'Raleway', 'Raleway', 'Sans'),
  AppFontOption('sourcesans3', 'Source Sans 3', 'Source Sans 3', 'Sans'),
  AppFontOption('firasans', 'Fira Sans', 'Fira Sans', 'Sans'),
  AppFontOption('quicksand', 'Quicksand', 'Quicksand', 'Rounded'),
  AppFontOption('baloo2', 'Baloo 2', 'Baloo 2', 'Rounded'),
  AppFontOption('fredoka', 'Fredoka', 'Fredoka', 'Rounded'),
  AppFontOption('merriweather', 'Merriweather', 'Merriweather', 'Serif'),
  AppFontOption('ptserif', 'PT Serif', 'PT Serif', 'Serif'),
  AppFontOption('bitter', 'Bitter', 'Bitter', 'Serif'),
  AppFontOption('robotoslab', 'Roboto Slab', 'Roboto Slab', 'Slab serif'),
  AppFontOption('zillaslab', 'Zilla Slab', 'Zilla Slab', 'Slab serif'),
  AppFontOption('arvo', 'Arvo', 'Arvo', 'Slab serif'),
  AppFontOption('ibmplexmono', 'IBM Plex Mono', 'IBM Plex Mono', 'Monospace'),
  AppFontOption('orbitron', 'Orbitron', 'Orbitron', 'Techy / display'),
  AppFontOption('exo2', 'Exo 2', 'Exo 2', 'Techy / display'),
  AppFontOption('chakrapetch', 'Chakra Petch', 'Chakra Petch', 'Techy / display'),
  AppFontOption('rajdhani', 'Rajdhani', 'Rajdhani', 'Techy / display'),
  AppFontOption('oswald', 'Oswald', 'Oswald', 'Condensed'),
  AppFontOption('teko', 'Teko', 'Teko', 'Condensed'),
  AppFontOption('bebasneue', 'Bebas Neue', 'Bebas Neue', 'Condensed'),
  AppFontOption('caveat', 'Caveat', 'Caveat', 'Handwriting'),
  AppFontOption('patrickhand', 'Patrick Hand', 'Patrick Hand', 'Handwriting'),
  AppFontOption('vt323', 'VT323', 'VT323', 'Retro / pixel'),
  AppFontOption('silkscreen', 'Silkscreen', 'Silkscreen', 'Retro / pixel'),
];

/// Look up a font option by id, falling back to Default for an unknown id.
AppFontOption appFontById(String id) =>
    kAppFonts.firstWhere((f) => f.id == id, orElse: () => kAppFonts.first);

/// Category display order for the picker; categories with no fonts are skipped.
const List<String> kAppFontCategories = [
  'System', 'Sans', 'Rounded', 'Serif', 'Slab serif', 'Monospace',
  'Techy / display', 'Condensed', 'Handwriting', 'Retro / pixel',
  'High-readability',
];

class AppFontNotifier extends Notifier<String> {
  static const _key = 'app_font';

  @override
  String build() => 'standard';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    state = kAppFonts.any((f) => f.id == raw) ? raw! : 'standard';
  }

  Future<void> set(String id) async {
    state = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id);
  }
}

final appFontProvider =
    NotifierProvider<AppFontNotifier, String>(AppFontNotifier.new);

// ---------------------------------------------------------------------------
// Font scale
// ---------------------------------------------------------------------------

class FontScaleNotifier extends Notifier<double> {
  static const _key = 'font_scale';

  @override
  double build() => 1.0;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getDouble(_key) ?? 1.0;
  }

  Future<void> set(double scale) async {
    state = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, scale);
  }
}

final fontScaleProvider = NotifierProvider<FontScaleNotifier, double>(
  FontScaleNotifier.new,
);

// ---------------------------------------------------------------------------
// Grid columns  (1 | 2 | 3 - portrait preference; landscape auto-bumps +1)
// ---------------------------------------------------------------------------

class GridColumnsNotifier extends Notifier<int> {
  static const _key = 'grid_columns';

  @override
  int build() => 2;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt(_key) ?? 2;
  }

  Future<void> set(int cols) async {
    state = cols;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, cols);
  }
}

final gridColumnsProvider = NotifierProvider<GridColumnsNotifier, int>(
  GridColumnsNotifier.new,
);

// ---------------------------------------------------------------------------
// Allow rotation  (false = portrait-locked, true = follows device)
// ---------------------------------------------------------------------------

class AllowRotationNotifier extends Notifier<bool> {
  static const _key = 'allow_rotation';

  @override
  bool build() => false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
    await _applyOrientation(state);
  }

  Future<void> set(bool allow) async {
    state = allow;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, allow);
    await _applyOrientation(allow);
  }

  Future<void> _applyOrientation(bool allow) =>
      SystemChrome.setPreferredOrientations(
        allow
            ? [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
              ],
      );
}

final allowRotationProvider = NotifierProvider<AllowRotationNotifier, bool>(
  AllowRotationNotifier.new,
);

// ---------------------------------------------------------------------------
// Auto-arrange by status  (true = sort tiles by live status; false = manual)
// ---------------------------------------------------------------------------

/// Whether the dashboard re-sorts tiles by live status (Error → Printing →
/// Ready → Idle → Offline) on every status change. ON by default - the
/// historic behaviour, which floats active prints to the top.
///
/// Turning it OFF freezes the tiles in the user's own order and unlocks
/// long-press drag-to-reorder on the dashboard grid (the order is persisted by
/// [PrinterRegistry] and rides backups). Without this, a printer coming online
/// or starting a print would yank a hand-placed tile out from under the user.
/// Travels in backups.
class AutoArrangeNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(kAutoArrangeByStatusKey) ?? true;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kAutoArrangeByStatusKey, enabled);
  }
}

final autoArrangeProvider =
    NotifierProvider<AutoArrangeNotifier, bool>(AutoArrangeNotifier.new);

// ---------------------------------------------------------------------------
// Dashboard camera refresh rate
// ---------------------------------------------------------------------------

/// How often each dashboard tile re-fetches its webcam snapshot.
///
/// The dashboard previously pulled snapshots at each printer's Crowsnest
/// "target FPS" (up to ~15 FPS) continuously, for EVERY tile at once - a
/// large, constant data drain, especially over the Cloudflare tunnel. (This
/// was the cause of the "Moongate is spiking network traffic" reports.) This
/// global setting caps the dashboard to a sensible inter-frame interval.
/// `raw` keeps the old per-printer FPS behaviour for users who want a live
/// view and have the bandwidth to spare.
///
/// Scope: this only affects the *dashboard tile* previews. The full-screen
/// printer view is a Mainsail/Fluidd WebView that manages its own stream and
/// is unaffected.
enum DashboardCameraRefresh { raw, oneSecond, threeSeconds, fiveSeconds }

extension DashboardCameraRefreshX on DashboardCameraRefresh {
  /// Fixed inter-frame interval in milliseconds, or null for [raw] - in which
  /// case the tile falls back to the printer's own target FPS (self-throttled
  /// by the sequential fetch loop to whatever the camera can actually deliver).
  int? get intervalMs => switch (this) {
        DashboardCameraRefresh.raw          => null,
        DashboardCameraRefresh.oneSecond    => 1000,
        DashboardCameraRefresh.threeSeconds => 3000,
        DashboardCameraRefresh.fiveSeconds  => 5000,
      };

  /// Short label for the segmented picker.
  String get label => switch (this) {
        DashboardCameraRefresh.raw          => 'Raw',
        DashboardCameraRefresh.oneSecond    => '1s',
        DashboardCameraRefresh.threeSeconds => '3s',
        DashboardCameraRefresh.fiveSeconds  => '5s',
      };
}

/// Legacy single-rate key (pre-v0.9.14). A user who set it keeps that value:
/// both the local and tunnel rates fall back to it when their own key is unset,
/// so updating preserves the old behaviour. Fresh installs use the per-path
/// defaults below (local 1 s; tunnel 3 s - throttled to save mobile data).
const _legacyCameraRefreshKey = 'dashboard_camera_refresh';

/// Shared load/set for the two dashboard camera-refresh settings. A tile reads
/// the LOCAL rate while the phone is on Wi-Fi (even when reaching the printer
/// remotely over the tunnel) and the TUNNEL rate on mobile data, so the remote
/// feed is throttled only where data is metered (see [onMobileDataProvider] +
/// WebcamView).
abstract class _CameraRefreshNotifier extends Notifier<DashboardCameraRefresh> {
  String get key;
  DashboardCameraRefresh get fallback;

  @override
  DashboardCameraRefresh build() => fallback;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Per-path key wins; otherwise migrate from the old single key; else default.
    final raw = prefs.getString(key) ?? prefs.getString(_legacyCameraRefreshKey);
    state = DashboardCameraRefresh.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => fallback,
    );
  }

  Future<void> set(DashboardCameraRefresh value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value.name);
  }
}

class LocalCameraRefreshNotifier extends _CameraRefreshNotifier {
  @override
  String get key => 'dashboard_camera_refresh_local';
  @override
  DashboardCameraRefresh get fallback => DashboardCameraRefresh.oneSecond;
}

class TunnelCameraRefreshNotifier extends _CameraRefreshNotifier {
  @override
  String get key => 'dashboard_camera_refresh_tunnel';
  @override
  DashboardCameraRefresh get fallback => DashboardCameraRefresh.threeSeconds;
}

/// Tile webcam refresh rate while the phone is on Wi-Fi (default 1 s).
final localCameraRefreshProvider =
    NotifierProvider<LocalCameraRefreshNotifier, DashboardCameraRefresh>(
  LocalCameraRefreshNotifier.new,
);

/// Tile webcam refresh rate while the phone is on mobile data (default 3 s -
/// slower to save cellular data; adjustable in the Dashboard Camera Feeds
/// sheet).
final tunnelCameraRefreshProvider =
    NotifierProvider<TunnelCameraRefreshNotifier, DashboardCameraRefresh>(
  TunnelCameraRefreshNotifier.new,
);

// ---------------------------------------------------------------------------
// Network type  (is the phone on metered mobile data?)
// ---------------------------------------------------------------------------

/// Whether the phone is currently on **mobile data only** - cellular, with no
/// Wi-Fi or wired connection. Drives which dashboard camera-feed rate applies:
/// on Wi-Fi (even when a printer is reached remotely over the tunnel) the
/// faster local rate is used; only on metered mobile data does the throttled
/// tunnel rate kick in. Wi-Fi / Ethernet win when present (Android routes over
/// them and they aren't metered). Updated live as the phone changes networks.
class OnMobileDataNotifier extends Notifier<bool> {
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  bool build() {
    final conn = Connectivity();
    _sub = conn.onConnectivityChanged.listen(_apply);
    ref.onDispose(() => _sub?.cancel());
    // The stream only fires on change - seed with the current state.
    conn.checkConnectivity().then(_apply);
    return false; // assume unmetered until the first reading lands
  }

  void _apply(List<ConnectivityResult> results) {
    final hasUnmetered = results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
    final onMobile =
        results.contains(ConnectivityResult.mobile) && !hasUnmetered;
    if (onMobile != state) state = onMobile;
  }
}

final onMobileDataProvider =
    NotifierProvider<OnMobileDataNotifier, bool>(OnMobileDataNotifier.new);

// ---------------------------------------------------------------------------
// Camera config icons  (show/hide the per-tile camera gear)
// ---------------------------------------------------------------------------

/// Whether the small camera-config gear is shown in the corner of each
/// dashboard tile's webcam. On by default; users who don't set custom cameras
/// can turn it off so it never overlaps the image feed. Travels in backups.
class ShowCameraConfigIconsNotifier extends Notifier<bool> {
  static const _key = 'show_camera_config_icons';

  @override
  bool build() => true;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  Future<void> set(bool show) async {
    state = show;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, show);
  }
}

final showCameraConfigIconsProvider =
    NotifierProvider<ShowCameraConfigIconsNotifier, bool>(
  ShowCameraConfigIconsNotifier.new,
);

// ---------------------------------------------------------------------------
// Global power button  (a "power all machines" control in the top bar)
// ---------------------------------------------------------------------------

/// Whether the dashboard shows a global power button in the top bar, beside the
/// menu. OFF by default - only useful when machines expose Moonraker `[power …]`
/// devices (smart plugs / relays). When on, the button opens a sheet that
/// switches every reachable machine's power devices on, or off behind a
/// slide-to-confirm; printing machines are left on. Travels in backups.
class GlobalPowerButtonNotifier extends Notifier<bool> {
  static const _key = 'global_power_button';

  @override
  bool build() => false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}

final globalPowerButtonProvider =
    NotifierProvider<GlobalPowerButtonNotifier, bool>(
  GlobalPowerButtonNotifier.new,
);

/// Whether the dashboard shows the floating buttons at the bottom (add printer,
/// plus the reorder toggle in manual mode). ON by default. Users with a lot of
/// printers turn it off so the buttons stop floating over the bottom tiles;
/// adding a printer stays available from the menu, and reordering by turning
/// the buttons back on. Travels in backups.
class DashboardButtonsNotifier extends Notifier<bool> {
  static const _key = 'show_dashboard_buttons';

  @override
  bool build() => true;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}

final dashboardButtonsProvider =
    NotifierProvider<DashboardButtonsNotifier, bool>(
  DashboardButtonsNotifier.new,
);

// ---------------------------------------------------------------------------
// Print notifications  (opt-in foreground-service progress + state alerts)
// ---------------------------------------------------------------------------

/// Whether the background print-notification service is enabled. OFF by default.
/// Turning it on (from the first-run prompt or the menu) requests the Android 13+
/// POST_NOTIFICATIONS permission and starts the foreground service that polls
/// /status to post the persistent progress notification + state-change alerts.
/// This is just the persisted on/off preference - see `PrintNotificationService`
/// for the runtime service.
class PrintNotificationsEnabledNotifier extends Notifier<bool> {
  static const _key = 'print_notifications_enabled';

  @override
  bool build() => false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}

final printNotificationsEnabledProvider =
    NotifierProvider<PrintNotificationsEnabledNotifier, bool>(
  PrintNotificationsEnabledNotifier.new,
);

/// Whether the print-notification service is temporarily *paused* from the
/// dashboard's quick pause/play button. Distinct from
/// [printNotificationsEnabledProvider]: the master switch (menu) says the user
/// wants notifications at all AND controls whether the pause/play button is even
/// shown; this transient flag lets them stop the polling - and its battery cost -
/// for a spell without losing that setting. The foreground service runs only
/// when notifications are ENABLED **and** NOT paused. Persisted so a pause sticks
/// across app restarts / reboots (the point is to leave printers unwatched for
/// days), and cleared whenever the master switch is (re)enabled. Deliberately
/// NOT part of the settings backup - it's a moment-to-moment control, not a
/// preference, so a restore should never silently pause someone's alerts.
class NotificationsPausedNotifier extends Notifier<bool> {
  static const _key = 'print_notifications_paused';

  @override
  bool build() => false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> set(bool paused) async {
    state = paused;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, paused);
  }
}

final notificationsPausedProvider =
    NotifierProvider<NotificationsPausedNotifier, bool>(
  NotificationsPausedNotifier.new,
);

/// When on, the persistent status notification shows only online printers -
/// offline / shut-down machines are hidden from the roster. Off by default.
/// Travels in backups. The background isolate reads the same pref directly
/// (kNotifOnlineOnlyKey), so the switch and the service stay in step.
class NotifOnlineOnlyNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(kNotifOnlineOnlyKey) ?? false;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kNotifOnlineOnlyKey, enabled);
  }
}

final notifOnlineOnlyProvider =
    NotifierProvider<NotifOnlineOnlyNotifier, bool>(NotifOnlineOnlyNotifier.new);

// ---------------------------------------------------------------------------
// App lock  (optional biometric / PIN gate on launch)
// ---------------------------------------------------------------------------

/// Whether the app requires authentication before the dashboard is reachable.
/// Off by default; enabling it (from the App-lock settings screen) also sets a
/// PIN - see [PinService]. The runtime locked/unlocked state lives in
/// `lockStateProvider`; this is just the persisted on/off preference.
class AppLockEnabledNotifier extends Notifier<bool> {
  static const _key = 'app_lock_enabled';

  @override
  bool build() => false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}

final appLockEnabledProvider =
    NotifierProvider<AppLockEnabledNotifier, bool>(AppLockEnabledNotifier.new);

/// Whether to offer biometric unlock on top of the PIN. Only meaningful when
/// the lock is enabled AND the device actually has biometric hardware (see
/// `biometricAvailableProvider`). The PIN is always the fallback.
class BiometricUnlockNotifier extends Notifier<bool> {
  static const _key = 'app_lock_biometric';

  @override
  bool build() => false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}

final biometricUnlockProvider =
    NotifierProvider<BiometricUnlockNotifier, bool>(BiometricUnlockNotifier.new);

/// When the app should re-lock after returning from the background. The lock
/// ALWAYS appears on a cold launch; this only governs re-locking an already
/// running process. Default [coldLaunchOnly] = never re-lock while running.
enum AutoLockTimeout {
  immediately,
  oneMinute,
  fiveMinutes,
  fifteenMinutes,
  coldLaunchOnly,
}

extension AutoLockTimeoutX on AutoLockTimeout {
  /// How long the app may sit backgrounded before it re-locks, or null to never
  /// re-lock while the process lives (a cold launch still locks).
  Duration? get resumeAfter => switch (this) {
        AutoLockTimeout.immediately    => Duration.zero,
        AutoLockTimeout.oneMinute      => const Duration(minutes: 1),
        AutoLockTimeout.fiveMinutes    => const Duration(minutes: 5),
        AutoLockTimeout.fifteenMinutes => const Duration(minutes: 15),
        AutoLockTimeout.coldLaunchOnly => null,
      };

  String get label => switch (this) {
        AutoLockTimeout.immediately    => 'Immediately',
        AutoLockTimeout.oneMinute      => 'After 1 minute',
        AutoLockTimeout.fiveMinutes    => 'After 5 minutes',
        AutoLockTimeout.fifteenMinutes => 'After 15 minutes',
        AutoLockTimeout.coldLaunchOnly => 'Only on app launch',
      };
}

class AutoLockTimeoutNotifier extends Notifier<AutoLockTimeout> {
  static const _key = 'app_lock_timeout';

  @override
  AutoLockTimeout build() => AutoLockTimeout.coldLaunchOnly;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    state = AutoLockTimeout.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => AutoLockTimeout.coldLaunchOnly,
    );
  }

  Future<void> set(AutoLockTimeout value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.name);
  }
}

final autoLockTimeoutProvider =
    NotifierProvider<AutoLockTimeoutNotifier, AutoLockTimeout>(
  AutoLockTimeoutNotifier.new,
);

// ---------------------------------------------------------------------------
// Language / locale
// ---------------------------------------------------------------------------

/// The user's chosen UI language, stored as a bare language code (e.g. 'de').
///
/// `null` means "follow the device's system language" - [app.dart] passes a
/// null `locale` to MaterialApp, so Flutter resolves the system locale against
/// `AppLocalizations.supportedLocales` and falls back to English when the
/// device language isn't one we ship.
///
/// Whether the user has actually been shown the first-run language prompt is
/// tracked separately by the `language_selected` flag in the dashboard
/// onboarding flow - independent of which locale ends up active.
class LocaleNotifier extends Notifier<String?> {
  static const _key = 'app_locale';

  @override
  String? build() => null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key);
    state = (code == null || code.isEmpty) ? null : code;
  }

  /// Set the active language code, or pass `null` to revert to the system
  /// language. Persists to SharedPreferences.
  Future<void> set(String? languageCode) async {
    state = languageCode;
    final prefs = await SharedPreferences.getInstance();
    if (languageCode == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, languageCode);
    }
  }
}

final localeProvider =
    NotifierProvider<LocaleNotifier, String?>(LocaleNotifier.new);

// ---------------------------------------------------------------------------
// Notification poll interval
// ---------------------------------------------------------------------------

/// How often the opt-in print-notification foreground service polls each
/// printer's /status. The chosen value is the actual poll rate (no idle
/// backoff) - faster reacts quicker but uses a little more data/battery.
/// Default 30s. Changing it restarts the service (see
/// `PrintNotificationService.reschedule`).
enum NotifPollInterval { s5, s10, s15, s30, m1 }

extension NotifPollIntervalX on NotifPollInterval {
  int get ms => switch (this) {
        NotifPollInterval.s5  => 5000,
        NotifPollInterval.s10 => 10000,
        NotifPollInterval.s15 => 15000,
        NotifPollInterval.s30 => 30000,
        NotifPollInterval.m1  => 60000,
      };

  /// Short segmented-picker label (universal - not localised).
  String get label => switch (this) {
        NotifPollInterval.s5  => '5s',
        NotifPollInterval.s10 => '10s',
        NotifPollInterval.s15 => '15s',
        NotifPollInterval.s30 => '30s',
        NotifPollInterval.m1  => '1m',
      };
}

class NotifPollIntervalNotifier extends Notifier<NotifPollInterval> {
  static const _key = 'notif_poll_interval';

  @override
  NotifPollInterval build() => NotifPollInterval.s30;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    state = NotifPollInterval.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => NotifPollInterval.s30,
    );
  }

  Future<void> set(NotifPollInterval value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.name);
  }
}

final notifPollIntervalProvider =
    NotifierProvider<NotifPollIntervalNotifier, NotifPollInterval>(
  NotifPollIntervalNotifier.new,
);

// ---------------------------------------------------------------------------
// Notification content  (which fields show in the print notification + order)
// ---------------------------------------------------------------------------

/// The set + order of fields shown in the persistent print-status notification
/// (progress, time-remaining, finish-ETA, hotend, bed). Edited on the
/// Notification-content screen; read by the background isolate straight from
/// SharedPreferences (see [NotifFieldsConfig.fromPrefs]). Travels in backups.
class NotificationFieldsNotifier extends Notifier<NotifFieldsConfig> {
  @override
  NotifFieldsConfig build() => NotifFieldsConfig.defaults();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = NotifFieldsConfig.fromPrefs(
      prefs.getString(kNotifFieldsOrderKey),
      prefs.getString(kNotifFieldsEnabledKey),
    );
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kNotifFieldsOrderKey, state.orderPref);
    await prefs.setString(kNotifFieldsEnabledKey, state.enabledPref);
  }

  /// Show or hide [field].
  Future<void> setEnabled(NotifField field, bool on) async {
    final next = {...state.enabled};
    if (on) {
      next.add(field);
    } else {
      next.remove(field);
    }
    state = NotifFieldsConfig(state.order, next);
    await _persist();
  }

  /// Move a field within the display order (ReorderableListView indices).
  Future<void> reorder(int oldIndex, int newIndex) async {
    final order = List.of(state.order);
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = order.removeAt(oldIndex);
    order.insert(newIndex, moved);
    state = NotifFieldsConfig(order, state.enabled);
    await _persist();
  }
}

final notificationFieldsProvider =
    NotifierProvider<NotificationFieldsNotifier, NotifFieldsConfig>(
  NotificationFieldsNotifier.new,
);
