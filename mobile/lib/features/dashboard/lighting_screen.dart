import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../services/print_control_service.dart';
import '../../services/printer_registry.dart';
import '../../widgets/app_icons.dart';

/// Per-printer lighting setup (v0.9.8). Lists every printer; for each you switch
/// "Show on tile" on and pick EITHER an On + Off macro pair OR a single Toggle
/// macro, plus an optional Light Status Pin (a Klipper object such as
/// `output_pin caselight`) whose live value drives the lit/dark bulb on the
/// dashboard tile. Macros + objects are read live from each printer
/// (`printer/objects/list`); an offline printer falls back to typing names by
/// hand. The bulb itself lives in `printer_tile.dart`.
class LightingScreen extends StatelessWidget {
  const LightingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l       = AppLocalizations.of(context);
    final theme   = Theme.of(context);
    final printers = PrinterRegistry.instance.printers;

    return Scaffold(
      appBar: AppBar(title: Text(l.lightingTitle)),
      body: printers.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l.lightingNoPrinters, textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // ── Top instruction banner ──────────────────────────────────
                Container(
                  width: double.infinity,
                  color: theme.colorScheme.secondaryContainer,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(AppIcons.lightbulb_outline,
                          color: theme.colorScheme.onSecondaryContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l.lightingBanner,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final p in printers) _LightingPrinterCard(printer: p),
              ],
            ),
    );
  }
}

class _LightingPrinterCard extends StatefulWidget {
  final PrinterConfig printer;
  const _LightingPrinterCard({required this.printer});

  @override
  State<_LightingPrinterCard> createState() => _LightingPrinterCardState();
}

class _LightingPrinterCardState extends State<_LightingPrinterCard> {
  late Future<({List<String> macros, List<String> lightObjects})?> _future;

  late bool    _enabled      = widget.printer.lightingEnabled;
  late String? _onMacro      = widget.printer.lightOnMacro;
  late String? _offMacro     = widget.printer.lightOffMacro;
  late String? _toggleMacro  = widget.printer.lightToggleMacro;
  late String? _statusObject = widget.printer.lightStatusObject;
  late final TextEditingController _statusController =
      TextEditingController(text: widget.printer.lightStatusObject ?? '');

  @override
  void dispose() {
    _statusController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // The macro pickers read the live macro list; the status source is typed by
    // hand (with the example hint) - no auto-fill, which previously grabbed the
    // wrong single object (a display neopixel, a motor-power pin) on printers
    // the user never set up for lighting.
    _future = PrintControlService(widget.printer).listLightingTargets();
  }

  /// A usable control path exists - an on+off pair, or a toggle macro.
  bool get _canEnable {
    final hasPair = (_onMacro?.isNotEmpty ?? false) &&
        (_offMacro?.isNotEmpty ?? false);
    return hasPair || (_toggleMacro?.isNotEmpty ?? false);
  }

  void _persist() {
    // Never store "enabled" without a usable control path - otherwise the tile
    // would show a bulb that does nothing.
    if (!_canEnable) _enabled = false;
    PrinterRegistry.instance.updateLightingConfig(
      widget.printer.id,
      enabled:      _enabled,
      onMacro:      _onMacro,
      offMacro:     _offMacro,
      toggleMacro:  _toggleMacro,
      statusObject: _statusObject,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l     = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 12, 14),
        child: FutureBuilder<({List<String> macros, List<String> lightObjects})?>(
          future: _future,
          builder: (context, snap) {
            final loading = snap.connectionState != ConnectionState.done;
            final data    = snap.data;
            final macros  = data?.macros ?? const <String>[];
            // Done but null = every path failed (printer offline / unreachable):
            // pickers fall back to manual entry.
            final loadFailed = !loading && data == null;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header: name + enable switch ────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: Text(widget.printer.name,
                          style: theme.textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(l.lightingShowOnTile,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                    Switch(
                      value: _enabled && _canEnable,
                      onChanged: _canEnable
                          ? (v) => setState(() {
                                _enabled = v;
                                _persist();
                              })
                          : null,
                    ),
                  ],
                ),
                if (!_canEnable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(l.lightingNeedMacro,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ),

                if (loadFailed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(l.lightingLoadFailed,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error)),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _future = PrintControlService(widget.printer)
                                .listLightingTargets();
                          }),
                          child: Text(l.commonRetry),
                        ),
                      ],
                    ),
                  ),

                // ── Method 1: On + Off pair ─────────────────────────────────
                _TargetField(
                  label: l.lightingOnMacro,
                  value: _onMacro,
                  loading: loading,
                  pickTitle: l.lightingPickMacro,
                  options: macros,
                  onChanged: (v) => setState(() { _onMacro = v; _persist(); }),
                ),
                _TargetField(
                  label: l.lightingOffMacro,
                  value: _offMacro,
                  loading: loading,
                  pickTitle: l.lightingPickMacro,
                  options: macros,
                  onChanged: (v) => setState(() { _offMacro = v; _persist(); }),
                ),

                // ── Method 2 (optional): a single toggle macro ──────────────
                const SizedBox(height: 10),
                Text(l.lightingToggleSection,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontWeight: FontWeight.w600)),
                _TargetField(
                  label: l.lightingToggleMacro,
                  value: _toggleMacro,
                  loading: loading,
                  pickTitle: l.lightingPickMacro,
                  options: macros,
                  onChanged: (v) =>
                      setState(() { _toggleMacro = v; _persist(); }),
                ),

                // ── Light status source (optional, free text) ───────────────
                const SizedBox(height: 12),
                TextField(
                  controller: _statusController,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    labelText: l.lightingStatusSource,
                    hintText: l.lightingStatusHint,
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.outline,
                    ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    final t = v.trim();
                    _statusObject = t.isEmpty ? null : t;
                    _persist();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(l.lightingStatusSourceHelp,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A labelled, tappable field showing the currently-selected macro/object (or,
/// when empty, the [example] placeholder, else "Not set"). Tapping opens a
/// picker with the live options plus a manual-entry fallback. A trailing clear
/// button appears once a value is set.
class _TargetField extends StatelessWidget {
  final String label;
  final String? value;
  final bool loading;
  final String pickTitle;
  final List<String> options;
  final void Function(String?) onChanged;

  const _TargetField({
    required this.label,
    required this.value,
    required this.loading,
    required this.pickTitle,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l     = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final set   = value != null && value!.isNotEmpty;
    final placeholder = l.lightingNotSet;

    return InkWell(
      onTap: loading
          ? null
          : () async {
              final res = await _showTargetPicker(
                context,
                title: pickTitle,
                options: options,
                current: value,
              );
              if (res == null) return; // cancelled
              final v = res.clear ? null : res.value;
              onChanged(v == null || v.isEmpty ? null : v);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelSmall),
                  const SizedBox(height: 2),
                  Text(
                    set ? value! : placeholder,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: set
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.outline,
                      fontStyle: set ? FontStyle.normal : FontStyle.italic,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (set)
              IconButton(
                icon: const Icon(AppIcons.clear, size: 18),
                tooltip: l.lightingClear,
                onPressed: () => onChanged(null),
              )
            else
              const Icon(AppIcons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// Picker dialog: choose from the live [options] or type a name by hand (with an
/// optional [example] as the hint). Returns null on cancel, `(clear: true)` to
/// clear, or `(value: X)` to set.
Future<({bool clear, String? value})?> _showTargetPicker(
  BuildContext context, {
  required String title,
  required List<String> options,
  required String? current,
}) {
  // One field, two jobs: typing narrows the live list to the entries that
  // contain the text (any case), and Save / submit takes the text as a manual
  // entry for a name the list does not carry (printer offline, or a macro the
  // list missed). It starts empty so the full list shows; the current choice
  // is ticked in the list and kept when Save is pressed with nothing typed.
  final manual = TextEditingController();
  return showDialog<({bool clear, String? value})>(
    context: context,
    builder: (context) {
      final l     = AppLocalizations.of(context);
      final theme = Theme.of(context);
      return StatefulBuilder(
        builder: (context, setState) {
          final needle  = manual.text.trim().toLowerCase();
          final matches = needle.isEmpty
              ? options
              : [
                  for (final o in options)
                    if (o.toLowerCase().contains(needle)) o,
                ];
          void done() {
            final typed = manual.text.trim();
            Navigator.pop(
                context, (clear: false, value: typed.isEmpty ? current : typed));
          }
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: manual,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: l.lightingManualHint,
                      hintText:  current,
                      border:    const OutlineInputBorder(),
                      isDense:   true,
                    ),
                    onChanged:   (_) => setState(() {}),
                    onSubmitted: (_) => done(),
                  ),
                  if (options.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: matches.isEmpty
                            ? Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  l.lightingNoMatch,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color:     theme.colorScheme.outline,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              )
                            : ListView(
                                shrinkWrap: true,
                                children: [
                                  for (final o in matches)
                                    ListTile(
                                      dense: true,
                                      title: Text(o,
                                          overflow: TextOverflow.ellipsis),
                                      trailing: o == current
                                          ? Icon(AppIcons.check,
                                              color: theme.colorScheme.primary)
                                          : null,
                                      onTap: () => Navigator.pop(
                                          context, (clear: false, value: o)),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, (clear: true, value: null)),
                child: Text(l.lightingClear),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.commonCancel),
              ),
              FilledButton(
                onPressed: done,
                child: Text(l.commonSave),
              ),
            ],
          );
        },
      );
    },
  );
}
