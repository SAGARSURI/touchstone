import 'package:flutter/material.dart';

import '../tokens.dart';
import 'price_label.dart';

class Quote {
  const Quote(this.symbol, this.name, this.price, this.change);

  final String symbol;
  final String name;
  final double price;
  final double change;
}

class WatchRow extends StatelessWidget {
  const WatchRow({super.key, required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: Space.m),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: Row(
        children: <Widget>[
          SymbolAvatar(symbol: quote.symbol),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  quote.symbol,
                  style: TextStyle(fontWeight: FontWeight.w600, color: t.textPrimary),
                ),
                Text(
                  quote.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: t.textSecondary),
                ),
              ],
            ),
          ),
          PriceLabel(price: quote.price, change: quote.change, compact: true),
        ],
      ),
    );
  }
}

class SymbolAvatar extends StatelessWidget {
  const SymbolAvatar({super.key, required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return CircleAvatar(
      radius: 18,
      backgroundColor: t.surfaceMuted,
      child: Text(
        symbol.substring(0, 1),
        style: TextStyle(color: t.brandAccent, fontWeight: FontWeight.w700),
      ),
    );
  }
}
