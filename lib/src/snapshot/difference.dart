// The first difference between two captures, named by node and likely
// cause (spec: Self-checks, "Determinism gate").

import 'snapshot.dart';

/// The first node whose canonical line differs between two captures.
class SnapshotDifference {
  SnapshotDifference(this.nodeId, this.fields, this.cause, this.before, this.after);

  /// Full node id, or the header field that differs.
  final String nodeId;

  /// Detection fields that differ.
  final List<String> fields;

  /// The likely cause, in words.
  final String cause;
  final String before;
  final String after;

  @override
  String toString() =>
      'first differing node: $nodeId (${fields.join(', ')}). Likely cause: $cause\n'
      '  capture 1: ${clipLine(before)}\n'
      '  capture 2: ${clipLine(after)}';
}

/// Shortens a canonical line for a failure message.
String clipLine(String s) => s.length > 400 ? '${s.substring(0, 400)}…' : s;

/// The first difference between two canonical snapshot texts.
SnapshotDifference firstDifference(String a, String b) {
  final Snapshot sa = Snapshot.parse(a);
  final Snapshot sb = Snapshot.parse(b);
  for (final String field in <String>['inputs', 'toolchain']) {
    final Map<String, String> fa = field == 'inputs' ? sa.inputs : sa.toolchain;
    final Map<String, String> fb = field == 'inputs' ? sb.inputs : sb.toolchain;
    if (fa.toString() != fb.toString()) {
      return SnapshotDifference(field, <String>[field], 'the $field changed between captures', '$fa', '$fb');
    }
  }
  final List<(String, SnapshotNode)> na = sa.walk().toList();
  final List<(String, SnapshotNode)> nb = sb.walk().toList();
  for (var i = 0; i < na.length && i < nb.length; i++) {
    final (String idA, SnapshotNode x) = na[i];
    final (String idB, SnapshotNode y) = nb[i];
    if (idA != idB) {
      return SnapshotDifference(idA, const <String>['tree'], 'the component tree changed', idA, idB);
    }
    final fields = <String>[
      if (x.bounds != y.bounds) 'bounds',
      if (x.paint != y.paint) 'paint',
      if (x.semantics != y.semantics) 'semantics',
      if (x.opaque != y.opaque) 'opaque',
      if (x.type != y.type) 'type',
      if (x.style != y.style) 'style',
    ];
    if (fields.isNotEmpty) {
      return SnapshotDifference(idA, fields, _cause(fields, x, y), x.line, y.line);
    }
  }
  if (na.length != nb.length) {
    return SnapshotDifference(
      na.length < nb.length ? nb[na.length].$1 : na[nb.length].$1,
      const <String>['tree'],
      'a component appeared or disappeared between captures',
      '${na.length} nodes',
      '${nb.length} nodes',
    );
  }
  return SnapshotDifference('-', const <String>['coverage'], 'the coverage section changed', a, b);
}

String _cause(List<String> fields, SnapshotNode x, SnapshotNode y) {
  if (fields.contains('opaque') || (x.opaque != '-' && fields.contains('paint'))) {
    return 'an opaque node\'s pixels changed: an image still loading, a shader reading time, or a platform view';
  }
  if (fields.contains('bounds')) {
    return 'layout changed between captures: content that depends on the clock, random values or an async load';
  }
  if (fields.contains('paint')) {
    return 'paint changed with the same layout: a colour, text or image that depends on the clock or random values';
  }
  if (fields.contains('semantics')) {
    return 'semantics changed: a label or value that depends on the clock or random values';
  }
  return 'an explanation field changed: a diagnostics property that is not deterministic';
}
