import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/printer_config.dart';
import '../../services/printer_registry.dart';
import '../../services/supabase_service.dart';

/// v0.3.0 pairing flow (with v0.4.2 manual-entry fallback):
///
///   1. User opens MOONGATE_PAIR on the Pi → Pi pre-registers the
///      enrollment-token hash + its Ed25519 public key with Supabase.
///   2. Pi displays the GATE code via M118 + a QR containing
///      `moongate://pair?v=3&pk=<base64>&et=<raw>`.
///   3a. User scans the QR — app extracts `pk` and `et`.
///   3b. OR user types the GATE code shown on the Pi's console — app has
///       only `et`; the server uses its stored pubkey from the
///       enrollment row.
///   4. App asks for a friendly name and calls Supabase `/printer-claim`
///      with the current anonymous user's JWT.
///   5. On success, the printer row exists in Supabase owned by this
///      anonymous user. Add it to the local cache and navigate back.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _nameController      = TextEditingController(text: 'My Printer');

  // Two 4-digit boxes for the GATE code. Split lets us show a numpad
  // (TextInputType.number) instead of the full keyboard, and lets us
  // auto-advance focus from box 1 to box 2 after 4 digits.
  final _codeFirstController  = TextEditingController();
  final _codeSecondController = TextEditingController();
  final _codeFirstFocus       = FocusNode();
  final _codeSecondFocus      = FocusNode();

  MobileScannerController? _scannerController;
  StreamSubscription<BarcodeCapture>? _barcodeSub;

  bool   _scanning = false;
  bool   _loading  = false;
  String? _error;

  // QR-scan path: both fields populated.
  String? _scannedPubKey;
  String? _scannedEnrollmentToken;

  // Manual-entry path: normalised GATE-XXXX-XXXX token. Pubkey unknown
  // here — server uses its stored value from enrollment_tokens.
  String? _manualEnrollmentToken;

  @override
  void dispose() {
    _barcodeSub?.cancel();
    _scannerController?.dispose();
    _nameController.dispose();
    _codeFirstController.dispose();
    _codeSecondController.dispose();
    _codeFirstFocus.dispose();
    _codeSecondFocus.dispose();
    super.dispose();
  }

  // ── Manual code normalisation + box wiring ───────────────────────────────

  /// Build the canonical GATE-XXXX-XXXX form from the current contents of
  /// the two code boxes. Returns null until both boxes have exactly 4
  /// digits each (the formatters enforce digit-only + length 4 already,
  /// so this is mostly a length gate).
  static String? _normalisePairCode(String first, String second) {
    if (first.length != 4 || second.length != 4) return null;
    return 'GATE-$first-$second';
  }

  void _onFirstBoxChanged(String value) {
    // Auto-advance focus when the first box is full. The formatter caps
    // input at 4 digits so we don't have to handle longer strings here.
    if (value.length == 4) {
      _codeSecondFocus.requestFocus();
    }
    _updateManualCode();
  }

  void _onSecondBoxChanged(String _) {
    _updateManualCode();
  }

  void _updateManualCode() {
    final normalised = _normalisePairCode(
      _codeFirstController.text,
      _codeSecondController.text,
    );
    setState(() {
      _manualEnrollmentToken = normalised;
      // Clearing _error on every keystroke is noisy; only clear it when
      // the user has actually typed something that looks valid.
      if (normalised != null) _error = null;
    });
  }

  /// One 4-digit GATE-code box. Numpad keyboard, centered large digits,
  /// formatter clamps to digits-only and length 4. `isLast` controls the
  /// keyboard "action" button (next vs done) and whether textInputAction
  /// surfaces a Submit/Pair signal — done dismisses the keyboard on the
  /// final box.
  Widget _gateCodeBox({
    required TextEditingController controller,
    required FocusNode focusNode,
    required ValueChanged<String> onChanged,
    required bool isLast,
  }) {
    return TextField(
      controller: controller,
      focusNode:  focusNode,
      enabled:    !_loading,
      textAlign:  TextAlign.center,
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: 6,
      ),
      keyboardType: TextInputType.number,
      textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      onChanged: onChanged,
      decoration: const InputDecoration(
        counterText: '',
        hintText: '0000',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      ),
    );
  }

  // ── QR scanner ────────────────────────────────────────────────────────────

  Future<void> _openScanner() async {
    final before = await Permission.camera.status;
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isPermanentlyDenied) {
      _showPermissionDeniedDialog();
      return;
    }
    if (!status.isGranted) return;

    // Fresh-grant warmup — camera HAL needs ~700ms to register the
    // permission before bind succeeds reliably.
    if (before != PermissionStatus.granted) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    _barcodeSub?.cancel();
    _barcodeSub = null;
    _scannerController?.dispose();
    _scannerController = MobileScannerController(autoStart: false);

    _barcodeSub = _scannerController!.barcodes.listen((capture) {
      if (!mounted || capture.barcodes.isEmpty) return;
      final raw = capture.barcodes.first.rawValue ?? '';
      if (raw.isEmpty) return;
      _closeScanner();
      _applyScannedCode(raw);
    });

    setState(() => _scanning = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scannerController != null) {
        _scannerController!.start();
      }
    });
  }

  void _closeScanner() {
    _barcodeSub?.cancel();
    _barcodeSub = null;
    _scannerController?.stop();
    _scannerController?.dispose();
    _scannerController = null;
    if (mounted) setState(() => _scanning = false);
  }

  void _restartScanner() {
    _barcodeSub?.cancel();
    _barcodeSub = null;
    _scannerController?.stop();
    _scannerController?.dispose();
    _scannerController = null;
    setState(() => _scanning = false);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _openScanner();
    });
  }

  void _showPermissionDeniedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Camera permission required'),
        content: const Text(
          'Moongate needs camera access to scan QR codes.\n\n'
          'Open Settings → Apps → Moongate → Permissions '
          'and enable Camera, then come back and try again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () { Navigator.pop(ctx); openAppSettings(); },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // ── v=3 QR parsing ────────────────────────────────────────────────────────

  /// Parses `moongate://pair?v=3&pk=<base64>&et=<raw>` and either stages
  /// the values for confirmation or surfaces an error.
  void _applyScannedCode(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'moongate') {
      setState(() => _error =
          'Not a Moongate QR code. Run MOONGATE_PAIR on the printer to generate one.');
      return;
    }
    final version = uri.queryParameters['v'];
    final pk      = uri.queryParameters['pk'];
    final et      = uri.queryParameters['et'];
    if (version != '3' || pk == null || et == null || pk.isEmpty || et.isEmpty) {
      setState(() => _error =
          'This QR code is from an older Moongate version. Update the Pi to v0.3.0 first.');
      return;
    }
    setState(() {
      _scannedPubKey         = pk;
      _scannedEnrollmentToken = et;
      _error                 = null;
    });
  }

  // ── Claim ────────────────────────────────────────────────────────────────

  Future<void> _claim() async {
    // QR-scan path wins if present (it carries the pubkey for the
    // defense-in-depth server check). Manual path is the fallback.
    final scannedEt = _scannedEnrollmentToken;
    final manualEt  = _manualEnrollmentToken;
    final et = scannedEt ?? manualEt;
    if (et == null) {
      setState(() => _error =
          'Scan the QR code, or type the GATE code from the printer console.');
      return;
    }
    final pk = scannedEt != null ? _scannedPubKey : null;

    final name = _nameController.text.trim().isEmpty
        ? 'My Printer'
        : _nameController.text.trim();

    setState(() { _loading = true; _error = null; });

    try {
      final printerId = await SupabaseService.instance.claimPrinter(
        enrollmentToken: et,
        piPublicKey:     pk,
        name:            name,
      );
      await PrinterRegistry.instance.addClaimed(
        PrinterConfig(id: printerId, name: name),
      );
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/dashboard');
      }
    } on PairingNotFoundException catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    } on PairingConflictException catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Pairing failed: $e'; _loading = false; });
    }
  }

  void _resetScan() {
    setState(() {
      _scannedPubKey         = null;
      _scannedEnrollmentToken = null;
      _error                 = null;
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final hasScan   = _scannedPubKey != null && _scannedEnrollmentToken != null;
    final hasManual = !hasScan && _manualEnrollmentToken != null;
    final hasInput  = hasScan || hasManual;

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
              'Run MOONGATE_PAIR in your Klipper console — scan the QR or '
              'type the GATE code shown on the console.',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),

            // ── Printer name ───────────────────────────────────────────
            TextField(
              controller: _nameController,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: 'Printer name',
                hintText: 'e.g. Voron 2.4',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // ── Scan button / scanned status / manual entry ───────────
            if (!hasScan && !_scanning) ...[
              FilledButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR code'),
                onPressed: _loading ? null : _openScanner,
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Divider(color: cs.outlineVariant)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('OR',
                      style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w600)),
                ),
                Expanded(child: Divider(color: cs.outlineVariant)),
              ]),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'GATE code',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _gateCodeBox(
                    controller: _codeFirstController,
                    focusNode:  _codeFirstFocus,
                    onChanged:  _onFirstBoxChanged,
                    isLast:     false,
                  )),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('—',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  Expanded(child: _gateCodeBox(
                    controller: _codeSecondController,
                    focusNode:  _codeSecondFocus,
                    onChanged:  _onSecondBoxChanged,
                    isLast:     true,
                  )),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  _manualEnrollmentToken == null
                      ? 'Type the 8-digit code shown in your Klipper console.'
                      : 'Code looks valid ✓',
                  style: TextStyle(
                    fontSize: 12,
                    color: _manualEnrollmentToken != null
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],

            if (_scanning) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 280,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: MobileScanner(
                    controller: _scannerController!,
                    errorBuilder: (context, error) {
                      final isDenied = error.errorCode ==
                          MobileScannerErrorCode.permissionDenied;
                      return Container(
                        color: Colors.black87,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isDenied ? Icons.no_photography : Icons.videocam_off,
                              color: Colors.orange,
                              size: 40,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isDenied
                                  ? 'Camera permission needed'
                                  : 'Camera unavailable',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _restartScanner,
                              icon: const Icon(Icons.refresh, color: Colors.white70),
                              label: const Text('Retry',
                                  style: TextStyle(color: Colors.white70)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white30),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.close),
                label: const Text('Cancel scan'),
                onPressed: _closeScanner,
              ),
            ],

            if (hasScan) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: cs.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'QR scanned — code ${_scannedEnrollmentToken!}',
                        style: TextStyle(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _loading ? null : _resetScan,
                      child: const Text('Rescan'),
                    ),
                  ],
                ),
              ),
            ],

            if (hasInput) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _claim,
                child: _loading
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Pair printer'),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: cs.onErrorContainer),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
