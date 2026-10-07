// Phase 0 feasibility spikes (spec, Phases and exit gates):
//
//  A1  a custom recording context captures each node's own paint, including
//      opacity and layer effects: every paint mutation changes a paint hash in
//      the mutated subtree.
//  A2  paths, images and text are fingerprinted without rasterizing: no missed
//      mutation, no fingerprint change across repeats.
//  A4  equal hashes imply equal pixels: the shadow pixel audit finds 0 capture
//      gaps.
//  A10 first numbers: capture cost, snapshot size, share of opaque nodes.
//
// Results are written to build/phase0/ for the assumption register.

import 'dart:convert';
import 'dart:io';

import 'package:fixture_app/screens.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

import '../support/harness.dart';

/// Captures of the same commit per screen, compared byte for byte.
const int repeatsPerScreen = 5;

class MutationResult {
  MutationResult(this.screen, this.mutation, this.base, this.mutant);

  final String screen;
  final Mutation mutation;
  final Capture base;
  final Capture mutant;

  bool get recordingChanged => base.rootHash != mutant.rootHash;
  bool get pixelsChanged => !base.pixels.sameAs(mutant.pixels);

  /// The tagged subtree's hash changed: own paint, placement or child order.
  bool get targetSubtreeChanged =>
      base.byKey[mutation.target]?.subtreeHash != mutant.byKey[mutation.target]?.subtreeHash;

  bool get targetPaintChanged {
    final List<String> a = base.paintHashesUnder(mutation.target);
    final List<String> b = mutant.paintHashesUnder(mutation.target);
    return a.length != b.length || !_listEquals(a, b);
  }

  /// Changed the hash only through an opaque node's pixel hash: nothing
  /// recorded by value changed.
  bool get caughtOnlyByPixels => recordingChanged && base.valueText == mutant.valueText;

  /// Equal hashes with different pixels.
  bool get captureGap => !recordingChanged && pixelsChanged;

  /// A mutation the oracle can see, or that the fixture declares visible,
  /// that left the recording unchanged. Semantics are not recorded until
  /// Phase 1, so semantics mutations are out of scope here.
  bool get missed =>
      mutation.kind != MutationKind.semantics &&
      !recordingChanged &&
      (pixelsChanged || mutation.pixels == PixelExpectation.changes);

  /// Outside the pixel oracle's sight (glyph content under the box font):
  /// recorded or not, the oracle cannot judge it, so it is listed.
  bool get outsideOracle => mutation.pixels == PixelExpectation.outsideOracle && !pixelsChanged;

  /// A reported change with identical pixels, where the change is not one the
  /// spec places outside the oracle's sight.
  bool get falseAlarm => recordingChanged && !pixelsChanged && mutation.pixels != PixelExpectation.outsideOracle;

  /// The fixture's declared pixel expectation did not hold.
  bool get expectationWrong => switch (mutation.pixels) {
    PixelExpectation.changes => !pixelsChanged,
    PixelExpectation.unchanged => pixelsChanged,
    PixelExpectation.outsideOracle => pixelsChanged,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'screen': screen,
    'mutation': mutation.name,
    'kind': mutation.kind.name,
    'pixelExpectation': mutation.pixels.name,
    'recordingChanged': recordingChanged,
    'targetPaintChanged': targetPaintChanged,
    'targetSubtreeChanged': targetSubtreeChanged,
    'pixelsChanged': pixelsChanged,
    'differingPixels': base.pixels.differingPixels(mutant.pixels),
    'caughtOnlyByPixels': caughtOnlyByPixels,
    'captureGap': captureGap,
    'missed': missed,
    'falseAlarm': falseAlarm,
    'outsideOracle': outsideOracle,
    'expectationWrong': expectationWrong,
  };
}

bool _listEquals(List<String> a, List<String> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

void main() {
  final results = <MutationResult>[];
  final repeatDiffs = <String, int>{};
  final screenStats = <Map<String, Object?>>[];
  final kinds = <String, Map<String, Object?>>{};
  final rootHashes = <String, String>{};

  void countKinds(Capture capture) {
    for (final RecordedNode n in capture.recording.nodes) {
      final Map<String, Object?> k = kinds.putIfAbsent(
        n.renderObject.runtimeType.toString(),
        () => <String, Object?>{'nodes': 0, 'opaque': 0, 'reasons': <String>{}},
      );
      k['nodes'] = (k['nodes']! as int) + 1;
      if (n.isOpaque) {
        k['opaque'] = (k['opaque']! as int) + 1;
        (k['reasons']! as Set<String>).addAll(n.opaque.keys.map((OpaqueReason r) => r.name));
      }
    }
  }

  for (final FixtureScreen screen in fixtureScreens) {
    testWidgets('phase 0: ${screen.name}', (WidgetTester tester) async {
      final FixtureAssets assets = await makeAssets(tester);

      // Repeats: the same commit must give the same recording.
      final captures = <Capture>[
        for (var i = 0; i < repeatsPerScreen; i++) await captureFixture(tester, screen, screen.knobs, assets),
      ];
      final Capture base = captures.first;
      rootHashes[screen.name] = base.rootHash;
      var diffs = 0;
      for (final Capture c in captures.skip(1)) {
        if (c.rootHash != base.rootHash) {
          diffs++;
        }
        expect(c.pixels.sameAs(base.pixels), isTrue, reason: 'pixel oracle is not deterministic');
      }
      repeatDiffs[screen.name] = diffs;
      countKinds(base);
      final opsDir = Directory('build/phase0/ops')..createSync(recursive: true);
      File('${opsDir.path}/${screen.name}.txt').writeAsStringSync(
        base.recording.nodes
            .map((RecordedNode n) => '${n.index} ${n.renderObject.runtimeType} ${n.ops.join(' | ')}')
            .join('\n'),
      );

      // A10: cost of the same pump without capture, and snapshot size.
      final plainPumps = <int>[];
      for (var i = 0; i < repeatsPerScreen; i++) {
        final plain = Stopwatch()..start();
        await captureFixtureWithoutRecording(tester, screen, assets);
        plain.stop();
        plainPumps.add(plain.elapsedMicroseconds);
      }
      final List<RecordedNode> opaqueNodes = base.recording.nodes.where((RecordedNode n) => n.isOpaque).toList();
      final int opaque = opaqueNodes.length;
      final Rect view = base.recording.viewRect;
      final int unverified = base.recording.nodes.where((RecordedNode n) => !n.geometryVerified).length;
      final int bytes = base.recording.nodes.fold<int>(
        0,
        (int sum, RecordedNode n) => sum + utf8.encode(n.ops.join('\n')).length,
      );
      screenStats.add(<String, Object?>{
        'screen': screen.name,
        'nodes': base.recording.nodes.length,
        'opaqueNodes': opaque,
        'opaqueKinds': <String>{
          for (final RecordedNode n in base.recording.nodes)
            if (n.isOpaque) '${n.renderObject.runtimeType}(${n.opaque.keys.map((OpaqueReason r) => r.name).join('+')})',
        }.toList(),
        'unverifiedGeometryNodes': unverified,
        'opaqueRegions': <String>[
          for (final RecordedNode n in opaqueNodes) '${n.renderObject.runtimeType} ${base.recording.opaqueRegion(n)}',
        ],
        'opaqueAreaShare':
            opaqueNodes.fold<double>(0, (double sum, RecordedNode n) {
              final Rect r = base.recording.opaqueRegion(n);
              return sum + r.width * r.height;
            }) /
            (view.width * view.height),
        'opsBytes': bytes,
        'pumpMicros': plainPumps,
        'pumpInCaptureMicros': captures.map((Capture c) => c.timings.pump.inMicroseconds).toList(),
        'rasterMicros': captures.map((Capture c) => c.timings.raster.inMicroseconds).toList(),
        'recordMicros': captures.map((Capture c) => c.timings.record.inMicroseconds).toList(),
        'resolveMicros': captures.map((Capture c) => c.timings.resolve.inMicroseconds).toList(),
        'restoreMicros': captures.map((Capture c) => c.timings.restore.inMicroseconds).toList(),
      });

      for (final Mutation m in screen.mutations) {
        final Capture mutant = await captureFixture(tester, screen, screen.knobs.override(m.changes), assets);
        countKinds(mutant);
        results.add(MutationResult(screen.name, m, base, mutant));
      }

      expect(diffs, 0, reason: 'recording differs across repeats');
      expect(unverified, 0, reason: 'nodes whose paint transform could not be verified');
      final List<MutationResult> mine = results.where((MutationResult r) => r.screen == screen.name).toList();
      expect(
        mine.where((MutationResult r) => r.captureGap).map((MutationResult r) => r.mutation.name),
        isEmpty,
        reason: 'capture gaps',
      );
      expect(
        mine.where((MutationResult r) => r.expectationWrong).map((MutationResult r) => r.mutation.name),
        isEmpty,
        reason: 'fixture pixel expectations',
      );
      expect(
        mine.where((MutationResult r) => r.missed).map((MutationResult r) => r.mutation.name),
        isEmpty,
        reason: 'missed mutations',
      );
    });
  }

  tearDownAll(() {
    final dir = Directory('build/phase0')..createSync(recursive: true);
    final report = <String, Object?>{
      'flutter': Platform.environment['FLUTTER_VERSION'] ?? 'see flutter --version',
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'repeatsPerScreen': repeatsPerScreen,
      'repeatDiffs': repeatDiffs,
      'rootHashes': rootHashes,
      'mutations': results.map((MutationResult r) => r.toJson()).toList(),
      'screens': screenStats,
      'nodeKinds': kinds.map(
        (String k, Map<String, Object?> v) => MapEntry<String, Object?>(k, <String, Object?>{
          'nodes': v['nodes'],
          'opaque': v['opaque'],
          'reasons': (v['reasons']! as Set<String>).toList()..sort(),
        }),
      ),
    };
    File('${dir.path}/report.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    File('${dir.path}/root_hashes.txt').writeAsStringSync(
      (rootHashes.entries.map((MapEntry<String, String> e) => '${e.key} ${e.value}').toList()..sort()).join('\n'),
    );
  });
}

/// The same pump as [captureFixture], with no recording, for the A10 baseline.
Future<void> captureFixtureWithoutRecording(WidgetTester tester, FixtureScreen screen, FixtureAssets assets) =>
    pumpFixture(tester, screen, screen.knobs, assets);
