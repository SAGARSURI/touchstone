import 'package:flutter/material.dart';

import '../components/app_button.dart';
import '../components/price_label.dart';
import '../components/section_header.dart';
import '../components/watch_row.dart';
import '../tokens.dart';

/// Which overlay the screen opens over itself.
enum OverlayKind { none, dialog, sheet, snackbar }

/// Level 4: a position screen with a dialog, a bottom sheet, a snackbar or
/// the sort dropdown's menu opened over it. Exercises layers, scrim opacity
/// and paint order. The dropdown is opened the way a user does, by a tap.
class OverlaysScreen extends StatefulWidget {
  const OverlaysScreen({super.key, required this.quote, this.open = OverlayKind.none});

  final Quote quote;

  /// Opened after the first frame.
  final OverlayKind open;

  @override
  State<OverlaysScreen> createState() => _OverlaysScreenState();
}

class _OverlaysScreenState extends State<OverlaysScreen> {
  String _sort = 'Value';

  @override
  void initState() {
    super.initState();
    if (widget.open != OverlayKind.none) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openOverlay());
    }
  }

  void _openOverlay() {
    switch (widget.open) {
      case OverlayKind.none:
        break;
      case OverlayKind.dialog:
        showDialog<void>(
          context: context,
          builder: (_) => ConfirmOrderDialog(quote: widget.quote, shares: 10),
        );
      case OverlayKind.sheet:
        showModalBottomSheet<void>(
          context: context,
          builder: (_) => TradeSheet(quote: widget.quote),
        );
      case OverlayKind.snackbar:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: OrderPlacedMessage(symbol: widget.quote.symbol),
            action: SnackBarAction(label: 'Undo', onPressed: () {}),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.quote.symbol)),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: <Widget>[
          PositionSummary(quote: widget.quote, shares: 24),
          const SizedBox(height: Space.m),
          Row(
            children: <Widget>[
              const Expanded(child: SectionHeader('Lots')),
              SortDropdown(value: _sort, onChanged: (String v) => setState(() => _sort = v)),
            ],
          ),
          for (int i = 0; i < 4; i++)
            Container(
              height: 48,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.divider)),
              ),
              alignment: Alignment.centerLeft,
              child: Text('Lot ${i + 1}: ${6 * (i + 1)} shares', style: TextStyle(color: t.textPrimary)),
            ),
          const SizedBox(height: Space.l),
          const AppButton(label: 'Trade'),
        ],
      ),
    );
  }
}

class PositionSummary extends StatelessWidget {
  const PositionSummary({super.key, required this.quote, required this.shares});

  final Quote quote;
  final int shares;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(color: t.surfaceMuted, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  quote.name,
                  style: TextStyle(fontWeight: FontWeight.w600, color: t.textPrimary),
                ),
                Text('$shares shares', style: TextStyle(fontSize: 12, color: t.textSecondary)),
              ],
            ),
          ),
          PriceLabel(price: quote.price * shares, change: quote.change),
        ],
      ),
    );
  }
}

class SortDropdown extends StatelessWidget {
  const SortDropdown({super.key, required this.value, required this.onChanged});

  static const List<String> options = <String>['Value', 'Date', 'Gain'];

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButton<String>(
    value: value,
    underline: const SizedBox.shrink(),
    items: <DropdownMenuItem<String>>[
      for (final String o in options) DropdownMenuItem<String>(value: o, child: Text('Sort: $o')),
    ],
    onChanged: (String? v) => onChanged(v!),
  );
}

class ConfirmOrderDialog extends StatelessWidget {
  const ConfirmOrderDialog({super.key, required this.quote, required this.shares});

  final Quote quote;
  final int shares;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Confirm order'),
    content: Text('Buy $shares shares of ${quote.symbol} at ${quote.price.toStringAsFixed(2)}?'),
    actions: <Widget>[
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Buy')),
    ],
  );
}

class TradeSheet extends StatelessWidget {
  const TradeSheet({super.key, required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: Icon(Icons.add_circle_outline, color: t.positive),
            title: Text('Buy ${quote.symbol}'),
          ),
          ListTile(
            leading: Icon(Icons.remove_circle_outline, color: t.negative),
            title: Text('Sell ${quote.symbol}'),
          ),
          const ListTile(leading: Icon(Icons.notifications_none), title: Text('Set a price alert')),
        ],
      ),
    );
  }
}

class OrderPlacedMessage extends StatelessWidget {
  const OrderPlacedMessage({super.key, required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) => Text('Order placed for $symbol');
}
