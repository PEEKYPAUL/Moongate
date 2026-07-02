import 'dart:convert';

/// v0.3.0 printer config - minimal.
///
/// In v0.2.x this held the printer's local IP, the Pi-issued HS256 token,
/// and a Cloudflare tunnel URL. v0.3.0 mediates every call through
/// Supabase: the app calls /printer-access with the printer's UUID and
/// receives the current tunnel URL + a fresh EdDSA token good for ~5
/// minutes. So the only thing we persist locally is the Supabase
/// printer_id and user-facing metadata.
///
/// JSON is versioned via `schema_version` (3 for v0.3.0). Older payloads
/// produced by v0.2.x can be detected and discarded by [PrinterRegistry].
// Sentinel for copyWith's lanUrl param so callers can pass `null` to clear it
// without ambiguity vs "don't change". Module-private const.
const Object _sentinel = Object();

class PrinterConfig {
  static const int schemaVersion = 3;

  /// Supabase printer_id (UUID). Used as the key for /printer-access.
  final String id;

  /// User-chosen name.
  final String name;

  /// Cached LAN address of the Pi, learned from the /status response.
  /// When set, the app tries this URL (with the EdDSA token from
  /// /printer-access) before falling back to the Cloudflare tunnel.
  /// Format: `http://192.168.1.157:80`. Null until first successful poll.
  final String? lanUrl;

  /// Cached webcam display-transform settings, populated from the Moongate
  /// /status response after each successful poll. Persisted so the tile
  /// renders correctly on the very first frame after a cold launch.
  final bool webcamFlipH;
  final bool webcamFlipV;
  final int  webcamRotation; // 0 | 90 | 180 | 270
  final int  webcamTargetFps;

  /// 'mainsail' | 'fluidd' | null - sniffed once on first successful poll.
  /// Persisted so the tile can show the right logo on a cold launch
  /// (e.g. when the printer is powered off and the tile would otherwise
  /// be a blank spinner).
  final String? uiType;

  /// User-supplied camera override, set from the gear on the dashboard tile.
  /// An absolute URL to a camera on the LAN that Klipper doesn't serve - e.g.
  /// an old phone running an IP-webcam app at
  /// `http://192.168.0.107:8080/video`. When set it takes priority over the
  /// Pi-reported webcam: fetched directly on LAN, or routed through the Pi's
  /// `/mg-extcam` proxy (private-IP targets only) when remote. Null = use
  /// whatever the Pi reports (which may itself be an auto-detected external
  /// camera from Mainsail's webcam config).
  final String? customCameraUrl;

  /// Macro names the user has starred in the macro sheet to pin them to the
  /// top of the list (per-printer - some machines have dozens of macros and
  /// only a handful are run often). Stored as the raw Klipper macro names.
  /// Additive and optional, so it rides the v3 backup envelope without a
  /// schema bump. Empty when nothing is starred.
  final List<String> favouriteMacros;

  /// Per-printer lighting control (v0.9.8). [lightingEnabled] shows the bulb
  /// icon on the tile's webcam; the user supplies EITHER an on+off macro pair
  /// OR a single toggle macro, and optionally a [lightStatusObject] (a Klipper
  /// object such as `output_pin caselight` / `led …`) whose live value drives
  /// the lit/dark icon. All additive + optional, so they ride the v3 backup
  /// envelope without a schema bump.
  final bool    lightingEnabled;
  final String? lightOnMacro;
  final String? lightOffMacro;
  final String? lightToggleMacro;
  final String? lightStatusObject;

  /// Per-printer advanced power control (v0.9.11). [powerMacroEnabled] makes the
  /// tile's power button drive the printer via macros instead of a Moonraker
  /// `[power …]` device - for printers whose power is a Klipper macro. EITHER an
  /// on+off macro pair OR a single toggle macro. Stateless by design: power-by-
  /// macro can't reliably report state (powering off takes Klipper down), so the
  /// button offers an explicit On/Off choice rather than guessing. Additive +
  /// optional → rides the v3 backup envelope.
  final bool    powerMacroEnabled;
  final String? powerOnMacro;
  final String? powerOffMacro;
  final String? powerToggleMacro;

  /// Per-printer dashboard display (v0.9.12). When true, this printer's tile
  /// drops its 1:1 webcam square and renders compact (just the name +
  /// temperature band) on the dashboard, so printers you don't need to watch
  /// take far less space and the grid packs them masonry-style. The full
  /// webcam is still one tap away on the printer page. Additive + optional →
  /// rides the v3 backup envelope without a schema bump.
  final bool hideWebcam;

  const PrinterConfig({
    required this.id,
    required this.name,
    this.lanUrl,
    this.webcamFlipH     = false,
    this.webcamFlipV     = false,
    this.webcamRotation  = 0,
    this.webcamTargetFps = 15,
    this.uiType,
    this.customCameraUrl,
    this.favouriteMacros = const [],
    this.lightingEnabled   = false,
    this.lightOnMacro,
    this.lightOffMacro,
    this.lightToggleMacro,
    this.lightStatusObject,
    this.powerMacroEnabled = false,
    this.powerOnMacro,
    this.powerOffMacro,
    this.powerToggleMacro,
    this.hideWebcam = false,
  });

  PrinterConfig copyWith({
    String? name,
    Object? lanUrl = _sentinel, // sentinel so we can copy null in
    bool?   webcamFlipH,
    bool?   webcamFlipV,
    int?    webcamRotation,
    int?    webcamTargetFps,
    String? uiType,
    Object? customCameraUrl = _sentinel,
    List<String>? favouriteMacros,
    bool?   lightingEnabled,
    Object? lightOnMacro      = _sentinel,
    Object? lightOffMacro     = _sentinel,
    Object? lightToggleMacro  = _sentinel,
    Object? lightStatusObject = _sentinel,
    bool?   powerMacroEnabled,
    Object? powerOnMacro      = _sentinel,
    Object? powerOffMacro     = _sentinel,
    Object? powerToggleMacro  = _sentinel,
    bool?   hideWebcam,
  }) =>
      PrinterConfig(
        id:              id,
        name:            name            ?? this.name,
        lanUrl:          identical(lanUrl, _sentinel) ? this.lanUrl : lanUrl as String?,
        webcamFlipH:     webcamFlipH     ?? this.webcamFlipH,
        webcamFlipV:     webcamFlipV     ?? this.webcamFlipV,
        webcamRotation:  webcamRotation  ?? this.webcamRotation,
        webcamTargetFps: webcamTargetFps ?? this.webcamTargetFps,
        uiType:          uiType          ?? this.uiType,
        customCameraUrl: identical(customCameraUrl, _sentinel)
            ? this.customCameraUrl
            : customCameraUrl as String?,
        favouriteMacros: favouriteMacros ?? this.favouriteMacros,
        lightingEnabled: lightingEnabled ?? this.lightingEnabled,
        lightOnMacro: identical(lightOnMacro, _sentinel)
            ? this.lightOnMacro
            : lightOnMacro as String?,
        lightOffMacro: identical(lightOffMacro, _sentinel)
            ? this.lightOffMacro
            : lightOffMacro as String?,
        lightToggleMacro: identical(lightToggleMacro, _sentinel)
            ? this.lightToggleMacro
            : lightToggleMacro as String?,
        lightStatusObject: identical(lightStatusObject, _sentinel)
            ? this.lightStatusObject
            : lightStatusObject as String?,
        powerMacroEnabled: powerMacroEnabled ?? this.powerMacroEnabled,
        powerOnMacro: identical(powerOnMacro, _sentinel)
            ? this.powerOnMacro
            : powerOnMacro as String?,
        powerOffMacro: identical(powerOffMacro, _sentinel)
            ? this.powerOffMacro
            : powerOffMacro as String?,
        powerToggleMacro: identical(powerToggleMacro, _sentinel)
            ? this.powerToggleMacro
            : powerToggleMacro as String?,
        hideWebcam: hideWebcam ?? this.hideWebcam,
      );

  /// Normalise a user-typed printer address into a base [lanUrl] such as
  /// `http://192.168.1.50:7125`, or null if [input] is blank. Accepts a bare
  /// host, `host:port`, or a full `http(s)://` URL; defaults to http, drops
  /// any path, and validates host + port so a typo never gets persisted.
  ///
  /// Used by the "Advanced - custom network" field on the add-printer screen
  /// and the edit-printer dialog so people behind a reverse proxy / Docker can
  /// point the app straight at the address that serves their Mainsail/Fluidd
  /// page (the same origin that proxies the Moonraker API) - bypassing mDNS
  /// and the Pi-advertised IP/port entirely. Returns a clean base ready to
  /// have `/server/...` paths appended.
  static String? parseLanUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    var scheme = 'http';
    final schemeMatch =
        RegExp(r'^(https?)://', caseSensitive: false).firstMatch(s);
    if (schemeMatch != null) {
      scheme = schemeMatch.group(1)!.toLowerCase();
      s = s.substring(schemeMatch.end);
    }
    // Keep only the authority (host[:port]); drop any path/query a user
    // pasted from a browser URL bar.
    s = s.split('/').first.split('?').first.trim();
    final m = RegExp(r'^([A-Za-z0-9.\-]+)(?::(\d{1,5}))?$').firstMatch(s);
    if (m == null) return null;
    final host = m.group(1)!;
    final port = m.group(2);
    if (port != null) {
      final p = int.tryParse(port);
      if (p == null || p < 1 || p > 65535) return null;
      return '$scheme://$host:$port';
    }
    return '$scheme://$host';
  }

  // ── v0.2.x compat getters ──────────────────────────────────────────────
  //
  // These remain so UI code that still reads `printer.host` etc. keeps
  // compiling. v0.3.0 fetches everything fresh per call via Supabase
  // `/printer-access`; the stored fields are no longer the truth.
  //
  // !!! DO NOT USE THESE STUBS TO BUILD URLS !!!
  // Reading `host` to construct a snapshot / status / control URL silently
  // produces a relative path (e.g. `/webcam/?action=snapshot`), Image.network
  // and http.get error out, and the widget shows an error placeholder while
  // looking superficially "fine" in code review. This is exactly the bug the
  // v0.3 → v0.4.0 webcam preview regression rode in on (fixed in v0.4.1).
  // The authoritative absolute URL for any printer-bound request comes from
  // PrinterStatus (built by PrinterStatusService each poll using the LAN /
  // tunnel base it's currently winning on, plus the EdDSA token).
  String  get host         => '';
  String? get remoteHost   => null;
  String  get token        => '';
  bool    get preferRemote => true;

  Map<String, dynamic> toJson() => {
        'schema_version':  schemaVersion,
        'id':              id,
        'name':            name,
        if (lanUrl != null) 'lanUrl': lanUrl,
        'webcamFlipH':     webcamFlipH,
        'webcamFlipV':     webcamFlipV,
        'webcamRotation':  webcamRotation,
        'webcamTargetFps': webcamTargetFps,
        if (uiType != null) 'uiType': uiType,
        if (customCameraUrl != null) 'customCameraUrl': customCameraUrl,
        if (favouriteMacros.isNotEmpty) 'favouriteMacros': favouriteMacros,
        if (lightingEnabled) 'lightingEnabled': lightingEnabled,
        if (lightOnMacro != null) 'lightOnMacro': lightOnMacro,
        if (lightOffMacro != null) 'lightOffMacro': lightOffMacro,
        if (lightToggleMacro != null) 'lightToggleMacro': lightToggleMacro,
        if (lightStatusObject != null) 'lightStatusObject': lightStatusObject,
        if (powerMacroEnabled) 'powerMacroEnabled': powerMacroEnabled,
        if (powerOnMacro != null) 'powerOnMacro': powerOnMacro,
        if (powerOffMacro != null) 'powerOffMacro': powerOffMacro,
        if (powerToggleMacro != null) 'powerToggleMacro': powerToggleMacro,
        if (hideWebcam) 'hideWebcam': hideWebcam,
      };

  factory PrinterConfig.fromJson(Map<String, dynamic> j) {
    final version = j['schema_version'] as int?;
    if (version != schemaVersion) {
      throw const FormatException('legacy_v02_config');
    }
    return PrinterConfig(
      id:              j['id']   as String,
      name:            j['name'] as String,
      lanUrl:          j['lanUrl']          as String?,
      webcamFlipH:     j['webcamFlipH']     as bool? ?? false,
      webcamFlipV:     j['webcamFlipV']     as bool? ?? false,
      webcamRotation:  j['webcamRotation']  as int?  ?? 0,
      webcamTargetFps: j['webcamTargetFps'] as int?  ?? 15,
      uiType:          j['uiType']          as String?,
      customCameraUrl: j['customCameraUrl'] as String?,
      favouriteMacros: (j['favouriteMacros'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      lightingEnabled:   j['lightingEnabled']   as bool?   ?? false,
      lightOnMacro:      j['lightOnMacro']       as String?,
      lightOffMacro:     j['lightOffMacro']      as String?,
      lightToggleMacro:  j['lightToggleMacro']   as String?,
      lightStatusObject: j['lightStatusObject']  as String?,
      powerMacroEnabled: j['powerMacroEnabled']  as bool?   ?? false,
      powerOnMacro:      j['powerOnMacro']        as String?,
      powerOffMacro:     j['powerOffMacro']       as String?,
      powerToggleMacro:  j['powerToggleMacro']    as String?,
      hideWebcam:        j['hideWebcam']          as bool?   ?? false,
    );
  }

  static List<PrinterConfig> listFromJson(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => PrinterConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<PrinterConfig> printers) =>
      jsonEncode(printers.map((p) => p.toJson()).toList());

  /// v3 backup envelope: the printer list, an optional single-use restore
  /// code that lets a reinstalled app reclaim these printers (re-bind them to
  /// the new identity) without re-pairing, and an optional `settings` map of
  /// the user's global app preferences (theme, colours, columns, language, …;
  /// see [SettingsBackup]). Legacy backups were a bare array and v2 omitted
  /// `settings`; PrinterRegistry.importFromBackupFile still reads both.
  static String toBackupJson(List<PrinterConfig> printers,
          {String? restoreCode, Map<String, dynamic>? settings}) =>
      jsonEncode({
        'backup_version': 3,
        if (restoreCode != null) 'restore_code': restoreCode,
        'printers': printers.map((p) => p.toJson()).toList(),
        if (settings != null && settings.isNotEmpty) 'settings': settings,
      });
}

/// Live network path used by the last successful poll. v0.3.0 always
/// goes via tunnel (Supabase mediates the URL), so [PrinterConnection.local]
/// is no longer reported. Kept for backward-compat with the UI.
enum PrinterConnection { local, remote, offline }

/// Shared status → sort rank for BOTH the dashboard tiles and the print
/// notification, so the two orderings can never drift. Lower sorts first; ties
/// keep their original (added / dashboard) order via the callers' stable sort.
/// Priority: Error (needs attention) → Printing (incl. heating / paused) →
/// Ready → Idle → Offline.
int printerStatusRank(String state) => switch (state) {
      'error' => 0,
      'printing' || 'heating' || 'paused' => 1,
      'standby' || 'complete' || 'cancelled' => 2,
      'waiting' || 'startup' || 'starting_up' || 'connecting' => 3,
      'offline' => 4,
      _ => 3,
    };

/// One toolhead's live temperature, for printers that report more than one
/// extruder (IDEX, multi-material, tool changers). T0 is Klipper's `extruder`,
/// T1 its `extruder1`, and so on; [index] is that tool number. The dashboard
/// tile shows a flame + `T{index}` + temperature chip per entry, but only when
/// a printer reports more than one - a normal single-hotend machine keeps the
/// classic single chip.
class ToolheadTemp {
  final int    index;   // 0-based tool number, shown as T{index}
  final double temp;
  final double target;
  final bool   active;  // Klipper's currently-selected tool (toolhead.extruder)

  const ToolheadTemp({
    required this.index,
    required this.temp,
    required this.target,
    this.active = false,
  });
}

class PrinterStatus {
  /// Klipper print_stats state plus our synthetic states:
  ///   'printing' | 'paused' | 'standby' | 'complete' | 'cancelled' | 'error'
  ///   'startup'      - Klipper reachable but still initialising
  ///   'connecting'   - before the first status poll completes
  ///   'starting_up'  - Pi hasn't heartbeated to Supabase yet (just paired)
  ///   'waiting'      - Pi reachable, but the printer-side stack isn't
  ///                    (K3 printer power off, Klipper not running, etc.)
  ///   'offline'      - all network paths exhausted, Pi unreachable
  final String state;
  final double progress; // 0.0 - 1.0
  final double hotendTemp;
  final double hotendTarget;
  final double bedTemp;
  final double bedTarget;
  final double chamberTemp;
  final double chamberTarget;

  /// Per-toolhead live temperatures for multi-extruder printers (IDEX / tool
  /// changers). One entry per detected toolhead (T0 = `extruder`, T1 =
  /// `extruder1`, ...). Empty or single-entry on an ordinary one-hotend
  /// printer, where the tile keeps its classic single hotend chip; the grid
  /// layout engages only when this has more than one entry. [hotendTemp] /
  /// [hotendTarget] stay T0 so notifications and preheat are unchanged.
  final List<ToolheadTemp> toolheads;

  final String? filename;
  final PrinterConnection connection;

  /// v0.5.0: whether the cloud currently knows the printer's tunnel URL -
  /// i.e. remote access is ready, independent of which path THIS poll won
  /// on. The tile uses it to show a "remote connecting…" vs "remote ready"
  /// hint next to the Local badge, so a freshly-paired printer that came up
  /// Local can show the tunnel still being established in the background.
  final bool tunnelReady;

  /// Absolute, ready-to-fetch snapshot URL - base + path + (mg_token for
  /// tunnel mode). Built fresh each poll by PrinterStatusService so the
  /// URL always reflects the path the service is currently using and
  /// carries a valid access token. Null when no webcam is configured or
  /// the printer hasn't been reached yet.
  final String? webcamSnapshotUrl;
  final bool    webcamFlipH;
  final bool    webcamFlipV;
  final int     webcamRotation;
  final int     webcamTargetFps;

  /// True when [webcamSnapshotUrl] points at an external camera (a user
  /// override, or one auto-detected from Mainsail's webcam config) rather than
  /// the normal Pi snapshot endpoint. The tile then uses an MJPEG-aware
  /// fetcher that can pull a single frame from a stream URL, since these
  /// cameras usually expose only a stream (e.g. .../video), not a snapshot.
  final bool webcamIsExternal;

  /// Live light state from the configured [PrinterConfig.lightStatusObject]
  /// (v0.9.8): true = on, false = off, null = no status object configured or
  /// not yet known. Drives the lit/dark bulb on the tile.
  final bool? lightOn;

  /// True when Moonraker reports Klipper is shut down or errored
  /// (webhooks.state == "shutdown" / "error") - e.g. after an emergency stop.
  /// The tile swaps the E-STOP triangle for a firmware-restart button then.
  final bool klippyShutdown;

  const PrinterStatus({
    required this.state,
    required this.progress,
    required this.hotendTemp,
    required this.hotendTarget,
    required this.bedTemp,
    required this.bedTarget,
    this.chamberTemp   = 0,
    this.chamberTarget = 0,
    this.toolheads     = const [],
    this.filename,
    this.connection = PrinterConnection.offline,
    this.tunnelReady = false,
    this.webcamSnapshotUrl,
    this.webcamFlipH    = false,
    this.webcamFlipV    = false,
    this.webcamRotation = 0,
    this.webcamTargetFps = 15,
    this.webcamIsExternal = false,
    this.lightOn,
    this.klippyShutdown = false,
  });

  bool get isPrinting => state == 'printing' || state == 'paused';
  bool get isIdle => state == 'standby';

  /// Returns a copy with selected fields replaced. Used by the live tutorial to
  /// briefly doctor a tile's state for the demo (force tunnel mode, inject a
  /// chamber reading) and then restore the real one.
  PrinterStatus copyWith({
    String? state,
    double? progress,
    double? hotendTemp,
    double? hotendTarget,
    double? bedTemp,
    double? bedTarget,
    double? chamberTemp,
    double? chamberTarget,
    List<ToolheadTemp>? toolheads,
    String? filename,
    PrinterConnection? connection,
    bool? tunnelReady,
    String? webcamSnapshotUrl,
    bool? webcamFlipH,
    bool? webcamFlipV,
    int? webcamRotation,
    int? webcamTargetFps,
    bool? webcamIsExternal,
    bool? lightOn,
    bool? klippyShutdown,
  }) {
    return PrinterStatus(
      state:            state ?? this.state,
      progress:         progress ?? this.progress,
      hotendTemp:       hotendTemp ?? this.hotendTemp,
      hotendTarget:     hotendTarget ?? this.hotendTarget,
      bedTemp:          bedTemp ?? this.bedTemp,
      bedTarget:        bedTarget ?? this.bedTarget,
      chamberTemp:      chamberTemp ?? this.chamberTemp,
      chamberTarget:    chamberTarget ?? this.chamberTarget,
      toolheads:        toolheads ?? this.toolheads,
      filename:         filename ?? this.filename,
      connection:       connection ?? this.connection,
      tunnelReady:      tunnelReady ?? this.tunnelReady,
      webcamSnapshotUrl: webcamSnapshotUrl ?? this.webcamSnapshotUrl,
      webcamFlipH:      webcamFlipH ?? this.webcamFlipH,
      webcamFlipV:      webcamFlipV ?? this.webcamFlipV,
      webcamRotation:   webcamRotation ?? this.webcamRotation,
      webcamTargetFps:  webcamTargetFps ?? this.webcamTargetFps,
      webcamIsExternal: webcamIsExternal ?? this.webcamIsExternal,
      lightOn:          lightOn ?? this.lightOn,
      klippyShutdown:   klippyShutdown ?? this.klippyShutdown,
    );
  }

  static const offline = PrinterStatus(
    state: 'offline',
    progress: 0,
    hotendTemp: 0,
    hotendTarget: 0,
    bedTemp: 0,
    bedTarget: 0,
    connection: PrinterConnection.offline,
  );

  static const startingUp = PrinterStatus(
    state: 'starting_up',
    progress: 0,
    hotendTemp: 0,
    hotendTarget: 0,
    bedTemp: 0,
    bedTarget: 0,
    connection: PrinterConnection.offline,
  );

  /// Pi is reachable but its printer-side stack isn't responding - e.g.
  /// the K3's printer power is toggled off so Klipper isn't running, or
  /// Moonraker hasn't come back up yet after a restart.
  static const waiting = PrinterStatus(
    state: 'waiting',
    progress: 0,
    hotendTemp: 0,
    hotendTarget: 0,
    bedTemp: 0,
    bedTarget: 0,
    connection: PrinterConnection.offline,
  );
}
