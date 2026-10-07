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
  RecordedNode._(
    this.index,
    this.renderObject,
    this.parent,
    this._recording, {
    required this.toGlobal,
    required this.inheritedClip,
    required this.spreadClip,
    required this.geometryVerified,
  }) {
    describeContext = DescribeContext(renderObject, _markOpaque);
  }

  /// Position in paint order.
  final int index;
  final RenderObject renderObject;
  final RecordedNode? parent;
  final PaintRecording _recording;

  /// Maps this node's paint origin to global logical coordinates, composed
  /// from the transforms its ancestors painted with.
  final Matrix4 toGlobal;

  /// Global clip in effect when this node starts painting.
  final Rect inheritedClip;

  /// Set when an ancestor layer can move or spread this node's pixels (see
  /// [RecordingCanvas]).
  final Rect? spreadClip;

  /// Whether [toGlobal] agrees with the render object's own paint transform
  /// ([RenderObject.getTransformTo]). When it does not, this node's reach is
  /// the whole view.
  final bool geometryVerified;

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

  /// Number of times this node was marked opaque so far.
  int _opaqueMarks = 0;

  /// Global bounds of every pixel this node's own paint can change: what it
  /// drew, widened for stroke and blur, inside the clip in effect, plus the
  /// whole clip for effects with no bounded geometry. Null when it drew
  /// nothing.
  Rect? get reachBounds => _reach;
  Rect? _reach;

  /// Hash of [ops] after image fingerprints are resolved.
  late final String paintHash;

  /// Hash of this node's ops, child placements and children's subtree hashes.
  late final String subtreeHash;

  void _markOpaque(OpaqueReason reason, String detail) {
    _opaqueMarks++;
    (opaque[reason] ??= <String>{}).add(detail);
  }

  @override
  void op(String text) => ops.add(text);

  @override
  String image(ui.Image image) => _recording._addImage(image);

  @override
  void reach(Rect globalRect) {
    final Rect r = geometryVerified ? globalRect : _recording.viewRect;
    if (!(r.width > 0 && r.height > 0)) {
      return;
    }
    _reach = _reach?.expandToInclude(r) ?? r;
  }
}

/// The result of painting a render tree into [PaintRecorder].
class PaintRecording {
  PaintRecording._();

  final List<RecordedNode> nodes = <RecordedNode>[];
  final List<ui.Image> _images = <ui.Image>[];

  /// The view, in global logical coordinates.
  late final Rect viewRect;

  /// Global regions a backdrop filter reads and rewrites. A pixel change under
  /// one can spread anywhere inside it.
  final List<Rect> backdrops = <Rect>[];
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
  /// An opaque node's paint hash includes [pixelHash] of [opaqueRegion], so a
  /// change in what it draws still changes its hash.
  Future<void> resolve({required Future<String> Function(Rect globalRect) pixelHash}) async {
    final Map<RecordedNode, Rect> opaqueRegions = <RecordedNode, Rect>{
      for (final RecordedNode node in nodes)
        if (node.isOpaque) node: opaqueRegion(node),
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

  /// The pixels an opaque node's paint can change: its reach (or, if it drew
  /// nothing, the clip it was given) inside the view, grown by every backdrop
  /// filter it overlaps.
  Rect opaqueRegion(RecordedNode node) {
    Rect region = (node.reachBounds ?? node.inheritedClip).intersect(viewRect);
    for (final Rect backdrop in backdrops) {
      if (region.overlaps(backdrop)) {
        region = region.expandToInclude(backdrop.intersect(viewRect));
      }
    }
    return region;
  }

  static String _hash(List<String> lines) => sha256.convert(utf8.encode(lines.join('\n'))).toString();
}

/// Paints a render tree into per-node op streams.
class PaintRecorder {
  /// Records [view] and everything it paints. Call after the last pump, with
  /// no frame scheduled.
  static PaintRecording record(RenderView view) {
    final recording = PaintRecording._()..viewRect = Offset.zero & view.size;
    final node = RecordedNode._(
      0,
      view,
      null,
      recording,
      toGlobal: Matrix4.identity(),
      inheritedClip: recording.viewRect,
      spreadClip: null,
      geometryVerified: true,
    );
    recording.nodes.add(node);
    // Device pixel ratio and view size decide how every logical value maps to
    // pixels.
    node.op(c.rec('view', <Object?>[view.configuration.devicePixelRatio, c.size(view.size)]));
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

  static void _paintNode(PaintRecording recording, RecordedNode node) {
    final context = _RecordingContext(recording, node);
    node.renderObject.paint(context, Offset.zero);
  }

  /// Whether [composed] matches the render object's own paint transform to
  /// the view's logical coordinates. getTransformTo(null) stops below the
  /// render view's device pixel ratio transform; if that ever changed, every
  /// node would fail verification and be hashed over the whole view.
  static bool _verify(RenderObject ro, Matrix4 composed) {
    final Matrix4 reference = ro.getTransformTo(null);
    for (var i = 0; i < 16; i++) {
      final double a = composed.storage[i];
      final double b = reference.storage[i];
      if (!((a - b).abs() <= 1e-7 * (1 + a.abs()))) {
        return false;
      }
    }
    return true;
  }
}

class _RecordingContext extends ClipContext implements PaintingContext {
  _RecordingContext(this._recording, this._node)
    : canvas = RecordingCanvas(
        _node,
        _node.toGlobal,
        _node.geometryVerified ? _node.inheritedClip : _recording.viewRect,
        spreadClip: _node.spreadClip,
        trackClips: _node.geometryVerified,
      );

  final PaintRecording _recording;
  final RecordedNode _node;

  @override
  final RecordingCanvas canvas;

  DescribeContext get _ctx => _node.describeContext;

  void _op(String name, [List<Object?> fields = const <Object?>[]]) => _node.op(c.rec(name, fields));

  /// Runs [describe]; if it marked the node opaque, the effect it describes
  /// can change any pixel inside [localBounds] (in current canvas
  /// coordinates), or inside the current clip when it has no bounds.
  String _describeEffect(String Function() describe, {Rect? localBounds}) {
    final int before = _node._opaqueMarks;
    final String text = describe();
    if (_node._opaqueMarks != before) {
      if (localBounds == null) {
        canvas.reachClip();
      } else {
        canvas.reachLocal(localBounds);
      }
    }
    return text;
  }

  /// Runs [painter] inside canvas state for a pushed transform, clip or
  /// spreading layer, between the recorded push op and `pop`.
  void _push(String op, VoidCallback painter, {Matrix4? transform, Rect? localClip, bool spread = false}) {
    _node.op(op);
    canvas.pushState(transform: transform, localClip: localClip, spread: spread);
    painter();
    canvas.popState();
    _op('pop');
  }

  @override
  Rect get estimatedBounds => Rect.largest;

  @override
  void paintChild(RenderObject child, Offset offset) {
    // Mirrors RenderObject._paintWithContext: a child still needing layout was
    // skipped by layout and is not painted.
    if (child.debugNeedsLayout) {
      return;
    }
    Matrix4 toGlobal = canvas.childTransform(offset);
    Rect? spreadClip = canvas.spreadClip;
    final Layer? boundaryLayer = child.isRepaintBoundary ? child.debugLayer : null;
    if (boundaryLayer is TransformLayer && boundaryLayer.transform != null) {
      toGlobal = toGlobal.multiplied(boundaryLayer.transform!);
    }
    if (boundaryLayer is ImageFilterLayer) {
      spreadClip ??= canvas.currentClip;
    }
    final childNode = RecordedNode._(
      _recording.nodes.length,
      child,
      _node,
      _recording,
      toGlobal: toGlobal,
      inheritedClip: canvas.currentClip,
      spreadClip: spreadClip,
      geometryVerified: _node.geometryVerified && PaintRecorder._verify(child, toGlobal),
    );
    _recording.nodes.add(childNode);
    _node.children.add(childNode);
    _node.childOffsets.add(offset);
    _node.op('child');
    if (child.isRepaintBoundary) {
      // The real context composites a repaint boundary through its own layer,
      // built by updateCompositedLayer (an OpacityLayer for RenderOpacity, for
      // example). That layer's effect belongs to the child's own paint; its
      // offset is the placement already recorded above.
      final int before = childNode._opaqueMarks;
      childNode.op(c.rec('composite', <Object?>[_describeBoundaryLayer(boundaryLayer, childNode)]));
      if (childNode._opaqueMarks != before) {
        childNode.reach(spreadClip ?? canvas.currentClip);
      }
    }
    PaintRecorder._paintNode(_recording, childNode);
  }

  static String _describeBoundaryLayer(Layer? layer, RecordedNode node) {
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
    _push(
      c.rec('pushClipRect', <Object?>[c.rect(clipRect.shift(offset)), clipBehavior]),
      () => painter(this, offset),
      localClip: clipBehavior == Clip.none ? null : clipRect.shift(offset),
    );
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
    _push(
      c.rec('pushClipRRect', <Object?>[c.rrect(clipRRect.shift(offset)), c.rect(bounds.shift(offset)), clipBehavior]),
      () => painter(this, offset),
      localClip: clipBehavior == Clip.none ? null : clipRRect.outerRect.shift(offset),
    );
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
    _push(
      c.rec('pushClipRSE', <Object?>[
        c.rsuperellipse(clipRSuperellipse.shift(offset)),
        c.rect(bounds.shift(offset)),
        clipBehavior,
      ]),
      () => painter(this, offset),
      localClip: clipBehavior == Clip.none ? null : clipRSuperellipse.outerRect.shift(offset),
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
    if (clipBehavior != Clip.none) {
      // The clip's edge decides which pixels of everything inside show, and a
      // path fingerprint is lossy: pixel-hash the clipped area.
      _ctx.markOpaque(OpaqueReason.path, 'pushClipPath');
      canvas.reachLocal(shifted.getBounds().inflate(1));
    }
    _push(
      c.rec('pushClipPath', <Object?>[fingerprintPath(shifted), c.rect(bounds.shift(offset)), clipBehavior]),
      () => painter(this, offset),
      localClip: clipBehavior == Clip.none ? null : shifted.getBounds(),
    );
    return oldLayer;
  }

  @override
  ColorFilterLayer pushColorFilter(
    Offset offset,
    ColorFilter colorFilter,
    PaintingContextCallback painter, {
    ColorFilterLayer? oldLayer,
  }) {
    _push(
      c.rec('pushColorFilter', <Object?>[_describeEffect(() => describeColorFilter(colorFilter, _ctx))]),
      () => painter(this, offset),
    );
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
    // As PaintingContext.pushTransform: the transform applies about offset.
    final Matrix4 effective = Matrix4.translationValues(offset.dx, offset.dy, 0)
      ..multiply(transform)
      ..translateByDouble(-offset.dx, -offset.dy, 0, 1);
    _push(
      c.rec('pushTransform', <Object?>[c.offset(offset), c.float64s(transform.storage)]),
      () => painter(this, offset),
      transform: effective,
    );
    return oldLayer;
  }

  @override
  OpacityLayer pushOpacity(Offset offset, int alpha, PaintingContextCallback painter, {OpacityLayer? oldLayer}) {
    // The real context sets the layer's offset and paints at Offset.zero.
    _push(
      c.rec('pushOpacity', <Object?>[alpha, c.offset(offset)]),
      () => painter(this, Offset.zero),
      transform: Matrix4.translationValues(offset.dx, offset.dy, 0),
    );
    return oldLayer ?? OpacityLayer();
  }

  @override
  void pushLayer(ContainerLayer childLayer, PaintingContextCallback painter, Offset offset, {Rect? childPaintBounds}) {
    // A shader mask is drawn over its mask rect, onto its children's content.
    final String description = _describeEffect(
      () => _describeLayer(childLayer),
      localBounds: childLayer is ShaderMaskLayer ? childLayer.maskRect?.inflate(1) : null,
    );
    if (childLayer is BackdropFilterLayer) {
      _recording.backdrops.add(canvas.spreadClip ?? canvas.currentClip);
    }
    _push(
      c.rec('pushLayer', <Object?>[description, c.offset(offset)]),
      () => painter(this, offset),
      transform: _layerTransform(childLayer),
      localClip: _layerClip(childLayer),
      spread: childLayer is ImageFilterLayer || _isUnknownLayer(childLayer),
    );
  }

  /// How a pushed layer moves its content, as its addToScene applies it.
  Matrix4? _layerTransform(ContainerLayer layer) {
    switch (layer) {
      case TransformLayer():
        final Matrix4 t = Matrix4.translationValues(layer.offset.dx, layer.offset.dy, 0);
        return layer.transform == null ? t : (t..multiply(layer.transform!));
      case OffsetLayer():
        return Matrix4.translationValues(layer.offset.dx, layer.offset.dy, 0);
      case LeaderLayer():
        return Matrix4.translationValues(layer.offset.dx, layer.offset.dy, 0);
      case FollowerLayer():
        // Where the follower lands depends on its leader. The transform used
        // by the last composition is the one RenderFollowerLayer applies for
        // painting and hit testing.
        final RenderObject owner = _ctx.owner;
        return owner is RenderFollowerLayer ? owner.getCurrentTransform() : null;
      default:
        return null;
    }
  }

  static Rect? _layerClip(ContainerLayer layer) => switch (layer) {
    ClipRectLayer(:final clipRect?, :final clipBehavior) when clipBehavior != Clip.none => clipRect,
    ClipRRectLayer(:final clipRRect?, :final clipBehavior) when clipBehavior != Clip.none => clipRRect.outerRect,
    ClipRSuperellipseLayer(:final clipRSuperellipse?, :final clipBehavior) when clipBehavior != Clip.none =>
      clipRSuperellipse.outerRect,
    ClipPathLayer(:final clipPath?, :final clipBehavior) when clipBehavior != Clip.none => clipPath.getBounds(),
    _ => null,
  };

  static bool _isUnknownLayer(ContainerLayer layer) => switch (layer) {
    OffsetLayer() ||
    ColorFilterLayer() ||
    ClipRectLayer() ||
    ClipRRectLayer() ||
    ClipRSuperellipseLayer() ||
    ClipPathLayer() ||
    ShaderMaskLayer() ||
    BackdropFilterLayer() ||
    LeaderLayer() ||
    FollowerLayer() ||
    AnnotatedRegionLayer<Object>() => false,
    _ => true,
  };

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
        if (layer.clipPath != null && layer.clipBehavior != Clip.none) {
          _ctx.markOpaque(OpaqueReason.path, 'ClipPathLayer');
        }
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
        final RenderObject owner = _ctx.owner;
        if (owner is! RenderFollowerLayer) {
          _ctx.markOpaque(OpaqueReason.unknownLayer, 'FollowerLayer outside RenderFollowerLayer');
        }
        return c.rec('Follower', <Object?>[
          layer.showWhenUnlinked,
          if (layer.unlinkedOffset == null) null else c.offset(layer.unlinkedOffset!),
          if (layer.linkedOffset == null) null else c.offset(layer.linkedOffset!),
          // Which leader it follows, and where that leader is.
          if (owner is RenderFollowerLayer) c.float64s(owner.getCurrentTransform().storage),
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
        canvas.reachLocal(layer.rect);
        _op('addLayer', <Object?>['PlatformView', c.rect(layer.rect)]);
      case TextureLayer():
        _ctx.markOpaque(OpaqueReason.texture, 'TextureLayer');
        canvas.reachLocal(layer.rect);
        _op('addLayer', <Object?>['Texture', c.rect(layer.rect), layer.freeze, layer.filterQuality]);
      default:
        _ctx.markOpaque(OpaqueReason.unknownLayer, layer.runtimeType.toString());
        canvas.reachClip();
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
