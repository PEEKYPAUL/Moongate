import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../services/lan_discovery_service.dart';
import '../../services/printer_registry.dart';
import '../../services/printer_webview_cache.dart';
import '../../services/supabase_service.dart';
import '../../widgets/keyboard_affordance.dart';
import '../dashboard/feedback_sheet.dart';

/// v0.3.0 pairing flow (with v0.4.2 manual-entry fallback):
///
///   1. User opens MOONGATE_PAIR on the Pi → Pi pre-registers the
///      enrollment-token hash + its Ed25519 public key with Supabase.
///   2. Pi displays the GATE code via M118 + a QR containing
///      `moongate://pair?v=3&pk=<base64>&et=<raw>`.
///   3a. User scans the QR - app extracts `pk` and `et`.
///   3b. OR user types the GATE code shown on the Pi's console - app has
///       only `et`; the server uses its stored pubkey from the
///       enrollment row.
///   4. App asks for a friendly name and calls Supabase `/printer-claim`
///      with the current anonymous user's JWT.
///   5. On success, the printer row exists in Supabase owned by this
///      anonymous user. Add it to the local cache and navigate back.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, this.initialUri});

  /// A tapped moongate:// link (tap-to-pair on the Pi's pair page), staged on
  /// open exactly as if the QR scanner had read it. Null for normal opens.
  final String? initialUri;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _nameController      = TextEditingController();
  final _nameFocus           = FocusNode();

  // Optional "Advanced - custom network" address. When non-blank it becomes
  // the printer's lanUrl, overriding the QR/mDNS-supplied address. The escape
  // hatch for reverse-proxy / Docker setups where auto-discovery can't find
  // the printer (see TROUBLESHOOTING.md → reverse proxy).
  final _addressController   = TextEditingController();
  final _addressFocus        = FocusNode();

  // Two 4-digit boxes for the GATE code. Split lets us show a numpad
  // (TextInputType.number) instead of the full keyboard, and lets us
  // auto-advance focus from box 1 to box 2 after 4 digits.
  final _codeFirstController  = TextEditingController();
  final _codeSecondController = TextEditingController();
  final _codeFirstFocus       = FocusNode();
  final _codeSecondFocus      = FocusNode();

  // Drives the always-visible Scrollbar on the body so it's obvious the
  // add-printer form scrolls on small screens (user-reported).
  final _scrollController     = ScrollController();

  MobileScannerController? _scannerController;
  StreamSubscription<BarcodeCapture>? _barcodeSub;

  bool   _scanning = false;
  bool   _loading  = false;
  String? _error;

  // QR-scan path: both fields populated.
  String? _scannedPubKey;
  String? _scannedEnrollmentToken;
  // v0.5.1: LAN URL embedded in the QR (`ip`/`port`), if present. Lets a
  // fresh pair go Local immediately - no mDNS round-trip, no heartbeat wait.
  String? _scannedLanUrl;

  // Manual-entry path: normalised GATE-XXXX-XXXX token. Pubkey unknown
  // here - server uses its stored value from enrollment_tokens.
  String? _manualEnrollmentToken;

  // Cloudless LAN-only path: scanned a `moongate://lan` QR from a Pi installed
  // with --lan-only. No enrollment token, no Supabase claim - we just add the
  // printer by its LAN address. `_scannedLanUrl` above holds the address.
  bool    _scannedLanOnly = false;
  String? _scannedLanName;

  // Add-printer mode: false = Moongate cloud (GATE code / QR, tunnel + LAN),
  // true = Direct (LAN/VPN) - the cloudless lanOnly path. Scanning either QR
  // type auto-selects its mode; switching manually clears any staged scan.
  bool    _directMode = false;

  // The name field starts EMPTY and is required: the database filled up with
  // printers literally called "My Printer" because a pre-seeded default reads
  // as "already answered". Instead the empty field cycles example names as
  // its hint (below), and _claim blocks with pairingErrorNoName until the
  // user types something - so a nameless printer can no longer be created.
  Timer? _nameHintTimer;
  int    _nameHintIx = 0;

  @override
  void initState() {
    super.initState();
    _nameHintTimer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      // Only cycle while the hint is visible (field empty); a name in the
      // field hides the hint, so ticking would just be wasted rebuilds.
      if (mounted && _nameController.text.isEmpty) {
        setState(() => _nameHintIx++);
      }
    });
    // Tap-to-pair: stage the link the user tapped. Post-frame because the
    // parser reads AppLocalizations from context for its error strings.
    if (widget.initialUri != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyScannedCode(widget.initialUri!);
      });
    }
  }

  @override
  void dispose() {
    _nameHintTimer?.cancel();
    _barcodeSub?.cancel();
    _scannerController?.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    _addressController.dispose();
    _addressFocus.dispose();
    _codeFirstController.dispose();
    _codeSecondController.dispose();
    _codeFirstFocus.dispose();
    _codeSecondFocus.dispose();
    _scrollController.dispose();
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
  /// surfaces a Submit/Pair signal - done dismisses the keyboard on the
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
      onTap: () => showKeyboardFor(focusNode),
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

    // Fresh-grant warmup - camera HAL needs ~700ms to register the
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
    final l = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.pairingCameraPermissionTitle),
        content: Text(l.pairingCameraPermissionBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
          FilledButton(
            onPressed: () { Navigator.pop(ctx); openAppSettings(); },
            child: Text(l.pairingOpenSettings),
          ),
        ],
      ),
    );
  }

  // ── v=3 QR parsing ────────────────────────────────────────────────────────

  /// Parses `moongate://pair?v=3&pk=<base64>&et=<raw>` and either stages
  /// the values for confirmation or surfaces an error.
  void _applyScannedCode(String raw) {
    final l = AppLocalizations.of(context);
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'moongate') {
      setState(() => _error = l.pairingErrorNotMoongateQr);
      return;
    }
    // Cloudless LAN-only QR: `moongate://lan?v=1&ip=<ip>&port=<port>&name=<host>`.
    // No enrollment token - it just carries the LAN address. Handled here,
    // before the cloud-pairing v=3 check below.
    if (uri.host == 'lan') {
      final ip   = uri.queryParameters['ip'];
      final port = uri.queryParameters['port'];
      // Validate the scanned address through the same normaliser as manual
      // entry so a malformed QR can't create a garbage printer entry.
      final raw    = (port == null || port.isEmpty) ? (ip ?? '') : '$ip:$port';
      final lanUrl = PrinterConfig.parseLanUrl(raw);
      if (lanUrl == null) {
        setState(() => _error = l.pairingErrorNotMoongateQr);
        return;
      }
      final name = uri.queryParameters['name'];
      setState(() {
        _directMode             = true; // a LAN QR means Direct mode
        _scannedLanOnly         = true;
        _scannedLanUrl          = lanUrl;
        _scannedLanName         = (name != null && name.isNotEmpty) ? name : null;
        // The QR carries the Pi's hostname - pre-fill an untouched name field
        // with it so the required-name gate passes with something real (the
        // user can still overwrite it).
        if (_nameController.text.trim().isEmpty && _scannedLanName != null) {
          _nameController.text = _scannedLanName!;
        }
        _scannedPubKey          = null;
        _scannedEnrollmentToken = null;
        _error                  = null;
      });
      return;
    }
    final version = uri.queryParameters['v'];
    final pk      = uri.queryParameters['pk'];
    final et      = uri.queryParameters['et'];
    if (version != '3' || pk == null || et == null || pk.isEmpty || et.isEmpty) {
      setState(() => _error = l.pairingErrorOldQr);
      return;
    }
    // v0.5.1: optional LAN address embedded by v0.4.5+ Pis. Build the base
    // URL now so the new tile connects Local on its very first poll. Absent
    // on older Pis - we fall back to mDNS/tunnel exactly as before.
    final ip   = uri.queryParameters['ip'];
    final port = uri.queryParameters['port'];
    String? lanUrl;
    if (ip != null && ip.isNotEmpty) {
      lanUrl = (port == null || port.isEmpty || port == '80')
          ? 'http://$ip'
          : 'http://$ip:$port';
    }
    setState(() {
      _directMode            = false; // a pairing QR means cloud mode
      _scannedLanOnly        = false;
      _scannedLanName        = null;
      _scannedPubKey         = pk;
      _scannedEnrollmentToken = et;
      _scannedLanUrl         = lanUrl;
      _error                 = null;
    });
  }

  /// Segmented-control mode switch. Clears any staged scan (a cloud scan is
  /// meaningless in Direct mode and vice versa) but keeps the typed name and
  /// address, which carry over between modes.
  void _setMode(bool direct) {
    if (direct == _directMode) return;
    setState(() {
      _directMode            = direct;
      _scannedPubKey         = null;
      _scannedEnrollmentToken = null;
      _scannedLanOnly        = false;
      _scannedLanName        = null;
      _scannedLanUrl         = null;
      _error                 = null;
    });
  }

  // ── Claim ────────────────────────────────────────────────────────────────

  Future<void> _claim() async {
    final l = AppLocalizations.of(context);

    // A real name is required - no more silent "My Printer" fallback (the
    // cloud filled up with rows literally named that). Inline error + focus
    // beats a dialog: it sits right under the field the user must now use.
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = l.pairingErrorNoName);
      _nameFocus.requestFocus();
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      return;
    }

    // Direct (LAN/VPN) path: no Supabase claim. Mint a local id from the LAN
    // address (stable, so re-scanning the same Pi dedupes) and add it directly.
    // The status/control services see lanOnly and poll the plugin over the LAN
    // with no cloud token. Reached via the mode switch OR a moongate://lan QR.
    if (_directMode || _scannedLanOnly) {
      final manualLanUrl = PrinterConfig.parseLanUrl(_addressController.text);
      if (_addressController.text.trim().isNotEmpty && manualLanUrl == null) {
        setState(() => _error = l.pairingErrorBadAddress);
        return;
      }
      final effectiveLan = manualLanUrl ?? _scannedLanUrl;
      if (effectiveLan == null) {
        setState(() => _error = l.pairingErrorNoAddress);
        return;
      }
      final name = _nameController.text.trim();
      setState(() { _loading = true; _error = null; });
      try {
        final id = 'lan-${effectiveLan.replaceAll(RegExp(r'[^A-Za-z0-9]'), '-')}';
        await PrinterRegistry.instance.addClaimed(
          PrinterConfig(id: id, name: name, lanUrl: effectiveLan, lanOnly: true),
        );
        if (!mounted) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/dashboard');
        }
      } catch (e) {
        if (mounted) setState(() { _error = l.pairingErrorFailed(e.toString()); _loading = false; });
      }
      return;
    }

    // QR-scan path wins if present (it carries the pubkey for the
    // defense-in-depth server check). Manual path is the fallback.
    final scannedEt = _scannedEnrollmentToken;
    final manualEt  = _manualEnrollmentToken;
    final et = scannedEt ?? manualEt;
    if (et == null) {
      setState(() => _error = l.pairingErrorNoCode);
      return;
    }
    // Advanced override: an explicit address wins over the QR/mDNS one. A
    // typed-but-unparseable address is a user error worth flagging rather
    // than silently ignoring.
    final manualLanUrl = PrinterConfig.parseLanUrl(_addressController.text);
    if (_addressController.text.trim().isNotEmpty && manualLanUrl == null) {
      setState(() => _error = l.pairingErrorBadAddress);
      return;
    }
    final pk = scannedEt != null ? _scannedPubKey : null;

    final name = _nameController.text.trim();

    setState(() { _loading = true; _error = null; });

    try {
      final printerId = await SupabaseService.instance.claimPrinter(
        enrollmentToken: et,
        piPublicKey:     pk,
        name:            name,
      );
      // Seed the printer's LAN URL so it lands on the dashboard already
      // showing "Local" (~1 s) instead of "Starting up… waiting for first
      // heartbeat". Best source is the QR itself (v0.4.5+ Pis embed ip/port)
      // - deterministic, works even before the Pi advertises mDNS. For the
      // manual GATE-code path or older QRs we fall back to a brief mDNS
      // prewarm; if neither resolves, lanUrl stays null and the normal
      // background browse + tunnel path takes over (no regression).
      final lanUrl =
          manualLanUrl ?? _scannedLanUrl ?? await _prewarmLanUrl(printerId);
      // If this same machine was previously added as a Direct (LAN/VPN) tile,
      // absorb it: same LAN address = same Pi. The new cloud tile inherits
      // every persisted setting the old tile carried (webcam transforms,
      // custom camera, UI type - the full toJson round-trip) and, when the
      // name field was left untouched, its name too; the Direct tile is then
      // retired, so switching to cloud is one pairing instead of pair +
      // hunt + delete.
      final twin = _directTwinFor(lanUrl);
      var config = PrinterConfig(id: printerId, name: name, lanUrl: lanUrl);
      if (twin != null) {
        config = PrinterConfig.fromJson({
          ...twin.toJson(),
          'id':      printerId,
          'name':    _nameController.text.trim().isEmpty ? twin.name : name,
          'lanUrl':  lanUrl,
          'lanOnly': false,
        });
      }
      await PrinterRegistry.instance.addClaimed(config);
      if (twin != null) {
        await PrinterRegistry.instance.remove(twin.id);
        PrinterWebViewCache.instance.invalidate(twin.id);
      }
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
      if (mounted) setState(() { _error = l.pairingErrorFailed(e.toString()); _loading = false; });
    }
  }

  // ── First-launch / reinstall restore ─────────────────────────────────────

  /// Pick a backup file and merge its printers in, then head to the
  /// dashboard. Restored printers come back offline - a reinstall gets a new
  /// cloud identity, so the user re-pairs each Pi to bring it online. Shares
  /// PrinterRegistry.importFromBackupFile with the drawer "Restore config".
  Future<void> _importConfig() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    ImportOutcome? outcome;
    try {
      outcome = await PrinterRegistry.instance.importFromBackupFile();
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.pairingImportInvalidFile),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (outcome == null || !mounted) return; // user cancelled
    if (outcome.added == 0 && !outcome.reconnected) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.pairingImportNoNewPrinters)),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(outcome.reconnected
            ? l.pairingImportRestoredReconnected(outcome.added, outcome.reconnectedCount)
            : l.pairingImportRestoredRepair(outcome.added)),
      ),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/dashboard');
    }
  }

  /// Open the bug-report sheet pre-loaded with the current pairing attempt's
  /// state (method, scanned IP, manual address, last error, live mDNS) so a
  /// user who can't pair can report it without ever reaching the dashboard.
  void _reportPairingProblem() {
    final method = _scannedLanOnly
        ? 'lan_qr'
        : _directMode
            ? 'lan_manual'
            : _scannedEnrollmentToken != null
                ? 'qr'
                : (_manualEnrollmentToken != null ? 'gate_code' : 'none_yet');
    final manual = _addressController.text.trim();
    showFeedbackSheet(context, const [], pairingContext: {
      'method': method,
      'direct_mode': _directMode,
      'scanned_lan_url': _scannedLanUrl,
      'has_scanned_ip': _scannedLanUrl != null,
      'manual_address': manual.isEmpty ? null : manual,
      'last_error': _error,
      'mdns_discovered': LanDiscoveryService.instance.discovered,
    });
  }

  // ── First-add LAN pre-warm ───────────────────────────────────────────────

  /// Give mDNS a brief head start right after a successful claim so the
  /// printer shows "Local" on the dashboard almost immediately, rather than
  /// "Starting up…" for a poll cycle or two while discovery catches up.
  ///
  /// Pairing happens on the same network as the Pi (you just scanned its QR
  /// or typed its console code), so its `_moongate._tcp` advert is almost
  /// always resolvable within a second - often already cached from the
  /// startup / foreground browse, in which case the first lookup returns
  /// straight away. We kick a fresh browse and poll the resolved map for up
  /// to ~1.2 s, then seed the printer's `lanUrl` so the very first dashboard
  /// poll goes straight to LAN. On timeout (multicast blocked, Pi pre-v0.4.4,
  /// or off-network) we return null and the normal background browse + tunnel
  /// path takes over - no regression, just the old "Starting up…" window.
  Future<String?> _prewarmLanUrl(String printerId) async {
    LanDiscoveryService.instance.refresh().ignore(); // ~5 s browse, async
    for (var i = 0; i < 8; i++) { // 8 × 150 ms ≈ 1.2 s cap
      final url = LanDiscoveryService.instance.lookup(printerId);
      if (url != null) return url;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return null;
  }

  /// The current example name shown as the empty name field's hint. The list
  /// comes from one localised `|`-separated string so translators can swap in
  /// their own fun names; _nameHintTimer advances the index every ~2s while
  /// the field is empty.
  String _cyclingNameHint(AppLocalizations l) {
    final examples = l.pairingNameHintExamples.split('|');
    return l.pairingNameHintCycled(examples[_nameHintIx % examples.length]);
  }

  /// The Direct-added (`lan-` id) tile whose address points at the same
  /// machine as [lanUrl], if any. Compares host + effective port via Uri so
  /// `http://x` and `http://x:80` match. Converted cloud tiles (lanOnly but
  /// cloudPaired) are left alone - they carry a valid pairing of their own.
  PrinterConfig? _directTwinFor(String? lanUrl) {
    if (lanUrl == null) return null;
    final target = Uri.tryParse(lanUrl);
    if (target == null || target.host.isEmpty) return null;
    for (final p in PrinterRegistry.instance.printers) {
      if (!p.lanOnly || p.cloudPaired) continue;
      final u = Uri.tryParse(p.lanUrl ?? '');
      if (u == null || u.host.isEmpty) continue;
      if (u.host == target.host && u.port == target.port) return p;
    }
    return null;
  }

  void _resetScan() {
    setState(() {
      _scannedPubKey         = null;
      _scannedEnrollmentToken = null;
      _scannedLanOnly        = false;
      _scannedLanName        = null;
      _scannedLanUrl         = null;
      _error                 = null;
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l         = AppLocalizations.of(context);
    final cs        = Theme.of(context).colorScheme;
    final hasScan    = _scannedPubKey != null && _scannedEnrollmentToken != null;
    final hasLanScan = _scannedLanOnly;
    final hasManual  = !hasScan && !hasLanScan && _manualEnrollmentToken != null;
    final hasAddress = _addressController.text.trim().isNotEmpty;
    final hasInput   = _directMode
        ? (hasLanScan || hasAddress)
        : (hasScan || hasManual);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.pairingTitle),
        leading: PrinterRegistry.instance.printers.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/dashboard'),
              )
            : null,
      ),
      body: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          // + the system bar inset: a SingleChildScrollView never applies the
          // safe area itself, so without this the Pair/Add button at the form's
          // bottom could scroll to a stop under the Android button/gesture bar.
          // Android only - iOS has no opaque bar to clear.
          padding: EdgeInsets.fromLTRB(
              24, 24, 24,
              24 + (Platform.isAndroid
                  ? MediaQuery.of(context).padding.bottom : 0)),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Mode: Moongate cloud vs Direct (LAN/VPN) ───────────────
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(l.pairingModeCloud),
                  icon:  const Icon(Icons.cloud_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(l.pairingModeDirect),
                  icon:  const Icon(Icons.lan_outlined),
                ),
              ],
              selected: {_directMode},
              showSelectedIcon: false,
              onSelectionChanged:
                  _loading ? null : (s) => _setMode(s.first),
            ),
            const SizedBox(height: 16),
            Text(
              _directMode ? l.pairingDirectIntro : l.pairingIntro,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),

            // ── Printer name ───────────────────────────────────────────
            // Starts empty on purpose (see _nameHintTimer) - the hint cycles
            // through example names so it's obvious this wants a real one.
            TextField(
              controller: _nameController,
              focusNode: _nameFocus,
              enabled: !_loading,
              onTap: () => showKeyboardFor(_nameFocus),
              // Rebuild on edits so the required-name error clears as soon
              // as the user starts typing.
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: l.pairingNameLabel,
                // Keep the label floated even while empty+unfocused: with the
                // default behaviour it sits in the field and HIDES the hint,
                // and the whole point is that the cycling example names are
                // visible before the user ever taps the field.
                floatingLabelBehavior: FloatingLabelBehavior.always,
                hintText: _cyclingNameHint(l),
                border: const OutlineInputBorder(),
                suffixIcon: _loading ? null : ShowKeyboardButton(_nameFocus),
              ),
            ),
            const SizedBox(height: 16),

            // ── Scan button / scanned status / manual entry ───────────
            if (!hasScan && !hasLanScan && !_scanning) ...[
              FilledButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(l.pairingScanButton),
                onPressed: _loading ? null : _openScanner,
              ),
              const SizedBox(height: 6),
              Text(
                _directMode ? l.pairingDirectScanHint : l.pairingScanRecommended,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: cs.primary,
                ),
              ),
            ],

            // ── Cloud mode only: GATE-code manual entry ────────────────
            if (!_directMode && !hasScan && !_scanning) ...[
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Divider(color: cs.outlineVariant)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(l.pairingOr,
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
                  l.pairingGateCodeLabel,
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
                    child: Text('-',
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
                      ? l.pairingGateCodeHint
                      : l.pairingGateCodeValid,
                  style: TextStyle(
                    fontSize: 12,
                    color: _manualEnrollmentToken != null
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: Colors.amber.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.pairingGateCodeWarning,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: cs.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
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
                                  ? l.pairingCameraPermissionNeeded
                                  : l.pairingCameraUnavailable,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _restartScanner,
                              icon: const Icon(Icons.refresh, color: Colors.white70),
                              label: Text(l.commonRetry,
                                  style: const TextStyle(color: Colors.white70)),
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
                label: Text(l.pairingCancelScan),
                onPressed: _closeScanner,
              ),
            ],

            if (hasScan || hasLanScan) ...[
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
                        hasLanScan
                            ? l.pairingLanScanned(_scannedLanUrl ?? '')
                            : l.pairingQrScanned(_scannedEnrollmentToken!),
                        style: TextStyle(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _loading ? null : _resetScan,
                      child: Text(l.pairingRescan),
                    ),
                  ],
                ),
              ),
            ],

            // ── Direct mode: first-class address entry ─────────────────
            if (_directMode && !_scanning) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _addressController,
                focusNode: _addressFocus,
                enabled: !_loading,
                keyboardType: TextInputType.url,
                autocorrect: false,
                // setState so hasInput (the Add button) tracks the text.
                onChanged: (_) => setState(() {}),
                onTap: () => showKeyboardFor(_addressFocus),
                decoration: InputDecoration(
                  labelText: l.pairingAddressLabel,
                  hintText: l.pairingAddressHint,
                  helperText: l.pairingDirectAddressHelper,
                  border: const OutlineInputBorder(),
                  suffixIcon:
                      _loading ? null : ShowKeyboardButton(_addressFocus),
                ),
              ),
            ],

            // ── Advanced: manual address (reverse proxy / Docker) ──────
            if (!_directMode && !_scanning) ...[
              const SizedBox(height: 8),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  title: Text(
                    l.pairingAdvancedTitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  children: [
                    Text(
                      l.pairingAdvancedBody,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addressController,
                      focusNode: _addressFocus,
                      enabled: !_loading,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      onTap: () => showKeyboardFor(_addressFocus),
                      decoration: InputDecoration(
                        labelText: l.pairingAddressLabel,
                        hintText: l.pairingAddressHint,
                        border: const OutlineInputBorder(),
                        suffixIcon:
                            _loading ? null : ShowKeyboardButton(_addressFocus),
                      ),
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
                    : Text(_directMode ? l.pairingAddButton : l.pairingPairButton),
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

            // ── Direct mode: an honest list of what the cloudless path
            //    can't do, plus its two networking prerequisites ─────────
            if (_directMode && !_scanning) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.info_outline, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.pairingDirectCaveatsTitle,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      l.pairingDirectCaveats,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: cs.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Restore from a backup file (reinstall / first launch) ──
            if (!_scanning) ...[
              const SizedBox(height: 24),
              Divider(color: cs.onSurface.withValues(alpha: 0.12)),
              const SizedBox(height: 8),
              Text(
                l.pairingRestoreHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _loading ? null : _importConfig,
                icon: const Icon(Icons.file_download_outlined),
                label: Text(l.pairingImportButton),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: _loading ? null : _reportPairingProblem,
                icon: const Icon(Icons.bug_report_outlined, size: 18),
                label: Text(l.pairingReportButton),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}
