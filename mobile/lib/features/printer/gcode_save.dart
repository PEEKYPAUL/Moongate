import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/gcode_cache.dart';
import '../../services/print_control_service.dart';
import 'gcode_viewer_screen.dart' show GcodeViewerScreen;

/// "Save to phone" for a stored G-code file (v0.9.74): the WHOLE file, slicer
/// thumbnails and all, comes down over the connection the file listing
/// answered on ([PrintControlService.downloadGcode], so LAN, tunnel, Direct
/// mode and third-party printers alike, no plugin change), behind a progress
/// dialog with Cancel, then goes to the system "save as" sheet: the SAF
/// "create document" dialog on Android, the Files export picker on iPhone
/// (`FilePicker.saveFile` with `bytes`, the same path the printer backup
/// takes). A tunnel file over [GcodeViewerScreen.askAboveBytes] asks first,
/// like the viewer. Reached from the download button on every row of the
/// Start-a-print sheet and from the viewer's ⋮ menu.
Future<void> saveGcodeToPhone(
  BuildContext context,
  PrintControlService control,
  GcodeFile file, {
  required String base,
  required bool isLan,
}) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final name = file.path.split('/').last;

  // Already downloaded for the viewer (or an earlier save)? Straight to the
  // save sheet, no question and no progress dialog.
  final cached = await GcodeCache.read(control.config.id, file);
  if (!context.mounted) return;
  if (cached != null) {
    await _saveBytes(context, messenger, l, name, cached);
    return;
  }

  if (!isLan && file.size > GcodeViewerScreen.askAboveBytes) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.gcodeViewerLargeFile(formatGcodeSize(file.size))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.gcodeViewerDownload)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
  }

  // Progress dialog on the root navigator (above a bottom sheet too). Only
  // this function pops it, exactly once, after the download settles; Cancel
  // just completes the completer, which makes downloadGcode return null.
  final cancel = Completer<void>();
  final progress = ValueNotifier<(int, int)>((0, -1));
  var dialogOpen = true;
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(ctx).textTheme.titleMedium),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (ctx, p, _) {
            final (received, total) = p;
            final value = total > 0 ? received / total : null;
            final detail = received > 0
                ? (total > 0
                    ? '${formatGcodeSize(received)} / ${formatGcodeSize(total)}'
                    : formatGcodeSize(received))
                : null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: value, minHeight: 6),
                const SizedBox(height: 12),
                Text(l.gcodeViewerDownloading,
                    style: Theme.of(ctx).textTheme.bodyMedium),
                if (detail != null) ...[
                  const SizedBox(height: 4),
                  Text(detail,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.outline)),
                ],
              ],
            );
          },
        ),
        actions: [
          TextButton(
              onPressed: () {
                if (!cancel.isCompleted) cancel.complete();
              },
              child: Text(l.commonCancel)),
        ],
      ),
    ),
  ).whenComplete(() => dialogOpen = false));

  var last = 0;
  final bytes = await control.downloadGcode(
    file,
    base:   base,
    isLan:  isLan,
    cancel: cancel.future,
    onProgress: (r, t) {
      // Throttle the rebuilds to every ~64 KB.
      if (r - last > 65536 || r == t) {
        last = r;
        progress.value = (r, t);
      }
    },
  );
  if (dialogOpen && context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }
  if (cancel.isCompleted) return;
  if (bytes == null) {
    messenger.showSnackBar(SnackBar(
      content: Text(l.gcodeSaveFailed),
      backgroundColor: Colors.redAccent,
    ));
    return;
  }
  unawaited(GcodeCache.write(control.config.id, file, bytes));
  if (!context.mounted) return;
  await _saveBytes(context, messenger, l, name, bytes);
}

/// Hand [bytes] to the system "save as" sheet and report the outcome.
Future<void> _saveBytes(BuildContext context, ScaffoldMessengerState messenger,
    AppLocalizations l, String name, Uint8List bytes) async {
  String? savedPath;
  try {
    // With `bytes`, saveFile writes the file itself through the system
    // dialog (scoped storage allows nothing else) and returns its path, or
    // null when the user backs out.
    savedPath = await FilePicker.platform.saveFile(
      dialogTitle: l.gcodeSaveToPhone,
      fileName: name,
      bytes: bytes,
    );
  } catch (_) {
    messenger.showSnackBar(SnackBar(
      content: Text(l.gcodeSaveFailed),
      backgroundColor: Colors.redAccent,
    ));
    return;
  }
  if (savedPath == null) return; // cancelled
  messenger.showSnackBar(SnackBar(content: Text(l.gcodeSaved(name))));
}

/// "22.6 MB" style sizes.
String formatGcodeSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}
