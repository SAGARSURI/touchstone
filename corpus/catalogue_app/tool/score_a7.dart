// Scores A7 (doc/phase3/a7_expectations.md) from the three runs' outputs:
//
//   dart run tool/score_a7.dart <default.json> <real.json> <device output>
//
// The device output is the text `flutter test` printed for
// integration_test/a7_device_test.dart: one `A7 {json}` line per seed.

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln('Usage: dart run tool/score_a7.dart <default.json> <real.json> <device output>');
    exit(64);
  }
  List<Map<String, Object?>> rows(String path) =>
      (jsonDecode(File(path).readAsStringSync()) as List<Object?>).cast<Map<String, Object?>>();
  final Map<int, Map<String, Object?>> byDefault = {for (final r in rows(args[0])) r['seed']! as int: r};
  final Map<int, Map<String, Object?>> byReal = {for (final r in rows(args[1])) r['seed']! as int: r};
  final device = <int, Map<String, Object?>>{};
  for (final String line in File(args[2]).readAsLinesSync()) {
    final int at = line.indexOf('A7 {');
    if (at >= 0) {
      final r = jsonDecode(line.substring(at + 3)) as Map<String, Object?>;
      device[r['seed']! as int] = r;
    }
  }

  var applied = 0;
  final mismatched = <String>[];
  final noisy = <String>{};
  var noisyCount = 0;
  final scored = <int>[];
  for (final int seed in device.keys.toList()..sort()) {
    final Map<String, Object?> d = device[seed]!;
    final Map<String, Object?>? a = byDefault[seed];
    final Map<String, Object?>? b = byReal[seed];
    if (d['mutation'] == null && a?['mutation'] == null && b?['mutation'] == null) {
      continue;
    }
    applied++;
    String short(Object? m) {
      final s = '$m';
      return s.length > 120 ? '${s.substring(0, 120)}...' : s;
    }

    if (a == null ||
        b == null ||
        d['scene'] != a['scene'] ||
        short(a['mutation']) != d['mutation'] ||
        b['mutation'] != a['mutation']) {
      mismatched.add(
        '$seed ${d['scene']}: device "${d['mutation']}", default "${short(a?['mutation'])}", '
        'real "${short(b?['mutation'])}"',
      );
      continue;
    }
    if (d['noisy'] == true) {
      noisy.add('${d['scene']}');
      noisyCount++;
      continue;
    }
    scored.add(seed);
  }

  bool visible(int s) => device[s]!['pixelsChanged'] == true || device[s]!['semanticsChanged'] == true;
  bool reported(Map<String, Object?> r) => r['snapshotChanged'] == true && r['verdict'] != 'pass';
  final List<int> deviceVisible = scored.where(visible).toList();
  String line(int s, Map<String, Object?> r) =>
      '$s ${r['scene']}: ${r['mutation']} (snapshot changed ${r['snapshotChanged']}, verdict ${r['verdict']}; '
      'device pixels ${device[s]!['pixelsChanged']}, semantics ${device[s]!['semanticsChanged']})';

  final out = StringBuffer()
    ..writeln('Seeds on the device: ${device.length}; mutations applied: $applied')
    ..writeln('Matched across the three runs: ${applied - mismatched.length} of $applied')
    ..writeln('Left out as noisy on the device: $noisyCount (scenes: ${(noisy.toList()..sort()).join(', ')})')
    ..writeln('Scored: ${scored.length}; device-visible: ${deviceVisible.length}')
    ..writeln();
  for (final (String name, Map<int, Map<String, Object?>> run) in <(String, Map<int, Map<String, Object?>>)>[
    ('Real fonts', byReal),
    ('Default font', byDefault),
  ]) {
    final List<int> misses = deviceVisible.where((int s) => !reported(run[s]!)).toList();
    final List<int> reverse = scored.where((int s) => !visible(s) && run[s]!['snapshotChanged'] == true).toList();
    out
      ..writeln('$name: ${misses.length} misses of ${deviceVisible.length} device-visible mutations')
      ..writeAll(<String>[for (final int s in misses) '  miss ${line(s, run[s]!)}\n'])
      ..writeln('$name, the reverse: ${reverse.length} reported changes the device did not show')
      ..writeAll(<String>[for (final int s in reverse) '  ${line(s, run[s]!)}\n'])
      ..writeln();
  }
  out
    ..writeln('Mismatched seeds:')
    ..writeAll(<String>[for (final String m in mismatched) '  $m\n']);
  stdout.write(out);
}
