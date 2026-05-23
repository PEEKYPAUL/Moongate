import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../../models/printer_config.dart';
import '../../services/auth_service.dart';
import '../../services/network_discovery_service.dart';
import '../../services/printer_registry.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen>
    with WidgetsBindingObserver {
  // Two 4-digit code boxes
  final _code1Controller = TextEditingController();
  final _code2Controller = TextEditingController();
  final _code1Focus      = FocusNode();
  final _code2Focus      = FocusNode();

  // Separate fields for local IP and tunnel URL so both can be stored
  final _localController  = TextEditingController();
  final _tunnelController = TextEditingController();
  final _nameController   = TextEditingController();

  // Explicit controller gives us start/stop control over the camera resource.
  // Created fresh each time the scanner is opened; disposed when closed or
  // when the app goes to background so the camera is properly released.
  MobileScannerController? _scannerController;

  bool _scanning        = false;
  bool _scannerOpening  = false; // guard against overlapping open calls
  bool _loading         = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController?.dispose();
    _code1Controller.dispose();
    _code2Controller.dispose();
    _code1Focus.dispose();
    _code2Focus.dispose();
    _localController.dispose();
    _tunnelController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // ── Scanner lifecycle ───────────────────────────────────────────────────────

  /// Stop or restart the camera when the app is backgrounded / foregrounded.
  /// Without this, coming back from the permission dialog or from another
  /// app often leaves the scanner in a broken state.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_scanning) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _scannerController?.stop();
      case AppLifecycleState.resumed:
        // Re-open with a fresh controller rather than restarting the old one.
        // Calling start() on a stopped controller can fail on some Android OEMs;
        // a fresh controller + 600 ms delay is more reliable.
        _restartScanner();
      default:
        break;
    }
  }

  /// Open the QR scanner with a fresh controller.
  ///
  /// If a previous controller exists it is disposed first and we wait 600 ms
  /// for the Android Camera2 layer to fully release the hardware before
  /// acquiring it again.  Skipping this delay is the most common cause of
  /// "Camera unavailable" errors on Android.
  Future<void> _openScanner() async {
    if (_scannerOpening) return;
    _scannerOpening = true;

    if (_scannerController != null) {
      _scannerController!.dispose();
      _scannerController = null;
      if (mounted) setState(() => _scanning = false);
      // Android Camera2 is asynchronous — the hardware isn't released
      // until the native session fully closes, which can take 400-800 ms.
      await Future.delayed(const Duration(milliseconds: 700));
    }

    if (!mounted) { _scannerOpening = false; return; }

    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
    );
    _scannerOpening = false;
    setState(() => _scanning = true);
  }

  /// Close the scanner and release the camera.
  void _closeScanner() {
    _scannerController?.dispose();
    _scannerController = null;
    _scannerOpening = false;
    setState(() => _scanning = false);
  }

  /// Restart after an error: dispose the broken controller, wait for the
  /// hardware to release, then open a fresh one.
  Future<void> _restartScanner() async {
    _scannerController?.dispose();
    _scannerController = null;
    _scannerOpening = false;
    if (mounted) setState(() => _scanning = false);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) _openScanner();
  }

  /// Full code string assembled from both boxes: GATE-1234-5678
  String get _fullCode =>
      'GATE-${_code1Controller.text.trim()}-${_code2Controller.text.trim()}';

  /// Normalises whatever the user typed into a full HTTPS URL.
  ///
  /// Handles all three common forms:
  ///   "racing-partly-mouse-surprised"             → https://racing-partly-mouse-surprised.trycloudflare.com
  ///   "racing-partly-mouse-surprised.trycloudflare.com" → https://racing-partly-mouse-surprised.trycloudflare.com
  ///   "https://racing-partly-mouse-surprised.trycloudflare.com" → unchanged
  String _normalizeTunnelUrl(String raw) {
    if (raw.isEmpty) return raw;
    // If there's no dot in the input it must be just the subdomain part
    if (!raw.contains('.')) {
      raw = '$raw.trycloudflare.com';
    }
    // Ensure the scheme is present
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      raw = 'https://$raw';
    }
    return raw;
  }

  Future<void> _pair() async {
    final localRaw  = _localController.text.trim();
    final tunnelRaw = _normalizeTunnelUrl(_tunnelController.text.trim());
    final name      = _nameController.text.trim().isEmpty
        ? 'My Printer' : _nameController.text.trim();
    final part1 = _code1Controller.text.trim();
    final part2 = _code2Controller.text.trim();

    if (localRaw.isEmpty && tunnelRaw.isEmpty) {
      setState(() => _error =
          'Enter a local IP, a tunnel URL, or both.');
      return;
    }
    if (part1.length != 4 || part2.length != 4) {
      setState(() => _error = 'Enter all 8 digits of the pairing code.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    // Try local first (if provided), then fall back to tunnel.
    // This lets the user be on either network and still pair.
    String? successHost;
    AuthResult? result;

    if (localRaw.isNotEmpty) {
      result = await AuthService.instance.exchangeCode(
        host: localRaw, code: _fullCode, deviceName: name,
      );
      if (result.success) successHost = localRaw;
    }

    if (successHost == null && tunnelRaw.isNotEmpty) {
      result = await AuthService.instance.exchangeCode(
        host: tunnelRaw, code: _fullCode, deviceName: name,
      );
      if (result.success) successHost = tunnelRaw;
    }

    if (!mounted) return;

    if (successHost != null && result!.success) {
      // Determine the stored local host and optional remote host.
      // If the user only provided the tunnel URL, use it as the local host
      // but mark preferRemote=true so we always go via tunnel.
      final storedLocal = localRaw.isNotEmpty
          ? AuthService.buildBaseUrl(localRaw)
          : AuthService.buildBaseUrl(tunnelRaw);
      final storedRemote = tunnelRaw.isNotEmpty ? tunnelRaw : null;
      final preferRemote = localRaw.isEmpty && tunnelRaw.isNotEmpty;

      final printer = PrinterConfig(
        id:           const Uuid().v4(),
        name:         name,
        host:         storedLocal,
        token:        AuthService.instance.token!,
        remoteHost:   storedRemote,
        preferRemote: preferRemote,
      );
      await PrinterRegistry.instance.add(printer);
      if (!mounted) return;
      if (context.canPop()) { context.pop(); } else { context.go('/dashboard'); }
    } else {
      setState(() {
        _error   = result?.error ?? 'Could not reach printer on local or tunnel.';
        _loading = false;
      });
    }
  }

  /// Handles any scanned QR value. Three formats:
  ///
  ///   1. moongate://pair?local=IP:80&remote=https://x.trycloudflare.com&token=JWT
  ///      Rich QR — pre-issued token, works with no network at scan time.
  ///
  ///   2. moongate://pair?code=GATE-XXXX-XXXX
  ///      Code-only QR — fills the code boxes; user still needs to tap Connect.
  ///
  ///   3. Bare GATE-XXXX-XXXX (or text containing that pattern)
  ///      Same as above, fills code boxes.
  void _applyScannedCode(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme == 'moongate') {
      // ── Format 1: full token QR ────────────────────────────────────────────
      final local  = uri.queryParameters['local'];
      final remote = uri.queryParameters['remote'];
      final token  = uri.queryParameters['token'];
      if (local != null && token != null) {
        _closeScanner();
        _pairWithDirectToken(local: local, remote: remote, token: token);
        return;
      }

      // ── Format 2: code-only QR (moongate://pair?code=GATE-XXXX-XXXX) ──────
      final code = uri.queryParameters['code'];
      if (code != null) {
        final m = RegExp(r'GATE-([A-Z0-9]{4})-([A-Z0-9]{4})')
            .firstMatch(code.toUpperCase());
        if (m != null) {
          _code1Controller.text = m.group(1)!;
          _code2Controller.text = m.group(2)!;
          _closeScanner();
          return;
        }
      }
    }

    // ── Format 3: bare GATE code anywhere in the raw string ──────────────────
    final match = RegExp(r'GATE-([A-Z0-9]{4})-([A-Z0-9]{4})')
        .firstMatch(raw.toUpperCase());
    if (match != null) {
      _code1Controller.text = match.group(1)!;
      _code2Controller.text = match.group(2)!;
      _closeScanner();
    }
  }

  /// Called when the QR contained a pre-issued JWT token (rich QR format).
  /// Stores token + both host addresses directly — no HTTP request needed,
  /// so works even when the phone can't reach the Pi (AP isolation, remote).
  Future<void> _pairWithDirectToken({
    required String local,
    String? remote,
    required String token,
  }) async {
    final name = _nameController.text.trim().isEmpty
        ? 'My Printer' : _nameController.text.trim();

    setState(() { _loading = true; _error = null; });

    try {
      await AuthService.instance.persistDirect(host: local, token: token);
      if (!mounted) return;

      // If no local URL in the QR (edge case), fall back to using tunnel as host
      final localHost = local.isNotEmpty
          ? AuthService.instance.host!
          : (remote ?? AuthService.instance.host!);

      final printer = PrinterConfig(
        id:           const Uuid().v4(),
        name:         name,
        host:         localHost,
        token:        AuthService.instance.token!,
        remoteHost:   remote,
        // Prefer remote if there's a tunnel URL and no meaningful local address
        preferRemote: remote != null && local.startsWith('localhost'),
      );
      await PrinterRegistry.instance.add(printer);
      if (!mounted) return;
      if (context.canPop()) { context.pop(); } else { context.go('/dashboard'); }
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Pairing failed: $e'; });
    }
  }

  Future<void> _showNetworkPicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _NetworkPickerSheet(),
    );
    if (selected != null) _localController.text = selected;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Printer'),
        leading: PrinterRegistry.instance.printers.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/dashboard'),
              )
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Run MOONGATE_PAIR in your Klipper console, then scan the QR '
              'or enter the code below.',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),

            // ── Printer name ───────────────────────────────────────────────
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Printer name',
                hintText: 'e.g. Voron 2.4',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),

            // ── Local IP + find button ─────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _localController,
                    decoration: const InputDecoration(
                      labelText: 'Local IP (same network)',
                      hintText: '192.168.1.50',
                      border: OutlineInputBorder(),
                      helperText: 'Leave blank if adding remotely',
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Find on local network',
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 16),
                    ),
                    onPressed: _showNetworkPicker,
                    child: const Icon(Icons.wifi_find),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Tunnel URL ─────────────────────────────────────────────────
            TextField(
              controller: _tunnelController,
              decoration: const InputDecoration(
                labelText: 'Tunnel URL (remote access)',
                hintText: 'words-words-words  or  https://…trycloudflare.com',
                border: OutlineInputBorder(),
                helperText:
                    'Paste the full URL or just the subdomain (e.g. racing-partly-mouse)',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 8),

            // ── Tip ────────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: cs.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Adding remotely? Leave the local IP blank and paste '
                      'the tunnel URL (or just the subdomain part shown in '
                      'the Klipper console). The code exchange goes via the '
                      'tunnel — no local Wi-Fi needed.',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Pairing code ───────────────────────────────────────────────
            Text(
              'Pairing code',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: cs.onSurface.withValues(alpha:0.7),
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // "GATE-" prefix label
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(8)),
                    border: Border.all(color: cs.outline),
                  ),
                  child: Text(
                    'GATE-',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: cs.primary,
                    ),
                  ),
                ),

                // First 4 digits
                Expanded(
                  child: TextField(
                    controller:   _code1Controller,
                    focusNode:    _code1Focus,
                    maxLength:    4,
                    keyboardType: TextInputType.number,
                    textAlign:    TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700,
                        letterSpacing: 4),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '0000',
                      hintStyle: TextStyle(
                          color: cs.onSurface.withValues(alpha:0.25),
                          letterSpacing: 4),
                      border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: cs.outline),
                      ),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      if (v.length == 4) {
                        _code2Focus.requestFocus();
                      }
                    },
                  ),
                ),

                // Separator dash
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    border: Border.symmetric(
                        horizontal: BorderSide(color: cs.outline)),
                  ),
                  child: Text(
                    '-',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700,
                        color: cs.onSurface.withValues(alpha:0.5)),
                  ),
                ),

                // Second 4 digits
                Expanded(
                  child: TextField(
                    controller:   _code2Controller,
                    focusNode:    _code2Focus,
                    maxLength:    4,
                    keyboardType: TextInputType.number,
                    textAlign:    TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700,
                        letterSpacing: 4),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '0000',
                      hintStyle: TextStyle(
                          color: cs.onSurface.withValues(alpha:0.25),
                          letterSpacing: 4),
                      border: const OutlineInputBorder(
                          borderRadius: BorderRadius.horizontal(
                              right: Radius.circular(8))),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(8)),
                        borderSide: BorderSide(color: cs.outline),
                      ),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _pair(),
                  ),
                ),

                // QR scanner toggle
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Scan QR',
                  onPressed: _scanning ? _closeScanner : _openScanner,
                ),
              ],
            ),

            // ── QR camera preview ──────────────────────────────────────────
            if (_scanning) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 240,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: MobileScanner(
                    controller: _scannerController!,
                    onDetect: (capture) {
                      if (capture.barcodes.isEmpty) return;
                      final raw = capture.barcodes.first.rawValue ?? '';
                      if (raw.isEmpty) return;
                      _closeScanner(); // release camera before processing
                      _applyScannedCode(raw);
                    },
                    errorBuilder: (context, error, child) {
                      final isDenied = error.errorCode ==
                          MobileScannerErrorCode.permissionDenied;
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isDenied ? Icons.no_photography : Icons.videocam_off,
                              color: Colors.orange,
                              size: 40,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isDenied
                                  ? 'Camera permission needed'
                                  : 'Camera unavailable',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            // Show the actual error code — helps diagnose
                            // generic errors vs permission issues.
                            Text(
                              error.errorCode.name,
                              style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 11),
                            ),
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20),
                              child: Text(
                                isDenied
                                    ? 'Go to Settings → Apps → Moongate → Permissions and enable Camera, then tap Retry.'
                                    : 'The camera could not be opened.\nWait a moment and tap Retry.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ),
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                              onPressed: _restartScanner,
                              icon: const Icon(Icons.refresh,
                                  color: Colors.white70),
                              label: const Text('Retry',
                                  style: TextStyle(color: Colors.white70)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: Colors.white30),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],

            // ── Error ──────────────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _loading ? null : _pair,
              child: _loading
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Local network printer picker ──────────────────────────────────────────────

class _NetworkPickerSheet extends StatefulWidget {
  const _NetworkPickerSheet();

  @override
  State<_NetworkPickerSheet> createState() => _NetworkPickerSheetState();
}

class _NetworkPickerSheetState extends State<_NetworkPickerSheet> {
  final _manualController = TextEditingController();
  final _discovery        = NetworkDiscoveryService.instance;

  bool _scanning = false;
  String? _myIp;
  String? _status;
  final List<DiscoveredPrinter> _found = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final ip = await _discovery.myLocalIp();
    if (mounted) setState(() => _myIp = ip);
  }

  Future<void> _startScan() async {
    if (_myIp == null) {
      setState(() => _status =
          'No Wi-Fi detected. Connect to your home network first.');
      return;
    }
    setState(() {
      _scanning = true;
      _found.clear();
      _status = 'Scanning ${_myIp!.split('.').take(3).join('.')}.0/24…';
    });

    await for (final printer in _discovery.scanForPrinters()) {
      if (!mounted) break;
      setState(() => _found.add(printer));
    }

    if (mounted) {
      setState(() {
        _scanning = false;
        _status   = _found.isEmpty
            ? 'No printers found. Make sure Klipper is running.'
            : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize:     0.4,
        maxChildSize:     0.92,
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha:0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Find your printer',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            if (_myIp != null)
              Text(
                'Your phone is on ${_myIp!.split('.').take(3).join('.')}.x',
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha:0.55), fontSize: 13),
              ),
            const SizedBox(height: 20),

            FilledButton.icon(
              icon: _scanning
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search),
              label: Text(_scanning ? 'Scanning…' : 'Scan for Klipper printers'),
              onPressed: _scanning ? null : _startScan,
            ),

            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(_status!,
                  style: TextStyle(
                      color: cs.onSurface.withValues(alpha:0.6), fontSize: 13)),
            ],

            if (_found.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._found.map((p) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.print_outlined,
                          color: Colors.green),
                      title: Text(p.ip),
                      subtitle: const Text('Moonraker on :7125'),
                      trailing: TextButton(
                        onPressed: () => Navigator.pop(context, p.host),
                        child: const Text('Select'),
                      ),
                    ),
                  )),
            ],

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),

            Text('Or enter address manually',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: cs.primary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualController,
                    decoration: const InputDecoration(
                      hintText: '192.168.1.x',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final v = _manualController.text.trim();
                    if (v.isNotEmpty) Navigator.pop(context, v);
                  },
                  child: const Text('Use'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
