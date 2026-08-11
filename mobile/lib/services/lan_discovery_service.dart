import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';

/// Discovers Moongate-advertising Pis on the local network via mDNS.
///
/// Companion to the Pi-side Avahi service file installed by v0.4.4+ (see
/// `docs/v0.5-lan-discovery-design.md` §6). Browses for `_moongate._tcp.local`
/// services, extracts each one's `printer_id` from the TXT records, and
/// keeps a `printerId → "http://host[:port]"` map. The status and control
/// services consult this map at the top of every LAN-bound call; when an
/// entry is present, the discovered URL takes precedence over the
/// persisted `lanUrl` so an IP change is recovered without needing a
/// tunnel-side round-trip.
///
/// Stateless across cold launches - the map is in-memory only. On launch
/// the persisted `lanUrl` from `PrinterRegistry` covers us until the first
/// browse populates the map (~500 ms on a typical home network).
class LanDiscoveryService {
  LanDiscoveryService._();
  static final LanDiscoveryService instance = LanDiscoveryService._();

  /// Avahi advertises `_moongate._tcp` (no leading underscores in the
  /// `type` field passed to BonsoirDiscovery - bonsoir adds them itself).
  static const _serviceType = '_moongate._tcp';

  /// How long to listen for advertisements per browse cycle. 5 s is
  /// conservative - most home networks resolve mDNS in <500 ms, but
  /// the longer window covers stale Avahi caches, congested WiFi, and
  /// the bonsoir-on-Android cold-start delay.
  static const _browseDuration = Duration(seconds: 5);

  /// How long to wait for the OS resolver when a browse answers with a
  /// hostname instead of an address (the iOS/bonsoir behaviour). The name
  /// was just advertised so it is almost always in the mDNS cache; a hung
  /// lookup must not outlive the browse window it runs inside.
  static const _lookupTimeout = Duration(seconds: 2);

  /// printer_id → discovered LAN URL.
  final Map<String, String> _discovered = {};

  /// Reentrancy guard for [refresh]. Concurrent calls are no-ops while
  /// a browse is already in flight - saves spawning duplicate Bonjour
  /// resolvers on every quick-fire foreground/poll-trigger overlap.
  bool _refreshing = false;

  /// Discovered URL for the given printer, or null if mDNS hasn't surfaced
  /// it in this session. Synchronous - callers can use it without `await`.
  String? lookup(String printerId) => _discovered[printerId];

  /// Snapshot of everything the current browse has resolved (printer_id →
  /// URL). Used by the bug-report diagnostics so a "can't find my printer"
  /// report shows whether mDNS surfaced anything at all.
  Map<String, String> get discovered => Map.unmodifiable(_discovered);

  /// Start a 5 s browse cycle. Safe to call concurrently - a second call
  /// while a browse is already in flight is a no-op.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    BonsoirDiscovery? discovery;
    StreamSubscription<BonsoirDiscoveryEvent>? subscription;
    try {
      discovery = BonsoirDiscovery(type: _serviceType);
      await discovery.ready;

      // The stream getter is nullable on bonsoir - guard, but in practice
      // it's non-null after `ready` resolves on Android and iOS.
      subscription = discovery.eventStream?.listen((event) {
        // Don't await here; the bonsoir docs note that long-running event
        // handlers can stall delivery of the next event. Fire-and-forget
        // the resolve / dispatch so the stream keeps draining.
        _onEvent(event, discovery!).catchError((Object e) {
          _log('Event handler failed: $e');
        });
      });

      await discovery.start();
      await Future<void>.delayed(_browseDuration);
    } catch (e) {
      _log('refresh failed: $e');
    } finally {
      // Always tear down, even if start() threw. Swallow stop/cancel errors
      // - if the discovery never actually started, stop will throw, and
      // that's fine.
      try {
        await discovery?.stop();
      } catch (_) {}
      try {
        await subscription?.cancel();
      } catch (_) {}
      _refreshing = false;
    }
  }

  Future<void> _onEvent(
      BonsoirDiscoveryEvent event, BonsoirDiscovery discovery) async {
    final service = event.service;
    if (service == null) return;

    switch (event.type) {
      case BonsoirDiscoveryEventType.discoveryServiceFound:
        // On Android, NsdManager auto-resolves so this event already
        // carries host+port+attributes. On iOS, an explicit resolve()
        // call is needed. Calling resolve() on an already-resolved
        // service is a cheap no-op, so we always do it for symmetry.
        try {
          await service.resolve(discovery.serviceResolver);
        } catch (e) {
          _log('Resolve failed for ${service.name}: $e');
        }
        break;
      case BonsoirDiscoveryEventType.discoveryServiceResolved:
        if (service is ResolvedBonsoirService) {
          await _onResolved(service);
        }
        break;
      // Lost / started / stopped / resolve-failed all no-op per §7.5 -
      // stale entries get refreshed by the next browse cycle. We don't
      // drop them on a single "lost" event because Avahi sometimes
      // re-announces after a brief network blip.
      // ignore: no_default_cases
      default:
        break;
    }
  }

  Future<void> _onResolved(ResolvedBonsoirService service) async {
    final attrs = service.attributes;
    final printerId = attrs['printer_id'];
    if (printerId == null || printerId.isEmpty) {
      _log('Resolved service has no printer_id TXT, ignoring: ${service.name}');
      return;
    }
    // bonsoir 5.x: ResolvedBonsoirService.host is nullable (the resolver
    // can complete with no IP if it raced a 'lost' event, etc.). Treat
    // null and empty the same way - skip; the next browse will retry.
    final host = service.host;
    final port = service.port;
    if (host == null || host.isEmpty) {
      _log('Resolved service has no host, ignoring: ${service.name}');
      return;
    }
    final url = urlForHost(await _numericHostFor(host), port);
    if (url == null) {
      // Never store it: everything that consults this map treats a hit as
      // better than the persisted lanUrl, so one bad answer would strand the
      // printer on the tunnel while it sits on the same subnet (the field
      // case: Android resolving to fe80::...%wlan0).
      _log('Unusable resolved host for ${printerId.substring(0, 8)}... '
          '($host), ignoring');
      return;
    }
    if (_discovered[printerId] != url) {
      _log('Discovered ${printerId.substring(0, 8)}... → $url');
      _discovered[printerId] = url;
    }
  }

  /// Numeric host for a resolved mDNS answer. Android's resolver hands back
  /// addresses already (they pass through untouched via the tryParse gate);
  /// iOS/bonsoir hands back the advertised *hostname* (`voron24.local.`),
  /// which must not enter the map as-is: inside WKWebView, Mainsail's
  /// Moonraker websocket resolves such names AAAA-first with no IPv4
  /// fallback, and MainsailOS nginx listens on IPv4 only, so the first
  /// printer-page open dies on a perfectly healthy LAN (#268). Resolving
  /// here - the single point where discovered hosts enter the map - fixes
  /// every consumer at once. On lookup failure or timeout the hostname is
  /// kept: the pre-fix behaviour, and still the right last resort on
  /// networks where names do work end to end.
  Future<String> _numericHostFor(String host) async {
    if (InternetAddress.tryParse(host) != null) return host;
    try {
      final addresses =
          await InternetAddress.lookup(host).timeout(_lookupTimeout);
      return pickResolvedHost(host, addresses);
    } catch (_) {
      return host;
    }
  }

  /// Address pick order for a hostname the OS resolver expanded: the first
  /// IPv4, else the first IPv6 that would survive [urlForHost]'s gates
  /// (zone-indexed and fe80::/10 link-local never win), else the hostname
  /// itself. IPv4 outranks IPv6 because Pi-class rigs serve nginx on
  /// `0.0.0.0` only - a routable AAAA that beats the A record is exactly
  /// the #268 failure. Static and pure for tests.
  static String pickResolvedHost(
      String host, List<InternetAddress> addresses) {
    for (final a in addresses) {
      if (a.type == InternetAddressType.IPv4) return a.address;
    }
    for (final a in addresses) {
      if (a.type == InternetAddressType.IPv6 &&
          urlForHost(a.address, 80) != null) {
        return a.address;
      }
    }
    return host;
  }

  /// LAN URL for a resolved mDNS host, or null when the host can never work
  /// as one. Android's resolver happily answers with IPv6 link-local
  /// addresses carrying a zone index (`fe80::...%wlan0`) - meaningless off
  /// the resolving interface and unusable in a URL, so they are rejected
  /// rather than stored. A usable plain IPv6 host is bracketed; IPv4 and
  /// hostnames pass through unchanged. Static and pure for tests.
  static String? urlForHost(String host, int port) {
    if (host.contains('%')) return null; // zone index = interface-scoped
    var h = host;
    if (h.contains(':')) {
      // IPv6. Link-local (fe80::/10) is unroutable outside its interface -
      // covers fe80-febf in the first hextet, any case.
      final first = h.split(':').first.toLowerCase();
      if (first.length == 4 &&
          first.startsWith('fe') &&
          '89ab'.contains(first[2])) {
        return null;
      }
      h = '[$h]';
    }
    return port == 80 ? 'http://$h' : 'http://$h:$port';
  }

  /// Forget all discoveries - used on sign-out / user change.
  void clear() {
    _discovered.clear();
  }

  void _log(String msg) => dev.log(msg, name: 'MOONGATE/MDNS');
}
