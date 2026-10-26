import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../services/printer_registry.dart';
import '../../services/printer_status_service.dart';

/// Bottom sheet that picks which Klipper object the chamber reading comes
/// from (v0.9.77), opened by holding the chamber chip on a tile or on the
/// Single-printer dashboard. Lists every temperature-reporting object the
/// printer has, chamber-named ones first, with its live reading; "Auto" at
/// the top names what the default rule resolves to. The choice persists per
/// printer ([PrinterConfig.chamberSensor]) and rides every status poll to the
/// plugin, so both dashboards, the tunnel path and the temperature alerts all
/// read the same sensor. [service] is the tile's own status service: it knows
/// the printer's reachable base and re-polls as soon as the pick changes.
Future<void> showChamberPickerSheet(
  BuildContext context, {
  required PrinterConfig printer,
  required PrinterStatusService service,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _ChamberPickerSheet(printer: printer, service: service),
  );
}

class _ChamberPickerSheet extends StatefulWidget {
  final PrinterConfig printer;
  final PrinterStatusService service;

  const _ChamberPickerSheet({required this.printer, required this.service});

  @override
  State<_ChamberPickerSheet> createState() => _ChamberPickerSheetState();
}

class _ChamberPickerSheetState extends State<_ChamberPickerSheet> {
  late final Future<List<TemperatureSensorReading>> _sensors;

  @override
  void initState() {
    super.initState();
    _sensors = widget.service.listTemperatureSensors();
  }

  /// The persisted pick, read live from the registry - the widget's config
  /// snapshot can lag an edit made elsewhere while the sheet is open.
  String? get _liveChosen {
    for (final p in PrinterRegistry.instance.printers) {
      if (p.id == widget.printer.id) return p.chamberSensor;
    }
    return widget.printer.chamberSensor;
  }

  Future<void> _choose(String? key) async {
    final nav = Navigator.of(context);
    await PrinterRegistry.instance.updateChamberSensor(widget.printer.id, key);
    widget.service.pollNow();
    if (nav.mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l     = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hint  = theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);

    // Keyboard inset (none here, but the standard shell) + the system
    // navigation bar: the last row must never sit under the buttons.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
                child: Text(l.chamberPickerTitle,
                    style: theme.textTheme.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(l.chamberPickerIntro, style: hint),
              ),
              Flexible(
                child: FutureBuilder<List<TemperatureSensorReading>>(
                  future: _sensors,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final all = snap.data ?? const <TemperatureSensorReading>[];
                    if (all.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Text(l.chamberPickerEmpty, style: hint),
                      );
                    }
                    return _list(context, l, all);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(l.chamberPickerHint, style: hint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, AppLocalizations l,
      List<TemperatureSensorReading> all) {
    final chosen   = _liveChosen;
    final chamber  = [for (final s in all) if (s.isChamberNamed) s];
    final other    = [for (final s in all) if (!s.isChamberNamed) s];
    final autoKey  = PrinterStatusService.defaultChamberKey(
        [for (final s in all) s.key]);
    final autoHit  = autoKey == null
        ? null
        : all.firstWhere((s) => s.key == autoKey);
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        _SensorRow(
          title:    l.chamberPickerAuto,
          subtitle: autoHit == null
              ? l.chamberPickerAutoNone
              : l.chamberPickerAutoUses(autoHit.name),
          reading:  autoHit == null ? '' : _format(autoHit),
          selected: chosen == null,
          onTap:    () => _choose(null),
        ),
        if (chamber.isNotEmpty) _section(context, l.chamberPickerSectionChamber),
        for (final s in chamber) _row(s, chosen),
        if (other.isNotEmpty) _section(context, l.chamberPickerSectionOther),
        for (final s in other) _row(s, chosen),
      ],
    );
  }

  Widget _row(TemperatureSensorReading s, String? chosen) => _SensorRow(
        title:    s.name,
        subtitle: s.key,
        mono:     true,
        reading:  _format(s),
        selected: chosen == s.key,
        onTap:    () => _choose(s.key),
      );

  Widget _section(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.hintColor,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  static String _format(TemperatureSensorReading s) {
    final t = s.temperature;
    if (t == null) return '';
    final cur = '${t.toStringAsFixed(1)}°';
    return s.target > 0 ? '$cur / ${s.target.toStringAsFixed(0)}°' : cur;
  }
}

class _SensorRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool   mono;
  final String reading;
  final bool   selected;
  final VoidCallback onTap;

  const _SensorRow({
    required this.title,
    required this.subtitle,
    this.mono = false,
    required this.reading,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return ListTile(
      dense: true,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? primary : null,
      ),
      title: Text(
        title,
        style: selected
            ? TextStyle(color: primary, fontWeight: FontWeight.w600)
            : null,
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.hintColor,
          fontFamily: mono ? 'monospace' : null,
          fontSize: 11,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        reading,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      onTap: onTap,
    );
  }
}
