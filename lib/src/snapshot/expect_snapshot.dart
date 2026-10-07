// expectSnapshot and the determinism gate (spec: Developer experience; Self-
// checks, "Determinism gate").
//
// A baseline is written only after 3 consecutive captures are byte-identical;
// otherwise the first differing node is reported with its likely cause.
// Comparing a capture with its baseline is a root-hash check. The typed
// change report comes with the diff engine (Phase 2).

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../testing/helpers.dart';
import 'capture.dart';
import 'snapshot.dart';

/// Captures needed for a baseline, all byte-identical.
const int determinismCaptures = 3;

/// Re-creates the state being captured between determinism captures.
typedef Rebuild = Future<void> Function(WidgetTester tester);

/// The outcome of the determinism gate.
class DeterminismReport {
  DeterminismReport(this.captures, this.firstDifference);

  /// The canonical text of each capture.
  final List<String> captures;

  /// Null when every capture was identical.
  final SnapshotDifference? firstDifference;

  bool get deterministic => firstDifference == null;
}

/// The first node whose canonical line differs between two captures.
class SnapshotDifference {
  SnapshotDifference(this.nodeId, this.fields, this.cause, this.before, this.after);

  /// Full node id, or the header field that differs.
  final String nodeId;

  /// Detection fields that differ.
  final List<String> fields;

  /// The likely cause, in words.
  final String cause;
  final String before;
  final String after;

  @override
  String toString() =>
      'first differing node: $nodeId (${fields.join(', ')}). Likely cause: $cause\n'
      '  capture 1: ${_clip(before)}\n'
      '  capture 2: ${_clip(after)}';

  static String _clip(String s) => s.length > 400 ? '${s.substring(0, 400)}…' : s;
}

/// Rebuilds every widget, relayouts and repaints everything, then pumps, as a
/// hot reload would. A capture that depends on anything but the tree's
/// declared inputs (the wall clock, random values, call order) changes.
Future<void> rebuildEverything(WidgetTester tester) async {
  final Element root = tester.binding.rootElement!;
  tester.binding.buildOwner!.reassemble(root);
  for (final view in tester.binding.renderViews) {
    view.reassemble();
  }
  await tester.pump();
}

/// Runs the determinism gate: [determinismCaptures] captures of [id] with
/// [rebuild] between them.
Future<DeterminismReport> checkDeterminism(
  WidgetTester tester,
  String id, {
  SnapshotOptions options = const SnapshotOptions(),
  Rebuild rebuild = rebuildEverything,
}) async {
  final captures = <String>[];
  for (var i = 0; i < determinismCaptures; i++) {
    if (i > 0) {
      if (clockIsFixed) {
        await rebuild(tester);
      } else {
        final List<StackTrace> reads = await recordClockReads(() => rebuild(tester));
        if (reads.isNotEmpty) {
          return DeterminismReport(
            captures,
            SnapshotDifference(
              '-',
              const <String>['clock'],
              'the wall clock was read while building (package:clock). Wrap the test body in withFixedClock.',
              _firstAppFrame(reads.first),
              '',
            ),
          );
        }
      }
      if (!options.atPumpedTime && tester.binding.hasScheduledFrame) {
        return DeterminismReport(
          captures,
          SnapshotDifference(
            '-',
            const <String>['frame'],
            'an animation, ticker or timer started again after a rebuild, so the tree never settles',
            '',
            '',
          ),
        );
      }
    }
    captures.add((await captureSnapshot(tester, id, options: options)).toCanonical());
    if (i > 0 && captures[i] != captures[0]) {
      return DeterminismReport(captures, firstDifference(captures[0], captures[i]));
    }
  }
  return DeterminismReport(captures, null);
}

String _firstAppFrame(StackTrace trace) {
  final List<String> lines = trace.toString().split('\n');
  return lines.firstWhere(
    (String l) => !l.contains('package:clock/') && !l.contains('package:touchstone/') && !l.contains('dart:'),
    orElse: () => lines.first,
  );
}

/// The first difference between two canonical snapshot texts.
SnapshotDifference firstDifference(String a, String b) {
  final Snapshot sa = Snapshot.parse(a);
  final Snapshot sb = Snapshot.parse(b);
  for (final String field in <String>['inputs', 'toolchain']) {
    final Map<String, String> fa = field == 'inputs' ? sa.inputs : sa.toolchain;
    final Map<String, String> fb = field == 'inputs' ? sb.inputs : sb.toolchain;
    if (fa.toString() != fb.toString()) {
      return SnapshotDifference(field, <String>[field], 'the $field changed between captures', '$fa', '$fb');
    }
  }
  final List<(String, SnapshotNode)> na = sa.walk().toList();
  final List<(String, SnapshotNode)> nb = sb.walk().toList();
  for (var i = 0; i < na.length && i < nb.length; i++) {
    final (String idA, SnapshotNode x) = na[i];
    final (String idB, SnapshotNode y) = nb[i];
    if (idA != idB) {
      return SnapshotDifference(idA, const <String>['tree'], 'the component tree changed', idA, idB);
    }
    final fields = <String>[
      if (x.bounds != y.bounds) 'bounds',
      if (x.paint != y.paint) 'paint',
      if (x.semantics != y.semantics) 'semantics',
      if (x.opaque != y.opaque) 'opaque',
      if (x.type != y.type) 'type',
      if (x.style != y.style) 'style',
    ];
    if (fields.isNotEmpty) {
      return SnapshotDifference(idA, fields, _cause(fields, x, y), x.line, y.line);
    }
  }
  if (na.length != nb.length) {
    return SnapshotDifference(
      na.length < nb.length ? nb[na.length].$1 : na[nb.length].$1,
      const <String>['tree'],
      'a component appeared or disappeared between captures',
      '${na.length} nodes',
      '${nb.length} nodes',
    );
  }
  return SnapshotDifference('-', const <String>['coverage'], 'the coverage section changed', a, b);
}

String _cause(List<String> fields, SnapshotNode x, SnapshotNode y) {
  if (fields.contains('opaque') || (x.opaque != '-' && fields.contains('paint'))) {
    return 'an opaque node\'s pixels changed: an image still loading, a shader reading time, or a platform view';
  }
  if (fields.contains('bounds')) {
    return 'layout changed between captures: content that depends on the clock, random values or an async load';
  }
  if (fields.contains('paint')) {
    return 'paint changed with the same layout: a colour, text or image that depends on the clock or random values';
  }
  if (fields.contains('semantics')) {
    return 'semantics changed: a label or value that depends on the clock or random values';
  }
  return 'an explanation field changed: a diagnostics property that is not deterministic';
}

/// Where the baseline for [id] lives: `snapshots/<id>.snapshot` beside the
/// test file.
File baselineFile(String id) {
  final GoldenFileComparator comparator = goldenFileComparator;
  final Uri base = comparator is LocalFileComparator ? comparator.basedir : Directory.current.uri;
  return File.fromUri(base.resolve('snapshots/$id.snapshot'));
}

/// Captures [id] and compares it with its baseline. With
/// `flutter test --update-goldens`, or when no baseline exists yet and
/// [recordMissing] is true, the baseline is written after the determinism
/// gate passes.
Future<void> expectSnapshot(
  WidgetTester tester,
  String id, {
  SnapshotOptions options = const SnapshotOptions(),
  Rebuild rebuild = rebuildEverything,
  bool recordMissing = false,
}) async {
  final File file = baselineFile(id);
  final bool exists = file.existsSync();
  if (autoUpdateGoldenFiles || (!exists && recordMissing)) {
    final DeterminismReport report = await checkDeterminism(tester, id, options: options, rebuild: rebuild);
    if (!report.deterministic) {
      fail('Snapshot $id is not deterministic, so no baseline was written.\n${report.firstDifference}');
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(report.captures.first);
    return;
  }
  if (!exists) {
    fail('No baseline for snapshot $id at ${file.path}. Run flutter test --update-goldens to record it.');
  }
  final Snapshot baseline = Snapshot.parse(file.readAsStringSync());
  final Snapshot capture = await captureSnapshot(tester, id, options: options);
  if (baseline.toolchain.toString() != capture.toolchain.toString()) {
    fail(
      'Snapshot $id was recorded with a different toolchain, so it is not compared.\n'
      '  baseline: ${baseline.toolchain}\n  this run: ${capture.toolchain}',
    );
  }
  if (baseline.rootHash != capture.rootHash) {
    final SnapshotDifference d = firstDifference(baseline.toCanonical(), capture.toCanonical());
    fail(
      'Snapshot $id differs from its baseline. First differing node: ${d.nodeId} (${d.fields.join(', ')}).\n'
      '  baseline: ${SnapshotDifference._clip(d.before)}\n  this run: ${SnapshotDifference._clip(d.after)}',
    );
  }
}
