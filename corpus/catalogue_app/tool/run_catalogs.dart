// Runs the mutation and no-op catalogs (tool/catalogs.dart) and writes
// build/catalogs/report.json and build/catalogs/report.md.
//
//   dart run tool/run_catalogs.dart [entry-id ...]
//
// Each entry is applied to the source in place and always restored, then the
// probe test captures its scenes and compares them with an unedited run.

import 'dart:convert';
import 'dart:io';

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

Future<Map<String, Object?>> _run(Entry e, String base, bool noOp) async {
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
    await _probe(e.scenes, out, base: base);
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
      if (e.expectNode != null)
        'attributed': firstNodes.isNotEmpty && firstNodes.every((String n) => typeOf(n) == e.expectNode),
      'firstNodes': firstNodes,
      'scenes': scenes,
    };
  } finally {
    originals.forEach((String path, String text) => File(path).writeAsStringSync(text));
  }
}

Future<void> main(List<String> args) async {
  final List<Entry> all = <Entry>[...mutations, ...noOps];
  final List<Entry> chosen = args.isEmpty ? all : all.where((Entry e) => args.contains(e.id)).toList();
  final List<String> sceneIds = <String>{for (final Entry e in chosen) ...e.scenes}.toList();
  const base = 'build/catalogs/base';
  await _probe(sceneIds, base);
  final results = <Map<String, Object?>>[];
  for (final Entry e in chosen) {
    stdout.writeln('running ${e.id}');
    results.add(await _run(e, base, noOps.contains(e)));
  }
  File('build/catalogs/report.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));

  final md = StringBuffer()
    ..writeln('| Entry | Kind | Oracle expected | Oracle saw | Snapshot changed | Missed | First differing node |')
    ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
  for (final r in results) {
    md.writeln(
      '| ${r['id']} | ${r['kind']} | ${r['expectedOracle']} | ${r['oracle']} | ${r['snapshotChanged']} | '
      '${r['missed'] ?? 'n/a'} | ${(r['firstNodes']! as List<Object?>).join('<br>')} |',
    );
  }
  File('build/catalogs/report.md').writeAsStringSync(md.toString());
  stdout.write(md);
}
