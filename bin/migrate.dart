// dart run touchstone:migrate --from <old flutter executable> [flutter test arguments]
//
// Moves baselines to the toolchain `flutter` runs now (spec: A12). First the
// tests run on the old toolchain, where every snapshot that matches its
// baseline records the pixels of its test view. Then they run on this one,
// where every baseline from the old toolchain is rewritten with a pixel proof
// beside it. Prints what review will show against HEAD: pixel-identical
// snapshots pass, the rest need review.

import 'dart:io';

import 'package:touchstone/review.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2 || args.first != '--from') {
    stderr.writeln(usage);
    exit(64);
  }
  final String old = args[1];
  final List<String> testArgs = args.sublist(2);
  final Directory pending = Directory('build/touchstone/migration');
  if (pending.existsSync()) {
    pending.deleteSync(recursive: true);
  }

  stdout.writeln('On the old toolchain ($old): recording the pixels of every snapshot that matches its baseline.\n');
  final int proved = await _run(old, <String>['test', '--dart-define=TOUCHSTONE_MIGRATION=prove', ...testArgs]);
  if (proved != 0) {
    stdout.writeln(
      '\nSome tests failed on the old toolchain. Their snapshots get no pixel proof, so they will need review.',
    );
  }
  stdout.writeln('\nOn this toolchain: rewriting every baseline from the old one, with its pixel proof.\n');
  final int applied = await _run('flutter', <String>['test', '--dart-define=TOUCHSTONE_MIGRATION=apply', ...testArgs]);

  stdout.writeln('\nWhat review will show against HEAD:\n');
  try {
    stdout.write(review(base: 'HEAD', policy: loadPolicy()).render());
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exit(64);
  }
  exit(applied);
}

Future<int> _run(String flutter, List<String> args) async {
  final Process p = await Process.start(
    flutter,
    args,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  return p.exitCode;
}

const String usage = '''
Usage: dart run touchstone:migrate --from <old flutter executable> [flutter test arguments]

Run it with the new Flutter release on the PATH, and the old one's flutter
executable after --from. Baselines from the old release are rewritten; each
gets a .migration file beside it with the pixel proof. Commit both.''';
