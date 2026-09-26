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

/// True when [url] is an http(s) link into a private / local network - the
/// printer's own network. Over the tunnel the phone is away from that
/// network, so such a link (Spoolman on the Pi, a camera's LAN address)
/// cannot be reached; the printer screen says so instead of opening a
/// browser tab that fails. Non-web schemes are never "on a network".
bool linkIsOnPrinterNetwork(String url) {
  final u = Uri.tryParse(url);
  if (u == null || (u.scheme != 'http' && u.scheme != 'https')) return false;
  return isPrinterNetworkHost(u.host);
}

/// True for a host that only exists on a private / local network: RFC 1918
/// IPv4 (10/8, 172.16/12, 192.168/16), link-local 169.254/16 and loopback,
/// IPv6 unique-local (fc00::/7), link-local (fe80::/10) and `::1`,
/// `localhost`, mDNS `.local`, the `.lan` / `.home` / `.internal` /
/// `.localdomain` conventions, and any bare single-label name (`voron24`).
bool isPrinterNetworkHost(String host) {
  var h = host.trim().toLowerCase();
  if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length - 1);
  if (h.isEmpty) return false;

  final v4 = _ipv4Octets(h);
  if (v4 != null) {
    final a = v4[0], b = v4[1];
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 169 && b == 254) ||
        a == 127;
  }
  if (h.contains(':')) {
    // IPv6: unique-local fc00::/7, link-local fe80::/10, loopback.
    if (h == '::1') return true;
    if (h.startsWith('fc') || h.startsWith('fd')) return true;
    return h.startsWith('fe8') ||
        h.startsWith('fe9') ||
        h.startsWith('fea') ||
        h.startsWith('feb');
  }
  if (h == 'localhost') return true;
  for (final suffix in const [
    '.local', '.lan', '.home', '.internal', '.localdomain'
  ]) {
    if (h.endsWith(suffix)) return true;
  }
  return !h.contains('.'); // a bare hostname only resolves on its own LAN
}

List<int>? _ipv4Octets(String h) {
  final parts = h.split('.');
  if (parts.length != 4) return null;
  final out = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return null;
    out.add(n);
  }
  return out;
}
