// A3: snapshots are byte-identical across runs and machines (spec,
// Assumption register). Each repeat pumps every catalogue scene from scratch
// and captures it. Results go to build/a3/<label>.json; tool/a3_summary.dart
// compares them across repeats, shards and operating systems.
//
//   flutter test test/a3 --dart-define=REPEATS=100 --dart-define=LABEL=linux-0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

import '../support/scenes.dart';

const int _repeats = int.fromEnvironment('REPEATS', defaultValue: 2);
const String _label = String.fromEnvironment('LABEL', defaultValue: 'local');

void main() {
  final hashes = <String, List<String>>{};
  final first = <String, String>{};

  for (var r = 0; r < _repeats; r++) {
    for (final Scene scene in scenes) {
      testWidgets('repeat $r ${scene.id}', (WidgetTester tester) async {
        await pumpScene(tester, scene);
        final Snapshot s = await captureSnapshot(tester, scene.id, options: scene.options);
        (hashes[scene.id] ??= <String>[]).add(s.rootHash);
        first.putIfAbsent(scene.id, s.toCanonical);
        // A repeat that differs from this run's first capture fails at once.
        if (first[scene.id] != s.toCanonical()) {
          fail(
            'repeat $r of ${scene.id} differs from repeat 0.\n'
            '${firstDifference(first[scene.id]!, s.toCanonical())}',
          );
        }
      });
    }
  }

  tearDownAll(() {
    final dir = Directory('build/a3')..createSync(recursive: true);
    File('${dir.path}/$_label.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'label': _label,
        'repeats': _repeats,
        'toolchain': toolchainFingerprint(),
        'hashes': hashes,
        'snapshots': first,
      }),
    );
  });
}
