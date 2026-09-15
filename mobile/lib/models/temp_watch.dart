/// Temperature watches (v0.9.68, plugin 0.6.27+): the printer-side cousin of
/// the Android heat-soak alert ([HeatSoakArm] in heat_alerts.dart).
///
/// A watch lives in the Moongate plugin: "wait for these temperatures, in
/// whichever direction each one needs, optionally hold them for a soak time,
/// then say so once" - judged on the Pi every 20 s, so the phone can be asleep
/// and an iPhone gets the alert as a push. The app arms two kinds from the
/// Start-print dialog:
///
///   * `app-soak` - preheat the bed (and an active chamber heater) first, wait
///     for every temperature, run the soak clock, then START THE PRINT by
///     itself (only if the printer is still idle);
///   * `app-cool` - after the print has run and ended, alert once the bed and
///     chamber are back within [kCoolDownDeltaC] of what they read when Start
///     was tapped ("ready to remove").
///
/// The plugin also reports the live watches in /status (`temp_watches`), which
/// the tile turns into "Soaking · 12 min left". Pure Dart, unit-tested.
library;

import 'dart:math' as math;

/// First plugin that understands /server/moongate/temp-watch.
const String kTempWatchMinPlugin = '0.6.27';

/// "Cool enough to remove" = bed and chamber back within this many °C of the
/// readings taken when the print was started (Paul, 15/09/2026).
const double kCoolDownDeltaC = 5;

const String kTempWatchSoakId = 'app-soak';
const String kTempWatchCoolId = 'app-cool';

/// One live watch as the plugin reports it.
class TempWatchInfo {
  final String id;

  /// role → goal °C (roles: extruder, extruderN, bed, chamber).
  final Map<String, double> wait;

  /// role → 'up' (warming to the goal) or 'down' (cooling to it).
  final Map<String, String> dirs;
  final int soakMinutes;
  final String msg;

  /// gcodes-relative file the plugin starts once the watch fires ('' = none).
  final String thenStart;
  final bool afterPrint;
  final int armedTs;   // epoch seconds
  final int reachedTs; // epoch seconds, 0 until every goal was reached
  final int dueTs;     // epoch seconds the soak ends, 0 until the clock runs

  const TempWatchInfo({
    required this.id,
    required this.wait,
    required this.dirs,
    this.soakMinutes = 0,
    this.msg         = '',
    this.thenStart   = '',
    this.afterPrint  = false,
    this.armedTs     = 0,
    this.reachedTs   = 0,
    this.dueTs       = 0,
  });

  /// Every goal is a cool-down (the "ready to remove" kind, or a PRINT_END
  /// macro's cool-down).
  bool get coolDown =>
      wait.isNotEmpty && dirs.values.every((d) => d == 'down');

  /// The soak clock is running.
  bool get soaking => reachedTs > 0 && dueTs > 0;

  /// Whole minutes until the soak ends (0 once due).
  int minutesLeft(int nowMs) =>
      math.max(0, ((dueTs * 1000 - nowMs) / 60000).ceil());

  /// File name without its folders, for the tile.
  String get thenStartName => thenStart.split('/').last;

  /// Tolerant decode: anything malformed is null.
  static TempWatchInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id      = raw['id'];
    final rawWait = raw['wait'];
    if (id is! String || id.isEmpty || rawWait is! Map) return null;
    final wait = <String, double>{};
    for (final e in rawWait.entries) {
      final k = e.key;
      final v = e.value;
      if (k is String && v is num && v > 0) wait[k] = v.toDouble();
    }
    if (wait.isEmpty) return null;
    final dirs = <String, String>{};
    final rawDirs = raw['dirs'];
    if (rawDirs is Map) {
      for (final e in rawDirs.entries) {
        final k = e.key;
        final v = e.value;
        if (k is String && (v == 'up' || v == 'down')) dirs[k] = v as String;
      }
    }
    int intOf(Object? v) => v is num ? v.toInt() : 0;
    return TempWatchInfo(
      id:          id,
      wait:        wait,
      dirs:        dirs,
      soakMinutes: intOf(raw['soak']),
      msg:         raw['msg'] is String ? raw['msg'] as String : '',
      thenStart:   raw['then_start'] is String ? raw['then_start'] as String : '',
      afterPrint:  raw['after_print'] == true,
      armedTs:     intOf(raw['armed_ts']),
      reachedTs:   intOf(raw['reached_ts']),
      dueTs:       intOf(raw['due_ts']),
    );
  }

  /// The /status `temp_watches` list; an older plugin (no field) gives [].
  static List<TempWatchInfo> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (fromJson(e) case final w?) w,
    ];
  }
}

/// What the tile says about the live watches.
enum TempWatchTileKind { soaking, waitingForTemp, coolDownArmed }

class TempWatchTileLine {
  final TempWatchTileKind kind;

  /// Which watch the line describes (what a tap cancels).
  final String id;
  final int minutesLeft;

  /// The file the watch will start, '' when none.
  final String file;
  const TempWatchTileLine({
    required this.kind,
    required this.id,
    this.minutesLeft = 0,
    this.file = '',
  });
}

/// Pick the one line the tile shows: a warm-up (soak / at-temperature) watch
/// beats a cool-down one, since it is the thing happening now.
TempWatchTileLine? tempWatchTileLine(List<TempWatchInfo> watches, int nowMs) {
  if (watches.isEmpty) return null;
  for (final w in watches) {
    if (w.coolDown) continue;
    if (w.soaking) {
      return TempWatchTileLine(
        kind:        TempWatchTileKind.soaking,
        id:          w.id,
        minutesLeft: w.minutesLeft(nowMs),
        file:        w.thenStartName,
      );
    }
    return TempWatchTileLine(
      kind: TempWatchTileKind.waitingForTemp,
      id:   w.id,
      file: w.thenStartName,
    );
  }
  final cool = watches.firstWhere((w) => w.coolDown);
  return TempWatchTileLine(kind: TempWatchTileKind.coolDownArmed, id: cool.id);
}

/// The temperatures a cool-down watch will wait for, for the dialog's helper
/// text: the readings now plus [delta]. A chamber reading of 0 means the
/// printer reports none (no chamber goal).
({double bed, double? chamber}) coolDownGoals({
  required double bedNow,
  required double chamberNow,
  double delta = kCoolDownDeltaC,
}) =>
    (
      bed:     bedNow + delta,
      chamber: chamberNow > 0 ? chamberNow + delta : null,
    );

/// Body of the POST that arms the preheat-and-soak watch. [chamberHeater] is
/// the `heater_generic` object on the rare printer that actively heats its
/// chamber (it is then SET like the bed); on the usual passive chamber the
/// value is only waited for.
Map<String, dynamic> soakArmPayload({
  required double bed,
  double chamber = 0,
  String? chamberHeater,
  required int soakMinutes,
  required String file,
  required String msg,
}) =>
    {
      'id':   kTempWatchSoakId,
      'set':  {
        'heater_bed': bed,
        if (chamber > 0 && chamberHeater != null) chamberHeater: chamber,
      },
      'wait': {
        'bed': bed,
        if (chamber > 0) 'chamber': chamber,
      },
      'soak':       soakMinutes,
      'msg':        msg,
      'then_start': file,
    };

/// Body of the POST that arms the "ready to remove" watch. The plugin reads
/// the bed and chamber NOW and waits, once the print has run and ended, for
/// both to fall back to those readings plus [delta].
Map<String, dynamic> coolArmPayload({
  required String msg,
  double delta = kCoolDownDeltaC,
}) =>
    {
      'id':             kTempWatchCoolId,
      'cooldown_delta': delta,
      'after_print':    true,
      'msg':            msg,
    };
