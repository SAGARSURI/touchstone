import 'package:flutter/material.dart';

import '../tokens.dart';

class PriceLabel extends StatelessWidget {
  const PriceLabel({super.key, required this.price, required this.change, this.compact = false});

  final double price;

  /// Percentage change.
  final double change;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    final bool up = change >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          price.toStringAsFixed(2),
          style: TextStyle(fontSize: compact ? 15 : 22, fontWeight: FontWeight.w600, color: t.textPrimary),
        ),
        ChangeBadge(change: change, color: up ? t.positive : t.negative),
      ],
    );
  }
}

class ChangeBadge extends StatelessWidget {
  const ChangeBadge({super.key, required this.change, required this.color});

  final double change;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final String sign = change >= 0 ? '+' : '';
    return Container(
      margin: const EdgeInsets.only(top: Space.xs),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
      child: Text(
        '$sign${change.toStringAsFixed(2)}%',
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}
