import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/printer_config.dart';
import 'printer_registry.dart';

/// Polls Moonraker's REST API to get current printer status.
/// One instance per printer tile; disposed when the tile leaves the tree.
///
/// Connection strategy (per candidate host — local first, then tunnel):
///   1. Try the Moongate plugin endpoint (/server/moongate/status).
///      Returns rich data: tunnel URL, webcam path, full print stats.
///   2. Fall back to the native Moonraker object query API.
///      Works even without the Moongate plugin installed.
///      Tries progressively simpler object sets to handle printers where
///      optional objects (heater_bed, display_status) are not configured.
///
/// Chamber sensor discovery:
///   On the first reachable connection, calls /printer/objects/list and
///   finds any temperature_sensor or heater_generic whose name contains
///   "chamber" (case-insensitive).  This handles every naming convention:
///   [temperature_sensor chamber], [temperature_sensor CHAMBER],
///   [temperature_sensor Chamber_Temp], [heater_generic CHAMBER], etc.
///   The discovered key is cached for the lifetime of this service instance.
///
/// A _polling guard prevents concurrent polls from stacking up when the
/// previous poll is still timing out on an unreachable host.
class PrinterStatusService {
  final PrinterConfig config;
  final _controller          = StreamController<PrinterStatus>.broadcast();
  final _tunnelUrlController = StreamController<String>.broadcast();
  Timer? _timer;
  bool _disposed = false;
  bool _polling  = false; // guard: skip tick if previous poll still running

  /// Mutable local copy of the connection preference — updated immediately
  /// on success so the very next poll uses the right order, and persisted
  /// to [PrinterRegistry] so the preference survives app restarts.
  bool _preferRemote;

  /// The Moonraker object key for the chamber temperature sensor, e.g.
  /// "temperature_sensor CHAMBER".  Null until discovery runs or when no
  /// chamber sensor is found.  Populated by [_discoverChamberSensor].
  String? _chamberKey;

  /// Set to true once discovery has been attempted (whether or not a sensor
  /// was found) so we don't call /printer/objects/list on every poll.
  bool _chamberDiscovered = false;

  // Always start local-first — preferRemote is a session-only optimisation.
  // Persisting it caused both printers to show "Tunnel" on every app launch
  // even when on the same LAN as the printer.
  PrinterStatusService(this.config) : _preferRemote = false;

  Stream<PrinterStatus> get stream => _controller.stream;

  /// Emits the updated tunnel URL whenever the Pi reports a URL that differs
  /// from what is stored in the config.  Subscribe in the webcam widget to
  /// immediately start using the fresh URL within the same session.
  Stream<String> get tunnelUrlUpdates => _tunnelUrlController.stream;

  void start({Duration interval = const Duration(seconds: 4)}) {
    _poll();
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _controller.close();
    _tunnelUrlController.close();
  }

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
    // ── Candidate ordering ────────────────────────────────────────────────
    //
    // Each printer remembers which path worked last (_preferRemote).
    // A printer on a completely different network (e.g. work printer)
    // has an unreachable local IP — without this, every 4-second poll
    // wastes a 2-second timeout on it before falling back to tunnel.
    //
    // Preference is updated automatically after each successful poll:
    //   • tunnel succeeds → _preferRemote = true  → tunnel tried first next time
    //   • local  succeeds → _preferRemote = false → local  tried first next time
    //
    // This means coming home automatically flips back to local-first as soon
    // as the local connection wins for the first time.
    final local  = config.host;
    final remote = config.remoteHost;

    final candidates = (_preferRemote && remote != null)
        ? [remote, local]            // remote-preferred: skip local timeout
        : [local, if (remote != null) remote]; // local-first default

    for (final baseUrl in candidates) {
      // Use a longer timeout for remote/tunnel connections: Cloudflare Quick
      // Tunnels can take 1-3 s to warm up after being idle, and general WAN
      // latency is higher than LAN.  A 2-second timeout fires before the
      // tunnel has a chance to respond, making the printer look "Offline"
      // even when the tunnel is working fine.
      final isRemote = remote != null && baseUrl == remote;
      final timeout  = isRemote
          ? const Duration(seconds: 8)  // tunnel: allow for cold-start latency
          : const Duration(seconds: 3); // local LAN: fast or not reachable

      // Discover the chamber sensor key on the first reachable host.
      // One extra HTTP call on the very first poll, zero overhead after that.
      if (!_chamberDiscovered) {
        await _discoverChamberSensor(baseUrl, timeout: timeout);
      }

      // ── 1. Moongate plugin endpoint (preferred) ──────────────────────────
      final moongate = await _tryMoongateEndpoint(baseUrl, timeout: timeout);
      if (moongate != null) {
        _onSuccess(baseUrl);
        if (!_disposed) _controller.add(moongate);
        return;
      }

      // ── 2. Native Moonraker API fallback ─────────────────────────────────
      //   Works even without the Moongate plugin.  Tries progressively
      //   simpler object sets to handle printers without a heated bed or
      //   other optional Klipper objects.
      final native = await _tryNativeEndpoint(baseUrl, timeout: timeout);
      if (native != null) {
        _onSuccess(baseUrl);
        if (!_disposed) _controller.add(native);
        return;
      }
    }

    // All candidates failed — printer is unreachable.
    if (!_disposed) _controller.add(PrinterStatus.offline);
  }

  // ── Chamber sensor discovery ───────────────────────────────────────────────
  //
  // Calls /printer/objects/list once and scans for any temperature_sensor or
  // heater_generic whose name contains "chamber" (case-insensitive).
  //
  // Examples this handles:
  //   [temperature_sensor chamber]      → key: "temperature_sensor chamber"
  //   [temperature_sensor CHAMBER]      → key: "temperature_sensor CHAMBER"
  //   [temperature_sensor Chamber_Temp] → key: "temperature_sensor Chamber_Temp"
  //   [heater_generic CHAMBER]          → key: "heater_generic CHAMBER"
  //
  // Sets _chamberDiscovered = true even if no sensor is found, so we don't
  // call /printer/objects/list on every subsequent poll.

  Future<void> _discoverChamberSensor(
      String baseUrl, {required Duration timeout}) async {
    try {
      final uri      = Uri.parse('$baseUrl/printer/objects/list');
      final response = await http.get(uri).timeout(timeout);
      if (response.statusCode == 200) {
        final body    = jsonDecode(response.body) as Map<String, dynamic>;
        final objects =
            ((body['result']?['objects']) as List<dynamic>?) ?? [];
        for (final obj in objects) {
          final key = obj.toString();
          // Match temperature_sensor, heater_generic, OR temperature_fan
          // (Micron+ and other enclosures often use temperature_fan for the
          // chamber fan which also exposes a temperature reading).
          if ((key.startsWith('temperature_sensor ') ||
               key.startsWith('heater_generic ') ||
               key.startsWith('temperature_fan ')) &&
              key.toLowerCase().contains('chamber')) {
            _chamberKey = key; // e.g. "temperature_sensor CHAMBER"
            break;
          }
        }
      }
      // Mark done regardless — avoids calling /printer/objects/list every poll
      // when the host is reachable but has no chamber sensor.
      _chamberDiscovered = true;
    } catch (_) {
      // Network error — leave _chamberDiscovered = false so we retry next poll
      // (the host may not have been reachable yet).
    }
  }

  /// Called after every successful poll.  Updates the in-session connection
  /// preference so the next poll in this session tries the right host first.
  /// NOT persisted — on app launch we always start local-first so a printer
  /// that was on a remote network last session doesn't keep trying tunnel
  /// first when you're back home on the same LAN.
  void _onSuccess(String baseUrl) {
    final isRemote = baseUrl != config.host;
    if (isRemote == _preferRemote) return; // no change
    _preferRemote = isRemote;
  }

  // ── Moongate plugin endpoint ───────────────────────────────────────────────

  Future<PrinterStatus?> _tryMoongateEndpoint(
      String baseUrl, {required Duration timeout}) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/server/moongate/status?mg_token=${Uri.encodeComponent(config.token)}',
      );
      final response = await http.get(uri).timeout(timeout);
      if (response.statusCode != 200) return null;

      final body   = jsonDecode(response.body) as Map<String, dynamic>;
      final result = body['result'] as Map<String, dynamic>;
      final status = result['status'] as Map<String, dynamic>;

      return _parseStatus(status: status, moongateResult: result, baseUrl: baseUrl);
    } catch (_) {
      return null;
    }
  }

  // ── Native Moonraker object query ──────────────────────────────────────────
  //
  // Moonraker returns HTTP 400 when you query an object that isn't registered
  // in the Klipper config (e.g. `heater_bed` on a printer without a heated
  // bed, or `display_status` on a printer without a display).  We try
  // progressively simpler object sets and stop at the first 200 response.
  // A timeout or any non-400 error causes an immediate bail-out.

  Future<PrinterStatus?> _tryNativeEndpoint(
      String baseUrl, {required Duration timeout}) async {
    // Build the query list dynamically.  If we've discovered the chamber sensor
    // key, prepend a query that includes it — the app will try that first and
    // only fall back to the no-chamber queries if it returns 400.
    final chamberParam = _chamberKey != null
        ? '&${Uri.encodeComponent(_chamberKey!)}'
        : '';
    final queries = [
      if (chamberParam.isNotEmpty)
        'print_stats&extruder&heater_bed$chamberParam', // with chamber sensor
      'print_stats&extruder&heater_bed', // most Mainsail setups (no chamber)
      'print_stats&extruder',            // no heated bed
      'print_stats',                     // absolute minimum
    ];

    for (final q in queries) {
      try {
        final uri = Uri.parse('$baseUrl/printer/objects/query?$q');
        final response = await http.get(uri).timeout(timeout);

        if (response.statusCode == 200) {
          final body   = jsonDecode(response.body) as Map<String, dynamic>;
          final result = body['result'] as Map<String, dynamic>;
          final status = result['status'] as Map<String, dynamic>;
          return _parseStatus(
              status: status, moongateResult: null, baseUrl: baseUrl);
        }

        // 400 = object not found → try a simpler query set
        if (response.statusCode == 400) continue;

        // Any other non-200 (401, 403, 5xx …) → give up on this host
        return null;
      } catch (_) {
        // Timeout or network error → give up on this host immediately
        // (don't bother retrying simpler queries — the host is unreachable)
        return null;
      }
    }
    return null;
  }

  // ── Shared status parser ───────────────────────────────────────────────────

  PrinterStatus _parseStatus({
    required Map<String, dynamic> status,
    required Map<String, dynamic>? moongateResult,
    required String baseUrl,
  }) {
    final printStats = status['print_stats'] as Map<String, dynamic>? ?? {};
    final extruder   = status['extruder']    as Map<String, dynamic>? ?? {};
    final heaterBed  = status['heater_bed']  as Map<String, dynamic>? ?? {};

    // Chamber temperature — look up by discovered key first, then fall back to
    // common hardcoded names.  The fallback covers:
    //   • Printers using the Moongate plugin before it also started querying
    //     the chamber sensor server-side.
    //   • Edge cases where discovery hasn't completed yet on the first frame.
    Map<String, dynamic>? chamberSensor = _chamberKey != null
        ? status[_chamberKey!] as Map<String, dynamic>?
        : null;
    chamberSensor ??=
        (status['temperature_sensor chamber'] ??
         status['temperature_sensor CHAMBER'] ??
         status['temperature_sensor chamber_temp'] ??
         status['temperature_sensor CHAMBER_TEMP'] ??
         status['heater_generic chamber'] ??
         status['heater_generic CHAMBER'] ??
         status['temperature_fan chamber'] ??
         status['temperature_fan CHAMBER']) as Map<String, dynamic>?;

    // display_status.progress is the real slicer %; only available from the
    // Moongate endpoint (which includes the full Moonraker status object).
    final displayStatus = status['display_status'] as Map<String, dynamic>? ?? {};

    // When Klipper is still initialising, print_stats is present in the
    // Moonraker response but its 'state' field is null/absent.  Return
    // 'startup' rather than 'offline' so the badge says "Starting" instead of
    // "Offline" — the connection is working, Klipper just isn't ready yet.
    final state = (printStats['state'] as String?) ?? 'startup';

    final double progress;
    if (displayStatus['progress'] != null) {
      progress = (displayStatus['progress'] as num).toDouble().clamp(0.0, 1.0);
    } else if (printStats['print_duration'] != null &&
        printStats['total_duration'] != null &&
        (printStats['total_duration'] as num) > 0) {
      progress = ((printStats['print_duration'] as num) /
              (printStats['total_duration'] as num))
          .clamp(0.0, 1.0)
          .toDouble();
    } else {
      progress = 0.0;
    }

    // Detect tunnel URL rotation — only available from the Moongate endpoint.
    if (moongateResult != null && !_disposed) {
      final liveTunnelUrl = moongateResult['tunnel_url'] as String?;
      if (liveTunnelUrl != null &&
          liveTunnelUrl.isNotEmpty &&
          liveTunnelUrl != config.remoteHost) {
        _tunnelUrlController.add(liveTunnelUrl);
        PrinterRegistry.instance
            .updateRemoteHost(config.id, liveTunnelUrl)
            .ignore();
      }

      // Persist webcam transform settings so the tile is correct from the
      // very first frame on the next launch — before any poll completes.
      final flipH    = (moongateResult['webcam_flip_horizontal'] as bool?) ?? false;
      final flipV    = (moongateResult['webcam_flip_vertical']   as bool?) ?? false;
      final rotation = (moongateResult['webcam_rotation'] as num?)?.toInt() ?? 0;
      PrinterRegistry.instance.updateWebcamInfo(
        config.id, flipH: flipH, flipV: flipV, rotation: rotation,
      ).ignore();
    }

    final connection = (baseUrl == config.host)
        ? PrinterConnection.local
        : PrinterConnection.remote;

    return PrinterStatus(
      state:              state,
      progress:           progress,
      hotendTemp:         (extruder['temperature']       as num?)?.toDouble() ?? 0,
      hotendTarget:       (extruder['target']            as num?)?.toDouble() ?? 0,
      bedTemp:            (heaterBed['temperature']      as num?)?.toDouble() ?? 0,
      bedTarget:          (heaterBed['target']           as num?)?.toDouble() ?? 0,
      chamberTemp:        (chamberSensor?['temperature'] as num?)?.toDouble() ?? 0,
      chamberTarget:      (chamberSensor?['target']      as num?)?.toDouble() ?? 0,
      filename:           printStats['filename']         as String?,
      connection:         connection,
      webcamSnapshotPath: moongateResult?['webcam_snapshot_path'] as String?,
      // Webcam display transforms — match whatever Mainsail has configured.
      // Only available via the Moongate endpoint; fall back to no-transform.
      webcamFlipH:    (moongateResult?['webcam_flip_horizontal'] as bool?) ?? false,
      webcamFlipV:    (moongateResult?['webcam_flip_vertical']   as bool?) ?? false,
      webcamRotation: (moongateResult?['webcam_rotation'] as num?)?.toInt() ?? 0,
    );
  }
}
