import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/custom_theme_provider.dart';
import 'providers/settings_provider.dart';
import 'services/lan_discovery_service.dart';
import 'services/printer_registry.dart';
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
  // Supabase printers table that this user owns — we refresh from
  // Supabase asynchronously in the dashboard.
  await PrinterRegistry.instance.load();

  final container = ProviderContainer();
  await container.read(themeModeProvider.notifier).load();
  await container.read(customThemeProvider.notifier).load();
  await container.read(fontScaleProvider.notifier).load();
  await container.read(gridColumnsProvider.notifier).load();
  await container.read(allowRotationProvider.notifier).load();

  // v0.5.0: kick off the first mDNS browse in the background so the
  // LanDiscoveryService cache is (ideally) populated by the time the
  // dashboard fires its first poll. The browse races against the
  // 2 s splash screen + the first 4 s poll interval — a typical home
  // WiFi resolves mDNS in <500 ms, so the cache wins the race in
  // practice. If it doesn't, the first poll falls back to the persisted
  // lanUrl exactly as v0.4.x did. See docs/v0.5-lan-discovery-design.md §7.
  LanDiscoveryService.instance.refresh().ignore();

  runApp(UncontrolledProviderScope(container: container, child: const MoongateApp()));
}
