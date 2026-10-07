// A13: existing golden tests can be made deterministic (spec, Assumption
// register).
//
// Each catalogue state gets a conventional golden test, written the way such
// tests usually are: pump, settle, matchesGoldenFile. The determinism gate
// then runs at the point the golden is taken. Pass criterion: every test the
// gate fails gets a message naming the first differing node and its cause.
// Results go to build/a13/results.json.

import 'dart:convert';
import 'dart:io';

import 'package:catalogue_app/catalogue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

import '../support/scenes.dart';

/// How a conventional test reaches the golden. Most scenes already pump the
/// usual way; these two differ from the deterministic version in scenes.dart.
final Map<String, Future<void> Function(WidgetTester, Widget Function(Widget))> conventional =
    <String, Future<void> Function(WidgetTester, Widget Function(Widget))>{
      // The image is handed over as bytes and the test just settles.
      for (final (String state, int tab) in <(String, int)>[('overview', 0), ('news', 1), ('collapsed', 0)])
        'detail/$state': (WidgetTester tester, Widget Function(Widget) host) async {
          final controller = ScrollController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            host(
              DetailScreen(
                quote: seededQuotes().first,
                image: MemoryImage(await headerImageBytes(tester)),
                initialTab: tab,
                controller: controller,
              ),
            ),
          );
          if (state == 'collapsed') {
            controller.jumpTo(300);
          }
          await tester.pumpAndSettle();
        },
      // pumpAndSettle would time out on the shimmer, so the test pumps a fixed
      // time and takes the golden.
      'states/loading': (WidgetTester tester, Widget Function(Widget) host) async {
        await tester.pumpWidget(host(const StatesScreen(state: LoadState.loading)));
        await tester.pump(const Duration(milliseconds: 300));
      },
    };

void main() {
  final results = <Map<String, Object?>>[];

  for (final Scene scene in scenes) {
    testWidgets('conventional golden: ${scene.id}', (WidgetTester tester) async {
      usePhone(tester);
      await (conventional[scene.id] ?? scene.pump)(tester, hostFor());

      // The gate runs as a conventional test would declare it: no pumped time.
      final DeterminismReport report = await checkDeterminism(
        tester,
        scene.id,
        options: SnapshotOptions(state: scene.state, theme: scene.theme),
      );
      String golden = 'match';
      try {
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${scene.id}.png'));
      } on TestFailure catch (e) {
        golden = 'mismatch: ${e.message?.split('\n').first}';
      }
      final SnapshotDifference? d = report.firstDifference;
      results.add(<String, Object?>{
        'test': scene.id,
        'deterministic': report.deterministic,
        'golden': golden,
        if (d != null) ...<String, Object?>{'node': d.nodeId, 'fields': d.fields, 'cause': d.cause},
      });
    });
  }

  tearDownAll(() {
    final dir = Directory('build/a13')..createSync(recursive: true);
    File('${dir.path}/results.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
    // The pass criterion: a failing test names a node and a cause.
    final unnamed = <Object?>[
      for (final r in results)
        if (r['deterministic'] == false && (r['node'] == '-' || (r['cause'] as String).isEmpty)) r['test'],
    ];
    expect(unnamed, isEmpty, reason: 'gate failures without a named node');
  });
}
