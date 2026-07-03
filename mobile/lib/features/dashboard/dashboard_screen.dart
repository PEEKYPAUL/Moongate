import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../providers/custom_theme_provider.dart';
import '../../providers/dashboard_background_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/update_provider.dart';
import '../../providers/version_provider.dart';
import '../../services/changelog_service.dart';
import '../../services/ota_installer.dart';
import '../../services/print_notification_service.dart';
import '../../services/printer_access_cache.dart';
import '../../services/printer_registry.dart';
import '../../services/printer_status_registry.dart';
import '../../services/printer_webview_cache.dart';
import '../../services/settings_backup.dart';
import '../../services/supabase_service.dart';
import '../../services/update_service.dart';
import '../donation/donation_prompt.dart';
import '../info/ui_guide.dart';
import '../language/language_picker.dart';
import '../notifications/notifications_prompt.dart';
import '../tutorial/tutorial_anchors.dart';
import '../tutorial/tutorial_controller.dart';
import '../tutorial/tutorial_offer.dart';
import 'feedback_sheet.dart';
import 'printer_tile.dart';
import 'camera_feeds_overlay.dart';
import 'webcams_overlay.dart';
import 'power_all_sheet.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<PrinterConfig> _printers = [];
  bool _updateDismissed = false;

  /// Lets the live tutorial open/close the end drawer to demo the menu.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _tutorialDrawerOpen = false;

  /// True once the first _load() has run, so the "offer the tutorial on the
  /// first printer" trigger fires on a real pairing, not the initial load.
  bool _firstLoadDone = false;

  /// Guards against the tutorial offer popup being shown twice at once.
  bool _tutorialOfferInFlight = false;

  /// Transient (not persisted) manual-reorder editing state. Only meaningful
  /// when auto-arrange is off: true = tiles draggable + hint shown ("arranging");
  /// false = tiles locked in their saved order, dashboard clean ("settled").
  /// Toggled by the bottom-left Reorder/Done button.
  bool _reordering = false;

  // Always-visible scrollbar for the drawer body so small-screen users can see
  // there's more below the fold (user-reported - not obvious it scrolled).
  final ScrollController _drawerScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    // Show the pairing/reinstall explainer on cold launch until the user opts
    // out ("Don't show again"). Post-frame so the dialog has a mounted context.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _runFirstRunOnboarding().ignore());
  }

  @override
  void dispose() {
    _drawerScroll.dispose();
    super.dispose();
  }

  void _load() {
    final list = PrinterRegistry.instance.printers;
    final wasEmpty = _printers.isEmpty;
    if (mounted) setState(() => _printers = list);
    // Keep the print-notification isolate's printer list in step - it reads a
    // separate cached snapshot, so poke it whenever the set may have changed
    // (pair / remove / restore). No-op when notifications are off.
    PrintNotificationService.instance.refreshNow().ignore();
    // Offer the walkthrough the moment the user's first printer lands on the
    // dashboard (not just on the next cold launch). Skipped on the initial load
    // - the first-run sequence handles existing users.
    if (_firstLoadDone && wasEmpty && list.isNotEmpty) {
      _maybeOfferTutorial();
    }
    _firstLoadDone = true;
  }

  /// Persist a drag-to-reorder from the dashboard grid (manual mode only).
  /// reorderable_grid_view reports the *final* index directly, so this is a
  /// plain removeAt/insert - no ReorderableListView-style `-1` fix-up. The new
  /// order is written through the registry (the dashboard's order of record;
  /// rides backups).
  void _onReorder(int oldIndex, int newIndex) {
    final reordered = List<PrinterConfig>.of(_printers);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    setState(() => _printers = reordered);
    PrinterRegistry.instance
        .setOrder([for (final p in reordered) p.id])
        .ignore();
  }

  /// Flip the auto-arrange setting from the drawer. Turning it OFF drops the
  /// dashboard straight into arranging mode (tiles immediately draggable, so the
  /// feature is right there); turning it back ON ends any arranging session.
  void _setAutoArrange(bool enabled) {
    ref.read(autoArrangeProvider.notifier).set(enabled);
    setState(() => _reordering = !enabled);
  }

  /// Stable-sort the printer list by live status priority (printerStatusRank,
  /// shared with the notification): Error → Printing → Ready → Idle → Offline,
  /// keeping the added/dashboard order within each tier. A printer that hasn't
  /// polled yet counts as 'connecting' (Idle tier). Recomputed on every status
  /// change via the StreamBuilder in build().
  List<PrinterConfig> _sortByStatus(List<PrinterConfig> list) {
    final ranked = [
      for (var i = 0; i < list.length; i++)
        (
          i,
          list[i],
          printerStatusRank(
            PrinterStatusRegistry.instance.snapshot(list[i].id)?.state ??
                'connecting',
          ),
        ),
    ];
    ranked.sort(
        (a, b) => a.$3 != b.$3 ? a.$3.compareTo(b.$3) : a.$1.compareTo(b.$1));
    return [for (final r in ranked) r.$2];
  }

  Future<void> _removePrinter(PrinterConfig printer) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.dashboardRemovePrinterTitle),
        content: Text(l.dashboardRemovePrinterBody(printer.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonRemove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Release the Supabase row first so the same Pi can be re-paired
    // without manual cleanup. Fail-open: if Supabase is unreachable we
    // still clear local state and surface a hint so the user isn't trapped.
    final released = await SupabaseService.instance.releasePrinter(printer.id);
    await PrinterRegistry.instance.remove(printer.id);
    PrinterAccessCache.instance.invalidate(printer.id);
    PrinterWebViewCache.instance.invalidate(printer.id);

    if (!released && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.dashboardRemoveSupabaseUnreachable),
        ),
      );
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    // The live tutorial opens/closes the menu drawer for its menu steps.
    ref.listen<TutorialState>(
      tutorialControllerProvider,
      (_, next) => _syncTutorialDrawer(next),
    );
    // Check for update - runs once per session, silently ignored on failure.
    final updateAsync = ref.watch(updateProvider);
    final update = _updateDismissed ? null : updateAsync.valueOrNull;

    final gridColumns = ref.watch(gridColumnsProvider);
    final autoArrange = ref.watch(autoArrangeProvider);
    final globalPowerButton = ref.watch(globalPowerButtonProvider);
    final showDashboardButtons = ref.watch(dashboardButtonsProvider);
    // Quick pause/play button in the app bar - only when print notifications are
    // on (the master switch lives in the menu). [notifPaused] flips its icon.
    final printNotifications = ref.watch(printNotificationsEnabledProvider);
    final notifPaused = ref.watch(notificationsPausedProvider);
    // The custom dashboard background is part of the Custom theme - render it
    // only while that theme is active (it's configured on the Custom theme
    // screen, which is only reachable when Custom is selected, so this also
    // keeps the clear-× always in reach).
    final isCustomTheme = ref.watch(themeModeProvider) == AppThemeMode.custom;
    final customBackground =
        isCustomTheme ? ref.watch(dashboardBackgroundProvider) : null;
    // When a background image is set it covers the FULL screen: it wraps the
    // whole Scaffold (see the return below) and the app bar + scaffold go
    // transparent so it shows behind the top bar too, not just the body.
    final hasCustomBg = customBackground != null && customBackground.isNotEmpty;
    // Printer-tile see-through (Custom theme only) so a custom background shows
    // through; 1.0 = opaque (the default, and all non-custom themes).
    final tileOpacity =
        isCustomTheme ? ref.watch(customThemeProvider).tileOpacity : 1.0;

    // Reload after the printer screen pops so any rename done in the app bar
    // there propagates to the tile.
    void openPrinter(PrinterConfig p) =>
        context.push('/printer/${p.id}').then((_) => _load());

    final Widget body;
    if (_printers.isEmpty) {
      body = _EmptyState(
          onAddPrinter: () => context.push('/pair').then((_) => _load()));
    } else if (autoArrange) {
      // Re-sort tiles by live status (active prints float up) whenever a
      // printer's state changes - printerStatusRank, shared with the
      // notification. Tiles are keyed by id so a reorder moves a tile (and
      // its poller) rather than rebuilding it.
      body = StreamBuilder<void>(
        stream: PrinterStatusRegistry.instance.changes,
        builder: (context, _) => _PrinterGrid(
          printers: _sortByStatus(_printers),
          columns: gridColumns,
          onTap: openPrinter,
          tileOpacity: tileOpacity,
        ),
      );
    } else {
      // Manual order: tiles stay where the user put them; entering reorder mode
      // turns the grid into a draggable grid of the actual tiles. Deliberately
      // NOT wrapped in the status StreamBuilder - re-sorting is exactly what the
      // user turned off here, and a rebuild mid-drag would fight the gesture.
      // Each tile still refreshes its own content through its status stream.
      body = Column(
        children: [
          if (_reordering && _printers.length > 1) const _ReorderHint(),
          Expanded(
            child: _PrinterGrid(
              printers: _printers,
              columns: gridColumns,
              onTap: openPrinter,
              tileOpacity: tileOpacity,
              // Non-null only while actively arranging → the draggable reorder
              // list; otherwise the read-only masonry in the saved order.
              onReorder: _reordering ? _onReorder : null,
            ),
          ),
        ],
      );
    }

    final scaffold = Scaffold(
      key: _scaffoldKey,
      backgroundColor: hasCustomBg ? Colors.transparent : null,
      appBar: AppBar(
        backgroundColor: hasCustomBg ? Colors.transparent : null,
        elevation: hasCustomBg ? 0 : null,
        scrolledUnderElevation: hasCustomBg ? 0 : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The Moongate moon-gate logo beside the wordmark.
            SvgPicture.asset('assets/icons/moongate_icon.svg',
                width: 26, height: 26),
            const SizedBox(width: 8),
            const Text('Moongate'),
          ],
        ),
        actions: [
          // Global power button (opt-in, drawer toggle): sits left of the menu
          // and opens the power-all sheet. Hidden unless turned on and there's
          // at least one printer to act on.
          if (globalPowerButton && _printers.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.power_settings_new),
              tooltip: l.globalPowerTooltip,
              onPressed: () => showGlobalPowerSheet(context, _printers),
            ),
          // Quick pause / resume for the print-notification service. Lets the
          // user stop the background polling - and its battery drain - while
          // their printers will be off for a while, without opening the menu.
          // Shown only when notifications are enabled there; icon + tooltip flip
          // with the paused state. Anchor for the one-off first-enable hint.
          if (printNotifications && _printers.isNotEmpty)
            IconButton(
              key: TutorialAnchors.instance.notifPause,
              icon: Icon(notifPaused ? Icons.play_arrow : Icons.pause),
              tooltip:
                  notifPaused ? l.notifResumeTooltip : l.notifPauseTooltip,
              onPressed: _toggleNotificationsPaused,
            ),
          Builder(
            builder: (ctx) => IconButton(
              key: TutorialAnchors.instance.menuIcon,
              icon: const Icon(Icons.menu),
              tooltip: l.dashboardMenuTooltip,
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: _buildDrawer(context),
      // The custom background (when set) wraps the whole Scaffold below and the
      // app bar is transparent, so the body just renders normally on top of it.
      body: ValueListenableBuilder<bool>(
        valueListenable: SupabaseService.instance.signedIn,
        builder: (context, signedIn, _) {
          final banners = <Widget>[
            if (update != null)
              _UpdateBanner(
                update: update,
                onDismiss: () => setState(() => _updateDismissed = true),
                onWhatsNew: () => _showUpdateNotes(context, update),
              ),
            if (!signedIn) const _SignInBanner(),
          ];
          if (banners.isEmpty) return body;
          return Column(
            children: [...banners, Expanded(child: body)],
          );
        },
      ),
      floatingActionButton: (_printers.isEmpty || !showDashboardButtons)
          ? null
          : SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Bottom-left: enter / leave manual reorder mode. Only shown
                    // in manual mode when there's more than one tile to move.
                    // "Done" settles the arrangement and clears the drag hint;
                    // "Reorder" re-enters it. The order itself is already saved
                    // on every drop - this button is purely the editing UI.
                    if (!autoArrange && _printers.length > 1)
                      FloatingActionButton(
                        heroTag: 'reorderFab',
                        onPressed: () =>
                            setState(() => _reordering = !_reordering),
                        backgroundColor: _reordering ? Colors.green : null,
                        foregroundColor: _reordering ? Colors.white : null,
                        // Tooltips keep the action labelled (for accessibility +
                        // long-press) now that the button itself is icon-only.
                        tooltip: _reordering
                            ? l.dashboardReorderDone
                            : l.dashboardReorderStart,
                        child: _reordering
                            ? const Icon(Icons.check)
                            : SvgPicture.asset(
                                'assets/icons/drag_drop.svg',
                                width: 24,
                                height: 24,
                                colorFilter: ColorFilter.mode(
                                    cs.onPrimaryContainer, BlendMode.srcIn),
                              ),
                      )
                    else
                      const SizedBox.shrink(),
                    // Bottom-right: add a printer.
                    FloatingActionButton(
                      key: TutorialAnchors.instance.addPrinter,
                      heroTag: 'addFab',
                      onPressed: () async {
                        await context.push('/pair');
                        _load();
                      },
                      tooltip: l.dashboardAddPrinter,
                      child: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
    // Full-screen custom background: paint it behind the whole (transparent)
    // Scaffold so it covers the app bar + status-bar area, not just the body.
    return hasCustomBg
        ? _DashboardBackground(imagePath: customBackground, child: scaffold)
        : scaffold;
  }

  /// Toggle the opt-in print-notification service. Turning it ON first asks for
  /// the Android 13+ notification permission; if denied, the toggle stays off.
  Future<void> _togglePrintNotifications(bool enable) async {
    if (enable) {
      final granted =
          await PrintNotificationService.instance.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(AppLocalizations.of(context).printNotifPermissionNeeded),
          ));
        }
        return; // leave the toggle off
      }
    }
    await ref.read(printNotificationsEnabledProvider.notifier).set(enable);
    // A fresh (un)toggle clears any prior pause so the service state matches the
    // switch exactly - enabling always starts watching, not silently paused.
    await ref.read(notificationsPausedProvider.notifier).set(false);
    await PrintNotificationService.instance.sync(enable);
  }

  // Serialises _toggleNotificationsPaused: the start/stop it drives await the
  // plugin's async isRunningService check, which is only idempotent when calls
  // don't overlap. Without this, a sub-second double-tap can interleave (tap 2's
  // start() sees the not-yet-torn-down service as "running" and no-ops while
  // tap 1's stop() lands) leaving the service stopped but the flag/icon saying
  // running. Dropping the re-entrant tap keeps the pref, service and icon in step.
  bool _notifPauseBusy = false;

  /// Quick pause / resume from the app bar. Flips the persisted paused flag and
  /// starts or stops the foreground service accordingly, so pausing genuinely
  /// halts the polling (and its battery cost), not just the notification's
  /// display. Only reachable while notifications are enabled, so [enabled] here
  /// is true; the service runs when enabled AND not paused.
  Future<void> _toggleNotificationsPaused() async {
    if (_notifPauseBusy) return; // ignore re-taps until this toggle settles
    _notifPauseBusy = true;
    try {
      final paused = !ref.read(notificationsPausedProvider);
      await ref.read(notificationsPausedProvider.notifier).set(paused);
      final enabled = ref.read(printNotificationsEnabledProvider);
      await PrintNotificationService.instance.sync(enabled && !paused);
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(paused ? l.notifPausedSnack : l.notifResumedSnack),
          duration: const Duration(seconds: 2),
        ));
    } finally {
      _notifPauseBusy = false;
    }
  }

  Widget _buildDrawer(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fontScale     = ref.watch(fontScaleProvider);
    final themeMode     = ref.watch(themeModeProvider);
    final appFont       = ref.watch(appFontProvider);
    // "Phone colours" is only offered where the OS actually provides a palette
    // (Android 12+); elsewhere the option is hidden (see app.dart fallback).
    final dynamicColourSupported =
        ref.watch(dynamicColorSupportedProvider).valueOrNull ?? false;
    final gridColumns   = ref.watch(gridColumnsProvider);
    final allowRotation = ref.watch(allowRotationProvider);
    final autoArrange   = ref.watch(autoArrangeProvider);
    final showCameraIcons = ref.watch(showCameraConfigIconsProvider);
    final printNotifications = ref.watch(printNotificationsEnabledProvider);
    final pollInterval = ref.watch(notifPollIntervalProvider);
    final notifOnlineOnly = ref.watch(notifOnlineOnlyProvider);
    final globalPowerButton = ref.watch(globalPowerButtonProvider);
    final showDashboardButtons = ref.watch(dashboardButtonsProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Row(
                children: [
                  Icon(Icons.print,
                      color: Theme.of(context).colorScheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Text('Moongate',
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            const Divider(),

            // ── Scrollable body (safe in landscape / small screens) ──────────
            Expanded(
              child: Scrollbar(
                controller: _drawerScroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _drawerScroll,
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [

                    // Printer management (grouped for the tutorial spotlight).
                    KeyedSubtree(
                      key: TutorialAnchors.instance.menuPrinters,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                    ListTile(
                      leading: const Icon(Icons.add_circle_outline),
                      title: Text(l.dashboardAddPrinter),
                      onTap: () async {
                        Navigator.pop(context);
                        await context.push('/pair');
                        _load();
                      },
                    ),
                    if (_printers.isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.remove_circle_outline,
                            color: Colors.redAccent),
                        title: Text(l.dashboardRemovePrinter,
                            style: const TextStyle(color: Colors.redAccent)),
                        onTap: () {
                          Navigator.pop(context);
                          _showRemoveSheet(context);
                        },
                      ),
                        ],
                      ),
                    ),

                    const Divider(),

                    // Import / Export (grouped for the tutorial spotlight).
                    KeyedSubtree(
                      key: TutorialAnchors.instance.menuBackup,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                    if (_printers.isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.upload_file_outlined),
                        title: Text(l.dashboardBackUpConfig),
                        subtitle:
                            Text(l.dashboardBackUpConfigSubtitle),
                        onTap: () {
                          Navigator.pop(context);
                          _exportConfig();
                        },
                      ),
                    ListTile(
                      leading: const Icon(Icons.file_download_outlined),
                      title: Text(l.dashboardRestoreConfig),
                      subtitle: Text(l.dashboardRestoreConfigSubtitle),
                      onTap: () {
                        Navigator.pop(context);
                        _importConfig();
                      },
                    ),
                        ],
                      ),
                    ),

                    const Divider(),

                    // Theme
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(l.dashboardThemeHeading,
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: Colors.white54)),
                    ),
                    RadioGroup<AppThemeMode>(
                      key: TutorialAnchors.instance.menuTheme,
                      groupValue: themeMode,
                      onChanged: (v) {
                        if (v == null) return;
                        ref.read(themeModeProvider.notifier).set(v);
                        // Selecting "Custom" should jump straight into the
                        // colour editor - saves the user a second tap and
                        // makes the option discoverable in one click.
                        if (v == AppThemeMode.custom) {
                          Navigator.pop(context);
                          context.push('/theme/custom');
                        }
                      },
                      child: Column(
                        children: [
                          RadioListTile(
                            value: AppThemeMode.dark,
                            title: Text(l.dashboardThemeDark),
                            secondary: const Icon(Icons.dark_mode),
                          ),
                          RadioListTile(
                            value: AppThemeMode.light,
                            title: Text(l.dashboardThemeLight),
                            secondary: const Icon(Icons.light_mode),
                          ),
                          // "Phone colours" (Material You) - shown only where
                          // the OS provides a wallpaper palette (Android 12+).
                          if (dynamicColourSupported)
                            RadioListTile(
                              value: AppThemeMode.system,
                              title: Text(l.dashboardThemeSystem),
                              secondary: const Icon(Icons.auto_awesome),
                            ),
                          RadioListTile(
                            value: AppThemeMode.custom,
                            title: Text(l.dashboardThemeCustom),
                            secondary: const Icon(Icons.palette_outlined),
                          ),
                        ],
                      ),
                    ),
                    // Always offer a way back into the editor - handy when
                    // Custom is already selected and the user just wants to
                    // tweak a colour without re-tapping the radio.
                    if (themeMode == AppThemeMode.custom)
                      ListTile(
                        leading: const Icon(Icons.tune),
                        title: Text(l.dashboardCustomiseColours),
                        subtitle: Text(
                            l.dashboardCustomiseColoursSubtitle),
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/theme/custom');
                        },
                      ),
                    // Font - choose the app typeface. The phone's own system
                    // font can't be read by a Flutter app, so we offer a small
                    // bundled set instead (see appFontProvider).
                    ListTile(
                      leading: const Icon(Icons.font_download_outlined),
                      title: Text(l.dashboardFontHeading),
                      subtitle: Text(
                        appFontById(appFont).label,
                        style: TextStyle(fontFamily: appFontById(appFont).family),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.4),
                      ),
                      onTap: () => _showFontPicker(context),
                    ),
                    const Divider(),

                    // Font size (grouped for the tutorial spotlight).
                    KeyedSubtree(
                      key: TutorialAnchors.instance.menuDisplaySize,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(l.dashboardFontSizeHeading,
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: Colors.white54)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.text_fields, size: 16),
                          Expanded(
                            child: Slider(
                              value: fontScale,
                              min: 0.8,
                              max: 1.4,
                              divisions: 6,
                              label: _fontScaleLabel(fontScale),
                              onChanged: (v) =>
                                  ref.read(fontScaleProvider.notifier).set(v),
                            ),
                          ),
                          const Icon(Icons.text_fields, size: 22),
                        ],
                      ),
                    ),
                        ],
                      ),
                    ),

                    const Divider(),

                    // ── Lighting ──────────────────────────────────────────────
                    // Pulled up here (right under Font size) for quick reach -
                    // it was previously buried near the bottom of the About list.
                    ListTile(
                      leading: const Icon(Icons.lightbulb_outline),
                      title: Text(l.lightingTitle),
                      subtitle: Text(l.lightingMenuSubtitle),
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/lighting').then((_) => _load());
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.power_settings_new),
                      title: Text(l.powerMenuTitle),
                      subtitle: Text(l.powerMenuSubtitle),
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/power').then((_) => _load());
                      },
                    ),

                    const Divider(),

                    // ── Dashboard layout (grouped for the tutorial spotlight) ──
                    KeyedSubtree(
                      key: TutorialAnchors.instance.menuColumns,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(l.dashboardLayoutHeading,
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: Colors.white54)),
                    ),
                    // Column count picker
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: SegmentedButton<int>(
                        // No selected-checkmark - it pushes the label onto a
                        // second line in these narrow segments. Selection is
                        // shown by the highlighted background instead. Icons
                        // dropped too for a clean, single-line look.
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        segments: [
                          ButtonSegment(value: 1, label: Text(l.dashboardColumnCount(1))),
                          ButtonSegment(value: 2, label: Text(l.dashboardColumnCount(2))),
                          ButtonSegment(value: 3, label: Text(l.dashboardColumnCount(3))),
                        ],
                        selected: {gridColumns},
                        onSelectionChanged: (s) =>
                            ref.read(gridColumnsProvider.notifier).set(s.first),
                      ),
                    ),
                        ],
                      ),
                    ),
                    // Rotation toggle
                    SwitchListTile(
                      dense: true,
                      secondary: const Icon(Icons.screen_rotation_outlined),
                      title: Text(l.dashboardRotateWithDevice),
                      subtitle: Text(l.dashboardRotateWithDeviceSubtitle),
                      value: allowRotation,
                      onChanged: (v) =>
                          ref.read(allowRotationProvider.notifier).set(v),
                    ),
                    // Auto-arrange vs. manual drag-to-reorder. ON (default)
                    // keeps the historic status sort; OFF freezes the order and
                    // unlocks long-press drag on the grid.
                    SwitchListTile(
                      dense: true,
                      secondary: const Icon(Icons.swap_vert),
                      title: Text(l.dashboardAutoArrange),
                      subtitle: Text(l.dashboardAutoArrangeSubtitle),
                      value: autoArrange,
                      onChanged: _setAutoArrange,
                    ),
                    // Global power button: adds a power-all control to the top
                    // bar. Off by default - only useful with Moonraker [power]
                    // devices (smart plugs / relays).
                    SwitchListTile(
                      dense: true,
                      secondary: const Icon(Icons.power_settings_new),
                      title: Text(l.globalPowerButtonTitle),
                      subtitle: Text(l.globalPowerButtonSubtitle),
                      value: globalPowerButton,
                      onChanged: (v) =>
                          ref.read(globalPowerButtonProvider.notifier).set(v),
                    ),
                    // Show/hide the floating buttons at the bottom of the
                    // dashboard (add printer + the reorder toggle). ON by
                    // default; users with many printers hide them so they stop
                    // covering the bottom tiles - adding a printer stays in the
                    // menu, and reordering by turning the buttons back on.
                    SwitchListTile(
                      dense: true,
                      secondary: const Icon(Icons.smart_button_outlined),
                      title: Text(l.dashboardShowButtons),
                      subtitle: Text(l.dashboardShowButtonsSubtitle),
                      value: showDashboardButtons,
                      onChanged: (v) =>
                          ref.read(dashboardButtonsProvider.notifier).set(v),
                    ),

                    const Divider(),

                    // ── Camera feeds (grouped for the tutorial spotlight) ──────
                    // Per-path tile webcam refresh rates. Opens a sheet with two
                    // Raw/1s/3s/5s pickers - each tile uses the local rate on the
                    // LAN and the tunnel rate when remote, so the remote feed can
                    // be throttled to save data.
                    KeyedSubtree(
                      key: TutorialAnchors.instance.menuCameras,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.shutter_speed),
                      title: Text(l.cameraFeedsMenuTitle),
                      subtitle: Text(l.cameraFeedsMenuSubtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(context);
                        showCameraFeedsSheet(context);
                      },
                    ),
                    // Per-printer webcam visibility. Opens a sheet listing every
                    // printer with a switch; turning one off collapses its tile
                    // to the compact (no-camera) layout, which the masonry packs
                    // in - and it stops that tile fetching snapshots (data saver).
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.videocam_outlined),
                      title: Text(l.dashboardShowWebcams),
                      subtitle: Text(l.dashboardShowWebcamsSubtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(context);
                        showWebcamsSheet(context).then((_) => _load());
                      },
                    ),
                    // Show / hide the per-tile camera config gear.
                    SwitchListTile(
                      dense: true,
                      secondary: const Icon(Icons.tune),
                      title: Text(l.dashboardShowCameraIcons),
                      subtitle: Text(l.dashboardShowCameraIconsSubtitle),
                      value: showCameraIcons,
                      onChanged: (v) => ref
                          .read(showCameraConfigIconsProvider.notifier)
                          .set(v),
                    ),
                        ],
                      ),
                    ),

                    // Print notifications run on an Android foreground service;
                    // iOS has no equivalent yet, so the whole section (and its
                    // leading divider) is Android-only - don't offer a feature
                    // that does nothing on iOS. See docs/ios-port-plan.md.
                    if (Platform.isAndroid) const Divider(),

                    // ── Print notifications ──────────────────────────────────
                    // Opt-in foreground service: live progress + state alerts.
                    if (Platform.isAndroid)
                      SwitchListTile(
                        dense: true,
                        secondary:
                            const Icon(Icons.notifications_active_outlined),
                        title: Text(l.printNotifTitle),
                        subtitle: Text(l.printNotifSubtitle),
                        value: printNotifications,
                        onChanged: _togglePrintNotifications,
                      ),
                    // Poll cadence - only relevant while notifications are on.
                    if (Platform.isAndroid && printNotifications) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Text(l.notifPollIntervalTitle,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: Colors.white54)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: SegmentedButton<NotifPollInterval>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: [
                            for (final i in NotifPollInterval.values)
                              ButtonSegment(value: i, label: Text(i.label)),
                          ],
                          selected: {pollInterval},
                          onSelectionChanged: (s) {
                            ref
                                .read(notifPollIntervalProvider.notifier)
                                .set(s.first);
                            PrintNotificationService.instance
                                .reschedule()
                                .ignore();
                          },
                        ),
                      ),
                      // Hide offline printers from the persistent status list.
                      SwitchListTile(
                        dense: true,
                        secondary: const Icon(Icons.filter_alt_outlined),
                        title: Text(l.notifOnlineOnlyTitle),
                        subtitle: Text(l.notifOnlineOnlySubtitle),
                        value: notifOnlineOnly,
                        onChanged: (v) {
                          ref.read(notifOnlineOnlyProvider.notifier).set(v);
                          PrintNotificationService.instance
                              .refreshNow()
                              .ignore();
                        },
                      ),
                      // Edit which fields show in the notification + their order.
                      ListTile(
                        leading: const Icon(Icons.format_list_bulleted),
                        title: Text(l.notifContentTitle),
                        subtitle: Text(l.notifContentSubtitle),
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/settings/notifications');
                        },
                      ),
                    ],

                    const Divider(),

                    // ── About (grouped for the tutorial spotlight) ────────────
                    KeyedSubtree(
                      key: TutorialAnchors.instance.menuAbout,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(l.dashboardAboutHeading,
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: Colors.white54)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.new_releases_outlined),
                      title: Text(l.dashboardWhatsNew),
                      subtitle: Text(l.dashboardWhatsNewSubtitle),
                      onTap: () {
                        Navigator.pop(context);
                        _showChangelog(context);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: Text(l.dashboardHowPairingWorks),
                      subtitle: Text(l.dashboardHowPairingWorksSubtitle),
                      onTap: () {
                        Navigator.pop(context);
                        _showPairingHelp(context);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(l.uiGuideTitle),
                      subtitle: Text(l.uiGuideMenuSubtitle),
                      onTap: () {
                        Navigator.pop(context);
                        showUiGuide(context);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.bug_report_outlined),
                      title: Text(l.dashboardReportProblem),
                      subtitle: Text(l.dashboardReportProblemSubtitle),
                      onTap: () {
                        Navigator.pop(context);
                        showFeedbackSheet(context, _printers);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: Text(l.dashboardAppLock),
                      subtitle: Text(ref.watch(appLockEnabledProvider)
                          ? l.dashboardAppLockOn
                          : l.dashboardAppLockOff),
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/settings/app-lock');
                      },
                    ),
                        ],
                      ),
                    ),
                    // Hidden on iOS: Apple rejects in-app donation links to
                    // the developer, so the tip jar is Android-only.
                    if (Platform.isAndroid)
                      ListTile(
                        key: TutorialAnchors.instance.menuSupport,
                        leading: const Icon(Icons.coffee_outlined,
                            color: Colors.amber),
                        title: Text(l.dashboardBuyMeCoffee),
                        subtitle: Text(l.dashboardBuyMeCoffeeSubtitle),
                        onTap: () async {
                          Navigator.pop(context);
                          await launchUrl(
                            Uri.parse(kDonationUrl),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                      ),

                    const Divider(),

                    // Settings + Language scroll with the rest of the menu now;
                    // only the build number stays pinned at the very bottom.
                    ListTile(
                      key: TutorialAnchors.instance.menuSettings,
                      leading: const Icon(Icons.settings_outlined),
                      title: Text(l.dashboardSettings),
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/settings');
                      },
                    ),
                    ListTile(
                      key: TutorialAnchors.instance.menuLanguage,
                      leading: const Icon(Icons.translate),
                      title: Text(l.menuLanguage),
                      subtitle: Text(
                        nativeLanguageName(ref.watch(localeProvider)) ??
                            l.languageSystemDefault,
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        showLanguagePicker(context);
                      },
                    ),
                  ],
                ),
              ),
              ),
            ),

            // ── Bottom: tutorial + build number stay pinned ───────────────────
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: Text(l.tutorialMenuTitle),
              onTap: () {
                Navigator.pop(context);
                _startTutorial();
              },
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: ref.watch(appVersionProvider).when(
                data: (v) => Text(
                  l.dashboardVersion(v),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error:   (_, __) => const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Saves the printer list to a JSON file chosen via the Android Storage
  /// Access Framework, so the user can keep it somewhere safe before a
  /// destructive reinstall and load it back afterwards. NB: this carries the
  /// printer list only - NOT the Supabase anonymous identity (that lives in
  /// flutter_secure_storage and is wiped on uninstall), so a restored config
  /// still needs a re-pair per printer to bind the new anon UID.
  Future<void> _exportConfig() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Mint a single-use restore code so this backup can bring the printers
    // back ONLINE after a reinstall (re-binds them to the new identity), not
    // just restore the list. Best-effort - a list-only backup if it fails.
    final restoreCode = await SupabaseService.instance.createRestoreGrant();
    final settings = await SettingsBackup.snapshot();
    if (!mounted) return;
    final bytes = Uint8List.fromList(
      utf8.encode(
        PrinterConfig.toBackupJson(_printers,
            restoreCode: restoreCode, settings: settings),
      ),
    );
    String? savedPath;
    try {
      // On Android, passing `bytes` makes saveFile write the file through the
      // SAF "create document" dialog and return its path (null if cancelled).
      // Without `bytes`, saveFile only returns a path and leaves the write to
      // us - which scoped storage won't allow.
      savedPath = await FilePicker.platform.saveFile(
        dialogTitle: l.dashboardSaveBackupDialogTitle,
        fileName: 'moongate-printers.json',
        bytes: bytes,
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.dashboardBackupFailed),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (!mounted || savedPath == null) return; // user cancelled
    messenger.showSnackBar(
      SnackBar(
        content: Text(restoreCode != null
            ? l.dashboardBackupSuccess(_printers.length)
            : l.dashboardBackupSuccessListOnly(_printers.length)),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// Lets the user pick a previously saved backup file via the SAF document
  /// picker and restores it, making the dashboard match the backup exactly. If
  /// the device has printers the backup doesn't include, [_confirmRestoreReplace]
  /// asks before removing them.
  Future<void> _importConfig() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    ImportOutcome? outcome;
    try {
      outcome = await PrinterRegistry.instance.importFromBackupFile(
        confirmReplace: _confirmRestoreReplace,
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.dashboardInvalidBackupFile),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (outcome == null || !mounted) return; // user cancelled
    _load();
    // A restored backup may carry global app settings (theme, colours, columns,
    // language, …); the import wrote them to prefs, so reload the providers to
    // apply them live and re-sync the notification service to the restored
    // on/off preference.
    await _reloadSettingsAfterRestore();
    if (!mounted) return;
    final String msg;
    if (outcome.added == 0) {
      // Nothing new added - a re-apply onto an existing dashboard (reordered /
      // config-updated / tiles removed). The count-based messages would read
      // "0 printers restored", so use a generic confirmation instead.
      msg = l.dashboardRestoreApplied;
    } else if (outcome.reconnected) {
      msg = l.dashboardRestoreReconnected(
          outcome.added, outcome.reconnectedCount);
    } else if (outcome.hadRestoreCode) {
      msg = l.dashboardRestoreNoneReconnected(outcome.added);
    } else {
      msg = l.dashboardRestoreListOnly(outcome.added);
    }
    messenger.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 6)),
    );
  }

  /// Confirms a destructive restore: the backup doesn't include [toRemove], so
  /// restoring will drop those tiles to match it. Returns true to proceed. Never
  /// shown on a clean install (nothing to remove). Removed printers stay paired,
  /// so they can be re-added or restored later.
  Future<bool> _confirmRestoreReplace(List<PrinterConfig> toRemove) async {
    if (!mounted) return false;
    final l = AppLocalizations.of(context);
    final names = toRemove.map((p) => p.name).join(', ');
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.dashboardRestoreReplaceTitle),
        content: Text(l.dashboardRestoreReplaceBody(names)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.dashboardRestoreReplaceConfirm),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  /// Re-read the settings providers from prefs after a restore wrote new
  /// values, so theme / colours / columns / language / etc. update without a
  /// restart. Mirrors the startup loads in main.dart - minus the device-bound
  /// app-lock, which a backup never carries.
  Future<void> _reloadSettingsAfterRestore() async {
    await ref.read(themeModeProvider.notifier).load();
    await ref.read(localeProvider.notifier).load();
    await ref.read(customThemeProvider.notifier).load();
    await ref.read(fontScaleProvider.notifier).load();
    await ref.read(appFontProvider.notifier).load();
    await ref.read(gridColumnsProvider.notifier).load();
    await ref.read(allowRotationProvider.notifier).load();
    await ref.read(autoArrangeProvider.notifier).load();
    await ref.read(localCameraRefreshProvider.notifier).load();
    await ref.read(tunnelCameraRefreshProvider.notifier).load();
    await ref.read(showCameraConfigIconsProvider.notifier).load();
    await ref.read(printNotificationsEnabledProvider.notifier).load();
    await ref.read(notificationsPausedProvider.notifier).load();
    await ref.read(notificationFieldsProvider.notifier).load();
    await ref.read(notifOnlineOnlyProvider.notifier).load();
    await ref.read(globalPowerButtonProvider.notifier).load();
    await ref.read(dashboardButtonsProvider.notifier).load();
    await PrintNotificationService.instance.sync(
        ref.read(printNotificationsEnabledProvider) &&
            !ref.read(notificationsPausedProvider));
  }

  void _showRemoveSheet(BuildContext context) {
    final l = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      // Without SafeArea the last ListTile clips behind the 3-button nav
      // bar on devices using on-screen system navigation.
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.dashboardRemoveSheetTitle,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ..._printers.map(
              (p) => ListTile(
                leading: const Icon(Icons.print, color: Colors.redAccent),
                title: Text(p.name),
                subtitle: Text(
                  l.dashboardPrinterIdShort(p.id.substring(0, 8)),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onTap: () {
                  Navigator.pop(ctx);
                  _removePrinter(p);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _fontScaleLabel(double v) {
    if (v <= 0.85) return 'XS';
    if (v <= 0.95) return 'S';
    if (v <= 1.05) return 'M';
    if (v <= 1.15) return 'L';
    if (v <= 1.25) return 'XL';
    return 'XXL';
  }

  void _showChangelog(BuildContext context) =>
      _showChangelogSheet(context, future: ChangelogService.loadBundled());

  /// The "what's new in this update" overlay - entries from the user's installed
  /// build up to the latest, fetched from master (the installed app can't carry
  /// notes for a version newer than itself).
  void _showUpdateNotes(BuildContext context, UpdateInfo update) =>
      _showChangelogSheet(
        context,
        future: ChangelogService.entriesSinceInstalled(),
        update: update,
      );

  /// Shared changelog dialog. With [update] set it's the update overlay - it
  /// gains Update + View-on-GitHub actions and a fallback message when the
  /// remote fetch returns nothing.
  void _showChangelogSheet(
    BuildContext context, {
    required Future<List<ChangelogEntry>> future,
    UpdateInfo? update,
  }) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.dashboardWhatsNew),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380, maxWidth: 360),
          child: FutureBuilder<List<ChangelogEntry>>(
            future: future,
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final entries = snap.data ?? const <ChangelogEntry>[];
              if (entries.isEmpty) {
                // Only the update overlay reaches here (remote fetch failed) -
                // the bundled list is never empty.
                return Text(l.updateNotesUnavailable,
                    style: Theme.of(ctx).textTheme.bodySmall);
              }
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in entries) ...[
                      Text(
                        entry.version,
                        style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      for (final bullet in entry.bullets)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, top: 2),
                          child: Text('• $bullet',
                              style: Theme.of(ctx).textTheme.bodySmall),
                        ),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          if (update != null)
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://github.com/PEEKYPAUL/Moongate/releases/latest'),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(l.updateViewOnGithub),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.commonClose),
          ),
          if (update != null)
            FilledButton(
              // Close the notes overlay, then run the SAME in-app OTA the update
              // banner uses (download + install with a progress bar, browser
              // fallback). This button previously opened the browser to the APK,
              // bypassing the in-app updater; "View on GitHub" above stays the
              // manual route.
              onPressed: () {
                Navigator.pop(ctx);
                _startInAppUpdate(context, update);
              },
              child: Text(l.dashboardUpdate),
            ),
        ],
      ),
    );
  }

  // ── Pairing onboarding help ──────────────────────────────────────────────
  static const _pairingHelpDismissedKey = 'pairing_help_dismissed';
  static const _languageSelectedKey = 'language_selected';
  static const _notifPromptedKey = 'notifications_prompted';
  static const _donationPromptedKey = 'donation_prompted';
  static const _tutorialOfferedKey = 'tutorial_offered';

  /// First cold start: prompt for a language once, then run the pairing
  /// explainer. The language prompt is gated by [_languageSelectedKey] so it
  /// appears only on the very first launch; the pairing explainer keeps its
  /// existing show-until-dismissed behaviour and follows it.
  Future<void> _runFirstRunOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_languageSelectedKey) ?? false)) {
      if (!mounted) return;
      await showLanguagePicker(context, firstRun: true);
      await prefs.setBool(_languageSelectedKey, true);
    }
    await _maybeShowPairingHelp();
    await _maybeOfferNotifications();
    await _maybeShowDonationPrompt();
    await _maybeOfferTutorial();
    await _maybeShowPauseHint();
  }

  static const _pauseHintSeenKey = 'notif_pause_hint_seen';

  /// Spotlight the app bar's pause/play button once, the first time print
  /// notifications are on and the dashboard is at rest. Runs last in the
  /// first-run chain (and again on later cold launches until seen), so it never
  /// overlaps the notifications / donation / tutorial popups, and skips while the
  /// main walkthrough is active - the user just enabled notifications, so the
  /// button is now on the app bar to point at. Android-only, like the feature.
  Future<void> _maybeShowPauseHint() async {
    if (!Platform.isAndroid) return;
    if (!mounted) return;
    if (!ref.read(printNotificationsEnabledProvider)) return;
    if (_printers.isEmpty) return;
    if (ref.read(tutorialControllerProvider).active) return;
    // The button lives in the app bar, so the drawer must be closed to see it.
    if (_scaffoldKey.currentState?.isEndDrawerOpen ?? false) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_pauseHintSeenKey) ?? false) return;
    if (!mounted) return;
    await prefs.setBool(_pauseHintSeenKey, true);
    ref.read(tutorialControllerProvider.notifier).startPauseHint();
  }

  /// Offer the live walkthrough once, after the user has a printer to look at.
  /// Mirrors the other first-run prompts: gated on having ≥1 printer and shown
  /// once (the flag is set when the user starts it or ticks "don't remind me").
  /// Dismissing without choosing leaves the flag clear, so it offers again.
  Future<void> _maybeOfferTutorial() async {
    if (_tutorialOfferInFlight) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_tutorialOfferedKey) ?? false) return;
    if (PrinterRegistry.instance.printers.isEmpty) return;
    if (!mounted) return;
    _tutorialOfferInFlight = true;
    final result = await showTutorialOffer(context);
    _tutorialOfferInFlight = false;
    if (result == null) return;
    if (result.start || result.dontRemind) {
      await prefs.setBool(_tutorialOfferedKey, true);
    }
    if (result.start) _startTutorial();
  }

  /// Launch the walkthrough now (from the offer popup or the drawer entry).
  void _startTutorial() {
    ref.read(tutorialControllerProvider.notifier).start();
  }

  /// Pick the app typeface from the bundled set, grouped by style. Each option
  /// previews in its own font; the phone's own selected font can't be read by a
  /// Flutter app, so this bundled set is the alternative.
  Future<void> _showFontPicker(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final current = ref.read(appFontProvider);
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.dashboardFontHeading),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: RadioGroup<String>(
              groupValue: current,
              onChanged: (v) {
                if (v != null) Navigator.pop(ctx, v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final cat in kAppFontCategories)
                    if (kAppFonts.any((f) => f.category == cat)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 2),
                        child: Text(
                          cat,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.55),
                              ),
                        ),
                      ),
                      for (final f in kAppFonts.where((e) => e.category == cat))
                        RadioListTile<String>(
                          value: f.id,
                          title: Text(
                            f.label,
                            style: TextStyle(fontFamily: f.family),
                          ),
                        ),
                    ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (picked != null && picked != current) {
      await ref.read(appFontProvider.notifier).set(picked);
    }
  }

  /// Open or close the end drawer to match the tutorial's current step, so the
  /// menu steps can spotlight drawer entries.
  void _syncTutorialDrawer(TutorialState s) {
    final step = s.current;
    final wantOpen = s.active && (step?.requiresDrawer ?? false);
    final st = _scaffoldKey.currentState;
    if (st == null) return;
    if (wantOpen) {
      if (!_tutorialDrawerOpen) {
        _tutorialDrawerOpen = true;
        st.openEndDrawer();
      }
      // Scroll the spotlighted entry into view (after the drawer settles, or
      // after the previous menu step's scroll finishes).
      final key = (step?.anchors.isNotEmpty ?? false) ? step!.anchors.first : null;
      if (key != null) {
        Future.delayed(const Duration(milliseconds: 180), () {
          if (!mounted) return;
          final ctx = key.currentContext;
          if (ctx == null || !ctx.mounted) return;
          Scrollable.ensureVisible(ctx,
              duration: const Duration(milliseconds: 250), alignment: 0.5);
        });
      }
    } else if (_tutorialDrawerOpen) {
      _tutorialDrawerOpen = false;
      if (st.isEndDrawerOpen) st.closeEndDrawer();
    }
  }


  /// A one-time, low-pressure nudge to support the project, shown on a cold
  /// start. Gated on having at least one printer so it never interrupts a brand
  /// new user mid-pairing (the donation ask lands once they're actually set up,
  /// not before they've seen the app work). Shown exactly once - the
  /// [_donationPromptedKey] flag is a first-run flag, so it's excluded from
  /// backups and can't carry over to a fresh install.
  Future<void> _maybeShowDonationPrompt() async {
    // Apple rejects in-app donation links to the developer, so the first-run
    // tip-jar nudge is Android-only. (The drawer item is guarded the same way.)
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_donationPromptedKey) ?? false) return;
    if (PrinterRegistry.instance.printers.isEmpty) return;
    if (!mounted) return;
    final wantsToDonate = await showDonationPrompt(context);
    await prefs.setBool(_donationPromptedKey, true);
    if (!wantsToDonate) return;
    await launchUrl(Uri.parse(kDonationUrl),
        mode: LaunchMode.externalApplication);
  }

  /// Offer print notifications once - but only after the user actually has a
  /// printer (an empty dashboard has nothing to notify about, and a fresh
  /// install pairs first). Tapping "Turn on" requests the OS permission and
  /// enables the service.
  Future<void> _maybeOfferNotifications() async {
    // Background print notifications need an Android foreground service; iOS
    // has no equivalent yet, so never offer them there. (The settings toggle
    // is hidden on iOS the same way.)
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_notifPromptedKey) ?? false) return;
    if (PrinterRegistry.instance.printers.isEmpty) return;
    if (!mounted) return;
    final wantsIt = await showPrintNotificationsPrompt(context);
    await prefs.setBool(_notifPromptedKey, true);
    if (!wantsIt) return;
    final granted = await PrintNotificationService.instance.requestPermission();
    if (!granted) return;
    await ref.read(printNotificationsEnabledProvider.notifier).set(true);
    await ref.read(notificationsPausedProvider.notifier).set(false);
    await PrintNotificationService.instance.sync(true);
  }

  /// On cold launch, show the "how pairing works" explainer unless the user
  /// ticked "Don't show this again". Pressing OK without ticking shows it again
  /// next launch - by design, so the workflow lands for users who skim it.
  Future<void> _maybeShowPairingHelp() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_pairingHelpDismissedKey) ?? false) return;
    if (!mounted) return;
    await _showPairingHelp(context);
  }

  /// The pairing / reinstall explainer. Reachable on launch and from the menu
  /// ("How pairing works"). The "Don't show again" tick persists the dismissal
  /// so it never auto-shows again.
  Future<void> _showPairingHelp(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    var dontShowAgain = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.push_pin_outlined, color: cs.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(l.dashboardHowPairingWorks)),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 440, maxWidth: 360),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Prerequisite, called out first: the app cannot pair until
                  // the Moongate plugin is running on the user's Klipper Pi.
                  // Tinted to stand out, with a tappable link to the README
                  // quick-start (install step 1).
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.extension, color: cs.primary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.dashboardPairingHelpPluginTitle,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text(l.dashboardPairingHelpPluginBody,
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: cs.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => launchUrl(
                              Uri.parse(
                                  'https://github.com/PEEKYPAUL/Moongate#quick-start'),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: Text(l.dashboardPairingHelpPluginAction),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _pairingHelpItem(ctx, Icons.qr_code_2, cs.primary,
                      l.dashboardPairingHelpPairOnceTitle,
                      l.dashboardPairingHelpPairOnceBody),
                  _pairingHelpItem(ctx, Icons.check_circle_outline, Colors.green,
                      l.dashboardPairingHelpUpdatesTitle,
                      l.dashboardPairingHelpUpdatesBody),
                  _pairingHelpItem(ctx, Icons.cloud_download_outlined, cs.primary,
                      l.dashboardPairingHelpReinstallTitle,
                      l.dashboardPairingHelpReinstallBody),
                  _pairingHelpItem(ctx, Icons.restart_alt, Colors.orangeAccent,
                      l.dashboardPairingHelpNoBackupTitle,
                      l.dashboardPairingHelpNoBackupBody),
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    value: dontShowAgain,
                    onChanged: (v) => setLocal(() => dontShowAgain = v ?? false),
                    title: Text(l.dashboardDontShowAgain),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                if (dontShowAgain) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool(_pairingHelpDismissedKey, true);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(l.commonOk),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pairingHelpItem(
      BuildContext ctx, IconData icon, Color color, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: Theme.of(ctx)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(body, style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// ── Update banner ─────────────────────────────────────────────────────────────

/// Shown above the dashboard while the app has no cloud session yet - usually
/// the anonymous sign-in being rate-limited after several reinstalls in a row.
/// SupabaseService retries on its own, so this is purely informational and
/// disappears once a session lands and the tiles reconnect.
class _SignInBanner extends StatelessWidget {
  const _SignInBanner();

  @override
  Widget build(BuildContext context) {
    final l  = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l.dashboardSignInRetrying,
                style: TextStyle(color: cs.onSecondaryContainer, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  final UpdateInfo update;
  final VoidCallback onDismiss;
  final VoidCallback onWhatsNew;

  const _UpdateBanner({
    required this.update,
    required this.onDismiss,
    required this.onWhatsNew,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.system_update_alt_rounded,
                    color: cs.onPrimaryContainer, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.dashboardUpdateAvailable(update.version),
                    style: TextStyle(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            // Actions on their own row so "What's new" + Later + Update always
            // fit, even on a narrow phone.
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDismiss,
                  style: TextButton.styleFrom(
                      foregroundColor: cs.onPrimaryContainer),
                  child: Text(l.dashboardUpdateLater),
                ),
                TextButton(
                  onPressed: onWhatsNew,
                  style: TextButton.styleFrom(
                      foregroundColor: cs.onPrimaryContainer),
                  child: Text(l.dashboardWhatsNew),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => _startInAppUpdate(context, update),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                  ),
                  child: Text(l.dashboardUpdate),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Kicks off the in-app update. On Android, shows a download-progress dialog
/// that auto-launches the installer; elsewhere (iOS) it falls back to opening
/// the release in a browser (no sideloading on iOS).
void _startInAppUpdate(BuildContext context, UpdateInfo update) {
  if (!Platform.isAndroid) {
    launchUrl(Uri.parse(update.apkUrl), mode: LaunchMode.externalApplication);
    return;
  }
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDownloadDialog(update: update),
  );
}

/// Downloads the new APK with a progress bar, then launches the system
/// installer. Any failure (network, or the user declining the install
/// permission) falls back to opening the release in a browser.
class _UpdateDownloadDialog extends StatefulWidget {
  final UpdateInfo update;
  const _UpdateDownloadDialog({required this.update});

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  double _progress = 0; // < 0 while the total size is still unknown
  bool _installing = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final path = await OtaInstaller.downloadApk(
        widget.update.apkUrl,
        (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      // Dialog dismissed (Cancel) mid-download → don't pop the installer up.
      if (!mounted) return;
      setState(() => _installing = true);
      final ok = await OtaInstaller.installApk(path);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(); // the system installer is now in front
      } else {
        setState(() => _failed = true); // install permission declined
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _openInBrowser() {
    launchUrl(Uri.parse(widget.update.apkUrl),
        mode: LaunchMode.externalApplication);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_failed) {
      return AlertDialog(
        title: Text(l.dashboardUpdate),
        content: Text(l.updateFailed),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.dashboardUpdateLater),
          ),
          FilledButton(
            onPressed: _openInBrowser,
            child: Text(l.updateOpenInBrowser),
          ),
        ],
      );
    }
    final determinate = !_installing && _progress >= 0;
    return AlertDialog(
      title: Text(_installing ? l.updateOpeningInstaller : l.updateDownloading),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: determinate ? _progress : null),
          if (determinate) ...[
            const SizedBox(height: 12),
            Text('${(_progress * 100).round()}%'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.dashboardUpdateLater),
        ),
      ],
    );
  }
}

// ── Printer grid ──────────────────────────────────────────────────────────────

class _PrinterGrid extends StatelessWidget {
  final List<PrinterConfig> printers;
  final void Function(PrinterConfig) onTap;

  /// Portrait column count chosen by the user (1, 2, or 3).
  /// When the device rotates to landscape, one extra column is added
  /// automatically so the extra horizontal space is used well.
  final int columns;

  /// When non-null, the dashboard is in manual-order mode: the tiles are dragged
  /// around a fixed-cell ReorderableGridView and this fires with the new
  /// (old, new) indices. Null in the default auto-arrange mode, where the grid
  /// is the read-only masonry view.
  final void Function(int oldIndex, int newIndex)? onReorder;

  /// Printer-tile background opacity (Custom theme); 1.0 = opaque.
  final double tileOpacity;

  const _PrinterGrid({
    required this.printers,
    required this.onTap,
    required this.columns,
    this.tileOpacity = 1.0,
    this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isLandscape = constraints.maxWidth > constraints.maxHeight;

      // In landscape, bump by 1 so the extra width is used comfortably.
      // Capped at 4 to keep tiles readable even on small phone screens.
      final effectiveCols = isLandscape
          ? (columns + 1).clamp(2, 4)
          : columns;

      const padding = EdgeInsets.all(12);
      const spacing = 10.0;

      // Keyed by id so a reorder (or a status re-sort) moves a tile and its
      // poller rather than rebuilding it. `bounded` tiles are for the fixed-cell
      // reorder grid (see PrinterTile.bounded); the masonry view leaves it off.
      Widget tileAt(int i, {bool bounded = false}) => PrinterTile(
            key: ValueKey(printers[i].id),
            printer: printers[i],
            onTap: () => onTap(printers[i]),
            tileOpacity: tileOpacity,
            bounded: bounded,
            // The first tile carries the live-tutorial spotlight anchors.
            anchorForTutorial: i == 0,
          );

      // Manual-order mode: drag the actual tiles around the grid - the original
      // workflow. reorderable_grid_view needs uniform cells, so while arranging
      // every tile takes one fixed-height cell (the webcam square plus a fixed
      // status band, sized from the real tile width so it matches the display
      // tiles closely) and the bounded tile lets a busy full tile give a little
      // height back. A compact (webcam-hidden) tile just sits with space beneath
      // it - alignment isn't the point here; the masonry packing returns the
      // moment you tap Done.
      if (onReorder != null) {
        const tileTextBand = 104.0;
        final tileWidth = (constraints.maxWidth -
                padding.horizontal -
                spacing * (effectiveCols - 1)) /
            effectiveCols;
        return ReorderableGridView.builder(
          padding: padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: effectiveCols,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: tileWidth / (tileWidth + tileTextBand),
          ),
          itemCount: printers.length,
          onReorder: onReorder!,
          itemBuilder: (_, i) => tileAt(i, bounded: true),
        );
      }

      // Display mode: masonry so full (webcam) tiles and compact (band-only)
      // tiles each take their natural height and pack the columns tightly -
      // roughly two compact tiles fit in the height of one full tile.
      return MasonryGridView.count(
        padding: padding,
        crossAxisCount: effectiveCols,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        itemCount: printers.length,
        itemBuilder: (context, i) => tileAt(i),
      );
    });
  }
}

/// Subtle strip shown above the grid in manual-order mode so the user knows the
/// tiles are now draggable (the gesture isn't otherwise discoverable). Only
/// rendered when there's more than one printer to reorder.
class _ReorderHint extends StatelessWidget {
  const _ReorderHint();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final faint =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.drag_indicator, size: 15, color: faint),
          const SizedBox(width: 4),
          Text(
            l.dashboardReorderHint,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: faint),
          ),
        ],
      ),
    );
  }
}

/// Wraps the whole dashboard screen with the user's custom background image.
/// The image is centred and scaled-down (never upscaled, never distorted) over
/// the theme's scaffold colour, so a small logo or a wrong-aspect picture still
/// shows the theme colour around and behind it (and through any transparency).
/// Decoding is capped to ~1440px wide to keep memory sane on large photos.
class _DashboardBackground extends StatelessWidget {
  final String? imagePath;
  final Widget child;

  const _DashboardBackground({required this.imagePath, required this.child});

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    if (path == null || path.isEmpty) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        image: DecorationImage(
          image: ResizeImage(FileImage(File(path)), width: 1440),
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
        ),
      ),
      child: child,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddPrinter;

  const _EmptyState({required this.onAddPrinter});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.print_disabled,
              size: 72, color: Colors.white24),
          const SizedBox(height: 16),
          Text(l.dashboardEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l.dashboardEmptyBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: Text(l.dashboardAddPrinter),
            onPressed: onAddPrinter,
          ),
        ],
      ),
    );
  }
}
