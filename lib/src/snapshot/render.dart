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
import '../diff/changes.dart';
import '../review/crops.dart';
import '../review/png.dart';

/// Overrides TOUCHSTONE_RENDER_DIR, for tests of render mode.
@visibleForTesting
String? debugRenderDirectory;

/// Overrides TOUCHSTONE_RENDER_IDS, for tests of render mode.
@visibleForTesting
Set<String>? debugRenderIds;

/// The directory render mode writes to, or null when it is off.
String? get renderDirectory => debugRenderDirectory ?? Platform.environment['TOUCHSTONE_RENDER_DIR'];

/// The snapshots to render, by [renderKey], or null for all of them.
Set<String>? get renderIds {
  if (debugRenderIds != null) {
    return debugRenderIds;
  }
  final String? ids = Platform.environment['TOUCHSTONE_RENDER_IDS'];
  return ids?.split(',').where((String s) => s.isNotEmpty).toSet();
}

/// The view's pixels now, with its device pixel ratio.
Future<Render> renderView(WidgetTester tester) async {
  final RenderView view = tester.binding.renderViews.first;
  final double dpr = view.flutterView.devicePixelRatio;
  final PixelRegion region = (await tester.runAsync(() => rasterize(view, Offset.zero & view.size)))!;
  // Compositing runs composition callbacks; pump the frames they schedule,
  // without advancing time, as capture does.
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
  return Render(Rgba(region.width, region.height, region.rgba), dpr);
}

/// A snapshot's name in render mode: its [baseline] file relative to the
/// working directory (the package the tests run in), without `.snapshot`.
/// Ids alone may repeat between test directories; baseline files do not.
String renderKey(File baseline) {
  final String path = _shown(baseline.path);
  return path.endsWith('.snapshot') ? path.substring(0, path.length - '.snapshot'.length) : path;
}

/// Writes the view's pixels to `<dir>/<key>.png`, with its device pixel
/// ratio in `<dir>/<key>.json`, when [key] is one of [renderIds].
Future<void> renderForReview(WidgetTester tester, String key, String dir) async {
  final Set<String>? keys = renderIds;
  if (keys != null && !keys.contains(key)) {
    return;
  }
  await tester.pump();
  final Render render = await renderView(tester);
  final png = File('$dir/$key.png');
  png.parent.createSync(recursive: true);
  png.writeAsBytesSync(encodePng(render.image));
  File('$dir/$key.json').writeAsStringSync(jsonEncode(<String, Object>{'dpr': render.dpr}));
}

/// For a failing snapshot (an amendment to the spec's "A test fails", agreed
/// on 2026-10-10): writes the after crop of each changed component, from the
/// view as it is now, to `<failures>/<id>/`, and returns the lines that list
/// them for the failure message. The baseline keeps no pixels, so there is
/// no before crop here; `dart run touchstone:update --images` renders one.
Future<String> writeFailureCrops(WidgetTester tester, ChangeReport report, Directory failures) async {
  if (report.kind != ReportKind.diff || report.items.isEmpty) {
    return '';
  }
  final dir = Directory('${failures.path}/${report.snapshotId}');
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
  final List<ItemCrops> crops = writeCrops(report, null, await renderView(tester), failures.path);
  final files = <String>[];
  for (final ItemCrops c in crops) {
    if (c.after == null || c.sameAs != null) {
      continue;
    }
    final List<int> items = <int>[
      for (final ItemCrops o in crops)
        if (o == c || o.sameAs == c.number) o.number,
    ];
    files.add('${_shown('${failures.path}/${c.after}')} (item${items.length > 1 ? 's' : ''} ${items.join(', ')})');
  }
  if (files.isEmpty) {
    return '';
  }
  return '\nThe changed components as they render now:\n'
      '${files.map((String f) => '  $f\n').join()}'
      'For before and diff images too, record it with dart run touchstone:update --images.';
}

/// [path] relative to the working directory when it is under it.
String _shown(String path) {
  final String here = Directory.current.absolute.path;
  final String abs = File(path).absolute.path;
  return abs.startsWith('$here/') ? abs.substring(here.length + 1) : abs;
}
