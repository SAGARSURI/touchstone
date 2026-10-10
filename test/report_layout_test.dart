// The report layout after the DX sessions (doc/phase3/dx_results.md): a
// count of items by type under the verdict, a blank line between items, one
// line per distinct change, and long values broken before their arrow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

class Row2 extends StatelessWidget {
  const Row2({super.key, required this.title, required this.hint});
  final String title;
  final String hint;
  @override
  Widget build(BuildContext context) => Semantics(
    label: hint,
    child: SizedBox(width: 300, height: 40, child: Text(title)),
  );
}

class Box extends StatelessWidget {
  const Box({super.key, required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(width: 40, height: 40, child: ColoredBox(color: color));
}

class Pad extends StatelessWidget {
  const Pad({super.key, required this.bottom});
  final double bottom;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottom),
    child: const SizedBox(width: 40, height: 40),
  );
}

final _options = SnapshotOptions(policy: ComponentPolicy(include: <Type>{Row2, Box, Pad}));

Widget _app(Widget a, Widget b) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[a, b]),
  ),
);

void main() {
  testWidgets('each distinct change gets its own line, long ones break before the arrow', (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(_app(const Row2(title: 'Short', hint: 'a'), const Box(color: Color(0xFF000000))));
    await tester.pumpAndSettle();
    final Snapshot a = await captureSnapshot(tester, 'x', options: _options);
    await tester.pumpWidget(
      _app(
        const Row2(title: 'A considerably longer title that will not fit on one line', hint: 'b'),
        const Box(color: Color(0xFFFFFFFF)),
      ),
    );
    await tester.pumpAndSettle();
    final Snapshot b = await captureSnapshot(tester, 'x', options: _options);
    final ChangeReport r = diffSnapshots(a, b);
    final String text = renderReport(r, Policy.defaults().decide(r));
    final List<String> lines = text.split('\n');

    expect(lines[1], startsWith('2 items: '));
    expect(text, isNot(contains('more field')));
    expect(text, contains('\n\n2  '), reason: 'a blank line before the second item');
    for (final String line in lines) {
      expect(line.length, lessThanOrEqualTo(100), reason: line);
    }
    final int title = lines.indexWhere((String l) => l.contains('"Short"'));
    expect(lines[title + 1].trimLeft(), startsWith('-> "A considerably longer title'));
    final int value = lines[title].indexOf(RegExp(r'\S+: "Short"'));
    expect(lines[title + 1].indexOf('->'), value + 2, reason: 'the arrow sits just inside the value column');
    printOnFailure(text);
    h.dispose();
  });

  testWidgets('a long "at:" line breaks between instances, under its label', (WidgetTester tester) async {
    Widget boxes(Color color) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: Wrap(children: <Widget>[for (var i = 0; i < 20; i++) Box(color: color)]),
      ),
    );
    await tester.pumpWidget(boxes(const Color(0xFF000000)));
    await tester.pumpAndSettle();
    final Snapshot a = await captureSnapshot(tester, 'x', options: _options);
    await tester.pumpWidget(boxes(const Color(0xFFFFFFFF)));
    await tester.pumpAndSettle();
    final Snapshot b = await captureSnapshot(tester, 'x', options: _options);
    final ChangeReport r = diffSnapshots(a, b);
    final String text = renderReport(r, Policy.defaults().decide(r));
    final List<String> lines = text.split('\n');

    expect(text, contains('Box in 20 places'));
    for (final String line in lines) {
      expect(line.length, lessThanOrEqualTo(100), reason: line);
    }
    final int at = lines.indexWhere((String l) => l.trimLeft().startsWith('at: Box@0, '));
    expect(at, greaterThan(0));
    final int column = lines[at].indexOf('Box@0');
    expect(lines[at + 1].indexOf(RegExp(r'\S')), column, reason: 'the next line starts under the first instance');
    expect(lines.skip(at).join(' '), contains('Box@19'));
    printOnFailure(text);
  });

  testWidgets("a layout change's size and the property that changed it are on separate lines", (
    WidgetTester tester,
  ) async {
    Widget pad(double bottom) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: Pad(bottom: bottom),
      ),
    );
    await tester.pumpWidget(pad(8));
    await tester.pumpAndSettle();
    final Snapshot a = await captureSnapshot(tester, 'x', options: _options);
    await tester.pumpWidget(pad(9));
    await tester.pumpAndSettle();
    final Snapshot b = await captureSnapshot(tester, 'x', options: _options);
    final ChangeReport r = diffSnapshots(a, b);
    final String text = renderReport(r, Policy.defaults().decide(r));
    final List<String> lines = text.split('\n');

    final int size = lines.indexWhere((String l) => l.endsWith('size 40x48 -> 40x49'));
    expect(size, greaterThan(0));
    expect(lines[size + 1].trimLeft(), startsWith('Padding.padding: '));
    expect(r.items.single.change!.summary, startsWith('size 40x48 -> 40x49; Padding.padding: '));
    printOnFailure(text);
  });
}
