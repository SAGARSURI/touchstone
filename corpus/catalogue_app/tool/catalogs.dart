// The mutation and no-op refactor catalogs on the catalogue app (spec:
// Verification strategy, "Mutation catalog" and "No-op refactor catalog").
//
// Each entry is one source edit. tool/run_catalogs.dart applies it, captures
// the listed scenes with their oracle (pixels and semantics), and restores
// the source. Expected results are written here, before any diff engine
// exists, and are not edited to match what the tool reports.

/// One edit to a file: [find] must occur exactly once unless [all].
class Edit {
  const Edit(this.file, this.find, this.replace, {this.all = false});

  final String file;
  final String find;
  final String replace;
  final bool all;
}

/// What the oracle is expected to see.
enum Oracle {
  /// Pixels change.
  pixels,

  /// Only semantics change.
  semantics,

  /// Nothing changes: the edit is invisible in a widget test (for example a
  /// font weight drawn with the FlutterTest font).
  none,
}

class Entry {
  const Entry(this.id, this.kind, this.edits, this.scenes, {required this.oracle, this.expectNode});

  final String id;

  /// The catalog kind, in the spec's words.
  final String kind;
  final List<Edit> edits;
  final List<String> scenes;
  final Oracle oracle;

  /// The component type the change belongs to (A6): the first differing
  /// node should be of this type. Null for no-ops.
  final String? expectNode;
}

const String _settings = 'lib/screens/settings.dart';

const List<Entry> mutations = <Entry>[
  Entry(
    'colour-token',
    'colour or token',
    <Edit>[Edit('lib/tokens.dart', 'positive: Color(0xFF1E8E3E),', 'positive: Color(0xFF1E8E3F),')],
    <String>['watchlist/top'],
    oracle: Oracle.pixels,
    expectNode: 'ChangeBadge',
  ),
  Entry(
    'text',
    'text',
    <Edit>[Edit(_settings, "title: 'Linked accounts'", "title: 'Linked bank accounts'")],
    <String>['settings/default'],
    oracle: Oracle.pixels,
    expectNode: 'SettingsTile',
  ),
  Entry(
    'padding-1px',
    'padding by 1 px',
    <Edit>[
      Edit(
        'lib/components/section_header.dart',
        'EdgeInsets.fromLTRB(Space.m, Space.l, Space.m, Space.s)',
        'EdgeInsets.fromLTRB(Space.m, Space.l, Space.m, Space.s + 1)',
      ),
    ],
    <String>['buttons/all', 'settings/default'],
    oracle: Oracle.pixels,
    expectNode: 'SectionHeader',
  ),
  Entry(
    'size',
    'size',
    <Edit>[Edit('lib/components/settings_tile.dart', 'width: 36,', 'width: 37,')],
    <String>['settings/default'],
    oracle: Oracle.pixels,
    expectNode: 'SettingsIcon',
  ),
  Entry(
    'widget-added',
    'widget added',
    <Edit>[
      Edit(
        _settings,
        "const SectionHeader('About'),",
        "const SectionHeader('About'),\n          const SettingsTile(icon: Icons.lock_outline, title: 'Privacy'),",
      ),
    ],
    <String>['settings/default'],
    oracle: Oracle.pixels,
    expectNode: 'SettingsTile',
  ),
  Entry(
    'widget-removed',
    'widget removed',
    <Edit>[
      Edit(
        _settings,
        "          const SettingsTile(icon: Icons.description_outlined, title: 'Terms of service'),\n"
            '          const Divider(height: 1),\n',
        '',
      ),
    ],
    <String>['settings/default'],
    oracle: Oracle.pixels,
    expectNode: 'SettingsTile',
  ),
  Entry(
    'widget-reordered',
    'widget reordered',
    <Edit>[
      Edit(
        _settings,
        "          const SettingsTile(icon: Icons.person_outline, title: 'Profile', subtitle: 'Name, email, phone'),\n"
            '          const Divider(height: 1),\n'
            "          const SettingsTile(icon: Icons.account_balance_outlined, title: 'Linked accounts', trailingText: '2'),\n",
        "          const SettingsTile(icon: Icons.account_balance_outlined, title: 'Linked accounts', trailingText: '2'),\n"
            '          const Divider(height: 1),\n'
            "          const SettingsTile(icon: Icons.person_outline, title: 'Profile', subtitle: 'Name, email, phone'),\n",
      ),
    ],
    <String>['settings/default'],
    oracle: Oracle.pixels,
    expectNode: 'SettingsTile',
  ),
  Entry(
    'opacity',
    'opacity',
    <Edit>[
      Edit(
        'lib/components/status_view.dart',
        'Icon(icon, size: 48, color: t.textSecondary),',
        'Opacity(opacity: 0.6, child: Icon(icon, size: 48, color: t.textSecondary)),',
      ),
    ],
    <String>['states/empty', 'states/error'],
    oracle: Oracle.pixels,
    expectNode: 'StatusView',
  ),
  Entry(
    'clip',
    'clip',
    <Edit>[
      Edit(
        'lib/screens/detail.dart',
        "Image(image: image, fit: BoxFit.cover, semanticLabel: 'Company headquarters');",
        'ClipRRect(\n    borderRadius: BorderRadius.circular(24),\n'
            "    child: Image(image: image, fit: BoxFit.cover, semanticLabel: 'Company headquarters'),\n  );",
      ),
    ],
    <String>['detail/overview'],
    oracle: Oracle.pixels,
    expectNode: 'HeaderImage',
  ),
  Entry(
    'font-weight',
    'font weight',
    <Edit>[
      Edit(
        'lib/components/price_label.dart',
        'fontWeight: FontWeight.w600, color: t.textPrimary',
        'fontWeight: FontWeight.w700, color: t.textPrimary',
      ),
    ],
    <String>['watchlist/top'],
    // The FlutterTest font draws every weight the same (a declared limit).
    oracle: Oracle.none,
    expectNode: 'PriceLabel',
  ),
  Entry(
    'icon',
    'icon',
    <Edit>[Edit(_settings, 'icon: Icons.language,', 'icon: Icons.translate,')],
    <String>['settings/default'],
    oracle: Oracle.pixels,
    expectNode: 'SettingsIcon',
  ),
  Entry(
    'image',
    'image',
    <Edit>[
      Edit(
        'test/support/scenes.dart',
        'final image = MemoryImage(await headerImageBytes(tester));',
        'final image = MemoryImage(await headerImageBytes(tester, variant: true));',
      ),
    ],
    <String>['detail/overview'],
    oracle: Oracle.pixels,
    expectNode: 'HeaderImage',
  ),
  Entry(
    'enabled-state',
    'enabled state',
    <Edit>[
      Edit('lib/screens/button_set.dart', "label: 'Continue', enabled: false)", "label: 'Continue', enabled: true)"),
    ],
    <String>['buttons/all'],
    oracle: Oracle.pixels,
    expectNode: 'AppButton',
  ),
  Entry(
    'selected-state',
    'selected state',
    <Edit>[Edit(_settings, 'this.notifications = true', 'this.notifications = false')],
    <String>['settings/default'],
    oracle: Oracle.pixels,
    expectNode: 'SettingsTile',
  ),
  Entry(
    'semantics-label',
    'semantics label',
    <Edit>[Edit('lib/screens/detail.dart', "semanticLabel: 'Company headquarters'", "semanticLabel: 'Head office'")],
    <String>['detail/overview'],
    oracle: Oracle.semantics,
    expectNode: 'HeaderImage',
  ),
  Entry(
    'custom-painter',
    'CustomPainter output',
    <Edit>[Edit('lib/components/app_button.dart', 'value: 0.7,', 'value: 0.75,')],
    <String>['buttons/all'],
    oracle: Oracle.pixels,
    expectNode: '_Spinner',
  ),
  Entry(
    'theme',
    'theme',
    <Edit>[Edit('lib/tokens.dart', 'scaffoldBackgroundColor: t.surface,', 'scaffoldBackgroundColor: t.surfaceMuted,')],
    <String>['text/all', 'settings/default'],
    oracle: Oracle.pixels,
    expectNode: null,
  ),
];

/// Paint order is not in this catalog: levels 1 to 3 have no overlapping
/// sibling components. The fixture app's paint-order mutations cover it.

const List<Entry> noOps = <Entry>[
  Entry(
    'extract-widget',
    'extract a widget',
    <Edit>[
      Edit(
        'lib/components/watch_row.dart',
        '''          Expanded(
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
          ),''',
        '''          Expanded(child: QuoteNames(quote: quote)),''',
      ),
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
    ],
    <String>['watchlist/top'],
    oracle: Oracle.none,
  ),
  Entry(
    'inline-widget',
    'inline a widget',
    <Edit>[
      Edit('lib/components/settings_tile.dart', 'leading: SettingsIcon(icon: icon),', '''leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: t.surfaceMuted, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 20, color: t.brandAccent),
      ),'''),
    ],
    <String>['settings/default'],
    oracle: Oracle.none,
  ),
  Entry(
    'wrap-layout-neutral',
    'wrap in a layout-neutral widget',
    <Edit>[
      Edit(
        'lib/components/price_label.dart',
        'ChangeBadge(change: change, color: up ? t.positive : t.negative),',
        'RepaintBoundary(child: ChangeBadge(change: change, color: up ? t.positive : t.negative)),',
      ),
    ],
    <String>['watchlist/top', 'detail/overview'],
    oracle: Oracle.none,
  ),
  Entry(
    'add-const',
    'add const',
    <Edit>[
      Edit(
        'lib/components/status_view.dart',
        '            SizedBox(height: Space.m),',
        '            const SizedBox(height: Space.m),',
      ),
    ],
    <String>['states/empty', 'states/error'],
    oracle: Oracle.none,
  ),
  Entry(
    'stateless-to-stateful',
    'convert stateless to stateful',
    <Edit>[
      Edit(
        'lib/components/section_header.dart',
        'class SectionHeader extends StatelessWidget {',
        'class SectionHeader extends StatefulWidget {',
      ),
      Edit(
        'lib/components/section_header.dart',
        '  final String title;\n\n  @override\n  Widget build(BuildContext context) {',
        '  final String title;\n\n  @override\n  State<SectionHeader> createState() => _SectionHeaderState();\n}\n\n'
            'class _SectionHeaderState extends State<SectionHeader> {\n  String get title => widget.title;\n\n'
            '  @override\n  Widget build(BuildContext context) {',
      ),
    ],
    <String>['buttons/all', 'settings/default'],
    oracle: Oracle.none,
  ),
  Entry(
    'rename-class',
    'rename a class',
    <Edit>[Edit('lib/components/watch_row.dart', 'SymbolAvatar', 'TickerAvatar', all: true)],
    <String>['watchlist/top'],
    oracle: Oracle.none,
  ),
];
