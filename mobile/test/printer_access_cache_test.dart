import 'package:flutter_test/flutter_test.dart';

import 'package:moongate/services/printer_access_cache.dart';
import 'package:moongate/services/supabase_service.dart';

/// A Direct-added printer's synthetic id ('lan-…') has no cloud row by
/// construction, so PrinterAccessCache must refuse it locally - before any
/// Supabase call. In this test environment Supabase is never initialized:
/// if the guard were missing, the lookup would blow up on the uninitialized
/// client instead of throwing the typed not-found, so a pass here proves no
/// network path was reached. (The prod symptom this locks out: the webview
/// cookie refresh minting for 'lan-http---192-168-1-84' every 4 minutes,
/// a 500 per attempt, July 2026.)
void main() {
  test('Direct-mode synthetic id fails locally with PrinterNotFound', () {
    expect(
      () => PrinterAccessCache.instance.get('lan-http---192-168-1-84'),
      throwsA(isA<PrinterNotFoundException>()),
    );
  });

  test('the guard is prefix-anchored, not a substring match', () {
    // A UUID id containing 'lan-' elsewhere must NOT trip the guard; it
    // should fall through toward a real lookup (which here fails on the
    // uninitialized Supabase client - anything but PrinterNotFound).
    expect(
      () => PrinterAccessCache.instance.get('0b5dlan-fake-uuid'),
      throwsA(isNot(isA<PrinterNotFoundException>())),
    );
  });

  // The failure-driven re-mint hold (v0.9.71). One phone polling a printer
  // whose Pi rejected every token (clock skew) every 3 s dropped the cached
  // token and minted a fresh one on EVERY poll: 1,110 printer-access calls
  // an hour from a single client (09/10/2026). The ladder below caps a
  // permanently-wedged printer at 4 mints an hour.
  group('nextRejectHold ladder', () {
    final t0 = DateTime(2026, 10, 9, 21);

    test('the first reject drops the cache and opens a 1-minute hold', () {
      final h = PrinterAccessCache.nextRejectHold(null, t0);
      expect(h, isNotNull);
      expect(h!.until, t0.add(const Duration(minutes: 1)));
      expect(h.nextHold, const Duration(minutes: 2));
    });

    test('a repeat inside the hold keeps the token (null = no drop)', () {
      final h = PrinterAccessCache.nextRejectHold(null, t0)!;
      expect(PrinterAccessCache.nextRejectHold(
          h, t0.add(const Duration(seconds: 3))), isNull);
      expect(PrinterAccessCache.nextRejectHold(
          h, t0.add(const Duration(seconds: 59))), isNull);
      expect(PrinterAccessCache.nextRejectHold(
          h, t0.add(const Duration(seconds: 60))), isNotNull);
    });

    test('the ladder doubles to a 15-minute ceiling', () {
      RejectHold? h;
      var now = t0;
      final minutes = <int>[];
      for (var i = 0; i < 8; i++) {
        h = PrinterAccessCache.nextRejectHold(h, now)!;
        minutes.add(h.until.difference(now).inMinutes);
        now = h.until; // the next reject lands the moment the hold lapses
      }
      expect(minutes, [1, 2, 4, 8, 15, 15, 15, 15]);
    });

    test('a 3-second poll against a permanent 401: 7 mints in the first '
        'hour, 4 an hour after that', () {
      RejectHold? h;
      var drops1 = 0, drops2 = 0;
      for (var s = 0; s < 7200; s += 3) {
        final now = t0.add(Duration(seconds: s));
        final next = PrinterAccessCache.nextRejectHold(h, now);
        if (next != null) {
          h = next;
          if (s < 3600) {
            drops1++;
          } else {
            drops2++;
          }
        }
      }
      expect(drops1, 7); // 0, 1, 3, 7, 15, 30, 45 min
      expect(drops2, 4);
    });

    test('a lapsed episode starts the ladder again at one minute', () {
      const ceiling = Duration(minutes: 15);
      final old = RejectHold(until: t0, nextHold: ceiling);
      // Rejected again just after the hold: the ladder continues (15 min).
      final t1   = t0.add(const Duration(seconds: 1));
      final soon = PrinterAccessCache.nextRejectHold(old, t1)!;
      expect(soon.until.difference(t1), ceiling);
      // Rejected again long after: a fresh episode, back to 1 min.
      final t2   = t0.add(const Duration(minutes: 16));
      final late = PrinterAccessCache.nextRejectHold(old, t2)!;
      expect(late.until.difference(t2), const Duration(minutes: 1));
      expect(late.nextHold, const Duration(minutes: 2));
    });
  });

  group('invalidateAfterReject on the instance', () {
    const id = '0f0f0f0f-0000-4000-8000-000000000001';

    test('first drop true, repeat false, a user-driven invalidate lifts it',
        () {
      final c = PrinterAccessCache.instance;
      expect(c.invalidateAfterReject(id), isTrue);
      expect(c.invalidateAfterReject(id), isFalse);
      c.invalidate(id);
      expect(c.invalidateAfterReject(id), isTrue);
      c.clear();
      expect(c.invalidateAfterReject(id), isTrue);
      c.clear();
    });
  });
}
