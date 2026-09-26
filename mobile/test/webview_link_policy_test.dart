import 'package:flutter_test/flutter_test.dart';

import 'package:moongate/services/webview_link_policy.dart';

/// Locks the printer-WebView link policy: the printer's own origin stays in
/// the WebView, everything a desktop browser would open in a new tab goes to
/// the phone's browser. From two live reports (26/09/2026): a GitHub commit
/// link in Mainsail's Update Manager took the kept-warm WebView to github.com
/// for good, and the AFC panel's Spoolman link (same Pi, port 7912) had no
/// way back.
void main() {
  const lan    = 'http://192.168.1.251';
  const tunnel = 'https://calm-otter-flying.trycloudflare.com';

  group('the printer\'s own origin stays in the WebView', () {
    test('Mainsail routes and Moonraker paths on the LAN address', () {
      for (final url in [
        'http://192.168.1.251/',
        'http://192.168.1.251/machine',
        'http://192.168.1.251/#/console',
        'http://192.168.1.251/server/files/gcodes/part.gcode',
        'http://192.168.1.251/moongate-pair.html',
      ]) {
        expect(classifyWebLink(baseUrl: lan, url: url),
            WebLinkTarget.inWebView, reason: url);
      }
    });

    test('an explicit :80 is the same origin as no port', () {
      expect(classifyWebLink(baseUrl: lan, url: 'http://192.168.1.251:80/'),
          WebLinkTarget.inWebView);
      expect(
          classifyWebLink(
              baseUrl: 'http://192.168.1.251:80', url: 'http://192.168.1.251/'),
          WebLinkTarget.inWebView);
    });

    test('the tunnel origin, host case-insensitive', () {
      expect(classifyWebLink(baseUrl: tunnel, url: '$tunnel/machine'),
          WebLinkTarget.inWebView);
      expect(
          classifyWebLink(
              baseUrl: tunnel,
              url: 'https://Calm-Otter-Flying.trycloudflare.com/'),
          WebLinkTarget.inWebView);
    });

    test('a Direct-mode address with a custom port', () {
      expect(
          classifyWebLink(
              baseUrl: 'http://printer.lan:8080',
              url: 'http://printer.lan:8080/machine'),
          WebLinkTarget.inWebView);
    });

    test('the site switching http <-> https on the standard ports', () {
      expect(classifyWebLink(baseUrl: lan, url: 'https://192.168.1.251/'),
          WebLinkTarget.inWebView);
      expect(
          classifyWebLink(
              baseUrl: 'https://voron24.local', url: 'http://voron24.local/'),
          WebLinkTarget.inWebView);
    });

    test('page internals are never sent outside', () {
      for (final url in [
        'about:blank',
        'blob:http://192.168.1.251/2f4e1a0c',
        'data:text/html,<p>hi</p>',
        'javascript:void(0)',
      ]) {
        expect(classifyWebLink(baseUrl: lan, url: url),
            WebLinkTarget.inWebView, reason: url);
      }
    });

    test('anything we cannot judge stays put', () {
      expect(classifyWebLink(baseUrl: lan, url: '/relative/path'),
          WebLinkTarget.inWebView);
      expect(classifyWebLink(baseUrl: lan, url: ''), WebLinkTarget.inWebView);
      expect(classifyWebLink(baseUrl: lan, url: 'http://[bad'),
          WebLinkTarget.inWebView);
      // A base with no scheme or host gives nothing to compare against - the
      // policy must never block the printer page itself.
      expect(classifyWebLink(baseUrl: '', url: 'https://github.com/'),
          WebLinkTarget.inWebView);
      expect(
          classifyWebLink(baseUrl: '192.168.1.251', url: 'http://192.168.1.251/'),
          WebLinkTarget.inWebView);
    });
  });

  group('what a browser would open in a new tab goes to the phone\'s browser',
      () {
    test('the Update Manager commit link (Schlonky\'s recording)', () {
      expect(
          classifyWebLink(
              baseUrl: lan,
              url: 'https://github.com/PEEKYPAUL/Moongate/commit/c64e6e2'),
          WebLinkTarget.externalBrowser);
      expect(
          classifyWebLink(
              baseUrl: tunnel,
              url: 'https://github.com/PEEKYPAUL/Moongate/commit/c64e6e2'),
          WebLinkTarget.externalBrowser);
    });

    test('the AFC panel\'s Spoolman link: same Pi, port 7912 (MC-red)', () {
      expect(classifyWebLink(baseUrl: lan, url: 'http://192.168.1.251:7912/'),
          WebLinkTarget.externalBrowser);
    });

    test('other services on the same host: go2rtc, Moonraker direct', () {
      expect(
          classifyWebLink(
              baseUrl: lan,
              url: 'http://192.168.1.251:1984/api/stream.mjpeg?src=camera'),
          WebLinkTarget.externalBrowser);
      expect(
          classifyWebLink(
              baseUrl: lan, url: 'http://192.168.1.251:7125/server/info'),
          WebLinkTarget.externalBrowser);
    });

    test('an https link to a non-standard port is not the TLS-redirect case',
        () {
      expect(
          classifyWebLink(baseUrl: lan, url: 'https://192.168.1.251:8443/'),
          WebLinkTarget.externalBrowser);
    });

    test('the Mainsail docs, a LAN address from the tunnel, localhost', () {
      expect(
          classifyWebLink(
              baseUrl: lan, url: 'https://docs.mainsail.xyz/overview'),
          WebLinkTarget.externalBrowser);
      expect(classifyWebLink(baseUrl: tunnel, url: 'http://192.168.1.251/'),
          WebLinkTarget.externalBrowser);
      expect(classifyWebLink(baseUrl: lan, url: 'http://localhost:7125/'),
          WebLinkTarget.externalBrowser);
    });

    test('mailto:, tel: and other app schemes', () {
      expect(classifyWebLink(baseUrl: lan, url: 'mailto:help@example.com'),
          WebLinkTarget.externalBrowser);
      expect(classifyWebLink(baseUrl: lan, url: 'tel:+441234567890'),
          WebLinkTarget.externalBrowser);
    });
  });

  // Over the tunnel a link into the printer's own network cannot be reached,
  // so the printer screen shows a note instead of a browser tab that fails.
  group('links into the printer\'s own network', () {
    test('private, link-local and loopback IPv4 hosts', () {
      for (final host in [
        '192.168.1.251',
        '10.0.0.5',
        '172.16.0.1',
        '172.31.255.254',
        '169.254.1.1',
        '127.0.0.1',
      ]) {
        expect(isPrinterNetworkHost(host), isTrue, reason: host);
      }
    });

    test('public IPv4 and the 172.x neighbours outside /12', () {
      for (final host in ['8.8.8.8', '172.15.0.1', '172.32.0.1', '1.1.1.1']) {
        expect(isPrinterNetworkHost(host), isFalse, reason: host);
      }
    });

    test('IPv6 unique-local, link-local and loopback, with or without []', () {
      for (final host in ['fd12:3456::1', 'fc00::1', 'fe80::1', '::1',
          '[fe80::1]']) {
        expect(isPrinterNetworkHost(host), isTrue, reason: host);
      }
      expect(isPrinterNetworkHost('2001:db8::1'), isFalse);
    });

    test('local names: mDNS, LAN conventions, a bare hostname, localhost', () {
      for (final host in ['voron24.local', 'VORON24.LOCAL', 'k3.lan',
          'printer.home', 'pi.internal', 'voron24', 'localhost']) {
        expect(isPrinterNetworkHost(host), isTrue, reason: host);
      }
    });

    test('internet names are not', () {
      for (final host in ['github.com', 'docs.mainsail.xyz',
          'calm-otter-flying.trycloudflare.com']) {
        expect(isPrinterNetworkHost(host), isFalse, reason: host);
      }
    });

    test('only web links count', () {
      expect(linkIsOnPrinterNetwork('http://192.168.1.251:7912/'), isTrue);
      expect(linkIsOnPrinterNetwork('http://voron24.local:1984/'), isTrue);
      expect(linkIsOnPrinterNetwork('https://github.com/PEEKYPAUL/Moongate'),
          isFalse);
      expect(linkIsOnPrinterNetwork('mailto:pi@192.168.1.251'), isFalse);
      expect(linkIsOnPrinterNetwork('not a url'), isFalse);
    });
  });
}
