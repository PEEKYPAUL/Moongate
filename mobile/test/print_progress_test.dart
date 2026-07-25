import 'package:flutter_test/flutter_test.dart';

import 'package:moongate/services/print_progress.dart';

/// Locks the progress maths to Mainsail's default "file position (relative)"
/// mode. The headline case uses a real snapshot captured live from a print on
/// the Micron - at that moment the old elapsed-time calc read ~12% while
/// Mainsail (and now this) read ~10.85%.
void main() {
  group('computePrintProgress', () {
    test('file-relative matches Mainsail (real Micron snapshot)', () {
      // Live values: file_position 401193, gcode_start_byte 10286,
      // gcode_end_byte 3614739 → (401193-10286)/(3614739-10286) = 0.10845.
      final p = computePrintProgress(
        filePosition: 401193,
        gcodeStartByte: 10286,
        gcodeEndByte: 3614739,
        displayProgress: 0.11,
        sdcardProgress: 0.11037,
      );
      expect(p * 100, closeTo(10.845, 0.01));
    });

    test('byte offsets win over display/sdcard (no time-based path)', () {
      // Even when display/sdcard are present, the relative byte calc is used.
      final p = computePrintProgress(
        filePosition: 1812366, // halfway through the body below
        gcodeStartByte: 10286,
        gcodeEndByte: 3614739,
        displayProgress: 0.9, // bogus on purpose - must be ignored
        sdcardProgress: 0.9,
      );
      expect(p, closeTo(0.5, 0.001));
    });

    test('clamps below the start byte to 0 (still in the header)', () {
      expect(
        computePrintProgress(
          filePosition: 5000,
          gcodeStartByte: 10286,
          gcodeEndByte: 3614739,
        ),
        0.0,
      );
    });

    test('clamps past the end byte to 1 (end gcode)', () {
      expect(
        computePrintProgress(
          filePosition: 3700000,
          gcodeStartByte: 10286,
          gcodeEndByte: 3614739,
        ),
        1.0,
      );
    });

    test('falls back to display_status when offsets unknown', () {
      expect(
        computePrintProgress(displayProgress: 0.42, sdcardProgress: 0.40),
        closeTo(0.42, 1e-9),
      );
    });

    test('falls back to virtual_sdcard when no display progress', () {
      expect(computePrintProgress(sdcardProgress: 0.40), closeTo(0.40, 1e-9));
    });

    test('ignores invalid offsets (end <= start)', () {
      expect(
        computePrintProgress(
          filePosition: 401193,
          gcodeStartByte: 100,
          gcodeEndByte: 100,
          displayProgress: 0.11,
        ),
        closeTo(0.11, 1e-9),
      );
    });

    test('zero when nothing is known', () {
      expect(computePrintProgress(), 0.0);
    });
  });

  // The Mainsail-style remaining-time blend behind the notification card's
  // remaining/ETA line and (v0.9.53) the dashboard tile's time chip. Locking
  // the gates here keeps the two surfaces in agreement forever.
  group('printRemainingSeconds', () {
    test('38% into a print, 26 min elapsed → ~42 min left (no metadata)', () {
      // The v0.9.53 user-report screenshot: Mainsail showed total 0:26:11
      // elapsed at 38%; with no metadata the estimate stays the classic
      // elapsed × (1-p)/p = 1571 × 0.62/0.38 ≈ 2563s ≈ 42.7 min.
      final r = printRemainingSeconds(
        state: 'printing',
        progress: 0.38,
        printDurationSec: 1571,
      );
      expect(r, isNotNull);
      expect(r!, closeTo(2563, 1));
    });

    // The 2026-07-25 user report: a bottom-heavy ABS-CF box (solid base +
    // brim), slicer total 3:02:53 (10973s). Early on, byte-position progress
    // trails the filament fraction badly, so the old file-only extrapolation
    // read ~4h07m while Mainsail showed ~2h58m. Inputs below are solved from
    // the two screenshots against Mainsail's default ETA (the average of the
    // file / filament / slicer estimates) - the blend must land on Mainsail's
    // displayed ETA, minute-close.
    test('Mainsail parity: 11:37 snapshot → ~2h57m, not the old ~4h07m', () {
      final r = printRemainingSeconds(
        state:             'printing',
        progress:          0.045,   // file-relative, layer 11/325
        printDurationSec:  888,     // Total 0:14:48
        filamentUsedMm:    2750,    // Filament 2.75 m
        filamentTotalMm:   12050,
        slicerEstimateSec: 10973,
      );
      expect(r, isNotNull);
      // file 18845 + filament 3003 + slicer 10085, averaged. Mainsail's
      // displayed ETA 14:35 ⇒ 10680s remaining - within a minute.
      expect(r!, closeTo(10644, 60));
    });

    test('Mainsail parity: 11:40 snapshot → finish 14:30 on the dot', () {
      final r = printRemainingSeconds(
        state:             'printing',
        progress:          0.0549,
        printDurationSec:  1039,    // Total 0:17:19
        filamentUsedMm:    3260,    // Filament 3.26 m
        filamentTotalMm:   12050,
        slicerEstimateSec: 10973,
      );
      expect(r, isNotNull);
      // 10207s ≈ 2h50m from 11:40 ⇒ 14:30, exactly Mainsail's displayed ETA.
      expect(r!, closeTo(10207, 60));
    });

    test('slicer estimate alone carries the first seconds of a print', () {
      // Too early for either extrapolation (progress 0.5%, 10s elapsed), but
      // the slicer total is valid from the first second - the chip no longer
      // hides for the opening minutes when metadata is known.
      final r = printRemainingSeconds(
        state:             'printing',
        progress:          0.005,
        printDurationSec:  10,
        slicerEstimateSec: 10973,
      );
      expect(r, isNotNull);
      expect(r!, closeTo(10963, 1));
    });

    test('an overrun print drops the (negative) slicer estimate', () {
      // 90% done but already past the slicer's total: slicer remaining would
      // be negative, so only the file extrapolation counts.
      final r = printRemainingSeconds(
        state:             'printing',
        progress:          0.9,
        printDurationSec:  20000,
        slicerEstimateSec: 10973,
      );
      expect(r, isNotNull);
      expect(r!, closeTo(2222, 1));
    });

    test('garbage filament inputs are ignored, not averaged', () {
      // total of 0 and used > total must both fall out of the blend.
      for (final (used, total) in [(100.0, 0.0), (1200.0, 1000.0)]) {
        final r = printRemainingSeconds(
          state:            'printing',
          progress:         0.5,
          printDurationSec: 1000,
          filamentUsedMm:   used,
          filamentTotalMm:  total,
        );
        expect(r, isNotNull);
        expect(r!, closeTo(1000, 1)); // file-only
      }
    });

    test('null unless actively printing (paused estimate is frozen)', () {
      for (final s in ['paused', 'standby', 'complete', 'offline']) {
        expect(
          printRemainingSeconds(
              state: s, progress: 0.5, printDurationSec: 600),
          isNull,
        );
      }
    });

    test('null while too early to extrapolate', () {
      expect(
        printRemainingSeconds(
            state: 'printing', progress: 0.01, printDurationSec: 600),
        isNull,
      );
      expect(
        printRemainingSeconds(
            state: 'printing', progress: 0.5, printDurationSec: 10),
        isNull,
      );
    });

    test('null when implausibly long (> 100h)', () {
      expect(
        printRemainingSeconds(
            state: 'printing', progress: 0.02, printDurationSec: 8000),
        isNull,
      );
    });
  });

  group('formatRemainingDuration', () {
    test('pads minutes under an hour boundary', () {
      expect(formatRemainingDuration(3900), '1h05m');
    });

    test('minutes only under an hour', () {
      expect(formatRemainingDuration(840), '14m');
    });
  });
}
