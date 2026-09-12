import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/heat_alerts.dart';

/// Per-printer heat-soak arms (see [HeatSoakArm]). The preheat sheet (on the
/// UI isolate) arms one when Set is pressed with the heat-soak alert on; the
/// opt-in print-notification background isolate judges it against every live
/// poll, persists the moment every temperature was reached (the soak clock),
/// fires the one-shot alert and clears it. Piggybacking that service is why the
/// alert only fires while print notifications are on - the preheat sheet warns
/// up front when they're off.
///
/// Stored as a JSON `{printerId: arm}` map under one key. Deliberately NOT part
/// of the settings backup - an arm is a live, here-and-now thing, not a
/// preference to carry across installs (settings_backup_completeness_test.dart
/// documents the exclusion). SharedPreferences caches per-isolate, so every
/// method reload()s first to see the other isolate's writes.
///
/// v0.9.67 replaced the earlier count-from-Set deadlines (`heatsoak_deadlines`)
/// with these arms; a leftover value under the old key is simply ignored.
class HeatsoakTimers {
  HeatsoakTimers._();

  static const String prefsKey = 'heatsoak_arms';

  /// Arm (or replace) the heat-soak alert for [printerId] - also how the
  /// isolate records the soak clock starting (the arm with `reachedAtMs` set).
  static Future<void> arm(String printerId, HeatSoakArm arm) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final map = _decode(prefs.getString(prefsKey));
    map[printerId] = arm;
    await prefs.setString(prefsKey, _encode(map));
  }

  /// Cancel any heat-soak alert for [printerId] - also how the isolate clears
  /// one after it fires or gives up. No-op when none is armed.
  static Future<void> cancel(String printerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final map = _decode(prefs.getString(prefsKey));
    if (map.remove(printerId) != null) {
      await prefs.setString(prefsKey, _encode(map));
    }
  }

  /// The current arms (printerId → arm). Reloads first so a caller in the
  /// background isolate sees arms set on the UI isolate.
  static Future<Map<String, HeatSoakArm>> snapshot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return _decode(prefs.getString(prefsKey));
  }

  static String _encode(Map<String, HeatSoakArm> arms) =>
      jsonEncode({for (final e in arms.entries) e.key: e.value.toJson()});

  static Map<String, HeatSoakArm> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in decoded.entries)
          if (HeatSoakArm.fromJson(e.value) case final arm?) e.key: arm,
      };
    } catch (_) {
      return {};
    }
  }
}
