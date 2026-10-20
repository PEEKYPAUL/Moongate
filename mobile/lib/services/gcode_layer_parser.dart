import 'dart:math' as math;
import 'dart:typed_data';

/// Turns a sliced G-code file into layers of extrusion segments, each segment
/// tagged with the part-cooling fan and hotend target in force when the slicer
/// wrote it. Feeds the layer viewer's heat map (features/printer/
/// gcode_viewer_screen.dart).
///
/// Pure Dart over the raw bytes (no String decode of a 12 MB file, no
/// per-line allocation on the hot path), so it runs inside `Isolate.run`.
/// Only moves that push filament are kept: travels, retractions and wipes are
/// dropped, as are start/end markers and the nozzle position - by design.
///
/// Layer boundaries: `;LAYER_CHANGE` (Orca, Bambu, PrusaSlicer, SuperSlicer),
/// `;LAYER:` (Cura, ideaMaker) and `; layer N,` (Simplify3D) when present;
/// otherwise a new Z while extruding starts a layer (z-hop travels don't).
///
/// Fan: `M106 S0-255` without a `P` (or `P0`) and `M107` - the part fan only;
/// Orca's aux / exhaust fans (`M106 P2`, `P3`) are ignored. The value is the
/// commanded one, so Klipper's `max_power` scaling is not visible here.
///
/// Hotend: `M104` / `M109 S`, `SET_HEATER_TEMPERATURE HEATER=extruder* TARGET=`
/// and the temperature argument on `PRINT_START` / `START_PRINT`, because most
/// Klipper files set the first temperature inside that macro.
class GcodeLayer {
  /// Height of this layer in mm (the Z of its first extrusion).
  final double z;

  /// Segment end points, four floats per segment: x1, y1, x2, y2 (mm).
  final Float32List points;

  /// Part-cooling fan per segment, 0..1.
  final Float32List fan;

  /// Hotend target per segment, degrees C (0 when the file never set one).
  final Float32List temp;

  const GcodeLayer(
      {required this.z,
      required this.points,
      required this.fan,
      required this.temp});

  int get segmentCount => fan.length;
}

class GcodeModel {
  final List<GcodeLayer> layers;
  final double minX, minY, maxX, maxY;
  final double fanMin, fanMax, tempMin, tempMax;

  /// True when the file carried slicer layer markers (else the Z heuristic
  /// built the layers).
  final bool markers;

  const GcodeModel({
    required this.layers,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.fanMin,
    required this.fanMax,
    required this.tempMin,
    required this.tempMax,
    required this.markers,
  });

  int get segmentCount =>
      layers.fold(0, (n, l) => n + l.segmentCount);
  double get width => maxX - minX;
  double get depth => maxY - minY;
  double get height => layers.isEmpty ? 0 : layers.last.z;
  double get centerX => (minX + maxX) / 2;
  double get centerY => (minY + maxY) / 2;
}

/// Level of detail for the viewer's layer stack: merge chains of consecutive
/// segments that continue each other (end meets start) and fall in the same
/// colour band (of [bands] between [lo] and [hi]) into one chord, as long as
/// every point the chord skips stays within [tol] mm of it and the chord is
/// no longer than [maxLen] mm. With [tol] around half a screen pixel the
/// dimmed stack looks the same while curved perimeters, arcs and textured
/// walls, where a slicer writes thousands of sub-millimetre segments,
/// collapse several-fold; straight infill is left alone. Returns the merged
/// (points, values) in the same layout as [GcodeLayer.points] /
/// [GcodeLayer.fan].
(Float32List, Float32List) decimateSegments(Float32List p, Float32List v,
    {required double lo,
    required double hi,
    required int bands,
    required double maxLen,
    required double tol}) {
  final n = v.length;
  final outP = Float32List(n * 4);
  final outV = Float32List(n);
  final span = (hi - lo) == 0 ? 1.0 : (hi - lo);
  final top = bands - 1;
  final tol2 = tol * tol;
  final maxLen2 = maxLen * maxLen;
  int band(double x) {
    final q = (((x - lo) / span) * top).round();
    return q < 0 ? 0 : (q > top ? top : q);
  }

  var k = 0;
  var i = 0;
  while (i < n) {
    final sx = p[i * 4], sy = p[i * 4 + 1];
    var ex = p[i * 4 + 2], ey = p[i * 4 + 3];
    final q = band(v[i]);
    var j = i + 1;
    while (j < n) {
      if ((p[j * 4] - ex).abs() > 1e-3 || (p[j * 4 + 1] - ey).abs() > 1e-3) {
        break; // not a continuation
      }
      if (band(v[j]) != q) break;
      final nex = p[j * 4 + 2], ney = p[j * 4 + 3];
      final cx = nex - sx, cy = ney - sy;
      final c2 = cx * cx + cy * cy;
      if (c2 > maxLen2) break;
      // Every skipped vertex (the ends of segments i..j-1) must lie within
      // tol of the new chord s -> ne.
      var ok = true;
      if (c2 > 1e-12) {
        for (var t = i; t < j; t++) {
          final px = p[t * 4 + 2] - sx, py = p[t * 4 + 3] - sy;
          final cross = px * cy - py * cx;
          if (cross * cross > tol2 * c2) {
            ok = false;
            break;
          }
        }
      }
      if (!ok) break;
      ex = nex;
      ey = ney;
      j++;
    }
    outP[k * 4] = sx;
    outP[k * 4 + 1] = sy;
    outP[k * 4 + 2] = ex;
    outP[k * 4 + 3] = ey;
    outV[k] = v[i];
    k++;
    i = j;
  }
  return (
    Float32List.sublistView(outP, 0, k * 4),
    Float32List.sublistView(outV, 0, k),
  );
}

/// Growable Float32 buffer (the per-layer segment store while parsing).
class _F32Buf {
  Float32List _d = Float32List(256);
  int length = 0;

  void add(double v) {
    if (length == _d.length) {
      final n = Float32List(_d.length * 2);
      n.setRange(0, length, _d);
      _d = n;
    }
    _d[length++] = v;
  }

  Float32List take() => Float32List.sublistView(_d, 0, length);
}

class _LayerBuf {
  final double z;
  final _F32Buf pts = _F32Buf();
  final _F32Buf fan = _F32Buf();
  final _F32Buf temp = _F32Buf();
  _LayerBuf(this.z);

  bool get isEmpty => fan.length == 0;

  GcodeLayer build() => GcodeLayer(
      z: z, points: pts.take(), fan: fan.take(), temp: temp.take());
}

// Byte constants.
const int _nl = 0x0A, _cr = 0x0D, _sp = 0x20, _tab = 0x09, _semi = 0x3B;
const int _star = 0x2A, _eq = 0x3D;

/// Parse [bytes] (the file as stored on the printer, or its tail from
/// Moonraker's `gcode_start_byte`) into layers. Never throws on odd input;
/// an unparseable file simply yields no layers.
GcodeModel parseGcode(Uint8List bytes) => _Parser(bytes).run();

class _Parser {
  final Uint8List b;
  _Parser(this.b);

  // Motion state.
  double x = 0, y = 0, z = 0, e = 0;
  bool absXyz = true, absE = true;
  bool havePos = false; // an XY has been seen (so the first move isn't a line from 0,0)

  // Heat state.
  double fan = 0;
  final Map<int, double> toolTemp = {};
  int tool = 0;

  // Layers.
  bool markers = false;
  final List<_LayerBuf> seq = []; // marker mode, in file order
  final Map<int, _LayerBuf> byZ = {}; // heuristic mode, keyed by Z in microns
  _LayerBuf? cur;
  bool pendingMarker = false; // a marker seen; the next extrusion opens the layer

  // Stats.
  double minX = double.infinity, minY = double.infinity;
  double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  double fanMin = double.infinity, fanMax = double.negativeInfinity;
  double tempMin = double.infinity, tempMax = double.negativeInfinity;

  // Scratch for the current line's params (indexed by letter A..Z).
  final Float64List pv = Float64List(26);
  final Uint8List pset = Uint8List(26);

  GcodeModel run() {
    final n = b.length;
    var i = 0;
    while (i < n) {
      var end = i;
      while (end < n && b[end] != _nl) {
        end++;
      }
      var le = end;
      if (le > i && b[le - 1] == _cr) le--;
      _line(i, le);
      i = end + 1;
    }
    return _finish();
  }

  GcodeModel _finish() {
    final List<GcodeLayer> layers;
    if (markers) {
      layers = [for (final l in seq) if (!l.isEmpty) l.build()];
    } else {
      final keys = byZ.keys.toList()..sort();
      layers = [for (final k in keys) if (!byZ[k]!.isEmpty) byZ[k]!.build()];
    }
    if (layers.isEmpty) {
      return const GcodeModel(
          layers: [],
          minX: 0, minY: 0, maxX: 0, maxY: 0,
          fanMin: 0, fanMax: 0, tempMin: 0, tempMax: 0,
          markers: false);
    }
    return GcodeModel(
      layers: layers,
      minX: minX, minY: minY, maxX: maxX, maxY: maxY,
      fanMin: fanMin, fanMax: fanMax,
      tempMin: tempMin.isFinite ? tempMin : 0,
      tempMax: tempMax.isFinite ? tempMax : 0,
      markers: markers,
    );
  }

  // ── Lines ────────────────────────────────────────────────────────────────

  void _line(int s, int e) {
    while (s < e && (b[s] == _sp || b[s] == _tab)) {
      s++;
    }
    if (s >= e) return;
    final c0 = b[s];
    if (c0 == _semi) {
      _comment(s + 1, e);
      return;
    }
    // Strip a trailing comment.
    var ce = e;
    for (var k = s; k < e; k++) {
      if (b[k] == _semi) {
        ce = k;
        break;
      }
    }
    while (ce > s && (b[ce - 1] == _sp || b[ce - 1] == _tab)) {
      ce--;
    }
    if (ce <= s) return;

    final up = c0 & 0xDF; // upper-case the command letter
    if (up == 0x47 /* G */) {
      final code = _intAfter(s + 1, ce);
      switch (code) {
        case 0:
        case 1:
          _params(s, ce);
          _linear();
          break;
        case 2:
        case 3:
          _params(s, ce);
          _arc(code == 2);
          break;
        case 90:
          absXyz = true;
          absE = true;
          break;
        case 91:
          absXyz = false;
          absE = false;
          break;
        case 92:
          _params(s, ce);
          if (_has('X')) x = _p('X');
          if (_has('Y')) y = _p('Y');
          if (_has('Z')) z = _p('Z');
          if (_has('E')) this.e = _p('E'); // `e` here is the line end
          break;
      }
      return;
    }
    if (up == 0x4D /* M */) {
      final code = _intAfter(s + 1, ce);
      switch (code) {
        case 82:
          absE = true;
          break;
        case 83:
          absE = false;
          break;
        case 104:
        case 109:
          _params(s, ce);
          if (_has('S')) {
            final t = _has('T') ? _p('T').round() : tool;
            _setTemp(t, _p('S'));
          }
          break;
        case 106:
          _params(s, ce);
          if (!_has('P') || _p('P').round() == 0) {
            fan = _has('S') ? (_p('S') / 255.0).clamp(0.0, 1.0) : 1.0;
          }
          break;
        case 107:
          _params(s, ce);
          if (!_has('P') || _p('P').round() == 0) fan = 0;
          break;
      }
      return;
    }
    if (up == 0x54 /* T */ && ce - s <= 3) {
      final t = _intAfter(s + 1, ce);
      if (t >= 0) tool = t;
      return;
    }
    // Extended commands (Klipper macros). Only two matter and they are rare,
    // so a String for the line is fine here.
    if (_startsWith(s, ce, 'PRINT_START') ||
        _startsWith(s, ce, 'START_PRINT')) {
      _macroTemp(String.fromCharCodes(b, s, ce), const [
        'EXTRUDER_TEMP', 'EXTRUDER', 'HOTEND', 'HOTEND_TEMP', 'NOZZLE_TEMP',
        'NOZZLE', 'TOOL_TEMP', 'TEMP_HOTEND', 'TEMP_EXTRUDER', 'E_TEMP',
        'PRINT_TEMP', 'TEMP_NOZZLE',
      ]);
    } else if (_startsWith(s, ce, 'SET_HEATER_TEMPERATURE')) {
      final line = String.fromCharCodes(b, s, ce).toUpperCase();
      if (line.contains('HEATER=EXTRUDER')) {
        final m = RegExp(r'TARGET=([0-9.]+)').firstMatch(line);
        final v = m == null ? null : double.tryParse(m.group(1)!);
        if (v != null) {
          final tm = RegExp(r'HEATER=EXTRUDER(\d*)').firstMatch(line);
          final t = tm == null || tm.group(1)!.isEmpty
              ? 0
              : int.parse(tm.group(1)!);
          _setTemp(t, v);
        }
      }
    }
  }

  void _comment(int s, int e) {
    // Markers the slicers write. Keep this cheap: one letter check first.
    if (s >= e) return;
    while (s < e && b[s] == _sp) {
      s++;
    }
    if (s >= e) return;
    final c = b[s] & 0xDF;
    if (c == 0x4C /* L */) {
      if (_startsWith(s, e, 'LAYER_CHANGE') ||
          (_startsWith(s, e, 'LAYER:') ) ||
          (_startsWith(s, e, 'LAYER ') && _s3dLayer(s, e))) {
        _marker();
      }
    }
  }

  // Simplify3D: "; layer 12, Z = 2.400" - but also "; layer end" (skip).
  bool _s3dLayer(int s, int e) {
    final k = s + 6;
    return k < e && b[k] >= 0x30 && b[k] <= 0x39;
  }

  void _marker() {
    if (!markers) {
      // Switch modes: whatever the heuristic collected so far becomes the
      // first layer(s) in Z order.
      markers = true;
      final keys = byZ.keys.toList()..sort();
      seq.addAll([for (final k in keys) byZ[k]!]);
      byZ.clear();
    }
    pendingMarker = true;
  }

  // ── Moves ────────────────────────────────────────────────────────────────

  void _linear() {
    final nx = _has('X') ? (absXyz ? _p('X') : x + _p('X')) : x;
    final ny = _has('Y') ? (absXyz ? _p('Y') : y + _p('Y')) : y;
    final nz = _has('Z') ? (absXyz ? _p('Z') : z + _p('Z')) : z;
    var de = 0.0;
    if (_has('E')) {
      final ne = absE ? _p('E') : e + _p('E');
      de = ne - e;
      e = ne;
    }
    final moved = (nx != x || ny != y);
    if (de > 1e-6 && moved && havePos) {
      _segment(x, y, nx, ny, nz);
    }
    x = nx;
    y = ny;
    z = nz;
    if (_has('X') || _has('Y')) havePos = true;
  }

  void _arc(bool clockwise) {
    final nx = _has('X') ? (absXyz ? _p('X') : x + _p('X')) : x;
    final ny = _has('Y') ? (absXyz ? _p('Y') : y + _p('Y')) : y;
    final nz = _has('Z') ? (absXyz ? _p('Z') : z + _p('Z')) : z;
    var de = 0.0;
    if (_has('E')) {
      final ne = absE ? _p('E') : e + _p('E');
      de = ne - e;
      e = ne;
    }
    final extruding = de > 1e-6 && havePos;
    double cx, cy;
    if (_has('I') || _has('J')) {
      cx = x + (_has('I') ? _p('I') : 0);
      cy = y + (_has('J') ? _p('J') : 0);
    } else if (_has('R')) {
      final r = _p('R');
      final dx = nx - x, dy = ny - y;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d == 0 || d > 2 * r.abs()) {
        if (extruding) _segment(x, y, nx, ny, nz);
        x = nx;
        y = ny;
        z = nz;
        return;
      }
      final h = math.sqrt(math.max(0, r * r - (d / 2) * (d / 2)));
      final mx = (x + nx) / 2, my = (y + ny) / 2;
      final sgn = (clockwise ? -1 : 1) * (r < 0 ? -1 : 1);
      cx = mx - sgn * h * dy / d;
      cy = my + sgn * h * dx / d;
    } else {
      if (extruding) _segment(x, y, nx, ny, nz);
      x = nx;
      y = ny;
      z = nz;
      return;
    }
    if (extruding) {
      final r = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
      var a0 = math.atan2(y - cy, x - cx);
      var a1 = math.atan2(ny - cy, nx - cx);
      var sweep = a1 - a0;
      if (clockwise) {
        if (sweep >= 0) sweep -= 2 * math.pi;
      } else {
        if (sweep <= 0) sweep += 2 * math.pi;
      }
      // Full circle (start == end).
      if ((nx - x).abs() < 1e-6 && (ny - y).abs() < 1e-6) {
        sweep = clockwise ? -2 * math.pi : 2 * math.pi;
      }
      final steps = math.max(1, (sweep.abs() / (5 * math.pi / 180)).ceil());
      var px = x, py = y;
      for (var k = 1; k <= steps; k++) {
        final a = a0 + sweep * k / steps;
        final qx = k == steps ? nx : cx + r * math.cos(a);
        final qy = k == steps ? ny : cy + r * math.sin(a);
        _segment(px, py, qx, qy, nz);
        px = qx;
        py = qy;
      }
    }
    x = nx;
    y = ny;
    z = nz;
  }

  void _segment(double x1, double y1, double x2, double y2, double zz) {
    final layer = _layerFor(zz);
    layer.pts
      ..add(x1)
      ..add(y1)
      ..add(x2)
      ..add(y2);
    layer.fan.add(fan);
    final t = toolTemp[tool] ?? toolTemp[0] ?? 0.0;
    layer.temp.add(t);
    if (x1 < minX) minX = x1;
    if (x2 < minX) minX = x2;
    if (x1 > maxX) maxX = x1;
    if (x2 > maxX) maxX = x2;
    if (y1 < minY) minY = y1;
    if (y2 < minY) minY = y2;
    if (y1 > maxY) maxY = y1;
    if (y2 > maxY) maxY = y2;
    if (fan < fanMin) fanMin = fan;
    if (fan > fanMax) fanMax = fan;
    if (t > 0) {
      if (t < tempMin) tempMin = t;
      if (t > tempMax) tempMax = t;
    }
  }

  _LayerBuf _layerFor(double zz) {
    if (markers) {
      if (pendingMarker || cur == null) {
        pendingMarker = false;
        cur = _LayerBuf(zz);
        seq.add(cur!);
      }
      return cur!;
    }
    final key = (zz * 1000).round();
    final c = cur;
    if (c != null && (c.z * 1000).round() == key) return c;
    return cur = byZ.putIfAbsent(key, () => _LayerBuf(zz));
  }

  void _setTemp(int t, double v) {
    if (v < 0) return;
    toolTemp[t] = v;
  }

  void _macroTemp(String line, List<String> keys) {
    final up = line.toUpperCase();
    for (final m in RegExp(r'([A-Z_]+)=([0-9.]+)').allMatches(up)) {
      final k = m.group(1)!;
      if (keys.contains(k)) {
        final v = double.tryParse(m.group(2)!);
        if (v != null && v > 0) {
          // The macro sets the hotend for the active tool (tool 0 normally).
          toolTemp.putIfAbsent(tool, () => v);
          return;
        }
      }
    }
  }

  // ── Tokens ───────────────────────────────────────────────────────────────

  /// Read `A12.5 B-3 ...` from [s] to [e] into pv/pset (letters only; the
  /// command word itself is skipped by the caller passing its start - the
  /// first token is the command, which we also record harmlessly).
  void _params(int s, int e) {
    pset.fillRange(0, 26, 0);
    var i = s;
    // skip the command word (G1 / M106)
    while (i < e && b[i] != _sp && b[i] != _tab) {
      i++;
    }
    while (i < e) {
      final c = b[i];
      if (c == _sp || c == _tab) {
        i++;
        continue;
      }
      final L = c & 0xDF;
      if (L < 0x41 || L > 0x5A) {
        // Not a letter (a checksum '*', '=' from a macro) - stop.
        if (c == _star || c == _eq) return;
        i++;
        continue;
      }
      i++;
      final r = _number(i, e);
      if (r != null) {
        pv[L - 0x41] = r;
        pset[L - 0x41] = 1;
      }
      // advance past the number
      while (i < e && b[i] != _sp && b[i] != _tab) {
        i++;
      }
    }
  }

  bool _has(String letter) => pset[letter.codeUnitAt(0) - 0x41] == 1;
  double _p(String letter) => pv[letter.codeUnitAt(0) - 0x41];

  /// Integer right after a command letter (G1 -> 1, M106 -> 106, T0 -> 0);
  /// -1 when absent. Tolerates "G01" and "G1.0".
  int _intAfter(int s, int e) {
    var i = s;
    var v = 0;
    var any = false;
    while (i < e) {
      final c = b[i];
      if (c >= 0x30 && c <= 0x39) {
        v = v * 10 + (c - 0x30);
        any = true;
        i++;
      } else {
        break;
      }
    }
    return any ? v : -1;
  }

  /// Fast decimal parse at [i]; null when no digits. Handles sign, fraction
  /// and an exponent (rare). Faster than double.parse on a substring.
  double? _number(int i, int e) {
    var neg = false;
    if (i < e && (b[i] == 0x2D || b[i] == 0x2B)) {
      neg = b[i] == 0x2D;
      i++;
    }
    var v = 0.0;
    var any = false;
    while (i < e && b[i] >= 0x30 && b[i] <= 0x39) {
      v = v * 10 + (b[i] - 0x30);
      any = true;
      i++;
    }
    if (i < e && b[i] == 0x2E) {
      i++;
      var f = 0.1;
      while (i < e && b[i] >= 0x30 && b[i] <= 0x39) {
        v += (b[i] - 0x30) * f;
        f *= 0.1;
        any = true;
        i++;
      }
    }
    if (!any) return null;
    if (i < e && (b[i] | 0x20) == 0x65 /* e */) {
      i++;
      var en = false;
      if (i < e && (b[i] == 0x2D || b[i] == 0x2B)) {
        en = b[i] == 0x2D;
        i++;
      }
      var ex = 0;
      while (i < e && b[i] >= 0x30 && b[i] <= 0x39) {
        ex = ex * 10 + (b[i] - 0x30);
        i++;
      }
      v *= math.pow(10.0, en ? -ex : ex);
    }
    return neg ? -v : v;
  }

  bool _startsWith(int s, int e, String word) {
    if (e - s < word.length) return false;
    for (var k = 0; k < word.length; k++) {
      if ((b[s + k] & 0xDF) != (word.codeUnitAt(k) & 0xDF)) return false;
    }
    return true;
  }
}
