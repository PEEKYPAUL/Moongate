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

  // ── v0.9.82: the four ways 0.9.81 could still lose an identity ────────────

  group('adoptAction (path 2: an expired copy on disk)', () {
    test('a live newer copy is recovered as-is', () {
      final mine   = facts('r1', now.add(const Duration(minutes: 5)));
      final stored = facts('r2', now.add(const Duration(minutes: 55)));
      expect(SessionRefreshPolicy.adoptAction(mine: mine, stored: stored, now: now),
          AdoptAction.recover);
    });

    test('an expired newer copy is refreshed from its token, never recovered', () {
      // Both isolates slept past expiry; the service's copy r2 is the newer
      // rotation but its access token is dead. gotrue's recoverSession would
      // sign it out (auto-refresh is off) - refresh from r2 instead.
      final mine   = facts('r1', now.subtract(const Duration(hours: 3)));
      final stored = facts('r2', now.subtract(const Duration(hours: 2)));
      expect(SessionRefreshPolicy.adoptAction(mine: mine, stored: stored, now: now),
          AdoptAction.refreshWithToken);
    });

    test('a copy inside the expiry margin counts as expired', () {
      final stored = facts('r2', now.add(const Duration(seconds: 20)));
      expect(SessionRefreshPolicy.adoptAction(mine: null, stored: stored, now: now),
          AdoptAction.refreshWithToken);
    });

    test('nothing newer on disk means nothing to adopt', () {
      final mine = facts('r1', now.add(const Duration(minutes: 5)));
      expect(SessionRefreshPolicy.adoptAction(mine: mine, stored: mine, now: now),
          AdoptAction.none);
      expect(SessionRefreshPolicy.adoptAction(mine: mine, stored: null, now: now),
          AdoptAction.none);
    });
  });

  group('isExpired', () {
    test('expired, inside the margin, live, and no-expiry', () {
      expect(SessionRefreshPolicy.isExpired(
          session: facts('r', now.subtract(const Duration(hours: 1))), now: now), isTrue);
      expect(SessionRefreshPolicy.isExpired(
          session: facts('r', now.add(const Duration(seconds: 59))), now: now), isTrue);
      expect(SessionRefreshPolicy.isExpired(
          session: facts('r', now.add(const Duration(seconds: 61))), now: now), isFalse);
      expect(SessionRefreshPolicy.isExpired(
          session: const SessionFacts(refreshToken: 'r', expiresAt: null, userId: 'u'),
          now: now), isFalse);
      expect(SessionRefreshPolicy.isExpired(session: null, now: now), isFalse);
    });

    test('the margin is wider than gotrue\'s own 30 s', () {
      expect(SessionRefreshPolicy.expiredMargin, greaterThan(const Duration(seconds: 30)));
    });
  });

  group('classifyRejection (path 3: only a real rejection is a loss)', () {
    RefreshVerdict verdict(String? code, {String? message, String? status}) =>
        SessionRefreshPolicy.classifyRejection(
            code: code, message: message, statusCode: status);

    test('the token, session or user being gone is a loss', () {
      for (final c in [
        'refresh_token_not_found',
        'refresh_token_already_used',
        'session_not_found',
        'session_expired',
        'user_not_found',
        'user_banned',
      ]) {
        expect(verdict(c, status: '400'), RefreshVerdict.identityGone, reason: c);
      }
    });

    test('a rate limit is NOT a loss', () {
      expect(verdict('over_request_rate_limit', status: '429'), RefreshVerdict.retryLater);
    });

    test('an unknown or unexpected code is NOT a loss', () {
      expect(verdict('unexpected_failure', status: '500'), RefreshVerdict.retryLater);
      expect(verdict('validation_failed', status: '400'), RefreshVerdict.retryLater);
      expect(verdict('something_new_from_2027', status: '400'), RefreshVerdict.retryLater);
    });

    test('no code at all: only the legacy "invalid refresh token" wording is a loss', () {
      expect(verdict(null, message: 'Invalid Refresh Token: Refresh Token Not Found', status: '400'),
          RefreshVerdict.identityGone);
      expect(verdict(null, message: 'Invalid Refresh Token: Already Used', status: '400'),
          RefreshVerdict.identityGone);
      expect(verdict(null, message: 'Received an empty response with status code 400', status: '400'),
          RefreshVerdict.retryLater);
      expect(verdict(null, message: null, status: null), RefreshVerdict.retryLater);
    });

    test('a known code wins over a scary message', () {
      expect(verdict('over_request_rate_limit', message: 'Invalid Refresh Token', status: '429'),
          RefreshVerdict.retryLater);
    });
  });

  group('startupAction (paths 1 and 4: the library dropped an expired session)', () {
    test('the library recovered a live session: use it', () {
      expect(SessionRefreshPolicy.startupAction(libraryRecovered: true, snapshotRefreshToken: 'r1'),
          StartupAction.useRecovered);
      expect(SessionRefreshPolicy.startupAction(libraryRecovered: true, snapshotRefreshToken: null),
          StartupAction.useRecovered);
    });

    test('the 25/11 morning: no session after boot but a refresh token was on disk = refresh it', () {
      // 0.9.81 signed out here and minted a new user; the printers were
      // orphaned. 0.9.82 refreshes from the snapshot instead.
      expect(SessionRefreshPolicy.startupAction(libraryRecovered: false, snapshotRefreshToken: 'r1'),
          StartupAction.refreshSnapshot);
    });

    test('nothing on disk at all is the only time a new identity is allowed', () {
      expect(SessionRefreshPolicy.startupAction(libraryRecovered: false, snapshotRefreshToken: null),
          StartupAction.noSession);
      expect(SessionRefreshPolicy.startupAction(libraryRecovered: false, snapshotRefreshToken: ''),
          StartupAction.noSession);
    });
  });
}
