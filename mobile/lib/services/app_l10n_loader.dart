import 'dart:ui' as ui;

import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

/// Load the user's chosen UI locale (or the system / English fallback) and
/// return its AppLocalizations. Usable outside the widget tree - it's a pure
/// Dart load with no BuildContext - so background isolates (the print
/// notification service, the widget refresh) and start-up code read in the
/// same language as the app.
Future<AppLocalizations> loadAppL10n() async {
  var code = (await SharedPreferences.getInstance()).getString('app_locale');
  code ??= ui.PlatformDispatcher.instance.locale.languageCode;
  try {
    return await AppLocalizations.delegate.load(ui.Locale(code));
  } catch (_) {
    return AppLocalizations.delegate.load(const ui.Locale('en'));
  }
}
