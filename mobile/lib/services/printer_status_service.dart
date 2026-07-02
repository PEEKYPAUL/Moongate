import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;

import '../models/printer_config.dart';
import 'lan_discovery_service.dart';
import 'print_progress.dart';
import 'printer_access_cache.dart';
import 'printer_liveness_service.dart';
import 'printer_registry.dart';
import 'printer_status_registry.dart';
import 'supabase_service.dart';

/// Polls the Moongate plugin's /server/moongate/status endpoint for one
/// printer.
///
/// v0.3.0 changes from v0.2.x:
///   • There is no longer any local-IP / tunnel candidate logic. The Pi
///     is only reachable via the tunnel URL that Supabase hands out from
///     /printer-access. The plugin endpoint validates the EdDSA token we
///     attach.
///   • Before every poll the service asks [PrinterAccessCache] for a
///     fresh `{tunnel_url, access_token}`. The cache reuses the token
///     until ~30s before its 5-min TTL, then refreshes via Supabase.
///   • On 401 from the Pi we invalidate the access entry and retry once
///     - the token may be expired or revoked.
class PrinterStatusService {
  final PrinterConfig config;

  final _controller = StreamController<PrinterStatus>.broadcast();
  Timer? _timer;
  bool _disposed = false;
  bool _polling  = false;

  // ── Chamber sensor discovery (kept from v0.2.x - same logic) ─────────────
  String? _chamberKey;
  bool    _chamberDiscovered = false;

  /// Extra extruder object names beyond the first (`extruder1`, `extruder2`, ...)
  /// found in the object list, for multi-toolhead printers - empty on an
  /// ordinary single-hotend machine. Discovered once alongside the chamber
  /// sensor. Excludes `extruder_stepper <name>` helpers (those aren't hotends).
  /// Used as the fallback when there's no klipper-toolchanger object.
  List<String> _extraExtruderKeys = const [];

  /// Authoritative klipper-toolchanger enumeration: (tool number → that tool's
  /// own extruder heater object name), learned once from the `[toolchanger]` +
  /// `[tool <name>]` objects. Non-empty only on a real tool changer; then it
  /// takes precedence over [_extraExtruderKeys] (handles any heater naming and
  /// gives the true active tool). Empty → fall back to the extruder scan.
  List<({int number, String extruder})> _toolchangerTools = const [];

  /// Matches an extra-hotend object name (`extruder1`, `extruder2`, ...); the
  /// bare `extruder` (T0) is handled separately.
  static final _extruderNumRe = RegExp(r'^extruder\d+$');

  // ── File-metadata cache for accurate progress ────────────────────────────
  // The slicer's gcode body byte offsets, cached per filename. They drive the
  // Mainsail-matching "file position (relative)" progress in _parseStatus -
  // (file_position − start) / (end − start) - via [computePrintProgress].
  int?    _gcodeStartByte;
  int?    _gcodeEndByte;
  String? _metadataFilename;

  // ── LAN-first state ──────────────────────────────────────────────────────
  // The printer's last-known LAN URL is fetched from /status (Pi reports
  // local_ip + http_port). When set, EVERY poll tries LAN before the
  // tunnel - so reconnecting to home WiFi after being on cellular flips
  // the tile back to "Local" on the very next poll. The cost is one ~2s
  // LAN timeout per poll when off-LAN; that's the trade we explicitly
  // want per the user's "always check for local first" rule.
  //
  // `_currentLanUrl` is a mutable copy initialised from the PrinterConfig
  // snapshot. Subsequent /status responses update it in-place so the very
  // next poll uses the freshly-learned LAN URL.
  //
  // v0.5.0: [LanDiscoveryService] takes priority over this when present.
  // The discovered URL is what the Pi is *currently* advertising on mDNS;
  // the persisted one might be stale (DHCP renewal, router reboot). See
  // docs/v0.5-lan-discovery-design.md §8.1.
  String? _currentLanUrl;

  // v0.5.0: bump every poll. Trigger a fresh mDNS browse every Nth poll
  // (N=15 ≈ 1 min at 4 s polling) so IP changes are picked up promptly
  // without spamming the network. See docs/v0.5-lan-discovery-design.md §7.4.
  int _pollCount = 0;
  static const int _mDnsBrowseEveryNPolls = 15;

  // ── Startup grace window ──────────────────────────────────────────────────
  // A freshly-paired or rebooting Pi legitimately has no tunnel URL yet and
  // may not answer on LAN for a few seconds, so we show 'starting_up' for a
  // bounded window after this service's first poll. Once it elapses with the
  // printer still unreachable on every path we report 'offline' instead of
  // sticking on "Starting up…" forever - the bug this fixes is a just-paired
  // host that's actually powered off, which never gets a tunnel URL (so
  // tunnelReady stays false indefinitely) and used to sit on 'starting_up'.
  DateTime? _firstPollAt;
  static const Duration _startupGrace = Duration(seconds: 45);

  /// Why the most recent /status attempt resolved as it did (ok / http_401 /
  /// http_404 / timeout / error) - set inside _tryMoongateEndpoint and
  /// captured by the bug-report diagnostics.
  String? _lastEndpointReason;

  /// Accumulates THIS poll's diagnostics (both the LAN and the tunnel attempt
  /// outcomes) so a bug report shows the tunnel result too - not just LAN. The
  /// old code only ever recorded the LAN attempt, which is exactly why a tunnel
  /// 500 never surfaced in a report. Reset at the top of every poll.
  Map<String, dynamic> _pollDiag = {};

  void _recordPollDiag(Map<String, dynamic> updates) {
    _pollDiag = {..._pollDiag, ...updates, 'at': DateTime.now().toIso8601String()};
    PrinterStatusRegistry.instance.recordPoll(config.id, _pollDiag);
  }

  /// The user's current custom camera URL for this printer, read LIVE from the
  /// registry each poll - so a change made via the tile gear takes effect on
  /// the next poll without recreating the service. Falls back to the snapshot
  /// the service was constructed with.
  String? get _liveCustomCameraUrl {
    for (final p in PrinterRegistry.instance.printers) {
      if (p.id == config.id) return p.customCameraUrl;
    }
    return config.customCameraUrl;
  }

  /// The user's configured light status object for this printer (e.g.
  /// `output_pin caselight`), read LIVE from the registry each poll like
  /// [_liveCustomCameraUrl] so an edit in the lighting overlay takes effect on
  /// the next poll. Null/empty → no real-state read (the tile falls back to
  /// tracking taps optimistically).
  String? get _liveLightStatusObject {
    PrinterConfig live = config;
    for (final p in PrinterRegistry.instance.printers) {
      if (p.id == config.id) {
        live = p;
        break;
      }
    }
    // Only read the light's real state when lighting is actually enabled for
    // this printer - otherwise an orphaned/disabled status object would be
    // polled needlessly.
    if (!live.lightingEnabled) return null;
    final raw = live.lightStatusObject;
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  bool get _withinStartupGrace =>
      _firstPollAt != null &&
      DateTime.now().difference(_firstPollAt!) < _startupGrace;

  PrinterStatusService(this.config)
      : _currentLanUrl = config.lanUrl,
        _uiType        = config.uiType,
        _uiTypeChecked = config.uiType != null;

  Stream<PrinterStatus> get stream => _controller.stream;

  String? get uiType => _uiType;

  // ── UI-type detection (Mainsail vs Fluidd) ───────────────────────────────
  // The tile renders the appropriate logo as a webcam placeholder when no
  // camera is configured, AND as a "the printer is currently offline" hint
  // so the tile stays identifiable when the K3 is powered off. Detection
  // is done once per printer (persisted in PrinterConfig) by sniffing the
  // root page HTML for "mainsail" or "fluidd".
  String? _uiType;
  // Seeded `true` when the config already has a persisted uiType - saves a
  // redundant root-page fetch on every cold launch.
  bool    _uiTypeChecked;

  Future<void> _detectUiType(String baseUrl, String accessToken,
      {required bool isLan}) async {
    _uiTypeChecked = true;
    try {
      final uri      = Uri.parse('$baseUrl/');
      // Tunnel-side the Mainsail root is gated by the auth proxy, so we send
      // the EdDSA token. On LAN we hit nginx directly, which serves the root
      // without auth - and sending the Bearer there would be wrong (see
      // _authedGet).
      final response = await _authedGet(
          uri, accessToken,
          isLan: isLan,
          timeout: const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = response.body.toLowerCase();
        String? detected;
        if (body.contains('mainsail')) {
          detected = 'mainsail';
        } else if (body.contains('fluidd')) {
          detected = 'fluidd';
        }
        if (detected != null) {
          _uiType = detected;
          // Persist so a future cold launch can show the logo immediately,
          // even before any poll succeeds (printer powered off, Pi rebooting).
          PrinterRegistry.instance.updateUiType(config.id, detected).ignore();
        }
      }
    } catch (_) {
      // Detection failed - retry on next successful poll
      _uiTypeChecked = false;
    }
  }

  void start({Duration interval = const Duration(seconds: 4)}) {
    _poll();
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  /// Trigger an immediate poll outside the timer cadence - e.g. when the app
  /// returns to the foreground. Aggressive battery optimisation (Samsung
  /// Freecess et al.) can freeze the process and suspend our [Timer], leaving
  /// the tile stuck on a stale 'offline'; polling on resume recovers it at
  /// once instead of waiting for the next tick. Cheap: [_poll] no-ops if one
  /// is already in flight.
  void pollNow() => _poll();

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _controller.close();
  }

  void _log(String msg) => dev.log(msg, name: 'MOONGATE/STATUS/${config.id.substring(0, 8)}');

  Future<void> _poll() async {
    if (_disposed || _polling) return;
    _polling = true;
    try {
      await _doPoll();
    } finally {
      _polling = false;
    }
  }

  Future<void> _doPoll() async {
    _firstPollAt ??= DateTime.now();
    _pollDiag = {};
    if (!SupabaseService.instance.ready) {
      // Supabase isn't authenticated yet (cold start, no network).
      if (!_disposed) _controller.add(PrinterStatus.offline);
      return;
    }

    // 0. v0.5.0: every Nth poll, kick off a non-blocking mDNS browse so
    //    the LanDiscoveryService cache stays fresh against IP changes.
    //    Fire-and-forget - never gate the poll itself on the browse.
    _pollCount++;
    if (_pollCount % _mDnsBrowseEveryNPolls == 1) {
      LanDiscoveryService.instance.refresh().ignore();
    }

    // 0.5 Liveness gate. Don't spend an Edge call (/printer-access mints the
    //     token) on a printer with no token-free sign of life. We learn
    //     online/offline from the cloud's last_seen over Realtime
    //     ([PrinterLivenessService] - NOT an Edge Function) and, failing that, a
    //     token-free LAN probe (so LAN still works when the heartbeat/cloud is
    //     down). A powered-off printer (stale last_seen, no LAN) thus costs zero
    //     Edge Function calls. Skipped during the startup grace so a fresh pair
    //     or app-resume still comes up via the normal "starting up" path below.
    final inStartupGrace =
        DateTime.now().difference(_firstPollAt!) < _startupGrace;
    if (!inStartupGrace &&
        PrinterLivenessService.instance.isKnownOffline(config.id)) {
      // Positive evidence the printer is offline (cloud last_seen is stale).
      // Confirm with a token-free LAN HEAD first - a Pi that's up on the LAN but
      // failing its heartbeats (e.g. clock skew) is still reachable and must not
      // be skipped. Only when that ALSO fails do we declare offline without
      // minting a token. Unknown / fresh last_seen falls through and polls - we
      // never gate on missing data, so a slow/failed seed can't show a live
      // printer offline.
      final probeUrl =
          LanDiscoveryService.instance.lookup(config.id) ?? _currentLanUrl;
      final lanUp = probeUrl != null && await _lanHeadReachable(probeUrl);
      if (!lanUp) {
        if (!_disposed) _controller.add(PrinterStatus.offline);
        return;
      }
    }

    // 1. Fresh access token (+ tunnel URL when known) from Supabase.
    //    v0.5.0: the token now comes back even before the Pi has reported a
    //    tunnel URL (access.tunnelUrl == null in that window) so the LAN
    //    path isn't gated on the cloud→tunnel round-trip. We only land in
    //    'starting_up' below when BOTH LAN and tunnel are unavailable.
    PrinterAccess access;
    try {
      access = await PrinterAccessCache.instance.get(config.id);
    } on PrinterUnavailableException {
      // Legacy 503 (Pi pre-v0.5 server, or server says wait): nothing we
      // can do without a token. Surface "starting up".
      if (!_disposed) _controller.add(PrinterStatus.startingUp);
      return;
    } on PrinterNotFoundException {
      _log('Printer not found in Supabase - emitting offline');
      if (!_disposed) _controller.add(PrinterStatus.offline);
      return;
    } catch (e) {
      _log('Access fetch failed: $e');
      if (!_disposed) _controller.add(PrinterStatus.offline);
      return;
    }

    // Whether the cloud knows the tunnel yet - surfaced on the tile as the
    // background "remote ready / connecting" hint regardless of which path
    // wins this poll.
    final bool tunnelReady = access.tunnelUrl != null;

    // 2. Discover chamber sensor on first reach
    if (!_chamberDiscovered) {
      await _discoverChamberSensor(access);
    }

    // 3. LAN-first on every poll. Same EdDSA token works on LAN or
    //    tunnel; the 2s fast-fail timeout inside _tryMoongateEndpoint
    //    caps the off-LAN penalty.
    //
    //    v0.5.0: a freshly-discovered URL from mDNS takes precedence over
    //    the persisted lanUrl. When both are set and the discovered one
    //    differs (Pi just moved IPs), we go straight to the new IP
    //    without wasting a poll on the stale persisted one. Crucially this
    //    runs even when tunnelReady is false - pairing happens on-LAN, so
    //    the tile can go "Local" the instant the owner binds, with the
    //    tunnel still coming up in the background.
    final discoveredLanUrl = LanDiscoveryService.instance.lookup(config.id);
    final lanUrl = discoveredLanUrl ?? _currentLanUrl;
    if (lanUrl != null) {
      _lastEndpointReason = null;
      final lan = await _tryMoongateEndpoint(
          baseUrl: lanUrl, access: access, isLan: true, tunnelReady: tunnelReady);
      // Capture why this LAN /status attempt resolved as it did, for the
      // bug-report diagnostics (ok / http_401 / http_404 / timeout / error).
      _recordPollDiag({
        'lan_url': lanUrl,
        'lan_status': _lastEndpointReason ?? 'unknown',
        if (discoveredLanUrl != null) 'discovered_url': discoveredLanUrl,
      });
      if (lan != null) {
        if (!_disposed) _controller.add(lan);
        return;
      }
    }

    // 4. Tunnel via Cloudflare - only when we actually have a URL.
    if (access.tunnelUrl != null) {
      final tunnelStatus = await _tryMoongateEndpoint(
          baseUrl: access.tunnelUrl!, access: access, isLan: false, tunnelReady: true);
      _recordPollDiag({
        'tunnel_url': access.tunnelUrl,
        'tunnel_status': _lastEndpointReason ?? 'unknown',
      });
      if (tunnelStatus != null) {
        if (!_disposed) _controller.add(tunnelStatus);
        return;
      }

      // 5. A 401 means the token itself was rejected (e.g. invalidated
      //    server-side) - a fresh one may work, so drop the cache and try ONCE
      //    more before declaring offline. For any other failure (timeout,
      //    offline, 404) a new token can't help: the Pi simply isn't reachable,
      //    so re-minting is pure waste. Re-minting on every poll for an
      //    offline-but-still-paired printer (whose stale tunnel URL keeps this
      //    branch alive) was the dominant source of /printer-access Edge
      //    Function calls - so we skip it unless the failure was an auth reject.
      if (_lastEndpointReason == 'http_401') {
        PrinterAccessCache.instance.invalidate(config.id);
        try {
          access = await PrinterAccessCache.instance.get(config.id);
        } catch (_) {
          if (!_disposed) _controller.add(PrinterStatus.offline);
          return;
        }
        if (access.tunnelUrl != null) {
          final retry = await _tryMoongateEndpoint(
              baseUrl: access.tunnelUrl!, access: access, isLan: false, tunnelReady: true);
          _recordPollDiag({
            'tunnel_url': access.tunnelUrl,
            'tunnel_status': _lastEndpointReason ?? 'unknown',
          });
          if (retry != null) {
            if (!_disposed) _controller.add(retry);
            return;
          }
        }
      }
    }

    // 6. All Moongate /status paths failed. Distinguish for the user:
    //    • Pi reachable (any HTTP answer) but the Moongate/Klipper stack
    //      isn't responding - e.g. the K3 printer-power toggle is off, so
    //      Moonraker may be up but Klipper isn't ('waiting').
    //    • Nothing answers anywhere, the cloud has no tunnel yet, and we
    //      only started polling moments ago → freshly paired / rebooting,
    //      so show 'starting_up' - but bounded by a grace window.
    //    • Otherwise nothing answers on any path → 'offline'.
    //
    // The grace window is the fix: a just-paired host that is genuinely
    // unreachable (powered off) never heartbeats a tunnel URL, so tunnelReady
    // stays false forever. Without the time bound the tile would sit on
    // "Starting up…" indefinitely instead of settling to offline.
    final reachable = await _isPiReachable(access);
    if (reachable) {
      if (!_disposed) _controller.add(PrinterStatus.waiting);
      return;
    }
    if (!_disposed) {
      _controller.add(
        (!tunnelReady && _withinStartupGrace)
            ? PrinterStatus.startingUp
            : PrinterStatus.offline,
      );
    }
  }

  // ── Reachability probe ───────────────────────────────────────────────────
  // HEADs the LAN URL (if we have one and haven't been failing it) and the
  // tunnel URL. ANY HTTP response back - auth proxy's 401, nginx's 200/304
  // for the Mainsail root, even an upstream-down 502 - proves the Pi
  // answered. We only get an exception when nothing on that host is
  // listening. Used to differentiate "Klipper not running" from "Pi off"
  // after the moongate /status path has given up.
  Future<bool> _isPiReachable(PrinterAccess access) async {
    // Include the mDNS-discovered URL, not just the persisted one: right after
    // a fresh pair the LAN /status poll may have failed (owner-bind/token not
    // settled yet) so _currentLanUrl is still null - but the printer is plainly
    // on the network. Probing the discovered URL here keeps the tile on
    // "Starting up…" instead of flipping to a scary "Offline" while it settles.
    final discovered = LanDiscoveryService.instance.lookup(config.id);
    final candidates = <String>[
      if (discovered != null) discovered,
      if (_currentLanUrl != null) _currentLanUrl!,
      if (access.tunnelUrl != null) access.tunnelUrl!,
    ];
    for (final base in candidates) {
      try {
        // 4s, not 2s: a Cloudflare Quick Tunnel cold-start can exceed 2s, and a
        // slow-but-alive host should read as "reachable", not "offline".
        await http.head(Uri.parse(base)).timeout(const Duration(seconds: 4));
        return true;
      } catch (_) {
        // Refused / timeout / DNS - try next candidate
      }
    }
    return false;
  }

  /// Token-free LAN reachability check for the liveness gate: HEAD [lanUrl] and
  /// treat ANY HTTP answer (even a 401 from the auth proxy) as "the Pi is up on
  /// this network". No access token needed, so it never costs an Edge call - it's
  /// how a printer that's offline-from-the-cloud but actually reachable on the
  /// LAN (e.g. a clock-skewed Pi whose heartbeats 401) still gets polled. When
  /// the phone is remote, the private LAN IP simply fast-fails (no route).
  Future<bool> _lanHeadReachable(String lanUrl) async {
    try {
      await http.head(Uri.parse(lanUrl)).timeout(const Duration(seconds: 2));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Authed GET helper ────────────────────────────────────────────────────
  // v0.4 puts an EdDSA auth proxy in front of Moonraker on the tunnel
  // side; un-authed calls to /printer/* and /server/* return 401, so we
  // attach the access token as Authorization: Bearer on every tunnel-side
  // GET.
  //
  // On LAN we MUST NOT send that header. The LAN request reaches Moonraker
  // directly (nginx → Moonraker over loopback, no auth proxy in the path),
  // and Moonraker treats any Authorization: Bearer as one of ITS OWN JWTs -
  // it tries to decode our EdDSA access token, fails, and returns 401
  // "JWT Decode Error". That silently broke the progress bar, chamber temp,
  // and accurate-progress metadata on LAN. LAN is trusted by subnet (and the
  // moongate /status path authenticates via ?mg_token= in the query), so no
  // Authorization header is needed - or wanted - there.
  Future<http.Response> _authedGet(
    Uri uri,
    String accessToken, {
    required bool isLan,
    required Duration timeout,
  }) {
    return http
        .get(uri,
            headers: isLan ? null : {'Authorization': 'Bearer $accessToken'})
        .timeout(timeout);
  }

  // ── Chamber sensor discovery (one call per service lifetime) ─────────────

  Future<void> _discoverChamberSensor(PrinterAccess access) async {
    // Best-effort, once per service lifetime. Use whatever base is usable:
    // the discovered/persisted LAN URL first, the tunnel only if there is
    // one. With neither available (fresh pair, tunnel not up, off-LAN) we
    // skip and retry on a later poll.
    final lanBase = LanDiscoveryService.instance.lookup(config.id)
        ?? _currentLanUrl;
    final base    = lanBase ?? access.tunnelUrl;
    if (base == null) return;
    // We're on LAN whenever a LAN base won the selection above; only fall
    // through to the tunnel (and its Bearer header) when no LAN URL exists.
    final isLan = lanBase != null;
    try {
      final uri      = Uri.parse('$base/printer/objects/list');
      final response = await _authedGet(
          uri, access.accessToken,
          isLan: isLan,
          timeout: const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body    = jsonDecode(response.body) as Map<String, dynamic>;
        final objects =
            (body['result']?['objects'] as List<dynamic>?) ?? [];
        // A printer can expose several "chamber" sensors (e.g. a
        // temperature_combined "Chamber" that averages "Chamber_Rear" and
        // "Chamber_Y"). Prefer the sensor named exactly "chamber", the
        // combined or standalone reading the user means, and only fall back to
        // the first partial match when there is no exact one.
        const prefixes = [
          'temperature_sensor ',
          'heater_generic ',
          'temperature_fan ',
        ];
        String? exact;
        String? partial;
        for (final obj in objects) {
          final key    = obj.toString();
          final prefix = prefixes.firstWhere(
              (p) => key.startsWith(p), orElse: () => '');
          if (prefix.isEmpty) continue;
          final name = key.substring(prefix.length).toLowerCase();
          if (!name.contains('chamber')) continue;
          partial ??= key;
          if (name == 'chamber') {
            exact = key;
            break;
          }
        }
        _chamberKey = exact ?? partial;

        // Multi-toolhead: collect any extruder1, extruder2 ... (T1 and up).
        // Klipper names extra hotends extruderN; the bare `extruder` is T0 and
        // is always queried, and `extruder_stepper <name>` helpers carry a
        // space, so an exact ^extruder\d+$ match picks out only real hotends.
        final extra = <String>[];
        for (final obj in objects) {
          final key = obj.toString();
          if (RegExp(r'^extruder\d+$').hasMatch(key)) extra.add(key);
        }
        extra.sort((a, b) =>
            int.parse(a.substring(8)).compareTo(int.parse(b.substring(8))));
        _extraExtruderKeys = extra;

        // Prefer the authoritative klipper-toolchanger enumeration when the
        // printer exposes a `[toolchanger]` object: read each `[tool <name>]`
        // object (the space excludes `tool_probe ...`) for its own extruder
        // heater + tool number. This handles any heater naming the bare
        // extruderN scan would miss and yields the real active tool. If it
        // comes back empty we keep the extruderN scan above as the fallback.
        if (objects.any((o) => o.toString() == 'toolchanger')) {
          final toolKeys = objects
              .map((o) => o.toString())
              .where((k) => k.startsWith('tool '))
              .toList();
          if (toolKeys.isNotEmpty) {
            _toolchangerTools = await _queryToolMap(
                base, access.accessToken, toolKeys, isLan: isLan);
          }
        }

        // Only mark discovery done once the list call actually returned 200, so
        // a cold-tunnel 502/503 on the first poll retries next time instead of
        // giving up for the whole service lifetime (which left chamber blank).
        _chamberDiscovered = true;
      }
    } catch (_) {
      // Network blip - retry next poll.
    }
  }

  /// One-shot query of a tool changer's `[tool <name>]` objects → the
  /// (tool number, extruder heater name) for each, sorted by number. Each tool
  /// object names its own extruder, so this is naming-agnostic. Returns empty on
  /// any failure (the caller then falls back to the extruderN scan).
  Future<List<({int number, String extruder})>> _queryToolMap(
      String base, String accessToken, List<String> toolKeys,
      {required bool isLan}) async {
    try {
      final query    = toolKeys.map(Uri.encodeComponent).join('&');
      final uri      = Uri.parse('$base/printer/objects/query?$query');
      final response = await _authedGet(
          uri, accessToken,
          isLan: isLan,
          timeout: const Duration(seconds: 5));
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final s    = body['result']?['status'] as Map<String, dynamic>?;
      if (s == null) return const [];
      final tools = <({int number, String extruder})>[];
      for (final key in toolKeys) {
        final obj = s[key] as Map<String, dynamic>?;
        if (obj == null) continue;
        final extruder = (obj['extruder'] as String?)?.trim();
        if (extruder == null || extruder.isEmpty) continue;
        tools.add((
          number:   (obj['tool_number'] as num?)?.toInt() ?? 0,
          extruder: extruder,
        ));
      }
      tools.sort((a, b) => a.number.compareTo(b.number));
      return tools;
    } catch (_) {
      return const [];
    }
  }

  // ── File metadata for accurate progress ──────────────────────────────────
  // Fetches the printing file's gcode body byte offsets (once per filename) so
  // _parseStatus can report Mainsail's "file position (relative)" progress.

  Future<void> _fetchFileMetadata(
      String baseUrl, String accessToken, String? filename,
      {required bool isLan}) async {
    if (filename == null || filename.isEmpty) return;
    if (filename == _metadataFilename) return;
    _gcodeStartByte   = null;
    _gcodeEndByte     = null;
    _metadataFilename = null;
    try {
      final encoded  = Uri.encodeComponent(filename);
      final uri      = Uri.parse(
          '$baseUrl/server/files/metadata?filename=$encoded');
      final response = await _authedGet(
          uri, accessToken,
          isLan: isLan,
          timeout: const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final result =
            jsonDecode(response.body)['result'] as Map<String, dynamic>?;
        final start = (result?['gcode_start_byte'] as num?)?.toInt();
        final end   = (result?['gcode_end_byte']   as num?)?.toInt();
        // Only cache (and stop re-fetching) once we have a usable range; a file
        // Moonraker is still analysing may omit the offsets for a moment.
        if (start != null && end != null && end > start) {
          _gcodeStartByte   = start;
          _gcodeEndByte     = end;
          _metadataFilename = filename;
        }
      }
    } catch (_) {}
  }

  // ── Moongate plugin endpoint ─────────────────────────────────────────────

  Future<PrinterStatus?> _tryMoongateEndpoint({
    required String        baseUrl,
    required PrinterAccess access,
    required bool          isLan,
    required bool          tunnelReady,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/server/moongate/status?mg_token=${Uri.encodeComponent(access.accessToken)}',
      );
      // LAN: fast-fail at 2s so off-LAN polling doesn't stall.
      // Tunnel: 8s for Cloudflare Quick Tunnel cold-start latency.
      final timeout = isLan
          ? const Duration(seconds: 2)
          : const Duration(seconds: 8);
      final response = await http.get(uri).timeout(timeout);
      if (response.statusCode == 401) {
        _lastEndpointReason = 'http_401';
        return null;
      }
      if (response.statusCode != 200) {
        _lastEndpointReason = 'http_${response.statusCode}';
        return null;
      }

      final body   = jsonDecode(response.body) as Map<String, dynamic>;
      final result = body['result'] as Map<String, dynamic>;
      final status = Map<String, dynamic>.from(
          result['status'] as Map<String, dynamic>);

      if (_chamberKey != null && status[_chamberKey!] == null) {
        await _supplementaryChamberQuery(baseUrl, access.accessToken, status,
            isLan: isLan);
      }
      // The plugin's /status only returns the first extruder, so fetch the extra
      // hotends (and the active tool) separately for a multi-toolhead printer -
      // same supplement pattern the chamber sensor uses. Prefer the toolchanger
      // path (each tool's own extruder + the active tool) and fall back to the
      // extruderN scan when this isn't a tool changer.
      if (_toolchangerTools.isNotEmpty) {
        await _supplementaryToolchangerQuery(baseUrl, access.accessToken, status,
            isLan: isLan);
      } else if (_extraExtruderKeys.isNotEmpty) {
        await _supplementaryExtruderQuery(baseUrl, access.accessToken, status,
            isLan: isLan);
      }
      if (status['display_status'] == null ||
          status['virtual_sdcard'] == null) {
        await _supplementaryProgressQuery(baseUrl, access.accessToken, status,
            isLan: isLan);
      }
      final lightObj = _liveLightStatusObject;
      if (lightObj != null && status[lightObj] == null) {
        await _supplementaryLightQuery(
            baseUrl, access.accessToken, lightObj, status, isLan: isLan);
      }

      final stats = status['print_stats'] as Map<String, dynamic>? ?? {};
      if (stats['state'] == 'printing') {
        await _fetchFileMetadata(
            baseUrl, access.accessToken, stats['filename'] as String?,
            isLan: isLan);
      }

      // Fire-and-forget UI detection on the first successful connection so
      // the tile knows whether to show the Mainsail or Fluidd logo when no
      // webcam is configured.
      if (!_uiTypeChecked) _detectUiType(baseUrl, access.accessToken, isLan: isLan);

      _lastEndpointReason = 'ok';
      return _parseStatus(
        status: status,
        moongateResult: result,
        isLan: isLan,
        baseUrl: baseUrl,
        accessToken: access.accessToken,
        tunnelReady: tunnelReady,
      );
    } on TimeoutException {
      _lastEndpointReason = 'timeout';
      return null;
    } catch (_) {
      _lastEndpointReason = 'error';
      return null;
    }
  }

  Future<void> _supplementaryChamberQuery(
      String baseUrl, String accessToken, Map<String, dynamic> status,
      {required bool isLan}) async {
    try {
      final encoded  = Uri.encodeComponent(_chamberKey!);
      final uri      = Uri.parse(
          '$baseUrl/printer/objects/query?$encoded');
      final response = await _authedGet(
          uri, accessToken,
          isLan: isLan,
          timeout: const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final s    = body['result']?['status'] as Map<String, dynamic>?;
        final data = s?[_chamberKey!];
        if (data != null) status[_chamberKey!] = data;
      }
    } catch (_) {}
  }

  // ── Extra toolheads (multi-extruder printers) ────────────────────────────

  /// Fetches the extra hotends (`extruder1`, `extruder2`, ...) plus `toolhead`
  /// (for the currently-selected tool) in one query and folds them into
  /// [status]. The Moongate plugin's /status only carries the first extruder,
  /// so a multi-toolhead printer needs this supplement - it works on LAN and
  /// through the tunnel proxy, exactly like the chamber query.
  Future<void> _supplementaryExtruderQuery(
      String baseUrl, String accessToken, Map<String, dynamic> status,
      {required bool isLan}) async {
    try {
      final objects = [..._extraExtruderKeys, 'toolhead'];
      final query   = objects.map(Uri.encodeComponent).join('&');
      final uri      = Uri.parse('$baseUrl/printer/objects/query?$query');
      final response = await _authedGet(
          uri, accessToken,
          isLan: isLan,
          timeout: const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final s    = body['result']?['status'] as Map<String, dynamic>?;
        if (s != null) {
          for (final key in objects) {
            if (s[key] != null) status[key] = s[key];
          }
        }
      }
    } catch (_) {}
  }

  /// Multi-toolhead supplement for a klipper-toolchanger: fetch the
  /// `toolchanger` object (for the active tool) plus each mapped tool's extruder
  /// heater (for its live temp) in one query, folded into [status]. 'extruder'
  /// (T0) is already in the plugin /status but re-querying is harmless. Pi-
  /// direct, so no added Supabase Edge calls.
  Future<void> _supplementaryToolchangerQuery(
      String baseUrl, String accessToken, Map<String, dynamic> status,
      {required bool isLan}) async {
    try {
      final objects = <String>{
        'toolchanger',
        for (final t in _toolchangerTools) t.extruder,
      }.toList();
      final query    = objects.map(Uri.encodeComponent).join('&');
      final uri      = Uri.parse('$baseUrl/printer/objects/query?$query');
      final response = await _authedGet(
          uri, accessToken,
          isLan: isLan,
          timeout: const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final s    = body['result']?['status'] as Map<String, dynamic>?;
        if (s != null) {
          for (final key in objects) {
            if (s[key] != null) status[key] = s[key];
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _supplementaryProgressQuery(
      String baseUrl, String accessToken, Map<String, dynamic> status,
      {required bool isLan}) async {
    try {
      final uri = Uri.parse(
          '$baseUrl/printer/objects/query?display_status&virtual_sdcard&webhooks');
      final response = await _authedGet(
          uri, accessToken,
          isLan: isLan,
          timeout: const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final s    = body['result']?['status'] as Map<String, dynamic>?;
        if (s != null) {
          if (status['display_status'] == null && s['display_status'] != null) {
            status['display_status'] = s['display_status'];
          }
          if (status['virtual_sdcard'] == null && s['virtual_sdcard'] != null) {
            status['virtual_sdcard'] = s['virtual_sdcard'];
          }
          // Klipper health - drives the tile's after-E-STOP restart button.
          if (s['webhooks'] != null) status['webhooks'] = s['webhooks'];
        }
      }
    } catch (_) {}
  }

  // ── Light status object (v0.9.8) ─────────────────────────────────────────

  Future<void> _supplementaryLightQuery(String baseUrl, String accessToken,
      String object, Map<String, dynamic> status, {required bool isLan}) async {
    try {
      final encoded  = Uri.encodeComponent(object);
      final uri      = Uri.parse('$baseUrl/printer/objects/query?$encoded');
      final response = await _authedGet(
          uri, accessToken,
          isLan: isLan,
          timeout: const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final s    = body['result']?['status'] as Map<String, dynamic>?;
        final data = s?[object];
        if (data != null) status[object] = data;
      }
    } catch (_) {}
  }

  /// Interpret a light object's Klipper status into on/off. `output_pin` exposes
  /// a `value` (0..1, on if > 0); LED types (led / neopixel / dotstar) expose
  /// `color_data` as a list of [r,g,b,w] channels - on if any channel of any
  /// pixel is lit. Null when the shape isn't recognised.
  static bool? _interpretLight(dynamic data) {
    if (data is! Map) return null;
    final value = data['value'];
    if (value is num) return value > 0;
    final colorData = data['color_data'];
    if (colorData is List) {
      for (final px in colorData) {
        if (px is List) {
          for (final ch in px) {
            if (ch is num && ch > 0) return true;
          }
        }
      }
      return false;
    }
    return null;
  }

  // ── Shared status parser (unchanged from v0.2.x logic) ───────────────────

  PrinterStatus _parseStatus({
    required Map<String, dynamic> status,
    required Map<String, dynamic>? moongateResult,
    required bool                 isLan,
    required String               baseUrl,
    required String               accessToken,
    required bool                 tunnelReady,
  }) {
    final printStats = status['print_stats'] as Map<String, dynamic>? ?? {};
    final extruder   = status['extruder']    as Map<String, dynamic>? ?? {};
    final heaterBed  = status['heater_bed']  as Map<String, dynamic>? ?? {};

    Map<String, dynamic>? chamberSensor = _chamberKey != null
        ? status[_chamberKey!] as Map<String, dynamic>?
        : null;
    if (chamberSensor == null) {
      // Fallback when discovery has not set a key yet: scan whatever sensors
      // are in this payload for a chamber one, case-insensitively, so a
      // mixed-case name like "Chamber" is caught too.
      for (final entry in status.entries) {
        final k = entry.key.toLowerCase();
        if ((k.startsWith('temperature_sensor ') ||
             k.startsWith('heater_generic ') ||
             k.startsWith('temperature_fan ')) &&
            k.contains('chamber')) {
          final v = entry.value;
          if (v is Map<String, dynamic>) chamberSensor = v;
          break;
        }
      }
    }

    final displayStatus = status['display_status'] as Map<String, dynamic>? ?? {};
    final virtualSdcard = status['virtual_sdcard'] as Map<String, dynamic>? ?? {};

    final state = (printStats['state'] as String?) ?? 'startup';

    final double displayProg =
        (displayStatus['progress'] as num?)?.toDouble() ?? 0.0;
    final double sdcardProg =
        (virtualSdcard['progress'] as num?)?.toDouble() ?? 0.0;
    final double? filePosition =
        (virtualSdcard['file_position'] as num?)?.toDouble();

    // File-relative progress - matches Mainsail's default and the notification
    // (single source of truth in computePrintProgress). The slicer-time
    // estimate that used to lead here read several % ahead of Mainsail.
    final double progress = computePrintProgress(
      filePosition:    filePosition,
      gcodeStartByte:  _gcodeStartByte,
      gcodeEndByte:    _gcodeEndByte,
      displayProgress: displayProg,
      sdcardProgress:  sdcardProg,
    );

    // Persist webcam transform info - keeps the tile correct on next launch.
    // Also pick up the Pi's local_ip if it surfaced, so future polls can
    // try LAN first.
    if (moongateResult != null) {
      final flipH    = (moongateResult['webcam_flip_horizontal'] as bool?) ?? false;
      final flipV    = (moongateResult['webcam_flip_vertical']   as bool?) ?? false;
      final rotation = (moongateResult['webcam_rotation']    as num?)?.toInt() ?? 0;
      final fps      = (moongateResult['webcam_target_fps']  as num?)?.toInt() ?? 15;
      PrinterRegistry.instance.updateWebcamInfo(
        config.id,
        flipH:     flipH,
        flipV:     flipV,
        rotation:  rotation,
        targetFps: fps,
      ).ignore();

      final lip  = moongateResult['local_ip']  as String?;
      final port = (moongateResult['http_port'] as num?)?.toInt() ?? 80;
      if (lip != null && lip.isNotEmpty && lip != 'localhost') {
        final newLanUrl = port == 80 ? 'http://$lip' : 'http://$lip:$port';
        // Update the service's mutable copy IMMEDIATELY so the very next
        // poll tries LAN first. Also persist to the registry for cold-start.
        _currentLanUrl = newLanUrl;
        PrinterRegistry.instance.updateLanUrl(config.id, newLanUrl).ignore();
      }

      // Record the Pi's plugin version in this poll's diagnostics so a bug
      // report shows which plugin the printer is actually running (absent =
      // pre-v0.6.4 plugin that doesn't report it yet - itself a useful signal).
      final pluginVersion = moongateResult['plugin_version'] as String?;
      if (pluginVersion != null && pluginVersion.isNotEmpty) {
        _recordPollDiag({'plugin_version': pluginVersion});
      }
    }

    // Build the absolute snapshot URL from the path the Pi reported plus
    // the base URL we're currently winning the poll on. Tunnel-side needs
    // the EdDSA token in the query string because Image.network can't set
    // headers or cookies - the auth proxy accepts mg_token via query as a
    // documented fallback (see klipper-plugin/moongate_authproxy.py).
    // LAN-side needs no auth because Moonraker / nginx trust the subnet.
    final snapshotPath = moongateResult?['webcam_snapshot_path'] as String?;
    String? webcamSnapshotUrl;
    if (snapshotPath != null && snapshotPath.isNotEmpty) {
      if (isLan) {
        webcamSnapshotUrl = '$baseUrl$snapshotPath';
      } else {
        final sep = snapshotPath.contains('?') ? '&' : '?';
        webcamSnapshotUrl =
            '$baseUrl$snapshotPath${sep}mg_token=${Uri.encodeComponent(accessToken)}';
      }
    }

    // External / custom camera override.
    // Precedence: user override (the tile gear) > a camera auto-detected from
    // Mainsail's webcam config (the plugin reports its absolute URL because
    // Moonraker can't snapshot it for us) > the normal Pi snapshot built
    // above. These are absolute LAN URLs - typically an MJPEG stream from a
    // phone webcam. On LAN we fetch them directly; remote we route through the
    // Pi's /mg-extcam proxy, which only ever forwards to private LAN IPs (see
    // klipper-plugin/moongate_authproxy.py).
    final customUrl    = _liveCustomCameraUrl?.trim();
    final autoSnapshot = (moongateResult?['webcam_snapshot_external'] as String?)?.trim();
    final autoStream   = (moongateResult?['webcam_stream_external']   as String?)?.trim();
    final externalUrl = (customUrl != null && customUrl.isNotEmpty)
        ? customUrl
        : (autoSnapshot != null && autoSnapshot.isNotEmpty)
            ? autoSnapshot
            : (autoStream != null && autoStream.isNotEmpty)
                ? autoStream
                : null;

    bool webcamIsExternal = false;
    if (externalUrl != null && externalUrl.isNotEmpty) {
      webcamIsExternal = true;
      if (isLan) {
        webcamSnapshotUrl = externalUrl;
      } else {
        webcamSnapshotUrl =
            '$baseUrl/mg-extcam?u=${Uri.encodeComponent(externalUrl)}'
            '&mg_token=${Uri.encodeComponent(accessToken)}';
      }
    }

    final lightObj = _liveLightStatusObject;
    final bool? lightOn =
        lightObj != null ? _interpretLight(status[lightObj]) : null;

    // Klipper health from Moonraker's webhooks object: "shutdown" (e.g. after an
    // emergency stop) or "error" means the machine needs a firmware restart to
    // come back - the tile then shows a restart button instead of the E-STOP
    // triangle. (Also corrects the misleading "idle" a shut-down printer showed.)
    final webhooks       = status['webhooks'] as Map<String, dynamic>?;
    final klippyState    = webhooks?['state'] as String?;
    final klippyShutdown =
        klippyState == 'shutdown' || klippyState == 'error';

    // Multi-toolhead list, built from whatever extruder objects are present in
    // the merged status map. On plugin 0.6.12+ the /status call itself carries
    // every extruder + toolhead + toolchanger, so this works even when the app's
    // own object queries can't get through (e.g. a remote / VPN client); on
    // older plugins the supplements above fold the same objects in when they
    // can. Active tool: the toolchanger's tool_number, else toolhead.extruder. A
    // single-hotend printer yields just T0, so the tile shows the grid only when
    // there's more than one.
    final activeToolNum =
        ((status['toolchanger'] as Map<String, dynamic>?)?['tool_number']
                as num?)
            ?.toInt();
    final activeKey =
        (status['toolhead'] as Map<String, dynamic>?)?['extruder'] as String?;
    final toolheads = <ToolheadTemp>[];
    for (final key in status.keys) {
      if (key != 'extruder' && !_extruderNumRe.hasMatch(key)) continue;
      final obj = status[key] as Map<String, dynamic>?;
      if (obj == null || obj.isEmpty) continue;
      final idx = key == 'extruder' ? 0 : int.tryParse(key.substring(8)) ?? 0;
      toolheads.add(ToolheadTemp(
        index:  idx,
        temp:   (obj['temperature'] as num?)?.toDouble() ?? 0,
        target: (obj['target']      as num?)?.toDouble() ?? 0,
        active: activeToolNum != null
            ? idx == activeToolNum
            : key == (activeKey ?? 'extruder'),
      ));
    }
    toolheads.sort((a, b) => a.index.compareTo(b.index));

    return PrinterStatus(
      state:              state,
      progress:           progress,
      hotendTemp:         (extruder['temperature']       as num?)?.toDouble() ?? 0,
      hotendTarget:       (extruder['target']            as num?)?.toDouble() ?? 0,
      bedTemp:            (heaterBed['temperature']      as num?)?.toDouble() ?? 0,
      bedTarget:          (heaterBed['target']           as num?)?.toDouble() ?? 0,
      chamberTemp:        (chamberSensor?['temperature'] as num?)?.toDouble() ?? 0,
      chamberTarget:      (chamberSensor?['target']      as num?)?.toDouble() ?? 0,
      toolheads:          toolheads,
      filename:           printStats['filename']         as String?,
      connection:         isLan ? PrinterConnection.local : PrinterConnection.remote,
      tunnelReady:        tunnelReady,
      webcamSnapshotUrl:  webcamSnapshotUrl,
      webcamFlipH:     (moongateResult?['webcam_flip_horizontal'] as bool?) ?? false,
      webcamFlipV:     (moongateResult?['webcam_flip_vertical']   as bool?) ?? false,
      webcamRotation:  (moongateResult?['webcam_rotation']        as num?)?.toInt() ?? 0,
      webcamTargetFps: (moongateResult?['webcam_target_fps']      as num?)?.toInt() ?? 15,
      webcamIsExternal: webcamIsExternal,
      lightOn:          lightOn,
      klippyShutdown:   klippyShutdown,
    );
  }
}
