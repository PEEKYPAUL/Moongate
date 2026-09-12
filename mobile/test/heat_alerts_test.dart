import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/models/heat_alerts.dart';

void main() {
  const t0 = 1000000; // an arbitrary "armed at" epoch ms
  const soon = t0 + 5 * 60 * 1000; // five minutes on, well past the grace

  AtTempArm arm(Map<String, double> targets, {bool multi = false}) =>
      AtTempArm(armedAtMs: t0, targets: targets, multi: multi);

  group('evaluateAtTemp', () {
    test('fires once every armed heater reads its target', () {
      final v = evaluateAtTemp(
        arm:   arm({'h0': 210, 'bed': 60}),
        live:  const {
          'h0':  HeaterReading(209.4, 210),
          'bed': HeaterReading(60.2, 60),
        },
        nowMs: soon,
      );
      expect(v, AtTempVerdict.fire);
    });

    test('waits while any armed heater is still ramping', () {
      final v = evaluateAtTemp(
        arm:   arm({'h0': 210, 'bed': 60}),
        live:  const {
          'h0':  HeaterReading(210, 210),
          'bed': HeaterReading(48, 60),
        },
        nowMs: soon,
      );
      expect(v, AtTempVerdict.wait);
    });

    test('a reading within the margin counts as at temperature', () {
      expect(
        evaluateAtTemp(
          arm:   arm({'h0': 210}),
          live:  const {'h0': HeaterReading(207.5, 210)},
          nowMs: soon,
        ),
        AtTempVerdict.fire,
      );
      expect(
        evaluateAtTemp(
          arm:   arm({'h0': 210}),
          live:  const {'h0': HeaterReading(206.5, 210)},
          nowMs: soon,
        ),
        AtTempVerdict.wait,
      );
    });

    test('ignores heaters the sheet did not set', () {
      // Bed left alone at 0 - only the hotend was armed.
      final v = evaluateAtTemp(
        arm:   arm({'h0': 210}),
        live:  const {
          'h0':  HeaterReading(210, 210),
          'bed': HeaterReading(22, 0),
        },
        nowMs: soon,
      );
      expect(v, AtTempVerdict.fire);
    });

    test('the live target is the truth, not the one the sheet sent', () {
      // A PRINT_START macro retargeted the hotend to 230 after the sheet's 210.
      expect(
        evaluateAtTemp(
          arm:   arm({'h0': 210}),
          live:  const {'h0': HeaterReading(212, 230)},
          nowMs: soon,
        ),
        AtTempVerdict.wait,
      );
      expect(
        evaluateAtTemp(
          arm:   arm({'h0': 210}),
          live:  const {'h0': HeaterReading(229, 230)},
          nowMs: soon,
        ),
        AtTempVerdict.fire,
      );
    });

    test('a zero target inside the grace window just waits', () {
      // The SET may not have landed in the poll that was already in flight.
      final v = evaluateAtTemp(
        arm:   arm({'h0': 210}),
        live:  const {'h0': HeaterReading(25, 0)},
        nowMs: t0 + 10 * 1000,
      );
      expect(v, AtTempVerdict.wait);
    });

    test('a zero target after the grace window cancels (heaters off)', () {
      final v = evaluateAtTemp(
        arm:   arm({'h0': 210, 'bed': 60}),
        live:  const {
          'h0':  HeaterReading(25, 0),
          'bed': HeaterReading(60, 60),
        },
        nowMs: soon,
      );
      expect(v, AtTempVerdict.cancel);
    });

    test('a missing reading waits (extra hotend not supplemented yet)', () {
      final v = evaluateAtTemp(
        arm:   arm({'h0': 210, 'h1': 230}, multi: true),
        live:  const {'h0': HeaterReading(210, 210)},
        nowMs: soon,
      );
      expect(v, AtTempVerdict.wait);
    });

    test('a stale arm cancels without firing, even if at temperature', () {
      final v = evaluateAtTemp(
        arm:   arm({'h0': 210}),
        live:  const {'h0': HeaterReading(210, 210)},
        nowMs: t0 + kAtTempStaleMs + 1,
      );
      expect(v, AtTempVerdict.cancel);
    });

    test('an arm with nothing to wait for cancels', () {
      expect(
        evaluateAtTemp(arm: arm({}), live: const {}, nowMs: soon),
        AtTempVerdict.cancel,
      );
    });

    test('multi-toolhead: every armed tool must arrive', () {
      final a = arm({'h0': 210, 'h1': 230, 'bed': 60}, multi: true);
      expect(
        evaluateAtTemp(
          arm:   a,
          live:  const {
            'h0':  HeaterReading(210, 210),
            'h1':  HeaterReading(180, 230),
            'bed': HeaterReading(60, 60),
          },
          nowMs: soon,
        ),
        AtTempVerdict.wait,
      );
      expect(
        evaluateAtTemp(
          arm:   a,
          live:  const {
            'h0':  HeaterReading(210, 210),
            'h1':  HeaterReading(228, 230),
            'bed': HeaterReading(60, 60),
          },
          nowMs: soon,
        ),
        AtTempVerdict.fire,
      );
    });
  });

  group('roles', () {
    test('hotend roles round-trip their tool number; bed has none', () {
      expect(hotendRole(0), 'h0');
      expect(hotendRole(3), 'h3');
      expect(hotendIndexOf('h0'), 0);
      expect(hotendIndexOf('h12'), 12);
      expect(hotendIndexOf(bedRole), isNull);
      expect(hotendIndexOf('h'), isNull);
      expect(hotendIndexOf('hx'), isNull);
    });

    test('needsExtraHotends only for a tool beyond T0', () {
      expect(const AtTempArm(armedAtMs: t0, targets: {'h0': 210, 'bed': 60})
          .needsExtraHotends, isFalse);
      expect(const AtTempArm(armedAtMs: t0, targets: {'h1': 230})
          .needsExtraHotends, isTrue);
    });
  });

  group('AtTempArm json', () {
    test('round-trips', () {
      const a = AtTempArm(
          armedAtMs: t0, targets: {'h0': 210, 'bed': 60}, multi: true);
      final back = AtTempArm.fromJson(a.toJson());
      expect(back, isNotNull);
      expect(back!.armedAtMs, t0);
      expect(back.targets, {'h0': 210.0, 'bed': 60.0});
      expect(back.multi, isTrue);
    });

    test('drops malformed or empty arms', () {
      expect(AtTempArm.fromJson(null), isNull);
      expect(AtTempArm.fromJson('nope'), isNull);
      expect(AtTempArm.fromJson({'at': 1}), isNull);
      expect(AtTempArm.fromJson({'at': 1, 'targets': {}}), isNull);
      // A 0 target is "heater off" - nothing to reach - and is not kept.
      expect(AtTempArm.fromJson({'at': 1, 'targets': {'h0': 0}}), isNull);
      expect(AtTempArm.fromJson({'at': 'x', 'targets': {'h0': 210}}), isNull);
    });

    test('tolerates a missing multi flag and integer temps', () {
      final back = AtTempArm.fromJson({'at': 5, 'targets': {'bed': 60}});
      expect(back!.multi, isFalse);
      expect(back.targets['bed'], 60.0);
    });
  });

  group('atTempSummary', () {
    test('single hotend reads Hotend / Bed with the live targets', () {
      final s = atTempSummary(
        arm({'bed': 60, 'h0': 210}),
        const {
          'h0':  HeaterReading(210.4, 210),
          'bed': HeaterReading(60.1, 60),
        },
        hotendLabel: 'Hotend',
        bedLabel:    'Bed',
      );
      expect(s, 'Hotend 210° · Bed 60°');
    });

    test('multi-toolhead reads T0 / T1 in tool order, bed last', () {
      final s = atTempSummary(
        arm({'bed': 60, 'h1': 230, 'h0': 210}, multi: true),
        const {
          'h0':  HeaterReading(210, 210),
          'h1':  HeaterReading(230, 230),
          'bed': HeaterReading(60, 60),
        },
        hotendLabel: 'Hotend',
        bedLabel:    'Bed',
      );
      expect(s, 'T0 210° · T1 230° · Bed 60°');
    });

    test('falls back to the armed target when the poll has no reading', () {
      final s = atTempSummary(
        arm({'h0': 215}),
        const {},
        hotendLabel: 'Hotend',
        bedLabel:    'Bed',
      );
      expect(s, 'Hotend 215°');
    });
  });
}
