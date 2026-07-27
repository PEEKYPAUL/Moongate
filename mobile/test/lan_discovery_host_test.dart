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
}
