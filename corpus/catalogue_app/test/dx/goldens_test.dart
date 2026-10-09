// The golden arm of the developer-experience protocol
// (doc/phase3/dx_protocol.md): the catalogue's conventional golden tests,
// failing the usual way. The scenes are pumped as A13's conventional tests
// pump them; the goldens are this test's own, recorded on macOS by the
// record-baselines workflow. A13's goldens are taken after its determinism
// gate rebuilds and pumps the tree, and on `states/loading` that draws
// different pixels, so they are not this test's.
//
//   flutter test test/dx/goldens_test.dart
@Tags(<String>['baseline'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../a13/conventional_goldens_test.dart' show conventional;
import '../support/scenes.dart';

void main() {
  for (final Scene scene in levelsOneToThree) {
    testWidgets(scene.id, (WidgetTester tester) async {
      usePhone(tester);
      await (conventional[scene.id] ?? scene.pump)(tester, hostFor());
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${scene.id}.png'));
    });
  }
}
