import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tutorial_anchors.dart';

/// One step of the live walkthrough.
///
/// [anchor] is the GlobalKey of the element to spotlight (null = a centred
/// message with no spotlight). [id] selects the localized copy in the overlay,
/// kept as a plain string so the controller stays free of l10n imports.
class TutorialStep {
  final String id;

  /// Elements to spotlight this step. Most steps have one; some highlight a few
  /// at once (e.g. the connection bar and its Local/Tunnel label together).
  /// Empty = a message with no spotlight.
  final List<GlobalKey> anchors;

  /// Whether to dim the screen behind the spotlight. Turned off for steps that
  /// open their own modal (e.g. the preheat sheet) which already dims the rest.
  final bool dimScreen;

  /// Force the callout card to the top of the screen. Used when a bottom sheet
  /// is on screen so the card sits above it rather than under it.
  final bool forceCardTop;

  /// Whether the end (menu) drawer must be open for this step. The dashboard
  /// opens it on entry and closes it when the tour leaves the menu steps.
  final bool requiresDrawer;

  /// When this step has several [anchors], whether to spotlight them as one
  /// combined box (their bounding rectangle) rather than a separate ring around
  /// each. Used for the hotend / bed / chamber temperatures so they read as a
  /// single group. No effect with zero or one anchor.
  final bool unifyAnchors;

  const TutorialStep({
    required this.id,
    this.anchors = const [],
    this.dimScreen = true,
    this.forceCardTop = false,
    this.requiresDrawer = false,
    this.unifyAnchors = false,
  });
}

/// Immutable run state of the tutorial: whether it is active, which step we are
/// on, and the ordered step list for this run.
class TutorialState {
  final bool active;
  final int index;
  final List<TutorialStep> steps;

  const TutorialState({
    this.active = false,
    this.index = 0,
    this.steps = const [],
  });

  TutorialStep? get current =>
      active && index >= 0 && index < steps.length ? steps[index] : null;
  int get total => steps.length;
  bool get isLast => index >= steps.length - 1;

  TutorialState copyWith({bool? active, int? index, List<TutorialStep>? steps}) =>
      TutorialState(
        active: active ?? this.active,
        index: index ?? this.index,
        steps: steps ?? this.steps,
      );
}

/// Drives the walkthrough: start / next / skip. Kept deliberately small; the
/// step list grows here as each slice of the tour lands. Navigation, fake-state
/// injection and theme snapshot-restore hook in around these calls in later
/// slices.
class TutorialController extends Notifier<TutorialState> {
  @override
  TutorialState build() => const TutorialState();

  /// The ordered steps for a run. Grows per slice. Slice 2: the full tile tour
  /// (local bar -> tunnel bar -> hotend -> bed -> chamber -> webcam). The first
  /// dashboard tile fakes the matching state for each step and restores after.
  List<TutorialStep> _buildSteps() {
    final a = TutorialAnchors.instance;
    return [
      TutorialStep(id: 'localBar', anchors: [a.connectionBar, a.connectionLabel]),
      TutorialStep(id: 'tunnelBar', anchors: [a.connectionBar, a.connectionLabel]),
      TutorialStep(id: 'remoteBuilding', anchors: [a.tunnelDot]),
      // Hotend, bed and chamber temperatures are spotlighted together in one
      // step, as a single combined box around all three chips.
      TutorialStep(
        id: 'temps',
        anchors: [a.tempHotend, a.tempBed, a.tempChamber],
        unifyAnchors: true,
      ),
      TutorialStep(id: 'estop', anchors: [a.estop]),
      TutorialStep(id: 'webcam', anchors: [a.webcam]),
      // Preheat: first spotlight the long-press area (name + temps), then open
      // the real sheet. The sheet dims the rest itself, so that step adds no
      // scrim and floats the card above the sheet.
      TutorialStep(id: 'preheatPress', anchors: [a.preheatArea]),
      const TutorialStep(id: 'preheatSheet', dimScreen: false, forceCardTop: true),
      TutorialStep(id: 'addPrinter', anchors: [a.addPrinter]),
      // Hamburger menu. First point at the menu button (drawer still closed),
      // then the drawer opens and we walk its entries top to bottom; the
      // dashboard auto-scrolls each entry into view.
      TutorialStep(id: 'menuIcon', anchors: [a.menuIcon]),
      TutorialStep(id: 'menuPrinters', anchors: [a.menuPrinters], requiresDrawer: true),
      TutorialStep(id: 'menuBackup', anchors: [a.menuBackup], requiresDrawer: true),
      TutorialStep(id: 'menuDisplaySize', anchors: [a.menuDisplaySize], requiresDrawer: true),
      TutorialStep(id: 'menuColumns', anchors: [a.menuColumns], requiresDrawer: true),
      TutorialStep(id: 'menuCameras', anchors: [a.menuCameras], requiresDrawer: true),
      TutorialStep(id: 'menuLanguage', anchors: [a.menuLanguage], requiresDrawer: true),
    ];
  }

  void start() {
    state = TutorialState(active: true, index: 0, steps: _buildSteps());
  }

  /// One-off coach-mark shown the first time print notifications are turned on:
  /// a single spotlight over the app bar's pause/play button. Reuses the tour
  /// overlay (single step → no progress dots, no Skip, just "Done"). No-op if a
  /// run is already active so it can't stomp the main walkthrough.
  void startPauseHint() {
    if (state.active) return;
    state = TutorialState(
      active: true,
      index: 0,
      steps: [TutorialStep(id: 'pauseButton', anchors: [TutorialAnchors.instance.notifPause])],
    );
  }

  void next() {
    if (!state.active) return;
    if (state.isLast) {
      finish();
      return;
    }
    state = state.copyWith(index: state.index + 1);
  }

  /// Step back one (so an accidental Next doesn't force a restart). No-op on the
  /// first step.
  void previous() {
    if (!state.active || state.index == 0) return;
    state = state.copyWith(index: state.index - 1);
  }

  /// End the tour (reached the end, or the user tapped Skip).
  void finish() {
    state = const TutorialState();
  }
}

final tutorialControllerProvider =
    NotifierProvider<TutorialController, TutorialState>(TutorialController.new);
