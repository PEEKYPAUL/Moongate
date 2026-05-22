import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/printer_config.dart';
import 'printer_registry.dart';

/// Polls Moonraker's REST API to get current printer status.
/// One instance per printer tile; disposed when the tile leaves the tree.
class PrinterStatusService {
  final PrinterConfig config;
  final _controller        = StreamController<PrinterStatus>.broadcast();
  final _tunnelUrlController = StreamController<String>.broadcast();
  Timer? _timer;
  bool _disposed = false;

  PrinterStatusService(this.config);

  Stream<PrinterStatus> get stream => _controller.stream;

  /// Emits the updated tunnel URL whenever the Pi reports a URL that differs
  /// from what is stored in the config.  Subscribe in the webcam widget to
  /// immediately start using the fresh URL within the same session.
  Stream<String> get tunnelUrlUpdates => _tunnelUrlController.stream;

  void start({Duration interval = const Duration(seconds: 4)}) {
    _poll();
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _controller.close();
    _tunnelUrlController.close();
  }

  Future<void> _poll() async {
    if (_disposed) return;
    // Try local first, fall back to remote (Cloudflare tunnel) if unreachable.
    // config.host is a full URL: "http://192.168.x.x:80"
    // config.remoteHost is an HTTPS URL: "https://xxxx.trycloudflare.com"
    final candidates = [
      config.host,
      if (config.remoteHost != null) config.remoteHost!,
    ];

    for (final baseUrl in candidates) {
      try {
        // Use the Moongate proxy endpoint — it validates our JWT and fetches
        // from Moonraker on localhost, so it works both locally and via tunnel.
        // Token is passed as a query param because WebRequest has no get_header.
        final uri = Uri.parse(
          '$baseUrl/server/moongate/status?mg_token=${Uri.encodeComponent(config.token)}',
        );
        final response = await http.get(uri)
            .timeout(const Duration(seconds: 5));

        if (response.statusCode != 200) continue;

        final body   = jsonDecode(response.body) as Map<String, dynamic>;
        final result = body['result'] as Map<String, dynamic>;
        final status = result['status'] as Map<String, dynamic>;

        final printStats = status['print_stats'] as Map<String, dynamic>? ?? {};
        final extruder   = status['extruder']    as Map<String, dynamic>? ?? {};
        final heaterBed  = status['heater_bed']  as Map<String, dynamic>? ?? {};

        final state    = (printStats['state'] as String?) ?? 'offline';
        final progress = (printStats['print_duration'] != null &&
                printStats['total_duration'] != null &&
                (printStats['total_duration'] as num) > 0)
            ? ((printStats['print_duration'] as num) /
                    (printStats['total_duration'] as num))
                .clamp(0.0, 1.0)
            : 0.0;

        if (_disposed) return;

        // Detect tunnel URL rotation and push the fresh URL immediately.
        final liveTunnelUrl = result['tunnel_url'] as String?;
        if (liveTunnelUrl != null &&
            liveTunnelUrl.isNotEmpty &&
            liveTunnelUrl != config.remoteHost) {
          _tunnelUrlController.add(liveTunnelUrl);
          PrinterRegistry.instance
              .updateRemoteHost(config.id, liveTunnelUrl)
              .ignore();
        }

        // Webcam path as configured in Moonraker (injected by Pi plugin).
        // Falls back to the mjpeg-streamer default if the Pi plugin is older.
        final webcamPath = result['webcam_snapshot_path'] as String?;

        // Record which network path succeeded so the UI can show the indicator.
        final connection = (baseUrl == config.host)
            ? PrinterConnection.local
            : PrinterConnection.remote;

        _controller.add(PrinterStatus(
          state:              state,
          progress:           progress.toDouble(),
          hotendTemp:         (extruder['temperature'] as num?)?.toDouble() ?? 0,
          hotendTarget:       (extruder['target']      as num?)?.toDouble() ?? 0,
          bedTemp:            (heaterBed['temperature'] as num?)?.toDouble() ?? 0,
          bedTarget:          (heaterBed['target']      as num?)?.toDouble() ?? 0,
          filename:           printStats['filename'] as String?,
          connection:         connection,
          webcamSnapshotPath: webcamPath,
        ));
        return; // success — stop trying candidates
      } catch (_) {
        // This candidate failed; try the next one.
      }
    }

    if (!_disposed) _controller.add(PrinterStatus.offline);
  }
}
