import 'dart:convert';

/// v0.3.0 printer config — minimal.
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

  /// 'mainsail' | 'fluidd' | null — sniffed once on first successful poll.
  /// Persisted so the tile can show the right logo on a cold launch
  /// (e.g. when the printer is powered off and the tile would otherwise
  /// be a blank spinner).
  final String? uiType;

  const PrinterConfig({
    required this.id,
    required this.name,
    this.lanUrl,
    this.webcamFlipH     = false,
    this.webcamFlipV     = false,
    this.webcamRotation  = 0,
    this.webcamTargetFps = 15,
    this.uiType,
  });

  PrinterConfig copyWith({
    String? name,
    Object? lanUrl = _sentinel, // sentinel so we can copy null in
    bool?   webcamFlipH,
    bool?   webcamFlipV,
    int?    webcamRotation,
    int?    webcamTargetFps,
    String? uiType,
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
      );

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
}

/// Live network path used by the last successful poll. v0.3.0 always
/// goes via tunnel (Supabase mediates the URL), so [PrinterConnection.local]
/// is no longer reported. Kept for backward-compat with the UI.
enum PrinterConnection { local, remote, offline }

class PrinterStatus {
  /// Klipper print_stats state plus our synthetic states:
  ///   'printing' | 'paused' | 'standby' | 'complete' | 'cancelled' | 'error'
  ///   'startup'      — Klipper reachable but still initialising
  ///   'connecting'   — before the first status poll completes
  ///   'starting_up'  — Pi hasn't heartbeated to Supabase yet (just paired)
  ///   'waiting'      — Pi reachable, but the printer-side stack isn't
  ///                    (K3 printer power off, Klipper not running, etc.)
  ///   'offline'      — all network paths exhausted, Pi unreachable
  final String state;
  final double progress; // 0.0 – 1.0
  final double hotendTemp;
  final double hotendTarget;
  final double bedTemp;
  final double bedTarget;
  final double chamberTemp;
  final double chamberTarget;
  final String? filename;
  final PrinterConnection connection;

  /// Absolute, ready-to-fetch snapshot URL — base + path + (mg_token for
  /// tunnel mode). Built fresh each poll by PrinterStatusService so the
  /// URL always reflects the path the service is currently using and
  /// carries a valid access token. Null when no webcam is configured or
  /// the printer hasn't been reached yet.
  final String? webcamSnapshotUrl;
  final bool    webcamFlipH;
  final bool    webcamFlipV;
  final int     webcamRotation;
  final int     webcamTargetFps;

  const PrinterStatus({
    required this.state,
    required this.progress,
    required this.hotendTemp,
    required this.hotendTarget,
    required this.bedTemp,
    required this.bedTarget,
    this.chamberTemp   = 0,
    this.chamberTarget = 0,
    this.filename,
    this.connection = PrinterConnection.offline,
    this.webcamSnapshotUrl,
    this.webcamFlipH    = false,
    this.webcamFlipV    = false,
    this.webcamRotation = 0,
    this.webcamTargetFps = 15,
  });

  bool get isPrinting => state == 'printing' || state == 'paused';
  bool get isIdle => state == 'standby';

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

  /// Pi is reachable but its printer-side stack isn't responding — e.g.
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
