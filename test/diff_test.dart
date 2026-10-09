// The diff engine, cascade grouping, policy and report on small trees.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

class Card2 extends StatelessWidget {
  const Card2({super.key, this.height = 40, this.color = const Color(0xFF2196F3), this.label = 'card'});
  final double height;
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color),
      child: Text(label),
    ),
  );
}

class Holder extends StatelessWidget {
  const Holder({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(4), child: child);
}

class Dots extends StatelessWidget {
  const Dots({super.key, required this.radius});
  final double radius;
  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(40, 40), painter: _Dots(radius));
}

class _Dots extends CustomPainter {
  _Dots(this.radius);
  final double radius;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawCircle(const Offset(20, 20), radius, Paint());
  @override
  bool shouldRepaint(_Dots old) => old.radius != radius;
}

/// Draws a path, so its paint is hashed by pixels.
class Wave extends StatelessWidget {
  const Wave({super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(40, 20), painter: _Wave());
}

class _Wave extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..moveTo(0, 10)
      ..quadraticBezierTo(10, 0, 20, 10)
      ..quadraticBezierTo(30, 20, 40, 10),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
  @override
  bool shouldRepaint(_Wave old) => false;
}

final options = SnapshotOptions(policy: ComponentPolicy(include: <Type>{Card2, Holder, Holder2, Dots, Wave}));

Widget app(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: ColoredBox(
    color: const Color(0xFFFFFFFF),
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 200, child: child),
    ),
  ),
);

Future<ChangeReport> diffOf(WidgetTester tester, Widget before, Widget after) async {
  await tester.pumpWidget(app(before));
  await tester.pumpAndSettle();
  final Snapshot a = await captureSnapshot(tester, 'x', options: options);
  await tester.pumpWidget(app(after));
  await tester.pumpAndSettle();
  final Snapshot b = await captureSnapshot(tester, 'x', options: options);
  return diffSnapshots(a, b);
}

/// "Type node" for each top-level item.
List<String> top(ChangeReport r) => <String>[
  for (final ReportItem i in r.items)
    i.change != null ? '${i.change!.type.label} ${i.change!.nodeId}' : 'Shift ${i.group!.ancestor.fullId}',
];

Widget column(List<Widget> children) =>
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);

void main() {
  testWidgets('equal snapshots give an empty report and a pass', (WidgetTester tester) async {
    final ChangeReport r = await diffOf(tester, column(<Widget>[const Card2()]), column(<Widget>[const Card2()]));
    expect(r.kind, ReportKind.equal);
    expect(Policy.defaults().decide(r).verdict, Verdict.pass);
  });

  testWidgets('an insertion at the start of a column names the shift as its consequence', (WidgetTester tester) async {
    final ChangeReport r = await diffOf(
      tester,
      column(<Widget>[const Card2(label: 'a'), const Card2(label: 'b'), const Card2(label: 'c')]),
      column(<Widget>[
        const Card2(label: 'new', height: 20),
        const Card2(label: 'a'),
        const Card2(label: 'b'),
        const Card2(label: 'c'),
      ]),
    );
    expect(top(r), <String>['Added root/Card2@0']);
    final ReportItem item = r.items.single;
    expect(item.causedGroups.single.summary, '3 components shifted down 20 px');
    expect(Policy.defaults().decide(r).verdict, Verdict.needsReview);
    expect(renderReport(r, Policy.defaults().decide(r)), contains('consequence: 3 components shifted down 20 px'));
  });

  testWidgets('a removal names the shift as its consequence', (WidgetTester tester) async {
    final ChangeReport r = await diffOf(
      tester,
      column(<Widget>[const Card2(label: 'a'), const Card2(label: 'b'), const Card2(label: 'c')]),
      column(<Widget>[const Card2(label: 'b'), const Card2(label: 'c')]),
    );
    expect(top(r), <String>['Removed root/Card2@0']);
    expect(r.items.single.causedGroups.single.summary, '2 components shifted up 40 px');
  });

  testWidgets('a resize names the shift as its consequence', (WidgetTester tester) async {
    final ChangeReport r = await diffOf(
      tester,
      column(<Widget>[const Card2(label: 'a'), const Card2(label: 'b')]),
      column(<Widget>[const Card2(label: 'a', height: 50), const Card2(label: 'b')]),
    );
    expect(top(r), <String>['Layout root/Card2@0']);
    expect(r.items.single.change!.detail, startsWith('size 200x40 -> 200x50; '));
    expect(r.items.single.change!.detail, contains('SizedBox.height: 40.0 -> 50.0'));
    expect(r.items.single.causedGroups.single.summary, '1 component shifted down 10 px');
  });

  testWidgets('two candidates give possible causes and no single root cause', (WidgetTester tester) async {
    final ChangeReport r = await diffOf(
      tester,
      column(<Widget>[const Card2(label: 'a'), const Card2(label: 'b'), const Card2(label: 'c')]),
      column(<Widget>[
        const Card2(label: 'a', height: 50),
        const Card2(label: 'b', height: 45),
        const Card2(label: 'c'),
      ]),
    );
    final ShiftGroup g = r.groups.singleWhere((ShiftGroup g) => g.dy == 15);
    expect(g.cause, isNull);
    expect(g.candidates.map((Change c) => c.nodeId), <String>['root/Card2@0', 'root/Card2@1']);
    expect(top(r), contains('Shift root'));
  });

  testWidgets('swapped siblings are one reorder, and the other sibling\'s shift is its consequence', (
    WidgetTester tester,
  ) async {
    final ChangeReport r = await diffOf(
      tester,
      column(<Widget>[const Card2(label: 'a'), const Card2(label: 'b')]),
      column(<Widget>[const Card2(label: 'b'), const Card2(label: 'a')]),
    );
    expect(top(r), <String>['Reordered root/Card2@0']);
    expect(r.items.single.change!.detail, 'position 2 -> 1 among siblings');
    expect(r.items.single.causedGroups.single.summary, '1 component shifted down 40 px');
  });

  testWidgets('a colour change is a style change, named by property', (WidgetTester tester) async {
    final ChangeReport r = await diffOf(
      tester,
      column(<Widget>[const Card2()]),
      column(<Widget>[const Card2(color: Color(0xFFF44336))]),
    );
    expect(top(r), <String>['Style root/Card2@0']);
    expect(r.items.single.change!.detail, contains('RenderDecoratedBox.decoration'));
  });

  testWidgets('a text change is a content change', (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final ChangeReport r = await diffOf(
      tester,
      column(<Widget>[const Card2(label: 'one')]),
      column(<Widget>[const Card2(label: 'two')]),
    );
    expect(top(r), <String>['Content root/Card2@0']);
    expect(r.items.single.change!.detail, contains('"one" -> "two"'));
    h.dispose();
  });

  testWidgets('a semantics-only change is a semantics change', (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final ChangeReport r = await diffOf(
      tester,
      Holder(
        child: Semantics(label: 'Pay', child: const SizedBox(width: 10, height: 10)),
      ),
      Holder(
        child: Semantics(label: 'Pay now', child: const SizedBox(width: 10, height: 10)),
      ),
    );
    expect(top(r), <String>['Semantics root/Holder@0']);
    h.dispose();
  });

  testWidgets('custom painter output is unexplained paint, flagged first', (WidgetTester tester) async {
    final ChangeReport r = await diffOf(
      tester,
      column(<Widget>[const Card2(), const Dots(radius: 5)]),
      column(<Widget>[const Card2(color: Color(0xFFF44336)), const Dots(radius: 6)]),
    );
    expect(top(r), <String>['Paint root/Dots@0', 'Style root/Card2@0']);
    expect(r.items.first.flagged, isTrue);
    expect(r.unexplainedCount, 1);
  });

  testWidgets('a parent that grew by its child\'s growth is that child\'s consequence', (WidgetTester tester) async {
    final ChangeReport r = await diffOf(
      tester,
      column(<Widget>[const Holder(child: Card2(label: 'a')), const Card2(label: 'b')]),
      column(<Widget>[const Holder(child: Card2(label: 'a', height: 60)), const Card2(label: 'b')]),
    );
    expect(top(r), <String>['Layout root/Holder@0/Card2@0']);
    final ReportItem item = r.items.single;
    expect(item.consequences.map((Change c) => '${c.type.label} ${c.nodeId}'), contains('Layout root/Holder@0'));
    expect(r.groups.single.cause!.nodeId, 'root/Holder@0/Card2@0');
  });

  testWidgets('padding that moves framework children inside a component is a layout change', (
    WidgetTester tester,
  ) async {
    final ChangeReport r = await diffOf(
      tester,
      const Holder2(
        child: SizedBox(
          width: 40,
          height: 40,
          child: Holder(child: ColoredBox(color: Color(0xFF000000))),
        ),
      ),
      const Holder2(
        child: SizedBox(
          width: 40,
          height: 40,
          child: Holder(
            child: Padding(
              padding: EdgeInsets.only(left: 1),
              child: ColoredBox(color: Color(0xFF000000)),
            ),
          ),
        ),
      ),
    );
    expect(top(r), <String>['Layout root/Holder2@0/Holder@0']);
    expect(r.items.single.change!.detail, startsWith('inside: '));
  });

  testWidgets('a pixel-hashed component that only moves keeps its paint and joins the shift', (
    WidgetTester tester,
  ) async {
    final ChangeReport r = await diffOf(
      tester,
      column(<Widget>[const Card2(label: 'a'), const Wave()]),
      column(<Widget>[const Card2(label: 'a', height: 50), const Wave()]),
    );
    expect(top(r), <String>['Layout root/Card2@0']);
    expect(r.groups.single.members.single.fullId, 'root/Wave@0');
  });

  testWidgets('a switch turned off is a style change on the component that holds it', (WidgetTester tester) async {
    Widget tile(bool on) => Holder(
      child: Material(
        child: Switch(value: on, onChanged: (_) {}),
      ),
    );
    final ChangeReport r = await diffOf(tester, tile(true), tile(false));
    expect(top(r), containsAll(<String>['Style root/Holder@0', 'Semantics root/Holder@0']));
    expect(r.items.first.change!.detail, contains('Switch.value: on -> off'));
  });

  testWidgets('a key change on the same output is an identity change and passes', (WidgetTester tester) async {
    final ChangeReport r = await diffOf(
      tester,
      column(<Widget>[const Card2(key: ValueKey<String>('a'))]),
      column(<Widget>[const Card2(key: ValueKey<String>('b'))]),
    );
    expect(top(r), <String>['Identity root/Card2#b']);
    expect(r.infoOnly, isTrue);
    expect(Policy.defaults().decide(r).verdict, Verdict.pass);
  });

  testWidgets('the same output under a new parent is moved', (WidgetTester tester) async {
    final ChangeReport r = await diffOf(
      tester,
      column(<Widget>[const Holder(child: SizedBox(height: 10)), const Card2(key: ValueKey<String>('k'))]),
      column(<Widget>[
        const Holder(child: SizedBox(height: 10)),
        const Holder2(child: Card2(key: ValueKey<String>('k'))),
      ]),
    );
    expect(top(r), containsAll(<String>['Added root/Holder2@0', 'Moved root/Holder2@0/Card2#k']));
  });

  testWidgets('a different toolchain goes to migration', (WidgetTester tester) async {
    await tester.pumpWidget(app(const Card2()));
    final Snapshot a = await captureSnapshot(tester, 'x', options: options);
    final b = Snapshot(
      id: a.id,
      inputs: a.inputs,
      toolchain: <String, String>{...a.toolchain, 'flutter': '9.9.9'},
      coverage: a.coverage,
      root: a.root,
    );
    final ChangeReport r = diffSnapshots(a, b);
    expect(r.kind, ReportKind.migration);
    expect(renderReport(r, Policy.defaults().decide(r)), contains('flutter: ${a.toolchain['flutter']} -> 9.9.9'));
  });

  group('policy', () {
    test('rules parse, and a pass rule must name a component and a type', () {
      final p = Policy.parse('# comment\npass Chart Paint\nforbid * Semantics\n');
      expect(p.rules.map((Rule r) => r.action), <RuleAction>[RuleAction.pass, RuleAction.forbid]);
      expect(() => Policy.parse('pass * Paint'), throwsFormatException);
      expect(() => Policy.parse('pass Chart *'), throwsFormatException);
      expect(() => Policy.parse('pass Chart Paint 1px'), throwsFormatException);
      expect(() => Policy.parse('pass Chart Colour'), throwsFormatException);
    });

    testWidgets('a pass rule passes only its component and type', (WidgetTester tester) async {
      final ChangeReport r = await diffOf(
        tester,
        column(<Widget>[const Card2(), const Dots(radius: 5)]),
        column(<Widget>[const Card2(), const Dots(radius: 6)]),
      );
      expect(Policy.parse('pass Dots Paint').decide(r).verdict, Verdict.pass);
      expect(Policy.parse('pass Dots Style').decide(r).verdict, Verdict.needsReview);
      expect(Policy.parse('pass Card2 Paint').decide(r).verdict, Verdict.needsReview);
    });

    testWidgets('a forbid rule fails, and so does a change outside the declared expectations', (
      WidgetTester tester,
    ) async {
      final ChangeReport r = await diffOf(
        tester,
        column(<Widget>[const Card2()]),
        column(<Widget>[const Card2(color: Color(0xFFF44336))]),
      );
      expect(Policy.parse('forbid * Style').decide(r).verdict, Verdict.fail);
      expect(Policy.parse('expect Card2 Style').decide(r).verdict, Verdict.needsReview);
      expect(Policy.parse('expect Card2 Layout').decide(r).verdict, Verdict.fail);
    });
  });
}

class Holder2 extends StatelessWidget {
  const Holder2({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
