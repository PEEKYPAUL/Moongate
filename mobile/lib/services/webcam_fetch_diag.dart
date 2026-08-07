/// Consecutive HARD failures after which a camera is treated as dead rather
/// than still waking: the wake window skips its optimistic spinner
/// (WebcamView) and the status service sets a failing custom override aside
/// in favour of the printer's own camera (resolveWebcamSource). One shared
/// number so the two layers can never disagree about what "dead" means.
const int kDeadCameraThreshold = 6;

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
    // The relay form (/mg-extcam?u=...) hides which camera actually failed
    // once the query is redacted - surface the u= target, itself redacted,
    // so a bug report names the address that's bouncing.
    final target = Uri.tryParse(url)?.queryParameters['u'];
    if (target != null && target.isNotEmpty) {
      entry['target'] = redactUrl(target);
    } else {
      entry.remove('target');
    }
    if (ok) {
      entry['last_success'] = now;
      entry['consecutive_failures'] = 0;
      entry['consecutive_hard']     = 0;
    } else {
      entry['consecutive_failures'] =
          ((entry['consecutive_failures'] as int?) ?? 0) + 1;
      // Hard = something answered "no" (an HTTP status, a refused or
      // unroutable connection). Timeouts and empty bodies stay soft - that's
      // what a genuinely waking on-demand camera produces, and the wake
      // window treats the two classes differently.
      if (result == 'error' || result.startsWith('http ')) {
        entry['consecutive_hard'] =
            ((entry['consecutive_hard'] as int?) ?? 0) + 1;
      } else {
        entry['consecutive_hard'] = 0;
      }
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

  /// Consecutive failed fetches (any kind) recorded for this printer against
  /// the same (redacted) URL - zero when the URL changed or nothing is
  /// recorded yet. The wake window's expired state shows the "unreachable"
  /// message only when this is non-zero (failures actually on record).
  static int consecutiveFailures(String? printerId, String url) {
    final entry = printerId == null ? null : _byPrinter[printerId];
    if (entry == null || entry['url'] != redactUrl(url)) return 0;
    return (entry['consecutive_failures'] as int?) ?? 0;
  }

  /// Consecutive HARD failures (HTTP status / refused connection) for this
  /// printer against the same (redacted) URL. These counters outlive the
  /// webcam widget, so the wake window can skip the optimistic spinner for a
  /// camera this session already knows is dead instead of restarting it on
  /// every remount (grid scroll, app reopen).
  static int consecutiveHardFailures(String? printerId, String url) {
    final entry = printerId == null ? null : _byPrinter[printerId];
    if (entry == null || entry['url'] != redactUrl(url)) return 0;
    return (entry['consecutive_hard'] as int?) ?? 0;
  }

  /// Test hook - the per-printer map is process-global state, so tests clear
  /// it between cases. Production never calls this.
  static void reset() => _byPrinter.clear();
}
