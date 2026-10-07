// The ground truth for catalogs and generated mutations (spec: Verification
// strategy): the view's pixels and its semantics tree, read independently of
// the snapshot.

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

class Oracle {
  Oracle(this.pixels, this.semantics);

  /// Hash of the whole view's pixels.
  final String pixels;

  /// The semantics tree in traversal order, without node ids or identity
  /// hashes.
  final String semantics;

  Map<String, String> toJson() => <String, String>{'pixels': pixels, 'semantics': semantics};
}

/// Reads the oracle. Semantics must be enabled by the caller.
Future<Oracle> readOracle(WidgetTester tester) async {
  final RenderView view = tester.binding.renderViews.first;
  final PixelRegion region = (await tester.runAsync(() => rasterize(view, Offset.zero & view.size)))!;
  // Compositing for the raster can schedule frames; pump them without time.
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
  final SemanticsNode? root = view.owner!.semanticsOwner?.rootSemanticsNode;
  final String semantics = root == null
      ? '-'
      : root
            .toStringDeep(childOrder: DebugSemanticsDumpOrder.traversalOrder)
            .replaceAll(RegExp(r'SemanticsNode#\d+'), 'SemanticsNode')
            // Object identity hashes differ between runs.
            .replaceAll(RegExp(r'#[0-9a-f]{5}\b'), '#');
  return Oracle(region.hash, semantics);
}
