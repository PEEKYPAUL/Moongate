import 'package:flutter_test/flutter_test.dart';

import 'package:moongate/models/printer_config.dart';
import 'package:moongate/services/printer_webview_cache.dart';

/// Locks the "tile says Local, printer page says Tunnel" fix: a kept-warm
/// tunnel session must be dropped (and rebuilt on LAN) whenever the
/// dashboard's status poll is currently succeeding over LAN. From a live
/// user report: page pre-warmed off-WiFi rode the tunnel forever while the
/// tile honestly showed Local.
void main() {
  group('tunnelSessionStaleOnLan', () {
    test('tunnel session + poll on LAN = stale, rebuild', () {
      expect(
        PrinterWebViewCache.tunnelSessionStaleOnLan(
          sessionUsingLan: false,
          pollConnection:  PrinterConnection.local,
        ),
        isTrue,
      );
    });

    test('tunnel session + poll on tunnel = keep (nothing better available)',
        () {
      expect(
        PrinterWebViewCache.tunnelSessionStaleOnLan(
          sessionUsingLan: false,
          pollConnection:  PrinterConnection.remote,
        ),
        isFalse,
      );
    });

    test('tunnel session + printer offline = keep (rebuild would only fail)',
        () {
      expect(
        PrinterWebViewCache.tunnelSessionStaleOnLan(
          sessionUsingLan: false,
          pollConnection:  PrinterConnection.offline,
        ),
        isFalse,
      );
    });

    test('tunnel session + no poll yet = keep (no evidence to act on)', () {
      expect(
        PrinterWebViewCache.tunnelSessionStaleOnLan(
          sessionUsingLan: false,
          pollConnection:  null,
        ),
        isFalse,
      );
    });

    test('LAN session is never stale here, whatever the poll says', () {
      for (final conn in [...PrinterConnection.values, null]) {
        expect(
          PrinterWebViewCache.tunnelSessionStaleOnLan(
            sessionUsingLan: true,
            pollConnection:  conn,
          ),
          isFalse,
          reason: 'LAN session must be kept for poll=$conn '
              '(the existing _revalidateWarm handles a dead LAN)',
        );
      }
    });
  });
}
