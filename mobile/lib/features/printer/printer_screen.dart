import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/printer_config.dart';

/// Full-screen WebView showing the local Mainsail/Fluidd instance.
///
/// Connection strategy:
///   • Remote-first printers (preferRemote=true, e.g. work printer on a
///     different network) skip the local attempt entirely and go straight
///     to the Cloudflare tunnel URL — no 3-second wasted timeout.
///   • Local-first printers try local first; if the main page hasn't loaded
///     after 3 s the screen falls back to the tunnel URL automatically.
///
/// Error handling:
///   • HTTP errors (4xx/5xx) on the main frame — e.g. Cloudflare Error 1033
///     when the tunnel is down — show an in-app overlay instead of the raw
///     Cloudflare HTML, with contextual recovery buttons.
///   • Network-level errors on the main frame (no connection, DNS failure,
///     SSL error) while in tunnel mode show the same overlay.
///   Sub-resource errors (webcam URLs pointing at localhost, etc.) are
///   intentionally ignored so they don't flip the whole page into error state.
class PrinterScreen extends StatefulWidget {
  final PrinterConfig printer;

  const PrinterScreen({super.key, required this.printer});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen>
    with WidgetsBindingObserver {
  late final WebViewController _webController;

  bool    _loading     = true;
  bool    _usingRemote = false;
  bool    _didFallback = false; // prevent double-fallback in one load cycle
  String? _errorType;           // 'tunnel' | 'local' | null (no error)
  Timer?  _fallbackTimer;

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
          if (mounted) setState(() { _loading = true; _errorType = null; });
        },
        onPageFinished: (_) {
          _fallbackTimer?.cancel();
          if (mounted) setState(() => _loading = false);
        },

        // ── Main-frame HTTP errors (Cloudflare 530, nginx 502, etc.) ──────
        // Sub-resource errors are ignored — Mainsail loads webcam URLs that
        // point at localhost and will always 404/fail on the phone.
        onHttpError: (HttpResponseError error) {
          if (!error.request.isForMainFrame) return;
          final code = error.response?.statusCode ?? 0;
          if (code >= 400 && mounted) {
            _fallbackTimer?.cancel();
            setState(() {
              _loading   = false;
              _errorType = _usingRemote ? 'tunnel' : 'local';
            });
          }
        },

        // ── Main-frame network errors (no connection, DNS, SSL) ───────────
        // Only surface the in-app error overlay when we're already in tunnel
        // mode (or have no tunnel fallback). While still on local, a network
        // error is normal — the fallback timer handles the switch to tunnel.
        onWebResourceError: (WebResourceError error) {
          if (!error.isForMainFrame) return;
          final noFallback = widget.printer.remoteHost == null;
          if ((_usingRemote || noFallback) && mounted) {
            _fallbackTimer?.cancel();
            setState(() {
              _loading   = false;
              _errorType = _usingRemote ? 'tunnel' : 'local';
            });
          }
        },
      ));
  }

  /// Load the correct starting URL.
  ///
  /// Remote-first printers (preferRemote=true) skip straight to the tunnel
  /// so there's no 3-second wasted local timeout for a printer that's on a
  /// completely different network.
  void _startLoad() {
    _fallbackTimer?.cancel();
    _didFallback = false;
    _errorType   = null;

    final remote     = widget.printer.remoteHost;
    final goRemote   = widget.printer.preferRemote && remote != null;

    if (goRemote) {
      // Remote-first: straight to tunnel, no local attempt
      _usingRemote = true;
      _didFallback = true;
      _loadRemoteUrl();
    } else {
      // Local-first: try local, fall back to tunnel after 3 s if needed
      _usingRemote = false;
      _loadUrl(widget.printer.host);
      if (remote != null) {
        _fallbackTimer = Timer(const Duration(seconds: 3), _tryRemote);
      }
    }
  }

  void _tryRemote() {
    final remote = widget.printer.remoteHost;
    if (_didFallback || remote == null) return;
    _didFallback = true;
    _fallbackTimer?.cancel();
    if (mounted) setState(() => _usingRemote = true);
    _loadRemoteUrl();
  }

  void _loadRemoteUrl() {
    final remote    = widget.printer.remoteHost!;
    final remoteUri = Uri.parse(remote);
    final wsScheme  = remoteUri.scheme == 'https' ? 'wss' : 'ws';
    final serverHint = '$wsScheme://${remoteUri.host}';
    _loadUrl('$remote/?server=${Uri.encodeComponent(serverHint)}');
  }

  Future<void> _loadUrl(String url) async {
    await _webController.loadRequest(Uri.parse(url));
  }

  // ── Error recovery actions ──────────────────────────────────────────────────

  void _retryCurrentUrl() {
    setState(() { _errorType = null; _loading = true; });
    if (_usingRemote) {
      _loadRemoteUrl();
    } else {
      _loadUrl(widget.printer.host);
    }
  }

  void _switchToLocal() {
    _fallbackTimer?.cancel();
    _didFallback = false;
    setState(() { _errorType = null; _usingRemote = false; _loading = true; });
    _loadUrl(widget.printer.host);
  }

  void _switchToRemote() {
    _fallbackTimer?.cancel();
    setState(() { _errorType = null; _loading = true; });
    _tryRemote();
  }

  @override
  Widget build(BuildContext context) {
    final hasRemote = widget.printer.remoteHost != null;
    final hasLocal  = !widget.printer.preferRemote ||
        widget.printer.host != widget.printer.remoteHost;

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
          if (hasRemote)
            IconButton(
              icon: Icon(
                _usingRemote ? Icons.wifi : Icons.cloud_outlined,
                size: 20,
              ),
              tooltip: _usingRemote ? 'Switch to local' : 'Switch to remote',
              onPressed: () {
                if (_usingRemote) {
                  _switchToLocal();
                } else {
                  _switchToRemote();
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
          // WebView always present in tree — keeps state across overlay show/hide
          WebViewWidget(controller: _webController),

          // Loading spinner
          if (_loading && _errorType == null)
            const Center(child: CircularProgressIndicator()),

          // In-app error overlay — replaces the raw Cloudflare/nginx error page
          if (_errorType != null)
            _ErrorOverlay(
              isTunnel:   _errorType == 'tunnel',
              hasLocal:   hasLocal,
              hasRemote:  hasRemote && !_usingRemote,
              onRetry:    _retryCurrentUrl,
              onLocal:    _switchToLocal,
              onRemote:   _switchToRemote,
            ),
        ],
      ),
    );
  }
}

// ── In-app error overlay ──────────────────────────────────────────────────────

class _ErrorOverlay extends StatelessWidget {
  final bool isTunnel;
  final bool hasLocal;
  final bool hasRemote;
  final VoidCallback onRetry;
  final VoidCallback onLocal;
  final VoidCallback onRemote;

  const _ErrorOverlay({
    required this.isTunnel,
    required this.hasLocal,
    required this.hasRemote,
    required this.onRetry,
    required this.onLocal,
    required this.onRemote,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final (icon, title, body) = isTunnel
        ? (
            Icons.cloud_off_outlined,
            'Tunnel unreachable',
            'The Cloudflare tunnel to your printer is not responding.\n\n'
                'This usually means:\n'
                '• cloudflared restarted and has a new URL\n'
                '• The Pi lost its internet connection\n\n'
                'Try switching to local Wi-Fi, or restart cloudflared on '
                'the Pi and re-run MOONGATE_PAIR to get the new tunnel URL.',
          )
        : (
            Icons.wifi_off_outlined,
            'Printer unreachable',
            'Could not connect to your printer on the local network.\n\n'
                'Make sure your phone is on the same Wi-Fi as the printer '
                'and that Moonraker is running.',
          );

    return Container(
      color: cs.surface,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: cs.error),
          const SizedBox(height: 20),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: cs.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            body,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurface.withValues(alpha: 0.7)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Retry same URL
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),

          // Switch to local (shown when tunnel failed and local URL exists)
          if (isTunnel && hasLocal) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onLocal,
              icon: const Icon(Icons.wifi),
              label: const Text('Try local network'),
            ),
          ],

          // Switch to tunnel (shown when local failed and tunnel exists)
          if (!isTunnel && hasRemote) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRemote,
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('Try tunnel'),
            ),
          ],
        ],
      ),
    );
  }
}
