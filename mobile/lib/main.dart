import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/custom_theme_provider.dart';
import 'providers/dashboard_background_provider.dart';
import 'providers/settings_provider.dart';
import 'services/lan_discovery_service.dart';
import 'services/ota_installer.dart';
import 'services/print_notification_service.dart';
import 'services/printer_liveness_service.dart';
import 'services/printer_registry.dart';
import 'services/push_notification_service.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // v0.3.0: every printer call is mediated by Supabase. Initialise the
  // client and sign in anonymously BEFORE the first frame so the dashboard
  // can immediately show "your" printers (RLS-scoped). The first launch on
  // a fresh install makes one HTTP round-trip to /auth/v1/signup; the
  // session is persisted to flutter_secure_storage so subsequent launches
  // are instant.
  await SupabaseService.instance.initialize();

  // Load the local printer registry. In v0.3.0 this is a cache of the
  // Supabase printers table that this user owns - we refresh from
  // Supabase asynchronously in the dashboard.
  await PrinterRegistry.instance.load();

  final container = ProviderContainer();
  await container.read(themeModeProvider.notifier).load();
  await container.read(localeProvider.notifier).load();
  await container.read(customThemeProvider.notifier).load();
  await container.read(fontScaleProvider.notifier).load();
  await container.read(appFontProvider.notifier).load();
  await container.read(gridColumnsProvider.notifier).load();
  await container.read(allowRotationProvider.notifier).load();
  await container.read(autoArrangeProvider.notifier).load();
  await container.read(localCameraRefreshProvider.notifier).load();
  await container.read(tunnelCameraRefreshProvider.notifier).load();
  await container.read(showCameraConfigIconsProvider.notifier).load();
  await container.read(appLockEnabledProvider.notifier).load();
  await container.read(biometricUnlockProvider.notifier).load();
  await container.read(autoLockTimeoutProvider.notifier).load();
  await container.read(printNotificationsEnabledProvider.notifier).load();
  await container.read(notifPollIntervalProvider.notifier).load();
  await container.read(notificationFieldsProvider.notifier).load();
  await container.read(notifOnlineOnlyProvider.notifier).load();
  await container.read(dashboardBackgroundProvider.notifier).load();
  await container.read(globalPowerButtonProvider.notifier).load();
  await container.read(dashboardButtonsProvider.notifier).load();

  // Start listening for Wi-Fi <-> mobile-data changes now, so the dashboard's
  // camera feeds pick the right refresh rate from the first frame.
  container.read(onMobileDataProvider);

  // Bring the print-notification foreground service in line with the saved
  // preference - starts it if the user left notifications on. Best-effort.
  PrintNotificationService.instance
      .sync(container.read(printNotificationsEnabledProvider))
      .ignore();

  // v0.5.0: kick off the first mDNS browse in the background so the
  // LanDiscoveryService cache is (ideally) populated by the time the
  // dashboard fires its first poll. The browse races against the
  // 2 s splash screen + the first 4 s poll interval - a typical home
  // WiFi resolves mDNS in <500 ms, so the cache wins the race in
  // practice. If it doesn't, the first poll falls back to the persisted
  // lanUrl exactly as v0.4.x did. See docs/v0.5-lan-discovery-design.md §7.
  LanDiscoveryService.instance.refresh().ignore();

  // Track printer liveness (last_seen) over Realtime so the dashboard can show
  // offline printers and skip minting tokens for them - keeping an offline Pi at
  // zero Edge Function cost. No-ops until the anon session lands, then self-starts.
  PrinterLivenessService.instance.start();

  // iOS background push notifications: ask for permission and register this
  // device's APNs token so the cloud can alert it when a print finishes. iOS
  // only (Android keeps its foreground-service notifications); a no-op there
  // and best-effort everywhere (degrades silently without a paid Apple account).
  PushNotificationService.instance.start();

  // Clean up the APK left behind by a previous in-app update. By now its install
  // has finished (or was declined), so the ~80 MB file is just dead weight in
  // the cache - users were seeing it as the app eating storage. Best-effort, off
  // the startup path.
  OtaInstaller.clearDownloadedApks().ignore();

  runApp(UncontrolledProviderScope(container: container, child: const MoongateApp()));
}
