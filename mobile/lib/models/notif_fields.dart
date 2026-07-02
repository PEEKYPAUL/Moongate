// The configurable segments of the persistent print-status notification's
// "printing" / "paused" lines, plus the (de)serialisation shared between the
// settings UI (NotificationFieldsNotifier) and the background notification
// isolate (PrintNotificationService). The printer name + status emoji are fixed
// and NOT part of this list.

/// One toggleable + reorderable piece of the notification line.
enum NotifField { progress, remaining, eta, hotend, bed }

/// SharedPreferences keys. Stored as two comma-joined strings (not StringLists)
/// so the values also ride the scalar-only settings backup (SettingsBackup) and
/// parse trivially in the background isolate.
const String kNotifFieldsOrderKey = 'notif_fields_order';
const String kNotifFieldsEnabledKey = 'notif_fields_enabled';

/// When true, the persistent status notification lists ONLY online printers -
/// offline / shut-down machines are filtered out of the roster. The foreground
/// service keeps running regardless; this is purely a display filter. Read by
/// both the settings switch (notifOnlineOnlyProvider) and the background isolate
/// (PrintNotificationService). Rides the settings backup.
const String kNotifOnlineOnlyKey = 'notif_online_only';

/// The dashboard's "Auto-arrange by status" toggle key. ON (default) re-sorts
/// by live status so active prints float to the top; OFF freezes the user's
/// manual drag-to-reorder order. Read by both the dashboard (autoArrangeProvider)
/// and the background isolate, so the persistent notification roster mirrors the
/// dashboard's order in either mode. Rides the settings backup.
const String kAutoArrangeByStatusKey = 'auto_arrange_by_status';

/// Inline markers prefixing the finish-time / temperature segments so each stays
/// self-describing even when the user reorders them. Shared by the live
/// notification renderer and the settings-screen preview so the two never drift.
const String kNotifEtaMarker = '🏁';
const String kNotifHotendMarker = '🔥';
const String kNotifBedMarker = '🟧';

/// The shown fields + their order. Immutable; a fresh instance is produced on
/// every edit so Riverpod notices the change.
class NotifFieldsConfig {
  /// Every field exactly once, in display (left-to-right) order.
  final List<NotifField> order;

  /// The subset currently shown.
  final Set<NotifField> enabled;

  const NotifFieldsConfig(this.order, this.enabled);

  /// Default order - everything on, in the historic reading order.
  static const List<NotifField> defaultOrder = [
    NotifField.progress,
    NotifField.remaining,
    NotifField.eta,
    NotifField.hotend,
    NotifField.bed,
  ];

  /// All fields, all enabled.
  factory NotifFieldsConfig.defaults() =>
      NotifFieldsConfig(List.of(defaultOrder), defaultOrder.toSet());

  static NotifField? _byName(String name) {
    for (final f in NotifField.values) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// Rebuild from the two raw pref strings (either may be null / unset).
  ///
  /// The order is forward-compatible: any field missing from a saved (or older)
  /// order string is appended in [defaultOrder] position, so every field always
  /// appears exactly once. A null `enabledRaw` means "never customised" → all
  /// on; a present value (even empty) is taken verbatim.
  factory NotifFieldsConfig.fromPrefs(String? orderRaw, String? enabledRaw) {
    final order = <NotifField>[];
    if (orderRaw != null) {
      for (final n in orderRaw.split(',')) {
        final f = _byName(n.trim());
        if (f != null && !order.contains(f)) order.add(f);
      }
    }
    for (final f in defaultOrder) {
      if (!order.contains(f)) order.add(f);
    }

    final Set<NotifField> enabled;
    if (enabledRaw == null) {
      enabled = order.toSet();
    } else {
      final e = <NotifField>{};
      for (final n in enabledRaw.split(',')) {
        final f = _byName(n.trim());
        if (f != null) e.add(f);
      }
      enabled = e;
    }
    return NotifFieldsConfig(order, enabled);
  }

  /// Comma-joined order, for SharedPreferences / backup.
  String get orderPref => order.map((f) => f.name).join(',');

  /// Comma-joined enabled subset (in display order), for SharedPreferences /
  /// backup.
  String get enabledPref =>
      order.where(enabled.contains).map((f) => f.name).join(',');
}

/// A representative rendering of [f] for the settings-screen live preview - the
/// real values come from the printer at notification time.
String notifFieldExample(NotifField f) => switch (f) {
      NotifField.progress => '56%',
      NotifField.remaining => '~14m',
      NotifField.eta => '${kNotifEtaMarker}1:20',
      NotifField.hotend => '${kNotifHotendMarker}210°',
      NotifField.bed => '${kNotifBedMarker}60°',
    };
