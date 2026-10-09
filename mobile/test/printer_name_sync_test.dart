// Pins PrinterRegistry.cloudRenamesNeeded, the pure half of the name sync
// that keeps a cloud-paired printer's Supabase row (the iPhone push title's
// source) in line with the name on the phone. The Discord report behind it:
// a typo fixed in the app still headed every notification, because the row
// kept the pairing-time name.
import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/models/printer_config.dart';
import 'package:moongate/services/printer_registry.dart';
import 'package:moongate/services/supabase_service.dart';

const _idA = '11111111-1111-4111-8111-111111111111';
const _idB = '22222222-2222-4222-8222-222222222222';

RemotePrinterRow _row(String id, String name) =>
    RemotePrinterRow(id: id, name: name);

void main() {
  group('cloudRenamesNeeded', () {
    test('a renamed cloud printer is pushed under its local name', () {
      final out = PrinterRegistry.cloudRenamesNeeded(
        const [PrinterConfig(id: _idA, name: 'Voron 2.4')],
        [_row(_idA, 'Vorn 2.4')],
      );
      expect(out, {_idA: 'Voron 2.4'});
    });

    test('a matching name needs nothing', () {
      final out = PrinterRegistry.cloudRenamesNeeded(
        const [PrinterConfig(id: _idA, name: 'Voron 2.4')],
        [_row(_idA, 'Voron 2.4')],
      );
      expect(out, isEmpty);
    });

    test('only the printers that differ are listed', () {
      final out = PrinterRegistry.cloudRenamesNeeded(
        const [
          PrinterConfig(id: _idA, name: 'Voron 2.4'),
          PrinterConfig(id: _idB, name: 'K3'),
        ],
        [_row(_idA, 'Voron 2.4'), _row(_idB, 'K3 typo')],
      );
      expect(out, {_idB: 'K3'});
    });

    test('a Direct-mode printer has no row and is skipped', () {
      final out = PrinterRegistry.cloudRenamesNeeded(
        const [PrinterConfig(id: 'lan-abc', name: 'Micron+')],
        [_row('lan-abc', 'something else')],
      );
      expect(out, isEmpty);
    });

    test('a printer the account no longer holds is skipped', () {
      final out = PrinterRegistry.cloudRenamesNeeded(
        const [PrinterConfig(id: _idA, name: 'Voron 2.4')],
        const [],
      );
      expect(out, isEmpty);
    });

    test('the local name is trimmed before comparing and sending', () {
      final out = PrinterRegistry.cloudRenamesNeeded(
        const [PrinterConfig(id: _idA, name: '  Voron 2.4 ')],
        [_row(_idA, 'Voron 2.4')],
      );
      expect(out, isEmpty);
      final out2 = PrinterRegistry.cloudRenamesNeeded(
        const [PrinterConfig(id: _idA, name: '  Voron ')],
        [_row(_idA, 'Voron 2.4')],
      );
      expect(out2, {_idA: 'Voron'});
    });

    test('an empty local name is never sent', () {
      final out = PrinterRegistry.cloudRenamesNeeded(
        const [PrinterConfig(id: _idA, name: '   ')],
        [_row(_idA, 'Voron 2.4')],
      );
      expect(out, isEmpty);
    });
  });
}
