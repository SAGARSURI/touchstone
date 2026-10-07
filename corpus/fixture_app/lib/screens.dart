import 'fixture.dart';
import 'screens/basic_screens.dart';
import 'screens/kind_screens.dart';
import 'screens/rich_screens.dart';

export 'fixture.dart';

/// Every fixture screen, in the order the harness runs them.
final List<FixtureScreen> fixtureScreens = <FixtureScreen>[
  textScreen,
  decoratedScreen,
  effectsScreen,
  imageScreen,
  listScreen,
  chartScreen,
  platformViewScreen,
  themedScreen,
  overlayScreen,
  kindsScreen,
];
