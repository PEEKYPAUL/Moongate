import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;

import '../models/printer_config.dart';
import 'lan_discovery_service.dart';
import 'printer_access_cache.dart';
import 'printer_registry.dart';
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
///     — the token may be expired or revoked.
class PrinterStatusService {
  final PrinterConfig config;

  final _controller = StreamController<PrinterStatus>.broadcast();
  Timer? _timer;
  bool _disposed = false;
  bool _polling  = false;

  // ── Chamber sensor discovery (kept from v0.2.x — same logic) ─────────────
  String? _chamberKey;
  bool    _chamberDiscovered = false;

  // ── File-metadata cache for accurate progress (kept from v0.2.x) ─────────
  double? _estimatedPrintSeconds;
  String? _metadataFilename;

  // ── LAN-first state ──────────────────────────────────────────────────────
  // The printer's last-known LAN URL is fetched from /status (Pi reports
  // local_ip + http_port). When set, EVERY poll tries LAN before the
  // tunnel — so reconnecting to home WiFi after being on cellular flips
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
  // Seeded `true` when the config already has a persisted uiType — saves a
  // redundant root-page fetch on every cold launch.
  bool    _uiTypeChecked;

  Future<void> _detectUiType(String baseUrl, String accessToken) async {
    _uiTypeChecked = true;
    try {
      final uri      = Uri.parse('$baseUrl/');
      // In v0.4 the tunnel-side Mainsail root is gated by the auth proxy;
      // we attach the EdDSA token. On LAN the header is ignored.
      final response = await _authedGet(
          uri, accessToken,
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
      // Detection failed — retry on next successful poll
      _uiTypeChecked = false;
    }
  }

  void start({Duration interval = const Duration(seconds: 4)}) {
    _poll();
    _timer = Timer.periodic(interval, (_) => _poll());
  }

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
    if (!SupabaseService.instance.ready) {
      // Supabase isn't authenticated yet (cold start, no network).
      if (!_disposed) _controller.add(PrinterStatus.offline);
      return;
    }

    // 0. v0.5.0: every Nth poll, kick off a non-blocking mDNS browse so
    //    the LanDiscoveryService cache stays fresh against IP changes.
    //    Fire-and-forget — never gate the poll itself on the browse.
    _pollCount++;
    if (_pollCount % _mDnsBrowseEveryNPolls == 1) {
      LanDiscoveryService.instance.refresh().ignore();
    }

    // 1. Fresh access token + tunnel URL from Supabase
    PrinterAccess access;
    try {
      access = await PrinterAccessCache.instance.get(config.id);
    } on PrinterUnavailableException {
      // Pi hasn't sent its first heartbeat yet.
      if (!_disposed) _controller.add(PrinterStatus.startingUp);
      return;
    } on PrinterNotFoundException {
      _log('Printer not found in Supabase — emitting offline');
      if (!_disposed) _controller.add(PrinterStatus.offline);
      return;
    } catch (e) {
      _log('Access fetch failed: $e');
      if (!_disposed) _controller.add(PrinterStatus.offline);
      return;
    }

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
    //    without wasting a poll on the stale persisted one.
    final discoveredLanUrl = LanDiscoveryService.instance.lookup(config.id);
    final lanUrl = discoveredLanUrl ?? _currentLanUrl;
    if (lanUrl != null) {
      final lan = await _tryMoongateEndpoint(
          baseUrl: lanUrl, access: access, isLan: true);
      if (lan != null) {
        if (!_disposed) _controller.add(lan);
        return;
      }
    }

    // 4. Tunnel via Cloudflare
    final tunnelStatus =
        await _tryMoongateEndpoint(baseUrl: access.tunnelUrl, access: access, isLan: false);
    if (tunnelStatus != null) {
      if (!_disposed) _controller.add(tunnelStatus);
      return;
    }

    // 5. Maybe the token got invalidated server-side. Drop cache and
    //    try once more with a fresh token before declaring offline.
    PrinterAccessCache.instance.invalidate(config.id);
    try {
      access = await PrinterAccessCache.instance.get(config.id);
    } catch (_) {
      if (!_disposed) _controller.add(PrinterStatus.offline);
      return;
    }
    final retry =
        await _tryMoongateEndpoint(baseUrl: access.tunnelUrl, access: access, isLan: false);
    if (retry != null) {
      if (!_disposed) _controller.add(retry);
      return;
    }

    // 6. All moongate paths failed. Distinguish two cases for the user:
    //    • Pi reachable but Klipper / Moonraker not responding — common
    //      on the K3 when the printer-power toggle inside Mainsail is off
    //      ('waiting'). Tile shows "Connected" + the logo, not "Offline".
    //    • Nothing answers on either LAN or tunnel — actually offline.
    final reachable = await _isPiReachable(access);
    if (!_disposed) {
      _controller.add(reachable ? PrinterStatus.waiting : PrinterStatus.offline);
    }
  }

  // ── Reachability probe ───────────────────────────────────────────────────
  // HEADs the LAN URL (if we have one and haven't been failing it) and the
  // tunnel URL. ANY HTTP response back — auth proxy's 401, nginx's 200/304
  // for the Mainsail root, even an upstream-down 502 — proves the Pi
  // answered. We only get an exception when nothing on that host is
  // listening. Used to differentiate "Klipper not running" from "Pi off"
  // after the moongate /status path has given up.
  Future<bool> _isPiReachable(PrinterAccess access) async {
    final candidates = <String>[
      if (_currentLanUrl != null) _currentLanUrl!,
      access.tunnelUrl,
    ];
    for (final base in candidates) {
      try {
        await http.head(Uri.parse(base))
            .timeout(const Duration(seconds: 2));
        return true;
      } catch (_) {
        // Refused / timeout / DNS — try next candidate
      }
    }
    return false;
  }

  // ── Authed GET helper ────────────────────────────────────────────────────
  // v0.4 puts an EdDSA auth proxy in front of Moonraker on the tunnel
  // side; un-authed calls to /printer/* and /server/* return 401. We
  // attach the access token as Authorization: Bearer on every tunnel-side
  // GET. On the LAN side the header is ignored — nginx and Moonraker
  // don't read it (Moonraker has its own ?token= mechanism and trusts the
  // LAN subnet by default).
  Future<http.Response> _authedGet(
    Uri uri,
    String accessToken, {
    required Duration timeout,
  }) {
    return http
        .get(uri, headers: {'Authorization': 'Bearer $accessToken'})
        .timeout(timeout);
  }

  // ── Chamber sensor discovery (one call per service lifetime) ─────────────

  Future<void> _discoverChamberSensor(PrinterAccess access) async {
    try {
      final uri      = Uri.parse(
          '${access.tunnelUrl}/printer/objects/list');
      final response = await _authedGet(
          uri, access.accessToken,
          timeout: const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body    = jsonDecode(response.body) as Map<String, dynamic>;
        final objects =
            (body['result']?['objects'] as List<dynamic>?) ?? [];
        for (final obj in objects) {
          final key = obj.toString();
          if ((key.startsWith('temperature_sensor ') ||
               key.startsWith('heater_generic ') ||
               key.startsWith('temperature_fan ')) &&
              key.toLowerCase().contains('chamber')) {
            _chamberKey = key;
            break;
          }
        }
      }
      _chamberDiscovered = true;
    } catch (_) {
      // Network blip — retry next poll.
    }
  }

  // ── File metadata for accurate progress (kept from v0.2.x) ───────────────

  Future<void> _fetchFileMetadata(
      String baseUrl, String accessToken, String? filename) async {
    if (filename == null || filename.isEmpty) return;
    if (filename == _metadataFilename) return;
    _estimatedPrintSeconds = null;
    _metadataFilename      = null;
    try {
      final encoded  = Uri.encodeComponent(filename);
      final uri      = Uri.parse(
          '$baseUrl/server/files/metadata?filename=$encoded');
      final response = await _authedGet(
          uri, accessToken,
          timeout: const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body      = jsonDecode(response.body) as Map<String, dynamic>;
        final estimated =
            (body['result']?['estimated_time'] as num?)?.toDouble();
        if (estimated != null && estimated > 0) {
          _estimatedPrintSeconds = estimated;
          _metadataFilename      = filename;
        }
      }
    } catch (_) {}
  }

  // ── Moongate plugin endpoint ─────────────────────────────────────────────

  Future<PrinterStatus?> _tryMoongateEndpoint({
    required String        baseUrl,
    required PrinterAccess access,
    required bool          isLan,
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
      if (response.statusCode == 401) return null;
      if (response.statusCode != 200) return null;

      final body   = jsonDecode(response.body) as Map<String, dynamic>;
      final result = body['result'] as Map<String, dynamic>;
      final status = Map<String, dynamic>.from(
          result['status'] as Map<String, dynamic>);

      if (_chamberKey != null && status[_chamberKey!] == null) {
        await _supplementaryChamberQuery(baseUrl, access.accessToken, status);
      }
      if (status['display_status'] == null ||
          status['virtual_sdcard'] == null) {
        await _supplementaryProgressQuery(baseUrl, access.accessToken, status);
      }

      final stats = status['print_stats'] as Map<String, dynamic>? ?? {};
      if (stats['state'] == 'printing') {
        await _fetchFileMetadata(
            baseUrl, access.accessToken, stats['filename'] as String?);
      }

      // Fire-and-forget UI detection on the first successful connection so
      // the tile knows whether to show the Mainsail or Fluidd logo when no
      // webcam is configured.
      if (!_uiTypeChecked) _detectUiType(baseUrl, access.accessToken);

      return _parseStatus(
        status: status,
        moongateResult: result,
        isLan: isLan,
        baseUrl: baseUrl,
        accessToken: access.accessToken,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _supplementaryChamberQuery(
      String baseUrl, String accessToken, Map<String, dynamic> status) async {
    try {
      final encoded  = Uri.encodeComponent(_chamberKey!);
      final uri      = Uri.parse(
          '$baseUrl/printer/objects/query?$encoded');
      final response = await _authedGet(
          uri, accessToken,
          timeout: const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final s    = body['result']?['status'] as Map<String, dynamic>?;
        final data = s?[_chamberKey!];
        if (data != null) status[_chamberKey!] = data;
      }
    } catch (_) {}
  }

  Future<void> _supplementaryProgressQuery(
      String baseUrl, String accessToken, Map<String, dynamic> status) async {
    try {
      final uri = Uri.parse(
          '$baseUrl/printer/objects/query?display_status&virtual_sdcard');
      final response = await _authedGet(
          uri, accessToken,
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
        }
      }
    } catch (_) {}
  }

  // ── Shared status parser (unchanged from v0.2.x logic) ───────────────────

  PrinterStatus _parseStatus({
    required Map<String, dynamic> status,
    required Map<String, dynamic>? moongateResult,
    required bool                 isLan,
    required String               baseUrl,
    required String               accessToken,
  }) {
    final printStats = status['print_stats'] as Map<String, dynamic>? ?? {};
    final extruder   = status['extruder']    as Map<String, dynamic>? ?? {};
    final heaterBed  = status['heater_bed']  as Map<String, dynamic>? ?? {};

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

    final displayStatus = status['display_status'] as Map<String, dynamic>? ?? {};
    final virtualSdcard = status['virtual_sdcard'] as Map<String, dynamic>? ?? {};

    final state = (printStats['state'] as String?) ?? 'startup';

    final double printDuration =
        (printStats['print_duration'] as num?)?.toDouble() ?? 0.0;
    final double displayProg =
        (displayStatus['progress'] as num?)?.toDouble() ?? 0.0;
    final double sdcardProg =
        (virtualSdcard['progress'] as num?)?.toDouble() ?? 0.0;

    final double progress;
    if (_estimatedPrintSeconds != null &&
        _estimatedPrintSeconds! > 0 &&
        printDuration > 0 &&
        state == 'printing') {
      progress = (printDuration / _estimatedPrintSeconds!).clamp(0.0, 1.0);
    } else if (displayProg > 0.0) {
      progress = displayProg.clamp(0.0, 1.0);
    } else if (sdcardProg > 0.0) {
      progress = sdcardProg.clamp(0.0, 1.0);
    } else {
      progress = 0.0;
    }

    // Persist webcam transform info — keeps the tile correct on next launch.
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
    }

    // Build the absolute snapshot URL from the path the Pi reported plus
    // the base URL we're currently winning the poll on. Tunnel-side needs
    // the EdDSA token in the query string because Image.network can't set
    // headers or cookies — the auth proxy accepts mg_token via query as a
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
      connection:         isLan ? PrinterConnection.local : PrinterConnection.remote,
      webcamSnapshotUrl:  webcamSnapshotUrl,
      webcamFlipH:     (moongateResult?['webcam_flip_horizontal'] as bool?) ?? false,
      webcamFlipV:     (moongateResult?['webcam_flip_vertical']   as bool?) ?? false,
      webcamRotation:  (moongateResult?['webcam_rotation']        as num?)?.toInt() ?? 0,
      webcamTargetFps: (moongateResult?['webcam_target_fps']      as num?)?.toInt() ?? 15,
    );
  }
}
