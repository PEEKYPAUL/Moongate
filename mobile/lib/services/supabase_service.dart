import 'dart:async';
import 'dart:developer' as dev;

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
  // The anon key is intentionally embedded in the APK — it grants only
  // anon-role permissions, all of which are locked down to "your own rows"
  // by Row-Level Security policies. Service role is NEVER in the app.
  static const _supabaseUrl     = 'https://wlmmaoupmupbrrkcjglj.supabase.co';
  static const _supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndsbW1hb3VwbXVwYnJya2NqZ2xqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2NTAyMzYsImV4cCI6MjA5NTIyNjIzNn0.EnIxrykASzZCBBCJtDVJetiWBFKGgFTQDRdkyhBCasw';

  bool _initialized = false;

  void _log(String msg) => dev.log(msg, name: 'MOONGATE/SUPABASE');

  /// Initialise the Supabase client and ensure there's an authenticated
  /// session. Idempotent — safe to call from main() and re-call after
  /// hot-restart.
  Future<void> initialize() async {
    if (_initialized) return;
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );
    _initialized = true;

    final existing = client.auth.currentSession;
    if (existing == null) {
      _log('No session yet — signing in anonymously');
      try {
        await client.auth.signInAnonymously();
        _log('Anonymous sign-in OK, user_id=${client.auth.currentUser?.id}');
      } catch (e) {
        _log('signInAnonymously failed: $e');
        rethrow;
      }
    } else {
      _log('Existing session, user_id=${existing.user.id}');
    }
  }

  /// The underlying client for direct table queries.
  SupabaseClient get client => Supabase.instance.client;

  /// Current anonymous user id, or null if not signed in.
  String? get userId => client.auth.currentUser?.id;

  /// Has the client been initialized AND signed in?
  bool get ready => _initialized && userId != null;

  // ── Pairing ────────────────────────────────────────────────────────────────

  /// Claim a printer using the enrollment token and Pi public key from a
  /// scanned v=3 QR. On success returns the Supabase printer id.
  ///
  /// Throws:
  ///   • [PairingNotFoundException] for 404 — token expired / used / mismatched
  ///   • [PairingConflictException] for 409 — Pi already paired (run RESET_OWNER)
  ///   • [Exception] for any other failure
  Future<String> claimPrinter({
    required String enrollmentToken,
    required String piPublicKey,
    required String name,
  }) async {
    try {
      final response = await client.functions.invoke(
        'printer-claim',
        body: {
          'enrollment_token': enrollmentToken,
          'pi_public_key':    piPublicKey,
          'name':             name,
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
  ///   • [PrinterNotFoundException] for 404 — printer doesn't exist or
  ///     isn't owned by this user.
  ///   • [PrinterUnavailableException] for 503 — printer exists but the Pi
  ///     hasn't sent its first heartbeat yet (just paired).
  ///     The exception's [retryAfter] tells the caller how long to wait.
  Future<PrinterAccess> getPrinterAccess(String printerId) async {
    try {
      final response = await client.functions.invoke(
        'printer-access',
        body: {'printer_id': printerId},
      );
      final data = response.data;
      if (data is Map) {
        final tunnel = data['tunnel_url']   as String?;
        final token  = data['access_token'] as String?;
        final expIn  = (data['expires_in']  as num?)?.toInt() ?? 300;
        if (tunnel != null && token != null) {
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
  /// as success — the user's intent ("forget this printer") is satisfied
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
        _log('release-printer 404 for $printerId — already gone, treating as success');
        return true;
      }
      _log('release-printer HTTP ${e.status}: ${e.details}');
      return false;
    } catch (e) {
      _log('release-printer failed: $e');
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
}

/// Result of a /printer-access call.
class PrinterAccess {
  final String   tunnelUrl;
  final String   accessToken;
  final DateTime expiresAt;

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
