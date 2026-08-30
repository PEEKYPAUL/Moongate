enum GcodeCompletionKind { command, macro, parameter, value, history }

class GcodeCompletion {
  final GcodeCompletionKind kind;
  final String displayText, insertionText;
  final String? description;
  final int start, end, rank;
  const GcodeCompletion(
      {required this.kind,
      required this.displayText,
      required this.insertionText,
      this.description,
      required this.start,
      required this.end,
      this.rank = 0});
}
