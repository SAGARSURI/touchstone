import 'package:flutter/material.dart';

import '../tokens.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.l, Space.m, Space.s),
      child: Semantics(
        header: true,
        child: Text(
          title.toUpperCase(),
          style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: t.textSecondary),
        ),
      ),
    );
  }
}
