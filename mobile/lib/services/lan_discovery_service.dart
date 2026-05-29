import 'dart:async';
import 'dart:developer' as dev;

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
/// Stateless across cold launches — the map is in-memory only. On launch
/// the persisted `lanUrl` from `PrinterRegistry` covers us until the first
/// browse populates the map (~500 ms on a typical home network).
class LanDiscoveryService {
  LanDiscoveryService._();
  static final LanDiscoveryService instance = LanDiscoveryService._();

  /// Avahi advertises `_moongate._tcp` (no leading underscores in the
  /// `type` field passed to BonsoirDiscovery — bonsoir adds them itself).
  static const _serviceType = '_moongate._tcp';

  /// How long to listen for advertisements per browse cycle. 5 s is
  /// conservative — most home networks resolve mDNS in <500 ms, but
  /// the longer window covers stale Avahi caches, congested WiFi, and
  /// the bonsoir-on-Android cold-start delay.
  static const _browseDuration = Duration(seconds: 5);

  /// printer_id → discovered LAN URL.
  final Map<String, String> _discovered = {};

  /// Reentrancy guard for [refresh]. Concurrent calls are no-ops while
  /// a browse is already in flight — saves spawning duplicate Bonjour
  /// resolvers on every quick-fire foreground/poll-trigger overlap.
  bool _refreshing = false;

  /// Discovered URL for the given printer, or null if mDNS hasn't surfaced
  /// it in this session. Synchronous — callers can use it without `await`.
  String? lookup(String printerId) => _discovered[printerId];

  /// Start a 5 s browse cycle. Safe to call concurrently — a second call
  /// while a browse is already in flight is a no-op.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    BonsoirDiscovery? discovery;
    StreamSubscription<BonsoirDiscoveryEvent>? subscription;
    try {
      discovery = BonsoirDiscovery(type: _serviceType);
      await discovery.ready;

      // The stream getter is nullable on bonsoir — guard, but in practice
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
      // — if the discovery never actually started, stop will throw, and
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
          _onResolved(service);
        }
        break;
      // Lost / started / stopped / resolve-failed all no-op per §7.5 —
      // stale entries get refreshed by the next browse cycle. We don't
      // drop them on a single "lost" event because Avahi sometimes
      // re-announces after a brief network blip.
      // ignore: no_default_cases
      default:
        break;
    }
  }

  void _onResolved(ResolvedBonsoirService service) {
    final attrs = service.attributes;
    final printerId = attrs['printer_id'];
    if (printerId == null || printerId.isEmpty) {
      _log('Resolved service has no printer_id TXT, ignoring: ${service.name}');
      return;
    }
    final host = service.host;
    final port = service.port;
    if (host.isEmpty) {
      _log('Resolved service has no host, ignoring: ${service.name}');
      return;
    }
    final url = port == 80 ? 'http://$host' : 'http://$host:$port';
    if (_discovered[printerId] != url) {
      _log('Discovered ${printerId.substring(0, 8)}... → $url');
      _discovered[printerId] = url;
    }
  }

  /// Forget all discoveries — used on sign-out / user change.
  void clear() {
    _discovered.clear();
  }

  void _log(String msg) => dev.log(msg, name: 'MOONGATE/MDNS');
}
