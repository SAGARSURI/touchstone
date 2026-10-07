import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../fixture.dart';

class _WaveClipper extends CustomClipper<Path> {
  const _WaveClipper(this.depth);

  final double depth;

  @override
  Path getClip(Size size) => Path()
    ..lineTo(0, size.height - depth)
    ..quadraticBezierTo(size.width / 2, size.height + depth, size.width, size.height - depth)
    ..lineTo(size.width, 0)
    ..close();

  @override
  bool shouldReclip(_WaveClipper old) => old.depth != depth;
}

class _ShaderPainter extends CustomPainter {
  _ShaderPainter(this.program, this.mix);

  final ui.FragmentProgram? program;
  final double mix;

  @override
  void paint(Canvas canvas, Size size) {
    if (program == null) {
      return;
    }
    final shader = program!.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, mix);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_ShaderPainter old) => old.mix != mix;
}

/// A platform view controller with no platform behind it, so a
/// PlatformViewSurface can be built in a widget test.
class FakePlatformViewController extends PlatformViewController {
  @override
  int get viewId => 1;

  @override
  Future<void> clearFocus() async {}

  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async {}

  @override
  Future<void> dispose() async {}
}

final _controller = FakePlatformViewController();
final _link = LayerLink();

final kindsScreen = FixtureScreen(
  name: 'kinds',
  defaults: <String, Object?>{
    'field': 'hello@example.com',
    'cursorColor': const Color(0xFF2962FF),
    'waveDepth': 12.0,
    'shapeColor': const Color(0xFF00ACC1),
    'fitted': BoxFit.contain,
    'quarterTurns': 1,
    'followerOffset': const Offset(0, 24),
    'fadeOpacity': 0.4,
    'shaderMix': 1.0,
  },
  build: (Knobs k, FixtureAssets a) => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      tagged(
        'field',
        TextField(
          controller: TextEditingController(text: k('field')),
          cursorColor: k('cursorColor'),
          decoration: const InputDecoration(labelText: 'Email'),
        ),
      ),
      const SizedBox(height: 12),
      tagged(
        'clipPath',
        ClipPath(
          clipper: _WaveClipper(k('waveDepth')),
          child: Container(height: 60, color: const Color(0xFF7CB342)),
        ),
      ),
      const SizedBox(height: 12),
      tagged(
        'physicalShape',
        PhysicalShape(
          clipper: const ShapeBorderClipper(shape: StadiumBorder()),
          color: k('shapeColor'),
          elevation: 4,
          child: const SizedBox(height: 40, width: 200),
        ),
      ),
      const SizedBox(height: 12),
      tagged(
        'fitted',
        SizedBox(
          width: 120,
          height: 40,
          child: FittedBox(
            fit: k('fitted'),
            child: Container(width: 60, height: 60, color: const Color(0xFFEF6C00)),
          ),
        ),
      ),
      const SizedBox(height: 12),
      tagged(
        'rotated',
        RotatedBox(
          quarterTurns: k('quarterTurns'),
          child: Container(width: 60, height: 20, color: const Color(0xFF8D6E63)),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 60,
        child: Stack(
          children: <Widget>[
            CompositedTransformTarget(
              link: _link,
              child: Container(width: 40, height: 20, color: const Color(0xFF546E7A)),
            ),
            tagged(
              'follower',
              CompositedTransformFollower(
                link: _link,
                offset: k('followerOffset'),
                child: Container(width: 40, height: 20, color: const Color(0xFFAB47BC)),
              ),
            ),
          ],
        ),
      ),
      tagged(
        'fade',
        FadeTransition(
          opacity: AlwaysStoppedAnimation<double>(k('fadeOpacity')),
          child: Container(height: 30, color: const Color(0xFF26C6DA)),
        ),
      ),
      const SizedBox(height: 12),
      tagged('fragment', CustomPaint(size: const Size(120, 40), painter: _ShaderPainter(a.program, k('shaderMix')))),
      const SizedBox(height: 12),
      tagged(
        'platformView',
        SizedBox(
          width: 200,
          height: 80,
          child: PlatformViewSurface(
            controller: _controller,
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            gestureRecognizers: const {},
          ),
        ),
      ),
    ],
  ),
  mutations: const <Mutation>[
    Mutation('editable text', {'field': 'hello@example.org'}, target: 'field', pixels: PixelExpectation.outsideOracle),
    Mutation('clip path', {'waveDepth': 13.0}, target: 'clipPath'),
    Mutation('physical shape colour', {'shapeColor': Color(0xFF00ACC2)}, target: 'physicalShape'),
    Mutation('fitted box', {'fitted': BoxFit.fill}, target: 'fitted'),
    Mutation('rotated box', {'quarterTurns': 2}, target: 'rotated'),
    Mutation('follower offset', {'followerOffset': Offset(0, 25)}, target: 'follower', kind: MutationKind.layout),
    Mutation('fade opacity', {'fadeOpacity': 0.45}, target: 'fade'),
    Mutation('fragment uniform', {'shaderMix': 0.5}, target: 'fragment'),
  ],
);
