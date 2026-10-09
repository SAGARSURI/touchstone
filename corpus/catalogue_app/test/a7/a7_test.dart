// A7, the tool's side (doc/phase3/a7_expectations.md): the generated
// mutations of seeds 0 to 299, with the default test font or with the fonts the
// app draws with. Runs only when asked:
//
//   flutter test test/a7 --dart-define=A7_FONTS=default
//   flutter test test/a7 --dart-define=A7_FONTS=real
//
// Per seed: the scene, the mutation, whether the snapshot changed and the
// default policy's verdict, and whether the test environment's pixels and
// semantics changed. Results go to build/a7/<fonts>.json. The device's side
// is integration_test/a7_device_test.dart.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

import '../generated/mutator.dart';
import '../support/oracle.dart';
import '../support/scenes.dart';
import 'a7_seeds.dart';

const String _fonts = String.fromEnvironment('A7_FONTS');

/// The fonts the app draws with, from the files the Flutter SDK ships: Roboto
/// for Material's Android typography, and Material Icons.
Future<void> _loadRealFonts() async {
  final String root = Platform.environment['FLUTTER_ROOT'] ?? (throw StateError('FLUTTER_ROOT is not set'));
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  final List<File> roboto =
      dir.listSync().whereType<File>().where((File f) => RegExp(r'/Roboto-\w+\.ttf$').hasMatch(f.path)).toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  await SnapshotFonts.load('Roboto', <Uint8List>[for (final File f in roboto) f.readAsBytesSync()]);
  await SnapshotFonts.load('MaterialIcons', <Uint8List>[
    File('${dir.path}/MaterialIcons-Regular.otf').readAsBytesSync(),
  ]);
}

class _Base {
  _Base(this.oracle, this.snapshot);

  final Oracle oracle;
  final Snapshot snapshot;
}

void main() {
  final results = <Map<String, Object?>>[];
  final bases = <String, _Base>{};

  sceneScrollBehavior = a7ScrollBehavior;
  setUpAll(() async {
    if (_fonts == 'real') {
      await _loadRealFonts();
    }
  });

  for (int seed = a7FirstSeed; seed < a7FirstSeed + a7SeedCount; seed++) {
    testWidgets('seed $seed', skip: _fonts.isEmpty, (WidgetTester tester) async {
      final random = Random(seed);
      final Scene scene = scenes[random.nextInt(scenes.length)];
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpScene(tester, scene);
      final _Base base = bases[scene.id] ??= _Base(
        await readOracle(tester),
        await captureSnapshot(tester, scene.id, options: scene.options),
      );
      final AppliedMutation? m = mutate(tester.binding.renderViews.first, random);
      final row = <String, Object?>{'seed': seed, 'scene': scene.id};
      if (m != null) {
        await tester.pump();
        final Oracle oracle = await readOracle(tester);
        final Snapshot after = await captureSnapshot(tester, scene.id, options: scene.options);
        row.addAll(<String, Object?>{
          'mutation': m.description,
          'snapshotChanged': after.rootHash != base.snapshot.rootHash,
          'verdict': Policy.defaults().decide(diffSnapshots(base.snapshot, after)).verdict.label,
          'pixelsChanged': oracle.pixels != base.oracle.pixels,
          'semanticsChanged': oracle.semantics != base.oracle.semantics,
        });
      }
      results.add(row);
      handle.dispose();
    });
  }

  tearDownAll(() {
    if (_fonts.isEmpty) {
      return;
    }
    File('build/a7/$_fonts.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
  });
}
