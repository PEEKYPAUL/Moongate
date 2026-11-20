import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/models/notif_events.dart';
import 'package:moongate/models/notif_fields.dart';

void main() {
  group('milestoneIndex - which progress step a print has reached', () {
    test('off yields nothing', () {
      expect(milestoneIndex(MilestoneMode.off, 0.5, 3600), isNull);
    });

    test('25% steps: 0 before the first, then 1..3, never the 100% step', () {
      expect(milestoneIndex(MilestoneMode.every25, 0.00, 0), 0);
      expect(milestoneIndex(MilestoneMode.every25, 0.24, 0), 0);
      expect(milestoneIndex(MilestoneMode.every25, 0.25, 0), 1);
      expect(milestoneIndex(MilestoneMode.every25, 0.51, 0), 2);
      expect(milestoneIndex(MilestoneMode.every25, 0.75, 0), 3);
      expect(milestoneIndex(MilestoneMode.every25, 0.99, 0), 3);
      expect(milestoneIndex(MilestoneMode.every25, 1.00, 0), 3);
    });

    test('10% steps top out at 90', () {
      expect(milestoneIndex(MilestoneMode.every10, 0.09, 0), 0);
      expect(milestoneIndex(MilestoneMode.every10, 0.10, 0), 1);
      expect(milestoneIndex(MilestoneMode.every10, 0.95, 0), 9);
      expect(milestoneIndex(MilestoneMode.every10, 1.00, 0), 9);
    });

    test('hourly counts whole hours of print time', () {
      expect(milestoneIndex(MilestoneMode.hourly, 0.5, 0), 0);
      expect(milestoneIndex(MilestoneMode.hourly, 0.5, 3599), 0);
      expect(milestoneIndex(MilestoneMode.hourly, 0.5, 3600), 1);
      expect(milestoneIndex(MilestoneMode.hourly, 0.5, 7300), 2);
    });

    test('out-of-range progress is clamped', () {
      expect(milestoneIndex(MilestoneMode.every25, -0.1, 0), 0);
      expect(milestoneIndex(MilestoneMode.every25, 1.7, 0), 3);
    });
  });

  group('shouldAlertMilestone - the baseline rule', () {
    test('the first look at a print is a baseline, never an alert', () {
      expect(shouldAlertMilestone(null, 0), isFalse);
      expect(shouldAlertMilestone(null, 2), isFalse); // service started at 60%
    });

    test('only a step UP alerts', () {
      expect(shouldAlertMilestone(0, 1), isTrue);
      expect(shouldAlertMilestone(1, 1), isFalse);
      expect(shouldAlertMilestone(2, 1), isFalse); // file-relative dip
    });
  });

  group('milestonePercent - the label for a step', () {
    test('percent modes label the step, hourly has none', () {
      expect(milestonePercent(MilestoneMode.every25, 2), 50);
      expect(milestonePercent(MilestoneMode.every10, 7), 70);
      expect(milestonePercent(MilestoneMode.hourly, 2), isNull);
      expect(milestonePercent(MilestoneMode.off, 1), isNull);
    });
  });

  test('MilestoneMode.fromPref round-trips and defaults to off', () {
    for (final m in MilestoneMode.values) {
      expect(MilestoneMode.fromPref(m.name), m);
    }
    expect(MilestoneMode.fromPref(null), MilestoneMode.off);
    expect(MilestoneMode.fromPref('weekly'), MilestoneMode.off);
  });
}
