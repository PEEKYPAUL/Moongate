import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../services/print_control_service.dart';
import '../../services/printer_status_registry.dart';
import '../../widgets/app_icons.dart';

/// Outcome of a global power action, surfaced as a snackbar by the caller after
/// the sheet closes (the sheet's own context is gone once it pops).
class _PowerResult {
  final bool on; // true = powered on, false = powered off
  final int done; // machines where the action succeeded
  final int total; // machines we attempted
  const _PowerResult(
      {required this.on, required this.done, required this.total});

  String message(AppLocalizations l) =>
      on ? l.globalPowerResultOn(done, total) : l.globalPowerResultOff(done, total);
}

/// Show the "power all machines" sheet. On open it resolves each printer's power
/// capability (its Advanced Power macros when enabled, otherwise its Moonraker
/// power devices), then offers only the actions the fleet actually supports:
/// "power on all" (a tap) and/or "power off all" (a slide-to-confirm). Machines
/// that are printing or unreachable are excluded and shown as such. Surfaces a
/// result snackbar via [context] once it closes.
Future<void> showGlobalPowerSheet(
    BuildContext context, List<PrinterConfig> printers) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = AppLocalizations.of(context);
  final result = await showModalBottomSheet<_PowerResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _GlobalPowerSheet(printers: printers),
  );
  if (result != null) {
    messenger.showSnackBar(SnackBar(content: Text(result.message(l))));
  }
}

/// How one dashboard printer can be powered in bulk, resolved when the sheet
/// opened. A printer drives EITHER its Advanced Power macros ([macroMode]) or a
/// Moonraker `[power …]` device, never both - mirroring the per-tile button.
class _Row {
  final PrinterConfig printer;

  /// Drive via Advanced Power macros (true) or Moonraker power devices (false).
  final bool macroMode;

  /// Its Moonraker power devices (device mode only; empty in macro mode).
  final List<PowerDevice> devices;

  /// Reachable enough to act on now: the Pi answered for its devices (device
  /// mode), or the live status says it's online with Klipper up (macro mode - a
  /// Klipper power macro can't run on a machine that's off).
  final bool reachable;

  /// Currently printing or paused (never powered off).
  final bool printing;

  /// A usable on / off path exists for this printer.
  final bool canOn;
  final bool canOff;

  /// Macro mode with ONLY a toggle macro: usable from the tile button but not a
  /// directional bulk action (a toggle can't know which way to go across a
  /// fleet). Shown muted so the user sees why it's not included.
  final bool toggleOnly;

  _Row({
    required this.printer,
    required this.macroMode,
    required this.devices,
    required this.reachable,
    required this.printing,
    required this.canOn,
    required this.canOff,
    required this.toggleOnly,
  });

  /// Eligible to be switched on / off by the bulk action: reachable, not
  /// mid-print, and has that direction.
  bool get onTarget => reachable && !printing && canOn;
  bool get offTarget => reachable && !printing && canOff;

  /// Some configured power capability (so it's worth a "skipped" line even when
  /// offline). A reachable machine with no power control at all is hidden.
  bool get capable => canOn || canOff || toggleOnly;

  /// Worth a row: power-capable, or an unreachable machine (shown as skipped, in
  /// case its capability just couldn't be read).
  bool get relevant => capable || !reachable;
}

class _GlobalPowerSheet extends StatefulWidget {
  final List<PrinterConfig> printers;
  const _GlobalPowerSheet({required this.printers});

  @override
  State<_GlobalPowerSheet> createState() => _GlobalPowerSheetState();
}

class _GlobalPowerSheetState extends State<_GlobalPowerSheet> {
  List<_Row>? _rows; // null while loading
  bool _busy = false; // an on/off run is in progress

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await Future.wait(widget.printers.map(_resolve));
    if (!mounted) return;
    setState(() => _rows = rows.where((r) => r.relevant).toList());
  }

  /// Resolve one printer's power capability for the sheet. Macro-mode printers
  /// read from config + the live status (no round-trip); device-mode printers
  /// ask Moonraker for their `[power]` devices.
  Future<_Row> _resolve(PrinterConfig p) async {
    final st = PrinterStatusRegistry.instance.snapshot(p.id);
    final printing = st?.isPrinting ?? false;

    if (p.powerMacroEnabled) {
      final hasOn = p.powerOnMacro?.isNotEmpty ?? false;
      final hasOff = p.powerOffMacro?.isNotEmpty ?? false;
      final hasToggle = p.powerToggleMacro?.isNotEmpty ?? false;
      return _Row(
        printer: p,
        macroMode: true,
        devices: const [],
        reachable: _online(st),
        printing: printing,
        canOn: hasOn,
        canOff: hasOff,
        toggleOnly: !hasOn && !hasOff && hasToggle,
      );
    }

    final devices = await PrintControlService(p).listPowerDevices();
    final hasDevices = devices != null && devices.isNotEmpty;
    return _Row(
      printer: p,
      macroMode: false,
      devices: devices ?? const [],
      reachable: devices != null,
      printing: printing,
      canOn: hasDevices,
      canOff: hasDevices,
      toggleOnly: false,
    );
  }

  /// Online enough to run a Klipper power macro: the Pi answered and Klipper is
  /// up. A machine that's offline or "waiting" (powered off, Klipper down) can't
  /// run one, so it's treated as unreachable for macro power.
  bool _online(PrinterStatus? st) =>
      st != null &&
      st.connection != PrinterConnection.offline &&
      st.state != 'offline' &&
      st.state != 'waiting';

  Future<void> _powerOnAll() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.globalPowerConfirmOnTitle),
        content: Text(l.globalPowerConfirmOnBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.globalPowerOnAll),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(on: true, targets: _rows!.where((r) => r.onTarget).toList());
  }

  Future<void> _powerOffAll() =>
      _run(on: false, targets: _rows!.where((r) => r.offTarget).toList());

  Future<void> _run({required bool on, required List<_Row> targets}) async {
    setState(() => _busy = true);
    var done = 0;
    for (final r in targets) {
      final svc = PrintControlService(r.printer);
      bool ok;
      if (r.macroMode) {
        // Run the configured on / off macro (LAN-first, then tunnel).
        final macro = on ? r.printer.powerOnMacro : r.printer.powerOffMacro;
        ok = macro != null && macro.isNotEmpty && await svc.runMacro(macro);
      } else {
        // Switch every Moonraker power device on the machine.
        ok = r.devices.isNotEmpty;
        for (final d in r.devices) {
          if (!await svc.setPowerDevice(d.name, on)) ok = false;
        }
      }
      if (ok) done++;
    }
    if (!mounted) return;
    Navigator.pop(
        context, _PowerResult(on: on, done: done, total: targets.length));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rows = _rows;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(AppIcons.power_settings_new, size: 22),
                const SizedBox(width: 8),
                Text(l.globalPowerSheetTitle,
                    style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 12),
            if (rows == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!rows.any((r) => r.capable))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(l.globalPowerNothing,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor)),
              )
            else ...[
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: ListView(
                  shrinkWrap: true,
                  children: [for (final r in rows) _rowTile(r, theme, l)],
                ),
              ),
              const SizedBox(height: 12),
              // "Power on all" appears only when at least one machine can be
              // powered on (a device, or an on macro).
              if (rows.any((r) => r.onTarget)) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _powerOnAll,
                    icon: const Icon(AppIcons.power_settings_new, size: 18),
                    label: Text(l.globalPowerOnAll),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              // "Power off all" appears only when at least one machine can be
              // powered off.
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (rows.any((r) => r.offTarget))
                _SlideToConfirm(
                    label: l.globalPowerSlideOff, onConfirm: _powerOffAll),
              const SizedBox(height: 8),
              Center(
                child: Text(l.globalPowerPrintingNote,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rowTile(_Row r, ThemeData theme, AppLocalizations l) {
    final cs = theme.colorScheme;
    String label;
    Color color;
    if (!r.reachable) {
      label = l.globalPowerStateOffline;
      color = theme.hintColor;
    } else if (r.printing) {
      label = l.globalPowerStateKeptPrinting;
      color = cs.tertiary;
    } else if (r.toggleOnly) {
      label = l.globalPowerStateToggleOnly;
      color = cs.outline;
    } else if (r.canOn && r.canOff) {
      label = l.globalPowerStateOnOff;
      color = cs.primary;
    } else if (r.canOff) {
      label = l.globalPowerStateOffOnly;
      color = cs.primary;
    } else {
      label = l.globalPowerStateOnOnly;
      color = cs.primary;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(AppIcons.print_outlined,
              size: 18, color: r.reachable ? null : theme.disabledColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(r.printer.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Text(label,
              style: theme.textTheme.labelMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Slide-to-confirm control: drag the thumb across to fire [onConfirm]. Used for
/// the deliberately-hard "power off everything" action so it can never be a
/// stray tap. Releasing short of the end snaps back; clearing ~90% commits.
class _SlideToConfirm extends StatefulWidget {
  final String label;
  final VoidCallback onConfirm;
  const _SlideToConfirm({required this.label, required this.onConfirm});

  @override
  State<_SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<_SlideToConfirm> {
  double _dx = 0;
  bool _committed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const height = 52.0;
    const thumb = 46.0;
    return LayoutBuilder(builder: (ctx, c) {
      final maxDx = (c.maxWidth - thumb - 4).clamp(0.0, double.infinity);
      final progress = maxDx == 0 ? 0.0 : (_dx / maxDx).clamp(0.0, 1.0);
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Stack(
          children: [
            Center(
              child: Opacity(
                opacity: (1 - progress).clamp(0.0, 1.0),
                child: Text(widget.label,
                    style: TextStyle(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            Positioned(
              left: 2 + _dx,
              top: 3,
              child: GestureDetector(
                onHorizontalDragUpdate: _committed
                    ? null
                    : (d) => setState(
                        () => _dx = (_dx + d.delta.dx).clamp(0.0, maxDx)),
                onHorizontalDragEnd: _committed
                    ? null
                    : (_) {
                        if (_dx >= maxDx * 0.9) {
                          setState(() {
                            _dx = maxDx;
                            _committed = true;
                          });
                          widget.onConfirm();
                        } else {
                          setState(() => _dx = 0);
                        }
                      },
                child: Container(
                  width: thumb,
                  height: thumb,
                  decoration:
                      BoxDecoration(color: cs.error, shape: BoxShape.circle),
                  child: Icon(
                      _committed ? AppIcons.check : AppIcons.power_settings_new,
                      color: cs.onError),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
