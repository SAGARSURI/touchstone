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

// A tile that also draws a colour derived from its own, which has no token.
class ShadedTile extends StatelessWidget {
  const ShadedTile({super.key, this.color = const Color(0xFF000000)});
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 100,
    height: 20,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: color.withAlpha(0x80)),
      ),
    ),
  );
}

// A tile with a colour and a corner radius, and a line of text.
class RoundTile extends StatelessWidget {
  const RoundTile({super.key, this.color = const Color(0xFF000000), this.radius = 4, this.text = ''});
  final Color color;
  final double radius;
  final String text;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 100,
    height: 20,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
      child: Text(text, maxLines: 1),
    ),
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
    // Dart's own compiled snapshots, committed by mistake, are not ours.
    File('$root/.dart_tool/pub/bin/touchstone/review.dart-3.13.5.snapshot')
      ..createSync(recursive: true)
      ..writeAsBytesSync(<int>[0x80, 0xFF, 0x00]);
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
    // The overview comes first and names every change once; each snapshot's
    // report follows, and the verdict line is also the last line.
    final List<String> lines = r.render().trimRight().split('\n');
    final String overview = lines.takeWhile((String l) => l != 'Each snapshot:').join('\n');
    expect(lines.first, startsWith('4 snapshots differ from HEAD'));
    expect(lines.last, lines.first);
    // A summary of at most five lines opens it, naming what fits on a line
    // and counting the rest; the overview follows under "All changes:".
    expect(lines.sublist(1, 4), <String>[
      'Also: Style Tile, Layout Tile, test/snapshots/gone.snapshot (snapshot removed), +1 more',
      '',
      'All changes:',
    ]);
    expect(
      renderSummary(<String, ChangeReport>{
        for (final SnapshotReview s in r.reviews)
          if (s.report case final ChangeReport report) s.path: report,
      }, width: 25),
      'Also: Style Tile, +1 more\n',
    );
    expect(overview, contains('Other changes:\n'));
    expect(
      overview,
      contains('  Style Tile: ColoredBox.color: #FF000000 -> #FFFF0000, in test/snapshots/a.snapshot\n'),
    );
    expect(overview, contains('  Layout Tile: '));
    expect(overview, contains('SizedBox.height: 20.0 -> 30.0, in test/snapshots/b.snapshot\n'));
    expect(overview, contains('  test/snapshots/gone.snapshot: snapshot removed\n'));
    expect(overview, contains('  test/snapshots/new.snapshot: new snapshot'));
    expect(overview, isNot(contains('Unexplained')));
    expect(r.reviews.first.text, contains('ColoredBox.color'));

    final ReviewResult strict = review(base: 'HEAD', policy: Policy.parse('forbid Tile Layout'), root: root);
    expect(strict.reviews[1].decision.verdict, Verdict.fail);
    expect(strict.exitCode, 1);
    // The summary names what fails the rules before anything else.
    expect(strict.render().split('\n')[1], 'Fails the rules: Layout Tile');

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
      policy: ComponentPolicy(include: <Type>{Tile, ShadedTile}),
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
    final String two = await scene(const Column(children: <Widget>[Tile(), Tile(height: 30), ShadedTile()]));
    final String oneAfter = await scene(const Tile(color: after));
    final String twoAfter = await scene(
      const Column(
        children: <Widget>[
          Tile(color: after),
          Tile(height: 30, color: after),
          ShadedTile(color: after),
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
        'Causes in more than one snapshot:\n  brand.accent #FF000000 -> #FFFF0000: style change on 3 Tile, 1 ShadedTile in 2 snapshots\n',
      ),
    );
    expect(r.render().split('\n')[1], 'Shared cause: brand.accent #FF000000 -> #FFFF0000, 4 components in 2 snapshots');
    // Changes a shared cause explains are not listed again in the overview.
    expect(r.render().split('Each snapshot:').first, isNot(contains('Style Tile')));
  });

  testWidgets('the overview keeps what a shared cause does not explain, and groups by whole values', (
    WidgetTester tester,
  ) async {
    const Color before = Color(0xFF000000);
    const Color after = Color(0xFFFF0000);
    final tokens = SnapshotOptions(
      policy: ComponentPolicy(include: <Type>{RoundTile}),
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

    final String long = 'a' * 120;
    final Directory dir = Directory.systemTemp.createTempSync('touchstone_overview');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String root = dir.resolveSymbolicLinksSync();
    Directory('$root/test/snapshots').createSync(recursive: true);
    void write(String name, String text) => File('$root/test/snapshots/$name.snapshot').writeAsStringSync(text);
    write('one', await scene(const RoundTile()));
    write('two', await scene(const RoundTile()));
    write('three', await scene(RoundTile(text: long)));
    write('four', await scene(RoundTile(text: long)));
    git(root, <String>['init', '-q']);
    git(root, <String>['add', '.']);
    git(root, <String>['commit', '-q', '-m', 'base']);
    // The token changes in two snapshots; in one, the radius changes too.
    write('one', await scene(const RoundTile(color: after)));
    write('two', await scene(const RoundTile(color: after, radius: 8)));
    // The same long text changes to two different texts.
    write('three', await scene(RoundTile(text: '${long}b')));
    write('four', await scene(RoundTile(text: '${long}c')));

    final String overview = review(
      base: 'HEAD',
      policy: Policy.defaults(),
      root: root,
    ).render().split('Each snapshot:').first.replaceAll('\n      ', ' ');
    expect(overview, contains('brand.accent #FF000000 -> #FFFF0000: style change on 2 RoundTile in 2 snapshots'));
    expect(overview, matches(RegExp(r'Style RoundTile: [^\n]*BorderRadius')));
    // The token's own colour field is the shared cause, not listed again.
    expect(overview, isNot(contains('bg.color')));
    expect(overview, contains('in test/snapshots/three.snapshot'));
    expect(overview, contains('in test/snapshots/four.snapshot'));
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
