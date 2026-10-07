// Test helpers for deterministic captures (spec: Determinism controls; A13).
//
// Animations settle or are captured at an explicitly pumped time, images are
// decoded before capture, the clock is fixed, and random values are seeded.

import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../snapshot/capture.dart';

final Object _fixedClockKey = Object();

/// Runs [body] with `clock.now()` (package:clock) fixed at [time]. App code
/// that reads time through package:clock then renders the same in every run.
Future<T> withFixedClock<T>(DateTime time, Future<T> Function() body) =>
    withClock(Clock.fixed(time), () => runZoned(body, zoneValues: <Object, Object>{_fixedClockKey: true}));

/// Whether the current zone has a clock fixed by [withFixedClock].
bool get clockIsFixed => Zone.current[_fixedClockKey] == true;

/// Runs [body] with a clock that records every read of package:clock time.
/// Returns where each read happened, so a capture can name it.
Future<List<StackTrace>> recordClockReads(Future<void> Function() body) async {
  final reads = <StackTrace>[];
  final Clock outer = clock;
  await withClock(
    Clock(() {
      reads.add(StackTrace.current);
      return outer.now();
    }),
    body,
  );
  return reads;
}

/// Pumps until no frame is scheduled. Fails the capture, naming the cause,
/// if an animation never settles within [timeout] of fake time.
Future<void> settle(WidgetTester tester, {Duration timeout = const Duration(minutes: 10)}) async {
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, timeout);
  } on FlutterError catch (e) {
    throw CaptureFailure(
      'the tree never settles: an animation, ticker or periodic timer keeps scheduling frames ($e). '
      'Capture at an explicit time with tester.pump(duration) instead, or stop the animation in the test.',
    );
  }
}

/// Decodes [images] so they are painted on the next frame, then pumps it.
Future<void> precacheImages(WidgetTester tester, Iterable<ImageProvider> images) async {
  final BuildContext context = tester.binding.rootElement!;
  await tester.runAsync(() async {
    for (final image in images) {
      await precacheImage(image, context);
    }
  });
  await tester.pump();
}

/// A seeded random source for test data. Pass it to the code under test
/// instead of `Random()`.
Random seededRandom([int seed = 0]) => Random(seed);
