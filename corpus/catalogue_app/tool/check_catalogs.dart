// Checks that every catalog edit applies: each find string occurs exactly
// once (or at least once with `all`) in the current source. No source is
// changed.
//
//   dart run tool/check_catalogs.dart

import 'dart:io';

import 'catalogs.dart';

void main() {
  var bad = 0;
  for (final Entry e in <Entry>[...mutations, ...cascades, ...noOps]) {
    for (final Edit edit in e.edits) {
      final int count = edit.find.allMatches(File(edit.file).readAsStringSync()).length;
      if (count == 0 || (!edit.all && count != 1)) {
        stdout.writeln('${e.id}: "${edit.find.split('\n').first}" occurs $count times in ${edit.file}');
        bad++;
      }
    }
  }
  stdout.writeln(bad == 0 ? 'all edits apply' : '$bad edits do not apply');
  exitCode = bad == 0 ? 0 : 1;
}
