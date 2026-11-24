import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/custom_theme_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/heater_icon.dart';

/// Shows the dashboard icon guide as a centered popup.
///
/// The (long) list scrolls inside the dialog while the "Back to dashboard"
/// button stays pinned at the bottom of the popup. The dialog is centered and
/// height-capped so it never runs under the status bar or the bottom system
/// navigation bar.
Future<void> showUiGuide(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _UiGuideDialog(),
  );
}

class _UiGuideDialog extends ConsumerWidget {
  const _UiGuideDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    // The E-STOP icon follows the Custom theme's E-stop colour (matching the
    // tile) when that theme is active; otherwise the classic emergency red.
    final estopColor = ref.watch(themeModeProvider) == AppThemeMode.custom
        ? ref.watch(customThemeProvider).estop
        : Colors.red;
    // Cap the scroll area to ~60% of the screen so the centered dialog (plus
    // its title and pinned button) always stays clear of the system bars.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;

    return AlertDialog(
      title: Text(l.uiGuideTitle),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(l.uiGuideIntro,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),

                _header(context, l.uiGuideSectionConnection),
                _row(AppIcons.wifi_rounded, Colors.green, l.uiGuideLocalTitle,
                    l.uiGuideLocalDesc),
                _row(AppIcons.cloud_outlined, cs.primary, l.uiGuideTunnelTitle,
                    l.uiGuideTunnelDesc),
                _row(AppIcons.cloud_done_rounded, Colors.green,
                    l.uiGuideTunnelReadyTitle, l.uiGuideTunnelReadyDesc),
                _row(AppIcons.cloud_sync_outlined, Colors.orange,
                    l.uiGuideTunnelConnectingTitle,
                    l.uiGuideTunnelConnectingDesc),

                _header(context, l.uiGuideSectionTemperatures),
                _row(AppIcons.whatshot, Colors.deepOrange, l.uiGuideHotendTitle,
                    l.uiGuideHotendDesc),
                _row(AppIcons.bed, Colors.blue, l.uiGuideBedTitle,
                    l.uiGuideBedDesc),
                _row(null, Colors.teal, l.uiGuideChamberTitle,
                    l.uiGuideChamberDesc, asset: kChamberIconAsset),

                _header(context, l.uiGuideSectionControls),
                _row(AppIcons.play_arrow_rounded, Colors.green,
                    l.uiGuideResumeTitle, l.uiGuideResumeDesc),
                _row(AppIcons.pause_rounded, Colors.orange, l.uiGuidePauseTitle,
                    l.uiGuidePauseDesc),
                _row(AppIcons.stop_rounded, Colors.redAccent, l.uiGuideStopTitle,
                    l.uiGuideStopDesc),
                _row(AppIcons.warning_rounded, estopColor, l.uiGuideEstopTitle,
                    l.uiGuideEstopDesc),
                _row(AppIcons.restart_alt, cs.primary,
                    l.uiGuideFirmwareRestartTitle,
                    l.uiGuideFirmwareRestartDesc),

                _header(context, l.uiGuideSectionTileButtons),
                _row(AppIcons.folder_open_rounded, cs.primary,
                    l.uiGuideFilesTitle, l.uiGuideFilesDesc),
                _row(AppIcons.code_rounded, cs.primary, l.uiGuideMacrosTitle,
                    l.uiGuideMacrosDesc),
                _row(AppIcons.power_settings_new, Colors.green,
                    l.uiGuidePowerTitle, l.uiGuidePowerDesc),
                _row(AppIcons.lightbulb, Colors.amber, l.uiGuideLightingTitle,
                    l.uiGuideLightingDesc),
                _row(AppIcons.visibility_outlined, cs.primary,
                    l.uiGuideCameraViewTitle, l.uiGuideCameraViewDesc),
                _row(AppIcons.settings, Colors.blueGrey,
                    l.uiGuideCameraSetupTitle, l.uiGuideCameraSetupDesc),

                _header(context, l.uiGuideSectionStatus),
                _row(AppIcons.check_circle_outline, Colors.teal,
                    l.uiGuideStatusReadyTitle, l.uiGuideStatusReadyDesc),
                _row(AppIcons.close_rounded, Colors.teal,
                    l.uiGuideClearJobTitle, l.uiGuideClearJobDesc),
                _row(AppIcons.cancel_outlined, Colors.blueGrey,
                    l.uiGuideStatusCancelledTitle,
                    l.uiGuideStatusCancelledDesc),
                _row(AppIcons.error_outline, Colors.redAccent,
                    l.uiGuideStatusErrorTitle, l.uiGuideStatusErrorDesc),
                _row(AppIcons.hourglass_empty, Colors.blueGrey,
                    l.uiGuideStatusStartingTitle, l.uiGuideStatusStartingDesc),

                _header(context, l.uiGuideSectionWebcam),
                _row(AppIcons.wifi_off, Colors.redAccent, l.uiGuideOfflineTitle,
                    l.uiGuideOfflineDesc),
                _row(AppIcons.videocam_off, Colors.blueGrey,
                    l.uiGuideNoWebcamTitle, l.uiGuideNoWebcamDesc),
              ],
            ),
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(AppIcons.arrow_back),
          label: Text(l.uiGuideBack),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
      );

  Widget _row(IconData? icon, Color color, String title, String desc,
          {String? asset}) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: heaterIcon(icon: icon, asset: asset, size: 24, color: color),
        title: Text(title),
        subtitle: Text(desc),
      );
}
