import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/printer_access_cache.dart';
import '../../services/printer_registry.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Remove all printers from this device',
                style: TextStyle(color: Colors.redAccent)),
            subtitle: const Text(
                'Clears the local printer cache. Your Supabase account is kept so re-pairing works seamlessly.'),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Remove all printers?'),
                  content: const Text(
                      'All paired printers will be removed from this device. '
                      'You can re-add them by running MOONGATE_PAIR on the printer.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Remove all'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                PrinterAccessCache.instance.clear();
                for (final p in List.of(PrinterRegistry.instance.printers)) {
                  await PrinterRegistry.instance.remove(p.id);
                }
                if (context.mounted) context.go('/pair');
              }
            },
          ),
        ],
      ),
    );
  }
}
