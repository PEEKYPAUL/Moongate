// The home-screen widget's data feed (v0.9.79, Android).
//
// The print-notification isolate already polls every printer once per tick,
// so instead of a second poller the widget is fed from that loop: at the end
// of each tick the isolate writes ONE JSON snapshot of the fleet through
// home_widget's SharedPreferences bridge and asks the Glance widget to
// redraw. The widget never computes anything itself - every word it shows
// (state, remaining time, finish clock, layer line, the stale hint's
// templates) is produced here in Dart, already localised to the app's own
// language, so the Kotlin side only renders. That is also what makes the
// feed platform-neutral: an iOS WidgetKit twin would read the same JSON.
//
// This file is pure Dart (no Flutter / plugin imports) so it can be unit
// tested; the plugin calls live in services/widget_feed.dart.

import 'dart:convert';

import 'printer_config.dart';

/// Schema version written into every snapshot. Bump when a field changes
/// meaning, so an older widget binary can ignore a newer snapshot cleanly.
const kWidgetSnapshotVersion = 1;

/// One printer, as the widget shows it. Numbers stay numeric (progress, temps)
/// because the layouts draw rings and bars from them; every word is a ready
/// display string.
class WidgetPrinter {
  /// PrinterConfig.id - the widget's tap target is `moongate://printer/<id>`.
  final String id;
  final String name;

  /// The raw state the colour follows ('printing', 'paused', 'error',
  /// 'heating', 'offline', 'standby', ...). `printerStatusRank` ranks it.
  final String state;

  /// The localised state word shown next to the name (Printing / Paused /
  /// Ready / Offline ...) - the same word the notification roster uses.
  final String stateLabel;

  /// 0..1 while printing or paused; 0 otherwise.
  final double progress;

  /// Seconds left, when the shared estimate has one; null hides the ETA.
  final int? remainingSec;

  /// "~1h05m" - the remaining time, pre-formatted. Null when unknown.
  final String? remainingLabel;

  /// "13:20" / "1:20 PM" - the projected finish, in the app's locale. Null
  /// when unknown.
  final String? finishClock;

  /// The printing file's name, without its folder. Null when idle.
  final String? filename;

  /// "Layer 12 / 300", when the slicer reports layers. Null otherwise.
  final String? layerLabel;

  final double hotend;
  final double hotendTarget;
  final double bed;
  final double bedTarget;

  /// 0 when the printer has no chamber sensor (the widget hides the chip).
  final double chamber;

  const WidgetPrinter({
    required this.id,
    required this.name,
    required this.state,
    required this.stateLabel,
    this.progress       = 0,
    this.remainingSec,
    this.remainingLabel,
    this.finishClock,
    this.filename,
    this.layerLabel,
    this.hotend         = 0,
    this.hotendTarget   = 0,
    this.bed            = 0,
    this.bedTarget      = 0,
    this.chamber        = 0,
  });

  /// Dashboard ranking (error first, then printing / paused / heating, then
  /// ready, idle, offline) - the small layouts show the lowest rank.
  int get rank => printerStatusRank(state);

  Map<String, dynamic> toJson() => {
        'id':             id,
        'name':           name,
        'state':          state,
        'stateLabel':     stateLabel,
        'progress':       progress,
        if (remainingSec   != null) 'remainingSec':   remainingSec,
        if (remainingLabel != null) 'remainingLabel': remainingLabel,
        if (finishClock    != null) 'finishClock':    finishClock,
        if (filename       != null) 'filename':       filename,
        if (layerLabel     != null) 'layerLabel':     layerLabel,
        'hotend':         hotend,
        'hotendTarget':   hotendTarget,
        'bed':            bed,
        'bedTarget':      bedTarget,
        'chamber':        chamber,
        'rank':           rank,
      };

  factory WidgetPrinter.fromJson(Map<String, dynamic> j) => WidgetPrinter(
        id:             j['id'] as String,
        name:           j['name'] as String,
        state:          j['state'] as String,
        stateLabel:     j['stateLabel'] as String,
        progress:       (j['progress'] as num?)?.toDouble() ?? 0,
        remainingSec:   (j['remainingSec'] as num?)?.toInt(),
        remainingLabel: j['remainingLabel'] as String?,
        finishClock:    j['finishClock'] as String?,
        filename:       j['filename'] as String?,
        layerLabel:     j['layerLabel'] as String?,
        hotend:         (j['hotend']       as num?)?.toDouble() ?? 0,
        hotendTarget:   (j['hotendTarget'] as num?)?.toDouble() ?? 0,
        bed:            (j['bed']          as num?)?.toDouble() ?? 0,
        bedTarget:      (j['bedTarget']    as num?)?.toDouble() ?? 0,
        chamber:        (j['chamber']      as num?)?.toDouble() ?? 0,
      );
}

/// The whole fleet as the widget last saw it.
class WidgetSnapshot {
  /// Wall clock of the poll that produced this, epoch milliseconds. The widget
  /// turns the age into its "Updated N min ago" hint while [monitoring] is off.
  final int updatedAt;

  /// True while the print-notification service is running - the snapshot is
  /// live and refreshes every poll. False once the service stops or is paused
  /// (the data is kept so the widget can show it greyed), and after a one-shot
  /// refresh from the widget's own glyph.
  final bool monitoring;

  /// Printers in dashboard order (auto-arranged by status when that setting is
  /// on, else the user's manual order) - the fleet layout lists them as given.
  final List<WidgetPrinter> printers;

  /// Index into [printers] of the one the small layouts show. See
  /// [pickFeaturedIndex].
  final int featured;

  /// The localised templates the widget needs for text it must build itself
  /// (the moving "updated ago" hint, the empty states). Keys are
  /// [WidgetStrings] constants; `{n}` is the one substitution the widget does.
  final Map<String, String> strings;

  const WidgetSnapshot({
    required this.updatedAt,
    required this.monitoring,
    required this.printers,
    required this.featured,
    this.strings = const {},
  });

  Map<String, dynamic> toJson() => {
        'v':          kWidgetSnapshotVersion,
        'updatedAt':  updatedAt,
        'monitoring': monitoring,
        'featured':   featured,
        'printers':   [for (final p in printers) p.toJson()],
        'strings':    strings,
      };

  String encode() => jsonEncode(toJson());

  factory WidgetSnapshot.fromJson(Map<String, dynamic> j) => WidgetSnapshot(
        updatedAt:  (j['updatedAt'] as num?)?.toInt() ?? 0,
        monitoring: j['monitoring'] as bool? ?? false,
        featured:   (j['featured'] as num?)?.toInt() ?? 0,
        printers: [
          for (final p in (j['printers'] as List? ?? const []))
            WidgetPrinter.fromJson(p as Map<String, dynamic>),
        ],
        strings: {
          for (final e in (j['strings'] as Map? ?? const {}).entries)
            e.key as String: e.value as String,
        },
      );

  /// Null when [raw] isn't a snapshot we can read (absent, corrupt, or a
  /// newer schema).
  static WidgetSnapshot? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return null;
      final v = (j['v'] as num?)?.toInt() ?? 0;
      if (v > kWidgetSnapshotVersion) return null;
      return WidgetSnapshot.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  /// The same snapshot marked no-longer-live, data kept. Written when the
  /// service stops so the widget greys out instead of lying.
  WidgetSnapshot asStale() => WidgetSnapshot(
        updatedAt:  updatedAt,
        monitoring: false,
        printers:   printers,
        featured:   featured,
        strings:    strings,
      );
}

/// Which printer the one-printer layouts (2x2, 4x1) show: the first in
/// dashboard-rank order - an erroring printer beats a printing one, a printing
/// one beats an idle one, and ties keep the list's own order (so the
/// user's manual arrangement decides between two idle machines). 0 for an
/// empty list.
int pickFeaturedIndex(List<WidgetPrinter> printers) {
  var best = 0;
  for (var i = 1; i < printers.length; i++) {
    if (printers[i].rank < printers[best].rank) best = i;
  }
  return best;
}

/// Keys of the localised templates carried in [WidgetSnapshot.strings]. The
/// Kotlin side looks these up by name and substitutes `{n}` where present.
abstract final class WidgetStrings {
  /// Shown before any snapshot exists: how to feed the widget.
  static const noData       = 'noData';

  /// A snapshot with zero printers: nothing paired yet.
  static const noPrinters   = 'noPrinters';

  /// "Updated just now" - the stale hint under a minute old.
  static const justNow      = 'justNow';

  /// "Updated {n} min ago".
  static const minutesAgo   = 'minutesAgo';

  /// "Updated {n} h ago".
  static const hoursAgo     = 'hoursAgo';

  /// "Updated {n} d ago".
  static const daysAgo      = 'daysAgo';

  /// The pre-key the templates are saved under alongside the snapshot, so a
  /// fresh install's widget has words before the service has ever run.
  static const all = [noData, noPrinters, justNow, minutesAgo, hoursAgo, daysAgo];
}
