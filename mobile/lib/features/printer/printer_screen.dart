import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/vpn_service.dart';

/// Phase 1: WebView pointing at the local Mainsail/Fluidd instance.
/// Phase 2 (planned): replace with native Flutter widgets consuming
/// MoonrakerService directly.
class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen>
    with WidgetsBindingObserver {
  late final WebViewController _webController;
  bool _vpnConnecting = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAndLoad();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    VpnService.instance.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      VpnService.instance.disconnect();
    } else if (state == AppLifecycleState.resumed) {
      _startAndLoad();
    }
  }

  Future<void> _startAndLoad() async {
    // TODO: load WireGuard config from stored Tailscale auth key
    // await VpnService.instance.connect(wireGuardConfig);
    setState(() => _vpnConnecting = false);

    final host = AuthService.instance.host ?? '';
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('http://$host'));
  }

  @override
  Widget build(BuildContext context) {
    if (_vpnConnecting) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moongate'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: WebViewWidget(controller: _webController),
    );
  }
}
