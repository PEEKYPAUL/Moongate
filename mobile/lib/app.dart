import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/pairing_screen.dart';
import 'features/printer/printer_screen.dart';
import 'features/settings/settings_screen.dart';

final _router = GoRouter(
  initialLocation: '/pair',
  redirect: (context, state) {
    // TODO: redirect to /printer if a valid token already exists
    return null;
  },
  routes: [
    GoRoute(path: '/pair', builder: (_, __) => const PairingScreen()),
    GoRoute(path: '/printer', builder: (_, __) => const PrinterScreen()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
  ],
);

class MoongateApp extends ConsumerWidget {
  const MoongateApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Moongate',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
      ),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
