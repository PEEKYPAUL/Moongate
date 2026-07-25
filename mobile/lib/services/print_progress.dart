// Print-progress maths shared by the dashboard tile ([PrinterStatusService])
// and the print notification ([PrintNotificationService]) so the two can never
// disagree - and so both match what Mainsail shows.
//
// They used to drift: the tile preferred an elapsed-time ÷ slicer-estimate
// calculation while the notification used the raw file fraction, and neither
// matched Mainsail's default. This is the single source of truth.

import 'package:intl/intl.dart';

/// Print progress as a fraction in 0..1, computed to match Mainsail's default
/// **"file position (relative)"** mode: the printed byte position mapped onto
/// the slicer's gcode body, between [gcodeStartByte] and [gcodeEndByte], so the
/// file header (embedded thumbnails, config block) and trailing end-gcode don't
/// skew the percentage.
///
/// We deliberately do NOT use elapsed-time ÷ slicer-estimate: the slicer's
/// estimate is routinely off by 10-40%, which made the tile read several percent
/// ahead of Mainsail (the bug this replaces).
///
/// Fallback chain when the byte offsets or file position aren't known yet (e.g.
/// the file metadata hasn't loaded for the first second of a print):
///   1. file-relative - needs [filePosition] + both valid gcode byte offsets
///   2. [displayProgress] - Klipper's `display_status.progress` (mirrors the
///      file fraction when the slice has no M73; honours M73 when it does)
///   3. [sdcardProgress]  - raw `virtual_sdcard.progress` (file-absolute)
///   4. 0
double computePrintProgress({
  double? filePosition,
  int? gcodeStartByte,
  int? gcodeEndByte,
  double? displayProgress,
  double? sdcardProgress,
}) {
  if (filePosition != null &&
      gcodeStartByte != null &&
      gcodeEndByte != null &&
      gcodeEndByte > gcodeStartByte) {
    final rel =
        (filePosition - gcodeStartByte) / (gcodeEndByte - gcodeStartByte);
    return rel.clamp(0.0, 1.0);
  }
  if (displayProgress != null && displayProgress > 0) {
    return displayProgress.clamp(0.0, 1.0);
  }
  if (sdcardProgress != null && sdcardProgress > 0) {
    return sdcardProgress.clamp(0.0, 1.0);
  }
  return 0.0;
}

/// Print time remaining (seconds), following Mainsail's ETA recipe so the chip
/// lands on the numbers users compare it against: the average of every
/// estimate source with usable inputs -
///   file     - elapsed ÷ file-relative progress (the classic extrapolation,
///              and still the sole source when no metadata is known)
///   filament - elapsed ÷ filament fraction (print_stats.filament_used over
///              the file metadata's filament_total)
///   slicer   - the slicer's own total (file metadata estimated_time) minus
///              elapsed
/// (mainsail-crew/mainsail src/store/printer/getters.ts getEstimatedTimeETA,
/// whose default averages exactly these three.)
///
/// The two extrapolating sources only join once they have enough signal to
/// mean anything (fraction ≥ 2%, ≥ 30s elapsed - below that the division
/// produces garbage like "~43h"); the slicer total is trustworthy from the
/// first second. The blend is what keeps the early-print number sane: pure
/// file extrapolation read ~4h against Mainsail's ~3h at 5% of an ABS print
/// whose opening minutes are brim + solid bottom layers (2026-07-25 user
/// report - both screenshots are fixtures in print_progress_test.dart).
///
/// Null when there's nothing meaningful to show:
///   - not actively printing (a paused print's elapsed clock is frozen, so its
///     estimate silently goes stale - hide rather than mislead);
///   - no source has usable inputs yet;
///   - implausibly long (> 100h - a corrupt duration/progress pair).
double? printRemainingSeconds({
  required String state,
  required double progress,
  required double printDurationSec,
  double? filamentUsedMm,
  double? filamentTotalMm,
  double? slicerEstimateSec,
}) {
  if (state != 'printing') return null;

  final estimates = <double>[];

  // file: elapsed ÷ byte-position progress.
  if (progress >= 0.02 && printDurationSec >= 30) {
    estimates.add(printDurationSec * (1 - progress) / progress);
  }

  // filament: elapsed ÷ consumed-filament fraction. A bottom-heavy part
  // (solid base, brim) has this fraction running well ahead of the byte
  // position early in the print, which is precisely the correction that
  // pulls Mainsail's average down to a realistic figure.
  if (filamentUsedMm != null &&
      filamentTotalMm != null &&
      filamentTotalMm > 0 &&
      printDurationSec >= 30) {
    final fraction = filamentUsedMm / filamentTotalMm;
    if (fraction >= 0.02 && fraction <= 1) {
      estimates.add(printDurationSec * (1 - fraction) / fraction);
    }
  }

  // slicer: its own total minus elapsed. Goes negative once a print overruns
  // the slicer's guess - drop it then, as Mainsail's average does.
  if (slicerEstimateSec != null && slicerEstimateSec > 0) {
    final slicerRemaining = slicerEstimateSec - printDurationSec;
    if (slicerRemaining > 0) estimates.add(slicerRemaining);
  }

  if (estimates.isEmpty) return null;
  final remaining =
      estimates.reduce((a, b) => a + b) / estimates.length;
  if (remaining <= 0 || remaining > 100 * 3600) return null;
  return remaining;
}

/// "1h05m" / "14m" - how much longer the print has to run.
String formatRemainingDuration(double seconds) {
  final d = Duration(seconds: seconds.round());
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}m' : '${m}m';
}

/// Wall-clock time the print is projected to finish ("1:20 AM" / "13:20"),
/// localised 12/24h via [localeName] - the same "ETA" Klipper and Mainsail
/// display. Null if the locale's date symbols didn't load, so callers fall
/// back to the remaining duration.
String? formatFinishClock(double remainingSeconds, String localeName) {
  try {
    final finish =
        DateTime.now().add(Duration(seconds: remainingSeconds.round()));
    return DateFormat.jm(localeName).format(finish);
  } catch (_) {
    return null;
  }
}
