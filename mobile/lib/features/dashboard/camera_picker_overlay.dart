import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../services/printer_registry.dart';
import '../../services/printer_status_service.dart';

/// True when the tile / full-screen camera should offer the camera switcher
/// for this printer: more than one reported camera (plugin 0.6.22+) and no
/// custom-URL override in force - the gear override outranks the picker, so
/// showing a switcher under it would silently do nothing.
bool cameraSwitchAvailable(PrinterConfig printer, PrinterStatus? status) {
  if ((status?.webcams.length ?? 0) < 2) return false;
  final override = printer.customCameraUrl;
  return override == null || override.trim().isEmpty;
}

/// Bottom sheet that switches which of a printer's cameras the dashboard tile
/// (and the full-screen camera view) shows. Only reachable when a status
/// reported more than one camera. The choice persists per printer
/// ([PrinterConfig.selectedWebcam] - the uid/name key, stable across Mainsail
/// renames and reorders) and [onSwitched] nudges the caller's status service
/// so the feed re-resolves on the very next poll instead of waiting out the
/// cadence.
Future<void> showCameraPickerSheet(
  BuildContext context, {
  required PrinterConfig printer,
  required List<PrinterWebcam> cams,
  required VoidCallback onSwitched,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => _CameraPickerSheet(
      printer:    printer,
      cams:       cams,
      onSwitched: onSwitched,
    ),
  );
}

class _CameraPickerSheet extends StatelessWidget {
  final PrinterConfig printer;
  final List<PrinterWebcam> cams;
  final VoidCallback onSwitched;

  const _CameraPickerSheet({
    required this.printer,
    required this.cams,
    required this.onSwitched,
  });

  /// The persisted pick, read live from the registry - the widget's config
  /// snapshot can lag an edit made elsewhere while the sheet is open.
  String? get _liveSelectedKey {
    for (final p in PrinterRegistry.instance.printers) {
      if (p.id == printer.id) return p.selectedWebcam;
    }
    return printer.selectedWebcam;
  }

  @override
  Widget build(BuildContext context) {
    final l      = AppLocalizations.of(context);
    final theme  = Theme.of(context);
    final active = PrinterStatusService.selectWebcam(cams, _liveSelectedKey);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
              child: Text(l.cameraPickerTitle,
                  style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l.cameraPickerIntro,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ),
            for (var i = 0; i < cams.length; i++)
              _CameraRow(
                label: cams[i].name.isNotEmpty
                    ? cams[i].name
                    : l.cameraFallbackName(i + 1),
                selected: active != null && cams[i].key == active.key,
                onTap: () async {
                  final nav = Navigator.of(context);
                  await PrinterRegistry.instance
                      .updateSelectedWebcam(printer.id, cams[i].key);
                  onSwitched();
                  if (nav.mounted) nav.pop();
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                l.cameraPickerHint,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CameraRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(
        selected ? Icons.videocam : Icons.videocam_outlined,
        color: selected ? theme.colorScheme.primary : null,
      ),
      title: Text(
        label,
        style: selected
            ? TextStyle(
                color:      theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              )
            : null,
      ),
      trailing: selected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : const Icon(Icons.radio_button_unchecked),
      onTap: onTap,
    );
  }
}
