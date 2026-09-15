import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/models/temp_watch.dart';

void main() {
  const t0 = 1700000000; // epoch seconds

  Map<String, dynamic> soak({int reached = 0, int due = 0, String file = 'abs/benchy.gcode'}) => {
        'id':          'app-soak',
        'wait':        {'bed': 110.0, 'chamber': 45.0},
        'dirs':        {'bed': 'up', 'chamber': 'up'},
        'soak':        20,
        'msg':         'Heat-soak complete: Bed {bed}',
        'then_start':  file,
        'after_print': false,
        'armed_ts':    t0,
        'reached_ts':  reached,
        'due_ts':      due,
      };

  Map<String, dynamic> cool() => {
        'id':          'app-cool',
        'wait':        {'bed': 29.0, 'chamber': 28.0},
        'dirs':        {'bed': 'down', 'chamber': 'down'},
        'soak':        0,
        'after_print': true,
        'armed_ts':    t0,
      };

  group('TempWatchInfo.fromJson', () {
    test('decodes a soak watch', () {
      final w = TempWatchInfo.fromJson(soak(reached: t0 + 600, due: t0 + 1800))!;
      expect(w.id, 'app-soak');
      expect(w.wait, {'bed': 110.0, 'chamber': 45.0});
      expect(w.dirs, {'bed': 'up', 'chamber': 'up'});
      expect(w.soakMinutes, 20);
      expect(w.thenStartName, 'benchy.gcode');
      expect(w.soaking, isTrue);
      expect(w.coolDown, isFalse);
    });

    test('a cool-down watch is every goal downwards', () {
      final w = TempWatchInfo.fromJson(cool())!;
      expect(w.coolDown, isTrue);
      expect(w.afterPrint, isTrue);
      expect(w.soaking, isFalse);
    });

    test('rejects malformed entries and an older plugin\'s missing list', () {
      expect(TempWatchInfo.fromJson(null), isNull);
      expect(TempWatchInfo.fromJson({'id': 'x'}), isNull);
      expect(TempWatchInfo.fromJson({'id': 'x', 'wait': {'bed': 0}}), isNull);
      expect(TempWatchInfo.listFromJson(null), isEmpty);
      expect(TempWatchInfo.listFromJson([soak(), 'junk', {'id': ''}]).length, 1);
    });

    test('minutesLeft counts whole minutes up to the due time, never negative', () {
      final w = TempWatchInfo.fromJson(soak(reached: t0, due: t0 + 1200))!;
      expect(w.minutesLeft(t0 * 1000), 20);
      expect(w.minutesLeft((t0 + 1200 - 61) * 1000), 2);
      expect(w.minutesLeft((t0 + 5000) * 1000), 0);
    });
  });

  group('tempWatchTileLine', () {
    test('nothing armed = no line', () {
      expect(tempWatchTileLine(const [], 0), isNull);
    });

    test('a soaking watch shows the minutes left and the file', () {
      final line = tempWatchTileLine(
          TempWatchInfo.listFromJson([soak(reached: t0, due: t0 + 1200)]),
          (t0 + 300) * 1000)!;
      expect(line.kind, TempWatchTileKind.soaking);
      expect(line.id, 'app-soak');
      expect(line.minutesLeft, 15);
      expect(line.file, 'benchy.gcode');
    });

    test('a watch still heating says waiting', () {
      final line = tempWatchTileLine(TempWatchInfo.listFromJson([soak()]), t0 * 1000)!;
      expect(line.kind, TempWatchTileKind.waitingForTemp);
      expect(line.file, 'benchy.gcode');
    });

    test('the warm-up watch beats the cool-down one', () {
      final line = tempWatchTileLine(
          TempWatchInfo.listFromJson([cool(), soak()]), t0 * 1000)!;
      expect(line.kind, TempWatchTileKind.waitingForTemp);
    });

    test('only a cool-down armed', () {
      final line = tempWatchTileLine(TempWatchInfo.listFromJson([cool()]), t0 * 1000)!;
      expect(line.kind, TempWatchTileKind.coolDownArmed);
      expect(line.id, 'app-cool');
    });
  });

  group('cool-down goals + payloads', () {
    test('goals are the readings now plus the delta; no chamber = no goal', () {
      final g = coolDownGoals(bedNow: 24.3, chamberNow: 23.0);
      expect(g.bed, closeTo(29.3, 0.001));
      expect(g.chamber, closeTo(28.0, 0.001));
      expect(coolDownGoals(bedNow: 24, chamberNow: 0).chamber, isNull);
    });

    test('soak payload sets the bed, waits for bed + chamber, starts the file', () {
      final p = soakArmPayload(
          bed: 110, chamber: 45, soakMinutes: 20, file: 'abs/benchy.gcode', msg: 'done');
      expect(p['id'], 'app-soak');
      expect(p['set'], {'heater_bed': 110.0});
      expect(p['wait'], {'bed': 110.0, 'chamber': 45.0});
      expect(p['soak'], 20);
      expect(p['then_start'], 'abs/benchy.gcode');
    });

    test('an active chamber heater is set as well as waited for', () {
      final p = soakArmPayload(
          bed: 110, chamber: 45, chamberHeater: 'heater_generic chamber',
          soakMinutes: 0, file: 'a.gcode', msg: 'm');
      expect(p['set'], {'heater_bed': 110.0, 'heater_generic chamber': 45.0});
    });

    test('no chamber value = bed only', () {
      final p = soakArmPayload(bed: 60, soakMinutes: 5, file: 'a.gcode', msg: 'm');
      expect(p['set'], {'heater_bed': 60.0});
      expect(p['wait'], {'bed': 60.0});
    });

    test('cool payload is after-print with the delta', () {
      final p = coolArmPayload(msg: 'Ready');
      expect(p['id'], 'app-cool');
      expect(p['after_print'], isTrue);
      expect(p['cooldown_delta'], kCoolDownDeltaC);
      expect(p['msg'], 'Ready');
    });
  });
}
