import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/printer_config.dart';
import '../../providers/settings_provider.dart';
import '../../providers/update_provider.dart';
import '../../providers/version_provider.dart';
import '../../services/printer_registry.dart';
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
    if (confirmed == true) {
      await PrinterRegistry.instance.remove(printer.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check for update — runs once per session, silently ignored on failure.
    final updateAsync = ref.watch(updateProvider);
    final update = _updateDismissed ? null : updateAsync.valueOrNull;

    final body = _printers.isEmpty
        ? _EmptyState(onAddPrinter: () => context.push('/pair').then((_) => _load()))
        : _PrinterGrid(
            printers: _printers,
            onTap: (p) => context.push('/printer/${p.id}'),
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
    final fontScale = ref.watch(fontScaleProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Row(
                children: [
                  Icon(Icons.print, color: Theme.of(context).colorScheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Text('Moongate',
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            const Divider(),

            // Add printer
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Add printer'),
              onTap: () async {
                Navigator.pop(context);
                await context.push('/pair');
                _load();
              },
            ),

            // Remove printer (only if there's something to remove)
            if (_printers.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                title: const Text('Remove printer',
                    style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  _showRemoveSheet(context);
                },
              ),

            const Divider(),

            // Export config (backup before reinstall)
            if (_printers.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.upload_outlined),
                title: const Text('Export config'),
                subtitle: const Text('Copy to clipboard before reinstalling'),
                onTap: () {
                  Navigator.pop(context);
                  _exportConfig();
                },
              ),

            // Import config (restore after reinstall)
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
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white54)),
            ),
            RadioGroup<ThemeMode>(
              groupValue: themeMode,
              onChanged: (v) {
                if (v != null) ref.read(themeModeProvider.notifier).set(v);
              },
              child: const Column(
                children: [
                  RadioListTile(
                    value: ThemeMode.system,
                    title: Text('System default'),
                    secondary: Icon(Icons.brightness_auto),
                  ),
                  RadioListTile(
                    value: ThemeMode.dark,
                    title: Text('Dark'),
                    secondary: Icon(Icons.dark_mode),
                  ),
                  RadioListTile(
                    value: ThemeMode.light,
                    title: Text('Light'),
                    secondary: Icon(Icons.light_mode),
                  ),
                ],
              ),
            ),

            const Divider(),

            // Font size
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Font size',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white54)),
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

            const Spacer(),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                context.push('/settings');
              },
            ),

            // Version info
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: ref.watch(appVersionProvider).when(
                data: (v) => Text(
                  'Moongate v$v',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
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
    controller.dispose();
    if (confirmed != true || !mounted) return;

    try {
      final printers = PrinterConfig.listFromJson(controller.text.trim());
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
      builder: (ctx) => Column(
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
              subtitle: Text(p.host, style: const TextStyle(fontSize: 12)),
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
}

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

  const _PrinterGrid({
    required this.printers,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final crossAxis = constraints.maxWidth > 600 ? 3 : 2;
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxis,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          // 0.68 gives ~47% more height than width, leaving room for the
          // progress bar + control buttons that appear while printing.
          childAspectRatio: 0.75,
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
