import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/printer_config.dart';
import 'lan_discovery_service.dart';
import 'printer_access_cache.dart';
import 'printer_registry.dart';
import 'supabase_service.dart';

/// Sends print-control commands to the Moongate plugin.
///
/// v0.3.0: each call fetches a fresh `{tunnel_url, access_token}` from
/// Supabase (via [PrinterAccessCache]) before hitting the Pi. The plugin
/// validates the EdDSA token and proxies the action through to Klipper.
class PrintControlService {
  final PrinterConfig config;
  PrintControlService(this.config);

  /// Send a print control action.
  /// [action]: `pause` | `resume` | `cancel` | `firmware_restart` | `emergency_stop`
  /// Returns `true` if the Pi accepted the command.
  Future<bool> sendAction(String action) async {
    if (!SupabaseService.instance.ready) return false;

    PrinterAccess access;
    try {
      access = await PrinterAccessCache.instance.get(config.id);
    } catch (_) {
      return false;
    }

    // v0.5.0: pick the freshest available LAN URL.
    //   1. A discovered URL from mDNS (= what the Pi is *currently*
    //      advertising on the LAN - survives DHCP IP changes).
    //   2. The registry-live lanUrl (what the status service most
    //      recently learned from a successful /status response). This
    //      read closes the v0.4.x bug where the control service captured
    //      `config.lanUrl` at construction and never re-read it, so an
    //      IP change picked up by the status service didn't propagate to
    //      pause/resume/cancel until the tile was rebuilt.
    //   3. Fall through to the construction-time config.lanUrl if the
    //      registry entry has vanished (race during printer removal).
    //
    // See docs/v0.5-lan-discovery-design.md §8.2 and §10.2.
    final discovered = LanDiscoveryService.instance.lookup(config.id);
    final live = PrinterRegistry.instance.printers
        .firstWhere(
          (p) => p.id == config.id,
          orElse: () => config,
        )
        .lanUrl;
    final lanUrl = discovered ?? live;
    if (lanUrl != null &&
        await _send(lanUrl, access.accessToken, action,
                    timeout: const Duration(seconds: 2))) {
      return true;
    }

    // Tunnel only when the cloud has reported one. v0.5.0: a freshly-paired
    // printer can be controlled over LAN before its tunnel exists, so a null
    // tunnel here is normal, not a failure.
    if (access.tunnelUrl != null &&
        await _send(access.tunnelUrl!, access.accessToken, action,
                    timeout: const Duration(seconds: 10))) {
      return true;
    }

    // 401 / network blip - drop the cache and retry tunnel once with a
    // fresh token. LAN already tried.
    PrinterAccessCache.instance.invalidate(config.id);
    try {
      access = await PrinterAccessCache.instance.get(config.id);
    } catch (_) {
      return false;
    }
    if (access.tunnelUrl == null) return false;
    return _send(access.tunnelUrl!, access.accessToken, action,
                 timeout: const Duration(seconds: 10));
  }

  Future<bool> _send(
    String baseUrl,
    String token,
    String action, {
    required Duration timeout,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/server/moongate/control'
        '?mg_token=${Uri.encodeComponent(token)}'
        '&action=${Uri.encodeComponent(action)}',
      );
      final response = await http.post(uri).timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── G-code library: list stored files + start a print ─────────────────────
  //
  // These talk to Moonraker directly (not the plugin's /control endpoint),
  // mirroring how PrinterStatusService already pulls /printer/objects/query
  // and /server/files/metadata: on LAN no auth header (Moonraker trusts the
  // subnet), on the tunnel a Bearer token (the auth proxy gates it). So the
  // feature needs no plugin update - it rides the same transparent proxy.

  /// List the G-code files stored on the printer (Moonraker `gcodes` root),
  /// newest first, together with the connection (LAN or tunnel) that answered
  /// - so [fetchThumbnail] can reuse that exact path instead of re-probing LAN
  /// on every row (the per-row LAN timeout is what stalled thumbnails on the
  /// tunnel). Returns null when every path failed; the file list may be empty
  /// when the printer simply has no files yet.
  Future<GcodeListing?> listGcodes() async {
    String? winBase;
    var winLan = false;
    final files = await _viaLanThenTunnel<List<GcodeFile>>(
        (base, token, isLan) async {
      try {
        final uri = Uri.parse('$base/server/files/list?root=gcodes');
        final resp = await http
            .get(uri, headers: isLan ? null : {'Authorization': 'Bearer $token'})
            .timeout(Duration(seconds: isLan ? 4 : 12));
        if (resp.statusCode != 200) return null;
        final result =
            (jsonDecode(resp.body)['result'] as List<dynamic>?) ?? const [];
        final files = result
            .whereType<Map<String, dynamic>>()
            .map(GcodeFile.fromJson)
            .where((f) => f.isGcode)
            .toList()
          ..sort((a, b) => b.modified.compareTo(a.modified));
        winBase = base;
        winLan = isLan;
        return files;
      } catch (_) {
        return null;
      }
    });
    if (files == null || winBase == null) return null;
    return GcodeListing(files: files, base: winBase!, isLan: winLan);
  }

  /// Start printing a stored file by its `gcodes`-relative path. LAN-first,
  /// then tunnel; returns true once Moonraker accepts the start.
  Future<bool> startPrint(String filename) async {
    final ok = await _viaLanThenTunnel((base, token, isLan) async {
      try {
        final uri = Uri.parse('$base/printer/print/start'
            '?filename=${Uri.encodeComponent(filename)}');
        final resp = await http
            .post(uri,
                headers: isLan ? null : {'Authorization': 'Bearer $token'})
            .timeout(Duration(seconds: isLan ? 4 : 12));
        // null (not false) on a non-200 so the next path is still tried - a LAN
        // Moonraker that rejects an untrusted POST falls back to the tunnel.
        return resp.statusCode == 200 ? true : null;
      } catch (_) {
        return null;
      }
    });
    return ok ?? false;
  }

  // ── Klipper macros: list the defined macros + run one ──────────────────────
  //
  // Same transparent-proxy story as the G-code calls above: `printer/objects/
  // list` and `printer/gcode/script` are core Moonraker endpoints, so on LAN
  // they go header-less and on the tunnel they carry the Bearer token the auth
  // proxy gates - no plugin update needed. `objects/query` is already used by
  // PrinterStatusService over the tunnel, and `gcode/script` is just an action
  // POST like `print/start`, so both are known to pass the proxy.

  /// List the Klipper macros defined on the printer - the `[gcode_macro …]`
  /// sections, read from Moonraker's `printer/objects/list` and filtered to the
  /// `gcode_macro ` objects. Hidden: `_`-prefixed helpers (Klipper's private-
  /// macro convention) and Moongate's own plumbing macros (`MOONGATE_*` - one
  /// of which unpairs the printer). Returns the bare macro names, alphabetised
  /// (case-insensitively); null when every path failed, an empty list when the
  /// printer simply defines no user macros.
  Future<List<String>?> listMacros() async {
    const prefix = 'gcode_macro ';
    return _viaLanThenTunnel<List<String>>((base, token, isLan) async {
      try {
        final uri = Uri.parse('$base/printer/objects/list');
        final resp = await http
            .get(uri, headers: isLan ? null : {'Authorization': 'Bearer $token'})
            .timeout(Duration(seconds: isLan ? 4 : 12));
        if (resp.statusCode != 200) return null;
        final objects =
            (jsonDecode(resp.body)['result']?['objects'] as List<dynamic>?) ??
                const [];
        return objects
            .whereType<String>()
            .where((o) => o.startsWith(prefix))
            .map((o) => o.substring(prefix.length))
            .where((name) =>
                !name.startsWith('_') &&
                !name.toUpperCase().startsWith('MOONGATE_'))
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      } catch (_) {
        return null;
      }
    });
  }

  /// For the lighting config screen: the printer's runnable macros (same filter
  /// as [listMacros]) plus its light-capable objects (output_pin / led /
  /// neopixel / dotstar), each as the full Klipper object name so the status
  /// poll can query its live value. One `printer/objects/list` fetch; null when
  /// every path failed.
  Future<({List<String> macros, List<String> lightObjects})?>
      listLightingTargets() async {
    const macroPrefix = 'gcode_macro ';
    const lightPrefixes = [
      'output_pin ', 'led ', 'neopixel ', 'dotstar ', 'pca9533 ', 'pca9632 ',
    ];
    return _viaLanThenTunnel((base, token, isLan) async {
      try {
        final uri = Uri.parse('$base/printer/objects/list');
        final resp = await http
            .get(uri, headers: isLan ? null : {'Authorization': 'Bearer $token'})
            .timeout(Duration(seconds: isLan ? 4 : 12));
        if (resp.statusCode != 200) return null;
        final objects =
            (jsonDecode(resp.body)['result']?['objects'] as List<dynamic>?) ??
                const [];
        final strs = objects.whereType<String>().toList();
        final macros = strs
            .where((o) => o.startsWith(macroPrefix))
            .map((o) => o.substring(macroPrefix.length))
            .where((name) =>
                !name.startsWith('_') &&
                !name.toUpperCase().startsWith('MOONGATE_'))
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        final lights = strs
            .where((o) => lightPrefixes.any((p) => o.startsWith(p)))
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return (macros: macros, lightObjects: lights);
      } catch (_) {
        return null;
      }
    });
  }

  /// POST a single G-code line to Moonraker's `printer/gcode/script` over
  /// [base]. Returns true on HTTP 200, else null so [_viaLanThenTunnel] tries
  /// the next path. One command per call: callers that set several things (e.g.
  /// [setHeaterTargets]) issue one request each rather than a newline-joined
  /// batch, so a single heater can't abort the rest and each result is visible.
  Future<bool?> _postGcode(
      String base, String token, bool isLan, String gcode) async {
    try {
      final uri = Uri.parse('$base/printer/gcode/script'
          '?script=${Uri.encodeComponent(gcode)}');
      final resp = await http
          .post(uri,
              headers: isLan ? null : {'Authorization': 'Bearer $token'})
          .timeout(Duration(seconds: isLan ? 4 : 12));
      // null (not false) on non-200 so the next path is still tried.
      return resp.statusCode == 200 ? true : null;
    } catch (_) {
      return null;
    }
  }

  /// Run a Klipper macro by name via Moonraker's `printer/gcode/script`. Klipper
  /// uppercases the command token before dispatch, so the name is sent verbatim
  /// from the object list. LAN-first, then tunnel; returns true once Moonraker
  /// accepts it (200).
  Future<bool> runMacro(String macro) async {
    final ok = await _viaLanThenTunnel(
        (base, token, isLan) => _postGcode(base, token, isLan, macro));
    return ok ?? false;
  }

  // ── Heaters: detect object names + set target temperatures ─────────────────
  //
  // `SET_HEATER_TEMPERATURE HEATER=<name> TARGET=<°C>` is a core Klipper gcode,
  // so it rides the same transparent `printer/gcode/script` proxy as [runMacro]
  // - no plugin update. The one wrinkle is the heater's object NAME: it's almost
  // always `extruder` / `heater_bed`, but a custom config can call them
  // something else (e.g. `[heater_generic hotend]`). So we ask the printer for
  // its `available_heaters` and map by convention, falling back to the Klipper
  // defaults the rest of the app already assumes (PrinterStatusService reads
  // `extruder` / `heater_bed` directly).

  /// The printer's hotend + bed heater object names for SET_HEATER_TEMPERATURE.
  /// Reads `available_heaters` from Moonraker; on any failure returns the
  /// Klipper defaults (`extruder` / `heater_bed`) so a standard machine still
  /// works without the probe.
  Future<({String hotend, String bed})> detectHeaters() async {
    final names =
        await _viaLanThenTunnel<List<String>>((base, token, isLan) async {
      try {
        final uri = Uri.parse('$base/printer/objects/query?heaters');
        final resp = await http
            .get(uri,
                headers: isLan ? null : {'Authorization': 'Bearer $token'})
            .timeout(Duration(seconds: isLan ? 4 : 12));
        if (resp.statusCode != 200) return null;
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final result = body['result'] as Map<String, dynamic>?;
        final status = result?['status'] as Map<String, dynamic>?;
        final heaters = status?['heaters'] as Map<String, dynamic>?;
        final raw = heaters?['available_heaters'] as List<dynamic>?;
        return (raw ?? const []).whereType<String>().toList();
      } catch (_) {
        return null;
      }
    });
    return mapHeaterNames(names ?? const []);
  }

  /// Pick the hotend + bed heater object names from a printer's [available]
  /// heaters. Hotend: the primary `extruder`, else any `extruder<N>` / a name
  /// containing "hotend", else the default `extruder`. Bed: `heater_bed`, else a
  /// name containing "bed", else the default `heater_bed`. Static + visible for
  /// testing the mapping without a live printer.
  static ({String hotend, String bed}) mapHeaterNames(List<String> available) {
    String resolve(
        List<String> exact, bool Function(String) loose, String fallback) {
      for (final want in exact) {
        for (final a in available) {
          if (a.toLowerCase() == want) return a;
        }
      }
      for (final a in available) {
        if (loose(a.toLowerCase())) return a;
      }
      return fallback;
    }

    final hotend = resolve(
      const ['extruder'],
      (a) => a.startsWith('extruder') || a.contains('hotend'),
      'extruder',
    );
    final bed = resolve(
      const ['heater_bed'],
      (a) => a.contains('bed'),
      'heater_bed',
    );
    return (hotend: hotend, bed: bed);
  }

  /// Set one or more heater target temperatures. [targets] maps each heater
  /// OBJECT name (`extruder`, `extruder1`, ... , `heater_bed`) to its °C target;
  /// pass 0 to turn one off. Sends ONE `SET_HEATER_TEMPERATURE` request per
  /// heater over the transparent `printer/gcode/script` proxy (no plugin update),
  /// reusing a single resolved connection. Returns true once every heater is
  /// accepted, false when [targets] is empty or any heater is rejected. Used by
  /// the preheat sheet, including multi-toolhead machines that set every hotend
  /// (up to 6) at once.
  ///
  /// One request per heater rather than a single newline-joined script: separate
  /// commands stop one heater's error from aborting the rest, and each result is
  /// logged so a multi-toolhead set that only takes on some hotends is
  /// diagnosable. The connection is resolved once and reused, so a 6-hotend set
  /// does not pay a LAN-probe timeout per command.
  Future<bool> setHeaterTargets(Map<String, double> targets) async {
    if (targets.isEmpty) return false;
    final cmds = targets.entries
        .map((e) =>
            'SET_HEATER_TEMPERATURE HEATER=${e.key} TARGET=${e.value.round()}')
        .toList();
    final result = await _viaLanThenTunnel<bool>((base, token, isLan) async {
      // The first command doubles as the connection probe: a miss returns null
      // so _viaLanThenTunnel falls through to the next path; the rest then ride
      // the same connection.
      final firstOk = await _postGcode(base, token, isLan, cmds.first);
      dev.log('${isLan ? 'lan' : 'tunnel'} "${cmds.first}" -> $firstOk',
          name: 'MOONGATE/PREHEAT');
      if (firstOk != true) return null;
      var allOk = true;
      for (final cmd in cmds.skip(1)) {
        final ok = await _postGcode(base, token, isLan, cmd);
        dev.log('"$cmd" -> $ok', name: 'MOONGATE/PREHEAT');
        if (ok != true) allOk = false;
      }
      return allOk;
    });
    return result ?? false;
  }

  /// Convenience for the common single-hotend + bed case. A null target leaves
  /// that heater untouched; 0 turns one off. Thin wrapper over
  /// [setHeaterTargets].
  Future<bool> setHeaters({
    double? hotend,
    double? bed,
    required String hotendName,
    required String bedName,
  }) =>
      setHeaterTargets({
        if (hotend != null) hotendName: hotend,
        if (bed != null) bedName: bed,
      });

  /// Clear a finished job and return Klipper's print state to standby (Idle).
  ///
  /// After a print ends, `print_stats.state` stays at `complete` (or
  /// `cancelled`) until something clears it, so the tile keeps showing
  /// "Done"/"Cancelled". `SDCARD_RESET_FILE` unloads the virtual-sdcard file and
  /// calls `print_stats.reset()`, which returns the state to `standby` - the
  /// same gcode Mainsail/Fluidd fire from their post-print "clear" action (it
  /// resets the stats even when no file is loaded, and Klipper only refuses it
  /// when run *from* the SD file mid-print, which never applies here). Rides the
  /// same transparent `printer/gcode/script` proxy as [runMacro] (no plugin
  /// update); because it changes the *real* Klipper state, both the dashboard
  /// poll and the notification isolate read Idle on their next cycle.
  Future<bool> resetPrintState() async {
    final ok = await _viaLanThenTunnel((base, token, isLan) async {
      try {
        final uri = Uri.parse('$base/printer/gcode/script'
            '?script=${Uri.encodeComponent('SDCARD_RESET_FILE')}');
        final resp = await http
            .post(uri,
                headers: isLan ? null : {'Authorization': 'Bearer $token'})
            .timeout(Duration(seconds: isLan ? 4 : 12));
        // null (not false) on non-200 so the next path is still tried.
        return resp.statusCode == 200 ? true : null;
      } catch (_) {
        return null;
      }
    });
    return ok ?? false;
  }

  // ── Power devices: list + switch a Moonraker [power …] device ──────────────
  //
  // Moonraker's device_power component manages [power …] sections (any type -
  // shelly / gpio / tplink / tasmota …) and stays up while the printer itself
  // is powered off, so these work even when Klipper is down - the "switch the
  // printer on from its tile" case. Core Moonraker endpoints → same transparent
  // proxy as the macro/file calls, no plugin update.

  /// This printer's Moonraker power devices (name + on/off + whether Moonraker
  /// locks it during a print). Null when every path failed; empty when the
  /// printer defines no [power …] device. Works whenever Moonraker is reachable,
  /// including while the printer it controls is off.
  Future<List<PowerDevice>?> listPowerDevices() async {
    return _viaLanThenTunnel<List<PowerDevice>>((base, token, isLan) async {
      try {
        final uri = Uri.parse('$base/machine/device_power/devices');
        final resp = await http
            .get(uri, headers: isLan ? null : {'Authorization': 'Bearer $token'})
            .timeout(Duration(seconds: isLan ? 4 : 12));
        if (resp.statusCode != 200) return null;
        final list =
            (jsonDecode(resp.body)['result']?['devices'] as List<dynamic>?) ??
                const [];
        return list
            .whereType<Map<String, dynamic>>()
            .map(PowerDevice.fromJson)
            .toList();
      } catch (_) {
        return null;
      }
    });
  }

  /// Switch a power [device] on or off via Moonraker. LAN-first, then tunnel;
  /// true once Moonraker accepts it (200). Moonraker itself refuses to power a
  /// `locked_while_printing` device off mid-print, so a rejected off returns
  /// false rather than cutting a running print.
  Future<bool> setPowerDevice(String device, bool on) async {
    final ok = await _viaLanThenTunnel((base, token, isLan) async {
      try {
        final uri = Uri.parse('$base/machine/device_power/device'
            '?device=${Uri.encodeComponent(device)}'
            '&action=${on ? 'on' : 'off'}');
        final resp = await http
            .post(uri,
                headers: isLan ? null : {'Authorization': 'Bearer $token'})
            .timeout(Duration(seconds: isLan ? 4 : 12));
        return resp.statusCode == 200 ? true : null;
      } catch (_) {
        return null;
      }
    });
    return ok ?? false;
  }

  /// Fetch a slicer-embedded thumbnail for [file] over the already-resolved
  /// [base]/[isLan] connection from [listGcodes] - no per-row LAN re-probe,
  /// which is what stalled thumbnails on the tunnel. Reads the file's metadata
  /// for a suitable thumbnail, then pulls it from the gcodes store. Returns the
  /// image bytes, an empty list when the file has no embedded thumbnail, or
  /// null on failure (logged for diagnosis).
  Future<Uint8List?> fetchThumbnail(GcodeFile file,
      {required String base, required bool isLan}) async {
    final PrinterAccess access;
    try {
      access = await PrinterAccessCache.instance.get(config.id);
    } catch (_) {
      return null;
    }
    final headers =
        isLan ? null : {'Authorization': 'Bearer ${access.accessToken}'};
    final where = isLan ? 'lan' : 'tunnel';
    try {
      final metaUri = Uri.parse('$base/server/files/metadata'
          '?filename=${Uri.encodeComponent(file.path)}');
      final metaResp = await http
          .get(metaUri, headers: headers)
          .timeout(Duration(seconds: isLan ? 5 : 15));
      if (metaResp.statusCode != 200) {
        dev.log('thumb meta HTTP ${metaResp.statusCode} ($where) ${file.path}',
            name: 'MOONGATE/THUMB');
        return null;
      }
      final thumbs = (jsonDecode(metaResp.body)['result']?['thumbnails']
              as List<dynamic>?) ??
          const [];
      int widthOf(Map<String, dynamic> t) => (t['width'] as num?)?.toInt() ?? 0;
      final sized = thumbs.whereType<Map<String, dynamic>>().toList()
        ..sort((a, b) => widthOf(a).compareTo(widthOf(b)));
      if (sized.isEmpty) return Uint8List(0); // no embedded thumbnail
      // Largest no wider than 400px (crisp in the tile, light over the tunnel);
      // fall back to the smallest if every thumbnail is larger.
      final capped = sized.where((t) => widthOf(t) <= 400).toList();
      final best = capped.isNotEmpty ? capped.last : sized.first;
      final rel = best['relative_path'] as String?;
      if (rel == null) return Uint8List(0);
      // relative_path is relative to the gcode file's parent folder, so prepend
      // that folder to get the path within the gcodes root.
      final dir = file.folder;
      final thumbPath = dir == null ? rel : '$dir/$rel';
      final encoded = thumbPath.split('/').map(Uri.encodeComponent).join('/');
      final imgUri = Uri.parse('$base/server/files/gcodes/$encoded');
      final imgResp = await http
          .get(imgUri, headers: headers)
          .timeout(Duration(seconds: isLan ? 6 : 20));
      if (imgResp.statusCode != 200) {
        dev.log('thumb img HTTP ${imgResp.statusCode} ($where) $thumbPath',
            name: 'MOONGATE/THUMB');
        return null;
      }
      return imgResp.bodyBytes;
    } catch (e) {
      dev.log('thumb error ($where) ${file.path}: $e', name: 'MOONGATE/THUMB');
      return null;
    }
  }

  /// Resolve the freshest LAN base then the tunnel, running [call] against each
  /// until one returns non-null. Mirrors [sendAction]'s path order - including
  /// the one-shot token refresh + tunnel retry - so a fresh-paired (tunnel-
  /// less) printer still works on LAN and a stale token self-heals.
  Future<T?> _viaLanThenTunnel<T>(
      Future<T?> Function(String base, String token, bool isLan) call) async {
    if (!SupabaseService.instance.ready) return null;

    PrinterAccess access;
    try {
      access = await PrinterAccessCache.instance.get(config.id);
    } catch (_) {
      return null;
    }

    final discovered = LanDiscoveryService.instance.lookup(config.id);
    final live = PrinterRegistry.instance.printers
        .firstWhere((p) => p.id == config.id, orElse: () => config)
        .lanUrl;
    final lanUrl = discovered ?? live;
    if (lanUrl != null) {
      final r = await call(lanUrl, access.accessToken, true);
      if (r != null) return r;
    }

    if (access.tunnelUrl != null) {
      final r = await call(access.tunnelUrl!, access.accessToken, false);
      if (r != null) return r;
    }

    // 401 / network blip - drop the cache, refresh the token, retry tunnel once.
    PrinterAccessCache.instance.invalidate(config.id);
    try {
      access = await PrinterAccessCache.instance.get(config.id);
    } catch (_) {
      return null;
    }
    if (access.tunnelUrl != null) {
      return call(access.tunnelUrl!, access.accessToken, false);
    }
    return null;
  }
}

/// Result of [PrintControlService.listGcodes]: the files plus the connection
/// (LAN or tunnel) that answered, reused for fetching each row's thumbnail so
/// thumbnails don't re-probe LAN per row.
class GcodeListing {
  final List<GcodeFile> files;
  final String base;
  final bool isLan;
  const GcodeListing(
      {required this.files, required this.base, required this.isLan});
}

/// A G-code file stored on the printer, parsed from Moonraker's
/// `/server/files/list?root=gcodes` response.
class GcodeFile {
  /// Path relative to the gcodes root, e.g. `calibration/benchy.gcode`.
  final String path;

  /// Last-modified time in unix seconds (0 when unknown).
  final double modified;

  /// File size in bytes (0 when unknown).
  final int size;

  const GcodeFile({
    required this.path,
    required this.modified,
    required this.size,
  });

  factory GcodeFile.fromJson(Map<String, dynamic> j) => GcodeFile(
        path:     (j['path'] as String?) ?? '',
        modified: (j['modified'] as num?)?.toDouble() ?? 0,
        size:     (j['size'] as num?)?.toInt() ?? 0,
      );

  bool get isGcode {
    final p = path.toLowerCase();
    return p.endsWith('.gcode') || p.endsWith('.gco') || p.endsWith('.g');
  }

  /// Just the filename, without any subdirectory prefix.
  String get name {
    final i = path.lastIndexOf('/');
    return i >= 0 ? path.substring(i + 1) : path;
  }

  /// The subdirectory the file lives in, or null when it sits at the root.
  String? get folder {
    final i = path.lastIndexOf('/');
    return i > 0 ? path.substring(0, i) : null;
  }

  DateTime? get modifiedAt => modified > 0
      ? DateTime.fromMillisecondsSinceEpoch((modified * 1000).round())
      : null;
}

/// A Moonraker power device - a `[power …]` section - from
/// `/machine/device_power/devices`. Type-agnostic: shelly, gpio, tplink,
/// tasmota, etc. all surface here the same way.
class PowerDevice {
  /// The device name (the `[power <name>]` label), e.g. "printer".
  final String name;

  /// True when Moonraker reports the device on. (Moonraker also has transient
  /// "init"/"error" statuses; anything but "on" is treated as off.)
  final bool on;

  /// Moonraker blocks powering this device off while a print is running.
  final bool lockedWhilePrinting;

  const PowerDevice({
    required this.name,
    required this.on,
    required this.lockedWhilePrinting,
  });

  factory PowerDevice.fromJson(Map<String, dynamic> j) => PowerDevice(
        name: (j['device'] as String?) ?? '',
        on: (j['status'] as String?) == 'on',
        lockedWhilePrinting: (j['locked_while_printing'] as bool?) ?? false,
      );
}
