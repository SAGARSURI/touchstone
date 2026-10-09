// The diff engine (spec: Diff engine and cascade attribution).
//
// Compares two snapshots from the root down, skips every equal subtree, and
// reports each remaining difference as a typed change:
//
// 1. Toolchain check: a fingerprint mismatch goes to migration, never to a
//    diff.
// 2. Root hash: equal hashes pass with no further work.
// 3. Descend: children are matched by id. Siblings whose ordinal ids changed
//    only because a sibling was added or removed are matched by content, and
//    siblings whose order changed are reported as reordered.
// 4. Second matching pass: unmatched nodes on both sides are paired by type,
//    bounds and paint hash (A5).
// 5. Classify each matched pair by the detection fields that differ, using
//    the explanation fields to name the cause.
// 6. Group cascades (cascade.dart).
// 7. Label the rest: a paint change with no named cause is unexplained.
//
// Pure Dart: no Flutter import, so the review command runs on the Dart VM.

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../snapshot/snapshot.dart';
import 'cascade.dart';
import 'changes.dart';

/// Semantics keys that describe where a node is, not what it is. A change
/// in only these follows from a layout change and is not reported on its
/// own when bounds changed in the same subtree.
const Set<String> _semanticsGeometry = <String>{
  'rect',
  'transform',
  'scrollPosition',
  'scrollExtentMin',
  'scrollExtentMax',
  'scrollIndex',
  'scrollChildCount',
};

/// Semantics keys that carry the node's text.
const Set<String> _semanticsText = <String>{'label', 'value'};

/// Style keys whose change is a content change rather than a style change.
bool _isContentStyleKey(String key) => key.startsWith('RenderImage.image');

/// The input key that lists components declared dynamic in the test.
const String dynamicInputKey = 'dynamic';

/// Compares [before] (the baseline) with [after] (the capture).
ChangeReport diffSnapshots(Snapshot before, Snapshot after) {
  if (before.toolchain.toString() != after.toolchain.toString()) {
    return ChangeReport.migration(after.id, before.toolchain, after.toolchain);
  }
  if (before.rootHash == after.rootHash && before.inputs.toString() == after.inputs.toString()) {
    return ChangeReport.equal(after.id);
  }
  return _Diff(before, after).run();
}

class _Diff {
  _Diff(this.beforeSnapshot, this.afterSnapshot)
    : before = DiffNode.tree(beforeSnapshot.root, isBefore: true),
      after = DiffNode.tree(afterSnapshot.root, isBefore: false);

  final Snapshot beforeSnapshot;
  final Snapshot afterSnapshot;
  final DiffNode before;
  final DiffNode after;

  /// How each pair was matched, by after node.
  final Map<DiffNode, _Match> _how = <DiffNode, _Match>{};

  ChangeReport run() {
    _pair(before, after, _Match.id);
    _matchChildren(before, after);
    _secondPass();
    final Set<String> dynamicNames = <String>{
      for (final String s in (afterSnapshot.inputs[dynamicInputKey] ?? '').split(','))
        if (s.isNotEmpty) s,
    };
    final changes = <Change>[];
    for (final DiffNode a in after.walk()) {
      final DiffNode? b = a.match;
      if (b == null) {
        if (a.parent?.match != null || a.parent == null) {
          changes.add(Change(ChangeType.added, a, null, 'at ${a.boundsText}${_descendantNote(a)}'));
        }
        continue;
      }
      changes.addAll(_classify(b, a, dynamic: _isDynamic(a, dynamicNames)));
    }
    for (final DiffNode b in before.walk()) {
      if (b.match == null && (b.parent?.match != null || b.parent == null)) {
        changes.add(Change(ChangeType.removed, null, b, 'was at ${b.boundsText}${_descendantNote(b)}'));
      }
    }
    final List<String> inputs = <String>[
      for (final String k in <String>{...beforeSnapshot.inputs.keys, ...afterSnapshot.inputs.keys})
        if (beforeSnapshot.inputs[k] != afterSnapshot.inputs[k])
          '$k: ${beforeSnapshot.inputs[k] ?? '(none)'} -> ${afterSnapshot.inputs[k] ?? '(none)'}',
    ];
    return groupCascades(afterSnapshot.id, before, after, changes, inputChanges: inputs);
  }

  bool _isDynamic(DiffNode a, Set<String> names) =>
      names.contains(a.typeName) || names.contains(a.segment) || names.contains(a.fullId);

  String _descendantNote(DiffNode n) {
    final int count = n.walk().length - 1;
    return count == 0 ? '' : ', with ${count == 1 ? '1 component' : '$count components'} inside';
  }

  void _pair(DiffNode b, DiffNode a, _Match how) {
    b.match = a;
    a.match = b;
    _how[a] = how;
  }

  /// Pairs the children of a matched pair, then descends into each pair.
  void _matchChildren(DiffNode b, DiffNode a) {
    if (b.node.subtreeHash == a.node.subtreeHash) {
      _pairEqual(b, a);
      return;
    }
    final Map<String, DiffNode> afterById = <String, DiffNode>{for (final DiffNode c in a.children) c.segment: c};
    final idPairs = <DiffNode, DiffNode>{};
    for (final DiffNode c in b.children) {
      final DiffNode? m = afterById[c.segment];
      if (m != null) {
        idPairs[c] = m;
      }
    }
    // Loose: unmatched, or matched by id with different content. A loose
    // node whose position-free content equals exactly one loose node of the
    // same type on the other side is paired with it instead. This keeps an
    // insertion from renumbering every later sibling into a content change,
    // and finds reorders.
    final Set<DiffNode> looseBefore = <DiffNode>{
      for (final DiffNode c in b.children)
        if (idPairs[c] == null || idPairs[c]!.shapeKey != c.shapeKey) c,
    };
    final Set<DiffNode> looseAfter = <DiffNode>{
      for (final DiffNode c in a.children)
        if (!idPairs.containsValue(c) || idPairs.entries.any((e) => e.value == c && e.key.shapeKey != c.shapeKey)) c,
    };
    final Map<String, List<DiffNode>> byShapeAfter = <String, List<DiffNode>>{};
    for (final DiffNode c in looseAfter) {
      (byShapeAfter['${c.typeName}\n${c.shapeKey}'] ??= <DiffNode>[]).add(c);
    }
    final Map<String, List<DiffNode>> byShapeBefore = <String, List<DiffNode>>{};
    for (final DiffNode c in looseBefore) {
      (byShapeBefore['${c.typeName}\n${c.shapeKey}'] ??= <DiffNode>[]).add(c);
    }
    final contentPairs = <DiffNode, DiffNode>{};
    for (final MapEntry<String, List<DiffNode>> e in byShapeBefore.entries) {
      final List<DiffNode>? others = byShapeAfter[e.key];
      if (e.value.length == 1 && others != null && others.length == 1) {
        contentPairs[e.value.single] = others.single;
      }
    }
    final pairs = <DiffNode, DiffNode>{};
    final Set<DiffNode> taken = contentPairs.values.toSet();
    for (final DiffNode c in b.children) {
      if (contentPairs[c] case final DiffNode m) {
        pairs[c] = m;
      } else if (idPairs[c] case final DiffNode m when !taken.contains(m)) {
        pairs[c] = m;
      }
    }
    // Reordered: pairs outside the longest run that keeps sibling order.
    final List<DiffNode> ordered = <DiffNode>[
      for (final DiffNode c in b.children)
        if (pairs.containsKey(c)) c,
    ];
    final Set<DiffNode> inOrder = _longestInOrder(ordered, (DiffNode c) => a.children.indexOf(pairs[c]!)).toSet();
    for (final MapEntry<DiffNode, DiffNode> e in pairs.entries) {
      final _Match how = !inOrder.contains(e.key)
          ? _Match.reordered
          : (e.key.segment == e.value.segment || (e.key.isOrdinal && e.value.isOrdinal))
          ? _Match.id
          : _Match.identity;
      _pair(e.key, e.value, how);
    }
    for (final MapEntry<DiffNode, DiffNode> e in pairs.entries) {
      _matchChildren(e.key, e.value);
    }
  }

  void _pairEqual(DiffNode b, DiffNode a) {
    for (var i = 0; i < b.children.length; i++) {
      _pair(b.children[i], a.children[i], _Match.id);
      _pairEqual(b.children[i], a.children[i]);
    }
  }

  /// The second matching pass (spec, A5): pairs unmatched nodes on both sides
  /// by type, bounds and paint hash, wherever they are in the tree.
  void _secondPass() {
    while (true) {
      String key(DiffNode n) => '${n.typeName}\n${n.node.bounds}\n${n.node.paint}';
      final Map<String, List<DiffNode>> b = <String, List<DiffNode>>{};
      for (final DiffNode n in before.walk()) {
        if (n.match == null) {
          (b[key(n)] ??= <DiffNode>[]).add(n);
        }
      }
      final Map<String, List<DiffNode>> a = <String, List<DiffNode>>{};
      for (final DiffNode n in after.walk()) {
        if (n.match == null) {
          (a[key(n)] ??= <DiffNode>[]).add(n);
        }
      }
      var paired = false;
      for (final MapEntry<String, List<DiffNode>> e in b.entries) {
        final List<DiffNode>? others = a[e.key];
        if (e.value.length != 1 || others == null || others.length != 1) {
          continue;
        }
        final DiffNode bn = e.value.single;
        final DiffNode an = others.single;
        final bool sameParent = bn.parent?.match == an.parent && an.parent != null;
        _pair(bn, an, sameParent ? _Match.identity : _Match.moved);
        _matchChildren(bn, an);
        paired = true;
      }
      if (!paired) {
        return;
      }
    }
  }

  List<Change> _classify(DiffNode b, DiffNode a, {required bool dynamic}) {
    final out = <Change>[];
    final _Match how = _how[a]!;
    if (how == _Match.moved) {
      out.add(Change(ChangeType.moved, a, b, 'from ${b.parent?.fullId ?? '-'} to ${a.parent?.fullId ?? '-'}'));
    } else if (how == _Match.reordered) {
      out.add(
        Change(
          ChangeType.reordered,
          a,
          b,
          'position ${b.parent!.children.indexOf(b) + 1} -> ${a.parent!.children.indexOf(a) + 1} among siblings',
        ),
      );
    } else if (how == _Match.identity) {
      out.add(Change(ChangeType.identity, a, b, 'id ${b.segment} -> ${a.segment}'));
    }
    if (b.node.line.split('\tsub=').first == a.node.line.split('\tsub=').first ||
        (b.node.detectionText.split('\t').skip(1).join('\t') == a.node.detectionText.split('\t').skip(1).join('\t') &&
            b.node.style == a.node.style)) {
      return out;
    }
    final Bounds? bb = b.bounds;
    final Bounds? ab = a.bounds;
    final bool sizeChanged = bb?.w != ab?.w || bb?.h != ab?.h;
    final bool paintChanged = b.node.paint != a.node.paint || b.node.opaque != a.node.opaque;
    final Map<String, String> styleChanges = _mapChanges(_style(b.node.style), _style(a.node.style));
    final Map<String, String> semanticsChanges = _semanticsChanges(b.node.semantics, a.node.semantics);
    final bool textChanged = semanticsChanges.keys.any(_semanticsText.contains);
    final bool otherSemantics = semanticsChanges.keys.any((String k) => !_semanticsText.contains(k));

    Change? layout;
    if (sizeChanged) {
      out.add(layout = Change(ChangeType.layout, a, b, 'size ${bb?.sizeText ?? '-'} -> ${ab?.sizeText ?? '-'}'));
    }
    if (paintChanged) {
      final bool contentStyle = styleChanges.isNotEmpty && styleChanges.keys.every(_isContentStyleKey);
      if (styleChanges.isNotEmpty && !contentStyle) {
        out.add(Change(ChangeType.style, a, b, _describeMap(styleChanges)));
      } else if (contentStyle || textChanged) {
        if (!dynamic) {
          final Map<String, String> content = <String, String>{
            ...styleChanges,
            for (final MapEntry<String, String> e in semanticsChanges.entries)
              if (_semanticsText.contains(e.key)) e.key: e.value,
          };
          out.add(Change(ChangeType.content, a, b, _describeMap(content)));
        }
      } else if (layout != null && b.node.opaque == a.node.opaque) {
        // A box painted at its new size: the paint follows the layout change.
        out.add(Change(ChangeType.paint, a, b, 'paint changed with the new size')..causedBy = layout);
      } else if (b.node.opaque != a.node.opaque) {
        out.add(Change(ChangeType.paint, a, b, 'unexplained (opaque reasons ${b.node.opaque} -> ${a.node.opaque})'));
      } else {
        out.add(
          Change(
            ChangeType.paint,
            a,
            b,
            a.node.opaque == '-' ? 'unexplained (paint commands changed)' : 'unexplained (pixel hash changed)',
          ),
        );
      }
    }
    if (otherSemantics || (textChanged && !paintChanged)) {
      final Map<String, String> sem = <String, String>{
        for (final MapEntry<String, String> e in semanticsChanges.entries)
          if (!paintChanged || !_semanticsText.contains(e.key)) e.key: e.value,
      };
      if (sem.isNotEmpty) {
        out.add(Change(ChangeType.semantics, a, b, _describeMap(sem)));
      }
    }
    final bool geometryOnly = semanticsChanges.isEmpty && b.node.semantics != a.node.semantics && !_layoutChanged;
    if (geometryOnly && out.every((Change c) => c.type.isInfo)) {
      out.add(Change(ChangeType.semantics, a, b, 'geometry: rect, transform or scroll extent changed'));
    }
    return out;
  }

  /// Whether any node was added, removed or changed bounds. A semantics change
  /// in geometry alone is reported only when nothing moved anywhere.
  late final bool _layoutChanged =
      after.walk().any((DiffNode n) => n.match == null || n.match!.node.bounds != n.node.bounds) ||
      before.walk().any((DiffNode n) => n.match == null);
}

enum _Match { id, reordered, identity, moved }

/// The longest subsequence of [items] whose [index] increases.
List<T> _longestInOrder<T>(List<T> items, int Function(T) index) {
  if (items.isEmpty) {
    return <T>[];
  }
  final List<int> keys = items.map(index).toList();
  final List<int> length = List<int>.filled(items.length, 1);
  final List<int> previous = List<int>.filled(items.length, -1);
  for (var i = 0; i < items.length; i++) {
    for (var j = 0; j < i; j++) {
      if (keys[j] < keys[i] && length[j] + 1 > length[i]) {
        length[i] = length[j] + 1;
        previous[i] = j;
      }
    }
  }
  var best = 0;
  for (var i = 1; i < items.length; i++) {
    if (length[i] > length[best]) {
      best = i;
    }
  }
  final out = <T>[];
  for (int i = best; i >= 0; i = previous[i]) {
    out.add(items[i]);
  }
  return out.reversed.toList();
}

Map<String, String> _style(String json) {
  final Object? decoded = jsonDecode(json);
  if (decoded is! Map) {
    return <String, String>{};
  }
  return <String, String>{for (final MapEntry<Object?, Object?> e in decoded.entries) '${e.key}': '${e.value}'};
}

/// Keys whose value differs, mapped to "old -> new".
Map<String, String> _mapChanges(Map<String, String> before, Map<String, String> after) => <String, String>{
  for (final String k in <String>{...before.keys, ...after.keys})
    if (before[k] != after[k]) k: '${before[k] ?? '(none)'} -> ${after[k] ?? '(none)'}',
};

String _describeMap(Map<String, String> m) => m.entries.map((e) => '${e.key}: ${e.value}').join('; ');

/// Differences in what the semantics nodes say, ignoring where they are.
/// Keys are semantics property names; nodes are compared in order.
Map<String, String> _semanticsChanges(String before, String after) {
  if (before == after) {
    return <String, String>{};
  }
  List<Map<String, Object?>> parse(String s) => <Map<String, Object?>>[
    for (final Object? n in (jsonDecode(s) as List<Object?>)) (n! as Map<String, Object?>),
  ];
  Map<String, Object?> meaning(Map<String, Object?> n) => <String, Object?>{
    for (final MapEntry<String, Object?> e in n.entries)
      if (!_semanticsGeometry.contains(e.key)) e.key: e.value,
  };
  final List<Map<String, Object?>> b = parse(before).map(meaning).where((m) => m.isNotEmpty).toList();
  final List<Map<String, Object?>> a = parse(after).map(meaning).where((m) => m.isNotEmpty).toList();
  if (jsonEncode(b) == jsonEncode(a)) {
    return <String, String>{};
  }
  final out = <String, String>{};
  if (b.length != a.length) {
    out['nodes'] = '${b.length} -> ${a.length} semantics nodes';
  }
  for (var i = 0; i < b.length && i < a.length; i++) {
    for (final String k in <String>{...b[i].keys, ...a[i].keys}) {
      final String bv = b[i].containsKey(k) ? jsonEncode(b[i][k]) : '(none)';
      final String av = a[i].containsKey(k) ? jsonEncode(a[i][k]) : '(none)';
      if (bv != av) {
        out[k] = out.containsKey(k) ? '${out[k]}, $bv -> $av' : '$bv -> $av';
      }
    }
  }
  if (out.isEmpty) {
    // Same nodes, different order or count after dropping empty ones.
    out['nodes'] = 'semantics nodes changed';
  }
  return out;
}

/// Global bounds of a node.
class Bounds {
  const Bounds(this.x, this.y, this.w, this.h);

  static Bounds? parse(String s) {
    if (s == '-') {
      return null;
    }
    final List<double> v = s.split(',').map(double.parse).toList();
    return Bounds(v[0], v[1], v[2], v[3]);
  }

  final double x;
  final double y;
  final double w;
  final double h;

  String get sizeText => '${_n(w)}x${_n(h)}';

  @override
  String toString() => '${_n(x)},${_n(y)},${_n(w)},${_n(h)}';
}

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// A snapshot node with its place in the tree, for the diff.
class DiffNode {
  DiffNode._(this.node, this.fullId, this.parent, this.isBefore);

  /// Builds the tree under [root] and numbers it in depth-first order.
  factory DiffNode.tree(SnapshotNode root, {required bool isBefore}) {
    var order = 0;
    DiffNode build(SnapshotNode n, DiffNode? parent) {
      final d = DiffNode._(n, parent == null ? n.id : '${parent.fullId}/${n.id}', parent, isBefore)..order = order++;
      for (final SnapshotNode c in n.children) {
        d.children.add(build(c, d));
      }
      return d;
    }

    return build(root, null);
  }

  final SnapshotNode node;
  final String fullId;
  final DiffNode? parent;
  final bool isBefore;
  final List<DiffNode> children = <DiffNode>[];

  /// Depth-first position: layout order.
  late final int order;

  /// The node on the other side, once matched.
  DiffNode? match;

  String get segment => node.id;

  /// `Type` for `Type@n` and `Type#key`.
  String get typeName => node.type.split(' (').first;

  /// An id given by position among siblings, not by an explicit key.
  bool get isOrdinal => RegExp(r'@\d+$').hasMatch(segment);

  late final Bounds? bounds = Bounds.parse(node.bounds);

  String get boundsText => bounds?.toString() ?? '-';

  /// Depth-first, this node first.
  List<DiffNode> walk() => <DiffNode>[this, for (final DiffNode c in children) ...c.walk()];

  bool isUnder(DiffNode ancestor) {
    for (DiffNode? n = parent; n != null; n = n.parent) {
      if (identical(n, ancestor)) {
        return true;
      }
    }
    return false;
  }

  /// Position-free content: type, size, paint, what the semantics say, and
  /// the children with their offsets from this node. Equal keys mean the same
  /// subtree drawn somewhere else.
  late final String shapeKey = () {
    final out = StringBuffer()
      ..writeln(typeName)
      ..writeln(bounds?.sizeText ?? '-')
      ..writeln(node.paint)
      ..writeln(node.opaque)
      ..writeln(_semanticsWithoutPlace(node.semantics));
    for (final DiffNode c in children) {
      final Bounds? cb = c.bounds;
      final Bounds? b = bounds;
      out.writeln(cb == null || b == null ? '-' : '${cb.x - b.x},${cb.y - b.y}');
      out.writeln(c.shapeKey);
    }
    return sha256.convert(utf8.encode(out.toString())).toString();
  }();
}

String _semanticsWithoutPlace(String json) {
  final Object? decoded = jsonDecode(json);
  if (decoded is! List) {
    return json;
  }
  return jsonEncode(<Object?>[
    for (final Object? n in decoded)
      if (n is Map<String, Object?>)
        <String, Object?>{
          for (final MapEntry<String, Object?> e in n.entries)
            if (e.key != 'transform' && !e.key.startsWith('scroll')) e.key: e.value,
        },
  ]);
}
