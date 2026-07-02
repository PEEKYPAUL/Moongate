import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:ui' as ui;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../models/notif_fields.dart';
import '../models/printer_config.dart';
import 'heatsoak_timers.dart';
import 'print_control_service.dart';
import 'print_progress.dart';
import 'printer_access_cache.dart';
import 'printer_registry.dart';
import 'supabase_service.dart';

// ── Tuning ────────────────────────────────────────────────────────────────
// Everything posts on ONE silent channel, "Print status":
//   • the persistent foreground-service notification - a status-only roster of
//     every printer (Name - Printing / Ready / Idle / Offline). No numbers; the
//     live detail lives on the cards below;
//   • one live card per active print: progress while it runs, then a clearable
//     "Finished <time>" summary.
// The cards used to live on a separate HIGH-importance "Print jobs" channel so
// they could buzz on start/finish - but a HIGH card always outranks the LOW,
// silent roster in the shade, and as both refresh each poll Android kept
// re-sorting them (the two "swapped places"). Sharing the LOW channel keeps each
// card pinned directly under the roster and silent; _postActiveCard also fixes
// each card's `when` to its print-start so the roster - refreshed to "now" every
// poll - keeps sorting above it. The old 'alerts' channel is deleted on startup.
const _serviceChannelId     = 'moongate_print_progress';
const _serviceChannelName   = 'Print status';
const _serviceChannelDesc   = 'A live, at-a-glance status of all your printers.';
// Legacy HIGH-importance card channel, retired for the shared status channel
// above. Kept only so onStart can delete it from existing installs.
const _legacyCardsChannelId = 'moongate_print_alerts';
const _serviceId            = 4711;

// Discrete, attention-grabbing channel for the one-shot "Heat-soak complete"
// alert fired when a preheat / soak timer set on a tile elapses. HIGH (it
// buzzes) - unlike the silent status roster + cards - because the whole point is
// to call the user back to the machine. A separate channel so it can be muted on
// its own. See HeatsoakTimers (the armed deadlines) + _fireDueHeatsoaks.
const _heatsoakChannelId   = 'moongate_heatsoak';
const _heatsoakChannelName = 'Heatsoak timer';
const _heatsoakChannelDesc =
    'Alerts you when a preheat / heat-soak timer set on a printer finishes.';

// A soak deadline this far past when the isolate finally sees it (e.g.
// notifications were off across the deadline) is dropped without buzzing rather
// than firing a confusing late alert.
const _heatsoakStaleMs = 60 * 60 * 1000; // 1 hour

// Default poll cadence, overridden by the user's "Update frequency" setting
// (`notif_poll_interval`). The chosen interval is the ACTUAL poll rate - there
// is no idle backoff, so a print start / error / recovery shows within one
// tick. LAN-first, so it's free at home and a long print costs ~1-2 MB cellular.
const _defaultPollIntervalMs = 30000;

/// Map the persisted `notif_poll_interval` enum name to milliseconds.
int _pollIntervalMsFromPref(String? name) => switch (name) {
      's5'  => 5000,
      's10' => 10000,
      's15' => 15000,
      'm1'  => 60000,
      _     => _defaultPollIntervalMs, // 's30' / unset
    };

/// Load the user's chosen UI locale (or the system / English fallback) and
/// return its AppLocalizations. Usable from the background isolate - it's a pure
/// Dart load with no BuildContext - so the notification reads in the same
/// language as the app even though it runs outside the widget tree.
Future<AppLocalizations> _loadL10n() async {
  var code = (await SharedPreferences.getInstance()).getString('app_locale');
  code ??= ui.PlatformDispatcher.instance.locale.languageCode;
  try {
    return await AppLocalizations.delegate.load(ui.Locale(code));
  } catch (_) {
    return AppLocalizations.delegate.load(const ui.Locale('en'));
  }
}

/// Main-isolate manager for the opt-in print-notification foreground service.
/// The actual polling runs in a background isolate (`_PrintTaskHandler`) so it
/// survives the UI being backgrounded. OFF by default - see
/// `printNotificationsEnabledProvider`.
class PrintNotificationService {
  PrintNotificationService._();
  static final PrintNotificationService instance = PrintNotificationService._();

  bool _configured = false;
  int  _configuredIntervalMs = _defaultPollIntervalMs;

  /// Read the user's chosen poll interval (ms) from SharedPreferences.
  Future<int> _readPollIntervalMs() async {
    final prefs = await SharedPreferences.getInstance();
    return _pollIntervalMsFromPref(prefs.getString('notif_poll_interval'));
  }

  void _configure(int intervalMs) {
    if (_configured && _configuredIntervalMs == intervalMs) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _serviceChannelId,
        channelName: _serviceChannelName,
        channelDescription: _serviceChannelDesc,
        // LOW + onlyAlertOnce: a silent, persistent progress notification that
        // updates in place without buzzing on every percent.
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(intervalMs),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _configured = true;
    _configuredIntervalMs = intervalMs;
  }

  /// Request the Android 13+ POST_NOTIFICATIONS permission. Returns true when
  /// granted. Safe to call before [start].
  Future<bool> requestPermission() async {
    _configure(await _readPollIntervalMs());
    final result = await FlutterForegroundTask.requestNotificationPermission();
    return result == NotificationPermission.granted;
  }

  /// Start the foreground service if it isn't already running.
  Future<void> start() async {
    _configure(await _readPollIntervalMs());
    if (await FlutterForegroundTask.isRunningService) return;
    final l = await _loadL10n();
    await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      notificationTitle: 'Moongate',
      notificationText: l.printNotifWatching,
      notificationIcon: const NotificationIcon(
          metaDataName: 'com.moongate.app.notification_icon'),
      callback: startPrintNotificationCallback,
    );
  }

  /// Stop the foreground service if it is running.
  Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  /// Align the running service with the persisted on/off toggle. Called at
  /// startup and whenever the toggle changes.
  Future<void> sync(bool enabled) => enabled ? start() : stop();

  /// Re-read the poll interval and, if the service is running, restart it so a
  /// new cadence takes effect at once (the repeat interval is fixed at service
  /// start, so changing it needs a stop/start).
  Future<void> reschedule() async {
    if (await FlutterForegroundTask.isRunningService) {
      await stop();
      await start();
    }
  }

  /// Poke the running background task to refresh the notification immediately -
  /// call after the printer set changes (pair / remove / restore) so it updates
  /// at once instead of waiting for the next poll. No-op when off.
  Future<void> refreshNow() async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask('refresh');
    }
  }
}

/// Foreground-task isolate entry point. MUST be a top-level function.
@pragma('vm:entry-point')
void startPrintNotificationCallback() {
  FlutterForegroundTask.setTaskHandler(_PrintTaskHandler());
}

/// Runs in the background isolate. On each tick it polls every printer's
/// `/status`, refreshes the persistent status roster (one line per printer),
/// and maintains a live "Print jobs" card per active print - progress while it
/// runs, a clearable summary when it finishes (clearing it resets the print so
/// the dashboard and roster settle to Ready together).
class _PrintTaskHandler extends TaskHandler {
  final _alerts = FlutterLocalNotificationsPlugin();
  bool _busy = false;
  // Per-printer lifecycle of its print card: none → active (a live print) → done
  // (a clearable finished/cancelled/error summary). Drives when the card is
  // posted, updated and cleared. In-memory only - a service restart re-derives
  // it from the next poll.
  final Map<String, _CardPhase> _cardPhase = {};
  // Wall-clock (epoch ms) each printer's current card started. Used as the card's
  // fixed `when` so it sorts just under the roster - see _postActiveCard.
  final Map<String, int> _cardStartedAt = {};
  // Cloud last_seen per printer, refreshed once per tick by a single RLS-scoped
  // SELECT (PostgREST, NOT an Edge Function). Lets _poll skip the token mint for
  // a printer that's positively offline - see _isKnownOffline.
  Map<String, DateTime> _lastSeen = {};
  // Per-printer gcode byte offsets (from file metadata), cached per filename so
  // the notification's progress matches Mainsail's file-relative default and the
  // dashboard. Fetched once per print - see _fetchOffsets.
  final Map<String, _MetaOffsets> _meta = {};

  /// Per-printer extra-hotend object keys (`extruder1`, `extruder2`, ...),
  /// discovered once via `printer/objects/list` so multi-toolhead temps can be
  /// supplemented each tick. A cached empty list means "single hotend - never
  /// re-query"; a printer absent from the map hasn't been discovered yet.
  final Map<String, List<String>> _extraExtruders = {};
  late AppLocalizations _l;
  // Which notification segments to show + their order - re-read from prefs each
  // tick (the user edits them on the main isolate). Defaults to all-on.
  NotifFieldsConfig _fields = NotifFieldsConfig.defaults();

  void _log(String msg) => dev.log(msg, name: 'MOONGATE/NOTIF');

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Background isolate: register plugins so http / shared_preferences /
    // supabase channels work here.
    try {
      ui.DartPluginRegistrant.ensureInitialized();
    } catch (_) {}

    await _alerts.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_moongate'),
    ));
    final androidPlugin = _alerts.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // Live print cards share the foreground service's silent "Print status"
    // channel so they sit with - and just under - the status roster instead of
    // outranking it (a HIGH card always floats above the LOW roster, which made
    // the two swap places). Ensure it exists at LOW importance; the service
    // creates it too, so this is idempotent.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _serviceChannelId,
        _serviceChannelName,
        description: _serviceChannelDesc,
        importance: Importance.low,
      ),
    );
    // Retire the old HIGH-importance "Print jobs" channel from earlier builds so
    // it stops lingering in the user's notification settings. No-op if absent.
    await androidPlugin?.deleteNotificationChannel(_legacyCardsChannelId);

    // Discrete HIGH channel for the one-shot heat-soak alert (buzzes, unlike the
    // silent roster). Idempotent - created here so it exists the moment a timer
    // is armed.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _heatsoakChannelId,
        _heatsoakChannelName,
        description: _heatsoakChannelDesc,
        importance: Importance.high,
      ),
    );

    // Clear any per-print cards stranded by a previous run (force-stop / crash)
    // so we never show a stale "printing" card. Only our card-id range is
    // touched - never the foreground-service notification (id 4711).
    try {
      for (final a in await _alerts.getActiveNotifications()) {
        final id = a.id;
        if (id != null && id != _serviceId && (id & 0x10000000) != 0) {
          await _alerts.cancel(id);
        }
      }
    } catch (_) {}

    // Supabase in this isolate re-loads the persisted anon session, so it can
    // mint the same per-printer access tokens the app uses.
    try {
      await SupabaseService.instance.initialize();
    } catch (e) {
      _log('Supabase init failed in isolate: $e');
    }

    _l = await _loadL10n(); // localise the notification to the app's language

    // Locale-aware 12/24h clock for the print-finish ETA. This background
    // isolate has no BuildContext (so no TimeOfDay.format); intl's locale
    // formatter needs its symbol data loaded once before DateFormat.jm runs.
    try {
      await initializeDateFormatting();
    } catch (_) {}

    _tick(); // immediate first poll so the notification isn't empty for 30s
  }

  @override
  void onRepeatEvent(DateTime timestamp) => _tick();

  @override
  void onReceiveData(Object data) {
    // Main app signalled a printer add / remove / restore - refresh now rather
    // than waiting for the next 30s/2min tick. _tick() reloads the registry
    // from disk, so it picks up the change immediately.
    _tick();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Service stopped (notifications turned off) - remove our per-print cards;
    // the foreground-service roster is torn down by the plugin separately.
    for (final pid in _cardPhase.keys.toList()) {
      try {
        await _alerts.cancel(_cardId(pid));
      } catch (_) {}
    }
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      // Re-read the notification-content config the user may have changed on the
      // main isolate. SharedPreferences caches per-isolate, so reload() first or
      // we'd never see their edits (same gotcha as the printer-set refresh).
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      _fields = NotifFieldsConfig.fromPrefs(
        prefs.getString(kNotifFieldsOrderKey),
        prefs.getString(kNotifFieldsEnabledKey),
      );
      final onlineOnly = prefs.getBool(kNotifOnlineOnlyKey) ?? false;
      // Mirror the dashboard's "Auto-arrange by status" toggle (same key +
      // default as autoArrangeProvider): ON floats active prints to the top by
      // live status; OFF keeps the user's saved manual order so the roster
      // matches the tiles.
      final autoArrange = prefs.getBool(kAutoArrangeByStatusKey) ?? true;

      await PrinterRegistry.instance.load();
      final printers = PrinterRegistry.instance.printers;

      // One cheap fleet read of last_seen (PostgREST, not an Edge call) gates the
      // per-printer token mints below, so an offline printer costs zero Edge
      // Function calls even though this service polls 24/7.
      await _refreshLiveness();

      final entries = <(String, _Poll?)>[];
      final postedDoneThisTick = <String>{};

      for (final p in printers) {
        final s = await _poll(p);

        // Only a LIVE /status read (a genuine Klipper state) drives the card
        // lifecycle. A connectivity placeholder (synthetic Idle, live == false)
        // or an offline tick (s == null) must NOT touch the cards - otherwise a
        // transient network blip looks like the print ending and would wrongly
        // clear the card. Offline mid-print just leaves the existing card alone.
        if (s != null && s.live) {
          await _updateCardFor(p, s, postedDoneThisTick);
        }

        entries.add((p.name, s)); // every printer, online or not
      }

      // Float active prints to the top - same ranking the dashboard uses
      // (printerStatusRank), stable within a tier (original order preserved).
      // Only when auto-arrange is on; off = keep the manual dashboard order
      // (entries are already in the registry order the tiles use).
      final List<(String, _Poll?)> sorted;
      if (autoArrange) {
        final ranked = [for (var i = 0; i < entries.length; i++) (i, entries[i])];
        ranked.sort((a, b) {
          final ra = _rank(a.$2.$2);
          final rb = _rank(b.$2.$2);
          return ra != rb ? ra.compareTo(rb) : a.$1.compareTo(b.$1);
        });
        sorted = [for (final r in ranked) r.$2];
      } else {
        sorted = entries;
      }

      // "Show only online devices": drop offline / shut-down printers from the
      // roster (the foreground service keeps running - this is display-only).
      final shown =
          onlineOnly ? [for (final e in sorted) if (!_isOffline(e.$2)) e] : sorted;

      await _updatePersistent(shown,
          noneOnline: onlineOnly && shown.isEmpty && printers.isNotEmpty);

      // A "Finished" card that's vanished from the shade since a prior tick was
      // swiped away or cleared via its ✕ action - treat that as the user
      // clearing the print and reset Klipper to standby, so the dashboard badge
      // and the roster line settle to Ready together.
      await _detectClearedDoneCards(printers, postedDoneThisTick);

      // Heat-soak timers: fire the one-shot alert for any printer whose soak
      // deadline (armed from the tile's preheat sheet) has elapsed. Piggybacks
      // this poll loop - so it only runs while notifications are enabled, which
      // the preheat sheet warns about up front.
      await _fireDueHeatsoaks(printers);
    } catch (e) {
      _log('tick failed: $e');
    } finally {
      _busy = false;
    }
  }

  /// Sort rank for a printer's notification line - shares printerStatusRank
  /// with the dashboard so the two orderings stay identical. A warming printer
  /// counts as 'heating' (Printing tier); an unreachable one as 'offline'.
  int _rank(_Poll? s) {
    if (s == null) return printerStatusRank('offline');
    if (s.state == 'shutdown') return printerStatusRank('offline');
    if (_warming(s)) return printerStatusRank('heating');
    return printerStatusRank(s.state);
  }

  /// A roster entry that renders as "Offline": unreachable (null poll) or a
  /// shut-down Klipper. The "show only online devices" filter hides these.
  static bool _isOffline(_Poll? s) => s == null || s.state == 'shutdown';

  Future<void> _updatePersistent(List<(String, _Poll?)> entries,
      {bool noneOnline = false}) async {
    final String title;
    final String text;
    if (entries.isEmpty) {
      title = 'Moongate';
      // "Show only online devices" on with every printer offline: show the calm
      // idle watcher line (as at service start) instead of the alarming "No
      // printers online", which a user flagged as naggy (#126). The real fix,
      // letting the watcher sleep via push, is tracked separately.
      text = noneOnline ? _l.printNotifWatching : _l.printNotifNoPrinters;
    } else if (entries.length == 1) {
      // Single printer: emoji + full status on the title line.
      title = _statusLine(entries.first.$1, entries.first.$2, withEmoji: true);
      text = '';
    } else {
      // Collapsed glance = just the status emojis (one per printer, in order).
      // Expanded body = the full per-printer lines, with NO repeated emoji so
      // it reads cleanly rather than busy.
      title = entries.map((e) => _emoji(e.$2)).join(' ');
      text = entries.map((e) => _statusLine(e.$1, e.$2)).join('\n');
    }
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  // ── Liveness (offline gate) ─────────────────────────────────────────────────

  /// Refresh every owned printer's cloud last_seen in one RLS-scoped query
  /// (PostgREST - not an Edge Function). Best-effort: on failure we keep the
  /// previous snapshot, and the gate fails open on anything unknown.
  Future<void> _refreshLiveness() async {
    try {
      final rows = await SupabaseService.instance.client
          .from('printers')
          .select('id, last_seen');
      final next = <String, DateTime>{};
      for (final r in rows as List) {
        final id = r['id'] as String?;
        final raw = r['last_seen'] as String?;
        if (id == null || raw == null) continue;
        final ts = DateTime.tryParse(raw);
        if (ts != null) next[id] = ts.toUtc();
      }
      _lastSeen = next;
    } catch (_) {
      // Keep the prior snapshot; _isKnownOffline fails open on unknown ids.
    }
  }

  /// True only with positive evidence the printer is offline: a known last_seen
  /// older than the window (2× the 5-min heartbeat + slack). Unknown → false, so
  /// the gate fails open and polls rather than hiding a live printer.
  bool _isKnownOffline(String printerId) {
    final ts = _lastSeen[printerId];
    if (ts == null) return false;
    return DateTime.now().toUtc().difference(ts) >= const Duration(minutes: 12);
  }

  /// Token-free LAN reachability: HEAD the persisted LAN URL; any HTTP answer
  /// (even 401) means the Pi is up on this network, so a printer that's offline
  /// in the cloud but reachable on the LAN still gets polled. Remote → fast-fail.
  Future<bool> _lanHeadReachable(PrinterConfig p) async {
    final lan = p.lanUrl;
    if (lan == null || lan.isEmpty) return false;
    try {
      await http.head(Uri.parse(lan)).timeout(const Duration(seconds: 2));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  Future<_Poll?> _poll(PrinterConfig p) async {
    // Liveness gate (mirrors the dashboard): skip the token mint - an Edge call
    // - for a printer with positive evidence of being offline (stale cloud
    // last_seen) and no token-free LAN answer. Fails open on unknown last_seen.
    if (_isKnownOffline(p.id) && !await _lanHeadReachable(p)) {
      return null; // offline → no token, zero Edge Function cost
    }
    final PrinterAccess access;
    try {
      // Cached per-isolate so a 30 s / 5 s poll loop reuses one token for
      // ~4.5 min instead of minting a fresh one from /printer-access on every
      // single tick. Running 24/7 in this foreground service, the uncached call
      // was a major source of Edge Function invocations - even for printers
      // that are powered off (their last token mints fine regardless).
      access = await PrinterAccessCache.instance.get(p.id);
    } catch (_) {
      return null; // offline / not yet heartbeated / network
    }
    final bases = <(String, bool)>[
      if (p.lanUrl != null && p.lanUrl!.isNotEmpty) (p.lanUrl!, true),
      if (access.tunnelUrl != null && access.tunnelUrl!.isNotEmpty)
        (access.tunnelUrl!, false),
    ];
    for (final (base, isLan) in bases) {
      final r = await _fetchStatus(p.id, base, access.accessToken, isLan);
      if (r != null) return r;
    }
    // No /status answer on any path. Distinguish a Pi that's up but whose
    // Moongate/Klipper stack isn't responding (Idle) from one that's genuinely
    // unreachable / powered off (Offline). A stale tunnel URL lingers in the
    // cloud after a Pi shuts down (printer-access still hands back the last
    // known one), so "a tunnel URL exists" is NOT proof of life - probe like
    // the dashboard does. The synthetic Idle is marked live: false so it never
    // drives a state-change alert.
    if (await _isReachable(p, access)) {
      return const _Poll(
        state: 'waiting',
        progress: 0,
        printDurationSec: 0,
        hotend: 0,
        hotendTarget: 0,
        bed: 0,
        bedTarget: 0,
        live: false,
      );
    }
    return null; // genuinely unreachable → Offline
  }

  /// HEAD the LAN and tunnel bases: ANY HTTP answer (even a 401 / 502) proves
  /// the host is up; only a thrown error means nothing is listening. Mirrors
  /// [PrinterStatusService] `_isPiReachable` so the notification's
  /// Idle-vs-Offline call matches the dashboard's. Used after every /status
  /// path has failed, to avoid labelling a powered-off printer "Idle".
  Future<bool> _isReachable(PrinterConfig p, PrinterAccess access) async {
    final candidates = <String>[
      if (p.lanUrl != null && p.lanUrl!.isNotEmpty) p.lanUrl!,
      if (access.tunnelUrl != null && access.tunnelUrl!.isNotEmpty)
        access.tunnelUrl!,
    ];
    for (final base in candidates) {
      try {
        await http.head(Uri.parse(base)).timeout(const Duration(seconds: 4));
        return true;
      } catch (_) {
        // Refused / timeout / DNS - try the next candidate.
      }
    }
    return false;
  }

  Future<_Poll?> _fetchStatus(
      String printerId, String base, String token, bool isLan) async {
    try {
      final uri = Uri.parse(
          '$base/server/moongate/status?mg_token=${Uri.encodeComponent(token)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final result = body['result'] as Map<String, dynamic>?;
      final status = result?['status'] as Map<String, dynamic>?;
      if (status == null) return null;

      final printStats = status['print_stats'] as Map<String, dynamic>? ?? const {};
      final extruder   = status['extruder']     as Map<String, dynamic>? ?? const {};
      final bed        = status['heater_bed']   as Map<String, dynamic>? ?? const {};

      // The plugin's /status returns ONLY print_stats / heater_bed / extruder -
      // progress lives in display_status & virtual_sdcard, which aren't in this
      // payload. Mirror PrinterStatusService and pull them from a supplementary
      // /printer/objects/query, otherwise % stays pinned at 0 the whole print.
      var display  = status['display_status'] as Map<String, dynamic>?;
      var sdcard   = status['virtual_sdcard'] as Map<String, dynamic>?;
      var webhooks = status['webhooks'] as Map<String, dynamic>?;
      if (display == null || sdcard == null || webhooks == null) {
        final supp = await _fetchProgress(base, token, isLan: isLan);
        display  ??= supp?['display_status'] as Map<String, dynamic>?;
        sdcard   ??= supp?['virtual_sdcard'] as Map<String, dynamic>?;
        webhooks ??= supp?['webhooks'] as Map<String, dynamic>?;
      }

      // Klipper not engaged - e.g. the printer's mainboard is switched off while
      // the Pi stays powered (common, with a separate Pi supply). Moonraker still
      // answers, but print_stats is FROZEN at its last value (often "printing")
      // with no live temps - so trusting it shows a stale "Printing" and leaves
      // the print card stuck. webhooks.state is the source of truth; mirror the
      // dashboard (PrinterStatusService) and treat shutdown/error as offline, so
      // the roster reads Offline and _updateCardFor clears the stuck card.
      final klippyState = webhooks?['state'] as String?;
      if (klippyState == 'shutdown' || klippyState == 'error') {
        return const _Poll(
          state:            'shutdown',
          progress:         0,
          printDurationSec: 0,
          hotend:           0,
          hotendTarget:     0,
          bed:              0,
          bedTarget:        0,
        );
      }

      final state    = (printStats['state'] as String?) ?? 'standby';
      final filename = printStats['filename'] as String?;

      // File-relative progress, matching Mainsail and the dashboard (shared
      // computePrintProgress). Needs the gcode byte offsets from file metadata;
      // fetch them once per print, cached per printer. Until they load we fall
      // back to display_status / virtual_sdcard (within ~1% of Mainsail).
      _MetaOffsets? offsets;
      if (state == 'printing' && filename != null && filename.isNotEmpty) {
        offsets =
            await _fetchOffsets(printerId, base, token, filename, isLan: isLan);
      }
      final progress = computePrintProgress(
        filePosition:    (sdcard?['file_position'] as num?)?.toDouble(),
        gcodeStartByte:  offsets?.startByte,
        gcodeEndByte:    offsets?.endByte,
        displayProgress: (display?['progress'] as num?)?.toDouble(),
        sdcardProgress:  (sdcard?['progress'] as num?)?.toDouble(),
      );

      // Multi-toolhead temps for the notification's hotend line (Option C:
      // "🔥210° 205° 25°"). Only while a card actually shows temps (printing /
      // paused), and only when the printer reports extra hotends. T0 is the
      // extruder already in this payload; the rest come from a supplement that
      // hits the Pi directly (no Supabase cost), mirroring PrinterStatusService.
      final toolheads = <ToolheadTemp>[
        ToolheadTemp(
          index:  0,
          temp:   (extruder['temperature'] as num?)?.toDouble() ?? 0,
          target: (extruder['target']      as num?)?.toDouble() ?? 0,
        ),
      ];
      if (state == 'printing' || state == 'paused') {
        final extras =
            await _discoverExtruders(printerId, base, token, isLan: isLan);
        if (extras.isNotEmpty) {
          final supp = await _fetchExtruders(base, token, extras, isLan: isLan);
          if (supp != null) {
            for (final key in extras) {
              final obj = supp[key] as Map<String, dynamic>?;
              if (obj == null) continue;
              toolheads.add(ToolheadTemp(
                index:  int.tryParse(key.substring(8)) ?? 0,
                temp:   (obj['temperature'] as num?)?.toDouble() ?? 0,
                target: (obj['target']      as num?)?.toDouble() ?? 0,
              ));
            }
            toolheads.sort((a, b) => a.index.compareTo(b.index));
          }
        }
      }

      return _Poll(
        state:            state,
        progress:         progress,
        printDurationSec: (printStats['print_duration'] as num?)?.toDouble() ?? 0,
        hotend:           (extruder['temperature'] as num?)?.toDouble() ?? 0,
        hotendTarget:     (extruder['target']      as num?)?.toDouble() ?? 0,
        bed:              (bed['temperature']      as num?)?.toDouble() ?? 0,
        bedTarget:        (bed['target']           as num?)?.toDouble() ?? 0,
        toolheads:        toolheads,
      );
    } catch (_) {
      return null;
    }
  }

  /// Supplementary fetch. The moongate /status payload omits display_status,
  /// virtual_sdcard & webhooks (Klipper health), so read them from Moonraker:
  /// LAN goes through nginx untouched (no auth header - Moonraker would reject
  /// our EdDSA token as a bad JWT), the tunnel goes through the auth proxy
  /// (Bearer). Best-effort - null on any failure just leaves progress at 0.
  Future<Map<String, dynamic>?> _fetchProgress(String base, String token,
      {required bool isLan}) async {
    try {
      final uri = Uri.parse(
          '$base/printer/objects/query?display_status&virtual_sdcard&webhooks');
      final resp = await http
          .get(uri, headers: isLan ? null : {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['result']?['status'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Fetch + cache the printing file's gcode body byte offsets (per printer, per
  /// filename) so progress can be computed file-relative like Mainsail. Fetched
  /// once per print - the offsets don't change - so it adds no per-tick cost. On
  /// any failure the previous cache entry is kept (progress just falls back).
  Future<_MetaOffsets?> _fetchOffsets(
      String printerId, String base, String token, String filename,
      {required bool isLan}) async {
    final cached = _meta[printerId];
    if (cached != null && cached.filename == filename) return cached;
    try {
      final uri = Uri.parse(
          '$base/server/files/metadata?filename=${Uri.encodeComponent(filename)}');
      final resp = await http
          .get(uri, headers: isLan ? null : {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return cached;
      final result = (jsonDecode(resp.body) as Map<String, dynamic>)['result']
          as Map<String, dynamic>?;
      final m = _MetaOffsets(
        filename,
        (result?['gcode_start_byte'] as num?)?.toInt(),
        (result?['gcode_end_byte']   as num?)?.toInt(),
      );
      _meta[printerId] = m;
      return m;
    } catch (_) {
      return cached;
    }
  }

  // ── Multi-toolhead temps (extra hotends) ─────────────────────────────────

  /// Discover a printer's extra hotend object names (`extruder1`, `extruder2`,
  /// ...) once via `printer/objects/list`, cached per printer. Klipper names
  /// extra hotends `extruder{N}`; `extruder_stepper <name>` helpers carry a
  /// space, so an exact `^extruder\d+$` match picks only real hotends. A cached
  /// empty list means single-hotend (never re-queried). Only cached on a 200 so
  /// a cold-tunnel blip retries next tick. Pi-direct - no Supabase cost.
  Future<List<String>> _discoverExtruders(
      String printerId, String base, String token,
      {required bool isLan}) async {
    final cached = _extraExtruders[printerId];
    if (cached != null) return cached;
    try {
      final uri = Uri.parse('$base/printer/objects/list');
      final resp = await http
          .get(uri, headers: isLan ? null : {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return const [];
      final objects =
          (jsonDecode(resp.body)['result']?['objects'] as List<dynamic>?) ??
              const [];
      final extra = <String>[];
      for (final o in objects) {
        final key = o.toString();
        if (RegExp(r'^extruder\d+$').hasMatch(key)) extra.add(key);
      }
      extra.sort((a, b) =>
          int.parse(a.substring(8)).compareTo(int.parse(b.substring(8))));
      _extraExtruders[printerId] = extra;
      return extra;
    } catch (_) {
      return const [];
    }
  }

  /// Fetch the live objects for [keys] (a printer's extra hotends) in one
  /// `printer/objects/query`, returning the Moonraker `status` map or null on
  /// failure. Same header rule as the other supplements (LAN header-less, tunnel
  /// Bearer).
  Future<Map<String, dynamic>?> _fetchExtruders(
      String base, String token, List<String> keys,
      {required bool isLan}) async {
    try {
      final query = keys.map(Uri.encodeComponent).join('&');
      final uri = Uri.parse('$base/printer/objects/query?$query');
      final resp = await http
          .get(uri, headers: isLan ? null : {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['result']?['status'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  // ── Formatting ──────────────────────────────────────────────────────────────

  /// True while a heater is still ramping to a set target and we should show a
  /// "Heating" line instead of the static Ready/Idle/0% label - i.e. pre-print
  /// soak, or the start of a print before extrusion (progress still ~0). Not
  /// for a paused print, where "Paused x%" is the more useful line.
  bool _warming(_Poll s) =>
      s.isHeating &&
      s.state != 'paused' &&
      (s.state != 'printing' || s.progress < 0.02);

  /// One line per printer for the status roster: just the name and a plain
  /// state word. All the live detail (progress, ETA, temps) lives on the
  /// per-print "Print jobs" card now, not here.
  String _statusLine(String name, _Poll? s, {bool withEmoji = false}) {
    final e = withEmoji ? '${_emoji(s)} ' : '';
    return '$e$name - ${_rosterLabel(s)}';
  }

  /// The plain state word shown for a printer on the status roster: Offline /
  /// Heating / Printing / Paused / Error / Starting up / Idle / Ready. A
  /// finished or cancelled print reads "Ready" - the printer is free again and
  /// the card carries the outcome.
  String _rosterLabel(_Poll? s) {
    if (s == null) return _l.printStatusOffline;
    if (_warming(s)) return _l.printStatusHeating;
    switch (s.state) {
      case 'printing':
        return _l.printStatusPrinting;
      case 'paused':
        return _l.printStatusPaused;
      case 'complete':
      case 'cancelled':
        return _l.printStatusReady;
      case 'error':
        return _l.printStatusError;
      case 'shutdown':
        return _l.printStatusOffline;
      case 'startup':
      case 'starting_up':
      case 'connecting':
        return _l.printStatusStartingUp;
      case 'waiting':
        return _l.printStatusIdle;
      case 'standby':
      default:
        return _l.printStatusReady;
    }
  }

  /// Render one configured [field] for state [s], or null when it doesn't apply
  /// (e.g. remaining/ETA before the print is far enough along to estimate).
  String? _fieldSegment(NotifField field, _Poll s) {
    switch (field) {
      case NotifField.progress:
        return '${(s.progress * 100).round()}%';
      case NotifField.remaining:
        final rem = _remainingSeconds(s);
        return rem == null ? null : '~${_formatRemaining(rem)}';
      case NotifField.eta:
        final rem = _remainingSeconds(s);
        if (rem == null) return null;
        final clock = _formatFinishClock(rem);
        return clock == null ? null : '$kNotifEtaMarker$clock';
      case NotifField.hotend:
        // Multi-toolhead: list every hotend's live temperature after one 🔥,
        // space-joined and positional (T0, T1, ... in order) - e.g.
        // "🔥210° 205° 25°". A single-hotend printer keeps the classic "🔥210°".
        if (s.toolheads.length > 1) {
          return kNotifHotendMarker +
              s.toolheads.map((t) => '${t.temp.round()}°').join(' ');
        }
        return '$kNotifHotendMarker${s.hotend.round()}°';
      case NotifField.bed:
        return '$kNotifBedMarker${s.bed.round()}°';
    }
  }

  /// Status emoji used as the line / summary prefix.
  String _emoji(_Poll? s) {
    if (s == null) return '⚫';
    if (_warming(s)) return '🔥';
    switch (s.state) {
      case 'printing':
        return '🖨️';
      case 'paused':
        return '⏸️';
      // A finished print reads "Ready" on the roster (see _rosterLabel), so its
      // glance emoji is the ready dot too - the card carries the ✓.
      case 'complete':
        return '🟢';
      case 'error':
        return '🔴';
      case 'shutdown':
        return '⚫';
      case 'waiting':
        return '🟡';
      case 'startup':
      case 'starting_up':
      case 'connecting':
        return '⏳';
      case 'standby':
      default:
        return '🟢';
    }
  }

  /// Print time remaining (seconds), estimated from elapsed/progress with no
  /// extra metadata call. Null while it's too early - or implausibly long - to
  /// be meaningful.
  double? _remainingSeconds(_Poll s) {
    if (s.state != 'printing') return null;
    if (s.progress < 0.02 || s.printDurationSec < 30) return null;
    final remaining = s.printDurationSec * (1 - s.progress) / s.progress;
    if (remaining <= 0 || remaining > 100 * 3600) return null;
    return remaining;
  }

  /// "1h05m" / "14m" - how much longer the print has to run.
  String _formatRemaining(double seconds) {
    final d = Duration(seconds: seconds.round());
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}m' : '${m}m';
  }

  /// Wall-clock time the print is projected to finish ("1:20 AM" / "13:20"),
  /// localised 12/24h via the loaded UI locale - the same "ETA" Klipper and
  /// Mainsail display. Null if the locale's date symbols didn't load, so the
  /// line just falls back to showing the remaining duration alone.
  String? _formatFinishClock(double remainingSeconds) {
    try {
      final finish =
          DateTime.now().add(Duration(seconds: remainingSeconds.round()));
      return DateFormat.jm(_l.localeName).format(finish);
    } catch (_) {
      return null;
    }
  }

  // ── Print-job cards ─────────────────────────────────────────────────────────
  //
  // One card per actively-printing printer, posted on the same silent "Print
  // status" channel as the roster so it sits directly under it (never above).
  // It appears quietly when a print starts, updates its progress silently while
  // running, then collapses to a clearable "Finished <time>" card when the job
  // ends. Clearing that card - by swipe or its ✕ action - is detected on the
  // next poll and resets the print, so the dashboard badge and the roster line
  // settle to Ready together.

  /// Stable per-printer notification id for its card. High bit 0x10000000 marks
  /// it as one of ours (and keeps it clear of the foreground-service id 4711),
  /// so a stale card can be recognised and cancelled without touching the
  /// roster notification.
  int _cardId(String printerId) =>
      0x10000000 | (printerId.hashCode & 0x0FFFFFFF);

  /// Drive one printer's card from a fresh live poll. [prev] is its previous
  /// Klipper state (null on the first observation since the service started).
  Future<void> _updateCardFor(
      PrinterConfig p, _Poll s, Set<String> postedDoneThisTick) async {
    final cur = s.state;
    final phase = _cardPhase[p.id] ?? _CardPhase.none;
    final isActive = cur == 'printing' || cur == 'paused';
    final isTerminal =
        cur == 'complete' || cur == 'cancelled' || cur == 'error';

    if (isActive) {
      // Fix the card's timestamp at the print's start (first active tick) so it
      // stays put under the ever-refreshed roster - see _postActiveCard.
      final startedMs = _cardStartedAt.putIfAbsent(
          p.id, () => DateTime.now().millisecondsSinceEpoch);
      await _postActiveCard(p, s, startedMs);
      _cardPhase[p.id] = _CardPhase.active;
    } else if (isTerminal) {
      // Only collapse to a Done card if we were actually tracking a live print.
      // Klipper holds the terminal state until the next print, so seeing it from
      // `none` is a re-observation (launch / a reset elsewhere), not a fresh
      // finish - posting then would show a stray card.
      if (phase == _CardPhase.active) {
        final startedMs =
            _cardStartedAt[p.id] ?? DateTime.now().millisecondsSinceEpoch;
        await _postDoneCard(p, cur, startedMs);
        _cardPhase[p.id] = _CardPhase.done;
        postedDoneThisTick.add(p.id);
      }
    } else {
      // standby / idle / starting up: the printer is free. Clear any card we
      // had - this is also how an in-app reset (or the next print) removes the
      // Done card: the state returns to standby and we cancel here.
      if (phase != _CardPhase.none) {
        await _alerts.cancel(_cardId(p.id));
        _cardPhase[p.id] = _CardPhase.none;
        _cardStartedAt.remove(p.id);
      }
    }
  }

  /// Post / update the live card for a running (or paused) print. Pinned
  /// (`ongoing`) so it can't be swiped away mid-print. The detail (progress %,
  /// remaining, ETA, temps) all rides in the one-line [_cardBody] so it reads in
  /// the collapsed shade without expanding - deliberately NO progress bar: in the
  /// collapsed view the bar sits in place of that body line, which is exactly
  /// what users had to expand the card to get past.
  ///
  /// Silent, on the shared "Print status" channel, with [startedMs] (the print's
  /// start) as a fixed `when`: same LOW importance as the roster so it can't
  /// outrank it, and an older timestamp so the roster - refreshed to "now" every
  /// poll - keeps sorting above it. Together that pins the card just under the
  /// roster and stops the two swapping places in the shade.
  Future<void> _postActiveCard(PrinterConfig p, _Poll s, int startedMs) async {
    final android = AndroidNotificationDetails(
      _serviceChannelId,
      _serviceChannelName,
      channelDescription: _serviceChannelDesc,
      importance: Importance.low,
      priority: Priority.low,
      silent: true,
      onlyAlertOnce: true,
      icon: 'ic_stat_moongate',
      ongoing: true,
      when: startedMs,
      showWhen: false,
    );
    await _alerts.show(_cardId(p.id), p.name, _cardBody(s),
        NotificationDetails(android: android));
  }

  /// Post the clearable summary card for a finished / cancelled / errored print.
  /// Swipeable, with a ✕ "Clear" action; either way of dismissing it is picked
  /// up by [_detectClearedDoneCards] on the next tick. Silent and on the shared
  /// "Print status" channel, keeping [startedMs] as its `when` so it stays put
  /// under the roster (see _postActiveCard).
  Future<void> _postDoneCard(
      PrinterConfig p, String state, int startedMs) async {
    final clock = _nowClock();
    final String body;
    switch (state) {
      case 'cancelled':
        body = clock == null
            ? _l.printStatusCancelled
            : '${_l.printStatusCancelled} · $clock';
        break;
      case 'error':
        body = _l.printStatusError;
        break;
      default: // complete
        body = clock == null
            ? _l.printNotifFinished
            : '${_l.printNotifFinished} $clock';
    }
    final android = AndroidNotificationDetails(
      _serviceChannelId,
      _serviceChannelName,
      channelDescription: _serviceChannelDesc,
      importance: Importance.low,
      priority: Priority.low,
      silent: true,
      onlyAlertOnce: true,
      icon: 'ic_stat_moongate',
      ongoing: false,
      autoCancel: true,
      when: startedMs,
      showWhen: false,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('mg_clear', _l.notifClearAction,
            cancelNotification: true),
      ],
    );
    await _alerts.show(
        _cardId(p.id), p.name, body, NotificationDetails(android: android));
  }

  /// Reset any printer whose Done card has disappeared from the shade since a
  /// prior tick (the user swiped it or tapped ✕). Best-effort: if the active
  /// notifications can't be enumerated (old Android), do nothing rather than
  /// fire a spurious reset. Skips cards posted this very tick to avoid a race
  /// with the OS reflecting a freshly-posted notification.
  Future<void> _detectClearedDoneCards(
      List<PrinterConfig> printers, Set<String> postedDoneThisTick) async {
    final waiting = printers
        .where((p) =>
            _cardPhase[p.id] == _CardPhase.done &&
            !postedDoneThisTick.contains(p.id))
        .toList();
    if (waiting.isEmpty) return;

    final Set<int> activeIds;
    try {
      final active = await _alerts.getActiveNotifications();
      activeIds = active.map((a) => a.id).whereType<int>().toSet();
    } catch (_) {
      return;
    }

    for (final p in waiting) {
      if (activeIds.contains(_cardId(p.id))) continue;
      _cardPhase[p.id] = _CardPhase.none; // clear first so we fire just once
      _cardStartedAt.remove(p.id);
      unawaited(PrintControlService(p).resetPrintState());
      _log('done card cleared (${p.name}) → SDCARD_RESET_FILE');
    }
  }

  /// The card's text for a running / paused print: the user-chosen detail
  /// segments (progress / remaining / finish-time / temps), or "Printing
  /// started" until the print is far enough along to estimate.
  String _cardBody(_Poll s) {
    final segs = _enabledSegments(s);
    if (s.state == 'paused') {
      return segs.isEmpty
          ? _l.printStatusPaused
          : '${_l.printStatusPaused} · ${segs.join(' · ')}';
    }
    // printing
    if (s.progress < 0.02) {
      final warm = _warming(s) ? _heatingSegs(s) : const <String>[];
      return [_l.printNotifStarted, ...warm].join(' · ');
    }
    return segs.isEmpty ? _l.printStatusPrinting : segs.join(' · ');
  }

  /// The enabled detail segments, in the user's chosen order, skipping any that
  /// don't apply yet (e.g. remaining / ETA before the print can be estimated).
  List<String> _enabledSegments(_Poll s) {
    final segs = <String>[];
    for (final f in _fields.order) {
      if (!_fields.enabled.contains(f)) continue;
      final seg = _fieldSegment(f, s);
      if (seg != null) segs.add(seg);
    }
    return segs;
  }

  /// Heater ramp segments ("25→210°"), shown on the card before extrusion while
  /// the printer is still warming up.
  List<String> _heatingSegs(_Poll s) => [
        if (s.hotendTarget > 0) '${s.hotend.round()}→${s.hotendTarget.round()}°',
        if (s.bedTarget > 0) '${s.bed.round()}→${s.bedTarget.round()}°',
      ];

  /// Localised wall-clock now ("3:45 PM" / "15:45") for the finished card, or
  /// null if the locale's date symbols didn't load.
  String? _nowClock() {
    try {
      return DateFormat.jm(_l.localeName).format(DateTime.now());
    } catch (_) {
      return null;
    }
  }

  // ── Heat-soak timers ────────────────────────────────────────────────────────

  /// Per-printer notification id for its one-shot heat-soak alert. High bit
  /// 0x20000000 keeps it clear of the service id (4711) and the print-card range
  /// (0x10000000), so the three never collide.
  int _heatsoakId(String printerId) =>
      0x20000000 | (printerId.hashCode & 0x0FFFFFFF);

  /// Fire the one-shot "Heat-soak complete" alert for any printer whose soak
  /// deadline (armed from the tile's preheat sheet) has elapsed, then clear it. A
  /// long-stale deadline is dropped without buzzing; deadlines for printers no
  /// longer present are pruned.
  Future<void> _fireDueHeatsoaks(List<PrinterConfig> printers) async {
    final deadlines = await HeatsoakTimers.snapshot();
    if (deadlines.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final known = {for (final p in printers) p.id};
    for (final p in printers) {
      final due = deadlines[p.id];
      if (due == null || nowMs < due) continue;
      if (nowMs - due <= _heatsoakStaleMs) await _postHeatsoakAlert(p);
      await HeatsoakTimers.cancel(p.id);
    }
    for (final id in deadlines.keys) {
      if (!known.contains(id)) await HeatsoakTimers.cancel(id);
    }
  }

  /// Post the one-shot, attention-grabbing "Heat-soak complete" alert for [p].
  Future<void> _postHeatsoakAlert(PrinterConfig p) async {
    const android = AndroidNotificationDetails(
      _heatsoakChannelId,
      _heatsoakChannelName,
      channelDescription: _heatsoakChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_moongate',
      autoCancel: true,
    );
    await _alerts.show(
      _heatsoakId(p.id),
      _l.heatsoakDoneTitle,
      _l.heatsoakDoneBody(p.name),
      const NotificationDetails(android: android),
    );
  }
}

/// Lifecycle of a printer's "Print jobs" card.
enum _CardPhase { none, active, done }

/// The gcode body byte offsets for one printer's current file (from Moonraker
/// metadata), used to compute Mainsail-style file-relative progress.
class _MetaOffsets {
  final String filename;
  final int? startByte;
  final int? endByte;
  const _MetaOffsets(this.filename, this.startByte, this.endByte);
}

/// A single printer's parsed status - just what the notification needs.
class _Poll {
  final String state;
  final double progress;        // 0..1
  final double printDurationSec;
  final double hotend;
  final double hotendTarget;
  final double bed;
  final double bedTarget;

  /// Live per-toolhead temperatures for a multi-hotend printer (IDEX / tool
  /// changer), sorted by tool number - populated only while printing / paused,
  /// and only when the printer reports extra hotends. Empty on an ordinary
  /// single-hotend machine, where the notification keeps its classic single 🔥
  /// chip.
  final List<ToolheadTemp> toolheads;

  /// True when this came from a real /status read (a genuine Klipper state).
  /// False for the synthesized "reachable but /status didn't answer" Idle
  /// placeholder - those must never drive a state-change alert (see _tick).
  final bool live;
  const _Poll({
    required this.state,
    required this.progress,
    required this.printDurationSec,
    required this.hotend,
    required this.hotendTarget,
    required this.bed,
    required this.bedTarget,
    this.toolheads = const [],
    this.live = true,
  });

  // A heater is actively ramping when it has a real target set and the current
  // reading is still meaningfully below it. Drives the "Heating" line during
  // pre-print soak / the start of a print before extrusion - when print_stats
  // is still standby (or printing at 0%) and nothing about the heaters would
  // otherwise show. `_heatTargetFloor` ignores low "keep-warm" trickle targets.
  static const double _heatTargetFloor = 35;
  static const double _heatMargin      = 3;
  bool _ramping(double cur, double tgt) =>
      tgt > _heatTargetFloor && (tgt - cur) > _heatMargin;
  bool get isHeating => _ramping(hotend, hotendTarget) || _ramping(bed, bedTarget);
}
