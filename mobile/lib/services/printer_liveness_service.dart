import 'dart:async';
import 'dart:developer' as dev;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Tracks each printer's cloud-reported liveness (`last_seen`, bumped by the
/// Pi's heartbeat) so the dashboard can tell online from offline WITHOUT
/// spending an Edge Function call.
///
/// `/printer-access` (which mints the per-call access token) is an Edge Function
/// and was the dominant Supabase invocation cost - and the app was calling it on
/// every poll even for printers that are powered off. Reading `last_seen` over
/// Supabase **Realtime** (or via a plain RLS-scoped SELECT) is NOT an Edge
/// Function invocation, so the poll loop can consult this first and skip the
/// token mint for an offline printer entirely → an offline Pi costs zero
/// Edge Function calls. See [PrinterStatusService] for the gate.
///
/// Liveness is learned three ways, most→least responsive:
///   1. a Realtime subscription that pushes every `last_seen` change,
///   2. an initial RLS-scoped SELECT to seed current state on start, and
///   3. a periodic re-seed (safety net for a dropped/reconnected websocket,
///      which doesn't replay missed events).
///
/// Degrades gracefully: if the `printers` table isn't in the Realtime
/// publication yet (migration not applied), the subscription simply receives
/// nothing and the periodic re-seed keeps state fresh.
class PrinterLivenessService {
  PrinterLivenessService._();
  static final PrinterLivenessService instance = PrinterLivenessService._();

  /// A printer counts as cloud-online if its `last_seen` is within this window.
  /// The Pi heartbeats every 5 min in steady state, so 2× + slack avoids
  /// flapping a healthy printer to "offline" between heartbeats.
  static const _onlineWindow = Duration(minutes: 12);

  /// How often to re-read the whole fleet's `last_seen` as a safety net for a
  /// Realtime reconnect gap (Realtime doesn't replay events missed while down).
  /// One RLS-scoped SELECT for all the user's rows - not an Edge Function.
  static const _reseedEvery = Duration(minutes: 5);

  final Map<String, DateTime> _lastSeen = {};
  RealtimeChannel? _channel;
  Timer? _reseedTimer;
  bool _started = false;

  /// Coalesces a burst of [refresh] calls (every dashboard tile fires one on
  /// app resume) into a single in-flight SELECT.
  Future<void>? _refreshing;

  void _log(String msg) => dev.log(msg, name: 'MOONGATE/LIVENESS');

  /// True only when we have a `last_seen` for [printerId] AND it's older than
  /// [_onlineWindow] - i.e. positive evidence the printer is offline. Returns
  /// false when `last_seen` is unknown (not seeded yet / never heartbeated), so
  /// the caller fails OPEN (polls) rather than wrongly showing a live printer
  /// offline just because we haven't learned its state yet.
  bool isKnownOffline(String printerId) {
    final ts = _lastSeen[printerId];
    if (ts == null) return false;
    return DateTime.now().toUtc().difference(ts) >= _onlineWindow;
  }

  /// Most recent known `last_seen` for [printerId] (diagnostics), or null.
  DateTime? lastSeen(String printerId) => _lastSeen[printerId];

  /// Seed current state + subscribe to live changes. Idempotent. Safe to call
  /// before sign-in completes - it registers a one-shot retry for when the
  /// anonymous session lands.
  Future<void> start() async {
    if (_started) return;
    final uid = SupabaseService.instance.userId;
    if (uid == null) {
      // Not signed in yet - retry when the anon session arrives.
      SupabaseService.instance.signedIn.addListener(_onSignedIn);
      return;
    }
    _started = true;
    await _reseed();
    _subscribe(uid);
    _reseedTimer?.cancel();
    _reseedTimer = Timer.periodic(_reseedEvery, (_) => _reseed());
    _log('started (owner=$uid)');
  }

  void _onSignedIn() {
    if (SupabaseService.instance.signedIn.value && !_started) {
      SupabaseService.instance.signedIn.removeListener(_onSignedIn);
      start();
    }
  }

  /// Re-read the fleet's `last_seen` now, out of the periodic cadence. Call on
  /// app resume: while backgrounded the OS can freeze the process, dropping the
  /// Realtime socket and suspending the re-seed timer, so [_lastSeen] (and thus
  /// [isKnownOffline]) can hold a stale 'offline' verdict for a printer that has
  /// since come back on - the exact case where the poll gate would keep the tile
  /// offline until a cold start. A fresh SELECT corrects it before the status
  /// poll re-runs. Starts the service instead if it never came up (no session at
  /// launch). Concurrent calls share one SELECT.
  Future<void> refresh() {
    if (!_started) return start();
    return _refreshing ??= _reseed().whenComplete(() => _refreshing = null);
  }

  /// Read every owned printer's `last_seen` in one RLS-scoped query (PostgREST,
  /// not an Edge Function). Best-effort: a failure just leaves the existing map.
  Future<void> _reseed() async {
    try {
      final rows = await SupabaseService.instance.client
          .from('printers')
          .select('id, last_seen');
      for (final r in rows as List) {
        _apply(r as Map);
      }
      _log('re-seeded (${_lastSeen.length} known)');
    } catch (e) {
      _log('re-seed failed (Realtime + LAN probe still cover it): $e');
    }
  }

  void _subscribe(String uid) {
    _channel?.unsubscribe();
    final channel = SupabaseService.instance.client
        .channel('printers-liveness')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'printers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'owner_user_id',
            value: uid,
          ),
          callback: (payload) => _apply(payload.newRecord),
        )
        .subscribe();
    _channel = channel;
  }

  /// Merge one printers row (from a SELECT or a Realtime payload) into the map.
  void _apply(Map record) {
    final id = record['id'] as String?;
    final raw = record['last_seen'] as String?;
    if (id == null || raw == null) return; // DELETE payloads carry no new row
    final ts = DateTime.tryParse(raw);
    if (ts != null) _lastSeen[id] = ts.toUtc();
  }
}
