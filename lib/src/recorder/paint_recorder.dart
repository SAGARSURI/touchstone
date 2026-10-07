// Records each render object's own paint, including opacity and layer effects
// (assumption A1).
//
// TestRecordingPaintingContext.paintChild paints the whole subtree into one
// stream, and its pushOpacity and pushLayer drop the alpha and the layer. Here
// every render object gets its own op stream: a child leaves a marker in its
// parent's stream and records into its own, painted at its own origin so its
// ops do not change when only its position changes. Layer pushes record the
// layer's type and parameters.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/rendering.dart';

import 'canonical.dart' as c;
import 'describe.dart';
import 'fingerprint.dart';
import 'recording_canvas.dart';

/// One render object's own paint.
class RecordedNode implements OpSink {
  RecordedNode._(this.index, this.renderObject, this.parent, this._recording) {
    describeContext = DescribeContext(renderObject, _markOpaque);
  }

  /// Position in paint order.
  final int index;
  final RenderObject renderObject;
  final RecordedNode? parent;
  final PaintRecording _recording;

  /// Children in paint order.
  final List<RecordedNode> children = <RecordedNode>[];

  /// Offset each child was painted at, relative to this node's origin.
  final List<Offset> childOffsets = <Offset>[];

  /// Canonical ops. A child appears as the op `child`.
  final List<String> ops = <String>[];

  /// Reasons this node's paint could not be recorded by value.
  final Map<OpaqueReason, Set<String>> opaque = <OpaqueReason, Set<String>>{};

  @override
  late final DescribeContext describeContext;

  bool get isOpaque => opaque.isNotEmpty;

  /// Hash of [ops] after image fingerprints are resolved.
  late final String paintHash;

  /// Hash of this node's ops, child placements and children's subtree hashes.
  late final String subtreeHash;

  void _markOpaque(OpaqueReason reason, String detail) {
    (opaque[reason] ??= <String>{}).add(detail);
  }

  @override
  void op(String text) => ops.add(text);

  @override
  String image(ui.Image image) => _recording._addImage(image);

  /// Global bounds of the render object's paint bounds.
  Rect get globalPaintBounds => MatrixUtils.transformRect(renderObject.getTransformTo(null), renderObject.paintBounds);
}

/// The result of painting a render tree into [PaintRecorder].
class PaintRecording {
  PaintRecording._();

  final List<RecordedNode> nodes = <RecordedNode>[];
  final List<ui.Image> _images = <ui.Image>[];
  final List<String?> _imageFingerprints = <String?>[];

  RecordedNode get root => nodes.first;

  String _addImage(ui.Image image) {
    _images.add(image.clone());
    return '\u0001img${_images.length - 1}\u0001';
  }

  static final RegExp _imagePlaceholder = RegExp('\u0001img(\\d+)\u0001');

  /// Reads image bytes and computes every hash. Must run outside the fake
  /// async zone of a widget test, for example inside `tester.runAsync`.
  ///
  /// An opaque node's paint hash includes [pixelHash] of its global paint
  /// bounds, so a change in what it draws still changes its hash.
  Future<void> resolve({required Future<String> Function(Rect globalRect) pixelHash}) async {
    final Map<RecordedNode, Rect> opaqueRegions = <RecordedNode, Rect>{
      for (final RecordedNode node in nodes)
        if (node.isOpaque) node: node.globalPaintBounds,
    };
    for (final ui.Image image in _images) {
      _imageFingerprints.add(await fingerprintImage(image));
      image.dispose();
    }
    _images.clear();
    for (final RecordedNode node in nodes.reversed) {
      final List<String> ops = node.ops
          .map(
            (String op) =>
                op.replaceAllMapped(_imagePlaceholder, (Match m) => _imageFingerprints[int.parse(m.group(1)!)]!),
          )
          .toList();
      final Rect? region = opaqueRegions[node];
      if (region != null) {
        ops.add('pixels(${c.rect(region)};${await pixelHash(region)})');
      }
      node.ops
        ..clear()
        ..addAll(ops);
      node.paintHash = _hash(ops);
      node.subtreeHash = _hash(<String>[
        node.paintHash,
        for (var i = 0; i < node.children.length; i++)
          '${c.offset(node.childOffsets[i])}${node.children[i].subtreeHash}',
      ]);
    }
  }

  static String _hash(List<String> lines) => sha256.convert(utf8.encode(lines.join('\n'))).toString();
}

/// Paints a render tree into per-node op streams.
class PaintRecorder {
  /// Records [root] and everything it paints. Call after the last pump, with
  /// no frame scheduled.
  static PaintRecording record(RenderObject root) {
    final recording = PaintRecording._();
    final RecordedNode node = _newNode(recording, root, null);
    _paintNode(recording, node);
    return recording;
  }

  /// Marks every recorded render object as needing paint.
  ///
  /// Render objects set properties on the layers they own before handing them
  /// to the painting context (RenderShaderMask sets its mask rect from the
  /// paint offset, for example). Recording paints each node at its own origin,
  /// so those properties are left with recording values. The next frame
  /// repaints them with the real context. Rasterize before recording, and pump
  /// a frame after calling this.
  static void restore(PaintRecording recording) {
    for (final RecordedNode node in recording.nodes) {
      if (node.renderObject.attached) {
        node.renderObject.markNeedsPaint();
      }
    }
  }

  static RecordedNode _newNode(PaintRecording recording, RenderObject ro, RecordedNode? parent) {
    final node = RecordedNode._(recording.nodes.length, ro, parent, recording);
    recording.nodes.add(node);
    return node;
  }

  static void _paintNode(PaintRecording recording, RecordedNode node) {
    final context = _RecordingContext(recording, node);
    node.renderObject.paint(context, Offset.zero);
  }
}

class _RecordingContext extends ClipContext implements PaintingContext {
  _RecordingContext(this._recording, this._node) : canvas = RecordingCanvas(_node);

  final PaintRecording _recording;
  final RecordedNode _node;

  @override
  final Canvas canvas;

  DescribeContext get _ctx => _node.describeContext;

  void _op(String name, [List<Object?> fields = const <Object?>[]]) => _node.op(c.rec(name, fields));

  @override
  Rect get estimatedBounds => Rect.largest;

  @override
  void paintChild(RenderObject child, Offset offset) {
    // Mirrors RenderObject._paintWithContext: a child still needing layout was
    // skipped by layout and is not painted.
    if (child.debugNeedsLayout) {
      return;
    }
    final RecordedNode childNode = PaintRecorder._newNode(_recording, child, _node);
    _node.children.add(childNode);
    _node.childOffsets.add(offset);
    _node.op('child');
    if (child.isRepaintBoundary) {
      // The real context composites a repaint boundary through its own layer,
      // built by updateCompositedLayer (an OpacityLayer for RenderOpacity, for
      // example). That layer's effect belongs to the child's own paint; its
      // offset is the placement already recorded above.
      childNode.op(c.rec('composite', <Object?>[_describeBoundaryLayer(child, childNode)]));
    }
    PaintRecorder._paintNode(_recording, childNode);
  }

  static String _describeBoundaryLayer(RenderObject child, RecordedNode node) {
    final Layer? layer = child.debugLayer;
    switch (layer) {
      case null:
        return '-';
      case OpacityLayer():
        return c.rec('Opacity', <Object?>[layer.alpha]);
      case ImageFilterLayer():
        return c.rec('ImageFilter', <Object?>[
          if (layer.imageFilter == null) null else describeImageFilter(layer.imageFilter!, node.describeContext),
        ]);
      case TransformLayer():
        return c.rec('Transform', <Object?>[
          if (layer.transform == null) null else c.float64s(layer.transform!.storage),
        ]);
      default:
        if (layer.runtimeType == OffsetLayer) {
          return 'Offset';
        }
        node.describeContext.markOpaque(OpaqueReason.unknownLayer, layer.runtimeType.toString());
        return 'Layer?(${layer.runtimeType})';
    }
  }

  @override
  ClipRectLayer? pushClipRect(
    bool needsCompositing,
    Offset offset,
    Rect clipRect,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.hardEdge,
    ClipRectLayer? oldLayer,
  }) {
    _op('pushClipRect', <Object?>[c.rect(clipRect.shift(offset)), clipBehavior]);
    painter(this, offset);
    _op('pop');
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
    _op('pushClipRRect', <Object?>[c.rrect(clipRRect.shift(offset)), c.rect(bounds.shift(offset)), clipBehavior]);
    painter(this, offset);
    _op('pop');
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
    _op('pushClipRSE', <Object?>[
      c.rsuperellipse(clipRSuperellipse.shift(offset)),
      c.rect(bounds.shift(offset)),
      clipBehavior,
    ]);
    painter(this, offset);
    _op('pop');
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
    _op('pushClipPath', <Object?>[fingerprintPath(clipPath.shift(offset)), c.rect(bounds.shift(offset)), clipBehavior]);
    painter(this, offset);
    _op('pop');
    return oldLayer;
  }

  @override
  ColorFilterLayer pushColorFilter(
    Offset offset,
    ColorFilter colorFilter,
    PaintingContextCallback painter, {
    ColorFilterLayer? oldLayer,
  }) {
    _op('pushColorFilter', <Object?>[describeColorFilter(colorFilter, _ctx)]);
    painter(this, offset);
    _op('pop');
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
    _op('pushTransform', <Object?>[c.offset(offset), c.float64s(transform.storage)]);
    painter(this, offset);
    _op('pop');
    return oldLayer;
  }

  @override
  OpacityLayer pushOpacity(Offset offset, int alpha, PaintingContextCallback painter, {OpacityLayer? oldLayer}) {
    // The real context sets the layer's offset and paints at Offset.zero.
    _op('pushOpacity', <Object?>[alpha, c.offset(offset)]);
    painter(this, Offset.zero);
    _op('pop');
    return oldLayer ?? OpacityLayer();
  }

  @override
  void pushLayer(ContainerLayer childLayer, PaintingContextCallback painter, Offset offset, {Rect? childPaintBounds}) {
    _op('pushLayer', <Object?>[_describeLayer(childLayer), c.offset(offset)]);
    painter(this, offset);
    _op('pop');
  }

  String _describeLayer(ContainerLayer layer) {
    switch (layer) {
      case OpacityLayer():
        return c.rec('Opacity', <Object?>[layer.alpha, c.offset(layer.offset)]);
      case ImageFilterLayer():
        return c.rec('ImageFilter', <Object?>[
          if (layer.imageFilter == null) null else describeImageFilter(layer.imageFilter!, _ctx),
          c.offset(layer.offset),
        ]);
      case TransformLayer():
        return c.rec('Transform', <Object?>[
          if (layer.transform == null) null else c.float64s(layer.transform!.storage),
          c.offset(layer.offset),
        ]);
      case ColorFilterLayer():
        return c.rec('ColorFilter', <Object?>[
          if (layer.colorFilter == null) null else describeImageFilter(layer.colorFilter!, _ctx),
        ]);
      case ClipRectLayer():
        return c.rec('ClipRect', <Object?>[
          if (layer.clipRect == null) null else c.rect(layer.clipRect!),
          layer.clipBehavior,
        ]);
      case ClipRRectLayer():
        return c.rec('ClipRRect', <Object?>[
          if (layer.clipRRect == null) null else c.rrect(layer.clipRRect!),
          layer.clipBehavior,
        ]);
      case ClipRSuperellipseLayer():
        return c.rec('ClipRSE', <Object?>[
          if (layer.clipRSuperellipse == null) null else c.rsuperellipse(layer.clipRSuperellipse!),
          layer.clipBehavior,
        ]);
      case ClipPathLayer():
        return c.rec('ClipPath', <Object?>[
          if (layer.clipPath == null) null else fingerprintPath(layer.clipPath!),
          layer.clipBehavior,
        ]);
      case ShaderMaskLayer():
        return c.rec('ShaderMask', <Object?>[
          if (layer.shader == null) null else describeShader(layer.shader!, _ctx),
          if (layer.maskRect == null) null else c.rect(layer.maskRect!),
          layer.blendMode,
        ]);
      case BackdropFilterLayer():
        return c.rec('Backdrop', <Object?>[
          if (layer.filter == null) null else describeImageFilter(layer.filter!, _ctx),
          layer.blendMode,
          layer.backdropKey != null,
        ]);
      case LeaderLayer():
        return c.rec('Leader', <Object?>[c.offset(layer.offset)]);
      case FollowerLayer():
        return c.rec('Follower', <Object?>[
          layer.showWhenUnlinked,
          if (layer.unlinkedOffset == null) null else c.offset(layer.unlinkedOffset!),
          if (layer.linkedOffset == null) null else c.offset(layer.linkedOffset!),
        ]);
      case AnnotatedRegionLayer<Object>():
        // Annotations carry data for the system UI, not pixels.
        return 'Annotated';
      case OffsetLayer():
        return c.rec('Offset', <Object?>[c.offset(layer.offset)]);
      default:
        _ctx.markOpaque(OpaqueReason.unknownLayer, layer.runtimeType.toString());
        return 'Layer?(${layer.runtimeType})';
    }
  }

  @override
  void addLayer(Layer layer) {
    switch (layer) {
      case PlatformViewLayer():
        _ctx.markOpaque(OpaqueReason.platformView, 'PlatformViewLayer');
        _op('addLayer', <Object?>['PlatformView', c.rect(layer.rect)]);
      case TextureLayer():
        _ctx.markOpaque(OpaqueReason.texture, 'TextureLayer');
        _op('addLayer', <Object?>['Texture', c.rect(layer.rect), layer.freeze, layer.filterQuality]);
      default:
        _ctx.markOpaque(OpaqueReason.unknownLayer, layer.runtimeType.toString());
        _op('addLayer', <Object?>['?${layer.runtimeType}']);
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
  ui.PictureRecorder get recorder => throw UnsupportedError('No picture recorder while recording paint.');
}
