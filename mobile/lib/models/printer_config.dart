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

enum MacroControlParameterKind { text, number, toggle }

List<MacroControlParameter> inferMacroParameters(String gcode) {
  final found = <String, MacroControlParameter>{};
  final references = RegExp(
    r'params\.([A-Za-z_][A-Za-z0-9_]*)(?:\s*\|\s*default\s*\(\s*([^)]*?)\s*\))?',
    caseSensitive: false,
  );
  for (final match in references.allMatches(gcode)) {
    final name = match.group(1)!.toUpperCase();
    var value = match.group(2)?.trim() ?? '';
    if (value.length >= 2 &&
        ((value.startsWith("'") && value.endsWith("'")) ||
            (value.startsWith('"') && value.endsWith('"')))) {
      value = value.substring(1, value.length - 1);
    }
    final lower = value.toLowerCase();
    final kind = lower == 'true' || lower == 'false'
        ? MacroControlParameterKind.toggle
        : num.tryParse(value) != null
            ? MacroControlParameterKind.number
            : MacroControlParameterKind.text;
    final parameter = MacroControlParameter(
      name: name,
      label: name,
      kind: kind,
      defaultValue: kind == MacroControlParameterKind.toggle
          ? (lower == 'true' ? '1' : '0')
          : value,
    );
    if (!found.containsKey(name) || found[name]!.defaultValue.isEmpty) {
      found[name] = parameter;
    }
  }
  return found.values.toList();
}

enum ControlPanelModuleType { temperatures, motion, macros }

class ControlPanelModule {
  final String id;
  final ControlPanelModuleType type;
  final String title;
  final int color;

  const ControlPanelModule({
    required this.id,
    required this.type,
    this.title = '',
    this.color = 0xFFFFFFFF,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'color': color,
      };

  factory ControlPanelModule.fromJson(Map<String, dynamic> json) =>
      ControlPanelModule(
        id: json['id'] as String? ?? '',
        type: ControlPanelModuleType.values.firstWhere(
          (type) => type.name == json['type'],
          orElse: () => ControlPanelModuleType.macros,
        ),
        title: json['title'] as String? ?? '',
        color: (json['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
      );
}

const defaultControlPanelModules = [
  ControlPanelModule(
      id: 'temperatures',
      type: ControlPanelModuleType.temperatures,
      color: 0xFFFFFFFF),
  ControlPanelModule(
      id: 'motion', type: ControlPanelModuleType.motion, color: 0xFFFFFFFF),
  ControlPanelModule(
      id: 'macros', type: ControlPanelModuleType.macros, color: 0xFFFFFFFF),
];

class MacroControlParameter {
  final String name;
  final String label;
  final MacroControlParameterKind kind;
  final String defaultValue;

  const MacroControlParameter({
    required this.name,
    required this.label,
    this.kind = MacroControlParameterKind.text,
    this.defaultValue = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'label': label,
        'kind': kind.name,
        'defaultValue': defaultValue,
      };

  factory MacroControlParameter.fromJson(Map<String, dynamic> json) =>
      MacroControlParameter(
        name: json['name'] as String? ?? '',
        label: json['label'] as String? ?? '',
        kind: MacroControlParameterKind.values.firstWhere(
          (kind) => kind.name == json['kind'],
          orElse: () => MacroControlParameterKind.text,
        ),
        defaultValue: json['defaultValue'] as String? ?? '',
      );
}

class MacroControl {
  static final RegExp _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  final String id;
  final String macro;
  final String label;
  final String icon;
  final String color;
  final bool confirm;
  final List<MacroControlParameter> parameters;

  const MacroControl({
    required this.id,
    required this.macro,
    required this.label,
    this.icon = 'play',
    this.color = 'blue',
    this.confirm = true,
    this.parameters = const [],
  });

  bool get isValid {
    final names = parameters.map((parameter) => parameter.name).toList();
    return id.isNotEmpty &&
        label.isNotEmpty &&
        _identifier.hasMatch(macro) &&
        names.every(_identifier.hasMatch) &&
        names.toSet().length == names.length;
  }

  String command(Map<String, String> values) {
    if (!isValid) throw const FormatException('Invalid macro control');
    final arguments = <String>[];
    for (final parameter in parameters) {
      final value = (values[parameter.name] ?? parameter.defaultValue).trim();
      if (value.isEmpty) continue;
      if (value.contains('\n') || value.contains('\r')) {
        throw const FormatException('Macro parameters must be single-line');
      }
      arguments.add('${parameter.name.toUpperCase()}=$value');
    }
    return [macro, ...arguments].join(' ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'macro': macro,
        'label': label,
        'icon': icon,
        'color': color,
        'confirm': confirm,
        'parameters': parameters.map((parameter) => parameter.toJson()).toList(),
      };

  factory MacroControl.fromJson(Map<String, dynamic> json) => MacroControl(
        id: json['id'] as String? ?? '',
        macro: json['macro'] as String? ?? '',
        label: json['label'] as String? ?? '',
        icon: json['icon'] as String? ?? 'play',
        color: json['color'] as String? ?? 'blue',
        confirm: json['confirm'] as bool? ?? true,
        parameters: (json['parameters'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(MacroControlParameter.fromJson)
                .where((parameter) => parameter.name.isNotEmpty)
                .toList() ??
            const [],
      );
}

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

  /// LAN-only / cloudless printer: added from a `moongate://lan` QR (or manual
  /// LAN entry) against a Pi installed with `--lan-only`. There is no Supabase
  /// row and no tunnel; the status/control services poll the plugin over the
  /// LAN with no cloud token (the Pi trusts the LAN). See PrinterStatusService.
  final bool lanOnly;

  /// True when this printer was added through cloud pairing, so its id is the
  /// Supabase row's UUID. Direct-added printers mint a local `lan-<address>`
  /// id instead - there is no cloud row to release on remove, and flipping one
  /// to cloud mode can never work (nothing to poll). Gates the Direct-mode
  /// toggle and the release-on-remove call.
  bool get cloudPaired => !id.startsWith('lan-');

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

  /// Which of the printer's cameras the dashboard tile (and the full-screen
  /// camera) shows, picked from the tile's camera switcher when the plugin
  /// reports more than one (plugin 0.6.22+). Stores the camera's Moonraker
  /// uid (name as the fallback key on older Moonrakers without uids) - never
  /// its list position, so renaming or reordering cameras in Mainsail can't
  /// silently swap the feed. Null = the printer's first camera, exactly the
  /// pre-multicam behaviour; a key that stops matching (camera deleted) also
  /// falls back to the first camera rather than blanking the tile. Additive +
  /// optional → rides the v3 backup envelope without a schema bump.
  final String? selectedWebcam;

  /// Macro names the user has starred in the macro sheet to pin them to the
  /// top of the list (per-printer - some machines have dozens of macros and
  /// only a handful are run often). Stored as the raw Klipper macro names.
  /// Additive and optional, so it rides the v3 backup envelope without a
  /// schema bump. Empty when nothing is starred.
  final List<String> favouriteMacros;

  /// User-built macro cards shown at the top of the macro sheet. Stored with
  /// the printer so controls follow the normal settings backup/restore path.
  final List<MacroControl> macroControls;

  /// Ordered modules in the printer's customizable control panel.
  final List<ControlPanelModule> controlPanelModules;

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
    this.lanOnly         = false,
    this.webcamFlipH     = false,
    this.webcamFlipV     = false,
    this.webcamRotation  = 0,
    this.webcamTargetFps = 15,
    this.uiType,
    this.customCameraUrl,
    this.selectedWebcam,
    this.favouriteMacros = const [],
    this.macroControls    = const [],
    this.controlPanelModules = defaultControlPanelModules,
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
    bool?   lanOnly,
    bool?   webcamFlipH,
    bool?   webcamFlipV,
    int?    webcamRotation,
    int?    webcamTargetFps,
    String? uiType,
    Object? customCameraUrl = _sentinel,
    Object? selectedWebcam  = _sentinel,
    List<String>? favouriteMacros,
    List<MacroControl>? macroControls,
    List<ControlPanelModule>? controlPanelModules,
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
        lanOnly:         lanOnly         ?? this.lanOnly,
        webcamFlipH:     webcamFlipH     ?? this.webcamFlipH,
        webcamFlipV:     webcamFlipV     ?? this.webcamFlipV,
        webcamRotation:  webcamRotation  ?? this.webcamRotation,
        webcamTargetFps: webcamTargetFps ?? this.webcamTargetFps,
        uiType:          uiType          ?? this.uiType,
        customCameraUrl: identical(customCameraUrl, _sentinel)
            ? this.customCameraUrl
            : customCameraUrl as String?,
        selectedWebcam: identical(selectedWebcam, _sentinel)
            ? this.selectedWebcam
            : selectedWebcam as String?,
        favouriteMacros: favouriteMacros ?? this.favouriteMacros,
        macroControls:    macroControls    ?? this.macroControls,
        controlPanelModules:
            controlPanelModules ?? this.controlPanelModules,
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
        if (lanOnly) 'lanOnly': lanOnly,
        'webcamFlipH':     webcamFlipH,
        'webcamFlipV':     webcamFlipV,
        'webcamRotation':  webcamRotation,
        'webcamTargetFps': webcamTargetFps,
        if (uiType != null) 'uiType': uiType,
        if (customCameraUrl != null) 'customCameraUrl': customCameraUrl,
        if (selectedWebcam != null) 'selectedWebcam': selectedWebcam,
        if (favouriteMacros.isNotEmpty) 'favouriteMacros': favouriteMacros,
        if (macroControls.isNotEmpty)
          'macroControls': macroControls.map((control) => control.toJson()).toList(),
        'controlPanelModules':
            controlPanelModules.map((module) => module.toJson()).toList(),
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
      lanOnly:         j['lanOnly']         as bool? ?? false,
      webcamFlipH:     j['webcamFlipH']     as bool? ?? false,
      webcamFlipV:     j['webcamFlipV']     as bool? ?? false,
      webcamRotation:  j['webcamRotation']  as int?  ?? 0,
      webcamTargetFps: j['webcamTargetFps'] as int?  ?? 15,
      uiType:          j['uiType']          as String?,
      customCameraUrl: j['customCameraUrl'] as String?,
      selectedWebcam:  j['selectedWebcam']  as String?,
      favouriteMacros: (j['favouriteMacros'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      macroControls: (j['macroControls'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(MacroControl.fromJson)
              .where((control) => control.isValid)
              .toList() ??
          const [],
      controlPanelModules: j.containsKey('controlPanelModules')
          ? (j['controlPanelModules'] as List<dynamic>?)
                  ?.whereType<Map<String, dynamic>>()
                  .map(ControlPanelModule.fromJson)
                  .where((module) => module.id.isNotEmpty)
                  .toList() ??
              const []
          : defaultControlPanelModules,
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

/// One camera as the plugin reports it in /status `webcams` (0.6.22+), in
/// Moonraker's order. On older plugins PrinterStatusService synthesises a
/// single entry from the legacy flat webcam_* fields, so downstream code has
/// one shape either way. The tile's camera switcher appears only when a
/// status carries more than one of these; [key] (uid, else name) is what
/// [PrinterConfig.selectedWebcam] persists.
class PrinterWebcam {
  final String  name;
  final String? uid;
  /// Pi-served relative snapshot path (`/webcam/?action=snapshot`); the
  /// service appends it to whichever base URL the poll is winning on.
  final String? snapshotPath;
  final bool    flipH;
  final bool    flipV;
  final int     rotation;  // 0 | 90 | 180 | 270
  final int     targetFps;
  /// Absolute URL of a camera living on ANOTHER LAN device (phone webcam,
  /// IP cam) - fetched directly on LAN, via /mg-extcam when remote.
  final String? streamExternal;
  final String? snapshotExternal;

  const PrinterWebcam({
    required this.name,
    this.uid,
    this.snapshotPath,
    this.flipH     = false,
    this.flipV     = false,
    this.rotation  = 0,
    this.targetFps = 15,
    this.streamExternal,
    this.snapshotExternal,
  });

  /// Stable identity for persistence + matching: Moonraker's uid when it has
  /// one, else the (user-visible, user-chosen) name.
  String get key => (uid != null && uid!.isNotEmpty) ? uid! : name;
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

  /// Klipper's `print_stats.print_duration` - seconds of actual printing on
  /// the current job (excludes heat-up/pause time). 0 when idle or unknown.
  /// Feeds the tile's time-remaining chip via [printRemainingSeconds], the
  /// same Mainsail-style estimate the notification card shows.
  final double printDurationSec;

  /// Klipper's `print_stats.filament_used` (mm) plus the printing file's
  /// `filament_total` / `estimated_time` from Moonraker metadata - the extra
  /// inputs [printRemainingSeconds] blends, Mainsail-style, so the time chip
  /// stops drifting an hour from Mainsail early in a print. Null when the
  /// metadata isn't known (yet); the estimate then falls back to elapsed ÷
  /// progress alone, exactly the pre-v0.9.56 behaviour.
  final double? filamentUsedMm;
  final double? filamentTotalMm;
  final double? slicerEstimateSec;

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

  /// Every camera this printer reports (plugin 0.6.22+ sends the full list;
  /// older plugins yield one synthesised entry). The webcam* fields above are
  /// always the SELECTED camera's, resolved by the service - the tile shows
  /// its switcher when this has more than one entry.
  final List<PrinterWebcam> webcams;

  /// Live light state from the configured [PrinterConfig.lightStatusObject]
  /// (v0.9.8): true = on, false = off, null = no status object configured or
  /// not yet known. Drives the lit/dark bulb on the tile.
  final bool? lightOn;

  /// True when Moonraker reports Klipper is shut down or errored
  /// (webhooks.state == "shutdown" / "error") - e.g. after an emergency stop.
  /// The tile swaps the E-STOP triangle for a firmware-restart button then.
  final bool klippyShutdown;

  /// The Moongate Pi-plugin version this printer reported on the poll
  /// (`plugin_version` in /status, present from plugin 0.6.4). Null = this
  /// poll didn't come through the plugin path, or a pre-0.6.4 plugin. Drives
  /// the tile's plugin-update badge via `pluginVersionIsOutdated`.
  final String? pluginVersion;

  /// True when the plugin advertises the remote self-update action
  /// (`plugin_can_self_update` in /status, plugin 0.6.16+). The update dialog
  /// then offers one-tap "Update now" instead of Mainsail instructions.
  final bool pluginCanSelfUpdate;

  /// True when this poll set the tile's custom camera override aside because
  /// its address kept hard-failing while the printer reports a camera of its
  /// own ([webcamSnapshotUrl] is then the printer's camera, not the
  /// override). The tile shows a tappable notice so the swap is never
  /// silent; the override itself is untouched and comes back the moment the
  /// user edits it (see resolveWebcamSource in PrinterStatusService).
  final bool customCameraDown;

  /// True when this poll set the printer's own reported camera aside because
  /// its address kept hard-failing - a webcam entry left pointing at a
  /// dismantled camera service - and [webcamSnapshotUrl] is the default
  /// snapshot path instead. Same tappable-notice contract as
  /// [customCameraDown]; the entry itself stays Mainsail's to fix, and
  /// fixing it re-arms the selection on the next poll (see
  /// resolveWebcamSource in PrinterStatusService).
  final bool configuredCameraDown;

  const PrinterStatus({
    required this.state,
    required this.progress,
    this.printDurationSec = 0,
    this.filamentUsedMm,
    this.filamentTotalMm,
    this.slicerEstimateSec,
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
    this.webcams = const [],
    this.lightOn,
    this.klippyShutdown = false,
    this.pluginVersion,
    this.pluginCanSelfUpdate = false,
    this.customCameraDown = false,
    this.configuredCameraDown = false,
  });

  bool get isPrinting => state == 'printing' || state == 'paused';
  bool get isIdle => state == 'standby';

  /// Returns a copy with selected fields replaced. Used by the live tutorial to
  /// briefly doctor a tile's state for the demo (force tunnel mode, inject a
  /// chamber reading) and then restore the real one.
  PrinterStatus copyWith({
    String? state,
    double? progress,
    double? printDurationSec,
    double? filamentUsedMm,
    double? filamentTotalMm,
    double? slicerEstimateSec,
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
    List<PrinterWebcam>? webcams,
    bool? lightOn,
    bool? klippyShutdown,
    String? pluginVersion,
    bool? pluginCanSelfUpdate,
    bool? customCameraDown,
    bool? configuredCameraDown,
  }) {
    return PrinterStatus(
      state:            state ?? this.state,
      progress:         progress ?? this.progress,
      printDurationSec: printDurationSec ?? this.printDurationSec,
      filamentUsedMm:   filamentUsedMm ?? this.filamentUsedMm,
      filamentTotalMm:  filamentTotalMm ?? this.filamentTotalMm,
      slicerEstimateSec: slicerEstimateSec ?? this.slicerEstimateSec,
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
      webcams:          webcams ?? this.webcams,
      lightOn:          lightOn ?? this.lightOn,
      klippyShutdown:   klippyShutdown ?? this.klippyShutdown,
      pluginVersion:    pluginVersion ?? this.pluginVersion,
      pluginCanSelfUpdate: pluginCanSelfUpdate ?? this.pluginCanSelfUpdate,
      customCameraDown: customCameraDown ?? this.customCameraDown,
      configuredCameraDown: configuredCameraDown ?? this.configuredCameraDown,
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
