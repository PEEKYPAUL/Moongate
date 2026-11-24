import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/app_icons.dart';

/// A numeric PIN entry surface: a dot row plus an on-screen keypad. Shared by
/// the lock screen and the set / confirm / verify flows (see [showPinSheet]).
///
/// [onSubmit] is called with the entered PIN when it reaches [expectedLength]
/// (auto-submit), or - when [expectedLength] is null - when the user taps
/// Continue (enabled between [minLength] and [maxLength]). It returns an error
/// message to display (the buffer clears, the view stays open) or null on
/// success.
class PinEntryView extends StatefulWidget {
  const PinEntryView({
    super.key,
    required this.title,
    required this.onSubmit,
    this.subtitle,
    this.expectedLength,
    this.minLength = 4,
    this.maxLength = 6,
    this.enabled = true,
    this.statusText,
    this.belowKeypad,
  });

  final String title;
  final String? subtitle;
  final int? expectedLength;
  final int minLength;
  final int maxLength;
  final bool enabled;

  /// Externally supplied status/error (e.g. a lockout countdown), shown in
  /// place of the internal "wrong PIN" message.
  final String? statusText;

  /// Extra actions under the keypad (biometric button, "Forgot PIN?").
  final Widget? belowKeypad;

  final Future<String?> Function(String pin) onSubmit;

  @override
  State<PinEntryView> createState() => _PinEntryViewState();
}

class _PinEntryViewState extends State<PinEntryView> {
  String _buffer = '';
  String? _error;
  bool _busy = false;

  int get _dotCount => widget.expectedLength ?? widget.maxLength;

  @override
  void didUpdateWidget(PinEntryView old) {
    super.didUpdateWidget(old);
    // Clear any half-typed PIN when the pad is disabled (e.g. lockout begins).
    if (!widget.enabled && _buffer.isNotEmpty) _buffer = '';
  }

  void _onDigit(String d) {
    if (!widget.enabled || _busy || _buffer.length >= widget.maxLength) return;
    setState(() {
      _buffer += d;
      _error = null;
    });
    if (widget.expectedLength != null &&
        _buffer.length == widget.expectedLength) {
      _submit();
    }
  }

  void _onBackspace() {
    if (!widget.enabled || _busy || _buffer.isEmpty) return;
    setState(() => _buffer = _buffer.substring(0, _buffer.length - 1));
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final err = await widget.onSubmit(_buffer);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      if (err != null) _buffer = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final canContinue = widget.expectedLength == null &&
        _buffer.length >= widget.minLength &&
        _buffer.length <= widget.maxLength;
    final status = widget.statusText ?? _error;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(widget.subtitle!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          _Dots(count: _dotCount, filled: _buffer.length, color: cs.primary),
          SizedBox(
            height: 28,
            child: Center(
              child: status == null
                  ? null
                  : Text(status,
                      style: TextStyle(color: cs.error),
                      textAlign: TextAlign.center),
            ),
          ),
          _Keypad(
            enabled: widget.enabled && !_busy,
            onDigit: _onDigit,
            onBackspace: _onBackspace,
          ),
          if (widget.expectedLength == null) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: canContinue && !_busy ? _submit : null,
              child: Text(l.pinContinue),
            ),
          ],
          if (widget.belowKeypad != null) ...[
            const SizedBox(height: 8),
            widget.belowKeypad!,
          ],
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.filled, required this.color});
  final int count;
  final int filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final on = i < filled;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? color : Colors.transparent,
            border: Border.all(color: color, width: 1.6),
          ),
        );
      }),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
  });
  final bool enabled;
  final void Function(String) onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    Widget digit(String d) => Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 72,
            height: 60,
            child: OutlinedButton(
              onPressed: enabled ? () => onDigit(d) : null,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(d, style: Theme.of(context).textTheme.headlineSmall),
            ),
          ),
        );

    Widget back() => Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 72,
            height: 60,
            child: IconButton.filledTonal(
              onPressed: enabled ? onBackspace : null,
              icon: const Icon(AppIcons.backspace_outlined),
            ),
          ),
        );

    Widget row(List<Widget> kids) =>
        Row(mainAxisAlignment: MainAxisAlignment.center, children: kids);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([digit('1'), digit('2'), digit('3')]),
        row([digit('4'), digit('5'), digit('6')]),
        row([digit('7'), digit('8'), digit('9')]),
        row([const SizedBox(width: 88), digit('0'), back()]),
      ],
    );
  }
}

/// Shows a modal PIN entry sheet and returns the entered PIN, or null if the
/// user dismissed it. When a [validator] is supplied, the sheet only resolves
/// once it returns null (valid); a non-null result is shown as an error and the
/// user can retry.
Future<String?> showPinSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  int? expectedLength,
  int minLength = 4,
  int maxLength = 6,
  Future<String?> Function(String pin)? validator,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: PinEntryView(
        title: title,
        subtitle: subtitle,
        expectedLength: expectedLength,
        minLength: minLength,
        maxLength: maxLength,
        onSubmit: (pin) async {
          if (validator != null) {
            final err = await validator(pin);
            if (err != null) return err;
          }
          if (ctx.mounted) Navigator.pop(ctx, pin);
          return null;
        },
        ),
      ),
    ),
  );
}
