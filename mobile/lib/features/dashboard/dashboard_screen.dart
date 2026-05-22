import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/printer_config.dart';
import '../../providers/settings_provider.dart';
import '../../services/printer_registry.dart';
import 'printer_tile.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<PrinterConfig> _printers = [];

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
      body: _printers.isEmpty
          ? _EmptyState(onAddPrinter: () => context.push('/pair').then((_) => _load()))
          : _PrinterGrid(
              printers: _printers,
              onTap: (p) => context.push('/printer/${p.id}'),
              onRemove: _removePrinter,
            ),
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
          ],
        ),
      ),
    );
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
