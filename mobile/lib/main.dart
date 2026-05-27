import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/custom_theme_provider.dart';
import 'providers/settings_provider.dart';
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

  runApp(UncontrolledProviderScope(container: container, child: const MoongateApp()));
}
