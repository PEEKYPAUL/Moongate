import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moongate/l10n/app_localizations.dart';
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
}
