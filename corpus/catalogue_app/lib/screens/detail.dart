import 'package:flutter/material.dart';

import '../components/price_label.dart';
import '../components/section_header.dart';
import '../components/watch_row.dart';
import '../tokens.dart';

/// Level 3: a detail page with a header image, a collapsing app bar and tabs.
/// The image comes from [image]: a NetworkImage in the app, an in-memory
/// image in tests.
class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.quote, required this.image, this.initialTab = 0, this.controller});

  final Quote quote;
  final ImageProvider image;
  final int initialTab;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Scaffold(
        body: NestedScrollView(
          controller: controller,
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) => <Widget>[
            SliverAppBar(
              pinned: true,
              expandedHeight: 200,
              title: Text(quote.symbol),
              flexibleSpace: FlexibleSpaceBar(background: HeaderImage(image: image)),
              bottom: TabBar(
                labelColor: t.textPrimary,
                tabs: const <Widget>[
                  Tab(text: 'Overview'),
                  Tab(text: 'News'),
                  Tab(text: 'Holders'),
                ],
              ),
            ),
          ],
          body: TabBarView(
            children: <Widget>[
              OverviewTab(quote: quote),
              const _ListTab(title: 'Headlines', count: 12),
              const _ListTab(title: 'Top holders', count: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class HeaderImage extends StatelessWidget {
  const HeaderImage({super.key, required this.image});

  final ImageProvider image;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: Image(image: image, fit: BoxFit.cover, semanticLabel: 'Company headquarters'),
  );
}

class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key, required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return ListView(
      padding: const EdgeInsets.all(Space.m),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(quote.name, style: TextStyle(fontSize: 18, color: t.textPrimary)),
            ),
            PriceLabel(price: quote.price, change: quote.change),
          ],
        ),
        const SectionHeader('About'),
        Text(
          '${quote.name} is a fictional company used to exercise the snapshot tool.',
          style: TextStyle(color: t.textSecondary),
        ),
      ],
    );
  }
}

class _ListTab extends StatelessWidget {
  const _ListTab({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: count,
    itemBuilder: (BuildContext context, int i) => ListTile(title: Text('$title ${i + 1}')),
  );
}
