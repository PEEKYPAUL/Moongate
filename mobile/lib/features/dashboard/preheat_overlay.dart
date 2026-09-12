import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/heat_alerts.dart';
import '../../models/printer_config.dart';
import '../../providers/settings_provider.dart';
import '../../services/heatsoak_timers.dart';
import '../../services/print_control_service.dart';
import '../../services/print_notification_service.dart';

/// Client-side sanity cap on an entered target. Klipper enforces each heater's
/// real `max_temp` and rejects anything above it (surfaced as a failure
/// snackbar), so this is just a fat-finger guard, not a safety limit.
const double _maxTemp = 400;

/// Ceiling on the soak time (10 hours), so a stray extra digit can't arm an
/// absurd wait.
const int _maxMinutes = 600;

/// Bottom sheet to preheat a printer's hotend / bed (and chamber, where the
/// printer has one) and optionally arm a heat-soak alert. Opened by a
/// long-press on a tile's temperature row (online + idle only - see
/// `printer_tile.dart`). Sends `SET_HEATER_TEMPERATURE` to the printer's
/// Moonraker console over the same LAN→tunnel proxy as the macro runner, so it
/// needs no plugin change. Heater object names are auto-detected
/// (`available_heaters`) so it works whether the config calls them
/// extruder/heater_bed or something custom.
///
/// The heat-soak alert (v0.9.67) rides the opt-in print-notification service:
/// the sheet arms a [HeatSoakArm] naming the temperatures just set plus a soak
/// time, and the service's background isolate fires once every one of them
/// reads its target (soak time 0) or once they have held for the soak time.
/// The chamber on nearly every printer is a passive sensor warmed by the bed,
/// so entering a chamber temperature insists on a bed temperature too - typing
/// 45° for the chamber alone would never get there. The service is
/// Android-only, so on iOS the alert controls give way to a one-line note
/// rather than offering an alert that can never fire; and the sheet warns
/// (with a one-tap enable) when the service is off.
Future<void> showPreheatSheet(
  BuildContext context,
  PrinterConfig printer, {
  required double hotendTarget,
  required double bedTarget,
  double chamberTemp = 0,
  double chamberTarget = 0,
  List<ToolheadTemp> toolheads = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Span the full width even in landscape. Material 3's default caps a modal
    // bottom sheet at 640dp and centres it, so on a wide (landscape) screen the
    // sheet floated in the middle with the dashboard showing on either side.
    constraints: const BoxConstraints(maxWidth: double.infinity),
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _PreheatSheet(
      printer: printer,
      hotendTarget: hotendTarget,
      bedTarget: bedTarget,
      chamberTemp: chamberTemp,
      chamberTarget: chamberTarget,
      toolheads: toolheads,
    ),
  );
}

class _PreheatSheet extends ConsumerStatefulWidget {
  final PrinterConfig printer;
  final double hotendTarget;
  final double bedTarget;

  /// The tile's live chamber reading and target - 0 when the printer reports
  /// no chamber sensor, which hides the chamber field (same rule as the
  /// tile's chamber chip).
  final double chamberTemp;
  final double chamberTarget;
  final List<ToolheadTemp> toolheads;
  const _PreheatSheet({
    required this.printer,
    required this.hotendTarget,
    required this.bedTarget,
    required this.chamberTemp,
    required this.chamberTarget,
    required this.toolheads,
  });

  @override
  ConsumerState<_PreheatSheet> createState() => _PreheatSheetState();
}

class _PreheatSheetState extends ConsumerState<_PreheatSheet> {
  late final PrintControlService _control;

  /// The toolheads to offer a field for, sorted by tool number. A single-hotend
  /// printer keeps the classic Hotend + Bed layout; a multi-toolhead printer
  /// (IDEX / tool changer) lists one compact row per tool (T0, T1, ...) plus
  /// Bed.
  late final List<ToolheadTemp> _tools;
  late final List<TextEditingController> _hotendCtls;
  final _bedCtl = TextEditingController();
  final _chamberCtl = TextEditingController();
  final _timeCtl = TextEditingController(text: '0');

  /// "Heat-soak alert" - off each time the sheet opens, the same way the soak
  /// time starts at 0.
  bool _soakOn = false;

  bool get _isMulti => _tools.length > 1;

  /// Whether to offer the chamber field: only when the printer reports a
  /// chamber sensor (the tile shows its chamber chip on the same test).
  bool get _hasChamber => widget.chamberTemp > 0;

  /// Detected heater object names. Seeded with the Klipper defaults and replaced
  /// when the `available_heaters` probe returns, so a Set fired before the probe
  /// lands still targets the right heaters on a standard machine.
  ({String hotend, String bed}) _heaters =
      (hotend: 'extruder', bed: 'heater_bed');

  /// The chamber HEATER object, on the rare printer that actively heats its
  /// chamber (`heater_generic chamber`). Null for the usual passive sensor -
  /// then the chamber value is only a temperature to wait for, never set.
  String? _chamberHeater;

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _tools = [...widget.toolheads]..sort((a, b) => a.index.compareTo(b.index));
    _hotendCtls = List.generate(
        _isMulti ? _tools.length : 1, (_) => TextEditingController());
    _control = PrintControlService(widget.printer);
    _control.availableHeaters().then((names) {
      if (!mounted) return;
      setState(() {
        _heaters       = PrintControlService.mapHeaterNames(names);
        _chamberHeater = PrintControlService.mapChamberHeater(names);
      });
    });
  }

  @override
  void dispose() {
    for (final c in _hotendCtls) {
      c.dispose();
    }
    _bedCtl.dispose();
    _chamberCtl.dispose();
    _timeCtl.dispose();
    super.dispose();
  }

  double? _parseTemp(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return null;
    return v.clamp(0, _maxTemp).toDouble();
  }

  int _parseMinutes(String s) {
    final v = int.tryParse(s.trim());
    if (v == null || v < 0) return 0;
    return v > _maxMinutes ? _maxMinutes : v;
  }

  /// A chamber temperature entered without a bed temperature: the bed is what
  /// heats the chamber on nearly every printer, so that wait could never end.
  /// Blocks Set and shows the reason under the chamber field.
  bool get _chamberNeedsBed {
    if (!_hasChamber) return false;
    final chamber = _parseTemp(_chamberCtl.text);
    return chamber != null && chamber > 0 && _parseTemp(_bedCtl.text) == null;
  }

  Future<void> _enableNotifications() async {
    final granted =
        await PrintNotificationService.instance.requestPermission();
    if (!granted) return; // user denied at the OS prompt - the warning stays
    await ref.read(printNotificationsEnabledProvider.notifier).set(true);
    // Enabling here also clears any prior dashboard pause, so the service
    // actually starts (it runs only when enabled AND not paused).
    await ref.read(notificationsPausedProvider.notifier).set(false);
    await PrintNotificationService.instance.sync(true);
  }

  /// Heater object name for tool [index]: the detected primary hotend for T0
  /// (honours a custom `[heater_generic hotend]` name), and Klipper's convention
  /// `extruder{N}` for the rest.
  String _hotendName(int index) =>
      index == 0 ? _heaters.hotend : 'extruder$index';

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final targets = <String, double>{};
    final confirmParts = <String>[];
    // Temperatures for the heat-soak alert, by role (h0 / h1 ... / bed /
    // chamber) - only the ones actually being heated (a 0 target is "off",
    // nothing to reach).
    final roles = <String, double>{};

    void addHotend(int index, String label, double? temp) {
      if (temp == null) return;
      targets[_hotendName(index)] = temp;
      if (temp > 0) roles[hotendRole(index)] = temp;
      confirmParts.add('$label ${temp.round()}°');
    }

    if (_isMulti) {
      for (var i = 0; i < _tools.length; i++) {
        addHotend(_tools[i].index, 'T${_tools[i].index}',
            _parseTemp(_hotendCtls[i].text));
      }
    } else {
      addHotend(0, l.preheatHotend, _parseTemp(_hotendCtls[0].text));
    }

    final bed = _parseTemp(_bedCtl.text);
    if (bed != null) {
      targets[_heaters.bed] = bed;
      if (bed > 0) roles[bedRole] = bed;
      confirmParts.add('${l.preheatBed} ${bed.round()}°');
    }

    // The chamber: a temperature to wait for on a passive (bed-warmed)
    // chamber, and additionally a target to SET on the rare active one.
    final chamber = _hasChamber ? _parseTemp(_chamberCtl.text) : null;
    if (chamber != null && chamber > 0) {
      roles[chamberRole] = chamber;
      final heater = _chamberHeater;
      if (heater != null) {
        targets[heater] = chamber;
        confirmParts.add('${l.preheatChamber} ${chamber.round()}°');
      }
    }

    if (targets.isEmpty) return; // nothing to set
    final minutes = _parseMinutes(_timeCtl.text);
    final messenger = ScaffoldMessenger.of(context); // survives the pop

    setState(() => _sending = true);
    final ok = await _control.setHeaterTargets(targets);
    if (!mounted) return;

    if (!ok) {
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(
        content: Text(l.preheatFailed),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
      return;
    }

    // Arm (or clear) the heat-soak alert. Armed even when notifications are
    // off - the in-sheet warning already flagged that - so it still fires if
    // the user enables them before the temperatures arrive.
    final soak = _soakOn && roles.isNotEmpty;
    if (soak) {
      await HeatsoakTimers.arm(
        widget.printer.id,
        HeatSoakArm(
          armedAtMs:   DateTime.now().millisecondsSinceEpoch,
          targets:     roles,
          multi:       _isMulti,
          soakMinutes: minutes,
        ),
      );
    } else {
      await HeatsoakTimers.cancel(widget.printer.id);
    }
    if (!mounted) return;

    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text(_confirmText(l, confirmParts, soak ? minutes : null)),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  /// "Set Hotend 210° · Bed 60°", plus what was armed: the soak time when one
  /// is set, "at-temperature alert on" for a 0-minute soak, nothing when the
  /// alert is off ([soakMinutes] null).
  String _confirmText(
      AppLocalizations l, List<String> parts, int? soakMinutes) {
    final set = l.preheatSetConfirm(parts.join(' · '));
    if (soakMinutes == null) return set;
    final armed = soakMinutes > 0
        ? l.preheatSoakIn(soakMinutes)
        : l.preheatAtTempArmed;
    return '$set · $armed';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final notifsOn = ref.watch(printNotificationsEnabledProvider);
    final hasTemp = _hotendCtls.any((c) => c.text.trim().isNotEmpty) ||
        _bedCtl.text.trim().isNotEmpty;
    final chamberNeedsBed = _chamberNeedsBed;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: title + printer name (matches the macros sheet) ──
              Text(l.preheatTitle, style: theme.textTheme.titleMedium),
              Text(
                widget.printer.name,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),

              // ── Hotend(s) + bed targets (any may be left blank) ──────────
              // Single-hotend printers keep the classic Hotend + Bed fields; a
              // multi-toolhead printer lists a compact row per tool (T0, T1, …)
              // then Bed, so every hotend can be set at once.
              if (_isMulti) ...[
                for (var i = 0; i < _tools.length; i++) ...[
                  _HeaterRow(
                    controller: _hotendCtls[i],
                    label: 'T${_tools[i].index}',
                    icon: Icons.whatshot,
                    color: Colors.deepOrange,
                    currentTarget: _tools[i].target,
                    active: _tools[i].active,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                ],
                _HeaterRow(
                  controller: _bedCtl,
                  label: l.preheatBed,
                  icon: Icons.bed,
                  color: Colors.blue,
                  currentTarget: widget.bedTarget,
                  active: false,
                  onChanged: (_) => setState(() {}),
                ),
              ] else ...[
                _TempField(
                  controller: _hotendCtls[0],
                  label: l.preheatHotend,
                  icon: Icons.whatshot,
                  color: Colors.deepOrange,
                  currentTarget: widget.hotendTarget,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _TempField(
                  controller: _bedCtl,
                  label: l.preheatBed,
                  icon: Icons.bed,
                  color: Colors.blue,
                  currentTarget: widget.bedTarget,
                  onChanged: (_) => setState(() {}),
                ),
              ],

              // ── Chamber (only when the printer reports a chamber sensor) ──
              // On the usual passive chamber this is a temperature to wait
              // for, warmed by the bed - hence the bed rule below; on a
              // printer with a chamber heater it is set like any other.
              if (_hasChamber) ...[
                const SizedBox(height: 12),
                _TempField(
                  controller: _chamberCtl,
                  label: l.preheatChamber,
                  icon: Icons.sensor_window,
                  color: Colors.teal,
                  currentTarget: widget.chamberTarget,
                  helperText: l.preheatChamberHelp,
                  errorText: chamberNeedsBed ? l.preheatChamberNeedsBed : null,
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                l.preheatHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),

              // ── Optional heat-soak alert ─────────────────────────────────
              // Runs in the Android print-notification service (its isolate
              // watches the thermistors and the soak clock), so on iOS the
              // controls give way to a one-line note instead of offering an
              // alert that can never fire.
              if (Platform.isAndroid) ...[
                SwitchListTile(
                  value: _soakOn,
                  onChanged: (v) => setState(() => _soakOn = v),
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.thermostat_outlined),
                  title: Text(l.preheatSoakSwitch),
                  subtitle: Text(l.preheatSoakSwitchHelp),
                ),
                if (_soakOn) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _timeCtl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: l.preheatSoakLabel,
                      helperText: l.preheatSoakHelp,
                      prefixIcon: const Icon(Icons.timer_outlined),
                      suffixText: l.preheatMinutes,
                      border: const OutlineInputBorder(),
                    ),
                  ),

                  // The alert needs the print-notification service running,
                  // so warn (with a one-tap enable) when it's off.
                  if (!notifsOn) ...[
                    const SizedBox(height: 12),
                    _NotifWarning(onEnable: _enableNotifications),
                  ],
                ],
              ] else
                Text(
                  l.preheatAlertsAndroidOnly,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_sending || !hasTemp || chamberNeedsBed)
                      ? null
                      : _submit,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.local_fire_department),
                  label: Text(l.preheatSet),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One integer-°C temperature field. Empty = leave that heater alone; the
/// current target (when set) shows as the greyed hint so the user can see what
/// it's on now. Optional helper / error text under the box (the chamber field
/// uses both).
class _TempField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color color;
  final double currentTarget;
  final String? helperText;
  final String? errorText;
  final ValueChanged<String> onChanged;

  const _TempField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.color,
    required this.currentTarget,
    this.helperText,
    this.errorText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: color),
        suffixText: '°C',
        hintText: currentTarget > 0 ? currentTarget.round().toString() : null,
        helperText: helperText,
        helperMaxLines: 3,
        errorText: errorText,
        errorMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// One compact heater row for the multi-toolhead preheat layout: a coloured
/// flame/bed icon, a short label (T0, T1, ... / Bed) with the active tool bold,
/// and a dense °C field on the right. Empty = leave that heater alone; the
/// current target (when set) shows as the greyed hint.
class _HeaterRow extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color color;
  final double currentTarget;
  final bool active;
  final ValueChanged<String> onChanged;

  const _HeaterRow({
    required this.controller,
    required this.label,
    required this.icon,
    required this.color,
    required this.currentTarget,
    required this.active,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: active ? FontWeight.bold : FontWeight.w500,
              color: active ? theme.colorScheme.primary : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: onChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText:
                  currentTarget > 0 ? currentTarget.round().toString() : null,
              suffixText: '°C',
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}

/// Heads-up shown when the heat-soak alert is on but print notifications are
/// off (so the alert can't fire), with a one-tap enable.
class _NotifWarning extends StatelessWidget {
  final VoidCallback onEnable;
  const _NotifWarning({required this.onEnable});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_off_outlined,
              size: 20, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l.preheatNotifWarning,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(onPressed: onEnable, child: Text(l.preheatNotifEnable)),
        ],
      ),
    );
  }
}
