import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../components/watch_row.dart';
import '../tokens.dart';
import 'watchlist.dart';

/// Level 5: prices that tick every second and flash when they change.
/// Exercises dynamic content, timers and a fixed clock. Time is read through
/// package:clock and the ticks come from [random], so a test can fix both.
class LivePricesScreen extends StatefulWidget {
  LivePricesScreen({super.key, List<Quote>? quotes, Random? random, this.tick = const Duration(seconds: 1)})
    : quotes = quotes ?? seededQuotes().take(8).toList(),
      random = random ?? Random();

  final List<Quote> quotes;
  final Random random;
  final Duration tick;

  @override
  State<LivePricesScreen> createState() => _LivePricesScreenState();
}

class _LivePricesScreenState extends State<LivePricesScreen> {
  late List<double> _prices = <double>[for (final Quote q in widget.quotes) q.price];
  late DateTime _updated = clock.now();
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.tick, (_) => _onTick());
  }

  void _onTick() {
    setState(() {
      _prices = <double>[
        for (final double p in _prices)
          // About half the prices move on each tick.
          widget.random.nextBool() ? p : p + (widget.random.nextInt(41) - 20) / 100,
      ];
      _updated = clock.now();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live')),
      body: Column(
        children: <Widget>[
          UpdatedAt(time: _updated),
          Expanded(
            child: ListView(
              children: <Widget>[
                for (int i = 0; i < widget.quotes.length; i++)
                  LivePriceRow(
                    key: ValueKey<String>(widget.quotes[i].symbol),
                    quote: widget.quotes[i],
                    price: _prices[i],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class UpdatedAt extends StatelessWidget {
  const UpdatedAt({super.key, required this.time});

  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    String two(int n) => n.toString().padLeft(2, '0');
    return Container(
      width: double.infinity,
      color: t.surfaceMuted,
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
      child: Text(
        'Updated ${two(time.hour)}:${two(time.minute)}:${two(time.second)}',
        style: TextStyle(fontSize: 12, color: t.textSecondary),
      ),
    );
  }
}

/// A row whose background flashes green or red for 600 ms when its price
/// moves.
class LivePriceRow extends StatefulWidget {
  const LivePriceRow({super.key, required this.quote, required this.price});

  final Quote quote;
  final double price;

  @override
  State<LivePriceRow> createState() => _LivePriceRowState();
}

class _LivePriceRowState extends State<LivePriceRow> with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  bool _up = true;

  @override
  void didUpdateWidget(LivePriceRow old) {
    super.didUpdateWidget(old);
    if (widget.price != old.price) {
      _up = widget.price > old.price;
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return AnimatedBuilder(
      animation: _flash,
      builder: (BuildContext context, Widget? child) {
        // Rises to full tint in the first third, then fades out.
        final double v = _flash.isAnimating ? (_flash.value < 1 / 3 ? _flash.value * 3 : (1 - _flash.value) * 1.5) : 0;
        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          decoration: BoxDecoration(
            color: Color.lerp(t.surface, _up ? t.positive : t.negative, 0.2 * v),
            border: Border(bottom: BorderSide(color: t.divider)),
          ),
          child: child,
        );
      },
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              widget.quote.symbol,
              style: TextStyle(fontWeight: FontWeight.w600, color: t.textPrimary),
            ),
          ),
          LivePrice(price: widget.price),
        ],
      ),
    );
  }
}

class LivePrice extends StatelessWidget {
  const LivePrice({super.key, required this.price});

  final double price;

  @override
  Widget build(BuildContext context) => Text(
    price.toStringAsFixed(2),
    style: TextStyle(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      color: AppTokens.of(context).textPrimary,
    ),
  );
}
