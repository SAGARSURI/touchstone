// The pixel oracle: rasterize a region of the widget-test view and hash it.
//
// Rasterization goes through the render view's root layer, the same layer tree
// the test binding composites. The root layer applies the device pixel ratio,
// so the region is rasterized at physical resolution.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/rendering.dart';

/// Raw RGBA pixels of a region, at physical resolution.
class PixelRegion {
  PixelRegion(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;

  String get hash => 'px($width x $height:${sha256.convert(rgba)})';

  bool sameAs(PixelRegion other) {
    if (width != other.width || height != other.height || rgba.length != other.rgba.length) {
      return false;
    }
    for (var i = 0; i < rgba.length; i++) {
      if (rgba[i] != other.rgba[i]) {
        return false;
      }
    }
    return true;
  }

  /// The pixels of [logicalRect], where this region holds the whole view at
  /// [devicePixelRatio]. Pixel edges are rounded outwards.
  PixelRegion crop(Rect logicalRect, double devicePixelRatio) {
    final int left = (logicalRect.left * devicePixelRatio).floor().clamp(0, width);
    final int top = (logicalRect.top * devicePixelRatio).floor().clamp(0, height);
    final int right = (logicalRect.right * devicePixelRatio).ceil().clamp(left, width);
    final int bottom = (logicalRect.bottom * devicePixelRatio).ceil().clamp(top, height);
    final int w = right - left;
    final int h = bottom - top;
    final out = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      final int from = ((top + y) * width + left) * 4;
      out.setRange(y * w * 4, (y + 1) * w * 4, rgba, from);
    }
    return PixelRegion(w, h, out);
  }

  /// Number of pixels whose RGBA value differs.
  int differingPixels(PixelRegion other) {
    if (width != other.width || height != other.height) {
      return width * height;
    }
    var count = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      if (rgba[i] != other.rgba[i] ||
          rgba[i + 1] != other.rgba[i + 1] ||
          rgba[i + 2] != other.rgba[i + 2] ||
          rgba[i + 3] != other.rgba[i + 3]) {
        count++;
      }
    }
    return count;
  }
}

/// Rasterizes [logicalRect] of [view]. Must run outside the fake async zone of
/// a widget test, for example inside `tester.runAsync`.
Future<PixelRegion> rasterize(RenderView view, Rect logicalRect) async {
  final double dpr = view.flutterView.devicePixelRatio;
  final Rect viewRect = Offset.zero & view.size;
  final Rect clipped = logicalRect.intersect(viewRect);
  if (clipped.isEmpty) {
    return PixelRegion(0, 0, Uint8List(0));
  }
  final layer = view.debugLayer! as OffsetLayer;
  final Rect physical = Rect.fromLTRB(clipped.left * dpr, clipped.top * dpr, clipped.right * dpr, clipped.bottom * dpr);
  final ui.Image image = await layer.toImage(physical);
  try {
    final ByteData? bytes = await image.toByteData();
    return PixelRegion(image.width, image.height, bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
