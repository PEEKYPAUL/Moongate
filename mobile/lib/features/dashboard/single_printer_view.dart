import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/plugin_version.dart';
import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../providers/settings_provider.dart';
import '../../services/print_control_service.dart';
import '../../services/print_progress.dart';
import '../../services/printer_status_registry.dart';
import '../../services/printer_status_service.dart';
import '../../widgets/adaptive_tool_button.dart';
import '../../widgets/webcam_view.dart';
import '../printer/printer_camera_screen.dart';
import '../tutorial/tutorial_anchors.dart';
import '../tutorial/tutorial_controller.dart';
import 'camera_picker_overlay.dart';
import 'console_overlay.dart';
import 'control_panel_overlay.dart';
import 'file_system_overlay.dart';
import 'gcode_files_overlay.dart';
import 'macros_overlay.dart';
import 'preheat_overlay.dart';
import 'printer_tile.dart';

/// The Single-printer dashboard: one printer full screen, Klipper-screen style
/// but Moongate-shaped. Top to bottom - a pinned status header (the Local /
/// Tunnel colour bar, print state, E-STOP), the camera, the job card, the
/// temperatures, the big Macros / Console / Print files buttons, and the X Y Z
/// position. Wider than tall (landscape with "Rotate with device", tablets,
/// unfolded foldables) it splits: header + camera left, controls right.
///
/// Everything it opens is the sheet the tile already uses, and the safety rules
/// are the tile's too: E-STOP fires on a double-tap, Cancel needs a second tap
/// within 4 s. It runs its own status poller for the printer on screen - with
/// [PrinterStatusService.wantPosition] on - and feeds [PrinterStatusRegistry]
/// like a tile, so the printer list and the tile order stay current. The
/// dashboard keys it by printer id, so ‹ › swaps in a fresh poller.
class SinglePrinterView extends ConsumerStatefulWidget {
  final PrinterConfig printer;

  /// Where [printer] sits in the saved order (0-based) and how many printers
  /// there are - the "2 of 4" beside the name.
  final int index;
  final int count;

  /// Opens the printer list (a tap on the name).
  final VoidCallback onChoosePrinter;

  /// Opens the printer's own web interface (Mainsail / Fluidd).
  final VoidCallback onOpenPrinterPage;

  /// Custom-theme card opacity, as on the tiles; 1.0 = opaque.
  final double tileOpacity;

  const SinglePrinterView({
    super.key,
    required this.printer,
    required this.index,
    required this.count,
    required this.onChoosePrinter,
    required this.onOpenPrinterPage,
    this.tileOpacity = 1.0,
  });

  @override
  ConsumerState<SinglePrinterView> createState() => _SinglePrinterViewState();
}

class _SinglePrinterViewState extends ConsumerState<SinglePrinterView>
    with WidgetsBindingObserver {
  late final PrinterStatusService _statusService;
  late final PrintControlService  _controlService;
  late PrinterStatus _status;

  /// False until this view's own first poll lands. Until then [_status] is the
  /// registry's last snapshot - which can be old, since only the printer on
  /// screen is polled - so the controls wait and a thin bar shows the refresh.
  bool _fresh = false;

  /// Web UI type ('mainsail' / 'fluidd'), seeded from the saved config.
  String? _uiType;

  bool _stopConfirmPending = false;
  Timer? _stopConfirmTimer;
  bool _homing = false;

  /// Live tutorial: the same demo contract as the first dashboard tile - while
  /// a demo step shows doctored state, [_realBehindDemo] keeps the real status.
  PrinterStatus? _realBehindDemo;
  bool _preheatDemoOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final p = widget.printer;
    _status = PrinterStatusRegistry.instance.snapshot(p.id) ??
        PrinterStatus(
          state:           'connecting',
          progress:        0,
          hotendTemp:      0,
          hotendTarget:    0,
          bedTemp:         0,
          bedTarget:       0,
          connection:      PrinterConnection.offline,
          webcamFlipH:     p.webcamFlipH,
          webcamFlipV:     p.webcamFlipV,
          webcamRotation:  p.webcamRotation,
          webcamTargetFps: p.webcamTargetFps,
        );
    _uiType         = p.uiType;
    _statusService  = PrinterStatusService(p)..wantPosition = true;
    _controlService = PrintControlService(p);
    _statusService.stream.listen((s) {
      PrinterStatusRegistry.instance.update(p.id, s);
      if (!mounted) return;
      if (_realBehindDemo != null) {
        _realBehindDemo = s;
        _fresh = true;
        return;
      }
      // A print that ended while Cancel waited for its second tap resets it.
      if (_status.isPrinting && !s.isPrinting && _stopConfirmPending) {
        _stopConfirmTimer?.cancel();
        _stopConfirmPending = false;
      }
      setState(() {
        _status = s;
        _fresh  = true;
        final detected = _statusService.uiType;
        if (detected != null && detected != _uiType) _uiType = detected;
      });
    });
    _statusService.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusService.dispose();
    _stopConfirmTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Same as the tile: a frozen-then-resumed process polls at once.
    if (state == AppLifecycleState.resumed) _statusService.resumePoll();
  }

  // ── Live tutorial demo state (mirrors the first tile) ─────────────────────
  static const _demoSteps = {
    'localBar', 'tunnelBar', 'remoteBuilding', 'temps',
    'estop', 'tools', 'webcam', 'preheatPress', 'preheatSheet',
  };

  void _applyDemoForStep(TutorialState s) {
    final id = s.active ? s.current?.id : null;
    if (id != null && _demoSteps.contains(id)) {
      _realBehindDemo ??= _status;
      setState(() => _status = _demoStatusFor(id));
    } else if (_realBehindDemo != null) {
      setState(() {
        _status = _realBehindDemo!;
        _realBehindDemo = null;
      });
    }
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
      hotendTarget:  _status.hotendTarget,
      bedTarget:     _status.bedTarget,
      chamberTemp:   _status.chamberTemp,
      chamberTarget: _status.chamberTarget,
      toolheads:     _status.toolheads,
    ).whenComplete(() => _preheatDemoOpen = false);
  }

  void _closePreheatDemo() {
    if (!_preheatDemoOpen) return;
    _preheatDemoOpen = false;
    Navigator.of(context).maybePop();
  }

  PrinterStatus _demoStatusFor(String id) {
    final real = _realBehindDemo ?? _status;
    final base = real.copyWith(
      state:          'standby',
      connection:     PrinterConnection.local,
      tunnelReady:    true,
      hotendTemp:     real.hotendTemp > 0 ? real.hotendTemp : 24,
      bedTemp:        real.bedTemp > 0 ? real.bedTemp : 24,
      klippyShutdown: false,
    );
    switch (id) {
      case 'tunnelBar':
        return base.copyWith(connection: PrinterConnection.remote);
      case 'remoteBuilding':
        return base.copyWith(tunnelReady: false);
      case 'temps':
        return base.chamberTemp > 0 ? base : base.copyWith(chamberTemp: 28);
      default:
        return base;
    }
  }

  // ── State helpers ──────────────────────────────────────────────────────────

  /// Controls act on what the printer is doing NOW - not on an old snapshot.
  bool get _live => _fresh || _realBehindDemo != null;

  bool get _idle =>
      _status.state == 'standby' ||
      _status.state == 'complete' ||
      _status.state == 'cancelled';

  bool get _canPreheat =>
      _live && _status.connection != PrinterConnection.offline && _idle;

  /// Why there is no live reading ('connecting' / 'starting_up' / 'waiting' /
  /// 'offline'), or null when there is one - the tile's overlay rule.
  String? get _overlay {
    final s = _status;
    if (s.state == 'connecting')  return 'connecting';
    if (s.state == 'starting_up') return 'starting_up';
    if (s.state == 'waiting')     return 'waiting';
    if (s.connection == PrinterConnection.offline) return 'offline';
    return null;
  }

  /// Moonraker is reachable: the console, file system and web page work even
  /// while Klipper is in error or still booting (the tile's tools-row rule).
  bool get _toolsUp => _status.state != 'offline' && _status.state != 'connecting';

  // ── Actions ────────────────────────────────────────────────────────────────

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _handlePause() async {
    final ok = await _controlService.sendAction('pause');
    if (!ok && mounted) _snack(AppLocalizations.of(context).tilePauseFailed);
  }

  Future<void> _handleResume() async {
    final ok = await _controlService.sendAction('resume');
    if (!ok && mounted) _snack(AppLocalizations.of(context).tileResumeFailed);
  }

  /// Cancel needs a second tap within 4 s - the tile's stop rule.
  void _handleCancel() {
    if (_stopConfirmPending) {
      _stopConfirmTimer?.cancel();
      setState(() => _stopConfirmPending = false);
      _controlService.sendAction('cancel');
      return;
    }
    setState(() => _stopConfirmPending = true);
    _stopConfirmTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _stopConfirmPending = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context).tileStopAgainToCancel),
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _handleEmergencyStop() async {
    HapticFeedback.heavyImpact();
    final ok = await _controlService.sendAction('emergency_stop');
    if (!ok && mounted) {
      _snack(AppLocalizations.of(context).tileEmergencyStopFailed);
    }
  }

  Future<void> _handleFirmwareRestart() async {
    HapticFeedback.mediumImpact();
    await _controlService.sendAction('firmware_restart');
  }

  Future<void> _homeAll() async {
    if (_homing) return;
    HapticFeedback.mediumImpact();
    setState(() => _homing = true);
    final ok = await _controlService.runPanelCommand('G28');
    if (!mounted) return;
    setState(() => _homing = false);
    if (!ok) _snack(AppLocalizations.of(context).controlPanelCommandFailed);
    _statusService.pollNow();
  }

  void _openPreheat() {
    HapticFeedback.mediumImpact();
    showPreheatSheet(
      context,
      widget.printer,
      hotendTarget:  _status.hotendTarget,
      bedTarget:     _status.bedTarget,
      chamberTemp:   _status.chamberTemp,
      chamberTarget: _status.chamberTarget,
      toolheads:     _status.toolheads,
    );
  }

  // ── Layout ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ref.listen<TutorialState>(
      tutorialControllerProvider,
      (_, next) => _applyDemoForStep(next),
    );
    // The nav bar / gesture bar / home indicator: the last card must clear it
    // on BOTH platforms (the tile grid pads it on Android only).
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final showCamera  = !widget.printer.hideWebcam;

    // Sides only: the app bar owns the top, the scroll padding the bottom. In
    // landscape this clears the camera cutout and a side 3-button bar.
    return SafeArea(
      top: false,
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = showCamera &&
              (constraints.maxWidth > constraints.maxHeight ||
               constraints.maxWidth >= 720);
          final controls = <Widget>[
            _jobCard(context, l),
            _tempsCard(context, l),
            _buttons(context, l),
            _positionCard(context, l),
          ];
          Widget scrolling(List<Widget> children) => ListView(
                padding: EdgeInsets.only(bottom: 16 + bottomInset),
                children: children,
              );

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: bottomInset),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(context, l),
                        Expanded(child: _camera(context)),
                      ],
                    ),
                  ),
                ),
                Expanded(child: scrolling(controls)),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Pinned: the name, state and E-STOP never scroll away.
              _header(context, l),
              Expanded(
                child: scrolling([
                  if (showCamera)
                    AspectRatio(aspectRatio: 16 / 9, child: _camera(context)),
                  ...controls,
                ]),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _header(BuildContext context, AppLocalizations l) {
    final theme  = Theme.of(context);
    final s      = _status;
    final online = s.connection != PrinterConnection.offline;
    final conn   = switch (s.connection) {
      PrinterConnection.local   => Colors.green,
      PrinterConnection.remote  => Colors.orange,
      PrinterConnection.offline => theme.colorScheme.outlineVariant,
    };
    final base = theme.colorScheme.surface.withValues(alpha: widget.tileOpacity);
    final eta  = _etaLine();

    return Container(
      // The whole header wears a wash of the Local / Tunnel colour.
      color: online ? Color.alphaBlend(conn.withValues(alpha: 0.10), base) : base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(
            key: TutorialAnchors.instance.connectionBar,
            child: Container(height: 4, color: conn),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _nameButton(theme, l),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _stateBadge(l),
                          if (online) _connectionLabel(theme, l, conn),
                          if (eta != null) eta,
                        ],
                      ),
                      if (s.tempWatches.isNotEmpty)
                        TileTempWatchLine(printer: widget.printer, status: s),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _estop(l),
              ],
            ),
          ),
          // Fixed height either way, so nothing below jumps when it goes.
          SizedBox(
            height: 2,
            child: _live ? null : const LinearProgressIndicator(minHeight: 2),
          ),
        ],
      ),
    );
  }

  Widget _nameButton(ThemeData theme, AppLocalizations l) {
    final muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: widget.onChoosePrinter,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              widget.printer.name,
              style: theme.textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.count > 1) ...[
            const SizedBox(width: 8),
            Text(
              l.singlePrinterPosition(widget.index + 1, widget.count),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          Icon(Icons.expand_more, color: muted),
        ],
      ),
    );
  }

  Widget _stateBadge(AppLocalizations l) {
    final s = _status;
    // The tile shows these connection states on its camera overlay rather
    // than a badge; the header gives them a matching pill.
    final (String, IconData)? pill = switch (s.state) {
      'waiting'     => (l.tileConnected, Icons.hourglass_empty),
      'starting_up' => (l.tileStartingUp, Icons.hourglass_empty),
      _ when s.connection == PrinterConnection.offline && s.state != 'connecting'
                    => (l.tileOffline, Icons.wifi_off),
      _             => null,
    };
    if (pill == null) {
      return TileStatusBadge(
        printer: widget.printer,
        status: s,
        onCleared: _statusService.pollNow,
      );
    }
    return _Pill(label: pill.$1, icon: pill.$2);
  }

  Widget _connectionLabel(ThemeData theme, AppLocalizations l, Color conn) {
    final local = _status.connection == PrinterConnection.local;
    return KeyedSubtree(
      key: TutorialAnchors.instance.connectionLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(local ? Icons.wifi_rounded : Icons.cloud_outlined,
              size: 16, color: conn),
          const SizedBox(width: 4),
          Text(
            local ? l.tileLocal : l.tileTunnel,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: conn, fontWeight: FontWeight.w600),
          ),
          if (local)
            KeyedSubtree(
              key: TutorialAnchors.instance.tunnelDot,
              child: TileTunnelStatusDot(ready: _status.tunnelReady),
            ),
        ],
      ),
    );
  }

  /// Time left or finish time for a running print - the tile chip's setting
  /// and estimate - or null when it is off or there is nothing to estimate.
  Widget? _etaLine() {
    if (!ref.watch(tileEtaProvider)) return null;
    final s = _status;
    final remaining = printRemainingSeconds(
      state:             s.state,
      progress:          s.progress,
      printDurationSec:  s.printDurationSec,
      filamentUsedMm:    s.filamentUsedMm,
      filamentTotalMm:   s.filamentTotalMm,
      slicerEstimateSec: s.slicerEstimateSec,
    );
    if (remaining == null) return null;
    final clock = ref.watch(tileEtaFormatProvider) == TileEtaFormat.finish
        ? formatFinishClock(remaining, AppLocalizations.of(context).localeName)
        : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(clock != null ? Icons.sports_score : Icons.schedule,
            size: 15, color: Colors.blueGrey),
        const SizedBox(width: 3),
        Text(
          clock ?? '~${formatRemainingDuration(remaining)}',
          style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
        ),
      ],
    );
  }

  Widget _estop(AppLocalizations l) {
    if (_status.klippyShutdown) {
      return TileRestartButton(
        tooltip: l.tileFirmwareRestart,
        onTap: _handleFirmwareRestart,
        size: 40,
      );
    }
    return KeyedSubtree(
      key: TutorialAnchors.instance.estop,
      child: TileEstopButton(
        tooltip: l.tileEmergencyStop,
        onFire: _handleEmergencyStop,
        size: 40,
      ),
    );
  }

  // ── Camera ─────────────────────────────────────────────────────────────────

  Widget _camera(BuildContext context) {
    final s       = _status;
    final hasFeed = _live && (s.webcamSnapshotUrl ?? '').isNotEmpty;
    final overlay = _overlay;
    final p       = widget.printer;
    return KeyedSubtree(
      key: TutorialAnchors.instance.webcam,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Tap the picture for the full-screen camera (pinch zoom, rotation).
        onTap: hasFeed ? () => showPrinterCameraOverlay(context, p) : null,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              WebcamView(
                // A snapshot URL carries its own poll's token - wait for this
                // view's first poll rather than fetch with a stale one.
                webcamSnapshotUrl: _live ? s.webcamSnapshotUrl : null,
                webcamFlipH:      s.webcamFlipH,
                webcamFlipV:      s.webcamFlipV,
                webcamRotation:   s.webcamRotation,
                webcamTargetFps:  s.webcamTargetFps,
                webcamIsExternal: s.webcamIsExternal,
                uiType:           _uiType,
                printerId:        p.id,
                pluginOutdated:   s.connection != PrinterConnection.offline &&
                    pluginVersionIsOutdated(s.pluginVersion),
              ),
              if (overlay != null)
                TileConnectionProbe(state: overlay, uiType: _uiType),
              if (s.customCameraDown || s.configuredCameraDown)
                Positioned(
                  top: 8,
                  left: 8,
                  child: TileCameraDownNotice(
                    printer: p,
                    configured: !s.customCameraDown,
                    onApplied: _statusService.pollNow,
                  ),
                ),
              Positioned(
                top: 6,
                right: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cameraSwitchAvailable(p, s)) ...[
                      TileCameraSwitchButton(
                        printer:    p,
                        status:     s,
                        onSwitched: _statusService.pollNow,
                      ),
                      const SizedBox(width: 6),
                    ],
                    TileCameraConfigButton(
                        printer: p, onApplied: _statusService.pollNow),
                    if (printerHasLighting(p)) ...[
                      const SizedBox(width: 6),
                      TileLightBulbButton(printer: p, status: s),
                    ],
                  ],
                ),
              ),
              if (hasFeed)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: TileCameraExpandButton(printer: p),
                ),
              Positioned(
                bottom: 8,
                left: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (s.connection != PrinterConnection.offline &&
                        pluginVersionIsOutdated(s.pluginVersion)) ...[
                      TilePluginUpdateButton(printer: p, status: s),
                      const SizedBox(width: 6),
                    ],
                    TilePowerButton(printer: p, status: s),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Job card ───────────────────────────────────────────────────────────────

  Widget _jobCard(BuildContext context, AppLocalizations l) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final s     = _status;
    final Widget body;

    if (s.isPrinting) {
      final paused = s.state == 'paused';
      final color  = paused ? Colors.orange : theme.colorScheme.primary;
      final layers = s.currentLayer != null && (s.totalLayer ?? 0) > 0
          ? l.singleLayer(s.currentLayer!, s.totalLayer!)
          : null;
      final stopColor = _stopConfirmPending ? Colors.red : Colors.redAccent;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s.filename != null)
            Text(s.filename!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: s.progress,
                    minHeight: 7,
                    backgroundColor: color.withValues(alpha: 0.15),
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(s.progress * 100).round()}%',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (layers != null) ...[
            const SizedBox(height: 6),
            Text(layers,
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: paused
                    ? FilledButton.tonalIcon(
                        onPressed: _live ? _handleResume : null,
                        style: _tinted(Colors.green),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: _label(l.tileResume),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: _live ? _handlePause : null,
                        style: _tinted(Colors.orange),
                        icon: const Icon(Icons.pause_rounded),
                        label: _label(l.tilePause),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _live ? _handleCancel : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: stopColor,
                    side: BorderSide(color: stopColor.withValues(alpha: 0.6)),
                  ),
                  icon: Icon(_stopConfirmPending
                      ? Icons.stop_circle_rounded
                      : Icons.stop_rounded),
                  label: _label(_stopConfirmPending
                      ? l.tileConfirmStop
                      : l.tileStopPrint),
                ),
              ),
            ],
          ),
        ],
      );
    } else if (_overlay case final overlay?) {
      // No live reading: say why, in the tile overlay's words.
      final (title, sub, icon) = switch (overlay) {
        'offline'     => (l.tileOffline, l.tilePrinterUnreachable, Icons.wifi_off),
        'starting_up' => (l.tileStartingUp, l.tileWaitingForHeartbeat, Icons.hourglass_empty),
        'waiting'     => (l.tileConnected, l.tilePrinterIdle, Icons.hourglass_empty),
        _             => (l.tileConnecting, l.tileReachingPrinter, Icons.sync),
      };
      body = Row(
        children: [
          Icon(icon, color: Colors.blueGrey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Text(sub,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ],
            ),
          ),
        ],
      );
    } else if (s.state == 'error' || s.state == 'startup') {
      final error = s.state == 'error';
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(error ? Icons.error_outline : Icons.hourglass_empty,
                  color: error ? Colors.red : Colors.blueGrey),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  error ? l.tilePrinterError : l.tileKlipperStarting,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: error ? Colors.red : null),
                ),
              ),
            ],
          ),
          if (error) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _live ? _handleFirmwareRestart : null,
                    style: _tinted(Colors.orange),
                    icon: const Icon(Icons.restart_alt),
                    label: _label(l.tileFirmwareRestart),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showConsoleSheet(context, widget.printer),
                    icon: const Icon(Icons.terminal_rounded),
                    label: _label(l.tileConsole),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    } else {
      // Idle: ready, or a finished / cancelled job still on the badge.
      final (label, icon, color) = switch (s.state) {
        'complete'  => (l.tilePrintComplete, Icons.check_circle_outline, Colors.teal),
        'cancelled' => (l.tilePrintCancelled, Icons.cancel_outlined, Colors.blueGrey),
        _           => (l.tileReady, Icons.check_circle_outline, Colors.blueGrey),
      };
      final lastFile = s.state == 'standby' ? null : s.filename;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: theme.textTheme.titleSmall?.copyWith(color: color)),
              ),
            ],
          ),
          if (lastFile != null && lastFile.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(lastFile,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _live
                      ? () => showGcodeFilesSheet(context, widget.printer,
                          status: _status)
                      : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: _label(l.gcodeSheetTitle),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _canPreheat ? _openPreheat : null,
                  icon: const Icon(Icons.whatshot),
                  label: _label(l.preheatTitle),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return _card(context, child: body);
  }

  // ── Temperatures ───────────────────────────────────────────────────────────

  Widget _tempsCard(BuildContext context, AppLocalizations l) {
    if (_overlay != null) return const SizedBox.shrink();
    final s = _status;
    final a = TutorialAnchors.instance;
    final cells = <Widget>[];
    if (s.toolheads.length > 1) {
      for (final t in s.toolheads) {
        final cell = _TempCell(
          icon: Icons.whatshot,
          color: Colors.deepOrange,
          temp: t.temp,
          target: t.target,
          label: 'T${t.index}',
          emphasise: t.active,
        );
        cells.add(t.index == 0 ? KeyedSubtree(key: a.tempHotend, child: cell) : cell);
      }
    } else {
      cells.add(KeyedSubtree(
        key: a.tempHotend,
        child: _TempCell(
          icon: Icons.whatshot,
          color: Colors.deepOrange,
          temp: s.hotendTemp,
          target: s.hotendTarget,
          label: l.preheatHotend,
        ),
      ));
    }
    cells.add(KeyedSubtree(
      key: a.tempBed,
      child: _TempCell(
        icon: Icons.bed,
        color: Colors.blue,
        temp: s.bedTemp,
        target: s.bedTarget,
        label: l.preheatBed,
      ),
    ));
    if (s.chamberTemp > 0) {
      cells.add(KeyedSubtree(
        key: a.tempChamber,
        child: _TempCell(
          icon: Icons.sensor_window,
          color: Colors.teal,
          temp: s.chamberTemp,
          target: s.chamberTarget,
          label: l.preheatChamber,
        ),
      ));
    }

    // Equal cells, at most four to a row (three once a multi-tool printer needs
    // a second row), so the rows line up instead of flowing raggedly.
    final perRow = cells.length <= 4 ? cells.length : 3;
    final rows   = <Widget>[];
    for (var i = 0; i < cells.length; i += perRow) {
      final end = i + perRow > cells.length ? cells.length : i + perRow;
      rows.add(Row(
        children: [
          for (final c in cells.sublist(i, end)) Expanded(child: c),
          for (var k = end - i; k < perRow; k++)
            const Expanded(child: SizedBox.shrink()),
        ],
      ));
    }

    return KeyedSubtree(
      key: a.preheatArea,
      child: _card(
        context,
        // Tap or hold anywhere on the temperatures to preheat (idle only).
        onTap: _canPreheat ? _openPreheat : null,
        onLongPress: _canPreheat ? _openPreheat : null,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: Column(
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: 12),
              rows[r],
            ],
          ],
        ),
      ),
    );
  }

  // ── Buttons ────────────────────────────────────────────────────────────────

  Widget _buttons(BuildContext context, AppLocalizations l) {
    final s       = _status;
    final klipper = _live && (s.isPrinting || _idle);
    final idle    = _live && _idle;
    final tools   = _toolsUp;
    final web     = switch (_uiType) {
      'mainsail' => 'Mainsail',
      'fluidd'   => 'Fluidd',
      _          => l.singleWebInterface,
    };
    return KeyedSubtree(
      key: TutorialAnchors.instance.toolsRow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // IntrinsicHeight: a label that wraps to two lines grows all three
            // buttons together, so the row stays one even shape.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _BigButton(
                      icon: Icons.play_circle_outline,
                      label: l.tileMacros,
                      onPressed: klipper
                          ? () => showMacrosSheet(context, widget.printer)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BigButton(
                      icon: Icons.terminal_rounded,
                      label: l.tileConsole,
                      onPressed: tools
                          ? () => showConsoleSheet(context, widget.printer)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BigButton(
                      icon: Icons.folder_open_rounded,
                      label: l.singlePrintFiles,
                      onPressed: idle
                          ? () => showGcodeFilesSheet(context, widget.printer,
                              status: _status)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Measured labels (AdaptiveToolButton): a label that doesn't fit
            // its third of the row becomes a tooltipped icon, never an ellipsis.
            Row(
              children: [
                Expanded(
                  child: AdaptiveToolButton(
                    icon: Icons.code_rounded,
                    label: l.controlPanelTitle,
                    onPressed: idle
                        ? () => showControlPanel(context, widget.printer, _status)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AdaptiveToolButton(
                    icon: Icons.snippet_folder_outlined,
                    label: l.tileFileSystem,
                    onPressed: tools
                        ? () => showFileSystemSheet(context, widget.printer)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AdaptiveToolButton(
                    icon: Icons.open_in_new,
                    label: web,
                    onPressed: tools ? widget.onOpenPrinterPage : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Position ───────────────────────────────────────────────────────────────

  Widget _positionCard(BuildContext context, AppLocalizations l) {
    if (_overlay != null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final s     = _status;
    final pos   = s.klippyShutdown ? null : s.position;
    final axes  = s.homedAxes ?? '';
    final homed = axes.contains('x') && axes.contains('y') && axes.contains('z');
    final idle  = _live && _idle;
    final (String strip, IconData stripIcon, Color stripColor) = pos == null
        ? (l.controlPanelPositionUnknown, Icons.help_outline, muted)
        : homed
            ? (l.controlPanelHomed, Icons.check_circle, Colors.green)
            : (l.controlPanelNotHomed, Icons.warning_amber_rounded,
                theme.colorScheme.error);
    String value(int i, int digits) =>
        pos == null ? '--' : pos[i].toStringAsFixed(digits);

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l.singlePosition,
                    style: theme.textTheme.labelLarge?.copyWith(color: muted)),
              ),
              Icon(stripIcon, size: 16, color: stripColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(strip,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: stripColor)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _AxisValue(axis: 'X', value: value(0, 2), homed: axes.contains('x'))),
              const SizedBox(width: 8),
              Expanded(child: _AxisValue(axis: 'Y', value: value(1, 2), homed: axes.contains('y'))),
              const SizedBox(width: 8),
              Expanded(child: _AxisValue(axis: 'Z', value: value(2, 3), homed: axes.contains('z'))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: idle && !_homing ? _homeAll : null,
                  icon: _homing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.home_outlined),
                  label: _label(l.controlPanelHome),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: idle
                      ? () => showControlPanel(context, widget.printer, _status)
                      : null,
                  icon: const Icon(Icons.open_with),
                  label: _label(l.singleMove),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Small shared bits ──────────────────────────────────────────────────────

  Widget _card(
    BuildContext context, {
    required Widget child,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    EdgeInsets padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
  }) {
    final theme = Theme.of(context);
    final op    = widget.tileOpacity;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      clipBehavior: Clip.antiAlias,
      // Custom-theme tile opacity, exactly as the tiles apply it.
      color: op < 1.0
          ? theme.colorScheme.surfaceContainerLow.withValues(alpha: op)
          : null,
      surfaceTintColor: op < 1.0 ? Colors.transparent : null,
      elevation: op < 1.0 ? 0 : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(padding: padding, child: child),
      ),
    );
  }

  static Widget _label(String text) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);

  static ButtonStyle _tinted(Color color) => FilledButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.18),
        foregroundColor: color,
      );
}

/// Header pill for the connection states (Offline, Connected, Starting up),
/// in the tile status badge's shape.
class _Pill extends StatelessWidget {
  final String label;
  final IconData icon;
  const _Pill({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// One temperature: the heater's icon (in colour only while it has a target),
/// the reading, the target, and a label underneath.
class _TempCell extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double temp;
  final double target;
  final String label;

  /// Bold label - the active tool on a multi-tool printer.
  final bool emphasise;

  const _TempCell({
    required this.icon,
    required this.color,
    required this.temp,
    required this.target,
    required this.label,
    this.emphasise = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final muted  = theme.colorScheme.onSurfaceVariant;
    final active = target > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Scales down rather than overflows in a narrow cell at a large
        // display size.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: active ? color : Colors.blueGrey),
              const SizedBox(width: 3),
              Text(
                '${temp.toStringAsFixed(0)}°',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (active)
                Text(
                  '/${target.toStringAsFixed(0)}°',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: emphasise ? FontWeight.w700 : null,
          ),
        ),
      ],
    );
  }
}

/// A big tonal button: icon over label, two lines allowed for a long
/// translation.
class _BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _BigButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
      ),
    );
  }
}

/// One axis of the position readout; the letter turns green once that axis is
/// homed.
class _AxisValue extends StatelessWidget {
  final String axis;
  final String value;
  final bool homed;

  const _AxisValue({
    required this.axis,
    required this.value,
    required this.homed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            axis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: homed ? Colors.green : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: theme.textTheme.titleMedium),
            ),
          ),
        ],
      ),
    );
  }
}
