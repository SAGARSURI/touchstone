// Summarises A3 repeat runs: dart run tool/a3_summary.dart <dir>
//
// Reads every <label>.json written by test/a3/repeat_test.dart, where the
// label starts with the host (linux-3, macos-7, macosintel-0, linuxarm-0).
// Prints a Markdown table and two verdicts:
//
// - Phase 1 exit gate: every host ran its 1,000 repeats of every scene and
//   saw one snapshot per scene. The script exits non-zero if not, including
//   when a host is missing or ran fewer captures.
// - A3: every Mac host (labels starting with macos: arm64 and Intel) gave the
//   same snapshot of every scene. A failure here is A3's result, which takes
//   its fallback (baselines pinned to one host in the fingerprint), so it is
//   reported but does not fail the job.

import 'dart:convert';
import 'dart:io';

/// Hosts the workflow runs and the repeats each must complete.
const List<String> expectedHosts = <String>['linux', 'linuxarm', 'macos', 'macosintel'];
const int repeatsPerHost = 1000;

void main(List<String> args) {
  final dir = Directory(args.isEmpty ? 'build/a3' : args.first);
  final List<File> files =
      dir.listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.json')).toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  // os -> scene -> distinct hashes; os -> captures.
  final distinct = <String, Map<String, Set<String>>>{};
  final captures = <String, int>{};
  final repeats = <String, int>{};
  final toolchains = <String, Set<String>>{};
  for (final File f in files) {
    final json = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    final String os = (json['label']! as String).split('-').first;
    toolchains.putIfAbsent(os, () => <String>{}).add(jsonEncode(json['toolchain']));
    repeats[os] = (repeats[os] ?? 0) + (json['repeats']! as int);
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
    final int scenes = distinct[os]!.length;
    final bool complete = (repeats[os] ?? 0) >= repeatsPerHost && captures[os] == repeats[os]! * scenes;
    failed = failed || unstable.isNotEmpty || !complete;
    final int shards = files.where((File f) => f.uri.pathSegments.last.startsWith('$os-')).length;
    out.writeln(
      '| $os | $shards | ${captures[os]} | ${distinct[os]!.length} | '
      '${unstable.isEmpty ? 0 : unstable.join(', ')} |',
    );
  }
  final List<String> missing = <String>[
    for (final String host in expectedHosts)
      if (!distinct.containsKey(host) || (repeats[host] ?? 0) < repeatsPerHost) host,
  ];
  failed = failed || missing.isNotEmpty;
  // Each pair of hosts: the scenes whose snapshots differ between them.
  final List<String> hosts = distinct.keys.toList()..sort();
  for (var i = 0; i < hosts.length; i++) {
    for (var j = i + 1; j < hosts.length; j++) {
      final String a = hosts[i], b = hosts[j];
      final List<String> differ = <String>[
        for (final String scene in distinct[a]!.keys)
          if ((distinct[a]![scene]!.toList()..sort()).join() !=
              ((distinct[b]![scene] ?? <String>{}).toList()..sort()).join())
            scene,
      ];
      if (i == 0 && j == 1) {
        out.writeln();
      }
      out.writeln(
        'Across $a and $b: ${differ.isEmpty ? 'every scene identical' : '${differ.length} differ: ${differ.join(', ')}'} '
        '(informative; a baseline is compared only on its own host).',
      );
    }
  }
  final List<String> macs = <String>[
    for (final String h in hosts)
      if (h.startsWith('macos')) h,
  ];
  final List<String> macDiffer = <String>[
    if (macs.isNotEmpty)
      for (final String scene in distinct[macs.first]!.keys)
        if (macs.map((String h) => ((distinct[h]![scene] ?? <String>{}).toList()..sort()).join()).toSet().length > 1)
          scene,
  ];
  out
    ..writeln()
    ..writeln(
      'Exit gate (0 differing snapshots in $repeatsPerHost repeats per host): ${failed ? 'FAIL' : 'pass'}'
      '${missing.isEmpty ? '' : '; incomplete or missing: ${missing.join(', ')}'}',
    )
    ..writeln(
      'A3 (identical across Macs: ${macs.join(', ')}): '
      '${macs.length < 2
          ? 'not measured'
          : macDiffer.isEmpty
          ? 'pass'
          : 'FAIL on ${macDiffer.join(', ')}'}',
    );
  out
    ..writeln()
    ..writeln('Toolchains: ${toolchains.map((String os, Set<String> t) => MapEntry(os, t.join(' | ')))}');
  stdout.write(out);
  // Annotations make the result readable from the checks API as well.
  if (Platform.environment['GITHUB_ACTIONS'] == 'true') {
    for (final String line
        in out
            .toString()
            .split('\n')
            .where(
              (String l) =>
                  l.startsWith('|') || l.startsWith('Across') || l.startsWith('Exit gate') || l.startsWith('A3'),
            )) {
      stdout.writeln('::notice title=A3::$line');
    }
  }
  final String? summary = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summary != null) {
    File(summary).writeAsStringSync(out.toString(), mode: FileMode.append);
  }
  if (failed) {
    exitCode = 1;
  }
}
