/// The diff engine, policy and report, without Flutter: usable from the
/// Dart VM, as the review command does.
library;

export 'src/diff/changes.dart';
export 'src/diff/diff.dart' show Bounds, DiffNode, diffSnapshots, dynamicInputKey;
export 'src/diff/policy.dart';
export 'src/diff/report.dart';
export 'src/snapshot/snapshot.dart';
