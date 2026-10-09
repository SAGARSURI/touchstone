// Cascade attribution (spec: Diff engine, "Cascade attribution").
//
// A causal claim is made only when exactly one candidate cause exists.
//
// - Shift group: components under a common ancestor whose size and paint are
//   unchanged and whose position moved by the same vector. The ancestor is
//   the nearest one that did not itself move by that vector.
// - Candidate cause: a component earlier in layout order under that
//   ancestor, or the ancestor itself, that was added, removed, resized or
//   restyled. A reordered or moved component counts too, earlier on either
//   side, since it moves its siblings the way an insertion or removal does.
// - Upward growth: a parent whose size changed by the same amount as one
//   changed child is a consequence of that child.
//
// Additions, recorded in doc/phase2/diff.md. A parent's style or inside
// layout change in which properties only appeared or disappeared, beside one
// added or removed child, is that child's consequence. And a component whose only change
// is unexplained paint, and whose direct child components were added, removed,
// reordered, resized or shifted, has that paint change folded under the
// children's single root cause. A parent's own paint records where its
// framework children sit and which child components it paints, so those
// children moving changes it. The fold is labelled as not verified, because
// the paint is compared by hash.

import 'changes.dart';
import 'diff.dart';

/// The change types that make a component a candidate cause.
const Set<ChangeType> _causeTypes = <ChangeType>{
  ChangeType.added,
  ChangeType.removed,
  ChangeType.layout,
  ChangeType.style,
  ChangeType.reordered,
  ChangeType.moved,
};

/// Changes that leave a component's own output as it was.
const Set<ChangeType> _positionOnly = <ChangeType>{ChangeType.identity};

ChangeReport groupCascades(
  String snapshotId,
  DiffNode before,
  DiffNode after,
  List<Change> changes, {
  List<String> inputChanges = const <String>[],
}) {
  final Map<DiffNode, List<Change>> byNode = <DiffNode, List<Change>>{};
  for (final Change c in changes) {
    (byNode[c.node] ??= <Change>[]).add(c);
  }

  // Upward growth, deepest first so chains fold to their root.
  final List<Change> layouts = changes.where((Change c) => c.type == ChangeType.layout).toList()
    ..sort((Change x, Change y) => _depth(y.node).compareTo(_depth(x.node)));
  for (final Change parent in layouts) {
    final (double, double)? delta = _sizeDelta(parent);
    if (delta == null || delta == (0.0, 0.0)) {
      continue;
    }
    final List<Change> growing = <Change>[
      for (final DiffNode child in parent.node.children)
        for (final Change c in byNode[child] ?? const <Change>[])
          if (c.type == ChangeType.layout && _sizeDelta(c) == delta) c,
    ];
    if (growing.length == 1) {
      parent.causedBy = growing.single;
    }
  }

  // A parent's style, or layout inside it, where render objects only
  // appeared or disappeared, beside exactly one child component that was
  // added or removed: the child's wrappers (a keep-alive, a divider drawn per
  // child) came or went with it.
  for (final Change c in changes) {
    final bool sameSize = c.before?.bounds?.sizeText == c.after?.bounds?.sizeText;
    if (!c.presenceOnly ||
        c.after == null ||
        c.causedBy != null ||
        !(c.type == ChangeType.style || (c.type == ChangeType.layout && sameSize))) {
      continue;
    }
    final List<Change> structural = <Change>[
      for (final Change cc in changes)
        if ((cc.type == ChangeType.added && identical(cc.after!.parent, c.after)) ||
            (cc.type == ChangeType.removed && c.before != null && identical(cc.before!.parent, c.before)))
          cc,
    ];
    if (structural.length == 1) {
      c.causedBy = structural.single;
    }
  }

  // Shift groups.
  bool shifted(DiffNode a) {
    final DiffNode? b = a.match;
    if (b == null || a.bounds == null || b.bounds == null) {
      return false;
    }
    if (a.bounds!.w != b.bounds!.w || a.bounds!.h != b.bounds!.h) {
      return false;
    }
    if (a.bounds!.x == b.bounds!.x && a.bounds!.y == b.bounds!.y) {
      return false;
    }
    return (byNode[a] ?? const <Change>[]).every((Change c) => _positionOnly.contains(c.type));
  }

  (double, double) vector(DiffNode a) => (a.bounds!.x - a.match!.bounds!.x, a.bounds!.y - a.match!.bounds!.y);

  final Map<String, List<DiffNode>> topMost = <String, List<DiffNode>>{};
  final Map<String, DiffNode> ancestors = <String, DiffNode>{};
  for (final DiffNode a in after.walk()) {
    if (!shifted(a) || a.parent == null) {
      continue;
    }
    final (double, double) v = vector(a);
    if (shifted(a.parent!) && vector(a.parent!) == v) {
      continue;
    }
    // The common ancestor is the nearest one that did not move by the same
    // vector. A parent that moved with its children but changed in another
    // way (a row clipped at the viewport's edge) is not a member, and the
    // shift belongs to whatever moved it.
    DiffNode p = a.parent!;
    while (p.parent != null && _movedBy(p, v)) {
      p = p.parent!;
    }
    final key = '${p.fullId}\n${v.$1},${v.$2}';
    (topMost[key] ??= <DiffNode>[]).add(a);
    ancestors[key] = p;
  }
  final groups = <ShiftGroup>[];
  for (final MapEntry<String, List<DiffNode>> e in topMost.entries) {
    final (double, double) v = vector(e.value.first);
    var count = 0;
    for (final DiffNode m in e.value) {
      count += m.walk().where((DiffNode n) => shifted(n) && vector(n) == v).length;
    }
    groups.add(ShiftGroup(ancestors[e.key]!, v.$1, v.$2, e.value, count));
  }

  // Candidate causes for each group.
  for (final ShiftGroup g in groups) {
    final DiffNode p = g.ancestor;
    final DiffNode? pBefore = p.match;
    final int firstAfter = g.members.map((DiffNode m) => m.order).reduce((int x, int y) => x < y ? x : y);
    final int firstBefore = g.members.map((DiffNode m) => m.match!.order).reduce((int x, int y) => x < y ? x : y);
    bool insideMember(DiffNode n) => g.members.any((DiffNode m) => identical(n, m) || n.isUnder(m));
    bool insideMemberBefore(DiffNode n) => g.members.any((DiffNode m) => identical(n, m.match) || n.isUnder(m.match!));
    final Map<DiffNode, Change> candidateByNode = <DiffNode, Change>{};
    for (final Change c in changes) {
      if (!_causeTypes.contains(c.type)) {
        continue;
      }
      final bool eligible = c.type == ChangeType.removed
          ? pBefore != null &&
                c.before!.isUnder(pBefore) &&
                c.before!.order < firstBefore &&
                !insideMemberBefore(c.before!)
          : identical(c.after, p) ||
                (c.after!.isUnder(p) &&
                    !insideMember(c.after!) &&
                    (c.after!.order < firstAfter ||
                        // A reordered or moved component was earlier on the baseline's side.
                        (c.before != null &&
                            c.before!.order < firstBefore &&
                            pBefore != null &&
                            c.before!.isUnder(pBefore))));
      if (!eligible) {
        continue;
      }
      final Change root = c.root;
      candidateByNode.putIfAbsent(root.node, () => _primary(byNode[root.node] ?? <Change>[root]));
    }
    g.candidates = candidateByNode.values.toList();
  }

  // A parent's unexplained paint where its children moved or changed.
  for (final Change c in changes) {
    if (c.type != ChangeType.paint || c.after == null || c.causedBy != null) {
      continue;
    }
    final DiffNode x = c.after!;
    final roots = <DiffNode, Change>{};
    var childrenChanged = false;
    for (final DiffNode child in x.children) {
      for (final Change cc in byNode[child] ?? const <Change>[]) {
        if (cc.type == ChangeType.paint || cc.type == ChangeType.semantics || cc.type == ChangeType.content) {
          continue;
        }
        childrenChanged = true;
        roots.putIfAbsent(cc.root.node, () => cc.root);
      }
      if (shifted(child)) {
        childrenChanged = true;
      }
    }
    for (final Change cc in changes) {
      if (cc.type == ChangeType.removed && x.match != null && identical(cc.before!.parent, x.match)) {
        childrenChanged = true;
        roots.putIfAbsent(cc.before!, () => cc);
      }
    }
    for (final ShiftGroup g in groups) {
      if (identical(g.ancestor, x) || g.members.any((DiffNode m) => identical(m.parent, x))) {
        childrenChanged = true;
        if (g.cause case final Change cause) {
          roots.putIfAbsent(cause.root.node, () => cause.root);
        } else {
          roots[x] = c; // no single cause: keep it unexplained
        }
      }
    }
    if (childrenChanged && roots.length == 1 && !identical(roots.values.single, c)) {
      c.causedBy = roots.values.single;
    }
  }

  // Report items.
  final Map<Change, ReportItem> itemFor = <Change, ReportItem>{};
  final items = <ReportItem>[];
  for (final Change c in changes) {
    if (c.causedBy != null) {
      continue;
    }
    final item = ReportItem.change(c, flagged: c.type == ChangeType.paint);
    itemFor[c] = item;
    items.add(item);
  }
  for (final Change c in changes) {
    if (c.causedBy != null) {
      final Change root = c.root;
      (itemFor[root] ?? itemFor[_primary(byNode[root.node] ?? <Change>[root])])?.consequences.add(c);
    }
  }
  for (final ShiftGroup g in groups) {
    final Change? cause = g.cause;
    if (cause != null && itemFor[cause] != null) {
      itemFor[cause]!.causedGroups.add(g);
    } else {
      items.add(ReportItem.group(g));
    }
  }
  items.sort((ReportItem x, ReportItem y) {
    if (x.flagged != y.flagged) {
      return x.flagged ? -1 : 1;
    }
    return _sortOrder(x).compareTo(_sortOrder(y));
  });
  return ChangeReport.diff(snapshotId, changes, groups, items, inputChanges);
}

bool _movedBy(DiffNode n, (double, double) v) {
  final Bounds? a = n.bounds;
  final Bounds? b = n.match?.bounds;
  return a != null && b != null && (a.x - b.x, a.y - b.y) == v;
}

int _depth(DiffNode n) {
  var d = 0;
  for (DiffNode? p = n.parent; p != null; p = p.parent) {
    d++;
  }
  return d;
}

(double, double)? _sizeDelta(Change c) {
  final Bounds? a = c.after?.bounds;
  final Bounds? b = c.before?.bounds;
  if (a == null || b == null) {
    return null;
  }
  return (a.w - b.w, a.h - b.h);
}

/// The change that names a component as a cause: structure first, then
/// layout, then style.
Change _primary(List<Change> changes) {
  for (final ChangeType t in <ChangeType>[
    ChangeType.added,
    ChangeType.removed,
    ChangeType.moved,
    ChangeType.reordered,
    ChangeType.layout,
    ChangeType.style,
  ]) {
    for (final Change c in changes) {
      if (c.type == t) {
        return c;
      }
    }
  }
  return changes.first;
}

/// Layout order for sorting: removed components sort where they were, next to
/// the capture's components around them.
double _sortOrder(ReportItem i) {
  final Change? c = i.change;
  if (c == null) {
    return i.group!.members.first.order.toDouble();
  }
  if (c.after != null) {
    return c.after!.order.toDouble();
  }
  // A removed node: just after its parent's counterpart, or at its own order.
  final DiffNode? parent = c.before!.parent?.match;
  return parent == null ? c.before!.order.toDouble() : parent.order + 0.5;
}
