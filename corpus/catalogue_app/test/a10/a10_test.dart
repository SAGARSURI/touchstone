// A10: what capture costs on the catalogue (doc/phase3/a10_expectations.md).
// Runs only when asked:
//
//   flutter test test/a10/a10_test.dart --dart-define=A10_MODE=record
//   flutter test test/a10/a10_test.dart --dart-define=A10_MODE=plain
//   flutter test test/a10/a10_test.dart --dart-define=A10_MODE=capture
//   flutter test test/a10/a10_test.dart --dart-define=A10_MODE=compare
//
// `plain` pumps each scene as snapshots_test.dart does. `capture` also does
// what expectSnapshot does for an unchanged snapshot: read the baseline,
// parse it, capture the detection fields, compare root hashes and toolchains. `compare` does the
// same, then times the comparison alone, with the parse, and with reading the file over 1,000 rounds,
// so it is kept out of the wall time of `capture`. `record` writes the
// baselines that `capture` compares against into build/a10/, since the
// committed ones are macOS baselines. Per-scene stopwatch times go to
// build/a10/<mode>.json.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/src/snapshot/capture.dart' show captureDetectionOnly;
import 'package:touchstone/touchstone.dart';

import '../support/scenes.dart';

const String _mode = String.fromEnvironment('A10_MODE');

File _baseline(Scene scene) => File('build/a10/snapshots/${scene.id.replaceAll('/', '__')}.snapshot');

void main() {
  final times = <String, Map<String, int>>{};

  for (final Scene scene in scenes) {
    testWidgets(scene.id, skip: _mode.isEmpty, (WidgetTester tester) async {
      final pump = Stopwatch()..start();
      await pumpScene(tester, scene);
      pump.stop();
      final row = <String, int>{'pumpUs': pump.elapsedMicroseconds};
      switch (_mode) {
        case 'record':
          final Snapshot s = await captureSnapshot(tester, scene.id, options: scene.options);
          _baseline(scene)
            ..parent.createSync(recursive: true)
            ..writeAsStringSync(s.toCanonical());
        case 'capture' || 'compare':
          final check = Stopwatch()..start();
          // Read as expectSnapshot reads it.
          final Snapshot baseline = Snapshot.parseBytes(_baseline(scene).readAsBytesSync());
          final Snapshot capture = await captureDetectionOnly(tester, scene.id, options: scene.options);
          final bool equal =
              baseline.rootHash == capture.rootHash && baseline.toolchain.toString() == capture.toolchain.toString();
          check.stop();
          expect(equal, isTrue, reason: '${scene.id} differs from the snapshot recorded in build/a10');
          row['captureUs'] = check.elapsedMicroseconds;
          if (_mode == 'capture') {
            break;
          }

          // The comparison alone, with the parse, and with reading the file
          // too, over 1,000 rounds.
          final Uint8List bytes = _baseline(scene).readAsBytesSync();
          final compare = Stopwatch()..start();
          var same = 0;
          for (var i = 0; i < 1000; i++) {
            if (baseline.rootHash == capture.rootHash &&
                baseline.toolchain.toString() == capture.toolchain.toString()) {
              same++;
            }
          }
          compare.stop();
          final parsed = Stopwatch()..start();
          for (var i = 0; i < 1000; i++) {
            final Snapshot b = Snapshot.parseBytes(bytes);
            if (b.rootHash == capture.rootHash && b.toolchain.toString() == capture.toolchain.toString()) {
              same++;
            }
          }
          parsed.stop();
          final read = Stopwatch()..start();
          for (var i = 0; i < 1000; i++) {
            final Snapshot b = Snapshot.parseBytes(_baseline(scene).readAsBytesSync());
            if (b.rootHash == capture.rootHash && b.toolchain.toString() == capture.toolchain.toString()) {
              same++;
            }
          }
          read.stop();
          expect(same, 3000);
          row['compareNsPerRound'] = compare.elapsedMicroseconds;
          row['parseAndCompareUsPerRound'] = parsed.elapsedMicroseconds ~/ 1000;
          row['readParseAndCompareUsPerRound'] = read.elapsedMicroseconds ~/ 1000;
      }
      times[scene.id] = row;
    });
  }

  tearDownAll(() {
    if (_mode.isEmpty) {
      return;
    }
    File('build/a10/$_mode.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(times));
  });
}
