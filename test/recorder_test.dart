import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/src/recorder/describe.dart';
import 'package:touchstone/touchstone.dart';

DescribeContext _ctx(RenderObject owner, List<OpaqueReason> opaque) =>
    DescribeContext(owner, (OpaqueReason r, String _) => opaque.add(r));

Future<PaintRecording> _record(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: widget));
  final RenderView view = tester.binding.renderViews.first;
  final PaintRecording recording = PaintRecorder.record(view);
  await tester.runAsync(() => recording.resolve(pixelHash: (Rect r) async => (await rasterize(view, r)).hash));
  PaintRecorder.restore(recording);
  await tester.pump();
  return recording;
}

void main() {
  group('describe', () {
    final owner = RenderDecoratedBox(decoration: const BoxDecoration());

    test('colours keep every bit', () {
      final opaque = <OpaqueReason>[];
      final String a = describePaint(Paint()..color = const Color(0xFF123456), _ctx(owner, opaque));
      final String b = describePaint(Paint()..color = const Color(0xFF123457), _ctx(owner, opaque));
      expect(a, isNot(b));
      expect(opaque, isEmpty);
    });

    test('a mask filter is described only when a rebuilt one is equal', () {
      final opaque = <OpaqueReason>[];
      final String exact = describeMaskFilter(const MaskFilter.blur(BlurStyle.normal, 2.5), _ctx(owner, opaque));
      expect(exact, 'MF.blur(normal,2.5)');
      expect(opaque, isEmpty);
      // 2.51 prints as 2.5, so the printed value cannot be trusted.
      describeMaskFilter(const MaskFilter.blur(BlurStyle.normal, 2.51), _ctx(owner, opaque));
      expect(opaque, <OpaqueReason>[OpaqueReason.unknownMaskFilter]);
    });

    test('a box shadow sigma is recovered from the decoration', () {
      const shadow = BoxShadow(blurRadius: 3);
      final shadowOwner = RenderDecoratedBox(decoration: const BoxDecoration(boxShadow: <BoxShadow>[shadow]));
      final opaque = <OpaqueReason>[];
      final Paint paint = Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurSigma);
      expect(describeMaskFilter(paint.maskFilter!, _ctx(shadowOwner, opaque)), startsWith('MF.blur(normal,'));
      expect(opaque, isEmpty);
    });

    test('8-bit colour filters are exact, others are opaque', () {
      final opaque = <OpaqueReason>[];
      expect(
        describeColorFilter(const ColorFilter.mode(Color(0x80FF0000), BlendMode.srcIn), _ctx(owner, opaque)),
        startsWith('CF.mode(c('),
      );
      expect(opaque, isEmpty);
      describeColorFilter(
        ColorFilter.mode(const Color.from(alpha: 1, red: 0.123456, green: 0, blue: 0), BlendMode.srcIn),
        _ctx(owner, opaque),
      );
      expect(opaque, <OpaqueReason>[OpaqueReason.unknownFilter]);
    });

    test('gradients without a decoration are opaque', () {
      final opaque = <OpaqueReason>[];
      final ui.Gradient shader = ui.Gradient.linear(Offset.zero, const Offset(1, 0), <Color>[
        const Color(0xFF000000),
        const Color(0xFFFFFFFF),
      ]);
      describeShader(shader, _ctx(owner, opaque));
      expect(opaque, <OpaqueReason>[OpaqueReason.unknownShader]);
    });
  });

  group('recorder', () {
    testWidgets('records opacity alpha from the composited layer', (WidgetTester tester) async {
      Future<String> hashFor(double opacity) async {
        final PaintRecording r = await _record(
          tester,
          Opacity(
            opacity: opacity,
            child: const ColoredBox(color: Color(0xFF00FF00)),
          ),
        );
        return r.nodes.firstWhere((RecordedNode n) => n.renderObject is RenderOpacity).paintHash;
      }

      expect(await hashFor(0.5), isNot(await hashFor(0.6)));
    });

    testWidgets('own paint does not change when only position changes', (WidgetTester tester) async {
      Future<String> hashAt(double left) async {
        final PaintRecording r = await _record(
          tester,
          Stack(
            children: <Widget>[
              Positioned(
                left: left,
                top: 0,
                width: 20,
                height: 20,
                child: const ColoredBox(color: Color(0xFF0000FF)),
              ),
            ],
          ),
        );
        return r.nodes
            .firstWhere((RecordedNode n) => n.renderObject.runtimeType.toString() == '_RenderColoredBox')
            .paintHash;
      }

      expect(await hashAt(0), await hashAt(10));
    });

    testWidgets('a texture is opaque and pixel-hashed', (WidgetTester tester) async {
      final PaintRecording r = await _record(
        tester,
        const SizedBox(width: 10, height: 10, child: Texture(textureId: 1)),
      );
      final RecordedNode node = r.nodes.firstWhere((RecordedNode n) => n.isOpaque);
      expect(node.opaque.keys, <OpaqueReason>[OpaqueReason.texture]);
      expect(node.ops.last, startsWith('pixels('));
    });
  });
}
