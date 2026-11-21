import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/models/widget_snapshot.dart';
import 'package:moongate/services/deep_link_service.dart';

WidgetPrinter _p(String id, String state, {double progress = 0}) => WidgetPrinter(
      id:         id,
      name:       'Printer $id',
      state:      state,
      stateLabel: state,
      progress:   progress,
    );

void main() {
  group('WidgetSnapshot - the JSON the Glance widget reads', () {
    test('round-trips every field, numbers staying numeric', () {
      const snap = WidgetSnapshot(
        updatedAt:  1763640000000,
        monitoring: true,
        featured:   1,
        strings:    {WidgetStrings.updatedAt: 'Updated {n}'},
        printers: [
          WidgetPrinter(
            id: 'a', name: 'Voron', state: 'standby', stateLabel: 'Ready',
            hotend: 24.4, bed: 23.1,
          ),
          WidgetPrinter(
            id:             'b',
            name:           'Micron+',
            state:          'printing',
            stateLabel:     'Printing',
            progress:       0.42,
            remainingSec:   3900,
            remainingLabel: '~1h05m',
            finishClock:    '13:20',
            filename:       'benchy.gcode',
            layerLabel:     'Layer 84 / 200',
            hotend:         245,
            hotendTarget:   245,
            bed:            105,
            bedTarget:      105,
            chamber:        48,
          ),
        ],
      );

      final back = WidgetSnapshot.decode(snap.encode())!;
      expect(back.updatedAt, 1763640000000);
      expect(back.monitoring, isTrue);
      expect(back.featured, 1);
      expect(back.strings[WidgetStrings.updatedAt], 'Updated {n}');
      expect(back.printers, hasLength(2));

      final b = back.printers[1];
      expect(b.id, 'b');
      expect(b.state, 'printing');
      expect(b.stateLabel, 'Printing');
      expect(b.progress, closeTo(0.42, 1e-9));
      expect(b.remainingSec, 3900);
      expect(b.remainingLabel, '~1h05m');
      expect(b.finishClock, '13:20');
      expect(b.filename, 'benchy.gcode');
      expect(b.layerLabel, 'Layer 84 / 200');
      expect(b.hotend, 245);
      expect(b.chamber, 48);

      final a = back.printers[0];
      expect(a.remainingSec, isNull);
      expect(a.finishClock, isNull);
      expect(a.filename, isNull);
    });

    test('carries the schema version and each printer\'s dashboard rank', () {
      final j = jsonDecode(WidgetSnapshot(
        updatedAt:  1,
        monitoring: true,
        featured:   0,
        printers:   [_p('e', 'error'), _p('p', 'printing'), _p('o', 'offline')],
      ).encode()) as Map<String, dynamic>;
      expect(j['v'], kWidgetSnapshotVersion);
      final ranks = [for (final p in j['printers'] as List) p['rank']];
      expect(ranks, [0, 1, 4]);
    });

    test('unknown optional keys are simply absent from the JSON', () {
      final j = jsonDecode(jsonEncode(_p('x', 'standby').toJson()))
          as Map<String, dynamic>;
      expect(j.containsKey('remainingSec'), isFalse);
      expect(j.containsKey('finishClock'), isFalse);
      expect(j.containsKey('layerLabel'), isFalse);
      expect(j['progress'], 0);
    });

    test('decode rejects garbage and newer schemas, tolerates missing fields', () {
      expect(WidgetSnapshot.decode(null), isNull);
      expect(WidgetSnapshot.decode(''), isNull);
      expect(WidgetSnapshot.decode('not json'), isNull);
      expect(WidgetSnapshot.decode('[1,2]'), isNull);
      expect(
          WidgetSnapshot.decode('{"v": ${kWidgetSnapshotVersion + 1}}'), isNull);
      final sparse = WidgetSnapshot.decode('{"v": 1}')!;
      expect(sparse.printers, isEmpty);
      expect(sparse.monitoring, isFalse);
      expect(sparse.strings, isEmpty);
    });

    test('asStale keeps the data and only drops the live flag', () {
      final live = WidgetSnapshot(
        updatedAt:  42,
        monitoring: true,
        featured:   0,
        printers:   [_p('a', 'printing', progress: 0.5)],
        strings:    const {WidgetStrings.noData: 'x'},
      );
      final stale = live.asStale();
      expect(stale.monitoring, isFalse);
      expect(stale.updatedAt, 42);
      expect(stale.printers.single.progress, 0.5);
      expect(stale.strings, live.strings);
    });
  });

  group('pickFeaturedIndex - the printer the small layouts show', () {
    test('error beats printing beats ready beats offline', () {
      final list = [
        _p('offline', 'offline'),
        _p('ready', 'standby'),
        _p('printing', 'printing'),
        _p('error', 'error'),
      ];
      expect(pickFeaturedIndex(list), 3);
      expect(pickFeaturedIndex(list.sublist(0, 3)), 2);
      expect(pickFeaturedIndex(list.sublist(0, 2)), 1);
      expect(pickFeaturedIndex(list.sublist(0, 1)), 0);
    });

    test('paused and heating sit in the printing tier', () {
      expect(pickFeaturedIndex([_p('a', 'standby'), _p('b', 'paused')]), 1);
      expect(pickFeaturedIndex([_p('a', 'standby'), _p('b', 'heating')]), 1);
    });

    test('ties keep the list order (the dashboard arrangement decides)', () {
      expect(pickFeaturedIndex([_p('a', 'printing'), _p('b', 'printing')]), 0);
      expect(pickFeaturedIndex([_p('a', 'standby'), _p('b', 'standby')]), 0);
    });

    test('an empty fleet picks index 0 harmlessly', () {
      expect(pickFeaturedIndex(const []), 0);
    });
  });

  group('DeepLinkService - the widget\'s tap link', () {
    test('the dashboard link is the one widget link, on the pairing scheme', () {
      final uri = Uri.parse('moongate://dashboard');
      expect(DeepLinkService.isWidgetUri(uri), isTrue);
      // Host only: a path here would reach go_router as the platform's
      // initial route (the first test build's printer links crashed on that).
      expect(uri.path, isEmpty);
      expect(DeepLinkService.isWidgetUri(Uri.parse('moongate://pair?v=3')), isFalse);
      expect(DeepLinkService.isWidgetUri(Uri.parse('https://dashboard')), isFalse);
    });

    test('the retired per-printer links are no longer widget links', () {
      expect(DeepLinkService.isWidgetUri(Uri.parse('moongate://printer/abc-123')),
          isFalse);
      expect(DeepLinkService.isWidgetUri(Uri.parse('moongate://printer?id=abc')),
          isFalse);
    });

    test('widget links never read as pairing payloads', () {
      expect(DeepLinkService.isPairingUri(Uri.parse('moongate://dashboard')), isFalse);
    });
  });
}
