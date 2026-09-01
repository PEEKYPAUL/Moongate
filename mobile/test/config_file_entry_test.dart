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

    test('a timestamped updater copy is a backup (crowsnest style)', () {
      expect(_entry('crowsnest.conf.2024-12-22-1121').isBackup, isTrue);
      expect(_entry('printer.cfg.2026-01-03').isBackup, isTrue);
      expect(_entry('sub/crowsnest.conf.2024-12-22-1121').isBackup, isTrue);
    });

    test('the timestamp tail is exact - lookalikes are NOT backups', () {
      expect(_entry('crowsnest.conf').isBackup, isFalse);
      expect(_entry('crowsnest.conf.d').isBackup, isFalse);
      expect(_entry('probe.cfg.202-12-22-1121').isBackup, isFalse);
      expect(_entry('notes.txt.2024-12-22-1121').isBackup, isFalse);
    });
  });

  group('ConfigFileEntry.isEditable', () {
    test('a timestamped backup opens as the config text it is', () {
      expect(_entry('crowsnest.conf.2024-12-22-1121').isEditable, isTrue);
      expect(_entry('printer.cfg.2026-01-03').isEditable, isTrue);
    });

    test('unknown extensions stay read-only', () {
      expect(_entry('photo.png').isEditable, isFalse);
      expect(_entry('crowsnest.conf.d').isEditable, isFalse);
    });

    test('plain config files are editable', () {
      expect(_entry('printer.cfg').isEditable, isTrue);
      expect(_entry('crowsnest.conf').isEditable, isTrue);
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
