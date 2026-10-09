// The golden arm of the developer-experience protocol
// (doc/phase3/dx_protocol.md): the catalogue's conventional golden tests,
// failing the usual way. The goldens are A13's, recorded on macOS.
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
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('../a13/goldens/${scene.id}.png'));
    });
  }
}
