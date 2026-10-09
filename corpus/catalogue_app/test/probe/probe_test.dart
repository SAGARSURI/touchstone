// Captures catalogue scenes with their oracle, for the mutation and no-op
// catalogs (tool/run_catalogs.dart). Run by that tool, not on its own:
//
//   flutter test test/probe/probe_test.dart \
//     --dart-define=PROBE_SCENES=settings/default,... \
//     --dart-define=PROBE_OUT=build/catalogs/<entry> [--dart-define=PROBE_BASE=build/catalogs/base]
//
// With PROBE_BASE, each scene is compared with the base capture and the
// differences are written next to it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

import '../support/oracle.dart';
import '../support/cascade_stack.dart';
import '../support/scenes.dart';

const String _scenes = String.fromEnvironment('PROBE_SCENES');
const String _out = String.fromEnvironment('PROBE_OUT');
const String _base = String.fromEnvironment('PROBE_BASE');

/// Every node whose detection or explanation fields differ, matched by id.
List<Map<String, Object?>> nodeDifferences(Snapshot a, Snapshot b) {
  final Map<String, SnapshotNode> na = <String, SnapshotNode>{
    for (final (String id, SnapshotNode n) in a.walk()) id: n,
  };
  final Map<String, SnapshotNode> nb = <String, SnapshotNode>{
    for (final (String id, SnapshotNode n) in b.walk()) id: n,
  };
  return <Map<String, Object?>>[
    for (final String id in <String>{...na.keys, ...nb.keys})
      if (!na.containsKey(id))
        <String, Object?>{'node': id, 'change': 'added', 'type': nb[id]!.type}
      else if (!nb.containsKey(id))
        <String, Object?>{'node': id, 'change': 'removed', 'type': na[id]!.type}
      else if (<String>[
            if (na[id]!.bounds != nb[id]!.bounds) 'bounds',
            if (na[id]!.paint != nb[id]!.paint) 'paint',
            if (na[id]!.semantics != nb[id]!.semantics) 'semantics',
            if (na[id]!.opaque != nb[id]!.opaque) 'opaque',
            if (na[id]!.type != nb[id]!.type) 'type',
            if (na[id]!.style != nb[id]!.style) 'style',
          ]
          case final List<String> fields when fields.isNotEmpty)
        <String, Object?>{'node': id, 'change': 'changed', 'fields': fields, 'type': nb[id]!.type},
  ];
}

void main() {
  if (_scenes.isEmpty || _out.isEmpty) {
    test('probe needs PROBE_SCENES and PROBE_OUT', () {}, skip: 'run by tool/run_catalogs.dart');
    return;
  }
  for (final String id in _scenes.split(',')) {
    final Scene scene = <Scene>[...scenes, ...experimentScenes].firstWhere((Scene s) => s.id == id);
    testWidgets(id, (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpScene(tester, scene);
      final Oracle oracle = await readOracle(tester);
      final Snapshot snapshot = await captureSnapshot(tester, id, options: scene.options);
      final file = File('$_out/${id.replaceAll('/', '__')}.json')..parent.createSync(recursive: true);
      final result = <String, Object?>{
        'scene': id,
        ...oracle.toJson(),
        'rootHash': snapshot.rootHash,
        'snapshot': snapshot.toCanonical(),
      };
      final baseFile = File('$_base/${id.replaceAll('/', '__')}.json');
      if (_base.isNotEmpty && baseFile.existsSync()) {
        final base = jsonDecode(baseFile.readAsStringSync()) as Map<String, Object?>;
        final Snapshot before = Snapshot.parse(base['snapshot']! as String);
        result['compare'] = <String, Object?>{
          'pixelsChanged': base['pixels'] != oracle.pixels,
          'semanticsChanged': base['semantics'] != oracle.semantics,
          'snapshotChanged': before.rootHash != snapshot.rootHash,
          if (before.rootHash != snapshot.rootHash) ...<String, Object?>{
            'firstNode': firstDifference(before.toCanonical(), snapshot.toCanonical()).nodeId,
            'nodes': nodeDifferences(before, snapshot),
          },
        };
      }
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
      handle.dispose();
    });
  }
}
