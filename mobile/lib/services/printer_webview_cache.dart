import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../models/printer_config.dart';
import 'lan_discovery_service.dart';
import 'printer_access_cache.dart';
import 'printer_registry.dart';
import 'supabase_service.dart';

/// Build a [WebViewController] with media autoplay enabled - the one factory
/// behind both the printer screen and the prewarm below, so every Mainsail/
/// Fluidd WebView behaves the same. Mainsail renders a go2rtc / WebRTC webcam
/// as a muted autoplaying <video> element; Android's WebView blocks ANY
/// scripted playback without a user gesture by default and iOS additionally
/// forces fullscreen-only playback, so those webcam cards sat black in the
/// app while working fine in a desktop browser.
WebViewController createWebViewController() {
  late final PlatformWebViewControllerCreationParams params;
  if (WebViewPlatform.instance is WebKitWebViewPlatform) {
    params = WebKitWebViewControllerCreationParams(
      allowsInlineMediaPlayback:     true,
      mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
    );
  } else {
    params = const PlatformWebViewControllerCreationParams();
  }
  final controller = WebViewController.fromPlatformCreationParams(params);
  final platform = controller.platform;
  if (platform is AndroidWebViewController) {
    platform.setMediaPlaybackRequiresUserGesture(false);
  }
  return controller;
}

/// One warm Mainsail/Fluidd WebView, kept alive between visits to the dashboard
/// so re-opening a printer is instant. Holds the loaded SPA and its live
/// Moonraker WebSocket; a new [WebViewWidget] re-attaches to [controller] with
/// that state intact. See [PrinterWebViewCache].
class LiveWebSession {
  LiveWebSession({
    required this.controller,
    required this.baseUrl,
    required this.usingLan,
    required this.tunnelUrl,
  });

  /// The retained controller. Its native WebView survives as long as this
  /// session is in the cache.
  final WebViewController controller;

  /// The origin the controller actually loaded (LAN or tunnel) - used for the
  /// reopen liveness probe.
  String baseUrl;

  /// True if [baseUrl] is the LAN address. A LAN session goes stale the moment
  /// you leave home, so the screen revalidates these on reopen / resume.
  bool usingLan;

  /// Full tunnel URL, or null on a LAN-only session - drives the "use tunnel"
  /// retry and lets the refresh timer notice a rotated tunnel.
  String? tunnelUrl;

  /// Last time a screen attached to this session - the LRU key for
  /// memory-pressure eviction.
  DateTime lastUsed = DateTime.now();

  Timer? cookieRefresh;

  String? get tunnelHost =>
      tunnelUrl == null ? null : Uri.tryParse(tunnelUrl!)?.host;

  void dispose() {
    cookieRefresh?.cancel();
    cookieRefresh = null;
    // The native WebView is freed once no [WebViewWidget] references the
    // controller (we never show an evicted session) and Dart GCs it.
  }
}

/// Keeps every visited printer's Mainsail/Fluidd WebView warm so re-opening a
/// printer is instant instead of replaying Mainsail's "Initializing…" load -
/// the slow, every-single-time experience over the tunnel. The controller (and
/// its loaded page + live Moonraker WebSocket) lives here, not in the screen
/// State, so popping back to the dashboard no longer tears it down.
///
/// Cost: each warm session is a full WebView plus an open WebSocket. By default
/// we keep them all, but we listen for the OS low-memory signal and evict the
/// least-recently-used under pressure, so a large fleet on a small phone sheds
/// webviews instead of being killed.
class PrinterWebViewCache with WidgetsBindingObserver {
  PrinterWebViewCache._() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final PrinterWebViewCache instance = PrinterWebViewCache._();

  // Access-ordered: a touched entry is re-inserted at the end, so `.keys.first`
  // is the least-recently-used and `.keys.last` the most-recent.
  final Map<String, LiveWebSession> _sessions = {};

  void _log(String msg) => dev.log(msg, name: 'MOONGATE/WEBCACHE');

  /// The warm session for [printerId] (moved to most-recent), or null if none.
  LiveWebSession? lookup(String printerId) {
    final s = _sessions.remove(printerId);
    if (s == null) return null;
    s.lastUsed = DateTime.now();
    _sessions[printerId] = s;
    return s;
  }

  /// Whether a kept-warm session should be dropped in favour of a rebuild
  /// because it rides the tunnel while the dashboard's status poll is
  /// currently succeeding over LAN. A session's transport is decided ONCE
  /// (usually at app-start pre-warm, possibly off-WiFi), so without this a
  /// tunnel-born session stays on the tunnel forever - the tile honestly
  /// says Local while the printer page says Tunnel, paying tunnel latency
  /// and the remote-camera limits for no reason. The poll re-probes LAN
  /// every few seconds, so its verdict is the freshest signal available
  /// and costs no extra probe here.
  static bool tunnelSessionStaleOnLan({
    required bool               sessionUsingLan,
    required PrinterConnection? pollConnection,
  }) =>
      !sessionUsingLan && pollConnection == PrinterConnection.local;

  /// Register a freshly loaded session and start its background cookie refresh
  /// so it stays authed while off-screen.
  void store(String printerId, LiveWebSession session) {
    _sessions.remove(printerId)?.dispose();
    _sessions[printerId] = session;
    _scheduleCookieRefresh(printerId, session);
    _log('stored $printerId (${_sessions.length} warm)');
  }

  /// Drop one printer's warm session - call on refresh, address edit, removal,
  /// or a detected tunnel rotation, so the next open reloads from scratch.
  void invalidate(String printerId) {
    final s = _sessions.remove(printerId);
    if (s == null) return;
    s.dispose();
    _log('invalidated $printerId');
  }

  /// Wipe everything. Called on sign-out / wipe-and-re-pair.
  void clear() {
    for (final s in _sessions.values) {
      s.dispose();
    }
    _sessions.clear();
    _log('cleared');
  }

  /// Pre-warm every configured printer's Mainsail/Fluidd page in the background
  /// at startup, so the FIRST open of a printer is instant instead of replaying
  /// Mainsail's "Initializing…". Mirrors the screen's cold-load path (LAN-first,
  /// tunnel fallback) but headless - no widget is mounted; the page loads, its
  /// Moonraker WebSocket connects, and the controller is stored warm. A printer
  /// already warm is skipped; one that's offline / not yet reachable is skipped
  /// silently (the screen cold-loads it on open, exactly as before). Each warms
  /// concurrently so one slow printer doesn't hold up the rest; best-effort.
  void prewarmAll(List<PrinterConfig> printers) {
    for (final printer in printers) {
      if (_sessions.containsKey(printer.id)) continue;
      unawaited(_prewarmOne(printer));
    }
  }

  /// True when [printerId] must not touch the cloud: a Direct (LAN/VPN)
  /// printer, whether Direct-added (synthetic 'lan-…' id, no cloud row ever)
  /// or a cloud-paired one the user switched to Direct. Registry-live so a
  /// mode toggle takes effect without recreating anything.
  bool _isDirectMode(String printerId) {
    if (printerId.startsWith('lan-')) return true;
    for (final p in PrinterRegistry.instance.printers) {
      if (p.id == printerId) return p.lanOnly;
    }
    return false;
  }

  Future<void> _prewarmOne(PrinterConfig printer) async {
    try {
      String? useUrl;
      var usingLan = false;
      String? tunnelUrl;
      if (_isDirectMode(printer.id)) {
        // Direct (LAN/VPN): no Supabase mint, no mg_token cookie - mirror the
        // printer screen's Direct branch. LAN only; there is no tunnel to
        // fall back to. (Minting for a Direct-added id would just 500 the
        // Edge Function - its synthetic id isn't a cloud row.)
        final lanUrl =
            LanDiscoveryService.instance.lookup(printer.id) ?? printer.lanUrl;
        if (lanUrl == null || !await _isLanReachable(lanUrl)) return;
        useUrl   = lanUrl;
        usingLan = true;
      } else {
        final access = await PrinterAccessCache.instance.get(printer.id);
        await setMgTokenCookie(access);
        tunnelUrl = access.tunnelUrl;

        // Prefer LAN when reachable (Mainsail loads far faster direct), else
        // the tunnel - the same resolution the printer screen uses on a cold
        // open.
        final lanUrl =
            LanDiscoveryService.instance.lookup(printer.id) ?? printer.lanUrl;
        if (lanUrl != null && await _isLanReachable(lanUrl)) {
          useUrl = lanUrl;
          usingLan = true;
        } else if (tunnelUrl != null) {
          useUrl = tunnelUrl;
        }
      }
      if (useUrl == null) return; // not reachable yet - the screen cold-loads it

      // A real visit may have warmed (or be warming) this printer while we
      // awaited the access fetch / probe - don't clobber the live session.
      if (_sessions.containsKey(printer.id)) return;

      // Load headless, but only KEEP the session if the page actually finishes -
      // so we never hand the screen a blank/failed page (an offline printer would
      // otherwise lose its "starting up, retry" overlay to a dead page). This
      // also makes prewarm self-validating: if a headless WebView can't load on
      // this device, the wait times out, nothing is stored, and opening falls
      // back to the normal cold load - no regression.
      final controller = createWebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted);
      final loaded = Completer<bool>();
      controller.setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (!loaded.isCompleted) loaded.complete(true);
        },
        onWebResourceError: (err) {
          if (err.isForMainFrame == true && !loaded.isCompleted) {
            loaded.complete(false);
          }
        },
      ));
      await controller.loadRequest(Uri.parse('$useUrl/'));
      final ok = await loaded.future
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
      if (!ok) return; // blank / failed / too slow - the screen cold-loads on open

      // A real visit may have warmed this printer while the page loaded.
      if (_sessions.containsKey(printer.id)) return;
      store(
        printer.id,
        LiveWebSession(
          controller: controller,
          baseUrl:    useUrl,
          usingLan:   usingLan,
          tunnelUrl:  tunnelUrl,
        ),
      );
      _log('prewarmed ${printer.id} (${usingLan ? 'LAN' : 'tunnel'})');
    } catch (_) {
      // Offline / not paired / blip - skip; the screen cold-loads on open.
    }
  }

  // Token TTL is 5 min; refresh the cookie at 4 so a backgrounded session never
  // sends an expired token. Lives here (not in the screen) so it keeps running
  // while the printer screen is closed - without it a warm tunnel session would
  // silently 401 after five minutes. Also notices a rotated tunnel URL and
  // drops the now-unroutable session.
  void _scheduleCookieRefresh(String printerId, LiveWebSession session) {
    session.cookieRefresh?.cancel();
    session.cookieRefresh =
        Timer.periodic(const Duration(minutes: 4), (_) async {
      try {
        // Direct (LAN/VPN) mode has no cloud row and no mg_token cookie to
        // keep fresh - minting from here only 500s the Edge Function (this
        // exact timer was one real install's 15 calls/hr, July 2026).
        // Checked per tick so a mode toggle takes effect while the session
        // stays warm, in either direction.
        if (_isDirectMode(printerId)) return;
        final access = await PrinterAccessCache.instance.get(printerId);
        await setMgTokenCookie(access);
        final host = session.tunnelHost;
        if (host != null &&
            access.tunnelUrl != null &&
            Uri.tryParse(access.tunnelUrl!)?.host != host) {
          invalidate(printerId);
        }
      } catch (_) {
        // A single missed refresh isn't fatal - the live cookie is good for a
        // few more minutes and the screen's Retry covers a hard failure.
      }
    });
  }

  @override
  void didHaveMemoryPressure() {
    if (_sessions.length <= 1) return;
    final keep = _sessions.keys.last; // most-recently-used = likely on-screen
    final drop = _sessions.keys.where((k) => k != keep).toList();
    _log('memory pressure - evicting ${drop.length}, keeping $keep');
    for (final id in drop) {
      _sessions.remove(id)?.dispose();
    }
  }

  /// Set the EdDSA `mg_token` cookie scoped to the tunnel host so the Pi's auth
  /// proxy accepts every WebView request (HTML, JS, XHR, WS upgrade). No-op
  /// without a tunnel URL (LAN is trusted) or on v0.3 Pis. Shared by the screen
  /// (initial set) and the refresh timer here.
  static Future<void> setMgTokenCookie(PrinterAccess access) async {
    if (access.tunnelUrl == null) return;
    final tunnel = Uri.tryParse(access.tunnelUrl!);
    if (tunnel == null || tunnel.host.isEmpty) return;
    try {
      await WebViewCookieManager().setCookie(WebViewCookie(
        name:   'mg_token',
        value:  access.accessToken,
        domain: tunnel.host,
        path:   '/',
      ));
    } catch (_) {
      // setCookie can throw on older WebView versions; fall through.
    }
  }

  /// Fast LAN liveness probe used by [prewarmAll] (mirrors the printer screen's
  /// own `_isLanReachable`): true iff `${url}/server/info` answers within 2 s.
  /// Hits Moonraker's own endpoint (not nginx, which always 200s for Mainsail's
  /// index), so a sub-500 status doubles as a printer-side liveness signal;
  /// 401/403 still counts as reachable. Only network failures / timeouts fall
  /// through to the tunnel.
  static Future<bool> _isLanReachable(String url) async {
    try {
      final resp = await http
          .get(Uri.parse('$url/server/info'))
          .timeout(const Duration(seconds: 2));
      return resp.statusCode < 500;
    } catch (_) {
      return false;
    }
  }
}
