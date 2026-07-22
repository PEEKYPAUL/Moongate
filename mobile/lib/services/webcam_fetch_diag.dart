/// In-memory per-printer record of how the webcam fetch loop is doing, for
/// the in-app bug report. A camera that silently never produces a frame (the
/// "eternal logo" class of report) is invisible in every other diagnostic -
/// the poll succeeds, the printer is online, only the frames are missing.
/// WebcamView records every fetch outcome here; DiagnosticsService reads it
/// when composing a report. Pure Dart, no Flutter imports, session-only.
class WebcamFetchDiag {
  WebcamFetchDiag._();

  static final Map<String, Map<String, Object?>> _byPrinter = {};

  /// Strip the query string - the tunnel snapshot URL carries mg_token, and
  /// a custom camera URL could carry credentials. Host + path is all a bug
  /// report needs to tell LAN-direct from relay from a stale gear override.
  static String redactUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return 'unparseable';
    final port = u.hasPort ? ':${u.port}' : '';
    return '${u.scheme}://${u.host}$port${u.path}';
  }

  /// Record the outcome of one fetch attempt. [result] is a short token:
  /// 'ok', 'empty', 'not-image', 'http 502', 'timeout', 'error'.
  static void record(
    String? printerId, {
    required String url,
    required bool external,
    required String result,
  }) {
    if (printerId == null) return;
    final now = DateTime.now().toIso8601String();
    final entry = _byPrinter.putIfAbsent(printerId, () => {});
    final ok = result == 'ok';
    entry['url']      = redactUrl(url);
    entry['external'] = external;
    entry['last_attempt'] = now;
    entry['last_result']  = result;
    if (ok) {
      entry['last_success'] = now;
      entry['consecutive_failures'] = 0;
    } else {
      entry['consecutive_failures'] =
          ((entry['consecutive_failures'] as int?) ?? 0) + 1;
    }
    entry['attempts'] = ((entry['attempts'] as int?) ?? 0) + 1;
  }

  /// Record what the widget is currently showing ('frames' | 'waking' |
  /// 'placeholder') so the report pairs fetch outcomes with what the user
  /// actually sees.
  static void recordShowing(String? printerId, String showing) {
    if (printerId == null) return;
    _byPrinter.putIfAbsent(printerId, () => {})['showing'] = showing;
  }

  /// Snapshot for the bug report, or null if this printer's webcam never
  /// attempted a fetch this session (e.g. webcam hidden / none configured).
  static Map<String, Object?>? report(String printerId) {
    final entry = _byPrinter[printerId];
    return entry == null ? null : Map.unmodifiable(entry);
  }
}
