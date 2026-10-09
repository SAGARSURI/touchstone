import 'package:flutter/material.dart';

import '../components/app_button.dart';
import '../components/watch_row.dart';
import '../tokens.dart';
import 'watchlist.dart';

/// What the user has chosen so far. Each step reads and updates it, so the
/// state carries across screens.
class OrderDraft extends ChangeNotifier {
  OrderDraft(this.basket);

  /// The symbols in the order, in execution order.
  final List<Quote> basket;
  Quote? _symbol;
  int _shares = 0;

  Quote? get symbol => _symbol;
  int get shares => _shares;

  void choose(Quote q) {
    _symbol = q;
    notifyListeners();
  }

  void setShares(int n) {
    _shares = n;
    notifyListeners();
  }

  void move(int from, int to) {
    basket.insert(to, basket.removeAt(from));
    notifyListeners();
  }
}

/// Level 5: a four-step order flow (symbol, amount, review, done) with
/// animated page transitions and a reorderable list. Exercises captures at
/// pumped times, drag state and state across screens.
class OrderFlowScreen extends StatefulWidget {
  const OrderFlowScreen({super.key});

  @override
  State<OrderFlowScreen> createState() => _OrderFlowScreenState();
}

class _OrderFlowScreenState extends State<OrderFlowScreen> {
  final OrderDraft _draft = OrderDraft(seededQuotes().skip(10).take(4).toList());

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SymbolStep(draft: _draft);
}

void _next(BuildContext context, Widget Function() step) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => step()));

class SymbolStep extends StatelessWidget {
  const SymbolStep({super.key, required this.draft});

  final OrderDraft draft;

  @override
  Widget build(BuildContext context) {
    final List<Quote> quotes = seededQuotes().take(6).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('1 of 4 · Symbol')),
      body: ListView(
        children: <Widget>[
          for (final Quote q in quotes)
            InkWell(
              key: ValueKey<String>('pick ${q.symbol}'),
              onTap: () {
                draft.choose(q);
                _next(context, () => AmountStep(draft: draft));
              },
              child: WatchRow(quote: q),
            ),
        ],
      ),
    );
  }
}

class AmountStep extends StatelessWidget {
  const AmountStep({super.key, required this.draft});

  final OrderDraft draft;

  static const List<int> presets = <int>[5, 10, 25, 50];

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return ListenableBuilder(
      listenable: draft,
      builder: (BuildContext context, _) => Scaffold(
        appBar: AppBar(title: const Text('2 of 4 · Amount')),
        body: Padding(
          padding: const EdgeInsets.all(Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '${draft.symbol!.symbol} at ${draft.symbol!.price.toStringAsFixed(2)}',
                style: TextStyle(color: t.textSecondary),
              ),
              const SizedBox(height: Space.m),
              Text(
                '${draft.shares} shares',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, color: t.textPrimary),
              ),
              const SizedBox(height: Space.m),
              Wrap(
                spacing: Space.s,
                children: <Widget>[
                  for (final int n in presets)
                    ChoiceChip(
                      key: ValueKey<String>('shares $n'),
                      label: Text('$n'),
                      selected: draft.shares == n,
                      onSelected: (_) => draft.setShares(n),
                    ),
                ],
              ),
              const Spacer(),
              AppButton(
                key: const ValueKey<String>('to review'),
                label: 'Review',
                enabled: draft.shares > 0,
                onPressed: () => _next(context, () => ReviewStep(draft: draft)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReviewStep extends StatelessWidget {
  const ReviewStep({super.key, required this.draft});

  final OrderDraft draft;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return ListenableBuilder(
      listenable: draft,
      builder: (BuildContext context, _) => Scaffold(
        appBar: AppBar(title: const Text('3 of 4 · Review')),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OrderSummary(draft: draft),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
              child: Text('Also buy, in this order', style: TextStyle(color: t.textSecondary)),
            ),
            Expanded(
              child: ReorderableListView(
                buildDefaultDragHandles: false,
                onReorderItem: draft.move,
                children: <Widget>[
                  for (int i = 0; i < draft.basket.length; i++)
                    BasketRow(key: ValueKey<String>(draft.basket[i].symbol), index: i, quote: draft.basket[i]),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.m),
              child: AppButton(
                key: const ValueKey<String>('place order'),
                label: 'Place order',
                onPressed: () => _next(context, () => DoneStep(draft: draft)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OrderSummary extends StatelessWidget {
  const OrderSummary({super.key, required this.draft});

  final OrderDraft draft;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    final Quote q = draft.symbol!;
    return Container(
      margin: const EdgeInsets.all(Space.m),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(color: t.surfaceMuted, borderRadius: BorderRadius.circular(12)),
      child: Text(
        'Buy ${draft.shares} ${q.symbol} for ${(q.price * draft.shares).toStringAsFixed(2)}',
        style: TextStyle(fontWeight: FontWeight.w600, color: t.textPrimary),
      ),
    );
  }
}

class BasketRow extends StatelessWidget {
  const BasketRow({super.key, required this.index, required this.quote});

  final int index;
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Material(
      color: t.surface,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: Space.m),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.divider)),
        ),
        child: Row(
          children: <Widget>[
            Text('${index + 1}.', style: TextStyle(color: t.textSecondary)),
            const SizedBox(width: Space.m),
            Expanded(
              child: Text(quote.symbol, style: TextStyle(color: t.textPrimary)),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Icon(Icons.drag_handle, key: ValueKey<String>('drag ${quote.symbol}'), color: t.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class DoneStep extends StatelessWidget {
  const DoneStep({super.key, required this.draft});

  final OrderDraft draft;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('4 of 4 · Done'), automaticallyImplyLeading: false),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.check_circle, size: 64, color: t.positive),
            const SizedBox(height: Space.m),
            Text(
              'Order placed: ${draft.shares} ${draft.symbol!.symbol}',
              style: TextStyle(fontSize: 18, color: t.textPrimary),
            ),
            const SizedBox(height: Space.s),
            Text(
              'Then ${draft.basket.map((Quote q) => q.symbol).join(', ')}',
              style: TextStyle(color: t.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
