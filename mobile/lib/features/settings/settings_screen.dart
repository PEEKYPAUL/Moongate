import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../services/printer_access_cache.dart';
import '../../services/printer_registry.dart';
import '../../services/printer_webview_cache.dart';
import '../../services/supabase_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: Text(l.settingsRemoveAllTitle,
                style: const TextStyle(color: Colors.redAccent)),
            subtitle: Text(l.settingsRemoveAllSubtitle),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l.settingsRemoveAllConfirmTitle),
                  content: Text(l.settingsRemoveAllConfirmBody),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(l.commonCancel)),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(l.settingsRemoveAllConfirmAction),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                PrinterAccessCache.instance.clear();
                PrinterWebViewCache.instance.clear();
                for (final p in List.of(PrinterRegistry.instance.printers)) {
                  await PrinterRegistry.instance.remove(p.id);
                }
                if (context.mounted) context.go('/pair');
              }
            },
          ),
          // Account/data deletion (App Store guideline 5.1.1(v)): wipes the
          // anonymous account and its cloud records, then carries on with a
          // fresh anonymous identity. Heavier than "remove all printers" above,
          // which only unpairs locally.
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined,
                color: Colors.redAccent),
            title: Text(l.dashboardDeleteData,
                style: const TextStyle(color: Colors.redAccent)),
            subtitle: Text(l.dashboardDeleteDataSubtitle),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l.deleteDataConfirmTitle),
                  content: Text(l.deleteDataConfirmBody),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(l.commonCancel)),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(l.commonDelete),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !context.mounted) return;
              try {
                await SupabaseService.instance.deleteAccount();
                await PrinterRegistry.instance.clear();
                if (context.mounted) context.go('/pair');
              } catch (_) {
                messenger.showSnackBar(
                    SnackBar(content: Text(l.deleteDataError)));
              }
            },
          ),
        ],
      ),
    );
  }
}
