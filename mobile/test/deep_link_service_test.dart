import 'package:flutter_test/flutter_test.dart';

import 'package:moongate/services/deep_link_service.dart';

void main() {
  group('DeepLinkService.isPairingUri', () {
    test('accepts the cloud pairing payload', () {
      final uri = Uri.parse(
          'moongate://pair?v=3&pk=abc123&et=GATE-1234-5678&ip=192.168.1.50&port=80');
      expect(DeepLinkService.isPairingUri(uri), isTrue);
    });

    test('accepts the LAN-only payload', () {
      final uri =
          Uri.parse('moongate://lan?v=1&ip=192.168.1.50&port=80&name=voron');
      expect(DeepLinkService.isPairingUri(uri), isTrue);
    });

    test('rejects other schemes carrying our hosts', () {
      expect(DeepLinkService.isPairingUri(Uri.parse('https://pair/x')), isFalse);
      expect(DeepLinkService.isPairingUri(Uri.parse('http://lan')), isFalse);
    });

    test('rejects unknown moongate hosts rather than surfacing errors', () {
      expect(
          DeepLinkService.isPairingUri(Uri.parse('moongate://update?v=9')),
          isFalse);
      expect(DeepLinkService.isPairingUri(Uri.parse('moongate://')), isFalse);
    });
  });
}
