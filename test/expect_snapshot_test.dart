// expectSnapshot's comparison: the failure message is the change report, and
// declared dynamic content is the one difference that passes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

class Price extends StatelessWidget {
  const Price(this.text, {super.key, this.height = 20});
  final String text;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(width: 100, height: height, child: Text(text));
}

class Row2 extends StatelessWidget {
  const Row2({super.key, required this.price, this.color = const Color(0xFF000000)});
  final Widget price;
  final Color color;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[price]),
  );
}

Widget app(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

SnapshotOptions options({Set<String> dynamic = const <String>{}}) => SnapshotOptions(
  policy: ComponentPolicy(include: <Type>{Price, Row2}),
  dynamicComponents: dynamic,
);

Future<(Snapshot, Snapshot)> pair(WidgetTester tester, Widget a, Widget b, {Set<String> dynamic = const {}}) async {
  await tester.pumpWidget(app(a));
  final Snapshot x = await captureSnapshot(tester, 'row', options: options(dynamic: dynamic));
  await tester.pumpWidget(app(b));
  final Snapshot y = await captureSnapshot(tester, 'row', options: options(dynamic: dynamic));
  return (x, y);
}

void main() {
  testWidgets('a difference fails with the change report as the message', (WidgetTester tester) async {
    final (Snapshot a, Snapshot b) = await pair(
      tester,
      const Row2(price: Price('12.50')),
      const Row2(price: Price('12.50'), color: Color(0xFF0000FF)),
    );
    final String? message = compareWithBaseline(a, b);
    expect(message, startsWith('row    fail\n'));
    expect(message, contains('Style'));
    expect(message, contains('Row2@0'));
    expect(message, contains('--update-goldens'));
  });

  testWidgets('content of a declared dynamic component is not compared', (WidgetTester tester) async {
    final (Snapshot a, Snapshot b) = await pair(
      tester,
      const Row2(price: Price('12.50')),
      const Row2(price: Price('13.75')),
      dynamic: <String>{'Price'},
    );
    expect(a.inputs['dynamic'], 'Price');
    expect(a.rootHash, isNot(b.rootHash));
    expect(compareWithBaseline(a, b), isNull);
  });

  testWidgets('the same content change fails when the component is not declared dynamic', (WidgetTester tester) async {
    final (Snapshot a, Snapshot b) = await pair(
      tester,
      const Row2(price: Price('12.50')),
      const Row2(price: Price('13.75')),
    );
    expect(compareWithBaseline(a, b), contains('Content'));
  });

  testWidgets('a dynamic component\'s layout is still compared', (WidgetTester tester) async {
    final (Snapshot a, Snapshot b) = await pair(
      tester,
      const Row2(price: Price('12.50')),
      const Row2(price: Price('13.75', height: 24)),
      dynamic: <String>{'Price'},
    );
    final String? message = compareWithBaseline(a, b);
    expect(message, contains('Layout'));
    expect(message, isNot(contains('Content')));
  });

  testWidgets('the update report shows what review will see', (WidgetTester tester) async {
    final (Snapshot a, Snapshot b) = await pair(
      tester,
      const Row2(price: Price('12.50')),
      const Row2(price: Price('12.50', height: 30)),
    );
    final String report = updateReport(a, b);
    expect(report, startsWith('row    needs-review\n'));
    expect(report, contains('size 100x20 -> 100x30'));
  });
}
