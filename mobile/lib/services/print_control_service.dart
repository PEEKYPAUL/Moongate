import 'package:http/http.dart' as http;

import '../models/printer_config.dart';
import 'lan_discovery_service.dart';
import 'printer_access_cache.dart';
import 'printer_registry.dart';
import 'supabase_service.dart';

/// Sends print-control commands to the Moongate plugin.
///
/// v0.3.0: each call fetches a fresh `{tunnel_url, access_token}` from
/// Supabase (via [PrinterAccessCache]) before hitting the Pi. The plugin
/// validates the EdDSA token and proxies the action through to Klipper.
class PrintControlService {
  final PrinterConfig config;
  PrintControlService(this.config);

  /// Send a print control action.
  /// [action]: `pause` | `resume` | `cancel` | `firmware_restart` | `emergency_stop`
  /// Returns `true` if the Pi accepted the command.
  Future<bool> sendAction(String action) async {
    if (!SupabaseService.instance.ready) return false;

    PrinterAccess access;
    try {
      access = await PrinterAccessCache.instance.get(config.id);
    } catch (_) {
      return false;
    }

    // v0.5.0: pick the freshest available LAN URL.
    //   1. A discovered URL from mDNS (= what the Pi is *currently*
    //      advertising on the LAN — survives DHCP IP changes).
    //   2. The registry-live lanUrl (what the status service most
    //      recently learned from a successful /status response). This
    //      read closes the v0.4.x bug where the control service captured
    //      `config.lanUrl` at construction and never re-read it, so an
    //      IP change picked up by the status service didn't propagate to
    //      pause/resume/cancel until the tile was rebuilt.
    //   3. Fall through to the construction-time config.lanUrl if the
    //      registry entry has vanished (race during printer removal).
    //
    // See docs/v0.5-lan-discovery-design.md §8.2 and §10.2.
    final discovered = LanDiscoveryService.instance.lookup(config.id);
    final live = PrinterRegistry.instance.printers
        .firstWhere(
          (p) => p.id == config.id,
          orElse: () => config,
        )
        .lanUrl;
    final lanUrl = discovered ?? live;
    if (lanUrl != null &&
        await _send(lanUrl, access.accessToken, action,
                    timeout: const Duration(seconds: 2))) {
      return true;
    }

    if (await _send(access.tunnelUrl, access.accessToken, action,
                    timeout: const Duration(seconds: 10))) {
      return true;
    }

    // 401 / network blip — drop the cache and retry tunnel once with a
    // fresh token. LAN already tried.
    PrinterAccessCache.instance.invalidate(config.id);
    try {
      access = await PrinterAccessCache.instance.get(config.id);
    } catch (_) {
      return false;
    }
    return _send(access.tunnelUrl, access.accessToken, action,
                 timeout: const Duration(seconds: 10));
  }

  Future<bool> _send(
    String baseUrl,
    String token,
    String action, {
    required Duration timeout,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/server/moongate/control'
        '?mg_token=${Uri.encodeComponent(token)}'
        '&action=${Uri.encodeComponent(action)}',
      );
      final response = await http.post(uri).timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
