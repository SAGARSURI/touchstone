// dart run touchstone:update [flutter test arguments]
//
// Runs flutter test --update-goldens, which rewrites each snapshot only after
// the determinism gate passes, then prints the change report every rewritten
// snapshot will show in review (spec: Updating baselines), against HEAD.

import 'dart:io';

import 'package:touchstone/review.dart';

Future<void> main(List<String> args) async {
  final Process test = await Process.start(
    'flutter',
    <String>['test', '--update-goldens', ...args],
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final int code = await test.exitCode;
  stdout.writeln('\nWhat review will show against HEAD:\n');
  try {
    stdout.write(review(base: 'HEAD', policy: loadPolicy()).render());
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exit(64);
  }
  exit(code);
}
