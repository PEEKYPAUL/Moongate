import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:go_router/go_router.dart';

/// Tap-to-pair: routes OS-delivered `moongate://` links into the pairing
/// screen.
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

  /// Idempotent. Wired from the app root, which owns the router.
  void start(GoRouter router) {
    _sub ??= AppLinks().uriLinkStream.listen((uri) {
      if (!isPairingUri(uri)) return;
      final now = DateTime.now();
      if (uri == _lastUri &&
          _lastAt != null &&
          now.difference(_lastAt!) < const Duration(seconds: 2)) {
        return;
      }
      _lastUri = uri;
      _lastAt  = now;
      // Land on the dashboard first so the pairing screen pops back to it
      // from every entry point (cold start included - this also cancels the
      // splash's own pending hop, its navigation is mounted-guarded).
      router.go('/dashboard');
      router.push('/pair', extra: uri.toString());
    });
  }
}
