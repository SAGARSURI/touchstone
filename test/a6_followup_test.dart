// Report changes after the A6 review (doc/phase3/a6_followup_expectations.md):
// one edit to a shared widget is one cause, ink that follows moved tiles is
// not unexplained paint, and a removed child's semantics node goes with it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

class Bar extends StatelessWidget {
  const Bar({super.key, this.height = 40, this.label = 'bar'});
  final double height;
  final String label;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF2196F3)),
      child: Text(label),
    ),
  );
}

class Header extends StatelessWidget {
  const Header({super.key, this.bottom = 8});
  final double bottom;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, bottom), child: const Text('Section'));
}

class Tile extends StatelessWidget {
  const Tile({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => ListTile(title: Text(title));
}

/// A Material that paints its tiles' ink, so its own paint draws at their
/// bounds.
class Sheet extends StatelessWidget {
  const Sheet({super.key, this.bottom = 8});
  final double bottom;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 300,
    child: Material(
      child: Column(
        children: <Widget>[
          Header(bottom: bottom),
          const Tile(title: 'a'),
          Header(bottom: bottom),
          const Tile(title: 'b'),
        ],
      ),
    ),
  );
}

class Dot extends StatelessWidget {
  const Dot({super.key, required this.radius});
  final double radius;
  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(20, 20), painter: _Dot(radius));
}

class _Dot extends CustomPainter {
  _Dot(this.radius);
  final double radius;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawCircle(const Offset(10, 10), radius, Paint());
  @override
  bool shouldRepaint(_Dot old) => old.radius != radius;
}

/// Gives each child its own labelled semantics node, which this component
/// owns.
class Labelled extends StatelessWidget {
  const Labelled({super.key, required this.radii});
  final List<double> radii;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 80,
    child: Column(
      children: <Widget>[
        for (final double r in radii)
          Semantics(
            container: true,
            label: 'dot $r',
            child: Dot(radius: r),
          ),
      ],
    ),
  );
}

final _options = SnapshotOptions(policy: ComponentPolicy(include: <Type>{Bar, Header, Tile, Sheet, Dot, Labelled}));

Widget _app(Widget child) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: 200, child: child),
  ),
);

Future<ChangeReport> _diff(WidgetTester tester, Widget before, Widget after) async {
  await tester.pumpWidget(_app(before));
  await tester.pumpAndSettle();
  final Snapshot a = await captureSnapshot(tester, 'x', options: _options);
  await tester.pumpWidget(_app(after));
  await tester.pumpAndSettle();
  final Snapshot b = await captureSnapshot(tester, 'x', options: _options);
  return diffSnapshots(a, b);
}

String _render(ChangeReport r) => renderReport(r, Policy.defaults().decide(r));

Widget _bars(double h) => Column(
  mainAxisSize: MainAxisSize.min,
  children: <Widget>[
    Bar(height: h),
    const Bar(label: 'x'),
    Bar(height: h),
    const Bar(label: 'y'),
  ],
);

void main() {
  testWidgets('one edit to copies of a widget is one cause of the shifts below them', (WidgetTester tester) async {
    final ChangeReport r = await _diff(tester, _bars(40), _bars(41));
    expect(r.groups, hasLength(2));
    expect(r.items.where((ReportItem i) => i.group != null), isEmpty);
    final String text = _render(r);
    expect(text, contains('Bar in 2 places'));
    expect(text, contains('consequence: 2 components shifted down 1 to 2 px'));
    expect(text, isNot(contains('possible causes')));
  });

  testWidgets('different changes above a shift are still only possible causes', (WidgetTester tester) async {
    final ChangeReport r = await _diff(
      tester,
      _bars(40),
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Bar(height: 41),
          Bar(label: 'x'),
          Bar(height: 42),
          Bar(label: 'y'),
        ],
      ),
    );
    expect(_render(r), contains('possible causes'));
  });

  testWidgets('ink drawn at moved tiles is not unexplained paint', (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final ChangeReport r = await _diff(tester, const Sheet(), const Sheet(bottom: 9));
    expect(r.unexplainedCount, 0);
    expect(r.items.where((ReportItem i) => i.flagged), isEmpty);
    final String text = _render(r);
    expect(text, contains('Header in 2 places'));
    expect(text, contains('repainted only to follow it: Sheet around it'));
    expect(text, isNot(contains('not verified')));
    h.dispose();
  });

  testWidgets("a removed child's semantics node goes with it", (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final ChangeReport r = await _diff(
      tester,
      const Labelled(radii: <double>[4, 5, 6]),
      const Labelled(radii: <double>[5, 6]),
    );
    expect(r.items, hasLength(1));
    expect(r.items.single.change!.type, ChangeType.removed);
    final String text = _render(r);
    expect(text, contains('3 -> 2 semantics nodes'));
    expect(text, contains('went with the child'));
    expect(text, isNot(contains('"dot 4.0" -> "dot 5.0"')));
    h.dispose();
  });
}
