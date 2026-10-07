// A Canvas that copies every argument by value at call time.
//
// The stock TestRecordingCanvas keeps argument identity, not value, and leaves
// Path, Image and Paragraph as engine handles. This canvas writes each call as
// canonical text immediately, with handles fingerprinted (assumption A2).

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
}

class RecordingCanvas implements Canvas {
  RecordingCanvas(this._sink);

  final OpSink _sink;
  final List<Matrix4> _transforms = <Matrix4>[Matrix4.identity()];

  DescribeContext get _ctx => _sink.describeContext;

  String _p(Paint paint) => describePaint(paint, _ctx);

  void _op(String name, [List<Object?> fields = const <Object?>[]]) => _sink.op(c.rec(name, fields));

  Matrix4 get _top => _transforms.last;

  @override
  void save() {
    _transforms.add(_top.clone());
    _op('save');
  }

  @override
  void saveLayer(Rect? bounds, Paint paint) {
    _transforms.add(_top.clone());
    _op('saveLayer', <Object?>[if (bounds == null) null else c.rect(bounds), _p(paint)]);
  }

  @override
  void restore() {
    if (_transforms.length > 1) {
      _transforms.removeLast();
    }
    _op('restore');
  }

  @override
  void restoreToCount(int count) {
    while (_transforms.length > count && _transforms.length > 1) {
      _transforms.removeLast();
    }
    _op('restoreToCount', <Object?>[count]);
  }

  @override
  int getSaveCount() => _transforms.length;

  @override
  void translate(double dx, double dy) {
    _top.translateByDouble(dx, dy, 0, 1);
    _op('translate', <Object?>[dx, dy]);
  }

  @override
  void scale(double sx, [double? sy]) {
    _top.scaleByDouble(sx, sy ?? sx, 1, 1);
    _op('scale', <Object?>[sx, sy]);
  }

  @override
  void rotate(double radians) {
    _top.rotateZ(radians);
    _op('rotate', <Object?>[radians]);
  }

  @override
  void skew(double sx, double sy) {
    _top.multiply(Matrix4.skew(sx, sy));
    _op('skew', <Object?>[sx, sy]);
  }

  @override
  void transform(Float64List matrix4) {
    _top.multiply(Matrix4.fromFloat64List(matrix4));
    _op('transform', <Object?>[c.float64s(matrix4)]);
  }

  @override
  Float64List getTransform() => Float64List.fromList(_top.storage);

  @override
  void clipRect(Rect rect, {ui.ClipOp clipOp = ui.ClipOp.intersect, bool doAntiAlias = true}) =>
      _op('clipRect', <Object?>[c.rect(rect), clipOp, doAntiAlias]);

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) => _op('clipRRect', <Object?>[c.rrect(rrect), doAntiAlias]);

  @override
  void clipRSuperellipse(RSuperellipse rsuperellipse, {bool doAntiAlias = true}) =>
      _op('clipRSE', <Object?>[c.rsuperellipse(rsuperellipse), doAntiAlias]);

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) => _op('clipPath', <Object?>[fingerprintPath(path), doAntiAlias]);

  // Culling decisions must not depend on where the node sits, so painters that
  // ask see an unbounded clip and record everything they would draw.
  @override
  Rect getLocalClipBounds() => Rect.largest;

  @override
  Rect getDestinationClipBounds() => Rect.largest;

  @override
  void drawColor(Color color, BlendMode blendMode) => _op('drawColor', <Object?>[c.color(color), blendMode]);

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => _op('drawLine', <Object?>[c.offset(p1), c.offset(p2), _p(paint)]);

  @override
  void drawPaint(Paint paint) => _op('drawPaint', <Object?>[_p(paint)]);

  @override
  void drawRect(Rect rect, Paint paint) => _op('drawRect', <Object?>[c.rect(rect), _p(paint)]);

  @override
  void drawRRect(RRect rrect, Paint paint) => _op('drawRRect', <Object?>[c.rrect(rrect), _p(paint)]);

  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) =>
      _op('drawDRRect', <Object?>[c.rrect(outer), c.rrect(inner), _p(paint)]);

  @override
  void drawRSuperellipse(RSuperellipse rsuperellipse, Paint paint) =>
      _op('drawRSE', <Object?>[c.rsuperellipse(rsuperellipse), _p(paint)]);

  @override
  void drawOval(Rect rect, Paint paint) => _op('drawOval', <Object?>[c.rect(rect), _p(paint)]);

  @override
  void drawCircle(Offset center, double radius, Paint paint) =>
      _op('drawCircle', <Object?>[c.offset(center), radius, _p(paint)]);

  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter, Paint paint) =>
      _op('drawArc', <Object?>[c.rect(rect), startAngle, sweepAngle, useCenter, _p(paint)]);

  @override
  void drawPath(Path path, Paint paint) => _op('drawPath', <Object?>[fingerprintPath(path), _p(paint)]);

  @override
  void drawImage(ui.Image image, Offset offset, Paint paint) =>
      _op('drawImage', <Object?>[_sink.image(image), c.offset(offset), _p(paint)]);

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) =>
      _op('drawImageRect', <Object?>[_sink.image(image), c.rect(src), c.rect(dst), _p(paint)]);

  @override
  void drawImageNine(ui.Image image, Rect center, Rect dst, Paint paint) =>
      _op('drawImageNine', <Object?>[_sink.image(image), c.rect(center), c.rect(dst), _p(paint)]);

  @override
  void drawPicture(ui.Picture picture) {
    _ctx.markOpaque(OpaqueReason.picture, 'drawPicture');
    _op('drawPicture?');
  }

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      _op('drawParagraph', <Object?>[fingerprintParagraph(paragraph, _ctx), c.offset(offset)]);

  @override
  void drawPoints(ui.PointMode pointMode, List<Offset> points, Paint paint) =>
      _op('drawPoints', <Object?>[pointMode, c.points(points), _p(paint)]);

  @override
  void drawRawPoints(ui.PointMode pointMode, Float32List points, Paint paint) =>
      _op('drawRawPoints', <Object?>[pointMode, c.float32s(points), _p(paint)]);

  @override
  void drawVertices(ui.Vertices vertices, BlendMode blendMode, Paint paint) {
    _ctx.markOpaque(OpaqueReason.vertices, 'drawVertices');
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
  ) => _op('drawAtlas', <Object?>[
    _sink.image(atlas),
    transforms.map((RSTransform t) => '${c.d(t.scos)},${c.d(t.ssin)},${c.d(t.tx)},${c.d(t.ty)}').join('|'),
    rects.map(c.rect).join(''),
    colors == null ? null : c.colors(colors),
    blendMode,
    if (cullRect == null) null else c.rect(cullRect),
    _p(paint),
  ]);

  @override
  void drawRawAtlas(
    ui.Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) => _op('drawRawAtlas', <Object?>[
    _sink.image(atlas),
    c.float32s(rstTransforms),
    c.float32s(rects),
    colors == null ? null : c.int32s(colors),
    blendMode,
    if (cullRect == null) null else c.rect(cullRect),
    _p(paint),
  ]);

  @override
  void drawShadow(Path path, Color color, double elevation, bool transparentOccluder) =>
      _op('drawShadow', <Object?>[fingerprintPath(path), c.color(color), elevation, transparentOccluder]);
}
