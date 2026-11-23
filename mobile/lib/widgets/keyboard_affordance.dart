import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import 'app_icons.dart';

/// Force the soft keyboard (IME) to (re)appear for [node].
///
/// Some Android keyboards don't re-open when the user taps a text field that
/// *already* holds focus - e.g. after dismissing the IME with the system Back
/// or ▼ key. That left people stuck, unable to get back into a field to fix a
/// typo (user-reported on the add-printer screen). Wiring this into a field's
/// `onTap` makes the natural "tap the field again" gesture work everywhere;
/// [ShowKeyboardButton] is the visible, device-agnostic fallback.
void showKeyboardFor(FocusNode node) {
  if (node.hasFocus) {
    // Focus didn't change, so the framework won't re-show the IME on its own.
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  } else {
    // Focusing a blurred field opens the IME as part of normal focus handling.
    node.requestFocus();
  }
}

/// A subtle keyboard glyph for a text field's `suffixIcon`. Tapping it always
/// brings the IME back for [node] - the guaranteed escape hatch on devices
/// that won't re-show the keyboard when you tap an already-focused field.
class ShowKeyboardButton extends StatelessWidget {
  const ShowKeyboardButton(this.node, {super.key});

  final FocusNode node;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(AppIcons.keyboard_outlined),
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      tooltip: AppLocalizations.of(context).commonShowKeyboard,
      onPressed: () => showKeyboardFor(node),
    );
  }
}
