// Phase 0 harness: pump a fixture screen, record its paint, and rasterize it
// for the pixel oracle.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fixture_app/screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

/// Logical viewport for every fixture capture.
const Size fixtureViewport = Size(390, 844);
const double fixtureDevicePixelRatio = 3.0;

class Capture {
  Capture(this.recording, this.pixels, this.byKey, this.timings);

  final PaintRecording recording;
  final PixelRegion pixels;

  /// The recorded node of each tagged widget's first render object.
  final Map<String, RecordedNode> byKey;
  final CaptureTimings timings;

  String get rootHash => recording.root.subtreeHash;

  /// Everything the recording holds by value: every node's ops except the
  /// pixel hashes of opaque nodes, and every child placement. A mutation that
  /// changes [rootHash] but not this was caught only by the pixel fallback.
  String get valueText => recording.nodes
      .map(
        (RecordedNode n) =>
            '${n.index} ${n.renderObject.runtimeType} '
            '${n.ops.where((String op) => !op.startsWith('pixels(')).join('|')} '
            '${n.childOffsets.join(',')}',
      )
      .join('\n');

  /// Own paint hashes of every node in the tagged subtree, sorted.
  List<String> paintHashesUnder(String key) {
    final RecordedNode? node = byKey[key];
    if (node == null) {
      return const <String>[];
    }
    final out = <String>[];
    void visit(RecordedNode n) {
      out.add(n.paintHash);
      n.children.forEach(visit);
    }

    visit(node);
    return out..sort();
  }
}

class CaptureTimings {
  CaptureTimings({
    required this.pump,
    required this.raster,
    required this.record,
    required this.resolve,
    required this.restore,
  });

  final Duration pump;

  /// One full-view rasterization: the pixel oracle, and the source of
  /// opaque-node pixel hashes.
  final Duration raster;
  final Duration record;
  final Duration resolve;

  /// Marking recorded nodes for repaint and pumping the frame that restores
  /// the layers recording touched.
  final Duration restore;
}

Future<FixtureAssets> makeAssets(WidgetTester tester) async {
  Future<Uint8List> png(bool variant) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 12; x++) {
        canvas.drawRect(
          Rect.fromLTWH(x * 4.0, y * 4.0, 4, 4),
          Paint()..color = Color.fromARGB(255, x * 20, y * 30, (x + y) * 10),
        );
      }
    }
    if (variant) {
      canvas.drawRect(const Rect.fromLTWH(20, 12, 1, 1), Paint()..color = const Color(0xFFFFFFFF));
    }
    final ui.Image image = await recorder.endRecording().toImage(48, 32);
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  return (await tester.runAsync(
    () async => FixtureAssets(
      imageA: await png(false),
      imageB: await png(true),
      program: await ui.FragmentProgram.fromAsset('shaders/tint.frag'),
    ),
  ))!;
}

Future<Capture> captureFixture(
  WidgetTester tester,
  FixtureScreen screen,
  Knobs knobs,
  FixtureAssets assets, {
  bool withPixels = true,
}) async {
  final pumpWatch = Stopwatch()..start();
  await pumpFixture(tester, screen, knobs, assets);
  pumpWatch.stop();

  final RenderView view = tester.binding.renderViews.first;
  final double dpr = view.flutterView.devicePixelRatio;
  // The pixel oracle and opaque-node pixel hashes come from one rasterization
  // taken before recording, while the layer tree is exactly what the frame
  // composited.
  final rasterWatch = Stopwatch()..start();
  final PixelRegion full = (await tester.runAsync(() => rasterize(view, Offset.zero & view.size)))!;
  rasterWatch.stop();

  final recordWatch = Stopwatch()..start();
  final PaintRecording recording = PaintRecorder.record(view);
  recordWatch.stop();

  final Map<RenderObject, RecordedNode> byObject = <RenderObject, RecordedNode>{
    for (final RecordedNode n in recording.nodes) n.renderObject: n,
  };
  final byKey = <String, RecordedNode>{};
  for (final Element e in find.byWidgetPredicate((Widget w) => w.key is ValueKey<String>).evaluate()) {
    final String key = (e.widget.key! as ValueKey<String>).value;
    final RenderObject? ro = e.renderObject;
    final RecordedNode? node = ro == null ? null : byObject[ro];
    if (node != null) {
      byKey[key] = node;
    }
  }

  final resolveWatch = Stopwatch()..start();
  await tester.runAsync(() => recording.resolve(pixelHash: (Rect r) async => full.crop(r, dpr).hash));
  resolveWatch.stop();

  final restoreWatch = Stopwatch()..start();
  PaintRecorder.restore(recording);
  await tester.pump();
  restoreWatch.stop();
  expect(tester.binding.hasScheduledFrame, isFalse);
  final PixelRegion pixels = withPixels ? full : PixelRegion(0, 0, Uint8List(0));
  return Capture(
    recording,
    pixels,
    byKey,
    CaptureTimings(
      pump: pumpWatch.elapsed,
      raster: rasterWatch.elapsed,
      record: recordWatch.elapsed,
      resolve: resolveWatch.elapsed,
      restore: restoreWatch.elapsed,
    ),
  );
}

/// Pumps [screen] from an empty tree, decodes its images and settles.
Future<void> pumpFixture(WidgetTester tester, FixtureScreen screen, Knobs knobs, FixtureAssets assets) async {
  tester.view.physicalSize = fixtureViewport * fixtureDevicePixelRatio;
  tester.view.devicePixelRatio = fixtureDevicePixelRatio;

  // Start from an empty tree so no state carries over between captures.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(body: screen.build(knobs, assets))),
  );
  if (screen.usesImages) {
    final BuildContext context = tester.element(find.byType(Scaffold));
    await tester.runAsync(() async {
      await precacheImage(MemoryImage(assets.imageA), context);
      await precacheImage(MemoryImage(assets.imageB), context);
    });
  }
  await tester.pumpAndSettle();
  // Settle: capture only when no frame is scheduled.
  expect(tester.binding.hasScheduledFrame, isFalse, reason: 'a frame is pending at capture');
}
