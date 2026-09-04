import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';

IconData macroControlIcon(String value) => switch (value) {
      'filament' => Icons.cable_rounded,
      'tune' => Icons.tune_rounded,
      'clean' => Icons.cleaning_services_rounded,
      _ => Icons.play_arrow_rounded,
    };

Color macroControlColor(BuildContext context, String value) => switch (value) {
      'purple' => Colors.deepPurple,
      'orange' => Colors.deepOrange,
      'green' => Colors.green,
      _ => Theme.of(context).colorScheme.primary,
    };

Future<MacroControl?> showMacroControlBuilder(
  BuildContext context, {
  required String macro,
  MacroControl? existing,
  List<MacroControlParameter> suggestedParameters = const [],
}) =>
    showModalBottomSheet<MacroControl>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MacroControlBuilder(
        macro: macro,
        existing: existing,
        suggestedParameters: suggestedParameters,
      ),
    );

class _MacroControlBuilder extends StatefulWidget {
  final String macro;
  final MacroControl? existing;
  final List<MacroControlParameter> suggestedParameters;

  const _MacroControlBuilder({
    required this.macro,
    required this.suggestedParameters,
    this.existing,
  });

  @override
  State<_MacroControlBuilder> createState() => _MacroControlBuilderState();
}

class _MacroControlBuilderState extends State<_MacroControlBuilder> {
  late final TextEditingController _label;
  late String _icon;
  late String _color;
  late bool _confirm;
  late List<MacroControlParameter> _parameters;

  @override
  void initState() {
    super.initState();
    final control = widget.existing;
    _label = TextEditingController(text: control?.label ?? widget.macro);
    _icon = control?.icon ?? 'play';
    _color = control?.color ?? 'blue';
    _confirm = control?.confirm ?? true;
    _parameters = [
      ...(control?.parameters ?? widget.suggestedParameters),
    ];
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _editParameter([int? index]) async {
    final current = index == null ? null : _parameters[index];
    final name = TextEditingController(text: current?.name ?? '');
    final label = TextEditingController(text: current?.label ?? '');
    final initial = TextEditingController(text: current?.defaultValue ?? '');
    var kind = current?.kind ?? MacroControlParameterKind.number;
    String? error;
    final result = await showDialog<MacroControlParameter>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(current == null
              ? AppLocalizations.of(context).macroControlAddParameter
              : AppLocalizations.of(context).macroControlEditParameter),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).macroControlParameterName,
                    errorText: error,
                  ),
                ),
                TextField(
                  controller: label,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).macroControlParameterLabel),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MacroControlParameterKind>(
                  initialValue: kind,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).macroControlParameterType),
                  items: [
                    DropdownMenuItem(
                      value: MacroControlParameterKind.number,
                      child: Text(AppLocalizations.of(context).macroControlTypeNumber),
                    ),
                    DropdownMenuItem(
                      value: MacroControlParameterKind.text,
                      child: Text(AppLocalizations.of(context).macroControlTypeText),
                    ),
                    DropdownMenuItem(
                      value: MacroControlParameterKind.toggle,
                      child: Text(AppLocalizations.of(context).macroControlTypeToggle),
                    ),
                  ],
                  onChanged: (value) => setDialogState(() => kind = value!),
                ),
                if (kind != MacroControlParameterKind.toggle)
                  TextField(
                    controller: initial,
                    keyboardType: kind == MacroControlParameterKind.number
                        ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                        : TextInputType.text,
                    decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).macroControlDefaultValue),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).commonCancel),
            ),
            FilledButton(
              onPressed: () {
                final key = name.text.trim().toUpperCase();
                final valid = RegExp(r'^[A-Z_][A-Z0-9_]*$').hasMatch(key);
                final duplicate = _parameters.asMap().entries.any(
                    (entry) => entry.key != index && entry.value.name == key);
                if (!valid || duplicate) {
                  setDialogState(() => error = AppLocalizations.of(context)
                      .macroControlParameterInvalid);
                  return;
                }
                Navigator.pop(
                  context,
                  MacroControlParameter(
                    name: key,
                    label: label.text.trim().isEmpty ? key : label.text.trim(),
                    kind: kind,
                    defaultValue: kind == MacroControlParameterKind.toggle
                        ? '0'
                        : initial.text.trim(),
                  ),
                );
              },
              child: Text(AppLocalizations.of(context).commonDone),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    label.dispose();
    initial.dispose();
    if (result == null || !mounted) return;
    setState(() => index == null
        ? _parameters.add(result)
        : _parameters[index] = result);
  }

  void _save() {
    final label = _label.text.trim();
    if (label.isEmpty) return;
    Navigator.pop(
      context,
      MacroControl(
        id: widget.existing?.id ??
            '${widget.macro}-${DateTime.now().microsecondsSinceEpoch}',
        macro: widget.macro,
        label: label,
        icon: _icon,
        color: _color,
        confirm: _confirm,
        parameters: _parameters,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.existing == null
                  ? l.macroControlCreate
                  : l.macroControlEdit,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(widget.macro,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              TextField(
                controller: _label,
                autofocus: widget.existing == null,
                decoration: InputDecoration(labelText: l.macroControlLabel),
              ),
              const SizedBox(height: 16),
              Text(l.macroControlIcon,
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final icon in ['play', 'filament', 'tune', 'clean'])
                    ChoiceChip(
                      selected: _icon == icon,
                      avatar: Icon(macroControlIcon(icon), size: 18),
                      label: Text(icon),
                      onSelected: (_) => setState(() => _icon = icon),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(l.macroControlColor,
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final color in ['blue', 'purple', 'orange', 'green'])
                    ChoiceChip(
                      selected: _color == color,
                      avatar: CircleAvatar(
                          radius: 7,
                          backgroundColor: macroControlColor(context, color)),
                      label: Text(color),
                      onSelected: (_) => setState(() => _color = color),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.macroControlConfirm),
                value: _confirm,
                onChanged: (value) => setState(() => _confirm = value),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(l.macroControlParameters,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  TextButton.icon(
                    onPressed: _editParameter,
                    icon: const Icon(Icons.add),
                    label: Text(l.macroControlAddParameter),
                  ),
                ],
              ),
              for (var i = 0; i < _parameters.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_parameters[i].label),
                  subtitle: Text('${_parameters[i].name} · ${_parameters[i].kind.name}'),
                  onTap: () => _editParameter(i),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _parameters.removeAt(i)),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: Text(l.commonSave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> showMacroControlRunner(
    BuildContext context, MacroControl control) async {
  if (control.parameters.isEmpty && !control.confirm) {
    return control.command(const {});
  }
  final values = {
    for (final parameter in control.parameters)
      parameter.name: parameter.defaultValue,
  };
  final controllers = {
    for (final parameter in control.parameters)
      if (parameter.kind != MacroControlParameterKind.toggle)
        parameter.name: TextEditingController(text: parameter.defaultValue),
  };
  final command = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final preview = control.command(values);
        return AlertDialog(
          title: Text(control.label),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final parameter in control.parameters)
                  if (parameter.kind == MacroControlParameterKind.toggle)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(parameter.label),
                      value: values[parameter.name] == '1',
                      onChanged: (value) => setState(
                          () => values[parameter.name] = value ? '1' : '0'),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: controllers[parameter.name],
                        keyboardType:
                            parameter.kind == MacroControlParameterKind.number
                                ? const TextInputType.numberWithOptions(
                                    decimal: true, signed: true)
                                : TextInputType.text,
                        decoration: InputDecoration(labelText: parameter.label),
                        onChanged: (value) =>
                            setState(() => values[parameter.name] = value),
                      ),
                    ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(AppLocalizations.of(context).macroControlPreview,
                      style: Theme.of(context).textTheme.labelLarge),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(preview,
                      style: const TextStyle(fontFamily: 'monospace')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).commonCancel),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, preview),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(AppLocalizations.of(context).macroRunAction),
            ),
          ],
        );
      },
    ),
  );
  for (final controller in controllers.values) {
    controller.dispose();
  }
  return command;
}
