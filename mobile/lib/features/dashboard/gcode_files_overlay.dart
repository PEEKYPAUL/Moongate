import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/plugin_version.dart';
import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../models/temp_watch.dart';
import '../../services/print_control_service.dart';

/// Bottom-sheet G-code browser. Lists the files already stored on the printer
/// (Moonraker's `gcodes` root), lets the user pick one, and starts it after a
/// confirmation. Opened from the folder button on an online-and-ready tile -
/// see `printer_tile.dart`. The button itself is hidden while a print is
/// running, so this sheet is only ever reached when the printer can accept a
/// new job. [status] is the tile's live reading: it feeds the confirm
/// dialog's optional preheat-and-soak and cool-down rows (plugin 0.6.27+),
/// which are hidden without it.
Future<void> showGcodeFilesSheet(BuildContext context, PrinterConfig printer,
    {PrinterStatus? status}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _GcodeFilesSheet(printer: printer, status: status),
  );
}

class _GcodeFilesSheet extends StatefulWidget {
  final PrinterConfig printer;
  final PrinterStatus? status;
  const _GcodeFilesSheet({required this.printer, this.status});

  @override
  State<_GcodeFilesSheet> createState() => _GcodeFilesSheetState();
}

class _GcodeFilesSheetState extends State<_GcodeFilesSheet> {
  late final PrintControlService _control;
  late Future<GcodeListing?> _future;
  String? _selected; // selected file's path, or null
  bool _starting = false;

  /// In-flight / loaded thumbnail fetches keyed by file path, so scrolling the
  /// list doesn't refetch as ListView rebuilds tiles.
  final Map<String, Future<Uint8List?>> _thumbs = {};

  @override
  void initState() {
    super.initState();
    _control = PrintControlService(widget.printer);
    _future = _control.listGcodes();
  }

  void _reload() => setState(() {
        _selected = null;
        _thumbs.clear();
        _future = _control.listGcodes();
      });

  Future<Uint8List?> _thumb(GcodeFile f, GcodeListing listing) =>
      _thumbs.putIfAbsent(
          f.path,
          () => _control.fetchThumbnail(f,
              base: listing.base, isLan: listing.isLan));

  Future<void> _start() async {
    final path = _selected;
    if (path == null || _starting) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context); // survives the sheet close
    final name = path.split('/').last;
    final printer = widget.printer;

    final prefs = await _StartPrefs.load(printer.id);
    if (!mounted) return;
    final choice = await showDialog<_StartChoice>(
      context: context,
      builder: (ctx) => _StartPrintDialog(
        fileName: name,
        status:   widget.status,
        temps:    _control.fetchFileTemps(path),
        prefs:    prefs,
      ),
    );
    if (choice == null || !mounted) return;
    await _StartPrefs.save(printer.id, choice);

    setState(() => _starting = true);
    bool ok;
    String text;
    if (choice.soak) {
      // The plugin preheats, waits for every temperature, runs the soak clock
      // and starts the print itself (only if the printer is still idle then).
      final heaters = await _control.availableHeaters();
      final chamberHeater = PrintControlService.mapChamberHeater(heaters);
      ok = await _control.armTempWatch(soakArmPayload(
        bed:           choice.bed,
        chamber:       choice.chamber,
        chamberHeater: chamberHeater,
        soakMinutes:   choice.soakMinutes,
        file:          path,
        msg:           _soakMessage(l, choice),
      ));
      text = ok ? l.gcodeSoakArmed(printer.name, name) : l.gcodeSoakArmFailed;
    } else {
      ok = await _control.startPrint(path);
      text = ok ? l.gcodeStarted(name) : l.gcodeStartFailed;
    }
    if (ok && choice.cool) {
      final coolOk = await _control
          .armTempWatch(coolArmPayload(msg: _coolMessage(l, name)));
      text = '$text · ${coolOk ? l.gcodeCoolArmed : l.gcodeCoolArmFailed}';
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // close the sheet
    messenger.showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  /// The alert the plugin sends when the soak is done, worded HERE so it
  /// arrives in the user's language. `{bed}` / `{chamber}` are the plugin's
  /// own placeholders, filled with the live readings when it fires; the
  /// plugin appends what happened to the print ("· printing benchy.gcode").
  String _soakMessage(AppLocalizations l, _StartChoice c) {
    final withChamber = c.chamber > 0;
    if (c.soakMinutes > 0) {
      return withChamber
          ? l.tempWatchSoakDoneMsg('{bed}', '{chamber}', c.soakMinutes)
          : l.tempWatchSoakDoneMsgBed('{bed}', c.soakMinutes);
    }
    return withChamber
        ? l.tempWatchAtTempMsg('{bed}', '{chamber}')
        : l.tempWatchAtTempMsgBed('{bed}');
  }

  /// The "ready to remove" alert; `{mins}` is filled by the plugin with the
  /// minutes since the print ended.
  String _coolMessage(AppLocalizations l, String file) {
    final hasChamber = (widget.status?.chamberTemp ?? 0) > 0;
    return hasChamber
        ? l.tempWatchCoolMsg('{bed}', '{chamber}', file, '{mins}')
        : l.tempWatchCoolMsgBed('{bed}', file, '{mins}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.gcodeSheetTitle, style: theme.textTheme.titleMedium),
                        Text(
                          widget.printer.name,
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
              child: FutureBuilder<GcodeListing?>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return _Centered(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(l.gcodeLoading,
                              style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    );
                  }
                  final listing = snap.data;
                  if (listing == null) {
                    return _Centered(
                      child: _Message(
                        icon: Icons.cloud_off,
                        text: l.gcodeError,
                        action: FilledButton.tonal(
                          onPressed: _reload,
                          child: Text(l.commonRetry),
                        ),
                      ),
                    );
                  }
                  final files = listing.files;
                  if (files.isEmpty) {
                    return _Centered(
                      child: _Message(
                        icon: Icons.folder_off_outlined,
                        text: l.gcodeEmpty,
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: files.length,
                    itemBuilder: (context, i) {
                      final f = files[i];
                      final selected = f.path == _selected;
                      return ListTile(
                        selected: selected,
                        selectedTileColor:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        leading: _GcodeThumb(future: _thumb(f, listing)),
                        title: Text(
                          f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // Down from ListTile's default 16px titleMedium to a
                          // more refined 14px medium for the file name.
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          _subtitle(context, f),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        trailing: selected
                            ? Icon(Icons.check_circle,
                                color: theme.colorScheme.primary)
                            : null,
                        onTap: () => setState(
                            () => _selected = selected ? null : f.path),
                      );
                    },
                  );
                },
              ),
            ),

            // ── Start bar ───────────────────────────────────────────────
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed:
                        (_selected != null && !_starting) ? _start : null,
                    icon: _starting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(l.gcodeStartButton),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "subfolder · 12 Jun 2026 · 4.2 MB" - parts omitted when unknown.
  String _subtitle(BuildContext context, GcodeFile f) {
    final parts = <String>[];
    if (f.folder != null) parts.add(f.folder!);
    final dt = f.modifiedAt;
    if (dt != null) {
      parts.add(MaterialLocalizations.of(context).formatShortDate(dt));
    }
    final size = _formatSize(f.size);
    if (size.isNotEmpty) parts.add(size);
    return parts.join('  ·  ');
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var s = bytes.toDouble();
    var u = 0;
    while (s >= 1024 && u < units.length - 1) {
      s /= 1024;
      u++;
    }
    final decimals = (u == 0 || s >= 100) ? 0 : 1;
    return '${s.toStringAsFixed(decimals)} ${units[u]}';
  }
}

// ── Start-print dialog: optional preheat-and-soak + cool-down alert ─────────

/// What the dialog decided.
class _StartChoice {
  final bool   soak;
  final double bed;
  final double chamber;
  final int    soakMinutes;
  final bool   cool;
  const _StartChoice({
    required this.soak,
    required this.bed,
    required this.chamber,
    required this.soakMinutes,
    required this.cool,
  });
}

/// The rows a user last chose, per printer (an enclosed ABS machine and a
/// bare-bed printer want different answers), so the dialog opens the way they
/// left it. One JSON map under `gcode_start_prefs`, which rides backups.
class _StartPrefs {
  static const String prefsKey = 'gcode_start_prefs';

  final bool   soak;
  final bool   cool;
  final double bed;
  final double chamber;
  final int    soakMinutes;
  const _StartPrefs({
    this.soak        = false,
    this.cool        = false,
    this.bed         = 0,
    this.chamber     = 0,
    this.soakMinutes = 20,
  });

  static Map<String, dynamic> _all(SharedPreferences p) {
    try {
      final decoded = jsonDecode(p.getString(prefsKey) ?? '{}');
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return {};
  }

  static Future<_StartPrefs> load(String printerId) async {
    final p = await SharedPreferences.getInstance();
    final m = _all(p)[printerId];
    if (m is! Map) return const _StartPrefs();
    double real(Object? v) => v is num ? v.toDouble() : 0;
    return _StartPrefs(
      soak:        m['soak'] == true,
      cool:        m['cool'] == true,
      bed:         real(m['bed']),
      chamber:     real(m['chamber']),
      soakMinutes: m['min'] is num ? (m['min'] as num).toInt() : 20,
    );
  }

  static Future<void> save(String printerId, _StartChoice c) async {
    final p   = await SharedPreferences.getInstance();
    final all = _all(p);
    final prev = all[printerId] is Map ? all[printerId] as Map : const {};
    all[printerId] = {
      'soak':    c.soak,
      'cool':    c.cool,
      'bed':     c.bed > 0 ? c.bed : prev['bed'],
      'chamber': c.chamber > 0 ? c.chamber : prev['chamber'],
      'min':     c.soakMinutes,
    };
    await p.setString(prefsKey, jsonEncode(all));
  }
}

/// "Start print?" with the two optional rows (plugin 0.6.27+): preheat and
/// soak first (bed, chamber where the printer has a sensor, soak minutes;
/// the print then starts by itself) and the cool-down alert, whose helper
/// text names the temperatures it will wait for (the readings now + 5°).
class _StartPrintDialog extends StatefulWidget {
  final String fileName;
  final PrinterStatus? status;
  final Future<FileTemps?> temps;
  final _StartPrefs prefs;
  const _StartPrintDialog({
    required this.fileName,
    required this.status,
    required this.temps,
    required this.prefs,
  });

  @override
  State<_StartPrintDialog> createState() => _StartPrintDialogState();
}

class _StartPrintDialogState extends State<_StartPrintDialog> {
  late bool _soak = widget.prefs.soak;
  late bool _cool = widget.prefs.cool;
  late final _bedCtl     = TextEditingController(text: _fmt(widget.prefs.bed));
  late final _chamberCtl = TextEditingController(text: _fmt(widget.prefs.chamber));
  late final _minCtl     = TextEditingController(text: '${widget.prefs.soakMinutes}');

  /// The slicer's first-layer bed temperature, once the metadata arrives.
  int? _fileBed;

  static String _fmt(double v) => v > 0 ? '${v.round()}' : '';

  @override
  void initState() {
    super.initState();
    widget.temps.then((t) {
      if (!mounted || t == null) return;
      setState(() {
        final bed = t.bed;
        if (bed != null) {
          _fileBed = bed.round();
          _bedCtl.text = _fmt(bed); // the file knows best
        }
        final chamber = t.chamber;
        if (chamber != null && _chamberCtl.text.isEmpty) {
          _chamberCtl.text = _fmt(chamber);
        }
      });
    });
  }

  @override
  void dispose() {
    _bedCtl.dispose();
    _chamberCtl.dispose();
    _minCtl.dispose();
    super.dispose();
  }

  bool get _supported =>
      pluginVersionAtLeast(widget.status?.pluginVersion, kTempWatchMinPlugin);
  bool get _hasChamber => (widget.status?.chamberTemp ?? 0) > 0;

  double _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;
  int get _minutes => (int.tryParse(_minCtl.text.trim()) ?? 0).clamp(0, 600);
  bool get _soakValid => !_soak || _num(_bedCtl) > 0;

  _StartChoice get _choice => _StartChoice(
        soak:        _soak && _supported,
        bed:         _num(_bedCtl),
        chamber:     _hasChamber ? _num(_chamberCtl) : 0,
        soakMinutes: _minutes,
        cool:        _cool && _supported,
      );

  Widget _field(TextEditingController ctl, String label) => Expanded(
        child: TextField(
          controller: ctl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l      = AppLocalizations.of(context);
    final theme  = Theme.of(context);
    final hint   = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final status = widget.status;
    final goals  = status == null
        ? null
        : coolDownGoals(bedNow: status.bedTemp, chamberNow: status.chamberTemp);
    final delta  = kCoolDownDeltaC.round();
    return AlertDialog(
      title: Text(l.gcodeConfirmTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.gcodeConfirmBody(widget.fileName)),
            if (status != null) ...[
              const Divider(height: 24),
              if (!_supported)
                Text(l.gcodeNeedsPlugin, style: hint)
              else ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.gcodeSoakSwitch),
                  value: _soak,
                  onChanged: (v) => setState(() => _soak = v),
                ),
                if (_soak) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _field(_bedCtl, l.preheatBed),
                      if (_hasChamber) ...[
                        const SizedBox(width: 8),
                        _field(_chamberCtl, l.preheatChamber),
                      ],
                      const SizedBox(width: 8),
                      _field(_minCtl, l.gcodeSoakMinutes),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_fileBed != null)
                    Text(l.gcodeSoakFromFile(_fileBed!), style: hint),
                  Text(
                    _soakValid ? l.gcodeSoakHelp : l.gcodeSoakNeedsBed,
                    style: _soakValid
                        ? hint
                        : hint?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.gcodeCoolSwitch),
                  value: _cool,
                  onChanged: (v) => setState(() => _cool = v),
                ),
                if (_cool && goals != null)
                  Text(
                    goals.chamber != null
                        ? l.gcodeCoolHelp(delta, goals.bed.round(),
                            goals.chamber!.round())
                        : l.gcodeCoolHelpBed(delta, goals.bed.round()),
                    style: hint,
                  ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _soakValid ? () => Navigator.pop(context, _choice) : null,
          child: Text(l.gcodeStartAction),
        ),
      ],
    );
  }
}

class _Centered extends StatelessWidget {
  final Widget child;
  const _Centered({required this.child});
  @override
  Widget build(BuildContext context) =>
      Center(child: Padding(padding: const EdgeInsets.all(24), child: child));
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: theme.colorScheme.outline),
        const SizedBox(height: 12),
        Text(text,
            textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    );
  }
}

/// Leading thumbnail for a G-code row: the slicer-embedded preview when the
/// file has one, otherwise a legible file glyph. Always a fixed rounded box so
/// the row height stays even whether or not a thumbnail loads.
class _GcodeThumb extends StatelessWidget {
  final Future<Uint8List?> future;
  const _GcodeThumb({required this.future});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 46,
        height: 46,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        child: FutureBuilder<Uint8List?>(
          future: future,
          builder: (context, snap) {
            final bytes = snap.data;
            if (bytes != null && bytes.isNotEmpty) {
              return Image.memory(bytes,
                  fit: BoxFit.cover, gaplessPlayback: true);
            }
            // Loading, or the file has no embedded thumbnail - show a clear
            // glyph rather than the faint outline icon it replaces.
            return Icon(Icons.description,
                size: 24, color: theme.colorScheme.onSurfaceVariant);
          },
        ),
      ),
    );
  }
}
