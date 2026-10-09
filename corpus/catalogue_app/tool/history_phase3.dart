// The catalogue history, changes 7 to 10 (spec: Catalogue scenarios,
// "Scripted changes"), with their expected results written before any of
// them runs. Changes 1 to 6 are in history.dart, frozen on 2026-10-07.
//
// FROZEN on 2026-10-09. test/history_test.dart pins this file's hash, so any
// edit shows up in review as a change to the frozen history.
//
// How the history runs in Phase 3 (doc/phase3/plan.md, step 3):
//
// - Changes 1 to 10 apply in order, each on top of the ones before it, as
//   commits do. A change whose expected result is a failure (6 and 9) would
//   not be merged, so the next change applies on top of the one before it.
// - Each change is compared with the state before it: every snapshot is
//   captured before and after on one host, diffed, and given a verdict by the
//   default policy plus the change's declared expectations, if any.
// - Changes 1 to 6 were written for the 15 snapshots of levels 1 to 3. They
//   also run over the 29 snapshots of levels 4 and 5, and their expected
//   results, as written, apply there unchanged.
// - The shadow pixel audit runs on every snapshot of every change: a
//   snapshot whose pixels or semantics changed while its root hash did not is
//   a capture gap (A4 on real code).

import 'catalogs.dart' show Edit;

/// The verdict a change is expected to get on the snapshots it touches.
enum Expect { pass, needsReview, fail, migration }

class Change {
  const Change(
    this.number,
    this.title,
    this.edits,
    this.expected, {
    this.verdict = Expect.needsReview,
    this.declared = '',
    this.toolchain,
  });

  final int number;

  /// The change in the spec's words.
  final String title;
  final List<Edit> edits;

  /// The spec's expected result, made concrete for this catalogue.
  final String expected;

  /// The verdict on every snapshot the change touches. Snapshots it does not
  /// touch must stay identical.
  final Expect verdict;

  /// The pull request's declared expectations, in the rules format.
  final String declared;

  /// For a toolchain change: the Flutter version the history moves to.
  final String? toolchain;
}

const List<Change> historyPhase3 = <Change>[
  Change(
    7,
    'Upgrade a design-library dependency that shifts default paddings',
    <Edit>[
      Edit(
        'lib/tokens.dart',
        '    extensions: <ThemeExtension<dynamic>>[t],\n',
        '    // Component defaults from the design library\'s new release.\n'
            '    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 20)),\n'
            '    inputDecorationTheme: const InputDecorationTheme(contentPadding: EdgeInsets.fromLTRB(12, 18, 12, 18)),\n'
            '    extensions: <ThemeExtension<dynamic>>[t],\n',
      ),
    ],
    'The catalogue has no third-party design library; its components take their defaults from the Material '
        'theme, so the upgrade is made where such a library\'s defaults land. List tiles get 4 px more '
        'horizontal padding and text fields 2 px more vertical padding on each side. Expected: many small '
        'layout changes, on every component built on a ListTile (SettingsTile, TradeSheet, BranchCard, the '
        'detail page\'s list tabs) or a text field (LabeledField), in every snapshot that shows one. Where a '
        'shift has exactly one component that changed its own layout as its candidate, such as the rows below a '
        'taller LabeledField, it is grouped under that cause. Where it has several, it lists them as possible '
        'causes, and where it has none it says the cause is unknown. No cause is stated as certain unless it '
        'is the component that changed. No component is added or removed, and no content changes.',
  ),
  Change(
    8,
    'Change one data point and the stroke width in the chart',
    <Edit>[
      Edit(
        'lib/screens/chart.dart',
        'Candle(103.20, 106.16, 102.00, 104.98),',
        'Candle(103.20, 106.16, 102.00, 105.98),',
      ),
      Edit('lib/screens/chart.dart', 'strokeWidth: 2);', 'strokeWidth: 3);'),
    ],
    'Day 15\'s close moves from 104.98 to 105.98, and the line is drawn 3 px wide instead of 2. Expected, in '
        'chart/default and chart/tooltip: a paint change on PriceChart@0 (the line) and PriceChart@1 (the '
        'candles), and on nothing else. Both draw paths, so they are pixel-hashed (A2 fallback) and the path '
        'fingerprint cannot name the change: each is flagged as unexplained paint. The tooltip (day 19) and the '
        'last close (day 30) are unchanged. Every other snapshot is identical.',
  ),
  Change(
    9,
    'Mix a refactor, an intended restyle and an accidental 1 px padding change in one pull request',
    <Edit>[
      // The refactor: the tile's trailing widget is extracted, with no visual effect.
      Edit(
        'lib/components/settings_tile.dart',
        '''      trailing: value != null
          ? Switch(value: value!, onChanged: (_) {})
          : trailingText != null
          ? Text(trailingText!, style: TextStyle(color: t.textSecondary))
          : Icon(Icons.chevron_right, color: t.textSecondary),
    );
  }
}''',
        '''      trailing: TileTrailing(value: value, text: trailingText),
    );
  }
}

class TileTrailing extends StatelessWidget {
  const TileTrailing({super.key, this.value, this.text});

  final bool? value;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return value != null
        ? Switch(value: value!, onChanged: (_) {})
        : text != null
        ? Text(text!, style: TextStyle(color: t.textSecondary))
        : Icon(Icons.chevron_right, color: t.textSecondary);
  }
}''',
      ),
      // The intended restyle: rounder change badges.
      Edit(
        'lib/components/price_label.dart',
        'borderRadius: BorderRadius.circular(4)',
        'borderRadius: BorderRadius.circular(8)',
      ),
      // The accidental change: 1 px more below every section header.
      Edit(
        'lib/components/section_header.dart',
        'EdgeInsets.fromLTRB(Space.m, Space.l, Space.m, Space.s)',
        'EdgeInsets.fromLTRB(Space.m, Space.l, Space.m, Space.s + 1)',
      ),
    ],
    'Three separate entries. The refactor is an identity change on each SettingsTile (TileTrailing added), '
        'listed as info. The restyle is a style change on each ChangeBadge, which the pull request declares. '
        'The padding is a layout change on each SectionHeader, with the components below it shifted 1 px as '
        'its consequences; it is outside the declared expectations and fails. Snapshots with a SectionHeader '
        'fail. Snapshots with ChangeBadges and no SectionHeader are needs-review. Snapshots with only the '
        'refactor pass.',
    verdict: Expect.fail,
    declared: 'expect ChangeBadge Style',
  ),
  Change(
    10,
    'Upgrade Flutter to the next stable release',
    <Edit>[],
    'Flutter 3.47.6 to 3.47.7, the next stable release when Phase 3 ran (a patch release). Every snapshot\'s '
        'toolchain fingerprint differs, so each is routed to migration and none is diffed. A snapshot whose '
        'pixels are identical on both releases re-baselines automatically, with the pixel proof attached. The '
        'rest go to review with their differences. Expected for a patch release: every snapshot pixel-identical, '
        'so all re-baseline automatically.',
    verdict: Expect.migration,
    toolchain: '3.47.7',
  ),
];
