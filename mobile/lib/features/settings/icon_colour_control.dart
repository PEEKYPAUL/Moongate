import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/custom_theme_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/app_icons.dart';

/// Theme-section row for the app-wide icon colour (see [iconColourProvider]).
///
/// The default is "follow the theme": icons keep the colour the active theme
/// gives them, exactly as before this setting existed. Tapping the row opens a
/// bottom sheet to either keep that default or pick a single colour that tints
/// every icon which doesn't set its own. Styled to match the Custom-theme
/// colour picker (preview swatch, HEX field, preset grid).
class IconColourRow extends ConsumerWidget {
  const IconColourRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final colour = ref.watch(iconColourProvider);
    // The swatch shows the picked colour, or - while following the theme - the
    // colour the theme currently gives icons, so the preview is honest either way.
    final shown = colour ?? IconTheme.of(context).color ?? cs.onSurface;

    return ListTile(
      leading: const Icon(AppIcons.colorize),
      title: Text(l.iconColourTitle),
      subtitle:
          Text(colour == null ? l.iconColourFollowTheme : CustomTheme.hexOf(colour)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: shown,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cs.onSurface.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(AppIcons.chevron_right,
              color: cs.onSurface.withValues(alpha: 0.4)),
        ],
      ),
      onTap: () async {
        final choice = await showModalBottomSheet<_IconColourChoice>(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => _IconColourSheet(initial: colour),
        );
        if (choice != null) {
          await ref.read(iconColourProvider.notifier).set(choice.colour);
        }
      },
    );
  }
}

/// Result of the sheet: a colour, or `null` for "follow the theme". A dismissed
/// sheet returns no choice at all (null from showModalBottomSheet), so the
/// caller can tell "follow theme" apart from "left it alone".
class _IconColourChoice {
  final Color? colour;
  const _IconColourChoice(this.colour);
}

class _IconColourSheet extends StatefulWidget {
  final Color? initial;
  const _IconColourSheet({required this.initial});

  @override
  State<_IconColourSheet> createState() => _IconColourSheetState();
}

class _IconColourSheetState extends State<_IconColourSheet> {
  late bool _followTheme = widget.initial == null;
  late Color _current = widget.initial ?? const Color(0xFF6C63FF);
  late final TextEditingController _hexController =
      TextEditingController(text: CustomTheme.hexOf(_current).substring(1));
  String? _hexError;

  // Same curated palette as the Custom-theme colour picker, for consistency.
  static const List<Color> _presets = [
    Color(0xFF000000), Color(0xFF121212), Color(0xFF1E1E1E),
    Color(0xFF424242), Color(0xFF757575), Color(0xFFBDBDBD),
    Color(0xFFEEEEEE), Color(0xFFFFFFFF),
    Color(0xFFE53935), Color(0xFFCF6679), Color(0xFFFF7043),
    Color(0xFFFFA726), Color(0xFFFFCA28), Color(0xFFD4AF37),
    Color(0xFF66BB6A), Color(0xFF26A69A), Color(0xFF00897B),
    Color(0xFF42A5F5), Color(0xFF1E88E5), Color(0xFF1A237E),
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
      _followTheme = false;
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
            : null; // don't yell while the user is still typing
      } else {
        _current = parsed;
        _followTheme = false;
        _hexError = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final l = AppLocalizations.of(context);
    // Add the keyboard inset and the system nav-bar inset so the Done button
    // never sits under either (matches the Custom-theme picker).
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + mq.padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            Text(l.iconColourTitle,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),

            // Follow the theme (the default). On = ignore the colour below.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _followTheme,
              title: Text(l.iconColourFollowTheme),
              onChanged: (v) => setState(() => _followTheme = v),
            ),

            // Colour controls - dimmed while following the theme, but tapping a
            // preset or typing a hex also switches off "Follow theme".
            AnimatedOpacity(
              opacity: _followTheme ? 0.4 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
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
                      child: Icon(AppIcons.palette_outlined,
                          color: _current.computeLuminance() > 0.5
                              ? Colors.black54
                              : Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                      final selected = !_followTheme &&
                          p.toARGB32() == _current.toARGB32();
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
                ],
              ),
            ),

            const SizedBox(height: 20),
            FilledButton(
              onPressed: (!_followTheme && _hexError != null)
                  ? null
                  : () => Navigator.pop(
                        context,
                        _IconColourChoice(_followTheme ? null : _current),
                      ),
              child: Text(l.commonDone),
            ),
          ],
        ),
      ),
    );
  }
}
