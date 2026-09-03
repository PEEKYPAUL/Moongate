import '../models/klipper_config_doc.dart';

class IncludeDiagnostic {
  final String path;
  final String message;
  const IncludeDiagnostic(this.path, this.message);
  @override
  String toString() => '$path: $message';
}

class KlipperIncludeResolution {
  final List<String> files;
  final Map<String, List<String>> graph;
  final List<IncludeDiagnostic> diagnostics;
  const KlipperIncludeResolution(this.files, this.graph, this.diagnostics);
  bool get isValid => diagnostics.isEmpty;
}

/// Resolves Klipper's file includes using a listing and already-fetched text.
class KlipperIncludeResolver {
  final int maxDepth;
  final int maxBytes;
  const KlipperIncludeResolver(
      {this.maxDepth = 32, this.maxBytes = 4 * 1024 * 1024});

  KlipperIncludeResolution resolve(String root, Map<String, String> contents) {
    final files = contents.keys
        .map(_clean)
        .where((p) => p != null)
        .cast<String>()
        .toSet();
    final graph = <String, List<String>>{};
    final diagnostics = <IncludeDiagnostic>[];
    final ordered = <String>[];
    final visiting = <String>{};
    final visited = <String>{};
    var bytes = 0;
    void visit(String path, int depth) {
      if (depth > maxDepth) {
        diagnostics.add(IncludeDiagnostic(path, 'include nesting is too deep'));
        return;
      }
      if (visiting.contains(path)) {
        diagnostics.add(IncludeDiagnostic(path, 'cyclic include'));
        return;
      }
      if (visited.contains(path)) {
        diagnostics
            .add(IncludeDiagnostic(path, 'file included more than once'));
        return;
      }
      final text = contents[path];
      if (text == null) {
        diagnostics.add(IncludeDiagnostic(path, 'missing included file'));
        return;
      }
      bytes += text.length;
      if (bytes > maxBytes) {
        diagnostics
            .add(IncludeDiagnostic(path, 'aggregate config is too large'));
        return;
      }
      visiting.add(path);
      visited.add(path);
      ordered.add(path);
      final targets = <String>[];
      for (final section in KlipperConfigDoc.parse(text).sections) {
        if (!section.isInclude) continue;
        final pattern = section.name.substring('include '.length).trim();
        final base =
            path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
        final resolvedPattern = base.isEmpty ? pattern : '$base/$pattern';
        final matches = files
            .where((candidate) => _matches(resolvedPattern, candidate))
            .toList()
          ..sort();
        if (matches.isEmpty) {
          diagnostics
              .add(IncludeDiagnostic(path, 'include has no match: $pattern'));
        }
        targets.addAll(matches);
      }
      graph[path] = targets;
      for (final target in targets) {
        visit(target, depth + 1);
      }
      visiting.remove(path);
    }

    final normalizedRoot = _clean(root);
    if (normalizedRoot == null || !files.contains(normalizedRoot)) {
      diagnostics.add(IncludeDiagnostic(
          root, 'root file is outside the config root or missing'));
    } else {
      visit(normalizedRoot, 0);
    }
    return KlipperIncludeResolution(ordered, graph, diagnostics);
  }

  static List<String> matchingPaths(
      String includingPath, String pattern, Iterable<String> available) {
    final slash = includingPath.lastIndexOf('/');
    final prefix = slash < 0 ? '' : includingPath.substring(0, slash + 1);
    final rootedPattern = prefix + pattern;
    return available.where((path) => _matches(rootedPattern, path)).toList()
      ..sort();
  }

  static String relativePath(String includingPath, String targetPath) {
    final from = includingPath.split('/')..removeLast();
    final target = targetPath.split('/');
    var common = 0;
    while (common < from.length &&
        common < target.length &&
        from[common] == target[common]) {
      common++;
    }
    return [
      for (var i = common; i < from.length; i++) '..',
      ...target.skip(common),
    ].join('/');
  }

  static String? _clean(String path) {
    if (path.startsWith('/')) return null;
    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isEmpty) return null;
        parts.removeLast();
      } else {
        parts.add(part);
      }
    }
    return parts.isEmpty ? null : parts.join('/');
  }

  static bool _matches(String pattern, String path) {
    final clean = _clean(path);
    final cleanPattern = _clean(pattern);
    if (clean == null || cleanPattern == null) return false;
    final escaped = cleanPattern
        .split('*')
        .map((part) => part.split('?').map(RegExp.escape).join('[^/]'))
        .join('[^/]*');
    return RegExp('^$escaped\$').hasMatch(clean);
  }
}
