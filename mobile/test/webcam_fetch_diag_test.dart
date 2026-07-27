import 'package:flutter_test/flutter_test.dart';

import 'package:moongate/services/webcam_fetch_diag.dart';

// The session-wide fetch history behind the wake window's honesty: the relay
// target surfaced for bug reports, and the hard-vs-soft failure split that
// decides whether a remounting tile deserves a fresh spinner.

void main() {
  setUp(WebcamFetchDiag.reset);

  test('mg-extcam target is surfaced, redacted, and cleared on LAN flip', () {
    const relay =
        'https://pi.example/mg-extcam?u=http%3A%2F%2F192.168.1.84%2Fwebcam%3Ftoken%3Dsecret&mg_token=xyz';
    WebcamFetchDiag.record('p1', url: relay, external: true, result: 'http 502');
    expect(WebcamFetchDiag.report('p1')!['target'], 'http://192.168.1.84/webcam');

    // Back on LAN the URL IS the camera - no stale relay target may linger.
    WebcamFetchDiag.record('p1',
        url: 'http://192.168.1.84/webcam', external: true, result: 'ok');
    expect(WebcamFetchDiag.report('p1')!.containsKey('target'), isFalse);
  });

  test('hard and soft failures are counted apart, both reset on success', () {
    const url = 'http://192.0.2.5/snap';
    WebcamFetchDiag.record('p2', url: url, external: false, result: 'timeout');
    WebcamFetchDiag.record('p2', url: url, external: false, result: 'http 502');
    WebcamFetchDiag.record('p2', url: url, external: false, result: 'error');
    expect(WebcamFetchDiag.consecutiveFailures('p2', url), 3);
    expect(WebcamFetchDiag.consecutiveHardFailures('p2', url), 2);

    // A soft failure breaks a hard run - a camera that alternates 502s with
    // timeouts is flaky, not provably dead.
    WebcamFetchDiag.record('p2', url: url, external: false, result: 'empty');
    expect(WebcamFetchDiag.consecutiveFailures('p2', url), 4);
    expect(WebcamFetchDiag.consecutiveHardFailures('p2', url), 0);

    WebcamFetchDiag.record('p2', url: url, external: false, result: 'ok');
    expect(WebcamFetchDiag.consecutiveFailures('p2', url), 0);
    expect(WebcamFetchDiag.consecutiveHardFailures('p2', url), 0);
  });

  test('counters answer zero for a different URL or unknown printer', () {
    const url = 'http://192.0.2.5/snap';
    WebcamFetchDiag.record('p3', url: url, external: false, result: 'http 404');
    expect(WebcamFetchDiag.consecutiveHardFailures('p3', url), 1);
    expect(
        WebcamFetchDiag.consecutiveHardFailures('p3', 'http://192.0.2.6/snap'),
        0);
    expect(WebcamFetchDiag.consecutiveHardFailures('nobody', url), 0);
    expect(WebcamFetchDiag.consecutiveHardFailures(null, url), 0);
  });
}
