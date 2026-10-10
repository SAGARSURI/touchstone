// Capture gaps found by the Phase 1 adversarial review. Each test is a case
// where two different screens gave one snapshot, a placeholder was recorded,
// or a change was named on the wrong node.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

class Box extends StatelessWidget {
  const Box({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class Label extends StatelessWidget {
  const Label(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text);
}

class Ticker2 extends StatefulWidget {
  const Ticker2({super.key});
  @override
  State<Ticker2> createState() => _Ticker2State();
}

class _Ticker2State extends State<Ticker2> {
  @override
  Widget build(BuildContext context) => Text('${clock.now().microsecondsSinceEpoch}');
}

final policy = ComponentPolicy(include: <Type>{Box, Label, Ticker2});
final options = SnapshotOptions(policy: policy);

SnapshotNode node(Snapshot s, String id) => s.walk().firstWhere(((String, SnapshotNode) e) => e.$1 == id).$2;

Widget app(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: ColoredBox(
    color: const Color(0xFFFFFFFF),
    child: Align(alignment: Alignment.topLeft, child: child),
  ),
);

Future<Uint8List> png(WidgetTester tester, Color color) async => (await tester.runAsync(() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = color);
  final ui.Image image = await recorder.endRecording().toImage(4, 4);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}))!;

Future<CaptureFailure> captureFails(WidgetTester tester) async {
  try {
    await captureSnapshot(tester, 'x', options: options);
  } on CaptureFailure catch (e) {
    return e;
  }
  fail('the capture succeeded');
}

void main() {
  testWidgets('an undecoded decoration image fails the capture and names its component', (WidgetTester tester) async {
    final Uint8List red = await png(tester, const Color(0xFFFF0000));
    final Uint8List green = await png(tester, const Color(0xFF00FF00));
    Widget tree(Uint8List bytes) => Box(
      child: SizedBox(
        width: 40,
        height: 40,
        child: DecoratedBox(
          decoration: BoxDecoration(image: DecorationImage(image: MemoryImage(bytes))),
        ),
      ),
    );
    await tester.pumpWidget(app(tree(red)));
    final CaptureFailure failure = await captureFails(tester);
    expect(failure.message, contains('not decoded'));
    expect(failure.difference!.nodeId, 'root/Box@0');
    expect(failure.difference!.cause, contains('image load'));

    await precacheImages(tester, <ImageProvider>[MemoryImage(red), MemoryImage(green)]);
    final Snapshot a = await captureSnapshot(tester, 'x', options: options);
    await tester.pumpWidget(app(tree(green)));
    final Snapshot b = await captureSnapshot(tester, 'x', options: options);
    expect(a.rootHash, isNot(b.rootHash));
  });

  testWidgets('with gaplessPlayback, the new image loading fails the capture', (WidgetTester tester) async {
    final redImage = MemoryImage(await png(tester, const Color(0xFFFF0000)));
    final greenImage = MemoryImage(await png(tester, const Color(0xFF00FF00)));
    await tester.pumpWidget(app(Box(child: Image(image: redImage, width: 20, height: 20, gaplessPlayback: true))));
    await precacheImages(tester, <ImageProvider>[redImage]);
    await captureSnapshot(tester, 'x', options: options);
    await tester.pumpWidget(app(Box(child: Image(image: greenImage, width: 20, height: 20, gaplessPlayback: true))));
    final CaptureFailure failure = await captureFails(tester);
    expect(failure.message, contains('MemoryImage'));
    expect(failure.difference!.nodeId, 'root/Box@0');
  });

  testWidgets('an image that failed to load shows its error widget and can be captured', (WidgetTester tester) async {
    await tester.pumpWidget(
      app(
        Box(
          child: Image.memory(
            Uint8List.fromList(<int>[1, 2, 3, 4]),
            width: 20,
            height: 20,
            errorBuilder: (_, _, _) =>
                const SizedBox(width: 20, height: 20, child: ColoredBox(color: Color(0xFF888888))),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(find.byType(ColoredBox), findsNWidgets(2), reason: 'the error widget is shown');
    final DeterminismReport report = await checkDeterminism(tester, 'x', options: options);
    expect(report.deterministic, isTrue);
  });

  testWidgets('semantics sort keys are recorded, so a reading-order change is seen', (WidgetTester tester) async {
    Widget tree(bool swap) => Box(
      child: Column(
        children: <Widget>[
          Semantics(sortKey: OrdinalSortKey(swap ? 2 : 1), child: const Text('first')),
          Semantics(sortKey: OrdinalSortKey(swap ? 1 : 2), child: const Text('second')),
        ],
      ),
    );
    await tester.pumpWidget(app(tree(false)));
    final Snapshot a = await captureSnapshot(tester, 'x', options: options);
    await tester.pumpWidget(app(tree(true)));
    final Snapshot b = await captureSnapshot(tester, 'x', options: options);
    expect(a.rootHash, isNot(b.rootHash));
    expect(a.root.children.single.semantics, contains('"sortKey":"ordinal 1.0"'));
  });

  testWidgets('sibling ids stay unique when keys look alike', (WidgetTester tester) async {
    await tester.pumpWidget(
      app(
        const Column(
          children: <Widget>[
            Label('a', key: ValueKey<String>('7')),
            Label('b', key: ValueKey<int>(7)),
            Label('c', key: ValueKey<String>('7@1')),
            Label('d', key: ValueKey<String>('#x')),
          ],
        ),
      ),
    );
    final Snapshot s = await captureSnapshot(tester, 'x', options: options);
    expect(s.walk().map(((String, SnapshotNode) e) => e.$1).toList(), <String>[
      'root',
      'root/Label#7',
      'root/Label#7@1',
      'root/Label#7%401',
      'root/Label#%23x',
    ]);
  });

  testWidgets('class declarations in strings and comments, and plain classes, are not components', (
    WidgetTester tester,
  ) async {
    final Directory dir = Directory.systemTemp.createTempSync('touchstone_scan');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/lib/models').createSync(recursive: true);
    File('${dir.path}/pubspec.yaml').writeAsStringSync('name: myapp\n');
    File('${dir.path}/lib/models/layout.dart').writeAsStringSync(
      'class Padding { final double v = 0; }\n'
      '/* class Align extends StatelessWidget {} */\n'
      'const s = """\nclass Center extends StatelessWidget {}\n""";\n'
      "const t = '\${'class SizedBox extends X'}';\n",
    );
    File('${dir.path}/lib/box.dart').writeAsStringSync('class Box extends StatelessWidget {}\n');
    final scanned = ComponentPolicy(packageRoots: <String>[dir.path]);
    expect(scanned.declaredClasses.keys, <String>['Box']);
    await tester.pumpWidget(
      app(
        const Box(
          child: Padding(
            padding: EdgeInsets.all(4),
            child: Center(child: Text('x')),
          ),
        ),
      ),
    );
    final Snapshot s = await captureSnapshot(tester, 'x', options: SnapshotOptions(policy: scanned));
    expect(s.walk().map(((String, SnapshotNode) e) => e.$1).toList(), <String>['root', 'root/Box@0']);
  });

  testWidgets('a text span with a recognizer keeps its semantics', (WidgetTester tester) async {
    final tap = TapGestureRecognizer()..onTap = () {};
    addTearDown(tap.dispose);
    Widget tree({required bool link}) => Box(
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            const TextSpan(text: 'Read '),
            TextSpan(text: 'terms', semanticsLabel: 'terms of service', recognizer: link ? tap : null),
          ],
        ),
      ),
    );
    await tester.pumpWidget(app(tree(link: true)));
    final Snapshot a = await captureSnapshot(tester, 'x', options: options);
    expect(a.root.children.single.semantics, allOf(contains('terms of service'), contains('isLink')));
    // Same pixels, but the span is no longer a link a screen reader can tap.
    await tester.pumpWidget(app(tree(link: false)));
    final Snapshot b = await captureSnapshot(tester, 'x', options: options);
    expect(a.rootHash, isNot(b.rootHash));
  });

  testWidgets('a hint override is recorded by its action, not a run-dependent id', (WidgetTester tester) async {
    await tester.pumpWidget(
      app(Semantics(onTap: () {}, onTapHint: 'other', child: const SizedBox(width: 5, height: 5))),
    );
    await captureSnapshot(tester, 'x', options: options);
    await tester.pumpWidget(
      app(
        Box(
          child: Semantics(
            onTap: () {},
            onTapHint: 'open',
            child: const SizedBox(width: 10, height: 10, child: ColoredBox(color: Color(0xFF000000))),
          ),
        ),
      ),
    );
    final Snapshot s = await captureSnapshot(tester, 'x', options: options);
    expect(s.root.children.single.semantics, contains('"customActions":["hint tap: open"]'));
  });

  testWidgets('a clock read in a State class names its component', (WidgetTester tester) async {
    await tester.pumpWidget(app(const Box(child: Ticker2())));
    final DeterminismReport report = await checkDeterminism(tester, 'x', options: options);
    expect(report.deterministic, isFalse);
    expect(report.firstDifference!.nodeId, 'root/Box@0/Ticker2@0');
    expect(report.firstDifference!.cause, contains('wall clock'));
  });

  testWidgets('a font loaded outside SnapshotFonts fails the capture', (WidgetTester tester) async {
    // flutter_tester sits in bin/cache/artifacts/engine/<host>/; the Material
    // icon font is in bin/cache/artifacts/material_fonts/.
    final File font = File(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts/MaterialIcons-Regular.otf',
    );
    const icon = Icon(IconData(0xe5ca, fontFamily: 'ExtraIcons'), size: 40);
    await tester.pumpWidget(app(const Box(child: icon)));
    await captureSnapshot(tester, 'x', options: options);
    await tester.runAsync(() async {
      final loader = FontLoader('ExtraIcons')
        ..addFont(Future<ByteData>.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    });
    await tester.pumpWidget(app(const Box(child: Text('x'))));
    await tester.pumpWidget(app(const Box(child: icon)));
    final CaptureFailure failure = await captureFails(tester);
    expect(failure.message, contains('ExtraIcons'));
    expect(failure.message, contains('SnapshotFonts.load'));
  });
  testWidgets('a path drawn only outside the clip hashes no pixels, so changes elsewhere do not touch it', (
    WidgetTester tester,
  ) async {
    // The last row of a list, cut off by the viewport, whose bottom border is
    // drawn with a path below the visible area (A6 review, seed 945).
    Widget scene(Color top) => app(
      SizedBox(
        width: 100,
        height: 100,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Box(
                  child: SizedBox(width: 100, height: 50, child: ColoredBox(color: top)),
                ),
                const SizedBox(height: 100),
                const Box(
                  child: SizedBox(
                    width: 100,
                    height: 50,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFF888888))),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(scene(const Color(0xFF000000)));
    final Snapshot a = await captureSnapshot(tester, 'x', options: options);
    expect(node(a, 'root/Box@1').opaque, isNot('-'));
    await tester.pumpWidget(scene(const Color(0xFF0000FF)));
    final Snapshot b = await captureSnapshot(tester, 'x', options: options);
    expect(node(b, 'root/Box@1').paint, node(a, 'root/Box@1').paint);
    final ChangeReport r = diffSnapshots(a, b);
    expect(<String>[for (final ReportItem i in r.items) i.change!.nodeId], <String>['root/Box@0']);
  });

  testWidgets('a tooltip traversal link is recorded without a run-dependent id', (WidgetTester tester) async {
    Widget tip() => MaterialApp(
      home: Box(
        child: Tooltip(message: 'Back', child: const SizedBox(width: 48, height: 48)),
      ),
    );
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(tip());
    await tester.pumpAndSettle();
    final Snapshot a = await captureSnapshot(tester, 'x', options: options);
    // A new tree gives the overlay portal a new State, as a second run does.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(tip());
    await tester.pumpAndSettle();
    final Snapshot b = await captureSnapshot(tester, 'x', options: options);
    handle.dispose();
    expect(a.toCanonical(), contains('traversalParentIdentifier'));
    expect(b.toCanonical(), a.toCanonical());
  });
}
