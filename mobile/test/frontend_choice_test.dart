import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/models/printer_config.dart';
import 'package:moongate/services/frontend_choice.dart';

/// v0.9.84: the Mainsail / Fluidd switch. The plugin (0.6.32+) lists the
/// interfaces the Pi serves; these rules decide which one the printer page
/// opens, what the switch button offers, and the URL / cookie each load uses.
void main() {
  const mainsail = PrinterFrontend(type: 'mainsail', port: 80);
  const fluidd   = PrinterFrontend(type: 'fluidd',   port: 81);
  const octo     = PrinterFrontend(type: 'octoprint', port: 5000);

  PrinterConfig printer({String? preferredUi, List<PrinterFrontend>? frontends,
      String? lanUrl = 'http://192.168.1.50'}) =>
      PrinterConfig(
        id:          'p1',
        name:        'Voron',
        lanUrl:      lanUrl,
        preferredUi: preferredUi,
        frontends:   frontends ?? const [],
      );

  group('parseFrontendList', () {
    test('reads the plugin shape, drops junk and duplicate types', () {
      final list = parseFrontendList({
        'frontends': [
          {'type': 'mainsail', 'port': 80},
          {'type': 'fluidd',   'port': 81},
          {'type': 'fluidd',   'port': 4409},  // same type again: dropped
          {'type': 'bad',      'port': 'x'},
          {'type': '',         'port': 82},
          'junk',
        ],
      });
      expect(list, [mainsail, fluidd]);
    });

    test('older plugins and odd answers give an empty list', () {
      expect(parseFrontendList(null), isEmpty);
      expect(parseFrontendList({}), isEmpty);
      expect(parseFrontendList({'frontends': 'nope'}), isEmpty);
    });
  });

  group('currentFrontend / otherFrontend', () {
    test('the persisted pick wins when still listed', () {
      expect(currentFrontend([mainsail, fluidd], 'fluidd', defaultPort: 80),
          fluidd);
    });

    test('a pick the printer no longer lists falls back to the default port',
        () {
      expect(currentFrontend([mainsail, fluidd], 'octoprint', defaultPort: 80),
          mainsail);
    });

    test('no pick: the interface on the advertised port, else the first', () {
      expect(currentFrontend([mainsail, fluidd], null, defaultPort: 80),
          mainsail);
      expect(currentFrontend([mainsail, fluidd], null, defaultPort: 81),
          fluidd);
      expect(currentFrontend([fluidd, octo], null, defaultPort: 80), fluidd);
      expect(currentFrontend(const [], null, defaultPort: 80), isNull);
    });

    test('the button offers the OTHER interface, and only with exactly two',
        () {
      expect(otherFrontend([mainsail, fluidd], mainsail), fluidd);
      expect(otherFrontend([mainsail, fluidd], fluidd), mainsail);
      expect(otherFrontend([mainsail, fluidd, octo], mainsail), isNull);
      expect(otherFrontend([mainsail], mainsail), isNull);
      expect(otherFrontend([mainsail, fluidd], null), isNull);
    });

    test('switching flips which logo the button shows', () {
      // On Mainsail the button shows Fluidd's mark; after the switch the
      // page is on Fluidd and the button shows the sail (Paul, 27/11/2026).
      final before = currentFrontend([mainsail, fluidd], null, defaultPort: 80);
      expect(otherFrontend([mainsail, fluidd], before)!.type, 'fluidd');
      final after = currentFrontend([mainsail, fluidd], 'fluidd', defaultPort: 80);
      expect(otherFrontend([mainsail, fluidd], after)!.type, 'mainsail');
    });
  });

  group('lanUrlForPort / portOfUrl', () {
    test('re-points the LAN address at another port', () {
      expect(lanUrlForPort('http://192.168.1.50', 81), 'http://192.168.1.50:81');
      expect(lanUrlForPort('http://192.168.1.50:80', 81), 'http://192.168.1.50:81');
      expect(lanUrlForPort('http://voron.local:4408', 4409),
          'http://voron.local:4409');
    });

    test('port 80 drops the suffix, matching the plugin-advertised form', () {
      expect(lanUrlForPort('http://192.168.1.50:81', 80), 'http://192.168.1.50');
      expect(lanUrlForPort('https://printer.example', 443),
          'https://printer.example');
    });

    test('garbage comes back untouched', () {
      expect(lanUrlForPort('not a url', 81), 'not a url');
      expect(lanUrlForPort('', 81), '');
    });

    test('portOfUrl reads the explicit or default port', () {
      expect(portOfUrl('http://192.168.1.50'), 80);
      expect(portOfUrl('http://192.168.1.50:7125'), 7125);
      expect(portOfUrl('https://printer.example'), 443);
      expect(portOfUrl('garbage'), 80);
    });
  });

  group('chosenFrontend / lanUrlForChoice / mgUiCookieValue', () {
    test('one interface: nothing to choose, URL and cookie as before', () {
      final p = printer(frontends: [mainsail]);
      expect(chosenFrontend(p, defaultPort: 80), isNull);
      expect(lanUrlForChoice('http://192.168.1.50', p), 'http://192.168.1.50');
      expect(mgUiCookieValue(p, defaultPort: 80), 'default');
    });

    test('two interfaces, no pick: the default port, cookie names it', () {
      final p = printer(frontends: [mainsail, fluidd]);
      expect(lanUrlForChoice('http://192.168.1.50', p), 'http://192.168.1.50');
      expect(mgUiCookieValue(p, defaultPort: 80), 'mainsail');
    });

    test('two interfaces, Fluidd picked: port 81 at home, cookie away', () {
      final p = printer(frontends: [mainsail, fluidd], preferredUi: 'fluidd');
      expect(lanUrlForChoice('http://192.168.1.50', p), 'http://192.168.1.50:81');
      expect(mgUiCookieValue(p, defaultPort: 80), 'fluidd');
    });

    test('a pick with no list (older plugin) changes nothing', () {
      final p = printer(preferredUi: 'fluidd');
      expect(lanUrlForChoice('http://192.168.1.50', p), 'http://192.168.1.50');
      expect(mgUiCookieValue(p, defaultPort: 80), 'default');
    });
  });

  group('persistence', () {
    test('preferredUi and frontends ride the config JSON', () {
      final p = printer(frontends: [mainsail, fluidd], preferredUi: 'fluidd');
      final back = PrinterConfig.fromJson(p.toJson());
      expect(back.preferredUi, 'fluidd');
      expect(back.frontends, [mainsail, fluidd]);
    });

    test('absent fields read as no pick and no list', () {
      final back = PrinterConfig.fromJson(printer().toJson());
      expect(back.preferredUi, isNull);
      expect(back.frontends, isEmpty);
    });
  });

  group('names and logos', () {
    test('display names', () {
      expect(frontendDisplayName('mainsail'), 'Mainsail');
      expect(frontendDisplayName('fluidd'), 'Fluidd');
      expect(frontendDisplayName('octoprint'), 'OctoPrint');
      expect(frontendDisplayName('klipperscreen'), 'Klipperscreen');
    });

    test('the tile logo follows the pick, then the sniff, then the saved type',
        () {
      expect(effectiveUiType(printer(preferredUi: 'fluidd'), 'mainsail'),
          'fluidd');
      expect(effectiveUiType(printer(), 'mainsail'), 'mainsail');
      expect(effectiveUiType(printer(), null), isNull);
    });

    test('marks exist for the two UIs we ship logos for', () {
      expect(frontendMarkAsset('mainsail'), isNotNull);
      expect(frontendMarkAsset('fluidd'), isNotNull);
      expect(frontendMarkAsset('octoprint'), isNull);
    });
  });
}
