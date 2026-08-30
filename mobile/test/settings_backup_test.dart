import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moongate/models/notif_fields.dart';
import 'package:moongate/services/settings_backup.dart';

/// Proves the customizable print-notification content (which fields show + the
/// order) is carried by the backup/restore feature - exported by
/// [SettingsBackup.snapshot] into the file's `settings` map and put back by
/// [SettingsBackup.apply] on a fresh device. Also guards against a future
/// change silently dropping these keys from the backup allow-list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('notification-content settings survive a backup export → import',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // 1. User customises the notification: ETA first, bed hidden.
    final original = NotifFieldsConfig.fromPrefs(
        'eta,progress,remaining,hotend,bed', 'eta,progress,remaining,hotend');
    await prefs.setString('notif_fields_order', original.orderPref);
    await prefs.setString('notif_fields_enabled', original.enabledPref);
    await prefs.setString('theme_mode', 'dark'); // an unrelated setting too

    // 2. Export: the snapshot that goes into the backup file must carry both.
    final backup = await SettingsBackup.snapshot();
    expect(backup['notif_fields_order'], original.orderPref,
        reason: 'field order must be written into the backup');
    expect(backup['notif_fields_enabled'], original.enabledPref,
        reason: 'enabled-field set must be written into the backup');

    // 3. Simulate restoring onto a fresh install - nothing set yet.
    await prefs.clear();
    expect(prefs.getString('notif_fields_order'), isNull);

    // 4. Import: apply() writes the allow-listed keys back.
    await SettingsBackup.apply(backup);

    // 5. The rebuilt config matches what the user had, exactly.
    final restored = NotifFieldsConfig.fromPrefs(
      prefs.getString('notif_fields_order'),
      prefs.getString('notif_fields_enabled'),
    );
    expect(restored.orderPref, original.orderPref);
    expect(restored.enabledPref, original.enabledPref);
    expect(restored.order.first, NotifField.eta, reason: 'ETA stayed first');
    expect(restored.enabled.contains(NotifField.bed), isFalse,
        reason: 'bed stayed hidden');
  });

  test('the file-browser clutter-filter choice rides the backup', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // The user opted to see everything (the non-default choice).
    await prefs.setBool('fs_hide_backups_hidden', false);
    final backup = await SettingsBackup.snapshot();
    expect(backup['fs_hide_backups_hidden'], isFalse,
        reason: 'the choice must be written into the backup');

    // Fresh install, then restore: the unticked checkbox comes back.
    await prefs.clear();
    await SettingsBackup.apply(backup);
    expect(prefs.getBool('fs_hide_backups_hidden'), isFalse);
  });

  test('a never-customised user omits the keys (defaults apply on restore)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // independent of any prior test's cached instance
    await prefs.setString('theme_mode', 'light'); // an unrelated setting only
    final backup = await SettingsBackup.snapshot();
    // Unset keys are deliberately absent, so restore leaves the all-on default.
    expect(backup.containsKey('notif_fields_order'), isFalse);
    expect(backup.containsKey('notif_fields_enabled'), isFalse);
    final fallback = NotifFieldsConfig.fromPrefs(
        backup['notif_fields_order'] as String?,
        backup['notif_fields_enabled'] as String?);
    expect(fallback.enabled.length, NotifField.values.length,
        reason: 'no saved config => every field shown');
  });
}
