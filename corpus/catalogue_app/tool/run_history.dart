// Runs the catalogue history, changes 1 to 9, as doc/phase3/history_expectations.md
// says, and writes build/history/results.json and one report per change in
// build/history/<n>/report.txt.
//
//   dart run tool/run_history.dart [--score-only]
//
// Changes apply to the source in place, each on top of the ones before it,
// and the source is always restored. Changes 6 and 9 are expected to fail and
// are not merged: they are undone before the next change. Change 10 (a Flutter
// upgrade) runs separately.

import 'dart:convert';
import 'dart:io';

import 'package:touchstone/diff.dart';

import 'catalogs.dart' show Edit;
import 'history.dart' as h1;
import 'history_phase3.dart' as h3;

class _Step {
  _Step(this.number, this.title, this.edits, {this.declared = ''});

  final int number;
  final String title;
  final List<Edit> edits;
  final String declared;

  bool get merged => number != 6 && number != 9;
}

final List<_Step> _steps = <_Step>[
  for (final h1.Change c in h1.history) _Step(c.number, c.title, c.edits),
  for (final h3.Change c in h3.historyPhase3)
    if (c.toolchain == null) _Step(c.number, c.title, c.edits, declared: c.declared),
];

Future<void> _probe(String out) async {
  final ProcessResult r = await Process.run('flutter', <String>[
    'test',
    'test/probe/history_probe_test.dart',
    '--dart-define=PROBE_OUT=$out',
  ]);
  if (r.exitCode != 0) {
    throw StateError('history probe failed for $out:\n${r.stdout}\n${r.stderr}');
  }
}

Map<String, Map<String, Object?>> _read(String dir) => <String, Map<String, Object?>>{
  for (final FileSystemEntity f in Directory(dir).listSync())
    if (f is File && f.path.endsWith('.json'))
      (jsonDecode(f.readAsStringSync()) as Map<String, Object?>)['scene']! as String:
          jsonDecode(f.readAsStringSync()) as Map<String, Object?>,
};

void _apply(List<Edit> edits) {
  for (final Edit edit in edits) {
    final file = File(edit.file);
    final String text = file.readAsStringSync();
    final int count = edit.find.allMatches(text).length;
    if (count == 0 || (!edit.all && count != 1)) {
      throw StateError('expected one "${edit.find}" in ${edit.file}, found $count');
    }
    file.writeAsStringSync(text.replaceAll(edit.find, edit.replace));
  }
}

Map<String, String> _snapshotFiles(List<Edit> edits) => <String, String>{
  for (final Edit e in edits) e.file: File(e.file).readAsStringSync(),
};

/// Scores one change: [before] and [after] are the probe outputs.
Map<String, Object?> _score(
  _Step step,
  Map<String, Map<String, Object?>> before,
  Map<String, Map<String, Object?>> after,
) {
  final Policy policy = step.declared.isEmpty
      ? Policy.defaults()
      : Policy.parse(step.declared, source: 'change ${step.number} expectations');
  final text = StringBuffer('Change ${step.number}: ${step.title}\n\n');
  final scenes = <Map<String, Object?>>[];
  var items = 0;
  var flagged = 0;
  final wrongCertain = <String>[];
  for (final String id in after.keys.toList()..sort()) {
    final Map<String, Object?> a = after[id]!;
    final Map<String, Object?> b = before[id]!;
    final row = <String, Object?>{'scene': id};
    if (a['failure'] != null) {
      row['failure'] = a['failure'];
      row['verdict'] = Verdict.fail.label;
      text.writeln('== $id: capture failed: ${jsonEncode(a['failure'])}\n');
      scenes.add(row);
      continue;
    }
    final bool pixels = a['pixels'] != b['pixels'];
    final bool semantics = a['semantics'] != b['semantics'];
    final bool snapshot = a['rootHash'] != b['rootHash'];
    final ChangeReport r = diffSnapshots(
      Snapshot.parse(b['snapshot']! as String),
      Snapshot.parse(a['snapshot']! as String),
    );
    final Decision d = policy.decide(r);
    row.addAll(<String, Object?>{
      'pixelsChanged': pixels,
      'semanticsChanged': semantics,
      'snapshotChanged': snapshot,
      'gap': (pixels || semantics) && !snapshot,
      'verdict': d.verdict.label,
      'items': <String>[
        for (final ReportItem i in r.items)
          i.change != null
              ? '${i.flagged ? 'Unexplained ' : ''}${i.change!.type.label} ${i.change!.nodeId}'
              : 'Shift ${i.group!.ancestor.fullId}: ${i.group!.summary}, '
                    '${i.group!.candidates.isEmpty ? 'cause unknown' : '${i.group!.candidates.length} possible causes'}',
      ],
      'groups': <String>[
        for (final ShiftGroup g in r.groups)
          '${g.summary} under ${g.ancestor.fullId}: '
              '${g.cause != null ? 'cause ${g.cause!.type.label} ${g.cause!.nodeId}' : '${g.candidates.length} candidates'}',
      ],
      'reasons': d.reasons,
    });
    if (snapshot) {
      items += r.items.length;
      flagged += r.items.where((ReportItem i) => i.flagged).length;
      text
        ..writeln('== $id')
        ..writeln(renderReport(r, d));
    }
    for (final ShiftGroup g in r.groups) {
      if (g.cause != null) {
        // Recorded for review: whether the single cause is the edited
        // component or one it sits in is judged per change.
        wrongCertain.add('$id: ${g.cause!.type.label} ${g.cause!.nodeId}');
      }
    }
    scenes.add(row);
  }
  Directory('build/history/${step.number}').createSync(recursive: true);
  File('build/history/${step.number}/report.txt').writeAsStringSync(text.toString());
  bool all(String k) => scenes.any((Map<String, Object?> s) => s[k] == true);
  return <String, Object?>{
    'change': step.number,
    'title': step.title,
    'merged': step.merged,
    'gaps': <String>[
      for (final s in scenes)
        if (s['gap'] == true) s['scene']! as String,
    ],
    'changedSnapshots': scenes.where((Map<String, Object?> s) => s['snapshotChanged'] == true).length,
    'failedCaptures': scenes.where((Map<String, Object?> s) => s['failure'] != null).length,
    'anyOracleChange': all('pixelsChanged') || all('semanticsChanged'),
    'items': items,
    'unexplained': flagged,
    'singleCauses': wrongCertain,
    'scenes': scenes,
  };
}

Future<void> main(List<String> args) async {
  final bool scoreOnly = args.contains('--score-only');
  final originals = <String, String>{};
  for (final _Step s in _steps) {
    for (final Edit e in s.edits) {
      originals.putIfAbsent(e.file, () => File(e.file).readAsStringSync());
    }
  }
  final results = <Map<String, Object?>>[];
  try {
    if (!scoreOnly) {
      stdout.writeln('step 0: the catalogue as committed');
      await _probe('build/history/0');
    }
    var previous = 'build/history/0';
    for (final _Step step in _steps) {
      final Map<String, String> undo = _snapshotFiles(step.edits);
      _apply(step.edits);
      final out = 'build/history/${step.number}';
      if (!scoreOnly) {
        stdout.writeln('change ${step.number}: ${step.title}');
        await _probe(out);
      }
      results.add(_score(step, _read(previous), _read(out)));
      if (step.merged) {
        previous = out;
      } else {
        undo.forEach((String path, String text) => File(path).writeAsStringSync(text));
      }
    }
  } finally {
    originals.forEach((String path, String text) => File(path).writeAsStringSync(text));
  }
  final int items = results.fold(0, (int n, Map<String, Object?> r) => n + (r['items']! as int));
  final int flagged = results.fold(0, (int n, Map<String, Object?> r) => n + (r['unexplained']! as int));
  final summary = <String, Object?>{
    'gaps': results.fold<int>(0, (int n, Map<String, Object?> r) => n + (r['gaps']! as List<Object?>).length),
    'items': items,
    'unexplained': flagged,
    'unexplainedRate': items == 0 ? 0 : flagged / items,
  };
  File('build/history/results.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{'summary': summary, 'changes': results}),
  );
  stdout.writeln(jsonEncode(summary));
}
