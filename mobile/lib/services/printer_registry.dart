import 'package:shared_preferences/shared_preferences.dart';

import '../models/printer_config.dart';

/// Persists the list of paired printers to SharedPreferences.
class PrinterRegistry {
  PrinterRegistry._();
  static final PrinterRegistry instance = PrinterRegistry._();

  static const _key = 'moongate_printers';

  List<PrinterConfig> _printers = [];

  List<PrinterConfig> get printers => List.unmodifiable(_printers);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      _printers = PrinterConfig.listFromJson(raw);
    } catch (_) {
      // Saved data is corrupted or from an incompatible old version.
      // Clear it so the app starts clean rather than crashing every launch.
      _printers = [];
      await prefs.remove(_key);
    }
  }

  Future<void> add(PrinterConfig printer) async {
    _printers = [..._printers, printer];
    await _save();
  }

  Future<void> remove(String printerId) async {
    _printers = _printers.where((p) => p.id != printerId).toList();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, PrinterConfig.listToJson(_printers));
  }
}
