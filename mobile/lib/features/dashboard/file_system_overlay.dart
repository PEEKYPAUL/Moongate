import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../services/print_control_service.dart';
import 'config_editor_overlay.dart';

/// Bottom-sheet file browser over the printer's `config` root (printer.cfg
/// and friends). One recursive Moonraker listing feeds the whole browse -
/// folders are derived client-side from the slashes, so drilling into a
/// folder is instant and costs no request. Tapping an editable file opens
/// the structured editor ([showConfigEditorSheet]) on the exact connection
/// this listing resolved. Opened from the tools row on a tile - see
/// `printer_tile.dart`.
Future<void> showFileSystemSheet(BuildContext context, PrinterConfig printer) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _FileSystemSheet(printer: printer),
  );
}

class _FileSystemSheet extends StatefulWidget {
  final PrinterConfig printer;
  const _FileSystemSheet({required this.printer});

  @override
  State<_FileSystemSheet> createState() => _FileSystemSheetState();
}

class _FileSystemSheetState extends State<_FileSystemSheet> {
  late final PrintControlService _control;
  late Future<ConfigListing?> _future;

  /// The folder being shown, '' for the config root. Purely a client-side
  /// view over the one recursive listing.
  String _dir = '';

  @override
  void initState() {
    super.initState();
    _control = PrintControlService(widget.printer);
    _future = _control.listConfigFiles();
  }

  void _reload() => setState(() => _future = _control.listConfigFiles());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.72,
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                if (_dir.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() {
                      final i = _dir.lastIndexOf('/');
                      _dir = i > 0 ? _dir.substring(0, i) : '';
                    }),
                  )
                else
                  const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.fsSheetTitle, style: theme.textTheme.titleMedium),
                      Text(
                        _dir.isEmpty
                            ? widget.printer.name
                            : '${widget.printer.name} · $_dir',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: l.commonRetry,
                  onPressed: _reload,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── File list / states ──────────────────────────────────────
          Expanded(
            child: FutureBuilder<ConfigListing?>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return _Centered(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(l.fsLoading, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  );
                }
                final listing = snap.data;
                if (listing == null) {
                  return _Centered(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off,
                            size: 40, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(l.fsError,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: _reload,
                          child: Text(l.commonRetry),
                        ),
                      ],
                    ),
                  );
                }

                // Derive this level's folders and files from the flat
                // recursive listing.
                final prefix = _dir.isEmpty ? '' : '$_dir/';
                final folders = <String>{};
                final files = <ConfigFileEntry>[];
                for (final f in listing.files) {
                  if (!f.path.startsWith(prefix)) continue;
                  final rest = f.path.substring(prefix.length);
                  final slash = rest.indexOf('/');
                  if (slash < 0) {
                    files.add(f);
                  } else {
                    folders.add(rest.substring(0, slash));
                  }
                }
                if (folders.isEmpty && files.isEmpty) {
                  return _Centered(
                    child:
                        Text(l.fsEmpty, style: theme.textTheme.bodyMedium),
                  );
                }
                final sortedFolders = folders.toList()
                  ..sort((a, b) =>
                      a.toLowerCase().compareTo(b.toLowerCase()));
                return SafeArea(
                  top: false,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      for (final d in sortedFolders)
                        ListTile(
                          leading: Icon(Icons.folder_rounded,
                              color: theme.colorScheme.outline),
                          title: Text(d,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(
                              () => _dir = _dir.isEmpty ? d : '$_dir/$d'),
                        ),
                      for (final f in files)
                        ListTile(
                          leading: Icon(
                            f.isEditable
                                ? Icons.description_outlined
                                : Icons.insert_drive_file_outlined,
                            color: f.isEditable
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                          ),
                          title: Text(f.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            _subtitle(context, f),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          enabled: f.isEditable,
                          onTap: f.isEditable
                              ? () => showConfigEditorSheet(
                                    context,
                                    printer: widget.printer,
                                    base:    listing.base,
                                    token:   listing.token,
                                    isLan:   listing.isLan,
                                    path:    f.path,
                                  )
                              : null,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// "12 Jun 2026 · 4.2 KB" - parts omitted when unknown.
  String _subtitle(BuildContext context, ConfigFileEntry f) {
    final parts = <String>[];
    final dt = f.modifiedAt;
    if (dt != null) {
      parts.add(MaterialLocalizations.of(context).formatShortDate(dt));
    }
    if (f.size > 0) {
      parts.add(f.size < 1024
          ? '${f.size} B'
          : f.size < 1024 * 1024
              ? '${(f.size / 1024).toStringAsFixed(1)} KB'
              : '${(f.size / (1024 * 1024)).toStringAsFixed(1)} MB');
    }
    return parts.join(' · ');
  }
}

class _Centered extends StatelessWidget {
  final Widget child;
  const _Centered({required this.child});
  @override
  Widget build(BuildContext context) =>
      Center(child: Padding(padding: const EdgeInsets.all(24), child: child));
}
