import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/printer_config.dart';
import '../../providers/settings_provider.dart';
import '../../providers/update_provider.dart';
import '../../providers/version_provider.dart';
import '../../services/printer_access_cache.dart';
import '../../services/printer_registry.dart';
import '../../services/supabase_service.dart';
import '../../services/update_service.dart';
import 'printer_tile.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<PrinterConfig> _printers = [];
  bool _updateDismissed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final list = PrinterRegistry.instance.printers;
    if (mounted) setState(() => _printers = list);
  }

  Future<void> _removePrinter(PrinterConfig printer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove printer?'),
        content: Text('Remove "${printer.name}" from Moongate?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
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

    if (!released && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Removed locally, but couldn’t reach Supabase. '
            'Run MOONGATE_RESET_OWNER on the Pi if re-pairing fails.',
          ),
        ),
      );
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    // Check for update — runs once per session, silently ignored on failure.
    final updateAsync = ref.watch(updateProvider);
    final update = _updateDismissed ? null : updateAsync.valueOrNull;

    final gridColumns = ref.watch(gridColumnsProvider);

    final body = _printers.isEmpty
        ? _EmptyState(onAddPrinter: () => context.push('/pair').then((_) => _load()))
        : _PrinterGrid(
            printers: _printers,
            columns:  gridColumns,
            // Reload after the printer screen pops so any rename done in
            // the app bar there propagates to the tile.
            onTap:    (p) => context.push('/printer/${p.id}').then((_) => _load()),
            onRemove: _removePrinter,
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Moongate'),
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: _buildDrawer(context),
      body: update != null
          ? Column(
              children: [
                _UpdateBanner(
                  update: update,
                  onDismiss: () => setState(() => _updateDismissed = true),
                ),
                Expanded(child: body),
              ],
            )
          : body,
      floatingActionButton: _printers.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: () async {
                await context.push('/pair');
                _load();
              },
              tooltip: 'Add printer',
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final fontScale     = ref.watch(fontScaleProvider);
    final themeMode     = ref.watch(themeModeProvider);
    final gridColumns   = ref.watch(gridColumnsProvider);
    final allowRotation = ref.watch(allowRotationProvider);

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
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [

                    // Printer management
                    ListTile(
                      leading: const Icon(Icons.add_circle_outline),
                      title: const Text('Add printer'),
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
                        title: const Text('Remove printer',
                            style: TextStyle(color: Colors.redAccent)),
                        onTap: () {
                          Navigator.pop(context);
                          _showRemoveSheet(context);
                        },
                      ),

                    const Divider(),

                    // Import / Export
                    if (_printers.isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.upload_outlined),
                        title: const Text('Export config'),
                        subtitle:
                            const Text('Copy to clipboard before reinstalling'),
                        onTap: () {
                          Navigator.pop(context);
                          _exportConfig();
                        },
                      ),
                    ListTile(
                      leading: const Icon(Icons.download_outlined),
                      title: const Text('Import config'),
                      subtitle: const Text('Restore from exported text'),
                      onTap: () {
                        Navigator.pop(context);
                        _importConfig();
                      },
                    ),

                    const Divider(),

                    // Theme
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text('Theme',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: Colors.white54)),
                    ),
                    RadioGroup<AppThemeMode>(
                      groupValue: themeMode,
                      onChanged: (v) {
                        if (v == null) return;
                        ref.read(themeModeProvider.notifier).set(v);
                        // Selecting "Custom" should jump straight into the
                        // colour editor — saves the user a second tap and
                        // makes the option discoverable in one click.
                        if (v == AppThemeMode.custom) {
                          Navigator.pop(context);
                          context.push('/theme/custom');
                        }
                      },
                      child: const Column(
                        children: [
                          RadioListTile(
                            value: AppThemeMode.system,
                            title: Text('System default'),
                            secondary: Icon(Icons.brightness_auto),
                          ),
                          RadioListTile(
                            value: AppThemeMode.dark,
                            title: Text('Dark'),
                            secondary: Icon(Icons.dark_mode),
                          ),
                          RadioListTile(
                            value: AppThemeMode.light,
                            title: Text('Light'),
                            secondary: Icon(Icons.light_mode),
                          ),
                          RadioListTile(
                            value: AppThemeMode.custom,
                            title: Text('Custom'),
                            secondary: Icon(Icons.palette_outlined),
                          ),
                        ],
                      ),
                    ),
                    // Always offer a way back into the editor — handy when
                    // Custom is already selected and the user just wants to
                    // tweak a colour without re-tapping the radio.
                    if (themeMode == AppThemeMode.custom)
                      ListTile(
                        leading: const Icon(Icons.tune),
                        title: const Text('Customise colours'),
                        subtitle: const Text(
                            'Edit the five theme slots — HEX or palette'),
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/theme/custom');
                        },
                      ),

                    const Divider(),

                    // Font size
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text('Font size',
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

                    const Divider(),

                    // ── Dashboard layout ──────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text('Dashboard layout',
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
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        segments: const [
                          ButtonSegment(
                            value: 1,
                            icon: Icon(Icons.view_stream, size: 16),
                            label: Text('1 col'),
                          ),
                          ButtonSegment(
                            value: 2,
                            icon: Icon(Icons.view_column, size: 16),
                            label: Text('2 col'),
                          ),
                          ButtonSegment(
                            value: 3,
                            icon: Icon(Icons.view_module, size: 16),
                            label: Text('3 col'),
                          ),
                        ],
                        selected: {gridColumns},
                        onSelectionChanged: (s) =>
                            ref.read(gridColumnsProvider.notifier).set(s.first),
                      ),
                    ),
                    // Rotation toggle
                    SwitchListTile(
                      dense: true,
                      secondary: const Icon(Icons.screen_rotation_outlined),
                      title: const Text('Rotate with device'),
                      subtitle: const Text('Unlocks landscape orientation'),
                      value: allowRotation,
                      onChanged: (v) =>
                          ref.read(allowRotationProvider.notifier).set(v),
                    ),

                    const Divider(),

                    // ── About ────────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text('About',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: Colors.white54)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.new_releases_outlined),
                      title: const Text("What's new"),
                      subtitle: const Text('Recent changes at a glance'),
                      onTap: () {
                        Navigator.pop(context);
                        _showChangelog(context);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.coffee_outlined,
                          color: Colors.amber),
                      title: const Text('Buy me a coffee'),
                      subtitle: const Text('Tip the dev via PayPal'),
                      onTap: () async {
                        Navigator.pop(context);
                        await launchUrl(
                          Uri.parse(
                              'https://www.paypal.com/donate/?hosted_button_id=WCWAZKQ7WKQB4'),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // ── Bottom bar — always visible ───────────────────────────────────
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                context.push('/settings');
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: ref.watch(appVersionProvider).when(
                data: (v) => Text(
                  'Moongate v$v',
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

  /// Copies the printer list JSON to the clipboard so the user can paste it
  /// somewhere safe before uninstalling, then restore via Import after reinstall.
  Future<void> _exportConfig() async {
    final json = PrinterConfig.listToJson(_printers);
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Printer config copied to clipboard — paste it somewhere safe!'),
        duration: Duration(seconds: 4),
      ),
    );
  }

  /// Shows a dialog where the user can paste a previously exported JSON string
  /// to restore their printer list after a reinstall.
  Future<void> _importConfig() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import printer config'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Paste your exported JSON here…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    // Capture text BEFORE disposing — reading .text after dispose is unsafe.
    final importText = controller.text.trim();
    controller.dispose();
    if (confirmed != true || !mounted) return;

    try {
      final printers = PrinterConfig.listFromJson(importText);
      // Merge: add only printers not already in registry (match by id).
      final existing = PrinterRegistry.instance.printers.map((p) => p.id).toSet();
      for (final p in printers) {
        if (!existing.contains(p.id)) {
          await PrinterRegistry.instance.add(p);
        }
      }
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${printers.length} printer(s) imported.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid config — make sure you pasted the full exported text.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showRemoveSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      // Without SafeArea the last ListTile clips behind the 3-button nav
      // bar on devices using on-screen system navigation.
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Remove a printer',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ..._printers.map(
              (p) => ListTile(
                leading: const Icon(Icons.print, color: Colors.redAccent),
                title: Text(p.name),
                subtitle: Text(
                  'id ${p.id.substring(0, 8)}…',
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

  void _showChangelog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("What's new"),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380, maxWidth: 360),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in _changelog) ...[
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
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ChangelogEntry {
  final String version;
  final List<String> bullets;
  const _ChangelogEntry(this.version, this.bullets);
}

// Top-level brief — bumped on each release. Newest first.
const _changelog = <_ChangelogEntry>[
  _ChangelogEntry('v0.5.0', [
    'Dashboard tile stays "Local" when your Pi\'s IP changes — even if the internet is down',
    'Finds your Pi on the local network via mDNS (pairs with the v0.4.4 Pi advertisement)',
    'Print controls now read the live LAN URL too — no stale-IP gap after DHCP changes',
    'Falls through to v0.4.x behaviour when discovery doesn\'t resolve (different WiFi, multicast blocked, etc.)',
    'Re-run the Pi installer to enable the Pi-side advertisement',
  ]),
  _ChangelogEntry('v0.4.4', [
    'Pi-side groundwork for LAN discovery — your Pi now advertises itself on the local network',
    'No visible change yet on its own; pairs with the upcoming v0.5.0 app update',
    'Re-run the Pi installer to pick up the change',
  ]),
  _ChangelogEntry('v0.4.3', [
    'Webcam tile now works on slow camera servers (stock RatRig Micron+ / uv4l-mjpeg)',
    'Self-throttles to whatever the camera can deliver instead of cancelling its own fetches',
    'No Pi-side change needed — just update the app',
  ]),
  _ChangelogEntry('v0.4.2', [
    'Re-pair after app reinstall just works — no more "already paired"',
    'Pairing goes live within seconds, not up to 5 minutes',
    'Mainsail through tunnel stays connected on cellular',
    'Type the GATE code if the camera can\'t scan the QR',
  ]),
  _ChangelogEntry('v0.4.1', [
    'Dashboard tile webcam preview works again on LAN and tunnel',
    'No reinstall on the Pi needed — just this app update',
  ]),
  _ChangelogEntry('v0.4.0', [
    'Hardened remote access — the tunnel URL alone grants nothing',
    'Mainsail reachable through the tunnel from anywhere',
    "Added 'Buy me a coffee' and this 'What's new'",
  ]),
  _ChangelogEntry('v0.3.0', [
    'Cloud-mediated pairing — no more URL sharing required',
    'LAN-first routing for snappier home use',
    'Cleaner remove / re-pair flow',
  ]),
  _ChangelogEntry('v0.2.29', [
    'Initial public release',
    'Pi-issued JWT auth, dual-path local + tunnel',
    'Mainsail / Fluidd WebView per printer',
  ]),
];

// ── Update banner ─────────────────────────────────────────────────────────────

class _UpdateBanner extends StatelessWidget {
  final UpdateInfo update;
  final VoidCallback onDismiss;

  const _UpdateBanner({required this.update, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.system_update_alt_rounded,
                color: cs.onPrimaryContainer, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Update available — v${update.version}',
                style: TextStyle(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(foregroundColor: cs.onPrimaryContainer),
              child: const Text('Later'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () => launchUrl(
                Uri.parse(update.apkUrl),
                mode: LaunchMode.externalApplication,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Printer grid ──────────────────────────────────────────────────────────────

class _PrinterGrid extends StatelessWidget {
  final List<PrinterConfig> printers;
  final void Function(PrinterConfig) onTap;
  final void Function(PrinterConfig) onRemove;

  /// Portrait column count chosen by the user (1, 2, or 3).
  /// When the device rotates to landscape, one extra column is added
  /// automatically so the extra horizontal space is used well.
  final int columns;

  const _PrinterGrid({
    required this.printers,
    required this.onTap,
    required this.onRemove,
    required this.columns,
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

      // Aspect ratio (width / height) per column count.
      // Wider tiles (fewer columns) can be shorter; narrow tiles need more
      // height to keep the webcam + controls comfortable.
      final aspectRatio = switch (effectiveCols) {
        1 => 1.4,   // single full-width tile: landscape feel
        2 => 0.75,  // default two-column layout
        3 => 0.65,  // three columns — a bit taller relative to width
        _ => 0.55,  // four columns in landscape from a 3-col portrait pref
      };

      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: effectiveCols,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: aspectRatio,
        ),
        itemCount: printers.length,
        itemBuilder: (_, i) => PrinterTile(
          printer: printers[i],
          onTap: () => onTap(printers[i]),
        ),
      );
    });
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddPrinter;

  const _EmptyState({required this.onAddPrinter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.print_disabled,
              size: 72, color: Colors.white24),
          const SizedBox(height: 16),
          Text('No printers added yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('Tap the button below to pair your first printer.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add printer'),
            onPressed: onAddPrinter,
          ),
        ],
      ),
    );
  }
}
