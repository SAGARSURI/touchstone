// The capture pipeline (spec: Flutter capture, Capture steps).
//
// Settle, select components, record geometry and paint, read semantics and
// style, then hash bottom-up and return the snapshot.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Ink;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../audit/pixels.dart';
import '../recorder/canonical.dart' as c;
import '../recorder/paint_recorder.dart';
import 'components.dart';
import 'difference.dart';
import 'snapshot.dart';
import 'toolchain.dart';

/// Returns a design-token name for a resolved value, or null. Project code,
/// so a theme extension, a generated table or plain constants all work.
typedef TokenResolver = String? Function(Object value);

class SnapshotOptions {
  const SnapshotOptions({
    this.policy,
    this.state,
    this.theme,
    this.tokenResolver,
    this.atPumpedTime = false,
    this.dynamicComponents = const <String>{},
  });

  /// Which widgets are components. Defaults to classes declared in the
  /// package under test.
  final ComponentPolicy? policy;

  /// The declared app state, recorded in `inputs`.
  final String? state;

  /// The declared theme variant, recorded in `inputs`.
  final String? theme;

  final TokenResolver? tokenResolver;

  /// Captures at the frame the test last pumped, though a frame is scheduled
  /// (spec: "Capture only when no frame is scheduled, or at an explicitly
  /// pumped time"). For content that animates forever, such as a shimmer.
  /// The frame's time stamp is recorded in `inputs` as `frameTime`, and the
  /// capture's own pumps do not advance time.
  final bool atPumpedTime;

  /// Components whose content changes from run to run, such as a clock or a
  /// live price: a component type, an id segment or a full id. Their content
  /// (text and images) is not compared; their structure, layout, style and
  /// semantics are (spec: "Dynamic content is declared in the test"). Recorded
  /// in `inputs` as `dynamic`.
  final Set<String> dynamicComponents;

  SnapshotOptions _atPumpedTime() => SnapshotOptions(
    policy: policy,
    state: state,
    theme: theme,
    tokenResolver: tokenResolver,
    atPumpedTime: true,
    dynamicComponents: dynamicComponents,
  );
}

/// The capture could not produce a deterministic snapshot.
class CaptureFailure implements Exception {
  CaptureFailure(this.message, {this.difference});

  final String message;

  /// The node the failure was traced to, when it could be.
  final SnapshotDifference? difference;

  @override
  String toString() => 'Touchstone capture failed: $message${difference == null ? '' : '\n$difference'}';
}

/// A snapshot together with what produced it, for audits.
class Capture {
  Capture(this.snapshot, this.recording, this.tree, this.rasterized);

  final Snapshot snapshot;
  final PaintRecording recording;
  final ComponentTree tree;

  /// Whether any pixels were rasterized (only when a node is opaque).
  final bool rasterized;
}

/// Captures the current widget tree of [tester] as a snapshot named [id].
Future<Snapshot> captureSnapshot(
  WidgetTester tester,
  String id, {
  SnapshotOptions options = const SnapshotOptions(),
}) async => (await captureWithDetails(tester, id, options: options)).snapshot;

ComponentPolicy? _defaultPolicy;

Future<Capture> captureWithDetails(
  WidgetTester tester,
  String id, {
  SnapshotOptions options = const SnapshotOptions(),
}) async {
  if (!options.atPumpedTime && tester.binding.hasScheduledFrame) {
    throw CaptureFailure(
      'a frame is scheduled before capture. Capture only when settled (pumpAndSettle) or at an explicitly pumped '
      'time (SnapshotOptions.atPumpedTime); an animation, a ticker or a timer is still running.',
      difference: await diagnoseUnsettled(tester, id, options),
    );
  }
  final List<_PendingImage> pending = await _pendingImages(tester);
  if (pending.isNotEmpty) {
    throw CaptureFailure(
      'an image is not decoded: ${pending.map((_PendingImage p) => p.describe()).join(', ')}. Precache it '
      'before capture (precacheImages, or precacheImage inside tester.runAsync, then pump).',
      difference: await _diagnoseImages(tester, id, options, pending),
    );
  }
  final List<String> unregistered = await _fontsLoadedElsewhere(tester);
  if (unregistered.isNotEmpty) {
    throw CaptureFailure(
      'text in ${unregistered.join(', ')} renders with a font that was not loaded through SnapshotFonts.load, so '
      'the toolchain fingerprint cannot record it. Load fonts for snapshot tests with SnapshotFonts.load.',
    );
  }
  return _capture(tester, id, options);
}

/// Font families the shown text uses that render with a font loaded outside
/// [SnapshotFonts.load] (a FontLoader or loadFontFromList). Each family is
/// drawn with the code points it shows and compared with the same text in a
/// family that is not loaded, which falls back to the test font.
Future<List<String>> _fontsLoadedElsewhere(WidgetTester tester) async {
  final codePoints = <String, Set<int>>{};
  void addSpan(InlineSpan span, String? inherited) {
    final String? family = span.style?.fontFamily ?? inherited;
    if (span is TextSpan) {
      final String? text = span.text;
      if (family != null && text != null) {
        (codePoints[family] ??= <int>{}).addAll(text.runes);
      }
      for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
        addSpan(child, family);
      }
    }
  }

  void visit(RenderObject ro) {
    if (ro is RenderParagraph) {
      addSpan(ro.text, null);
    } else if (ro is RenderEditable && ro.text != null) {
      addSpan(ro.text!, null);
    }
    ro.visitChildren(visit);
  }

  visit(tester.binding.renderViews.first);
  final out = <String>[];
  var probed = false;
  for (final MapEntry<String, Set<int>> e in codePoints.entries) {
    if (_testFonts.contains(e.key) || SnapshotFonts.isLoaded(e.key) || e.value.isEmpty) {
      continue;
    }
    final String text = String.fromCharCodes((e.value.toList()..sort()).take(64));
    final bool differs = (await tester.runAsync(
      () async => await _drawText(text, e.key) != await _drawText(text, '_touchstone_unloaded_family'),
    ))!;
    if (differs) {
      out.add(e.key);
    }
    probed = true;
  }
  if (probed) {
    // Drawing in real async time leaves a frame scheduled with a focused
    // text field, as rasterizing does; pump it without advancing the clock.
    await tester.pump();
  }
  return out..sort();
}

/// The fonts flutter_tester registers itself; they are part of its version.
const Set<String> _testFonts = <String>{'FlutterTest', 'Ahem'};

Future<String> _drawText(String text, String family) async {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: family, fontSize: 20))..addText(text);
  final ui.Paragraph paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: 1000));
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawParagraph(paragraph, Offset.zero);
  final ui.Picture picture = recorder.endRecording();
  final String metrics = '${paragraph.longestLine} ${paragraph.height}';
  final ui.Image image = await picture.toImage(1000, paragraph.height.ceil().clamp(1, 2000));
  final ByteData? bytes = await image.toByteData();
  image.dispose();
  picture.dispose();
  paragraph.dispose();
  return '$metrics ${sha256.convert(bytes!.buffer.asUint8List())}';
}

/// Traces a scheduled frame to the node it changes: captures at the current
/// time, pumps 100 ms, captures again and compares. Advances the test's
/// clock, so it runs only once a capture has already failed.
Future<SnapshotDifference> diagnoseUnsettled(WidgetTester tester, String id, SnapshotOptions options) async {
  final SnapshotOptions pumped = options._atPumpedTime();
  try {
    final String before = (await captureWithDetails(tester, id, options: pumped)).snapshot.toCanonical();
    await tester.pump(const Duration(milliseconds: 100));
    final Snapshot later = (await captureWithDetails(tester, id, options: pumped)).snapshot;
    // Compare the trees only: the frame time in the inputs always differs.
    final String after = Snapshot(
      id: later.id,
      inputs: Snapshot.parse(before).inputs,
      toolchain: later.toolchain,
      coverage: later.coverage,
      root: later.root,
    ).toCanonical();
    final SnapshotDifference d = firstDifference(before, after);
    if (before == after) {
      return SnapshotDifference(
        '-',
        const <String>['frame'],
        'a frame is scheduled but nothing changes over 100 ms: a timer or ticker that does not repaint',
        '',
        '',
      );
    }
    return SnapshotDifference(
      d.nodeId,
      d.fields,
      'an animation, ticker or timer is still running and changes this node over time',
      d.before,
      d.after,
    );
  } on CaptureFailure catch (e) {
    // An image still loading takes precedence.
    return e.difference ?? SnapshotDifference('-', const <String>['capture'], e.message, '', '');
  }
}

/// Names the components whose images are not decoded yet.
Future<SnapshotDifference> _diagnoseImages(
  WidgetTester tester,
  String id,
  SnapshotOptions options,
  List<_PendingImage> pending,
) async {
  final Capture capture = await _capture(tester, id, options._atPumpedTime());
  final List<String> owners = <String>{
    // A component that paints only the placeholder may have been pruned.
    for (final _PendingImage p in pending)
      p.shownBy == null ? capture.tree.root.fullId : capture.tree.shownOwnerOf(p.shownBy!).fullId,
  }.toList();
  return SnapshotDifference(
    owners.first,
    const <String>['paint'],
    'an image load: ${pending.first.describe()} is not decoded yet, so its placeholder would be '
        'recorded${owners.length > 1 ? ' (also in ${owners.skip(1).join(', ')})' : ''}',
    '',
    '',
  );
}

Future<Capture> _capture(WidgetTester tester, String id, SnapshotOptions options) async {
  final ComponentPolicy policy = options.policy ?? (_defaultPolicy ??= ComponentPolicy());
  void checkSettled(String when) {
    if (!options.atPumpedTime) {
      _checkSettled(tester, when);
    }
  }

  final SemanticsHandle semanticsHandle = tester.ensureSemantics();
  try {
    await tester.pump();
    checkSettled('after building semantics');

    final RenderView view = tester.binding.renderViews.first;
    final PaintRecording recording = PaintRecorder.record(view);
    // Recording leaves layer properties with recording values; repaint them
    // before any pixel is read.
    PaintRecorder.restore(recording);
    await tester.pump();

    PixelRegion? raster;
    final double dpr = view.flutterView.devicePixelRatio;
    await tester.runAsync(
      () => recording.resolve(
        pixelHash: (Rect region) async {
          raster ??= await rasterize(view, Offset.zero & view.size);
          return raster!.crop(region, dpr).hash;
        },
      ),
    );
    if (raster != null) {
      // Compositing the view for the raster runs composition callbacks, and
      // the next frame may schedule one more. Pump those frames, without
      // advancing time, so the tree is left settled.
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      checkSettled('after rasterizing opaque nodes');
    }

    final tree = ComponentTree.build(tester.binding.rootElement!, policy);
    final _Semantics semanticsIndex = _semanticsByComponent(view, tree);
    final Map<Component, List<Map<String, Object?>>> semantics = semanticsIndex.byComponent;
    final painted = <Component>{for (final RecordedNode n in recording.nodes) tree.ownerOfRenderObject(n.renderObject)};
    final shown = <Component>{};
    for (final Component comp in tree.all.toList().reversed) {
      if (painted.contains(comp) || semantics.containsKey(comp) || comp.children.any(shown.contains)) {
        shown.add(comp);
      }
    }
    tree.pruneAndName(shown.contains);

    final assembly = _PaintAssembly(tree)..run(recording);
    final opaqueNodes = <String, List<String>>{};
    SnapshotNode build(Component comp) {
      final List<String> reasons = (assembly.opaque[comp] ?? <String>{}).toList()..sort();
      if (reasons.isNotEmpty) {
        opaqueNodes[comp.fullId] = reasons;
      }
      return SnapshotNode(
        id: comp.segment,
        bounds: comp.parent == null ? _rect(Offset.zero & view.size) : _bounds(comp.renderObject),
        paint: sha256.convert(utf8.encode(assembly.text(comp))).toString(),
        semantics: jsonEncode(semantics[comp] ?? const <Object?>[]),
        opaque: reasons.isEmpty ? '-' : reasons.join('+'),
        flat: _flat(comp, assembly, semanticsIndex),
        type: comp.element == null ? 'root' : policy.typeOf(comp.element!.widget),
        style: jsonEncode(
          _style(assembly.renderObjects[comp] ?? const <RecordedNode>[], options.tokenResolver, comp.element),
        ),
        children: comp.children.map(build).toList(),
      );
    }

    final SnapshotNode root = build(tree.root);
    final snapshot = Snapshot(
      id: id,
      inputs: _inputs(tester, view, options),
      toolchain: toolchainFingerprint(),
      coverage: Coverage(limits: _limits(recording), opaqueNodes: opaqueNodes),
      root: root,
    );
    return Capture(snapshot, recording, tree, raster != null);
  } finally {
    semanticsHandle.dispose();
  }
}

void _checkSettled(WidgetTester tester, String when) {
  if (tester.binding.hasScheduledFrame) {
    throw CaptureFailure(
      'a frame is scheduled $when. Capture only when settled (pumpAndSettle) or at an explicitly pumped time; '
      'an animation, a ticker or a timer is still running.',
    );
  }
}

/// An image still loading and the render object that would show it.
class _PendingImage {
  _PendingImage(this.provider, this.shownBy);
  final ImageProvider provider;
  final RenderObject? shownBy;

  String describe() => provider.toString();
}

/// Images must be decoded before capture; a pending load would record a
/// placeholder, or with gaplessPlayback the previous image. Checks the images
/// of `Image` and `Ink` widgets and of decorated boxes (Container,
/// DecoratedBox, CircleAvatar) against the image cache. A load that failed
/// stays pending in the cache but has reported its error, so an error widget
/// can be captured.
Future<List<_PendingImage>> _pendingImages(WidgetTester tester) async {
  final ImageCache cache = PaintingBinding.instance.imageCache;
  if (cache.pendingImageCount == 0) {
    return const <_PendingImage>[];
  }
  Future<bool> isPending(ImageProvider provider, ImageConfiguration configuration) async {
    final Object? key = await tester.runAsync(() => provider.obtainKey(configuration));
    if (key == null || !cache.statusForKey(key).pending) {
      return false;
    }
    // The stream completer replays an error it already reported to a new
    // listener, synchronously.
    var failed = false;
    final ImageStream stream = provider.resolve(configuration);
    final listener = ImageStreamListener((_, _) {}, onError: (_, _) => failed = true);
    stream.addListener(listener);
    stream.removeListener(listener);
    return !failed;
  }

  DecorationImage? imageOf(Decoration? decoration) => switch (decoration) {
    BoxDecoration(:final DecorationImage? image) => image,
    ShapeDecoration(:final DecorationImage? image) => image,
    _ => null,
  };

  final pending = <_PendingImage>[];
  for (final Element e in find.byType(Image, skipOffstage: false).evaluate()) {
    final image = e.widget as Image;
    final ImageConfiguration configuration = createLocalImageConfiguration(
      e,
      size: image.width != null && image.height != null ? Size(image.width!, image.height!) : null,
    );
    if (await isPending(image.image, configuration)) {
      pending.add(_PendingImage(image.image, e.findRenderObject()));
    }
  }
  for (final Element e in find.byType(Ink, skipOffstage: false).evaluate()) {
    final DecorationImage? image = imageOf((e.widget as Ink).decoration);
    if (image != null && await isPending(image.image, createLocalImageConfiguration(e))) {
      pending.add(_PendingImage(image.image, e.findRenderObject()));
    }
  }
  final decorated = <RenderDecoratedBox>[];
  void visit(RenderObject ro) {
    if (ro is RenderDecoratedBox) {
      decorated.add(ro);
    }
    ro.visitChildren(visit);
  }

  visit(tester.binding.renderViews.first);
  for (final RenderDecoratedBox ro in decorated) {
    final DecorationImage? image = imageOf(ro.decoration);
    if (image != null && await isPending(image.image, ro.configuration.copyWith(size: ro.size))) {
      pending.add(_PendingImage(image.image, ro));
    }
  }
  return pending;
}

String _rect(Rect r) => '${c.d(r.left)},${c.d(r.top)},${c.d(r.width)},${c.d(r.height)}';

String _bounds(RenderObject? ro) {
  if (ro == null || !ro.attached || ro.debugNeedsLayout || (ro is RenderBox && !ro.hasSize)) {
    return '-';
  }
  return _rect(MatrixUtils.transformRect(ro.getTransformTo(null), ro.paintBounds));
}

Map<String, String> _inputs(WidgetTester tester, RenderView view, SnapshotOptions options) => <String, String>{
  'viewport': '${c.d(view.size.width)}x${c.d(view.size.height)}@${c.d(view.flutterView.devicePixelRatio)}',
  'platform': defaultTargetPlatform.name,
  'locale': tester.platformDispatcher.locale.toLanguageTag(),
  'textScale': c.d(tester.platformDispatcher.textScaleFactor),
  'brightness': tester.platformDispatcher.platformBrightness.name,
  'theme': options.theme ?? '-',
  'state': options.state ?? '-',
  if (options.atPumpedTime) 'frameTime': '${tester.binding.currentSystemFrameTimeStamp.inMicroseconds}us',
  if (options.dynamicComponents.isNotEmpty) 'dynamic': (options.dynamicComponents.toList()..sort()).join(','),
};

List<String> _limits(PaintRecording recording) {
  bool any(bool Function(RenderObject) test) => recording.nodes.any((RecordedNode n) => test(n.renderObject));
  return <String>[
    if (SnapshotFonts.usingTestFont)
      'text: the FlutterTest font draws glyphs as boxes, and icon fonts are not loaded, so glyph shape, font '
          'weight and which icon is drawn are not in the pixels; the recorded text and code points are. Wrapping, '
          'truncation and overflow follow the test font\'s metrics',
    if (debugDisableShadows) 'shadows: flutter_test sets debugDisableShadows, so shadow blur is not drawn',
    if (any((RenderObject r) => r is RenderSliverMultiBoxAdaptor))
      'unbuilt: list items outside the viewport are not built and not in this snapshot',
    if (any((RenderObject r) => r is TextureBox || r is PlatformViewRenderBox))
      'platform views and textures: their pixels do not exist in a widget test; bounds only',
  ];
}

/// Builds each component's paint text from the per-render-object recording.
///
/// Commands of framework render objects go to the nearest component above
/// them. A child component leaves a marker naming it, in paint order; its
/// position is its bounds. Paint a component reaches through another place in
/// the render tree (an overlay entry, for example) is an extra entry with its
/// global transform.
class _PaintAssembly {
  _PaintAssembly(this.tree);

  final ComponentTree tree;
  final Map<Component, StringBuffer> _text = <Component, StringBuffer>{};
  final Map<Component, Set<String>> opaque = <Component, Set<String>>{};
  final Map<Component, List<RecordedNode>> renderObjects = <Component, List<RecordedNode>>{};

  /// Where each component's paint starts, in paint order, with the component
  /// whose paint reached it (null for the root).
  final Map<Component, List<(RecordedNode, Component?)>> entries = <Component, List<(RecordedNode, Component?)>>{};

  String text(Component comp) => _text[comp]?.toString() ?? '';

  void run(PaintRecording recording) => _entry(recording.root, null);

  void _entry(RecordedNode node, Component? from) {
    final Component comp = tree.ownerOfRenderObject(node.renderObject);
    (entries[comp] ??= <(RecordedNode, Component?)>[]).add((node, from));
    final StringBuffer out = _text.putIfAbsent(comp, StringBuffer.new);
    final bool primary = comp.parent == null || identical(node.renderObject, comp.renderObject);
    if (!primary || !node.geometryVerified) {
      out.write('entry(${c.float64s(node.toGlobal.storage)})');
    }
    _segment(node, comp, out);
  }

  void _segment(RecordedNode node, Component comp, StringBuffer out) {
    (renderObjects[comp] ??= <RecordedNode>[]).add(node);
    if (node.isOpaque) {
      (opaque[comp] ??= <String>{}).addAll(node.opaque.keys.map((r) => r.name));
    }
    out.write('{');
    var k = 0;
    for (final String op in node.ops) {
      if (op != 'child') {
        out
          ..write(op)
          ..write('\n');
        continue;
      }
      RecordedNode child = node.children[k];
      final Offset offset = node.childOffsets[k];
      k++;
      // A render object of this component that draws nothing and holds one
      // child at its own origin (a repaint boundary, a size box) leaves no
      // trace in the paint, so wrapping in a layout-neutral widget does not
      // change it (A5).
      while (identical(tree.ownerOfRenderObject(child.renderObject), comp) && _passThrough(child)) {
        (renderObjects[comp] ??= <RecordedNode>[]).add(child);
        child = child.children.single;
      }
      final Component owner = tree.ownerOfRenderObject(child.renderObject);
      if (identical(owner, comp)) {
        out.write('child${c.offset(offset)}');
        _segment(child, comp, out);
        continue;
      }
      final Component? via = comp.childToward(owner);
      final bool primary = identical(child.renderObject, owner.renderObject);
      out
        // A child component is named by its index among this component's
        // children, not its id, so an id change alone leaves this paint as it
        // was (spec: Identity is info only).
        ..write(via == null ? 'foreign(${jsonEncode(owner.fullId)})' : 'comp(${comp.children.indexOf(via)})')
        ..write(primary && child.geometryVerified ? '' : c.offset(offset))
        ..write('\n');
      _entry(child, comp);
    }
    out.write('}');
  }
}

/// The flattened output of [comp]'s subtree (spec: Node fields, `flat`).
///
/// The paint is written as if the subtree were one component: a child
/// component's commands appear where its marker would, after the paint offset
/// that places it, and a render object that only passes its one child through
/// is left out whichever component built it. Paint that a component outside
/// the subtree draws in the middle is a `foreign` marker. A component of the
/// subtree whose paint starts outside it, such as an overlay entry, follows
/// with its global transform. The semantics are the subtree's nodes in
/// semantics tree order, whichever component owns each one.
String _flat(Component comp, _PaintAssembly assembly, _Semantics semantics) {
  final inside = <Component>{};
  void collect(Component member) {
    inside.add(member);
    member.children.forEach(collect);
  }

  collect(comp);
  final ComponentTree tree = assembly.tree;
  final out = StringBuffer();
  void segment(RecordedNode node) {
    out.write('{');
    var k = 0;
    for (final String op in node.ops) {
      if (op != 'child') {
        out
          ..write(op)
          ..write('\n');
        continue;
      }
      RecordedNode child = node.children[k];
      final Offset offset = node.childOffsets[k];
      k++;
      while (inside.contains(tree.ownerOfRenderObject(child.renderObject)) && _passThrough(child)) {
        child = child.children.single;
      }
      if (inside.contains(tree.ownerOfRenderObject(child.renderObject))) {
        out.write('child${c.offset(offset)}');
        segment(child);
      } else {
        out
          ..write('foreign${c.offset(offset)}')
          ..write('\n');
      }
    }
    out.write('}');
  }

  void visit(Component member) {
    for (final (RecordedNode node, Component? from)
        in assembly.entries[member] ?? const <(RecordedNode, Component?)>[]) {
      if (from != null && inside.contains(from)) {
        continue; // Written in place by its parent's segment.
      }
      final bool primary = member.parent == null || identical(node.renderObject, member.renderObject);
      if (!identical(member, comp) || !primary || !node.geometryVerified) {
        out.write('entry(${c.float64s(node.toGlobal.storage)})');
      }
      segment(node);
    }
    member.children.forEach(visit);
  }

  visit(comp);
  final List<Map<String, Object?>> nodes = <Map<String, Object?>>[
    for (final (Component owner, Map<String, Object?> node) in semantics.ordered)
      if (inside.contains(owner)) node,
  ];
  return sha256.convert(utf8.encode('$out\n${jsonEncode(nodes)}')).toString();
}

bool _passThrough(RecordedNode node) =>
    node.ops.length == 1 &&
    node.ops.single == 'child' &&
    node.children.length == 1 &&
    node.childOffsets.single == Offset.zero &&
    !node.isOpaque;

/// Every semantics node in the tree, grouped by the component that owns the
/// render object that created it. A node merged into its parent is described
/// by the parent's data instead.
///
/// Some nodes belong to no render object: a paragraph builds one child node
/// per text span with a recognizer. Those are described with the node whose
/// render object built them.
class _Semantics {
  final Map<Component, List<Map<String, Object?>>> byComponent = <Component, List<Map<String, Object?>>>{};

  /// Every node with its owner, in the order the render tree is walked.
  final List<(Component, Map<String, Object?>)> ordered = <(Component, Map<String, Object?>)>[];

  void add(Component owner, Map<String, Object?> node) {
    (byComponent[owner] ??= <Map<String, Object?>>[]).add(node);
    ordered.add((owner, node));
  }
}

_Semantics _semanticsByComponent(RenderView view, ComponentTree tree) {
  final owned = <SemanticsNode, RenderObject>{};
  void collect(RenderObject ro) {
    final SemanticsNode? node = ro.debugSemantics;
    if (node != null) {
      owned.putIfAbsent(node, () => ro);
    }
    ro.visitChildren(collect);
  }

  collect(view);
  final out = _Semantics();
  final seen = <SemanticsNode>{};
  void visit(RenderObject ro) {
    final SemanticsNode? node = ro.debugSemantics;
    if (node != null && owned[node] == ro && node.attached && !node.isMergedIntoParent && seen.add(node)) {
      final Component owner = _semanticsOwner(ro, node, tree);
      out.add(owner, _describeSemantics(node));
      void unowned(SemanticsNode parent) {
        parent.visitChildren((SemanticsNode child) {
          if (!owned.containsKey(child) && !child.isMergedIntoParent && seen.add(child)) {
            out.add(owner, _describeSemantics(child));
            unowned(child);
          }
          return true;
        });
      }

      unowned(node);
    }
    ro.visitChildren(visit);
  }

  visit(view);
  return out;
}

/// The component a semantics node belongs to: the nearest component that
/// contains every render object contributing content to it.
///
/// A node is formed at a boundary render object, which is often a framework
/// wrapper above the component that supplied its label (a list item's
/// IndexedSemantics, for example). Attributing the node to the boundary's
/// component would name the screen instead of the item (A6).
Component _semanticsOwner(RenderObject boundary, SemanticsNode node, ComponentTree tree) {
  final contributors = <Component>{};
  if (_contributesContent(boundary)) {
    contributors.add(tree.ownerOfRenderObject(boundary));
  }
  void visit(RenderObject ro) {
    final SemanticsNode? own = ro.debugSemantics;
    if (own != null && own != node && own.attached && !own.isMergedIntoParent) {
      return; // A node of its own.
    }
    if (_contributesContent(ro)) {
      contributors.add(tree.ownerOfRenderObject(ro));
    }
    ro.visitChildrenForSemantics(visit);
  }

  boundary.visitChildrenForSemantics(visit);
  if (contributors.isEmpty) {
    return tree.ownerOfRenderObject(boundary);
  }
  return contributors.reduce(_commonAncestor);
}

Component _commonAncestor(Component a, Component b) {
  final ancestors = <Component>{};
  for (Component? c = a; c != null; c = c.parent) {
    ancestors.add(c);
  }
  for (Component? c = b; c != null; c = c.parent) {
    if (ancestors.contains(c)) {
      return c;
    }
  }
  return b;
}

/// Whether [ro] adds content to the semantics tree: text, a role, a flag
/// or an action. Structure alone (a boundary, an index among scrolled
/// children, a sort key, a text direction) is not content.
bool _contributesContent(RenderObject ro) {
  final config = SemanticsConfiguration();
  // ignore: invalid_use_of_protected_member
  ro.describeSemanticsConfiguration(config);
  if (!config.hasBeenAnnotated) {
    return false;
  }
  return config.label.isNotEmpty ||
      config.value.isNotEmpty ||
      config.increasedValue.isNotEmpty ||
      config.decreasedValue.isNotEmpty ||
      config.hint.isNotEmpty ||
      config.tooltip.isNotEmpty ||
      config.identifier.isNotEmpty ||
      config.role != SemanticsRole.none ||
      config.isButton ||
      config.isLink ||
      config.isHeader ||
      config.isImage ||
      config.isSlider ||
      config.isKeyboardKey ||
      config.isHidden ||
      config.isTextField ||
      config.isReadOnly ||
      config.isObscured ||
      config.isMultiline ||
      config.isSelected ||
      config.liveRegion ||
      config.scopesRoute ||
      config.namesRoute ||
      config.isInMutuallyExclusiveGroup ||
      config.hasImplicitScrolling ||
      config.isExpanded != null ||
      config.isEnabled != null ||
      config.isChecked != null ||
      config.isToggled != null ||
      config.isFocused != null ||
      config.isRequired != null ||
      config.maxValue != null ||
      config.minValue != null ||
      config.linkUrl != null ||
      config.textSelection != null ||
      config.platformViewId != null ||
      config.scrollPosition != null ||
      config.customSemanticsActions.isNotEmpty ||
      config.onTap != null ||
      config.onLongPress != null ||
      config.onScrollLeft != null ||
      config.onScrollRight != null ||
      config.onScrollUp != null ||
      config.onScrollDown != null ||
      config.onScrollToOffset != null ||
      config.onIncrease != null ||
      config.onDecrease != null ||
      config.onCopy != null ||
      config.onCut != null ||
      config.onPaste != null ||
      config.onDismiss != null ||
      config.onSetText != null ||
      config.onSetSelection != null ||
      config.onFocus != null ||
      config.onExpand != null ||
      config.onCollapse != null;
}

Map<String, Object?> _describeSemantics(SemanticsNode node) {
  final SemanticsData d = node.getSemanticsData();
  final out = <String, Object?>{'rect': c.rect(d.rect)};
  void put(String key, Object? value) {
    if (value == null || value == '' || (value is List && value.isEmpty)) {
      return;
    }
    out[key] = value;
  }

  String? attributed(AttributedString s) {
    if (s.string.isEmpty && s.attributes.isEmpty) {
      return null;
    }
    return s.attributes.isEmpty ? s.string : '${s.string} ${s.attributes.map((a) => a.toString()).join(',')}';
  }

  put('transform', d.transform == null ? null : c.float64s(d.transform!.storage));
  put('label', attributed(d.attributedLabel));
  put('value', attributed(d.attributedValue));
  put('increasedValue', attributed(d.attributedIncreasedValue));
  put('decreasedValue', attributed(d.attributedDecreasedValue));
  put('hint', attributed(d.attributedHint));
  put('tooltip', d.tooltip);
  put('identifier', d.identifier);
  put('role', d.role == SemanticsRole.none ? null : d.role.name);
  put('flags', d.flagsCollection.toStrings());
  put('actions', <String>[
    for (final SemanticsAction a in SemanticsAction.values)
      if ((d.actions & a.index) != 0) a.name,
  ]);
  // By label, or by the action whose hint it overrides: the action's id is a
  // counter that depends on what the test built before.
  put('customActions', <String>[
    for (final int id in d.customSemanticsActionIds ?? const <int>[])
      if (CustomSemanticsAction.getAction(id) case final CustomSemanticsAction a)
        a.label ?? 'hint ${a.action?.name}: ${a.hint}',
  ]);
  put('textDirection', d.textDirection?.name);
  put('textSelection', d.textSelection == null ? null : '${d.textSelection!.start},${d.textSelection!.end}');
  put('headingLevel', d.headingLevel == 0 ? null : d.headingLevel);
  put('maxValueLength', d.maxValueLength);
  put('currentValueLength', d.currentValueLength);
  put('scrollChildCount', d.scrollChildCount);
  put('scrollIndex', d.scrollIndex);
  put('scrollPosition', d.scrollPosition == null ? null : c.d(d.scrollPosition!));
  put('scrollExtentMin', d.scrollExtentMin == null ? null : c.d(d.scrollExtentMin!));
  put('scrollExtentMax', d.scrollExtentMax == null ? null : c.d(d.scrollExtentMax!));
  put('platformViewId', d.platformViewId);
  put('linkUrl', d.linkUrl?.toString());
  put('validationResult', d.validationResult == SemanticsValidationResult.none ? null : d.validationResult.name);
  put('inputType', d.inputType == ui.SemanticsInputType.none ? null : d.inputType.name);
  put('locale', d.locale?.toLanguageTag());
  put('minValue', d.minValue);
  put('maxValue', d.maxValue);
  put('controls', d.controlsNodes == null ? null : (d.controlsNodes!.toList()..sort()));
  put('tags', d.tags == null ? null : (d.tags!.map((t) => t.name).toList()..sort()));
  // Reading order follows from the rects and text direction above, plus sort
  // keys and traversal links.
  put('sortKey', _sortKey(node.sortKey));
  put('traversalParentIdentifier', node.traversalParentIdentifier?.toString());
  put('traversalChildIdentifier', node.traversalChildIdentifier?.toString());
  return out;
}

String? _sortKey(SemanticsSortKey? key) => switch (key) {
  null => null,
  OrdinalSortKey(:final String? name, :final double order) => 'ordinal${name == null ? '' : ' $name'} ${c.d(order)}',
  _ => '${key.runtimeType}${key.name == null ? '' : ' ${key.name}'}',
};

const Set<String> _styleSkip = <String>{
  'creator',
  'parentData',
  'constraints',
  'size',
  // A sliver's size: an output of layout, like `size`.
  'geometry',
  'layer',
  'semantic boundary',
  'needs compositing',
  'needsCompositing',
  'metrics',
  'diagnosis',
  'configuration',
  'isSemanticBoundary',
  'paintBounds',
  'semanticBounds',
  'debugNeedsLayout',
  'debugNeedsPaint',
  // Recorded in the semantics field.
  'semantics node',
};

final RegExp _notStyle = RegExp('Semantics|MouseRegion|Pointer|MetaData');

bool _drawsSomething(String op) =>
    op.startsWith('draw') ||
    op.startsWith('clip') ||
    op.startsWith('push') ||
    op.startsWith('saveLayer') ||
    op.startsWith('composite') ||
    op.startsWith('addLayer');

final RegExp _identity = RegExp(r'#[0-9a-f]{5}\b');

/// Explanation field `style`: diagnostics properties of the render objects
/// that drew this component's paint. Never hashed.
///
/// A property whose value is itself diagnosticable, such as a decoration, is
/// expanded one level (`RenderDecoratedBox.decoration.color`), and text is
/// described by its spans' styles (`RenderParagraph.text.style.fontWeight`),
/// so a change names the property that changed. The widget that created each
/// render object is described the same way. Text content is not style; it is
/// recorded under content keys (`RenderParagraph.plainText`, `Text.data`) that
/// the diff reads as content.
Map<String, String> _style(List<RecordedNode> nodes, TokenResolver? resolver, Element? component) {
  final out = <String, String>{};
  String describe(DiagnosticsNode p) {
    String text = p.toDescription().replaceAll(_identity, '#');
    if (text.length > 240) {
      text = '${text.substring(0, 240)}…';
    }
    final Object? value = p.value;
    final String? token = value == null || resolver == null ? null : resolver(value);
    return token == null ? text : '$token ($text)';
  }

  void put(String key, String value) {
    var k = key;
    for (var n = 2; out.containsKey(k); n++) {
      k = '$key.$n';
    }
    out[k] = value;
  }

  bool shown(DiagnosticsNode p) {
    final String? name = p.name;
    return name != null &&
        name.isNotEmpty &&
        !_styleSkip.contains(name) &&
        !p.isFiltered(DiagnosticLevel.info) &&
        // A child widget's description includes its text; children are
        // described by their own render objects.
        p.value is! Widget &&
        p.value is! List<Widget> &&
        // A scroll position describes the viewport's size, which is layout,
        // and a child delegate describes the children, which are compared as
        // components.
        p.value is! ViewportOffset &&
        p.value is! SliverChildDelegate;
  }

  final described = <Element>{};
  for (final node in nodes) {
    final RenderObject ro = node.renderObject;
    final String type = ro.runtimeType.toString();
    // Semantics and pointer handling are recorded elsewhere or not drawn.
    // Every other render object is described. Those that only place their
    // children (`layout.RenderPadding.padding`) explain layout, since a
    // child's offset is part of this component's paint.
    if (_notStyle.hasMatch(type)) {
      continue;
    }
    final String prefix = node.ops.any(_drawsSomething) ? '' : layoutStylePrefix;
    void properties(String type, Diagnosticable of) {
      for (final DiagnosticsNode p in of.toDiagnosticsNode().getProperties()) {
        if (!shown(p)) {
          continue;
        }
        final String key = '$type.${p.name}';
        put(key, describe(p));
        final Object? value = p.value;
        if (value is Diagnosticable && value is! RenderObject && value is! Widget) {
          for (final DiagnosticsNode q in value.toDiagnosticsNode().getProperties()) {
            if (shown(q) && q.value != null) {
              put('$key.${q.name}', describe(q));
            }
          }
        }
      }
    }

    properties('$prefix$type', ro);
    // Some render objects report none of their paint parameters (the
    // private one behind ColoredBox has no diagnostics), so the widget that
    // created the render object is described too (`ColoredBox.color`).
    // The framework widgets between the component and this render object are
    // described too, once each: a state such as `Switch.value` is often held
    // by a widget whose render object does not report it.
    final Object? creator = ro.debugCreator;
    if (creator is DebugCreator) {
      void describeWidget(Element e, String prefix) {
        if (!described.add(e)) {
          return;
        }
        final String name = e.widget.runtimeType.toString().split('<').first;
        if (!_notStyle.hasMatch(name)) {
          properties('$prefix$name', e.widget);
        }
      }

      describeWidget(creator.element, prefix);
      creator.element.visitAncestorElements((Element e) {
        if (identical(e, component)) {
          return false;
        }
        // A render object widget is described with its own render object,
        // when that is drawn by this component.
        if (e.widget is! RenderObjectWidget) {
          describeWidget(e, e.widget is ParentDataWidget ? layoutStylePrefix : '');
        }
        return true;
      });
    }
    if (node.imageFingerprints.isNotEmpty) {
      // Content, not style: the diff reads this key as content.
      put('$type.images', node.imageFingerprints.join(','));
    }
    final InlineSpan? text = switch (ro) {
      RenderParagraph() => ro.text,
      RenderEditable() => ro.text,
      _ => null,
    };
    if (text != null) {
      // Content, not style: the diff reads this key as content.
      put('$type.plainText', jsonEncode(text.toPlainText()));
    }
    text?.visitChildren((InlineSpan span) {
      final TextStyle? style = span.style;
      if (style != null) {
        for (final DiagnosticsNode q in style.toDiagnosticsNode().getProperties()) {
          if (shown(q) && q.value != null) {
            put('$type.text.style.${q.name}', describe(q));
          }
        }
      }
      return true;
    });
  }
  return out;
}
