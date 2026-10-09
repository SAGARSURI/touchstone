// Toolchain migration inside expectSnapshot (spec: A12). See
// ../diff/migration_proof.dart for the proof and how review uses it.
//
//   flutter test --dart-define=TOUCHSTONE_MIGRATION=prove   (old toolchain)
//   flutter test --dart-define=TOUCHSTONE_MIGRATION=apply   (new toolchain)
//
// `dart run touchstone:migrate` runs both.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../audit/pixels.dart';
import '../diff/migration_proof.dart';
import '../recorder/pixel_digest.dart';
import 'snapshot.dart';

enum MigrationMode {
  /// A normal run.
  off,

  /// On the old toolchain: snapshots that match their baselines write a
  /// pending proof.
  prove,

  /// On the new toolchain: baselines from another toolchain are rewritten,
  /// each with its proof.
  apply,
}

const String _define = String.fromEnvironment('TOUCHSTONE_MIGRATION');

/// Overrides the mode set with `--dart-define`, for tests.
@visibleForTesting
MigrationMode? debugMigrationMode;

MigrationMode get migrationMode =>
    debugMigrationMode ??
    switch (_define) {
      '' => MigrationMode.off,
      'prove' => MigrationMode.prove,
      'apply' => MigrationMode.apply,
      _ => throw ArgumentError('TOUCHSTONE_MIGRATION must be prove or apply, not "$_define"'),
    };

/// Where the old toolchain's pending proofs are kept between the two runs,
/// under the package's build directory.
@visibleForTesting
Directory pendingProofDirectory = Directory('build/touchstone/migration');

File pendingProofFile(String id) => File('${pendingProofDirectory.path}/${id.replaceAll('/', '__')}.proof');

/// The proof committed beside the baseline [baseline].
File proofFileFor(File baseline) =>
    File('${baseline.path.substring(0, baseline.path.length - '.snapshot'.length)}.migration');

/// Rasterizes the whole test view and digests it.
Future<ViewPixels> viewPixels(WidgetTester tester) async {
  await tester.pump();
  final RenderView view = tester.binding.renderViews.first;
  final PixelRegion region = (await tester.runAsync(() => rasterize(view, Offset.zero & view.size)))!;
  // Compositing the view runs composition callbacks; pump the frames they
  // schedule, without advancing time, as capture does.
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
  return ViewPixels(region.width, region.height, pixelDigest(region.rgba));
}

/// On the old toolchain, after [baseline] matched its capture: records the
/// view's pixels for the run on the new toolchain.
Future<void> writePendingProof(WidgetTester tester, Snapshot baseline) async {
  final ViewPixels pixels = await viewPixels(tester);
  pendingProofFile(baseline.id)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      MigrationProof(baseline.id, MigrationSide(baseline.toolchain, baseline.rootHash, pixels)).toText(),
    );
}

/// On the new toolchain: the proof for moving [old] to [updated], from the
/// pending proof when one covers [old].
Future<MigrationProof> completeProof(WidgetTester tester, Snapshot old, Snapshot updated) async {
  final File pending = pendingProofFile(old.id);
  MigrationSide before = MigrationSide(old.toolchain, old.rootHash, null);
  if (pending.existsSync()) {
    final MigrationProof p = MigrationProof.parse(pending.readAsStringSync());
    if (p.before.rootHash == old.rootHash && mapEquals(p.before.toolchain, old.toolchain)) {
      before = p.before;
    }
  }
  final ViewPixels pixels = await viewPixels(tester);
  return MigrationProof(old.id, before, MigrationSide(updated.toolchain, updated.rootHash, pixels));
}
