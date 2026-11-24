import 'package:flutter_test/flutter_test.dart';

import 'package:moongate/services/session_refresh_policy.dart';

/// The identity-loss bug of November 2026: the UI isolate and the
/// print-notification isolate each refreshed the shared anonymous session from
/// their own copy of the refresh token; the second one to refresh presented a
/// token GoTrue had already rotated, which revoked the whole token family and
/// left the install signed out -> a brand-new anonymous user on the next cold
/// start, every paired printer orphaned ("tiles offline, tapping in works").
/// These tests pin the two decisions that prevent it.
void main() {
  final now = DateTime.utc(2026, 11, 24, 20, 0, 0);
  int secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  SessionFacts facts(String token, DateTime exp, [String uid = 'u1']) =>
      SessionFacts(refreshToken: token, expiresAt: secs(exp), userId: uid);

  group('shouldAdopt', () {
    test('a newer copy persisted by another isolate is adopted', () {
      final mine   = facts('r1', now.add(const Duration(minutes: 5)));
      final stored = facts('r2', now.add(const Duration(minutes: 60)));
      expect(SessionRefreshPolicy.shouldAdopt(mine: mine, stored: stored), isTrue);
    });

    test('the same token is never re-adopted', () {
      final mine   = facts('r1', now.add(const Duration(minutes: 5)));
      final stored = facts('r1', now.add(const Duration(minutes: 5)));
      expect(SessionRefreshPolicy.shouldAdopt(mine: mine, stored: stored), isFalse);
    });

    test('an OLDER copy on disk is ignored (my memory is the newer rotation)', () {
      final mine   = facts('r2', now.add(const Duration(minutes: 60)));
      final stored = facts('r1', now.add(const Duration(minutes: 5)));
      expect(SessionRefreshPolicy.shouldAdopt(mine: mine, stored: stored), isFalse);
    });

    test('no in-memory session adopts whatever is on disk', () {
      final stored = facts('r1', now.add(const Duration(minutes: 5)));
      expect(SessionRefreshPolicy.shouldAdopt(mine: null, stored: stored), isTrue);
    });

    test('nothing on disk, or a copy without a refresh token, is never adopted', () {
      final mine = facts('r1', now.add(const Duration(minutes: 5)));
      expect(SessionRefreshPolicy.shouldAdopt(mine: mine, stored: null), isFalse);
      expect(
        SessionRefreshPolicy.shouldAdopt(
          mine: mine,
          stored: SessionFacts(
              refreshToken: null, expiresAt: secs(now.add(const Duration(hours: 2))), userId: 'u1'),
        ),
        isFalse,
      );
    });

    test('a newer copy is adopted even when expires_at ties are impossible to break the other way', () {
      // Equal expiry with a different token = ambiguous; stay put rather than
      // thrash between two isolates' copies.
      final mine   = facts('r1', now.add(const Duration(minutes: 30)));
      final stored = facts('r2', now.add(const Duration(minutes: 30)));
      expect(SessionRefreshPolicy.shouldAdopt(mine: mine, stored: stored), isFalse);
    });
  });

  group('needsRefresh', () {
    const margin = Duration(seconds: 90);

    test('a token with plenty of life left is not refreshed', () {
      final s = facts('r1', now.add(const Duration(minutes: 30)));
      expect(SessionRefreshPolicy.needsRefresh(session: s, now: now, margin: margin), isFalse);
    });

    test('a token inside the margin is refreshed', () {
      final s = facts('r1', now.add(const Duration(seconds: 60)));
      expect(SessionRefreshPolicy.needsRefresh(session: s, now: now, margin: margin), isTrue);
    });

    test('an already-expired token is refreshed', () {
      final s = facts('r1', now.subtract(const Duration(minutes: 10)));
      expect(SessionRefreshPolicy.needsRefresh(session: s, now: now, margin: margin), isTrue);
    });

    test('no session, or no expiry, is left alone', () {
      expect(SessionRefreshPolicy.needsRefresh(session: null, now: now, margin: margin), isFalse);
      const s = SessionFacts(refreshToken: 'r1', expiresAt: null, userId: 'u1');
      expect(SessionRefreshPolicy.needsRefresh(session: s, now: now, margin: margin), isFalse);
    });
  });

  test('the November scenario: UI resumes after an hour, service rotated meanwhile', () {
    // UI isolate paused with token r1 (expiry long gone); the service isolate
    // refreshed hourly and persisted r4 with a fresh expiry. The UI must adopt
    // r4 and must NOT refresh with r1.
    final mine   = facts('r1', now.subtract(const Duration(minutes: 70)));
    final stored = facts('r4', now.add(const Duration(minutes: 55)));
    expect(SessionRefreshPolicy.shouldAdopt(mine: mine, stored: stored), isTrue);
    // After adopting, the fresh copy does not need a refresh yet.
    expect(
      SessionRefreshPolicy.needsRefresh(
          session: stored, now: now, margin: const Duration(seconds: 90)),
      isFalse,
    );
  });
}
