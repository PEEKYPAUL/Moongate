import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'gcode_layer_parser.dart' show GcodeModel;
import 'print_control_service.dart' show GcodeFile;

/// Session cache of stored G-code files (v0.9.76), so a file is downloaded
/// from the printer once per app run and then serves both the layer viewer
/// and Save to phone. The bytes sit on disk, not in memory (a 90 MB file is
/// not something to hold in RAM), in the app's cache folder
/// (`getApplicationCacheDirectory()/gcode/<key>.gcode`), capped at [maxBytes]
/// with the least recently used files deleted first, and **emptied at every
/// app launch** ([clearAtLaunch], called from `main`): Paul's call, 23/10,
/// no re-download while the app runs and nothing left behind once it
/// restarts. The key is the printer, the path, the modified time and the
/// size, so a re-sliced file under the same name is fetched afresh. Every
/// failure is swallowed: a cache miss is never an error.
///
/// Also keeps the last parsed [GcodeModel] in memory, so reopening the file
/// you just looked at skips the parse too.
class GcodeCache {
  static const int maxBytes = 300 * 1024 * 1024;

  /// Empty the cache folder. Called once at app start, off the startup path.
  static Future<void> clearAtLaunch() async {
    try {
      final d = Directory('${(await getApplicationCacheDirectory()).path}/gcode');
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  /// Cache key for [file] on [printerId].
  static String key(String printerId, GcodeFile file) => sha1
      .convert(utf8.encode(
          '$printerId|${file.path}|${file.modified}|${file.size}'))
      .toString();

  static Future<Directory?> _dir() async {
    try {
      final d = Directory('${(await getApplicationCacheDirectory()).path}/gcode');
      if (!await d.exists()) await d.create(recursive: true);
      return d;
    } catch (_) {
      return null;
    }
  }

  static Future<File?> _fileFor(String key) async {
    final d = await _dir();
    return d == null ? null : File('${d.path}/$key.gcode');
  }

  /// True when the whole file is in the cache (the viewer then skips the
  /// "download over the internet?" question).
  static Future<bool> has(String printerId, GcodeFile file) async {
    try {
      final f = await _fileFor(key(printerId, file));
      if (f == null || !await f.exists()) return false;
      return file.size <= 0 || await f.length() == file.size;
    } catch (_) {
      return false;
    }
  }

  /// The cached bytes, or null. Touches the file so LRU eviction keeps it.
  static Future<Uint8List?> read(String printerId, GcodeFile file) async {
    try {
      final f = await _fileFor(key(printerId, file));
      if (f == null || !await f.exists()) return null;
      final bytes = await f.readAsBytes();
      if (file.size > 0 && bytes.length != file.size) {
        // A partial or stale copy: drop it.
        unawaited(f.delete().catchError((_) => f));
        return null;
      }
      unawaited(f.setLastModified(DateTime.now()).catchError((_) {}));
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Store [bytes] for [file] (written to a `.part` first, then renamed, so
  /// a reader never sees half a file), then evict down to [maxBytes].
  static Future<void> write(
      String printerId, GcodeFile file, Uint8List bytes) async {
    try {
      if (bytes.isEmpty || bytes.length > maxBytes ~/ 2) return;
      final f = await _fileFor(key(printerId, file));
      if (f == null) return;
      final part = File('${f.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(f.path);
      await _evict();
    } catch (_) {}
  }

  static Future<void> _evict() async {
    final d = await _dir();
    if (d == null) return;
    final entries = <(File, FileStat)>[];
    await for (final e in d.list()) {
      if (e is! File) continue;
      final st = await e.stat();
      if (e.path.endsWith('.part')) {
        // A write that never finished (the app died mid-save).
        if (DateTime.now().difference(st.modified).inHours >= 1) {
          unawaited(e.delete().catchError((_) => e));
        }
        continue;
      }
      if (e.path.endsWith('.gcode')) entries.add((e, st));
    }
    entries.sort((a, b) => b.$2.modified.compareTo(a.$2.modified));
    var total = 0;
    for (final (f, st) in entries) {
      total += st.size;
      if (total > maxBytes) {
        unawaited(f.delete().catchError((_) => f));
      }
    }
  }

  // ── The last parsed model, in memory ─────────────────────────────────────

  static String? _lastKey;
  static GcodeModel? _lastModel;

  /// The model parsed last time, when it was this [key]'s file.
  static GcodeModel? lastModel(String key) =>
      _lastKey == key ? _lastModel : null;

  static void rememberModel(String key, GcodeModel model) {
    _lastKey = key;
    _lastModel = model;
  }
}
