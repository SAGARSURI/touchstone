// Toolchain migration (spec: A12): pixel-identical snapshots re-baseline
// automatically with the pixel proof attached; the rest go to review.
//
// A second toolchain is simulated by rewriting the flutter version in a
// baseline and in its pending proof, as if both had been written by the old
// release.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/review.dart';
import 'package:touchstone/src/snapshot/migration.dart';
import 'package:touchstone/src/diff/ansi.dart';
import 'package:touchstone/touchstone.dart';

class Label extends StatelessWidget {
  const Label(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => SizedBox(width: 100, height: 20, child: Text(text));
}

final options = SnapshotOptions(policy: ComponentPolicy(include: <Type>{Label}));

Widget app(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

/// The text of a file written on this toolchain, as the old release would
/// have written it.
String asOldRelease(String text) => text.replaceAll(RegExp(r'flutter="[^"]*"'), 'flutter="3.47.5"');

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
  late Directory dir;
  late File baseline;

  setUp(() {
    dir = Directory(Directory.systemTemp.createTempSync('touchstone_migration').resolveSymbolicLinksSync());
    goldenFileComparator = LocalFileComparator(dir.uri.resolve('a_test.dart'));
    pendingProofDirectory = Directory('${dir.path}/build/touchstone/migration');
    baseline = File('${dir.path}/snapshots/label.snapshot');
  });

  tearDown(() {
    debugMigrationMode = null;
    dir.deleteSync(recursive: true);
  });

  /// Records a baseline of [text], proves it on this toolchain when [prove],
  /// then makes both look written by the old release. Returns the old
  /// baseline.
  Future<Snapshot> recordOnOldRelease(WidgetTester tester, String text, {bool prove = true}) async {
    await tester.pumpWidget(app(Label(text)));
    await expectSnapshot(tester, 'label', options: options, recordMissing: true);
    if (prove) {
      debugMigrationMode = MigrationMode.prove;
      await expectSnapshot(tester, 'label', options: options);
      final File pending = pendingProofFile('label');
      expect(pending.existsSync(), isTrue);
      pending.writeAsStringSync(asOldRelease(pending.readAsStringSync()));
    }
    baseline.writeAsStringSync(asOldRelease(baseline.readAsStringSync()));
    return Snapshot.parse(baseline.readAsStringSync());
  }

  Future<(Snapshot, MigrationProof)> apply(WidgetTester tester, String text) async {
    debugMigrationMode = MigrationMode.apply;
    await tester.pumpWidget(app(Label(text)));
    await expectSnapshot(tester, 'label', options: options);
    return (
      Snapshot.parse(baseline.readAsStringSync()),
      MigrationProof.parse(File('${dir.path}/snapshots/label.migration').readAsStringSync()),
    );
  }

  testWidgets('without migration, a baseline from another toolchain fails and is not compared', (
    WidgetTester tester,
  ) async {
    await recordOnOldRelease(tester, 'a', prove: false);
    debugMigrationMode = null;
    await expectLater(
      () => expectSnapshot(tester, 'label', options: options),
      throwsA(
        isA<TestFailure>().having(
          (TestFailure f) => stripAnsi(f.message ?? ''),
          'message',
          allOf(contains('different toolchain'), contains('flutter: 3.47.5 -> ')),
        ),
      ),
    );
  });

  testWidgets('identical pixels on both toolchains: the baseline is rewritten and review passes it', (
    WidgetTester tester,
  ) async {
    final Snapshot old = await recordOnOldRelease(tester, 'a');
    final (Snapshot updated, MigrationProof proof) = await apply(tester, 'a');

    expect(updated.toolchain, toolchainFingerprint());
    expect(proof.pixelsIdentical, isTrue);
    expect(proof.before.toolchain['flutter'], '3.47.5');
    expect(proof.after!.rootHash, updated.rootHash);

    final ChangeReport report = diffSnapshots(old, updated);
    final Decision decision = Policy.defaults().decide(report, proof: proof);
    expect(decision.verdict, Verdict.pass);
    expect(renderReport(report, decision), contains('Pixels identical on both toolchains (2400x1800 '));

    // The rewritten baseline now passes as an ordinary one.
    debugMigrationMode = null;
    await expectSnapshot(tester, 'label', options: options);
  });

  testWidgets('pixels that differ go to review with both digests', (WidgetTester tester) async {
    final Snapshot old = await recordOnOldRelease(tester, 'a');
    // The test font draws every glyph as the same box: a longer text, not a
    // different letter, changes the pixels.
    final (Snapshot updated, MigrationProof proof) = await apply(tester, 'ab');

    expect(proof.pixelsIdentical, isFalse);
    final Decision decision = Policy.defaults().decide(diffSnapshots(old, updated), proof: proof);
    expect(decision.verdict, Verdict.needsReview);
    expect(decision.reasons.last, startsWith('pixels differ: 2400x1800 '));
  });

  testWidgets('with no proof from the old toolchain, the migration goes to review', (WidgetTester tester) async {
    final Snapshot old = await recordOnOldRelease(tester, 'a', prove: false);
    final (Snapshot updated, MigrationProof proof) = await apply(tester, 'a');

    expect(proof.before.pixels, isNull);
    expect(proof.pixelsIdentical, isFalse);
    final Decision decision = Policy.defaults().decide(diffSnapshots(old, updated), proof: proof);
    expect(decision.verdict, Verdict.needsReview);
    expect(decision.reasons.last, contains('no pixels from the old toolchain'));
    expect(Policy.defaults().decide(diffSnapshots(old, updated)).reasons.last, 'no pixel proof');
  });

  testWidgets('a proof for other baselines does not pass a migration', (WidgetTester tester) async {
    final Snapshot old = await recordOnOldRelease(tester, 'a');
    final (Snapshot updated, MigrationProof proof) = await apply(tester, 'a');

    await tester.pumpWidget(app(const Label('c')));
    final Snapshot other = await captureSnapshot(tester, 'label', options: options);
    final Decision decision = Policy.defaults().decide(diffSnapshots(old, other), proof: proof);
    expect(decision.verdict, Verdict.needsReview);
    expect(decision.reasons.last, 'the pixel proof is for other baselines');
    expect(Policy.defaults().decide(diffSnapshots(old, updated), proof: proof).verdict, Verdict.pass);
  });

  testWidgets('review reads the proof beside each migrated snapshot', (WidgetTester tester) async {
    await recordOnOldRelease(tester, 'a');
    git(dir.path, <String>['init', '-q']);
    git(dir.path, <String>['add', 'snapshots']);
    git(dir.path, <String>['commit', '-q', '-m', 'old release']);
    await apply(tester, 'a');

    final ReviewResult result = review(base: 'HEAD', policy: Policy.defaults(), root: dir.path);
    expect(result.reviews.single.path, 'snapshots/label.snapshot');
    expect(result.verdict, Verdict.pass);
    expect(result.render(), contains('re-baselined automatically'));

    File('${dir.path}/snapshots/label.migration').deleteSync();
    final ReviewResult unproven = review(base: 'HEAD', policy: Policy.defaults(), root: dir.path);
    expect(unproven.verdict, Verdict.needsReview);
    expect(unproven.render(), contains('No pixel proof.'));
  });

  test('a proof survives its text form, and a pixels line that contradicts the digests is rejected', () {
    const proof = MigrationProof(
      'a/b',
      MigrationSide(<String, String>{'flutter': '3.47.6'}, 'r1', ViewPixels(800, 600, 'ab12')),
      MigrationSide(<String, String>{'flutter': '3.47.7'}, 'r2', ViewPixels(800, 600, 'ab12')),
    );
    final MigrationProof read = MigrationProof.parse(proof.toText());
    expect(read.toText(), proof.toText());
    expect(read.pixelsIdentical, isTrue);
    expect(
      () => MigrationProof.parse(proof.toText().replaceFirst('pixels\tidentical', 'pixels\tdiffer')),
      throwsFormatException,
    );
  });
}
