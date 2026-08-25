/// Pure decision logic for the loud one-shot "Printer alerts" the Android
/// foreground service fires on top of its silent roster + cards (v0.9.61).
///
/// Mirrors the Pi plugin's push-event matrix (PrintEventWatcher, plugin
/// 0.6.25) so an Android phone hears about the same moments an iPhone gets
/// pushed for: a print pausing, a print failing (with Klipper's reason), and
/// the machine itself erroring out / shutting down. "started" / "completed"
/// stay on the silent cards - routine, not exceptional.
///
/// Kept free of Flutter imports so the transition matrix is unit-testable.
library;

/// An exceptional printer moment worth a buzzing notification.
enum PrintEvent { paused, failed, machineError }

/// Map a live state transition to an alert, or null for the ones that stay
/// silent. [prev] is null on the first live observation after the service
/// starts - a baseline only, never an alert, exactly like the plugin: the
/// service must not buzz for whatever state a printer was already in.
///
/// States are the service's own: Klipper print_stats states, plus 'shutdown'
/// for "Klipper itself is down" (webhooks / klippy_state shutdown|error, the
/// machine-error case). Because a machine error overrides the polled state to
/// 'shutdown' before print_stats can report 'error', the plugin's "one alert
/// per disaster" 60-second suppression falls out for free here: 'failed' only
/// fires from a healthy printing/paused state, so the later shutdown→error
/// settle (print_stats still holding 'error' after a firmware restart) stays
/// silent instead of re-alerting minutes after the event.
PrintEvent? printEventFor(String? prev, String cur) {
  if (prev == null || prev == cur) return null;
  if (cur == 'paused' && prev == 'printing') return PrintEvent.paused;
  if (cur == 'error' && (prev == 'printing' || prev == 'paused')) {
    return PrintEvent.failed;
  }
  if (cur == 'shutdown') return PrintEvent.machineError;
  return null;
}

/// Whether a freshly polled MOONGATE_NOTIFY sequence number should alert.
/// The first observation ([prevSeq] null) is a baseline - alerting then would
/// replay a stale message every service start. A seq that went DOWN means the
/// plugin restarted (its counter is in-process); re-baseline silently.
bool shouldAlertCustom(int? prevSeq, int seq) =>
    prevSeq != null && seq > prevSeq;

/// Reduce Klipper's multi-line shutdown / error message to its useful first
/// line, mirroring the plugin's `_error_detail` (control characters become
/// spaces, boilerplate tail dropped, capped) so the Android alert body reads
/// exactly like the iOS push for the same incident.
String firstDetailLine(String? raw) {
  for (final line in (raw ?? '').split('\n')) {
    final cleaned = line
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
        .trim();
    if (cleaned.isNotEmpty) {
      return cleaned.length > 180 ? cleaned.substring(0, 180) : cleaned;
    }
  }
  return '';
}
