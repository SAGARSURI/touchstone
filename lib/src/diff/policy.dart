// Policy and verdicts (spec: Policy and verdicts).
//
// A written policy maps the change list to one of three verdicts, and no
// verdict depends on a numeric tolerance.

import 'changes.dart';
import 'migration_proof.dart';

enum Verdict {
  pass('pass'),
  needsReview('needs-review'),
  fail('fail');

  const Verdict(this.label);

  final String label;
}

/// A verdict with the reasons for it, one line each.
class Decision {
  Decision(this.verdict, this.reasons);

  final Verdict verdict;
  final List<String> reasons;
}

/// A project rule: `pass <component> <change type>` or
/// `forbid <component or *> <change type or *>`.
class Rule {
  Rule(this.action, this.component, this.type, this.line);

  final RuleAction action;

  /// A component type, an id segment such as `AppButton#submit`, the end of a
  /// full id, or `*` (forbid rules only).
  final String component;

  /// A change type label, or `*` (forbid rules only).
  final String type;

  /// The rule as written, for messages.
  final String line;

  bool matches(Change c) => _componentMatches(component, c) && (type == '*' || type == c.type.label);

  bool matchesGroup(ShiftGroup g) =>
      (component == '*' || g.members.any((m) => _nameMatches(component, m.typeName, m.segment, m.fullId))) &&
      (type == '*' || type == ChangeType.layout.label);
}

enum RuleAction { pass, forbid, expect }

bool _componentMatches(String pattern, Change c) => _nameMatches(pattern, c.componentType, c.node.segment, c.nodeId);

bool _nameMatches(String pattern, String type, String segment, String fullId) =>
    pattern == '*' || pattern == type || pattern == segment || pattern == fullId || fullId.endsWith('/$pattern');

/// The project's rules file, reviewed like code. One rule per line; `#`
/// starts a comment:
///
/// ```
/// # The chart's paint is a pixel hash and changes with every data refresh.
/// pass SparklineChart Paint
/// # No pull request may change semantics silently.
/// forbid * Semantics
/// ```
///
/// A pull request's declared expectations use the same form with `expect`:
/// `expect OrderButton Style`. When any are given, a visible change outside
/// them fails.
class Policy {
  Policy(this.rules);

  /// No rules: the spec's default policy.
  Policy.defaults() : rules = const <Rule>[];

  /// Parses [text]. Throws [FormatException] for a rule the spec does not
  /// allow: a pass rule must name one component and one change type, and no
  /// rule takes a size or tolerance.
  factory Policy.parse(String text, {String source = 'rules'}) {
    final rules = <Rule>[];
    final List<String> lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final String line = lines[i].split('#').first.trim();
      if (line.isEmpty) {
        continue;
      }
      final List<String> parts = line.split(RegExp(r'\s+'));
      String where() => '$source:${i + 1}: "$line"';
      if (parts.length != 3) {
        throw FormatException('${where()}: expected "<pass|forbid|expect> <component> <change type>"');
      }
      final RuleAction? action = switch (parts[0]) {
        'pass' => RuleAction.pass,
        'forbid' => RuleAction.forbid,
        'expect' => RuleAction.expect,
        _ => null,
      };
      if (action == null) {
        throw FormatException('${where()}: unknown rule "${parts[0]}"');
      }
      final String type = parts[2];
      if (type != '*' && !ChangeType.values.any((ChangeType t) => t.label == type)) {
        throw FormatException(
          '${where()}: unknown change type "$type"; one of ${ChangeType.values.map((t) => t.label).join(', ')}',
        );
      }
      if (action != RuleAction.forbid && (parts[1] == '*' || type == '*')) {
        throw FormatException('${where()}: a ${parts[0]} rule must name both a component and a change type');
      }
      rules.add(Rule(action, parts[1], type, line));
    }
    return Policy(rules);
  }

  final List<Rule> rules;

  Iterable<Rule> _of(RuleAction a) => rules.where((Rule r) => r.action == a);

  /// The verdict for a comparison of a committed baseline with the target
  /// branch's baseline (spec, Verdicts). A migration passes only with a
  /// [proof] that covers both baselines and shows identical pixels (A12).
  Decision decide(ChangeReport report, {MigrationProof? proof}) {
    switch (report.kind) {
      case ReportKind.equal:
        return Decision(Verdict.pass, const <String>[]);
      case ReportKind.migration:
        const routed = 'recorded with a different toolchain: routed to migration, not compared';
        if (proof == null || !proof.covers(report)) {
          return Decision(Verdict.needsReview, <String>[
            routed,
            proof == null ? 'no pixel proof' : 'the pixel proof is for other baselines',
          ]);
        }
        if (proof.pixelsIdentical) {
          return Decision(Verdict.pass, <String>[
            routed,
            'pixels identical on both toolchains (${proof.after!.pixels}): re-baselined automatically',
          ]);
        }
        return Decision(Verdict.needsReview, <String>[
          routed,
          proof.before.pixels == null
              ? 'no pixels from the old toolchain: the old baseline did not match its capture there'
              : 'pixels differ: ${proof.before.pixels} -> ${proof.after!.pixels}',
        ]);
      case ReportKind.diff:
        break;
    }
    final reasons = <String>[];
    var verdict = Verdict.pass;
    void raise(Verdict v, String reason) {
      reasons.add(reason);
      if (v.index > verdict.index) {
        verdict = v;
      }
    }

    for (final String input in report.inputChanges) {
      raise(Verdict.needsReview, 'declared input changed: $input');
    }
    final List<Rule> expected = _of(RuleAction.expect).toList();
    for (final ReportItem item in report.items) {
      final List<Change> own = <Change>[if (item.change != null) item.change!, ...item.consequences];
      for (final Rule r in _of(RuleAction.forbid)) {
        if (own.any(r.matches) ||
            (item.group != null && r.matchesGroup(item.group!)) ||
            item.causedGroups.any(r.matchesGroup)) {
          raise(Verdict.fail, 'forbidden by "${r.line}": ${_name(item)}');
        }
      }
      if (item.isInfo) {
        continue;
      }
      if (expected.isNotEmpty && !_expectedCovers(expected, item)) {
        raise(Verdict.fail, 'not in the declared expectations: ${_name(item)}');
        continue;
      }
      final Change? c = item.change;
      if (c != null && item.consequences.isEmpty && item.causedGroups.isEmpty) {
        final Rule? pass = _of(RuleAction.pass).where((Rule r) => r.matches(c)).firstOrNull;
        if (pass != null) {
          reasons.add('passed by "${pass.line}": ${_name(item)}');
          continue;
        }
      }
      raise(Verdict.needsReview, item.flagged ? 'unexplained: ${_name(item)}' : 'visible change: ${_name(item)}');
    }
    return Decision(verdict, reasons);
  }

  bool _expectedCovers(List<Rule> expected, ReportItem item) {
    if (item.group != null) {
      return expected.any((Rule r) => r.matchesGroup(item.group!));
    }
    return expected.any((Rule r) => r.matches(item.change!));
  }

  static String _name(ReportItem item) {
    final Change? c = item.change;
    if (c != null) {
      return '${c.type.label} ${c.nodeId}';
    }
    return 'shift under ${item.group!.ancestor.fullId}';
  }
}
