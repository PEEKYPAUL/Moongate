import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../models/gcode_completion.dart';
import '../../models/klipper_schema.dart';
import '../../services/print_control_service.dart';
import '../../services/gcode_completion_service.dart';
import '../../services/klipper_schema_service.dart';

/// Bottom-sheet G-code console. Opens with the printer's rolling history
/// (Moonraker's `server/gcode_store`, so lines from before the sheet existed
/// are already there), refreshes it every 2 seconds while open, and sends
/// typed commands over the exact connection the history fetch resolved - see
/// the console section in `print_control_service.dart` for why sends never
/// fall back between LAN and tunnel. Opened from the tools row on a tile -
/// `printer_tile.dart`.
///
/// Deliberately available in Klipper 'error' and 'waiting' states: the store
/// is served by Moonraker (not Klipper), so the console still shows the boot
/// or crash lines while Klipper itself is down - which is exactly when a
/// console is the diagnosis tool. Sends in those states come back with
/// Moonraker's "Klippy Host not connected" message as a local `!!` line.
Future<void> showConsoleSheet(BuildContext context, PrinterConfig printer) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      // Rise with the keyboard so the input row stays visible while typing.
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _ConsoleSheet(printer: printer),
    ),
  );
}

/// Commands offered as one-tap chips above the input. They only FILL the
/// input (send stays a deliberate second tap): G28 moves the machine, and a
/// pocket-brushed chip must never home a printer by itself.
const _quickCommands = ['G28', 'STATUS', 'FIRMWARE_RESTART'];

const _monoFallback = ['Menlo', 'Courier'];

class _ConsoleSheet extends StatefulWidget {
  final PrinterConfig printer;
  const _ConsoleSheet({required this.printer});

  @override
  State<_ConsoleSheet> createState() => _ConsoleSheetState();
}

class _ConsoleSheetState extends State<_ConsoleSheet> {
  late final PrintControlService _control;

  /// The resolved connection (base + token + LAN/tunnel). Null until the
  /// first fetch lands - and dropped back to null when a refresh tick fails,
  /// so the next tick re-probes LAN-then-tunnel (Pi IP change, phone left
  /// the LAN). Sends require it: no connection, no POST.
  ConsoleSnapshot? _conn;

  /// The store's lines, replaced wholesale each tick (the store is the
  /// source of truth - no local merging of increments to get wrong).
  List<ConsoleLine> _lines = const [];

  /// Locally-injected error lines (send failures, Moonraker refusals such as
  /// "Klippy Host not connected") - things the store itself can never carry.
  /// Appended after the store lines: they're only ever created moments ago,
  /// so the bottom of the transcript is their honest position.
  final List<ConsoleLine> _local = [];

  bool _loading = true;
  bool _failed = false;
  bool _refreshing = false;
  bool _sending = false;

  /// Whether the view is riding the bottom of the transcript. New lines only
  /// yank the scroll while true, so reading old lines isn't interrupted.
  bool _pinned = true;

  Timer? _tick;
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  List<GcodeCompletion> _suggestions = const [];
  final List<String> _history = [];
  int _historyIndex = 0;
  Map<String, String> _help = const {};
  List<String> _macros = const [];
  Map<String, List<String>> _parameters = const {};

  @override
  void initState() {
    super.initState();
    _control = PrintControlService(widget.printer);
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      _pinned =
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 48;
    });
    _refresh();
    _tick = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return; // a slow tunnel fetch outliving the 2s cadence
    _refreshing = true;
    try {
      final conn = _conn;
      if (conn == null) {
        final snap = await _control.fetchConsole();
        if (!mounted) return;
        if (snap != null) {
          setState(() {
            _conn = snap;
            _lines = snap.lines;
            _loading = false;
            _failed = false;
          });
          final results = await Future.wait([
            _control.fetchGcodeHelpOn(snap.base, snap.token, snap.isLan),
            _control.listMacros(),
            KlipperSchemaService().load(),
          ]);
          if (mounted) {
            final schema = results[2] as KlipperSchema;
            final liveHelp = results[0] as Map<String, String>?;
            setState(() {
              final schemaDescriptions = {
                for (final command in schema.commands)
                  command.name: command.description,
              };
              final names = liveHelp ?? schemaDescriptions;
              _help = {
                for (final entry in names.entries)
                  entry.key: liveHelp?[entry.key] ??
                      schemaDescriptions[entry.key] ??
                      entry.value,
              };
              _macros = (results[1] as List<String>?) ?? const [];
              _parameters = {
                for (final command in schema.commands)
                  command.name: [
                    for (final parameter in command.parameters)
                      '${parameter.name}=',
                  ],
              };
            });
          }
          _maybeAutoScroll();
        } else if (_lines.isEmpty) {
          setState(() {
            _loading = false;
            _failed = true;
          });
        }
      } else {
        final lines =
            await _control.fetchConsoleOn(conn.base, conn.token, conn.isLan);
        if (!mounted) return;
        if (lines != null) {
          final grew = lines.length != _lines.length ||
              (lines.isNotEmpty &&
                  _lines.isNotEmpty &&
                  lines.last.time != _lines.last.time);
          setState(() => _lines = lines);
          if (grew) _maybeAutoScroll();
        } else {
          _conn = null; // re-probe on the next tick
        }
      }
    } finally {
      _refreshing = false;
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _failed = false;
    });
    _refresh();
  }

  void _maybeAutoScroll() {
    if (!_pinned) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  ConsoleLine _localError(String message) => ConsoleLine(
        message: '!! $message',
        time: DateTime.now().millisecondsSinceEpoch / 1000,
        isCommand: false,
      );

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _sending) return;
    final l = AppLocalizations.of(context);
    _setInput('');
    _inputFocus.requestFocus(); // keep the keyboard up for the next command

    final conn = _conn;
    if (conn == null) {
      setState(() => _local.add(_localError(l.consoleSendFailed)));
      _maybeAutoScroll();
      return;
    }
    if (text.toUpperCase() == 'M112') {
      setState(() => _sending = true);
      final res =
          await _control.sendEmergencyStop(conn.base, conn.token, conn.isLan);
      if (mounted) setState(() => _sending = false);
      if (!mounted || res.delivered) return;
      setState(() => _local.add(_localError(l.consoleSendFailed)));
      return;
    }
    if (_history.isEmpty || _history.last != text) _history.add(text);
    _historyIndex = _history.length;
    setState(() => _sending = true);
    // Kick a quick refresh so the command's echo appears in ~half a second
    // rather than waiting out the 2s cadence - the send itself can block for
    // as long as the command runs (G28), so the echo must not gate on it.
    unawaited(
        Future<void>.delayed(const Duration(milliseconds: 400), _refresh));
    final res = await _control.sendConsoleCommand(
        conn.base, conn.token, conn.isLan, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!res.delivered) {
      setState(() => _local.add(_localError(l.consoleSendFailed)));
      _maybeAutoScroll();
    } else if (res.error != null) {
      setState(() => _local.add(_localError(res.error!)));
      _maybeAutoScroll();
    }
  }

  void _acceptSuggestion() {
    if (_suggestions.isEmpty) return;
    final suggestion = _suggestions.first;
    _setInputValue(TextEditingValue(
      text: _input.text.replaceRange(
          suggestion.start, suggestion.end, suggestion.insertionText),
      selection: TextSelection.collapsed(
          offset: suggestion.start + suggestion.insertionText.length),
    ));
    setState(() => _suggestions = const []);
  }

  void _setInput(String text) => _setInputValue(TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ));

  void _setInputValue(TextEditingValue value) {
    _input.value = value;
    if (mounted) {
      setState(() => _suggestions = GcodeCompletionService(
              commands: _help,
              macros: _macros,
              history: _history,
              parameters: _parameters)
          .complete(value.text, cursor: value.selection.baseOffset));
    }
  }

  void _moveHistory(int delta) {
    if (_history.isEmpty) return;
    _historyIndex = (_historyIndex + delta).clamp(0, _history.length);
    final text =
        _historyIndex == _history.length ? '' : _history[_historyIndex];
    _setInput(text);
  }

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
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.consoleSheetTitle,
                          style: theme.textTheme.titleMedium),
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
                  onPressed: _retry,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Transcript / states ─────────────────────────────────────
          Expanded(child: _transcript(theme, l)),

          // ── Quick chips + input row ─────────────────────────────────
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_suggestions.isNotEmpty)
                    SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final s in _suggestions.take(8))
                              ActionChip(
                                  label: Text(s.displayText),
                                  onPressed: () {
                                    _setInputValue(TextEditingValue(
                                      text: _input.text.replaceRange(
                                          s.start, s.end, s.insertionText),
                                      selection: TextSelection.collapsed(
                                          offset:
                                              s.start + s.insertionText.length),
                                    ));
                                    setState(() => _suggestions = const []);
                                    _inputFocus.requestFocus();
                                  })
                          ],
                        )),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final cmd in _quickCommands)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                cmd,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontFamilyFallback: _monoFallback,
                                  fontSize: 12,
                                ),
                              ),
                              onPressed: () {
                                _setInput(cmd);
                                _inputFocus.requestFocus();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.tab):
                                _acceptSuggestion,
                            const SingleActivator(LogicalKeyboardKey.arrowUp):
                                () => _moveHistory(-1),
                            const SingleActivator(LogicalKeyboardKey.arrowDown):
                                () => _moveHistory(1),
                            const SingleActivator(LogicalKeyboardKey.escape):
                                () => setState(() => _suggestions = const []),
                          },
                          child: TextField(
                            controller: _input,
                            focusNode: _inputFocus,
                            autocorrect: false,
                            enableSuggestions: false,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.send,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontFamilyFallback: _monoFallback,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: l.consoleInputHint,
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            onSubmitted: (value) => _suggestions.isNotEmpty
                                ? _acceptSuggestion()
                                : _send(value),
                            onChanged: (value) => _setInputValue(_input.value),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.send_rounded),
                        tooltip: l.consoleSend,
                        onPressed: _sending ? null : () => _send(_input.text),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _transcript(ThemeData theme, AppLocalizations l) {
    if (_loading) {
      return _Centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l.consoleLoading, style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }
    if (_failed && _lines.isEmpty && _local.isEmpty) {
      return _Centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(l.consoleError,
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _retry,
              child: Text(l.commonRetry),
            ),
          ],
        ),
      );
    }
    final display = [..._lines, ..._local];
    if (display.isEmpty) {
      return _Centered(
        child: Text(l.consoleEmpty, style: theme.textTheme.bodyMedium),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      itemCount: display.length,
      itemBuilder: (context, i) {
        final line = display[i];
        return _ConsoleLineRow(
          line: line,
          // A tap on a past command puts it back in the input for re-sending
          // or editing - the phone's stand-in for a desktop's up-arrow.
          onUse: line.kind == ConsoleLineKind.command
              ? () {
                  _input.text = line.message;
                  _input.selection =
                      TextSelection.collapsed(offset: line.message.length);
                  _inputFocus.requestFocus();
                }
              : null,
        );
      },
    );
  }
}

/// One transcript line, coloured by [ConsoleLine.kind]: sent commands lead
/// with `>` in the primary colour, `!!` errors in the error colour, `//`
/// info muted, plain responses in the default body colour.
class _ConsoleLineRow extends StatelessWidget {
  final ConsoleLine line;
  final VoidCallback? onUse;
  const _ConsoleLineRow({required this.line, this.onUse});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, text) = switch (line.kind) {
      ConsoleLineKind.command => (scheme.primary, '> ${line.message}'),
      ConsoleLineKind.error => (scheme.error, line.message),
      ConsoleLineKind.info => (scheme.outline, line.message),
      ConsoleLineKind.response => (scheme.onSurfaceVariant, line.message),
    };
    return InkWell(
      onTap: onUse,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: _monoFallback,
            fontSize: 12.5,
            height: 1.45,
            color: color,
          ),
        ),
      ),
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
