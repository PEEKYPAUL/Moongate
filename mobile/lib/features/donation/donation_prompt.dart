import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/app_icons.dart';

/// The PayPal "tip jar" link. Single source of truth - also used by the
/// drawer's "Buy me a coffee" item.
const String kDonationUrl =
    'https://www.paypal.com/donate/?hosted_button_id=WCWAZKQ7WKQB4';

/// A gentle, one-time first-run nudge to support the project. Deliberately
/// low-pressure: dismissible by tapping outside or "Maybe later", and the
/// caller only ever shows it once. Returns true if the user chose to donate,
/// so the caller can open [kDonationUrl].
Future<bool> showDonationPrompt(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(AppIcons.favorite, color: Colors.redAccent, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(l.donationPromptTitle)),
        ],
      ),
      content: Text(l.donationPromptBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.donationPromptLater),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(ctx).pop(true),
          icon: const Icon(AppIcons.coffee_outlined, size: 18),
          label: Text(l.dashboardBuyMeCoffee),
        ),
      ],
    ),
  );
  return result ?? false;
}
