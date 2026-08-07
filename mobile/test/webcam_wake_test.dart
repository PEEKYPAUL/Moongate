import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moongate/l10n/app_localizations.dart';
import 'package:moongate/services/webcam_fetch_diag.dart';
import 'package:moongate/widgets/webcam_view.dart';

// The wake-window state machine: spinner while the first frame is still being
// chased, honest placeholder after the window expires, reset on a URL change.
// In the test environment every HTTP request answers 400 (flutter_test's
// default HttpOverrides), so no frame ever arrives - exactly the dead-camera
// scenario the spinner exists for.

Widget _host(Widget child) => ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SizedBox(width: 200, height: 200, child: child)),
      ),
    );

Future<void> _teardown(WidgetTester tester) async {
  // Dispose the view, then drain the fetch loop's pending delay so the test
  // ends with no timers outstanding.
  await tester.pumpWidget(_host(const SizedBox()));
  await tester.pump(const Duration(seconds: 40));
}

void main() {
  setUp(WebcamFetchDiag.reset);

  testWidgets('waking spinner shows, then gives way to the placeholder',
      (tester) async {
    await tester.pumpWidget(_host(const WebcamView(
      webcamSnapshotUrl: 'http://192.0.2.1/snapshot',
      uiType: 'mainsail',
    )));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Camera waking up…'), findsOneWidget);

    // Ride past the wake window - the spinner must yield to the plain logo.
    await tester.pump(const Duration(seconds: 30));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Camera waking up…'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('no URL means no spinner - straight to the placeholder',
      (tester) async {
    await tester.pumpWidget(_host(const WebcamView(uiType: 'mainsail')));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Camera waking up…'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('a changed URL re-arms the wake window after expiry',
      (tester) async {
    await tester.pumpWidget(_host(const WebcamView(
      webcamSnapshotUrl: 'http://192.0.2.1/snapshot',
      uiType: 'mainsail',
    )));
    await tester.pump(const Duration(seconds: 30));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Transport flips (e.g. LAN -> tunnel): a fresh URL is a fresh chance.
    await tester.pumpWidget(_host(const WebcamView(
      webcamSnapshotUrl: 'http://192.0.2.2/snapshot',
      uiType: 'mainsail',
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('a token-only URL change does not resurrect an expired spinner',
      (tester) async {
    await tester.pumpWidget(_host(const WebcamView(
      webcamSnapshotUrl:
          'https://pi.example/mg-extcam?u=http%3A%2F%2F192.168.1.84%2F&mg_token=aaa',
      uiType: 'mainsail',
    )));
    await tester.pump(const Duration(seconds: 30));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // The mint rotates the token under the same camera - that must not be
    // treated as a new camera (the field failure mode: the spinner returning
    // forever for a dead address on every token refresh).
    await tester.pumpWidget(_host(const WebcamView(
      webcamSnapshotUrl:
          'https://pi.example/mg-extcam?u=http%3A%2F%2F192.168.1.84%2F&mg_token=bbb',
      uiType: 'mainsail',
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // A genuinely different relay target IS a new camera - fresh window.
    await tester.pumpWidget(_host(const WebcamView(
      webcamSnapshotUrl:
          'https://pi.example/mg-extcam?u=http%3A%2F%2F192.168.1.83%2F&mg_token=bbb',
      uiType: 'mainsail',
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('a run of hard failures on record skips the spinner on remount',
      (tester) async {
    const url = 'http://192.0.2.7/snapshot';
    for (var i = 0; i < 6; i++) {
      WebcamFetchDiag.record('deadcam',
          url: url, external: true, result: 'http 502');
    }

    await tester.pumpWidget(_host(const WebcamView(
      webcamSnapshotUrl: url,
      printerId: 'deadcam',
      uiType: 'mainsail',
    )));
    await tester.pump(const Duration(milliseconds: 300));

    // No fresh 25 s of pretending - straight to the honest message.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Camera unreachable, check its address'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets(
      'an outdated plugin turns the unreachable message into the update hint',
      (tester) async {
    // Old plugins have served broken camera info (0.6.16's _get_webcam_info
    // bug) - "check its address" sends that user hunting in exactly the
    // wrong place, so the message must name the plugin instead.
    const url = 'http://192.0.2.9/snapshot';
    for (var i = 0; i < 6; i++) {
      WebcamFetchDiag.record('oldplugincam',
          url: url, external: true, result: 'http 502');
    }

    await tester.pumpWidget(_host(const WebcamView(
      webcamSnapshotUrl: url,
      printerId: 'oldplugincam',
      pluginOutdated: true,
      uiType: 'mainsail',
    )));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
        find.text("Camera unreachable. The printer's plugin is out of date, "
            'updating it may fix the camera.'),
        findsOneWidget);
    expect(find.text('Camera unreachable, check its address'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('soft failures (a genuinely waking camera) still get a spinner',
      (tester) async {
    const url = 'http://192.0.2.8/snapshot';
    for (var i = 0; i < 6; i++) {
      WebcamFetchDiag.record('wakingcam',
          url: url, external: true, result: 'timeout');
    }

    await tester.pumpWidget(_host(const WebcamView(
      webcamSnapshotUrl: url,
      printerId: 'wakingcam',
      uiType: 'mainsail',
    )));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('natural expiry with failures on record shows the message',
      (tester) async {
    // With a printerId, the widget's own failing fetches (the test
    // environment answers every request with 400) land in the diag - after
    // the window expires the tile must say so, not show a logo that reads
    // as still loading.
    await tester.pumpWidget(_host(const WebcamView(
      webcamSnapshotUrl: 'http://192.0.2.9/snapshot',
      printerId: 'expiringcam',
      uiType: 'mainsail',
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Camera unreachable, check its address'), findsOneWidget);

    await _teardown(tester);
  });
}
