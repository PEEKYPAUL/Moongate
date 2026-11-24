import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../services/print_control_service.dart';
import '../../services/printer_registry.dart';
import '../../widgets/app_icons.dart';

/// Per-printer advanced power setup (v0.9.11). For printers whose power is a
/// Klipper macro rather than a Moonraker `[power …]` device: switch it on and
/// pick EITHER an On + Off macro pair OR a single Toggle macro. When enabled,
/// the tile's power button drives the printer through those macros instead of a
/// power device. Stateless by design - there's no reliable power-state to read
/// (powering off takes Klipper down), so the button asks On or Off explicitly.
/// Macros are read live from each printer (`printer/objects/list`); an offline
/// printer falls back to typing names by hand. The button lives in
/// `printer_tile.dart`.
class AdvancedPowerScreen extends StatelessWidget {
  const AdvancedPowerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l        = AppLocalizations.of(context);
    final theme    = Theme.of(context);
    final printers = PrinterRegistry.instance.printers;

    return Scaffold(
      appBar: AppBar(title: Text(l.powerScreenTitle)),
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
                      Icon(AppIcons.power_settings_new,
                          color: theme.colorScheme.onSecondaryContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l.powerScreenBanner,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final p in printers) _PowerPrinterCard(printer: p),
              ],
            ),
    );
  }
}

class _PowerPrinterCard extends StatefulWidget {
  final PrinterConfig printer;
  const _PowerPrinterCard({required this.printer});

  @override
  State<_PowerPrinterCard> createState() => _PowerPrinterCardState();
}

class _PowerPrinterCardState extends State<_PowerPrinterCard> {
  late Future<List<String>?> _future;

  late bool    _enabled     = widget.printer.powerMacroEnabled;
  late String? _onMacro     = widget.printer.powerOnMacro;
  late String? _offMacro    = widget.printer.powerOffMacro;
  late String? _toggleMacro = widget.printer.powerToggleMacro;

  @override
  void initState() {
    super.initState();
    _future = PrintControlService(widget.printer).listMacros();
  }

  /// A usable control path exists - any one of: an off macro (the common case,
  /// a Klipper power-off macro), an on macro, or a toggle. A full on+off pair is
  /// fine too. Off-only / on-only are allowed; you don't need both.
  bool get _canEnable =>
      (_onMacro?.isNotEmpty ?? false) ||
      (_offMacro?.isNotEmpty ?? false) ||
      (_toggleMacro?.isNotEmpty ?? false);

  void _persist() {
    // Never store "enabled" without a usable control path.
    if (!_canEnable) _enabled = false;
    PrinterRegistry.instance.updatePowerMacroConfig(
      widget.printer.id,
      enabled:     _enabled,
      onMacro:     _onMacro,
      offMacro:    _offMacro,
      toggleMacro: _toggleMacro,
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
        child: FutureBuilder<List<String>?>(
          future: _future,
          builder: (context, snap) {
            final loading = snap.connectionState != ConnectionState.done;
            final macros  = snap.data ?? const <String>[];
            // Done but null = every path failed (printer offline / unreachable):
            // the pickers fall back to manual entry.
            final loadFailed = !loading && snap.data == null;

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
                    Text(l.powerUseSwitch,
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
                    child: Text(l.powerNeedMacro,
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
                            _future =
                                PrintControlService(widget.printer).listMacros();
                          }),
                          child: Text(l.commonRetry),
                        ),
                      ],
                    ),
                  ),

                // ── Method 1: On + Off pair ─────────────────────────────────
                _TargetField(
                  label: l.powerOnMacro,
                  value: _onMacro,
                  loading: loading,
                  pickTitle: l.lightingPickMacro,
                  options: macros,
                  onChanged: (v) => setState(() { _onMacro = v; _persist(); }),
                ),
                _TargetField(
                  label: l.powerOffMacro,
                  value: _offMacro,
                  loading: loading,
                  pickTitle: l.lightingPickMacro,
                  options: macros,
                  onChanged: (v) => setState(() { _offMacro = v; _persist(); }),
                ),

                // ── Method 2 (optional): a single toggle macro ──────────────
                const SizedBox(height: 10),
                Text(l.powerToggleSection,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontWeight: FontWeight.w600)),
                _TargetField(
                  label: l.powerToggleMacro,
                  value: _toggleMacro,
                  loading: loading,
                  pickTitle: l.lightingPickMacro,
                  options: macros,
                  onChanged: (v) =>
                      setState(() { _toggleMacro = v; _persist(); }),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(l.powerToggleBulkNote,
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

/// A labelled, tappable field showing the selected macro (or "Not set").
/// Tapping opens a picker with the live [options] plus manual entry; a trailing
/// clear button appears once a value is set. (Mirrors the Lighting screen's
/// field - kept local so the two setup screens stay independent.)
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
                    set ? value! : l.lightingNotSet,
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

/// Picker dialog: choose from the live [options] or type a name by hand. Returns
/// null on cancel, `(clear: true)` to clear, or `(value: X)` to set.
Future<({bool clear, String? value})?> _showTargetPicker(
  BuildContext context, {
  required String title,
  required List<String> options,
  required String? current,
}) {
  final manual = TextEditingController(text: current ?? '');
  return showDialog<({bool clear, String? value})>(
    context: context,
    builder: (context) {
      final l     = AppLocalizations.of(context);
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (options.isNotEmpty)
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final o in options)
                          ListTile(
                            dense: true,
                            title: Text(o, overflow: TextOverflow.ellipsis),
                            trailing: o == current
                                ? Icon(AppIcons.check,
                                    color: theme.colorScheme.primary)
                                : null,
                            onTap: () =>
                                Navigator.pop(context, (clear: false, value: o)),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: manual,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l.lightingManualHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (v) =>
                    Navigator.pop(context, (clear: false, value: v.trim())),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, (clear: true, value: null)),
            child: Text(l.lightingClear),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
                context, (clear: false, value: manual.text.trim())),
            child: Text(l.commonSave),
          ),
        ],
      );
    },
  );
}
