// expectSnapshot and the determinism gate (spec: Developer experience; Self-
// checks, "Determinism gate").
//
// A baseline is written only after 3 consecutive captures are byte-identical;
// otherwise the first differing node is reported with its likely cause.
// Comparing a capture with its baseline is a root-hash check; only a mismatch
// reaches the diff, and the failure message is the change report.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../diff/changes.dart';
import '../diff/diff.dart';
import '../diff/migration_proof.dart';
import '../diff/policy.dart';
import '../diff/report.dart';
import '../testing/helpers.dart';
import 'capture.dart';
import 'components.dart';
import 'difference.dart';
import 'migration.dart';
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
/// gate passes, and the change report against the old baseline is printed.
///
/// A capture that differs from its baseline fails (spec: Verdicts), with the
/// change report as the message. The one difference that passes is content
/// of a component declared in [SnapshotOptions.dynamicComponents].
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
    final String text = report.captures.first;
    final String? old = exists ? file.readAsStringSync() : null;
    if (old == text) {
      return;
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
    final (Snapshot? previous, String? unreadable) = old == null ? (null, null) : _read(utf8.encode(old));
    // ignore: avoid_print
    print(switch (old) {
      null => 'Snapshot $id: new baseline written.',
      _ when previous == null =>
        'Snapshot $id: baseline rewritten. The old one could not be read ($unreadable), '
            'so there is no change report.',
      _ => updateReport(previous, Snapshot.parse(text)),
    });
    return;
  }
  if (!exists) {
    fail('No baseline for snapshot $id at ${file.path}. Run flutter test --update-goldens to record it.');
  }
  final (Snapshot? read, String? unreadable) = _read(file.readAsBytesSync());
  if (read == null) {
    fail(
      'The baseline for snapshot $id at ${file.path} could not be read ($unreadable). '
      'Re-record it with flutter test --update-goldens.',
    );
  }
  final Snapshot baseline = read;
  // The usual case on a pull request is an unchanged snapshot, which needs
  // only the hashes. The explanation fields are described when it differs.
  final Snapshot check = await captureDetectionOnly(tester, id, options: options);
  final bool sameToolchain = baseline.toolchain.toString() == check.toolchain.toString();
  if (baseline.rootHash == check.rootHash && sameToolchain) {
    if (migrationMode == MigrationMode.prove) {
      await writePendingProof(tester, baseline);
    }
    return;
  }
  if (!sameToolchain && migrationMode == MigrationMode.apply) {
    await _migrate(tester, file, baseline, options, rebuild);
    return;
  }
  final Snapshot capture = await captureSnapshot(tester, id, options: options);
  final String? message = compareWithBaseline(baseline, capture);
  if (message != null) {
    fail(message);
  }
}

/// Rewrites [baseline], recorded with another toolchain, after the
/// determinism gate passes, and writes the pixel proof beside it. Whether it
/// passes is decided in review.
Future<void> _migrate(
  WidgetTester tester,
  File file,
  Snapshot baseline,
  SnapshotOptions options,
  Rebuild rebuild,
) async {
  final DeterminismReport report = await checkDeterminism(tester, baseline.id, options: options, rebuild: rebuild);
  if (!report.deterministic) {
    fail('Snapshot ${baseline.id} is not deterministic, so it was not migrated.\n${report.firstDifference}');
  }
  final Snapshot updated = Snapshot.parse(report.captures.first);
  final MigrationProof proof = await completeProof(tester, baseline, updated);
  file.writeAsStringSync(report.captures.first);
  proofFileFor(file).writeAsStringSync(proof.toText());
  // ignore: avoid_print
  print(
    'Snapshot ${baseline.id}: migrated to the new toolchain. '
    '${switch (proof) {
      _ when proof.pixelsIdentical => 'Pixels identical, so review passes it.',
      _ when proof.before.pixels == null => 'No pixels from the old toolchain, so it needs review.',
      _ => 'Pixels differ, so it needs review.',
    }}',
  );
}

/// A committed baseline, or why it could not be parsed: written by an older
/// schema, or edited by hand.
(Snapshot?, String?) _read(Uint8List bytes) {
  try {
    return (Snapshot.parseBytes(bytes), null);
  } on FormatException catch (e) {
    return (null, clipLine(e.message));
  }
}

/// The failure message for [capture] against its [baseline], or null when
/// the only differences are content of declared dynamic components.
String? compareWithBaseline(Snapshot baseline, Snapshot capture) {
  final ChangeReport report = diffSnapshots(baseline, capture);
  switch (report.kind) {
    case ReportKind.equal:
      return null;
    case ReportKind.migration:
      return '${renderReport(report, Decision(Verdict.fail, const <String>[]))}'
          'Re-record it with flutter test --update-goldens on the new toolchain.';
    case ReportKind.diff:
      break;
  }
  if (report.items.isEmpty && report.inputChanges.isEmpty) {
    if (report.skippedContent.isNotEmpty) {
      return null;
    }
    // Bytes differ but no change was typed: report the bytes, never pass.
    final SnapshotDifference d = firstDifference(baseline.toCanonical(), capture.toCanonical());
    return 'Snapshot ${capture.id} differs from its baseline, and the diff named no change. '
        'First differing node: ${d.nodeId} (${d.fields.join(', ')}).\n'
        '  baseline: ${clipLine(d.before)}\n  this run: ${clipLine(d.after)}';
  }
  return '${renderReport(report, Decision(Verdict.fail, const <String>[]))}'
      'The capture differs from its baseline. If the change is intended, run flutter test --update-goldens '
      'to record it.';
}

/// What `--update-goldens` prints for a rewritten baseline: the change report
/// a reviewer will see, with the default policy's verdict.
String updateReport(Snapshot old, Snapshot updated) {
  final ChangeReport report = diffSnapshots(old, updated);
  return renderReport(report, Policy.defaults().decide(report));
}
