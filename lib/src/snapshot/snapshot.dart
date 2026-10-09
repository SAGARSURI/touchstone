// Snapshot schema v1 and its canonical text form (spec: Snapshot schema).
//
// A snapshot is a tree of component nodes with a hash at every node. Detection
// fields (id, bounds, paint, semantics, opaque) feed the hashes; explanation
// fields (type, style) only name causes and never affect a hash.
//
// Canonical form: UTF-8 text, a fixed header, then one node per line with its
// fields in a fixed order separated by tabs. Free text is JSON-encoded, doubles
// are written in shortest round-trip form, and the tree is given by two-space
// indentation.

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Raised on any change to the canonical form.
const int schemaVersion = 1;

const String _magic = 'touchstone-snapshot';

/// The `style` key prefix for render objects that draw nothing and only
/// place or size their children: their properties explain a layout change
/// inside a component, not a style change.
const String layoutStylePrefix = 'layout.';

class Snapshot {
  Snapshot({
    required this.id,
    required this.inputs,
    required this.toolchain,
    required this.coverage,
    required this.root,
  });

  /// Test name plus state and variant, such as `order_ticket/loading/dark`.
  final String id;

  /// Theme, locale, text scale, viewport, platform and declared app state.
  final Map<String, String> inputs;

  /// Flutter, engine, Dart and library versions, the renderer and the fonts.
  final Map<String, String> toolchain;

  final Coverage coverage;

  final SnapshotNode root;

  String get rootHash => root.subtreeHash;

  /// Every node in depth-first order, with its full id.
  Iterable<(String, SnapshotNode)> walk() sync* {
    Iterable<(String, SnapshotNode)> visit(String prefix, SnapshotNode node) sync* {
      final String full = prefix.isEmpty ? node.id : '$prefix/${node.id}';
      yield (full, node);
      for (final SnapshotNode child in node.children) {
        yield* visit(full, child);
      }
    }

    yield* visit('', root);
  }

  String toCanonical() {
    final out = StringBuffer()
      ..writeln('$_magic $schemaVersion')
      ..writeln('id\t${jsonEncode(id)}')
      ..writeln('inputs\t${_pairs(inputs)}')
      ..writeln('toolchain\t${_pairs(toolchain)}');
    for (final String limit in coverage.limits) {
      out.writeln('limit\t${jsonEncode(limit)}');
    }
    for (final MapEntry<String, List<String>> e in coverage.opaqueNodes.entries) {
      out.writeln('opaque\t${jsonEncode(e.key)}\t${e.value.join('+')}');
    }
    out
      ..writeln('rootHash\t$rootHash')
      ..writeln('nodes');
    void write(SnapshotNode node, int depth) {
      out.writeln('${'  ' * depth}${node.line}');
      for (final SnapshotNode child in node.children) {
        write(child, depth + 1);
      }
    }

    write(root, 0);
    return out.toString();
  }

  static String _pairs(Map<String, String> m) => m.entries.map((e) => '${e.key}=${jsonEncode(e.value)}').join('\t');

  /// Parses [text] written by [toCanonical]. Node hashes are recomputed and
  /// must match the ones written, so a hand-edited node is rejected. The
  /// header lines (inputs, toolchain, limits) are not hashed.
  static Snapshot parse(String text) {
    final List<String> lines = const LineSplitter().convert(text);
    var i = 0;
    String next() => lines[i++];
    final String head = next();
    if (head != '$_magic $schemaVersion') {
      throw FormatException('Not a touchstone schema $schemaVersion snapshot: $head');
    }
    String field(String name) {
      final String line = next();
      if (!line.startsWith('$name\t') && line != name) {
        throw FormatException('Expected $name, found: $line');
      }
      return line.length > name.length ? line.substring(name.length + 1) : '';
    }

    Map<String, String> pairs(String s) => <String, String>{
      for (final String p in s.isEmpty ? const <String>[] : s.split('\t'))
        p.substring(0, p.indexOf('=')): jsonDecode(p.substring(p.indexOf('=') + 1)) as String,
    };

    final id = jsonDecode(field('id')) as String;
    final Map<String, String> inputs = pairs(field('inputs'));
    final Map<String, String> toolchain = pairs(field('toolchain'));
    final limits = <String>[];
    final opaque = <String, List<String>>{};
    while (lines[i].startsWith('limit\t')) {
      limits.add(jsonDecode(next().substring(6)) as String);
    }
    while (lines[i].startsWith('opaque\t')) {
      final List<String> parts = next().split('\t');
      opaque[jsonDecode(parts[1]) as String] = parts[2].split('+');
    }
    final String rootHash = field('rootHash');
    field('nodes');
    final stack = <(int, SnapshotNode)>[];
    SnapshotNode? root;
    final pendingChildren = <SnapshotNode, List<SnapshotNode>>{};
    final order = <SnapshotNode>[];
    while (i < lines.length && lines[i].isNotEmpty) {
      final String line = next();
      final int depth = (line.length - line.trimLeft().length) ~/ 2;
      final SnapshotNode node = SnapshotNode._parseLine(line.trimLeft());
      order.add(node);
      pendingChildren[node] = <SnapshotNode>[];
      while (stack.isNotEmpty && stack.last.$1 >= depth) {
        stack.removeLast();
      }
      if (stack.isEmpty) {
        root = node;
      } else {
        pendingChildren[stack.last.$2]!.add(node);
      }
      stack.add((depth, node));
    }
    // Rebuild bottom-up so every subtree hash is recomputed from content.
    final rebuilt = <SnapshotNode, SnapshotNode>{};
    for (final SnapshotNode n in order.reversed) {
      rebuilt[n] = n._withChildren(<SnapshotNode>[for (final SnapshotNode c in pendingChildren[n]!) rebuilt[c]!]);
      if (rebuilt[n]!.subtreeHash != n._parsedSub) {
        throw FormatException('Subtree hash does not match content for ${n.id}');
      }
    }
    final snapshot = Snapshot(
      id: id,
      inputs: inputs,
      toolchain: toolchain,
      coverage: Coverage(limits: limits, opaqueNodes: opaque),
      root: rebuilt[root]!,
    );
    if (snapshot.rootHash != rootHash) {
      throw const FormatException('Root hash does not match content');
    }
    return snapshot;
  }
}

/// What this snapshot could not see.
class Coverage {
  Coverage({required this.limits, required this.opaqueNodes});

  /// Declared limits of the capture environment that applied to this capture.
  final List<String> limits;

  /// Full node id to the reasons its paint is a pixel hash.
  final Map<String, List<String>> opaqueNodes;
}

class SnapshotNode {
  SnapshotNode({
    required this.id,
    required this.bounds,
    required this.paint,
    required this.semantics,
    required this.opaque,
    required this.type,
    required this.style,
    required this.children,
  }) : subtreeHash = _subtreeHash(id, bounds, paint, semantics, opaque, children);

  /// This node's segment of its id: `Type#key` for an explicit key, otherwise
  /// `Type@n`, the n-th component of that type among its siblings. The full
  /// id joins the segments from the root with `/`.
  final String id;

  /// Global bounds in logical pixels, `x,y,width,height`, exact doubles; `-`
  /// when the component has no render object.
  final String bounds;

  /// SHA-256 of the node's own paint commands. An opaque node's commands
  /// include a pixel hash of every pixel its paint can reach.
  final String paint;

  /// The semantics nodes this component owns, canonical JSON.
  final String semantics;

  /// Why paint could not be recorded by value, `+`-separated; `-` if it could.
  final String opaque;

  /// Explanation: widget class and the package it comes from.
  final String type;

  /// Explanation: resolved visual properties, canonical JSON.
  final String style;

  final List<SnapshotNode> children;

  /// SHA-256 over the detection fields and the children's subtree hashes.
  final String subtreeHash;

  String? _parsedSub;

  String get detectionText => _detection(id, bounds, paint, semantics, opaque);

  String get line => <String>[
    jsonEncode(id),
    'bounds=$bounds',
    'paint=$paint',
    'sem=$semantics',
    'opaque=$opaque',
    'type=${jsonEncode(type)}',
    'style=$style',
    'sub=$subtreeHash',
  ].join('\t');

  static String _detection(String id, String bounds, String paint, String semantics, String opaque) =>
      <String>[jsonEncode(id), bounds, paint, semantics, opaque].join('\t');

  static String _subtreeHash(
    String id,
    String bounds,
    String paint,
    String semantics,
    String opaque,
    List<SnapshotNode> children,
  ) => sha256
      .convert(
        utf8.encode(
          <String>[
            _detection(id, bounds, paint, semantics, opaque),
            for (final SnapshotNode c in children) c.subtreeHash,
          ].join('\n'),
        ),
      )
      .toString();

  static SnapshotNode _parseLine(String line) {
    final List<String> parts = line.split('\t');
    String value(int i, String name) {
      if (!parts[i].startsWith('$name=')) {
        throw FormatException('Expected $name in: $line');
      }
      return parts[i].substring(name.length + 1);
    }

    return SnapshotNode(
      id: jsonDecode(parts[0]) as String,
      bounds: value(1, 'bounds'),
      paint: value(2, 'paint'),
      semantics: value(3, 'sem'),
      opaque: value(4, 'opaque'),
      type: jsonDecode(value(5, 'type')) as String,
      style: value(6, 'style'),
      children: const <SnapshotNode>[],
    ).._parsedSub = value(7, 'sub');
  }

  SnapshotNode _withChildren(List<SnapshotNode> children) => SnapshotNode(
    id: id,
    bounds: bounds,
    paint: paint,
    semantics: semantics,
    opaque: opaque,
    type: type,
    style: style,
    children: children,
  );
}
