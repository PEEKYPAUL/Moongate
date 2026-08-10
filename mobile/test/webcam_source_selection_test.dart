import 'package:flutter_test/flutter_test.dart';

import 'package:moongate/services/printer_status_service.dart';

// resolveWebcamSource: the per-poll camera pick - override > auto-detected >
// Pi snapshot path - and the dead-camera fallbacks: a hard-failing custom
// URL set aside in favour of the printer's own camera (the field case: a
// forgotten phone-webcam experiment masking a perfectly good camera), and a
// hard-failing printer camera set aside for the default snapshot path (the
// field case: a Mainsail webcam entry still pointing at go2rtc after a
// switch to Crowsnest). Pure function, so the whole matrix runs without a
// service, registry, or network.

void main() {
  WebcamSource pick({
    String? custom,
    String? autoSnapshot,
    String? autoStream,
    String? path,
    bool isLan = true,
    bool dead = false,
    bool latched = false,
    bool nativeDead = false,
    bool nativeLatched = false,
  }) =>
      resolveWebcamSource(
        customUrl:     custom,
        autoSnapshot:  autoSnapshot,
        autoStream:    autoStream,
        snapshotPath:  path,
        baseUrl:       isLan ? 'http://192.168.1.50' : 'https://pi.example',
        isLan:         isLan,
        accessToken:   'tok en', // space keeps the encoding visible
        customDead:    dead,
        customLatched: latched,
        nativeDead:    nativeDead,
        nativeLatched: nativeLatched,
      );

  test('healthy override outranks the auto camera and the snapshot path', () {
    final s = pick(
        custom: 'http://192.168.1.84:8080/video',
        autoSnapshot: 'http://192.168.1.50:1984/api/frame.jpeg?src=cam',
        path: '/webcam/?action=snapshot');
    expect(s.url, 'http://192.168.1.84:8080/video');
    expect(s.isExternal, isTrue);
    expect(s.customCameraDown, isFalse);
  });

  test('dead override falls back to the auto camera, visibly', () {
    final s = pick(
        custom: 'http://192.168.1.84:8080/video',
        autoSnapshot: 'http://192.168.1.50:1984/api/frame.jpeg?src=cam',
        dead: true);
    expect(s.url, 'http://192.168.1.50:1984/api/frame.jpeg?src=cam');
    expect(s.isExternal, isTrue);
    expect(s.customCameraDown, isTrue);
  });

  test('dead override falls back to the snapshot path when that is all', () {
    final s = pick(
        custom: 'http://192.168.1.84:8080/video',
        path: '/webcam/?action=snapshot',
        dead: true);
    expect(s.url, 'http://192.168.1.50/webcam/?action=snapshot');
    expect(s.isExternal, isFalse);
    expect(s.customCameraDown, isTrue);
  });

  test('dead override with nothing to fall back to stays put', () {
    final s = pick(custom: 'http://192.168.1.84:8080/video', dead: true);
    expect(s.url, 'http://192.168.1.84:8080/video');
    expect(s.isExternal, isTrue);
    expect(s.customCameraDown, isFalse);
  });

  test('the latch keeps the fallback after the counters reset (no flap)', () {
    // The fallback's own first success resets the failure counters, so
    // customDead reads false again - the latch alone must hold the line.
    final s = pick(
        custom: 'http://192.168.1.84:8080/video',
        autoSnapshot: 'http://192.168.1.50:1984/api/frame.jpeg?src=cam',
        latched: true);
    expect(s.url, 'http://192.168.1.50:1984/api/frame.jpeg?src=cam');
    expect(s.customCameraDown, isTrue);
  });

  test('no override: auto camera, then the path, then nothing', () {
    expect(pick(autoSnapshot: 'http://a/b.jpeg', path: '/webcam/').url,
        'http://a/b.jpeg');
    expect(pick(path: '/webcam/?action=snapshot').isExternal, isFalse);
    expect(pick().url, isNull);
  });

  test('auto snapshot outranks auto stream', () {
    final s = pick(
        autoSnapshot: 'http://a/frame.jpeg', autoStream: 'http://a/video');
    expect(s.url, 'http://a/frame.jpeg');
  });

  test('tunnel mode wraps the surviving external camera in the relay', () {
    final s = pick(
        custom: 'http://192.168.1.84:8080/video',
        autoSnapshot: 'http://192.168.1.85:1984/api/frame.jpeg?src=cam',
        isLan: false,
        dead: true);
    expect(
        s.url,
        'https://pi.example/mg-extcam'
        '?u=http%3A%2F%2F192.168.1.85%3A1984%2Fapi%2Fframe.jpeg%3Fsrc%3Dcam'
        '&mg_token=tok%20en');
    expect(s.customCameraDown, isTrue);
  });

  test('tunnel mode appends the token to a snapshot path correctly', () {
    expect(pick(path: '/webcam/?action=snapshot', isLan: false).url,
        'https://pi.example/webcam/?action=snapshot&mg_token=tok%20en');
    expect(pick(path: '/snapshot', isLan: false).url,
        'https://pi.example/snapshot?mg_token=tok%20en');
  });

  test('a go2rtc player URL is rewritten to its frame endpoint, both slots',
      () {
    expect(pick(custom: 'http://h:1984/stream.html?src=cam').url,
        'http://h:1984/api/frame.jpeg?src=cam');
    expect(pick(autoStream: 'http://h:1984/stream.html?src=cam').url,
        'http://h:1984/api/frame.jpeg?src=cam');
  });

  // ── The stale-entry fallback (dead printer camera → default path) ──────────

  test('dead auto camera falls back to the snapshot path, visibly', () {
    // The Schlonky case: the entry's go2rtc URL outlived go2rtc itself; the
    // plugin fills snapshot_path with the default for external-only entries.
    final s = pick(
        autoSnapshot: 'http://192.168.1.50:1984/api/frame.jpeg?src=cam',
        path: '/webcam/?action=snapshot',
        nativeDead: true);
    expect(s.url, 'http://192.168.1.50/webcam/?action=snapshot');
    expect(s.isExternal, isFalse);
    expect(s.configuredCameraDown, isTrue);
    expect(s.customCameraDown, isFalse);
  });

  test('the native latch keeps that fallback after the counters reset', () {
    final s = pick(
        autoSnapshot: 'http://192.168.1.50:1984/api/frame.jpeg?src=cam',
        path: '/webcam/?action=snapshot',
        nativeLatched: true);
    expect(s.url, 'http://192.168.1.50/webcam/?action=snapshot');
    expect(s.configuredCameraDown, isTrue);
  });

  test('dead non-default snapshot path falls back to the default path', () {
    final s = pick(path: '/webcam2/?action=snapshot', nativeDead: true);
    expect(s.url, 'http://192.168.1.50/webcam/?action=snapshot');
    expect(s.configuredCameraDown, isTrue);
  });

  test('dead DEFAULT snapshot path has nowhere to hop and stays put', () {
    final s = pick(path: '/webcam/?action=snapshot', nativeDead: true);
    expect(s.url, 'http://192.168.1.50/webcam/?action=snapshot');
    expect(s.configuredCameraDown, isFalse);
  });

  test('dead auto camera with no snapshot path stays put', () {
    final s = pick(
        autoSnapshot: 'http://192.168.1.50:1984/api/frame.jpeg?src=cam',
        nativeDead: true);
    expect(s.url, 'http://192.168.1.50:1984/api/frame.jpeg?src=cam');
    expect(s.configuredCameraDown, isFalse);
  });

  test('a healthy override stays in charge whatever the native verdict', () {
    final s = pick(
        custom: 'http://192.168.1.84:8080/video',
        autoSnapshot: 'http://192.168.1.50:1984/api/frame.jpeg?src=cam',
        path: '/webcam/?action=snapshot',
        nativeDead: true);
    expect(s.url, 'http://192.168.1.84:8080/video');
    expect(s.customCameraDown, isFalse);
    expect(s.configuredCameraDown, isFalse);
  });

  test('dead override then dead auto cascade down to the snapshot path', () {
    final s = pick(
        custom: 'http://192.168.1.84:8080/video',
        autoSnapshot: 'http://192.168.1.50:1984/api/frame.jpeg?src=cam',
        path: '/webcam/?action=snapshot',
        dead: true,
        nativeDead: true);
    expect(s.url, 'http://192.168.1.50/webcam/?action=snapshot');
    expect(s.isExternal, isFalse);
    expect(s.customCameraDown, isTrue);
    expect(s.configuredCameraDown, isTrue);
  });

  test('tunnel mode: the stale-entry fallback carries the token', () {
    final s = pick(
        autoSnapshot: 'http://192.168.1.85:1984/api/frame.jpeg?src=cam',
        path: '/webcam/?action=snapshot',
        isLan: false,
        nativeDead: true);
    expect(s.url,
        'https://pi.example/webcam/?action=snapshot&mg_token=tok%20en');
    expect(s.configuredCameraDown, isTrue);
  });
}
