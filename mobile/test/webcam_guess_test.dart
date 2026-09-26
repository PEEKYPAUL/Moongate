import 'package:flutter_test/flutter_test.dart';

import 'package:moongate/services/printer_status_service.dart';

// A printer with no camera entry in Moonraker still gets the MainsailOS
// default snapshot path from the plugin (its _defaults), and the app tries
// it quietly in case a stock Crowsnest answers there. When it does not, that
// is "no camera" (the logo), never "check its address" - there is no address
// to check. The K3 field case, 26/09/2026: no webcam, crowsnest stopped, the
// default path answering 502, and the tile telling Paul to check an address.
void main() {
  const defaultPath = '/webcam/?action=snapshot';

  group('webcamIsUnconfiguredGuess', () {
    test('an empty 0.6.22+ list with only the default path is a guess', () {
      expect(
          PrinterStatusService.webcamIsUnconfiguredGuess({
            'webcams':              <Object>[],
            'webcam_snapshot_path': defaultPath,
          }),
          isTrue);
    });

    test('a real entry is never a guess, even one at the default path', () {
      expect(
          PrinterStatusService.webcamIsUnconfiguredGuess({
            'webcams': [
              {'name': 'Cam1', 'snapshot_path': defaultPath},
            ],
            'webcam_snapshot_path': defaultPath,
          }),
          isFalse);
    });

    test('an external camera in the flat fields is configured', () {
      expect(
          PrinterStatusService.webcamIsUnconfiguredGuess({
            'webcams':                <Object>[],
            'webcam_snapshot_path':   defaultPath,
            'webcam_stream_external': 'http://192.168.0.107:8080/video',
          }),
          isFalse);
      expect(
          PrinterStatusService.webcamIsUnconfiguredGuess({
            'webcams':                  <Object>[],
            'webcam_snapshot_path':     defaultPath,
            'webcam_snapshot_external': 'http://192.168.1.50:1984/api/frame.jpeg?src=cam',
          }),
          isFalse);
    });

    test('an older plugin sends no list, so its default path is taken as real',
        () {
      expect(
          PrinterStatusService.webcamIsUnconfiguredGuess({
            'webcam_snapshot_path': defaultPath,
          }),
          isFalse);
    });

    test('a non-default path beside an empty list is not the plugin default',
        () {
      expect(
          PrinterStatusService.webcamIsUnconfiguredGuess({
            'webcams':              <Object>[],
            'webcam_snapshot_path': '/cam2/?action=snapshot',
          }),
          isFalse);
    });

    test('no status at all', () {
      expect(PrinterStatusService.webcamIsUnconfiguredGuess(null), isFalse);
      expect(PrinterStatusService.webcamIsUnconfiguredGuess({}), isFalse);
    });
  });
}
