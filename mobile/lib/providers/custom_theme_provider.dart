import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-configurable theme colours.  Five slots cover every meaningful
/// surface in the app:
///
///   • [accent]      — primary colour: FAB, buttons, progress bars, links
///   • [background]  — scaffold (page) background
///   • [surface]     — cards, sheets, drawer, dashboard tiles
///   • [text]        — primary on-surface text
///   • [error]       — destructive actions, error overlays, "Stop" button
///
/// Persisted as a JSON-encoded `{slot → "#RRGGBB"}` map under a single
/// SharedPreferences key.  Defaults match the seeded purple dark theme so
/// switching to "Custom" the first time looks identical to "Dark" until
/// the user actually edits something.
class CustomTheme {
  final Color accent;
  final Color background;
  final Color surface;
  final Color text;
  final Color error;

  /// Colour of the dashboard E-STOP button's ring + icon. Defaults to the
  /// classic emergency red. Applied on the Custom theme only (see
  /// printer_tile's _EstopButton); rides the custom_theme backup.
  final Color estop;

  /// Printer-tile background opacity, 0.0–1.0 (default 1.0 = opaque). Lets the
  /// custom dashboard background show through the tiles' card/stats area; the
  /// camera feed stays opaque. Applied on the Custom theme only (see
  /// printer_tile / dashboard_screen). Rides the custom_theme backup.
  final double tileOpacity;

  const CustomTheme({
    required this.accent,
    required this.background,
    required this.surface,
    required this.text,
    required this.error,
    this.estop = const Color(0xFFF44336),
    this.tileOpacity = 1.0,
  });

  /// Same palette as the default seeded dark theme so flipping to Custom
  /// without any edits doesn't change anything visually.
  static const defaults = CustomTheme(
    accent:     Color(0xFF6C63FF),
    background: Color(0xFF121212),
    surface:    Color(0xFF1E1E1E),
    text:       Color(0xFFFFFFFF),
    error:      Color(0xFFCF6679),
  );

  CustomTheme copyWith({
    Color? accent,
    Color? background,
    Color? surface,
    Color? text,
    Color? error,
    Color? estop,
    double? tileOpacity,
  }) =>
      CustomTheme(
        accent:     accent     ?? this.accent,
        background: background ?? this.background,
        surface:    surface    ?? this.surface,
        text:       text       ?? this.text,
        error:      error      ?? this.error,
        estop:      estop      ?? this.estop,
        tileOpacity: tileOpacity ?? this.tileOpacity,
      );

  Map<String, dynamic> toJson() => {
        'accent':     hexOf(accent),
        'background': hexOf(background),
        'surface':    hexOf(surface),
        'text':       hexOf(text),
        'error':      hexOf(error),
        'estop':      hexOf(estop),
        'tileOpacity': tileOpacity,
      };

  factory CustomTheme.fromJson(Map<String, dynamic> j) => CustomTheme(
        accent:     parseHex(j['accent']     as String?) ?? defaults.accent,
        background: parseHex(j['background'] as String?) ?? defaults.background,
        surface:    parseHex(j['surface']    as String?) ?? defaults.surface,
        text:       parseHex(j['text']       as String?) ?? defaults.text,
        error:      parseHex(j['error']      as String?) ?? defaults.error,
        estop:      parseHex(j['estop']      as String?) ?? defaults.estop,
        tileOpacity: (j['tileOpacity'] as num?)?.toDouble() ?? 1.0,
      );

  /// "#RRGGBB" uppercase, alpha stripped.  Used for both persistence and
  /// the editor's HEX input field.
  static String hexOf(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    String two(int v) => v.toRadixString(16).padLeft(2, '0');
    return '#${two(r)}${two(g)}${two(b)}'.toUpperCase();
  }

  /// Parse "#RRGGBB" or "RRGGBB".  Returns null on any invalid input so
  /// the caller can fall back to a default rather than crashing.
  static Color? parseHex(String? s) {
    if (s == null) return null;
    var cleaned = s.trim().replaceFirst('#', '');
    if (cleaned.length != 6) return null;
    final n = int.tryParse(cleaned, radix: 16);
    if (n == null) return null;
    return Color(0xFF000000 | n);
  }
}

class CustomThemeNotifier extends Notifier<CustomTheme> {
  static const _key = 'custom_theme';

  @override
  CustomTheme build() => CustomTheme.defaults;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      state = CustomTheme.defaults;
      return;
    }
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      state = CustomTheme.fromJson(j);
    } catch (_) {
      // Corrupted saved data — fall back to defaults rather than crashing.
      state = CustomTheme.defaults;
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.toJson()));
  }

  Future<void> setAccent(Color c)     async { state = state.copyWith(accent: c);     await _save(); }
  Future<void> setBackground(Color c) async { state = state.copyWith(background: c); await _save(); }
  Future<void> setSurface(Color c)    async { state = state.copyWith(surface: c);    await _save(); }
  Future<void> setText(Color c)       async { state = state.copyWith(text: c);       await _save(); }
  Future<void> setError(Color c)      async { state = state.copyWith(error: c);      await _save(); }
  Future<void> setEstop(Color c)      async { state = state.copyWith(estop: c);      await _save(); }
  Future<void> setTileOpacity(double v) async { state = state.copyWith(tileOpacity: v.clamp(0.0, 1.0)); await _save(); }

  Future<void> reset() async {
    state = CustomTheme.defaults;
    await _save();
  }
}

final customThemeProvider =
    NotifierProvider<CustomThemeNotifier, CustomTheme>(CustomThemeNotifier.new);
