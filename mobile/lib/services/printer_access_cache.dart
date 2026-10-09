import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'supabase_service.dart';

/// In-memory cache of `PrinterAccess` results, one per printer_id. Status
/// and control services call [get] before every HTTP request - the cache
/// reuses the same access token until ~30s before expiry, then refreshes.
///
/// Concurrent callers for the same printer share an in-flight Future so
/// we don't fire multiple /printer-access calls during a burst.
class PrinterAccessCache {
  PrinterAccessCache._();
  static final PrinterAccessCache instance = PrinterAccessCache._();

  final Map<String, PrinterAccess>             _cached  = {};
  final Map<String, Future<PrinterAccess>>     _pending = {};
  final Map<String, _NotFoundHold>             _notFound = {};
  final Map<String, RejectHold>                _reject   = {};

  /// Back-off for cached 404 verdicts: first re-probe after 1 min, doubling
  /// to a 15-min ceiling. At the ceiling a dead tile costs 4 Edge calls/hr
  /// instead of ~900, and a printer that legitimately reappears (a restore
  /// re-binding rows to this account) is picked up on the next probe.
  static const _notFoundHoldFirst = Duration(minutes: 1);
  static const _notFoundHoldMax   = Duration(minutes: 15);

  /// Back-off for failure-driven re-mints (a 401 from the Pi, a tunnel blip
  /// before a retry): the first drops the cache at once, repeats are held
  /// 1 min doubling to 15. See [invalidateAfterReject].
  static const _rejectHoldFirst = Duration(minutes: 1);
  static const _rejectHoldMax   = Duration(minutes: 15);

  void _log(String msg) => dev.log(msg, name: 'MOONGATE/ACCESS');

  /// Returns a valid (fresh) `PrinterAccess` for [printerId]. Re-uses the
  /// cached entry if it's not stale; otherwise refreshes via Supabase.
  ///
  /// A 404 ("printer not found") is remembered and re-thrown locally until its
  /// back-off expires, WITHOUT invoking the Edge Function again. A printer
  /// whose cloud row is gone (deleted, or re-paired/restored onto another
  /// account) is invisible to the liveness gate - its row is simply absent
  /// from `last_seen`, which reads as "unknown" and fails open - so before
  /// this hold every 4s dashboard poll minted-and-404'd forever. One such
  /// install was ~⅔ of ALL Edge Function invocations (July 2026 quota blow).
  Future<PrinterAccess> get(String printerId) async {
    // A Direct-added printer's synthetic id ('lan-…', see
    // PrinterConfig.cloudPaired) never has a cloud row - it isn't even a
    // UUID, so the mint can only fail (observed in prod as a 500 every
    // 4 min from the webview cookie refresh). Fail locally, zero Edge cost,
    // whatever call site asks.
    if (printerId.startsWith('lan-')) throw PrinterNotFoundException();

    final cached = _cached[printerId];
    if (cached != null && !cached.isStale()) return cached;

    final hold = _notFound[printerId];
    if (hold != null && DateTime.now().isBefore(hold.until)) {
      throw PrinterNotFoundException();
    }

    // Coalesce concurrent refreshes
    final inflight = _pending[printerId];
    if (inflight != null) return inflight;

    final future = _refresh(printerId);
    _pending[printerId] = future;
    try {
      final access = await future;
      _cached[printerId] = access;
      _notFound.remove(printerId);
      return access;
    } on PrinterNotFoundException {
      final next = hold?.nextHold ?? _notFoundHoldFirst;
      final doubled = next * 2;
      _notFound[printerId] = _NotFoundHold(
        until:    DateTime.now().add(next),
        nextHold: doubled > _notFoundHoldMax ? _notFoundHoldMax : doubled,
      );
      _log('404 for $printerId - holding printer-access probes for '
          '${next.inSeconds}s');
      rethrow;
    } finally {
      _pending.remove(printerId);
    }
  }

  Future<PrinterAccess> _refresh(String printerId) async {
    _log('Refreshing access for $printerId');
    return SupabaseService.instance.getPrinterAccess(printerId);
  }

  /// Drop the cached entry for [printerId] - call after a 401 from the Pi
  /// (the token may be stale despite our local clock saying otherwise). Also
  /// lifts any 404 hold: every call site is a user-driven retry (the error
  /// overlay's Retry, the printer page's refresh), which deserves one real
  /// probe immediately.
  void invalidate(String printerId) {
    _cached.remove(printerId);
    _notFound.remove(printerId);
    _reject.remove(printerId);
  }

  /// Failure-driven invalidate: the Pi rejected the token (401), or a tunnel
  /// request failed and the caller is about to retry. The FIRST one drops the
  /// cache so the retry gets a fresh mint - a token really can be invalidated
  /// server-side - but repeats are held (1 min, doubling to 15), during which
  /// the cached token stays and [get] costs nothing. Before the hold, a
  /// printer whose Pi rejected EVERY token (clock skew failing the replay
  /// window) on a 3 s poll minted 1,110 times an hour from one phone
  /// (Oct 2026); at the ceiling it is 4. Returns true when the cache was
  /// dropped. User-driven retries keep using [invalidate].
  bool invalidateAfterReject(String printerId) {
    final hold = nextRejectHold(_reject[printerId], DateTime.now());
    if (hold == null) {
      _log('reject hold for $printerId - keeping the cached token');
      return false;
    }
    _reject[printerId] = hold;
    _cached.remove(printerId);
    return true;
  }

  /// Pure ladder behind [invalidateAfterReject]: given the printer's previous
  /// hold (null when none) and the current time, the hold to store when the
  /// cache may be dropped now, or null while the previous hold still runs.
  /// A hold that lapsed more than the ceiling ago belongs to an old episode,
  /// so the ladder starts again at one minute instead of at the ceiling.
  @visibleForTesting
  static RejectHold? nextRejectHold(RejectHold? prev, DateTime now) {
    if (prev != null && now.isBefore(prev.until)) return null;
    final fresh   = prev == null || now.isAfter(prev.until.add(_rejectHoldMax));
    final next    = fresh ? _rejectHoldFirst : prev.nextHold;
    final doubled = next * 2;
    return RejectHold(
      until:    now.add(next),
      nextHold: doubled > _rejectHoldMax ? _rejectHoldMax : doubled,
    );
  }

  /// Wipe everything. Called on sign-out / user change.
  void clear() {
    _cached.clear();
    _pending.clear();
    _notFound.clear();
    _reject.clear();
  }
}

/// One remembered "the cloud says this printer doesn't exist" verdict:
/// suppress further Edge calls until [until], and if the next probe 404s
/// again, hold for [nextHold] (doubling toward the ceiling).
class _NotFoundHold {
  final DateTime until;
  final Duration nextHold;
  const _NotFoundHold({required this.until, required this.nextHold});
}

/// One failure-driven re-mint episode for a printer: no further cache drops
/// until [until]; the next drop after that holds for [nextHold].
class RejectHold {
  final DateTime until;
  final Duration nextHold;
  const RejectHold({required this.until, required this.nextHold});
}
