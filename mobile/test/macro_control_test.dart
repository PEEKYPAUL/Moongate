import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/models/printer_config.dart';
import 'package:moongate/services/print_control_service.dart';

void main() {
  const control = MacroControl(
    id: 'load-filament',
    macro: 'LOAD_FILAMENT',
    label: 'Load filament',
    icon: 'filament',
    color: 'purple',
    parameters: [
      MacroControlParameter(
        name: 'TEMP',
        label: 'Temperature',
        kind: MacroControlParameterKind.number,
        defaultValue: '220',
      ),
      MacroControlParameter(
        name: 'FAST',
        label: 'Fast',
        kind: MacroControlParameterKind.toggle,
        defaultValue: '0',
      ),
    ],
  );

  test('builds a macro command from defaults and supplied values', () {
    // FAST defaults to off, and an OFF toggle is omitted rather than sent as
    // FAST=0: Jinja sees params as strings and '0' is truthy, so an explicit
    // 0 would run the `{% if params.FAST|default(false) %}` branch anyway.
    expect(control.command(const {}), 'LOAD_FILAMENT TEMP=220');
    expect(control.command(const {'TEMP': '235', 'FAST': '1'}),
        'LOAD_FILAMENT TEMP=235 FAST=1');
    expect(control.command(const {'TEMP': '235', 'FAST': '0'}),
        'LOAD_FILAMENT TEMP=235');
  });

  test('omits blank optional values and rejects multiline injection', () {
    expect(control.command(const {'TEMP': '', 'FAST': ''}), 'LOAD_FILAMENT');
    expect(() => control.command(const {'TEMP': '220\nM112'}),
        throwsFormatException);
    expect(() => control.command(const {'TEMP': '220\rM112'}),
        throwsFormatException);
  });

  test('newline-bearing stored defaults are sanitized, not fatal', () {
    // Backups are hand-editable JSON; a smuggled newline in a default must
    // not make command() throw on every future run of the restored control.
    final restored = MacroControlParameter.fromJson(const {
      'name': 'TEMP',
      'label': 'Temperature',
      'kind': 'number',
      'defaultValue': '220\nM112',
    });
    expect(restored.defaultValue, '220 M112');
  });

  test('multiline macro defaults collapse to one line at inference', () {
    final parameters = inferMacroParameters(
        'M117 {params.MSG|default("line one\nline two")}');
    expect(parameters.single.defaultValue, 'line one line two');
  });

  test('macro name validity gate matches the load-time filter', () {
    expect(MacroControl.isValidMacroName('LOAD_FILAMENT'), isTrue);
    expect(MacroControl.isValidMacroName('_PRIVATE'), isTrue);
    expect(MacroControl.isValidMacroName('PRINT-START'), isFalse);
    expect(MacroControl.isValidMacroName('T0.1'), isFalse);
    expect(MacroControl.isValidMacroName(''), isFalse);
  });

  test('infers editable parameters and defaults from macro gcode', () {
    final parameters = inferMacroParameters('''
      M109 S{params.TEMP|default(220)|int}
      G1 E{params.LENGTH|default("50")|float}
      {% if params.FAST|default(false) %} G1 F3000 {% endif %}
      M117 {params.MESSAGE}
      M118 {params.TEMP}
    ''');
    expect(parameters.map((parameter) => parameter.name),
        ['TEMP', 'LENGTH', 'FAST', 'MESSAGE']);
    expect(parameters.map((parameter) => parameter.kind), [
      MacroControlParameterKind.number,
      MacroControlParameterKind.number,
      MacroControlParameterKind.toggle,
      MacroControlParameterKind.text,
    ]);
    expect(parameters.map((parameter) => parameter.defaultValue),
        ['220', '50', '0', '']);
  });

  test('reads homing, position and force-move capability for motion panel', () {
    final state = parseMotionPanelState({
      'result': {
        'status': {
          'toolhead': {
            'homed_axes': 'xy',
            'position': [12, 34.5, 6],
          },
          'configfile': {
            'settings': {
              'force_move': {'enable_force_move': true},
            },
          },
        },
      },
    });
    expect(state.homedAxes, 'xy');
    expect(state.position, [12.0, 34.5, 6.0]);
    expect(state.forceMoveEnabled, isTrue);
  });

  test('printer config round-trips macro controls through backups', () {
    const printer = PrinterConfig(
        id: 'printer-1', name: 'Voron', macroControls: [control]);
    final restored = PrinterConfig.fromJson(printer.toJson());
    expect(restored.macroControls, hasLength(1));
    expect(restored.macroControls.single.label, 'Load filament');
    expect(restored.macroControls.single.parameters.first.name, 'TEMP');
    expect(restored.copyWith(name: 'V2').macroControls, hasLength(1));
  });

  test('older printer JSON defaults to no macro controls', () {
    const printer = PrinterConfig(id: 'printer-1', name: 'Voron');
    expect(PrinterConfig.fromJson(printer.toJson()).macroControls, isEmpty);
  });

  test('malformed controls from a backup are ignored', () {
    final json = const PrinterConfig(id: 'printer-1', name: 'Voron').toJson();
    json['macroControls'] = [
      {
        'id': 'bad',
        'macro': 'LOAD_FILAMENT\nM112',
        'label': 'Bad',
      }
    ];
    expect(PrinterConfig.fromJson(json).macroControls, isEmpty);
  });

  test('control panel starts with presets and persists customization', () {
    const printer = PrinterConfig(id: 'printer-1', name: 'Voron');
    expect(printer.controlPanelModules.map((module) => module.type), [
      ControlPanelModuleType.temperatures,
      ControlPanelModuleType.motion,
      ControlPanelModuleType.macros,
    ]);
    expect(printer.controlPanelModules.every(
        (module) => module.color == 0xFFFFFFFF), isTrue);
    const custom = ControlPanelModule(
      id: 'motion',
      type: ControlPanelModuleType.motion,
      title: 'Jog',
      color: 0xFF123456,
    );
    final restored = PrinterConfig.fromJson(
        printer.copyWith(controlPanelModules: const [custom]).toJson());
    expect(restored.controlPanelModules.single.title, 'Jog');
    expect(restored.controlPanelModules.single.color, 0xFF123456);
  });

  test('an intentionally empty control panel stays empty', () {
    const printer = PrinterConfig(
        id: 'printer-1', name: 'Voron', controlPanelModules: []);
    expect(PrinterConfig.fromJson(printer.toJson()).controlPanelModules, isEmpty);
  });
}
