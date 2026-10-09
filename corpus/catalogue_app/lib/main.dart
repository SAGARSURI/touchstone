import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'catalogue.dart';

void main() => runApp(const CatalogueApp());

class CatalogueApp extends StatelessWidget {
  const CatalogueApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: supportedLocales,
    home: const _Index(),
  );
}

class _Index extends StatelessWidget {
  const _Index();

  @override
  Widget build(BuildContext context) {
    final Map<String, WidgetBuilder> screens = <String, WidgetBuilder>{
      'Buttons': (_) => const ButtonSetScreen(),
      'Text': (_) => const TextStylesScreen(),
      'Settings': (_) => const SettingsScreen(),
      'Sign in': (_) => const SignInScreen(),
      'Watchlist': (_) => WatchlistScreen(),
      'Detail': (_) => DetailScreen(
        quote: seededQuotes().first,
        image: const NetworkImage('https://picsum.photos/seed/touchstone/800/400'),
      ),
      'Empty': (_) => const StatesScreen(state: LoadState.empty),
      'Loading': (_) => const StatesScreen(state: LoadState.loading),
      'Error': (_) => const StatesScreen(state: LoadState.error),
      'Overlays': (_) => OverlaysScreen(quote: seededQuotes()[3]),
      'Chart': (_) => ChartScreen(selected: 18),
      'Live prices': (_) => LivePricesScreen(),
      'Map': (_) => MapScreen(),
      'Order flow': (_) => const OrderFlowScreen(),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Catalogue')),
      body: ListView(
        children: <Widget>[
          for (final MapEntry<String, WidgetBuilder> e in screens.entries)
            ListTile(
              title: Text(e.key),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: e.value)),
            ),
        ],
      ),
    );
  }
}
