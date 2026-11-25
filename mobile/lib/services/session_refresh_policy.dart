/// Pure decisions for Moongate's single-refresher session handling (v0.9.81,
/// hardened in v0.9.82).
///
/// Several isolates (the UI, the print-notification foreground service, the
/// widget's one-shot refresh) each run a Supabase client off the SAME
/// persisted anonymous session. gotrue's own auto-refresh is switched OFF in
/// all of them; instead every isolate periodically asks these questions and
/// acts on the answers through [SupabaseService.ensureFreshSession]:
///
///   1. [adoptAction]: has another isolate already rotated the refresh token
///      and persisted a NEWER session than the one in my memory? Then take
///      that copy instead of refreshing with my stale token - presenting a
///      token that was already used makes GoTrue revoke the whole token
///      family, which is how installs lost their identity. An expired copy is
///      REFRESHED from its token rather than handed to gotrue's
///      `recoverSession`, which signs an expired session out when auto-refresh
///      is off (the v0.9.81 cold-start wipe).
///   2. [needsRefresh]: is the access token about to expire? Only then refresh,
///      with the newest token we know of.
///   3. [classifyRejection]: when the server rejects a refresh, is the identity
///      really gone, or should we hold the token and try again later? Only an
///      explicit "this token / session / user no longer exists" counts as gone.
///      A rate limit or an unexpected error must never mint a new identity.
///   4. [startupAction]: what to do with the copy on disk at start - recover
///      a live one as-is, refresh an expired one from its token, or (only
///      with nothing on disk at all) start a new identity. The library has no
///      storage of its own any more, so its unawaited boot-time recovery can
///      no longer sign out and delete the copy behind our back.
///
/// Kept free of gotrue types so it is unit-testable in plain Dart.
class SessionFacts {
  final String?   refreshToken;
  /// Unix seconds, as GoTrue reports `expires_at`.
  final int?      expiresAt;
  final String?   userId;

  const SessionFacts({
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
  });
}

/// How to take on a copy another isolate persisted.
enum AdoptAction {
  /// Nothing newer on disk.
  none,
  /// A live copy: hand its JSON to gotrue's `recoverSession` (no network).
  recover,
  /// An expired (or nearly expired) copy: refresh from its refresh token.
  /// `recoverSession` would sign it out instead.
  refreshWithToken,
}

/// What a rejected refresh means for the install.
enum RefreshVerdict {
  /// The server said the token, session or user no longer exists. Only then
  /// is the identity gone and a new anonymous user justified (UI isolate).
  identityGone,
  /// Anything else - a rate limit, an unexpected code, no code at all. Keep
  /// the token and try again on a later pass; never start over.
  retryLater,
}

/// What to do with the copy on disk at start (the library has no storage of
/// its own any more, so the copy is Moongate's to bring back).
enum StartupAction {
  /// A live copy: hand it to gotrue as-is, no network.
  recoverSnapshot,
  /// An expired copy: refresh it from its refresh token.
  refreshSnapshot,
  /// Nothing on disk at all: first run, or a deliberate sign-out.
  noSession,
}

class SessionRefreshPolicy {
  SessionRefreshPolicy._();

  /// gotrue-dart treats a session as expired 30 s before `expires_at`
  /// (`Constants.expiryMargin`). Stay comfortably on the safe side: a copy
  /// this close to expiry is refreshed from its token, never recovered.
  static const expiredMargin = Duration(seconds: 60);

  /// True when [stored] (the copy on disk, possibly written by another
  /// isolate) carries a different refresh token than [mine] AND expires later,
  /// i.e. it is the result of a rotation this isolate has not seen. A missing
  /// in-memory session adopts any stored one. Equal or older copies, or a copy
  /// with no refresh token, are never adopted.
  static bool shouldAdopt({
    required SessionFacts? mine,
    required SessionFacts? stored,
  }) {
    if (stored == null || stored.refreshToken == null) return false;
    if (mine == null) return true;
    if (stored.refreshToken == mine.refreshToken) return false;
    final storedExp = stored.expiresAt ?? 0;
    final mineExp   = mine.expiresAt ?? 0;
    return storedExp > mineExp;
  }

  /// True when [session]'s access token has expired, or will within
  /// [expiredMargin] of [now]. No expiry = never expired (gotrue's reading).
  static bool isExpired({
    required SessionFacts? session,
    required DateTime now,
  }) {
    if (session == null || session.expiresAt == null) return false;
    final expires = DateTime.fromMillisecondsSinceEpoch(
        session.expiresAt! * 1000, isUtc: true);
    return !expires.isAfter(now.toUtc().add(expiredMargin));
  }

  /// [shouldAdopt], then HOW: a live copy is recovered as-is, an expired one
  /// is refreshed from its token.
  static AdoptAction adoptAction({
    required SessionFacts? mine,
    required SessionFacts? stored,
    required DateTime now,
  }) {
    if (!shouldAdopt(mine: mine, stored: stored)) return AdoptAction.none;
    return isExpired(session: stored, now: now)
        ? AdoptAction.refreshWithToken
        : AdoptAction.recover;
  }

  /// True when [session]'s access token expires within [margin] of [now]
  /// (or has already expired). A session with no expiry is never refreshed
  /// here - gotrue treats it as non-expiring.
  static bool needsRefresh({
    required SessionFacts? session,
    required DateTime now,
    required Duration margin,
  }) {
    if (session == null || session.expiresAt == null) return false;
    final expires =
        DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000, isUtc: true);
    return !expires.isAfter(now.toUtc().add(margin));
  }

  /// GoTrue's codes for "there is nothing to refresh any more". Everything
  /// else (`over_request_rate_limit`, `unexpected_failure`, an unknown code,
  /// no code) is a reason to wait, not to start over.
  static const _goneCodes = <String>{
    'refresh_token_not_found',
    'refresh_token_already_used',
    'session_not_found',
    'session_expired',
    'user_not_found',
    'user_banned',
  };

  /// Legacy GoTrue phrasing from before error codes existed.
  static const _goneMessages = <String>[
    'invalid refresh token',
    'refresh token not found',
    'already used',
    'session not found',
  ];

  /// Read a rejected refresh. [code] is gotrue's `AuthException.code`,
  /// [message] its message, [statusCode] the HTTP status as a string (gotrue
  /// keeps it as text). Network trouble and 5xx never reach here: gotrue
  /// raises them as retryable before this is asked.
  static RefreshVerdict classifyRejection({
    required String? code,
    required String? message,
    required String? statusCode,
  }) {
    if (code != null && _goneCodes.contains(code)) {
      return RefreshVerdict.identityGone;
    }
    if (code == null) {
      final m = (message ?? '').toLowerCase();
      for (final g in _goneMessages) {
        if (m.contains(g)) return RefreshVerdict.identityGone;
      }
    }
    return RefreshVerdict.retryLater;
  }

  /// What to do with [snapshot], the copy read from disk at start.
  static StartupAction startupAction({
    required SessionFacts? snapshot,
    required DateTime      now,
  }) {
    final token = snapshot?.refreshToken;
    if (token == null || token.isEmpty) return StartupAction.noSession;
    return isExpired(session: snapshot, now: now)
        ? StartupAction.refreshSnapshot
        : StartupAction.recoverSnapshot;
  }
}
