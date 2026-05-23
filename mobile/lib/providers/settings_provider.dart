import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Theme mode
// ---------------------------------------------------------------------------

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() => ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    state = switch (raw) {
      'light'  => ThemeMode.light,
      'system' => ThemeMode.system,
      _        => ThemeMode.dark,
    };
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

// ---------------------------------------------------------------------------
// Font scale
// ---------------------------------------------------------------------------

class FontScaleNotifier extends Notifier<double> {
  static const _key = 'font_scale';

  @override
  double build() => 1.0;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getDouble(_key) ?? 1.0;
  }

  Future<void> set(double scale) async {
    state = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, scale);
  }
}

final fontScaleProvider = NotifierProvider<FontScaleNotifier, double>(
  FontScaleNotifier.new,
);

// ---------------------------------------------------------------------------
// Grid columns  (1 | 2 | 3 — portrait preference; landscape auto-bumps +1)
// ---------------------------------------------------------------------------

class GridColumnsNotifier extends Notifier<int> {
  static const _key = 'grid_columns';

  @override
  int build() => 2;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt(_key) ?? 2;
  }

  Future<void> set(int cols) async {
    state = cols;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, cols);
  }
}

final gridColumnsProvider = NotifierProvider<GridColumnsNotifier, int>(
  GridColumnsNotifier.new,
);

// ---------------------------------------------------------------------------
// Allow rotation  (false = portrait-locked, true = follows device)
// ---------------------------------------------------------------------------

class AllowRotationNotifier extends Notifier<bool> {
  static const _key = 'allow_rotation';

  @override
  bool build() => false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
    await _applyOrientation(state);
  }

  Future<void> set(bool allow) async {
    state = allow;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, allow);
    await _applyOrientation(allow);
  }

  Future<void> _applyOrientation(bool allow) =>
      SystemChrome.setPreferredOrientations(
        allow
            ? [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
              ],
      );
}

final allowRotationProvider = NotifierProvider<AllowRotationNotifier, bool>(
  AllowRotationNotifier.new,
);
