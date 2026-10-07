import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(a.root.paint, isNot(b.root.paint));
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

  testWidgets('capture fails while an animation is running', (WidgetTester tester) async {
    await tester.pumpWidget(app(const SizedBox(width: 20, height: 20, child: CircularProgressIndicator())));
    expect(
      () => captureSnapshot(tester, 'x', options: options),
      throwsA(isA<CaptureFailure>().having((CaptureFailure f) => f.message, 'message', contains('frame is scheduled'))),
    );
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
      throwsA(isA<TestFailure>().having((TestFailure f) => f.message, 'message', contains('Card2@0/Label@0'))),
    );
  });

  test('the library version matches pubspec.yaml', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^version: (.+)$', multiLine: true).firstMatch(pubspec)!.group(1), touchstoneVersion);
  });
}
