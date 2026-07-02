import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/app_lock/app_lock_gate.dart';
import 'features/app_lock/app_lock_settings_screen.dart';
import 'features/auth/pairing_screen.dart';
import 'features/dashboard/advanced_power_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/dashboard/lighting_screen.dart';
import 'features/printer/printer_screen.dart';
import 'features/settings/custom_theme_screen.dart';
import 'features/settings/notification_content_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/tutorial/tutorial_overlay.dart';
import 'l10n/app_localizations.dart';
import 'providers/app_lock_provider.dart';
import 'providers/custom_theme_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/update_provider.dart';
import 'services/lan_discovery_service.dart';
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
    GoRoute(
      path: '/settings/app-lock',
      builder: (_, __) => const AppLockSettingsScreen(),
    ),
    GoRoute(
      path: '/settings/notifications',
      builder: (_, __) => const NotificationContentScreen(),
    ),
    GoRoute(
      path: '/lighting',
      builder: (_, __) => const LightingScreen(),
    ),
    GoRoute(
      path: '/power',
      builder: (_, __) => const AdvancedPowerScreen(),
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
    if (state == AppLifecycleState.paused) {
      // Stamp when we left so the app-lock can decide whether to re-lock on
      // resume (per the user's auto-lock timeout).
      ref.read(lockStateProvider.notifier).markBackgrounded();
    }
    if (state == AppLifecycleState.resumed) {
      // Re-lock if the configured background timeout has elapsed (no-op for the
      // default "only on cold launch").
      ref.read(lockStateProvider.notifier).evaluateOnResume();
      // Re-run the update check so a banner appears if CI published a new
      // release while we were backgrounded.
      ref.invalidate(updateProvider);
      // v0.5.0: kick off an mDNS browse so the LanDiscoveryService cache
      // is current the moment the user is looking at the dashboard.
      // Fire-and-forget - the browse completes in ~5 s in the background
      // and the status service will pick up any new entries on its next
      // poll cycle. See docs/v0.5-lan-discovery-design.md §7.4.
      LanDiscoveryService.instance.refresh().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appMode    = ref.watch(themeModeProvider);
    final fontScale  = ref.watch(fontScaleProvider);
    final custom     = ref.watch(customThemeProvider);
    final localeCode = ref.watch(localeProvider);
    final fontFamily = appFontById(ref.watch(appFontProvider)).family;

    final isCustom = appMode == AppThemeMode.custom;
    final isSystem = appMode == AppThemeMode.system;

    // "Phone colours" reads the wallpaper-derived Material You palette. It only
    // exists on Android 12+, so DynamicColorBuilder hands us null schemes
    // elsewhere (older Android, iOS) and we fall back to the seeded theme.
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final hasDynamic = lightDynamic != null && darkDynamic != null;

        final ThemeData lightTheme;
        final ThemeData darkTheme;
        if (isCustom) {
          // The user is taking over colour decisions, so pin both slots to the
          // same custom theme - the system dark-mode toggle shouldn't flip it.
          lightTheme = darkTheme = _buildCustomTheme(custom, fontFamily);
        } else if (isSystem && hasDynamic) {
          lightTheme = _buildDynamicTheme(lightDynamic, fontFamily);
          darkTheme  = _buildDynamicTheme(darkDynamic, fontFamily);
        } else {
          lightTheme = _buildSeededTheme(Brightness.light, fontFamily);
          darkTheme  = _buildSeededTheme(Brightness.dark, fontFamily);
        }

        return MaterialApp.router(
          title: 'Moongate',
          themeMode: _toFlutterMode(appMode),
          theme: lightTheme,
          darkTheme: darkTheme,
          routerConfig: _router,
          debugShowCheckedModeBanner: false,
          // i18n: a null locale follows the system language (resolved against
          // supportedLocales, English fallback); a non-null code is the user's
          // explicit pick from the language picker.
          locale: localeCode == null ? null : Locale(localeCode),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // Apply font scaling via builder so we inherit the real system
          // MediaQuery (status-bar height, nav-bar height, etc.) rather than
          // discarding it.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(fontScale),
            ),
            // Scale icons by the same factor as text. An Icon defaults to a
            // fixed pixel size; applyTextScaling multiplies that by the ambient
            // textScaler, so the display-size slider grows text and icons
            // together across the whole app rather than fonts alone. Merged at
            // the root so every Icon inherits it (a widget can still opt out
            // with applyTextScaling: false).
            child: IconTheme.merge(
              data: const IconThemeData(applyTextScaling: true),
              // The app-lock overlay sits above the router's Navigator, so no
              // route can render without the lock and the underlying screen is
              // preserved. The tutorial overlay sits below the lock (so a lock
              // screen still covers it) but above the router, so it can
              // spotlight any screen.
              child: AppLockGate(child: TutorialOverlay(child: child!)),
            ),
          ),
        );
      },
    );
  }

  /// Flutter's MaterialApp doesn't know about our extra values. `custom` falls
  /// through to `dark` (in custom mode `theme` and `darkTheme` are identical, so
  /// the mode is moot); `system` follows the device's own light/dark setting so
  /// the Material You palette tracks it.
  ThemeMode _toFlutterMode(AppThemeMode m) => switch (m) {
        AppThemeMode.light  => ThemeMode.light,
        AppThemeMode.dark   => ThemeMode.dark,
        AppThemeMode.custom => ThemeMode.dark,
        AppThemeMode.system => ThemeMode.system,
      };

  /// The original purple-seeded Material 3 theme.  Used for light / dark.
  ThemeData _buildSeededTheme(Brightness brightness, String? fontFamily) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6C63FF),
        brightness: brightness,
      ),
    );
  }

  /// Build a [ThemeData] from a system-supplied dynamic [ColorScheme] - the
  /// Android 12+ "Material You" palette handed to us by DynamicColorBuilder.
  /// Each scheme already carries its own brightness, so the light and dark
  /// slots are built from the two schemes the builder provides.
  ThemeData _buildDynamicTheme(ColorScheme scheme, String? fontFamily) {
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      fontFamily: fontFamily,
      colorScheme: scheme,
    );
  }

  /// Build a [ThemeData] from the user's five custom colours.  Uses
  /// [ColorScheme.fromSeed] with the accent as the seed so all the Material 3
  /// derivative slots (primary container, tertiary, etc.) stay harmonious,
  /// then overrides the slots the user explicitly picked.
  ThemeData _buildCustomTheme(CustomTheme c, String? fontFamily) {
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
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      cardColor: c.surface,
    );
  }
}
