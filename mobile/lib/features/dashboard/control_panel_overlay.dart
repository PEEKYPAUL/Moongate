import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../services/print_control_service.dart';
import '../../services/printer_registry.dart';
import 'macro_control_builder.dart';
import 'macros_overlay.dart';

Future<void> showControlPanel(
    BuildContext context, PrinterConfig printer, PrinterStatus status) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.94,
      child: _ControlPanel(printer: printer, status: status),
    ),
  );
}

class _ControlPanel extends StatefulWidget {
  final PrinterConfig printer;
  final PrinterStatus status;

  const _ControlPanel({required this.printer, required this.status});

  @override
  State<_ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<_ControlPanel> {
  late List<ControlPanelModule> _modules;
  late List<MacroControl> _macroControls;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _reloadFromRegistry();
  }

  PrinterConfig get _livePrinter => PrinterRegistry.instance.printers
      .where((printer) => printer.id == widget.printer.id)
      .firstOrNull ??
      widget.printer;

  void _reloadFromRegistry() {
    final printer = _livePrinter;
    _modules = [...printer.controlPanelModules];
    _macroControls = [...printer.macroControls];
  }

  Future<void> _saveModules(List<ControlPanelModule> modules) async {
    setState(() => _modules = modules);
    await PrinterRegistry.instance
        .updateControlPanelModules(widget.printer.id, modules);
  }

  Future<void> _choosePreset() async {
    final l = AppLocalizations.of(context);
    final preset = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.controlPanelPresets),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'essential'),
            child: Text(l.controlPanelPresetEssential),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'motion'),
            child: Text(l.controlPanelPresetMotion),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'macros'),
            child: Text(l.controlPanelPresetMacros),
          ),
        ],
      ),
    );
    if (preset == null || !mounted) return;
    final modules = switch (preset) {
      'motion' => defaultControlPanelModules.take(2).toList(),
      'macros' => [defaultControlPanelModules.last],
      _ => [...defaultControlPanelModules],
    };
    await _saveModules(modules);
  }

  Future<Color?> _pickColor(Color initial) {
    var hsv = HSVColor.fromColor(initial);
    return showDialog<Color>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context).macroControlColor),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 64,
                decoration: BoxDecoration(
                  color: hsv.toColor(),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              Slider(
                value: hsv.hue,
                min: 0,
                max: 360,
                onChanged: (value) => setDialogState(
                    () => hsv = hsv.withHue(value)),
              ),
              Slider(
                value: hsv.saturation,
                onChanged: (value) => setDialogState(
                    () => hsv = hsv.withSaturation(value)),
              ),
              Slider(
                value: hsv.value,
                onChanged: (value) =>
                    setDialogState(() => hsv = hsv.withValue(value)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, hsv.toColor()),
              child: Text(AppLocalizations.of(context).commonDone),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editModule(ControlPanelModule module) async {
    final title = TextEditingController(text: module.title);
    var color = Color(module.color);
    final updated = await showDialog<ControlPanelModule>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context).controlPanelEditModule),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).macroControlLabel),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(backgroundColor: color),
                title: Text(AppLocalizations.of(context).macroControlColor),
                trailing: const Icon(Icons.colorize),
                onTap: () async {
                  final picked = await _pickColor(color);
                  if (picked != null) setDialogState(() => color = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                ControlPanelModule(
                  id: module.id,
                  type: module.type,
                  title: title.text.trim(),
                  color: color.toARGB32(),
                ),
              ),
              child: Text(AppLocalizations.of(context).commonSave),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    if (updated == null || !mounted) return;
    await _saveModules([
      for (final item in _modules) if (item.id == module.id) updated else item,
    ]);
  }

  Future<void> _addModule() async {
    final used = _modules.map((module) => module.type).toSet();
    final available = ControlPanelModuleType.values
        .where((type) => !used.contains(type))
        .toList();
    if (available.isEmpty) return;
    final type = await showDialog<ControlPanelModuleType>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppLocalizations.of(context).controlPanelAddModule),
        children: [
          for (final type in available)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, type),
              child: Text(_moduleName(type)),
            ),
        ],
      ),
    );
    if (type == null || !mounted) return;
    final preset = defaultControlPanelModules.firstWhere(
        (module) => module.type == type);
    await _saveModules([..._modules, preset]);
  }

  String _moduleName(ControlPanelModuleType type) {
    final l = AppLocalizations.of(context);
    return switch (type) {
      ControlPanelModuleType.temperatures => l.controlPanelTemperatures,
      ControlPanelModuleType.motion => l.controlPanelMotion,
      ControlPanelModuleType.macros => l.macrosSheetTitle,
    };
  }

  Widget _module(ControlPanelModule module) {
    final color = Color(module.color);
    final foreground = color.computeLuminance() > 0.6
        ? Colors.black87
        : color;
    final title = module.title.isEmpty ? _moduleName(module.type) : module.title;
    final icon = switch (module.type) {
      ControlPanelModuleType.temperatures => Icons.thermostat_rounded,
      ControlPanelModuleType.motion => Icons.open_with_rounded,
      ControlPanelModuleType.macros => Icons.bolt_rounded,
    };
    final content = switch (module.type) {
      ControlPanelModuleType.temperatures => _TemperatureModule(
          printer: widget.printer, status: widget.status, color: color),
      ControlPanelModuleType.motion =>
        _MotionModule(
            printer: widget.printer, status: widget.status, color: color),
      ControlPanelModuleType.macros => _MacrosModule(
          printer: widget.printer,
          controls: _macroControls,
          color: color,
          onManage: () async {
            await showMacrosSheet(context, widget.printer);
            if (!mounted) return;
            setState(_reloadFromRegistry);
          },
        ),
    };
    return Card(
      key: ValueKey(module.id),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: color.withValues(alpha: 0.14),
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Icon(icon, color: foreground, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: foreground, fontWeight: FontWeight.bold)),
                ),
                if (_editing) ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editModule(module),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _saveModules(
                        _modules.where((item) => item.id != module.id).toList()),
                  ),
                  const Icon(Icons.drag_handle),
                ],
              ],
            ),
          ),
          content,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.controlPanelTitle,
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(widget.printer.name,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                tooltip: l.controlPanelPresets,
                icon: const Icon(Icons.auto_awesome_outlined),
                onPressed: _choosePreset,
              ),
              TextButton.icon(
                onPressed: () => setState(() => _editing = !_editing),
                icon: Icon(_editing ? Icons.check : Icons.dashboard_customize),
                label: Text(_editing ? l.commonDone : l.controlPanelCustomize),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _modules.isEmpty
              ? Center(
                  child: FilledButton.icon(
                    onPressed: _addModule,
                    icon: const Icon(Icons.add),
                    label: Text(l.controlPanelAddModule),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.all(12),
                  buildDefaultDragHandles: false,
                  itemCount: _modules.length + (_editing ? 1 : 0),
                  onReorderItem: (oldIndex, newIndex) {
                    if (oldIndex >= _modules.length) return;
                    final modules = [..._modules];
                    modules.insert(newIndex, modules.removeAt(oldIndex));
                    _saveModules(modules);
                  },
                  itemBuilder: (context, index) {
                    if (index == _modules.length) {
                      return Padding(
                        key: const ValueKey('add-module'),
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          onPressed: _addModule,
                          icon: const Icon(Icons.add),
                          label: Text(l.controlPanelAddModule),
                        ),
                      );
                    }
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(_modules[index].id),
                      index: index,
                      enabled: _editing,
                      child: _module(_modules[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TemperatureModule extends StatefulWidget {
  final PrinterConfig printer;
  final PrinterStatus status;
  final Color color;

  const _TemperatureModule(
      {required this.printer, required this.status, required this.color});

  @override
  State<_TemperatureModule> createState() => _TemperatureModuleState();
}

class _TemperatureModuleState extends State<_TemperatureModule> {
  late final PrintControlService _control;
  late final TextEditingController _hotend;
  late final TextEditingController _bed;
  ({String hotend, String bed}) _heaters =
      (hotend: 'extruder', bed: 'heater_bed');
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _control = PrintControlService(widget.printer);
    _hotend = TextEditingController(
        text: widget.status.hotendTarget > 0
            ? widget.status.hotendTarget.round().toString()
            : '');
    _bed = TextEditingController(
        text: widget.status.bedTarget > 0
            ? widget.status.bedTarget.round().toString()
            : '');
    _control.detectHeaters().then((value) {
      if (mounted) setState(() => _heaters = value);
    });
  }

  @override
  void dispose() {
    _hotend.dispose();
    _bed.dispose();
    super.dispose();
  }

  Future<void> _set({bool off = false}) async {
    if (_sending) return;
    final hotend = off ? 0.0 : double.tryParse(_hotend.text.trim());
    final bed = off ? 0.0 : double.tryParse(_bed.text.trim());
    final targets = <String, double>{
      if (hotend != null) _heaters.hotend: hotend.clamp(0, 500),
      if (bed != null) _heaters.bed: bed.clamp(0, 500),
    };
    if (targets.isEmpty) return;
    setState(() => _sending = true);
    final ok = await _control.setHeaterTargets(targets);
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? AppLocalizations.of(context).controlPanelCommandSent
          : AppLocalizations.of(context).preheatFailed),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hotend,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText:
                        '${l.preheatHotend} · ${widget.status.hotendTemp.round()}°',
                    suffixText: '°C',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _bed,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText:
                        '${l.preheatBed} · ${widget.status.bedTemp.round()}°',
                    suffixText: '°C',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  onPressed: _sending ? null : () => _set(off: true),
                  child: Text(l.controlPanelHeatersOff)),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: widget.color,
                  foregroundColor: widget.color.computeLuminance() > 0.6
                      ? Colors.black87
                      : Colors.white,
                ),
                onPressed: _sending ? null : _set,
                child: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(l.preheatSet),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MotionModule extends StatefulWidget {
  final PrinterConfig printer;
  final PrinterStatus status;
  final Color color;

  const _MotionModule(
      {required this.printer, required this.status, required this.color});

  @override
  State<_MotionModule> createState() => _MotionModuleState();
}

class _MotionModuleState extends State<_MotionModule> {
  late final PrintControlService _control;
  double _distance = 10;
  bool _moving = false;
  bool _loadingState = true;
  MotionPanelState? _state;

  @override
  void initState() {
    super.initState();
    _control = PrintControlService(widget.printer);
    _refreshState();
  }

  Future<void> _refreshState() async {
    final state = await _control.motionPanelState();
    if (!mounted) return;
    setState(() {
      _state = state;
      _loadingState = false;
    });
  }

  Future<void> _send(String command) async {
    if (_moving) return;
    setState(() => _moving = true);
    final ok = await _control.runPanelCommand(command);
    if (!mounted) return;
    setState(() => _moving = false);
    if (ok) _refreshState();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).consoleSendFailed),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _jog(String axis, double direction) {
    final amount = (_distance * direction).toStringAsFixed(
        _distance < 1 ? 1 : 0);
    _send('SAVE_GCODE_STATE NAME=MOONGATE_JOG\nG91\nG0 $axis$amount F3000\nRESTORE_GCODE_STATE NAME=MOONGATE_JOG');
  }

  void _extrude(double direction) {
    final amount = (_distance * direction).toStringAsFixed(
        _distance < 1 ? 1 : 0);
    _send('SAVE_GCODE_STATE NAME=MOONGATE_EXTRUDE\nM83\nG1 E$amount F300\nRESTORE_GCODE_STATE NAME=MOONGATE_EXTRUDE');
  }

  Future<void> _setPosition() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.controlPanelSetPosition),
        content: Text(l.controlPanelSetPositionConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.controlPanelSetPosition),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _send('SET_KINEMATIC_POSITION X=0 Y=0 Z=0');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final axes = _state?.homedAxes ?? '';
    final homed = axes.contains('x') && axes.contains('y') && axes.contains('z');
    final position = _state?.position ?? const <double>[];
    final statusColor = _loadingState || _state == null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : homed
            ? Colors.green
            : Theme.of(context).colorScheme.error;
    Widget button(IconData icon, VoidCallback action, String tooltip) =>
        IconButton.filledTonal(
          icon: Icon(icon),
          tooltip: tooltip,
          onPressed: _moving ? null : action,
        );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (_loadingState)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(homed ? Icons.check_circle : Icons.warning_amber_rounded,
                      color: statusColor, size: 19),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _loadingState
                        ? l.controlPanelPositionUnknown
                        : homed
                            ? l.controlPanelHomed
                            : _state == null
                                ? l.controlPanelPositionUnknown
                                : l.controlPanelNotHomed,
                    style: TextStyle(
                        color: statusColor, fontWeight: FontWeight.w600),
                  ),
                ),
                if (position.length >= 3)
                  Text(
                    'X ${position[0].toStringAsFixed(1)}  Y ${position[1].toStringAsFixed(1)}  Z ${position[2].toStringAsFixed(1)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
          if (!homed && (_state?.forceMoveEnabled ?? false)) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _moving ? null : _setPosition,
                icon: const Icon(Icons.my_location_rounded),
                label: Text(l.controlPanelSetPosition),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 0.1, label: Text('0.1 mm')),
              ButtonSegment(value: 1, label: Text('1 mm')),
              ButtonSegment(value: 10, label: Text('10 mm')),
            ],
            selected: {_distance},
            onSelectionChanged: (value) =>
                setState(() => _distance = value.single),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  button(Icons.keyboard_arrow_up, () => _jog('Y', 1), 'Y+'),
                  Row(
                    children: [
                      button(Icons.keyboard_arrow_left, () => _jog('X', -1), 'X−'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: FilledButton.tonal(
                          onPressed: _moving ? null : () => _send('G28'),
                          child: Text(l.controlPanelHome),
                        ),
                      ),
                      button(Icons.keyboard_arrow_right, () => _jog('X', 1), 'X+'),
                    ],
                  ),
                  button(Icons.keyboard_arrow_down, () => _jog('Y', -1), 'Y−'),
                ],
              ),
              const SizedBox(width: 24),
              Column(
                children: [
                  button(Icons.add, () => _jog('Z', 1), 'Z+'),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Z'),
                  ),
                  button(Icons.remove, () => _jog('Z', -1), 'Z−'),
                ],
              ),
            ],
          ),
          const Divider(height: 28),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
                '${l.controlPanelExtruder} · ${widget.status.hotendTemp.round()}°C',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _moving ? null : () => _extrude(-1),
                icon: const Icon(Icons.remove),
                label: Text(l.controlPanelRetract),
              ),
              FilledButton.icon(
                onPressed: _moving ? null : () => _extrude(1),
                icon: const Icon(Icons.add),
                label: Text(l.controlPanelExtrude),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MacrosModule extends StatefulWidget {
  final PrinterConfig printer;
  final List<MacroControl> controls;
  final Color color;
  final VoidCallback onManage;

  const _MacrosModule({
    required this.printer,
    required this.controls,
    required this.color,
    required this.onManage,
  });

  @override
  State<_MacrosModule> createState() => _MacrosModuleState();
}

class _MacrosModuleState extends State<_MacrosModule> {
  String? _running;

  Future<void> _run(MacroControl control) async {
    if (_running != null) return;
    final command = await showMacroControlRunner(context, control);
    if (command == null || !mounted) return;
    setState(() => _running = control.id);
    final ok = await PrintControlService(widget.printer).runMacro(command);
    if (!mounted) return;
    setState(() => _running = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? AppLocalizations.of(context).macroSent(control.label)
          : AppLocalizations.of(context).macroFailed(control.label)),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.controls.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l.controlPanelNoMacroControls,
                  textAlign: TextAlign.center),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final control in widget.controls)
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                        foregroundColor: widget.color.computeLuminance() > 0.6
                            ? Colors.black87
                            : widget.color),
                    onPressed: _running == null ? () => _run(control) : null,
                    icon: _running == control.id
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(macroControlIcon(control.icon)),
                    label: Text(control.label),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onManage,
              icon: const Icon(Icons.settings_outlined),
              label: Text(l.controlPanelManageMacros),
            ),
          ),
        ],
      ),
    );
  }
}
