import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io' show Platform;

import 'package:home_widget/home_widget.dart';

import '../l10n/app_localizations.dart';
import '../models/widget_snapshot.dart';

/// The plugin side of the home-screen widget feed (Android, v0.9.79).
///
/// home_widget stores whatever Dart saves in a SharedPreferences file the
/// Glance widget reads back (`HomeWidgetPreferences`), and `updateWidget`
/// broadcasts APPWIDGET_UPDATE to our receiver so it redraws. Two keys:
///   • [snapshotKey] - the fleet snapshot the print-notification isolate writes
///     once per poll ([WidgetSnapshot]);
///   • [stringsKey]  - the localised templates alone, written by the app at
///     start-up so a widget added before the service has ever run still has
///     words (the snapshot carries the same templates once it exists).
/// Every call is best-effort and Android-only: iOS has no widget yet, and a
/// failure here must never take the notification tick down with it.
abstract final class WidgetFeed {
  static const snapshotKey = 'fleet_snapshot';
  static const stringsKey  = 'widget_strings';

  /// The Glance receivers, fully qualified (the Kotlin package is the
  /// applicationId, shared by both flavors): one app-widget provider per
  /// picker size (width x height in cells), all rendering the same widget -
  /// see MoongateWidgetReceivers.kt. A redraw has to be asked of each.
  static const _pkg = 'com.moongate.app.moongate.MoongateWidgetReceiver';
  static const receivers = [
    '${_pkg}2x2',
    '${_pkg}2x4',
    '${_pkg}3x2',
    '${_pkg}3x4',
    '${_pkg}4x2',
    '${_pkg}4x3',
    '${_pkg}4x4',
  ];

  /// The URI the widget's refresh glyph fires into [registerRefreshCallback]'s
  /// callback via home_widget's background intent.
  static const refreshUri = 'moongate://widget/refresh';

  static bool get _supported => Platform.isAndroid;

  static void _log(String msg) => dev.log(msg, name: 'MOONGATE/WIDGET');

  /// The localised templates, keyed by [WidgetStrings]. `{n}` is left in the
  /// "Updated {n}" line for the widget to fill with the snapshot's clock time.
  static Map<String, String> templates(AppLocalizations l) => {
        WidgetStrings.noData:     l.widgetNoData,
        WidgetStrings.noPrinters: l.widgetNoPrinters,
        WidgetStrings.updatedAt:  l.widgetUpdatedAt('{n}'),
        WidgetStrings.status:     l.widgetStatus,
      };

  /// Save [snapshot] and redraw every placed widget.
  static Future<void> publish(WidgetSnapshot snapshot) async {
    if (!_supported) return;
    try {
      await HomeWidget.saveWidgetData<String>(snapshotKey, snapshot.encode());
      await _redrawAll();
    } catch (e) {
      _log('publish failed: $e');
    }
  }

  /// Save the templates alone (see [stringsKey]) and redraw.
  static Future<void> publishStrings(AppLocalizations l) async {
    if (!_supported) return;
    try {
      await HomeWidget.saveWidgetData<String>(
          stringsKey, jsonEncode(templates(l)));
      await _redrawAll();
    } catch (e) {
      _log('publishStrings failed: $e');
    }
  }

  /// Ask every provider to redraw its placed widgets (a provider with none
  /// placed is a no-op broadcast).
  static Future<void> _redrawAll() async {
    for (final name in receivers) {
      await HomeWidget.updateWidget(qualifiedAndroidName: name);
    }
  }

  /// Flip the stored snapshot to `monitoring: false`, keeping its data, so the
  /// widget greys out with an "updated N min ago" hint instead of showing a
  /// dead print as live. Called when the service stops or is paused. No-op
  /// when nothing has been written yet.
  static Future<void> markStale() async {
    if (!_supported) return;
    try {
      final raw  = await HomeWidget.getWidgetData<String>(snapshotKey);
      final snap = WidgetSnapshot.decode(raw);
      if (snap == null || !snap.monitoring) return;
      await publish(snap.asStale());
    } catch (e) {
      _log('markStale failed: $e');
    }
  }

  /// Register the Dart function the widget's refresh glyph runs in the
  /// background (home_widget spins up a headless engine for it). Must be a
  /// top-level `@pragma('vm:entry-point')` function; called once from main().
  static Future<void> registerRefreshCallback(
      Future<void> Function(Uri?) callback) async {
    if (!_supported) return;
    try {
      await HomeWidget.registerInteractivityCallback(callback);
    } catch (e) {
      _log('registerInteractivityCallback failed: $e');
    }
  }
}
