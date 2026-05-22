import 'package:http/http.dart' as http;

import '../models/printer_config.dart';

/// Sends print control commands to the Moongate plugin on the Pi.
/// The plugin validates the mg_token JWT and proxies the action to Moonraker
/// on localhost, so no separate Moonraker auth is needed.
class PrintControlService {
  final PrinterConfig config;

  PrintControlService(this.config);

  /// Send a print control action.
  /// [action] must be: `pause`, `resume`, `cancel`, or `emergency_stop`.
  /// Returns `true` if the command was accepted (HTTP 200) by any candidate.
  Future<bool> sendAction(String action) async {
    final candidates = [
      config.host,
      if (config.remoteHost != null) config.remoteHost!,
    ];

    for (final baseUrl in candidates) {
      try {
        final uri = Uri.parse(
          '$baseUrl/server/moongate/control'
          '?mg_token=${Uri.encodeComponent(config.token)}'
          '&action=${Uri.encodeComponent(action)}',
        );
        final response =
            await http.post(uri).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) return true;
      } catch (_) {
        // This candidate failed — try the next one.
      }
    }
    return false;
  }
}
