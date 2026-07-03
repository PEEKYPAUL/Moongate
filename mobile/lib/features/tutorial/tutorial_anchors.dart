import 'package:flutter/widgets.dart';

/// Shared GlobalKeys for the dashboard elements the live tutorial spotlights.
///
/// The first printer tile attaches these keys to its parts when it is the
/// designated tutorial-anchor tile, and the [TutorialOverlay] reads their
/// RenderBoxes to position the spotlight hole. Both sides reference the same
/// singleton so the keys are identical instances.
///
/// Slice 1 only needs the connection bar; the temps, webcam and printer-screen
/// anchors get added here as the tour is built out.
class TutorialAnchors {
  TutorialAnchors._();
  static final TutorialAnchors instance = TutorialAnchors._();

  /// The thin connection-state colour bar at the top of the first tile.
  final GlobalKey connectionBar = GlobalKey(debugLabel: 'tut_connectionBar');

  /// The Local/Tunnel text label + its wifi/cloud icon in the tile's name row.
  final GlobalKey connectionLabel = GlobalKey(debugLabel: 'tut_connectionLabel');

  /// The small tunnel-status pip next to the Local badge (building vs ready).
  final GlobalKey tunnelDot = GlobalKey(debugLabel: 'tut_tunnelDot');

  /// The hotend / bed / chamber temperature chips on the first tile.
  final GlobalKey tempHotend = GlobalKey(debugLabel: 'tut_tempHotend');
  final GlobalKey tempBed = GlobalKey(debugLabel: 'tut_tempBed');
  final GlobalKey tempChamber = GlobalKey(debugLabel: 'tut_tempChamber');

  /// The webcam square on the first tile.
  final GlobalKey webcam = GlobalKey(debugLabel: 'tut_webcam');

  /// The name + temperatures block, the long-press target that opens preheat.
  final GlobalKey preheatArea = GlobalKey(debugLabel: 'tut_preheatArea');

  /// The emergency-stop button at the end of the temperature row.
  final GlobalKey estop = GlobalKey(debugLabel: 'tut_estop');

  /// The add-printer floating action button on the dashboard.
  final GlobalKey addPrinter = GlobalKey(debugLabel: 'tut_addPrinter');

  /// The pause/play button in the app bar that suspends / resumes the print-
  /// notification service. Only present when notifications are enabled, so it's
  /// spotlighted by a one-off hint the first time they're turned on rather than
  /// as part of the main tour.
  final GlobalKey notifPause = GlobalKey(debugLabel: 'tut_notifPause');

  // ── Hamburger menu (end drawer) ─────────────────────────────────────────────
  /// The hamburger menu button in the app bar (spotlit before the drawer opens).
  final GlobalKey menuIcon = GlobalKey(debugLabel: 'tut_menuIcon');

  /// Add / remove printer entries, grouped.
  final GlobalKey menuPrinters = GlobalKey(debugLabel: 'tut_menuPrinters');

  /// Backup / restore config entries, grouped.
  final GlobalKey menuBackup = GlobalKey(debugLabel: 'tut_menuBackup');

  /// The Theme selector in the drawer.
  final GlobalKey menuTheme = GlobalKey(debugLabel: 'tut_menuTheme');

  /// The display-size (font size) slider in the drawer.
  final GlobalKey menuDisplaySize = GlobalKey(debugLabel: 'tut_menuDisplaySize');

  /// The dashboard layout column picker in the drawer.
  final GlobalKey menuColumns = GlobalKey(debugLabel: 'tut_menuColumns');

  /// The camera-feeds / webcams entries, grouped.
  final GlobalKey menuCameras = GlobalKey(debugLabel: 'tut_menuCameras');

  /// The About section, grouped.
  final GlobalKey menuAbout = GlobalKey(debugLabel: 'tut_menuAbout');

  /// The "buy me a coffee" support entry (Android only).
  final GlobalKey menuSupport = GlobalKey(debugLabel: 'tut_menuSupport');

  /// The Settings entry in the drawer (holds remove-all + delete-my-data).
  final GlobalKey menuSettings = GlobalKey(debugLabel: 'tut_menuSettings');

  /// The language entry in the drawer.
  final GlobalKey menuLanguage = GlobalKey(debugLabel: 'tut_menuLanguage');
}
