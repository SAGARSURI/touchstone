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
  // os -> scene -> the first snapshot's canonical text.
  final snapshots = <String, Map<String, String>>{};
  final toolchains = <String, Set<String>>{};
  for (final File f in files) {
    final json = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    final String os = (json['label']! as String).split('-').first;
    toolchains.putIfAbsent(os, () => <String>{}).add(jsonEncode(json['toolchain']));
    repeats[os] = (repeats[os] ?? 0) + (json['repeats']! as int);
    (json['snapshots'] as Map<String, Object?>? ?? const <String, Object?>{}).forEach(
      (String scene, Object? text) => (snapshots[os] ??= <String, String>{}).putIfAbsent(scene, () => text! as String),
    );
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
  // Which nodes and fields differ between the Macs, scene by scene.
  if (macs.length > 1 && macDiffer.isNotEmpty) {
    out
      ..writeln()
      ..writeln('### Where ${macs.join(' and ')} differ')
      ..writeln();
    for (final String scene in macDiffer) {
      final String? a = snapshots[macs[0]]?[scene], b = snapshots[macs[1]]?[scene];
      if (a == null || b == null) {
        continue;
      }
      final List<String> nodes = nodeDifferences(a, b);
      out.writeln('- $scene: ${nodes.take(8).join('; ')}${nodes.length > 8 ? '; and ${nodes.length - 8} more' : ''}');
    }
  }
  out
    ..writeln()
    ..writeln('Toolchains: ${toolchains.map((String os, Set<String> t) => MapEntry(os, t.join(' | ')))}');
  stdout.write(out);
  // Annotations make the result readable from the checks API as well.
  // GitHub keeps at most 10 annotations of a kind per step, so the whole
  // summary goes in one, with its line breaks encoded.
  if (Platform.environment['GITHUB_ACTIONS'] == 'true') {
    final String body = out.toString().replaceAll('%', '%25').replaceAll('\r', '').replaceAll('\n', '%0A');
    stdout.writeln('::notice title=A3::$body');
  }
  final String? summary = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summary != null) {
    File(summary).writeAsStringSync(out.toString(), mode: FileMode.append);
  }
  if (failed) {
    exitCode = 1;
  }
}

/// Node ids whose own fields differ between two canonical snapshots, each
/// with the differing fields; a paint difference names the node's opaque
/// reason, since an opaque node's paint is a pixel hash.
List<String> nodeDifferences(String a, String b) {
  Map<String, Map<String, String>> nodes(String text) {
    final List<String> lines = const LineSplitter().convert(text);
    final out = <String, Map<String, String>>{};
    final path = <String>[];
    for (final String line in lines.skipWhile((String l) => l != 'nodes').skip(1)) {
      if (line.trim().isEmpty) {
        break;
      }
      final int depth = (line.length - line.trimLeft().length) ~/ 2;
      final List<String> parts = line.trimLeft().split('\t');
      path
        ..length = depth
        ..add(jsonDecode(parts.first) as String);
      out[path.join('/')] = <String, String>{
        for (final String p in parts.skip(1))
          if (p.contains('=')) p.substring(0, p.indexOf('=')): p.substring(p.indexOf('=') + 1),
      };
    }
    return out;
  }

  final Map<String, Map<String, String>> na = nodes(a), nb = nodes(b);
  final out = <String>[];
  for (final String id in <String>{...na.keys, ...nb.keys}) {
    final Map<String, String>? fa = na[id], fb = nb[id];
    if (fa == null || fb == null) {
      out.add('$id ${fa == null ? 'added' : 'removed'}');
      continue;
    }
    final List<String> fields = <String>[
      for (final String k in fa.keys)
        if (k != 'sub' && fa[k] != fb[k]) k == 'paint' ? 'paint (opaque=${fa['opaque']})' : k,
    ];
    if (fields.isNotEmpty) {
      out.add('$id: ${fields.join(', ')}');
    }
  }
  return out;
}
