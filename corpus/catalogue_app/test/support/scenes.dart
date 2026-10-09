// The catalogue's captured states, shared by the snapshot tests, the repeat
// runs (A3), the golden comparison (A13) and the mutation generator.

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalogue_app/catalogue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

/// A phone viewport: 390 x 844 logical pixels at 3x.
const Size phoneSize = Size(390, 844);
const double phoneDpr = 3;

/// One captured state of a catalogue screen.
class Scene {
  const Scene(
    this.id,
    this.level,
    this.pump, {
    this.atPumpedTime = false,
    this.theme = 'light',
    this.dynamicComponents = const <String>{},
  });

  /// Snapshot id: `<screen>/<state>`.
  final String id;
  final int level;

  /// Pumps the screen into this state. Leaves it settled unless
  /// [atPumpedTime].
  final Future<void> Function(WidgetTester tester, Widget Function(Widget) host) pump;
  final bool atPumpedTime;
  final String theme;

  /// Components whose content changes from run to run in the app.
  final Set<String> dynamicComponents;

  String get state => id.split('/').last;

  SnapshotOptions get options => SnapshotOptions(
    state: state,
    theme: theme,
    tokenResolver: tokenName,
    atPumpedTime: atPumpedTime,
    dynamicComponents: dynamicComponents,
  );
}

/// Names the design token behind a colour, for the style field.
String? tokenName(Object value) {
  final Color? color = switch (value) {
    Color c => c,
    BoxDecoration d => d.color,
    _ => null,
  };
  if (color == null) {
    return null;
  }
  for (final AppTokens t in <AppTokens>[AppTokens.light, AppTokens.dark]) {
    for (final MapEntry<String, Color> e in t.named.entries) {
      if (e.value == color) {
        return e.key;
      }
    }
  }
  return null;
}

/// Sets the phone viewport for the rest of the test.
void usePhone(WidgetTester tester) {
  tester.view.physicalSize = phoneSize * phoneDpr;
  tester.view.devicePixelRatio = phoneDpr;
  addTearDown(tester.view.reset);
}

/// Wraps a screen in the app's MaterialApp with the given theme. With
/// [localized], the locale comes from the platform as in the app (English, or
/// Arabic for right-to-left); levels 1 to 3 predate it and keep the default
/// English localizations.
Widget Function(Widget) hostFor({
  Brightness brightness = Brightness.light,
  AppTokens? tokens,
  bool localized = false,
}) =>
    (Widget screen) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(brightness, tokens: tokens),
      localizationsDelegates: localized ? GlobalMaterialLocalizations.delegates : null,
      supportedLocales: localized ? supportedLocales : const <Locale>[Locale('en', 'US')],
      home: screen,
    );

/// A small, deterministic PNG standing in for the detail page's network image.
Future<Uint8List> headerImageBytes(WidgetTester tester, {bool variant = false}) async {
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var y = 0; y < 10; y++) {
      for (var x = 0; x < 20; x++) {
        canvas.drawRect(
          Rect.fromLTWH(x * 4.0, y * 4.0, 4, 4),
          Paint()..color = Color.fromARGB(255, 40 + x * 8, 60 + y * 12, 140 + (x + y) * 3),
        );
      }
    }
    if (variant) {
      canvas.drawRect(const Rect.fromLTWH(40, 20, 1, 1), Paint()..color = const Color(0xFFFFFFFF));
    }
    final ui.Image image = await recorder.endRecording().toImage(80, 40);
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }))!;
}

Future<void> _pumpSettled(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(screen);
  await settle(tester);
}

Future<void> _detail(WidgetTester tester, Widget Function(Widget) host, {int tab = 0, double scroll = 0}) async {
  final image = MemoryImage(await headerImageBytes(tester));
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    host(DetailScreen(quote: seededQuotes().first, image: image, initialTab: tab, controller: controller)),
  );
  await precacheImages(tester, <ImageProvider>[image]);
  if (scroll > 0) {
    controller.jumpTo(scroll);
  }
  await settle(tester);
}

Future<void> _watchlist(WidgetTester tester, Widget Function(Widget) host, {double scroll = 0}) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(host(WatchlistScreen(controller: controller)));
  if (scroll > 0) {
    controller.jumpTo(scroll);
  }
  await settle(tester);
}

/// Every level of the catalogue (spec, Catalogue scenarios).
final List<Scene> scenes = <Scene>[...levelsOneToThree, ...levelsFourAndFive];

/// Levels 1 to 3, captured since Phase 1.
final List<Scene> levelsOneToThree = <Scene>[
  Scene('buttons/all', 1, (WidgetTester t, h) => _pumpSettled(t, h(const ButtonSetScreen()))),
  Scene('text/all', 1, (WidgetTester t, h) => _pumpSettled(t, h(const TextStylesScreen()))),
  Scene('settings/default', 2, (WidgetTester t, h) => _pumpSettled(t, h(const SettingsScreen()))),
  for (final SignInState s in SignInState.values)
    Scene('sign_in/${s.name}', 2, (WidgetTester t, h) async {
      if (s == SignInState.focused) {
        // The software keyboard's inset.
        t.view.viewInsets = const FakeViewPadding(bottom: 300 * phoneDpr);
      }
      await _pumpSettled(t, h(SignInScreen(state: s)));
    }),
  Scene('watchlist/top', 3, (WidgetTester t, h) => _watchlist(t, h)),
  Scene('watchlist/scrolled', 3, (WidgetTester t, h) => _watchlist(t, h, scroll: 1500)),
  Scene('detail/overview', 3, (WidgetTester t, h) => _detail(t, h)),
  Scene('detail/news', 3, (WidgetTester t, h) => _detail(t, h, tab: 1)),
  Scene('detail/collapsed', 3, (WidgetTester t, h) => _detail(t, h, scroll: 300)),
  Scene('states/empty', 3, (WidgetTester t, h) => _pumpSettled(t, h(const StatesScreen(state: LoadState.empty)))),
  Scene('states/error', 3, (WidgetTester t, h) => _pumpSettled(t, h(const StatesScreen(state: LoadState.error)))),
  Scene('states/loading', 3, (WidgetTester t, h) async {
    await t.pumpWidget(h(const StatesScreen(state: LoadState.loading)));
    // The shimmer repeats forever: capture 300 ms into it.
    await t.pump(const Duration(milliseconds: 300));
  }, atPumpedTime: true),
];

/// A matrix variant (spec, level 4): theme, direction, text scale or viewport.
class Variant {
  const Variant(this.name, {this.dark = false, this.rtl = false, this.textScale = 1, this.size, this.dpr});

  final String name;
  final bool dark;
  final bool rtl;
  final double textScale;
  final Size? size;
  final double? dpr;

  /// Sets the platform's locale, text scale and viewport for the rest of the
  /// test, and returns the host for the theme.
  Widget Function(Widget) apply(WidgetTester tester) {
    if (rtl) {
      tester.platformDispatcher.localeTestValue = const Locale('ar');
      tester.platformDispatcher.localesTestValue = const <Locale>[Locale('ar')];
    }
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
    }
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    if (size != null) {
      tester.view.physicalSize = size! * dpr!;
      tester.view.devicePixelRatio = dpr!;
    }
    return hostFor(brightness: dark ? Brightness.dark : Brightness.light, localized: true);
  }
}

const List<Variant> variants = <Variant>[
  Variant('dark', dark: true),
  Variant('rtl', rtl: true),
  Variant('text_2x', textScale: 2),
  Variant('small', size: Size(320, 568), dpr: 2),
  Variant('large', size: Size(1024, 1366), dpr: 2),
];

/// The live price list's fixed clock.
final DateTime liveClock = DateTime(2026, 10, 9, 9, 30);

Future<void> _live(WidgetTester tester, Widget Function(Widget) host, {int ticks = 0, Duration? flashAt}) =>
    withFixedClock(liveClock, () async {
      await tester.pumpWidget(host(LivePricesScreen(random: Random(3))));
      for (int i = 0; i < ticks; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      if (flashAt != null) {
        await tester.pump(flashAt);
      } else {
        await settle(tester);
      }
    });

/// Taps through the order flow up to [step]: 1 symbol, 2 amount, 3 review,
/// 4 done.
Future<void> _order(WidgetTester tester, Widget Function(Widget) host, int step) async {
  await tester.pumpWidget(host(const OrderFlowScreen()));
  await settle(tester);
  if (step >= 2) {
    await tester.tap(find.byKey(const ValueKey<String>('pick ACM0')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('shares 25')));
    await settle(tester);
  }
  if (step >= 3) {
    await tester.tap(find.byKey(const ValueKey<String>('to review')));
    await settle(tester);
  }
  if (step >= 4) {
    await tester.tap(find.byKey(const ValueKey<String>('place order')));
    await settle(tester);
  }
}

/// Levels 4 and 5, added in Phase 3.
final List<Scene> levelsFourAndFive = <Scene>[
  for (final OverlayKind k in <OverlayKind>[OverlayKind.dialog, OverlayKind.sheet, OverlayKind.snackbar])
    Scene(
      'overlays/${k.name}',
      4,
      (WidgetTester t, h) => _pumpSettled(t, h(OverlaysScreen(quote: seededQuotes()[3], open: k))),
    ),
  Scene('overlays/dropdown', 4, (WidgetTester t, h) async {
    await _pumpSettled(t, h(OverlaysScreen(quote: seededQuotes()[3])));
    await t.tap(find.byType(SortDropdown));
    await settle(t);
  }),
  for (final Variant v in variants) ...<Scene>[
    Scene(
      'matrix/settings_${v.name}',
      4,
      (WidgetTester t, h) => _pumpSettled(t, v.apply(t)(const SettingsScreen())),
      theme: v.dark ? 'dark' : 'light',
    ),
    Scene(
      'matrix/sign_in_${v.name}',
      4,
      (WidgetTester t, h) => _pumpSettled(t, v.apply(t)(const SignInScreen(state: SignInState.error))),
      theme: v.dark ? 'dark' : 'light',
    ),
  ],
  Scene('chart/default', 5, (WidgetTester t, h) => _pumpSettled(t, h(ChartScreen()))),
  Scene('chart/tooltip', 5, (WidgetTester t, h) => _pumpSettled(t, h(ChartScreen(selected: 18)))),
  Scene('live/initial', 5, (WidgetTester t, h) => _live(t, h), dynamicComponents: const <String>{'LivePrice'}),
  Scene('live/ticked', 5, (WidgetTester t, h) => _live(t, h, ticks: 3), dynamicComponents: const <String>{'LivePrice'}),
  Scene(
    'live/flashing',
    5,
    (WidgetTester t, h) => _live(t, h, ticks: 1, flashAt: const Duration(milliseconds: 150)),
    atPumpedTime: true,
    dynamicComponents: const <String>{'LivePrice'},
  ),
  Scene('map/default', 5, (WidgetTester t, h) => _pumpSettled(t, h(MapScreen()))),
  Scene('order/symbol', 5, (WidgetTester t, h) => _order(t, h, 1)),
  Scene('order/amount', 5, (WidgetTester t, h) => _order(t, h, 2)),
  Scene('order/review', 5, (WidgetTester t, h) => _order(t, h, 3)),
  Scene('order/done', 5, (WidgetTester t, h) => _order(t, h, 4)),
  Scene('order/transition', 5, (WidgetTester t, h) async {
    await _order(t, h, 3);
    await t.tap(find.byKey(const ValueKey<String>('place order')));
    // Halfway through the page transition.
    await t.pump();
    await t.pump(const Duration(milliseconds: 150));
  }, atPumpedTime: true),
  Scene('order/dragging', 5, (WidgetTester t, h) async {
    await _order(t, h, 3);
    // Holds the first basket row halfway past the second; the gesture is not
    // released, so the capture sees the drag state.
    final TestGesture drag = await t.startGesture(t.getCenter(find.byKey(const ValueKey<String>('drag KES0'))));
    await drag.moveBy(const Offset(0, 40));
    await t.pump();
    await drag.moveBy(const Offset(0, 40));
    await settle(t);
  }),
];

/// Pumps [scene] on a phone viewport in the light theme.
Future<void> pumpScene(WidgetTester tester, Scene scene, {Widget Function(Widget)? host}) async {
  usePhone(tester);
  await scene.pump(tester, host ?? hostFor());
}
