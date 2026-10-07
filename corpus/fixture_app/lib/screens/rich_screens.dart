import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../fixture.dart';

final imageScreen = FixtureScreen(
  name: 'images',
  usesImages: true,
  defaults: <String, Object?>{
    'useB': false,
    'fit': BoxFit.cover,
    'icon': Icons.star,
    'iconColor': const Color(0xFFFFC107),
    'iconSize': 32.0,
  },
  build: (Knobs k, FixtureAssets a) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: <Widget>[
        tagged('image', Image.memory(k<bool>('useB') ? a.imageB : a.imageA, width: 96, height: 48, fit: k('fit'))),
        const SizedBox(height: 12),
        tagged(
          'decorationImage',
          Container(
            width: 120,
            height: 48,
            decoration: BoxDecoration(
              image: DecorationImage(image: MemoryImage(a.imageA), fit: BoxFit.fill),
            ),
          ),
        ),
        const SizedBox(height: 12),
        tagged('icon', Icon(k('icon'), color: k('iconColor'), size: k('iconSize'))),
      ],
    ),
  ),
  mutations: const <Mutation>[
    Mutation('image pixel', {'useB': true}, target: 'image'),
    Mutation('image fit', {'fit': BoxFit.contain}, target: 'image'),
    // The test font draws every glyph as the same box.
    Mutation('icon glyph', {'icon': Icons.star_border}, target: 'icon', pixels: PixelExpectation.outsideOracle),
    Mutation('icon colour', {'iconColor': Color(0xFFFFC108)}, target: 'icon'),
    Mutation('icon size', {'iconSize': 33.0}, target: 'icon', kind: MutationKind.layout),
  ],
);

final listScreen = FixtureScreen(
  name: 'lists',
  defaults: <String, Object?>{
    'rows': 30,
    'rowColor': const Color(0xFFFAFAFA),
    'divider': 1.0,
    'gridColumns': 3,
    'title': 'Watchlist',
  },
  build: (Knobs k, FixtureAssets _) => CustomScrollView(
    slivers: <Widget>[
      SliverAppBar(pinned: true, expandedHeight: 120, title: tagged('title', Text(k('title')))),
      SliverList.separated(
        itemCount: k('rows'),
        separatorBuilder: (_, _) => Divider(height: k('divider')),
        itemBuilder: (_, int i) => tagged(
          'row$i',
          Container(color: k('rowColor'), height: 44, alignment: Alignment.centerLeft, child: Text('Row $i')),
        ),
      ),
      SliverGrid.count(
        crossAxisCount: k('gridColumns'),
        children: <Widget>[for (var i = 0; i < 6; i++) ColoredBox(color: Color(0xFF26A69A + i * 8), child: Text('$i'))],
      ),
    ],
  ),
  mutations: const <Mutation>[
    Mutation('row colour', {'rowColor': Color(0xFFFAFAFB)}, target: 'row0'),
    Mutation('divider height', {'divider': 2.0}, target: 'row1', kind: MutationKind.layout),
    Mutation('app bar title', {'title': 'Watchlists'}, target: 'title'),
  ],
);

class ChartPainter extends CustomPainter {
  ChartPainter({required this.values, required this.stroke, required this.fillTop, required this.label});

  final List<double> values;
  final double stroke;
  final Color fillTop;
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    final double dx = size.width / (values.length - 1);
    final double maxV = values.reduce(math.max);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final Offset p = Offset(i * dx, size.height * (1 - values[i] / maxV));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    final Path fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[fillTop, const Color(0x002196F3)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = const Color(0xFF1976D2),
    );
    for (var i = 0; i < values.length; i += 3) {
      canvas.drawRect(
        Rect.fromLTWH(i * dx - 3, size.height - values[i] / maxV * 20, 6, values[i] / maxV * 20),
        Paint()..color = const Color(0xFF66BB6A),
      );
    }
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: 10, color: Color(0xFF000000)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(4, 4));
    tp.dispose();
  }

  @override
  bool shouldRepaint(ChartPainter old) =>
      old.values != values || old.stroke != stroke || old.fillTop != fillTop || old.label != label;
}

class SparkPainter extends CustomPainter {
  SparkPainter(this.points);

  final List<double> points;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(0, size.height / 2);
    for (var i = 0; i < points.length; i++) {
      path.quadraticBezierTo(
        (i + 0.5) * size.width / points.length,
        points[i],
        (i + 1) * size.width / points.length,
        size.height / 2,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFE91E63),
    );
    canvas.drawCircle(Offset(size.width, size.height / 2), 3, Paint()..color = const Color(0xFFE91E63));
  }

  @override
  bool shouldRepaint(SparkPainter old) => old.points != points;
}

final chartScreen = FixtureScreen(
  name: 'chart',
  defaults: <String, Object?>{
    'values': const <double>[3, 5, 4, 7, 6, 9, 8, 11, 10, 12, 9, 13],
    'stroke': 2.0,
    'fillTop': const Color(0x802196F3),
    'label': 'BTC 1D',
    'spark': const <double>[2, 18, 6, 14, 10],
  },
  build: (Knobs k, FixtureAssets _) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: <Widget>[
        tagged(
          'chart',
          CustomPaint(
            size: const Size(358, 180),
            painter: ChartPainter(values: k('values'), stroke: k('stroke'), fillTop: k('fillTop'), label: k('label')),
          ),
        ),
        const SizedBox(height: 12),
        tagged('spark', CustomPaint(size: const Size(120, 24), painter: SparkPainter(k('spark')))),
      ],
    ),
  ),
  mutations: const <Mutation>[
    Mutation('data point', {
      'values': <double>[3, 5, 4, 7, 6, 9, 8, 11, 10, 12, 9, 14],
    }, target: 'chart'),
    Mutation('stroke width', {'stroke': 2.5}, target: 'chart'),
    Mutation('gradient fill', {'fillTop': Color(0x812196F3)}, target: 'chart'),
    Mutation('painter label', {'label': 'ETH 1D'}, target: 'chart', pixels: PixelExpectation.outsideOracle),
    Mutation('curve control point', {
      'spark': <double>[2, 18, 6, 14, 11],
    }, target: 'spark'),
  ],
);

final platformViewScreen = FixtureScreen(
  name: 'platform_view',
  defaults: <String, Object?>{'headerColor': const Color(0xCCFFFFFF), 'mapHeight': 300.0},
  build: (Knobs k, FixtureAssets _) => Stack(
    children: <Widget>[
      // The map sits below the header so the header's pixels are judged by
      // its own recording, not by the texture's pixel hash.
      Positioned(
        left: 0,
        right: 0,
        top: 120,
        height: k('mapHeight'),
        child: tagged('map', const Texture(textureId: 7)),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        height: 80,
        child: tagged(
          'header',
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: ColoredBox(
                color: k('headerColor'),
                child: const Center(child: Text('Map')),
              ),
            ),
          ),
        ),
      ),
    ],
  ),
  mutations: const <Mutation>[
    Mutation('header colour', {'headerColor': Color(0x60FFFFFF)}, target: 'header'),
    // Blended over a near-white background, one alpha step rounds to the
    // same 8-bit output: a real value change no pixel shows.
    Mutation(
      'header alpha below output precision',
      {'headerColor': Color(0xCDFFFFFF)},
      target: 'header',
      pixels: PixelExpectation.unchanged,
    ),
  ],
);

Widget _settings(Knobs k) => ListView(
  children: <Widget>[
    tagged(
      'tile',
      ListTile(
        leading: const Icon(Icons.wifi),
        title: const Text('Wi-Fi'),
        trailing: Switch(value: k('switch'), onChanged: (_) {}),
      ),
    ),
    const Divider(),
    tagged(
      'button',
      Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(onPressed: k<bool>('enabled') ? () {} : null, child: const Text('Save')),
      ),
    ),
    tagged(
      'card',
      Card(
        margin: const EdgeInsets.all(16),
        child: Padding(padding: EdgeInsets.all(k('cardPadding')), child: const Text('Card content')),
      ),
    ),
    tagged('checkbox', Checkbox(value: k('checked'), onChanged: (_) {})),
    tagged('semantic', Semantics(label: k('semanticsLabel'), child: const SizedBox(width: 40, height: 40))),
  ],
);

final themedScreen = FixtureScreen(
  name: 'themed',
  defaults: <String, Object?>{
    'dark': false,
    'seed': const Color(0xFF6750A4),
    'switch': true,
    'enabled': true,
    'cardPadding': 16.0,
    'checked': false,
    'semanticsLabel': 'Status',
  },
  build: (Knobs k, FixtureAssets _) => Theme(
    data: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: k('seed'),
        brightness: k<bool>('dark') ? Brightness.dark : Brightness.light,
      ),
    ),
    child: Builder(builder: (BuildContext context) => Material(child: _settings(k))),
  ),
  mutations: const <Mutation>[
    Mutation('dark theme', {'dark': true}, target: 'tile'),
    Mutation('theme seed', {'seed': Color(0xFF00639B)}, target: 'button'),
    Mutation('switch state', {'switch': false}, target: 'tile'),
    Mutation('disabled state', {'enabled': false}, target: 'button'),
    Mutation('padding 1px', {'cardPadding': 17.0}, target: 'card', kind: MutationKind.layout),
    Mutation('selected state', {'checked': true}, target: 'checkbox'),
    Mutation(
      'semantics label',
      {'semanticsLabel': 'State'},
      target: 'semantic',
      kind: MutationKind.semantics,
      pixels: PixelExpectation.unchanged,
    ),
  ],
);

final overlayScreen = FixtureScreen(
  name: 'overlay',
  defaults: <String, Object?>{'scrim': const Color(0x8A000000), 'dialogTitle': 'Delete order?', 'sheetHeight': 160.0},
  build: (Knobs k, FixtureAssets _) => Stack(
    children: <Widget>[
      const Positioned.fill(
        child: ColoredBox(
          color: Color(0xFFECEFF1),
          child: Center(child: Text('Screen')),
        ),
      ),
      Positioned.fill(child: tagged('scrim', ColoredBox(color: k('scrim')))),
      Center(
        child: tagged(
          'dialog',
          Dialog(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(k('dialogTitle'), style: const TextStyle(fontSize: 18)),
            ),
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: k('sheetHeight'),
        child: tagged('sheet', const Material(elevation: 8, child: Center(child: Text('Sheet')))),
      ),
    ],
  ),
  mutations: const <Mutation>[
    Mutation('scrim opacity', {'scrim': Color(0x8B000000)}, target: 'scrim'),
    Mutation('dialog text', {'dialogTitle': 'Delete orders?'}, target: 'dialog'),
    Mutation('sheet height', {'sheetHeight': 161.0}, target: 'sheet', kind: MutationKind.layout),
  ],
);
