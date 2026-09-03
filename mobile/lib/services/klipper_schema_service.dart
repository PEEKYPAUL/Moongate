import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/klipper_schema.dart';

class KlipperSchemaService {
  static final instance = KlipperSchemaService._();
  KlipperSchemaService._();

  KlipperSchema? _schema;
  Future<KlipperSchema> load() async => _schema ??= _decode(
      await rootBundle.loadString('assets/klipper/config_schema.json'),
      await rootBundle.loadString('assets/klipper/gcode_schema.json'));
  ConfigSectionDefinition? matchSection(KlipperSchema schema, String name) {
    for (final s in schema.sections) {
      if (s.name == name) return s;
    }
    for (final s in schema.sections) {
      if (!s.name.contains('<name>')) continue;
      final pattern =
          '^${s.name.split('<name>').map(RegExp.escape).join('.+')}\$';
      if (RegExp(pattern).hasMatch(name)) return s;
    }
    return null;
  }
  KlipperSchema _decode(String config, String gcode) {
    final c = jsonDecode(config) as Map<String, dynamic>,
        g = jsonDecode(gcode) as Map<String, dynamic>;
    ConfigValueType type(Object? v) => ConfigValueType.values
        .firstWhere((x) => x.name == v, orElse: () => ConfigValueType.string);
    final sections = ((c['sections'] as List?) ?? []).map((x) {
      final m = x as Map<String, dynamic>;
      return ConfigSectionDefinition(
          name: m['name'],
          description: m['description'] ?? '',
          repeatable: m['repeatable'] ?? false,
          options: ((m['options'] as List?) ?? []).map((o) {
            final q = o as Map<String, dynamic>;
            return ConfigOptionDefinition(
                name: q['name'],
                description: q['description'] ?? '',
                type: type(q['type']),
                min: q['min'],
                max: q['max'],
                enumValues: List<String>.from(q['enum'] ?? const []));
          }).toList());
    }).toList();
    final commands = ((g['commands'] as List?) ?? []).map((x) {
      final m = x as Map<String, dynamic>;
      return GcodeCommandDefinition(
          name: m['name'],
          description: m['description'] ?? '',
          parameters: ((m['parameters'] as List?) ?? []).map((p) {
            final parameter = p as Map<String, dynamic>;
            return GcodeParameterDefinition(
              name: parameter['name'],
              description: parameter['description'] ?? '',
              type: type(parameter['type']),
              enumValues: List<String>.from(parameter['enum'] ?? const []),
            );
          }).toList());
    }).toList();
    return KlipperSchema(
        formatVersion: c['formatVersion'],
        upstreamCommit: c['upstreamCommit'],
        sections: sections,
        commands: commands);
  }
}
