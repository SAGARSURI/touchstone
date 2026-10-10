import 'dart:math';

import 'package:flutter/material.dart';

import '../components/section_header.dart';
import '../tokens.dart';

/// One trading day: open, high, low and close.
class Candle {
  const Candle(this.open, this.high, this.low, this.close);

  final double open;
  final double high;
  final double low;
  final double close;
}

/// 30 trading days of ACM0, oldest first.
const List<Candle> candles30 = <Candle>[
  Candle(120.00, 121.37, 116.62, 119.40),
  Candle(119.40, 120.15, 117.82, 120.09),
  Candle(120.09, 120.80, 114.60, 116.91),
  Candle(116.91, 121.74, 114.97, 119.51),
  Candle(119.51, 120.09, 118.22, 118.95),
  Candle(118.95, 121.60, 114.51, 115.35),
  Candle(115.35, 116.22, 114.16, 114.44),
  Candle(114.44, 115.39, 109.15, 110.08),
  Candle(110.08, 110.52, 105.14, 105.70),
  Candle(105.70, 106.79, 100.45, 103.11),
  Candle(103.11, 105.37, 99.81, 101.27),
  Candle(101.27, 107.92, 100.12, 105.24),
  Candle(105.24, 108.38, 102.94, 105.86),
  Candle(105.86, 107.49, 102.98, 103.20),
  Candle(103.20, 106.16, 102.00, 104.98),
  Candle(104.98, 107.85, 100.53, 101.00),
  Candle(101.00, 101.73, 96.06, 98.33),
  Candle(98.33, 100.48, 96.86, 99.69),
  Candle(99.69, 99.94, 97.67, 99.00),
  Candle(99.00, 99.58, 98.24, 99.48),
  Candle(99.48, 105.71, 97.13, 103.58),
  Candle(103.58, 104.98, 102.78, 104.75),
  Candle(104.75, 106.04, 100.09, 102.42),
  Candle(102.42, 103.33, 98.90, 99.49),
  Candle(99.49, 102.14, 98.61, 100.37),
  Candle(100.37, 103.28, 99.94, 101.57),
  Candle(101.57, 108.39, 99.76, 106.74),
  Candle(106.74, 106.97, 101.42, 103.48),
  Candle(103.48, 104.32, 100.49, 102.65),
  Candle(102.65, 104.35, 98.09, 98.54),
];

/// Level 5: a price chart drawn by a CustomPainter, with a line series, a
/// candlestick series, a gradient fill and a tooltip. Exercises path
/// fingerprints, shaders and the pixel-hash fallback.
class ChartScreen extends StatelessWidget {
  const ChartScreen({super.key, this.candles = candles30, this.selected});

  final List<Candle> candles;

  /// The day the tooltip shows, if any.
  final int? selected;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ACM0 · 30 days')),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: <Widget>[
          const SectionHeader('Close'),
          PriceChart(candles: candles, selected: selected, height: 200),
          const SizedBox(height: Space.m),
          const SectionHeader('Daily range'),
          PriceChart(candles: candles, style: ChartStyle.candles, height: 160),
          const SizedBox(height: Space.m),
          Text('Last close ${candles.last.close.toStringAsFixed(2)}', style: TextStyle(color: t.textSecondary)),
        ],
      ),
    );
  }
}

enum ChartStyle { line, candles }

class PriceChart extends StatelessWidget {
  const PriceChart({
    super.key,
    required this.candles,
    this.style = ChartStyle.line,
    this.selected,
    required this.height,
  });

  final List<Candle> candles;
  final ChartStyle style;
  final int? selected;
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    final painter = _ChartPainter(candles, style, t, strokeWidth: 2);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size size = Size(constraints.maxWidth, height);
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(child: CustomPaint(painter: painter)),
              if (selected != null)
                Positioned(
                  left: (painter.xOf(selected!, size) - 48).clamp(0, size.width - 96).toDouble(),
                  top: (painter.yOf(candles[selected!].close, size) - 52).clamp(0, height).toDouble(),
                  child: ChartTooltip(day: selected! + 1, value: candles[selected!].close),
                ),
            ],
          );
        },
      ),
    );
  }
}

class ChartTooltip extends StatelessWidget {
  const ChartTooltip({super.key, required this.day, required this.value});

  final int day;
  final double value;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
      decoration: BoxDecoration(
        color: t.textPrimary,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const <BoxShadow>[BoxShadow(blurRadius: 4, color: Color(0x33000000), offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Day $day', style: TextStyle(fontSize: 11, color: t.surface)),
          Text(
            value.toStringAsFixed(2),
            style: TextStyle(fontWeight: FontWeight.w600, color: t.surface),
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.candles, this.style, this.tokens, {required this.strokeWidth});

  final List<Candle> candles;
  final ChartStyle style;
  final AppTokens tokens;
  final double strokeWidth;

  double get _min => candles.map((Candle c) => c.low).reduce(min);
  double get _max => candles.map((Candle c) => c.high).reduce(max);

  double xOf(int i, Size size) => (i + 0.5) * size.width / candles.length;

  double yOf(double v, Size size) => size.height - (v - _min) / (_max - _min) * size.height;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = tokens.divider
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final double y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    switch (style) {
      case ChartStyle.line:
        final line = Path();
        for (int i = 0; i < candles.length; i++) {
          final Offset p = Offset(xOf(i, size), yOf(candles[i].close, size));
          i == 0 ? line.moveTo(p.dx, p.dy) : line.lineTo(p.dx, p.dy);
        }
        final Path fill = Path.from(line)
          ..lineTo(xOf(candles.length - 1, size), size.height)
          ..lineTo(xOf(0, size), size.height)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[tokens.brandAccent.withValues(alpha: 0.35), tokens.brandAccent.withValues(alpha: 0)],
            ).createShader(Offset.zero & size),
        );
        canvas.drawPath(
          line,
          Paint()
            ..color = tokens.brandAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeJoin = StrokeJoin.round,
        );
      case ChartStyle.candles:
        final double body = size.width / candles.length * 0.6;
        for (int i = 0; i < candles.length; i++) {
          final Candle c = candles[i];
          final Color color = c.close >= c.open ? tokens.positive : tokens.negative;
          final double x = xOf(i, size);
          canvas.drawLine(
            Offset(x, yOf(c.high, size)),
            Offset(x, yOf(c.low, size)),
            Paint()
              ..color = color
              ..strokeWidth = 1,
          );
          canvas.drawRect(
            Rect.fromLTRB(x - body / 2, yOf(max(c.open, c.close), size), x + body / 2, yOf(min(c.open, c.close), size)),
            Paint()..color = color,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.candles != candles || old.style != style || old.tokens != tokens || old.strokeWidth != strokeWidth;
}
