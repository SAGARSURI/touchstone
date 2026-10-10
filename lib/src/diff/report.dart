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
// by an "at:" line naming every instance; that line and consequences break
// between words too. When there are several items, a line under the verdict
// counts them by type, and a blank line separates the items (DX sessions,
// doc/phase3/dx_results.md).

import 'ansi.dart';
import 'changes.dart';
import 'diff.dart';
import 'policy.dart';
import 'summary.dart';

/// The style changes that share a cause in more than one of [reports], keyed
/// by snapshot: one line per cause, such as a token whose value changed, with
/// how many components of each type it changed and in how many snapshots.
/// Empty when no cause spans two snapshots.
String renderCauses(Map<String, ChangeReport> reports) {
  final out = StringBuffer();
  for (final MapEntry<String, List<(String, Change)>> e in _sharedCauses(reports).entries) {
    final int snapshots = <String>{for (final (String id, _) in e.value) id}.length;
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
    _wrap(out, '  ', '${e.key}: style change on $components in $snapshots snapshots', '      ');
  }
  return out.isEmpty ? '' : 'Causes in more than one snapshot:\n$out';
}

/// The style changes of [reports] by cause, keeping only causes found in
/// more than one snapshot.
Map<String, List<(String, Change)>> _sharedCauses(Map<String, ChangeReport> reports) {
  final byCause = <String, List<(String, Change)>>{};
  for (final MapEntry<String, ChangeReport> r in reports.entries) {
    for (final Change c in r.value.changes) {
      if (c.type == ChangeType.style && c.fields.isNotEmpty) {
        (byCause[_cause(c.fields)] ??= <(String, Change)>[]).add((r.key, c));
      }
    }
  }
  byCause.removeWhere((String _, List<(String, Change)> v) => <String>{for (final (String id, _) in v) id}.length < 2);
  return byCause;
}

/// The overview's items: lines grouped by their full values, each with the
/// snapshots it is in, the line as printed, and its name (change and
/// component type, or the snapshot) for the summary.
class _Overview {
  final failing = <String, Set<String>>{};
  final flagged = <String, Set<String>>{};
  final rest = <String, Set<String>>{};
  final shown = <String, String>{};
  final names = <String, String>{};
}

_Overview _overview(
  Map<String, ChangeReport> reports,
  Map<String, String> others, {
  bool Function(ReportItem item)? fails,
}) {
  final Set<String> shared = _sharedCauses(reports).keys.toSet();
  final o = _Overview();
  void add(Map<String, Set<String>> into, String line, String name, String id) {
    o.names[line] = name;
    (into[line] ??= <String>{}).add(id);
  }

  for (final MapEntry<String, ChangeReport> r in reports.entries) {
    if (r.value.kind == ReportKind.migration) {
      add(o.rest, '${r.key}: recorded with a different toolchain (migration)', '${r.key} (migration)', r.key);
      continue;
    }
    for (final String input in r.value.inputChanges) {
      add(o.rest, 'Input: $input', 'Input', r.key);
    }
    for (final ReportItem item in r.value.items) {
      // Information items are left out unless a rule fails them.
      final bool failing = fails?.call(item) ?? false;
      if (item.isInfo && !failing) {
        continue;
      }
      final Change? c = item.change;
      List<String>? values = c == null ? null : _overviewValues(c);
      if (!failing &&
          c != null &&
          c.type == ChangeType.style &&
          c.fields.isNotEmpty &&
          shared.contains(_cause(c.fields))) {
        // The shared cause explains its tokens and the colours that follow
        // from them; any other value that changed with them is still listed.
        final bool all = _cause(c.fields) == fieldValues(c.fields);
        final Map<String, String> unexplained = <String, String>{
          for (final MapEntry<String, String> f in c.fields.entries)
            if (!all && !_colourOnly(shortenValue(f.value))) f.key: f.value,
        };
        if (unexplained.isEmpty) {
          continue;
        }
        values = summarizeFieldList(unexplained);
      }
      final String name = c != null ? '${c.type.label} ${c.componentType}' : 'Shift ${item.group!.ancestor.typeName}';
      final String line = c != null
          ? '$name: ${values!.join('; ')}'
          : '$name: ${item.group!.summary}${item.group!.candidates.isEmpty ? ', cause unknown' : ''}';
      o.shown[line] = c != null ? '$name: ${values!.map(_short).join('; ')}' : line;
      add(
        failing
            ? o.failing
            : item.flagged
            ? o.flagged
            : o.rest,
        line,
        name,
        r.key,
      );
    }
  }
  for (final MapEntry<String, String> other in others.entries) {
    add(o.rest, '${other.key}: ${other.value}', '${other.key} (${other.value})', other.key);
  }
  return o;
}

/// The summary a review opens with, under its verdict line
/// (doc/phase3/review_summary_expectations.md): at most four lines of at
/// most [width] characters. "Fails the rules:" names the items [fails]
/// picks out (Policy.fails), "Check first:" names the unexplained items,
/// each shared cause that fits gets a line with how many components and
/// snapshots it changed, and "Also:" names every other item and counts the
/// shared causes left. Each line names what fits and counts the rest as
/// "+N more", so every distinct change is named or counted.
String renderSummary(
  Map<String, ChangeReport> reports, {
  Map<String, String> others = const <String, String>{},
  bool Function(ReportItem item)? fails,
  int width = 100,
}) {
  final _Overview o = _overview(reports, others, fails: fails);
  // Items by name, most snapshots first, with how many when more than one.
  List<String> named(Map<String, Set<String>> lines) {
    final bySnapshots = <String, Set<String>>{};
    for (final MapEntry<String, Set<String>> e in lines.entries) {
      (bySnapshots[o.names[e.key]!] ??= <String>{}).addAll(e.value);
    }
    final List<MapEntry<String, Set<String>>> sorted = bySnapshots.entries.toList()
      ..sort(
        (MapEntry<String, Set<String>> x, MapEntry<String, Set<String>> y) => y.value.length.compareTo(x.value.length),
      );
    return <String>[
      for (final MapEntry<String, Set<String>> e in sorted)
        e.value.length == 1 ? e.key : '${e.key} (${e.value.length} snapshots)',
    ];
  }

  // As many of [items] as fit after [prefix], then "+N more".
  String fit(String prefix, List<String> items) {
    for (int n = items.length; n > 0; n--) {
      final String more = n < items.length ? ', +${items.length - n} more' : '';
      final String line = '$prefix${items.take(n).join(', ')}$more';
      if (line.length <= width) {
        return line;
      }
    }
    return '$prefix+${items.length} more';
  }

  final List<String> causes = <String>[
    for (final MapEntry<String, List<(String, Change)>> e in _sharedCauses(reports).entries)
      () {
        final int snapshots = <String>{for (final (String id, _) in e.value) id}.length;
        final String counts = ', ${e.value.length} components in $snapshots snapshots';
        const prefix = 'Shared cause: ';
        final int room = width - prefix.length - counts.length;
        final String cause = e.key.length <= room
            ? e.key
            : room > 1
            ? '${e.key.substring(0, room - 1)}…'
            : '…';
        return '$prefix$cause$counts';
      }(),
  ];
  final List<String> failing = named(o.failing);
  final List<String> flagged = named(o.flagged);
  final List<String> rest = named(o.rest);
  final out = StringBuffer();
  if (failing.isNotEmpty) {
    out.writeln(fit('Fails the rules: ', failing));
  }
  if (flagged.isNotEmpty) {
    out.writeln(fit('Check first, unexplained: ', flagged));
  }
  final int room = 4 - (failing.isEmpty ? 0 : 1) - (flagged.isEmpty ? 0 : 1);
  final int ownLines = rest.isEmpty && causes.length <= room ? causes.length : room - 1;
  for (final String cause in causes.take(ownLines)) {
    out.writeln(cause);
  }
  final int left = causes.length - ownLines;
  final List<String> also = <String>[if (left > 0) '$left more shared ${left == 1 ? 'cause' : 'causes'}', ...rest];
  if (also.isNotEmpty) {
    out.writeln(fit('Also: ', also));
  }
  return out.toString();
}

/// The overview that follows the summary (doc/phase3/review_overview_expectations.md):
/// the unexplained items first, as the default policy flags them, then the
/// causes shared between snapshots, then every other visible item. Items
/// with the same change type, component type and wording are one line, with
/// the snapshot they are in, or how many. [others] are snapshots with no
/// report to read (new, removed, unreadable), each with why.
String renderOverview(Map<String, ChangeReport> reports, {Map<String, String> others = const <String, String>{}}) {
  final _Overview o = _overview(reports, others);
  final out = StringBuffer();
  void section(String title, Map<String, Set<String>> lines) {
    if (lines.isEmpty) {
      return;
    }
    out.writeln(title);
    final List<MapEntry<String, Set<String>>> sorted = lines.entries.toList()
      ..sort(
        (MapEntry<String, Set<String>> x, MapEntry<String, Set<String>> y) => y.value.length.compareTo(x.value.length),
      );
    for (final MapEntry<String, Set<String>> e in sorted) {
      final String where = e.value.length == 1 && e.key.startsWith('${e.value.single}: ')
          ? ''
          : e.value.length == 1
          ? ', in ${e.value.single}'
          : ', in ${e.value.length} snapshots';
      _wrap(out, '  ', '${o.shown[e.key] ?? e.key}$where', '      ');
    }
  }

  section('Unexplained, check these first:', o.flagged);
  out.write(renderCauses(reports));
  section('Other changes:', o.rest);
  return out.toString();
}

/// Whether [value], "old -> new", differs only in colours.
bool _colourOnly(String value) {
  if (_tokenValue.hasMatch(value)) {
    return true;
  }
  final List<String> sides = value.split(' -> ');
  if (sides.length != 2) {
    return false;
  }
  String plain(String side) => side.replaceAll(_colourText, '#');
  return plain(sides[0]) == plain(sides[1]);
}

// A colour as hex, or as Color(...), which may be cut off at the side's end.
final RegExp _colourText = RegExp(r'#[0-9A-Fa-f]{8}|Color\([^)]*(?:\)|$)');

/// [c]'s values for the overview. A layout change's new size follows from
/// the values that changed with it, and differs with the screen, so it is
/// left out when there are any: one padding change on many screens is one
/// line.
List<String> _overviewValues(Change c) {
  final List<String> values = _values(c);
  if (c.type != ChangeType.layout) {
    return values;
  }
  final List<String> causes = values.where((String v) => !v.startsWith('size ')).toList();
  return causes.isEmpty ? values : causes;
}

/// One changed value cut to a line's worth, so every value an
/// item changed is named; the snapshot's own report has the rest.
String _short(String value) =>
    value.length <= 96 ? value : '${value.substring(0, 95).replaceFirst(RegExp(r'…+$'), '')}…';

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

/// Renders [report] with [decision]'s verdict on the first line, with
/// terminal colour when [color] is true (ansi.dart).
String renderReport(ChangeReport report, Decision decision, {bool color = false}) {
  final Ansi a = Ansi(color);
  final String verdict = switch (decision.verdict) {
    Verdict.pass => a.boldGreen(decision.verdict.label),
    Verdict.needsReview => a.boldYellow(decision.verdict.label),
    Verdict.fail => a.boldRed(decision.verdict.label),
  };
  final out = StringBuffer('${a.bold(report.snapshotId)}    $verdict\n');
  switch (report.kind) {
    case ReportKind.equal:
      out.write('\nNo changes.\n');
      return out.toString();
    case ReportKind.migration:
      out.write('\nRecorded with a different toolchain, so not compared (migration).\n');
      for (final String k in <String>{...report.beforeToolchain!.keys, ...report.afterToolchain!.keys}) {
        if (report.beforeToolchain![k] != report.afterToolchain![k]) {
          out.write(
            '  ${highlightChange('$k: ${report.beforeToolchain![k] ?? '(none)'} -> ${report.afterToolchain![k] ?? '(none)'}', a)}\n',
          );
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
      _writeValues(out, _lead(a, number, c.type.label, where), <String>[
        for (final String v in _values(c)) highlightChange(v, a),
      ]);
      if (same.length > 1) {
        _writeLabelled(out, indent, 'at: ${same.map((ReportItem i) => names.of(i.change!.node)).join(', ')}', a);
      }
      for (final String line in _groupLines(<ShiftGroup>[for (final ReportItem i in same) ...i.causedGroups])) {
        _writeLabelled(out, indent, 'consequence: $line', a);
      }
      final List<(Change, DiffNode?)> ks = <(Change, DiffNode?)>[
        for (final ReportItem i in same)
          for (final Change k in i.consequences) (k, i.change!.node),
      ];
      for (final String line in _consequenceLines(ks, (DiffNode k, DiffNode? at) {
        final bool near = at != null && (identical(k, at) || identical(k, at.parent));
        return same.length > 1 && near ? _relative(k, at) : names.of(k);
      })) {
        _writeLabelled(out, indent, line, a);
      }
    } else {
      final ShiftGroup g = item.group!;
      final String causes = g.candidates.isEmpty
          ? 'cause unknown, needs review'
          : 'possible causes: ${g.candidates.map((Change x) => '${x.type.label} ${names.of(x.node)}').join(', ')}';
      _writeValues(out, _lead(a, number, 'Shift', names.of(g.ancestor)), <String>[g.summary, causes]);
      for (final String line in _consequenceLines(<(Change, DiffNode?)>[
        for (final Change k in item.consequences) (k, null),
      ], (DiffNode k, _) => names.of(k))) {
        _writeLabelled(out, indent, line, a);
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
      _writeLabelled(out, '   ', r, a, error: !r.startsWith('passed by'));
    }
  }
  return out.toString();
}

/// An item's first columns: its number, change type and component.
String _lead(Ansi a, String number, String type, String where) =>
    '$number${a.cyan(type)}${' ' * (10 - type.length).clamp(0, 10)}'
    '${a.bold(where)}${' ' * (24 - where.length).clamp(0, 24)}  ';

/// Lines longer than this break before their arrow, then between words.
const int _width = 100;

/// [values] after [lead], the first on its line and each other one under it.
void _writeValues(StringBuffer out, String lead, List<String> values) {
  final String under = ' ' * visibleLength(lead);
  for (var i = 0; i < values.length; i++) {
    final String start = i == 0 ? lead : under;
    final String value = values[i];
    final int arrow = value.indexOf(' -> ');
    if (visibleLength(start) + visibleLength(value) > _width && arrow > 0) {
      _wrap(out, start, value.substring(0, arrow), '$under   ');
      _wrap(out, '$under  ', value.substring(arrow + 1), '$under     ');
    } else {
      _wrap(out, start, value, '$under   ');
    }
  }
}

/// [line] after [indent], a further line starting under the text after its
/// label ("at: ", "consequence: ").
void _writeLabelled(StringBuffer out, String indent, String line, Ansi a, {bool error = false}) {
  final int colon = line.indexOf(': ');
  final String label = colon < 0 ? '' : line.substring(0, colon + 2);
  final String text = line.substring(label.length);
  _wrap(
    out,
    '$indent${error ? a.red(label) : a.dim(label)}',
    error ? a.red(text) : text,
    ' ' * (indent.length + label.length),
  );
}

/// [text] after [start], broken between words to fit [_width], each further
/// line starting with [more]. A word longer than a line is not broken.
void _wrap(StringBuffer out, String start, String text, String more) {
  final line = StringBuffer(start);
  var width = visibleLength(start);
  var empty = true;
  for (final String word in text.split(' ')) {
    final int w = visibleLength(word);
    if (!empty && width + 1 + w > _width) {
      out.writeln(line);
      line
        ..clear()
        ..write(more);
      width = visibleLength(more);
      empty = true;
    }
    line.write(empty ? word : ' $word');
    width += empty ? w : 1 + w;
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

/// The items of [report] as the report numbers them (from 1): the change
/// type, the component as the report names it, and the changes the item
/// holds (several when one change on copies of a component is folded into
/// one item; none for a shift), and for a shift its group.
List<({int number, String type, String component, List<Change> changes, ShiftGroup? group})> numberedItems(
  ChangeReport report,
) {
  final _Names names = _Names(report);
  var n = 0;
  return <({int number, String type, String component, List<Change> changes, ShiftGroup? group})>[
    for (final List<ReportItem> same in _folded(report.items))
      (
        number: ++n,
        type: same.first.change?.type.label ?? 'Shift',
        component: switch (same.first.change) {
          null => names.of(same.first.group!.ancestor),
          final Change c when same.length == 1 => names.of(c.node),
          final Change c => '${c.componentType} in ${same.length} places',
        },
        changes: <Change>[for (final ReportItem i in same) ?i.change],
        group: same.first.group,
      ),
  ];
}
