import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../fixture.dart';

const _mat = MutationKind.paint;

final textScreen = FixtureScreen(
  name: 'text',
  defaults: <String, Object?>{
    'heading': 'Order summary',
    'headingWeight': FontWeight.w700,
    'bodyColor': const Color(0xFF333333),
    'paragraphLines': 2,
    'letterSpacing': 0.0,
    'underline': false,
    'richColor': const Color(0xFF1565C0),
  },
  build: (Knobs k, FixtureAssets _) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        tagged('heading', Text(k('heading'), style: TextStyle(fontSize: 24, fontWeight: k('headingWeight')))),
        const SizedBox(height: 8),
        tagged(
          'body',
          Text(
            'A long paragraph that wraps across lines and is cut with an ellipsis '
            'when it runs past the line limit set for this fixture screen.',
            maxLines: k('paragraphLines'),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: k('bodyColor'),
              letterSpacing: k('letterSpacing'),
              decoration: k<bool>('underline') ? TextDecoration.underline : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        tagged(
          'rich',
          Text.rich(
            TextSpan(
              text: 'Total ',
              children: <InlineSpan>[
                TextSpan(
                  text: r'$42.00',
                  style: TextStyle(color: k('richColor'), fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
  mutations: const <Mutation>[
    Mutation('text content', {'heading': 'Order summery'}, target: 'heading', pixels: PixelExpectation.outsideOracle),
    Mutation('text length', {'heading': 'Order summary!'}, target: 'heading'),
    Mutation('font weight', {'headingWeight': FontWeight.w400}, target: 'heading'),
    Mutation('text colour', {'bodyColor': Color(0xFF333334)}, target: 'body'),
    Mutation('truncation', {'paragraphLines': 1}, target: 'body', kind: MutationKind.layout),
    Mutation('letter spacing', {'letterSpacing': 0.5}, target: 'body'),
    Mutation('decoration', {'underline': true}, target: 'body'),
    Mutation('span colour', {'richColor': Color(0xFF1565C1)}, target: 'rich'),
  ],
);

final decoratedScreen = FixtureScreen(
  name: 'decorated',
  defaults: <String, Object?>{
    'color': const Color(0xFF4CAF50),
    'radius': 12.0,
    'borderWidth': 2.0,
    'gradientEnd': const Color(0xFF0D47A1),
    'gradientStop': 0.6,
    'shadowBlur': 4.0,
    'shape': const StadiumBorder(),
  },
  build: (Knobs k, FixtureAssets _) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: <Widget>[
        tagged(
          'box',
          Container(
            height: 60,
            decoration: BoxDecoration(
              color: k('color'),
              borderRadius: BorderRadius.circular(k('radius')),
              border: Border.all(width: k('borderWidth'), color: const Color(0xFF1B5E20)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        tagged(
          'gradient',
          Container(
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[const Color(0xFF90CAF9), k('gradientEnd')],
                stops: <double>[0.0, k('gradientStop')],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        tagged(
          'shadow',
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              boxShadow: <BoxShadow>[BoxShadow(blurRadius: k('shadowBlur'), offset: const Offset(0, 2))],
            ),
          ),
        ),
        const SizedBox(height: 12),
        tagged(
          'shape',
          Container(
            height: 40,
            decoration: ShapeDecoration(color: const Color(0xFFFF7043), shape: k('shape')),
          ),
        ),
      ],
    ),
  ),
  mutations: const <Mutation>[
    Mutation('colour token', {'color': Color(0xFF4CAF51)}, target: 'box'),
    Mutation('corner radius', {'radius': 13.0}, target: 'box'),
    Mutation('border width', {'borderWidth': 3.0}, target: 'box'),
    Mutation('gradient colour', {'gradientEnd': Color(0xFF0D47A2)}, target: 'gradient'),
    Mutation('gradient stop', {'gradientStop': 0.61}, target: 'gradient'),
    // flutter_test sets debugDisableShadows, so blur is not drawn in tests.
    Mutation('shadow blur', {'shadowBlur': 5.0}, target: 'shadow', pixels: PixelExpectation.unchanged),
    Mutation('shape', {'shape': BeveledRectangleBorder()}, target: 'shape'),
  ],
);

final effectsScreen = FixtureScreen(
  name: 'effects',
  defaults: <String, Object?>{
    'opacity': 0.5,
    'clipRadius': 16.0,
    'clipOval': false,
    'angle': 0.1,
    'scale': 1.0,
    'paintOrderSwap': false,
    'colorFilter': const Color(0xFF8E24AA),
    'blur': 2.0,
    'maskEnd': const Color(0x00FFFFFF),
    'visible': true,
  },
  build: (Knobs k, FixtureAssets _) {
    Widget square(Color color, String label) => Container(width: 60, height: 60, color: color, child: Text(label));
    final List<Widget> stacked = <Widget>[
      Positioned(left: 0, top: 0, child: square(const Color(0xFFE53935), 'A')),
      Positioned(left: 30, top: 30, child: square(const Color(0xFF1E88E5), 'B')),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: <Widget>[
          tagged('opacity', Opacity(opacity: k('opacity'), child: square(const Color(0xFF43A047), 'O'))),
          tagged(
            'clip',
            k<bool>('clipOval')
                ? ClipOval(child: square(const Color(0xFFFB8C00), 'C'))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(k('clipRadius')),
                    child: square(const Color(0xFFFB8C00), 'C'),
                  ),
          ),
          tagged(
            'transform',
            Transform.rotate(
              angle: k('angle'),
              child: Transform.scale(scale: k('scale'), child: square(const Color(0xFF00897B), 'T')),
            ),
          ),
          tagged(
            'order',
            SizedBox(
              width: 90,
              height: 90,
              child: Stack(children: k<bool>('paintOrderSwap') ? stacked.reversed.toList() : stacked),
            ),
          ),
          tagged(
            'colorFilter',
            ColorFiltered(
              colorFilter: ColorFilter.mode(k('colorFilter'), BlendMode.modulate),
              child: square(const Color(0xFFFFFFFF), 'F'),
            ),
          ),
          tagged(
            'imageFilter',
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: k('blur'), sigmaY: k('blur')),
              child: square(const Color(0xFF3949AB), 'I'),
            ),
          ),
          tagged(
            'shaderMask',
            ShaderMask(
              shaderCallback: (Rect r) =>
                  LinearGradient(colors: <Color>[const Color(0xFFFFFFFF), k('maskEnd')]).createShader(r),
              child: square(const Color(0xFF6D4C41), 'S'),
            ),
          ),
          tagged(
            'backdrop',
            SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                children: <Widget>[
                  square(const Color(0xFFD81B60), 'X'),
                  Positioned.fill(
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: k('blur'), sigmaY: k('blur')),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          tagged('visibility', Visibility(visible: k('visible'), child: square(const Color(0xFF5E35B1), 'V'))),
        ],
      ),
    );
  },
  mutations: const <Mutation>[
    Mutation('opacity', {'opacity': 0.6}, target: 'opacity'),
    Mutation('clip radius', {'clipRadius': 17.0}, target: 'clip'),
    Mutation('clip shape', {'clipOval': true}, target: 'clip'),
    Mutation('rotation', {'angle': 0.11}, target: 'transform'),
    Mutation('scale', {'scale': 0.9}, target: 'transform'),
    Mutation('paint order', {'paintOrderSwap': true}, target: 'order', kind: _mat),
    Mutation('colour filter', {'colorFilter': Color(0xFF8E24AB)}, target: 'colorFilter'),
    Mutation('blur sigma', {'blur': 3.0}, target: 'imageFilter'),
    Mutation('shader mask', {'maskEnd': Color(0x10FFFFFF)}, target: 'shaderMask'),
    Mutation('widget removed', {'visible': false}, target: 'visibility', kind: MutationKind.structure),
  ],
);
