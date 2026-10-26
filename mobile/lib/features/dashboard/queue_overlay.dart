import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../services/print_control_service.dart';
import 'gcode_files_overlay.dart';

/// The print queue sheet (v0.9.78): Moonraker's own job queue, driven from
/// the phone. Opened from the "Up next" line on the Single-printer status
/// card, the Queue chip in its tool row, the "Next" line on a dashboard tile
/// and the Queue chip in Start a print. Lists the queued jobs in order, moves
/// one to the front (Moonraker's only reorder), removes one, clears all, and
/// starts or pauses the queue. Every call answers with the whole queue, so
/// the sheet repaints from the answer.
///
/// [initial] is the queue as the last status poll folded it (plugin 0.6.31+),
/// so the sheet opens with content and knows the printer's
/// `automatic_transition` setting; it refreshes from Moonraker at once.
/// [onChanged] lets the caller re-poll so the tile's line follows.
Future<void> showQueueSheet(
  BuildContext context,
  PrinterConfig printer, {
  PrintQueue? initial,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) =>
        _QueueSheet(printer: printer, initial: initial, onChanged: onChanged),
  );
}

class _QueueSheet extends StatefulWidget {
  final PrinterConfig printer;
  final PrintQueue? initial;
  final VoidCallback? onChanged;

  const _QueueSheet({required this.printer, this.initial, this.onChanged});

  @override
  State<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<_QueueSheet> {
  late final PrintControlService _control;
  PrintQueue? _queue;
  bool _loading = true;
  bool _busy    = false;

  /// Moonraker's own answers carry no `automatic_transition`; the folded
  /// status does. Keep the first one we saw.
  bool? get _automatic => widget.initial?.automaticTransition;

  @override
  void initState() {
    super.initState();
    _control = PrintControlService(widget.printer);
    _queue   = widget.initial;
    _refresh();
  }

  Future<void> _refresh() async {
    final q = await _control.queueStatus();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (q != null) _queue = q;
    });
  }

  /// Run one queue call; on success show the returned queue (and a toast),
  /// on failure keep what we had and say so.
  Future<void> _apply(Future<PrintQueue?> Function() op, {String? toast}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final q = await op();
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      if (q != null) _queue = q;
    });
    if (q != null) {
      widget.onChanged?.call();
      if (toast != null) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(toast)));
      }
    } else {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(l.queueFailed)));
    }
  }

  Future<void> _addFiles() async {
    await showGcodeFilesSheet(context, widget.printer, queueMode: true);
    if (mounted) await _refresh();
    widget.onChanged?.call();
  }

  Future<void> _clear(AppLocalizations l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.queueClear),
        content: Text(l.queueClearConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.queueClear)),
        ],
      ),
    );
    if (ok == true) await _apply(() => _control.queueRemove(all: true));
  }

  String _stateLabel(AppLocalizations l, String state) => switch (state) {
        'ready'    => l.queueStateReady,
        'loading'  => l.queueStateLoading,
        'starting' => l.queueStateStarting,
        _          => l.queueStatePaused,
      };

  @override
  Widget build(BuildContext context) {
    final l     = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hint  = theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);
    final q     = _queue;
    final running = q != null && q.isRunning;
    final hasJobs = q != null && q.jobs.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 2),
                child: Row(
                  children: [
                    Text(l.queueTitle, style: theme.textTheme.titleLarge),
                    const SizedBox(width: 10),
                    if (q != null)
                      _StatePill(
                        label:  _stateLabel(l, q.state),
                        active: running,
                      ),
                    const Spacer(),
                    if (hasJobs)
                      IconButton(
                        icon: const Icon(Icons.delete_sweep_outlined),
                        tooltip: l.queueClear,
                        onPressed: _busy ? null : () => _clear(l),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(
                  running ? l.queueIntroReady : l.queueIntroPaused,
                  style: hint,
                ),
              ),
              Flexible(child: _body(context, l, q)),
              if (_automatic != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    _automatic! ? l.queueHintAuto : l.queueHintManual,
                    style: hint,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _addFiles,
                        icon: const Icon(Icons.playlist_add),
                        label: Text(l.queueAddFiles),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: (_busy || !hasJobs)
                            ? null
                            : () => _apply(
                                  running
                                      ? _control.queuePause
                                      : _control.queueStart,
                                  toast: running
                                      ? l.queuePausedToast
                                      : l.queueStartedToast,
                                ),
                        icon: Icon(running
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded),
                        label: Text(running ? l.queuePause : l.queueStart),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l, PrintQueue? q) {
    final theme = Theme.of(context);
    if (q == null && _loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (q == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Text(l.queueFailed,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error)),
      );
    }
    if (q.jobs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Text(l.queueEmpty,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
      );
    }
    final first = q.isRunning;
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: q.jobs.length,
      itemBuilder: (context, i) {
        final j = q.jobs[i];
        final next = i == 0 && first;
        return ListTile(
          dense: true,
          selected: next,
          selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.10),
          leading: SizedBox(
            width: 24,
            child: Text(
              '${i + 1}',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                color: next ? theme.colorScheme.primary : theme.hintColor,
              ),
            ),
          ),
          title: Text(j.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text(
            next ? l.queueStartsWhenIdle : (j.folder ?? ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i > 0)
                IconButton(
                  icon: const Icon(Icons.vertical_align_top),
                  tooltip: l.queueMoveToFront,
                  onPressed: _busy
                      ? null
                      : () => _apply(() => _control.queueJump(j.jobId),
                          toast: l.queueMovedToast),
                ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: l.queueRemove,
                onPressed: _busy
                    ? null
                    : () => _apply(
                        () => _control.queueRemove(jobIds: [j.jobId]),
                        toast: l.queueRemovedToast),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatePill extends StatelessWidget {
  final String label;
  final bool active;
  const _StatePill({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = active
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final fg = active
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: fg)),
    );
  }
}

/// The one-line "Up next" / "Next" entry used by the Single-printer status
/// card and the dashboard tile: the first queued file and a count, tap opens
/// the sheet. Renders nothing when the queue is empty or unknown.
class QueueNextLine extends StatelessWidget {
  final PrinterConfig printer;
  final PrintQueue? queue;
  final VoidCallback? onChanged;

  /// Compact (tile) or the card's fuller row.
  final bool compact;

  const QueueNextLine({
    super.key,
    required this.printer,
    required this.queue,
    this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final q = queue;
    if (q == null || q.jobs.isEmpty) return const SizedBox.shrink();
    final l     = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final label = compact ? l.queueNext : l.queueUpNext;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => showQueueSheet(context, printer,
          initial: q, onChanged: onChanged),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 2 : 6),
        child: Row(
          children: [
            Icon(Icons.playlist_play, size: compact ? 14 : 18,
                color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(label,
                style: (compact
                        ? theme.textTheme.labelSmall
                        : theme.textTheme.bodySmall)
                    ?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                q.jobs.first.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: compact
                    ? theme.textTheme.labelSmall
                    : theme.textTheme.bodySmall,
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 6),
              Text(l.queueCount(q.count),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor)),
              Icon(Icons.chevron_right, size: 18, color: theme.hintColor),
            ],
          ],
        ),
      ),
    );
  }
}
