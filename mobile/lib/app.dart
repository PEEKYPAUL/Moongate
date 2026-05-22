import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/pairing_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/printer/printer_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/splash/splash_screen.dart';
import 'providers/settings_provider.dart';
import 'services/printer_registry.dart';

final _router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(
      path: '/',
      redirect: (_, __) => '/dashboard',
    ),
    GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
    GoRoute(path: '/pair', builder: (_, __) => const PairingScreen()),
    GoRoute(
      path: '/printer/:id',
      builder: (_, state) {
        final id = state.pathParameters['id']!;
        final printer = PrinterRegistry.instance.printers
            .firstWhere((p) => p.id == id);
        return PrinterScreen(printer: printer);
      },
    ),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
  ],
);

class MoongateApp extends ConsumerWidget {
  const MoongateApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final fontScale = ref.watch(fontScaleProvider);

    return MaterialApp.router(
      title: 'Moongate',
      themeMode: themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
      // Apply font scaling via builder so we inherit the real system MediaQuery
      // (status-bar height, nav-bar height, etc.) rather than discarding it.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(fontScale),
        ),
        child: child!,
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6C63FF),
        brightness: brightness,
      ),
    );
  }
}
