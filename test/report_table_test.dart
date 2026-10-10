// The change report as a table (table.dart): Before and After in their own
// columns, cells wrapped to fit 100 columns, borders lined up with or
// without colour.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/src/diff/ansi.dart';
import 'package:touchstone/src/diff/table.dart';
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

class Pad extends StatelessWidget {
  const Pad({super.key, required this.bottom});
  final double bottom;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottom),
    child: const SizedBox(width: 40, height: 40),
  );
}

final _options = SnapshotOptions(policy: ComponentPolicy(include: <Type>{Row2, Pad}));

Widget _app(String title, double bottom) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row2(title: title, hint: 'h'),
        Pad(bottom: bottom),
      ],
    ),
  ),
);

void main() {
  testWidgets('before and after in their own cells, every border lined up', (WidgetTester tester) async {
    await tester.pumpWidget(_app('Short', 8));
    await tester.pumpAndSettle();
    final Snapshot a = await captureSnapshot(tester, 'x', options: _options);
    await tester.pumpWidget(_app('A considerably longer title that will not fit in one cell of the table', 9));
    await tester.pumpAndSettle();
    final Snapshot b = await captureSnapshot(tester, 'x', options: _options);
    final ChangeReport r = diffSnapshots(a, b);
    final Decision d = Policy.defaults().decide(r);
    final String text = renderReport(r, d, table: true);
    final String colored = renderReport(r, d, table: true, color: true);
    printOnFailure(text);

    expect(stripAnsi(colored), text, reason: 'colour adds escapes and nothing else');
    final List<String> rows = text.split('\n').where((String l) => l.startsWith(RegExp('[│┌├└]'))).toList();
    expect(rows, isNotEmpty);
    for (final String l in rows) {
      expect(l.length, 100, reason: l);
    }
    for (final String l in colored.split('\n').where((String l) => l.contains('│'))) {
      expect(visibleLength(l), 100, reason: l);
    }
    final String header = rows.firstWhere((String l) => l.contains('Before'));
    final int beforeColumn = header.indexOf('Before');
    final int afterColumn = header.indexOf('After');
    final String size = rows.firstWhere((String l) => l.contains('│ size '));
    expect(size.indexOf('40x48'), beforeColumn);
    expect(size.indexOf('40x49'), afterColumn);
    final int title = rows.indexWhere((String l) => l.contains('"Short"'));
    expect(rows[title].indexOf('"Short"'), beforeColumn);
    expect(rows[title + 1].substring(afterColumn), startsWith('title'), reason: 'the long title wraps in its cell');
    expect(rows[title + 1].substring(beforeColumn, afterColumn - 2).trim(), '');
  });

  test('a cell breaks a long word after a dot, and carries an open colour to its next line', () {
    expect(wrapCell('Container.bg.borderRadius', 14), <String>['Container.bg.', 'borderRadius']);
    final List<String> lines = wrapCell('\x1B[31mone two three\x1B[0m', 8);
    expect(lines.map(stripAnsi), <String>['one two', 'three']);
    expect(lines[0], endsWith('\x1B[0m'), reason: 'closed before the border');
    expect(lines[1], startsWith('\x1B[31m'), reason: 'opened again');
  });
}
