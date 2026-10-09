// The catalogue history, changes 1 to 6 (spec: Catalogue scenarios,
// "Scripted changes"). Each change is one commit, applied in order on top of
// the previous ones, and its expected result is written here before the diff
// engine exists (Phase 2).
//
// FROZEN on 2026-10-07. test/history_test.dart pins this file's hash, so any
// edit shows up in review as a change to the frozen history.

import 'catalogs.dart' show Edit;

class Change {
  const Change(this.number, this.title, this.edits, this.scenes, this.expected);

  final int number;

  /// The change in the spec's words.
  final String title;
  final List<Edit> edits;

  /// Snapshots the change is run against.
  final List<String> scenes;

  /// The spec's expected result, made concrete for this catalogue.
  final String expected;
}

const List<String> _all = <String>[
  'buttons/all',
  'text/all',
  'settings/default',
  'sign_in/empty',
  'sign_in/focused',
  'sign_in/error',
  'sign_in/submitting',
  'watchlist/top',
  'watchlist/scrolled',
  'detail/overview',
  'detail/news',
  'detail/collapsed',
  'states/empty',
  'states/error',
  'states/loading',
];

const List<Change> history = <Change>[
  Change(
    1,
    'Change one colour token',
    <Edit>[Edit('lib/tokens.dart', 'brandAccent: Color(0xFF3949AB),', 'brandAccent: Color(0xFF3F51B5),')],
    _all,
    'Light theme brand.accent changes. It also seeds the Material colour scheme, so framework colours derived '
        'from it change too (app bars, switches, text field outlines, the tab indicator). Expected: a style change '
        'on each affected component, grouped under one cause, brand.accent, across all snapshots. No component is '
        'added, removed or moved.',
  ),
  Change(
    2,
    'Extract a widget and rename a class, with no visual effect',
    <Edit>[
      Edit('lib/components/watch_row.dart', '''          Expanded(
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
          ),''', '          Expanded(child: QuoteNames(quote: quote)),'),
      Edit(
        'lib/components/watch_row.dart',
        'class SymbolAvatar extends StatelessWidget {',
        '''class QuoteNames extends StatelessWidget {
  const QuoteNames({super.key, required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Column(
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
    );
  }
}

class SymbolAvatar extends StatelessWidget {''',
      ),
      Edit('lib/components/watch_row.dart', 'SymbolAvatar', 'TickerAvatar', all: true),
    ],
    <String>['watchlist/top', 'watchlist/scrolled'],
    'Pass. Identity changes listed as info: QuoteNames appears inside each WatchRow, SymbolAvatar is now '
        'TickerAvatar. Pixels and semantics are unchanged.',
  ),
  Change(
    3,
    'Add a promo banner above the watchlist',
    <Edit>[
      Edit(
        'lib/screens/watchlist.dart',
        '          SliverPersistentHeader(pinned: true, delegate: _HeaderDelegate(AppTokens.of(context))),\n',
        '          const SliverToBoxAdapter(child: PromoBanner()),\n'
            '          SliverPersistentHeader(pinned: true, delegate: _HeaderDelegate(AppTokens.of(context))),\n',
      ),
      Edit(
        'lib/screens/watchlist.dart',
        'class WatchlistHeader extends StatelessWidget {',
        '''class PromoBanner extends StatelessWidget {
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

class WatchlistHeader extends StatelessWidget {''',
      ),
    ],
    <String>['watchlist/top', 'watchlist/scrolled'],
    'One added component, PromoBanner. The header and the rows below it move down; they are folded in as '
        'consequences of the addition, not listed as separate changes. Rows that scroll out of the built range '
        'are reported as consequences too.',
  ),
  Change(
    4,
    'Remove a semantics label, leaving pixels unchanged',
    <Edit>[
      Edit(
        'lib/screens/detail.dart',
        "Image(image: image, fit: BoxFit.cover, semanticLabel: 'Company headquarters')",
        'Image(image: image, fit: BoxFit.cover)',
      ),
    ],
    <String>['detail/overview', 'detail/news', 'detail/collapsed'],
    'A semantics change on HeaderImage is reported (label removed). The pixel oracle sees nothing.',
  ),
  Change(
    5,
    'Add longer strings for a new locale',
    <Edit>[
      Edit(
        'lib/screens/settings.dart',
        "AppBar(title: const Text('Settings'))",
        "AppBar(title: const Text('Einstellungen'))",
      ),
      Edit("lib/screens/settings.dart", "title: 'Linked accounts'", "title: 'Verknüpfte Bankkonten und Depots'"),
      Edit(
        "lib/screens/settings.dart",
        "title: 'Unlock with biometrics'",
        "title: 'Mit biometrischen Daten entsperren'",
      ),
      Edit(
        "lib/screens/settings.dart",
        "subtitle: 'Name, email, phone'",
        "subtitle: 'Name, E-Mail-Adresse, Telefonnummer'",
      ),
      Edit('lib/screens/button_set.dart', "label: 'Continue'", "label: 'Weiter zur Zahlungsbestätigung'", all: true),
    ],
    <String>['settings/default', 'buttons/all'],
    'Content changes on each relabelled component (the settings tiles, the app bar title and the three '
        'Continue buttons). Where the German string wraps, the tile grows and later tiles move as consequences; '
        'where a button label overflows, the overflow is reported on that AppButton.',
  ),
  Change(
    6,
    'Introduce an unsettled animation or a wall-clock read in a test',
    <Edit>[
      Edit(
        'lib/components/app_button.dart',
        'const CircularProgressIndicator(value: 0.7, strokeWidth: 2.5)',
        'const CircularProgressIndicator(strokeWidth: 2.5)',
      ),
    ],
    <String>['buttons/all'],
    'The capture fails at the determinism gate. The message names root/ButtonSetScreen@0/AppButton#loading '
        '(the spinner now animates forever) and the cause, an animation still running. No baseline is written.',
  ),
];
