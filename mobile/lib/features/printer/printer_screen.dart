import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../models/notif_fields.dart';
import '../../models/printer_config.dart';
import '../../services/lan_discovery_service.dart';
import '../../services/printer_access_cache.dart';
import '../../services/printer_registry.dart';
import '../../services/printer_status_registry.dart';
import '../../services/printer_webview_cache.dart';
import '../../services/supabase_service.dart';
import '../../widgets/keyboard_affordance.dart';
import 'printer_camera_screen.dart';

/// Full-screen WebView showing the printer's Mainsail/Fluidd interface.
///
/// The [WebViewController] is NOT owned by this screen - it lives in
/// [PrinterWebViewCache], keyed by printer id, so popping back to the dashboard
/// leaves the loaded SPA and its Moonraker WebSocket alive and re-opening is
/// instant (no Mainsail "Initializing…", which is slow over the tunnel).
///
/// Cold flow (first open / after invalidation):
///   1. Fetch a fresh `{tunnel_url, access_token}` from Supabase via
///      [PrinterAccessCache].
///   2. v0.4: set an `mg_token` cookie on the WebView scoped to the tunnel
///      host. The auth proxy on the Pi reads it on every request (static
///      assets + WebSocket upgrade), verifies the EdDSA signature, and only
///      then proxies to nginx / Moonraker. On v0.3 Pis the cookie is set but
///      ignored. The cache refreshes it at ~4 min (TTL 5 min) so even a
///      backgrounded warm session never falls off the cliff.
///   3. Load the LAN URL when one is reachable (Mainsail loads dramatically
///      faster on direct LAN); fall back to the tunnel otherwise. The loaded
///      controller is then stored warm for next time.
///   4. On 503 from /printer-access (Pi hasn't heartbeated yet, fresh pairing)
///      retry after a short delay. On other errors surface an in-app overlay
///      with a Retry button.
///
/// Warm flow (re-open): re-attach to the cached controller instantly, then
/// revalidate a LAN session in the background (it's stale if you've left home).
/// The symmetric case is checked BEFORE re-attach: a tunnel session while the
/// status poll runs on LAN is dropped and rebuilt on the LAN.
class PrinterScreen extends StatefulWidget {
  final PrinterConfig printer;
  const PrinterScreen({super.key, required this.printer});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen>
    with WidgetsBindingObserver {
  WebViewController? _webController;

  bool    _loading   = true;
  bool    _usingLan  = false;
  bool    _localOnly = false;
  String? _errorMsg;
  String? _tunnelUrl;
  Timer?  _retryTimer;

  // Discoverability hint pointing at the camera icon. Shown ONLY when this
  // printer is loaded over the tunnel AND its webcam is an external (absolute
  // LAN-URL) camera - the one case where the embedded Mainsail webcam panel
  // can't load remotely. One-time: dismissing it (or opening the camera) sets
  // a persisted flag so it never shows again. A normal relative-URL webcam is
  // never flagged external, so a standard setup never sees this.
  bool _showCameraHint = false;

  // Local copy of the printer name so the app bar reflects renames
  // immediately, without waiting for a dashboard rebuild.
  late String _displayName = widget.printer.name;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Defer to after the first frame: _start() reads AppLocalizations.of(context)
    // synchronously, which can throw a null-check in initState before the
    // localization ancestor is available (seen as an endless spinner + default
    // "Tunnel" subtitle because _start aborted before loading anything).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    // The WebViewController is intentionally NOT disposed here - it lives on in
    // [PrinterWebViewCache] so the next open is instant.
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On resume re-run _start: a warm session re-attaches instantly and then
    // revalidates (the network may have changed while we were backgrounded); a
    // session the cache dropped (tunnel rotation) cold-reloads.
    if (state == AppLifecycleState.resumed && _webController != null) {
      _start();
    }
  }

  Future<void> _start() async {
    final l = AppLocalizations.of(context);

    // An explicit (re)start supersedes any pending auto-retry - without this a
    // manual Retry racing a scheduled one could fire two loads back to back.
    _retryTimer?.cancel();

    // Local-only mode (the dashboard's cloud toggle): the tunnel is never used
    // as a transport here - read up front so a warm TUNNEL session isn't
    // silently re-attached while the toggle is on.
    _localOnly =
        (await SharedPreferences.getInstance()).getBool(kLocalOnlyKey) ?? false;
    if (!mounted) return;

    // Warm? Re-attach to the live controller - instant, no reload, no
    // "Initializing…". Re-point the navigation delegate at this screen, then
    // revalidate in the background (a LAN session is dead if you've left home).
    var warm = PrinterWebViewCache.instance.lookup(widget.printer.id);
    if (warm != null && _localOnly && !warm.usingLan) {
      // A live tunnel session can't be reused in Local-only - drop it and
      // cold-load below (LAN when reachable, else the local-only notice).
      PrinterWebViewCache.instance.invalidate(widget.printer.id);
      warm = null;
    }
    if (warm != null &&
        PrinterWebViewCache.tunnelSessionStaleOnLan(
          sessionUsingLan: warm.usingLan,
          pollConnection:  PrinterStatusRegistry.instance
              .snapshot(widget.printer.id)
              ?.connection,
        )) {
      // The session was transport-decided once (pre-warm, possibly off-WiFi)
      // but the tile's poll is running on LAN right now - rebuild on the
      // better transport instead of trusting the tunnel forever. The cold
      // load below re-probes LAN itself, so a stale poll verdict still falls
      // through to the tunnel safely.
      PrinterWebViewCache.instance.invalidate(widget.printer.id);
      warm = null;
    }
    if (warm != null) {
      _webController = warm.controller;
      _webController!.setNavigationDelegate(_navDelegate());
      _usingLan  = warm.usingLan;
      _tunnelUrl = warm.tunnelUrl;
      setState(() { _loading = false; _errorMsg = null; });
      _revalidateWarm(warm);
      _maybeShowCameraHint();
      return;
    }

    // Cloudless LAN-only printer: load Mainsail straight from the LAN. No
    // Supabase access, no EdDSA cookie - the Pi serves nginx/Moonraker on the
    // LAN directly. We don't pre-probe /server/info here (that check is
    // unreliable from a routed/off-subnet client, and a failed probe would
    // wrongly show "not on this network"); we just load the page and let the
    // WebView's onWebResourceError surface a genuine failure.
    // Registry-live config, not widget.printer: the edit dialog can flip
    // Direct mode while this screen is open, and the reload must see it.
    final live = PrinterRegistry.instance.printers.firstWhere(
        (p) => p.id == widget.printer.id, orElse: () => widget.printer);
    if (live.lanOnly) {
      final lanUrl = live.lanUrl ?? widget.printer.lanUrl;
      if (lanUrl == null) {
        if (mounted) {
          setState(() { _loading = false; _errorMsg = l.printerLocalOnlyNoLan; });
        }
        return;
      }
      if (!mounted) return;
      // setState so the app-bar subtitle flips to "Local network" immediately,
      // not just after the first onPageStarted callback.
      setState(() {
        _usingLan  = true;
        _tunnelUrl = null;
        _loading   = true;
        _errorMsg  = null;
      });
      _initControllerIfNeeded();
      await _webController!.loadRequest(Uri.parse('$lanUrl/'));
      PrinterWebViewCache.instance.store(
        widget.printer.id,
        LiveWebSession(
          controller: _webController!,
          baseUrl:    lanUrl,
          usingLan:   true,
          tunnelUrl:  null,
        ),
      );
      _maybeShowCameraHint();
      return;
    }

    setState(() { _loading = true; _errorMsg = null; });
    try {
      final access = await PrinterAccessCache.instance.get(widget.printer.id);
      if (!mounted) return;
      _tunnelUrl = access.tunnelUrl;

      // v0.4: prime the EdDSA cookie before navigation so the auth proxy
      // accepts every WebView request (HTML, JS, XHR, WS upgrade). The cache
      // keeps it refreshed once the session is stored. No-op on v0.3 Pis.
      await PrinterWebViewCache.setMgTokenCookie(access);

      // Prefer the LAN URL when reachable - Mainsail loads dramatically faster
      // on direct LAN than through Cloudflare. Try the mDNS-discovered address
      // first (survives DHCP changes), then the persisted one. Pre-flight a
      // quick 2s probe: on cellular the phone has no route to RFC1918 addresses
      // but the WebView would block silently (no `onWebResourceError`, just a
      // forever spinner). The probe gives a fast decision and a clean
      // fall-through to the tunnel.
      final lanUrl = LanDiscoveryService.instance.lookup(widget.printer.id)
          ?? widget.printer.lanUrl;
      String? useUrl;
      if (lanUrl != null && await _isLanReachable(lanUrl)) {
        useUrl    = lanUrl;
        _usingLan = true;
      } else if (!_localOnly && access.tunnelUrl != null) {
        useUrl    = access.tunnelUrl;
        _usingLan = false;
      }

      // No usable URL. In Local-only mode that means the printer isn't on this
      // network - say so plainly (no auto-retry loop; Retry or turning the
      // toggle off re-probes). Otherwise the printer was just paired / is
      // rebooting and remote isn't up: show the same "starting up" retry the
      // 503 path uses instead of loading a null URL.
      if (useUrl == null) {
        if (!mounted) return;
        if (_localOnly) {
          setState(() {
            _loading  = false;
            _errorMsg = l.printerLocalOnlyNoLan;
          });
          return;
        }
        setState(() {
          _loading  = false;
          _errorMsg = l.printerStartingUpRetry(5);
        });
        _retryTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) _start();
        });
        return;
      }

      _initControllerIfNeeded();
      await _webController!.loadRequest(Uri.parse('$useUrl/'));

      // Keep this controller warm so the next open is instant. The cache starts
      // the background cookie refresh from here.
      PrinterWebViewCache.instance.store(
        widget.printer.id,
        LiveWebSession(
          controller: _webController!,
          baseUrl:    useUrl,
          usingLan:   _usingLan,
          tunnelUrl:  access.tunnelUrl,
        ),
      );
      _maybeShowCameraHint();
    } on PrinterUnavailableException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading  = false;
        _errorMsg = l.printerStartingUpRetry(e.retryAfter);
      });
      _retryTimer = Timer(Duration(seconds: e.retryAfter), () {
        if (mounted) _start();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _errorMsg = l.printerCouldNotReach('$e'); });
    }
  }

  /// Background check after re-attaching to a warm session. A LAN session is
  /// only valid while you're on that network - if the address no longer answers
  /// (you've left home) drop it and reload so the tunnel takes over, rather than
  /// leaving the user on a dead page. Tunnel sessions are trusted here: the
  /// cache's refresh timer drops them on rotation, a hard failure still
  /// surfaces the error overlay, and the tunnel-while-LAN case is already
  /// handled before re-attach in [_start].
  Future<void> _revalidateWarm(LiveWebSession warm) async {
    if (!warm.usingLan) return;
    final stillReachable = await _isLanReachable(warm.baseUrl);
    if (!mounted || stillReachable) return;
    PrinterWebViewCache.instance.invalidate(widget.printer.id);
    PrinterAccessCache.instance.invalidate(widget.printer.id);
    _start();
  }

  static const _cameraHintSeenKey = 'camera_hint_seen';

  /// Show the camera-discoverability hint iff we're on the tunnel, the webcam
  /// is an external (absolute-LAN-URL) camera the Mainsail panel can't load
  /// remotely, and the user hasn't already discovered/dismissed it. Reads the
  /// latest webcam classification from the dashboard tile's last poll.
  Future<void> _maybeShowCameraHint() async {
    if (_usingLan || _showCameraHint) return;
    final snap = PrinterStatusRegistry.instance.snapshot(widget.printer.id);
    if (snap?.webcamIsExternal != true) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_cameraHintSeenKey) ?? false) return;
    if (mounted) setState(() => _showCameraHint = true);
  }

  Future<void> _markCameraHintSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cameraHintSeenKey, true);
  }

  /// Open the full-screen native camera view. Also marks the hint as seen - if
  /// the user found the camera (via the app-bar icon or the hint), there's no
  /// need to nudge them again.
  void _openCamera() {
    _markCameraHintSeen();
    if (_showCameraHint) setState(() => _showCameraHint = false);
    showPrinterCameraOverlay(context, widget.printer);
  }

  void _dismissCameraHint() {
    _markCameraHintSeen();
    setState(() => _showCameraHint = false);
  }

  Future<void> _showEditPrinterDialog() async {
    final l = AppLocalizations.of(context);
    // Registry-live config: a previous edit in this same screen session may
    // already have changed the address or the Direct-mode flag.
    final live = PrinterRegistry.instance.printers.firstWhere(
        (p) => p.id == widget.printer.id, orElse: () => widget.printer);
    final result = await showDialog<({String name, String? lanUrl, bool lanOnly})>(
      context: context,
      builder: (_) => _EditPrinterDialog(
        initialName:    _displayName,
        initialLanUrl:  live.lanUrl,
        initialLanOnly: live.lanOnly,
        // A Direct-added printer has no cloud row - it can't become a cloud
        // printer, so it gets no toggle (re-pair through the cloud instead).
        canToggleLanOnly: live.cloudPaired,
      ),
    );
    if (result == null) return;
    final newName = result.name;
    if (newName.isNotEmpty && newName != _displayName) {
      await PrinterRegistry.instance.renamePrinter(widget.printer.id, newName);
      if (mounted) setState(() => _displayName = newName);
    }
    final addressChanged = result.lanUrl != live.lanUrl;
    if (addressChanged) {
      await PrinterRegistry.instance
          .updateLanUrl(widget.printer.id, result.lanUrl);
    }
    final modeChanged = result.lanOnly != live.lanOnly;
    if (modeChanged) {
      await PrinterRegistry.instance
          .setLanOnly(widget.printer.id, result.lanOnly);
    }
    if (addressChanged || modeChanged) {
      // The warm session belongs to the old address/transport - drop it and
      // reload so the change is visible right away, not on the next open.
      PrinterWebViewCache.instance.invalidate(widget.printer.id);
      if (modeChanged) PrinterAccessCache.instance.invalidate(widget.printer.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(modeChanged
                ? (result.lanOnly
                    ? l.printerDirectModeOn
                    : l.printerDirectModeOff)
                : (result.lanUrl == null
                    ? l.printerAddressCleared
                    : l.printerAddressUpdated)),
          ),
        );
      }
      if (modeChanged) _start();
    }
  }

  /// Force a fallback to the Cloudflare tunnel. Called from the Retry
  /// button on the error overlay (so a LAN load that fails surfaces a
  /// quick path to the tunnel).
  Future<void> _retryViaTunnel() async {
    if (_tunnelUrl == null) {
      _start();
      return;
    }
    setState(() { _loading = true; _errorMsg = null; _usingLan = false; });
    _initControllerIfNeeded();
    await _webController!.loadRequest(Uri.parse('$_tunnelUrl/'));
    // Re-store as a tunnel session so the warm cache reflects reality.
    PrinterWebViewCache.instance.store(
      widget.printer.id,
      LiveWebSession(
        controller: _webController!,
        baseUrl:    _tunnelUrl!,
        usingLan:   false,
        tunnelUrl:  _tunnelUrl,
      ),
    );
  }

  NavigationDelegate _navDelegate() => NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() { _loading = true; _errorMsg = null; });
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        // A 5xx on the main document is a SUCCESSFUL load to the WebView, so
        // without this it renders the upstream error page raw - typically
        // Cloudflare's "Bad gateway" when the tunnel is up but the web stack
        // behind it is still booting (a cold Pi answers 502/503 for its first
        // moments; issue #180). Show our own overlay and retry until the page
        // comes up. Main-document gate: only our loadRequest/reload requests
        // the bare '/' path - every Mainsail asset/XHR is deeper - and iOS
        // (which only reports main-frame responses here) may omit the request.
        onHttpError: (err) {
          if ((err.response?.statusCode ?? 0) < 500) return;
          final path = err.request?.uri.path;
          if (path != null && path != '/' && path != '') return;
          if (!mounted) return;
          final l = AppLocalizations.of(context);
          _retryTimer?.cancel();
          _retryTimer = Timer(const Duration(seconds: 5), () {
            if (mounted) _webController?.reload();
          });
          setState(() {
            _loading  = false;
            _errorMsg = l.printerWebUiRetry(5);
          });
        },
        onWebResourceError: (err) {
          if (err.isForMainFrame != true) return;
          if (!mounted) return;
          final l = AppLocalizations.of(context);
          setState(() {
            _loading  = false;
            _errorMsg = l.printerTunnelUnreachable(err.description);
          });
        },
      );

  void _initControllerIfNeeded() {
    if (_webController != null) return;
    _webController = createWebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(_navDelegate());
  }

  /// Fast LAN probe. Returns true iff `${url}/server/info` answers within 2
  /// seconds. We hit Moonraker's own info endpoint rather than `/` because
  /// nginx serving Mainsail's index always 200s - Moonraker only answers when
  /// actually reachable, so a 200 here is also a liveness signal for the
  /// printer side. 401/403 still counts as reachable (we got an answer); only
  /// network failures and timeouts fall through to the tunnel.
  Future<bool> _isLanReachable(String url) async {
    try {
      final uri = Uri.parse('$url/server/info');
      final resp = await http
          .get(uri)
          .timeout(const Duration(seconds: 2));
      return resp.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Edit icon directly before the name (name + advanced address).
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              tooltip: l.printerEdit,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: _showEditPrinterDialog,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _usingLan ? l.printerLocalNetwork : l.printerTunnelVia,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _usingLan ? Colors.green : Colors.orange,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          // Native Moongate camera view. Unlike the Mainsail webcam panel in
          // this WebView (which hits the camera's absolute LAN URL and so fails
          // for an external phone-cam when remote), this renders through the
          // resolved snapshot URL - /mg-extcam-proxied over the tunnel.
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip: l.printerCameraTooltip,
            onPressed: _openCamera,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Drop the warm session + access token so we reload from scratch
              // (also re-fetches a fresh tunnel URL - handles cloudflared
              // rotation).
              PrinterWebViewCache.instance.invalidate(widget.printer.id);
              PrinterAccessCache.instance.invalidate(widget.printer.id);
              _start();
            },
          ),
        ],
      ),
      // SafeArea keeps the embedded web UI clear of the Android button/gesture
      // bar (and the side bar in landscape) - Mainsail/Fluidd put interactive
      // rows right at their page bottom, which the system bar was overlapping.
      // Browsers keep web content above the nav bar too, so this matches what
      // the same page looks like in Chrome. Top stays with the AppBar. Android
      // only: iOS has no opaque bar, so the page keeps its pre-v0.9.54
      // full-bleed under the translucent home indicator.
      body: SafeArea(
        top:    false,
        bottom: Platform.isAndroid,
        left:   Platform.isAndroid,
        right:  Platform.isAndroid,
        child: Column(
          children: [
            // Camera-discoverability hint - a full-width strip directly under the
            // app bar (Moongate's own chrome), so it never overlaps the embedded
            // Mainsail page or the system nav bar. Gated to tunnel + external
            // camera (see _maybeShowCameraHint). Dismissible, one-time.
            if (_showCameraHint)
              Material(
                color: cs.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                  child: Row(
                    children: [
                      Icon(Icons.videocam_outlined,
                          size: 20, color: cs.onSecondaryContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l.cameraHintBody,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSecondaryContainer),
                        ),
                      ),
                      TextButton(
                        onPressed: _openCamera,
                        child: Text(l.cameraHintOpen),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: cs.onSecondaryContainer,
                        onPressed: _dismissCameraHint,
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  if (_webController != null)
                    WebViewWidget(
                      key: ValueKey(_webController),
                      controller: _webController!,
                    ),

                  if (_loading && _errorMsg == null)
                    const Center(child: CircularProgressIndicator()),

                  if (_errorMsg != null && !_loading)
                    Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: cs.surface,
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_off_outlined,
                              size: 64, color: cs.error),
                          const SizedBox(height: 20),
                          Text(
                            l.printerUnreachable,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(color: cs.error),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _errorMsg!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.7)),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          FilledButton.icon(
                            onPressed: () {
                              PrinterWebViewCache.instance
                                  .invalidate(widget.printer.id);
                              PrinterAccessCache.instance
                                  .invalidate(widget.printer.id);
                              _start();
                            },
                            icon: const Icon(Icons.refresh),
                            label: Text(l.commonRetry),
                          ),
                          // No tunnel escape hatch in Local-only mode - the
                          // whole point of the toggle is that remote stays off.
                          if (_usingLan && _tunnelUrl != null && !_localOnly) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _retryViaTunnel,
                              icon: const Icon(Icons.cloud_outlined),
                              label: Text(l.printerUseTunnel),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Edit-printer dialog ─────────────────────────────────────────────────────
//
// Name + an optional advanced "Printer address" override, for reverse-proxy /
// Docker setups where mDNS and the Pi-advertised address can't be reached.
// Wrapped in a StatefulWidget so the TextEditingControllers are owned by the
// dialog's State and disposed cleanly when the dialog is torn down. Disposing
// a controller from the calling code AFTER `await showDialog` resolves races
// the framework's own dispose pass and trips the `_dependents.isEmpty`
// assertion.

class _EditPrinterDialog extends StatefulWidget {
  final String  initialName;
  final String? initialLanUrl;
  final bool    initialLanOnly;
  // Cloud-paired printers can flip Direct (LAN/VPN) mode both ways; a
  // Direct-added `lan-` printer has no cloud row so it shows no toggle.
  final bool    canToggleLanOnly;
  const _EditPrinterDialog({
    required this.initialName,
    this.initialLanUrl,
    this.initialLanOnly   = false,
    this.canToggleLanOnly = false,
  });

  @override
  State<_EditPrinterDialog> createState() => _EditPrinterDialogState();
}

class _EditPrinterDialogState extends State<_EditPrinterDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialName);
  final FocusNode _nameFocus = FocusNode();
  // Show the stored lanUrl without the scheme - the friendlier host:port
  // form people actually type.
  late final TextEditingController _addressController = TextEditingController(
    text: (widget.initialLanUrl ?? '').replaceFirst(RegExp(r'^https?://'), ''),
  );
  final FocusNode _addressFocus = FocusNode();
  String? _addressError;
  late bool _lanOnly = widget.initialLanOnly;

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    _addressController.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  void _save() {
    final l       = AppLocalizations.of(context);
    final name    = _nameController.text.trim();
    final addrRaw = _addressController.text.trim();
    final lanUrl  = PrinterConfig.parseLanUrl(addrRaw);
    if (addrRaw.isNotEmpty && lanUrl == null) {
      setState(() => _addressError = l.printerAddressInvalid);
      return;
    }
    // Direct mode has no tunnel to fall back to - without an address the
    // printer would be permanently unreachable, so block that save.
    if (_lanOnly && lanUrl == null) {
      setState(() => _addressError = l.printerDirectModeNeedsAddress);
      return;
    }
    Navigator.pop(context, (name: name, lanUrl: lanUrl, lanOnly: _lanOnly));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.printerEdit),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            focusNode: _nameFocus,
            autofocus: true,
            maxLength: 48,
            textCapitalization: TextCapitalization.words,
            onTap: () => showKeyboardFor(_nameFocus),
            decoration: InputDecoration(
              labelText: l.printerNameLabel,
              border: const OutlineInputBorder(),
              suffixIcon: ShowKeyboardButton(_nameFocus),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _addressController,
            focusNode: _addressFocus,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onTap: () => showKeyboardFor(_addressFocus),
            decoration: InputDecoration(
              labelText: l.printerAddressLabel,
              hintText: l.printerAddressHint,
              helperText: l.printerAddressHelper,
              helperMaxLines: 2,
              errorText: _addressError,
              border: const OutlineInputBorder(),
              suffixIcon: ShowKeyboardButton(_addressFocus),
            ),
            onChanged: (_) {
              if (_addressError != null) setState(() => _addressError = null);
            },
          ),
          if (widget.canToggleLanOnly) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _lanOnly,
              onChanged: (v) => setState(() => _lanOnly = v),
              title: Text(l.printerDirectModeToggle),
              subtitle: Text(
                l.printerDirectModeSubtitle,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}
