// Typed changes and the change report (spec: Diff engine, "Change types" and
// "Report shape").

import 'diff.dart';
import 'summary.dart';

/// The spec's change types.
enum ChangeType {
  /// A component appears.
  added('Added'),

  /// A component disappears.
  removed('Removed'),

  /// The same component under a different parent.
  moved('Moved'),

  /// The same component at a different position among its siblings.
  reordered('Reordered'),

  /// The same output under a different id. Info only.
  identity('Identity'),

  /// Bounds changed.
  layout('Layout'),

  /// A resolved style property changed together with paint.
  style('Style'),

  /// Text or image changed.
  content('Content'),

  /// Label, role, flag or action changed.
  semantics('Semantics'),

  /// The paint hash changed with no named cause.
  paint('Paint');

  const ChangeType(this.label);

  final String label;

  bool get isInfo => this == identity;
}

/// One typed difference on one component.
class Change {
  Change(
    this.type,
    this.after,
    this.before,
    this.detail, {
    this.presenceOnly = false,
    this.ownLayoutChanged = false,
    this.lead = '',
    this.fields = const <String, String>{},
    this.contentMoved = false,
  });

  /// A layout change in which nothing the component draws changed, but
  /// framework children inside it moved: its paint differs only in where
  /// children are placed (the node's `shape` is equal on both sides).
  final bool contentMoved;

  /// For [contentMoved] with more than one child that could have moved them:
  /// those children's changes. Empty when there is one, which is then
  /// [causedBy], or none.
  List<Change> possibleCauses = <Change>[];

  /// The changed properties [detail] lists, each "old -> new"; empty when it
  /// lists none.
  final Map<String, String> fields;

  /// The words in [detail] before [fields], such as `inside: `.
  final String lead;

  /// [detail] as the report writes it: see summary.dart.
  String get summary => summaryLines.join('; ');

  /// [summary] as one entry per distinct change, the first with [lead].
  List<String> get summaryLines {
    if (fields.isEmpty) {
      return <String>[shortenValue(detail)];
    }
    final List<String> entries = summarizeFieldList(fields);
    return <String>['$lead${entries.first}', ...entries.skip(1)];
  }

  /// A layout change in which a property that sizes or places children
  /// changed on this component (`Padding.padding`), not only its size.
  final bool ownLayoutChanged;

  /// A style or layout change in which every property only appeared or
  /// disappeared: render objects were added to or removed from this
  /// component, as a child added beside them brings its own wrappers.
  final bool presenceOnly;

  final ChangeType type;

  /// The node in the capture; null when removed.
  final DiffNode? after;

  /// The node in the baseline; null when added.
  final DiffNode? before;

  /// What changed, in words: bounds, style properties, semantics values.
  final String detail;

  DiffNode get node => after ?? before!;

  /// The full id, on the side where the component exists.
  String get nodeId => node.fullId;

  String get componentType => node.typeName;

  /// Set when this change is a consequence of another (cascade grouping).
  Change? causedBy;

  /// Set when this change is a consequence of a shift group that has no
  /// single cause: a list item the shift moved into or out of the painted
  /// area.
  ShiftGroup? withShift;

  /// On a list item that is built but not painted on one side, or inside
  /// one: it moved into or out of the painted area.
  bool atRangeEdge = false;

  /// The change at the end of [causedBy].
  Change get root {
    Change c = this;
    while (c.causedBy != null) {
      c = c.causedBy!;
    }
    return c;
  }

  @override
  String toString() => '${type.label} $nodeId: $detail';
}

/// Components under one ancestor whose size and paint are unchanged and whose
/// position moved by the same vector.
class ShiftGroup {
  ShiftGroup(this.ancestor, this.dx, this.dy, this.members, this.componentCount);

  /// The parent, in the capture, of the group's top-most members.
  final DiffNode ancestor;
  final double dx;
  final double dy;

  /// Top-most moved components, in the capture.
  final List<DiffNode> members;

  /// Members plus the components inside them that moved with them.
  final int componentCount;

  /// The candidate causes, one change per candidate component.
  List<Change> candidates = <Change>[];

  /// The single root cause: the one candidate, or the first of several
  /// that are the same change on copies of one component (Sagar,
  /// 2026-10-10: those count as one cause).
  Change? get cause => candidates.length == 1 || sameChange(candidates) ? candidates.first : null;

  String get vectorText => describeVector(dx, dy);

  String get summary => '${componentCount == 1 ? '1 component' : '$componentCount components'} shifted $vectorText';
}

/// "down 64 px", "left 10 px", or "by (10, 10) px".
String describeVector(double dx, double dy) {
  String n(double v) => v == v.roundToDouble() ? v.abs().toInt().toString() : v.abs().toString();
  if (dx == 0) {
    return '${dy > 0 ? 'down' : 'up'} ${n(dy)} px';
  }
  if (dy == 0) {
    return '${dx > 0 ? 'right' : 'left'} ${n(dx)} px';
  }
  String s(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  return 'by (${s(dx)}, ${s(dy)}) px';
}

/// A line of the report: a change that is not a consequence of another, or a
/// shift group without a single root cause.
class ReportItem {
  ReportItem.change(Change this.change, {this.flagged = false}) : group = null;

  ReportItem.group(ShiftGroup this.group) : change = null, flagged = group.candidates.isEmpty;

  final Change? change;
  final ShiftGroup? group;

  /// Unexplained paint, or a shift of unknown cause: listed first.
  final bool flagged;

  /// Changes folded under this one, and shift groups it caused.
  final List<Change> consequences = <Change>[];
  final List<ShiftGroup> causedGroups = <ShiftGroup>[];

  bool get isInfo => change != null && change!.type.isInfo && consequences.isEmpty && causedGroups.isEmpty;

  /// For ordering: the node's layout order on its side.
  int get order => change?.node.order ?? group!.members.first.order;
}

/// What differs between a baseline and a capture.
class ChangeReport {
  ChangeReport._(
    this.snapshotId,
    this.kind, {
    this.beforeToolchain,
    this.afterToolchain,
    this.beforeRoot,
    this.afterRoot,
  });

  ChangeReport.equal(String snapshotId) : this._(snapshotId, ReportKind.equal);

  ChangeReport.migration(
    String snapshotId,
    Map<String, String> before,
    Map<String, String> after, {
    String? beforeRoot,
    String? afterRoot,
  }) : this._(
         snapshotId,
         ReportKind.migration,
         beforeToolchain: before,
         afterToolchain: after,
         beforeRoot: beforeRoot,
         afterRoot: afterRoot,
       );

  ChangeReport.diff(this.snapshotId, this.changes, this.groups, this.items, this.inputChanges)
    : kind = ReportKind.diff,
      beforeToolchain = null,
      afterToolchain = null,
      beforeRoot = null,
      afterRoot = null;

  final String snapshotId;
  final ReportKind kind;
  final Map<String, String>? beforeToolchain;
  final Map<String, String>? afterToolchain;

  /// For a migration: the two baselines' root hashes, which a pixel proof
  /// must name.
  final String? beforeRoot;
  final String? afterRoot;

  /// Every change found, including consequences.
  List<Change> changes = <Change>[];

  List<ShiftGroup> groups = <ShiftGroup>[];

  /// Top-level lines, flagged ones first, then in layout order.
  List<ReportItem> items = <ReportItem>[];

  /// Declared inputs that differ (theme, locale, state, dynamic components).
  List<String> inputChanges = <String>[];

  /// Components declared dynamic whose content changed and, as declared, was
  /// not compared.
  List<String> skippedContent = <String>[];

  /// No change at all.
  bool get isEqual => kind == ReportKind.equal || (kind == ReportKind.diff && items.isEmpty && inputChanges.isEmpty);

  /// Every top-level item is info-level.
  bool get infoOnly => kind == ReportKind.diff && inputChanges.isEmpty && items.every((ReportItem i) => i.isInfo);

  /// Paint changes with no named cause, and shifts with no candidate cause.
  int get unexplainedCount => items.where((ReportItem i) => i.flagged).length;
}

enum ReportKind {
  /// The snapshots are identical.
  equal,

  /// The toolchain fingerprints differ: routed to migration, not compared.
  migration,

  /// Compared; see the items.
  diff,
}

/// Whether [changes] are more than one change and all the same change on
/// copies of one component: the same type, component type and detail. One
/// edit to a shared widget (a padding in every SectionHeader) makes such
/// copies, so as candidate causes they count as one.
bool sameChange(Iterable<Change> changes) {
  final List<Change> cs = changes.toList();
  if (cs.length < 2) {
    return false;
  }
  final Change first = cs.first;
  return cs.every(
    (Change c) => c.type == first.type && c.componentType == first.componentType && c.detail == first.detail,
  );
}
