import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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

  /// Tracks which connection candidate the service is currently probing.
  /// Defaults to 'local' so the very first frame shows "Loading Local…"
  /// without needing to wait for the stream event.
  String _probePhase = 'local'; // 'local' | 'tunnel' | 'offline'
  StreamSubscription<String>? _probeSub;

  @override
  void initState() {
    super.initState();
    // Seed the initial status with persisted webcam transform settings so the
    // first frame already shows the correct orientation — before any poll.
    // Use 'connecting' rather than 'offline' so the badge says "Connecting"
    // during the first poll instead of immediately flashing "Offline".
    _status = PrinterStatus(
      state:          'connecting',
      progress:       0,
      hotendTemp:     0,
      hotendTarget:   0,
      bedTemp:        0,
      bedTarget:      0,
      connection:     PrinterConnection.offline,
      webcamFlipH:    widget.printer.webcamFlipH,
      webcamFlipV:    widget.printer.webcamFlipV,
      webcamRotation: widget.printer.webcamRotation,
    );
    _statusService = PrinterStatusService(widget.printer);
    _controlService = PrintControlService(widget.printer);
    // Subscribe to probe phase BEFORE start() so we catch the very first emit.
    _probeSub = _statusService.probePhase.listen((phase) {
      if (mounted) setState(() => _probePhase = phase);
    });
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
      setState(() => _status = s);
    });
    _statusService.start();
  }

  @override
  void dispose() {
    _statusService.dispose();
    _stopConfirmTimer?.cancel();
    _probeSub?.cancel();
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
                    printer: widget.printer,
                    connection: _status.connection,
                    webcamSnapshotPath: _status.webcamSnapshotPath,
                    webcamFlipH:    _status.webcamFlipH,
                    webcamFlipV:    _status.webcamFlipV,
                    webcamRotation: _status.webcamRotation,
                    tunnelUrlUpdates: _statusService.tunnelUrlUpdates,
                  ),
                  // ── Connection probe overlay ───────────────────────────────
                  // Covers the webcam area while searching for the printer and
                  // when it is unreachable — shows "Loading Local…",
                  // "Loading Tunnel…", or "Offline" with a spinner or icon so
                  // the app never looks stalled.
                  if (_status.state == 'connecting' ||
                      _status.connection == PrinterConnection.offline)
                    _ConnectionProbe(phase: _probePhase),
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
            // Hide action row while we haven't connected yet ('connecting')
            // or Klipper is still starting ('startup') — no actions available.
            if (_status.state != 'offline' &&
                _status.state != 'connecting' &&
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
// Network strategy delegated to PrinterStatusService:
//   The parent passes `connection` (local / remote / offline) which was
//   determined by the status service — it already tried local first, then
//   the tunnel.  The webcam simply mirrors that decision so both the status
//   indicator and the webcam image always use the same network path.
//
//   Subscribes to `tunnelUrlUpdates` so a rotated Quick Tunnel URL is used
//   within the same session without requiring a re-pair.

class _WebcamSnapshot extends StatefulWidget {
  final PrinterConfig     printer;
  final PrinterConnection connection;
  final String?           webcamSnapshotPath;
  final bool              webcamFlipH;
  final bool              webcamFlipV;
  final int               webcamRotation; // 0 | 90 | 180 | 270
  final Stream<String>?   tunnelUrlUpdates;

  const _WebcamSnapshot({
    required this.printer,
    required this.connection,
    this.webcamSnapshotPath,
    this.webcamFlipH    = false,
    this.webcamFlipV    = false,
    this.webcamRotation = 0,
    this.tunnelUrlUpdates,
  });

  @override
  State<_WebcamSnapshot> createState() => _WebcamSnapshotState();
}

class _WebcamSnapshotState extends State<_WebcamSnapshot> {
  int     _tick           = 0;
  String? _liveRemoteHost; // kept fresh via tunnelUrlUpdates
  StreamSubscription<String>? _tunnelSub;

  @override
  void initState() {
    super.initState();
    _liveRemoteHost = widget.printer.remoteHost;
    _tunnelSub = widget.tunnelUrlUpdates?.listen((freshUrl) {
      if (mounted) setState(() => _liveRemoteHost = freshUrl);
    });
    _startTicker();
  }

  @override
  void dispose() {
    _tunnelSub?.cancel();
    super.dispose();
  }

  void _startTicker() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _tick++);
      return true;
    });
  }

  String get _snapshotUrl {
    // Use whichever base the status service determined is reachable.
    final base = (widget.connection == PrinterConnection.remote &&
            _liveRemoteHost != null)
        ? _liveRemoteHost!
        : widget.printer.host;

    // Use the webcam path from Moonraker config; fall back to mjpeg-streamer default.
    final path = widget.webcamSnapshotPath ?? '/webcam/?action=snapshot';

    // Append cache-busting tick — respect whether path already has query params.
    final sep = path.contains('?') ? '&' : '?';
    return '$base$path${sep}_t=$_tick';
  }

  @override
  Widget build(BuildContext context) {
    Widget image = Image.network(
      _snapshotUrl,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      // No loadingBuilder — it overrides gaplessPlayback and causes a
      // one-second white flash.  Gapless holds the last frame silently.
      errorBuilder: (_, __, ___) => Container(
        color: Colors.black54,
        child: const Center(
          child: Icon(Icons.videocam_off, color: Colors.white30, size: 40),
        ),
      ),
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

// ── Connection probe overlay ──────────────────────────────────────────────────
//
// Shown in the webcam area while the app is trying to reach the printer, and
// while it is unreachable.  Replaces the static "Offline" camera icon with
// meaningful progress feedback:
//
//   phase == 'local'   →  spinner + "Loading Local…"
//   phase == 'tunnel'  →  spinner + "Loading Tunnel…"
//   phase == 'offline' →  wifi-off icon + "Offline"
//
// Automatically disappears as soon as any connection candidate succeeds.

class _ConnectionProbe extends StatelessWidget {
  final String phase;
  const _ConnectionProbe({required this.phase});

  @override
  Widget build(BuildContext context) {
    final isOffline = phase == 'offline';

    final label = switch (phase) {
      'tunnel'  => 'Loading Tunnel…',
      'offline' => 'Offline',
      _         => 'Loading Local…',   // 'local' or any unknown value
    };
    final sub = switch (phase) {
      'tunnel'  => 'Connecting via Cloudflare',
      'offline' => 'Retrying shortly…',
      _         => 'Checking local network',
    };

    return Container(
      color: Colors.black87,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isOffline)
            const Icon(Icons.wifi_off, size: 32, color: Colors.white30)
          else
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white54,
              ),
            ),
          const SizedBox(height: 10),
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
