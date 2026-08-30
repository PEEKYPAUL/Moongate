import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/models/klipper_config_doc.dart';

const _sample = '''
# Voron 2.4 - main config
[include mainsail.cfg]

[extruder]
rotation_distance: 22.678
pressure_advance: 0.045  # tuned for ABS 2026-06
max_temp = 285
nozzle_diameter:0.4
gcode_id: T0\t
dir_pin: !PB4

[bed_mesh]
speed: 300
points:
  10, 10
  340, 340

[gcode_macro PRINT_START]
# runs before every print
gcode:
  G28 ; home first
  QUAD_GANTRY_LEVEL
  # heat things
  M109 S{params.EXTRUDER|default(215)}

[save_variables]
variable_last = {'x': 1.0}

#*# <---------------------- SAVE_CONFIG ---------------------->
#*# DO NOT EDIT THIS BLOCK OR BELOW. The contents are auto-generated.
#*# [probe]
#*# z_offset = -0.755
''';

void main() {
  group('parse - structure', () {
    final doc = KlipperConfigDoc.parse(_sample);

    test('finds every section, includes included', () {
      expect(doc.sections.map((s) => s.name).toList(), [
        'include mainsail.cfg',
        'extruder',
        'bed_mesh',
        'gcode_macro PRINT_START',
        'save_variables',
      ]);
      expect(doc.sections.first.isInclude, isTrue);
      expect(doc.sections[1].isInclude, isFalse);
    });

    test('the autosave block is flagged, not parsed as sections', () {
      expect(doc.hasAutosaveBlock, isTrue);
      // The #*# [probe] line must NOT have become a section.
      expect(doc.sections.any((s) => s.name == 'probe'), isFalse);
    });

    test('text reproduces the input byte-for-byte', () {
      expect(doc.text, _sample);
    });
  });

  group('parse - options', () {
    final doc = KlipperConfigDoc.parse(_sample);
    final extruder = doc.sections[1];

    ConfigOption opt(String key) =>
        extruder.options.firstWhere((o) => o.key == key);

    test('colon and equals separators both parse', () {
      expect(opt('rotation_distance').value, '22.678');
      expect(opt('max_temp').value, '285');
    });

    test('no space after the separator still parses', () {
      expect(opt('nozzle_diameter').value, '0.4');
    });

    test('inline comment is split off the value and surfaced', () {
      final pa = opt('pressure_advance');
      expect(pa.value, '0.045');
      expect(pa.inlineComment, 'tuned for ABS 2026-06');
    });

    test('trailing whitespace stays outside the value span', () {
      expect(opt('gcode_id').value, 'T0');
    });

    test('a ! pin inversion is value, not noise', () {
      expect(opt('dir_pin').value, '!PB4');
    });

    test('single-line options are editable, comment lines are not options', () {
      expect(doc.canEdit(opt('rotation_distance')), isTrue);
      // '# runs before every print' inside the macro section is no option.
      final macro = doc.sections[3];
      expect(macro.options.map((o) => o.key).toList(), ['gcode']);
    });

    test('a dict value keeps its inner colon', () {
      final vars = doc.sections[4].options.single;
      expect(vars.key, 'variable_last');
      expect(vars.value, "{'x': 1.0}");
    });
  });

  group('parse - multi-line values', () {
    final doc = KlipperConfigDoc.parse(_sample);

    test('an indented block marks its option multi-line and view-only', () {
      final points = doc.sections[2].options.firstWhere((o) => o.key == 'points');
      expect(points.isMultiline, isTrue);
      expect(doc.canEdit(points), isFalse);
      final gcode = doc.sections[3].options.single;
      expect(gcode.isMultiline, isTrue);
    });

    test('continuation lines never parse as options of their own', () {
      final bedMesh = doc.sections[2];
      expect(bedMesh.options.map((o) => o.key).toList(), ['speed', 'points']);
    });

    test('a single-line value stays editable next to multi-line siblings', () {
      final speed = doc.sections[2].options.first;
      expect(speed.value, '300');
      expect(doc.canEdit(speed), isTrue);
    });
  });

  group('textWithEdits - the splice', () {
    test('replaces only the value, preserving everything around it', () {
      final doc = KlipperConfigDoc.parse(_sample);
      final pa = doc.sections[1].options.firstWhere(
          (o) => o.key == 'pressure_advance');
      final edited = doc.textWithEdits({pa: '0.052'});
      expect(edited,
          contains('pressure_advance: 0.052  # tuned for ABS 2026-06'));
      // One value changed, nothing else: the texts differ by exactly the
      // one line.
      final before = _sample.split('\n');
      final after  = edited.split('\n');
      expect(after.length, before.length);
      final changed = [
        for (var i = 0; i < before.length; i++)
          if (before[i] != after[i]) i,
      ];
      expect(changed, hasLength(1));
    });

    test('multiple edits land independently', () {
      final doc = KlipperConfigDoc.parse(_sample);
      final ex = doc.sections[1];
      final edited = doc.textWithEdits({
        ex.options.firstWhere((o) => o.key == 'rotation_distance'): '22.9',
        ex.options.firstWhere((o) => o.key == 'max_temp'): '290',
      });
      expect(edited, contains('rotation_distance: 22.9'));
      expect(edited, contains('max_temp = 290'));
    });

    test('an empty value edits into place and back', () {
      final doc = KlipperConfigDoc.parse('[a]\nkey: old\n');
      final key = doc.sections.single.options.single;
      expect(KlipperConfigDoc.parse(doc.textWithEdits({key: ''})).text,
          '[a]\nkey: \n');
    });
  });

  group('CRLF files', () {
    test('\\r rides along invisibly and survives an edit', () {
      const crlf = '[extruder]\r\nmax_temp: 285\r\n';
      final doc = KlipperConfigDoc.parse(crlf);
      final opt = doc.sections.single.options.single;
      // The \r is trailing whitespace, outside the span.
      expect(opt.value, '285');
      expect(doc.textWithEdits({opt: '290'}), '[extruder]\r\nmax_temp: 290\r\n');
    });
  });

  group('empty-value key lines', () {
    test('gcode: with nothing after the colon is multi-line, value empty', () {
      const text = '[gcode_macro M600]\ngcode:\n  PAUSE\n';
      final doc = KlipperConfigDoc.parse(text);
      final gcode = doc.sections.single.options.single;
      expect(gcode.value, '');
      expect(gcode.isMultiline, isTrue);
      expect(doc.text, text);
    });
  });

  group('structural insertions', () {
    test('preserve a terminal newline without adding a blank line', () {
      final doc = KlipperConfigDoc.parse('[a]\nkey: value\n');
      expect(doc.insertOption(doc.sections.single, 'other', 'x'),
          '[a]\nkey: value\nother: x\n');
      expect(doc.insertSection('b'), '[a]\nkey: value\n[b]\n');
    });

    test('preserve CRLF and autosave boundary', () {
      const text = '[a]\r\nkey: value\r\n#*# SAVE\r\n';
      final doc = KlipperConfigDoc.parse(text);
      expect(doc.insertSection('b'), '[a]\r\nkey: value\r\n[b]\r\n#*# SAVE\r\n');
    });
  });
}
