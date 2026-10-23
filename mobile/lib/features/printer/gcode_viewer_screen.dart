import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Vertices, VertexMode;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../services/gcode_cache.dart';
import '../../services/gcode_layer_parser.dart';
import '../../services/print_control_service.dart';
import 'gcode_save.dart';

/// Full-screen G-code layer viewer, opened from the View button on a row of
/// the Start-a-print sheet (features/dashboard/gcode_files_overlay.dart).
///
/// The file is downloaded over the connection the sheet's listing answered on
/// and parsed in a background isolate (services/gcode_layer_parser.dart) into
/// layers of extrusion segments, each tagged with the fan, hotend target,
/// speed and flow in force, plus a time per layer. Five heat maps, coloured
/// the way Orca's preview colours them: the same 11-stop ramp (dark blue,
/// green, yellow, red) spread linearly from the file's minimum to its
/// maximum. A sixth view, Colour (v0.9.73), paints every line in the
/// filament it was printed with (the slicer's `filament_colour` list, or a
/// fallback palette) and turns the legend into a key, one swatch per tool.
///
/// Which view opens first is the ⋮ menu's "Opens with": Auto (Colour for a
/// multi-material file, else Fan speed), Last used, or a fixed view. Stored
/// under `gcodeViewer.openWith`; the last chip tapped stays under
/// `gcodeViewer.mode`.
///
/// The picture is a 3D orbit drawn with no engine: a [CustomPainter] sets one
/// flat canvas transform per layer (the orbit matrix times the lift to that
/// layer's Z, orthographic) and draws the layer's mesh; layers go bottom to
/// top, which is exact occlusion while the camera stays above the top layer,
/// so the tilt is clamped to 5..88 degrees. One finger orbits, pinch zooms
/// around the pinch, two fingers pan, double tap resets; the rail steps
/// layers.
///
/// Each layer is a triangle mesh ([Vertices]): every extrusion segment is a
/// bead of its real width (0.42 mm, widened when zoomed far out so it still
/// covers a pixel) shaded dark at the edges and full colour down the middle,
/// so the layer lines read on a wall the way they do in Orca. Solid colour,
/// no transparency. The stack below the current layer uses a decimated copy
/// ([decimateSegments]); the current layer is full detail. NOT
/// `drawRawPoints(lines)`: Impeller splits that into one draw op per line
/// pair, which froze and then killed the app on the first S24 build.
///
/// Pops `true` when the user taps Start print, so the sheet selects the file
/// and runs its normal confirm dialog (soak / cool-down rows included).
class GcodeViewerScreen extends StatefulWidget {
  final PrinterConfig printer;
  final GcodeFile file;
  final String base;
  final bool isLan;

  /// What the printer's filament unit reports loaded per tool (the plugin's
  /// `filaments`, 0.6.29+), for the Colour view's Sliced / Loaded switch.
  /// Empty = no switch.
  final List<LoadedFilament> loaded;

  const GcodeViewerScreen({
    super.key,
    required this.printer,
    required this.file,
    required this.base,
    required this.isLan,
    this.loaded = const [],
  });

  /// Above this, a tunnel download asks first (LAN never asks).
  static const int askAboveBytes = 40 * 1024 * 1024;

  @override
  State<GcodeViewerScreen> createState() => _GcodeViewerScreenState();
}

enum _Phase { confirm, downloading, parsing, ready, error }

/// The views, in the order the chips show them: five heat maps and Colour.
enum GcodeViewMode { temp, flow, time, speed, fan, colour }

/// "Opens with" choices that are not a fixed [GcodeViewMode].
const String kGcodeViewerOpenAuto = 'auto';
const String kGcodeViewerOpenLast = 'last';

/// The ⋮ menu's "Save to phone" row (not an "Opens with" choice).
const String _kSaveToPhone = 'save';

class _GcodeViewerScreenState extends State<GcodeViewerScreen> {
  static const _prefMode = 'gcodeViewer.mode'; // the last chip tapped
  static const _prefOpen = 'gcodeViewer.openWith'; // auto / last / a mode
  static const _elMin = 5 * math.pi / 180;
  static const _elMax = 88 * math.pi / 180;
  static const _defAz = -35 * math.pi / 180;
  static const _defEl = 35 * math.pi / 180;
  static const _canvasBg = Color(0xFF2B2B2F); // Orca-dark in every theme
  static const _lineWidthMm = 0.42; // a typical extrusion width
  static const _minLinePx = 1.4; // never thinner than this on screen

  late final PrintControlService _control;
  _Phase _phase = _Phase.downloading;
  bool _noLayers = false;
  String? _errorDetail; // shown small under the error, for field reports
  GcodeMeta? _meta;
  int _received = 0;
  int _total = -1;
  Completer<void>? _cancel;

  GcodeModel? _model;
  /// One COARSE mesh (in chunks) per layer for the stack below the current
  /// layer; the current layer gets a full-detail mesh on demand.
  List<List<Vertices>>? _coarse;
  List<Vertices>? _curMesh;
  int _curMeshIndex = -1;
  double _meshWidth = _lineWidthMm; // model-space width the meshes were built at
  int _cur = 0;
  /// What the viewer opens with: [kGcodeViewerOpenAuto], [kGcodeViewerOpenLast]
  /// or a [GcodeViewMode] name.
  String _openWith = kGcodeViewerOpenAuto;
  GcodeViewMode _mode = GcodeViewMode.fan;
  bool _only = false;
  double _lo = 0, _hi = 1;

  /// Colour view: paint with what the printer says is loaded (true) or with
  /// the slicer's colours (false, the default every time the viewer opens).
  bool _showLoaded = false;

  // Orbit.
  double _az = _defAz, _el = _defEl;
  double _scale = 1, _fit = 1;
  Offset _pan = Offset.zero;
  Size _size = Size.zero;
  double _lastGestureScale = 1;

  Timer? _repeat;

  @override
  void initState() {
    super.initState();
    _control = PrintControlService(widget.printer);
    _boot();
  }

  @override
  void dispose() {
    _repeat?.cancel();
    _cancel?.complete();
    _disposeMeshes();
    super.dispose();
  }

  void _disposeMeshes() {
    final m = _coarse;
    _coarse = null;
    if (m != null) {
      for (final layer in m) {
        for (final v in layer) {
          v.dispose();
        }
      }
    }
    _disposeCurMesh();
  }

  void _disposeCurMesh() {
    final c = _curMesh;
    _curMesh = null;
    _curMeshIndex = -1;
    if (c != null) {
      for (final v in c) {
        v.dispose();
      }
    }
  }

  Future<void> _boot() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final saved = prefs.getString(_prefMode);
    final open = prefs.getString(_prefOpen) ?? kGcodeViewerOpenAuto;
    final last = GcodeViewMode.values.firstWhere((m) => m.name == saved,
        orElse: () => GcodeViewMode.fan);
    setState(() {
      _openWith = open;
      // A fixed choice applies now; Auto needs the file (decided after the
      // parse) and Last used is the remembered chip.
      _mode = GcodeViewMode.values.firstWhere((m) => m.name == open,
          orElse: () => last);
    });
    // Metadata first (cheap): layer count for the header, start byte for Range.
    _control
        .fetchGcodeMeta(widget.file, base: widget.base, isLan: widget.isLan)
        .then((m) {
      if (mounted && m != null) setState(() => _meta = m);
    });
    // A cached copy needs no download, so no "over the internet?" question.
    if (!widget.isLan &&
        widget.file.size > GcodeViewerScreen.askAboveBytes &&
        !await GcodeCache.has(widget.printer.id, widget.file)) {
      if (mounted) setState(() => _phase = _Phase.confirm);
      return;
    }
    await _download();
  }

  /// The file's bytes: the in-memory model from last time, the on-disk cache,
  /// or a fresh download of the WHOLE file (no Range header since v0.9.76, so
  /// the cached copy is complete and Save to phone can reuse it; the
  /// thumbnail preamble it used to skip is a few hundred KB).
  Future<void> _download() async {
    final cacheKey = GcodeCache.key(widget.printer.id, widget.file);
    final remembered = GcodeCache.lastModel(cacheKey);
    if (remembered != null) {
      _install(remembered);
      return;
    }
    var bytes = await GcodeCache.read(widget.printer.id, widget.file);
    if (!mounted) return;
    final fromCache = bytes != null;
    if (bytes == null) {
      final cancel = Completer<void>();
      setState(() {
        _phase = _Phase.downloading;
        _received = 0;
        _total = -1;
        _cancel = cancel;
      });
      bytes = await _control.downloadGcode(
        widget.file,
        base:   widget.base,
        isLan:  widget.isLan,
        cancel: cancel.future,
        onProgress: (r, t) {
          if (!mounted) return;
          // Throttle the rebuilds to every ~64 KB.
          if (r - _received > 65536 || r == t) {
            setState(() {
              _received = r;
              _total = t;
            });
          }
        },
      );
      if (!mounted || cancel.isCompleted) return;
      _cancel = null;
      if (bytes == null) {
        setState(() {
          _errorDetail = 'download';
          _phase = _Phase.error;
        });
        return;
      }
    }
    setState(() => _phase = _Phase.parsing);
    if (!fromCache) {
      unawaited(GcodeCache.write(widget.printer.id, widget.file, bytes));
    }
    final GcodeModel model;
    try {
      model = await _parseOffThread(bytes);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorDetail = e.toString();
          _phase = _Phase.error;
        });
      }
      return;
    }
    if (!mounted) return;
    if (model.layers.isEmpty) {
      setState(() {
        _noLayers = true;
        _phase = _Phase.error;
      });
      return;
    }
    GcodeCache.rememberModel(cacheKey, model);
    _install(model);
  }

  /// Show a parsed [model].
  void _install(GcodeModel model) {
    if (!mounted) return;
    setState(() {
      _model = model;
      _cur = model.layers.length - 1;
      _phase = _Phase.ready;
      if (_openWith == kGcodeViewerOpenAuto) _mode = _autoMode(model);
      _resetView(); // sets the scale, which the mesh width depends on
      _rebuildMeshes();
    });
  }

  /// Parse in a background isolate. A STATIC helper on purpose: a closure
  /// written inside the State's async method shares that method's context,
  /// and the progress callback in the same scope references the State, so
  /// the whole State would be captured and `Isolate.run` would refuse to
  /// send it ("Illegal argument in isolate message"). The first on-device
  /// build hit exactly that, as "Couldn't load this file".
  static Future<GcodeModel> _parseOffThread(Uint8List bytes) =>
      Isolate.run(() => parseGcode(bytes));

  void _cancelDownload() {
    _cancel?.complete();
    _cancel = null;
    Navigator.of(context).maybePop();
  }

  // ── Colour (Orca's range ramp) ───────────────────────────────────────────

  /// libvgcode's DEFAULT_RANGES_COLORS, what Orca's preview uses for every
  /// range view (fan, temperature, speed, flow, layer time): 11 stops,
  /// interpolated linearly from the file's minimum to its maximum.
  static const _ramp = [
    Color(0xFF0B2C7A), // bluish
    Color(0xFF135985),
    Color(0xFF1C8891),
    Color(0xFF04D60F),
    Color(0xFFAAF200),
    Color(0xFFFCF903),
    Color(0xFFF5CE0A),
    Color(0xFFE38820),
    Color(0xFFD16830),
    Color(0xFFC2523C),
    Color(0xFF942616), // reddish
  ];

  static Color _colorAt(double t) {
    t = t.clamp(0.0, 1.0);
    final n = _ramp.length - 1;
    final i = math.min(n - 1, (t * n).floor());
    return Color.lerp(_ramp[i], _ramp[i + 1], t * n - i)!;
  }

  // ── Colour mode (the file's filament colours) ────────────────────────────

  /// Fallback colours for tools the slicer gave no colour for (Cura,
  /// Simplify3D): six distinct hues, wrapping past the sixth tool.
  static const _palette = [
    Color(0xFFE53935),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFFDD835),
    Color(0xFF8E24AA),
    Color(0xFFFB8C00),
  ];

  /// The slicer's colour of the tool at [slot] in [m]'s key, unless the file
  /// gave none or gave every tool the same one (then the palette, so the
  /// tools can still be told apart).
  static Color _slicedColor(GcodeModel m, int slot) {
    final argb = m.tools[slot].argb;
    return argb != null && !m.slicerColoursIdentical
        ? Color(argb)
        : _palette[slot % _palette.length];
  }

  /// Grey for a tool whose gate / lane is empty or has no colour in Loaded.
  static const _emptyColor = Color(0xFF555555);

  /// What the printer reports loaded for tool number [tool], if anything.
  LoadedFilament? _loadedFor(int tool) {
    for (final f in widget.loaded) {
      if (f.tool == tool) return f;
    }
    return null;
  }

  /// The Sliced / Loaded switch shows when the printer reports a filament
  /// for at least one of the file's tools.
  bool get _hasLoaded {
    final m = _model;
    return m != null && m.tools.any((t) => _loadedFor(t.index) != null);
  }

  /// The colour the tool at [slot] paints with in the current source.
  Color _toolColor(GcodeModel m, int slot) {
    if (!_showLoaded) return _slicedColor(m, slot);
    final f = _loadedFor(m.tools[slot].index);
    return f == null || !f.loaded || f.argb == null
        ? _emptyColor
        : Color(f.argb!);
  }

  /// True when the loaded colour is clearly not the sliced one (the key
  /// then shows a dot in the sliced colour). Euclidean RGB, so white vs.
  /// off-white does not count.
  static bool _differs(Color a, Color b) {
    final dr = (a.r - b.r) * 255, dg = (a.g - b.g) * 255, db = (a.b - b.b) * 255;
    return dr * dr + dg * dg + db * db > 60 * 60;
  }

  /// Auto: Colour for a multi-material file, else Fan speed.
  static GcodeViewMode _autoMode(GcodeModel m) =>
      m.isMultiTool ? GcodeViewMode.colour : GcodeViewMode.fan;

  /// The key slot of every segment in [layer], as the band value the mesh
  /// builder and the decimator work with (tool numbers are bytes, so a
  /// 256-entry lookup maps them to slots).
  Float32List _slotValues(GcodeLayer layer) {
    final m = _model!;
    final out = Float32List(layer.segmentCount);
    if (m.tools.length <= 1) return out;
    final slot = Int32List(256);
    for (var i = 0; i < m.tools.length; i++) {
      slot[m.tools[i].index] = i;
    }
    final tool = layer.tool;
    for (var i = 0; i < out.length; i++) {
      out[i] = slot[tool[i]].toDouble();
    }
    return out;
  }

  /// Per-segment values of the current mode for [layer] (layer time is one
  /// value per layer, spread over its segments; Colour is the key slot).
  Float32List _valuesFor(GcodeLayer layer) => switch (_mode) {
        GcodeViewMode.fan    => layer.fan,
        GcodeViewMode.temp   => layer.temp,
        GcodeViewMode.speed  => layer.speed,
        GcodeViewMode.flow   => layer.flow,
        GcodeViewMode.time   => Float32List(layer.segmentCount)
          ..fillRange(0, layer.segmentCount, layer.time),
        GcodeViewMode.colour => _slotValues(layer),
      };

  /// Range of the current mode across the file, as Orca spreads the ramp.
  /// A single-valued file maps everything to the first stop. Colour mode
  /// uses one band per tool, so a slot maps to its own colour exactly.
  void _setRange() {
    final m = _model!;
    _bands = _mode == GcodeViewMode.colour
        ? math.max(1, m.tools.length)
        : _rampBands;
    switch (_mode) {
      case GcodeViewMode.colour:
        _lo = 0;
        _hi = (m.tools.length - 1).toDouble();
      case GcodeViewMode.fan:
        _lo = m.fanMin;
        _hi = m.fanMax;
      case GcodeViewMode.temp:
        _lo = m.tempMin;
        _hi = m.tempMax;
      case GcodeViewMode.speed:
        _lo = m.speedMin;
        _hi = m.speedMax;
      case GcodeViewMode.flow:
        _lo = m.flowMin;
        _hi = m.flowMax;
      case GcodeViewMode.time:
        _lo = m.timeMin;
        _hi = m.timeMax;
    }
  }

  /// The model-space line width for the current zoom: the real extrusion
  /// width, widened when zoomed far out so a line still covers a pixel.
  double get _wantedWidth =>
      math.max(_lineWidthMm, _minLinePx / math.max(_scale, 1e-6));

  static const _rampBands = 48;
  int _bands = _rampBands; // ramp modes: 48 steps; Colour: one per tool
  Int32List _lutMid = Int32List(0);
  Int32List _lutEdge = Int32List(0);

  /// Build the coarse meshes of every layer for the current mode and width.
  /// Done once per mode switch or when the zoom has moved the wanted width
  /// by more than a third, never per frame.
  void _rebuildMeshes() {
    final m = _model!;
    _setRange();
    _lutMid = Int32List(_bands);
    _lutEdge = Int32List(_bands);
    for (var q = 0; q < _bands; q++) {
      final c = _mode == GcodeViewMode.colour
          ? _toolColor(m, q)
          : _colorAt(q / (_bands - 1));
      _lutMid[q] = c.toARGB32();
      // Edges at 58 %: the bead reads as a round line and the layer lines
      // show on a wall, like Orca's lit tubes.
      _lutEdge[q] = Color.fromARGB(255, (c.r * 255 * 0.58).round(),
              (c.g * 255 * 0.58).round(), (c.b * 255 * 0.58).round())
          .toARGB32();
    }
    final width = _wantedWidth;
    _disposeMeshes();
    _meshWidth = width;
    // Chord error of about half a device pixel at the current zoom (never
    // under 0.1 mm), chords up to 4 mm: the stack reads the same. A file
    // that still exceeds the segment budget after that gets a looser
    // tolerance, up to three times, so a huge print stays drawable.
    var tol = math.max(0.1, 0.5 / math.max(_scale, 1e-6));
    const budget = 600000;
    List<(Float32List, Float32List)> coarse;
    var pass = 0;
    do {
      coarse = [
        for (final layer in m.layers)
          decimateSegments(layer.points, _valuesFor(layer),
              lo: _lo, hi: _hi, bands: _bands, maxLen: 4.0, tol: tol),
      ];
      final total = coarse.fold(0, (n, s) => n + s.$2.length);
      if (total <= budget || ++pass > 3) break;
      tol *= 2;
    } while (true);
    _coarse = [for (final s in coarse) _meshFrom(s, width)];
  }

  /// Full-detail mesh of the current layer, rebuilt when the layer changes
  /// (one layer is a few thousand segments: well under a frame).
  List<Vertices> _currentMesh() {
    if (_curMesh == null || _curMeshIndex != _cur) {
      _disposeCurMesh();
      final layer = _model!.layers[_cur];
      _curMesh = _meshFrom((layer.points, _valuesFor(layer)), _meshWidth);
      _curMeshIndex = _cur;
    }
    return _curMesh!;
  }

  /// Segments -> shaded bead meshes. Six vertices per segment (outer, middle
  /// and inner edge at each end, the ends capped by half a width), four
  /// triangles through an index list, edge colour dark and middle colour
  /// full. Chunked under 65 535 vertices because the index list is 16-bit.
  List<Vertices> _meshFrom((Float32List, Float32List) seg, double width) {
    final p = seg.$1;
    final values = seg.$2;
    final n = values.length;
    const perChunk = 10000; // 60 000 vertices
    final hw = width / 2;
    final span = (_hi - _lo) == 0 ? 1.0 : (_hi - _lo);
    final top = _bands - 1;
    final out = <Vertices>[];
    for (var start = 0; start < n; start += perChunk) {
      final count = math.min(perChunk, n - start);
      final pos = Float32List(count * 12);
      final col = Int32List(count * 6);
      final idx = Uint16List(count * 12);
      var k = 0, c = 0, j = 0;
      for (var s = 0; s < count; s++) {
        final i = start + s;
        final x1 = p[i * 4], y1 = p[i * 4 + 1], x2 = p[i * 4 + 2], y2 = p[i * 4 + 3];
        var dx = x2 - x1, dy = y2 - y1;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len < 1e-6) {
          dx = hw;
          dy = 0;
        } else {
          dx = dx / len * hw;
          dy = dy / len * hw;
        }
        final nx = -dy, ny = dx;
        final ax = x1 - dx, ay = y1 - dy, bx = x2 + dx, by = y2 + dy;
        // 0 a-outer, 1 a-mid, 2 a-inner, 3 b-outer, 4 b-mid, 5 b-inner
        pos[k] = ax + nx;      pos[k + 1] = ay + ny;
        pos[k + 2] = ax;       pos[k + 3] = ay;
        pos[k + 4] = ax - nx;  pos[k + 5] = ay - ny;
        pos[k + 6] = bx + nx;  pos[k + 7] = by + ny;
        pos[k + 8] = bx;       pos[k + 9] = by;
        pos[k + 10] = bx - nx; pos[k + 11] = by - ny;
        k += 12;
        var q = (((values[i] - _lo) / span) * top).round();
        if (q < 0) q = 0;
        if (q > top) q = top;
        final mid = _lutMid[q], edge = _lutEdge[q];
        col[c] = edge;
        col[c + 1] = mid;
        col[c + 2] = edge;
        col[c + 3] = edge;
        col[c + 4] = mid;
        col[c + 5] = edge;
        final v0 = s * 6;
        idx[j] = v0;         idx[j + 1] = v0 + 3; idx[j + 2] = v0 + 4;
        idx[j + 3] = v0;     idx[j + 4] = v0 + 4; idx[j + 5] = v0 + 1;
        idx[j + 6] = v0 + 1; idx[j + 7] = v0 + 4; idx[j + 8] = v0 + 5;
        idx[j + 9] = v0 + 1; idx[j + 10] = v0 + 5; idx[j + 11] = v0 + 2;
        c += 6;
        j += 12;
      }
      out.add(Vertices.raw(VertexMode.triangles, pos, colors: col, indices: idx));
    }
    return out;
  }

  /// After a zoom: rebuild when the wanted width drifted more than a third
  /// from what the meshes were built at (lines zoomed far out would vanish,
  /// lines zoomed in would look too fat).
  void _maybeRebuildForWidth() {
    if (_model == null) return;
    final r = _wantedWidth / _meshWidth;
    if (r > 1.34 || r < 0.75) setState(_rebuildMeshes);
  }

  Future<void> _setMode(GcodeViewMode mode) async {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      if (_model != null) _rebuildMeshes();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefMode, mode.name);
  }

  /// The ⋮ menu's pick: remember it, and show its effect right away (Auto
  /// and a fixed view switch the picture; Last used keeps what is up).
  Future<void> _setOpenWith(String value) async {
    setState(() => _openWith = value);
    final m = _model;
    if (m != null) {
      if (value == kGcodeViewerOpenAuto) {
        await _setMode(_autoMode(m));
      } else if (value != kGcodeViewerOpenLast) {
        await _setMode(GcodeViewMode.values
            .firstWhere((x) => x.name == value, orElse: () => _mode));
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefOpen, value);
  }

  // ── View ─────────────────────────────────────────────────────────────────

  void _resetView() {
    final m = _model;
    if (m == null || _size == Size.zero) return;
    _az = _defAz;
    _el = _defEl;
    // Fit the part's projected footprint at the default tilt: the XY
    // diagonal (any azimuth) foreshortened by sin(el), plus the height by
    // cos(el). 12 % margin each way; the legend and rail sit over the edges.
    final diag = math.sqrt(m.width * m.width + m.depth * m.depth);
    final pw = math.max(diag, 1.0);
    final ph = math.max(diag * math.sin(_el) + m.height * math.cos(_el), 1.0);
    _fit = math.min((_size.width - 64) / (pw * 1.12), (_size.height - 48) / (ph * 1.12));
    _scale = _fit;
    _pan = Offset.zero;
  }

  void _zoomAt(Offset focal, double f) {
    final ns = (_scale * f).clamp(_fit * 0.4, _fit * 14);
    f = ns / _scale;
    final c = Offset(_size.width / 2, _size.height / 2);
    // Keep the point under the fingers fixed: pan' = focal - c - (focal - c - pan) * f
    _pan = (focal - c) - ((focal - c) - _pan) * f;
    _scale = ns;
  }

  void _onScaleStart(ScaleStartDetails d) => _lastGestureScale = 1;

  void _onScaleEnd(ScaleEndDetails d) => _maybeRebuildForWidth();

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      if (d.pointerCount <= 1) {
        _az += d.focalPointDelta.dx * 0.01;
        _el = (_el + d.focalPointDelta.dy * 0.01).clamp(_elMin, _elMax);
      } else {
        final f = d.scale / _lastGestureScale;
        _lastGestureScale = d.scale;
        _zoomAt(d.localFocalPoint, f);
        _pan += d.focalPointDelta;
      }
    });
  }

  void _toggleTop() => setState(() {
        final top = _el > _elMax - 0.01;
        if (top) {
          _el = _defEl;
          _az = _defAz;
        } else {
          _el = _elMax;
          _az = 0;
        }
      });

  void _step(int delta) {
    final n = _model?.layers.length ?? 0;
    if (n == 0) return;
    final next = (_cur + delta).clamp(0, n - 1);
    if (next != _cur) setState(() => _cur = next);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final m = _model;
    final layers = m?.layers.length ?? _meta?.layerCount;
    final sub = <String>[
      widget.printer.name,
      if (widget.file.size > 0) _formatSize(widget.file.size),
      if (layers != null) l.gcodeViewerLayers(layers),
      if (_meta?.layerHeight != null)
        '${_trim(_meta!.layerHeight!)} mm',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
        actions: [
          // "Opens with": Auto / Last used / a fixed view, as a radio list,
          // then "Save to phone" (a fresh download of the WHOLE file: the
          // bytes the viewer holds skip the thumbnail preamble).
          PopupMenuButton<String>(
            tooltip: l.gcodeViewerOpensWith,
            onSelected: (v) => v == _kSaveToPhone
                ? saveGcodeToPhone(context, _control, widget.file,
                    base: widget.base, isLan: widget.isLan)
                : _setOpenWith(v),
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: _kSaveToPhone,
                child: Row(
                  children: [
                    Icon(Icons.download_outlined,
                        size: 20, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Text(l.gcodeSaveToPhone),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                enabled: false,
                height: 36,
                child: Text(l.gcodeViewerOpensWith,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ),
              _openItem(theme, kGcodeViewerOpenAuto, l.gcodeViewerOpenAuto,
                  hint: l.gcodeViewerOpenAutoHint),
              _openItem(theme, kGcodeViewerOpenLast, l.gcodeViewerOpenLast),
              const PopupMenuDivider(),
              for (final mode in GcodeViewMode.values)
                _openItem(theme, mode.name, _modeName(l, mode)),
            ],
          ),
        ],
      ),
      body: switch (_phase) {
        _Phase.confirm     => _confirmBody(l, theme),
        _Phase.downloading => _progressBody(l, theme, downloading: true),
        _Phase.parsing     => _progressBody(l, theme, downloading: false),
        _Phase.error       => _errorBody(l, theme),
        _Phase.ready       => _viewerBody(l, theme),
      },
    );
  }

  Widget _confirmBody(AppLocalizations l, ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_download_outlined,
                  size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(l.gcodeViewerLargeFile(_formatSize(widget.file.size)),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(l.commonCancel)),
                  const SizedBox(width: 12),
                  FilledButton(
                      onPressed: _download, child: Text(l.gcodeViewerDownload)),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _progressBody(AppLocalizations l, ThemeData theme,
      {required bool downloading}) {
    final value = downloading && _total > 0 ? _received / _total : null;
    final detail = downloading && _received > 0
        ? (_total > 0
            ? '${_formatSize(_received)} / ${_formatSize(_total)}'
            : _formatSize(_received))
        : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 220,
              child: LinearProgressIndicator(value: value, minHeight: 6),
            ),
            const SizedBox(height: 16),
            Text(downloading ? l.gcodeViewerDownloading : l.gcodeViewerParsing,
                style: theme.textTheme.bodyMedium),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(detail,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
            if (downloading) ...[
              const SizedBox(height: 16),
              TextButton(
                  onPressed: _cancelDownload, child: Text(l.commonCancel)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorBody(AppLocalizations l, ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_noLayers ? Icons.layers_clear_outlined : Icons.cloud_off_outlined,
                  size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(_noLayers ? l.gcodeViewerNoLayers : l.gcodeViewerError,
                  textAlign: TextAlign.center),
              if (!_noLayers && _errorDetail != null) ...[
                const SizedBox(height: 6),
                Text(_errorDetail!,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
              if (!_noLayers) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(
                    onPressed: _download, child: Text(l.commonRetry)),
              ],
            ],
          ),
        ),
      );

  String _modeName(AppLocalizations l, GcodeViewMode m) => switch (m) {
        GcodeViewMode.temp   => l.gcodeViewerModeTemp,
        GcodeViewMode.flow   => l.gcodeViewerModeFlow,
        GcodeViewMode.time   => l.gcodeViewerModeTime,
        GcodeViewMode.speed  => l.gcodeViewerModeSpeed,
        GcodeViewMode.fan    => l.gcodeViewerModeFan,
        GcodeViewMode.colour => l.gcodeViewerModeColour,
      };

  /// One row of the ⋮ menu: a radio dot, the label, an optional hint.
  PopupMenuItem<String> _openItem(ThemeData theme, String value, String label,
          {String? hint}) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(
                _openWith == value
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 20,
                color: _openWith == value
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline),
            const SizedBox(width: 12),
            Expanded(
              child: hint == null
                  ? Text(label)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label),
                        Text(hint,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ),
            ),
          ],
        ),
      );

  /// The Colour mode's key: one swatch per tool, in tool order, with the
  /// filament type when the file named it. In Loaded (v0.9.76) the swatch is
  /// what the printer reports in that tool's gate / lane, hatched when
  /// empty, with a dot in the sliced colour where the two clearly differ.
  List<Widget> _keyRows(AppLocalizations l, GcodeModel m) => [
        for (var i = 0; i < m.tools.length; i++) _keyRow(l, m, i),
        if (_showLoaded)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(l.gcodeViewerKeyLoadedNote,
                style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 10)),
          )
        else if (!m.hasSlicerColours || m.slicerColoursIdentical)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
                m.hasSlicerColours
                    ? l.gcodeViewerKeySameColours
                    : l.gcodeViewerKeyNoColours,
                style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 10)),
          ),
      ];

  Widget _keyRow(AppLocalizations l, GcodeModel m, int i) {
    final tool = m.tools[i];
    final f = _showLoaded ? _loadedFor(tool.index) : null;
    final empty = _showLoaded && (f == null || !f.loaded || f.argb == null);
    final colour = _toolColor(m, i);
    // "· PLA" from the file, or in Loaded "· PETG · gate 2" from the printer.
    final detail = _showLoaded
        ? [
            if (!empty && f?.material != null) f!.material!,
            if (f?.slot != null) f!.slot!,
            if (empty) l.gcodeViewerKeyEmpty,
          ].join(' · ')
        : (tool.type ?? '');
    final sliced = _slicedColor(m, i);
    final dot = _showLoaded && !empty && _differs(colour, sliced);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: empty ? const Color(0xFF3A3A3A) : colour,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: const Color(0x26FFFFFF)),
            ),
            child: empty
                ? const CustomPaint(painter: _HatchPainter())
                : null,
          ),
          const SizedBox(width: 7),
          Text('T${tool.index}',
              style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 10.5)),
          if (detail.isNotEmpty)
            Flexible(
              child: Text(' · $detail',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFF9A9A9A), fontSize: 10.5)),
            ),
          if (dot) ...[
            const Spacer(),
            Tooltip(
              message: l.gcodeViewerKeySliced,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: sliced,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x4DFFFFFF)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The key's header: the view name, plus the Sliced / Loaded switch when
  /// the printer reports loaded filaments for this file's tools.
  Widget _keyHeader(AppLocalizations l) {
    final label = Text(_modeName(l, _mode).toUpperCase(),
        style: const TextStyle(
            color: Color(0xFFB0B0B0), fontSize: 9.5, letterSpacing: 0.6));
    if (_mode != GcodeViewMode.colour || !_hasLoaded) return label;
    Widget seg(String text, bool loaded) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_showLoaded == loaded) return;
            setState(() {
              _showLoaded = loaded;
              _rebuildMeshes();
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            color: _showLoaded == loaded
                ? const Color(0xFF3D2A27)
                : Colors.transparent,
            child: Text(text,
                style: TextStyle(
                    color: _showLoaded == loaded
                        ? const Color(0xFFFFD1C6)
                        : const Color(0xFFBDBDBD),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500)),
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        label,
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF4A4A4A)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                seg(l.gcodeViewerKeySliced, false),
                seg(l.gcodeViewerKeyLoaded, true),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _viewerBody(AppLocalizations l, ThemeData theme) {
    final m = _model!;
    final layer = m.layers[_cur];
    final top = _el > _elMax - 0.01;
    // The file never set this value (not a thing in Colour mode).
    final unset = _mode != GcodeViewMode.colour && _hi <= 0;
    return Column(
      children: [
        // ── Mode chips ─────────────────────────────────────────────────────
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final mode in GcodeViewMode.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(_modeName(l, mode)),
                    selected: _mode == mode,
                    onSelected: (_) => _setMode(mode),
                    showCheckmark: false,
                  ),
                ),
            ],
          ),
        ),
        // ── Picture ───────────────────────────────────────────────────────
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final size = Size(c.maxWidth, c.maxHeight);
            if (size != _size) {
              final first = _size == Size.zero;
              _size = size;
              if (first) {
                _resetView();
                // The meshes were built before the first layout knew the
                // size; rebuild if the fit moved the wanted width (deferred:
                // we are inside build).
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _maybeRebuildForWidth());
              }
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  onDoubleTap: () => setState(() {
                    _resetView();
                    _maybeRebuildForWidth();
                  }),
                  child: CustomPaint(
                    painter: _LayerPainter(
                      model:   m,
                      below:   _coarse!,
                      current: _currentMesh(),
                      cur:     _cur,
                      only:    _only,
                      az:      _az,
                      el:      _el,
                      scale:   _scale,
                      pan:     _pan,
                      bg:      _canvasBg,
                    ),
                  ),
                ),
                // Layer / Z / tilt chip.
                Positioned(
                  left: 12,
                  top: 10,
                  child: _Glass(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.gcodeViewerLayer(_cur + 1, m.layers.length),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        Text(
                            'Z ${layer.z.toStringAsFixed(2)} mm · '
                            '${(_el * 180 / math.pi).round()}°',
                            style: const TextStyle(
                                color: Color(0xFFB0B0B0), fontSize: 10.5)),
                      ],
                    ),
                  ),
                ),
                // Legend: Orca's ramp from the file's minimum to its maximum.
                Positioned(
                  left: 12,
                  bottom: 10,
                  child: _Glass(
                    child: SizedBox(
                      width: _mode == GcodeViewMode.colour && _hasLoaded
                          ? 200
                          : 160,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _keyHeader(l),
                          if (_mode == GcodeViewMode.colour)
                            ..._keyRows(l, m)
                          else ...[
                            const SizedBox(height: 4),
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                gradient: const LinearGradient(colors: _ramp),
                              ),
                            ),
                            const SizedBox(height: 3),
                            if (unset)
                              Text(l.gcodeViewerTempUnset,
                                  style: const TextStyle(
                                      color: Color(0xFFE0E0E0), fontSize: 10))
                            else
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_legendLabel(_lo),
                                      style: const TextStyle(
                                          color: Color(0xFFE0E0E0),
                                          fontSize: 10)),
                                  Text(_legendLabel(_hi),
                                      style: const TextStyle(
                                          color: Color(0xFFE0E0E0),
                                          fontSize: 10)),
                                ],
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                // Layer rail.
                Positioned(
                  right: 4,
                  top: 6,
                  bottom: 6,
                  child: Column(
                    children: [
                      _repeatButton(Icons.keyboard_arrow_up,
                          l.gcodeViewerLayerUp, 1),
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 11),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 20),
                            ),
                            child: Slider(
                              value: _cur.toDouble(),
                              min: 0,
                              max: (m.layers.length - 1).toDouble(),
                              divisions: math.max(1, m.layers.length - 1),
                              onChanged: (v) =>
                                  setState(() => _cur = v.round()),
                            ),
                          ),
                        ),
                      ),
                      _repeatButton(Icons.keyboard_arrow_down,
                          l.gcodeViewerLayerDown, -1),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
        // ── Bottom bar ────────────────────────────────────────────────────
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                IconButton.outlined(
                  isSelected: _only,
                  tooltip: l.gcodeViewerOnlyLayer,
                  icon: const Icon(Icons.layers_outlined),
                  selectedIcon: const Icon(Icons.layers),
                  onPressed: () => setState(() => _only = !_only),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  isSelected: top,
                  tooltip: l.gcodeViewerTopDown,
                  icon: const Icon(Icons.crop_square_outlined),
                  selectedIcon: const Icon(Icons.crop_square),
                  onPressed: _toggleTop,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(l.gcodeStartButton),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _repeatButton(IconData icon, String tip, int delta) =>
      GestureDetector(
        onLongPressStart: (_) {
          _repeat?.cancel();
          _repeat = Timer.periodic(
              const Duration(milliseconds: 50), (_) => _step(delta));
        },
        onLongPressEnd: (_) => _repeat?.cancel(),
        onLongPressCancel: () => _repeat?.cancel(),
        child: IconButton.filledTonal(
          icon: Icon(icon),
          tooltip: tip,
          onPressed: () => _step(delta),
        ),
      );

  String _legendLabel(double v) => switch (_mode) {
        GcodeViewMode.fan    => '${(v * 100).round()} %',
        GcodeViewMode.temp   => '${v.round()} °C',
        GcodeViewMode.speed  => '${v.round()} mm/s',
        GcodeViewMode.flow   => '${v.toStringAsFixed(1)} mm³/s',
        GcodeViewMode.time   => _fmtTime(v),
        GcodeViewMode.colour => '', // the key has no range
      };

  static String _fmtTime(double s) {
    if (s < 60) return '${s.round()} s';
    final total = s.round();
    if (total < 3600) {
      return '${total ~/ 60}m ${(total % 60).toString().padLeft(2, '0')}s';
    }
    return '${total ~/ 3600}h ${((total % 3600) ~/ 60).toString().padLeft(2, '0')}m';
  }

  static String _trim(double v) {
    final s = v.toStringAsFixed(2);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var s = bytes.toDouble();
    var u = 0;
    while (s >= 1024 && u < units.length - 1) {
      s /= 1024;
      u++;
    }
    final decimals = (u == 0 || s >= 100) ? 0 : 1;
    return '${s.toStringAsFixed(decimals)} ${units[u]}';
  }
}

/// Translucent dark card for the overlays on the picture (always dark, like
/// the canvas, whatever the app theme).
/// Diagonal hatching for the key's "empty gate" swatch.
class _HatchPainter extends CustomPainter {
  const _HatchPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF777777)
      ..strokeWidth = 1.2;
    for (var d = -size.height; d < size.width; d += 4) {
      canvas.drawLine(Offset(d, size.height), Offset(d + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) => false;
}

class _Glass extends StatelessWidget {
  final Widget child;
  const _Glass({required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xD91C1C1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 5, 9, 5),
          child: child,
        ),
      );
}

class _LayerPainter extends CustomPainter {
  final GcodeModel model;
  final List<List<Vertices>> below; // coarse, one list of chunks per layer
  final List<Vertices> current; // full detail, the current layer
  final int cur;
  final bool only;
  final double az, el, scale;
  final Offset pan;
  final Color bg;

  _LayerPainter({
    required this.model,
    required this.below,
    required this.current,
    required this.cur,
    required this.only,
    required this.az,
    required this.el,
    required this.scale,
    required this.pan,
    required this.bg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final ca = math.cos(az), sa = math.sin(az);
    final se = math.sin(el), ce = math.cos(el);
    final cx = model.centerX, cy = model.centerY, zc = model.height / 2;
    final tx = size.width / 2 + pan.dx, ty = size.height / 2 + pan.dy;
    // Orthographic orbit as a 2D affine per layer:
    //   sx = (x-cx) cos(az) - (y-cy) sin(az)
    //   sy = -((x-cx) sin(az) + (y-cy) cos(az)) sin(el) - (z-zc) cos(el)
    final a = scale * ca, b = -scale * sa * se;
    final c = -scale * sa, d = -scale * ca * se;
    final m = Float64List(16);
    m[0] = a;
    m[1] = b;
    m[4] = c;
    m[5] = d;
    m[10] = 1;
    m[15] = 1;
    final baseTx = tx - (a * cx + c * cy);
    final baseTy = ty - (b * cx + d * cy);

    // Vertex colours carry everything; the paint is opaque white and
    // modulate leaves them exactly as built. Solid, no transparency.
    final paint = Paint()..color = const Color(0xFFFFFFFF);

    final from = only ? cur : 0;
    for (var i = from; i <= cur; i++) {
      final z = model.layers[i].z;
      m[12] = baseTx;
      m[13] = baseTy - scale * (z - zc) * ce;
      canvas.save();
      canvas.transform(m);
      final chunks = i == cur ? current : below[i];
      for (final v in chunks) {
        canvas.drawVertices(v, BlendMode.modulate, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LayerPainter o) =>
      o.model != model ||
      o.below != below ||
      o.current != current ||
      o.cur != cur ||
      o.only != only ||
      o.az != az ||
      o.el != el ||
      o.scale != scale ||
      o.pan != pan;
}
