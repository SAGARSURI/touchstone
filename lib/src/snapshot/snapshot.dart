// Snapshot schema v1 and its canonical text form (spec: Snapshot schema).
//
// A snapshot is a tree of component nodes with a hash at every node. Detection
// fields (id, bounds, paint, semantics, opaque, flat) feed the hashes; explanation
// fields (type, style, shape) only name causes and never affect a hash.
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
    // A checkout with autocrlf turns every line ending into CRLF; the first
    // one says which.
    final int firstEnd = text.indexOf('\n');
    if (firstEnd > 0 && text.codeUnitAt(firstEnd - 1) == 0x0D) {
      text = text.replaceAll('\r\n', '\n');
    }
    // The header is split into lines. The node lines, nearly all `style` on
    // the largest baselines, are read field by field in place (A10: splitting
    // them into lines and fields was most of the parse time).
    final int nodesAt = text.indexOf('\nnodes\n');
    if (nodesAt < 0) {
      throw const FormatException('No nodes line');
    }
    final List<String> lines = text.substring(0, nodesAt + 7).split('\n');
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
    // Lines first, as (depth, fields, children); nodes are built bottom-up
    // afterwards, so each subtree hash is computed once, from content, and
    // checked against the one stored.
    final stack = <_ParsedLine>[];
    _ParsedLine? root;
    final order = <_ParsedLine>[];
    var at = nodesAt + 7;
    while (at < text.length && text.codeUnitAt(at) != 0x0A) {
      var spaces = 0;
      while (at + spaces < text.length && text.codeUnitAt(at + spaces) == 0x20) {
        spaces++;
      }
      final parsed = _ParsedLine(spaces ~/ 2, <int>[]);
      at = _readFields(text, at + spaces, parsed.fields);
      order.add(parsed);
      while (stack.isNotEmpty && stack.last.depth >= parsed.depth) {
        stack.removeLast();
      }
      if (stack.isEmpty) {
        root = parsed;
      } else {
        stack.last.children.add(parsed);
      }
      stack.add(parsed);
    }
    for (final _ParsedLine n in order.reversed) {
      n.node = SnapshotNode._fromFields(text, n.fields, <SnapshotNode>[
        for (final _ParsedLine c in n.children) c.node!,
      ]);
    }
    final snapshot = Snapshot(
      id: id,
      inputs: inputs,
      toolchain: toolchain,
      coverage: Coverage(limits: limits, opaqueNodes: opaque),
      root: root!.node!,
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
    required this.flat,
    required this.type,
    required String this._style,
    this.shape = '-',
    required this.children,
  }) : _source = null,
       _styleStart = 0,
       _styleEnd = 0,
       subtreeHash = _subtreeHash(id, bounds, paint, semantics, opaque, flat, children);

  /// A node read from a baseline, whose style stays in [source] until it is
  /// asked for: a hash check never reads it, and on the largest baselines it
  /// is most of the text (A10).
  SnapshotNode._read({
    required this.id,
    required this.bounds,
    required this.paint,
    required this.semantics,
    required this.opaque,
    required this.flat,
    required this.type,
    required String this._source,
    required this._styleStart,
    required this._styleEnd,
    required this.shape,
    required this.children,
  }) : subtreeHash = _subtreeHash(id, bounds, paint, semantics, opaque, flat, children);

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

  /// SHA-256 of the subtree's output with component boundaries removed: the
  /// paint commands of this component and every component inside it, written
  /// as if they were one component, and their semantics nodes in semantics
  /// tree order. Equal on both sides when a refactor changed the widget
  /// structure but not the output (A5).
  final String flat;

  /// Explanation: widget class and the package it comes from.
  final String type;

  /// Explanation: resolved visual properties, canonical JSON.
  String get style => _style ??= _source!.substring(_styleStart, _styleEnd);

  String? _style;
  final String? _source;
  final int _styleStart;
  final int _styleEnd;

  /// Explanation: SHA-256 of the paint commands with every child's placement
  /// left out. Equal on both sides when the paint changed only because
  /// children inside the component moved, so the diff can say so instead of
  /// reporting unexplained paint. `-` in files written before Phase 3.
  final String shape;

  final List<SnapshotNode> children;

  /// SHA-256 over the detection fields and the children's subtree hashes.
  final String subtreeHash;

  String get detectionText => _detection(id, bounds, paint, semantics, opaque, flat);

  String get line => <String>[
    jsonEncode(id),
    'bounds=$bounds',
    'paint=$paint',
    'sem=$semantics',
    'opaque=$opaque',
    'flat=$flat',
    'type=${jsonEncode(type)}',
    'style=$style',
    // Optional: left out when unknown, so files written before it stay
    // canonical.
    if (shape != '-') 'shape=$shape',
    'sub=$subtreeHash',
  ].join('\t');

  static String _detection(String id, String bounds, String paint, String semantics, String opaque, String flat) =>
      <String>[jsonEncode(id), bounds, paint, semantics, opaque, flat].join('\t');

  static String _subtreeHash(
    String id,
    String bounds,
    String paint,
    String semantics,
    String opaque,
    String flat,
    List<SnapshotNode> children,
  ) => sha256
      .convert(
        utf8.encode(
          <String>[
            _detection(id, bounds, paint, semantics, opaque, flat),
            for (final SnapshotNode c in children) c.subtreeHash,
          ].join('\n'),
        ),
      )
      .toString();

  /// The node whose line's tab-separated fields are at [fields] in [text],
  /// as start and end offsets, with [children] already built. Throws if the
  /// stored subtree hash is not the one its content gives.
  static SnapshotNode _fromFields(String text, List<int> fields, List<SnapshotNode> children) {
    final int count = fields.length ~/ 2;
    String value(int i, String name) {
      if (i >= count || !text.startsWith('$name=', fields[2 * i])) {
        throw FormatException('Expected $name in: ${text.substring(fields.first, fields.last)}');
      }
      return text.substring(fields[2 * i] + name.length + 1, fields[2 * i + 1]);
    }

    if (count < 8 || !text.startsWith('style=', fields[14])) {
      throw FormatException('Expected style in: ${text.substring(fields.first, fields.last)}');
    }
    final node = SnapshotNode._read(
      id: jsonDecode(text.substring(fields[0], fields[1])) as String,
      bounds: value(1, 'bounds'),
      paint: value(2, 'paint'),
      semantics: value(3, 'sem'),
      opaque: value(4, 'opaque'),
      flat: value(5, 'flat'),
      type: jsonDecode(value(6, 'type')) as String,
      source: text,
      styleStart: fields[14] + 6,
      styleEnd: fields[15],
      shape: count > 9 ? value(8, 'shape') : '-',
      children: children,
    );
    if (node.subtreeHash != value(count > 9 ? 9 : 8, 'sub')) {
      throw FormatException('Subtree hash does not match content for ${node.id}');
    }
    return node;
  }
}

/// Adds the start and end offsets of each tab-separated field of the node
/// line that starts at [start], after its indentation, to [fields], and
/// returns where the next line starts. Nothing is copied: a field is read
/// once, when the node is built. `sub`, the subtree hash, is always the last
/// field, so the line ends with it; no field holds a raw tab or line break,
/// since free text is JSON.
int _readFields(String text, int start, List<int> fields) {
  var at = start;
  while (!text.startsWith('sub=', at)) {
    final int tab = text.indexOf('\t', at);
    if (tab < 0 || fields.length > 18) {
      throw FormatException('No subtree hash on the node line at offset $start');
    }
    fields
      ..add(at)
      ..add(tab);
    at = tab + 1;
  }
  int end = text.indexOf('\n', at);
  if (end < 0) {
    end = text.length;
  }
  fields
    ..add(at)
    ..add(end);
  return end + 1;
}

/// A node line read but not yet built, while [Snapshot.parse] collects its
/// children.
class _ParsedLine {
  _ParsedLine(this.depth, this.fields);

  final int depth;

  /// Start and end offsets of each field, from [_readFields].
  final List<int> fields;
  final List<_ParsedLine> children = <_ParsedLine>[];
  SnapshotNode? node;
}
