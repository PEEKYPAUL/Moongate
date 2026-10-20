import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Vertices, VertexMode;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../services/gcode_layer_parser.dart';
import '../../services/print_control_service.dart';

/// Full-screen G-code layer viewer, opened from the View button on a row of
/// the Start-a-print sheet (features/dashboard/gcode_files_overlay.dart).
///
/// The file is downloaded over the connection the sheet's listing answered on
/// and parsed in a background isolate (services/gcode_layer_parser.dart) into
/// layers of extrusion segments, each tagged with the part-cooling fan and
/// hotend target in force. The picture is a 3D orbit drawn with no engine: a
/// [CustomPainter] sets one flat canvas transform per layer (the orbit matrix
/// times the lift to that layer's Z, orthographic) and draws the layer's
/// points with `drawRawPoints`; layers go bottom to top, which is exact
/// occlusion while the camera stays above the top layer, so the tilt is
/// clamped to 5..88 degrees. One finger orbits, pinch zooms around the pinch,
/// two fingers pan, double tap resets; the rail steps layers.
///
/// Each layer is ONE triangle mesh ([Vertices]): every extrusion segment is a
/// thin quad at its real width (0.42 mm, widened when zoomed far out so it
/// still covers a pixel), coloured per vertex from the heat map. One
/// `drawVertices` per layer, so a 180-layer, 300k-segment file is 180 GPU
/// draws a frame. NOT `drawRawPoints(lines)`: Impeller splits that into one
/// draw op per line pair, which froze and then killed the app on the first
/// S24 build.
///
/// Pops `true` when the user taps Start print, so the sheet selects the file
/// and runs its normal confirm dialog (soak / cool-down rows included).
class GcodeViewerScreen extends StatefulWidget {
  final PrinterConfig printer;
  final GcodeFile file;
  final String base;
  final bool isLan;

  const GcodeViewerScreen({
    super.key,
    required this.printer,
    required this.file,
    required this.base,
    required this.isLan,
  });

  /// Above this, a tunnel download asks first (LAN never asks).
  static const int askAboveBytes = 40 * 1024 * 1024;

  @override
  State<GcodeViewerScreen> createState() => _GcodeViewerScreenState();
}

enum _Phase { confirm, downloading, parsing, ready, error }

class _GcodeViewerScreenState extends State<GcodeViewerScreen> {
  static const _prefMode = 'gcodeViewer.mode'; // 'cool' | 'hot'
  static const _elMin = 5 * math.pi / 180;
  static const _elMax = 88 * math.pi / 180;
  static const _defAz = -35 * math.pi / 180;
  static const _defEl = 35 * math.pi / 180;
  static const _canvasBg = Color(0xFF141414); // slicer-dark in every theme
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
  /// One COARSE mesh per layer (decimated segments) for the stack below the
  /// current layer; the current layer gets a full-detail mesh on demand.
  List<Vertices>? _coarse;
  Vertices? _curMesh;
  int _curMeshIndex = -1;
  double _meshWidth = _lineWidthMm; // model-space width the meshes were built at
  int _cur = 0;
  bool _cooling = true;
  bool _only = false;
  double _lo = 0, _hi = 1;

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
      for (final v in m) {
        v.dispose();
      }
    }
    _curMesh?.dispose();
    _curMesh = null;
    _curMeshIndex = -1;
  }

  Future<void> _boot() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _cooling = prefs.getString(_prefMode) != 'hot');
    // Metadata first (cheap): layer count for the header, start byte for Range.
    _control
        .fetchGcodeMeta(widget.file, base: widget.base, isLan: widget.isLan)
        .then((m) {
      if (mounted && m != null) setState(() => _meta = m);
    });
    if (!widget.isLan && widget.file.size > GcodeViewerScreen.askAboveBytes) {
      setState(() => _phase = _Phase.confirm);
      return;
    }
    await _download();
  }

  Future<void> _download() async {
    // Wait briefly for the metadata so the Range header can skip the preamble;
    // without it the whole file comes down, which the parser copes with.
    var waited = 0;
    while (_meta == null && waited < 1500 && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      waited += 100;
    }
    if (!mounted) return;
    final cancel = Completer<void>();
    setState(() {
      _phase = _Phase.downloading;
      _received = 0;
      _total = -1;
      _cancel = cancel;
    });
    final bytes = await _control.downloadGcode(
      widget.file,
      base:      widget.base,
      isLan:     widget.isLan,
      startByte: _meta?.gcodeStartByte ?? 0,
      cancel:    cancel.future,
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
    setState(() => _phase = _Phase.parsing);
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
    setState(() {
      _model = model;
      _cur = model.layers.length - 1;
      _phase = _Phase.ready;
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

  // ── Colour ───────────────────────────────────────────────────────────────

  static const _coolStops = [
    Color(0xFF8A4B2F), Color(0xFFB08A3A), Color(0xFF4FA08A),
    Color(0xFF39B7D6), Color(0xFFC7F2FF),
  ];
  static const _hotStops = [
    Color(0xFF3B0F70), Color(0xFF8C2981), Color(0xFFDE4968),
    Color(0xFFFE9F6D), Color(0xFFFCFDBF),
  ];

  List<Color> get _stops => _cooling ? _coolStops : _hotStops;

  Color _colorAt(double t) {
    final stops = _stops;
    t = t.clamp(0.0, 1.0);
    final n = stops.length - 1;
    final i = math.min(n - 1, (t * n).floor());
    return Color.lerp(stops[i], stops[i + 1], t * n - i)!;
  }

  /// The model-space line width for the current zoom: the real extrusion
  /// width, widened when zoomed far out so a line still covers a pixel.
  double get _wantedWidth =>
      math.max(_lineWidthMm, _minLinePx / math.max(_scale, 1e-6));

  static const _bands = 16;
  Int32List _lut = Int32List(0);

  /// Build the coarse mesh of every layer for the current mode and width.
  /// Each segment becomes a quad (two triangles, six vertices) coloured from
  /// a 16-step lookup. The stack below the current layer is drawn from these
  /// decimated meshes (see [_decimate]); the current layer's full-detail mesh
  /// is built on demand in [_currentMesh]. Done once per mode switch or when
  /// the zoom has moved the wanted width by more than a third, never per
  /// frame.
  void _rebuildMeshes() {
    final m = _model!;
    if (_cooling) {
      _lo = 0;
      _hi = math.max(m.fanMax, 0.01);
    } else {
      _lo = m.tempMin;
      _hi = m.tempMax <= m.tempMin ? m.tempMin + 10 : m.tempMax;
    }
    _lut = Int32List.fromList([
      for (var q = 0; q < _bands; q++) _colorAt(q / (_bands - 1)).toARGB32()
    ]);
    final width = _wantedWidth;
    _disposeMeshes();
    _meshWidth = width;
    // Chord error of about half a device pixel at the current zoom (never
    // under 0.1 mm), chords up to 4 mm: the dimmed stack reads the same.
    // A file that still exceeds the segment budget after that gets a looser
    // tolerance, up to three times, so a huge print stays drawable.
    var tol = math.max(0.1, 0.5 / math.max(_scale, 1e-6));
    const budget = 600000;
    List<(Float32List, Float32List)> coarse;
    var pass = 0;
    do {
      coarse = [
        for (final layer in m.layers)
          decimateSegments(layer.points, _cooling ? layer.fan : layer.temp,
              lo: _lo, hi: _hi, bands: _bands, maxLen: 4.0, tol: tol),
      ];
      final total = coarse.fold(0, (n, s) => n + s.$2.length);
      if (total <= budget || ++pass > 3) break;
      tol *= 2;
    } while (true);
    _coarse = [for (final s in coarse) _meshFrom(s, _lo, _hi, _lut, width)];
  }

  /// Full-detail mesh of the current layer, rebuilt when the layer changes
  /// (one layer is a few thousand segments: well under a frame).
  Vertices _currentMesh() {
    if (_curMesh == null || _curMeshIndex != _cur) {
      _curMesh?.dispose();
      final layer = _model!.layers[_cur];
      _curMesh = _meshFrom(
          (layer.points, _cooling ? layer.fan : layer.temp),
          _lo, _hi, _lut, _meshWidth);
      _curMeshIndex = _cur;
    }
    return _curMesh!;
  }

  static Vertices _meshFrom((Float32List, Float32List) seg, double lo,
      double hi, Int32List lut, double width) {
    final p = seg.$1;
    final values = seg.$2;
    final n = values.length;
    final pos = Float32List(n * 12);
    final col = Int32List(n * 6);
    final hw = width / 2;
    final span = (hi - lo) == 0 ? 1.0 : (hi - lo);
    final top = lut.length - 1;
    var k = 0, c = 0;
    for (var i = 0; i < n; i++) {
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
      // Normal of half-width, plus a half-width cap at each end so adjacent
      // segments of a perimeter meet without a notch.
      final nx = -dy, ny = dx;
      final ax = x1 - dx, ay = y1 - dy, bx = x2 + dx, by = y2 + dy;
      pos[k] = ax + nx;      pos[k + 1] = ay + ny;
      pos[k + 2] = bx + nx;  pos[k + 3] = by + ny;
      pos[k + 4] = bx - nx;  pos[k + 5] = by - ny;
      pos[k + 6] = ax + nx;  pos[k + 7] = ay + ny;
      pos[k + 8] = bx - nx;  pos[k + 9] = by - ny;
      pos[k + 10] = ax - nx; pos[k + 11] = ay - ny;
      k += 12;
      var q = (((values[i] - lo) / span) * top).round();
      if (q < 0) q = 0;
      if (q > top) q = top;
      final color = lut[q];
      col[c] = color;
      col[c + 1] = color;
      col[c + 2] = color;
      col[c + 3] = color;
      col[c + 4] = color;
      col[c + 5] = color;
      c += 6;
    }
    return Vertices.raw(VertexMode.triangles, pos, colors: col);
  }

  /// After a zoom: rebuild when the wanted width drifted more than a third
  /// from what the meshes were built at (lines zoomed far out would vanish,
  /// lines zoomed in would look too fat).
  void _maybeRebuildForWidth() {
    if (_model == null) return;
    final r = _wantedWidth / _meshWidth;
    if (r > 1.34 || r < 0.75) setState(_rebuildMeshes);
  }

  Future<void> _setMode(bool cooling) async {
    if (_cooling == cooling) return;
    setState(() {
      _cooling = cooling;
      if (_model != null) _rebuildMeshes();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefMode, cooling ? 'cool' : 'hot');
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

  Widget _viewerBody(AppLocalizations l, ThemeData theme) {
    final m = _model!;
    final layer = m.layers[_cur];
    final top = _el > _elMax - 0.01;
    final tempUnset = !_cooling && m.tempMax <= 0;
    return Column(
      children: [
        // ── Mode ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.ac_unit, size: 18),
                    label: Text(l.gcodeViewerModeCooling)),
                ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.local_fire_department_outlined,
                        size: 18),
                    label: Text(l.gcodeViewerModeHotend)),
              ],
              selected: {_cooling},
              onSelectionChanged: (s) => _setMode(s.first),
              showSelectedIcon: false,
            ),
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
                                color: Color(0xFF9A9A9A), fontSize: 10.5)),
                      ],
                    ),
                  ),
                ),
                // Legend.
                Positioned(
                  left: 12,
                  bottom: 10,
                  child: _Glass(
                    child: SizedBox(
                      width: 150,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              (_cooling
                                      ? l.gcodeViewerLegendFan
                                      : l.gcodeViewerLegendTemp)
                                  .toUpperCase(),
                              style: const TextStyle(
                                  color: Color(0xFF9A9A9A),
                                  fontSize: 9.5,
                                  letterSpacing: 0.6)),
                          const SizedBox(height: 4),
                          Container(
                            height: 8,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: LinearGradient(colors: _stops),
                            ),
                          ),
                          const SizedBox(height: 3),
                          if (tempUnset)
                            Text(l.gcodeViewerTempUnset,
                                style: const TextStyle(
                                    color: Color(0xFFCFCFCF), fontSize: 10))
                          else
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_legendLabel(_lo),
                                    style: const TextStyle(
                                        color: Color(0xFFCFCFCF),
                                        fontSize: 10)),
                                Text(_legendLabel(_hi),
                                    style: const TextStyle(
                                        color: Color(0xFFCFCFCF),
                                        fontSize: 10)),
                              ],
                            ),
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

  String _legendLabel(double v) =>
      _cooling ? '${(v * 100).round()} %' : '${v.round()} °C';

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
  final List<Vertices> below; // coarse, one per layer
  final Vertices current; // full detail, the current layer
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

    // Vertex colours carry the heat map; the paint only dims the layers
    // below the current one (modulate: colour x white-at-alpha).
    final dim = Paint()..color = const Color(0x9EFFFFFF); // alpha 0.62
    final full = Paint()..color = const Color(0xFFFFFFFF);

    final from = only ? cur : 0;
    for (var i = from; i <= cur; i++) {
      final z = model.layers[i].z;
      m[12] = baseTx;
      m[13] = baseTy - scale * (z - zc) * ce;
      canvas.save();
      canvas.transform(m);
      if (i == cur) {
        canvas.drawVertices(current, BlendMode.modulate, full);
      } else {
        canvas.drawVertices(below[i], BlendMode.modulate, dim);
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
