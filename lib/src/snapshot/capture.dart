// The capture pipeline (spec: Flutter capture, Capture steps).
//
// Settle, select components, record geometry and paint, read semantics and
// style, then hash bottom-up and return the snapshot.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
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
  const SnapshotOptions({this.policy, this.state, this.theme, this.tokenResolver, this.atPumpedTime = false});

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

  SnapshotOptions _atPumpedTime() =>
      SnapshotOptions(policy: policy, state: state, theme: theme, tokenResolver: tokenResolver, atPumpedTime: true);
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
  final List<Element> pending = _pendingImages(tester);
  if (pending.isNotEmpty) {
    throw CaptureFailure(
      'an image is not decoded: ${pending.map((Element e) => (e.widget as Image).image).join(', ')}. Precache it '
      'before capture (precacheImages, or precacheImage inside tester.runAsync, then pump).',
      difference: await _diagnoseImages(tester, id, options, pending),
    );
  }
  return _capture(tester, id, options);
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
  List<Element> pending,
) async {
  final Capture capture = await _capture(tester, id, options._atPumpedTime());
  final kept = capture.tree.all.toSet();
  String owner(Element e) {
    // A component that paints nothing but the placeholder may be pruned.
    Component c = capture.tree.ownerOfRenderObject(e.findRenderObject()!);
    while (!kept.contains(c) && c.parent != null) {
      c = c.parent!;
    }
    return c.fullId;
  }

  final List<String> owners = <String>{for (final Element e in pending) owner(e)}.toList();
  return SnapshotDifference(
    owners.first,
    const <String>['paint'],
    'an image load: ${(pending.first.widget as Image).image} is not decoded yet, so its placeholder would be '
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
    final Map<Component, List<Map<String, Object?>>> semantics = _semanticsByComponent(view, tree);
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
        type: comp.element == null ? 'root' : policy.typeOf(comp.element!.widget),
        style: jsonEncode(_style(assembly.renderObjects[comp] ?? const <RecordedNode>[], options.tokenResolver)),
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

/// Images must be decoded before capture; a pending load would record a
/// placeholder. Returns the `Image` elements still waiting.
List<Element> _pendingImages(WidgetTester tester) {
  final pending = <Element>[];
  for (final Element e in find.byType(Image, skipOffstage: true).evaluate()) {
    var hasImage = false;
    var raw = false;
    void visit(Element child) {
      if (child.widget is RawImage) {
        raw = true;
        hasImage = hasImage || (child.widget as RawImage).image != null;
        return;
      }
      child.visitChildren(visit);
    }

    e.visitChildren(visit);
    if (!raw || !hasImage) {
      pending.add(e);
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

  String text(Component comp) => _text[comp]?.toString() ?? '';

  void run(PaintRecording recording) => _entry(recording.root);

  void _entry(RecordedNode node) {
    final Component comp = tree.ownerOfRenderObject(node.renderObject);
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
      final RecordedNode child = node.children[k];
      final Offset offset = node.childOffsets[k];
      k++;
      final Component owner = tree.ownerOfRenderObject(child.renderObject);
      if (identical(owner, comp)) {
        out.write('child${c.offset(offset)}');
        _segment(child, comp, out);
        continue;
      }
      final Component? via = comp.childToward(owner);
      final bool primary = identical(child.renderObject, owner.renderObject);
      out
        ..write(via == null ? 'foreign(${jsonEncode(owner.fullId)})' : 'comp(${jsonEncode(via.segment)})')
        ..write(primary && child.geometryVerified ? '' : c.offset(offset))
        ..write('\n');
      _entry(child);
    }
    out.write('}');
  }
}

/// Every semantics node in the tree, grouped by the component that owns the
/// render object that created it. A node merged into its parent is described
/// by the parent's data instead.
Map<Component, List<Map<String, Object?>>> _semanticsByComponent(RenderView view, ComponentTree tree) {
  final out = <Component, List<Map<String, Object?>>>{};
  final seen = <SemanticsNode>{};
  void visit(RenderObject ro) {
    final SemanticsNode? node = ro.debugSemantics;
    if (node != null && node.attached && !node.isMergedIntoParent && seen.add(node)) {
      (out[_semanticsOwner(ro, node, tree)] ??= <Map<String, Object?>>[]).add(_describeSemantics(node));
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
  put('customActions', <String>[
    for (final int id in d.customSemanticsActionIds ?? const <int>[])
      CustomSemanticsAction.getAction(id)?.label ?? CustomSemanticsAction.getAction(id).toString(),
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
  return out;
}

const Set<String> _styleSkip = <String>{
  'creator',
  'parentData',
  'constraints',
  'size',
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
};

bool _drawsSomething(String op) =>
    op.startsWith('draw') || op.startsWith('clip') || op.startsWith('push') || op.startsWith('saveLayer');

final RegExp _identity = RegExp(r'#[0-9a-f]{5}\b');

/// Explanation field `style`: diagnostics properties of the render objects
/// that drew this component's paint. Never hashed.
Map<String, String> _style(List<RecordedNode> nodes, TokenResolver? resolver) {
  final out = <String, String>{};
  for (final node in nodes) {
    // Only render objects that drew something carry visual properties.
    if (!node.ops.any(_drawsSomething)) {
      continue;
    }
    final RenderObject ro = node.renderObject;
    final String type = ro.runtimeType.toString();
    for (final DiagnosticsNode p in ro.toDiagnosticsNode().getProperties()) {
      final String? name = p.name;
      if (name == null || name.isEmpty || _styleSkip.contains(name) || p.isFiltered(DiagnosticLevel.info)) {
        continue;
      }
      String text = p.toDescription().replaceAll(_identity, '#');
      if (text.length > 240) {
        text = '${text.substring(0, 240)}…';
      }
      final Object? value = p.value;
      final String? token = value == null || resolver == null ? null : resolver(value);
      String key = '$type.$name';
      for (var n = 2; out.containsKey(key); n++) {
        key = '$type.$name.$n';
      }
      out[key] = token == null ? text : '$token ($text)';
    }
  }
  return out;
}
