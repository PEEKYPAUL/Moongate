import 'package:flutter/material.dart';

/// An outlined icon+label button that keeps its label only when the full
/// text genuinely fits - otherwise it collapses to a tooltipped icon.
/// Built for the dashboard tile's tools row, where two buttons split a
/// tile's width: on narrow tiles (the 2-column grid) or with long
/// translations ("Dateisystem", "Файловая система") an ellipsized label
/// reads as noise, but dropping labels everywhere would cost the row its
/// discoverability. So each button measures its label at the live text
/// scale and direction and decides for itself, label-first.
class AdaptiveToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const AdaptiveToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  /// Chrome around the label inside an [OutlinedButton.icon]: horizontal
  /// padding (8+8), the 16px icon, its ~8px gap to the label, the 1px
  /// border each side, and a little slack so a rounding difference between
  /// this estimate and the real button layout can never ellipsize a label
  /// we decided "fits".
  static const double _chrome = 46;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = OutlinedButton.styleFrom(
      visualDensity:   VisualDensity.compact,
      padding:         const EdgeInsets.symmetric(horizontal: 8),
      minimumSize:     const Size(0, 30),
      side:            BorderSide(color: theme.colorScheme.outlineVariant),
      foregroundColor: theme.colorScheme.primary,
      textStyle:       theme.textTheme.labelMedium,
    );
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: theme.textTheme.labelMedium),
        textDirection: Directionality.of(context),
        textScaler:    MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final fits = painter.width + _chrome <= constraints.maxWidth;
      painter.dispose();

      if (!fits) {
        // Icon-only: the tooltip (long-press) carries the name, and so do
        // TalkBack and friends via the tooltip's semantics.
        return Tooltip(
          message: label,
          child: OutlinedButton(
            style: style,
            onPressed: onPressed,
            child: Icon(icon, size: 16),
          ),
        );
      }
      return OutlinedButton.icon(
        style: style,
        icon: Icon(icon, size: 16),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onPressed: onPressed,
      );
    });
  }
}
