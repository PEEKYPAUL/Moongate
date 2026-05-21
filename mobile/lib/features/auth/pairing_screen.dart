import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/auth_service.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _codeController = TextEditingController();
  final _hostController = TextEditingController();
  bool _scanning = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _hostController.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final code = _codeController.text.trim();
    final host = _hostController.text.trim();
    if (code.isEmpty || host.isEmpty) {
      setState(() => _error = 'Enter the printer IP and pairing code.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await AuthService.instance.exchangeCode(
      host: host,
      code: code,
      deviceName: 'Moongate Mobile',
    );
    if (!mounted) return;
    if (result.success) {
      context.go('/printer');
    } else {
      setState(() {
        _error = result.error ?? 'Pairing failed.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moongate')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add Printer',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Run MOONGATE_PAIR in your Klipper console, then enter the code or scan the QR.',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Printer Tailscale IP:port',
                hintText: '100.x.x.x:7125',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
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
                  onPressed: () => setState(() => _scanning = true),
                ),
              ],
            ),
            if (_scanning) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 240,
                child: MobileScanner(
                  onDetect: (capture) {
                    final barcode = capture.barcodes.first;
                    final raw = barcode.rawValue ?? '';
                    // QR payload: moongate://pair?code=GATE-XXXX-XXXX
                    final match = RegExp(r'code=(GATE-[A-Z0-9]+-[A-Z0-9]+)')
                        .firstMatch(raw);
                    if (match != null) {
                      _codeController.text = match.group(1)!;
                      setState(() => _scanning = false);
                    }
                  },
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const Spacer(),
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
