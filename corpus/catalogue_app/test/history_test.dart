// The catalogue history (tool/history.dart) is frozen before the diff engine
// is built: its hash is pinned, and every change must still apply in order.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/catalogs.dart' show Edit;
import '../tool/history.dart';

/// sha256 of tool/history.dart when it was frozen on 2026-10-07.
const String frozenHash = 'f8ab80936ecafdac7246aef7421f57b00fca747b51503a8bb9f6ef7acdc44379';

void main() {
  test('the history is frozen', () {
    final String text = File('tool/history.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(sha256.convert(utf8.encode(text)).toString(), frozenHash);
  });

  test('changes 1 to 6 apply in order to the current catalogue', () {
    final files = <String, String>{};
    for (final Change change in history) {
      for (final Edit edit in change.edits) {
        final String text = files[edit.file] ??= File(edit.file).readAsStringSync();
        final int count = edit.find.allMatches(text).length;
        expect(count, edit.all ? greaterThan(0) : 1, reason: 'change ${change.number}: "${edit.find}"');
        files[edit.file] = text.replaceAll(edit.find, edit.replace);
      }
    }
    expect(history.map((Change c) => c.number), <int>[1, 2, 3, 4, 5, 6]);
  });
}
