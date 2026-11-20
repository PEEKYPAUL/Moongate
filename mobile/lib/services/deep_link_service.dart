import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:go_router/go_router.dart';

import 'printer_registry.dart';

/// Routes OS-delivered `moongate://` links: tap-to-pair into the pairing
/// screen, and (v0.9.79) the home-screen widget's taps into the dashboard or
/// a printer.
///
/// The Pi's moongate-pair.html renders its QR payload as a tappable link for
/// the no-second-screen case (the phone that should pair is the one showing
/// the page, e.g. over Tailscale - it can't scan its own screen). The OS hands
/// the URI here via app_links; we navigate to the pairing screen, which runs
/// it through the exact parser the QR scanner uses. The app lock is untouched:
/// its overlay sits above the router, so a link tapped while locked just waits
/// behind the lock screen like any other navigation.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  StreamSubscription<Uri>? _sub;

  // uriLinkStream replays the launching link as well as delivering foreground
  // taps, but some platforms surface a cold-start link through BOTH that
  // replay and the initial-link API. Remember the last handled link briefly so
  // one tap can't stage the pairing form twice.
  Uri?      _lastUri;
  DateTime? _lastAt;

  /// True for the two pairing payloads the app understands. Anything else
  /// carrying our scheme (typo'd host, future payloads from a newer Pi) is
  /// ignored rather than dumped on the pairing screen as an error.
  static bool isPairingUri(Uri uri) =>
      uri.scheme == 'moongate' && (uri.host == 'pair' || uri.host == 'lan');

  /// The home-screen widget's two tap targets, on the same scheme the pair
  /// links use so one intent filter and one delivery path serve both:
  ///   • `moongate://dashboard`      - empty widget space;
  ///   • `moongate://printer/<id>`   - a printer's row / ring.
  static bool isWidgetUri(Uri uri) =>
      uri.scheme == 'moongate' &&
      (uri.host == 'dashboard' || uri.host == 'printer');

  /// The printer id a widget link names, or null for the dashboard link and
  /// for a malformed printer link (no id, or extra path).
  static String? widgetPrinterId(Uri uri) {
    if (uri.scheme != 'moongate' || uri.host != 'printer') return null;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segs.length == 1 ? segs.single : null;
  }

  /// Idempotent. Wired from the app root, which owns the router.
  void start(GoRouter router) {
    _sub ??= AppLinks().uriLinkStream.listen((uri) {
      final pairing = isPairingUri(uri);
      if (!pairing && !isWidgetUri(uri)) return;
      final now = DateTime.now();
      if (uri == _lastUri &&
          _lastAt != null &&
          now.difference(_lastAt!) < const Duration(seconds: 2)) {
        return;
      }
      _lastUri = uri;
      _lastAt  = now;
      // Land on the dashboard first so the next screen pops back to it from
      // every entry point (cold start included - this also cancels the
      // splash's own pending hop, its navigation is mounted-guarded).
      router.go('/dashboard');
      if (pairing) {
        router.push('/pair', extra: uri.toString());
        return;
      }
      // Widget tap: open the printer when it still exists (the registry is
      // loaded before the first frame, so a cold start resolves it too); a
      // removed printer's stale widget row just lands on the dashboard.
      final id = widgetPrinterId(uri);
      if (id != null &&
          PrinterRegistry.instance.printers.any((p) => p.id == id)) {
        router.push('/printer/$id');
      }
    });
  }
}
