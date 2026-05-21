import 'dart:io';

class TailscaleDevice {
  final String ip;
  String get host => '$ip:7125';

  const TailscaleDevice(this.ip);
}

class TailscaleService {
  static final instance = TailscaleService._();
  TailscaleService._();

  /// Returns this device's Tailscale IP (100.64.0.0/10), or null if not connected.
  Future<String?> myIp() async {
    try {
      for (final iface in await NetworkInterface.list()) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final p = addr.address.split('.');
            if (p.length == 4 && p[0] == '100') {
              final second = int.tryParse(p[1]) ?? 0;
              if (second >= 64 && second <= 127) return addr.address;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  bool get isConnected => _connected;
  bool _connected = false;

  Future<bool> checkConnected() async {
    _connected = (await myIp()) != null;
    return _connected;
  }

  /// Scans the /24 subnet around this device's Tailscale IP for port 7125.
  Stream<TailscaleDevice> scanForPrinters() async* {
    final myAddress = await myIp();
    if (myAddress == null) return;

    final parts = myAddress.split('.');
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';

    // Probe in batches of 20 to keep concurrency reasonable
    for (var base = 1; base <= 254; base += 20) {
      final batch = <Future<TailscaleDevice?>>[];
      for (var i = base; i < base + 20 && i <= 254; i++) {
        final ip = '$prefix.$i';
        if (ip == myAddress) continue;
        batch.add(_probe(ip));
      }
      final results = await Future.wait(batch);
      for (final d in results) {
        if (d != null) yield d;
      }
    }
  }

  Future<TailscaleDevice?> _probe(String ip) async {
    try {
      final s = await Socket.connect(ip, 7125,
          timeout: const Duration(milliseconds: 600));
      await s.close();
      return TailscaleDevice(ip);
    } catch (_) {
      return null;
    }
  }
}
