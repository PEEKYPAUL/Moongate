import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/services/klipper_include_resolver.dart';

void main() {
  test('resolves nested wildcard includes lexically', () {
    final result = const KlipperIncludeResolver().resolve('printer.cfg', {
      'printer.cfg': '[include configs/*.cfg]\n',
      'configs/z.cfg': '[z]\n',
      'configs/a.cfg': '[a]\n',
      'configs/sub.cfg': '[sub]\n',
    });
    expect(result.files,
        ['printer.cfg', 'configs/a.cfg', 'configs/sub.cfg', 'configs/z.cfg']);
    expect(result.diagnostics, isEmpty);
  });

  test('reports missing, traversal, cycles and repeats', () {
    final result = const KlipperIncludeResolver().resolve('printer.cfg', {
      'printer.cfg':
          '[include a.cfg]\n[include missing.cfg]\n[include ../x.cfg]\n',
      'a.cfg': '[include printer.cfg]\n',
    });
    expect(
        result.diagnostics.map((d) => d.message), contains('cyclic include'));
    expect(result.diagnostics.map((d) => d.message),
        contains('include has no match: missing.cfg'));
    expect(result.diagnostics.map((d) => d.message),
        contains('include has no match: ../x.cfg'));
  });

  test('resolves every pattern relative to the including directory', () {
    final result = const KlipperIncludeResolver().resolve('printer.cfg', {
      'printer.cfg': '[include configs/main.cfg]\n',
      'configs/main.cfg': '[include nested/*.cfg]\n',
      'configs/nested/ok.cfg': '[ok]\n',
      'nested/wrong.cfg': '[wrong]\n',
    });
    expect(result.files,
        ['printer.cfg', 'configs/main.cfg', 'configs/nested/ok.cfg']);
    expect(result.diagnostics, isEmpty);
  });

  test('wildcards do not cross path separators', () {
    expect(
      KlipperIncludeResolver.matchingPaths('configs/main.cfg', '*.cfg', [
        'configs/ok.cfg',
        'configs/nested/no.cfg',
      ]),
      ['configs/ok.cfg'],
    );
  });

  test('relative paths can move to a sibling folder without escaping root', () {
    expect(KlipperIncludeResolver.relativePath(
        'macros/tools.cfg', 'shared/common.cfg'), '../shared/common.cfg');
    expect(
        KlipperIncludeResolver.matchingPaths('macros/tools.cfg',
            '../shared/*.cfg', ['shared/common.cfg', 'outside.cfg']),
        ['shared/common.cfg']);
    expect(KlipperIncludeResolver.matchingPaths(
        'printer.cfg', '../outside.cfg', ['outside.cfg']), isEmpty);
  });
}
