/// Pure decision logic for the preheat sheet's "Notify when at temperature"
/// alert (v0.9.67) - the thermistor-reading sibling of the heat-soak countdown.
///
/// The sheet arms one [AtTempArm] per printer naming the heaters it just set,
/// by ROLE rather than Klipper object name ('h0' = the primary hotend, 'h1' =
/// `extruder1` and so on for a multi-toolhead machine, 'bed' = the bed), so the
/// Android notification isolate can match its live readings without knowing
/// whether a printer calls its hotend `extruder` or `heater_generic hotend`.
/// Each live poll then asks [evaluateAtTemp] whether to fire, keep waiting, or
/// quietly drop the arm. The heat-soak timer is a pure countdown from the
/// moment Set is pressed; this one never fires until the printer really reads
/// its targets, and the two are independent (arm either, or both).
///
/// Kept free of Flutter imports so the rules are unit-testable.
library;

/// Role key for the hotend of tool [index] ('h0', 'h1', ...). T0 is Klipper's
/// primary `extruder` whatever it is actually called; the rest are `extruderN`.
String hotendRole(int index) => 'h$index';

/// Role key for the heated bed.
const String bedRole = 'bed';

/// Tool number of a hotend role ('h2' → 2), or null for the bed / anything
/// unrecognised.
int? hotendIndexOf(String role) {
  if (role.length < 2 || !role.startsWith('h')) return null;
  return int.tryParse(role.substring(1));
}

/// One heater's live reading: current temperature and its CURRENT target, both
/// in °C, as the printer reports them now (not as the sheet set them).
class HeaterReading {
  final double temp;
  final double target;
  const HeaterReading(this.temp, this.target);
}

/// An armed at-temperature alert for one printer: when it was armed and which
/// heaters (by role) to wait for, with the targets the sheet sent - kept for
/// the alert text when a poll can't supply a live target.
class AtTempArm {
  final int armedAtMs;
  final Map<String, double> targets; // role → °C, only heaters being heated
  /// Whether the sheet was in its multi-toolhead layout (labels read "T0 210°"
  /// rather than "Hotend 210°" in the alert body).
  final bool multi;

  const AtTempArm({
    required this.armedAtMs,
    required this.targets,
    this.multi = false,
  });

  /// True when the arm waits on a tool beyond T0, whose reading the
  /// notification poll only fetches on demand (an idle printer's roster never
  /// shows extra hotends, so the isolate must supplement them for this).
  bool get needsExtraHotends =>
      targets.keys.any((r) => (hotendIndexOf(r) ?? 0) > 0);

  Map<String, dynamic> toJson() => {
        'at':      armedAtMs,
        'multi':   multi,
        'targets': targets,
      };

  /// Tolerant decode: anything malformed is null (dropped by the store).
  static AtTempArm? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'];
    final rawTargets = raw['targets'];
    if (at is! num || rawTargets is! Map) return null;
    final targets = <String, double>{};
    for (final e in rawTargets.entries) {
      final k = e.key;
      final v = e.value;
      if (k is String && v is num && v > 0) targets[k] = v.toDouble();
    }
    if (targets.isEmpty) return null;
    return AtTempArm(
      armedAtMs: at.toInt(),
      targets:   targets,
      multi:     raw['multi'] == true,
    );
  }
}

/// What a live poll means for an armed at-temperature alert.
enum AtTempVerdict {
  /// Not there yet (or the poll couldn't say) - check again next tick.
  wait,

  /// Every armed heater reads its target: alert, then clear the arm.
  fire,

  /// Give up silently: the arm went stale, or a heater was switched off since
  /// arming (the preheat was abandoned - nothing to wait for).
  cancel,
}

/// How far below its target a heater may read and still count as "at
/// temperature" (°C). Klipper's own `TEMPERATURE_WAIT` idiom uses a couple of
/// degrees; this matches the margin the notification roster uses to stop
/// calling a heater "heating", so the alert and the roster agree.
const double kAtTempMarginC = 3;

/// Grace after arming during which a zero target is NOT taken as "switched
/// off": the sheet arms right after its SET_HEATER_TEMPERATURE returns, but a
/// poll already in flight may still show the old target.
const int kAtTempGraceMs = 90 * 1000;

/// An arm older than this that still hasn't fired is dropped without buzzing
/// (notifications off across the whole warm-up, printer unreachable, ...), so
/// a forgotten arm can't surprise anyone hours later.
const int kAtTempStaleMs = 3 * 60 * 60 * 1000;

/// Judge one live poll against [arm]. [live] carries every heater reading the
/// poll has, by role (a role missing from it - an extra hotend not yet
/// supplemented - simply waits). The heater's CURRENT target is the truth: a
/// PRINT_START macro retargeting the hotend after the sheet set it changes
/// what "at temperature" means, and a target dropped to 0 (heaters off) after
/// the grace window cancels the arm outright.
AtTempVerdict evaluateAtTemp({
  required AtTempArm arm,
  required Map<String, HeaterReading> live,
  required int nowMs,
  double margin = kAtTempMarginC,
}) {
  if (arm.targets.isEmpty) return AtTempVerdict.cancel;
  final age = nowMs - arm.armedAtMs;
  if (age > kAtTempStaleMs) return AtTempVerdict.cancel;
  final inGrace = age < kAtTempGraceMs;
  for (final role in arm.targets.keys) {
    final r = live[role];
    if (r == null) return AtTempVerdict.wait;
    if (r.target <= 0) {
      return inGrace ? AtTempVerdict.wait : AtTempVerdict.cancel;
    }
    if (r.temp < r.target - margin) return AtTempVerdict.wait;
  }
  return AtTempVerdict.fire;
}

/// Human summary of what was reached, for the alert body: "Hotend 210° · Bed
/// 60°" on a single-hotend printer, "T0 210° · T1 230° · Bed 60°" on a
/// multi-toolhead one. Uses each heater's live target when the poll has it
/// (that is what was actually reached), else the target the sheet sent.
String atTempSummary(
  AtTempArm arm,
  Map<String, HeaterReading> live, {
  required String hotendLabel,
  required String bedLabel,
}) {
  final roles = arm.targets.keys.toList()..sort(_roleOrder);
  final parts = <String>[];
  for (final role in roles) {
    final idx = hotendIndexOf(role);
    final label = idx == null ? bedLabel : (arm.multi ? 'T$idx' : hotendLabel);
    final t = live[role]?.target ?? arm.targets[role]!;
    parts.add('$label ${t.round()}°');
  }
  return parts.join(' · ');
}

/// Hotends by tool number first, then the bed, then anything unknown.
int _roleOrder(String a, String b) {
  int rank(String r) {
    final idx = hotendIndexOf(r);
    if (idx != null) return idx;
    return r == bedRole ? 1 << 20 : 1 << 21;
  }

  return rank(a).compareTo(rank(b));
}
