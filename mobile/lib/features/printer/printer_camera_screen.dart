import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../providers/settings_provider.dart';
import '../../services/printer_status_service.dart';
import '../../widgets/webcam_view.dart';

/// Opens the Moongate-native camera view for one printer as a full-screen
/// **overlay** - a faded dialog over the current screen (no app-bar chrome), the
/// feed centred, with pinch-to-zoom / pan and a floating back arrow. While it's
/// open the app is allowed to rotate into landscape for widescreen viewing even
/// when it's otherwise portrait-locked; the user's [allowRotationProvider]
/// setting is restored when it closes.
///
/// Why this view exists: the printer detail page embeds the real Mainsail/Fluidd
/// UI in a WebView, so its webcam panel inherits Mainsail's *own* camera URL. For
/// an external camera (e.g. an old phone running an IP-webcam app) that URL is an
/// absolute LAN address like `http://192.168.0.107:8080/video`, which a phone on
/// mobile data simply can't reach. This view sidesteps that by rendering through
/// the SAME resolved snapshot URL the dashboard tile uses: LAN-direct at home, or
/// routed through the Pi's owner-token-gated `/mg-extcam` proxy when remote - so
/// the external camera keeps working away from home.
void showPrinterCameraOverlay(BuildContext context, PrinterConfig printer) {
  showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => _PrinterCameraOverlay(printer: printer),
    transitionBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class _PrinterCameraOverlay extends ConsumerStatefulWidget {
  final PrinterConfig printer;
  const _PrinterCameraOverlay({required this.printer});

  @override
  ConsumerState<_PrinterCameraOverlay> createState() =>
      _PrinterCameraOverlayState();
}

class _PrinterCameraOverlayState extends ConsumerState<_PrinterCameraOverlay> {
  late final PrinterStatusService _service;
  PrinterStatus? _status;

  static const _portraitOnly = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ];
  static const _allOrientations = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  @override
  void initState() {
    super.initState();
    // Allow landscape for widescreen viewing while the camera is open, even if
    // the app is otherwise portrait-locked - restored to the user's setting in
    // dispose().
    SystemChrome.setPreferredOrientations(_allOrientations);
    // Run our own status poll so the snapshot URL (and its short-lived
    // mg_token) stays fresh while this view is open - the same service the
    // dashboard tile uses, so all the LAN-vs-tunnel / external-camera URL
    // resolution is reused, not reimplemented.
    _service = PrinterStatusService(widget.printer);
    _service.stream.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _service.start();
  }

  @override
  void dispose() {
    _service.dispose();
    // Restore whatever the app's rotation setting was (portrait-locked unless
    // the user enabled "Allow rotation").
    SystemChrome.setPreferredOrientations(
      ref.read(allowRotationProvider) ? _allOrientations : _portraitOnly,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = _status;
    final url = s?.webcamSnapshotUrl;
    final hasCam = url != null && url.isNotEmpty;

    final isLocal = s?.connection == PrinterConnection.local;
    final subtitle = s == null || s.connection == PrinterConnection.offline
        ? null
        : (isLocal ? l.printerLocalNetwork : l.printerTunnelVia);

    Widget body;
    if (hasCam) {
      // Pinch-to-zoom / pan over a centred, letterboxed live frame. In
      // landscape the contained frame fills the wider screen - widescreen view.
      body = InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: WebcamView(
          webcamSnapshotUrl: url,
          webcamFlipH: s!.webcamFlipH,
          webcamFlipV: s.webcamFlipV,
          webcamRotation: s.webcamRotation,
          webcamTargetFps: s.webcamTargetFps,
          webcamIsExternal: s.webcamIsExternal,
          uiType: _service.uiType ?? widget.printer.uiType,
          printerId: widget.printer.id,
          fit: BoxFit.contain,
          respectDashboardThrottle: false,
        ),
      );
    } else if (s == null) {
      body = _CenterMessage(spinner: true, text: l.cameraConnecting);
    } else if (s.connection == PrinterConnection.offline) {
      body = _CenterMessage(
        icon: Icons.cloud_off_outlined,
        text: l.printerUnreachable,
      );
    } else {
      body = _CenterMessage(
        icon: Icons.videocam_off_outlined,
        text: l.cameraNoCamera,
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Centred, full-bleed feed.
          Positioned.fill(child: Center(child: body)),
          // Floating back arrow + printer name/connection, over the feed.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.printer.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: isLocal ? Colors.green : Colors.orange,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterMessage extends StatelessWidget {
  final IconData? icon;
  final bool spinner;
  final String text;
  const _CenterMessage({this.icon, this.spinner = false, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner)
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white54,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 56, color: Colors.white30),
          const SizedBox(height: 16),
          Text(text, style: const TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}
