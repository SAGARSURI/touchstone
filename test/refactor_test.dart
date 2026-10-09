// A5: refactors that change the widget structure but not the output are one
// info-level identity change, and look-alike edits that change the output are
// not (doc/phase2/a5_expectations.md, "Adversarial unit tests").

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

/// A row whose two labels are built inline, or by a [Labels] component.
class Tile extends StatelessWidget {
  const Tile({
    super.key,
    this.extract = false,
    this.labelColor = const Color(0xFF000000),
    this.labelPadding = 0,
    this.labelSemantics,
  });

  final bool extract;
  final Color labelColor;
  final double labelPadding;
  final String? labelSemantics;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFE0E0E0)),
      child: extract
          ? Labels(color: labelColor, padding: labelPadding, semantics: labelSemantics)
          : labels(const Color(0xFF000000), 0, null),
    ),
  );
}

Widget labels(Color color, double padding, String? semantics) {
  Widget out = Row(
    children: <Widget>[
      Text('AAPL', style: TextStyle(color: color)),
      const SizedBox(width: 8),
      const Text('Apple'),
    ],
  );
  if (padding > 0) {
    out = Padding(padding: EdgeInsets.all(padding), child: out);
  }
  if (semantics != null) {
    out = Semantics(label: semantics, child: out);
  }
  return out;
}

class Labels extends StatelessWidget {
  const Labels({super.key, required this.color, required this.padding, required this.semantics});

  final Color color;
  final double padding;
  final String? semantics;

  @override
  Widget build(BuildContext context) => labels(color, padding, semantics);
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => avatar(size);
}

/// [Avatar] after a rename.
class Monogram extends StatelessWidget {
  const Monogram({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => avatar(size);
}

Widget avatar(double size) => Container(
  width: size,
  height: size,
  decoration: BoxDecoration(color: const Color(0xFF3F51B5), borderRadius: BorderRadius.circular(8)),
  child: const Center(child: Text('A')),
);

/// A wrapper component.
class Frame extends StatelessWidget {
  const Frame({super.key, required this.child, this.clip = false});
  final Widget child;
  final bool clip;
  @override
  Widget build(BuildContext context) => clip ? ClipRRect(borderRadius: BorderRadius.circular(12), child: child) : child;
}

final options = SnapshotOptions(policy: ComponentPolicy(include: <Type>{Tile, Labels, Avatar, Monogram, Frame}));

Widget app(List<Widget> children) => Directionality(
  textDirection: TextDirection.ltr,
  child: ColoredBox(
    color: const Color(0xFFFFFFFF),
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    ),
  ),
);

Future<ChangeReport> diffOf(WidgetTester tester, List<Widget> before, List<Widget> after) async {
  await tester.pumpWidget(app(before));
  final Snapshot a = await captureSnapshot(tester, 'x', options: options);
  await tester.pumpWidget(app(after));
  final Snapshot b = await captureSnapshot(tester, 'x', options: options);
  return diffSnapshots(a, b);
}

List<String> items(ChangeReport r) => <String>[
  for (final ReportItem i in r.items)
    i.change != null ? '${i.change!.type.label} ${i.change!.nodeId}' : 'Shift ${i.group!.ancestor.fullId}',
];

Verdict verdict(ChangeReport r) => Policy.defaults().decide(r).verdict;

/// Whether an Identity item covers [id] or a component around it.
bool identityCovers(ChangeReport r, String id) => r.items.any(
  (ReportItem i) =>
      i.change?.type == ChangeType.identity && (id == i.change!.nodeId || id.startsWith('${i.change!.nodeId}/')),
);

void main() {
  group('refactors with the same output', () {
    testWidgets('extracting a widget is one identity change on its parent', (WidgetTester tester) async {
      final ChangeReport r = await diffOf(
        tester,
        const <Widget>[Tile(), Tile()],
        const <Widget>[Tile(extract: true), Tile(extract: true)],
      );
      expect(items(r), <String>['Identity root/Tile@0', 'Identity root/Tile@1']);
      expect(r.items.first.change!.detail, 'same output; added Labels');
      expect(verdict(r), Verdict.pass);
    });

    testWidgets('inlining a widget is one identity change on its parent', (WidgetTester tester) async {
      final ChangeReport r = await diffOf(tester, const <Widget>[Tile(extract: true)], const <Widget>[Tile()]);
      expect(items(r), <String>['Identity root/Tile@0']);
      expect(r.items.single.change!.detail, 'same output; removed Labels');
      expect(verdict(r), Verdict.pass);
    });

    testWidgets('renaming a class is one identity change on it', (WidgetTester tester) async {
      final ChangeReport r = await diffOf(tester, const <Widget>[Avatar()], const <Widget>[Monogram()]);
      expect(items(r), <String>['Identity root/Monogram@0']);
      expect(r.items.single.change!.detail, 'same output; renamed Avatar -> Monogram');
      expect(verdict(r), Verdict.pass);
    });
  });

  group('look-alike edits that change the output', () {
    testWidgets('extract a widget and change a colour inside it', (WidgetTester tester) async {
      final ChangeReport r = await diffOf(
        tester,
        const <Widget>[Tile()],
        const <Widget>[Tile(extract: true, labelColor: Color(0xFFFF0000))],
      );
      expect(verdict(r), Verdict.needsReview);
      expect(identityCovers(r, 'root/Tile@0/Labels@0'), isFalse);
    });

    testWidgets('extract a widget that adds padding', (WidgetTester tester) async {
      final ChangeReport r = await diffOf(
        tester,
        const <Widget>[Tile()],
        const <Widget>[Tile(extract: true, labelPadding: 2)],
      );
      expect(verdict(r), Verdict.needsReview);
      expect(identityCovers(r, 'root/Tile@0/Labels@0'), isFalse);
    });

    testWidgets('rename a class and change its size', (WidgetTester tester) async {
      final ChangeReport r = await diffOf(tester, const <Widget>[Avatar()], const <Widget>[Monogram(size: 37)]);
      expect(verdict(r), Verdict.needsReview);
      expect(items(r), containsAll(<String>['Removed root/Avatar@0', 'Added root/Monogram@0']));
      expect(identityCovers(r, 'root/Monogram@0'), isFalse);
    });

    testWidgets('inline a widget whose semantics label differs', (WidgetTester tester) async {
      final ChangeReport r = await diffOf(
        tester,
        const <Widget>[Tile(extract: true, labelSemantics: 'Apple stock')],
        const <Widget>[Tile()],
      );
      expect(verdict(r), Verdict.needsReview);
      expect(identityCovers(r, 'root/Tile@0'), isFalse);
    });

    testWidgets('move a child into a new wrapper component that also clips it', (WidgetTester tester) async {
      final ChangeReport r = await diffOf(
        tester,
        const <Widget>[Avatar()],
        const <Widget>[Frame(clip: true, child: Avatar())],
      );
      expect(verdict(r), Verdict.needsReview);
      expect(identityCovers(r, 'root/Frame@0/Avatar@0'), isFalse);
    });
  });
}
