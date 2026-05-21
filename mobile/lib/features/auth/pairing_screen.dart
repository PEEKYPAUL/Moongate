import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../models/printer_config.dart';
import '../../services/auth_service.dart';
import '../../services/printer_registry.dart';
import '../../services/tailscale_service.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _codeController = TextEditingController();
  final _hostController = TextEditingController();
  final _nameController = TextEditingController();
  bool _scanning = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _hostController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final code = _codeController.text.trim();
    final host = _hostController.text.trim();
    final name = _nameController.text.trim().isEmpty
        ? 'My Printer'
        : _nameController.text.trim();

    if (code.isEmpty || host.isEmpty) {
      setState(() => _error = 'Enter the printer IP:port and pairing code.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await AuthService.instance.exchangeCode(
      host: host,
      code: code,
      deviceName: name,
    );

    if (!mounted) return;

    if (result.success) {
      final printer = PrinterConfig(
        id: const Uuid().v4(),
        name: name,
        host: host,
        token: AuthService.instance.token!,
      );
      await PrinterRegistry.instance.add(printer);
      context.go('/dashboard');
    } else {
      setState(() {
        _error = result.error ?? 'Pairing failed.';
        _loading = false;
      });
    }
  }

  Future<void> _showTailscalePicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _TailscalePickerSheet(),
    );
    if (selected != null) {
      _hostController.text = selected;
    }
  }

  @override
  Widget build(BuildContext context) {
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
              'Run MOONGATE_PAIR in your Klipper console, then enter the code or scan the QR.',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6)),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Printer name',
                hintText: 'e.g. Ender 3 Pro',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            // ── Tailscale IP picker ────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _hostController,
                    decoration: const InputDecoration(
                      labelText: 'Printer Tailscale IP:port',
                      hintText: '100.x.x.x:7125',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Pick from Tailscale',
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 16),
                    ),
                    onPressed: _showTailscalePicker,
                    child: const Icon(Icons.wifi_tethering),
                  ),
                ),
              ],
            ),
            // ──────────────────────────────────────────────────────
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      labelText: 'Pairing code',
                      hintText: 'GATE-XXXX-XXXX',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Scan QR',
                  onPressed: () => setState(() => _scanning = !_scanning),
                ),
              ],
            ),
            if (_scanning) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 240,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: MobileScanner(
                    onDetect: (capture) {
                      final raw = capture.barcodes.first.rawValue ?? '';
                      final match = RegExp(r'code=(GATE-[A-Z0-9]+-[A-Z0-9]+)')
                          .firstMatch(raw);
                      if (match != null) {
                        _codeController.text = match.group(1)!;
                        setState(() => _scanning = false);
                      }
                    },
                  ),
                ),
              ),
            ],
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
                      height: 20,
                      width: 20,
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

// ── Tailscale device picker bottom sheet ──────────────────────────────────────

class _TailscalePickerSheet extends StatefulWidget {
  const _TailscalePickerSheet();

  @override
  State<_TailscalePickerSheet> createState() => _TailscalePickerSheetState();
}

class _TailscalePickerSheetState extends State<_TailscalePickerSheet> {
  final _manualController = TextEditingController();
  bool _scanning = false;
  bool _tailscaleConnected = false;
  final List<TailscaleDevice> _found = [];
  String? _scanStatus;

  @override
  void initState() {
    super.initState();
    _checkTailscale();
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _checkTailscale() async {
    final connected = await TailscaleService.instance.checkConnected();
    if (mounted) setState(() => _tailscaleConnected = connected);
  }

  Future<void> _openTailscale() async {
    // Try the Tailscale URL scheme first; fall back to Play Store
    final uri = Uri.parse('tailscale://');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await launchUrl(
        Uri.parse(
            'https://play.google.com/store/apps/details?id=com.tailscale.ipn'),
        mode: LaunchMode.externalApplication,
      );
    }
    // Re-check connection after returning from Tailscale
    await Future.delayed(const Duration(milliseconds: 800));
    await _checkTailscale();
  }

  Future<void> _startScan() async {
    if (!_tailscaleConnected) {
      setState(() => _scanStatus = 'Connect to Tailscale first.');
      return;
    }
    setState(() {
      _scanning = true;
      _found.clear();
      _scanStatus = 'Scanning your Tailscale network for Klipper printers…';
    });

    await for (final device in TailscaleService.instance.scanForPrinters()) {
      if (!mounted) break;
      setState(() => _found.add(device));
    }

    if (mounted) {
      setState(() {
        _scanning = false;
        _scanStatus = _found.isEmpty
            ? 'No printers found. Make sure Klipper is running and try again.'
            : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Pick a Tailscale device',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),

            // Step 1 — connect Tailscale
            _SectionLabel(label: '1  Connect to Tailscale'),
            const SizedBox(height: 8),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: cs.outlineVariant),
              ),
              leading: Icon(
                _tailscaleConnected
                    ? Icons.check_circle
                    : Icons.vpn_lock_outlined,
                color: _tailscaleConnected ? Colors.green : cs.primary,
              ),
              title: Text(_tailscaleConnected
                  ? 'Tailscale connected'
                  : 'Open Tailscale App'),
              subtitle: Text(_tailscaleConnected
                  ? 'Your device is on the Tailscale network'
                  : 'Sign in and connect, then come back here'),
              trailing: _tailscaleConnected
                  ? null
                  : const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _tailscaleConnected ? null : _openTailscale,
            ),
            const SizedBox(height: 20),

            // Step 2 — scan
            _SectionLabel(label: '2  Find your printer'),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: _scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.search),
              label: Text(_scanning ? 'Scanning…' : 'Scan for Klipper printers'),
              onPressed: (_scanning || !_tailscaleConnected) ? null : _startScan,
            ),
            if (_scanStatus != null) ...[
              const SizedBox(height: 8),
              Text(_scanStatus!,
                  style: TextStyle(
                      color: cs.onSurface.withOpacity(0.6), fontSize: 13)),
            ],
            if (_found.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._found.map(
                (d) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading:
                        const Icon(Icons.print_outlined, color: Colors.green),
                    title: Text(d.host),
                    subtitle: const Text('Moonraker responding on port 7125'),
                    trailing: TextButton(
                      onPressed: () => Navigator.pop(context, d.host),
                      child: const Text('Select'),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),

            // Manual entry
            _SectionLabel(label: 'Or enter IP manually'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualController,
                    decoration: const InputDecoration(
                      hintText: '100.x.x.x:7125',
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

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      );
}
