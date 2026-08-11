import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moongate/services/lan_discovery_service.dart';

// The mDNS host -> LAN URL gate. The field failure (2026-07-27 bug report):
// Android's resolver answered a browse with `fe80::4684:2651:1a53:50f6%wlan0`,
// the service stored it verbatim, and because a discovered URL outranks the
// persisted lanUrl everywhere, a printer sitting on the same subnet as the
// phone rode the tunnel forever. Unusable hosts must never enter the map -
// lookup() then answers null and every consumer falls back to the persisted
// address, which works.

void main() {
  test('IPv4 hosts pass through, port 80 elided', () {
    expect(LanDiscoveryService.urlForHost('192.168.1.105', 80),
        'http://192.168.1.105');
    expect(LanDiscoveryService.urlForHost('192.168.1.105', 7125),
        'http://192.168.1.105:7125');
  });

  test('mDNS hostnames pass through', () {
    expect(LanDiscoveryService.urlForHost('mainsailos.local', 80),
        'http://mainsailos.local');
  });

  test('zone-indexed hosts are rejected whatever the address', () {
    expect(
        LanDiscoveryService.urlForHost(
            'fe80::4684:2651:1a53:50f6%wlan0', 80),
        isNull);
    expect(LanDiscoveryService.urlForHost('2001:db8::1%eth0', 80), isNull);
  });

  test('IPv6 link-local is rejected across the fe80::/10 range, any case', () {
    expect(LanDiscoveryService.urlForHost('fe80::1', 80), isNull);
    expect(LanDiscoveryService.urlForHost('FE80::1', 80), isNull);
    expect(LanDiscoveryService.urlForHost('febf::1', 80), isNull);
    expect(LanDiscoveryService.urlForHost('fe9a::1', 80), isNull);
  });

  test('routable IPv6 is kept and bracketed', () {
    expect(LanDiscoveryService.urlForHost('2001:db8::1', 80),
        'http://[2001:db8::1]');
    expect(LanDiscoveryService.urlForHost('2001:db8::1', 7125),
        'http://[2001:db8::1]:7125');
    // fd00::/8 unique-local is routable on a site - keep it.
    expect(LanDiscoveryService.urlForHost('fd12:3456::1', 80),
        'http://[fd12:3456::1]');
    // "fe" in the first hextet but outside fe80::/10 is NOT link-local.
    expect(LanDiscoveryService.urlForHost('fec0::1', 80),
        'http://[fec0::1]');
  });

  // The resolved-address pick order (#268). iOS/bonsoir answers a browse
  // with the advertised hostname (`voron24.local.`, trailing dot) rather
  // than an address; stored verbatim it strands the printer page - inside
  // WKWebView, Mainsail's Moonraker websocket resolves the name AAAA-first
  // with no IPv4 fallback while MainsailOS nginx listens on IPv4 only. The
  // service now resolves the name and stores a concrete address instead.

  test('pick order: IPv4 wins even when the resolver lists AAAA first', () {
    // The field case verified on the Voron 2.4: the name resolved to a
    // unique-local IPv6 AND an IPv4; the websocket died on the IPv6.
    expect(
        LanDiscoveryService.pickResolvedHost('voron24.local.', [
          InternetAddress('fde4:8dba:82e1::c4'),
          InternetAddress('192.168.1.251'),
        ]),
        '192.168.1.251');
  });

  test('pick order: first IPv4 wins among several', () {
    expect(
        LanDiscoveryService.pickResolvedHost('mainsailos.local', [
          InternetAddress('192.168.1.10'),
          InternetAddress('10.0.0.4'),
        ]),
        '192.168.1.10');
  });

  test('pick order: routable IPv6 when no IPv4 exists', () {
    expect(
        LanDiscoveryService.pickResolvedHost('voron24.local.', [
          InternetAddress('fe80::1'),
          InternetAddress('fde4:8dba:82e1::c4'),
        ]),
        'fde4:8dba:82e1::c4');
  });

  test('pick order: link-local-only resolution keeps the hostname', () {
    // A name that only resolves to fe80::/10 must not enter the map as an
    // address - the hostname is the last resort that can still work.
    expect(
        LanDiscoveryService.pickResolvedHost('voron24.local.', [
          InternetAddress('fe80::4684:2651:1a53:50f6'),
        ]),
        'voron24.local.');
  });

  test('pick order: empty resolution keeps the hostname', () {
    expect(LanDiscoveryService.pickResolvedHost('voron24.local.', []),
        'voron24.local.');
  });
}
