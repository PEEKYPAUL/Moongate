import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/services/print_control_service.dart';

void main() {
  group('ConsoleLine.fromJson - the gcode_store contract', () {
    test('a command entry parses with its timestamp', () {
      final line = ConsoleLine.fromJson(const {
        'message': 'G28',
        'time': 1756300000.123,
        'type': 'command',
      });
      expect(line.message, 'G28');
      expect(line.time, closeTo(1756300000.123, 0.001));
      expect(line.isCommand, isTrue);
    });

    test('a response entry is not a command', () {
      final line = ConsoleLine.fromJson(const {
        'message': 'ok',
        'time': 1756300001,
        'type': 'response',
      });
      expect(line.isCommand, isFalse);
    });

    test('missing fields fall back instead of throwing', () {
      final line = ConsoleLine.fromJson(const {});
      expect(line.message, '');
      expect(line.time, 0);
      expect(line.isCommand, isFalse);
    });
  });

  group('ConsoleLine.kind - Klipper line conventions', () {
    ConsoleLine response(String message) =>
        ConsoleLine(message: message, time: 0, isCommand: false);

    test('commands classify as command regardless of content', () {
      // Klipper never receives `!!`/`//` prefixed COMMANDS in practice, but
      // the store's type field must outrank the prefix conventions.
      const cmd = ConsoleLine(message: '!! weird', time: 0, isCommand: true);
      expect(cmd.kind, ConsoleLineKind.command);
    });

    test('!! marks an error', () {
      expect(response('!! Must home axis first').kind, ConsoleLineKind.error);
    });

    test('// marks an info line', () {
      expect(response('// Klipper state: Ready').kind, ConsoleLineKind.info);
    });

    test('anything else is a plain response', () {
      expect(response('ok').kind, ConsoleLineKind.response);
      expect(
        response('X:175.0 Y:175.0 Z:20.35 E:1284.2').kind,
        ConsoleLineKind.response,
      );
      // The prefixes only count at the START of the line.
      expect(response('recv: !! echoed').kind, ConsoleLineKind.response);
    });

    test('a multi-line response classifies by its first line', () {
      expect(
        response('!! Shutdown due to M112\n// Once underlying issue…').kind,
        ConsoleLineKind.error,
      );
    });
  });
}
