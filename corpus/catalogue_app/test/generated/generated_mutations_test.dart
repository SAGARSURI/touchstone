// Generated mutations on the catalogue (spec: Verification strategy). Each
// seed picks a scene and one render-level mutation; the oracle (pixels and
// semantics) says whether anything a user could notice changed, and the
// snapshot must then change too. A miss replays from its seed:
//
//   flutter test test/generated --dart-define=GEN_START=<seed> --dart-define=GEN_COUNT=1
//
// Results go to build/generated/results_<start>_<count>.json.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

import '../support/oracle.dart';
import '../support/scenes.dart';
import 'mutator.dart';

const int _start = int.fromEnvironment('GEN_START');
const int _count = int.fromEnvironment('GEN_COUNT', defaultValue: 100);

class _Base {
  _Base(this.oracle, this.snapshot);

  final Oracle oracle;
  final Snapshot snapshot;
}

void main() {
  final results = <Map<String, Object?>>[];
  final bases = <String, _Base>{};

  for (int seed = _start; seed < _start + _count; seed++) {
    testWidgets('seed $seed', (WidgetTester tester) async {
      final random = Random(seed);
      final Scene scene = scenes[random.nextInt(scenes.length)];
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpScene(tester, scene);
      final _Base base = bases[scene.id] ??= _Base(
        await readOracle(tester),
        await captureSnapshot(tester, scene.id, options: scene.options),
      );

      final AppliedMutation? m = mutate(tester.binding.renderViews.first, random);
      final result = <String, Object?>{'seed': seed, 'scene': scene.id};
      if (m == null) {
        results.add(result..['applied'] = false);
        handle.dispose();
        return;
      }
      await tester.pump();
      final Oracle oracle = await readOracle(tester);
      final Capture capture = await captureWithDetails(tester, scene.id, options: scene.options);
      final Snapshot after = capture.snapshot;
      final bool pixels = oracle.pixels != base.oracle.pixels;
      final bool semantics = oracle.semantics != base.oracle.semantics;
      final bool snapshot = after.rootHash != base.snapshot.rootHash;
      final String owner = capture.tree.shownOwnerOf(m.target).fullId;
      final changed = <String>{};
      if (snapshot) {
        final Map<String, SnapshotNode> a = <String, SnapshotNode>{
          for (final (String id, SnapshotNode n) in base.snapshot.walk()) id: n,
        };
        for (final (String id, SnapshotNode n) in after.walk()) {
          final SnapshotNode? o = a.remove(id);
          if (o == null || o.line != n.line) {
            changed.add(id);
          }
        }
        changed.addAll(a.keys);
      }
      results.add(
        result..addAll(<String, Object?>{
          'applied': true,
          'mutation': m.description,
          'target': m.target.runtimeType.toString(),
          'owner': owner,
          'pixelsChanged': pixels,
          'semanticsChanged': semantics,
          'snapshotChanged': snapshot,
          'missed': (pixels || semantics) && !snapshot,
          'ownerChanged': changed.contains(owner),
          if (snapshot) 'firstNode': firstDifference(base.snapshot.toCanonical(), after.toCanonical()).nodeId,
        }),
      );
      handle.dispose();
      expect((pixels || semantics) && !snapshot, isFalse, reason: 'missed: ${m.description} on $owner');
    });
  }

  tearDownAll(() {
    final dir = Directory('build/generated')..createSync(recursive: true);
    File('${dir.path}/results_${_start}_$_count.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
  });
}
