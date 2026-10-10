// Render mode for review crops (spec: Developer experience, Review; Budgets:
// "renders the target branch's version of each changed snapshot once, to
// produce the before crops"). The review command runs the tests with
// TOUCHSTONE_RENDER_DIR set; expectSnapshot then writes the view's pixels
// for the snapshots it names and compares nothing. Crops are for reviewers
// only and never affect a verdict.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../audit/pixels.dart';
import '../review/png.dart';

/// Overrides TOUCHSTONE_RENDER_DIR, for tests of render mode.
@visibleForTesting
String? debugRenderDirectory;

/// Overrides TOUCHSTONE_RENDER_IDS, for tests of render mode.
@visibleForTesting
Set<String>? debugRenderIds;

/// The directory render mode writes to, or null when it is off.
String? get renderDirectory => debugRenderDirectory ?? Platform.environment['TOUCHSTONE_RENDER_DIR'];

/// The snapshot ids to render, or null for all of them.
Set<String>? get renderIds {
  if (debugRenderIds != null) {
    return debugRenderIds;
  }
  final String? ids = Platform.environment['TOUCHSTONE_RENDER_IDS'];
  return ids?.split(',').where((String s) => s.isNotEmpty).toSet();
}

/// Writes the view's pixels for [id] to `<dir>/<id>.png`, with its device
/// pixel ratio in `<dir>/<id>.json`, when [id] is one of [renderIds].
Future<void> renderForReview(WidgetTester tester, String id, String dir) async {
  final Set<String>? ids = renderIds;
  if (ids != null && !ids.contains(id)) {
    return;
  }
  await tester.pump();
  final RenderView view = tester.binding.renderViews.first;
  final double dpr = view.flutterView.devicePixelRatio;
  final PixelRegion region = (await tester.runAsync(() => rasterize(view, Offset.zero & view.size)))!;
  // Compositing runs composition callbacks; pump the frames they schedule,
  // without advancing time, as capture does.
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
  final png = File('$dir/$id.png');
  png.parent.createSync(recursive: true);
  png.writeAsBytesSync(encodePng(Rgba(region.width, region.height, region.rgba)));
  File('$dir/$id.json').writeAsStringSync(jsonEncode(<String, Object>{'dpr': dpr}));
}
