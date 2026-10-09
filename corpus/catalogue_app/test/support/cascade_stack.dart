// A stack of catalogue components for the cascade mutations (A8), since no
// catalogue screen has a stack. Edited in place by tool/run_catalogs.dart.

import 'package:catalogue_app/catalogue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

import 'scenes.dart';

/// The stack sizes to its largest non-positioned child, the button. The price
/// label is centred in it and the badge is pinned to its bottom right corner,
/// so resizing the button moves both, by different amounts.
class CascadeStack extends StatelessWidget {
  const CascadeStack({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // first child
            const Positioned(top: 0, left: 0, child: SectionHeader('Pinned')),
            const SizedBox(
              width: 300,
              height: 140,
              child: AppButton(key: ValueKey<String>('sizing'), label: 'Back'),
            ),
            const PriceLabel(price: 12.5, change: 0.5),
            Positioned(bottom: 0, right: 0, child: ChangeBadge(change: -1.25, color: t.negative)),
          ],
        ),
      ),
    );
  }
}

/// Scenes used only by experiments, never recorded as baselines.
final List<Scene> experimentScenes = <Scene>[
  Scene('cascade/stack', 3, (WidgetTester t, Widget Function(Widget) h) async {
    await t.pumpWidget(h(const CascadeStack()));
    await settle(t);
  }),
];
