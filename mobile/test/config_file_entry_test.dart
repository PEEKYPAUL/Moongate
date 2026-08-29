import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/services/print_control_service.dart';

ConfigFileEntry _entry(String path) =>
    ConfigFileEntry(path: path, modified: 0, size: 0);

void main() {
  group('ConfigFileEntry.isBackup - the clutter filter', () {
    test('a SAVE_CONFIG snapshot is a backup', () {
      expect(_entry('printer-20260829_101530.cfg').isBackup, isTrue);
    });

    test('a real printer-*.cfg with a non-date suffix is NOT a backup', () {
      expect(_entry('printer-macros.cfg').isBackup, isFalse);
      expect(_entry('printer-2026.cfg').isBackup, isFalse);
    });

    test('the date pattern is exact, not a loose prefix', () {
      // Wrong digit counts must not match.
      expect(_entry('printer-2026829_1015.cfg').isBackup, isFalse);
      // The snapshot name is exact - no leading extras.
      expect(_entry('my-printer-20260829_101530.cfg').isBackup, isFalse);
    });

    test('generic backup suffixes match, case-insensitively', () {
      expect(_entry('shaper.bak').isBackup, isTrue);
      expect(_entry('macros.BKP').isBackup, isTrue);
      expect(_entry('printer.cfg~').isBackup, isTrue);
      expect(_entry('printer.cfg').isBackup, isFalse);
    });

    test('a snapshot inside a folder still counts', () {
      expect(_entry('old/printer-20250101_000000.cfg').isBackup, isTrue);
    });
  });

  group('ConfigFileEntry.isHidden', () {
    test('dotfiles are hidden', () {
      expect(_entry('.mainsail.json').isHidden, isTrue);
    });

    test('anything under a dot-folder is hidden', () {
      expect(_entry('.theme/style.css').isHidden, isTrue);
      expect(_entry('KAMP/.cache/x').isHidden, isTrue);
    });

    test('normal files and folders are not hidden', () {
      expect(_entry('printer.cfg').isHidden, isFalse);
      expect(_entry('KAMP/Adaptive_Meshing.cfg').isHidden, isFalse);
    });
  });
}
