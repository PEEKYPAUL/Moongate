import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moongate/services/supabase_service.dart';

/// The session paths no device soak can drive on demand, run against the
/// real supabase_flutter + gotrue stack with a scripted network:
///
///   * a cold start on an EXPIRED saved session (what hit every 0.9.81 install
///     opened again after an hour away) refreshes it - online, offline-then-
///     online, through a 429 - and never mints a new identity;
///   * only the server's explicit "token / session / user gone" does, and even
///     then a newer copy another isolate persisted is tried first;
///   * background isolates never sign in;
///   * a deliberate delete clears the disk, nothing else does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const persistKey = 'sb-wlmmaoupmupbrrkcjglj-auth-token';
  const uidKey     = 'moongate_cloud_uid';
  const oldUid     = '11111111-aaaa-4bbb-8ccc-000000000001';
  const newUid     = '22222222-aaaa-4bbb-8ccc-000000000002';

  int nowSecs() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o)))
      .replaceAll('=', '');

  /// A syntactically valid JWT (Realtime and gotrue decode the payload).
  String jwt(String uid, int exp) =>
      '${b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${b64({'sub': uid, 'exp': exp, 'role': 'authenticated', 'aud': 'authenticated'})}.'
      'sig';

  Map<String, dynamic> sessionJson({
    required String uid,
    required String refreshToken,
    required int expiresAt,
  }) =>
      {
        'access_token':  jwt(uid, expiresAt),
        'token_type':    'bearer',
        'expires_in':    expiresAt - nowSecs(),
        'expires_at':    expiresAt,
        'refresh_token': refreshToken,
        'user': {
          'id':            uid,
          'aud':           'authenticated',
          'role':          'authenticated',
          'app_metadata':  <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'is_anonymous':  true,
          'created_at':    '2026-11-25T11:00:00Z',
        },
      };

  // ── The scripted server ────────────────────────────────────────────────────
  /// What /token does right now.
  var tokenMode = 'ok';
  final requests = <String>[]; // "POST /token r-old" style records
  var issued = 0;              // refresh tokens handed out so far
  Future<void> Function()? beforeTokenReply; // simulate another isolate

  http.Response json(int status, Object body) => http.Response(
        jsonEncode(body),
        status,
        headers: {
          'content-type':           'application/json',
          'x-supabase-api-version': '2024-01-01',
        },
      );

  http.Response error(int status, String code, String msg) =>
      json(status, {'code': code, 'error_code': code, 'msg': msg});

  Future<http.Response> handler(http.Request req) async {
    final path = req.url.path;
    if (path.endsWith('/auth/v1/token')) {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final presented = body['refresh_token'] as String? ?? '?';
      requests.add('POST /token $presented');
      if (beforeTokenReply != null) await beforeTokenReply!();
      switch (tokenMode) {
        case 'offline':
          throw http.ClientException('offline', req.url);
        case 'rate':
          return error(429, 'over_request_rate_limit', 'Request rate limit reached');
        case 'used':
          return error(400, 'refresh_token_already_used',
              'Invalid Refresh Token: Already Used');
        case 'not_found':
          return error(400, 'refresh_token_not_found',
              'Invalid Refresh Token: Refresh Token Not Found');
        default:
          issued++;
          return json(200, sessionJson(
              uid: oldUid, refreshToken: 'r-new-$issued',
              expiresAt: nowSecs() + 3600));
      }
    }
    if (path.endsWith('/auth/v1/signup')) {
      requests.add('POST /signup');
      issued++;
      return json(200, sessionJson(
          uid: newUid, refreshToken: 'r-fresh-$issued',
          expiresAt: nowSecs() + 3600));
    }
    if (path.endsWith('/auth/v1/logout')) {
      requests.add('POST /logout');
      return http.Response('', 204);
    }
    if (path.endsWith('/functions/v1/delete-account')) {
      requests.add('POST /delete-account');
      return json(200, {'ok': true});
    }
    requests.add('${req.method} $path');
    return json(404, {'msg': 'not scripted: $path'});
  }

  Future<void> seedDisk({Map<String, dynamic>? session, bool remembered = true}) async {
    SharedPreferences.setMockInitialValues({
      if (session != null) persistKey: jsonEncode(session),
      if (remembered) uidKey: oldUid,
    });
  }

  Future<Map<String, dynamic>?> onDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(persistKey);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> until(bool Function() done, {Duration timeout = const Duration(seconds: 60)}) async {
    final end = DateTime.now().add(timeout);
    while (!done()) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  final sb = SupabaseService.instance;

  setUp(() async {
    tokenMode = 'ok';
    requests.clear();
    issued = 0;
    beforeTokenReply = null;
    SupabaseService.httpClientForTests = MockClient(handler);
  });

  tearDown(() async {
    await sb.resetForTests();
    SupabaseService.httpClientForTests = null;
  });

  test('a live saved session is recovered as-is: same user, no network', () async {
    await seedDisk(session: sessionJson(
        uid: oldUid, refreshToken: 'r-live', expiresAt: nowSecs() + 3000));
    await sb.initialize();
    expect(sb.userId, oldUid);
    expect(sb.signedIn.value, isTrue);
    expect(sb.identityLost.value, isFalse);
    expect(requests.where((r) => r.startsWith('POST /token')), isEmpty);
    expect(requests.where((r) => r == 'POST /signup'), isEmpty);
  });

  test('the 25/11 morning: an EXPIRED saved session is refreshed, not replaced', () async {
    await seedDisk(session: sessionJson(
        uid: oldUid, refreshToken: 'r-old', expiresAt: nowSecs() - 7200));
    await sb.initialize();
    await until(() => sb.userId != null);
    expect(sb.userId, oldUid, reason: 'same identity');
    expect(requests, contains('POST /token r-old'));
    expect(requests, isNot(contains('POST /signup')));
    expect(sb.identityLost.value, isFalse);
    expect(sb.recoveryPending, isFalse);
    final disk = await onDisk();
    expect(disk?['refresh_token'], 'r-new-1', reason: 'the rotated token is persisted');
  });

  test('expired + OFFLINE at start: no identity minted, copy kept, recovers once online', () async {
    tokenMode = 'offline';
    await seedDisk(session: sessionJson(
        uid: oldUid, refreshToken: 'r-old', expiresAt: nowSecs() - 7200));
    await sb.initialize();
    // Let the offline attempt run its course (gotrue retries for a while).
    await until(() => sb.recoveryPending && requests.isNotEmpty);
    await until(() => !sb.signedIn.value && sb.recoveryPending);
    expect(sb.userId, isNull);
    expect(sb.identityLost.value, isFalse, reason: 'offline is never a loss');
    expect(requests, isNot(contains('POST /signup')));
    expect((await onDisk())?['refresh_token'], 'r-old', reason: 'the copy stays on disk');
    // Give the in-flight attempt time to finish failing, then go online.
    await Future<void>.delayed(const Duration(seconds: 2));
    tokenMode = 'ok';
    await sb.ensureFreshSession();
    await until(() => sb.userId != null, timeout: const Duration(seconds: 90));
    expect(sb.userId, oldUid);
    expect(sb.recoveryPending, isFalse);
    expect(sb.identityLost.value, isFalse);
    expect((await onDisk())?['refresh_token'], startsWith('r-new-'));
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('a 429 on the refresh is not a loss: held and retried', () async {
    tokenMode = 'rate';
    await seedDisk(session: sessionJson(
        uid: oldUid, refreshToken: 'r-old', expiresAt: nowSecs() - 7200));
    await sb.initialize();
    await until(() => requests.contains('POST /token r-old'));
    await until(() => sb.recoveryPending);
    expect(sb.userId, isNull);
    expect(sb.identityLost.value, isFalse);
    expect(requests, isNot(contains('POST /signup')));
    expect((await onDisk())?['refresh_token'], 'r-old');
    tokenMode = 'ok';
    await sb.ensureFreshSession();
    await until(() => sb.userId != null);
    expect(sb.userId, oldUid);
    expect(sb.recoveryPending, isFalse);
  });

  test('"already used" but another isolate persisted the child: adopt it, no loss', () async {
    tokenMode = 'used';
    await seedDisk(session: sessionJson(
        uid: oldUid, refreshToken: 'r-old', expiresAt: nowSecs() - 7200));
    // The other isolate rotated r-old -> r-other and wrote it to disk just
    // before our request is answered.
    beforeTokenReply = () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(persistKey, jsonEncode(sessionJson(
          uid: oldUid, refreshToken: 'r-other', expiresAt: nowSecs() + 3000)));
      beforeTokenReply = null;
    };
    await sb.initialize();
    await until(() => sb.userId != null);
    expect(sb.userId, oldUid);
    expect(sb.identityLost.value, isFalse);
    expect(requests, isNot(contains('POST /signup')));
    expect(requests.where((r) => r.startsWith('POST /token')).length, 1,
        reason: 'the live copy is recovered without another refresh');
  });

  test('"already used" with nothing newer anywhere IS a loss: new identity + banner', () async {
    tokenMode = 'used';
    await seedDisk(session: sessionJson(
        uid: oldUid, refreshToken: 'r-old', expiresAt: nowSecs() - 7200));
    await sb.initialize();
    await until(() => sb.userId != null);
    expect(sb.userId, newUid);
    expect(requests, contains('POST /signup'));
    expect(sb.identityLost.value, isTrue);
    expect(sb.previousUserId, oldUid);
    expect((await onDisk())?['refresh_token'], startsWith('r-fresh-'));
  });

  test('"refresh token not found" is a loss too', () async {
    tokenMode = 'not_found';
    await seedDisk(session: sessionJson(
        uid: oldUid, refreshToken: 'r-old', expiresAt: nowSecs() - 7200));
    await sb.initialize();
    await until(() => sb.userId != null);
    expect(sb.userId, newUid);
    expect(sb.identityLost.value, isTrue);
  });

  test('a BACKGROUND isolate never signs in: expired + offline just keeps the copy', () async {
    tokenMode = 'offline';
    await seedDisk(session: sessionJson(
        uid: oldUid, refreshToken: 'r-old', expiresAt: nowSecs() - 7200));
    await sb.initialize(allowSignIn: false, keepFresh: false);
    await until(() => sb.recoveryPending && requests.isNotEmpty);
    await until(() => !sb.signedIn.value);
    expect(requests, isNot(contains('POST /signup')));
    expect(sb.identityLost.value, isFalse);
    expect((await onDisk())?['refresh_token'], 'r-old');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a BACKGROUND isolate with a final rejection mints nothing', () async {
    tokenMode = 'used';
    await seedDisk(session: sessionJson(
        uid: oldUid, refreshToken: 'r-old', expiresAt: nowSecs() - 7200));
    await sb.initialize(allowSignIn: false, keepFresh: false);
    await until(() => requests.contains('POST /token r-old'));
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(sb.userId, isNull);
    expect(requests, isNot(contains('POST /signup')));
  });

  test('nothing on disk and nothing remembered: a first run signs in without a banner', () async {
    await seedDisk(session: null, remembered: false);
    await sb.initialize();
    await until(() => sb.userId != null);
    expect(sb.userId, newUid);
    expect(sb.identityLost.value, isFalse);
    expect((await onDisk())?['refresh_token'], startsWith('r-fresh-'),
        reason: 'the new session is persisted by Moongate itself');
  });

  test('nothing on disk but an identity remembered: banner + new identity (the honest loss)', () async {
    await seedDisk(session: null, remembered: true);
    await sb.initialize();
    await until(() => sb.userId != null);
    expect(sb.userId, newUid);
    expect(sb.identityLost.value, isTrue);
    expect(sb.previousUserId, oldUid);
  });

  test('deleteAccount clears the disk and shows no banner', () async {
    await seedDisk(session: sessionJson(
        uid: oldUid, refreshToken: 'r-live', expiresAt: nowSecs() + 3000));
    await sb.initialize();
    expect(sb.userId, oldUid);
    await sb.deleteAccount();
    await until(() => sb.userId == newUid);
    expect(sb.identityLost.value, isFalse);
    expect(requests, contains('POST /delete-account'));
    expect((await onDisk())?['refresh_token'], startsWith('r-fresh-'));
  });
}
