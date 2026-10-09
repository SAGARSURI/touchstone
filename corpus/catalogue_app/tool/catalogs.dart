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
  const Entry(
    this.id,
    this.kind,
    this.edits,
    this.scenes, {
    required this.oracle,
    this.expectNode,
    this.expectTypes = const <String>[],
    this.expectShift,
  });

  final String id;

  /// The catalog kind, in the spec's words.
  final String kind;
  final List<Edit> edits;
  final List<String> scenes;
  final Oracle oracle;

  /// The component type the change belongs to (A6): the first differing
  /// node should be of this type. Null for no-ops.
  final String? expectNode;

  /// Phase 2: the change types (spec, Diff engine, "Change types") the report
  /// should give [expectNode], written before the diff engine existed. A
  /// mutation is attributed correctly when the report has a top-level item on
  /// a component of type [expectNode] with every type listed here.
  final List<String> expectTypes;

  /// Phase 2, cascade mutations (A8): whether the edit should shift other
  /// components. When true, every shift group in the report should name the
  /// [expectNode] component as its single root cause; when false, the report
  /// should have no shift group. Null for entries that are not cascades.
  final bool? expectShift;
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
    expectTypes: <String>['Style'],
  ),
  Entry(
    'text',
    'text',
    <Edit>[Edit(_settings, "title: 'Linked accounts'", "title: 'Linked bank accounts'")],
    <String>['settings/default'],
    oracle: Oracle.pixels,
    expectNode: 'SettingsTile',
    expectTypes: <String>['Content'],
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
    expectTypes: <String>['Layout'],
    expectShift: true,
  ),
  Entry(
    'size',
    'size',
    <Edit>[Edit('lib/components/settings_tile.dart', 'width: 36,', 'width: 37,')],
    <String>['settings/default'],
    oracle: Oracle.pixels,
    expectNode: 'SettingsIcon',
    expectTypes: <String>['Layout'],
    expectShift: false,
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
    expectTypes: <String>['Added'],
    expectShift: true,
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
    expectTypes: <String>['Removed'],
    expectShift: true,
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
    expectTypes: <String>['Reordered'],
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
    expectTypes: <String>['Style'],
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
    expectTypes: <String>['Style'],
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
    expectTypes: <String>['Style'],
  ),
  Entry(
    'icon',
    'icon',
    <Edit>[Edit(_settings, 'icon: Icons.language,', 'icon: Icons.translate,')],
    <String>['settings/default'],
    oracle: Oracle.pixels,
    expectNode: 'SettingsIcon',
    expectTypes: <String>['Content'],
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
    expectTypes: <String>['Content'],
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
    expectTypes: <String>['Style', 'Semantics'],
  ),
  Entry(
    'selected-state',
    'selected state',
    <Edit>[Edit(_settings, 'this.notifications = true', 'this.notifications = false')],
    <String>['settings/default'],
    oracle: Oracle.pixels,
    expectNode: 'SettingsTile',
    expectTypes: <String>['Style', 'Semantics'],
  ),
  Entry(
    'semantics-label',
    'semantics label',
    <Edit>[Edit('lib/screens/detail.dart', "semanticLabel: 'Company headquarters'", "semanticLabel: 'Head office'")],
    <String>['detail/overview'],
    oracle: Oracle.semantics,
    expectNode: 'HeaderImage',
    expectTypes: <String>['Semantics'],
  ),
  Entry(
    'custom-painter',
    'CustomPainter output',
    <Edit>[Edit('lib/components/app_button.dart', 'value: 0.7,', 'value: 0.75,')],
    <String>['buttons/all'],
    oracle: Oracle.pixels,
    expectNode: '_Spinner',
    expectTypes: <String>['Paint'],
  ),
  Entry(
    'theme',
    'theme',
    <Edit>[Edit('lib/tokens.dart', 'scaffoldBackgroundColor: t.surface,', 'scaffoldBackgroundColor: t.surfaceMuted,')],
    <String>['text/all', 'settings/default'],
    oracle: Oracle.pixels,
    expectNode: null,
    expectTypes: <String>['Style'],
  ),
];

/// Paint order is not in this catalog: levels 1 to 3 have no overlapping
/// sibling components. The fixture app's paint-order mutations cover it.

/// Cascade mutations for A8 (spec: "insert, remove and resize near the start
/// of columns, lists and stacks"), written before the diff engine existed.
/// [Entry.expectNode] is the component whose change is the root cause.
const List<Entry> cascades = <Entry>[
  // Column: the sign-in form.
  Entry(
    'column-insert-start',
    'insert near the start of a column',
    <Edit>[
      Edit(
        'lib/screens/sign_in.dart',
        "          children: <Widget>[\n            LabeledField(\n              key: const ValueKey<String>('email'),",
        "          children: <Widget>[\n            const SectionHeader('Welcome back'),\n"
            "            LabeledField(\n              key: const ValueKey<String>('email'),",
      ),
      Edit(
        'lib/screens/sign_in.dart',
        "import '../components/app_button.dart';",
        "import '../components/app_button.dart';\nimport '../components/section_header.dart';",
      ),
    ],
    <String>['sign_in/empty'],
    oracle: Oracle.pixels,
    expectNode: 'SectionHeader',
    expectTypes: <String>['Added'],
    expectShift: true,
  ),
  Entry(
    'column-remove-start',
    'remove near the start of a column',
    <Edit>[
      Edit(
        'lib/screens/sign_in.dart',
        "            LabeledField(\n              key: const ValueKey<String>('password'),\n"
            "              label: 'Password',\n              controller: _password,\n"
            '              obscure: true,\n              enabled: !submitting,\n            ),\n',
        '',
      ),
    ],
    <String>['sign_in/empty'],
    oracle: Oracle.pixels,
    expectNode: 'LabeledField',
    expectTypes: <String>['Removed'],
    expectShift: true,
  ),
  // Column: the text styles screen.
  Entry(
    'column-resize-start',
    'resize near the start of a column',
    <Edit>[
      Edit(
        'lib/screens/text_styles.dart',
        "Heading('Portfolio', style: text.headlineMedium),",
        "Heading('Portfolio', style: text.headlineLarge),",
      ),
    ],
    <String>['text/all'],
    oracle: Oracle.pixels,
    expectNode: 'Heading',
    expectTypes: <String>['Layout'],
    expectShift: true,
  ),
  Entry(
    'column-insert-first',
    'insert at the start of a column',
    <Edit>[
      Edit(
        'lib/screens/text_styles.dart',
        "            Heading('Portfolio', style: text.headlineMedium),",
        "            Heading('Overview', style: text.titleSmall),\n            Heading('Portfolio', style: text.headlineMedium),",
      ),
    ],
    <String>['text/all'],
    oracle: Oracle.pixels,
    expectNode: 'Heading',
    expectTypes: <String>['Added'],
    expectShift: true,
  ),
  Entry(
    'column-remove-first',
    'remove the first child of a column',
    <Edit>[Edit('lib/screens/text_styles.dart', "            Heading('Portfolio', style: text.headlineMedium),\n", '')],
    <String>['text/all'],
    oracle: Oracle.pixels,
    expectNode: 'Heading',
    expectTypes: <String>['Removed'],
    expectShift: true,
  ),
  // List: the settings list.
  Entry(
    'list-insert-start',
    'insert at the start of a list',
    <Edit>[
      Edit(
        _settings,
        "          const SectionHeader('Account'),",
        "          const SettingsTile(icon: Icons.star_outline, title: 'Upgrade'),\n          const SectionHeader('Account'),",
      ),
    ],
    <String>['settings/default'],
    oracle: Oracle.pixels,
    expectNode: 'SettingsTile',
    expectTypes: <String>['Added'],
    expectShift: true,
  ),
  Entry(
    'list-remove-start',
    'remove the first child of a list',
    <Edit>[Edit(_settings, "          const SectionHeader('Account'),\n", '')],
    <String>['settings/default'],
    oracle: Oracle.pixels,
    expectNode: 'SectionHeader',
    expectTypes: <String>['Removed'],
    expectShift: true,
  ),
  Entry(
    'list-resize-start',
    'resize near the start of a list',
    <Edit>[
      Edit(
        _settings,
        "SettingsTile(icon: Icons.person_outline, title: 'Profile', subtitle: 'Name, email, phone'),",
        "SettingsTile(icon: Icons.person_outline, title: 'Profile'),",
      ),
    ],
    <String>['settings/default'],
    oracle: Oracle.pixels,
    expectNode: 'SettingsTile',
    expectTypes: <String>['Layout'],
    expectShift: true,
  ),
  // List: the button set.
  Entry(
    'list-insert-first',
    'insert at the start of a list',
    <Edit>[
      Edit(
        'lib/screens/button_set.dart',
        "          SectionHeader('Primary'),",
        "          AppButton(key: ValueKey<String>('first'), label: 'Get started'),\n          SectionHeader('Primary'),",
      ),
    ],
    <String>['buttons/all'],
    oracle: Oracle.pixels,
    expectNode: 'AppButton',
    expectTypes: <String>['Added'],
    expectShift: true,
  ),
  Entry(
    'list-remove-first',
    'remove the first child of a list',
    <Edit>[Edit('lib/screens/button_set.dart', "          SectionHeader('Primary'),\n", '')],
    <String>['buttons/all'],
    oracle: Oracle.pixels,
    expectNode: 'SectionHeader',
    expectTypes: <String>['Removed'],
    expectShift: true,
  ),
  // Lazy list: the watchlist.
  Entry(
    'lazy-list-insert-first',
    'insert at the start of a lazy list',
    <Edit>[
      Edit(
        'lib/screens/watchlist.dart',
        ': quotes = quotes ?? seededQuotes();',
        ": quotes = quotes ?? <Quote>[Quote('NEW0', 'Newco Holdings', 12.5, 0.5), ...seededQuotes()];",
      ),
    ],
    <String>['watchlist/top'],
    oracle: Oracle.pixels,
    expectNode: 'WatchRow',
    expectTypes: <String>['Added'],
    expectShift: true,
  ),
  Entry(
    'lazy-list-remove-first',
    'remove the first child of a lazy list',
    <Edit>[
      Edit(
        'lib/screens/watchlist.dart',
        ': quotes = quotes ?? seededQuotes();',
        ': quotes = quotes ?? seededQuotes().skip(1).toList();',
      ),
    ],
    <String>['watchlist/top'],
    oracle: Oracle.pixels,
    expectNode: 'WatchRow',
    expectTypes: <String>['Removed'],
    expectShift: true,
  ),
  // Stack: test/support/cascade_stack.dart, since no catalogue screen has one.
  Entry(
    'stack-insert-first',
    'insert at the start of a stack',
    <Edit>[
      Edit(
        'test/support/cascade_stack.dart',
        '          // first child\n',
        "          // first child\n          const Positioned(top: 0, right: 0, child: SectionHeader('New')),\n",
      ),
    ],
    <String>['cascade/stack'],
    oracle: Oracle.pixels,
    expectNode: 'SectionHeader',
    expectTypes: <String>['Added'],
    expectShift: false,
  ),
  Entry(
    'stack-remove-first',
    'remove the first child of a stack',
    <Edit>[
      Edit(
        'test/support/cascade_stack.dart',
        "          const Positioned(top: 0, left: 0, child: SectionHeader('Pinned')),\n",
        '',
      ),
    ],
    <String>['cascade/stack'],
    oracle: Oracle.pixels,
    expectNode: 'SectionHeader',
    expectTypes: <String>['Removed'],
    expectShift: false,
  ),
  Entry(
    'stack-resize-first',
    'resize the first sizing child of a stack',
    <Edit>[
      Edit(
        'test/support/cascade_stack.dart',
        'width: 300,\n              height: 140,',
        'width: 320,\n              height: 160,',
      ),
    ],
    <String>['cascade/stack'],
    oracle: Oracle.pixels,
    expectNode: 'AppButton',
    expectTypes: <String>['Layout'],
    expectShift: true,
  ),
];

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
