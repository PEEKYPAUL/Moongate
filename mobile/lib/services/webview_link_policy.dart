/// Where a navigation requested inside the printer WebView should go.
///
/// The printer screen's WebView exists to show one site: the printer's own web
/// UI (Mainsail / Fluidd) at the session's base address - a LAN address, a
/// Direct-mode address or the tunnel. Both UIs are single-page apps that never
/// navigate the main frame themselves, so a main-frame navigation request
/// means the user tapped a link. A link to the printer's own origin stays in
/// the WebView. Anything else is what a desktop browser would open in a new
/// tab - a GitHub commit in Mainsail's Update Manager, the AFC panel's Spoolman
/// link (same host, another port), the Mainsail docs, a mailto: - so it goes
/// to the phone's browser and the WebView stays on the printer.
///
/// Why it matters: the controller is kept warm in `PrinterWebViewCache`, so
/// once it had followed such a link the printer "became" that page - Back
/// returned to the dashboard, re-opening the printer showed GitHub again, and
/// nothing in Moongate led back to Mainsail (Schlonky's recording and MC-red's
/// AFC -> Spoolman report, 26/09/2026).
library;

enum WebLinkTarget {
  /// Let the WebView load it: the printer's own pages, page internals.
  inWebView,

  /// Hand it to the phone's browser and keep the WebView where it is.
  externalBrowser,
}

/// Schemes a page uses for its own internals, never a place the user "goes".
const _pageInternalSchemes = {'about', 'blob', 'data', 'javascript', 'file'};

/// Classify [url], a main-frame navigation request, against [baseUrl], the
/// address the printer's web UI was loaded from.
///
/// Rules, in order:
/// - Anything unparseable, relative, or with no usable base: stay in the
///   WebView. This function must never block the printer page itself.
/// - Page-internal schemes (`about:blank`, `blob:`, `data:`, `javascript:`):
///   stay.
/// - Any other non-http(s) scheme (`mailto:`, `tel:`, `intent:`): the phone
///   has an app for it, the WebView does not.
/// - Same host and port as the base: the printer's own origin, stay.
/// - Same host, other port: another service on the Pi (Spoolman on 7912,
///   go2rtc on 1984, Moonraker on 7125), open outside. The one exception is
///   the site itself moving between http and https on their standard ports
///   (a printer whose nginx redirects to TLS) - still the printer.
/// - Any other host: outside.
WebLinkTarget classifyWebLink({required String baseUrl, required String url}) {
  final target = Uri.tryParse(url);
  final base   = Uri.tryParse(baseUrl);
  if (target == null || !target.hasScheme) return WebLinkTarget.inWebView;
  if (base == null || !base.hasScheme || base.host.isEmpty) {
    return WebLinkTarget.inWebView;
  }

  final scheme = target.scheme.toLowerCase();
  if (_pageInternalSchemes.contains(scheme)) return WebLinkTarget.inWebView;
  if (scheme != 'http' && scheme != 'https') {
    return WebLinkTarget.externalBrowser;
  }

  if (target.host.toLowerCase() != base.host.toLowerCase()) {
    return WebLinkTarget.externalBrowser;
  }
  if (target.port == base.port) return WebLinkTarget.inWebView;
  return _onStandardPort(base) && _onStandardPort(target)
      ? WebLinkTarget.inWebView
      : WebLinkTarget.externalBrowser;
}

bool _onStandardPort(Uri u) =>
    (u.scheme == 'http' && u.port == 80) ||
    (u.scheme == 'https' && u.port == 443);
