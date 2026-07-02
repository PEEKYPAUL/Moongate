import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Result of the first-run tutorial offer popup.
class TutorialOfferResult {
  /// The user chose to start the walkthrough now.
  final bool start;

  /// The user ticked "don't remind me again".
  final bool dontRemind;

  const TutorialOfferResult({required this.start, required this.dontRemind});
}

/// Shows the "would you like a quick tour?" popup. Returns null if dismissed
/// without a choice. The caller persists the don't-remind flag and starts the
/// tour as appropriate.
Future<TutorialOfferResult?> showTutorialOffer(BuildContext context) {
  return showDialog<TutorialOfferResult>(
    context: context,
    builder: (ctx) => const _TutorialOfferDialog(),
  );
}

class _TutorialOfferDialog extends StatefulWidget {
  const _TutorialOfferDialog();

  @override
  State<_TutorialOfferDialog> createState() => _TutorialOfferDialogState();
}

class _TutorialOfferDialogState extends State<_TutorialOfferDialog> {
  bool _dontRemind = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.tutorialOfferTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.tutorialOfferBody),
          const SizedBox(height: 8),
          // "Don't remind me again" only makes sense alongside declining, but
          // keep it visible so the user can opt out in one tap.
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _dontRemind,
            onChanged: (v) => setState(() => _dontRemind = v ?? false),
            title: Text(l.tutorialOfferDontRemind),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            TutorialOfferResult(start: false, dontRemind: _dontRemind),
          ),
          child: Text(l.tutorialOfferNo),
        ),
        FilledButton(
          // Starting the tour implies we have offered it; never re-offer.
          onPressed: () => Navigator.of(context).pop(
            const TutorialOfferResult(start: true, dontRemind: true),
          ),
          child: Text(l.tutorialOfferStart),
        ),
      ],
    );
  }
}
