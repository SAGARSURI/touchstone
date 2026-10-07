import 'package:flutter/material.dart';

import '../tokens.dart';

const String longParagraph =
    'Markets opened higher this morning as investors weighed new data on '
    'inflation and employment. Analysts expect volatility to remain elevated '
    'through the end of the quarter, with technology and energy leading the '
    'moves in both directions while bond yields drift lower.';

/// Level 1: headings, body and a long paragraph that wraps and truncates.
class TextStylesScreen extends StatelessWidget {
  const TextStylesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Text')),
      body: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Heading('Portfolio', style: text.headlineMedium),
            Heading('Today', style: text.titleLarge),
            const SizedBox(height: Space.s),
            BodyText('Your balance is up across 4 of 5 holdings.', color: t.textPrimary),
            const SizedBox(height: Space.m),
            BodyText(longParagraph, color: t.textSecondary),
            const SizedBox(height: Space.m),
            BodyText(longParagraph, color: t.textSecondary, maxLines: 2),
          ],
        ),
      ),
    );
  }
}

class Heading extends StatelessWidget {
  const Heading(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: style?.copyWith(color: AppTokens.of(context).textPrimary)),
  );
}

class BodyText extends StatelessWidget {
  const BodyText(this.text, {super.key, required this.color, this.maxLines});

  final String text;
  final Color color;

  /// When set, the text is truncated with an ellipsis.
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    style: TextStyle(fontSize: 14, height: 1.4, color: color),
  );
}
