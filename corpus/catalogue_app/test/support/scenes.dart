// The catalogue's captured states, shared by the snapshot tests, the repeat
// runs (A3), the golden comparison (A13) and the mutation generator.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalogue_app/catalogue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

/// A phone viewport: 390 x 844 logical pixels at 3x.
const Size phoneSize = Size(390, 844);
const double phoneDpr = 3;

/// One captured state of a catalogue screen.
class Scene {
  const Scene(this.id, this.level, this.pump, {this.atPumpedTime = false, this.theme = 'light'});

  /// Snapshot id: `<screen>/<state>`.
  final String id;
  final int level;

  /// Pumps the screen into this state. Leaves it settled unless
  /// [atPumpedTime].
  final Future<void> Function(WidgetTester tester, Widget Function(Widget) host) pump;
  final bool atPumpedTime;
  final String theme;

  String get state => id.split('/').last;

  SnapshotOptions get options =>
      SnapshotOptions(state: state, theme: theme, tokenResolver: tokenName, atPumpedTime: atPumpedTime);
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

/// Wraps a screen in the app's MaterialApp with the given theme.
Widget Function(Widget) hostFor({Brightness brightness = Brightness.light, AppTokens? tokens}) =>
    (Widget screen) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(brightness, tokens: tokens),
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

/// Levels 1 to 3 of the catalogue (spec, Catalogue scenarios).
final List<Scene> scenes = <Scene>[
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

/// Pumps [scene] on a phone viewport in the light theme.
Future<void> pumpScene(WidgetTester tester, Scene scene, {Widget Function(Widget)? host}) async {
  usePhone(tester);
  await scene.pump(tester, host ?? hostFor());
}
