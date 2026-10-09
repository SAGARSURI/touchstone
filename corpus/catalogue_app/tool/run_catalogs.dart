// Runs the mutation and no-op catalogs (tool/catalogs.dart) and writes
// build/catalogs/report.json and build/catalogs/report.md.
//
//   dart run tool/run_catalogs.dart [entry-id ...]
//
// Each entry is applied to the source in place and always restored, then the
// probe test captures its scenes and compares them with an unedited run.
//
// Phase 2: each scene's snapshots also go through the diff and the default
// policy, and the entry is scored as doc/phase2/expectations.md says. Each
// change report is written to build/catalogs/<entry>/report.txt.

import 'dart:convert';
import 'dart:io';

import 'package:touchstone/diff.dart';

import 'catalogs.dart';

Future<void> _probe(List<String> scenes, String out, {String? base}) async {
  final ProcessResult r = await Process.run('flutter', <String>[
    'test',
    'test/probe/probe_test.dart',
    '--dart-define=PROBE_SCENES=${scenes.join(',')}',
    '--dart-define=PROBE_OUT=$out',
    if (base != null) '--dart-define=PROBE_BASE=$base',
  ]);
  if (r.exitCode != 0) {
    throw StateError('probe failed for $out:\n${r.stdout}\n${r.stderr}');
  }
}

Map<String, Object?> _read(String dir, String scene) =>
    jsonDecode(File('$dir/${scene.replaceAll('/', '__')}.json').readAsStringSync()) as Map<String, Object?>;

Future<Map<String, Object?>> _run(Entry e, String base, bool noOp, {bool scoreOnly = false}) async {
  final originals = <String, String>{};
  try {
    for (final Edit edit in e.edits) {
      final file = File(edit.file);
      final String text = file.readAsStringSync();
      originals.putIfAbsent(edit.file, () => text);
      final int count = edit.find.allMatches(text).length;
      if (count == 0 || (!edit.all && count != 1)) {
        throw StateError('${e.id}: expected one "${edit.find}" in ${edit.file}, found $count');
      }
      file.writeAsStringSync(text.replaceAll(edit.find, edit.replace));
    }
    final out = 'build/catalogs/${e.id}';
    if (!scoreOnly) {
      await _probe(e.scenes, out, base: base);
    }
    final Map<String, Object?> scored = _score(e, base, out, noOp);
    final scenes = <Map<String, Object?>>[];
    for (final String scene in e.scenes) {
      scenes.add(<String, Object?>{'scene': scene, ...(_read(out, scene)['compare']! as Map<String, Object?>)});
    }
    bool any(String key) => scenes.any((Map<String, Object?> s) => s[key] == true);
    final bool pixels = any('pixelsChanged');
    final bool semantics = any('semanticsChanged');
    final bool snapshot = any('snapshotChanged');
    final String seen = pixels ? 'pixels' : (semantics ? 'semantics' : 'none');
    final List<String> firstNodes = <String>[
      for (final s in scenes)
        if (s['firstNode'] != null) s['firstNode']! as String,
    ];
    String typeOf(String fullId) => fullId.split('/').last.split(RegExp('[@#]')).first;
    return <String, Object?>{
      'id': e.id,
      'kind': e.kind,
      'expectedOracle': e.oracle.name,
      'oracle': seen,
      'expectationHeld': seen == e.oracle.name,
      'snapshotChanged': snapshot,
      if (!noOp) 'missed': (pixels || semantics) && !snapshot,
      if (!noOp) 'falseAlarmCandidate': !pixels && !semantics && snapshot,
      // A6 input: the edited component is among the nodes whose own paint or
      // semantics changed, or that were added or removed.
      if (e.expectNode != null)
        'landsOnExpected': scenes.every(
          (Map<String, Object?> s) =>
              s['snapshotChanged'] != true ||
              (s['nodes']! as List<Object?>).cast<Map<String, Object?>>().any(
                (Map<String, Object?> n) =>
                    typeOf(n['node']! as String) == e.expectNode &&
                    (n['change'] != 'changed' ||
                        (n['fields']! as List<Object?>).any((Object? f) => f == 'paint' || f == 'semantics')),
              ),
        ),
      'firstNodes': firstNodes,
      ...scored,
      if (!noOp) 'missedVerdict': (pixels || semantics) && scored['verdict'] == Verdict.pass.label,
      'scenes': scenes,
    };
  } finally {
    originals.forEach((String path, String text) => File(path).writeAsStringSync(text));
  }
}

/// The diff, the default policy and the scores for [e] (Phase 2).
Map<String, Object?> _score(Entry e, String base, String out, bool noOp) {
  final reports = <ChangeReport>[];
  final text = StringBuffer();
  var verdict = Verdict.pass;
  for (final String scene in e.scenes) {
    final ChangeReport r = diffSnapshots(
      Snapshot.parse(_read(base, scene)['snapshot']! as String),
      Snapshot.parse(_read(out, scene)['snapshot']! as String),
    );
    final Decision d = Policy.defaults().decide(r);
    if (d.verdict.index > verdict.index) {
      verdict = d.verdict;
    }
    reports.add(r);
    text
      ..write(renderReport(r, d))
      ..writeln();
  }
  File('$out/report.txt').writeAsStringSync(text.toString());

  final List<ChangeReport> changed = reports.where((ChangeReport r) => r.kind != ReportKind.equal).toList();
  final List<ReportItem> items = <ReportItem>[for (final ChangeReport r in changed) ...r.items];
  final List<ShiftGroup> groups = <ShiftGroup>[for (final ChangeReport r in changed) ...r.groups];
  String itemText(ReportItem i) => i.change != null
      ? '${i.change!.type.label} ${i.change!.nodeId}'
      : 'Shift ${i.group!.ancestor.fullId} (${i.group!.summary}, ${i.group!.candidates.length} candidates)';
  final result = <String, Object?>{
    'verdict': verdict.label,
    'items': items.map(itemText).toList(),
    'groups': <String>[
      for (final ShiftGroup g in groups)
        '${g.summary} under ${g.ancestor.fullId}: '
            '${g.cause != null ? 'cause ${g.cause!.type.label} ${g.cause!.nodeId}' : '${g.candidates.length} candidates'}',
    ],
  };
  if (noOp) {
    // A5: no change, or info-level identity changes only.
    result['strict'] = reports.every((ChangeReport r) => r.isEqual || r.infoOnly);
    return result;
  }
  if (e.expectTypes.isNotEmpty) {
    bool sceneCorrect(ChangeReport r) {
      if (e.expectNode == null) {
        return r.items.isNotEmpty && r.items.every((ReportItem i) => i.change?.type == ChangeType.style);
      }
      final Map<String, Set<String>> typesByNode = <String, Set<String>>{};
      for (final ReportItem i in r.items) {
        final Change? c = i.change;
        if (c != null && c.componentType == e.expectNode) {
          (typesByNode[c.nodeId] ??= <String>{}).add(c.type.label);
        }
      }
      return typesByNode.values.any((Set<String> t) => t.containsAll(e.expectTypes));
    }

    result['correct'] = changed.isNotEmpty && changed.every(sceneCorrect);
    result['extraItems'] = items
        .where((ReportItem i) => i.change == null || i.change!.componentType != e.expectNode)
        .map(itemText)
        .toList();
  }
  if (e.expectShift != null) {
    // A8.
    bool causeIsExpected(ShiftGroup g) => g.cause != null && g.cause!.componentType == e.expectNode;
    result['rootCauseCorrect'] = e.expectShift! ? groups.isNotEmpty && groups.every(causeIsExpected) : groups.isEmpty;
    result['wrongCertain'] = groups.any((ShiftGroup g) => g.cause != null && !causeIsExpected(g));
  }
  return result;
}

Future<void> main(List<String> arguments) async {
  // --score-only re-scores the last run's captures without capturing again.
  final List<String> args = <String>[...arguments];
  final bool scoreOnly = args.remove('--score-only');
  final List<Entry> all = <Entry>[...mutations, ...cascades, ...noOps];
  final List<Entry> chosen = args.isEmpty ? all : all.where((Entry e) => args.contains(e.id)).toList();
  final List<String> sceneIds = <String>{for (final Entry e in chosen) ...e.scenes}.toList();
  const base = 'build/catalogs/base';
  if (!scoreOnly) {
    await _probe(sceneIds, base);
  }
  final results = <Map<String, Object?>>[];
  for (final Entry e in chosen) {
    stdout.writeln('running ${e.id}');
    results.add(await _run(e, base, noOps.contains(e), scoreOnly: scoreOnly));
  }
  File('build/catalogs/report.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));

  final md = StringBuffer()
    ..writeln(
      '| Entry | Kind | Oracle saw | Verdict | Missed | Correct type | Root cause | Wrong certain | No-op strict '
      '| Top-level items |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
  String cell(Object? v) => v == null ? 'n/a' : '$v';
  for (final r in results) {
    md.writeln(
      '| ${r['id']} | ${r['kind']} | ${r['oracle']} | ${r['verdict']} | ${cell(r['missedVerdict'])} | '
      '${cell(r['correct'])} | ${cell(r['rootCauseCorrect'])} | ${cell(r['wrongCertain'])} | ${cell(r['strict'])} | '
      '${(r['items']! as List<Object?>).join('<br>')} |',
    );
  }
  File('build/catalogs/report.md').writeAsStringSync(md.toString());
  stdout.write(md);
}
