import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  void _log(String msg) => dev.log(msg, name: 'MOONGATE/SUPABASE');

  /// Initialise the Supabase client and ensure there's an authenticated
  /// session. Idempotent - safe to call from main() and re-call after
  /// hot-restart.
  Future<void> initialize() async {
    if (_initialized) return;
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabaseAnonKey,
    );
    _initialized = true;

    if (client.auth.currentSession != null) {
      _log('Existing session, user_id=${client.auth.currentUser?.id}');
      signedIn.value = true;
      return;
    }
    _log('No session yet - signing in anonymously');
    await _trySignIn();
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
    await client.auth.signOut();
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
