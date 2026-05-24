import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/pairing_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/printer/printer_screen.dart';
import 'features/settings/custom_theme_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/splash/splash_screen.dart';
import 'providers/custom_theme_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/update_provider.dart';
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
        // Guard against stale IDs (printer removed while screen was open).
        final printer = PrinterRegistry.instance.printers
            .where((p) => p.id == id)
            .firstOrNull;
        if (printer == null) return const DashboardScreen();
        return PrinterScreen(printer: printer);
      },
    ),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    GoRoute(
      path: '/theme/custom',
      builder: (_, __) => const CustomThemeScreen(),
    ),
  ],
);

class MoongateApp extends ConsumerStatefulWidget {
  const MoongateApp({super.key});

  @override
  ConsumerState<MoongateApp> createState() => _MoongateAppState();
}

class _MoongateAppState extends ConsumerState<MoongateApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-run the subnet locality check whenever the app comes back to the
    // foreground.  The phone may have moved to a different WiFi network
    // while we were backgrounded — without this refresh, the live
    // preferences we computed at cold-start would be stale and the printer
    // screen could try a now-unreachable local IP.
    if (state == AppLifecycleState.resumed) {
      PrinterRegistry.instance.refreshNetworkLocality();
      // Re-run the in-app update check too.  Without this the FutureProvider
      // would keep its first-launch cached result for the entire session, so
      // a user who had the app open before CI published a new release would
      // never see the banner appear even after the new version went live.
      ref.invalidate(updateProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appMode   = ref.watch(themeModeProvider);
    final fontScale = ref.watch(fontScaleProvider);
    final custom    = ref.watch(customThemeProvider);

    // When the user has picked Custom, force both light and dark slots to the
    // same custom theme — the user is taking over colour decisions so the
    // system's dark-mode toggle should not flip anything on us.
    final isCustom  = appMode == AppThemeMode.custom;
    final lightTheme = isCustom ? _buildCustomTheme(custom) : _buildSeededTheme(Brightness.light);
    final darkTheme  = isCustom ? _buildCustomTheme(custom) : _buildSeededTheme(Brightness.dark);

    return MaterialApp.router(
      title: 'Moongate',
      themeMode: _toFlutterMode(appMode),
      theme: lightTheme,
      darkTheme: darkTheme,
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

  /// Flutter's MaterialApp doesn't know about our extra `custom` value, so
  /// fall through to `dark` for it.  When in custom mode we set `theme` and
  /// `darkTheme` to the same thing anyway, so the mode passed here is moot.
  ThemeMode _toFlutterMode(AppThemeMode m) => switch (m) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light  => ThemeMode.light,
        AppThemeMode.dark   => ThemeMode.dark,
        AppThemeMode.custom => ThemeMode.dark,
      };

  /// The original purple-seeded Material 3 theme.  Used for system / light /
  /// dark.
  ThemeData _buildSeededTheme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6C63FF),
        brightness: brightness,
      ),
    );
  }

  /// Build a [ThemeData] from the user's five custom colours.  Uses
  /// [ColorScheme.fromSeed] with the accent as the seed so all the Material 3
  /// derivative slots (primary container, tertiary, etc.) stay harmonious,
  /// then overrides the slots the user explicitly picked.
  ThemeData _buildCustomTheme(CustomTheme c) {
    final isLightBg = c.background.computeLuminance() > 0.5;
    final brightness = isLightBg ? Brightness.light : Brightness.dark;

    Color contrastingOn(Color bg) =>
        bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    final base = ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
    );

    final scheme = base.copyWith(
      primary:                 c.accent,
      onPrimary:               contrastingOn(c.accent),
      // All "surface*" slots are M3's modern way of expressing the old
      // "background" + "card" pairing.  We map background → surface (page
      // bg) and the user's surface → all surfaceContainer* tiers (card bg).
      surface:                 c.background,
      onSurface:               c.text,
      surfaceContainerLowest:  c.background,
      surfaceContainerLow:     Color.lerp(c.background, c.surface, 0.5)!,
      surfaceContainer:        c.surface,
      surfaceContainerHigh:    c.surface,
      surfaceContainerHighest: c.surface,
      error:                   c.error,
      onError:                 contrastingOn(c.error),
      outline:                 c.text.withValues(alpha: 0.3),
      outlineVariant:          c.text.withValues(alpha: 0.15),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      cardColor: c.surface,
    );
  }
}
