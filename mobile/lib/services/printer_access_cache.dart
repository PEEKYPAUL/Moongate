import 'dart:async';
import 'dart:developer' as dev;

import 'supabase_service.dart';

/// In-memory cache of `PrinterAccess` results, one per printer_id. Status
/// and control services call [get] before every HTTP request — the cache
/// reuses the same access token until ~30s before expiry, then refreshes.
///
/// Concurrent callers for the same printer share an in-flight Future so
/// we don't fire multiple /printer-access calls during a burst.
class PrinterAccessCache {
  PrinterAccessCache._();
  static final PrinterAccessCache instance = PrinterAccessCache._();

  final Map<String, PrinterAccess>             _cached  = {};
  final Map<String, Future<PrinterAccess>>     _pending = {};

  void _log(String msg) => dev.log(msg, name: 'MOONGATE/ACCESS');

  /// Returns a valid (fresh) `PrinterAccess` for [printerId]. Re-uses the
  /// cached entry if it's not stale; otherwise refreshes via Supabase.
  Future<PrinterAccess> get(String printerId) async {
    final cached = _cached[printerId];
    if (cached != null && !cached.isStale()) return cached;

    // Coalesce concurrent refreshes
    final inflight = _pending[printerId];
    if (inflight != null) return inflight;

    final future = _refresh(printerId);
    _pending[printerId] = future;
    try {
      final access = await future;
      _cached[printerId] = access;
      return access;
    } finally {
      _pending.remove(printerId);
    }
  }

  Future<PrinterAccess> _refresh(String printerId) async {
    _log('Refreshing access for $printerId');
    return SupabaseService.instance.getPrinterAccess(printerId);
  }

  /// Drop the cached entry for [printerId] — call after a 401 from the Pi
  /// (the token may be stale despite our local clock saying otherwise).
  void invalidate(String printerId) {
    _cached.remove(printerId);
  }

  /// Wipe everything. Called on sign-out / user change.
  void clear() {
    _cached.clear();
    _pending.clear();
  }
}
