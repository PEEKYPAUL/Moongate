import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/update_service.dart';

/// Runs the update check once per app session (autoDispose = fresh each cold start).
/// Resolves to [UpdateInfo] if a newer build is available, null if up to date
/// or if the check could not be completed (no network, timeout, etc.).
final updateProvider = FutureProvider.autoDispose<UpdateInfo?>((ref) {
  return UpdateService().checkForUpdate();
});
