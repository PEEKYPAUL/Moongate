import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import '../../models/printer_config.dart';
import '../../services/print_control_service.dart';
import '../../services/printer_status_service.dart';

class PrinterTile extends StatefulWidget {
  final PrinterConfig printer;
  final VoidCallback onTap;

  const PrinterTile({super.key, required this.printer, required this.onTap});

  @override
  State<PrinterTile> createState() => _PrinterTileState();
}

class _PrinterTileState extends State<PrinterTile> {
  late final PrinterStatusService _statusService;
  late final PrintControlService _controlService;
  late PrinterStatus _status;

  bool _stopConfirmPending = false;
  Timer? _stopConfirmTimer;

  /// Web UI type — 'mainsail', 'fluidd', or null. Seeded from the persisted
  /// config (so a cold launch shows the logo immediately even if the
  /// printer is currently offline) and updated whenever the status service
  /// detects it for the first time on a fresh printer.
  String? _uiType;

  @override
  void initState() {
    super.initState();
    // Seed the initial status with persisted webcam transform settings so the
    // first frame already shows the correct orientation — before any poll.
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
    // logo immediately — without waiting for the first detection round-trip.
    _uiType = widget.printer.uiType;
    _statusService.stream.listen((s) {
      if (!mounted) return;
      final wasActive = _status.state == 'printing' || _status.state == 'paused';
      final isActive  = s.state == 'printing' || s.state == 'paused';
      // Print ended naturally while stop-confirm timer was still running —
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

  @override
  void dispose() {
    _statusService.dispose();
    _stopConfirmTimer?.cancel();
    super.dispose();
  }

  Future<void> _handlePause() async {
    final ok = await _controlService.sendAction('pause');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not reach printer — pause failed'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleResume() async {
    final ok = await _controlService.sendAction('resume');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not reach printer — resume failed'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleStop() {
    final isIdle = _status.state != 'printing' && _status.state != 'paused';
    if (isIdle) {
      // Firmware restart when idle/error — brings Klipper back to ready state.
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
        const SnackBar(
          content: Text('Press STOP again to cancel the print'),
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Colours used for the connection indicator throughout the tile.
    final connColor = switch (_status.connection) {
      PrinterConnection.local   => Colors.green,
      PrinterConnection.remote  => Colors.orange,
      PrinterConnection.offline => Colors.transparent,
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Connection accent bar (clipped to card corners at top) ────
            Container(height: 3, color: connColor),

            // ── Webcam ───────────────────────────────────────────────────
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _WebcamSnapshot(
                    webcamSnapshotUrl: _status.webcamSnapshotUrl,
                    webcamFlipH:     _status.webcamFlipH,
                    webcamFlipV:     _status.webcamFlipV,
                    webcamRotation:  _status.webcamRotation,
                    webcamTargetFps: _status.webcamTargetFps,
                    uiType: _uiType,
                  ),
                  // Overlay shown while we don't yet have a usable
                  // status (first poll in flight, Pi waiting for its first
                  // heartbeat, or settled offline). When the UI type is
                  // known we fall through to the logo + a small status
                  // hint instead of a generic spinner — so a powered-off
                  // K3 still looks like the K3, not a blank loading tile.
                  if (_overlayState(_status) case final overlay?)
                    _ConnectionProbe(state: overlay, uiType: _uiType),
                  // ── Status badge ───────────────────────────────────────────
                  // Only shown when connected — the probe overlay provides the
                  // status context while offline/connecting.
                  if (_status.connection != PrinterConnection.offline &&
                      _status.state != 'connecting')
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _StatusBadge(status: _status),
                    ),
                ],
              ),
            ),

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
                onTap: () {}, // absorb — don't navigate when tapping controls
                behavior: HitTestBehavior.opaque,
                child: _ActionRow(
                  status: _status,
                  stopConfirmPending: _stopConfirmPending,
                  onPause: _handlePause,
                  onResume: _handleResume,
                  onStop: _handleStop,
                ),
              ),

            // ── Name + temperatures ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Printer name + connection label on the same row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.printer.name,
                          style: theme.textTheme.titleSmall,
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
                              ? 'Local'
                              : 'Tunnel',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: connColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _TempChip(
                        icon: Icons.whatshot,
                        color: Colors.deepOrange,
                        temp: _status.hotendTemp,
                        target: _status.hotendTarget,
                      ),
                      const SizedBox(width: 8),
                      _TempChip(
                        icon: Icons.bed,
                        color: Colors.blue,
                        temp: _status.bedTemp,
                        target: _status.bedTarget,
                      ),
                      if (_status.chamberTemp > 0) ...[
                        const SizedBox(width: 8),
                        _TempChip(
                          icon: Icons.sensor_window,
                          color: Colors.teal,
                          temp: _status.chamberTemp,
                          target: _status.chamberTarget,
                        ),
                      ],
                    ],
                  ),
                  if (_status.filename != null && _status.isPrinting)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _status.filename!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white54),
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
}

// ── Action row: progress bar / status label + buttons side-by-side ────────────

class _ActionRow extends StatelessWidget {
  final PrinterStatus status;
  final bool stopConfirmPending;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  const _ActionRow({
    required this.status,
    required this.stopConfirmPending,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final printing = status.state == 'printing';
    final paused   = status.state == 'paused';
    final active   = printing || paused;
    final color    = paused ? Colors.orange : theme.colorScheme.primary;

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
                            paused ? 'Paused' : 'Printing',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: color),
                          ),
                          Text(
                            '${(status.progress * 100).toStringAsFixed(1)}%',
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
              tooltip: 'Resume',
              onTap: onResume,
            ),
          if (printing)
            _Btn(
              icon: Icons.pause_rounded,
              color: Colors.orange,
              tooltip: 'Pause',
              onTap: onPause,
            ),
          // Stop (active) / Firmware Restart (idle) — always shown for online printers.
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
                ? (stopConfirmPending ? 'Confirm stop' : 'Stop print')
                : 'Firmware restart',
            onTap: onStop,
          ),
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
    final (label, icon, color) = switch (status.state) {
      'complete'  => ('Print complete', Icons.check_circle_outline,  Colors.teal),
      'cancelled' => ('Print cancelled', Icons.cancel_outlined,      Colors.blueGrey),
      'error'     => ('Printer error',   Icons.error_outline,        Colors.red),
      'startup'   => ('Klipper starting', Icons.hourglass_empty,     Colors.blueGrey),
      _           => ('Ready',            Icons.check_circle_outline, Colors.blueGrey),
    };
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
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

// ── Webcam snapshot ───────────────────────────────────────────────────────────
//
// Self-paced fetch loop. We pull each snapshot ourselves with `http.get` and
// only schedule the next fetch *after* the current one resolves — successful,
// errored, or timed out. The effective frame rate self-adapts to whatever the
// webcam server can actually deliver: fast Crowsnest setups still hit the
// configured 15–30 FPS, slow uv4l-mjpeg (stock RatRig Micron+) and cellular-
// tunnel paths drop to whatever they can sustain, but they never sit on the
// placeholder forever.
//
// This replaces a v0.4.1-era `Image.network`-driven tick loop that incremented
// a cache-buster every `1000/fps` ms. On any path where a single snapshot
// took longer than that interval, `Image.network` would cancel every in-flight
// fetch with the next tick and no frame ever finished — see PR #5 for the
// tunnel-side incarnation of the same race. The fix there was a static 3 FPS
// cap on tunnel mode; this generalises that to any slow path.

class _WebcamSnapshot extends StatefulWidget {
  /// Absolute, ready-to-fetch snapshot URL (already includes mg_token for
  /// tunnel mode). Built by PrinterStatusService each poll. Null while
  /// no webcam is configured or the printer hasn't been reached yet —
  /// build() falls back to the UI-type logo placeholder.
  final String?           webcamSnapshotUrl;
  final bool              webcamFlipH;
  final bool              webcamFlipV;
  final int               webcamRotation; // 0 | 90 | 180 | 270
  /// Crowsnest / Mainsail Target FPS. Acts as the ceiling on the fetch
  /// rate; the actual rate is bounded below by whatever the server can
  /// sustain (the fetch loop is strictly sequential).
  final int               webcamTargetFps;
  /// 'mainsail' | 'fluidd' | null — shown as logo when no snapshot yet.
  final String?           uiType;

  const _WebcamSnapshot({
    this.webcamSnapshotUrl,
    this.webcamFlipH     = false,
    this.webcamFlipV     = false,
    this.webcamRotation  = 0,
    this.webcamTargetFps = 15,
    this.uiType,
  });

  @override
  State<_WebcamSnapshot> createState() => _WebcamSnapshotState();
}

class _WebcamSnapshotState extends State<_WebcamSnapshot> {
  /// Bytes of the most recent successful snapshot. Null until the first
  /// fetch lands; build() shows the UI-type logo placeholder in that
  /// window. After the first frame, `Image.memory(gaplessPlayback: true)`
  /// keeps the last decoded frame on screen across subsequent re-fetches
  /// — no flicker between updates.
  Uint8List? _currentBytes;

  @override
  void initState() {
    super.initState();
    _loop();
  }

  /// Sequential snapshot-fetch loop. One in flight at a time. The next
  /// `_fetchOnce` only starts after the previous one has fully resolved
  /// (200, non-200, timeout, or network error), so a slow upstream
  /// naturally throttles the effective frame rate instead of triggering
  /// the v0.4.1-era self-cancel race.
  ///
  /// The configured Target FPS becomes a *ceiling*: when a fetch returns
  /// faster than `1000/fps` ms, we sleep the remainder so we don't spam
  /// a fast server above the user's chosen rate. When it returns slower,
  /// the sleep is effectively zero and the next fetch starts immediately.
  Future<void> _loop() async {
    while (mounted) {
      final start = DateTime.now();
      await _fetchOnce();
      if (!mounted) return;

      final fps        = widget.webcamTargetFps.clamp(1, 60);
      final intervalMs = (1000 / fps).round();
      final elapsedMs  = DateTime.now().difference(start).inMilliseconds;
      final remaining  = intervalMs - elapsedMs;
      if (remaining > 0) {
        await Future.delayed(Duration(milliseconds: remaining));
      }
    }
  }

  /// One GET to the snapshot URL. Success → store bytes, the next build
  /// will render them. Failure → swallow silently; gaplessPlayback keeps
  /// the previous frame visible (or the placeholder if there isn't one
  /// yet).
  Future<void> _fetchOnce() async {
    final url = widget.webcamSnapshotUrl;
    if (url == null || url.isEmpty) return;
    try {
      // 8 s timeout. Generous because uv4l-mjpeg has been observed to
      // take 3 s+ per snapshot on first wake. We'd rather block the
      // loop briefly and get a frame than spin-fail and never display
      // anything.
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        setState(() => _currentBytes = resp.bodyBytes);
      }
    } catch (_) {
      // Network blip / 401 / timeout / parse error. No state change —
      // the previous frame stays on screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _currentBytes;
    Widget image = bytes != null
        ? Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          )
        : Container(
            color: Colors.black54,
            child: Center(child: _WebcamPlaceholder(uiType: widget.uiType)),
          );

    // Apply the webcam display transforms that Mainsail has configured.
    // This makes the tile image match the orientation shown in the web UI,
    // so an upside-down or mirrored camera looks correct in both places.
    final needsRotate = widget.webcamRotation != 0;
    final needsFlip   = widget.webcamFlipH || widget.webcamFlipV;

    if (needsRotate) {
      image = Transform.rotate(
        angle: widget.webcamRotation * math.pi / 180,
        child: image,
      );
    }
    if (needsFlip) {
      image = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(
          widget.webcamFlipH ? -1.0 : 1.0,
          widget.webcamFlipV ? -1.0 : 1.0,
          1.0,
        ),
        child: image,
      );
    }

    return image;
  }
}

// ── Webcam placeholder ────────────────────────────────────────────────────────
//
// Shown inside the webcam area when the snapshot image fails to load (no
// webcam configured, or camera service not running).  Displays the Mainsail
// or Fluidd logo if the UI type has been detected, otherwise a generic icon.

class _WebcamPlaceholder extends StatelessWidget {
  final String? uiType; // 'mainsail' | 'fluidd' | null

  const _WebcamPlaceholder({this.uiType});

  @override
  Widget build(BuildContext context) {
    if (uiType == 'mainsail') {
      return Opacity(
        opacity: 0.35,
        child: SvgPicture.asset(
          'assets/icons/mainsail_logo.svg',
          width: 130,
          fit: BoxFit.contain,
        ),
      );
    }
    if (uiType == 'fluidd') {
      return Opacity(
        opacity: 0.35,
        child: SvgPicture.asset(
          'assets/icons/fluidd_logo.svg',
          width: 130,
          fit: BoxFit.contain,
        ),
      );
    }
    return const Icon(Icons.videocam_off, color: Colors.white30, size: 40);
  }
}

// ── Connection probe overlay ──────────────────────────────────────────────────
//
// Shown in the webcam area when the tile has nothing live to render —
// first poll in flight, Pi not heartbeating yet, or settled offline.
//
// When the web UI type is known (persisted on the printer config after the
// first successful poll), the overlay renders that logo as the background
// so a powered-off K3 still looks like the K3, instead of a blank spinner
// tile. When the UI type is unknown we fall back to a generic spinner /
// wifi-off icon.

class _ConnectionProbe extends StatelessWidget {
  /// 'connecting'  — first poll in flight
  /// 'starting_up' — Pi hasn't heartbeated to Supabase yet
  /// 'waiting'     — Pi reachable but its printer-side stack isn't
  ///                 (K3 printer power off, Klipper not running, etc.)
  /// 'offline'     — settled, nothing answers on any path
  final String  state;
  final String? uiType; // 'mainsail' | 'fluidd' | null

  const _ConnectionProbe({required this.state, this.uiType});

  @override
  Widget build(BuildContext context) {
    final hasLogo = uiType == 'mainsail' || uiType == 'fluidd';

    final label = switch (state) {
      'offline'     => 'Offline',
      'starting_up' => 'Starting up…',
      'waiting'     => 'Connected',
      _             => 'Connecting…',
    };
    final sub = switch (state) {
      'offline'     => 'Printer unreachable',
      'starting_up' => 'Waiting for first heartbeat',
      'waiting'     => 'Printer idle',
      _             => 'Reaching printer',
    };

    // Top accent: spinner for "in flight" states, wifi-off when offline,
    // nothing for 'waiting' (the logo + Connected label carries it).
    // When the logo is showing we always skip the accent — the logo is
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
        // Status text — at the bottom when a logo is showing, centered
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

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final PrinterStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status.state) {
      'printing'   => ('Printing',   Colors.green),
      'paused'     => ('Paused',     Colors.orange),
      'standby'    => ('Idle',       Colors.blueGrey),
      'complete'   => ('Done',       Colors.teal),
      'cancelled'  => ('Cancelled',  Colors.blueGrey),
      'error'      => ('Error',      Colors.red),
      // Klipper is reachable but hasn't finished initialising yet
      'startup'    => ('Starting',   Colors.blueGrey),
      // Before the first poll completes
      'connecting' => ('Connecting', Colors.blueGrey),
      _            => ('Offline',    Colors.black54),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
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

  const _TempChip({
    required this.icon,
    required this.color,
    required this.temp,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: target > 0 ? color : Colors.white38),
        const SizedBox(width: 2),
        Text(
          '${temp.toStringAsFixed(0)}°',
          style: TextStyle(
            fontSize: 12,
            color: target > 0 ? Colors.white : Colors.white54,
          ),
        ),
        if (target > 0)
          Text(
            '/${target.toStringAsFixed(0)}°',
            style: const TextStyle(fontSize: 10, color: Colors.white54),
          ),
      ],
    );
  }
}
