// The change report as text (spec: Diff engine, "Report shape"):
//
//   order_ticket/loading/dark    needs-review
//
//   1  Added   PromoBanner#promo       16,24,358,56
//              consequence: 6 components shifted down 64 px
//   2  Style   OrderButton#submit      background: brand.primary -> brand.accent
//   3  Paint   SparklineChart#spark    unexplained (pixel hash changed)
//
// Each item opens with a change's short wording (summary.dart); a change to
// several values lists each on its own line, under the first, and a value
// too long for one line breaks before its arrow, then between words. The
// same change on several instances of one component is one item, followed
// by an "at:" line naming every instance. When there are several items, a
// line under the verdict counts them by type, and a blank line separates
// the items (DX sessions, doc/phase3/dx_results.md).

import 'changes.dart';
import 'diff.dart';
import 'policy.dart';
import 'summary.dart';

/// The style changes that share a cause in more than one of [reports], keyed
/// by snapshot: one line per cause, such as a token whose value changed, with
/// how many components of each type it changed and in how many snapshots.
/// Empty when no cause spans two snapshots.
String renderCauses(Map<String, ChangeReport> reports) {
  final byCause = <String, List<(String, Change)>>{};
  for (final MapEntry<String, ChangeReport> r in reports.entries) {
    for (final Change c in r.value.changes) {
      if (c.type == ChangeType.style && c.fields.isNotEmpty) {
        (byCause[_cause(c.fields)] ??= <(String, Change)>[]).add((r.key, c));
      }
    }
  }
  final out = StringBuffer();
  for (final MapEntry<String, List<(String, Change)>> e in byCause.entries) {
    final int snapshots = <String>{for (final (String id, _) in e.value) id}.length;
    if (snapshots < 2) {
      continue;
    }
    final types = <String, int>{};
    for (final (_, Change c) in e.value) {
      types.update(c.node.typeName, (int n) => n + 1, ifAbsent: () => 1);
    }
    final String components =
        (types.entries.toList()..sort((MapEntry<String, int> x, MapEntry<String, int> y) {
              final int byCount = y.value.compareTo(x.value);
              return byCount != 0 ? byCount : x.key.compareTo(y.key);
            }))
            .map((MapEntry<String, int> t) => '${t.value} ${t.key}')
            .join(', ');
    out.write('  ${e.key}: style change on $components in $snapshots snapshots\n');
  }
  return out.isEmpty ? '' : 'Causes in more than one snapshot:\n$out';
}

final RegExp _tokenValue = RegExp(r'^[A-Za-z][\w.]* #[0-9A-F]{8} -> #[0-9A-F]{8}$');

/// A style change's cause: the tokens whose value changed, when it has any,
/// since the other fields that changed with them (a colour derived from the
/// token, a style object holding it) follow from them. Otherwise everything
/// that changed.
String _cause(Map<String, String> fields) {
  final String values = fieldValues(fields);
  final List<String> tokens = values.split('; ').where(_tokenValue.hasMatch).toList();
  return tokens.isEmpty ? values : tokens.join('; ');
}

/// Renders [report] with [decision]'s verdict on the first line.
String renderReport(ChangeReport report, Decision decision) {
  final out = StringBuffer('${report.snapshotId}    ${decision.verdict.label}\n');
  switch (report.kind) {
    case ReportKind.equal:
      out.write('\nNo changes.\n');
      return out.toString();
    case ReportKind.migration:
      out.write('\nRecorded with a different toolchain, so not compared (migration).\n');
      for (final String k in <String>{...report.beforeToolchain!.keys, ...report.afterToolchain!.keys}) {
        if (report.beforeToolchain![k] != report.afterToolchain![k]) {
          out.write('  $k: ${report.beforeToolchain![k] ?? '(none)'} -> ${report.afterToolchain![k] ?? '(none)'}\n');
        }
      }
      for (final String reason in decision.reasons.skip(1)) {
        out.write('${reason[0].toUpperCase()}${reason.substring(1)}.\n');
      }
      return out.toString();
    case ReportKind.diff:
      break;
  }
  final List<List<ReportItem>> folded = _folded(report.items);
  if (folded.length > 1) {
    final byType = <String, int>{};
    for (final List<ReportItem> same in folded) {
      byType.update(same.first.change?.type.label ?? 'Shift', (int k) => k + 1, ifAbsent: () => 1);
    }
    final String types = byType.entries.map((MapEntry<String, int> e) => '${e.value} ${e.key}').join(', ');
    out.writeln('${folded.length} items: $types');
  }
  out.writeln();
  for (final String input in report.inputChanges) {
    out.writeln('   Input   $input');
  }
  final _Names names = _Names(report);
  const indent = '           ';
  var n = 0;
  for (final List<ReportItem> same in folded) {
    if (n > 0) {
      out.writeln();
    }
    n++;
    final String number = '$n'.padRight(3);
    final ReportItem item = same.first;
    final Change? c = item.change;
    if (c != null) {
      final String where = same.length == 1 ? names.of(c.node) : '${c.componentType} in ${same.length} places';
      _writeValues(out, '$number${c.type.label.padRight(10)}${where.padRight(24)}  ', _values(c));
      if (same.length > 1) {
        out.writeln('${indent}at: ${same.map((ReportItem i) => names.of(i.change!.node)).join(', ')}');
      }
      for (final String line in _groupLines(<ShiftGroup>[for (final ReportItem i in same) ...i.causedGroups])) {
        out.writeln('${indent}consequence: $line');
      }
      final List<(Change, DiffNode?)> ks = <(Change, DiffNode?)>[
        for (final ReportItem i in same)
          for (final Change k in i.consequences) (k, i.change!.node),
      ];
      for (final String line in _consequenceLines(ks, (DiffNode k, DiffNode? at) {
        final bool near = at != null && (identical(k, at) || identical(k, at.parent));
        return same.length > 1 && near ? _relative(k, at) : names.of(k);
      })) {
        out.writeln('$indent$line');
      }
    } else {
      final ShiftGroup g = item.group!;
      final String causes = g.candidates.isEmpty
          ? 'cause unknown, needs review'
          : 'possible causes: ${g.candidates.map((Change x) => '${x.type.label} ${names.of(x.node)}').join(', ')}';
      _writeValues(out, '$number${'Shift'.padRight(10)}${names.of(g.ancestor).padRight(24)}  ', <String>[
        g.summary,
        causes,
      ]);
      for (final String line in _consequenceLines(<(Change, DiffNode?)>[
        for (final Change k in item.consequences) (k, null),
      ], (DiffNode k, _) => names.of(k))) {
        out.writeln('$indent$line');
      }
    }
  }
  if (report.items.isEmpty && report.inputChanges.isEmpty) {
    out.writeln('No changes.');
  }
  final List<String> passed = decision.reasons.where((String r) => r.startsWith('passed by')).toList();
  final List<String> failed = decision.reasons
      .where((String r) => r.startsWith('forbidden') || r.startsWith('not in the declared'))
      .toList();
  if (passed.isNotEmpty || failed.isNotEmpty) {
    out.writeln();
    for (final String r in <String>[...failed, ...passed]) {
      out.writeln('   $r');
    }
  }
  return out.toString();
}

/// Lines longer than this break before their arrow, then between words.
const int _width = 100;

/// [values] after [lead], the first on its line and each other one under it.
void _writeValues(StringBuffer out, String lead, List<String> values) {
  final String under = ' ' * lead.length;
  for (var i = 0; i < values.length; i++) {
    final String start = i == 0 ? lead : under;
    final String value = values[i];
    final int arrow = value.indexOf(' -> ');
    if (start.length + value.length > _width && arrow > 0) {
      _wrap(out, start, value.substring(0, arrow), '$under   ');
      _wrap(out, '$under  ', value.substring(arrow + 1), '$under     ');
    } else {
      _wrap(out, start, value, '$under   ');
    }
  }
}

/// [text] after [start], broken between words to fit [_width], each further
/// line starting with [more]. A word longer than a line is not broken.
void _wrap(StringBuffer out, String start, String text, String more) {
  final line = StringBuffer(start);
  var empty = true;
  for (final String word in text.split(' ')) {
    if (!empty && line.length + 1 + word.length > _width) {
      out.writeln(line);
      line
        ..clear()
        ..write(more);
      empty = true;
    }
    line.write(empty ? word : ' $word');
    empty = false;
  }
  out.writeln(line);
}

/// [c]'s wording as one entry per distinct change.
List<String> _values(Change c) => switch (c.type) {
  ChangeType.added || ChangeType.removed => <String>[_detail(c)],
  _ when c.contentMoved => <String>[_detail(c)],
  _ => c.summaryLines,
};

String _detail(Change c) => switch (c.type) {
  ChangeType.added || ChangeType.removed => c.summary.replaceFirst(RegExp(r'^(at|was at) '), ''),
  _ when c.contentMoved && c.possibleCauses.isNotEmpty =>
    '${c.summary}; possible causes: ${c.possibleCauses.map((Change x) => '${x.type.label} ${x.node.segment}').join(', ')}',
  _ when c.contentMoved => '${c.summary}; cause unknown, needs review',
  _ => c.summary,
};

/// The consequence lines for [ks], each a consequence with the component of
/// the item it is under (null under a shift), naming components with [name].
/// A line that reads the same for several instances of a folded item is
/// written once.
///
/// Paint that only followed a layout change is proven, not listed: a
/// component painted at its new size, or one whose content moved with
/// nothing it draws changed (its shape is the same). The component's own
/// resize line already says the first; the rest are counted on one line.
/// Paint that is not proven is listed one per line.
List<String> _consequenceLines(List<(Change, DiffNode?)> ks, String Function(DiffNode, DiffNode?) name) {
  final lines = <String>{};
  final followed = <String, DiffNode>{};
  for (final (Change k, DiffNode? at) in ks) {
    final bool atNewSize = k.type == ChangeType.paint && k.causedBy != null && identical(k.causedBy!.node, k.node);
    if (atNewSize && identical(k.node, at)) {
      continue;
    }
    if ((atNewSize || k.contentMoved) && !k.atRangeEdge) {
      followed.putIfAbsent(name(k.node, at), () => k.node);
      continue;
    }
    lines.add('consequence: ${k.type.label} ${name(k.node, at)}: ${_consequenceDetail(k)}');
  }
  if (followed.length > 3) {
    final types = <String>{for (final DiffNode n in followed.values) n.typeName};
    lines.add('consequence: ${followed.length} components repainted only to follow it (${types.join(', ')})');
  } else if (followed.isNotEmpty) {
    lines.add('consequence: repainted only to follow it: ${followed.keys.join(', ')}');
  }
  return lines.toList();
}

/// [groups] caused by one item: one line each, or, when they all moved the
/// same way, one line with the range of distances.
List<String> _groupLines(List<ShiftGroup> groups) {
  if (groups.length < 2) {
    return <String>[for (final ShiftGroup g in groups) g.summary];
  }
  String direction(ShiftGroup g) => g.vectorText.split(' ').first;
  final String d = direction(groups.first);
  if (d == 'by' || groups.any((ShiftGroup g) => direction(g) != d)) {
    return <String>[for (final ShiftGroup g in groups) g.summary];
  }
  final List<double> distances = <double>[for (final ShiftGroup g in groups) g.dx.abs() + g.dy.abs()]..sort();
  String n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  final int count = groups.fold(0, (int sum, ShiftGroup g) => sum + g.componentCount);
  final String range = distances.first == distances.last
      ? n(distances.first)
      : '${n(distances.first)} to ${n(distances.last)}';
  return <String>['$count components shifted $d $range px'];
}

String _consequenceDetail(Change c) => switch (c.type) {
  _ when c.atRangeEdge && c.presenceOnly => '${c.summary} (list items built or dropped)',
  _ when c.atRangeEdge => '${c.summary} (moved into or out of the painted area)',
  ChangeType.paint when c.causedBy != null && identical(c.causedBy!.node, c.node) => c.summary,
  ChangeType.paint => 'paint changed where its children moved or changed (not verified: paint is compared by hash)',
  ChangeType.semantics when c.presenceOnly => '${c.summary} (${_cameOrWent(c)} with the child)',
  _ when c.presenceOnly && c.fields.isNotEmpty => '${_propertyNames(c.fields)} ${_cameOrWent(c)} with the child',
  _ when c.presenceOnly => '${c.summary} (${_cameOrWent(c)} with the child)',
  _ when c.contentMoved => c.summary,
  ChangeType.layout => '${c.summary}, grew with its child',
  _ => c.summary,
};

String _cameOrWent(Change c) => switch (c.causedBy?.type) {
  ChangeType.added => 'came',
  ChangeType.removed => 'went',
  _ => 'came or went',
};

/// The properties in [fields] once each: without the index of the child they
/// belong to (`Container.bg.4`), and without the parts of a property already
/// named (`Container.bg.border` under `Container.bg`).
String _propertyNames(Map<String, String> fields) {
  final List<String> names = <String>{for (final String k in fields.keys) k.replaceFirst(RegExp(r'(\.\d+)+$'), '')}
      .toList();
  return names.where((String n) => !names.any((String m) => n != m && n.startsWith('$m.'))).join(', ');
}

/// [items] with the same change on several instances of one component
/// folded together, at the first one's place. Every instance is still named.
List<List<ReportItem>> _folded(List<ReportItem> items) {
  final Map<String, List<ReportItem>> byKey = <String, List<ReportItem>>{};
  final out = <List<ReportItem>>[];
  var unique = 0;
  for (final ReportItem item in items) {
    final Change? c = item.change;
    // The same change on copies of one component is one line, whatever
    // each copy's consequences: their consequences are listed together.
    final String key = c == null
        ? '${unique++}'
        : <String>[c.type.label, c.componentType, '${item.flagged}', _detail(c)].join('\n');
    final List<ReportItem>? same = byKey[key];
    if (same != null) {
      same.add(item);
    } else {
      out.add(byKey[key] = <ReportItem>[item]);
    }
  }
  return out;
}

/// [n] named relative to a folded item's [node]: by type when it is the node
/// itself or its parent, so the line reads the same for every instance.
String _relative(DiffNode n, DiffNode node) {
  if (identical(n, node)) {
    return n.typeName;
  }
  if (identical(n, node.parent)) {
    return '${n.typeName} around it';
  }
  return n.fullId;
}

/// Short names: the id segment, with parent segments added until unique.
class _Names {
  _Names(ChangeReport report) {
    final Set<DiffNode> nodes = <DiffNode>{
      for (final Change c in report.changes) c.node,
      for (final ShiftGroup g in report.groups) g.ancestor,
    };
    for (final DiffNode n in nodes) {
      (_bySegment[n.segment] ??= <String>{}).add(n.fullId);
    }
  }

  final Map<String, Set<String>> _bySegment = <String, Set<String>>{};

  String of(DiffNode n) {
    final Set<String> same = _bySegment[n.segment] ?? <String>{};
    if (same.length <= 1) {
      return n.segment;
    }
    final List<String> parts = n.fullId.split('/');
    for (var k = 2; k <= parts.length; k++) {
      final String suffix = parts.sublist(parts.length - k).join('/');
      if (same.where((String id) => id.endsWith(suffix)).length == 1) {
        return suffix;
      }
    }
    return n.fullId;
  }
}
