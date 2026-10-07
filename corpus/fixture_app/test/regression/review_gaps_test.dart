// Regression cases from the Phase 0 review (doc/assumption_register.md,
// "Phase 0 review"). The cases in main, more and mixed were each a capture
// gap: two trees whose recordings hashed equal while their pixels differed.
// The cases in placement guard how far an opaque node's pixel hash reaches;
// the image filter one is a gap if spread is not tracked. Every pair must
// hash differently, and every pair must still change pixels.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

class Cap {
  Cap(this.hash, this.pixels, this.recording);
  final String hash;
  final PixelRegion pixels;
  final PaintRecording recording;
}

Future<Cap> cap(WidgetTester tester, Widget w, {double dpr = 3.0}) async {
  tester.view.physicalSize = const Size(300, 300) * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(w);
  await tester.pumpAndSettle();
  final RenderView view = tester.binding.renderViews.first;
  final double r = view.flutterView.devicePixelRatio;
  final PixelRegion full = (await tester.runAsync(() => rasterize(view, Offset.zero & view.size)))!;
  final PaintRecording rec = PaintRecorder.record(view);
  await tester.runAsync(() => rec.resolve(pixelHash: (Rect rr) async => full.crop(rr, r).hash));
  PaintRecorder.restore(rec);
  await tester.pump();
  for (final RecordedNode n in rec.nodes) {
    expect(n.geometryVerified, isTrue, reason: '${n.renderObject.runtimeType} transform not verified');
  }
  return Cap(rec.root.subtreeHash, full, rec);
}

/// Captures [a] and [b] and fails on a capture gap. Returns whether the
/// pixels differed, so a case can also check it still exercises a change.
Future<bool> compare(WidgetTester tester, Widget a, Widget b, {double dprB = 3.0}) async {
  final Cap ca = await cap(tester, a);
  final Cap cb = await cap(tester, b, dpr: dprB);
  final bool samePixels = ca.pixels.sameAs(cb.pixels);
  if (!samePixels) {
    expect(
      cb.hash,
      isNot(ca.hash),
      reason: 'capture gap: equal hashes, ${ca.pixels.differingPixels(cb.pixels)} pixels differ',
    );
  }
  return !samePixels;
}

Future<void> expectCaught(WidgetTester tester, Widget a, Widget b, {double dprB = 3.0}) async {
  expect(await compare(tester, a, b, dprB: dprB), isTrue, reason: 'the case no longer changes pixels');
}

Widget ltr(Widget child, {TextDirection dir = TextDirection.ltr}) => Directionality(
  textDirection: dir,
  child: ColoredBox(color: const Color(0xFFFFFFFF), child: child),
);

Widget gradBox(TextDirection dir) => ltr(
  dir: dir,
  const Center(
    child: SizedBox(
      width: 120,
      height: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: <Color>[Color(0xFFFF0000), Color(0xFF0000FF)],
          ),
        ),
      ),
    ),
  ),
);

/// A ShapeBorder that strokes its outline with its own gradient.
class GradientOutline extends ShapeBorder {
  const GradientOutline(this.colors);
  final List<Color> colors;
  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(6);
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path()..addRect(rect.deflate(6));
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRect(rect);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    canvas.drawRect(
      rect.deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..shader = LinearGradient(colors: colors).createShader(rect),
    );
  }

  @override
  ShapeBorder scale(double t) => this;
}

Widget shapeBox(List<Color> borderColors) => ltr(
  Center(
    child: SizedBox(
      width: 120,
      height: 60,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          gradient: const LinearGradient(colors: <Color>[Color(0xFFFFFF00), Color(0xFF00FFFF)]),
          shape: GradientOutline(borderColors),
        ),
      ),
    ),
  ),
);

class PathPainter extends CustomPainter {
  PathPainter(this.build, {this.stroke = false});
  final Path Function() build;
  final bool stroke;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      build(),
      Paint()
        ..color = const Color(0xFF000000)
        ..style = stroke ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(PathPainter old) => true;
}

/// Square with a V notch in its top edge; apex at x0 + a, the notch spans 20.
Path notch(double a) => Path()
  ..moveTo(0, 0)
  ..lineTo(60, 0)
  ..lineTo(60 + a, 8)
  ..lineTo(70, 0)
  ..lineTo(200, 0)
  ..lineTo(200, 200)
  ..lineTo(0, 200)
  ..close();

/// A stroked frame plus a zero-length contour (a round-cap dot) at [dot].
Path dotted(Offset dot) => Path()
  ..addRect(const Rect.fromLTWH(10, 10, 180, 180))
  ..moveTo(dot.dx, dot.dy)
  ..lineTo(dot.dx, dot.dy);

Widget painted(CustomPainter p, {Size size = const Size(200, 200)}) => ltr(
  Align(
    alignment: Alignment.topLeft,
    child: CustomPaint(size: size, painter: p),
  ),
);

class OutsidePainter extends CustomPainter {
  OutsidePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    // A gradient makes the node opaque; it draws well outside its 40x40 size.
    canvas.drawCircle(
      const Offset(150, 100),
      40,
      Paint()
        ..shader = ui.Gradient.linear(const Offset(110, 0), const Offset(190, 0), <Color>[
          color,
          const Color(0xFF0000FF),
        ]),
    );
  }

  @override
  bool shouldRepaint(OutsidePainter old) => true;
}

void main() {
  more();
  mixed();
  placement();
  testWidgets('directional gradient under LTR vs RTL', (WidgetTester t) async {
    await expectCaught(t, gradBox(TextDirection.ltr), gradBox(TextDirection.rtl));
  });

  testWidgets('second gradient misdescribed as the decoration gradient', (WidgetTester t) async {
    await expectCaught(
      t,
      shapeBox(const <Color>[Color(0xFFFF0000), Color(0xFF00FF00)]),
      shapeBox(const <Color>[Color(0xFF000000), Color(0xFFFFFFFF)]),
    );
  });

  testWidgets('path: mirrored notch between samples', (WidgetTester t) async {
    await expectCaught(t, painted(PathPainter(() => notch(2))), painted(PathPainter(() => notch(8))));
  });

  testWidgets('path: zero-length contour dot moved', (WidgetTester t) async {
    await expectCaught(
      t,
      painted(PathPainter(() => dotted(const Offset(60, 60)), stroke: true)),
      painted(PathPainter(() => dotted(const Offset(120, 140)), stroke: true)),
    );
  });

  testWidgets('opaque node draws outside its paint bounds', (WidgetTester t) async {
    await expectCaught(
      t,
      painted(OutsidePainter(const Color(0xFFFF0000)), size: const Size(40, 40)),
      painted(OutsidePainter(const Color(0xFF00FF00)), size: const Size(40, 40)),
    );
  });
}

final LayerLink linkA = LayerLink();
final LayerLink linkB = LayerLink();

Widget followers(bool toB) => ltr(
  Stack(
    children: <Widget>[
      Positioned(
        left: 20,
        top: 20,
        child: CompositedTransformTarget(link: linkA, child: const SizedBox(width: 40, height: 40)),
      ),
      Positioned(
        left: 180,
        top: 200,
        child: CompositedTransformTarget(link: linkB, child: const SizedBox(width: 40, height: 40)),
      ),
      Positioned(
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: toB ? linkB : linkA,
          child: const SizedBox(width: 30, height: 30, child: ColoredBox(color: Color(0xFFFF0000))),
        ),
      ),
    ],
  ),
);

Widget backdrop(double sigma) => ltr(
  Stack(
    children: <Widget>[
      const Positioned(left: 20, top: 20, width: 60, height: 60, child: ColoredBox(color: Color(0xFF0000FF))),
      Positioned(
        left: 220,
        top: 220,
        child: BackdropFilter(
          // A blur with bounds prints a fixed-decimal Rect, so it is opaque.
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, bounds: const Rect.fromLTWH(0, 0, 300, 300)),
          child: const SizedBox(width: 20, height: 20),
        ),
      ),
    ],
  ),
);

Widget backdropCompose(double sigma) => ltr(
  Stack(
    children: <Widget>[
      const Positioned(left: 20, top: 20, width: 60, height: 60, child: ColoredBox(color: Color(0xFF0000FF))),
      Positioned(
        left: 220,
        top: 220,
        child: BackdropFilter(
          filter: ui.ImageFilter.compose(
            outer: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            inner: const ColorFilter.mode(Color(0x10FF0000), BlendMode.srcOver),
          ),
          child: const SizedBox(width: 20, height: 20),
        ),
      ),
    ],
  ),
);

Widget dprBox() => ltr(
  const Center(
    child: SizedBox(width: 50, height: 50, child: ColoredBox(color: Color(0xFF00FF00))),
  ),
);

void more() {
  testWidgets('follower linked to a different leader', (WidgetTester t) async {
    await expectCaught(t, followers(false), followers(true));
  });
  testWidgets('opaque backdrop filter affects pixels outside its bounds', (WidgetTester t) async {
    await expectCaught(t, backdrop(2), backdrop(6));
  });
  testWidgets('opaque backdrop compose outside its bounds', (WidgetTester t) async {
    await expectCaught(t, backdropCompose(2), backdropCompose(6));
  });
  testWidgets('device pixel ratio', (WidgetTester t) async {
    await expectCaught(t, dprBox(), dprBox(), dprB: 2.0);
  });
}

Widget mixedGrad(double x) => ltr(
  Center(
    child: SizedBox(
      width: 200,
      height: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(x, 0).add(const AlignmentDirectional(-0.5, 0)),
            end: Alignment.centerRight,
            colors: const <Color>[Color(0xFFFF0000), Color(0xFF0000FF)],
          ),
        ),
      ),
    ),
  ),
);

void mixed() {
  testWidgets('mixed alignment prints one decimal', (WidgetTester t) async {
    await expectCaught(t, mixedGrad(-0.21), mixedGrad(-0.24));
  });
}

/// Fills its size with a gradient, which makes its node opaque.
class GradientFill extends CustomPainter {
  GradientFill(this.color, {this.layerFilter});
  final Color color;
  final ColorFilter? layerFilter;
  @override
  void paint(Canvas canvas, Size size) {
    if (layerFilter != null) {
      canvas.saveLayer(null, Paint()..colorFilter = layerFilter);
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, 0), <Color>[color, const Color(0xFF0000FF)]),
    );
    if (layerFilter != null) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(GradientFill old) => true;
}

Widget placed(Widget child, {double left = 200, double top = 200}) => ltr(
  Stack(
    children: <Widget>[Positioned(left: left, top: top, child: child)],
  ),
);

void placement() {
  testWidgets('opaque node away from the origin is hashed where it paints', (WidgetTester t) async {
    Widget box(Color color) => placed(CustomPaint(size: const Size(40, 40), painter: GradientFill(color)));
    await expectCaught(t, box(const Color(0xFFFF0000)), box(const Color(0xFF00FF00)));
  });

  testWidgets('image filter moves an opaque node out of its inner clip', (WidgetTester t) async {
    Widget moved(Color color) => placed(
      left: 20,
      top: 20,
      ImageFiltered(
        imageFilter: ui.ImageFilter.matrix(Matrix4.translationValues(150, 150, 0).storage),
        child: ClipRect(
          child: CustomPaint(size: const Size(40, 40), painter: GradientFill(color)),
        ),
      ),
    );
    await expectCaught(t, moved(const Color(0xFFFF0000)), moved(const Color(0xFF00FF00)));
  });

  testWidgets('a colour-filtered layer fills beyond what was drawn', (WidgetTester t) async {
    Widget filtered(Color tint) => placed(
      CustomPaint(
        size: const Size(40, 40),
        painter: GradientFill(const Color(0xFFFF0000), layerFilter: ColorFilter.mode(tint, BlendMode.srcOver)),
      ),
    );
    // The tint is not an 8-bit colour, so the filter is opaque and the node is
    // pixel-hashed. The filter tints the whole clip, not just the 40x40 rect.
    await expectCaught(
      t,
      filtered(Color.from(alpha: 0.06, red: 1, green: 0, blue: 0)),
      filtered(Color.from(alpha: 0.07, red: 1, green: 0, blue: 0)),
    );
  });

  testWidgets('an opaque node under a backdrop blur', (WidgetTester t) async {
    Widget under(Color color) => ltr(
      Stack(
        children: <Widget>[
          Positioned(
            left: 100,
            top: 100,
            child: CustomPaint(size: const Size(20, 20), painter: GradientFill(color)),
          ),
          Positioned(
            left: 0,
            top: 0,
            width: 300,
            height: 300,
            child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: const SizedBox.expand()),
          ),
        ],
      ),
    );
    await expectCaught(t, under(const Color(0xFFFF0000)), under(const Color(0xFF00FF00)));
  });
}
