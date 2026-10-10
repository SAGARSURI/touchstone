// Paints one render object's own drawing, without its children, onto a real
// canvas, for the pixel hash of an opaque node.
//
// Hashing the composited view over the node's reach also hashed whatever
// other components drew there: the children inside a clip path, a card
// painted over a map. A change in any of them changed this node's hash too,
// and the diff reported it here as unexplained paint. Painted alone, the node
// is hashed on exactly what it draws:
//
// - its own canvas calls, under its own transforms, clips and layer effects;
// - a clip path as the filled path, since the clip's edge is what the node
//   adds to its children's pixels;
// - a shader mask as the shader over its mask rect;
// - a platform view or texture as nothing, since neither has pixels in a
//   widget test (their rects are in the op text).
//
// Children are skipped: each is recorded, and hashed, on its own. A layer it
// cannot reproduce (an unknown layer type) makes [IsolatedPaint.record] give
// up, and the caller falls back to the composited view.

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

class IsolatedPaint {
  /// [ro]'s own drawing at its own origin, or null when a layer it pushes
  /// cannot be reproduced on a canvas.
  static ui.Picture? record(RenderObject ro) {
    final recorder = ui.PictureRecorder();
    final context = _IsolatedContext(ui.Canvas(recorder), ro);
    ro.paint(context, Offset.zero);
    final ui.Picture picture = recorder.endRecording();
    if (context.unsupported) {
      picture.dispose();
      return null;
    }
    return picture;
  }
}

class _IsolatedContext extends ClipContext implements PaintingContext {
  _IsolatedContext(this.canvas, this._owner);

  @override
  final Canvas canvas;

  final RenderObject _owner;

  bool unsupported = false;

  @override
  Rect get estimatedBounds => Rect.largest;

  @override
  void paintChild(RenderObject child, Offset offset) {}

  @override
  ClipRectLayer? pushClipRect(
    bool needsCompositing,
    Offset offset,
    Rect clipRect,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.hardEdge,
    ClipRectLayer? oldLayer,
  }) {
    final Rect rect = clipRect.shift(offset);
    clipRectAndPaint(rect, clipBehavior, rect, () => painter(this, offset));
    return oldLayer;
  }

  @override
  ClipRRectLayer? pushClipRRect(
    bool needsCompositing,
    Offset offset,
    Rect bounds,
    RRect clipRRect,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.antiAlias,
    ClipRRectLayer? oldLayer,
  }) {
    clipRRectAndPaint(clipRRect.shift(offset), clipBehavior, bounds.shift(offset), () => painter(this, offset));
    return oldLayer;
  }

  @override
  ClipRSuperellipseLayer? pushClipRSuperellipse(
    bool needsCompositing,
    Offset offset,
    Rect bounds,
    RSuperellipse clipRSuperellipse,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.antiAlias,
    ClipRSuperellipseLayer? oldLayer,
  }) {
    clipRSuperellipseAndPaint(
      clipRSuperellipse.shift(offset),
      clipBehavior,
      bounds.shift(offset),
      () => painter(this, offset),
    );
    return oldLayer;
  }

  @override
  ClipPathLayer? pushClipPath(
    bool needsCompositing,
    Offset offset,
    Rect bounds,
    Path clipPath,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.antiAlias,
    ClipPathLayer? oldLayer,
  }) {
    final Path shifted = clipPath.shift(offset);
    _mask(shifted, clipBehavior);
    clipPathAndPaint(shifted, clipBehavior, bounds.shift(offset), () => painter(this, offset));
    return oldLayer;
  }

  /// Draws a clip path's area, so a change in its edge changes the pixels.
  void _mask(Path path, Clip clipBehavior) {
    if (clipBehavior == Clip.none) {
      return;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF000000)
        ..isAntiAlias = clipBehavior != Clip.hardEdge,
    );
  }

  @override
  ColorFilterLayer pushColorFilter(
    Offset offset,
    ColorFilter colorFilter,
    PaintingContextCallback painter, {
    ColorFilterLayer? oldLayer,
  }) {
    canvas.saveLayer(null, Paint()..colorFilter = colorFilter);
    painter(this, offset);
    canvas.restore();
    return oldLayer ?? ColorFilterLayer();
  }

  @override
  TransformLayer? pushTransform(
    bool needsCompositing,
    Offset offset,
    Matrix4 transform,
    PaintingContextCallback painter, {
    TransformLayer? oldLayer,
  }) {
    final Matrix4 effective = Matrix4.translationValues(offset.dx, offset.dy, 0)
      ..multiply(transform)
      ..translateByDouble(-offset.dx, -offset.dy, 0, 1);
    canvas
      ..save()
      ..transform(effective.storage);
    painter(this, offset);
    canvas.restore();
    return oldLayer;
  }

  @override
  OpacityLayer pushOpacity(Offset offset, int alpha, PaintingContextCallback painter, {OpacityLayer? oldLayer}) {
    canvas
      ..saveLayer(null, Paint()..color = Color.fromARGB(alpha, 0, 0, 0))
      ..translate(offset.dx, offset.dy);
    painter(this, Offset.zero);
    canvas.restore();
    return oldLayer ?? OpacityLayer();
  }

  @override
  void pushLayer(ContainerLayer childLayer, PaintingContextCallback painter, Offset offset, {Rect? childPaintBounds}) {
    var saved = 1;
    canvas.save();
    switch (childLayer) {
      case TransformLayer(:final Offset offset, :final Matrix4? transform):
        canvas.translate(offset.dx, offset.dy);
        if (transform != null) {
          canvas.transform(transform.storage);
        }
      case OpacityLayer(:final int? alpha, :final Offset offset):
        canvas
          ..translate(offset.dx, offset.dy)
          ..saveLayer(null, Paint()..color = Color.fromARGB(alpha ?? 255, 0, 0, 0));
        saved++;
      case ImageFilterLayer(:final ui.ImageFilter? imageFilter, :final Offset offset):
        canvas
          ..translate(offset.dx, offset.dy)
          ..saveLayer(null, Paint()..imageFilter = imageFilter);
        saved++;
      case OffsetLayer(:final Offset offset) || LeaderLayer(:final Offset offset):
        canvas.translate(offset.dx, offset.dy);
      case FollowerLayer():
        final RenderObject owner = _owner;
        if (owner is! RenderFollowerLayer) {
          unsupported = true;
        } else {
          canvas.transform(owner.getCurrentTransform().storage);
        }
      case ColorFilterLayer(:final ColorFilter? colorFilter):
        canvas.saveLayer(null, Paint()..colorFilter = colorFilter);
        saved++;
      case ClipRectLayer(:final Rect? clipRect, :final Clip clipBehavior):
        if (clipRect != null && clipBehavior != Clip.none) {
          canvas.clipRect(clipRect, doAntiAlias: clipBehavior != Clip.hardEdge);
        }
      case ClipRRectLayer(:final RRect? clipRRect, :final Clip clipBehavior):
        if (clipRRect != null && clipBehavior != Clip.none) {
          canvas.clipRRect(clipRRect, doAntiAlias: clipBehavior != Clip.hardEdge);
        }
      case ClipRSuperellipseLayer(:final RSuperellipse? clipRSuperellipse, :final Clip clipBehavior):
        if (clipRSuperellipse != null && clipBehavior != Clip.none) {
          canvas.clipRSuperellipse(clipRSuperellipse, doAntiAlias: clipBehavior != Clip.hardEdge);
        }
      case ClipPathLayer(:final Path? clipPath, :final Clip clipBehavior):
        if (clipPath != null && clipBehavior != Clip.none) {
          _mask(clipPath, clipBehavior);
          canvas.clipPath(clipPath, doAntiAlias: clipBehavior != Clip.hardEdge);
        }
      case ShaderMaskLayer(:final Shader? shader, :final Rect? maskRect):
        if (shader != null && maskRect != null) {
          canvas.drawRect(maskRect, Paint()..shader = shader);
        }
      case BackdropFilterLayer() || AnnotatedRegionLayer<Object>():
        // A backdrop filter changes what is under it, not what this node
        // draws; an annotation carries no pixels.
        break;
      default:
        unsupported = true;
    }
    painter(this, offset);
    for (var i = 0; i < saved; i++) {
      canvas.restore();
    }
  }

  @override
  void addLayer(Layer layer) {
    if (layer is! PlatformViewLayer && layer is! TextureLayer) {
      unsupported = true;
    }
  }

  @override
  void appendLayer(Layer layer) => addLayer(layer);

  @override
  PaintingContext createChildContext(ContainerLayer childLayer, Rect bounds) => this;

  @override
  void stopRecordingIfNeeded() {}

  @override
  void setIsComplexHint() {}

  @override
  void setWillChangeHint() {}

  @override
  VoidCallback addCompositionCallback(CompositionCallback callback) => () {};

  @override
  ui.PictureRecorder get recorder => throw UnsupportedError('No picture recorder while painting one node alone.');
}
