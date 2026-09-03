import '../models/gcode_completion.dart';

class GcodeCompletionService {
  final Map<String, String> commands;
  final List<String> macros;
  final List<String> history;
  final Map<String, List<String>> parameters;
  const GcodeCompletionService(
      {this.commands = const {},
      this.macros = const [],
      this.history = const [],
      this.parameters = const {}});

  List<GcodeCompletion> complete(String input, {int? cursor}) {
    final pos = cursor ?? input.length;
    final left = input.substring(0, pos);
    final leftMatch = RegExp(r'[^\s]*$').firstMatch(left);
    final rightMatch = RegExp(r'^[^\s]*').firstMatch(input.substring(pos));
    final start = leftMatch?.start ?? pos;
    final end = pos + (rightMatch?.group(0)?.length ?? 0);
    final prefix = input.substring(start, pos);
    final tokens = left.trimLeft().split(RegExp(r'\s+'));
    final names = <String, GcodeCompletion>{};
    void add(String value, GcodeCompletionKind kind,
        {String? description, int rank = 0}) {
      if (!value.toLowerCase().startsWith(prefix.toLowerCase())) return;
      final key = value.toUpperCase();
      if ((names[key]?.rank ?? -1) > rank) return;
      names[key] = GcodeCompletion(
          kind: kind,
          displayText: value,
          insertionText: value,
          description: description,
          start: start,
          end: end,
          rank: rank);
    }

    if (tokens.length <= 1) {
      commands.forEach((k, v) =>
          add(k, GcodeCompletionKind.command, description: v, rank: 4));
      for (final m in macros) {
        add(m, GcodeCompletionKind.macro, rank: 3);
      }
      for (final h in history) {
        add(h, GcodeCompletionKind.history, rank: 1);
      }
    } else {
      final command = tokens.first.toUpperCase();
      final present =
          tokens.skip(1).map((t) => t.split('=').first.toUpperCase()).toSet();
      final values = parameters[command] ?? const <String>[];
      for (final value in values) {
        if (value.contains('=')) {
          final name = value.split('=').first.toUpperCase();
          if (!present.contains(name)) {
            add('$name=', GcodeCompletionKind.parameter, rank: 4);
          }
        } else {
          add(value, GcodeCompletionKind.value, rank: 2);
        }
      }
    }
    return names.values.toList()..sort((a, b) => b.rank.compareTo(a.rank));
  }
}
