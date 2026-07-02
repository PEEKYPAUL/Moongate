import 'package:shared_preferences/shared_preferences.dart';

enum _Kind { string, boolean, integer, real }

/// Snapshots and restores the user's GLOBAL app preferences for the
/// backup/restore feature (see [PrinterConfig.toBackupJson] and
/// [PrinterRegistry.importFromBackupFile]).
///
/// Only the explicit allow-list below travels in a backup. Deliberately
/// excluded:
///   • the app lock (`app_lock_*`) and its PIN - the PIN lives in
///     Keystore-backed secure storage and is device-bound; exporting "lock on"
///     without a PIN would lock the user out on another device, and writing the
///     PIN hash into a file would defeat its at-rest encryption.
///   • first-run onboarding flags (`language_selected`, `notifications_prompted`,
///     `pairing_help_dismissed`, `donation_prompted`) - transient UI state, not
///     preferences (so the donation nudge can still appear once on a fresh
///     install even after restoring a backup).
/// The printer list is carried separately, by the backup envelope itself.
///
/// The allow-list also gates [apply], so a hand-edited backup can only ever set
/// these known keys - never an arbitrary or sensitive preference.
class SettingsBackup {
  SettingsBackup._();

  static const Map<String, _Kind> _keys = {
    'theme_mode':                  _Kind.string,
    'app_font':                    _Kind.string,
    'custom_theme':                _Kind.string,
    'font_scale':                  _Kind.real,
    'grid_columns':                _Kind.integer,
    'allow_rotation':              _Kind.boolean,
    'auto_arrange_by_status':      _Kind.boolean,
    'dashboard_camera_refresh':        _Kind.string,
    'dashboard_camera_refresh_local':  _Kind.string,
    'dashboard_camera_refresh_tunnel': _Kind.string,
    'print_notifications_enabled': _Kind.boolean,
    'notif_poll_interval':         _Kind.string,
    'notif_fields_order':          _Kind.string,
    'notif_fields_enabled':        _Kind.string,
    'notif_online_only':           _Kind.boolean,
    'app_locale':                  _Kind.string,
    'show_camera_config_icons':    _Kind.boolean,
    'show_dashboard_buttons':      _Kind.boolean,
  };

  /// Snapshot the currently-set preferences into a JSON-safe map. Unset keys
  /// are omitted, so restoring leaves their defaults untouched.
  static Future<Map<String, dynamic>> snapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    for (final entry in _keys.entries) {
      final Object? v = switch (entry.value) {
        _Kind.string  => prefs.getString(entry.key),
        _Kind.boolean => prefs.getBool(entry.key),
        _Kind.integer => prefs.getInt(entry.key),
        _Kind.real    => prefs.getDouble(entry.key),
      };
      if (v != null) out[entry.key] = v;
    }
    return out;
  }

  /// Write a backup's `settings` map back into SharedPreferences. Unknown keys
  /// and type mismatches are ignored. Does NOT reload the Riverpod providers -
  /// the caller does that so the change shows live (see the dashboard restore).
  static Future<void> apply(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in _keys.entries) {
      final v = settings[entry.key];
      if (v == null) continue;
      final Future<bool>? write = switch (entry.value) {
        _Kind.string  => v is String ? prefs.setString(entry.key, v) : null,
        _Kind.boolean => v is bool   ? prefs.setBool(entry.key, v)   : null,
        _Kind.integer => v is int    ? prefs.setInt(entry.key, v)    : null,
        _Kind.real    => v is num    ? prefs.setDouble(entry.key, v.toDouble()) : null,
      };
      if (write != null) await write;
    }
  }
}
