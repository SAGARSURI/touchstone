// dart run touchstone:update [--images] [flutter test arguments]
//
// Runs flutter test --update-goldens, which rewrites each snapshot only after
// the determinism gate passes, then prints the change report every rewritten
// snapshot will show in review (spec: Updating baselines), against HEAD.
// With --images, it also writes before, after and diff crops of the changed
// components against HEAD to build/touchstone/review, as review --images does.

import 'dart:io';

import 'package:touchstone/review.dart';

Future<void> main(List<String> arguments) async {
  final bool images = arguments.contains('--images');
  final List<String> args = <String>[
    for (final String a in arguments)
      if (a != '--images') a,
  ];
  final Process test = await Process.start(
    'flutter',
    <String>['test', '--update-goldens', ...args],
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final int code = await test.exitCode;
  stdout.writeln('\nWhat review will show against HEAD:\n');
  try {
    final ReviewResult result = review(base: 'HEAD', policy: loadPolicy());
    stdout.write(result.render());
    if (images) {
      final List<ItemCrops> crops = await renderCrops(result);
      stdout.writeln(
        crops.isEmpty
            ? 'Images: none, no snapshot needs review or fails.'
            : 'Images: build/touchstone/review/index.html (${crops.length} changed components)',
      );
    }
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exit(64);
  } on ProcessException catch (e) {
    stderr.writeln('${e.executable} ${e.arguments.join(' ')}: ${e.message}');
    exit(69);
  }
  exit(code);
}
