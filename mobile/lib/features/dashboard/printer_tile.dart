import 'dart:async';

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
  PrinterStatus _status = PrinterStatus.offline;

  bool _stopConfirmPending = false;
  Timer? _stopConfirmTimer;

  @override
  void initState() {
    super.initState();
    _statusService = PrinterStatusService(widget.printer);
    _controlService = PrintControlService(widget.printer);
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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Webcam ───────────────────────────────────────────────────
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _WebcamSnapshot(printer: widget.printer),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _StatusBadge(status: _status),
                  ),
                ],
              ),
            ),

            // ── Progress + buttons in ONE row ────────────────────────────
            if (_status.state != 'offline')
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
                  Text(
                    widget.printer.name,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
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
      'complete' => ('Print complete', Icons.check_circle_outline, Colors.teal),
      'error'    => ('Printer error',  Icons.error_outline,        Colors.red),
      _          => ('Ready',          Icons.check_circle_outline,  Colors.blueGrey),
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

class _WebcamSnapshot extends StatefulWidget {
  final PrinterConfig printer;
  const _WebcamSnapshot({required this.printer});

  @override
  State<_WebcamSnapshot> createState() => _WebcamSnapshotState();
}

class _WebcamSnapshotState extends State<_WebcamSnapshot> {
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _tick++);
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.printer.remoteHost ?? widget.printer.host;
    final url  = '$base/webcam/?action=snapshot&_t=$_tick';
    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.black54,
        child: const Center(
          child: Icon(Icons.videocam_off, color: Colors.white30, size: 40),
        ),
      ),
      // No loadingBuilder — let gaplessPlayback hold the previous frame
      // silently while the next snapshot downloads. A loadingBuilder that
      // returns anything other than `child` overrides gapless behaviour and
      // causes the one-second flash we want to eliminate.
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
      'printing' => ('Printing', Colors.green),
      'paused'   => ('Paused',   Colors.orange),
      'standby'  => ('Idle',     Colors.blueGrey),
      'complete' => ('Done',     Colors.teal),
      'error'    => ('Error',    Colors.red),
      _          => ('Offline',  Colors.black54),
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
