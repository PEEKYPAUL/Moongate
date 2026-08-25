import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/models/notif_events.dart';

void main() {
  group('printEventFor - the loud-alert transition matrix', () {
    test('first observation is a baseline, never an alert', () {
      expect(printEventFor(null, 'printing'), isNull);
      expect(printEventFor(null, 'paused'), isNull);
      expect(printEventFor(null, 'error'), isNull);
      // Even a printer already dead when the service starts stays silent.
      expect(printEventFor(null, 'shutdown'), isNull);
    });

    test('printing → paused alerts (runout macros and manual pauses alike)', () {
      expect(printEventFor('printing', 'paused'), PrintEvent.paused);
    });

    test('resume and pause-adjacent shuffles stay silent', () {
      expect(printEventFor('paused', 'printing'), isNull);
      expect(printEventFor('paused', 'paused'), isNull);
      expect(printEventFor('standby', 'paused'), isNull);
    });

    test('a live print failing alerts, from printing or paused', () {
      expect(printEventFor('printing', 'error'), PrintEvent.failed);
      expect(printEventFor('paused', 'error'), PrintEvent.failed);
    });

    test('error seen from a non-print state stays silent', () {
      // Klipper holds 'error' in print_stats until the next job; re-seeing it
      // from standby (or right after a machine-error recovery) is a
      // re-observation, not a fresh failure.
      expect(printEventFor('standby', 'error'), isNull);
      expect(printEventFor('shutdown', 'error'), isNull);
    });

    test('the machine erroring out alerts from any healthy state', () {
      expect(printEventFor('printing', 'shutdown'), PrintEvent.machineError);
      expect(printEventFor('paused', 'shutdown'), PrintEvent.machineError);
      expect(printEventFor('standby', 'shutdown'), PrintEvent.machineError);
      expect(printEventFor('complete', 'shutdown'), PrintEvent.machineError);
    });

    test('a persisting shutdown never refires', () {
      expect(printEventFor('shutdown', 'shutdown'), isNull);
    });

    test('recovery is silent in v1, like the plugin pushes', () {
      expect(printEventFor('shutdown', 'standby'), isNull);
      expect(printEventFor('error', 'standby'), isNull);
    });

    test('routine transitions stay on the silent cards', () {
      expect(printEventFor('standby', 'printing'), isNull); // started
      expect(printEventFor('printing', 'complete'), isNull); // completed
      expect(printEventFor('printing', 'cancelled'), isNull);
      expect(printEventFor('printing', 'standby'), isNull);
    });
  });

  group('shouldAlertCustom - MOONGATE_NOTIFY sequence gating', () {
    test('first sighting is a baseline', () {
      expect(shouldAlertCustom(null, 5), isFalse);
    });

    test('a seq increase alerts', () {
      expect(shouldAlertCustom(5, 6), isTrue);
      expect(shouldAlertCustom(5, 50), isTrue);
    });

    test('same seq / a plugin restart (seq reset) re-baselines silently', () {
      expect(shouldAlertCustom(5, 5), isFalse);
      expect(shouldAlertCustom(5, 1), isFalse);
    });
  });

  group('firstDetailLine - Klipper reason extraction', () {
    test('takes the first non-empty line, trimmed', () {
      expect(
        firstDetailLine('Move out of range: 350.0 0.0 5.0\n'
            'Once the underlying issue is corrected, use the\n'
            '"FIRMWARE_RESTART" command to reset the firmware'),
        'Move out of range: 350.0 0.0 5.0',
      );
    });

    test('skips leading blank lines and strips control characters', () {
      expect(firstDetailLine('\n\n  \tShutdown due to M112 command\n'),
          'Shutdown due to M112 command');
    });

    test('empty / null / whitespace-only give an empty reason', () {
      expect(firstDetailLine(null), '');
      expect(firstDetailLine(''), '');
      expect(firstDetailLine('  \n \n'), '');
    });

    test('caps a runaway first line at 180 characters', () {
      expect(firstDetailLine('x' * 500).length, 180);
    });
  });
}
