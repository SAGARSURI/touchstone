// The review command: snapshot files at a git ref against the working tree.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/review.dart';
import 'package:touchstone/touchstone.dart';

class Tile extends StatelessWidget {
  const Tile({super.key, this.height = 20, this.color = const Color(0xFF000000)});
  final double height;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 100,
    height: height,
    child: ColoredBox(color: color),
  );
}

final options = SnapshotOptions(policy: ComponentPolicy(include: <Type>{Tile}));

Future<String> capture(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.topLeft, child: w),
    ),
  );
  return (await captureSnapshot(tester, 'tile', options: options)).toCanonical();
}

void git(String dir, List<String> args) {
  final ProcessResult r = Process.runSync('git', <String>[
    '-c',
    'user.name=t',
    '-c',
    'user.email=t@example.com',
    ...args,
  ], workingDirectory: dir);
  expect(r.exitCode, 0, reason: '${r.stderr}');
}

void main() {
  testWidgets('review compares each snapshot file with the base ref and applies the rules', (
    WidgetTester tester,
  ) async {
    final String base = await capture(tester, const Tile());
    final String restyled = await capture(tester, const Tile(color: Color(0xFFFF0000)));
    final String resized = await capture(tester, const Tile(height: 30));

    final Directory dir = Directory.systemTemp.createTempSync('touchstone_review');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String root = dir.resolveSymbolicLinksSync();
    File('$root/test/snapshots/a.snapshot')
      ..createSync(recursive: true)
      ..writeAsStringSync(base);
    File('$root/test/snapshots/b.snapshot').writeAsStringSync(base);
    File('$root/test/snapshots/gone.snapshot').writeAsStringSync(base);
    git(root, <String>['init', '-q']);
    git(root, <String>['add', '.']);
    git(root, <String>['commit', '-q', '-m', 'base']);

    File('$root/test/snapshots/a.snapshot').writeAsStringSync(restyled);
    File('$root/test/snapshots/b.snapshot').writeAsStringSync(resized);
    File('$root/test/snapshots/gone.snapshot').deleteSync();
    File('$root/test/snapshots/new.snapshot').writeAsStringSync(base);

    final ReviewResult r = review(base: 'HEAD', policy: Policy.defaults(), root: root);
    expect(r.reviews.map((SnapshotReview s) => '${s.path} ${s.decision.verdict.label}'), <String>[
      'test/snapshots/a.snapshot needs-review',
      'test/snapshots/b.snapshot needs-review',
      'test/snapshots/gone.snapshot needs-review',
      'test/snapshots/new.snapshot needs-review',
    ]);
    expect(r.exitCode, 2);
    expect(r.render(), contains('4 snapshots differ from HEAD: 0 pass, 4 needs-review, 0 fail.'));
    expect(r.reviews.first.text, contains('ColoredBox.color'));

    final ReviewResult strict = review(base: 'HEAD', policy: Policy.parse('forbid Tile Layout'), root: root);
    expect(strict.reviews[1].decision.verdict, Verdict.fail);
    expect(strict.exitCode, 1);

    File('$root/test/snapshots/a.snapshot').writeAsStringSync(base);
    File('$root/test/snapshots/b.snapshot').writeAsStringSync(base);
    File('$root/test/snapshots/gone.snapshot').writeAsStringSync(base);
    File('$root/test/snapshots/new.snapshot').deleteSync();
    final ReviewResult same = review(base: 'HEAD', policy: Policy.defaults(), root: root);
    expect(same.reviews, isEmpty);
    expect(same.exitCode, 0);
  });

  testWidgets('one token change in several snapshots is grouped under that token', (WidgetTester tester) async {
    const Color before = Color(0xFF000000);
    const Color after = Color(0xFFFF0000);
    final tokens = SnapshotOptions(
      policy: ComponentPolicy(include: <Type>{Tile}),
      tokenResolver: (Object v) => v == before || v == after ? 'brand.accent' : null,
    );
    Future<String> scene(Widget w) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(alignment: Alignment.topLeft, child: w),
        ),
      );
      return (await captureSnapshot(tester, 'tile', options: tokens)).toCanonical();
    }

    final String one = await scene(const Tile());
    final String two = await scene(const Column(children: <Widget>[Tile(), Tile(height: 30)]));
    final String oneAfter = await scene(const Tile(color: after));
    final String twoAfter = await scene(
      const Column(
        children: <Widget>[
          Tile(color: after),
          Tile(height: 30, color: after),
        ],
      ),
    );

    final Directory dir = Directory.systemTemp.createTempSync('touchstone_tokens');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String root = dir.resolveSymbolicLinksSync();
    File('$root/test/snapshots/one.snapshot')
      ..createSync(recursive: true)
      ..writeAsStringSync(one);
    File('$root/test/snapshots/two.snapshot').writeAsStringSync(two);
    git(root, <String>['init', '-q']);
    git(root, <String>['add', '.']);
    git(root, <String>['commit', '-q', '-m', 'base']);
    File('$root/test/snapshots/one.snapshot').writeAsStringSync(oneAfter);
    File('$root/test/snapshots/two.snapshot').writeAsStringSync(twoAfter);

    final ReviewResult r = review(base: 'HEAD', policy: Policy.defaults(), root: root);
    expect(r.reviews.first.text, contains('brand.accent #FF000000 -> #FFFF0000'));
    expect(
      r.render(),
      contains(
        'Causes in more than one snapshot:\n  brand.accent #FF000000 -> #FFFF0000: style change on 3 Tile in 2 snapshots\n',
      ),
    );
  });

  test('declared expectations hold only expect lines', () {
    final Directory dir = Directory.systemTemp.createTempSync('touchstone_expect');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/ok').writeAsStringSync('expect Tile Style\n');
    File('${dir.path}/bad').writeAsStringSync('pass Tile Style\n');
    expect(loadPolicy(rules: '${dir.path}/ok', expectations: '${dir.path}/ok').rules, hasLength(2));
    expect(() => loadPolicy(expectations: '${dir.path}/bad'), throwsFormatException);
  });
}
