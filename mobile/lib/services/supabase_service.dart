import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_refresh_policy.dart';

/// Wraps the Supabase client for Moongate v0.3.0:
///   • initialise + anonymous sign-in on first launch
///   • call /printer-claim to bind a Pi to the current anon user
///   • call /printer-access to get a fresh tunnel URL + 5-min EdDSA token
///   • fetch the current user's printers (RLS scoped)
///
/// All printers in v0.3.0 are owned by the local install's anonymous user.
/// There is no sharing in v0.3.0 by design (§16 of the design doc); each
/// install = one user = one printer set.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  // ── Project identifiers ────────────────────────────────────────────────────
  // The anon key is intentionally embedded in the APK - it grants only
  // anon-role permissions, all of which are locked down to "your own rows"
  // by Row-Level Security policies. Service role is NEVER in the app.
  static const _supabaseUrl     = 'https://wlmmaoupmupbrrkcjglj.supabase.co';
  static const _supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndsbW1hb3VwbXVwYnJya2NqZ2xqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2NTAyMzYsImV4cCI6MjA5NTIyNjIzNn0.EnIxrykASzZCBBCJtDVJetiWBFKGgFTQDRdkyhBCasw';

  bool _initialized = false;

  /// Whether we currently hold a usable anonymous session. Listenable so the
  /// dashboard can show a "reconnecting" banner instead of a silent screen of
  /// offline tiles when the anonymous sign-in is rate-limited (common after
  /// several reinstalls in a row). Flips true the instant a background retry
  /// lands a session; the tiles then reconnect on their next poll.
  final ValueNotifier<bool> signedIn = ValueNotifier<bool>(false);

  Timer? _signInRetryTimer;
  int _signInAttempt = 0;

  // ── Single-refresher session handling (v0.9.81) ───────────────────────────
  // The persisted-session key supabase_flutter writes
  // (`sb-<project ref>-auth-token`), read back here so an isolate can adopt
  // what another isolate rotated. Keep in step with [_supabaseUrl].
  static const _persistKey = 'sb-wlmmaoupmupbrrkcjglj-auth-token';
  // The cloud user id this install last held - the identity-loss detector.
  static const _uidKey = 'moongate_cloud_uid';
  // How often each isolate checks the access token (replaces gotrue's own
  // 10 s auto-refresh ticker, which is OFF everywhere - see [initialize]).
  static const _refreshEvery  = Duration(seconds: 30);
  // Refresh once the access token has less than this left.
  static const _refreshMargin = Duration(seconds: 90);

  Timer?        _refreshTimer;
  Future<void>? _refreshing;
  bool          _signInAllowed = true;

  // ── Recovery (v0.9.82) ────────────────────────────────────────────────────
  // gotrue-dart drops its session on its own in two places when auto-refresh
  // is off: recoverSession() on a copy whose access token has EXPIRED (what
  // supabase_flutter runs at every cold start), and _doRefresh() on ANY
  // non-network rejection, a 429 rate limit included. Both also delete the
  // persisted copy. 0.9.81 read either as "signed out" and minted a new
  // anonymous user, orphaning every printer. Now the copy is kept and the
  // session put back from its refresh token; only an explicit "token / session
  // / user no longer exists" from the server counts as a loss.
  //
  // A copy we still believe in after a refresh the server did not finally
  // reject, held for the next pass.
  _PersistedSession? _pendingRecovery;
  // The newest session this isolate has held, for the sign-out watcher.
  _PersistedSession? _lastKnown;
  // True while a recovery of our own is in flight (the watcher stands back).
  bool _recovering = false;
  // True while [deleteAccount] signs out on purpose: that one is not a loss.
  bool _deliberateSignOut = false;
  StreamSubscription<AuthState>? _authSub;

  /// True while a refresh the server did not finally reject is waiting to be
  /// retried (diagnostics).
  bool get recoveryPending => _pendingRecovery != null;

  /// True once this install's cloud identity was found to be gone (no
  /// persisted session where there used to be one, or a refresh the server
  /// definitively rejected). The app then signs in as a NEW anonymous user so
  /// it keeps working, but every printer paired under the old identity is
  /// orphaned until re-paired - the dashboard shows a banner saying so.
  final ValueNotifier<bool> identityLost = ValueNotifier<bool>(false);

  /// The user id that was lost (for the bug-report diagnostics), or null.
  String? previousUserId;

  void _log(String msg) => dev.log(msg, name: 'MOONGATE/SUPABASE');

  /// Initialise the Supabase client and ensure there's an authenticated
  /// session. Idempotent - safe to call from main() and re-call after
  /// hot-restart.
  ///
  /// [allowSignIn] is false in background isolates (the print-notification
  /// service, the widget's one-shot refresh): they only ever REUSE the
  /// session the UI isolate persisted and must never mint an identity of
  /// their own. [keepFresh] is false for a one-shot isolate (the widget's
  /// WorkManager refresh): a periodic timer there would keep the isolate
  /// alive after its job is done; it still gets one [ensureFreshSession]
  /// pass at start.
  Future<void> initialize({
    bool allowSignIn = true,
    bool keepFresh   = true,
  }) async {
    if (_initialized) return;
    _signInAllowed = allowSignIn;
    // Read the persisted copy BEFORE the library boots. supabase_flutter hands
    // it to gotrue-dart's recoverSession, which - with auto-refresh off - SIGNS
    // OUT a session whose access token has expired instead of refreshing it,
    // and deletes it from storage. That is what 0.9.81 did to every install
    // opened again after an hour away: a new anonymous user, every printer
    // orphaned. The snapshot keeps the refresh token so the session is
    // refreshed below instead.
    final snapshot = await _readPersistedSession();
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabaseAnonKey,
      // gotrue's own auto-refresh is OFF in every isolate. The
      // print-notification service (and the widget's one-shot refresh) run
      // their own Supabase client off the SAME persisted anonymous session;
      // with each client refreshing from its in-memory copy of the refresh
      // token, the second one to refresh presented a token the first had
      // already rotated, GoTrue's reuse detection revoked the whole token
      // family and the install ended up signed out -> a brand-new anonymous
      // user on the next cold start, every paired printer orphaned (the
      // "tiles offline but tapping in works" reports, Nov 2026).
      // [ensureFreshSession] is now the only refresher: it adopts whatever
      // another isolate persisted BEFORE it would ever refresh.
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
    _initialized = true;
    _watchLibrarySignOuts();
    _refreshTimer?.cancel();
    if (keepFresh) {
      _refreshTimer =
          Timer.periodic(_refreshEvery, (_) => ensureFreshSession().ignore());
    }

    switch (SessionRefreshPolicy.startupAction(
        libraryRecovered:     client.auth.currentSession != null,
        snapshotRefreshToken: snapshot?.facts.refreshToken)) {
      case StartupAction.useRecovered:
        _log('Existing session, user_id=${client.auth.currentUser?.id}');
        _lastKnown = _snapshotOf(client.auth.currentSession);
        signedIn.value = true;
        await _rememberUid();
        // About to expire? Bring it up to date now (adopting a newer persisted
        // copy first), before the dashboard's first poll.
        await ensureFreshSession();
        return;
      case StartupAction.refreshSnapshot:
        _log('Persisted session had expired - refreshing it instead of '
            'starting over');
        await _refreshFrom(snapshot!);
        if (client.auth.currentSession != null) {
          await _rememberUid();
        } else if (_pendingRecovery != null) {
          // Not a loss: the token is kept for the next pass.
          _log('Session recovery deferred');
        }
        // A final rejection was handled inside _refreshFrom (a new identity
        // in the UI isolate, nothing in a background one).
        return;
      case StartupAction.noSession:
        break;
    }
    if (!allowSignIn) {
      _log('No persisted session in this isolate; sign-in is the UI\'s job');
      return;
    }
    await _detectIdentityLoss();
    _log('No session yet - signing in anonymously');
    await _trySignIn();
  }

  /// Make sure the access token is good for the next while, refreshing it
  /// if needed - but FIRST adopt a newer session another isolate may have
  /// persisted, so this isolate never presents a refresh token that was
  /// already rotated elsewhere. Concurrent callers share one pass. Never
  /// throws: a network blip just leaves the token as it was for the next
  /// pass; a definitive rejection is handled by [_onSessionLost].
  Future<void> ensureFreshSession() {
    return _refreshing ??=
        _ensureFreshSession().whenComplete(() => _refreshing = null);
  }

  Future<void> _ensureFreshSession() async {
    if (!_initialized) return;
    final auth = client.auth;
    final pending = _pendingRecovery;
    if (pending != null && auth.currentSession == null) {
      await _refreshFrom(pending);
      return;
    }
    // What we present to the server, for the rejection path.
    _PersistedSession? attempted;
    try {
      final stored = await _readPersistedSession();
      final now    = DateTime.now();
      switch (SessionRefreshPolicy.adoptAction(
          mine: _facts(auth.currentSession), stored: stored?.facts, now: now)) {
        case AdoptAction.none:
          break;
        case AdoptAction.recover:
          _log('Adopting the session another isolate persisted');
          attempted = stored;
          await auth.recoverSession(stored!.raw);
          await _handOverToRealtime();
        case AdoptAction.refreshWithToken:
          // recoverSession would sign an EXPIRED copy out (auto-refresh is
          // off) - refresh from its token instead.
          _log('Adopting an expired copy another isolate persisted - '
              'refreshing it');
          attempted = stored;
          await auth.setSession(stored!.facts.refreshToken!);
          await _handOverToRealtime();
      }
      if (SessionRefreshPolicy.needsRefresh(
          session: _facts(auth.currentSession),
          now:     now,
          margin:  _refreshMargin)) {
        _log('Refreshing the access token');
        attempted = _snapshotOf(auth.currentSession);
        await auth.refreshSession();
      }
      final cur = auth.currentSession;
      if (cur != null) {
        _pendingRecovery = null;
        _lastKnown       = _snapshotOf(cur);
        if (!signedIn.value) signedIn.value = true;
      }
    } on AuthRetryableFetchException catch (e) {
      // gotrue keeps its session on a network failure; the next pass retries.
      _log('Refresh deferred (network): ${e.message}');
    } on AuthException catch (e) {
      if (attempted == null) {
        _log('Session check failed: ${e.code} ${e.message}');
        return;
      }
      await _onRefreshRejected(e, attempted: attempted);
    } catch (e) {
      _log('ensureFreshSession error: $e');
    }
  }

  /// Refresh the session from [s] - the copy gotrue-dart dropped or would
  /// drop. A LIVE copy is recovered as-is first (no network); an expired one,
  /// or a copy recoverSession refuses, is refreshed from its refresh token.
  /// Never throws: a final rejection ends in [_onSessionLost], anything else
  /// keeps the copy for a later pass.
  Future<void> _refreshFrom(_PersistedSession s) async {
    final auth = client.auth;
    _recovering = true;
    try {
      // Another isolate may have rotated this very token moments ago and
      // persisted the result - prefer that over presenting a used token.
      final latest = await _readPersistedSession();
      final use = (latest != null &&
              SessionRefreshPolicy.shouldAdopt(mine: s.facts, stored: latest.facts))
          ? latest
          : s;
      var recovered = false;
      if (!SessionRefreshPolicy.isExpired(session: use.facts, now: DateTime.now())) {
        try {
          await auth.recoverSession(use.raw);
          recovered = auth.currentSession != null;
        } on AuthException catch (e) {
          _log('recoverSession refused the copy (${e.code}) - refreshing instead');
        }
      }
      if (!recovered) await auth.setSession(use.facts.refreshToken!);
      _pendingRecovery = null;
      final cur = auth.currentSession;
      if (cur != null) {
        _lastKnown = _snapshotOf(cur);
        await _handOverToRealtime();
        signedIn.value = true;
        _log('Session recovered, user_id=${cur.user.id}');
      }
    } on AuthRetryableFetchException catch (e) {
      _log('Recovery deferred (network): ${e.message}');
      await _keepForRetry(s);
    } on AuthException catch (e) {
      await _onRefreshRejected(e, attempted: s);
    } catch (e) {
      _log('Recovery error: $e');
      await _keepForRetry(s);
    } finally {
      _recovering = false;
    }
  }

  /// The server rejected a refresh with [attempted]. Only an explicit "this
  /// token / session / user no longer exists" is a loss - and even then
  /// another isolate may have rotated our token and persisted the child, so
  /// that is tried first. Everything else (a 429, an unknown code) keeps the
  /// copy for a later pass.
  Future<void> _onRefreshRejected(AuthException e,
      {required _PersistedSession attempted}) async {
    final verdict = SessionRefreshPolicy.classifyRejection(
        code: e.code, message: e.message, statusCode: e.statusCode);
    if (verdict == RefreshVerdict.retryLater) {
      _log('Refresh rejected but not final (${e.statusCode} ${e.code}): '
          'keeping the session for a later pass');
      await _keepForRetry(attempted);
      return;
    }
    final latest = await _readPersistedSession();
    if (latest?.facts.refreshToken != null &&
        latest!.facts.refreshToken != attempted.facts.refreshToken) {
      _log('Our token was superseded by another isolate - trying its session');
      await _refreshFrom(latest);
      return;
    }
    _log('Refresh rejected for good: ${e.statusCode} ${e.code} ${e.message}');
    _pendingRecovery = null;
    await _onSessionLost();
  }

  /// Hold [s] for the next pass and put it back on disk (gotrue has deleted
  /// its copy) - unless another isolate has meanwhile persisted something
  /// newer, which is then what the next pass should use.
  Future<void> _keepForRetry(_PersistedSession s) async {
    try {
      final current = await _readPersistedSession();
      if (current != null &&
          SessionRefreshPolicy.shouldAdopt(mine: s.facts, stored: current.facts)) {
        _pendingRecovery = current;
        return;
      }
      _pendingRecovery = s;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_persistKey, s.raw);
    } catch (e) {
      _pendingRecovery = s;
      _log('Could not keep the session for retry: $e');
    }
  }

  /// Catch every sign-out we did not ask for - gotrue-dart drops its session
  /// by itself on an expired recoverSession and on any non-network refresh
  /// rejection - and put the session back from the last copy we held. Stands
  /// back while one of our own passes is already dealing with it.
  void _watchLibrarySignOuts() {
    _authSub?.cancel();
    _authSub = client.auth.onAuthStateChange.listen((state) {
      final s = state.session;
      if (s != null) {
        _lastKnown = _snapshotOf(s);
        return;
      }
      if (state.event != AuthChangeEvent.signedOut) return;
      if (_deliberateSignOut || _recovering || _refreshing != null) return;
      final last = _lastKnown;
      if (last?.facts.refreshToken == null) return;
      _log('Library signed the session out (${state.signOutReason}) - recovering');
      _lastKnown       = null;
      _pendingRecovery = last;
      scheduleMicrotask(() => ensureFreshSession().ignore());
    }, onError: (Object e) => _log('auth stream: $e'));
  }

  // recoverSession stays silent when the user id is unchanged, and Realtime
  // only learns new tokens from auth events - hand it over.
  Future<void> _handOverToRealtime() async {
    final s = client.auth.currentSession;
    if (s != null) await client.realtime.setAuth(s.accessToken);
  }

  _PersistedSession? _snapshotOf(Session? s) {
    if (s == null) return null;
    return _PersistedSession(raw: jsonEncode(s.toJson()), facts: _facts(s)!);
  }

  static SessionFacts? _facts(Session? s) => s == null
      ? null
      : SessionFacts(
          refreshToken: s.refreshToken,
          expiresAt:    s.expiresAt,
          userId:       s.user.id,
        );

  Future<_PersistedSession?> _readPersistedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // pick up another isolate's write
      final raw = prefs.getString(_persistKey);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return _PersistedSession(
        raw: raw,
        facts: SessionFacts(
          refreshToken: m['refresh_token'] as String?,
          expiresAt:    (m['expires_at'] as num?)?.toInt(),
          userId:       (m['user'] as Map?)?['id'] as String?,
        ),
      );
    } catch (e) {
      _log('Persisted session unreadable: $e');
      return null;
    }
  }

  /// The server rejected our refresh token for good (gotrue has already
  /// dropped the session and its persisted copy). Record the loss, then - in
  /// the UI isolate only - start a fresh anonymous identity so the app keeps
  /// working; the dashboard banner explains the re-pair.
  Future<void> _onSessionLost() async {
    signedIn.value  = false;
    _pendingRecovery = null;
    _lastKnown       = null;
    if (!_signInAllowed) return;
    await _detectIdentityLoss();
    _log('Session lost - signing in as a new anonymous user');
    await _trySignIn();
  }

  /// No session where this install used to have one = identity loss.
  Future<void> _detectIdentityLoss() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final old = prefs.getString(_uidKey);
      if (old != null && old.isNotEmpty) {
        previousUserId = old;
        identityLost.value = true;
        _log('Cloud identity lost (was $old)');
      }
    } catch (_) {}
  }

  Future<void> _rememberUid() async {
    final uid = userId;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_uidKey, uid);
    } catch (_) {}
  }

  Future<void> _forgetUid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_uidKey);
    } catch (_) {}
  }

  /// Clears the identity-lost flag once the user has seen the banner.
  void acknowledgeIdentityLoss() => identityLost.value = false;

  /// When the current access token expires (diagnostics), or null.
  DateTime? get sessionExpiresAt {
    final exp = client.auth.currentSession?.expiresAt;
    return exp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
  }

  /// One anonymous-sign-in attempt. NEVER throws: on success it flips
  /// [signedIn] true and stops retrying; on failure (typically a 429 rate
  /// limit after repeated reinstalls) it leaves [signedIn] false and schedules
  /// a backoff retry - so the app still launches and self-heals once the limit
  /// clears, instead of crashing on first frame or stranding every tile offline
  /// with no explanation.
  Future<void> _trySignIn() async {
    try {
      await client.auth.signInAnonymously();
      _signInAttempt = 0;
      _signInRetryTimer?.cancel();
      signedIn.value = true;
      await _rememberUid();
      _log('Anonymous sign-in OK, user_id=${client.auth.currentUser?.id}');
    } catch (e) {
      signedIn.value = false;
      _log('signInAnonymously failed (will retry): $e');
      _scheduleSignInRetry();
    }
  }

  void _scheduleSignInRetry() {
    _signInRetryTimer?.cancel();
    // Anon-sign-in rate-limit windows clear within ~a minute; back off
    // 5 -> 60 s, then keep retrying every 60 s so a stuck install recovers.
    const steps = [5, 10, 20, 40, 60];
    final delay = steps[_signInAttempt.clamp(0, steps.length - 1)];
    _signInAttempt++;
    _signInRetryTimer = Timer(Duration(seconds: delay), () {
      if (!signedIn.value) _trySignIn();
    });
  }

  /// The underlying client for direct table queries.
  SupabaseClient get client => Supabase.instance.client;

  /// Current anonymous user id, or null if not signed in.
  String? get userId => client.auth.currentUser?.id;

  /// Has the client been initialized AND signed in?
  bool get ready => _initialized && userId != null;

  // ── Pairing ────────────────────────────────────────────────────────────────

  /// Claim a printer using an enrollment token, optionally with the Pi's
  /// public key from a scanned v=3 QR. On success returns the Supabase
  /// printer id.
  ///
  /// [piPublicKey] is optional: the QR-scan path supplies it for a
  /// defense-in-depth check against the server-side enrollment row, while
  /// the manual-code-entry path (camera-failure fallback) omits it and
  /// lets the server trust its own stored pubkey.
  ///
  /// Throws:
  ///   • [PairingNotFoundException] for 404 - token expired / used / mismatched
  ///   • [PairingConflictException] for 409 - Pi already paired (run RESET_OWNER)
  ///   • [Exception] for any other failure
  Future<String> claimPrinter({
    required String  enrollmentToken,
    String?          piPublicKey,
    required String  name,
  }) async {
    try {
      final response = await client.functions.invoke(
        'printer-claim',
        body: {
          'enrollment_token': enrollmentToken,
          'name':             name,
          if (piPublicKey != null) 'pi_public_key': piPublicKey,
        },
      );
      final data = response.data;
      if (data is Map && data['printer_id'] is String) {
        return data['printer_id'] as String;
      }
      throw Exception('printer-claim returned unexpected payload: $data');
    } on FunctionException catch (e) {
      // supabase_flutter throws FunctionException for non-2xx before our
      // own status-based checks can run. Translate to our typed exceptions.
      if (e.status == 404) throw PairingNotFoundException();
      if (e.status == 409) throw PairingConflictException();
      throw Exception('printer-claim returned HTTP ${e.status}: ${e.details}');
    }
  }

  // ── Access (per-call tunnel URL + EdDSA token) ─────────────────────────────

  /// Fetch a fresh tunnel URL + access token for [printerId].
  /// The token expires in ~5 minutes; callers should cache and refresh.
  ///
  /// Throws:
  ///   • [PrinterNotFoundException] for 404 - printer doesn't exist or
  ///     isn't owned by this user.
  ///   • [PrinterUnavailableException] for 503 - printer exists but the Pi
  ///     hasn't sent its first heartbeat yet (just paired).
  ///     The exception's [retryAfter] tells the caller how long to wait.
  Future<PrinterAccess> getPrinterAccess(String printerId) async {
    try {
      final response = await client.functions.invoke(
        'printer-access',
        // v0.5.0: accept a token even when the tunnel URL isn't known yet,
        // so the LAN-first path works immediately after pairing. tunnel_url
        // comes back null in that window; we go Local via mDNS and pick up
        // the tunnel in the background once the Pi reports it.
        body: {'printer_id': printerId, 'accept_no_tunnel': true},
      );
      final data = response.data;
      if (data is Map) {
        final tunnel = data['tunnel_url']   as String?; // nullable in v0.5.0
        final token  = data['access_token'] as String?;
        final expIn  = (data['expires_in']  as num?)?.toInt() ?? 300;
        // Only the token is mandatory now - tunnel may legitimately be null.
        if (token != null) {
          return PrinterAccess(
            tunnelUrl:   tunnel,
            accessToken: token,
            expiresAt:   DateTime.now().add(Duration(seconds: expIn)),
          );
        }
      }
      throw Exception('printer-access returned unexpected payload: $data');
    } on FunctionException catch (e) {
      if (e.status == 404) throw PrinterNotFoundException();
      if (e.status == 503) {
        final retry = (e.details is Map
                ? (e.details as Map)['retry_after'] as num?
                : null)
            ?.toInt() ?? 5;
        throw PrinterUnavailableException(retryAfter: retry);
      }
      throw Exception('printer-access returned HTTP ${e.status}: ${e.details}');
    }
  }

  // ── Release (un-pair) ──────────────────────────────────────────────────────

  /// Delete the printer row from Supabase so the same Pi can be re-paired.
  /// Idempotent: a 404 (row already gone, or never owned by us) is treated
  /// as success - the user's intent ("forget this printer") is satisfied
  /// either way.
  ///
  /// Returns true on remote success, false on network/auth failure. The
  /// caller should still clear local state on false so the user isn't
  /// trapped if Supabase is unreachable.
  Future<bool> releasePrinter(String printerId) async {
    try {
      await client.functions.invoke(
        'release-printer',
        body: {'printer_id': printerId},
      );
      _log('Released printer $printerId');
      return true;
    } on FunctionException catch (e) {
      if (e.status == 404) {
        _log('release-printer 404 for $printerId - already gone, treating as success');
        return true;
      }
      _log('release-printer HTTP ${e.status}: ${e.details}');
      return false;
    } catch (e) {
      _log('release-printer failed: $e');
      return false;
    }
  }

  // ── Rename (cloud row) ─────────────────────────────────────────────────────

  /// Write a cloud-paired printer's display name to its Supabase row through
  /// the rename-printer Edge Function (clients can't update the table
  /// directly). The iPhone push title is built server-side from that row, so
  /// without this an in-app rename never reached notifications.
  ///
  /// Returns true once the row carries [name]; a 404 (row gone, or never
  /// ours) also returns true since there is nothing left to rename. False on
  /// network/auth failure so the caller can try again at the next launch.
  Future<bool> renamePrinterInCloud(String printerId, String name) async {
    try {
      await client.functions.invoke(
        'rename-printer',
        body: {'printer_id': printerId, 'name': name},
      );
      _log('Renamed printer $printerId in cloud');
      return true;
    } on FunctionException catch (e) {
      if (e.status == 404) {
        _log('rename-printer 404 for $printerId - no row to rename');
        return true;
      }
      _log('rename-printer HTTP ${e.status}: ${e.details}');
      return false;
    } catch (e) {
      _log('rename-printer failed: $e');
      return false;
    }
  }

  // ── Printers list (RLS-scoped to current user) ─────────────────────────────

  /// Returns the current user's printers as `[(id, name, last_seen)]`.
  /// RLS guarantees this only returns rows where owner_user_id = auth.uid().
  Future<List<RemotePrinterRow>> listMyPrinters() async {
    final rows = await client
        .from('printers')
        .select('id, name, last_seen, created_at')
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map((r) => RemotePrinterRow(
              id:        r['id']   as String,
              name:      r['name'] as String,
              lastSeen:  DateTime.tryParse(r['last_seen'] as String? ?? ''),
              createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
            ))
        .toList();
  }

  // ── Feedback / bug reports ─────────────────────────────────────────────────

  /// Submit an in-app bug report / feedback. Routed through the
  /// submit-feedback Edge Function - clients can't write the feedback table
  /// directly (same lockdown as every other table in this project). The
  /// destination is the feedback table only; a future version could forward
  /// to GitHub from the function without an app change.
  ///
  /// [diagnostics] is a free-form JSON map (app/device info, printer list)
  /// attached to help triage. Throws (FunctionException / network) on failure
  /// so the caller can surface an error; success is silent.
  Future<void> submitFeedback({
    required String comment,
    String? contact,
    String? printerName,
    String? appVersion,
    String? platform,
    Map<String, dynamic> diagnostics = const {},
  }) async {
    await client.functions.invoke(
      'submit-feedback',
      body: {
        'comment': comment,
        if (contact != null && contact.trim().isNotEmpty)
          'contact': contact.trim(),
        if (printerName != null && printerName.isNotEmpty)
          'printer_name': printerName,
        if (appVersion != null) 'app_version': appVersion,
        if (platform != null) 'platform': platform,
        'diagnostics': diagnostics,
      },
    );
    _log('Feedback submitted');
  }

  // ── Push notifications ──────────────────────────────────────────────────────

  /// Register (or refresh) this device's push token via the register-push-token
  /// Edge Function - clients can't write the device_push_tokens table directly
  /// (same lockdown as every other table here). [platform] is 'ios' or
  /// 'android'.
  ///
  /// Best effort: failures are logged, not thrown. A missing notification is
  /// never worth disrupting startup, and the app re-registers on the next
  /// launch anyway.
  Future<void> registerPushToken({
    required String token,
    required String platform,
  }) async {
    try {
      await client.functions.invoke(
        'register-push-token',
        body: {'token': token, 'platform': platform},
      );
      _log('Push token registered ($platform)');
    } catch (e) {
      _log('register-push-token failed (will retry next launch): $e');
    }
  }

  // ── Account deletion ────────────────────────────────────────────────────────

  /// Delete the current anonymous account and every cloud record tied to it
  /// (printers, push tokens, enrollment tokens; bug reports are de-identified).
  /// Backs the in-app "Delete my data" action (App Store guideline 5.1.1(v)).
  ///
  /// After the server deletes the auth user, the local session is invalid, so
  /// we sign out and start a FRESH anonymous identity - the app keeps working
  /// with an empty slate. Throws on failure so the UI can surface an error.
  Future<void> deleteAccount() async {
    await client.functions.invoke('delete-account');
    // A deliberate new identity - not a loss, so no banner and no recovery.
    await _forgetUid();
    _pendingRecovery  = null;
    _lastKnown        = null;
    _deliberateSignOut = true;
    try {
      await client.auth.signOut();
    } finally {
      _deliberateSignOut = false;
    }
    signedIn.value = false;
    _log('Account deleted; signing in fresh anonymous identity');
    await _trySignIn();
  }

  // ── Backup restore grants ──────────────────────────────────────────────────

  /// Mint a single-use restore code for the current identity (called when
  /// exporting a backup). Returns the raw code to embed in the backup file, or
  /// null on failure - export then falls back to a printer-list-only backup.
  Future<String?> createRestoreGrant() async {
    try {
      final res  = await client.functions.invoke('create-restore-grant');
      final data = res.data;
      if (data is Map && data['restore_code'] is String) {
        return data['restore_code'] as String;
      }
      return null;
    } catch (e) {
      _log('createRestoreGrant failed: $e');
      return null;
    }
  }

  /// Redeem a restore code after a reinstall: re-assigns the original
  /// identity's printers to the current anonymous user. Returns the number of
  /// printers reclaimed, or null if the code is invalid / expired / already
  /// used (404) so the caller can fall back to re-pairing.
  Future<int?> redeemRestoreGrant(String code) async {
    try {
      final res  = await client.functions
          .invoke('redeem-restore-grant', body: {'restore_code': code});
      final data  = res.data;
      final count = (data is Map) ? data['count'] : null;
      return count is int ? count : 0;
    } on FunctionException catch (e) {
      if (e.status == 404) return null; // invalid / expired / used code
      rethrow;
    }
  }
}

/// A session as supabase_flutter persisted it: the raw JSON (what
/// `recoverSession` takes) plus the facts the refresh policy decides on.
class _PersistedSession {
  final String       raw;
  final SessionFacts facts;
  const _PersistedSession({required this.raw, required this.facts});
}

/// Result of a /printer-access call.
class PrinterAccess {
  /// Cloudflare tunnel base URL, or null when the Pi hasn't reported one
  /// yet (fresh pair / Pi just rebooted). The access token is still valid
  /// on the LAN in that window - the app goes LAN-first via mDNS and the
  /// tunnel populates on the next heartbeat. A non-null value also doubles
  /// as the "remote access ready" signal surfaced on the tile.
  final String?  tunnelUrl;
  final String   accessToken;
  final DateTime expiresAt;

  /// True once the cloud knows the printer's tunnel URL - i.e. remote
  /// access is available, not just LAN.
  bool get tunnelReady => tunnelUrl != null;

  PrinterAccess({
    required this.tunnelUrl,
    required this.accessToken,
    required this.expiresAt,
  });

  /// True if the token is within [margin] of expiring; refresh if so.
  bool isStale({Duration margin = const Duration(seconds: 30)}) =>
      DateTime.now().isAfter(expiresAt.subtract(margin));
}

/// Minimal Supabase printer row exposed to the rest of the app.
class RemotePrinterRow {
  final String   id;
  final String   name;
  final DateTime? lastSeen;
  final DateTime? createdAt;

  RemotePrinterRow({
    required this.id,
    required this.name,
    this.lastSeen,
    this.createdAt,
  });
}

class PairingNotFoundException implements Exception {
  @override
  String toString() =>
      'Pairing code expired or already used. Run MOONGATE_PAIR on the printer again.';
}

class PairingConflictException implements Exception {
  @override
  String toString() =>
      'This printer is already paired with another account. Run MOONGATE_RESET_OWNER on the Pi.';
}

class PrinterNotFoundException implements Exception {
  @override
  String toString() => 'Printer not found.';
}

class PrinterUnavailableException implements Exception {
  final int retryAfter;
  PrinterUnavailableException({required this.retryAfter});
  @override
  String toString() =>
      'Printer is starting up. Try again in $retryAfter seconds.';
}
