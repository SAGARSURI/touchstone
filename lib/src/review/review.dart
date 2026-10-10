// The review and update commands (spec: Policy and verdicts; Updating
// baselines). Pure Dart: they read snapshot files from git and the working
// tree, so they run without Flutter.

import 'dart:io';

import '../diff/changes.dart';
import '../diff/diff.dart';
import '../diff/migration_proof.dart';
import '../diff/policy.dart';
import '../diff/report.dart';
import '../snapshot/snapshot.dart';

/// The project rules file, read from the package root when present.
const String defaultRulesFile = 'touchstone.rules';

/// One snapshot file's outcome.
class SnapshotReview {
  SnapshotReview(this.path, this.decision, this.text, [this.report]);

  /// The file's path relative to the package root.
  final String path;
  final Decision decision;

  /// The change report, when both versions could be read.
  final ChangeReport? report;

  /// What the reviewer reads: the change report, or why there is none.
  final String text;
}

/// Every snapshot file that differs between [base] and the working tree.
class ReviewResult {
  ReviewResult(this.base, this.reviews);

  final String base;
  final List<SnapshotReview> reviews;

  /// The worst verdict, or pass when nothing differs.
  Verdict get verdict => reviews.fold(
    Verdict.pass,
    (Verdict v, SnapshotReview r) => r.decision.verdict.index > v.index ? r.decision.verdict : v,
  );

  /// 0 pass, 1 fail, 2 needs-review.
  int get exitCode => switch (verdict) {
    Verdict.pass => 0,
    Verdict.fail => 1,
    Verdict.needsReview => 2,
  };

  /// The counts and the verdict, an overview of every distinct change
  /// (renderOverview), each snapshot's review, and the verdict line again
  /// as the last line; with terminal colour when [color] is true (ansi.dart).
  String render({bool color = false}) {
    int count(Verdict v) => reviews.where((SnapshotReview r) => r.decision.verdict == v).length;
    final String verdictLine = reviews.isEmpty
        ? 'No snapshot differs from $base.'
        : '${reviews.length} ${reviews.length == 1 ? 'snapshot differs' : 'snapshots differ'} from $base: '
              '${count(Verdict.pass)} pass, ${count(Verdict.needsReview)} needs-review, ${count(Verdict.fail)} fail. '
              'Verdict: ${verdict.label}.';
    final out = StringBuffer()..writeln(verdictLine);
    if (reviews.isEmpty) {
      return out.toString();
    }
    // Snapshots are named by id, or by file when two files share an id.
    final List<String> ids = <String>[for (final SnapshotReview r in reviews) ?r.report?.snapshotId];
    final bool byId = ids.toSet().length == ids.length;
    final String overview = renderOverview(
      <String, ChangeReport>{
        for (final SnapshotReview r in reviews)
          if (r.report case final ChangeReport report) byId ? report.snapshotId : r.path: report,
      },
      others: <String, String>{
        for (final SnapshotReview r in reviews)
          if (r.report == null) r.path: r.decision.reasons.first,
      },
    );
    out
      ..writeln()
      ..write(overview)
      ..writeln()
      ..writeln('Each snapshot:')
      ..writeln();
    for (final SnapshotReview r in reviews) {
      out
        ..write(switch (r.report) {
          final ChangeReport report when color => renderReport(report, r.decision, color: true),
          _ => r.text,
        })
        ..writeln();
    }
    out.writeln(verdictLine);
    return out.toString();
  }
}

/// Compares every `.snapshot` file under [root] (a directory inside a git
/// work tree) with its version at [base], and decides each with [policy].
ReviewResult review({required String base, required Policy policy, String root = '.'}) {
  final String top = _git(<String>['rev-parse', '--show-toplevel'], root).trim();
  final String prefix = _git(<String>['rev-parse', '--show-prefix'], root).trim();
  final Set<String> before = _snapshotPaths(
    _git(<String>['ls-tree', '-r', '--name-only', '--full-name', base, '--', '.'], root),
  );
  final Set<String> after = <String>{
    for (final FileSystemEntity f in Directory(root).listSync(recursive: true, followLinks: false))
      if (f is File && f.path.endsWith('.snapshot') && !_ignored(f.path))
        '$prefix${f.path.substring(root.length + 1)}'.replaceAll(r'\', '/'),
  };
  final reviews = <SnapshotReview>[];
  for (final String path in (<String>{...before, ...after}.toList()..sort())) {
    final String shown = path.substring(prefix.length);
    final String? old = before.contains(path) ? _git(<String>['show', '$base:$path'], top) : null;
    final String? now = after.contains(path) ? File('$top/$path').readAsStringSync() : null;
    if (old == now) {
      continue;
    }
    if (old == null || now == null) {
      final decision = Decision(Verdict.needsReview, <String>[old == null ? 'new snapshot' : 'snapshot removed']);
      reviews.add(SnapshotReview(shown, decision, '$shown    needs-review\n\n${decision.reasons.single}.\n'));
      continue;
    }
    final Snapshot a;
    final Snapshot b;
    try {
      a = Snapshot.parse(old);
      b = Snapshot.parse(now);
    } on FormatException catch (e) {
      final decision = Decision(Verdict.fail, <String>['unreadable snapshot: ${e.message}']);
      reviews.add(SnapshotReview(shown, decision, '$shown    fail\n\n${decision.reasons.single}\n'));
      continue;
    }
    final ChangeReport report = diffSnapshots(a, b);
    final Decision decision = policy.decide(report, proof: _proof(report, '$top/$path'));
    reviews.add(SnapshotReview(shown, decision, renderReport(report, decision), report));
  }
  return ReviewResult(base, reviews);
}

/// Parses `--name value` pairs; only [allowed] names are accepted. A name in
/// [flags] takes no value and maps to `'true'`.
Map<String, String> parseOptions(List<String> args, Set<String> allowed, {Set<String> flags = const <String>{}}) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final String a = args[i];
    final String name = a.startsWith('--') ? a.substring(2) : '';
    if (flags.contains(name)) {
      out[name] = 'true';
      continue;
    }
    if (!allowed.contains(name) || i + 1 >= args.length) {
      throw FormatException('Unknown or incomplete option: $a');
    }
    out[name] = args[++i];
  }
  return out;
}

/// Reads [rules] and [expectations] into one policy. Expectations use the
/// rules format with `expect` lines only.
Policy loadPolicy({String? rules, String? expectations}) {
  final ruleList = <Rule>[];
  final String? rulesPath = rules ?? (File(defaultRulesFile).existsSync() ? defaultRulesFile : null);
  if (rulesPath != null) {
    ruleList.addAll(Policy.parse(File(rulesPath).readAsStringSync(), source: rulesPath).rules);
  }
  if (expectations != null) {
    final Policy p = Policy.parse(File(expectations).readAsStringSync(), source: expectations);
    for (final Rule r in p.rules) {
      if (r.action != RuleAction.expect) {
        throw FormatException('$expectations: only expect lines belong in declared expectations: "${r.line}"');
      }
    }
    ruleList.addAll(p.rules);
  }
  return Policy(ruleList);
}

/// The pixel proof migration wrote beside the snapshot at [path], for a
/// migration report. A proof that cannot be read is no proof.
MigrationProof? _proof(ChangeReport report, String path) {
  if (report.kind != ReportKind.migration) {
    return null;
  }
  final file = File('${path.substring(0, path.length - '.snapshot'.length)}.migration');
  if (!file.existsSync()) {
    return null;
  }
  try {
    return MigrationProof.parse(file.readAsStringSync());
  } on FormatException {
    return null;
  }
}

Set<String> _snapshotPaths(String listing) => <String>{
  for (final String line in listing.split('\n'))
    if (line.endsWith('.snapshot') && !_ignored(line, separator: '/')) line,
};

/// Whether [path] is under `.dart_tool` or `build`, where Dart and Flutter
/// write their own `.snapshot` files.
bool _ignored(String path, {String? separator}) =>
    path.split(separator ?? Platform.pathSeparator).any((String part) => part == '.dart_tool' || part == 'build');

String _git(List<String> args, String dir) {
  final ProcessResult r = Process.runSync('git', args, workingDirectory: dir);
  if (r.exitCode != 0) {
    throw ProcessException('git', args, '${r.stderr}'.trim(), r.exitCode);
  }
  return r.stdout as String;
}
