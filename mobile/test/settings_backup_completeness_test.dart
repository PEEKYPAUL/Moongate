import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/services/settings_backup.dart';

/// The rule (Paul, 2026-08-30): a setting the user customised must survive
/// backup → restore unless there is a written reason it can't. This suite
/// scans lib/ for every preference key the app touches and fails when one is
/// neither on the SettingsBackup allow-list nor in the exclusion map below -
/// so a new setting can never silently skip backups again (the way
/// `global_power_button` did: its doc promised "Travels in backups" while the
/// allow-list never carried it).
///
/// Adding a setting? Either add its key to SettingsBackup._keys (it rides
/// backups, the usual choice) or add it here WITH the reason it must not.

const Map<String, String> _excluded = {
  // The app-lock family is device-bound: exporting "lock on" without its
  // PIN would lock the user out on another device (see the SettingsBackup doc).
  'app_lock_enabled':           'app-lock family, device-bound',
  'app_lock_biometric':         'app-lock family, device-bound',
  'app_lock_timeout':           'app-lock family, device-bound',
  'moongate_pin_hash':          'PIN material, never leaves the device',
  'moongate_pin_salt':          'PIN material, never leaves the device',
  'moongate_pin_len':           'PIN material, never leaves the device',
  'moongate_pin_fail_count':    'PIN lockout state, transient',
  'moongate_pin_lockout_until': 'PIN lockout state, transient',
  // First-run onboarding and one-time hints: transient UI state.
  'language_selected':          'first-run flag',
  'notifications_prompted':     'first-run flag',
  'pairing_help_dismissed':     'first-run flag',
  'donation_prompted':          'first-run flag',
  'tutorial_offered':           'first-run flag',
  'camera_hint_seen':           'one-time hint',
  'notif_pause_hint_seen':      'one-time hint',
  // Moment-to-moment controls, not preferences.
  'local_only_mode':            'a restore must never silently cut remote access',
  'print_notifications_paused': 'a restore must never silently pause alerts',
  'heatsoak_deadlines':         'running timers on THIS device',
  // Carried elsewhere / meaningless off-device.
  'moongate_printers':          'the printer list rides the backup envelope itself',
  'dashboard_background_path':  'device-local file path; the image cannot ride a JSON backup',
};

/// The idioms preference keys are written in across lib/: `_fooKey = '…'`
/// constants, the camera-refresh notifiers' `String get key => '…'`, and
/// literal keys passed straight to SharedPreferences get/set calls.
final List<RegExp> _patterns = [
  RegExp(r"(?:_key|Key|prefsKey)\s*=\s*'([a-z0-9_]+)'"),
  RegExp(r"String get key => '([a-z0-9_]+)'"),
  RegExp(r"(?:getString|getBool|getInt|getDouble|"
      r"setString|setBool|setInt|setDouble)\('([a-z0-9_]+)'"),
];

Set<String> _discoverKeys() {
  final keys = <String>{};
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final f in files) {
    final src = f.readAsStringSync();
    for (final p in _patterns) {
      for (final m in p.allMatches(src)) {
        keys.add(m.group(1)!);
      }
    }
  }
  return keys;
}

void main() {
  test('every preference key is classified: backed up or documented out', () {
    final discovered = _discoverKeys();
    // The scan itself must be alive - representative keys from each idiom.
    expect(discovered, contains('theme_mode'));
    expect(discovered, contains('dashboard_camera_refresh_local'));
    expect(discovered, contains('notif_fields_order'));

    final unclassified = discovered
        .difference(SettingsBackup.backedUpKeys)
        .difference(_excluded.keys.toSet());
    expect(unclassified, isEmpty,
        reason: 'New preference key(s) $unclassified: add each to the '
            'SettingsBackup allow-list so it rides backups, or to this '
            "test's exclusion map with the reason it must not.");
  });

  test('no key is both backed up and excluded', () {
    final both =
        SettingsBackup.backedUpKeys.intersection(_excluded.keys.toSet());
    expect(both, isEmpty,
        reason: 'Key(s) $both are allow-listed AND excluded - pick one.');
  });

  test('the allow-list holds no stale keys the app no longer writes', () {
    final stale = SettingsBackup.backedUpKeys.difference(_discoverKeys());
    expect(stale, isEmpty,
        reason: 'Allow-listed key(s) $stale no longer appear anywhere in '
            'lib/ - was the setting renamed or removed?');
  });
}
