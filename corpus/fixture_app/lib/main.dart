import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'screens.dart';

/// Runs the fixture screens as an app, for looking at them by eye.
void main() {
  final assets = FixtureAssets(imageA: Uint8List(0), imageB: Uint8List(0));
  runApp(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => ListView(
          children: <Widget>[
            for (final FixtureScreen s in fixtureScreens)
              if (!s.usesImages)
                ListTile(
                  title: Text(s.name),
                  onTap: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: s.build(s.knobs, assets)))),
                ),
          ],
        ),
      ),
    ),
  );
}
