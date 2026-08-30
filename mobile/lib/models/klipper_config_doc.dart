/// Line-preserving model of a Klipper-style config file (`printer.cfg`,
/// `moonraker.conf` - the same configparser dialect). The structured editor's
/// whole promise rests here: the file is NEVER re-serialised from a parse
/// tree. Every line is kept verbatim, and an edit only replaces the value's
/// own characters on its own line - so comments, blank lines, ordering,
/// indentation and even trailing `\r`s survive a save byte-for-byte.
///
/// What gets modelled (everything else stays raw, untouched):
/// - `[section]` headers, including `[gcode_macro NAME]` and `[include …]`.
/// - `key: value` / `key = value` options inside a section. A single-line
///   value exposes an editable span; a multi-line value (indented
///   continuation lines - gcode blocks, bed-mesh point lists) is view-only.
/// - Inline `#`/`;` comments on an option line, surfaced as helper text and
///   never part of the editable span.
/// - Klipper's `#*#` SAVE_CONFIG autosave block, flagged so the editor can
///   show it as locked (Klipper owns it - "DO NOT EDIT" by contract).
library;

import 'klipper_schema.dart';

/// One `[section]` of the file with the options found in its body.
class ConfigSection {
  /// The name between the brackets, e.g. `extruder`, `gcode_macro START`.
  final String name;

  /// Index into [KlipperConfigDoc.lines] of the `[…]` header line.
  final int lineIndex;

  final List<ConfigOption> options;
  final int bodyEnd;

  const ConfigSection({
    required this.name,
    required this.lineIndex,
    required this.options,
    this.bodyEnd = 0,
  });

  /// `[include …]` pseudo-sections pull other files in and have no body of
  /// their own - rendered as plain rows, not editable cards.
  bool get isInclude => name.startsWith('include ');
}

/// One `key: value` option line. [valueStart]/[valueEnd] bound the editable
/// characters within the raw line - between the separator and any inline
/// comment, trailing whitespace excluded - so replacement is a pure splice.
class ConfigOption {
  final String key;

  /// Index into [KlipperConfigDoc.lines] of the `key: value` line.
  final int lineIndex;

  /// Character offsets of the value within its raw line ([valueEnd]
  /// exclusive). Equal offsets mean an empty value.
  final int valueStart;
  final int valueEnd;

  /// The value text at parse time (single-line options only; for multi-line
  /// options this is just the key line's fragment, usually empty).
  final String value;

  /// True when indented continuation lines carry (more of) the value -
  /// gcode blocks, coordinate lists. View-only in the structured editor:
  /// splicing multi-line spans is where silent corruption lives.
  final bool isMultiline;

  /// Trailing `#`/`;` comment on the option's own line, prefix stripped -
  /// the natural helper text ("tuned for ABS").
  final String? inlineComment;

  const ConfigOption({
    required this.key,
    required this.lineIndex,
    required this.valueStart,
    required this.valueEnd,
    required this.value,
    required this.isMultiline,
    this.inlineComment,
  });
}

class KlipperConfigDoc {
  /// The file's lines exactly as split on `\n` (a `\r` from a CRLF file stays
  /// on its line, counted as trailing whitespace by the span logic), so
  /// `lines.join('\n')` reproduces the input byte-for-byte.
  final List<String> lines;

  final List<ConfigSection> sections;

  /// True when any `#*#` line exists - Klipper's SAVE_CONFIG autosave block.
  final bool hasAutosaveBlock;
  final List<ConfigDiagnostic> diagnostics;

  const KlipperConfigDoc({
    required this.lines,
    required this.sections,
    required this.hasAutosaveBlock,
    this.diagnostics = const [],
  });

  String get text => lines.join('\n');

  static final _sectionRe = RegExp(r'^\[([^\]]*)\]');
  static final _optionRe = RegExp(r'^([^\s:=#;\[][^:=#;]*?)\s*[:=](.*)$');

  static KlipperConfigDoc parse(String text) {
    final lines = text.split('\n');
    final sections = <ConfigSection>[];
    var autosave = false;
    final diagnostics = <ConfigDiagnostic>[];

    List<ConfigOption>? current; // options of the section being built

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      if (raw.startsWith('#*#')) {
        autosave = true;
        continue;
      }
      final trimmed = raw.trimRight();
      if (trimmed.isEmpty) continue;
      final first = trimmed.codeUnitAt(0);
      if (first == 0x23 || first == 0x3B) continue; // # or ; comment line
      // Indented line: continuation of the previous option's value (flagged
      // there via lookahead) or an orphan - either way not a new option.
      if (first == 0x20 || first == 0x09) continue;

      final sec = _sectionRe.firstMatch(trimmed);
      if (sec != null) {
        current = <ConfigOption>[];
        sections.add(ConfigSection(
          name: sec.group(1)!.trim(),
          lineIndex: i,
          options: current,
        ));
        continue;
      }

      // Dart's regex `.` refuses `\r` (a line terminator to it), so a CRLF
      // file's option lines would never match against [raw]. Match and span
      // against the line without its trailing `\r` - every offset stays
      // valid for [raw], since the `\r` sits beyond the value's end anyway.
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      final opt = _optionRe.firstMatch(line);
      if (opt == null || current == null) continue;

      // The value span starts after the separator, skipping its whitespace.
      // group(2) is everything after the separator, so its offset is just
      // the line length minus its own - no re-searching the line.
      var start = line.length - opt.group(2)!.length;
      while (start < line.length &&
          (line.codeUnitAt(start) == 0x20 || line.codeUnitAt(start) == 0x09)) {
        start++;
      }

      // End before any inline comment: a #/; at the value start, or one
      // preceded by whitespace (a # glued inside a value stays a value).
      var end = line.length;
      String? comment;
      for (var p = start; p < line.length; p++) {
        final c = line.codeUnitAt(p);
        if (c != 0x23 && c != 0x3B) continue;
        final atStart = p == start;
        final prev = p > start ? line.codeUnitAt(p - 1) : 0;
        if (atStart || prev == 0x20 || prev == 0x09) {
          end = p;
          comment = line.substring(p + 1).trim();
          if (comment.isEmpty) comment = null;
          break;
        }
      }
      // Trailing whitespace stays outside the span.
      while (end > start) {
        final c = line.codeUnitAt(end - 1);
        if (c == 0x20 || c == 0x09) {
          end--;
        } else {
          break;
        }
      }

      // Lookahead: an indented line following this one carries more of the
      // value. Blank lines are scanned PAST, not stopped at - configparser
      // (and so Klipper) joins values across empty lines, and a macro with
      // a blank line inside its gcode block must stay view-only, not become
      // a spliceable "single-line" option.
      var multiline = false;
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j];
        if (next.trim().isEmpty) continue;
        final nc = next.codeUnitAt(0);
        multiline = nc == 0x20 || nc == 0x09;
        break;
      }

      current.add(ConfigOption(
        key: opt.group(1)!.trim(),
        lineIndex: i,
        valueStart: start,
        valueEnd: end,
        value: raw.substring(start, end),
        isMultiline: multiline,
        inlineComment: comment,
      ));
    }

    for (final section in sections) {
      final seen = <String>{};
      for (final option in section.options) {
        if (!seen.add(option.key)) {
          diagnostics.add(ConfigDiagnostic('Duplicate option: ${option.key}',
              ConfigDiagnosticSeverity.warning,
              line: option.lineIndex));
        }
      }
    }
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      final next =
          i + 1 < sections.length ? sections[i + 1].lineIndex : lines.length;
      sections[i] = ConfigSection(
          name: s.name,
          lineIndex: s.lineIndex,
          options: s.options,
          bodyEnd: next);
    }
    return KlipperConfigDoc(
      lines: lines,
      sections: sections,
      hasAutosaveBlock: autosave,
      diagnostics: diagnostics,
    );
  }

  /// The full file text with each option in [edits] set to its new value -
  /// a pure per-line splice, everything else verbatim. Multi-line options
  /// and values containing a newline are rejected by [canEdit]/the caller;
  /// this method just splices.
  String textWithEdits(Map<ConfigOption, String> edits) {
    final out = List<String>.from(lines);
    edits.forEach((opt, value) {
      final raw = out[opt.lineIndex];
      out[opt.lineIndex] = raw.substring(0, opt.valueStart) +
          value +
          raw.substring(opt.valueEnd);
    });
    return out.join('\n');
  }

  /// Whether the structured editor offers [option] for editing: single-line
  /// values only, and only when its span still matches what was parsed
  /// (a defence against splicing into a line the model no longer describes).
  bool canEdit(ConfigOption option) {
    if (option.isMultiline) return false;
    if (option.lineIndex >= lines.length) return false;
    final raw = lines[option.lineIndex];
    if (option.valueEnd > raw.length) return false;
    return raw.substring(option.valueStart, option.valueEnd) == option.value;
  }

  String replaceOption(ConfigOption option, String value) {
    if (!canEdit(option) || value.contains('\n') || value.contains('\r')) {
      throw ArgumentError('Invalid single-line option edit');
    }
    return textWithEdits({option: value});
  }

  String insertOption(ConfigSection section, String key, String value) {
    if (value.contains('\n') ||
        value.contains('\r') ||
        section.options.any((o) => o.key == key)) {
      throw ArgumentError('Invalid or duplicate option');
    }
    final separator = section.options.isNotEmpty &&
            lines[section.options.first.lineIndex].contains('=')
        ? '='
        : ':';
    final out = List<String>.from(lines);
    out.insert(_insertionIndex(section.bodyEnd),
        '$key$separator $value$_lineEnding');
    return out.join('\n');
  }

  String insertSection(String name) {
    if (name.contains('\n') || name.contains(']')) {
      throw ArgumentError('Invalid section');
    }
    final out = List<String>.from(lines);
    final at = hasAutosaveBlock
        ? lines.indexWhere((l) => l.startsWith('#*#'))
        : lines.length;
    out.insert(_insertionIndex(at < 0 ? lines.length : at),
        '[${name.trim()}]$_lineEnding');
    return out.join('\n');
  }

  String get _lineEnding => lines.any((line) => line.endsWith('\r')) ? '\r' : '';

  /// Keep a terminal empty split line at the end of the file. Inserting at
  /// [lines.length] after `text.split('\n')` would move the new line past the
  /// sentinel and add a blank line before it.
  int _insertionIndex(int index) {
    final at = index.clamp(0, lines.length);
    return at == lines.length && lines.isNotEmpty && lines.last.isEmpty
        ? lines.length - 1
        : at;
  }
}
