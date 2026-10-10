// A Canvas that copies every argument by value at call time.
//
// The stock TestRecordingCanvas keeps argument identity, not value, and leaves
// Path, Image and Paragraph as engine handles. This canvas writes each call as
// canonical text immediately, with handles fingerprinted (assumption A2).
//
// It also tracks where each call can change pixels, in global logical
// coordinates: the call's own geometry, widened for stroke and blur, inside the
// clip in effect. A node whose paint cannot be recorded by value is
// pixel-hashed over exactly that reach, so the fallback fails closed.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'canonical.dart' as c;
import 'describe.dart';
import 'fingerprint.dart';

/// Receives the canonical text of each recorded operation.
abstract class OpSink {
  DescribeContext get describeContext;

  void op(String text);

  /// Registers an image whose bytes are fingerprinted after paint, and returns
  /// the placeholder that stands for it in the op text.
  String image(ui.Image image);

  /// Adds a global rect this node's paint can change.
  void reach(Rect globalRect);

  /// Adds a rect, in the node's own coordinates and before any clip, that
  /// its own drawing covers; null when the drawing has no bounds of its own
  /// (it fills or spreads over the whole clip).
  void reachOwn(Rect? local);
}

class _State {
  _State(this.transform, this.clip, this.spreadClip);

  final Matrix4 transform;

  /// Global clip bounds in effect; nothing drawn reaches outside it.
  Rect clip;

  /// Set inside a layer that can move or spread pixels (an image filter): the
  /// clip in effect where that layer was entered. Anything drawn inside may
  /// land anywhere within it.
  Rect? spreadClip;

  _State copy() => _State(transform.clone(), clip, spreadClip);
}

class RecordingCanvas implements Canvas {
  /// [toGlobal] maps this node's origin to global logical coordinates;
  /// [clip] is the global clip in effect when the node starts painting, and
  /// [spreadClip] is set when an ancestor layer can spread pixels.
  ///
  /// When [trackClips] is false the node's transform could not be verified,
  /// so clips never narrow its reach.
  RecordingCanvas(this._sink, this._toGlobal, Rect clip, {Rect? spreadClip, this.trackClips = true}) {
    _states.add(_State(Matrix4.identity(), clip, spreadClip));
  }

  final OpSink _sink;
  final Matrix4 _toGlobal;
  final bool trackClips;
  final List<_State> _states = <_State>[];

  DescribeContext get _ctx => _sink.describeContext;

  String _p(Paint paint) => describePaint(paint, _ctx);

  void _op(String name, [List<Object?> fields = const <Object?>[]]) => _sink.op(c.rec(name, fields));

  _State get _top => _states.last;
  Matrix4 get _m => _top.transform;

  /// The global clip currently in effect.
  Rect get currentClip => _top.clip;

  /// See [_State.spreadClip].
  Rect? get spreadClip => _top.spreadClip;

  /// Maps a rect in the current canvas coordinates to global coordinates.
  Rect toGlobal(Rect local) => MatrixUtils.transformRect(_toGlobal.multiplied(_m), local);

  /// The transform from a child painted at [offset] to global coordinates.
  Matrix4 childTransform(Offset offset) =>
      _toGlobal.multiplied(_m)..multiply(Matrix4.translationValues(offset.dx, offset.dy, 0));

  /// Records that pixels anywhere inside the current clip may change.
  void reachClip() {
    _sink
      ..reach(_top.spreadClip ?? currentClip)
      ..reachOwn(null);
  }

  /// Records that pixels inside [local], in current canvas coordinates, may
  /// change.
  void reachLocal(Rect local) {
    if (_top.spreadClip != null) {
      reachClip();
      return;
    }
    _sink
      ..reach(toGlobal(local).intersect(currentClip))
      ..reachOwn(MatrixUtils.transformRect(_m, local));
  }

  /// Records that pixels inside [local], widened for [paint], may change. A
  /// shader only colours the geometry it fills; an image filter can move or
  /// spread it anywhere inside the clip.
  void _drew(Rect local, [Paint? paint]) {
    if (paint != null && paint.imageFilter != null) {
      reachClip();
      return;
    }
    reachLocal(local.inflate(_widen(paint)));
  }

  /// Logical pixels a paint can reach beyond its geometry: half the stroke
  /// (times the miter limit for mitred joins), blur, and one pixel of
  /// antialiasing.
  static double _widen(Paint? paint) {
    if (paint == null) {
      return 1;
    }
    var w = 1.0;
    if (paint.style == PaintingStyle.stroke) {
      final double half = paint.strokeWidth == 0 ? 1 : paint.strokeWidth / 2;
      w += paint.strokeJoin == StrokeJoin.miter
          ? half * (paint.strokeMiterLimit < 1 ? 1 : paint.strokeMiterLimit)
          : half;
      w += paint.strokeCap == StrokeCap.butt ? 0 : half;
    }
    final MaskFilter? mask = paint.maskFilter;
    if (mask != null) {
      // toString prints sigma to one decimal; widen past the rounding.
      final Match? m = RegExp(r', (-?[\d.]+)\)$').firstMatch(mask.toString());
      final double sigma = m == null ? 100 : double.parse(m.group(1)!) + 0.1;
      w += 3 * sigma;
    }
    return w;
  }

  /// Pushes canvas state for a context-level transform, clip or spreading
  /// layer. Not recorded: the context records the push itself.
  void pushState({Matrix4? transform, Rect? localClip, bool spread = false}) {
    final _State next = _top.copy();
    if (spread) {
      next.spreadClip ??= next.clip;
    }
    if (transform != null) {
      next.transform.multiply(transform);
    }
    _states.add(next);
    if (localClip != null) {
      _clip(localClip);
    }
  }

  void popState() {
    if (_states.length > 1) {
      _states.removeLast();
    }
  }

  void _clip(Rect local) {
    if (trackClips) {
      _top.clip = _top.clip.intersect(toGlobal(local));
    }
  }

  @override
  void save() {
    _states.add(_top.copy());
    _op('save');
  }

  @override
  void saveLayer(Rect? bounds, Paint paint) {
    final _State next = _top.copy();
    if (paint.imageFilter != null) {
      // A filtered layer can move or spread its content anywhere inside the
      // clip, and a filter that affects transparent pixels fills it.
      reachClip();
      next.spreadClip ??= next.clip;
    } else if (paint.colorFilter != null || paint.blendMode != BlendMode.srcOver) {
      // The layer is composited over its whole bounds: a colour filter can
      // turn its transparent pixels opaque, and a blend mode such as srcIn
      // changes the destination where the layer is empty.
      if (bounds == null) {
        reachClip();
      } else {
        reachLocal(bounds);
      }
    }
    _states.add(next);
    _op('saveLayer', <Object?>[if (bounds == null) null else c.rect(bounds), _p(paint)]);
  }

  @override
  void restore() {
    popState();
    _op('restore');
  }

  @override
  void restoreToCount(int count) {
    while (_states.length > count && _states.length > 1) {
      _states.removeLast();
    }
    _op('restoreToCount', <Object?>[count]);
  }

  @override
  int getSaveCount() => _states.length;

  @override
  void translate(double dx, double dy) {
    _m.translateByDouble(dx, dy, 0, 1);
    _op('translate', <Object?>[dx, dy]);
  }

  @override
  void scale(double sx, [double? sy]) {
    _m.scaleByDouble(sx, sy ?? sx, 1, 1);
    _op('scale', <Object?>[sx, sy]);
  }

  @override
  void rotate(double radians) {
    _m.rotateZ(radians);
    _op('rotate', <Object?>[radians]);
  }

  @override
  void skew(double sx, double sy) {
    _m.multiply(Matrix4.skew(sx, sy));
    _op('skew', <Object?>[sx, sy]);
  }

  @override
  void transform(Float64List matrix4) {
    _m.multiply(Matrix4.fromFloat64List(matrix4));
    _op('transform', <Object?>[c.float64s(matrix4)]);
  }

  @override
  Float64List getTransform() => Float64List.fromList(_m.storage);

  @override
  void clipRect(Rect rect, {ui.ClipOp clipOp = ui.ClipOp.intersect, bool doAntiAlias = true}) {
    if (clipOp == ui.ClipOp.intersect) {
      _clip(rect);
    }
    _op('clipRect', <Object?>[c.rect(rect), clipOp, doAntiAlias]);
  }

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) {
    _clip(rrect.outerRect);
    _op('clipRRect', <Object?>[c.rrect(rrect), doAntiAlias]);
  }

  @override
  void clipRSuperellipse(RSuperellipse rsuperellipse, {bool doAntiAlias = true}) {
    _clip(rsuperellipse.outerRect);
    _op('clipRSE', <Object?>[c.rsuperellipse(rsuperellipse), doAntiAlias]);
  }

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) {
    // The clip's edge decides which pixels of later draws show, and a path's
    // fingerprint is lossy, so the clipped area is pixel-hashed.
    _ctx.markOpaque(OpaqueReason.path, 'clipPath');
    _drew(path.getBounds());
    _clip(path.getBounds());
    _op('clipPath', <Object?>[fingerprintPath(path), doAntiAlias]);
  }

  // Culling decisions must not depend on where the node sits, so painters that
  // ask see an unbounded clip and record everything they would draw.
  @override
  Rect getLocalClipBounds() => Rect.largest;

  @override
  Rect getDestinationClipBounds() => Rect.largest;

  @override
  void drawColor(Color color, BlendMode blendMode) {
    reachClip();
    _op('drawColor', <Object?>[c.color(color), blendMode]);
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    _drew(Rect.fromPoints(p1, p2), paint);
    _op('drawLine', <Object?>[c.offset(p1), c.offset(p2), _p(paint)]);
  }

  @override
  void drawPaint(Paint paint) {
    reachClip();
    _op('drawPaint', <Object?>[_p(paint)]);
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    _drew(rect, paint);
    _op('drawRect', <Object?>[c.rect(rect), _p(paint)]);
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
    _drew(rrect.outerRect, paint);
    _op('drawRRect', <Object?>[c.rrect(rrect), _p(paint)]);
  }

  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) {
    _drew(outer.outerRect, paint);
    _op('drawDRRect', <Object?>[c.rrect(outer), c.rrect(inner), _p(paint)]);
  }

  @override
  void drawRSuperellipse(RSuperellipse rsuperellipse, Paint paint) {
    _drew(rsuperellipse.outerRect, paint);
    _op('drawRSE', <Object?>[c.rsuperellipse(rsuperellipse), _p(paint)]);
  }

  @override
  void drawOval(Rect rect, Paint paint) {
    _drew(rect, paint);
    _op('drawOval', <Object?>[c.rect(rect), _p(paint)]);
  }

  @override
  void drawCircle(Offset center, double radius, Paint paint) {
    _drew(Rect.fromCircle(center: center, radius: radius), paint);
    _op('drawCircle', <Object?>[c.offset(center), radius, _p(paint)]);
  }

  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter, Paint paint) {
    _drew(rect, paint);
    _op('drawArc', <Object?>[c.rect(rect), startAngle, sweepAngle, useCenter, _p(paint)]);
  }

  @override
  void drawPath(Path path, Paint paint) {
    // A2 failed for paths: two different paths can share bounds, length and
    // every sampled tangent, and zero-length contours are not sampled at all.
    // Spec fallback: pixel hash for nodes that draw paths.
    _ctx.markOpaque(OpaqueReason.path, 'drawPath');
    _drew(path.getBounds(), paint);
    _op('drawPath', <Object?>[fingerprintPath(path), _p(paint)]);
  }

  @override
  void drawImage(ui.Image image, Offset offset, Paint paint) {
    _drew(offset & Size(image.width.toDouble(), image.height.toDouble()), paint);
    _op('drawImage', <Object?>[_sink.image(image), c.offset(offset), _p(paint)]);
  }

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {
    _drew(dst, paint);
    _op('drawImageRect', <Object?>[_sink.image(image), c.rect(src), c.rect(dst), _p(paint)]);
  }

  @override
  void drawImageNine(ui.Image image, Rect center, Rect dst, Paint paint) {
    _drew(dst, paint);
    _op('drawImageNine', <Object?>[_sink.image(image), c.rect(center), c.rect(dst), _p(paint)]);
  }

  @override
  void drawPicture(ui.Picture picture) {
    _ctx.markOpaque(OpaqueReason.picture, 'drawPicture');
    reachClip();
    _op('drawPicture?');
  }

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    // Glyph ink can overhang the line boxes (italics, ellipses, decorations),
    // so the reach is widened by half the paragraph's height.
    final double width = paragraph.width.isFinite ? paragraph.width : paragraph.maxIntrinsicWidth;
    final Rect box = offset & Size(width < paragraph.longestLine ? paragraph.longestLine : width, paragraph.height);
    _drew(box.inflate(paragraph.height / 2 + 2));
    _op('drawParagraph', <Object?>[fingerprintParagraph(paragraph, _ctx), c.offset(offset)]);
  }

  @override
  void drawPoints(ui.PointMode pointMode, List<Offset> points, Paint paint) {
    if (points.isNotEmpty) {
      _drew(
        points
            .skip(1)
            .fold(
              Rect.fromPoints(points.first, points.first),
              (Rect r, Offset p) => r.expandToInclude(Rect.fromPoints(p, p)),
            ),
        paint,
      );
    }
    _op('drawPoints', <Object?>[pointMode, c.points(points), _p(paint)]);
  }

  @override
  void drawRawPoints(ui.PointMode pointMode, Float32List points, Paint paint) {
    final pts = <Offset>[for (var i = 0; i + 1 < points.length; i += 2) Offset(points[i], points[i + 1])];
    if (pts.isNotEmpty) {
      _drew(
        pts
            .skip(1)
            .fold(
              Rect.fromPoints(pts.first, pts.first),
              (Rect r, Offset p) => r.expandToInclude(Rect.fromPoints(p, p)),
            ),
        paint,
      );
    }
    _op('drawRawPoints', <Object?>[pointMode, c.float32s(points), _p(paint)]);
  }

  @override
  void drawVertices(ui.Vertices vertices, BlendMode blendMode, Paint paint) {
    _ctx.markOpaque(OpaqueReason.vertices, 'drawVertices');
    reachClip();
    _op('drawVertices?', <Object?>[blendMode, _p(paint)]);
  }

  @override
  void drawAtlas(
    ui.Image atlas,
    List<RSTransform> transforms,
    List<Rect> rects,
    List<Color>? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) {
    if (cullRect == null) {
      reachClip();
    } else {
      _drew(cullRect, paint);
    }
    _op('drawAtlas', <Object?>[
      _sink.image(atlas),
      transforms.map((RSTransform t) => '${c.d(t.scos)},${c.d(t.ssin)},${c.d(t.tx)},${c.d(t.ty)}').join('|'),
      rects.map(c.rect).join(''),
      colors == null ? null : c.colors(colors),
      blendMode,
      if (cullRect == null) null else c.rect(cullRect),
      _p(paint),
    ]);
  }

  @override
  void drawRawAtlas(
    ui.Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) {
    if (cullRect == null) {
      reachClip();
    } else {
      _drew(cullRect, paint);
    }
    _op('drawRawAtlas', <Object?>[
      _sink.image(atlas),
      c.float32s(rstTransforms),
      c.float32s(rects),
      colors == null ? null : c.int32s(colors),
      blendMode,
      if (cullRect == null) null else c.rect(cullRect),
      _p(paint),
    ]);
  }

  @override
  void drawShadow(Path path, Color color, double elevation, bool transparentOccluder) {
    _ctx.markOpaque(OpaqueReason.path, 'drawShadow');
    // A shadow's spread depends on the light position, so it may reach
    // anywhere inside the clip.
    reachClip();
    _op('drawShadow', <Object?>[fingerprintPath(path), c.color(color), elevation, transparentOccluder]);
  }
}
