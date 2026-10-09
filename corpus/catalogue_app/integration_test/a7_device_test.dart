// A7, the device's side (doc/phase3/a7_expectations.md): the same seeds as
// test/a7/a7_test.dart, on a device or simulator, with the app's fonts
// bundled. Per seed: the scene, the mutation, and whether the pixels the
// device draws for the app, and its semantics, changed. Run by the
// a7-device workflow:
//
//   flutter test integration_test/a7_device_test.dart -d <simulator>
//
// Each result is printed as one line, `A7 {json}`, since the device's files
// are not readable from the host.

import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:touchstone/src/recorder/pixel_digest.dart';

import '../test/a7/a7_seeds.dart';
import '../test/generated/mutator.dart';
import '../test/support/scenes.dart';

/// Larger than the phone viewport at 3x, so the whole app is inside it
/// whatever transform the live test binding puts between the viewport and
/// the simulator's window.
const Rect _bounds = Rect.fromLTWH(0, 0, 1600, 3200);

/// The digest of the app's layer tree as the device's renderer draws it,
/// compared only with another raster on the same device.
Future<String> _raster(WidgetTester tester) async {
  await tester.pump();
  final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
  final Uint8List bytes = (await tester.runAsync(() async {
    final ui.Image image = await layer.toImage(_bounds);
    try {
      return (await image.toByteData())!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }))!;
  return pixelDigest(bytes);
}

String _semantics(WidgetTester tester) {
  final SemanticsNode? root = tester.binding.renderViews.first.owner!.semanticsOwner?.rootSemanticsNode;
  return root == null
      ? '-'
      : root
            .toStringDeep(childOrder: DebugSemanticsDumpOrder.traversalOrder)
            .replaceAll(RegExp(r'SemanticsNode#\d+'), 'SemanticsNode')
            .replaceAll(RegExp(r'#[0-9a-f]{5}\b'), '#');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  sceneScrollBehavior = a7ScrollBehavior;

  for (int seed = a7FirstSeed; seed < a7FirstSeed + a7SeedCount; seed++) {
    // The widget tests draw with Material's Android typography (Roboto); the
    // device does the same, with Roboto bundled.
    testWidgets('seed $seed', variant: TargetPlatformVariant.only(TargetPlatform.android), (WidgetTester tester) async {
      final random = Random(seed);
      final Scene scene = scenes[random.nextInt(scenes.length)];
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpScene(tester, scene);
      final String before = await _raster(tester);
      final String again = await _raster(tester);
      final String semanticsBefore = _semantics(tester);
      final AppliedMutation? m = mutate(tester.binding.renderViews.first, random);
      final row = <String, Object?>{'seed': seed, 'scene': scene.id, 'noisy': before != again};
      if (m != null) {
        await tester.pump();
        row.addAll(<String, Object?>{
          'mutation': m.description.length > 120 ? '${m.description.substring(0, 120)}...' : m.description,
          'mutationLength': m.description.length,
          'pixelsChanged': await _raster(tester) != before,
          'semanticsChanged': _semantics(tester) != semanticsBefore,
        });
      }
      handle.dispose();
      // ignore: avoid_print
      print('A7 ${jsonEncode(row)}');
    });
  }
}
