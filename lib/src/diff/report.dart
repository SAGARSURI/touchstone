// The change report as text (spec: Diff engine, "Report shape"):
//
//   order_ticket/loading/dark    needs-review
//
//   1  Added   PromoBanner#promo       16,24,358,56
//              consequence: 6 components shifted down 64 px
//   2  Style   OrderButton#submit      background: brand.primary -> brand.accent
//   3  Paint   SparklineChart#spark    unexplained (pixel hash changed)

import 'changes.dart';
import 'diff.dart';
import 'policy.dart';

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
      return out.toString();
    case ReportKind.diff:
      break;
  }
  out.writeln();
  for (final String input in report.inputChanges) {
    out.writeln('   Input   $input');
  }
  final _Names names = _Names(report);
  const indent = '           ';
  var n = 0;
  for (final ReportItem item in report.items) {
    n++;
    final String number = '$n'.padRight(3);
    final Change? c = item.change;
    if (c != null) {
      out.writeln('$number${c.type.label.padRight(10)}${names.of(c.node).padRight(24)}  ${_detail(c)}');
      for (final ShiftGroup g in item.causedGroups) {
        out.writeln('${indent}consequence: ${g.summary}');
      }
      for (final Change k in item.consequences) {
        out.writeln('${indent}consequence: ${k.type.label} ${names.of(k.node)}: ${_consequenceDetail(k)}');
      }
    } else {
      final ShiftGroup g = item.group!;
      final String causes = g.candidates.isEmpty
          ? 'cause unknown, needs review'
          : 'possible causes: ${g.candidates.map((Change x) => '${x.type.label} ${names.of(x.node)}').join(', ')}';
      out.writeln('$number${'Shift'.padRight(10)}${names.of(g.ancestor).padRight(24)}  ${g.summary}; $causes');
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

String _detail(Change c) => switch (c.type) {
  ChangeType.added || ChangeType.removed => c.detail.replaceFirst(RegExp(r'^(at|was at) '), ''),
  _ => c.detail,
};

String _consequenceDetail(Change c) => switch (c.type) {
  ChangeType.paint when identical(c.causedBy!.node, c.node) => c.detail,
  ChangeType.paint => 'paint changed where its children moved or changed (not verified: paint is compared by hash)',
  _ when c.presenceOnly => '${c.detail} (came or went with the child)',
  ChangeType.layout => '${c.detail}, grew with its child',
  _ => c.detail,
};

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
