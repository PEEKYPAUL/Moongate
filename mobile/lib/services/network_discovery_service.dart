import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class DiscoveredPrinter {
  final String ip;

  /// Host string — just the IP, port 80 is used via nginx proxy.
  String get host => ip;

  const DiscoveredPrinter(this.ip);
}

/// Scans the local WiFi subnet for Moonraker instances (port 7125).
/// Does NOT require Tailscale — works on any LAN.
class NetworkDiscoveryService {
  static final instance = NetworkDiscoveryService._();
  NetworkDiscoveryService._();

  /// Returns the device's primary local-network IPv4 address, or null.
  /// Excludes loopback (127.x), link-local (169.254.x), and
  /// Tailscale (100.64-127.x) ranges.
  Future<String?> myLocalIp() async {
    try {
      for (final iface in await NetworkInterface.list()) {
        // Prefer Wi-Fi interfaces but accept any
        for (final addr in iface.addresses) {
          if (addr.type != InternetAddressType.IPv4) continue;
          if (_isLocalPrivate(addr.address)) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isLocalPrivate(String ip) {
    final p = ip.split('.');
    if (p.length != 4) return false;
    final a = int.tryParse(p[0]) ?? -1;
    final b = int.tryParse(p[1]) ?? -1;

    if (a == 127) return false;                           // loopback
    if (a == 169 && b == 254) return false;               // link-local
    if (a == 100 && b >= 64 && b <= 127) return false;   // Tailscale

    return a == 10 ||                                      // 10.0.0.0/8
        (a == 172 && b >= 16 && b <= 31) ||               // 172.16.0.0/12
        (a == 192 && b == 168);                            // 192.168.0.0/16
  }

  /// Streams printers found by TCP-probing every host in the /24 subnet.
  /// Probe timeout is 500 ms; 20 hosts are probed concurrently.
  Stream<DiscoveredPrinter> scanForPrinters() async* {
    final myIp = await myLocalIp();
    if (myIp == null) return;

    final parts  = myIp.split('.');
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';

    for (var base = 1; base <= 254; base += 20) {
      final futures = <Future<DiscoveredPrinter?>>[];
      for (var i = base; i < base + 20 && i <= 254; i++) {
        final candidate = '$prefix.$i';
        if (candidate == myIp) continue;
        futures.add(_probe(candidate));
      }
      for (final result in await Future.wait(futures)) {
        if (result != null) yield result;
      }
    }
  }

  Future<DiscoveredPrinter?> _probe(String ip) async {
    try {
      // Use port 80 (nginx) — port 7125 (direct Moonraker) is often firewalled.
      // nginx proxies /server/* to Moonraker, so this always works on stock setups.
      final response = await http.get(
        Uri.parse('http://$ip/server/info'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(milliseconds: 800));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>?;
        if (body != null && body.containsKey('result')) {
          return DiscoveredPrinter(ip);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
