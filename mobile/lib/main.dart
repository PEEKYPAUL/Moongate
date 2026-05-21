import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/vpn_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await VpnService.instance.initialize();
  runApp(const ProviderScope(child: MoongateApp()));
}
