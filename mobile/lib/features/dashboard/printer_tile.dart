import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../providers/custom_theme_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/print_control_service.dart';
import '../../services/printer_registry.dart';
import '../../services/printer_status_registry.dart';
import '../../services/printer_status_service.dart';
import '../../widgets/webcam_view.dart';
import '../printer/printer_camera_screen.dart';
import '../tutorial/tutorial_anchors.dart';
import '../tutorial/tutorial_controller.dart';
import 'gcode_files_overlay.dart';
import 'macros_overlay.dart';
import 'preheat_overlay.dart';

class PrinterTile extends ConsumerStatefulWidget {
  final PrinterConfig printer;
  final VoidCallback onTap;

  /// Card background opacity (the Custom theme's tile opacity; 1.0 = opaque).
  /// When < 1 the tile's card/stats area goes see-through so a custom dashboard
  /// background shows through; the webcam image stays opaque.
  final double tileOpacity;

  /// True when the tile is rendered inside a fixed-height cell (the manual
  /// drag-to-reorder grid) rather than the masonry grid. A masonry cell has an
  /// unbounded height, so the webcam square defines the tile height there; a
  /// reorder cell is bounded, so the square is wrapped in a loose Flexible that
  /// can give height back rather than overflow on a busy tile. See _webcamCell.
  final bool bounded;

  /// True only for the one tile the live tutorial spotlights (the first tile on
  /// the dashboard). When set, the tile attaches the shared [TutorialAnchors]
  /// keys to its parts so the tutorial overlay can locate them. Off for every
  /// other tile (a GlobalKey must be mounted only once).
  final bool anchorForTutorial;

  const PrinterTile({
    super.key,
    required this.printer,
    required this.onTap,
    this.tileOpacity = 1.0,
    this.bounded = false,
    this.anchorForTutorial = false,
  });

  @override
  ConsumerState<PrinterTile> createState() => _PrinterTileState();
}

class _PrinterTileState extends ConsumerState<PrinterTile>
    with WidgetsBindingObserver {
  late final PrinterStatusService _statusService;
  late final PrintControlService _controlService;
  late PrinterStatus _status;

  bool _stopConfirmPending = false;
  Timer? _stopConfirmTimer;

  /// Live tutorial: while a demo step is showing doctored state on this (the
  /// first) tile, [_realBehindDemo] holds the genuine latest status so it can be
  /// restored the moment the demo ends. Null when no demo override is active.
  PrinterStatus? _realBehindDemo;

  /// True while the tutorial's preheat step has the preheat sheet open, so it
  /// can be closed again when the step moves on.
  bool _preheatDemoOpen = false;

  /// Web UI type - 'mainsail', 'fluidd', or null. Seeded from the persisted
  /// config (so a cold launch shows the logo immediately even if the
  /// printer is currently offline) and updated whenever the status service
  /// detects it for the first time on a fresh printer.
  String? _uiType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Seed the initial status with persisted webcam transform settings so the
    // first frame already shows the correct orientation - before any poll.
    // Use 'connecting' rather than 'offline' so the badge says "Connecting"
    // during the first poll instead of immediately flashing "Offline".
    _status = PrinterStatus(
      state:           'connecting',
      progress:        0,
      hotendTemp:      0,
      hotendTarget:    0,
      bedTemp:         0,
      bedTarget:       0,
      connection:      PrinterConnection.offline,
      webcamFlipH:     widget.printer.webcamFlipH,
      webcamFlipV:     widget.printer.webcamFlipV,
      webcamRotation:  widget.printer.webcamRotation,
      webcamTargetFps: widget.printer.webcamTargetFps,
    );
    _statusService = PrinterStatusService(widget.printer);
    _controlService = PrintControlService(widget.printer);
    // Seed from persisted config so a cold launch can render the right
    // logo immediately - without waiting for the first detection round-trip.
    _uiType = widget.printer.uiType;
    _statusService.stream.listen((s) {
      // Record the latest live status for the bug-report diagnostics, even if
      // this tile is no longer mounted - it's the most useful triage signal.
      PrinterStatusRegistry.instance.update(widget.printer.id, s);
      if (!mounted) return;
      // While the tutorial is showing a demo override on this tile, keep the
      // real status fresh behind the scenes but don't disturb what's on screen.
      if (_realBehindDemo != null) {
        _realBehindDemo = s;
        return;
      }
      final wasActive = _status.state == 'printing' || _status.state == 'paused';
      final isActive  = s.state == 'printing' || s.state == 'paused';
      // Print ended naturally while stop-confirm timer was still running -
      // clear the pending state so the button resets to "firmware restart".
      if (wasActive && !isActive && _stopConfirmPending) {
        _stopConfirmTimer?.cancel();
        _stopConfirmPending = false;
      }
      setState(() {
        _status = s;
        // Pick up UI type as soon as the service detects it.
        final detected = _statusService.uiType;
        if (detected != null && detected != _uiType) _uiType = detected;
      });
    });
    _statusService.start();
  }

  // ── Live tutorial demo state ───────────────────────────────────────────────
  // The first dashboard tile reacts to the tutorial's current step by showing a
  // clean, idle, locally-connected version of itself (so the tour reads well
  // even if the real printer is offline or mid-print), with the step's twist
  // applied (tunnel mode, or a faked chamber reading). Restored on the way out.
  static const _tileDemoSteps = {
    'localBar', 'tunnelBar', 'remoteBuilding', 'temps',
    'estop', 'webcam', 'preheatPress', 'preheatSheet',
  };

  void _applyDemoForStep(TutorialState s) {
    final id = s.active ? s.current?.id : null;
    if (id != null && _tileDemoSteps.contains(id)) {
      _realBehindDemo ??= _status; // remember the real status once
      setState(() => _status = _demoStatusFor(id));
    } else if (_realBehindDemo != null) {
      setState(() {
        _status = _realBehindDemo!;
        _realBehindDemo = null;
      });
    }
    // The second preheat step shows the real preheat sheet; open on entry, close
    // on the way out (next step, or the tour ending / being skipped).
    if (id == 'preheatSheet') {
      _openPreheatDemo();
    } else {
      _closePreheatDemo();
    }
  }

  void _openPreheatDemo() {
    if (_preheatDemoOpen) return;
    _preheatDemoOpen = true;
    showPreheatSheet(
      context,
      widget.printer,
      hotendTarget: _status.hotendTarget,
      bedTarget: _status.bedTarget,
      toolheads: _status.toolheads,
    ).whenComplete(() => _preheatDemoOpen = false);
  }

  void _closePreheatDemo() {
    if (!_preheatDemoOpen) return;
    _preheatDemoOpen = false;
    Navigator.of(context).maybePop();
  }

  PrinterStatus _demoStatusFor(String id) {
    final real = _realBehindDemo ?? _status;
    // A tidy, idle, local baseline so every tile step reads correctly.
    final base = real.copyWith(
      state:       'standby',
      connection:  PrinterConnection.local,
      tunnelReady: true,
      hotendTemp:  real.hotendTemp > 0 ? real.hotendTemp : 24,
      bedTemp:     real.bedTemp > 0 ? real.bedTemp : 24,
      klippyShutdown: false,
    );
    switch (id) {
      case 'tunnelBar':
        return base.copyWith(connection: PrinterConnection.remote);
      case 'remoteBuilding':
        // Stay on Local but show the tunnel as still building in the background.
        return base.copyWith(tunnelReady: false);
      case 'temps':
        // Spotlight all three chips at once: fake a chamber reading if the
        // printer has none, so the chamber chip mounts and can be highlighted.
        return base.chamberTemp > 0 ? base : base.copyWith(chamberTemp: 28);
      default:
        return base;
    }
  }

  /// Wrap [child] with a tutorial spotlight anchor, but only on the tile the
  /// tour targets (a GlobalKey must be mounted exactly once). Other tiles and
  /// the off-tour case pass the child straight through.
  Widget _anchor(GlobalKey key, Widget child) =>
      widget.anchorForTutorial ? KeyedSubtree(key: key, child: child) : child;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusService.dispose();
    _stopConfirmTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The OS may have frozen us (battery optimisation) and suspended the poll
    // timer. On return to the foreground, re-seed cloud liveness and poll
    // immediately so a stale 'offline' tile refreshes at once instead of waiting
    // up to a full cycle - and, crucially, so a printer powered back on while we
    // were away isn't held offline by a stale liveness verdict. The app-level
    // observer (app.dart) kicks the mDNS browse in parallel.
    if (state == AppLifecycleState.resumed) _statusService.resumePoll();
  }

  Future<void> _handlePause() async {
    final ok = await _controlService.sendAction('pause');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).tilePauseFailed),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleResume() async {
    final ok = await _controlService.sendAction('resume');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).tileResumeFailed),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleStop() {
    final isIdle = _status.state != 'printing' && _status.state != 'paused';
    if (isIdle) {
      // Firmware restart when idle/error - brings Klipper back to ready state.
      _controlService.sendAction('firmware_restart');
      return;
    }
    if (_stopConfirmPending) {
      _stopConfirmTimer?.cancel();
      setState(() => _stopConfirmPending = false);
      _controlService.sendAction('cancel');
    } else {
      setState(() => _stopConfirmPending = true);
      _stopConfirmTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _stopConfirmPending = false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).tileStopAgainToCancel),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Emergency stop - fired by a DOUBLE-tap on the tile's red triangle (a
  /// single tap is swallowed, so a stray touch can't halt a print). No confirm
  /// dialog: the double-tap IS the guard. Buzzes on fire; a snackbar surfaces
  /// only a failure to reach the printer. The printer drops to a shutdown/error
  /// state afterwards, where the tile's firmware-restart button recovers it.
  Future<void> _handleEmergencyStop() async {
    HapticFeedback.heavyImpact();
    final ok = await _controlService.sendAction('emergency_stop');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).tileEmergencyStopFailed),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Firmware restart - the recovery shown after an emergency stop (the triangle
  /// becomes a restart button while Klipper is shut down). Single tap; it's not
  /// destructive. Deliberately NOT automatic: a shutdown can point at a real
  /// problem worth checking before bringing the machine back.
  Future<void> _handleFirmwareRestart() async {
    HapticFeedback.mediumImpact();
    await _controlService.sendAction('firmware_restart');
  }

  /// Maps the current status to an overlay state, or null when the tile
  /// has a real reading to show.
  String? _overlayState(PrinterStatus s) {
    if (s.state == 'connecting')   return 'connecting';
    if (s.state == 'starting_up')  return 'starting_up';
    if (s.state == 'waiting')      return 'waiting';
    if (s.connection == PrinterConnection.offline) return 'offline';
    return null;
  }

  /// Wraps the webcam square for the tile's layout context. In the masonry grid
  /// (the default) the cell height is unbounded, so the bare square sets the
  /// height. In the manual-reorder grid the cell is a fixed height, so a loose
  /// Flexible lets a busy tile yield a few pixels instead of overflowing.
  Widget _webcamCell(Widget square) =>
      widget.bounded ? Flexible(fit: FlexFit.loose, child: square) : square;

  /// Whether the preheat / heat-soak sheet can be opened for this tile: online
  /// and idle - the same states the Macros button is offered on - so Klipper can
  /// accept SET_HEATER_TEMPERATURE and we never fight a running print.
  bool get _canPreheat =>
      _status.connection != PrinterConnection.offline &&
      (_status.state == 'standby' ||
       _status.state == 'complete' ||
       _status.state == 'cancelled');

  /// Wrap the name + temperature block so a long-press anywhere on it opens the
  /// preheat sheet - but only when [_canPreheat]; otherwise it renders plainly
  /// and a press does nothing (a normal tap still opens the printer page via the
  /// tile's InkWell). The big target replaces the old chips-only one, which got
  /// fiddly once the display-size slider stacks each chip into a narrow column.
  Widget _preheatable(Widget chips) {
    if (!_canPreheat) return chips;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        showPreheatSheet(
          context,
          widget.printer,
          hotendTarget: _status.hotendTarget,
          bedTarget: _status.bedTarget,
          toolheads: _status.toolheads,
        );
      },
      child: chips,
    );
  }

  /// The E-STOP triangle, or the firmware-restart button when Klipper is shut
  /// down. Shared by the single-hotend row and the multi-toolhead footer. The
  /// E-STOP carries the tutorial anchor (a no-op on non-tutorial tiles).
  Widget _estopWidget(AppLocalizations l) {
    if (_status.klippyShutdown) {
      return _RestartButton(
        tooltip: l.tileFirmwareRestart,
        onTap: _handleFirmwareRestart,
      );
    }
    return _anchor(
      TutorialAnchors.instance.estop,
      _EstopButton(
        tooltip: l.tileEmergencyStop,
        onFire: _handleEmergencyStop,
      ),
    );
  }

  /// Shared temperature row for EVERY tile (single- and multi-toolhead). All
  /// chips sit in one Wrap, so they flow onto as many rows as the tile width
  /// needs at ONE global size (the display-size slider) - they never shrink
  /// per-tile, which used to make a busy tile's temps smaller than a quiet
  /// one's. When the tile is too narrow to fit even one horizontal chip the
  /// chips stack (icon over value, much narrower) instead of clipping, so
  /// nothing overflows into the E-STOP, which stays pinned at the right.
  ///
  /// [chips] is a builder because whether the chips stack depends on the width
  /// the LayoutBuilder measures.
  Widget _tempRow(
    AppLocalizations l,
    List<Widget> Function(bool stack) chips,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1.0);
        // Width the Wrap has after reserving the E-STOP (its ring tracks the
        // scale) plus the gap before it.
        final wrapWidth = constraints.maxWidth - (24 * scale + 8);
        // Stack when the font is already large (the historic threshold) OR when
        // a horizontal chip would not fit the row - a labelled toolhead chip is
        // the widest, roughly 66px * scale. Stacking collapses a chip to its
        // widest single element (the value), which fits any tile, so this kills
        // the clip WITHOUT shrinking; size stays globally controlled.
        final stack = scale >= 1.15 || wrapWidth < 90 * scale;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: chips(stack),
              ),
            ),
            const SizedBox(width: 8),
            _estopWidget(l),
          ],
        );
      },
    );
  }

  /// The single-toolhead temperature row: hotend, bed, and (if present) chamber
  /// flowed through [_tempRow]. The [_anchor] calls are no-ops on every tile
  /// except the one the tutorial spotlights.
  Widget _singleToolheadTemps(AppLocalizations l) {
    return _tempRow(l, (stack) => [
      _anchor(
        TutorialAnchors.instance.tempHotend,
        _TempChip(
          icon: Icons.whatshot,
          color: Colors.deepOrange,
          temp: _status.hotendTemp,
          target: _status.hotendTarget,
          stack: stack,
        ),
      ),
      _anchor(
        TutorialAnchors.instance.tempBed,
        _TempChip(
          icon: Icons.bed,
          color: Colors.blue,
          temp: _status.bedTemp,
          target: _status.bedTarget,
          stack: stack,
        ),
      ),
      if (_status.chamberTemp > 0)
        _anchor(
          TutorialAnchors.instance.tempChamber,
          _TempChip(
            icon: Icons.sensor_window,
            color: Colors.teal,
            temp: _status.chamberTemp,
            target: _status.chamberTarget,
            stack: stack,
          ),
        ),
    ]);
  }

  /// The multi-toolhead temperature row: a flame + `T{n}` + temperature chip per
  /// tool, then bed and (if present) chamber, all in one [_tempRow] Wrap so they
  /// flow onto as many rows as the tile width needs (2 tools on a wide tile = one
  /// line; 6 on a narrow tile = a 3x2-ish grid), every chip the same global size.
  /// Bed and chamber are independent chips, so they wrap naturally with the
  /// tools. Every detected tool shows heated or not - a heating tool keeps the
  /// orange flame, idle ones go grey, the active tool's label is bold. Only
  /// reached when `_status.toolheads.length > 1`.
  Widget _multiToolheadTemps(AppLocalizations l) {
    return _tempRow(l, (stack) => [
      for (final t in _status.toolheads)
        t.index == 0
            ? _anchor(
                TutorialAnchors.instance.tempHotend,
                _ToolheadChip(tool: t, stack: stack),
              )
            : _ToolheadChip(tool: t, stack: stack),
      _anchor(
        TutorialAnchors.instance.tempBed,
        _TempChip(
          icon: Icons.bed,
          color: Colors.blue,
          temp: _status.bedTemp,
          target: _status.bedTarget,
          stack: stack,
        ),
      ),
      if (_status.chamberTemp > 0)
        _anchor(
          TutorialAnchors.instance.tempChamber,
          _TempChip(
            icon: Icons.sensor_window,
            color: Colors.teal,
            temp: _status.chamberTemp,
            target: _status.chamberTarget,
            stack: stack,
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    // The first tile drives the live tutorial's faked state: react to each step.
    if (widget.anchorForTutorial) {
      ref.listen<TutorialState>(
        tutorialControllerProvider,
        (_, next) => _applyDemoForStep(next),
      );
    }

    // Colours used for the connection indicator throughout the tile.
    final connColor = switch (_status.connection) {
      PrinterConnection.local   => Colors.green,
      PrinterConnection.remote  => Colors.orange,
      PrinterConnection.offline => Colors.transparent,
    };

    // Tiles with no live Klipper reading - offline, the Pi up but Klipper not
    // responding ("Printer idle" / waiting), or still connecting - have no real
    // temperatures, so they collapse to just the name (the 0°/0° band was
    // meaningless) and let the placeholder feed fill the whole tile, with no
    // dead band beneath the name. Tiles with a real reading keep the square +
    // temps below.
    final noLiveReading = _overlayState(_status) != null;

    final op = widget.tileOpacity;

    // Webcam hidden for this printer → render the compact, band-only tile that
    // the masonry grid packs tightly beneath the full tiles (no camera square).
    if (widget.printer.hideWebcam) {
      return _buildCompactTile(theme, l, connColor, noLiveReading, op);
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      // Custom-theme tile opacity: when < 1 the card goes see-through (drop the
      // M3 elevation tint + shadow so the alpha reads cleanly). The webcam image
      // inside stays opaque, so only the card/stats area shows the background.
      color: op < 1.0
          ? theme.colorScheme.surfaceContainerLow.withValues(alpha: op)
          : null,
      surfaceTintColor: op < 1.0 ? Colors.transparent : null,
      elevation: op < 1.0 ? 0 : null,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          // Size to content so the masonry grid can measure the tile's real
          // height (square + band) and pack the columns by it.
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Connection accent bar (clipped to card corners at top) ────
            Container(
              key: widget.anchorForTutorial
                  ? TutorialAnchors.instance.connectionBar
                  : null,
              height: 3,
              color: connColor,
            ),

            // ── Webcam ───────────────────────────────────────────────────
            // A fixed 1:1 square so the feed always reads cleanly, independent
            // of the status text below it. The masonry grid sizes each tile to
            // its own height - this square (= tile width) plus the status band -
            // and packs the columns by height, so a full tile stands about a
            // square taller than a compact (webcam-hidden) one. BoxFit.cover
            // crops to fill the square; no distortion. Normally a plain
            // AspectRatio - the masonry cell's height is unbounded, where a Flex
            // child would throw, so the square defines the height. In manual-
            // reorder mode the tile sits in a fixed-height cell instead, so
            // _webcamCell wraps it in a loose Flexible (bounded) to let a busy
            // tile give height back rather than overflow.
            _anchor(
                TutorialAnchors.instance.webcam,
                _webcamCell(AspectRatio(
              aspectRatio: 1.0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  WebcamView(
                    webcamSnapshotUrl: _status.webcamSnapshotUrl,
                    webcamFlipH:     _status.webcamFlipH,
                    webcamFlipV:     _status.webcamFlipV,
                    webcamRotation:  _status.webcamRotation,
                    webcamTargetFps: _status.webcamTargetFps,
                    webcamIsExternal: _status.webcamIsExternal,
                    uiType: _uiType,
                  ),
                  // Overlay shown while we don't yet have a usable
                  // status (first poll in flight, Pi waiting for its first
                  // heartbeat, or settled offline). When the UI type is
                  // known we fall through to the logo + a small status
                  // hint instead of a generic spinner - so a powered-off
                  // K3 still looks like the K3, not a blank loading tile.
                  if (_overlayState(_status) case final overlay?)
                    _ConnectionProbe(state: overlay, uiType: _uiType),
                  // ── Status badge ───────────────────────────────────────────
                  // Only shown when connected - the probe overlay provides the
                  // status context while offline/connecting.
                  if (_status.connection != PrinterConnection.offline &&
                      _status.state != 'connecting')
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _StatusBadge(
                        printer: widget.printer,
                        status: _status,
                        onCleared: _statusService.pollNow,
                      ),
                    ),
                  // Camera config gear (top-right). Lets the user point this
                  // tile at an external camera (e.g. a phone webcam). The
                  // button watches the "show camera icons" setting and renders
                  // nothing when it's off, so it never overlaps the feed.
                  // Top-right cluster: the camera-config gear (when its
                  // setting is on) and the lighting bulb (when this printer
                  // has lighting configured). The bulb sits in the corner; a
                  // tap runs the on/off/toggle macro and it glows amber when
                  // the light is on.
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CameraConfigButton(
                          printer: widget.printer,
                          onApplied: _statusService.pollNow,
                        ),
                        if (_hasLighting(widget.printer)) ...[
                          const SizedBox(width: 6),
                          _LightBulbButton(
                            printer: widget.printer,
                            status: _status,
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Expand-to-full-screen camera (bottom-right). Shown only
                  // when there's actually a live feed to open. Pushes the same
                  // native camera view the printer page uses (pinch-to-zoom,
                  // LAN-direct / tunnel-proxied snapshot URL) - a one-tap
                  // shortcut from the dashboard. The tile's own tap still opens
                  // the printer page; this button absorbs its own tap.
                  if ((_status.webcamSnapshotUrl ?? '').isNotEmpty)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: _CameraExpandButton(printer: widget.printer),
                    ),
                  // Power on/off (bottom-left) - shown only when this printer
                  // has a Moonraker power device. Works even when the printer
                  // is off (Moonraker stays up), so you can switch it on from
                  // an idle/offline tile; a tap asks to confirm first.
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: _PowerButton(
                      printer: widget.printer,
                      status: _status,
                    ),
                  ),
                ],
              ),
            ))),

            // ── Progress + buttons in ONE row ────────────────────────────
            // Hide action row when there's nothing to act on: offline,
            // Pi reachable but Klipper not responding ('waiting'), first
            // poll still in flight, Pi not heartbeating yet, or Klipper
            // itself still booting. TODO(v0.5+): show a "wake printer"
            // button in this row when state == 'waiting'.
            if (_status.state != 'offline' &&
                _status.state != 'connecting' &&
                _status.state != 'starting_up' &&
                _status.state != 'waiting' &&
                _status.state != 'startup')
              GestureDetector(
                onTap: () {}, // absorb - don't navigate when tapping controls
                behavior: HitTestBehavior.opaque,
                child: _ActionRow(
                  status: _status,
                  stopConfirmPending: _stopConfirmPending,
                  onPause: _handlePause,
                  onResume: _handleResume,
                  onStop: _handleStop,
                  onOpenFiles: () =>
                      showGcodeFilesSheet(context, widget.printer),
                  onOpenMacros: () => showMacrosSheet(context, widget.printer),
                ),
              ),

            // ── Name + temperatures ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The whole name + temperature block is one big long-press
                  // target: press and hold anywhere on the name or the hotend /
                  // bed / chamber readouts to open the preheat / heat-soak sheet
                  // (online + idle only). The E-STOP / restart button at the end
                  // swallows its own long-press, so it stays out of the gesture.
                  _anchor(
                    TutorialAnchors.instance.preheatArea,
                    _preheatable(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Printer name + connection label on the same row
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.printer.name,
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_status.connection != PrinterConnection.offline) ...[
                            const SizedBox(width: 4),
                            // The Local/Tunnel label + its icon, grouped so the
                            // tutorial can spotlight it (it flips to Tunnel + a
                            // cloud icon when the demo fakes tunnel mode).
                            _anchor(
                              TutorialAnchors.instance.connectionLabel,
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _status.connection == PrinterConnection.local
                                        ? Icons.wifi_rounded
                                        : Icons.cloud_outlined,
                                    size: 11,
                                    color: connColor,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    _status.connection == PrinterConnection.local
                                        ? l.tileLocal
                                        : l.tileTunnel,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: connColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  // v0.5.0: when on LAN, a small tunnel-status pip
                                  // (connecting vs ready) next to the Local badge.
                                  if (_status.connection == PrinterConnection.local)
                                    _anchor(
                                      TutorialAnchors.instance.tunnelDot,
                                      _TunnelStatusDot(ready: _status.tunnelReady),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      // Live temperatures - shown only when there's a real
                      // reading. Offline / waiting / connecting tiles collapse to
                      // just the name (no meaningless 0°/0° row), like the K3.
                      if (!noLiveReading) ...[
                        const SizedBox(height: 4),
                        _status.toolheads.length > 1
                            ? _multiToolheadTemps(l)
                            : _singleToolheadTemps(l),
                      ],
                    ],
                  ))),
                  if (_status.filename != null && _status.isPrinting)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _status.filename!,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact dashboard tile for a printer whose webcam is hidden
  /// ([PrinterConfig.hideWebcam]). Drops the 1:1 webcam square entirely and
  /// shows just the name plus a single status line - live print progress, live
  /// temperatures, or a connection-state label - so the tile collapses to about
  /// the slim band a full tile carries beneath its square. The masonry grid then
  /// packs these tightly (two compact tiles fit under one full one). A settings
  /// gear stays in reach so the webcam can always be switched back on from here,
  /// even when the global camera-config icons are off.
  Widget _buildCompactTile(
    ThemeData theme,
    AppLocalizations l,
    Color connColor,
    bool noLiveReading,
    double op,
  ) {
    final printing = _status.state == 'printing' || _status.state == 'paused';
    return Card(
      clipBehavior: Clip.antiAlias,
      color: op < 1.0
          ? theme.colorScheme.surfaceContainerLow.withValues(alpha: op)
          : null,
      surfaceTintColor: op < 1.0 ? Colors.transparent : null,
      elevation: op < 1.0 ? 0 : null,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Connection accent bar (matches the full tile).
            Container(
              key: widget.anchorForTutorial
                  ? TutorialAnchors.instance.connectionBar
                  : null,
              height: 3,
              color: connColor,
            ),
            Padding(
              // Right inset matches the full tile (10) so the connection icons
              // and the E-STOP line up with a full tile stacked above/below.
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The name + temperature block is one big long-press target
                  // (same as the full tile): press and hold anywhere on the name
                  // or the hotend / bed / chamber readouts to open the preheat /
                  // heat-soak sheet (online + idle only). The power button and the
                  // E-STOP / restart button each swallow their own long-press, so
                  // they stay out of the gesture.
                  _preheatable(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Name + connection label - same as the full tile: wifi/cloud
                      // icon + Local/Tunnel label + the remote-tunnel status dot. A
                      // power button leads the row (compact tiles have no webcam to
                      // host it); it self-hides when the printer has no power control.
                      Row(
                        children: [
                          _PowerButton(
                            printer: widget.printer,
                            status: _status,
                            onSurface: true,
                          ),
                          Expanded(
                            child: Text(
                              widget.printer.name,
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_status.connection != PrinterConnection.offline) ...[
                            const SizedBox(width: 4),
                            Icon(
                              _status.connection == PrinterConnection.local
                                  ? Icons.wifi_rounded
                                  : Icons.cloud_outlined,
                              size: 11,
                              color: connColor,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _status.connection == PrinterConnection.local
                                  ? l.tileLocal
                                  : l.tileTunnel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: connColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_status.connection == PrinterConnection.local)
                              _TunnelStatusDot(ready: _status.tunnelReady),
                          ],
                        ],
                      ),
                      // Print progress - kept so a compact tile still shows it.
                      if (printing)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: _CompactProgress(status: _status),
                        ),
                      // Live temperatures + E-STOP on the SAME row (same as the
                      // full tile) - shown whenever there's a live reading,
                      // including mid-print, so the E-STOP stays reachable.
                      if (!noLiveReading)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: _status.toolheads.length > 1
                              ? _multiToolheadTemps(l)
                              : _singleToolheadTemps(l),
                        ),
                    ],
                  )),
                  // Connection-state label when there's nothing live to show.
                  if (noLiveReading)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: _CompactStateLabel(state: _overlayState(_status)!),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action row: progress bar / status label + buttons side-by-side ────────────

class _ActionRow extends StatelessWidget {
  final PrinterStatus status;
  final bool stopConfirmPending;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenMacros;

  const _ActionRow({
    required this.status,
    required this.stopConfirmPending,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onOpenFiles,
    required this.onOpenMacros,
  });

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final l        = AppLocalizations.of(context);
    final printing = status.state == 'printing';
    final paused   = status.state == 'paused';
    final active   = printing || paused;
    final color    = paused ? Colors.orange : theme.colorScheme.primary;
    // "Ready to accept a print": online and idle/finished - not while printing
    // or paused (hide the folder then), and not on error/startup where Klipper
    // can't take a job yet. So it disappears mid-print and returns on complete.
    final ready = !active &&
        (status.state == 'standby' ||
         status.state == 'complete' ||
         status.state == 'cancelled');
    // Macros are offered on idle/finished tiles (standby / complete /
    // cancelled), beside the folder button; a tap runs after a confirm. They
    // hide while printing/paused so the progress bar keeps its width - the
    // buttons that matter then are pause/resume + stop, not a macro launcher.
    final canRunMacros = status.state == 'standby' ||
        status.state == 'complete' ||
        status.state == 'cancelled';

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Left: progress bar (active) OR status label (idle) ─────────
          Expanded(
            child: active
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            paused ? l.tilePaused : l.tilePrinting,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: color),
                          ),
                          Text(
                            '${(status.progress * 100).round()}%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: status.progress,
                          minHeight: 7,
                          backgroundColor: Colors.black26,
                          color: color,
                        ),
                      ),
                    ],
                  )
                : _IdleLabel(status: status),
          ),

          const SizedBox(width: 8),

          // ── Right: icon buttons ────────────────────────────────────────
          if (paused)
            _Btn(
              icon: Icons.play_arrow_rounded,
              color: Colors.green,
              tooltip: l.tileResume,
              onTap: onResume,
            ),
          if (printing)
            _Btn(
              icon: Icons.pause_rounded,
              color: Colors.orange,
              tooltip: l.tilePause,
              onTap: onPause,
            ),
          // Print a stored file - only when online and ready to accept a job.
          if (ready)
            _Btn(
              icon: Icons.folder_open_rounded,
              color: theme.colorScheme.primary,
              tooltip: l.tileOpenFiles,
              onTap: onOpenFiles,
            ),
          // Run a Klipper macro - idle/finished tiles only (hidden mid-print).
          if (canRunMacros) ...[
            const SizedBox(width: 4),
            _Btn(
              icon: Icons.code_rounded,
              color: theme.colorScheme.primary,
              tooltip: l.tileMacros,
              onTap: onOpenMacros,
            ),
          ],
          // Stop while printing/paused (cancel the job); firmware-restart ONLY
          // when Klipper has errored - the one time a restart is the fix. Hidden
          // across the healthy idle states (Ready / complete / cancelled) so a
          // resting tile stays uncluttered; the recovery action returns the
          // moment something actually goes wrong.
          if (active || status.state == 'error') ...[
            const SizedBox(width: 4),
            _Btn(
              icon: active
                  ? (stopConfirmPending
                      ? Icons.stop_circle_rounded
                      : Icons.stop_rounded)
                  : Icons.restart_alt,
              color: active
                  ? (stopConfirmPending ? Colors.red : Colors.redAccent)
                  : Colors.orange,
              tooltip: active
                  ? (stopConfirmPending ? l.tileConfirmStop : l.tileStopPrint)
                  : l.tileFirmwareRestart,
              onTap: onStop,
            ),
          ],
        ],
      ),
    );
  }
}

class _IdleLabel extends StatelessWidget {
  final PrinterStatus status;
  const _IdleLabel({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final (label, icon, color) = switch (status.state) {
      'complete'  => (l.tilePrintComplete, Icons.check_circle_outline,  Colors.teal),
      'cancelled' => (l.tilePrintCancelled, Icons.cancel_outlined,      Colors.blueGrey),
      'error'     => (l.tilePrinterError,  Icons.error_outline,        Colors.red),
      'startup'   => (l.tileKlipperStarting, Icons.hourglass_empty,     Colors.blueGrey),
      _           => (l.tileReady,           Icons.check_circle_outline, Colors.blueGrey),
    };
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        // Flexible + ellipsis so a longer label ("Print complete", and longer
        // still in other languages) shrinks instead of overflowing the row
        // when the folder + restart buttons share a narrow multi-column tile.
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Compact-tile pieces (webcam-hidden printers) ──────────────────────────────

/// Slim print-progress readout for a compact tile: "Printing"/"Paused" + the
/// percentage above a thin bar. Mirrors the full tile's action-row progress.
class _CompactProgress extends StatelessWidget {
  final PrinterStatus status;
  const _CompactProgress({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final l      = AppLocalizations.of(context);
    final paused = status.state == 'paused';
    final color  = paused ? Colors.orange : theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              paused ? l.tilePaused : l.tilePrinting,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
            Text(
              '${(status.progress * 100).round()}%',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: status.progress,
            minHeight: 6,
            backgroundColor: Colors.black26,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Connection-state label for a compact tile with no live reading (offline /
/// connecting / starting up / waiting). Reuses the same strings the full tile's
/// [_ConnectionProbe] shows, so the wording stays consistent across both.
class _CompactStateLabel extends StatelessWidget {
  final String state; // 'offline' | 'connecting' | 'starting_up' | 'waiting'
  const _CompactStateLabel({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final (label, icon) = switch (state) {
      'offline'     => (l.tileOffline,    Icons.wifi_off),
      'starting_up' => (l.tileStartingUp, Icons.hourglass_empty),
      'waiting'     => (l.tileConnected,  Icons.hourglass_empty),
      _             => (l.tileConnecting, Icons.sync),
    };
    return Row(
      children: [
        Icon(icon, size: 13, color: Colors.blueGrey),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.blueGrey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Small icon button ─────────────────────────────────────────────────────────

class _Btn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _Btn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

/// Red warning-triangle emergency-stop button shown under the connection label.
/// DOUBLE-tap fires [onFire] (Klipper M112) immediately - there is no confirm
/// dialog; the double-tap is the safety. A single tap is swallowed
/// (HitTestBehavior.opaque + a no-op onTap) so a stray touch neither halts the
/// print nor opens the printer screen.
class _EstopButton extends ConsumerWidget {
  final String tooltip;
  final VoidCallback onFire;
  const _EstopButton({required this.tooltip, required this.onFire});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The ring + icon follow the Custom theme's E-stop colour when that theme
    // is active; otherwise the classic emergency red.
    final c = ref.watch(themeModeProvider) == AppThemeMode.custom
        ? ref.watch(customThemeProvider).estop
        : Colors.red;
    // Scale the ring with the display-size slider so it tracks its icon (which
    // scales via applyTextScaling). Base kept compact - it was oversized and
    // frozen before.
    final ring = MediaQuery.textScalerOf(context).scale(24);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // swallow single taps - must not fire or navigate
        onLongPress: () {}, // swallow long-press too - stays out of the preheat gesture
        onDoubleTap: onFire,
        child: Container(
          width: ring,
          height: ring,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: c, width: 2),
          ),
          child: Icon(Icons.warning_rounded, color: c, size: 14),
        ),
      ),
    );
  }
}

/// Recovery button shown in place of the E-STOP triangle once Klipper is shut
/// down (e.g. after an emergency stop): a single tap fires FIRMWARE_RESTART to
/// bring the machine back online. Single tap, not double - recovery isn't
/// destructive, so it doesn't need the accidental-press guard.
class _RestartButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;
  const _RestartButton({required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: () {}, // swallow long-press - stays out of the preheat gesture
        child: Container(
          width: MediaQuery.textScalerOf(context).scale(24),
          height: MediaQuery.textScalerOf(context).scale(24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.orange, width: 2),
          ),
          child: const Icon(Icons.restart_alt, color: Colors.orange, size: 14),
        ),
      ),
    );
  }
}

// ── Connection probe overlay ──────────────────────────────────────────────────
//
// Shown in the webcam area when the tile has nothing live to render -
// first poll in flight, Pi not heartbeating yet, or settled offline.
//
// When the web UI type is known (persisted on the printer config after the
// first successful poll), the overlay renders that logo as the background
// so a powered-off K3 still looks like the K3, instead of a blank spinner
// tile. When the UI type is unknown we fall back to a generic spinner /
// wifi-off icon.

class _ConnectionProbe extends StatelessWidget {
  /// 'connecting'  - first poll in flight
  /// 'starting_up' - Pi hasn't heartbeated to Supabase yet
  /// 'waiting'     - Pi reachable but its printer-side stack isn't
  ///                 (K3 printer power off, Klipper not running, etc.)
  /// 'offline'     - settled, nothing answers on any path
  final String  state;
  final String? uiType; // 'mainsail' | 'fluidd' | null

  const _ConnectionProbe({required this.state, this.uiType});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hasLogo = uiType == 'mainsail' || uiType == 'fluidd';

    final label = switch (state) {
      'offline'     => l.tileOffline,
      'starting_up' => l.tileStartingUp,
      'waiting'     => l.tileConnected,
      _             => l.tileConnecting,
    };
    final sub = switch (state) {
      'offline'     => l.tilePrinterUnreachable,
      'starting_up' => l.tileWaitingForHeartbeat,
      'waiting'     => l.tilePrinterIdle,
      _             => l.tileReachingPrinter,
    };

    // Top accent: spinner for "in flight" states, wifi-off when offline,
    // nothing for 'waiting' (the logo + Connected label carries it).
    // When the logo is showing we always skip the accent - the logo is
    // the visual focus.
    Widget? accent;
    if (!hasLogo) {
      if (state == 'offline') {
        accent = const Icon(Icons.wifi_off, size: 32, color: Colors.white30);
      } else if (state == 'connecting' || state == 'starting_up') {
        accent = const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white54,
          ),
        );
      }
    }

    // With a logo, dim less so the logo reads through.
    final backdrop = hasLogo ? Colors.black54 : Colors.black87;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: backdrop),
        if (hasLogo)
          Center(
            child: Opacity(
              opacity: 0.4,
              child: SvgPicture.asset(
                uiType == 'mainsail'
                    ? 'assets/icons/mainsail_logo.svg'
                    : 'assets/icons/fluidd_logo.svg',
                width: 130,
                fit: BoxFit.contain,
              ),
            ),
          ),
        // Status text - at the bottom when a logo is showing, centered
        // when it isn't.
        Align(
          alignment: hasLogo ? Alignment.bottomCenter : Alignment.center,
          child: Padding(
            padding: EdgeInsets.only(bottom: hasLogo ? 10 : 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (accent != null) ...[
                  accent,
                  const SizedBox(height: 10),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Remote (tunnel) status dot ────────────────────────────────────────────────
//
// Shown next to the "Local" label so the user can see, at a glance, whether
// remote access is also ready while they're on the home network:
//   • amber cloud-sync  - the Pi's tunnel isn't registered with the cloud yet
//     (fresh pair, or Pi still booting cloudflared). Remote won't work until
//     this resolves, but Local already does - so the tile is usable now.
//   • green cloud-done  - the cloud knows the tunnel URL; remote access works.
// This is the "pairing icon → green tick" affordance: pairing happens on-LAN,
// the tile goes Local instantly, and the tunnel finishes establishing in the
// background without blocking anything.

class _TunnelStatusDot extends StatelessWidget {
  final bool ready;
  const _TunnelStatusDot({required this.ready});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Tooltip(
        message: ready ? l.tileRemoteReady : l.tileRemoteConnecting,
        child: Icon(
          ready ? Icons.cloud_done_rounded : Icons.cloud_sync_outlined,
          size: 11,
          color: ready ? Colors.green : Colors.orangeAccent,
        ),
      ),
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatefulWidget {
  final PrinterConfig printer;
  final PrinterStatus status;

  /// Called after a successful clear so the tile re-polls and the badge drops
  /// back to "Idle" without waiting a full cycle.
  final VoidCallback onCleared;

  const _StatusBadge({
    required this.printer,
    required this.status,
    required this.onCleared,
  });

  @override
  State<_StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<_StatusBadge> {
  late final PrintControlService _control = PrintControlService(widget.printer);
  bool _clearing = false;

  /// The two terminal states that leave a stuck badge with nothing else to act
  /// on - both cleared by SDCARD_RESET_FILE → standby. 'error' is left alone: it
  /// keeps the firmware-restart button and may need a deliberate reset.
  bool get _dismissable =>
      widget.status.state == 'complete' || widget.status.state == 'cancelled';

  Future<void> _clear() async {
    if (_clearing) return;
    // No confirm dialog: the × only shows on the terminal Done/Cancelled badge
    // (never while printing or idle), so a stray tap can't disturb a live job -
    // it just re-runs the harmless reset. One tap dismisses, as it should.
    final l = AppLocalizations.of(context);
    setState(() => _clearing = true);
    final ok = await _control.resetPrintState();
    if (!mounted) return;
    setState(() => _clearing = false);
    if (ok) {
      widget.onCleared(); // re-poll: 'complete'/'cancelled' → 'standby' (Idle)
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.tileClearJobFailed),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (label, color) = switch (widget.status.state) {
      'printing'   => (l.tilePrinting,      Colors.green),
      'paused'     => (l.tilePaused,        Colors.orange),
      'standby'    => (l.tileIdle,          Colors.blueGrey),
      'complete'   => (l.tileDone,          Colors.teal),
      'cancelled'  => (l.tileCancelled,     Colors.blueGrey),
      'error'      => (l.tileError,         Colors.red),
      // Klipper is reachable but hasn't finished initialising yet
      'startup'    => (l.tileStarting,      Colors.blueGrey),
      // Before the first poll completes
      'connecting' => (l.tileConnectingBadge, Colors.blueGrey),
      _            => (l.tileOffline,       Colors.black54),
    };
    final pill = Container(
      padding: EdgeInsets.only(
          left: 8, right: _dismissable ? 5 : 8, top: 3, bottom: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          // A small × turns a finished/cancelled badge into a dismiss
          // affordance: tap it to clear the job and drop the printer to Idle.
          if (_dismissable) ...[
            const SizedBox(width: 3),
            _clearing
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.6, color: Colors.white),
                  )
                : const Icon(Icons.close_rounded,
                    size: 14, color: Colors.white),
          ],
        ],
      ),
    );
    if (!_dismissable) return pill;
    return Tooltip(
      message: l.tileClearJobTooltip,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _clearing ? null : _clear,
          child: pill,
        ),
      ),
    );
  }
}

// ── Temperature chip ──────────────────────────────────────────────────────────

class _TempChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double temp;
  final double target;

  /// When non-null, forces stacked (true) or horizontal (false) layout - the
  /// temp row computes it from the tile width + display-size so every chip on a
  /// tile stacks together when the tile is too narrow, never shrinking. Null
  /// falls back to the display-size-only threshold.
  final bool? stack;

  const _TempChip({
    required this.icon,
    required this.color,
    required this.temp,
    required this.target,
    this.stack,
  });

  @override
  Widget build(BuildContext context) {
    // Temps must stay legible on BOTH themes. The old white-family colours were
    // invisible on the Light theme (white text + icons on a near-white card).
    // Use the same neutral blueGrey as the "Ready" idle label above the name -
    // it reads on light and dark alike. A heating element keeps its accent
    // colour (orange/blue/teal) on the icon while it has a target set.
    const neutral = Colors.blueGrey;
    final muted   = neutral.withValues(alpha: 0.7);
    final iconWidget = Icon(icon, size: 13, color: target > 0 ? color : muted);
    final valueWidget = Text(
      '${temp.toStringAsFixed(0)}°',
      style: TextStyle(
        fontSize: 12,
        color: target > 0 ? neutral : muted,
      ),
    );

    // With the display-size slider turned up, three "icon value" chips in one
    // row overflow a narrow tile. Past a threshold, stack each chip vertically
    // (icon over value) so the three read as two tidy rows - icons on top,
    // values beneath - instead of running off the edge.
    final stacked = stack ?? (MediaQuery.textScalerOf(context).scale(1.0) >= 1.15);
    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [iconWidget, const SizedBox(height: 1), valueWidget],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [iconWidget, const SizedBox(width: 2), valueWidget],
    );
  }
}

// ── Toolhead chip (multi-extruder printers) ───────────────────────────────────
//
// One tool's readout in the grid layout: a flame + T{index} + temperature.
// Follows [_TempChip]'s colour rules (a neutral blueGrey that reads on both
// the light and dark themes; the flame keeps its orange only while that tool
// has a target, going grey when the tool is idle). The tool number is bold
// when it's Klipper's currently-selected tool. Stacks icon-over-text past the
// same display-size threshold [_TempChip] uses.

class _ToolheadChip extends StatelessWidget {
  final ToolheadTemp tool;

  /// See [_TempChip.stack] - forces stacked/horizontal, else display-size only.
  final bool? stack;

  const _ToolheadChip({required this.tool, this.stack});

  @override
  Widget build(BuildContext context) {
    const neutral = Colors.blueGrey;
    final muted   = neutral.withValues(alpha: 0.7);
    final heating = tool.target > 0;

    final iconWidget = Icon(Icons.whatshot,
        size: 13, color: heating ? Colors.deepOrange : muted);
    final labelWidget = Text(
      'T${tool.index}',
      style: TextStyle(
        fontSize: 11,
        fontWeight: tool.active ? FontWeight.w700 : FontWeight.w500,
        color: tool.active ? neutral : muted,
      ),
    );
    final valueWidget = Text(
      '${tool.temp.toStringAsFixed(0)}°',
      style: TextStyle(
        fontSize: 12,
        color: heating ? neutral : muted,
      ),
    );

    final stacked = stack ?? (MediaQuery.textScalerOf(context).scale(1.0) >= 1.15);
    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [iconWidget, const SizedBox(height: 1), labelWidget, valueWidget],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        iconWidget,
        const SizedBox(width: 2),
        labelWidget,
        const SizedBox(width: 3),
        valueWidget,
      ],
    );
  }
}

// ── Camera config button + dialog ─────────────────────────────────────────────
//
// A small, semi-transparent gear in the corner of the webcam. Tapping it lets
// the user point this tile at a camera that isn't connected to Klipper - e.g.
// an old phone running an IP-webcam app. Watches the "show camera icons"
// setting and renders nothing when it's off, so it never overlaps the feed.

class _CameraConfigButton extends ConsumerWidget {
  final PrinterConfig printer;
  final VoidCallback onApplied;

  const _CameraConfigButton({required this.printer, required this.onApplied});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(showCameraConfigIconsProvider)) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    return Tooltip(
      message: l.cameraConfigTooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            final changed = await showCameraConfigDialog(context, printer);
            if (changed == true) onApplied();
          },
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              Icons.settings,
              size: 17,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Expand-camera button ──────────────────────────────────────────────────────
//
// A small, semi-transparent eye in the bottom-right corner of the webcam,
// rendered only when the tile has a live feed. Tapping it opens the centred
// camera overlay (pinch-to-zoom, landscape rotation, floating back arrow) over
// the same LAN-direct / tunnel-proxied snapshot URL the tile uses - as a
// one-tap shortcut straight from the dashboard, without going into the printer
// page first. Matches the corner-gear's chrome (same dark chip), eye dimmed so
// it sits quietly over the feed.

class _CameraExpandButton extends StatelessWidget {
  final PrinterConfig printer;

  const _CameraExpandButton({required this.printer});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Tooltip(
      message: l.printerCameraTooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.38),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showPrinterCameraOverlay(context, printer),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              Icons.visibility_outlined,
              size: 18,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Lighting bulb button ───────────────────────────────────────────────────
//
// A small bulb in the webcam's top-right corner, shown only when this printer
// has lighting configured (enabled + at least an on/off pair or a toggle macro
// - see [_hasLighting]). A tap runs the appropriate macro; the icon glows amber
// when the light is on and is dimmed when off. State comes from the configured
// status object's live value ([PrinterStatus.lightOn]) when set, falling back
// to tracking taps optimistically when it isn't. The tap flips the icon at once
// (optimistically) and the next poll reconciles it with reality.

/// Whether to show the bulb for [p]: lighting enabled AND a usable control path
/// (an on+off pair, or a single toggle macro).
bool _hasLighting(PrinterConfig p) {
  if (!p.lightingEnabled) return false;
  final hasPair = (p.lightOnMacro?.isNotEmpty ?? false) &&
      (p.lightOffMacro?.isNotEmpty ?? false);
  final hasToggle = p.lightToggleMacro?.isNotEmpty ?? false;
  return hasPair || hasToggle;
}

class _LightBulbButton extends StatefulWidget {
  final PrinterConfig printer;
  final PrinterStatus status;
  const _LightBulbButton({required this.printer, required this.status});

  @override
  State<_LightBulbButton> createState() => _LightBulbButtonState();
}

class _LightBulbButtonState extends State<_LightBulbButton> {
  late final PrintControlService _control = PrintControlService(widget.printer);

  /// Optimistic target set the instant the user taps, so the icon flips
  /// immediately instead of waiting up to a full poll. Cleared once the real
  /// status catches up (or on failure).
  bool? _pending;

  /// Fallback on/off when no status object is configured (no real reading), so
  /// the icon still reflects the last tap.
  bool _localOn = false;
  bool _busy = false;

  bool get _online => widget.status.connection != PrinterConnection.offline;

  bool get _displayOn {
    if (_pending != null) return _pending!;
    return widget.status.lightOn ?? _localOn;
  }

  @override
  void didUpdateWidget(covariant _LightBulbButton old) {
    super.didUpdateWidget(old);
    // Real state reached our optimistic target → hand control back to it.
    if (_pending != null && widget.status.lightOn == _pending) {
      _pending = null;
    }
  }

  Future<void> _tap() async {
    if (_busy) return;
    final p = widget.printer;
    final hasPair = (p.lightOnMacro?.isNotEmpty ?? false) &&
        (p.lightOffMacro?.isNotEmpty ?? false);
    final hasToggle = p.lightToggleMacro?.isNotEmpty ?? false;
    final hasStatus = p.lightStatusObject?.isNotEmpty ?? false;

    // On/off pair with no toggle and no status source → the real state is
    // unknown, so ask On or Off explicitly instead of guessing.
    if (hasPair && !hasToggle && !hasStatus) {
      final l = AppLocalizations.of(context);
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.lightChooseTitle(p.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.lightTurnOff),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.lightTurnOn),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      await _run(choice ? p.lightOnMacro! : p.lightOffMacro!, choice);
      return;
    }

    // Otherwise toggle by the known (or optimistic) state.
    final target = !_displayOn;
    final macro = hasPair
        ? (target ? p.lightOnMacro! : p.lightOffMacro!)
        : (p.lightToggleMacro ?? '');
    if (macro.isEmpty) return;
    await _run(macro, target);
  }

  Future<void> _run(String macro, bool target) async {
    setState(() {
      _busy = true;
      _pending = target;
      _localOn = target;
    });
    final ok = await _control.runMacro(macro);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        _pending = null;
        _localOn = !target;
      }
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).lightToggleFailed),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final on = _displayOn;
    return Tooltip(
      message: on ? l.lightTurnOff : l.lightTurnOn,
      child: Material(
        color: Colors.black.withValues(alpha: 0.38),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _online && !_busy ? _tap : null,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white70),
                  )
                : Icon(
                    on ? Icons.lightbulb : Icons.lightbulb_outline,
                    size: 18,
                    color: !_online
                        ? Colors.white24
                        : on
                            ? Colors.amber
                            : Colors.white.withValues(alpha: 0.6),
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Power on/off button ──────────────────────────────────────────────────────
//
// A power symbol in the webcam's bottom-left corner, shown only when this
// printer exposes a Moonraker power device (a [power …] section - any type).
// Crucially it works while the printer it controls is OFF, because Moonraker
// stays up: that's the "wake the printer from its idle/offline tile" case. A
// tap asks to confirm (on or off) so it isn't fired by accident; the icon glows
// green when on. Off is blocked mid-print for a locked_while_printing device.

class _PowerButton extends StatefulWidget {
  final PrinterConfig printer;
  final PrinterStatus status;

  /// When true, render for a card surface (the compact tile's name row): a plain
  /// theme-coloured icon with trailing space, instead of the dark webcam-overlay
  /// chip. Self-hides the same way when the printer has no power control.
  final bool onSurface;
  const _PowerButton({
    required this.printer,
    required this.status,
    this.onSurface = false,
  });

  @override
  State<_PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<_PowerButton> {
  late final PrintControlService _control = PrintControlService(widget.printer);

  /// The power device this tile controls (the one named "printer" if present,
  /// else the first). Null until the first successful fetch - the button renders
  /// nothing until then, so a printer with no power device shows no button.
  PowerDevice? _device;

  /// Optimistic target set the instant the user confirms, so the icon flips at
  /// once; cleared once Moonraker's real state catches up (or on failure).
  bool? _pending;
  bool _busy = false;

  bool get _isPrinting =>
      widget.status.state == 'printing' || widget.status.state == 'paused';

  bool get _displayOn => _pending ?? (_device?.on ?? false);

  /// Advanced Power Switch (v0.9.11): drive power via the configured macros
  /// instead of a Moonraker [power] device. Stateless - no device to track.
  bool get _macroMode => widget.printer.powerMacroEnabled;

  @override
  void initState() {
    super.initState();
    // Device mode fetches the Moonraker [power] device; macro mode is stateless.
    if (!_macroMode) _refresh();
  }

  @override
  void didUpdateWidget(covariant _PowerButton old) {
    super.didUpdateWidget(old);
    if (_macroMode) return; // macro mode tracks no Moonraker device
    // Re-fetch when the printer becomes reachable, or its Klipper state changes
    // (e.g. it just powered on), so the icon tracks reality without polling.
    final cameOnline = old.status.connection == PrinterConnection.offline &&
        widget.status.connection != PrinterConnection.offline;
    if (cameOnline || old.status.state != widget.status.state) {
      _refresh();
    }
    if (_pending != null && _device?.on == _pending) _pending = null;
  }

  Future<void> _refresh() async {
    final devices = await _control.listPowerDevices();
    if (!mounted || devices == null) return; // keep last-known on a blip
    PowerDevice? pick;
    for (final d in devices) {
      if (d.name.toLowerCase() == 'printer') {
        pick = d;
        break;
      }
    }
    pick ??= devices.isNotEmpty ? devices.first : null;
    setState(() {
      _device = pick;
      if (_pending != null && pick?.on == _pending) _pending = null;
    });
  }

  Future<void> _confirmAndToggle() async {
    final d = _device;
    if (d == null || _busy) return;
    final target = !_displayOn;
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            target ? l.powerConfirmOn(d.name) : l.powerConfirmOff(d.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(target ? l.powerTurnOn : l.powerTurnOff),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _pending = target;
    });
    final ok = await _control.setPowerDevice(d.name, target);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _pending = null;
    });
    if (ok) {
      _refresh(); // reconcile with Moonraker's real state
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.powerToggleFailed),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // ── Macro mode (Advanced Power Switch) ─────────────────────────────────────
  // Stateless: a toggle macro confirms then runs; an on+off pair asks On or Off
  // (the real state isn't knowable); a single-direction macro (off-only is the
  // common case - a Klipper power-off macro) confirms then runs that direction.
  Future<void> _macroTap() async {
    if (_busy) return;
    final p = widget.printer;
    final l = AppLocalizations.of(context);
    final hasToggle = p.powerToggleMacro?.isNotEmpty ?? false;
    String? macro;
    if (hasToggle) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.powerMacroToggleConfirm(p.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonOk),
            ),
          ],
        ),
      );
      if (ok != true) return;
      macro = p.powerToggleMacro;
    } else {
      final hasOn = p.powerOnMacro?.isNotEmpty ?? false;
      final hasOff = p.powerOffMacro?.isNotEmpty ?? false;
      if (hasOn && hasOff) {
        // A pair: don't assume state - let the user pick On or Off.
        final choice = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.powerMacroChooseTitle(p.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.powerTurnOff),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l.powerTurnOn),
              ),
            ],
          ),
        );
        if (choice == null) return; // cancelled
        macro = choice ? p.powerOnMacro : p.powerOffMacro;
      } else {
        // A single-direction macro: confirm, then run that one direction.
        final on = hasOn;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
                on ? l.powerConfirmOn(p.name) : l.powerConfirmOff(p.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(on ? l.powerTurnOn : l.powerTurnOff),
              ),
            ],
          ),
        );
        if (ok != true) return;
        macro = on ? p.powerOnMacro : p.powerOffMacro;
      }
    }
    if (macro == null || macro.isEmpty || !mounted) return;
    setState(() => _busy = true);
    final ok = await _control.runMacro(macro);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.powerToggleFailed),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  /// Renders the power icon with the right chrome: a plain theme-coloured icon
  /// (onSurface - the compact tile's name row) or the dark webcam-overlay chip
  /// (default). The overlay/surface icon colours are passed in so the on/off and
  /// disabled states stay readable against each backdrop.
  Widget _chrome({
    required String tooltip,
    required VoidCallback? onTap,
    required Color overlayIconColor,
    required Color surfaceIconColor,
  }) {
    final iconOrSpinner = _busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.onSurface
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white70,
            ),
          )
        : Icon(Icons.power_settings_new,
            size: 18,
            color: widget.onSurface ? surfaceIconColor : overlayIconColor);
    if (widget.onSurface) {
      // Compact tile: plain icon ahead of the name, with trailing space so it
      // reads as "[power]  name". No dark chip - it sits on the card surface.
      return Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InkWell(
            onTap: onTap,
            onLongPress: () {}, // swallow long-press - stays out of the preheat gesture
            borderRadius: BorderRadius.circular(8),
            child:
                Padding(padding: const EdgeInsets.all(2), child: iconOrSpinner),
          ),
        ),
      );
    }
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.38),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: () {}, // swallow long-press - stays out of the preheat gesture
          child:
              Padding(padding: const EdgeInsets.all(5), child: iconOrSpinner),
        ),
      ),
    );
  }

  Widget _buildMacroButton() {
    final l = AppLocalizations.of(context);
    return _chrome(
      tooltip: l.powerMacroTooltip,
      onTap: _busy ? null : _macroTap,
      overlayIconColor: Colors.white.withValues(alpha: 0.85),
      surfaceIconColor: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Advanced Power (macro) mode takes over the button when enabled.
    if (_macroMode) return _buildMacroButton();
    // Device mode: nothing until we know the printer has a power device.
    if (_device == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final on = _displayOn;
    // Moonraker refuses to cut a locked device mid-print, so grey-out the off
    // action then rather than let the tap fail.
    final blocked = on && _isPrinting && _device!.lockedWhilePrinting;
    final enabled = !_busy && !blocked;
    final cs = Theme.of(context).colorScheme;
    return _chrome(
      tooltip: blocked
          ? l.powerLockedWhilePrinting
          : (on ? l.powerTurnOff : l.powerTurnOn),
      onTap: enabled ? _confirmAndToggle : null,
      overlayIconColor: !enabled
          ? Colors.white24
          : on
              ? Colors.greenAccent
              : Colors.white.withValues(alpha: 0.6),
      surfaceIconColor: !enabled
          ? cs.onSurface.withValues(alpha: 0.3)
          : on
              ? Colors.green
              : cs.onSurfaceVariant,
    );
  }
}

/// Edit dialog for a tile's custom camera URL. Returns true if the URL was
/// changed (set or cleared), false/null if the user cancelled. Persists the
/// change to [PrinterRegistry]; the caller pokes the status service to refresh.
Future<bool?> showCameraConfigDialog(
    BuildContext context, PrinterConfig printer) {
  final controller = TextEditingController(text: printer.customCameraUrl ?? '');
  return showDialog<bool>(
    context: context,
    builder: (context) {
      final l = AppLocalizations.of(context);
      String? error;
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> apply() async {
            final raw = controller.text.trim();
            if (raw.isEmpty) {
              // Empty = clear the override (fall back to the Klipper camera).
              await PrinterRegistry.instance
                  .updateCustomCameraUrl(printer.id, null);
              if (context.mounted) Navigator.pop(context, true);
              return;
            }
            final uri = Uri.tryParse(raw);
            final ok = uri != null &&
                (uri.scheme == 'http' || uri.scheme == 'https') &&
                uri.host.isNotEmpty;
            if (!ok) {
              setState(() => error = l.cameraConfigInvalid);
              return;
            }
            await PrinterRegistry.instance
                .updateCustomCameraUrl(printer.id, raw);
            if (context.mounted) Navigator.pop(context, true);
          }

          return AlertDialog(
            title: Text(l.cameraConfigTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.cameraConfigDescription,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l.cameraConfigUrlLabel,
                    hintText: 'http://192.168.0.107:8080/video',
                    errorText: error,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (error != null) setState(() => error = null);
                  },
                  onSubmitted: (_) => apply(),
                ),
                const SizedBox(height: 10),
                Text(
                  l.cameraConfigRemoteNote,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).hintColor),
                ),
              ],
            ),
            actions: [
              if ((printer.customCameraUrl ?? '').isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await PrinterRegistry.instance
                        .updateCustomCameraUrl(printer.id, null);
                    if (context.mounted) Navigator.pop(context, true);
                  },
                  child: Text(l.cameraConfigUseDefault),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.commonCancel),
              ),
              FilledButton(
                onPressed: apply,
                child: Text(l.cameraConfigApply),
              ),
            ],
          );
        },
      );
    },
  );
}
