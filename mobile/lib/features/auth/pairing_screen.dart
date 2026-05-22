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

class _PairingScreenState extends State<PairingScreen> {
  // Two 4-digit code boxes
  final _code1Controller = TextEditingController();
  final _code2Controller = TextEditingController();
  final _code1Focus      = FocusNode();
  final _code2Focus      = FocusNode();

  final _hostController = TextEditingController();
  final _nameController = TextEditingController();

  bool _scanning = false;
  bool _loading  = false;
  String? _error;

  @override
  void dispose() {
    _code1Controller.dispose();
    _code2Controller.dispose();
    _code1Focus.dispose();
    _code2Focus.dispose();
    _hostController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// Full code string assembled from both boxes: GATE-1234-5678
  String get _fullCode =>
      'GATE-${_code1Controller.text.trim()}-${_code2Controller.text.trim()}';

  Future<void> _pair() async {
    final host = _hostController.text.trim();
    final name = _nameController.text.trim().isEmpty
        ? 'My Printer'
        : _nameController.text.trim();
    final part1 = _code1Controller.text.trim();
    final part2 = _code2Controller.text.trim();

    if (host.isEmpty) {
      setState(() => _error = 'Enter or scan your printer address first.');
      return;
    }
    if (part1.length != 4 || part2.length != 4) {
      setState(() => _error = 'Enter all 8 digits of the pairing code.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    final result = await AuthService.instance.exchangeCode(
      host:       host,
      code:       _fullCode,
      deviceName: name,
    );

    if (!mounted) return;

    if (result.success) {
      final printer = PrinterConfig(
        id:    const Uuid().v4(),
        name:  name,
        host:  AuthService.instance.host!,
        token: AuthService.instance.token!,
      );
      await PrinterRegistry.instance.add(printer);
      if (!mounted) return;
      context.go('/dashboard');
    } else {
      setState(() {
        _error   = result.error ?? 'Pairing failed.';
        _loading = false;
      });
    }
  }

  /// Handles any scanned QR value.
  ///
  /// Two formats are supported:
  ///
  ///   1. moongate://pair?host=192.168.1.x:80&token=JWT
  ///      Pre-issued token — no network request needed. Works even when the
  ///      phone can't reach the Pi directly (WiFi AP isolation etc.).
  ///
  ///   2. GATE-XXXX-XXXX (or a URL containing that pattern)
  ///      Manual code — fills the digit boxes so the user taps Connect.
  void _applyScannedCode(String raw) {
    // ── Format 1: direct JWT token in QR ─────────────────────────────────────
    // moongate://pair?local=IP:80&remote=https://x.trycloudflare.com&token=JWT
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme == 'moongate') {
      final local  = uri.queryParameters['local'];
      final remote = uri.queryParameters['remote'];
      final token  = uri.queryParameters['token'];
      if (local != null && token != null) {
        setState(() => _scanning = false);
        _pairWithDirectToken(local: local, remote: remote, token: token);
        return;
      }
    }

    // ── Format 2: GATE-XXXX-XXXX code ────────────────────────────────────────
    final match = RegExp(r'GATE-(\d{4})-(\d{4})').firstMatch(raw.toUpperCase());
    if (match != null) {
      _code1Controller.text = match.group(1)!;
      _code2Controller.text = match.group(2)!;
      setState(() => _scanning = false);
    }
  }

  /// Called when the QR contained a pre-issued JWT token.
  /// Stores token + both host addresses directly — no HTTP request needed,
  /// so works even when the phone can't reach the Pi directly.
  Future<void> _pairWithDirectToken({
    required String local,
    String? remote,
    required String token,
  }) async {
    final name = _nameController.text.trim().isEmpty
        ? 'My Printer'
        : _nameController.text.trim();

    setState(() { _loading = true; _error = null; });

    try {
      // Persist the local host + token (remote URL stored separately in config).
      await AuthService.instance.persistDirect(host: local, token: token);

      if (!mounted) return;

      final printer = PrinterConfig(
        id:         const Uuid().v4(),
        name:       name,
        host:       AuthService.instance.host!,   // normalised local URL
        token:      AuthService.instance.token!,
        remoteHost: remote,                        // Cloudflare HTTPS URL or null
      );
      await PrinterRegistry.instance.add(printer);

      if (!mounted) return;
      // Pop back to dashboard — this resolves the `await context.push('/pair')`
      // in DashboardScreen, which then calls _load() and picks up the new printer.
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/dashboard');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error   = 'Pairing failed: $e';
      });
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
    if (selected != null) _hostController.text = selected;
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
              'Run MOONGATE_PAIR in your Klipper console to get a code.',
              style: TextStyle(color: cs.onSurface.withValues(alpha:0.6)),
            ),
            const SizedBox(height: 24),

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

            // ── Printer address + find button ──────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _hostController,
                    decoration: const InputDecoration(
                      labelText: 'Printer address',
                      hintText: '192.168.1.x',
                      border: OutlineInputBorder(),
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
                  onPressed: () => setState(() => _scanning = !_scanning),
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
                    onDetect: (capture) {
                      if (capture.barcodes.isEmpty) return;
                      final raw = capture.barcodes.first.rawValue ?? '';
                      if (raw.isEmpty) return;
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
                              isDenied ? Icons.camera_alt : Icons.error_outline,
                              color: Colors.orange,
                              size: 40,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isDenied
                                  ? 'Camera access denied'
                                  : 'Camera unavailable',
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'Go to Settings › Apps › Moongate\n'
                                '› Permissions › Camera → Allow',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12),
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
