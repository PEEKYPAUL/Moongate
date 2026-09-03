import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/services/gcode_completion_service.dart';

void main() {
  const service = GcodeCompletionService(
    commands: {'RESTART': 'Reload config', 'STATUS': 'Report status'},
    macros: ['PRINT_START'],
    history: ['G28', 'STATUS'],
    parameters: {
      'SET_HEATER_TEMPERATURE': ['HEATER=', 'TARGET='],
    },
  );

  test('merges live commands, macros, and history by prefix', () {
    expect(service.complete('P').map((c) => c.displayText), ['PRINT_START']);
    expect(service.complete('R').single.description, 'Reload config');
    expect(service.complete('G').single.displayText, 'G28');
    expect(service.complete('STAT').single.description, 'Report status');
  });

  test('completes the token at the cursor', () {
    final result = service.complete('STA tail', cursor: 3).single;
    expect(result.displayText, 'STATUS');
    expect(
        'STA tail'.replaceRange(result.start, result.end, result.insertionText),
        'STATUS tail');
  });

  test('replacement covers the whole token when cursor is inside it', () {
    final result = service.complete('STAtus', cursor: 3).single;
    expect(result.start, 0);
    expect(result.end, 6);
    expect(
        'STAtus'.replaceRange(result.start, result.end, result.insertionText),
        'STATUS');
  });

  test('suggests missing parameters without duplicates', () {
    final result = service.complete('SET_HEATER_TEMPERATURE HEATER=extruder T');
    expect(result.map((c) => c.displayText), ['TARGET=']);
  });
}
