/// Structured UI snapshots for Flutter widget tests.
///
/// Experimental. See doc/assumption_register.md for the gates passed so far.
library;

export 'src/audit/pixels.dart';
export 'src/recorder/describe.dart' show OpaqueReason;
export 'src/recorder/paint_recorder.dart';
export 'src/snapshot/capture.dart'
    show CaptureFailure, Capture, SnapshotOptions, TokenResolver, captureSnapshot, captureWithDetails;
export 'src/snapshot/components.dart' show ComponentPolicy;
export 'src/snapshot/snapshot.dart';
export 'src/snapshot/toolchain.dart' show SnapshotFonts, touchstoneVersion, toolchainFingerprint;
export 'src/snapshot/expect_snapshot.dart';
export 'src/testing/helpers.dart';
