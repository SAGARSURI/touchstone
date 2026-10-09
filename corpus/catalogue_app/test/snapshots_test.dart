// Snapshot tests for catalogue levels 1 to 3. Baselines are written with
// `flutter test --update-goldens`, after the determinism gate passes, on
// macOS: the only host baselines are valid on (spec, A3). The `baseline` tag
// lets other hosts run everything else.
@Tags(<String>['baseline'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

import 'support/scenes.dart';

void main() {
  for (final Scene scene in scenes) {
    testWidgets(scene.id, (WidgetTester tester) async {
      await pumpScene(tester, scene);
      await expectSnapshot(tester, scene.id, options: scene.options);
    });
  }
}
