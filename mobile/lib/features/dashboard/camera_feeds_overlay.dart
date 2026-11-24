import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/app_icons.dart';

/// Bottom sheet that sets the dashboard-tile webcam refresh rate separately for
/// the LAN ("Local") and remote ("Tunnel") paths. Each tile fetches snapshots
/// at the local rate while connected over WiFi and the tunnel rate while remote
/// (see [WebcamView]), so you can keep a fast feed at home and throttle it away
/// from home to save mobile data. Both persist immediately and ride backups.
Future<void> showCameraFeedsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const _CameraFeedsSheet(),
  );
}

class _CameraFeedsSheet extends ConsumerWidget {
  const _CameraFeedsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final local = ref.watch(localCameraRefreshProvider);
    final tunnel = ref.watch(tunnelCameraRefreshProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
              child: Text(l.cameraFeedsMenuTitle,
                  style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text(
                l.cameraFeedsIntro,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ),
            _RateRow(
              icon: AppIcons.wifi_rounded,
              label: l.cameraFeedsLocalRate,
              selected: local,
              onChanged: (v) =>
                  ref.read(localCameraRefreshProvider.notifier).set(v),
            ),
            const SizedBox(height: 10),
            _RateRow(
              icon: AppIcons.cloud_outlined,
              label: l.cameraFeedsTunnelRate,
              selected: tunnel,
              onChanged: (v) =>
                  ref.read(tunnelCameraRefreshProvider.notifier).set(v),
            ),
          ],
        ),
      ),
    );
  }
}

/// One labelled segmented picker (Raw / 1s / 3s / 5s) - same button style as the
/// rest of the menu.
class _RateRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final DashboardCameraRefresh selected;
  final ValueChanged<DashboardCameraRefresh> onChanged;

  const _RateRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Row(
            children: [
              Icon(icon, size: 18, color: theme.hintColor),
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.labelLarge),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<DashboardCameraRefresh>(
            // No selected-checkmark - keeps Raw/1s/3s/5s on one line, matching
            // the other segmented pickers in the menu.
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            segments: [
              for (final r in DashboardCameraRefresh.values)
                ButtonSegment(value: r, label: Text(r.label)),
            ],
            selected: {selected},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ),
      ],
    );
  }
}
