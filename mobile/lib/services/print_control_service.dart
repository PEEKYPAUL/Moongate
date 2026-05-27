import 'package:http/http.dart' as http;

import '../models/printer_config.dart';
import 'printer_access_cache.dart';
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

    // LAN first if we have a cached URL — fast-fail at 2s
    final lanUrl = config.lanUrl;
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
