// A14: snapshots captured from web pages by corpus/web_prototype are schema
// v1. Parsing recomputes every hash, so a web capture that left a required
// field out, or hashed it differently, fails here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/touchstone.dart';

void main() {
  final List<File> files = Directory('corpus/web_prototype/snapshots').listSync().whereType<File>().toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  test('there are five web prototype snapshots', () => expect(files, hasLength(5)));

  for (final File f in files) {
    test('${f.uri.pathSegments.last} parses as schema v1 with every field set', () {
      final Snapshot s = Snapshot.parse(f.readAsStringSync());
      expect(s.toCanonical(), f.readAsStringSync());
      for (final String key in <String>['viewport', 'platform', 'locale', 'textScale', 'brightness']) {
        expect(s.inputs[key], isNotEmpty, reason: 'input $key');
      }
      for (final (String id, SnapshotNode n) in s.walk()) {
        for (final (String field, String value) in <(String, String)>[
          ('bounds', n.bounds),
          ('paint', n.paint),
          ('semantics', n.semantics),
          ('opaque', n.opaque),
          ('type', n.type),
          ('style', n.style),
        ]) {
          expect(value, isNotEmpty, reason: '$id.$field');
        }
      }
      // Non-empty is not enough: every screen has text, so some node must
      // carry an accessible name (the web's label, per the A14 mapping) and
      // some node a style.
      expect(s.walk().any(((String, SnapshotNode) e) => e.$2.semantics.contains('"name"')), isTrue);
      expect(s.walk().any(((String, SnapshotNode) e) => e.$2.style != '{}' && e.$2.style != '-'), isTrue);
    });
  }
}
