import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/printer_config.dart';
import 'lan_discovery_service.dart';
import 'printer_status_registry.dart';
import 'supabase_service.dart';
import 'webcam_fetch_diag.dart';

/// Assembles as much debug context as we can for a bug report - built to make
/// LAN / pairing failures self-explanatory so we can fix users' issues without
/// a back-and-forth. Every source is best-effort: anything that throws is
/// simply omitted, so collect() never fails the report.
class DiagnosticsService {
  DiagnosticsService._();

  static Future<Map<String, dynamic>> collect({
    required List<PrinterConfig> printers,
    Map<String, dynamic>? pairingContext,
  }) async {
    final out = <String, dynamic>{};

    try {
      final info = await PackageInfo.fromPlatform();
      out['app'] = {
        'version': info.version,
        'build': info.buildNumber,
        'package': info.packageName,
      };
    } catch (_) {}

    try {
      out['device'] = await _device();
    } catch (_) {}

    // The phone's own private IPs/subnets - no permission needed, and the
    // single most useful LAN signal: are we even on a private network, and
    // which subnet (vs the printer's address)?
    try {
      out['network'] = await _network();
    } catch (_) {}

    // Cloud identity - correlate with the printers table. A signed-out state
    // (or all printers offline) is the orphaned-anon-UID signature.
    out['cloud'] = {
      'user_id': SupabaseService.instance.userId,
      'signed_in': SupabaseService.instance.ready,
    };

    // Everything the mDNS browse currently sees - catches "found nothing"
    // (flaky multicast) vs "found it but couldn't connect".
    out['mdns_discovered'] = LanDiscoveryService.instance.discovered;

    out['printer_count'] = printers.length;
    out['printers'] = printers.map(_printer).toList();

    if (pairingContext != null) out['pairing'] = pairingContext;

    return out;
  }

  static Future<Map<String, dynamic>> _device() async {
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await plugin.androidInfo;
      return {
        'platform': 'android',
        'os': 'Android ${a.version.release} (API ${a.version.sdkInt})',
        'manufacturer': a.manufacturer,
        'model': a.model,
        'product': a.product,
        'is_physical': a.isPhysicalDevice,
      };
    }
    if (Platform.isIOS) {
      final i = await plugin.iosInfo;
      return {
        'platform': 'ios',
        'os': '${i.systemName} ${i.systemVersion}',
        'model': i.utsname.machine,
      };
    }
    return {'platform': Platform.operatingSystem};
  }

  static Future<Map<String, dynamic>> _network() async {
    final ifaces = <String>[];
    for (final ni in await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false)) {
      for (final addr in ni.addresses) {
        ifaces.add('${ni.name}: ${addr.address}');
      }
    }
    return {
      'interfaces': ifaces,
      // Crude "are we on WiFi/LAN?" hint - any RFC1918 address present.
      'on_private_network': ifaces.any((s) =>
          s.contains(' 192.168.') || s.contains(' 10.') || s.contains(' 172.')),
    };
  }

  static Map<String, dynamic> _printer(PrinterConfig p) {
    final live = PrinterStatusRegistry.instance.snapshot(p.id);
    final poll = PrinterStatusRegistry.instance.pollDiag(p.id);
    final discovered = LanDiscoveryService.instance.lookup(p.id);
    return {
      'id': p.id,
      'name': p.name,
      'ui_type': p.uiType,
      'plugin_version': poll?['plugin_version'],
      'webcam_target_fps': p.webcamTargetFps,
      'lan_url': p.lanUrl,
      'has_lan_url': p.lanUrl != null,
      'mdns_discovered_url': discovered,
      'mdns_matches_lan': discovered != null && discovered == p.lanUrl,
      if (live != null)
        'live': {
          'state': live.state,
          'connection': live.connection.name,
          'tunnel_ready': live.tunnelReady,
          'has_webcam': live.webcamSnapshotUrl != null,
        },
      // How the webcam fetch loop is doing for this printer - catches the
      // "everything online but the tile never shows frames" class of report.
      if (WebcamFetchDiag.report(p.id) case final webcam?) 'webcam': webcam,
      if (poll != null) 'last_poll': poll,
    };
  }
}
