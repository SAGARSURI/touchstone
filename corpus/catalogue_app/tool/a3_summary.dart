// Summarises A3 repeat runs: dart run tool/a3_summary.dart <dir>
//
// Reads every <label>.json written by test/a3/repeat_test.dart, where the
// label starts with the operating system (linux-3, macos-7). Prints a
// Markdown table and exits non-zero if any operating system saw two
// different snapshots of one scene. Agreement between operating systems is
// reported but is not part of the gate.

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final dir = Directory(args.isEmpty ? 'build/a3' : args.first);
  final List<File> files =
      dir.listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.json')).toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  // os -> scene -> distinct hashes; os -> captures.
  final distinct = <String, Map<String, Set<String>>>{};
  final captures = <String, int>{};
  final toolchains = <String, Set<String>>{};
  for (final File f in files) {
    final json = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    final String os = (json['label']! as String).split('-').first;
    toolchains.putIfAbsent(os, () => <String>{}).add(jsonEncode(json['toolchain']));
    (json['hashes']! as Map<String, Object?>).forEach((String scene, Object? list) {
      final List<String> hashes = (list! as List<Object?>).cast<String>();
      distinct.putIfAbsent(os, () => <String, Set<String>>{}).putIfAbsent(scene, () => <String>{}).addAll(hashes);
      captures[os] = (captures[os] ?? 0) + hashes.length;
    });
  }
  var failed = false;
  final out = StringBuffer()
    ..writeln('## A3: repeat runs')
    ..writeln()
    ..writeln('| OS | Shards | Captures | Scenes | Scenes with more than one snapshot |')
    ..writeln('| --- | --- | --- | --- | --- |');
  for (final String os in distinct.keys.toList()..sort()) {
    final List<String> unstable = <String>[
      for (final MapEntry<String, Set<String>> e in distinct[os]!.entries)
        if (e.value.length > 1) e.key,
    ];
    failed = failed || unstable.isNotEmpty;
    final int shards = files.where((File f) => f.uri.pathSegments.last.startsWith('$os-')).length;
    out.writeln(
      '| $os | $shards | ${captures[os]} | ${distinct[os]!.length} | '
      '${unstable.isEmpty ? 0 : unstable.join(', ')} |',
    );
  }
  if (distinct.length > 1) {
    final List<String> oses = distinct.keys.toList()..sort();
    final Set<String> scenes = distinct[oses.first]!.keys.toSet();
    final List<String> differ = <String>[
      for (final String scene in scenes)
        if (oses.map((String os) => (distinct[os]![scene] ?? <String>{}).join()).toSet().length > 1) scene,
    ];
    out
      ..writeln()
      ..writeln(
        'Across ${oses.join(' and ')}: ${differ.isEmpty ? 'every scene identical' : 'differ on ${differ.join(', ')}'} '
        '(informative; baselines are valid on one OS).',
      );
  }
  out
    ..writeln()
    ..writeln('Toolchains: ${toolchains.map((String os, Set<String> t) => MapEntry(os, t.join(' | ')))}');
  stdout.write(out);
  final String? summary = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summary != null) {
    File(summary).writeAsStringSync(out.toString(), mode: FileMode.append);
  }
  if (failed) {
    exitCode = 1;
  }
}
