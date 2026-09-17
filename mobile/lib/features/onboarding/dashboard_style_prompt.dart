import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';

/// First-run question: one printer or several? Shown once on a fresh install,
/// straight after the language picker and before the pairing help, so the user
/// lands in the dashboard style that suits them. The barrier can't be tapped
/// away - Continue unlocks once an option is picked. A system back press
/// returns null, which the caller treats as the Multi-printer dashboard (the
/// long-standing default). The menu's "Single-printer dashboard" checkbox
/// changes the choice any time, as the dialog says.
Future<DashboardMode?> showDashboardStylePrompt(BuildContext context) {
  return showDialog<DashboardMode>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DashboardStyleDialog(),
  );
}

class _DashboardStyleDialog extends StatefulWidget {
  const _DashboardStyleDialog();

  @override
  State<_DashboardStyleDialog> createState() => _DashboardStyleDialogState();
}

class _DashboardStyleDialogState extends State<_DashboardStyleDialog> {
  DashboardMode? _pick;

  @override
  Widget build(BuildContext context) {
    final l     = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return AlertDialog(
      title: Text(l.dashboardStyleTitle),
      // Scrolls rather than overflows in landscape or at a large display size.
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.dashboardStyleBody, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 14),
              _StyleOption(
                glyph: const _StyleGlyph(single: true),
                title: l.dashboardStyleSingleTitle,
                body: l.dashboardStyleSingleBody,
                selected: _pick == DashboardMode.single,
                onTap: () => setState(() => _pick = DashboardMode.single),
              ),
              const SizedBox(height: 10),
              _StyleOption(
                glyph: const _StyleGlyph(single: false),
                title: l.dashboardStyleMultiTitle,
                body: l.dashboardStyleMultiBody,
                selected: _pick == DashboardMode.multi,
                onTap: () => setState(() => _pick = DashboardMode.multi),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.menu, size: 18, color: muted),
                  const SizedBox(width: 8),
                  // The language picker's own line - the same promise, the
                  // same menu.
                  Expanded(
                    child: Text(
                      l.languagePickerSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _pick == null ? null : () => Navigator.of(context).pop(_pick),
          child: Text(l.languagePickerContinue),
        ),
      ],
    );
  }
}

/// One selectable answer: a small picture of the dashboard, a title and one
/// line of explanation. Selected = primary outline + a light primary wash.
class _StyleOption extends StatelessWidget {
  final Widget glyph;
  final String title;
  final String body;
  final bool selected;
  final VoidCallback onTap;

  const _StyleOption({
    required this.glyph,
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? cs.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                glyph,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(body,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tiny phone outline: one big camera block over a few control lines for the
/// single style, a 2 x 2 grid of tiles for the multi style.
class _StyleGlyph extends StatelessWidget {
  final bool single;
  const _StyleGlyph({required this.single});

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final block = cs.primary;
    final line  = cs.onSurfaceVariant.withValues(alpha: 0.45);
    Widget bar(double h, Color c) => Container(
          height: h,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
        );
    return Container(
      width: 40,
      height: 62,
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.onSurfaceVariant, width: 1.5),
      ),
      child: single
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                bar(17, block),
                const SizedBox(height: 4),
                bar(4, line),
                const SizedBox(height: 3),
                bar(4, line),
                const SizedBox(height: 3),
                bar(4, line),
              ],
            )
          : Column(
              children: [
                for (var r = 0; r < 2; r++) ...[
                  if (r > 0) const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(child: bar(19, block)),
                      const SizedBox(width: 3),
                      Expanded(child: bar(19, block)),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}
