import 'dart:math';

import 'package:flutter/material.dart';

import '../components/section_header.dart';
import '../components/watch_row.dart';
import '../tokens.dart';

const List<String> _names = <String>[
  'Acme', 'Borealis', 'Cobalt', 'Delta', 'Ember', 'Fjord', 'Granite', 'Harbor', 'Indigo', 'Juniper', //
  'Kestrel', 'Lumen', 'Meridian', 'Nimbus', 'Onyx', 'Pioneer', 'Quartz', 'Riverton', 'Summit', 'Tidal',
];

/// 50 quotes from a fixed seed, so every run sees the same data.
List<Quote> seededQuotes([int seed = 42, int count = 50]) {
  final random = Random(seed);
  return List<Quote>.generate(count, (int i) {
    final String name = _names[i % _names.length];
    final String symbol = '${name.substring(0, 3).toUpperCase()}${i ~/ _names.length}';
    final double price = 10 + random.nextInt(49000) / 100;
    final double change = (random.nextInt(1200) - 600) / 100;
    return Quote(symbol, '$name Holdings ${i + 1}', price, change);
  });
}

/// Level 3: 50 rows under a sticky header, in a lazy list.
class WatchlistScreen extends StatelessWidget {
  WatchlistScreen({super.key, List<Quote>? quotes, this.controller}) : quotes = quotes ?? seededQuotes();

  final List<Quote> quotes;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Watchlist')),
      body: CustomScrollView(
        controller: controller,
        slivers: <Widget>[
          const SliverToBoxAdapter(child: PromoBanner()),
          SliverPersistentHeader(pinned: true, delegate: _HeaderDelegate(AppTokens.of(context))),
          SliverList.builder(
            itemCount: quotes.length,
            itemBuilder: (BuildContext context, int i) =>
                WatchRow(key: ValueKey<String>(quotes[i].symbol), quote: quotes[i]),
          ),
        ],
      ),
    );
  }
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate(this.tokens);

  final AppTokens tokens;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(color: tokens.surface, child: const WatchlistHeader());

  @override
  bool shouldRebuild(_HeaderDelegate oldDelegate) => oldDelegate.tokens != tokens;
}

class PromoBanner extends StatelessWidget {
  const PromoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Container(
      margin: const EdgeInsets.all(Space.m),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(color: t.surfaceMuted, borderRadius: BorderRadius.circular(12)),
      child: Text('Zero fees on your first 10 trades', style: TextStyle(color: t.textPrimary)),
    );
  }
}

class WatchlistHeader extends StatelessWidget {
  const WatchlistHeader({super.key});

  @override
  Widget build(BuildContext context) => const Align(alignment: Alignment.centerLeft, child: SectionHeader('Symbols'));
}
