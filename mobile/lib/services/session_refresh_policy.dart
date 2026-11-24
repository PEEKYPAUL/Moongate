/// Pure decisions for Moongate's single-refresher session handling (v0.9.81).
///
/// Several isolates (the UI, the print-notification foreground service, the
/// widget's one-shot refresh) each run a Supabase client off the SAME
/// persisted anonymous session. gotrue's own auto-refresh is switched OFF in
/// all of them; instead every isolate periodically asks these two questions
/// and acts on the answers through [SupabaseService.ensureFreshSession]:
///
///   1. [shouldAdopt]: has another isolate already rotated the refresh token
///      and persisted a NEWER session than the one in my memory? Then take
///      that copy instead of refreshing with my stale token - presenting a
///      token that was already used makes GoTrue revoke the whole token
///      family, which is how installs lost their identity.
///   2. [needsRefresh]: is the access token about to expire? Only then refresh,
///      with the newest token we know of.
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

class SessionRefreshPolicy {
  SessionRefreshPolicy._();

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
}
