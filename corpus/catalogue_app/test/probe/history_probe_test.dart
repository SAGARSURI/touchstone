// Captures every catalogue scene with its oracle and the determinism gate,
// for one step of the catalogue history (tool/run_history.dart). Run by that
// tool, not on its own:
//
//   flutter test test/probe/history_probe_test.dart --dart-define=PROBE_OUT=build/history/<step>
//
// A scene that cannot be captured (it never settles, or the determinism gate
// fails) is written with the failure instead of a snapshot.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

import '../support/oracle.dart';
import '../support/scenes.dart';

const String _out = String.fromEnvironment('PROBE_OUT');

void main() {
  if (_out.isEmpty) {
    test('history probe needs PROBE_OUT', () {}, skip: 'run by tool/run_history.dart');
    return;
  }
  for (final Scene scene in scenes) {
    testWidgets(scene.id, (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final result = <String, Object?>{'scene': scene.id};
      try {
        try {
          await pumpScene(tester, scene);
        } on CaptureFailure {
          // The scene's own settle gave up. The capture below fails too, and
          // names the node that keeps scheduling frames.
        }
        final DeterminismReport gate = await checkDeterminism(tester, scene.id, options: scene.options);
        if (!gate.deterministic) {
          final SnapshotDifference d = gate.firstDifference!;
          result['failure'] = <String, Object?>{'node': d.nodeId, 'fields': d.fields, 'cause': d.cause};
        } else {
          final Oracle oracle = await readOracle(tester);
          final Snapshot snapshot = await captureSnapshot(tester, scene.id, options: scene.options);
          result.addAll(<String, Object?>{
            ...oracle.toJson(),
            'rootHash': snapshot.rootHash,
            'snapshot': snapshot.toCanonical(),
          });
        }
      } on CaptureFailure catch (e) {
        result['failure'] = <String, Object?>{
          'node': e.difference?.nodeId,
          'fields': e.difference?.fields,
          'cause': e.difference?.cause ?? e.message,
        };
      }
      File('$_out/${scene.id.replaceAll('/', '__')}.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
      handle.dispose();
    });
  }
}
