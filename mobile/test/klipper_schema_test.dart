import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/models/klipper_schema.dart';
import 'package:moongate/services/klipper_schema_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bundled catalog has provenance and unique keys', () async {
    final schema = await KlipperSchemaService.instance.load();
    expect(schema.formatVersion, 1);
    expect(schema.upstreamCommit, isNotEmpty);
    expect(schema.sections.map((s) => s.name).toSet().length,
        schema.sections.length);
    expect(schema.commands.map((c) => c.name).toSet().length,
        schema.commands.length);
    expect(
        schema.sections
            .firstWhere((s) => s.name == 'printer')
            .options
            .first
            .type,
        ConfigValueType.enumeration);
    expect(schema.sections.any((s) => s.name == 'gcode_macro <name>'), isTrue);
    expect(schema.sections.any((s) => s.name == 'heater_generic <name>'),
        isTrue);
    expect(schema.sections.any((s) => s.name == 'temperature_sensor <name>'),
        isTrue);
    expect(schema.sections.any((s) => s.name == 'stepper_<name>'), isTrue);
    expect(schema.sections.any((s) => s.name == 'tmc2209 <name>'), isTrue);
    expect(schema.sections.any((s) => s.name == 'include'), isFalse);
    expect(
        schema.sections
            .expand((section) => section.options)
            .any((option) => option.name == 'WARNING' || option.name.contains('<')),
        isFalse);
    final bedMesh =
        schema.sections.firstWhere((section) => section.name == 'bed_mesh');
    expect(
        bedMesh.options
            .firstWhere((option) => option.name == 'probe_count')
            .type,
        ConfigValueType.list);
  });

  test('parameterized sections match by base name', () {
    const schema = KlipperSchema(
        formatVersion: 1,
        upstreamCommit: 'test',
        sections: [ConfigSectionDefinition(name: 'mcu <name>')]);
    expect(KlipperSchemaService.instance.matchSection(schema, 'mcu host')?.name,
        'mcu <name>');
    expect(
        KlipperSchemaService.instance
            .matchSection(
                const KlipperSchema(
                    formatVersion: 1,
                    upstreamCommit: 'test',
                    sections: [
                      ConfigSectionDefinition(name: 'stepper_<name>')
                    ]),
                'stepper_x')
            ?.name,
        'stepper_<name>');
  });
}
