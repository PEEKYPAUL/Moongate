enum ConfigValueType {
  boolean,
  integer,
  floating,
  enumeration,
  pin,
  path,
  list,
  reference,
  string
}

enum ConfigDiagnosticSeverity { info, warning, error }

class ConfigOptionDefinition {
  final String name, description;
  final ConfigValueType type;
  final num? min, max;
  final List<String> enumValues;
  const ConfigOptionDefinition(
      {required this.name,
      this.description = '',
      this.type = ConfigValueType.string,
      this.min,
      this.max,
      this.enumValues = const []});
}

class ConfigSectionDefinition {
  final String name, description;
  final bool repeatable;
  final List<ConfigOptionDefinition> options;
  const ConfigSectionDefinition(
      {required this.name,
      this.description = '',
      this.repeatable = false,
      this.options = const []});
}

class GcodeParameterDefinition {
  final String name, description;
  final ConfigValueType type;
  final List<String> enumValues;
  const GcodeParameterDefinition(
      {required this.name,
      this.description = '',
      this.type = ConfigValueType.string,
      this.enumValues = const []});
}

class GcodeCommandDefinition {
  final String name, description;
  final List<GcodeParameterDefinition> parameters;
  const GcodeCommandDefinition(
      {required this.name, this.description = '', this.parameters = const []});
}

class ConfigDiagnostic {
  final String message;
  final ConfigDiagnosticSeverity severity;
  final int? line;
  const ConfigDiagnostic(this.message, this.severity, {this.line});
}

class KlipperSchema {
  final int formatVersion;
  final String upstreamCommit;
  final List<ConfigSectionDefinition> sections;
  final List<GcodeCommandDefinition> commands;
  const KlipperSchema(
      {required this.formatVersion,
      required this.upstreamCommit,
      this.sections = const [],
      this.commands = const []});
}
