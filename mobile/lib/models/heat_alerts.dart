/// Pure decision logic for the preheat sheet's heat-soak alert (v0.9.67).
///
/// A heat soak, as printer people mean it, is "get everything up to
/// temperature, then hold it there for a while so the frame settles". The
/// sheet arms one [HeatSoakArm] per printer naming the temperatures it just
/// set, by ROLE rather than Klipper object name ('h0' = the primary hotend,
/// 'h1' = `extruder1` and so on for a multi-toolhead machine, 'bed' = the bed,
/// 'chamber' = the chamber sensor), plus a soak time in minutes. The Android
/// notification isolate then asks [evaluateHeatSoak] on every live poll:
///
///   * until every role reads its target, WAIT (or CANCEL if the heaters were
///     switched off, i.e. the preheat was abandoned);
///   * the first poll where everything is at temperature FIRES when the soak
///     time is 0 ("At temperature"), else starts the soak clock (REACHED - the
///     caller persists that moment so a service restart keeps counting);
///   * once the clock runs out, FIRE ("Heat-soak complete"). A temperature sag
///     during the soak (a door opened) does NOT reset the clock - a drafty
///     machine could otherwise never finish a 20-minute soak.
///
/// The chamber is special: on nearly every printer it is a passive sensor
/// warmed by the bed, so its "target" is simply the value the user typed (the
/// sheet insists on a bed temperature alongside it). A printer with a real
/// `heater_generic` chamber reports a target of its own, which then wins.
///
/// Kept free of Flutter imports so the rules are unit-testable.
library;

/// Role key for the hotend of tool [index] ('h0', 'h1', ...). T0 is Klipper's
/// primary `extruder` whatever it is actually called; the rest are `extruderN`.
String hotendRole(int index) => 'h$index';

/// Role key for the heated bed.
const String bedRole = 'bed';

/// Role key for the chamber sensor (or chamber heater, where one exists).
const String chamberRole = 'chamber';

/// Tool number of a hotend role ('h2' → 2), or null for the bed / chamber /
/// anything unrecognised.
int? hotendIndexOf(String role) {
  if (role.length < 2 || !role.startsWith('h')) return null;
  return int.tryParse(role.substring(1));
}

/// One heater's (or sensor's) live reading: current temperature and its
/// CURRENT target, both in °C, as the printer reports them now. A passive
/// chamber sensor has no target and reports 0.
class HeaterReading {
  final double temp;
  final double target;
  const HeaterReading(this.temp, this.target);
}

/// An armed heat-soak alert for one printer.
class HeatSoakArm {
  /// When Set was pressed (epoch ms).
  final int armedAtMs;

  /// role → °C the sheet sent (or, for a passive chamber, the value to wait
  /// for). Only temperatures actually being heated - never 0.
  final Map<String, double> targets;

  /// Whether the sheet was in its multi-toolhead layout (the alert body then
  /// reads "T0 210°" rather than "Hotend 210°").
  final bool multi;

  /// How long every temperature must hold after being reached before the
  /// alert fires. 0 = fire the moment everything is at temperature.
  final int soakMinutes;

  /// The moment every role first read its target (epoch ms) - set by the
  /// isolate when the verdict was [HeatSoakVerdict.reached]; null until then.
  final int? reachedAtMs;

  const HeatSoakArm({
    required this.armedAtMs,
    required this.targets,
    this.multi       = false,
    this.soakMinutes = 0,
    this.reachedAtMs,
  });

  /// True once the soak clock is running.
  bool get soaking => reachedAtMs != null;

  /// True when the arm waits on a tool beyond T0, whose reading the
  /// notification poll only fetches on demand (an idle printer's roster never
  /// shows extra hotends, so the isolate must supplement them for this).
  bool get needsExtraHotends =>
      targets.keys.any((r) => (hotendIndexOf(r) ?? 0) > 0);

  HeatSoakArm copyWith({int? reachedAtMs}) => HeatSoakArm(
        armedAtMs:   armedAtMs,
        targets:     targets,
        multi:       multi,
        soakMinutes: soakMinutes,
        reachedAtMs: reachedAtMs ?? this.reachedAtMs,
      );

  Map<String, dynamic> toJson() => {
        'at':      armedAtMs,
        'multi':   multi,
        'soak':    soakMinutes,
        if (reachedAtMs != null) 'reached': reachedAtMs,
        'targets': targets,
      };

  /// Tolerant decode: anything malformed is null (dropped by the store).
  static HeatSoakArm? fromJson(Object? raw) {
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
    final soak    = raw['soak'];
    final reached = raw['reached'];
    return HeatSoakArm(
      armedAtMs:   at.toInt(),
      targets:     targets,
      multi:       raw['multi'] == true,
      soakMinutes: soak is num && soak > 0 ? soak.toInt() : 0,
      reachedAtMs: reached is num ? reached.toInt() : null,
    );
  }
}

/// What a live poll means for an armed heat-soak alert.
enum HeatSoakVerdict {
  /// Not there yet (or the poll couldn't say) - check again next tick.
  wait,

  /// Every temperature is reached and a soak time is set: start the clock.
  /// The caller persists `reachedAtMs = now` on the arm.
  reached,

  /// Alert now (at temperature with no soak time, or the soak has held), then
  /// clear the arm.
  fire,

  /// Give up silently: the arm went stale, a heater was switched off since
  /// arming (the preheat was abandoned - nothing to wait for), or the soak
  /// deadline was only noticed long after it passed.
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

/// An arm that still hasn't reached temperature this long after arming is
/// dropped without buzzing (notifications off across the whole warm-up, the
/// printer unreachable, a chamber that can't get there in this weather...).
/// Generous because a passive chamber can take an hour or more.
const int kHeatSoakStaleMs = 6 * 60 * 60 * 1000;

/// A soak deadline first noticed this long after it passed (e.g. notifications
/// were off across it) is dropped rather than firing a confusing late alert.
const int kHeatSoakLateMs = 60 * 60 * 1000;

/// Judge one live poll against [arm]. [live] carries every reading the poll
/// has, by role (a role missing from it - an extra hotend not yet supplemented,
/// a chamber sensor the payload lacks - simply waits). A heater's CURRENT
/// target is the truth: a PRINT_START macro retargeting the hotend after the
/// sheet set it changes what "at temperature" means, and a target dropped to
/// 0 (heaters off) after the grace window cancels the arm outright. The chamber
/// is judged against the value the sheet sent unless the printer reports a
/// chamber target of its own (an active chamber heater).
HeatSoakVerdict evaluateHeatSoak({
  required HeatSoakArm arm,
  required Map<String, HeaterReading> live,
  required int nowMs,
  double margin = kAtTempMarginC,
}) {
  if (arm.targets.isEmpty) return HeatSoakVerdict.cancel;

  final reachedAt = arm.reachedAtMs;
  if (reachedAt == null) {
    final age = nowMs - arm.armedAtMs;
    if (age > kHeatSoakStaleMs) return HeatSoakVerdict.cancel;
    final inGrace = age < kAtTempGraceMs;
    for (final role in arm.targets.keys) {
      final r = live[role];
      if (r == null) return HeatSoakVerdict.wait;
      if (role == chamberRole) {
        final goal = r.target > 0 ? r.target : arm.targets[role]!;
        if (r.temp < goal - margin) return HeatSoakVerdict.wait;
        continue;
      }
      if (r.target <= 0) {
        return inGrace ? HeatSoakVerdict.wait : HeatSoakVerdict.cancel;
      }
      if (r.temp < r.target - margin) return HeatSoakVerdict.wait;
    }
    return arm.soakMinutes > 0
        ? HeatSoakVerdict.reached
        : HeatSoakVerdict.fire;
  }

  // Soaking. Heaters switched off mid-soak = abandoned; a sag does not reset.
  for (final role in arm.targets.keys) {
    if (role == chamberRole) continue;
    final r = live[role];
    if (r != null && r.target <= 0) return HeatSoakVerdict.cancel;
  }
  final due = reachedAt + arm.soakMinutes * 60 * 1000;
  if (nowMs < due) return HeatSoakVerdict.wait;
  if (nowMs - due > kHeatSoakLateMs) return HeatSoakVerdict.cancel;
  return HeatSoakVerdict.fire;
}

/// Human summary of what was reached, for the alert body: "Hotend 210° · Bed
/// 100° · Chamber 45°" on a single-hotend printer, "T0 210° · T1 230° · Bed
/// 60°" on a multi-toolhead one. Uses each heater's live target when the poll
/// has one (that is what was actually reached), else the value the sheet sent
/// (always the case for a passive chamber).
String heatSoakSummary(
  HeatSoakArm arm,
  Map<String, HeaterReading> live, {
  required String hotendLabel,
  required String bedLabel,
  required String chamberLabel,
}) {
  final roles = arm.targets.keys.toList()..sort(_roleOrder);
  final parts = <String>[];
  for (final role in roles) {
    final idx = hotendIndexOf(role);
    final String label;
    if (idx != null) {
      label = arm.multi ? 'T$idx' : hotendLabel;
    } else if (role == chamberRole) {
      label = chamberLabel;
    } else {
      label = bedLabel;
    }
    final liveTarget = live[role]?.target ?? 0;
    final t = liveTarget > 0 ? liveTarget : arm.targets[role]!;
    parts.add('$label ${t.round()}°');
  }
  return parts.join(' · ');
}

/// Hotends by tool number first, then the bed, then the chamber, then
/// anything unknown.
int _roleOrder(String a, String b) {
  int rank(String r) {
    final idx = hotendIndexOf(r);
    if (idx != null) return idx;
    if (r == bedRole) return 1 << 20;
    if (r == chamberRole) return 1 << 21;
    return 1 << 22;
  }

  return rank(a).compareTo(rank(b));
}
