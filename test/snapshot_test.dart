import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/src/snapshot/capture.dart' show captureDetectionOnly;
import 'package:touchstone/touchstone.dart';

class Card2 extends StatelessWidget {
  const Card2({super.key, required this.child, this.color = const Color(0xFF2196F3)});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color),
    child: Padding(padding: const EdgeInsets.all(8), child: child),
  );
}

class Label extends StatelessWidget {
  const Label(this.text, {super.key, this.semantics});
  final String text;
  final String? semantics;
  @override
  Widget build(BuildContext context) => Semantics(label: semantics, child: Text(text));
}

class ClockLabel extends StatelessWidget {
  const ClockLabel({super.key});
  @override
  Widget build(BuildContext context) => Text('${clock.now().microsecondsSinceEpoch}');
}

class RandomBox extends StatelessWidget {
  RandomBox({super.key});
  final Random _random = Random();
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 20, height: 20, child: ColoredBox(color: Color(0xFF000000 | _random.nextInt(0xFFFFFF))));
}

final policy = ComponentPolicy(include: <Type>{Card2, Label, ClockLabel, RandomBox});
final options = SnapshotOptions(policy: policy);

Widget app(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: ColoredBox(
    color: const Color(0xFFFFFFFF),
    child: Align(alignment: Alignment.topLeft, child: child),
  ),
);

Future<Snapshot> snap(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(app(widget));
  return captureSnapshot(tester, 'test', options: options);
}

void main() {
  testWidgets('canonical text round-trips and a tampered baseline is rejected', (WidgetTester tester) async {
    final Snapshot s = await snap(tester, const Card2(child: Label('a')));
    final String text = s.toCanonical();
    expect(Snapshot.parse(text).toCanonical(), text);
    final String tampered = text.replaceFirst('"Label@0"', '"Label@1"');
    expect(() => Snapshot.parse(tampered), throwsFormatException);
  });

  testWidgets('a baseline checked out with CRLF line endings parses the same, and every subtree hash is checked', (
    WidgetTester tester,
  ) async {
    final Snapshot s = await snap(tester, const Card2(child: Label('a')));
    final String text = s.toCanonical();
    expect(Snapshot.parse(text.replaceAll('\n', '\r\n')).toCanonical(), text);
    // A leaf's stored subtree hash changed, with the root hash left as it was.
    final String leaf = s.root.children.first.children.first.subtreeHash;
    expect(() => Snapshot.parse(text.replaceFirst('sub=$leaf', 'sub=${'0' * leaf.length}')), throwsFormatException);
  });

  testWidgets('a capture for a hash check has the same detection fields and no explanation', (
    WidgetTester tester,
  ) async {
    final Snapshot full = await snap(tester, const Card2(child: Label('a')));
    final Snapshot check = await captureDetectionOnly(tester, 'test', options: options);
    expect(check.rootHash, full.rootHash);
    expect(check.root.children.single.style, '{}');
    expect(check.root.children.single.shape, '-');
    expect(full.root.children.single.style, isNot('{}'));
  });

  testWidgets('components get key or ordinal ids; framework widgets are not components', (WidgetTester tester) async {
    final Snapshot s = await snap(
      tester,
      const Card2(
        key: ValueKey<String>('card'),
        child: Column(
          children: <Widget>[
            Label('a'),
            Label('b'),
            Label('c', key: ValueKey<int>(7)),
          ],
        ),
      ),
    );
    expect(s.walk().map(((String, SnapshotNode) e) => e.$1).toList(), <String>[
      'root',
      'root/Card2#card',
      'root/Card2#card/Label@0',
      'root/Card2#card/Label@1',
      'root/Card2#card/Label#7',
    ]);
  });

  testWidgets('offstage components are not in the snapshot', (WidgetTester tester) async {
    final Snapshot s = await snap(
      tester,
      const Column(
        children: <Widget>[
          Label('shown'),
          Offstage(child: Label('hidden')),
        ],
      ),
    );
    expect(s.walk().map(((String, SnapshotNode) e) => e.$1), <String>['root', 'root/Label@0']);
  });

  testWidgets('moving a child component changes its bounds, not its parent paint', (WidgetTester tester) async {
    Widget tree(double gap) => Card2(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(height: gap),
          const Label('x'),
        ],
      ),
    );
    final Snapshot a = await snap(tester, tree(0));
    final Snapshot b = await snap(tester, tree(3));
    final SnapshotNode ca = a.root.children.single, cb = b.root.children.single;
    expect(ca.children.single.bounds, isNot(cb.children.single.bounds));
    expect(ca.children.single.paint, cb.children.single.paint);
    expect(a.rootHash, isNot(b.rootHash));
  });

  testWidgets('paint order of child components is part of the parent paint', (WidgetTester tester) async {
    Widget tree(bool swap) {
      final first = Positioned(
        left: 0,
        top: 0,
        child: Card2(
          key: const ValueKey<String>('red'),
          color: const Color(0xFFFF0000),
          child: const SizedBox(width: 10, height: 10),
        ),
      );
      final second = Positioned(
        left: 4,
        top: 4,
        child: Card2(key: const ValueKey<String>('blue'), child: const SizedBox(width: 10, height: 10)),
      );
      return SizedBox(
        width: 50,
        height: 50,
        child: Stack(children: swap ? <Widget>[second, first] : <Widget>[first, second]),
      );
    }

    final Snapshot a = await snap(tester, tree(false));
    final Snapshot b = await snap(tester, tree(true));
    // The children are listed in the new order and each keeps its own paint.
    expect(a.rootHash, isNot(b.rootHash));
    expect(diffSnapshots(a, b).changes.map((Change c) => c.type), contains(ChangeType.reordered));
  });

  testWidgets('paint order that differs from child order is part of the parent paint', (WidgetTester tester) async {
    Widget tree(bool reverse) => SizedBox(
      width: 50,
      height: 50,
      child: Flow(
        delegate: _PaintOrder(reverse),
        children: const <Widget>[
          Card2(key: ValueKey<String>('red'), color: Color(0xFFFF0000), child: SizedBox(width: 10, height: 10)),
          Card2(key: ValueKey<String>('blue'), child: SizedBox(width: 10, height: 10)),
        ],
      ),
    );

    final Snapshot a = await snap(tester, tree(false));
    final Snapshot b = await snap(tester, tree(true));
    expect(a.root.children.map((SnapshotNode n) => n.id), b.root.children.map((SnapshotNode n) => n.id));
    expect(a.root.paint, isNot(b.root.paint));
  });

  testWidgets('wrapping in a layout-neutral widget leaves the paint as it was', (WidgetTester tester) async {
    final Snapshot a = await snap(tester, const Card2(child: Label('a')));
    final Snapshot b = await snap(
      tester,
      const Card2(
        child: RepaintBoundary(child: SizedBox(child: Label('a'))),
      ),
    );
    expect(b.rootHash, a.rootHash);
  });

  testWidgets('a key change on a child component leaves the parent paint as it was', (WidgetTester tester) async {
    final Snapshot a = await snap(
      tester,
      Card2(key: const ValueKey<String>('a'), child: const SizedBox(width: 10, height: 10)),
    );
    final Snapshot b = await snap(
      tester,
      Card2(key: const ValueKey<String>('b'), child: const SizedBox(width: 10, height: 10)),
    );
    expect(a.root.children.single.id, isNot(b.root.children.single.id));
    expect(a.root.paint, b.root.paint);
  });

  testWidgets('a semantics-only change changes semantics and the root hash', (WidgetTester tester) async {
    final Snapshot a = await snap(tester, const Label('x', semantics: 'Price'));
    final Snapshot b = await snap(tester, const Label('x', semantics: 'Cost'));
    expect(a.root.children.single.semantics, isNot(b.root.children.single.semantics));
    expect(a.root.children.single.paint, b.root.children.single.paint);
    expect(a.rootHash, isNot(b.rootHash));
  });

  testWidgets('a label merged into a list item boundary belongs to the component that set it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 200,
          height: 200,
          child: ListView(children: const <Widget>[Label('a', semantics: 'Price')]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final Snapshot s = await captureSnapshot(tester, 'test', options: options);
    final SnapshotNode label = s.root.children.single;
    expect(label.semantics, contains('"label":"Price\\na"'));
    expect(s.root.semantics, isNot(contains('Price')));
  });

  testWidgets('capture fails while an animation is running and names the animating node', (WidgetTester tester) async {
    await tester.pumpWidget(
      app(const Card2(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator()))),
    );
    await expectLater(
      () => captureSnapshot(tester, 'x', options: options),
      throwsA(
        isA<CaptureFailure>()
            .having((CaptureFailure f) => f.message, 'message', contains('frame is scheduled'))
            .having((CaptureFailure f) => f.difference?.nodeId, 'node', 'root/Card2@0'),
      ),
    );
  });

  testWidgets('capture fails on an image that is not decoded and names its component', (WidgetTester tester) async {
    final Uint8List png = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = const Color(0xFF00FF00));
      final ui.Image image = await recorder.endRecording().toImage(4, 4);
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    await tester.pumpWidget(app(Card2(child: Image.memory(png, width: 4, height: 4))));
    final DeterminismReport report = await checkDeterminism(tester, 'x', options: options);
    expect(report.firstDifference!.nodeId, 'root/Card2@0');
    expect(report.firstDifference!.cause, contains('image load'));
  });

  testWidgets('atPumpedTime captures a running animation and records the frame time', (WidgetTester tester) async {
    await tester.pumpWidget(
      app(const Card2(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator()))),
    );
    await tester.pump(const Duration(milliseconds: 250));
    final pumped = SnapshotOptions(policy: policy, atPumpedTime: true);
    final DeterminismReport report = await checkDeterminism(tester, 'x', options: pumped);
    expect(report.deterministic, isTrue, reason: '${report.firstDifference}');
    expect(Snapshot.parse(report.captures.first).inputs['frameTime'], isNotNull);
  });

  testWidgets('the determinism gate names a node painted with random values', (WidgetTester tester) async {
    await tester.pumpWidget(app(RandomBox()));
    final DeterminismReport report = await checkDeterminism(tester, 'x', options: options);
    expect(report.deterministic, isFalse);
    expect(report.firstDifference!.nodeId, 'root/RandomBox@0');
    expect(report.firstDifference!.fields, contains('paint'));
  });

  testWidgets('the determinism gate fails a wall-clock read and passes a fixed clock', (WidgetTester tester) async {
    await tester.pumpWidget(app(const ClockLabel()));
    final DeterminismReport report = await checkDeterminism(tester, 'x', options: options);
    expect(report.deterministic, isFalse);
    expect(report.firstDifference!.cause, contains('wall clock'));
    expect(report.firstDifference!.nodeId, 'root/ClockLabel@0');

    await withFixedClock(DateTime.utc(2026, 10, 7), () async {
      await tester.pumpWidget(app(const ClockLabel(key: ValueKey<int>(1))));
      final DeterminismReport fixed = await checkDeterminism(tester, 'x', options: options);
      expect(fixed.deterministic, isTrue);
    });
  });

  testWidgets('expectSnapshot records a baseline, then passes and fails against it', (WidgetTester tester) async {
    final Directory dir = Directory.systemTemp.createTempSync('touchstone');
    addTearDown(() => dir.deleteSync(recursive: true));
    final GoldenFileComparator previous = goldenFileComparator;
    goldenFileComparator = LocalFileComparator(dir.uri.resolve('a_test.dart'));
    addTearDown(() => goldenFileComparator = previous);

    await tester.pumpWidget(app(const Card2(child: Label('a'))));
    await expectSnapshot(tester, 'card/idle', options: options, recordMissing: true);
    expect(File('${dir.path}/snapshots/card/idle.snapshot').existsSync(), isTrue);
    await expectSnapshot(tester, 'card/idle', options: options);

    await tester.pumpWidget(app(const Card2(child: Label('b'))));
    await expectLater(
      () => expectSnapshot(tester, 'card/idle', options: options),
      throwsA(
        isA<TestFailure>().having(
          (TestFailure f) => f.message,
          'message',
          allOf(startsWith('card/idle    fail'), contains('Content   Label@0'), contains('"a" -> "b"')),
        ),
      ),
    );
  });

  test('the library version matches pubspec.yaml', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^version: (.+)$', multiLine: true).firstMatch(pubspec)!.group(1), touchstoneVersion);
  });
}

/// Paints its children in reverse when [reverse] is set, so paint order and
/// child order differ.
class _PaintOrder extends FlowDelegate {
  _PaintOrder(this.reverse);
  final bool reverse;
  @override
  void paintChildren(FlowPaintingContext context) {
    for (var i = 0; i < context.childCount; i++) {
      final int k = reverse ? context.childCount - 1 - i : i;
      context.paintChild(k, transform: Matrix4.translationValues(4.0 * k, 4.0 * k, 0));
    }
  }

  @override
  bool shouldRepaint(_PaintOrder old) => old.reverse != reverse;
}
