// Generated mutations on the catalogue (spec: Verification strategy). Each
// seed picks a scene and one render-level mutation; the oracle (pixels and
// semantics) says whether anything a user could notice changed, and the
// snapshot must then change too. Phase 2 measures the same at verdict level:
// the diff and the default policy must not pass a change the oracle saw, and
// the report's type for the mutated component is recorded against the types
// accepted for its kind (doc/phase2/expectations.md). A miss replays from its
// seed:
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

/// Accepted change types per mutation kind, from doc/phase2/expectations.md.
const Map<String, Set<String>> _accepted = <String, Set<String>>{
  'decoration colour': <String>{'Style'},
  'decoration radius': <String>{'Style'},
  'text colour': <String>{'Style'},
  'font weight': <String>{'Style'},
  'shape colour': <String>{'Style'},
  'opacity': <String>{'Style'},
  'clip radius': <String>{'Style'},
  'text': <String>{'Content'},
  'padding 1px': <String>{'Layout', 'Style'},
  'size 1px': <String>{'Layout', 'Style'},
  'flex alignment': <String>{'Layout', 'Style'},
  'transform': <String>{'Layout', 'Style'},
  'image': <String>{'Content', 'Style'},
  'custom painter removed': <String>{'Paint', 'Style'},
  'semantics label': <String>{'Semantics'},
};

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
          // The node's own fields: an ancestor's subtree hash and flattened
          // output always change.
          String own(SnapshotNode x) => x.line.split('\tsub=').first.replaceFirst('\tflat=${x.flat}', '');
          if (o == null || own(o) != own(n)) {
            changed.add(id);
          }
        }
        changed.addAll(a.keys);
      }
      final ChangeReport report = diffSnapshots(base.snapshot, after);
      final Verdict verdict = Policy.defaults().decide(report).verdict;
      final String kind = m.description.split(':').first;
      // Types on the owner, as top-level items or as the cause of a group.
      final Set<String> ownerTypes = <String>{
        for (final ReportItem i in report.items)
          if (i.change != null && i.change!.nodeId == owner) i.change!.type.label,
      };
      final bool ownerIsItem = ownerTypes.isNotEmpty;
      bool sitsIn(String id) => owner == id || owner.startsWith('$id/');
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
          'verdict': verdict.label,
          'missedVerdict': (pixels || semantics) && verdict == Verdict.pass,
          'items': <String>[
            for (final ReportItem i in report.items)
              i.change != null
                  ? '${i.change!.type.label} ${i.change!.nodeId}'
                  : 'Shift ${i.group!.ancestor.fullId}: ${i.group!.summary}',
          ],
          'ownerIsItem': ownerIsItem,
          'ownerTypes': ownerTypes.toList(),
          if (_accepted[kind] case final Set<String> accepted) 'typeAccepted': ownerTypes.any(accepted.contains),
          'groups': <Map<String, Object?>>[
            for (final ShiftGroup g in report.groups)
              <String, Object?>{
                'ancestor': g.ancestor.fullId,
                'cause': g.cause?.nodeId,
                'candidates': g.candidates.length,
                // A8 on generated mutations: the single cause is the mutated
                // component, or a component it sits in.
                if (g.cause != null) 'causeOk': sitsIn(g.cause!.nodeId),
              },
          ],
        }),
      );
      handle.dispose();
      expect((pixels || semantics) && !snapshot, isFalse, reason: 'missed: ${m.description} on $owner');
      expect(
        (pixels || semantics) && verdict == Verdict.pass,
        isFalse,
        reason: 'passed by the policy: ${m.description} on $owner',
      );
    });
  }

  tearDownAll(() {
    final dir = Directory('build/generated')..createSync(recursive: true);
    File('${dir.path}/results_${_start}_$_count.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
  });
}
