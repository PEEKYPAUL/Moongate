import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/models/heat_alerts.dart';

void main() {
  const t0 = 1000000; // an arbitrary "armed at" epoch ms
  const soon = t0 + 5 * 60 * 1000; // five minutes on, well past the grace
  const minute = 60 * 1000;

  HeatSoakArm arm(Map<String, double> targets,
          {bool multi = false, int soak = 0, int? reachedAt}) =>
      HeatSoakArm(
        armedAtMs:   t0,
        targets:     targets,
        multi:       multi,
        soakMinutes: soak,
        reachedAtMs: reachedAt,
      );

  group('evaluateHeatSoak - reaching temperature', () {
    test('fires at once when every set temperature reads its target and '
        'the soak time is 0', () {
      final v = evaluateHeatSoak(
        arm:   arm({'h0': 210, 'bed': 60}),
        live:  const {
          'h0':  HeaterReading(209.4, 210),
          'bed': HeaterReading(60.2, 60),
        },
        nowMs: soon,
      );
      expect(v, HeatSoakVerdict.fire);
    });

    test('starts the soak clock instead when a soak time is set', () {
      final v = evaluateHeatSoak(
        arm:   arm({'h0': 210, 'bed': 60}, soak: 20),
        live:  const {
          'h0':  HeaterReading(210, 210),
          'bed': HeaterReading(60, 60),
        },
        nowMs: soon,
      );
      expect(v, HeatSoakVerdict.reached);
    });

    test('waits while any set temperature is still ramping', () {
      final v = evaluateHeatSoak(
        arm:   arm({'h0': 210, 'bed': 60}),
        live:  const {
          'h0':  HeaterReading(210, 210),
          'bed': HeaterReading(48, 60),
        },
        nowMs: soon,
      );
      expect(v, HeatSoakVerdict.wait);
    });

    test('a reading within the margin counts as at temperature', () {
      expect(
        evaluateHeatSoak(
          arm:   arm({'h0': 210}),
          live:  const {'h0': HeaterReading(207.5, 210)},
          nowMs: soon,
        ),
        HeatSoakVerdict.fire,
      );
      expect(
        evaluateHeatSoak(
          arm:   arm({'h0': 210}),
          live:  const {'h0': HeaterReading(206.5, 210)},
          nowMs: soon,
        ),
        HeatSoakVerdict.wait,
      );
    });

    test('ignores heaters the sheet did not set', () {
      // Bed left alone at 0 - only the hotend was armed.
      final v = evaluateHeatSoak(
        arm:   arm({'h0': 210}),
        live:  const {
          'h0':  HeaterReading(210, 210),
          'bed': HeaterReading(22, 0),
        },
        nowMs: soon,
      );
      expect(v, HeatSoakVerdict.fire);
    });

    test('the live target is the truth, not the one the sheet sent', () {
      // A PRINT_START macro retargeted the hotend to 230 after the sheet's 210.
      expect(
        evaluateHeatSoak(
          arm:   arm({'h0': 210}),
          live:  const {'h0': HeaterReading(212, 230)},
          nowMs: soon,
        ),
        HeatSoakVerdict.wait,
      );
      expect(
        evaluateHeatSoak(
          arm:   arm({'h0': 210}),
          live:  const {'h0': HeaterReading(229, 230)},
          nowMs: soon,
        ),
        HeatSoakVerdict.fire,
      );
    });

    test('a zero target inside the grace window just waits', () {
      // The SET may not have landed in the poll that was already in flight.
      final v = evaluateHeatSoak(
        arm:   arm({'h0': 210}),
        live:  const {'h0': HeaterReading(25, 0)},
        nowMs: t0 + 10 * 1000,
      );
      expect(v, HeatSoakVerdict.wait);
    });

    test('a zero target after the grace window cancels (heaters off)', () {
      final v = evaluateHeatSoak(
        arm:   arm({'h0': 210, 'bed': 60}),
        live:  const {
          'h0':  HeaterReading(25, 0),
          'bed': HeaterReading(60, 60),
        },
        nowMs: soon,
      );
      expect(v, HeatSoakVerdict.cancel);
    });

    test('a missing reading waits (extra hotend not supplemented yet)', () {
      final v = evaluateHeatSoak(
        arm:   arm({'h0': 210, 'h1': 230}, multi: true),
        live:  const {'h0': HeaterReading(210, 210)},
        nowMs: soon,
      );
      expect(v, HeatSoakVerdict.wait);
    });

    test('an arm that never reached temperature goes stale without firing',
        () {
      final v = evaluateHeatSoak(
        arm:   arm({'h0': 210}),
        live:  const {'h0': HeaterReading(210, 210)},
        nowMs: t0 + kHeatSoakStaleMs + 1,
      );
      expect(v, HeatSoakVerdict.cancel);
    });

    test('an arm with nothing to wait for cancels', () {
      expect(
        evaluateHeatSoak(arm: arm({}), live: const {}, nowMs: soon),
        HeatSoakVerdict.cancel,
      );
    });

    test('multi-toolhead: every armed tool must arrive', () {
      final a = arm({'h0': 210, 'h1': 230, 'bed': 60}, multi: true);
      expect(
        evaluateHeatSoak(
          arm:   a,
          live:  const {
            'h0':  HeaterReading(210, 210),
            'h1':  HeaterReading(180, 230),
            'bed': HeaterReading(60, 60),
          },
          nowMs: soon,
        ),
        HeatSoakVerdict.wait,
      );
      expect(
        evaluateHeatSoak(
          arm:   a,
          live:  const {
            'h0':  HeaterReading(210, 210),
            'h1':  HeaterReading(228, 230),
            'bed': HeaterReading(60, 60),
          },
          nowMs: soon,
        ),
        HeatSoakVerdict.fire,
      );
    });
  });

  group('evaluateHeatSoak - the chamber', () {
    test('a passive chamber is judged against the value the sheet sent', () {
      // Passive sensor: target 0, so the typed 45° is the goal.
      expect(
        evaluateHeatSoak(
          arm:   arm({'bed': 100, 'chamber': 45}),
          live:  const {
            'bed':     HeaterReading(100, 100),
            'chamber': HeaterReading(38, 0),
          },
          nowMs: soon,
        ),
        HeatSoakVerdict.wait,
      );
      expect(
        evaluateHeatSoak(
          arm:   arm({'bed': 100, 'chamber': 45}),
          live:  const {
            'bed':     HeaterReading(100, 100),
            'chamber': HeaterReading(42.5, 0),
          },
          nowMs: soon,
        ),
        HeatSoakVerdict.fire,
      );
    });

    test('an active chamber heater reports a target of its own, which wins',
        () {
      expect(
        evaluateHeatSoak(
          arm:   arm({'bed': 100, 'chamber': 45}),
          live:  const {
            'bed':     HeaterReading(100, 100),
            'chamber': HeaterReading(46, 50),
          },
          nowMs: soon,
        ),
        HeatSoakVerdict.wait,
      );
    });

    test('a chamber reading missing from the poll waits, never fires', () {
      expect(
        evaluateHeatSoak(
          arm:   arm({'bed': 100, 'chamber': 45}),
          live:  const {'bed': HeaterReading(100, 100)},
          nowMs: soon,
        ),
        HeatSoakVerdict.wait,
      );
    });

    test('a passive chamber never triggers the heaters-off cancel', () {
      // Only real heaters carry the "target dropped to 0" signal.
      expect(
        evaluateHeatSoak(
          arm:   arm({'bed': 100, 'chamber': 45}, soak: 10,
              reachedAt: soon),
          live:  const {
            'bed':     HeaterReading(100, 100),
            'chamber': HeaterReading(40, 0),
          },
          nowMs: soon + 5 * minute,
        ),
        HeatSoakVerdict.wait,
      );
    });
  });

  group('evaluateHeatSoak - the soak clock', () {
    test('waits until the soak time has held, then fires', () {
      final a = arm({'bed': 100}, soak: 20, reachedAt: soon);
      const live = {'bed': HeaterReading(100, 100)};
      expect(evaluateHeatSoak(arm: a, live: live, nowMs: soon + 19 * minute),
          HeatSoakVerdict.wait);
      expect(evaluateHeatSoak(arm: a, live: live, nowMs: soon + 20 * minute),
          HeatSoakVerdict.fire);
    });

    test('a sag during the soak does not reset the clock', () {
      // Door opened: the bed reads low for a while. The clock keeps running.
      final a = arm({'bed': 100}, soak: 20, reachedAt: soon);
      expect(
        evaluateHeatSoak(
          arm:   a,
          live:  const {'bed': HeaterReading(80, 100)},
          nowMs: soon + 20 * minute,
        ),
        HeatSoakVerdict.fire,
      );
    });

    test('heaters switched off mid-soak cancel it', () {
      final a = arm({'bed': 100}, soak: 20, reachedAt: soon);
      expect(
        evaluateHeatSoak(
          arm:   a,
          live:  const {'bed': HeaterReading(90, 0)},
          nowMs: soon + 5 * minute,
        ),
        HeatSoakVerdict.cancel,
      );
    });

    test('a soak deadline noticed far too late is dropped, not fired', () {
      final a = arm({'bed': 100}, soak: 20, reachedAt: soon);
      expect(
        evaluateHeatSoak(
          arm:   a,
          live:  const {'bed': HeaterReading(100, 100)},
          nowMs: soon + 20 * minute + kHeatSoakLateMs + 1,
        ),
        HeatSoakVerdict.cancel,
      );
    });

    test('the arming stale window no longer applies once soaking', () {
      // Armed long ago, reached late, soak still within its own window.
      const reached = t0 + kHeatSoakStaleMs - minute;
      final a = arm({'bed': 100}, soak: 30, reachedAt: reached);
      expect(
        evaluateHeatSoak(
          arm:   a,
          live:  const {'bed': HeaterReading(100, 100)},
          nowMs: reached + 30 * minute,
        ),
        HeatSoakVerdict.fire,
      );
    });
  });

  group('roles', () {
    test('hotend roles round-trip their tool number; bed and chamber have none',
        () {
      expect(hotendRole(0), 'h0');
      expect(hotendRole(3), 'h3');
      expect(hotendIndexOf('h0'), 0);
      expect(hotendIndexOf('h12'), 12);
      expect(hotendIndexOf(bedRole), isNull);
      expect(hotendIndexOf(chamberRole), isNull);
      expect(hotendIndexOf('h'), isNull);
      expect(hotendIndexOf('hx'), isNull);
    });

    test('needsExtraHotends only for a tool beyond T0', () {
      expect(const HeatSoakArm(armedAtMs: t0, targets: {'h0': 210, 'bed': 60})
          .needsExtraHotends, isFalse);
      expect(const HeatSoakArm(armedAtMs: t0, targets: {'h1': 230})
          .needsExtraHotends, isTrue);
    });
  });

  group('HeatSoakArm json', () {
    test('round-trips, soak clock included', () {
      const a = HeatSoakArm(
        armedAtMs:   t0,
        targets:     {'h0': 210, 'bed': 60, 'chamber': 45},
        multi:       true,
        soakMinutes: 20,
        reachedAtMs: soon,
      );
      final back = HeatSoakArm.fromJson(a.toJson());
      expect(back, isNotNull);
      expect(back!.armedAtMs, t0);
      expect(back.targets, {'h0': 210.0, 'bed': 60.0, 'chamber': 45.0});
      expect(back.multi, isTrue);
      expect(back.soakMinutes, 20);
      expect(back.reachedAtMs, soon);
      expect(back.soaking, isTrue);
    });

    test('copyWith starts the soak clock without touching the rest', () {
      const a = HeatSoakArm(
          armedAtMs: t0, targets: {'bed': 60}, soakMinutes: 5);
      final s = a.copyWith(reachedAtMs: soon);
      expect(s.reachedAtMs, soon);
      expect(s.soakMinutes, 5);
      expect(s.targets, {'bed': 60.0});
      expect(a.soaking, isFalse);
    });

    test('drops malformed or empty arms', () {
      expect(HeatSoakArm.fromJson(null), isNull);
      expect(HeatSoakArm.fromJson('nope'), isNull);
      expect(HeatSoakArm.fromJson({'at': 1}), isNull);
      expect(HeatSoakArm.fromJson({'at': 1, 'targets': {}}), isNull);
      // A 0 target is "heater off" - nothing to reach - and is not kept.
      expect(HeatSoakArm.fromJson({'at': 1, 'targets': {'h0': 0}}), isNull);
      expect(HeatSoakArm.fromJson({'at': 'x', 'targets': {'h0': 210}}),
          isNull);
    });

    test('tolerates missing optional fields and integer temps', () {
      final back = HeatSoakArm.fromJson({'at': 5, 'targets': {'bed': 60}});
      expect(back!.multi, isFalse);
      expect(back.soakMinutes, 0);
      expect(back.reachedAtMs, isNull);
      expect(back.targets['bed'], 60.0);
    });
  });

  group('heatSoakSummary', () {
    test('single hotend reads Hotend / Bed / Chamber with the live targets',
        () {
      final s = heatSoakSummary(
        arm({'chamber': 45, 'bed': 60, 'h0': 210}),
        const {
          'h0':      HeaterReading(210.4, 210),
          'bed':     HeaterReading(60.1, 60),
          'chamber': HeaterReading(45.6, 0),
        },
        hotendLabel:  'Hotend',
        bedLabel:     'Bed',
        chamberLabel: 'Chamber',
      );
      expect(s, 'Hotend 210° · Bed 60° · Chamber 45°');
    });

    test('multi-toolhead reads T0 / T1 in tool order, bed after', () {
      final s = heatSoakSummary(
        arm({'bed': 60, 'h1': 230, 'h0': 210}, multi: true),
        const {
          'h0':  HeaterReading(210, 210),
          'h1':  HeaterReading(230, 230),
          'bed': HeaterReading(60, 60),
        },
        hotendLabel:  'Hotend',
        bedLabel:     'Bed',
        chamberLabel: 'Chamber',
      );
      expect(s, 'T0 210° · T1 230° · Bed 60°');
    });

    test('falls back to the armed value when the poll has no reading', () {
      final s = heatSoakSummary(
        arm({'h0': 215}),
        const {},
        hotendLabel:  'Hotend',
        bedLabel:     'Bed',
        chamberLabel: 'Chamber',
      );
      expect(s, 'Hotend 215°');
    });
  });
}
