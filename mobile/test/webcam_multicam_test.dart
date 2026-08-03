import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/models/printer_config.dart';
import 'package:moongate/services/printer_status_service.dart';

// v0.9.59 multicam: the plugin (0.6.22+) reports every enabled camera in
// /status `webcams`; older plugins only send the flat webcam_* fields. These
// tests lock the parse fallback, the uid/name selection rules, and the
// PrinterConfig persistence of the pick - the contracts the tile switcher
// stands on.
void main() {
  group('parseWebcamList', () {
    test('parses the 0.6.22 list, fields mapped per camera', () {
      final cams = PrinterStatusService.parseWebcamList({
        'webcams': [
          {
            'name':            'Nozzle',
            'uid':             'aaa-111',
            'snapshot_path':   '/webcam/?action=snapshot',
            'flip_horizontal': true,
            'rotation':        180,
            'target_fps':      30,
          },
          {
            'name':            'Phone',
            'uid':             'bbb-222',
            'snapshot_path':   '/webcam/?action=snapshot',
            'stream_external': 'http://192.168.0.107:8080/video',
          },
        ],
        // Legacy flat fields ride alongside on 0.6.22 - the list must win.
        'webcam_snapshot_path': '/webcam/?action=snapshot',
      });
      expect(cams, hasLength(2));
      expect(cams[0].name, 'Nozzle');
      expect(cams[0].key, 'aaa-111');
      expect(cams[0].flipH, isTrue);
      expect(cams[0].rotation, 180);
      expect(cams[0].targetFps, 30);
      expect(cams[1].streamExternal, 'http://192.168.0.107:8080/video');
    });

    test('legacy flat fields synthesise a single camera (old plugin)', () {
      final cams = PrinterStatusService.parseWebcamList({
        'webcam_snapshot_path':   '/webcam/?action=snapshot',
        'webcam_flip_vertical':   true,
        'webcam_rotation':        90,
        'webcam_target_fps':      20,
        'webcam_stream_external': 'http://192.168.0.50:8080/video',
      });
      expect(cams, hasLength(1));
      expect(cams[0].snapshotPath, '/webcam/?action=snapshot');
      expect(cams[0].flipV, isTrue);
      expect(cams[0].rotation, 90);
      expect(cams[0].targetFps, 20);
      expect(cams[0].streamExternal, 'http://192.168.0.50:8080/video');
      // No uid on the synthesised entry - its key is the (empty) name.
      expect(cams[0].uid, isNull);
    });

    test('no webcam info at all yields an empty list', () {
      expect(PrinterStatusService.parseWebcamList(null), isEmpty);
      expect(PrinterStatusService.parseWebcamList({'other': 1}), isEmpty);
    });

    test('junk list entries are skipped, junk fields defaulted', () {
      final cams = PrinterStatusService.parseWebcamList({
        'webcams': [
          'not-a-map',
          {'name': 'ok', 'rotation': null, 'target_fps': null},
        ],
      });
      expect(cams, hasLength(1));
      expect(cams[0].rotation, 0);
      expect(cams[0].targetFps, 15);
    });
  });

  group('selectWebcam', () {
    const cams = [
      PrinterWebcam(name: 'Nozzle',  uid: 'aaa'),
      PrinterWebcam(name: 'Chamber', uid: 'bbb'),
      PrinterWebcam(name: 'NoUid'),
    ];

    test('matches by uid', () {
      expect(PrinterStatusService.selectWebcam(cams, 'bbb')!.name, 'Chamber');
    });

    test('matches by name when the camera has no uid', () {
      expect(PrinterStatusService.selectWebcam(cams, 'NoUid')!.name, 'NoUid');
    });

    test('null / unknown key falls back to the first camera', () {
      expect(PrinterStatusService.selectWebcam(cams, null)!.name, 'Nozzle');
      expect(PrinterStatusService.selectWebcam(cams, 'gone')!.name, 'Nozzle');
    });

    test('empty list yields null', () {
      expect(PrinterStatusService.selectWebcam(const [], 'aaa'), isNull);
    });
  });

  group('PrinterConfig.selectedWebcam persistence', () {
    test('round-trips through toJson/fromJson', () {
      const config = PrinterConfig(
        id:             'id-1',
        name:           'Voron',
        selectedWebcam: 'bbb-222',
      );
      final back = PrinterConfig.fromJson(config.toJson());
      expect(back.selectedWebcam, 'bbb-222');
    });

    test('absent key parses as null (older backups)', () {
      const config = PrinterConfig(id: 'id-1', name: 'Voron');
      final json = config.toJson();
      expect(json.containsKey('selectedWebcam'), isFalse);
      expect(PrinterConfig.fromJson(json).selectedWebcam, isNull);
    });

    test('copyWith sets and clears via the sentinel', () {
      const config = PrinterConfig(id: 'id-1', name: 'Voron');
      final set = config.copyWith(selectedWebcam: 'aaa');
      expect(set.selectedWebcam, 'aaa');
      // Omitting the argument keeps the current value...
      expect(set.copyWith(name: 'Renamed').selectedWebcam, 'aaa');
      // ...while passing null explicitly clears it (back to camera 1).
      expect(set.copyWith(selectedWebcam: null).selectedWebcam, isNull);
    });
  });
}
