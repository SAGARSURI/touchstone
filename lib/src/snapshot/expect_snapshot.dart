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
import 'components.dart';
import 'difference.dart';
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
              await _nodeForTrace(tester, id, options, reads.first),
              const <String>['clock'],
              'the wall clock was read while building (package:clock). Wrap the test body in withFixedClock.',
              _firstAppFrame(reads.first),
              '',
            ),
          );
        }
      }
      if (!options.atPumpedTime && tester.binding.hasScheduledFrame) {
        final SnapshotDifference d = await diagnoseUnsettled(tester, id, options);
        return DeterminismReport(
          captures,
          SnapshotDifference(
            d.nodeId,
            d.fields,
            'it settled before the rebuild but not after: an animation, ticker or timer started again. ${d.cause}',
            d.before,
            d.after,
          ),
        );
      }
    }
    try {
      captures.add((await captureSnapshot(tester, id, options: options)).toCanonical());
    } on CaptureFailure catch (e) {
      return DeterminismReport(
        captures,
        e.difference ?? SnapshotDifference('-', const <String>['capture'], e.message, '', ''),
      );
    }
    if (i > 0 && captures[i] != captures[0]) {
      return DeterminismReport(captures, firstDifference(captures[0], captures[i]));
    }
  }
  return DeterminismReport(captures, null);
}

/// The component whose code is on [trace], found by class name: the first
/// frame whose class is a component's widget class or its State class.
Future<String> _nodeForTrace(WidgetTester tester, String id, SnapshotOptions options, StackTrace trace) async {
  final Capture capture;
  try {
    capture = await captureWithDetails(tester, id, options: options);
  } on CaptureFailure {
    return '-';
  }
  String name(Type t) => t.toString().split('<').first;
  final classes = <(String, String)>[];
  void visit(Component c) {
    final Element? e = c.element;
    if (e != null) {
      classes.add((c.fullId, name(e.widget.runtimeType)));
      if (e is StatefulElement) {
        classes.add((c.fullId, name(e.state.runtimeType)));
      }
    }
    c.children.forEach(visit);
  }

  visit(capture.tree.root);
  for (final String line in '$trace'.split('\n')) {
    for (final (String fullId, String cls) in classes) {
      if (RegExp('(^|[^\\w\$])${RegExp.escape(cls)}\\.').hasMatch(line)) {
        return fullId;
      }
    }
  }
  return '-';
}

String _firstAppFrame(StackTrace trace) {
  final List<String> lines = trace.toString().split('\n');
  return lines.firstWhere(
    (String l) => !l.contains('package:clock/') && !l.contains('package:touchstone/') && !l.contains('dart:'),
    orElse: () => lines.first,
  );
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
      '  baseline: ${clipLine(d.before)}\n  this run: ${clipLine(d.after)}',
    );
  }
}
