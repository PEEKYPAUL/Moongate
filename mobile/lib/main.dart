import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/settings_provider.dart';
import 'services/printer_registry.dart';
import 'services/vpn_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await VpnService.instance.initialize();
  await PrinterRegistry.instance.load();

  final container = ProviderContainer();
  await container.read(themeModeProvider.notifier).load();
  await container.read(fontScaleProvider.notifier).load();
  await container.read(gridColumnsProvider.notifier).load();
  await container.read(allowRotationProvider.notifier).load();

  runApp(UncontrolledProviderScope(container: container, child: const MoongateApp()));
}
