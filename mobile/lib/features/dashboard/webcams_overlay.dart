import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../services/printer_registry.dart';
import '../../widgets/app_icons.dart';

/// Bottom sheet listing every dashboard printer with an on/off switch for its
/// webcam pane. Switching a printer off sets [PrinterConfig.hideWebcam], so its
/// dashboard tile collapses to the compact (no-camera) layout and the masonry
/// grid packs it tightly under the full tiles - and that tile stops fetching
/// snapshots, so it's also a per-printer data saver. Each change persists
/// immediately via the registry; the dashboard reloads when the sheet closes to
/// re-pack the grid.
Future<void> showWebcamsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const _WebcamsSheet(),
  );
}

class _WebcamsSheet extends StatefulWidget {
  const _WebcamsSheet();

  @override
  State<_WebcamsSheet> createState() => _WebcamsSheetState();
}

class _WebcamsSheetState extends State<_WebcamsSheet> {
  late List<PrinterConfig> _printers;

  @override
  void initState() {
    super.initState();
    _printers = PrinterRegistry.instance.printers;
  }

  // Switch ON = webcam shown = hideWebcam false. Re-read the registry after the
  // write so the switch reflects the persisted value.
  Future<void> _setShown(PrinterConfig p, bool shown) async {
    await PrinterRegistry.instance.updateHideWebcam(p.id, !shown);
    if (!mounted) return;
    setState(() => _printers = PrinterRegistry.instance.printers);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
              child: Text(l.dashboardShowWebcams,
                  style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l.dashboardShowWebcamsSubtitle,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _printers.length,
                itemBuilder: (context, i) {
                  final p = _printers[i];
                  return SwitchListTile(
                    secondary: const Icon(AppIcons.videocam_outlined),
                    title: Text(p.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    value: !p.hideWebcam,
                    onChanged: (v) => _setShown(p, v),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
