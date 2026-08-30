import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/klipper_config_doc.dart';
import '../../models/klipper_schema.dart';
import '../../models/printer_config.dart';
import '../../services/klipper_include_resolver.dart';
import '../../services/klipper_schema_service.dart';
import '../../services/print_control_service.dart';

/// Structured config editor as a near-full-height bottom sheet: sections as
/// cards, option NAMES fixed as labels, only the VALUES editable - the file
/// itself is never reformatted, because every save is a per-character splice
/// through [KlipperConfigDoc] (comments, ordering and layout survive
/// byte-for-byte). Multi-line values (gcode blocks, point lists) and
/// Klipper's SAVE_CONFIG autosave block render view-only.
///
/// The safety net around "Save and restart": before the first change a
/// backup copy (`<file>.moongate-bak`) is uploaded next to the file, and
/// after the RESTART the sheet watches Moonraker's `klippy_state` - if
/// Klipper comes back in error, one tap restores the backup and restarts
/// again. Moonraker serves all of this while Klipper is down, so a config
/// broken badly enough to keep Klipper from booting is fixed from here too.
///
/// All calls ride the ONE connection the file browser's listing resolved
/// ([base]/[token]/[isLan]) - a config write must never retry across
/// LAN/tunnel paths.
Future<void> showConfigEditorSheet(
  BuildContext context, {
  required PrinterConfig printer,
  required String base,
  required String token,
  required bool isLan,
  required String path,
  List<ConfigFileEntry> files = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Dismissal is guarded: unsaved edits must go through the discard
    // dialog, so the barrier and drag are off and the header X (via
    // maybePop) plus the system back are the only ways out.
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _ConfigEditorSheet(
        printer: printer,
        base: base,
        token: token,
        isLan: isLan,
        path: path,
        files: files,
      ),
    ),
  );
}

/// After-save restart flow state.
enum _RestartPhase { none, waiting, failed }

class _ConfigEditorSheet extends StatefulWidget {
  final PrinterConfig printer;
  final String base;
  final String token;
  final bool isLan;
  final String path;
  final List<ConfigFileEntry> files;

  const _ConfigEditorSheet({
    required this.printer,
    required this.base,
    required this.token,
    required this.isLan,
    required this.path,
    required this.files,
  });

  @override
  State<_ConfigEditorSheet> createState() => _ConfigEditorSheetState();
}

class _ConfigEditorSheetState extends State<_ConfigEditorSheet> {
  late final PrintControlService _control;

  /// The file text as last seen ON the printer (loaded, then updated on
  /// every successful save) - the baseline dirty-tracking compares against.
  String? _savedText;
  KlipperConfigDoc? _doc;
  KlipperSchema? _schema;
  bool _loading = true;
  bool _failed = false;

  /// What [_restore] writes back: the file as it was BEFORE this sheet's
  /// first change, captured when the `.moongate-bak` copy is uploaded.
  String? _backupContent;

  bool _saving = false;
  _RestartPhase _restart = _RestartPhase.none;

  /// One controller per option line, created lazily as rows build and kept
  /// across rebuilds so typing survives the sheet's setState churn. Cleared
  /// (and disposed) whenever the document baseline changes - after a save
  /// or a restore - so rows re-seed from the fresh parse.
  final Map<int, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _control = PrintControlService(widget.printer);
    _load();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final results = await Future.wait([
      _control.readConfigFile(
          widget.base, widget.token, widget.isLan, widget.path),
      KlipperSchemaService().load(),
    ]);
    final text = results[0] as String?;
    if (!mounted) return;
    // A config root should hold nothing above a few hundred KB - refuse to
    // build thousands of rows out of something that plainly isn't a config.
    if (text == null || text.length > 512 * 1024) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    _disposeControllers();
    setState(() {
      _savedText = text;
      _doc = KlipperConfigDoc.parse(text);
      _schema = results[1] as KlipperSchema;
      _loading = false;
    });
  }

  TextEditingController _ctl(ConfigOption o) =>
      _controllers.putIfAbsent(o.lineIndex, () {
        final c = TextEditingController(text: o.value);
        c.addListener(() => setState(() {})); // dirty count + button states
        return c;
      });

  /// Options whose field text differs from the file - what a save writes.
  Map<ConfigOption, String> _pendingEdits() {
    final doc = _doc;
    if (doc == null) return const {};
    final edits = <ConfigOption, String>{};
    for (final s in doc.sections) {
      for (final o in s.options) {
        final c = _controllers[o.lineIndex];
        if (c == null || !doc.canEdit(o)) continue;
        // A pasted newline would splice a raw line break into the file -
        // flatten it; the field is single-line anyway.
        final v = c.text.replaceAll('\n', ' ').replaceAll('\r', ' ');
        if (v != o.value) edits[o] = v;
      }
    }
    return edits;
  }

  /// Adopt [text] as the new on-printer baseline after a successful write.
  void _adopt(String text) {
    _disposeControllers();
    setState(() {
      _savedText = text;
      _doc = KlipperConfigDoc.parse(text);
    });
  }

  void _setWorkingText(String text) {
    _disposeControllers();
    setState(() => _doc = KlipperConfigDoc.parse(text));
  }

  ConfigSectionDefinition? _definition(ConfigSection section) {
    final schema = _schema;
    return schema == null
        ? null
        : KlipperSchemaService().matchSection(schema, section.name);
  }

  String? _valueError(
      ConfigSection section, ConfigOption option, String value) {
    final l = AppLocalizations.of(context);
    ConfigOptionDefinition? definition;
    for (final candidate in _definition(section)?.options ?? const []) {
      if (candidate.name == option.key) {
        definition = candidate;
        break;
      }
    }
    if (definition == null || value.isEmpty) return null;
    switch (definition.type) {
      case ConfigValueType.boolean:
        return const {'true', 'false'}.contains(value.toLowerCase())
            ? null
            : l.fsUseBoolean;
      case ConfigValueType.integer:
        final parsed = int.tryParse(value);
        if (parsed == null) return l.fsExpectedInteger;
        if (definition.min != null && parsed < definition.min!) {
          return 'Minimum ${definition.min}';
        }
        if (definition.max != null && parsed > definition.max!) {
          return 'Maximum ${definition.max}';
        }
        return null;
      case ConfigValueType.floating:
        final parsed = double.tryParse(value);
        if (parsed == null) return l.fsExpectedNumber;
        if (definition.min != null && parsed < definition.min!) {
          return 'Minimum ${definition.min}';
        }
        if (definition.max != null && parsed > definition.max!) {
          return 'Maximum ${definition.max}';
        }
        return null;
      case ConfigValueType.enumeration:
        return definition.enumValues.isNotEmpty &&
                !definition.enumValues.contains(value)
            ? 'Choose: ${definition.enumValues.join(', ')}'
            : null;
      default:
        return null;
    }
  }

  bool get _hasInvalidValues {
    final doc = _doc;
    if (doc == null) return false;
    return doc.sections.any((section) => section.options.any((option) {
          final value = _controllers[option.lineIndex]?.text ?? option.value;
          return _valueError(section, option, value) != null;
        }));
  }

  Future<void> _addOption(ConfigSection section) async {
    final doc = _doc;
    final definition = _definition(section);
    if (doc == null || definition == null) return;
    final existing = section.options.map((option) => option.key).toSet();
    final available = definition.options
        .where((option) => !existing.contains(option.name))
        .toList();
    if (available.isEmpty) return;
    final selected = await showDialog<ConfigOptionDefinition>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppLocalizations.of(context).fsAddField),
        children: [
          for (final option in available)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option),
              child: Text(option.name),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(selected.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(helperText: selected.description),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(AppLocalizations.of(context).commonDone),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && mounted) {
      final working =
          KlipperConfigDoc.parse(doc.textWithEdits(_pendingEdits()));
      final target = working.sections.firstWhere(
          (candidate) =>
              candidate.name == section.name &&
              candidate.lineIndex == section.lineIndex,
          orElse: () => working.sections
              .firstWhere((candidate) => candidate.name == section.name));
      _setWorkingText(working.insertOption(target, selected.name, value));
    }
  }

  Future<void> _addSection() async {
    final schema = _schema;
    final doc = _doc;
    if (schema == null || doc == null) return;
    final selected = await showDialog<ConfigSectionDefinition>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppLocalizations.of(context).fsAddSection),
        children: [
          for (final section in schema.sections)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, section),
              child: Text('[${section.name}]'),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    var name = selected.name;
    if (name.contains('<name>')) {
      final controller = TextEditingController();
      final suffix = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('[${selected.name}]'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(AppLocalizations.of(context).commonDone),
            ),
          ],
        ),
      );
      controller.dispose();
      if (suffix == null || suffix.isEmpty || !mounted) return;
      name = name.replaceFirst('<name>', suffix);
    }
    final working = KlipperConfigDoc.parse(doc.textWithEdits(_pendingEdits()));
    _setWorkingText(working.insertSection(name));
  }

  Future<void> _addInclude() async {
    final doc = _doc;
    if (doc == null) return;
    final paths = widget.files
        .where((file) => file.name.toLowerCase().endsWith('.cfg'))
        .map((file) => file.path)
        .where((path) => path != widget.path)
        .toList();
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppLocalizations.of(context).fsAddInclude),
        children: [
          for (final path in paths)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, path),
              child: Text(path),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final working = KlipperConfigDoc.parse(doc.textWithEdits(_pendingEdits()));
    final currentDir = widget.path.contains('/')
        ? widget.path.substring(0, widget.path.lastIndexOf('/'))
        : '';
    final relative = currentDir.isEmpty
        ? selected
        : selected.startsWith('$currentDir/')
            ? selected.substring(currentDir.length + 1)
            : selected;
    _setWorkingText(working.insertSection('include $relative'));
  }

  Future<void> _openInclude(ConfigSection section) async {
    final pattern = section.name.substring('include '.length).trim();
    final matches = KlipperIncludeResolver.matchingPaths(
        widget.path, pattern, widget.files.map((file) => file.path));
    if (matches.isEmpty) return;
    String? target = matches.length == 1 ? matches.single : null;
    target ??= await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(pattern),
        children: [
          for (final path in matches)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, path),
              child: Text(path),
            ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    await showConfigEditorSheet(context,
        printer: widget.printer,
        base: widget.base,
        token: widget.token,
        isLan: widget.isLan,
        path: target,
        files: widget.files);
  }

  Future<void> _save({required bool restart}) async {
    final doc = _doc;
    final saved = _savedText;
    if (doc == null || saved == null || _saving) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final edits = _pendingEdits();
    final structural = doc.text != saved;
    if (edits.isEmpty && !structural && !restart) return;
    if (_hasInvalidValues) return;

    setState(() => _saving = true);

    final current = await _control.readConfigFile(
        widget.base, widget.token, widget.isLan, widget.path);
    if (!mounted) return;
    if (current == null || current != saved) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
        content: Text(l.fsFileChanged),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    // First change this session: put the safety copy on the printer before
    // touching the file. A failed backup blocks the mutation: without it the
    // restore action promised by this editor cannot work.
    if (_backupContent == null && (edits.isNotEmpty || structural)) {
      final ok = await _control.writeConfigFile(widget.base, widget.token,
          widget.isLan, '${widget.path}.moongate-bak', saved);
      if (!mounted) return;
      if (!ok) {
        setState(() => _saving = false);
        messenger.showSnackBar(SnackBar(
          content: Text(l.fsSaveFailed),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      _backupContent = saved;
    }

    var newText = doc.textWithEdits(edits);
    if (newText != saved) {
      final ok = await _control.writeConfigFile(
          widget.base, widget.token, widget.isLan, widget.path, newText);
      if (!mounted) return;
      if (!ok) {
        setState(() => _saving = false);
        messenger.showSnackBar(SnackBar(
          content: Text(l.fsSaveFailed),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      _adopt(newText);
    }
    setState(() => _saving = false);
    if (restart) {
      _restartAndWatch();
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(l.fsSaved),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  /// RESTART reloads Klipper's config; then poll `klippy_state` until it
  /// settles. 'startup' (and unreachable moments while Klipper cycles) keep
  /// the watch alive; 'ready' ends it happily; 'error'/'shutdown' - or a
  /// 50s timeout - raise the restore banner.
  Future<void> _restartAndWatch() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _restart = _RestartPhase.waiting);
    final restartResult = await _control.sendConsoleCommand(
        widget.base, widget.token, widget.isLan, 'RESTART');
    if (!mounted) return;
    if (!restartResult.delivered || restartResult.error != null) {
      setState(() => _restart = _RestartPhase.none);
      messenger.showSnackBar(SnackBar(
        content: Text(l.fsSaveFailed),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    for (var i = 0; i < 25; i++) {
      if (!mounted || _restart != _RestartPhase.waiting) return;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || _restart != _RestartPhase.waiting) return;
      final state = await _control.fetchKlippyState(
          widget.base, widget.token, widget.isLan);
      if (!mounted || _restart != _RestartPhase.waiting) return;
      if (state == 'ready') {
        setState(() => _restart = _RestartPhase.none);
        messenger.showSnackBar(SnackBar(
          content: Text(l.fsRestartOk),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
        return;
      }
      if (state == 'error' || state == 'shutdown') break;
      // 'startup' / null: still coming up (or briefly unreachable) - wait.
    }
    if (mounted && _restart == _RestartPhase.waiting) {
      setState(() => _restart = _RestartPhase.failed);
    }
  }

  Future<void> _restore() async {
    final backup = _backupContent;
    if (backup == null || _saving) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _restart = _RestartPhase.none;
    });
    final ok = await _control.writeConfigFile(
        widget.base, widget.token, widget.isLan, widget.path, backup);
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
        content: Text(l.fsSaveFailed),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    _adopt(backup);
    setState(() => _saving = false);
    messenger.showSnackBar(SnackBar(
      content: Text(l.fsRestored),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
    _restartAndWatch();
  }

  Future<void> _confirmClose() async {
    final l = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.fsDiscardTitle),
        content: Text(l.fsDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.fsDiscard),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final dirty = _pendingEdits().length +
        ((_doc?.text != null && _doc?.text != _savedText) ? 1 : 0);

    return PopScope(
      canPop: dirty == 0 && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmClose();
      },
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.path.split('/').last,
                          style: theme.textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                    icon: const Icon(Icons.add),
                    tooltip: l.fsAddSection,
                    onPressed: _schema == null ? null : _addSection,
                  ),
                  IconButton(
                    icon: const Icon(Icons.account_tree_outlined),
                    tooltip: l.fsAddInclude,
                    onPressed: widget.files.isEmpty ? null : _addInclude,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            if (_restart == _RestartPhase.waiting) ...[
              const LinearProgressIndicator(minHeight: 2),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  l.fsRestartSent,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            ],
            if (_restart == _RestartPhase.failed)
              Container(
                width: double.infinity,
                color: theme.colorScheme.errorContainer,
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l.fsRestartFailedBanner,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer),
                      ),
                    ),
                    if (_backupContent != null)
                      TextButton(
                        onPressed: _restore,
                        child: Text(l.fsRestoreBackup),
                      ),
                    IconButton(
                      icon: Icon(Icons.close,
                          size: 18, color: theme.colorScheme.onErrorContainer),
                      onPressed: () =>
                          setState(() => _restart = _RestartPhase.none),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),

            // ── Sections / states ───────────────────────────────────
            Expanded(child: _body(theme, l)),

            // ── Save bar ────────────────────────────────────────────
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dirty > 0 ? l.fsUnsavedChanges : l.fsBackupNote,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: dirty > 0
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: dirty > 0 && !_saving && !_hasInvalidValues
                          ? () => _save(restart: false)
                          : null,
                      child: Text(l.fsSave),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: dirty > 0 && !_saving && !_hasInvalidValues
                          ? () => _save(restart: true)
                          : null,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(l.fsSaveRestart),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme, AppLocalizations l) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final doc = _doc;
    if (_failed || doc == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(l.fsEditorLoadError,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _load,
                child: Text(l.commonRetry),
              ),
            ],
          ),
        ),
      );
    }
    final itemCount = doc.sections.length + (doc.hasAutosaveBlock ? 1 : 0);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: itemCount,
      itemBuilder: (context, i) {
        if (i >= doc.sections.length) {
          // The trailing SAVE_CONFIG autosave block - Klipper owns it.
          return Card(
            child: ListTile(
              leading:
                  Icon(Icons.lock_outline, color: theme.colorScheme.outline),
              title: Text(
                l.fsAutosaveBlock,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          );
        }
        return _sectionCard(theme, l, doc, doc.sections[i]);
      },
    );
  }

  Widget _sectionCard(ThemeData theme, AppLocalizations l, KlipperConfigDoc doc,
      ConfigSection section) {
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Courier'],
      fontSize: 13,
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    if (section.isInclude) {
      return Card(
        child: ListTile(
          dense: true,
          leading: Icon(Icons.subdirectory_arrow_right_rounded,
              color: theme.colorScheme.outline),
          title: Text('[${section.name}]', style: mono),
          subtitle: Text(widget.path),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openInclude(section),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('[${section.name}]', style: mono)),
                if (_definition(section)?.options.any((candidate) => !section
                        .options
                        .any((option) => option.key == candidate.name)) ==
                    true)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: l.fsAddField,
                    onPressed: () => _addOption(section),
                  ),
              ],
            ),
            for (final o in section.options) ...[
              const SizedBox(height: 8),
              _optionRow(theme, l, doc, section, o),
            ],
          ],
        ),
      ),
    );
  }

  Widget _optionRow(ThemeData theme, AppLocalizations l, KlipperConfigDoc doc,
      ConfigSection section, ConfigOption o) {
    final keyStyle = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Courier'],
      fontSize: 12.5,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(o.key, style: keyStyle),
        if (o.inlineComment != null)
          Text(
            o.inlineComment!,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.outline, fontSize: 11),
          ),
      ],
    );
    if (!doc.canEdit(o)) {
      return Row(
        children: [
          Expanded(child: label),
          const SizedBox(width: 8),
          Icon(Icons.lock_outline, size: 14, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            l.fsViewOnly,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      );
    }
    final ctl = _ctl(o);
    final edited = ctl.text != o.value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 11, child: label),
        const SizedBox(width: 8),
        Expanded(
          flex: 9,
          child: TextField(
            controller: ctl,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Menlo', 'Courier'],
              fontSize: 13,
              color: edited
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              errorText: _valueError(section, o, ctl.text),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }
}
