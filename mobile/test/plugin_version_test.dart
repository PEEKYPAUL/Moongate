import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/config/plugin_version.dart';

void main() {
  group('pluginVersionAtLeast - capability gating', () {
    test('the minimum itself and anything newer satisfy it', () {
      expect(pluginVersionAtLeast('0.6.24', '0.6.24'), isTrue);
      expect(pluginVersionAtLeast('0.6.25', '0.6.24'), isTrue);
      expect(pluginVersionAtLeast('v0.7', '0.6.24'), isTrue);
      expect(pluginVersionAtLeast('1.0', '0.6.24'), isTrue);
    });

    test('older versions do not', () {
      expect(pluginVersionAtLeast('0.6.23', '0.6.24'), isFalse);
      expect(pluginVersionAtLeast('0.5.9', '0.6.24'), isFalse);
    });

    test('unknown versions are never attributed capabilities', () {
      // The opposite polarity to pluginVersionIsOutdated's unparseable-is-
      // current rule: a nag held back is safe, a capability assumed is not.
      expect(pluginVersionAtLeast(null, '0.6.24'), isFalse);
      expect(pluginVersionAtLeast('', '0.6.24'), isFalse);
      expect(pluginVersionAtLeast('garbage', '0.6.24'), isFalse);
    });
  });

  group('the 0.6.25 badge line this release ships', () {
    test('everything before 0.6.25 nudges, 0.6.25+ does not', () {
      expect(pluginVersionIsOutdated('0.6.22'), isTrue);
      expect(pluginVersionIsOutdated('0.6.24'), isTrue);
      expect(pluginVersionIsOutdated('0.6.25'), isFalse);
      expect(pluginVersionIsOutdated('0.6.26'), isFalse);
    });
  });
}
