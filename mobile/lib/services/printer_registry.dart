import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/printer_config.dart';
import 'settings_backup.dart';
import 'supabase_service.dart';

/// In v0.3.0 the source of truth is the Supabase `printers` table. The
/// registry is a local cache of that table for this user, populated on
/// demand and persisted to SharedPreferences so the dashboard renders
/// immediately on cold start.
///
/// Cross-tenant isolation is enforced by Row-Level Security at the
/// database layer - `select my printers` policy filters every query to
/// `owner_user_id = auth.uid()`. There is no way to see another user's
/// printers from this code path.
class PrinterRegistry {
  PrinterRegistry._();
  static final PrinterRegistry instance = PrinterRegistry._();

  static const _key = 'moongate_printers';

  List<PrinterConfig> _printers = [];

  List<PrinterConfig> get printers => List.unmodifiable(_printers);

  void _log(String msg) => dev.log(msg, name: 'MOONGATE/REGISTRY');

  // ── Local persistence ────────────────────────────────────────────────────

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Pull the latest from disk before reading. The print-notification
    // background isolate shares this registry but keeps its OWN cached
    // SharedPreferences snapshot - and as a foreground service it survives UI
    // restarts, so without a reload it never sees printers the main app
    // added/restored after the isolate started (the notification stuck on
    // "No Printers"). reload() also lets either side pick up removals.
    await prefs.reload();
    final raw   = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _printers = [];
      return;
    }
    try {
      _printers = PrinterConfig.listFromJson(raw);
      await _pruneOrphanLightStatus();
    } on FormatException catch (e) {
      // Legacy v0.2.x payload - drop it. The user will re-pair via the
      // new v=3 QR flow.
      _log('Dropping legacy persisted printers (${e.message})');
      _printers = [];
      await prefs.remove(_key);
    } catch (e) {
      _log('Corrupted printers JSON, dropping: $e');
      _printers = [];
      await prefs.remove(_key);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, PrinterConfig.listToJson(_printers));
  }

  /// One-off cleanup (v0.9.8): an early build auto-filled a light status object
  /// on printers with no light macros - sometimes even a non-light object like a
  /// display neopixel or a motor-power pin. A status object is meaningless
  /// without a control macro, so drop these orphans. Idempotent.
  Future<void> _pruneOrphanLightStatus() async {
    var changed = false;
    _printers = _printers.map((p) {
      final hasMacro = (p.lightOnMacro?.isNotEmpty ?? false) ||
          (p.lightOffMacro?.isNotEmpty ?? false) ||
          (p.lightToggleMacro?.isNotEmpty ?? false);
      if (!hasMacro && (p.lightStatusObject?.isNotEmpty ?? false)) {
        changed = true;
        return p.copyWith(lightStatusObject: null);
      }
      return p;
    }).toList();
    if (changed) await _save();
  }

  /// Pulls the current user's printers from Supabase (RLS-scoped) and
  /// merges them into the local cache. Local-only additions made during
  /// the same session (e.g. just-claimed printers) are preserved.
  ///
  /// Called from the dashboard on launch and on pull-to-refresh.
  Future<void> refreshFromSupabase() async {
    if (!SupabaseService.instance.ready) {
      _log('Supabase not ready, skipping refresh');
      return;
    }
    try {
      final rows = await SupabaseService.instance.listMyPrinters();
      final newList = <PrinterConfig>[];
      for (final r in rows) {
        // Preserve cached webcam settings if we already know this printer.
        final existing = _printers.where((p) => p.id == r.id).firstOrNull;
        newList.add(existing != null
            ? existing.copyWith(name: r.name)
            : PrinterConfig(id: r.id, name: r.name));
      }
      _printers = newList;
      await _save();
      _log('Refreshed: ${_printers.length} printer(s) from Supabase');
    } catch (e) {
      _log('refreshFromSupabase failed: $e');
    }
  }

  /// Add a printer locally after a successful claim. The Supabase row
  /// already exists by the time this is called; this just caches it.
  Future<void> addClaimed(PrinterConfig printer) async {
    final exists = _printers.any((p) => p.id == printer.id);
    if (!exists) {
      _printers = [..._printers, printer];
      await _save();
    }
  }

  /// Legacy alias for [addClaimed], retained for API compatibility.
  Future<void> add(PrinterConfig printer) => addClaimed(printer);

  /// Opens the SAF document picker, parses a Moongate backup, and restores it.
  /// The backup's printers are applied in their saved order - existing entries
  /// are updated to the backup's per-tile config, missing ones are added - and
  /// by DEFAULT any local printer the backup doesn't contain is KEPT (a merge,
  /// so restoring an old backup can't wipe printers paired since it was made).
  /// Removing those extras instead, so the dashboard matches the backup
  /// exactly, is an explicit choice: [resolveExtras] is invoked with them and
  /// returns true to remove, false to keep, or null to cancel the whole
  /// restore (leaving the single-use restore code unspent). With no callback
  /// wired (the first-launch import is always onto an empty list, so extras
  /// can't normally arise) they are kept.
  ///
  /// Returns the outcome, or null if the user cancelled the picker or the
  /// keep-or-remove dialog. Throws on a malformed / unreadable file so the
  /// caller can surface an error.
  ///
  /// Shared by the dashboard "Restore config" item and the first-launch pairing
  /// screen. A backup carries the printer list only, NOT the Supabase anon
  /// identity - restored printers stay offline until reclaimed by the restore
  /// code or re-paired (a reinstall gets a new cloud identity).
  Future<ImportOutcome?> importFromBackupFile({
    Future<bool?> Function(List<PrinterConfig> extras)? resolveExtras,
  }) async {
    // withData:true returns bytes inline rather than a path we may not be able
    // to read under scoped storage. Accept any file type (Android often greys
    // out custom .json filters) and validate by parsing instead.
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select a Moongate backup',
      withData: true,
    );
    if (picked == null) return null; // user cancelled
    final bytes = picked.files.single.bytes;
    if (bytes == null) throw const FormatException('unreadable_file');

    // Two shapes: a legacy bare array (printers only) or the v2/v3 envelope
    // { backup_version, restore_code?, printers: [...], settings? }.
    final decoded = jsonDecode(utf8.decode(bytes));
    final List<PrinterConfig> imported;
    String? restoreCode;
    Map<String, dynamic>? backedUpSettings;
    if (decoded is List) {
      imported = decoded
          .map((e) => PrinterConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } else if (decoded is Map<String, dynamic>) {
      final list = (decoded['printers'] as List<dynamic>?) ?? const [];
      imported = list
          .map((e) => PrinterConfig.fromJson(e as Map<String, dynamic>))
          .toList();
      final code = decoded['restore_code'];
      if (code is String && code.isNotEmpty) restoreCode = code;
      final s = decoded['settings'];
      if (s is Map<String, dynamic>) backedUpSettings = s;
    } else {
      throw const FormatException('unrecognised_backup');
    }

    // Merge by default: the backup's printers are applied, and local printers
    // the backup doesn't contain are KEPT unless the user explicitly chooses
    // otherwise. Ask BEFORE redeeming the single-use restore code so backing
    // out costs nothing. With no callback wired (the first-launch import is
    // always onto an empty list, so extras can't normally arise) keep them.
    final importedIds = imported.map((p) => p.id).toSet();
    final previousIds = _printers.map((p) => p.id).toSet();
    final extras =
        _printers.where((p) => !importedIds.contains(p.id)).toList();
    var dropExtras = false;
    if (extras.isNotEmpty && resolveExtras != null) {
      final removeExtras = await resolveExtras(extras);
      if (removeExtras == null) return null; // cancelled → nothing changes
      dropExtras = removeExtras;
    }

    // Reclaim ownership FIRST so the restored printers resolve online on their
    // first poll. Best-effort: an invalid/expired code or a network error just
    // leaves them offline until re-paired.
    var reconnectedCount = 0;
    final hadRestoreCode = restoreCode != null;
    if (restoreCode != null) {
      try {
        final reclaimed =
            await SupabaseService.instance.redeemRestoreGrant(restoreCode);
        // redeemRestoreGrant returns null on 404 (invalid / expired / already
        // used) and the re-homed count otherwise - which can legitimately be 0
        // (a valid code that matched no live printers). Only a count > 0 means
        // anything actually came back online.
        reconnectedCount = reclaimed ?? 0;
      } catch (e) {
        _log('redeemRestoreGrant failed during import: $e');
      }
    }

    // Rebuild the list from the backup, in its saved order: existing printers
    // are updated to the backup's per-tile config, missing ones added, and any
    // not in the backup kept on the end (the merge default) - or dropped when
    // the user explicitly chose to match the backup exactly.
    _printers = dropExtras
        ? List<PrinterConfig>.of(imported)
        : [...imported, ...extras];
    await _save();
    final added = imported.where((p) => !previousIds.contains(p.id)).length;

    // Apply any global app settings the backup carried (theme, colours,
    // columns, language, …). The allow-list inside SettingsBackup gates what
    // can be written; the UI reloads the providers afterwards to show it live.
    if (backedUpSettings != null) {
      await SettingsBackup.apply(backedUpSettings);
    }

    return ImportOutcome(
      added: added,
      removed: dropExtras ? extras.length : 0,
      reconnectedCount: reconnectedCount,
      hadRestoreCode: hadRestoreCode,
    );
  }

  /// Remove the local cache entry. Note: this does NOT delete the row
  /// from Supabase - for that, the user should run MOONGATE_RESET_OWNER
  /// on the Pi (it'll be cleaned up by the 6-week inactivity sweep
  /// thereafter, since no heartbeats can succeed once unpaired).
  Future<void> remove(String printerId) async {
    _printers = _printers.where((p) => p.id != printerId).toList();
    await _save();
  }

  /// Wipe the local printer list. Used by "Delete my data" once the cloud
  /// records have been deleted, so the dashboard reflects the empty state
  /// immediately instead of waiting on a Supabase refresh.
  Future<void> clear() async {
    _printers = [];
    await _save();
  }

  /// Persist a user-defined ordering of the printer list (set by drag-to-reorder
  /// on the dashboard when auto-arrange is off). The persisted list order *is*
  /// the dashboard order, so this just re-sequences and saves - it rides backups
  /// for free.
  ///
  /// [orderedIds] is the full set of printer ids in the desired order. Defensive
  /// against a concurrent pair/remove: ids we don't know are skipped, and any
  /// printer the list omits is appended in its current relative order so it can
  /// never be dropped. No-op when nothing actually moved.
  Future<void> setOrder(List<String> orderedIds) async {
    final byId = {for (final p in _printers) p.id: p};
    final reordered = <PrinterConfig>[];
    for (final id in orderedIds) {
      final p = byId.remove(id);
      if (p != null) reordered.add(p);
    }
    // Whatever wasn't named (e.g. paired on another isolate mid-drag) keeps its
    // original relative position rather than vanishing.
    for (final p in _printers) {
      if (byId.containsKey(p.id)) reordered.add(p);
    }
    final unchanged = reordered.length == _printers.length &&
        Iterable<int>.generate(reordered.length)
            .every((i) => reordered[i].id == _printers[i].id);
    if (unchanged) return;
    _printers = reordered;
    await _save();
  }

  /// Rename a printer locally. Note: the Supabase row's `name` field is
  /// left unchanged - the local rename is cosmetic only. Re-pairing would
  /// reset to whatever name was sent during the claim.
  Future<void> renamePrinter(String printerId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final idx = _printers.indexWhere((p) => p.id == printerId);
    if (idx == -1) return;
    if (_printers[idx].name == trimmed) return;
    _printers = List.of(_printers)
      ..[idx] = _printers[idx].copyWith(name: trimmed);
    await _save();
  }

  /// Flip a printer between cloud and Direct (LAN/VPN) mode. Only meaningful
  /// for cloud-paired printers - a Direct-added `lan-` id has no cloud row to
  /// go back to (see PrinterConfig.cloudPaired). The status/control services
  /// read the flag registry-live, so it takes effect on the next poll with no
  /// restart.
  Future<void> setLanOnly(String printerId, bool lanOnly) async {
    final idx = _printers.indexWhere((p) => p.id == printerId);
    if (idx == -1) return;
    if (_printers[idx].lanOnly == lanOnly) return;
    _printers = List.of(_printers)
      ..[idx] = _printers[idx].copyWith(lanOnly: lanOnly);
    await _save();
  }

  /// Update the cached LAN URL for a printer after a /status response
  /// surfaces it. Pass null to clear (e.g. when LAN starts failing).
  Future<void> updateLanUrl(String printerId, String? lanUrl) async {
    final idx = _printers.indexWhere((p) => p.id == printerId);
    if (idx == -1) return;
    if (_printers[idx].lanUrl == lanUrl) return;
    _printers = List.of(_printers)
      ..[idx] = _printers[idx].copyWith(lanUrl: lanUrl);
    await _save();
  }

  /// Persist the user's custom camera URL override (set from the tile gear).
  /// Pass null to clear it and fall back to the Pi-reported webcam.
  Future<void> updateCustomCameraUrl(String printerId, String? url) async {
    final idx = _printers.indexWhere((p) => p.id == printerId);
    if (idx == -1) return;
    if (_printers[idx].customCameraUrl == url) return;
    _printers = List.of(_printers)
      ..[idx] = _printers[idx].copyWith(customCameraUrl: url);
    await _save();
  }

  /// Persist which camera the tile's switcher picked (the camera's uid/name
  /// key, see [PrinterWebcam.key]). Pass null to fall back to the printer's
  /// first camera.
  Future<void> updateSelectedWebcam(String printerId, String? key) async {
    final idx = _printers.indexWhere((p) => p.id == printerId);
    if (idx == -1) return;
    if (_printers[idx].selectedWebcam == key) return;
    _printers = List.of(_printers)
      ..[idx] = _printers[idx].copyWith(selectedWebcam: key);
    await _save();
  }

  /// Persist whether this printer's webcam is hidden on the dashboard (set from
  /// the camera dialog). When true the tile renders compact (band-only) and the
  /// masonry grid packs it tightly. Rides backups via [PrinterConfig.hideWebcam].
  Future<void> updateHideWebcam(String printerId, bool hide) async {
    final idx = _printers.indexWhere((p) => p.id == printerId);
    if (idx == -1) return;
    if (_printers[idx].hideWebcam == hide) return;
    _printers = List.of(_printers)
      ..[idx] = _printers[idx].copyWith(hideWebcam: hide);
    await _save();
  }

  /// Persist the user's favourited macros for a printer - the ones starred in
  /// the macro sheet to pin them to the top of the list. The full set is stored
  /// each time (not a delta), so passing an empty list clears them. Rides
  /// backups for free via [PrinterConfig.favouriteMacros].
  Future<void> updateFavouriteMacros(
      String printerId, List<String> macros) async {
    final idx = _printers.indexWhere((p) => p.id == printerId);
    if (idx == -1) return;
    _printers = List.of(_printers)
      ..[idx] = _printers[idx].copyWith(favouriteMacros: macros);
    await _save();
  }

  Future<void> updateMacroControls(
      String printerId, List<MacroControl> controls) async {
    final idx = _printers.indexWhere((p) => p.id == printerId);
    if (idx == -1) return;
    _printers = List.of(_printers)
      ..[idx] = _printers[idx].copyWith(macroControls: controls);
    await _save();
  }

  Future<void> updateControlPanelModules(
      String printerId, List<ControlPanelModule> modules) async {
    final idx = _printers.indexWhere((p) => p.id == printerId);
    if (idx == -1) return;
    _printers = List.of(_printers)
      ..[idx] = _printers[idx].copyWith(controlPanelModules: modules);
    await _save();
  }

  /// Persist a printer's lighting config (v0.9.8): the enable flag, the on/off
  /// and toggle macros, and the optional status object. Full replace each call
  /// (the lighting screen always supplies the complete config); rides backups
  /// via [PrinterConfig]. Pass null for any macro/object to clear it.
  Future<void> updateLightingConfig(
    String printerId, {
    required bool enabled,
    String? onMacro,
    String? offMacro,
    String? toggleMacro,
    String? statusObject,
  }) async {
    final idx = _printers.indexWhere((p) => p.id == printerId);
    if (idx == -1) return;
    _printers = List.of(_printers)
      ..[idx] = _printers[idx].copyWith(
        lightingEnabled:   enabled,
        lightOnMacro:      onMacro,
        lightOffMacro:     offMacro,
        lightToggleMacro:  toggleMacro,
        lightStatusObject: statusObject,
      );
    await _save();
  }

  /// Persist a printer's advanced-power config (v0.9.11): the enable flag and
  /// the on/off + toggle macros. Full replace each call (the screen always
  /// supplies the complete config); rides backups via [PrinterConfig]. Pass
  /// null for any macro to clear it.
  Future<void> updatePowerMacroConfig(
    String printerId, {
    required bool enabled,
    String? onMacro,
    String? offMacro,
    String? toggleMacro,
  }) async {
    final idx = _printers.indexWhere((p) => p.id == printerId);
    if (idx == -1) return;
    _printers = List.of(_printers)
      ..[idx] = _printers[idx].copyWith(
        powerMacroEnabled: enabled,
        powerOnMacro:      onMacro,
        powerOffMacro:     offMacro,
        powerToggleMacro:  toggleMacro,
      );
    await _save();
  }

  /// Persist the detected web UI type ('mainsail' | 'fluidd') so the tile
  /// can render the right logo on a cold launch - including when the
  /// printer is currently offline (power-off, Pi rebooting, etc.).
  Future<void> updateUiType(String printerId, String uiType) async {
    final idx = _printers.indexWhere((p) => p.id == printerId);
    if (idx == -1) return;
    if (_printers[idx].uiType == uiType) return;
    _printers = List.of(_printers)
      ..[idx] = _printers[idx].copyWith(uiType: uiType);
    await _save();
  }

  /// Update webcam transform info from a successful Moongate /status poll.
  Future<void> updateWebcamInfo(
    String printerId, {
    required bool flipH,
    required bool flipV,
    required int  rotation,
    required int  targetFps,
  }) async {
    final idx = _printers.indexWhere((p) => p.id == printerId);
    if (idx == -1) return;
    final p = _printers[idx];
    if (p.webcamFlipH == flipH &&
        p.webcamFlipV == flipV &&
        p.webcamRotation == rotation &&
        p.webcamTargetFps == targetFps) {
      return;
    }
    _printers = List.of(_printers)
      ..[idx] = p.copyWith(
          webcamFlipH:     flipH,
          webcamFlipV:     flipV,
          webcamRotation:  rotation,
          webcamTargetFps: targetFps);
    await _save();
  }

  // ── v0.2.x compat stubs (kept so the UI doesn't break) ──────────────────

  /// Always returns true now - in v0.3.0 every printer is reached via the
  /// Supabase-mediated tunnel.
  bool? livePreferRemote(String printerId) => true;

  /// No-op in v0.3.0 - kept so PrinterStatusService doesn't break.
  void setLivePreferRemote(String printerId, bool preferRemote) {}

  /// No-op in v0.3.0 - Pi reports its tunnel URL to Supabase, and the
  /// app fetches the current one on every access call. There's nothing
  /// to persist client-side.
  Future<void> updateRemoteHost(String printerId, String newRemoteHost) async {}
}

/// Result of PrinterRegistry.importFromBackupFile.
class ImportOutcome {
  /// Printers added to the local list (ones the backup had that weren't already
  /// present).
  final int added;

  /// Printers removed because the backup didn't contain them (a confirmed
  /// full-replace restore). 0 on a clean install, or when extras were kept.
  final int removed;

  /// How many printers the backup's restore code actually re-homed to THIS
  /// identity. 0 if the backup had no code, the code was invalid / expired /
  /// already-used, or it matched no live printers - in every one of those
  /// cases nothing comes back online without a re-pair.
  final int reconnectedCount;

  /// True when the backup carried a restore code at all (so a reconnect was
  /// attempted). Lets the UI tell a "list-only backup" apart from "had a code
  /// but it reclaimed nothing".
  final bool hadRestoreCode;

  /// True only when at least one printer was actually re-bound - i.e. printers
  /// will come back online without a re-pair. Previously this was
  /// `reclaimed != null`, which was ALSO true for a valid-but-0-printer redeem,
  /// so the UI falsely claimed "reconnected".
  bool get reconnected => reconnectedCount > 0;

  const ImportOutcome({
    required this.added,
    this.removed = 0,
    required this.reconnectedCount,
    required this.hadRestoreCode,
  });
}
