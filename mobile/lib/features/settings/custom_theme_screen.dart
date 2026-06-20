import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/custom_theme_provider.dart';
import '../../providers/dashboard_background_provider.dart';

/// Full-screen colour editor for the Custom theme.
///
/// Five slots cover every meaningful surface in the app — see
/// [CustomTheme] for the full breakdown.  Each row is a tappable swatch
/// that opens a modal bottom sheet containing:
///
///   • a live-preview swatch
///   • a HEX input field (case-insensitive, optional leading `#`)
///   • a grid of 24 hand-picked preset colours
///
/// Changes apply instantly via Riverpod — no save button, no preview-vs-
/// apply mode.  A "Reset to defaults" action in the app bar reverts all
/// five slots to the seeded-purple-dark palette.
class CustomThemeScreen extends ConsumerWidget {
  const CustomThemeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme  = ref.watch(customThemeProvider);
    final notifier = ref.read(customThemeProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.customThemeTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: l.customThemeResetTooltip,
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l.customThemeResetConfirmTitle),
                  content: Text(l.customThemeResetConfirmBody),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(l.commonCancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(l.customThemeReset),
                    ),
                  ],
                ),
              );
              if (confirmed == true) await notifier.reset();
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          // ── Live preview ────────────────────────────────────────────────
          // Shows a stylised dashboard tile rendered with the *current*
          // theme so users can see how their picks interact before they
          // back out to the actual dashboard.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              l.customThemePreview,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: _PreviewTile(theme: theme),
          ),

          const Divider(height: 1),

          // ── Colour slots ────────────────────────────────────────────────
          _ColourRow(
            label: l.customThemeAccent,
            description: l.customThemeAccentDesc,
            colour: theme.accent,
            onPick: (c) => notifier.setAccent(c),
          ),
          _ColourRow(
            label: l.customThemeBackground,
            description: l.customThemeBackgroundDesc,
            colour: theme.background,
            onPick: (c) => notifier.setBackground(c),
          ),
          _ColourRow(
            label: l.customThemeSurface,
            description: l.customThemeSurfaceDesc,
            colour: theme.surface,
            onPick: (c) => notifier.setSurface(c),
          ),
          _ColourRow(
            label: l.customThemeText,
            description: l.customThemeTextDesc,
            colour: theme.text,
            onPick: (c) => notifier.setText(c),
          ),
          _ColourRow(
            label: l.customThemeError,
            description: l.customThemeErrorDesc,
            colour: theme.error,
            onPick: (c) => notifier.setError(c),
          ),
          _ColourRow(
            label: l.customThemeEstop,
            description: l.customThemeEstopDesc,
            colour: theme.estop,
            onPick: (c) => notifier.setEstop(c),
          ),

          const Divider(height: 1),

          // Dashboard background image — part of the Custom theme. Picks an
          // image to sit behind the tiles (centred, scaled-down, over the theme
          // colour); the × clears it. Shown only here, i.e. while Custom is on.
          const _BackgroundRow(),

          // Tile opacity (0–100): how see-through the printer tiles' background
          // is, so a custom background shows through; the camera feed stays
          // solid. Only takes visible effect with a background set.
          const _TileOpacityField(),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── A single colour-slot row ────────────────────────────────────────────────

class _ColourRow extends StatelessWidget {
  final String         label;
  final String         description;
  final Color          colour;
  final ValueChanged<Color> onPick;

  const _ColourRow({
    required this.label,
    required this.description,
    required this.colour,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _openPicker(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            // Big swatch
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: cs.onSurface.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    CustomTheme.hexOf(colour),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: cs.onSurface.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ColourPickerSheet(initial: colour, label: label),
    );
    if (picked != null) onPick(picked);
  }
}

// ─── Bottom-sheet colour picker ──────────────────────────────────────────────

class _ColourPickerSheet extends StatefulWidget {
  final Color  initial;
  final String label;

  const _ColourPickerSheet({required this.initial, required this.label});

  @override
  State<_ColourPickerSheet> createState() => _ColourPickerSheetState();
}

class _ColourPickerSheetState extends State<_ColourPickerSheet> {
  late Color _current = widget.initial;
  late final TextEditingController _hexController =
      TextEditingController(text: CustomTheme.hexOf(widget.initial).substring(1));
  String? _hexError;

  // A curated palette covering greys, accents and bright colours.
  // Two rows of greys, then warm/cool spectrum, then a couple of brights.
  static const List<Color> _presets = [
    // Greys / neutrals
    Color(0xFF000000), Color(0xFF121212), Color(0xFF1E1E1E),
    Color(0xFF424242), Color(0xFF757575), Color(0xFFBDBDBD),
    Color(0xFFEEEEEE), Color(0xFFFFFFFF),
    // Reds, oranges, yellows
    Color(0xFFE53935), Color(0xFFCF6679), Color(0xFFFF7043),
    Color(0xFFFFA726), Color(0xFFFFCA28), Color(0xFFD4AF37),
    // Greens
    Color(0xFF66BB6A), Color(0xFF26A69A), Color(0xFF00897B),
    // Blues
    Color(0xFF42A5F5), Color(0xFF1E88E5), Color(0xFF1A237E),
    // Purples / pinks
    Color(0xFF6C63FF), Color(0xFF7E57C2), Color(0xFFAB47BC),
    Color(0xFFEC407A),
  ];

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _apply(Color c) {
    setState(() {
      _current = c;
      _hexController.text = CustomTheme.hexOf(c).substring(1);
      _hexError = null;
    });
  }

  void _onHexChanged(String raw) {
    final parsed = CustomTheme.parseHex(raw);
    setState(() {
      if (parsed == null) {
        _hexError = raw.replaceFirst('#', '').length == 6
            ? AppLocalizations.of(context).customThemeInvalidHex
            : null; // don't yell while user is still typing
      } else {
        _current = parsed;
        _hexError = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final l = AppLocalizations.of(context);
    // `viewInsets.bottom`  → on-screen keyboard height (when open)
    // `padding.bottom`     → system navigation / gesture bar height
    // Add both so the Done button never sits under either.  The system nav
    // bar matters on phones with 3-button navigation where the bottom row of
    // the modal would otherwise be obscured.
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + mq.padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(widget.label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // Big live-preview swatch
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: _current,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cs.onSurface.withValues(alpha: 0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _current.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // HEX input
            Row(
              children: [
                Text(
                  '#',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 22,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _hexController,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      letterSpacing: 2,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'RRGGBB',
                      hintStyle: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.3),
                        letterSpacing: 2,
                      ),
                      errorText: _hexError,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9a-fA-F#]')),
                      LengthLimitingTextInputFormatter(7),
                    ],
                    onChanged: _onHexChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Preset palette grid
            Text(
              l.customThemePresets,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
            ),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 8,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: _presets.map((p) {
                final selected = p.toARGB32() == _current.toARGB32();
                return InkWell(
                  onTap: () => _apply(p),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: p,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? cs.primary
                            : cs.onSurface.withValues(alpha: 0.15),
                        width: selected ? 3 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Done
            FilledButton(
              onPressed: _hexError != null
                  ? null
                  : () => Navigator.pop(context, _current),
              child: Text(l.commonDone),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Mini preview tile ───────────────────────────────────────────────────────
//
// Renders a stylised dashboard tile so the user sees how the colour choices
// actually interact: accent on a progress bar, surface as the card body,
// text on top, accent again on the FAB-style chip, and the error/stop button.

class _PreviewTile extends StatelessWidget {
  final CustomTheme theme;

  const _PreviewTile({required this.theme});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.text.withValues(alpha: 0.15)),
      ),
      padding: const EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: theme.accent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l.customThemeSamplePrinter,
                  style: TextStyle(
                    color: theme.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Icon(Icons.wifi, color: theme.accent, size: 14),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(l.customThemePrinting,
                              style: TextStyle(
                                  color: theme.accent, fontSize: 11)),
                          Text('42.0%',
                              style: TextStyle(
                                  color: theme.accent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: 0.42,
                          minHeight: 6,
                          backgroundColor:
                              theme.text.withValues(alpha: 0.15),
                          color: theme.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.error.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.stop_rounded,
                      size: 18, color: theme.error),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '200°C / 60°C',
              style: TextStyle(
                color: theme.text.withValues(alpha: 0.55),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Dashboard background image row ───────────────────────────────────────────
//
// Part of the Custom theme: pick an image to sit behind the dashboard tiles
// (centred, scaled-down, over the theme's background colour, so a logo PNG or a
// wrong-aspect picture still shows the theme colour around it). The × clears it.
// The dashboard only paints it while the Custom theme is active.

class _BackgroundRow extends ConsumerWidget {
  const _BackgroundRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l  = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final bg = ref.watch(dashboardBackgroundProvider);
    final hasBg = bg != null && bg.isNotEmpty;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      leading: Icon(Icons.wallpaper_outlined, color: cs.onSurface),
      title: Text(l.dashboardBackgroundTitle),
      subtitle:
          Text(hasBg ? l.dashboardBackgroundCustom : l.dashboardBackgroundNone),
      trailing: hasBg
          ? IconButton(
              icon: const Icon(Icons.close),
              tooltip: l.dashboardBackgroundRemove,
              onPressed: () =>
                  ref.read(dashboardBackgroundProvider.notifier).clear(),
            )
          : Icon(Icons.chevron_right,
              color: cs.onSurface.withValues(alpha: 0.4)),
      onTap: () => _pick(context, ref),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    FilePickerResult? result;
    try {
      result = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
    } catch (_) {
      result = null;
    }
    final files = result?.files ?? const <PlatformFile>[];
    final picked = files.isNotEmpty ? files.first : null;
    final bytes = picked?.bytes;
    if (bytes == null) return; // cancelled, or the bytes couldn't be read
    await ref
        .read(dashboardBackgroundProvider.notifier)
        .setFromBytes(bytes, extension: picked?.extension ?? 'img');
    messenger.showSnackBar(SnackBar(
      content: Text(l.dashboardBackgroundSet),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }
}

// ─── Tile opacity field (0–100) ───────────────────────────────────────────────
//
// Type 0–100 to set how see-through the printer tiles' background is, so a
// custom dashboard background shows through; the camera feed stays solid.
// Applied (on the Custom theme) by printer_tile via CustomTheme.tileOpacity.

class _TileOpacityField extends ConsumerStatefulWidget {
  const _TileOpacityField();

  @override
  ConsumerState<_TileOpacityField> createState() => _TileOpacityFieldState();
}

class _TileOpacityFieldState extends ConsumerState<_TileOpacityField> {
  late final TextEditingController _controller = TextEditingController(
      text: '${(ref.read(customThemeProvider).tileOpacity * 100).round()}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply(String raw) {
    final n = int.tryParse(raw.trim());
    if (n == null) return; // mid-edit / empty — don't clobber
    ref
        .read(customThemeProvider.notifier)
        .setTileOpacity(n.clamp(0, 100) / 100);
  }

  @override
  Widget build(BuildContext context) {
    final l     = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.tileOpacityTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(l.tileOpacityDesc,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 78,
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              decoration: const InputDecoration(
                suffixText: '%',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _apply,
            ),
          ),
        ],
      ),
    );
  }
}
