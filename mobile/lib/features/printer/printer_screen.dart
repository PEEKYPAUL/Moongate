import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/printer_config.dart';

/// Phase 1: WebView pointing at the local Mainsail/Fluidd instance,
/// with automatic fallback to the Cloudflare tunnel on remote access.
class PrinterScreen extends StatefulWidget {
  final PrinterConfig printer;

  const PrinterScreen({super.key, required this.printer});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen>
    with WidgetsBindingObserver {
  late final WebViewController _webController;

  bool _loading          = true;
  bool _usingRemote      = false;
  bool _didFallback      = false;   // guard: fall back only once per load
  Timer? _fallbackTimer;            // kick in if local is just slow/unreachable

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initController();
    _startLoad();
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _didFallback = false;
      _startLoad();
    }
  }

  void _initController() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
          _fallbackTimer?.cancel(); // local loaded — no need to fall back
        },
        onWebResourceError: (_) {
          _tryRemote();
        },
      ));
  }

  /// Try local first; if it hasn't loaded within 3 s, switch to remote.
  void _startLoad() {
    _fallbackTimer?.cancel();
    _didFallback  = false;
    _usingRemote  = false;

    _loadUrl(widget.printer.host);

    // Start the fallback timer only when a remote URL is available.
    if (widget.printer.remoteHost != null) {
      _fallbackTimer = Timer(const Duration(seconds: 3), _tryRemote);
    }
  }

  void _tryRemote() {
    final remote = widget.printer.remoteHost;
    if (_didFallback || remote == null) return;
    _didFallback = true;
    _fallbackTimer?.cancel();
    if (mounted) setState(() => _usingRemote = true);
    // Pass ?server= so Mainsail/Fluidd connects its WebSocket back to the
    // same Cloudflare-tunnelled host rather than trying the stored local IP.
    final remoteUri = Uri.parse(remote);
    final wsScheme  = remoteUri.scheme == 'https' ? 'wss' : 'ws';
    final serverHint = '$wsScheme://${remoteUri.host}';
    _loadUrl('$remote/?server=${Uri.encodeComponent(serverHint)}');
  }

  Future<void> _loadUrl(String url) async {
    await _webController.loadRequest(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.printer.name),
            Text(
              _usingRemote ? 'Remote (tunnel)' : 'Local network',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _usingRemote ? Colors.orange : Colors.green,
                  ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          // Manual toggle between local and remote
          if (widget.printer.remoteHost != null)
            IconButton(
              icon: Icon(
                _usingRemote ? Icons.wifi : Icons.cloud_outlined,
                size: 20,
              ),
              tooltip: _usingRemote ? 'Switch to local' : 'Switch to remote',
              onPressed: () {
                _fallbackTimer?.cancel();
                if (_usingRemote) {
                  setState(() => _usingRemote = false);
                  _didFallback = false;
                  _loadUrl(widget.printer.host);
                } else {
                  _tryRemote();
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _fallbackTimer?.cancel();
              _didFallback = false;
              _startLoad();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _webController),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
