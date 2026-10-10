// The catalogue history is frozen before it runs: changes 1 to 6
// (tool/history.dart) before the diff engine was built, and changes 7 to 10
// (tool/history_phase3.dart) before Phase 3 ran them. Each file's hash is
// pinned, and every change must still apply in order.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/catalogs.dart' show Edit;
import '../tool/history.dart';
import '../tool/history_phase3.dart' as phase3;

/// sha256 of tool/history.dart when it was frozen on 2026-10-07.
const String frozenHash = 'f8ab80936ecafdac7246aef7421f57b00fca747b51503a8bb9f6ef7acdc44379';

/// sha256 of tool/history_phase3.dart when it was frozen on 2026-10-09.
const String frozenHashPhase3 = '29a31f6fcc56736f670008c4c63416e4ab2e36b45dbbc1c8bec71eb07417a73d';

String _hash(String path) =>
    sha256.convert(utf8.encode(File(path).readAsStringSync().replaceAll('\r\n', '\n'))).toString();

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

  test('changes 7 to 10 are frozen', () {
    expect(_hash('tool/history_phase3.dart'), frozenHashPhase3);
  });

  test('changes 7 to 10 apply in order on top of 1 to 5', () {
    // A change expected to fail (6 and 9) is not merged: the next change
    // applies on top of the one before it.
    final files = <String, String>{};
    void apply(int number, List<Edit> edits) {
      for (final Edit edit in edits) {
        final String text = files[edit.file] ??= File(edit.file).readAsStringSync();
        final int count = edit.find.allMatches(text).length;
        expect(count, edit.all ? greaterThan(0) : 1, reason: 'change $number: "${edit.find}"');
        files[edit.file] = text.replaceAll(edit.find, edit.replace);
      }
    }

    for (final Change change in history.where((Change c) => c.number != 6)) {
      apply(change.number, change.edits);
    }
    for (final phase3.Change change in phase3.historyPhase3) {
      final Map<String, String> before = Map<String, String>.of(files);
      apply(change.number, change.edits);
      if (change.number == 9) {
        files
          ..clear()
          ..addAll(before);
      }
    }
    expect(phase3.historyPhase3.map((phase3.Change c) => c.number), <int>[7, 8, 9, 10]);
  });
}
