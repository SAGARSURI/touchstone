// dart run touchstone:review [--base <git ref>] [--rules <file>] [--expect <file>] [--images]
//
// Compares every snapshot file in this package with its version at the base
// ref (the pull request's target branch) and prints each change report with
// its verdict. With --images, it also renders each snapshot that needs review
// or fails, at the base and in the working tree, and writes before, after and
// diff crops of the changed components to build/touchstone/review. Exit code:
// 0 pass, 1 fail, 2 needs-review; crops never change it.

import 'dart:io';

import 'package:touchstone/review.dart';

Future<void> main(List<String> args) async {
  final Map<String, String> options;
  try {
    options = parseOptions(args, const <String>{'base', 'rules', 'expect'}, flags: const <String>{'images'});
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n$usage');
    exit(64);
  }
  try {
    final Policy policy = loadPolicy(rules: options['rules'], expectations: options['expect']);
    final ReviewResult result = review(base: options['base'] ?? 'HEAD', policy: policy);
    stdout.write(result.render(color: useColor(out: stdout)));
    if (options['images'] != null) {
      await writeImages(result);
    }
    exit(result.exitCode);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exit(64);
  } on ProcessException catch (e) {
    stderr.writeln('${e.executable} ${e.arguments.join(' ')}: ${e.message}');
    exit(69);
  }
}

const String usage = '''
Usage: dart run touchstone:review [--base <git ref>] [--rules <file>] [--expect <file>] [--images]

  --base    the ref to compare with, normally the target branch (default HEAD)
  --rules   project rules (default touchstone.rules, when present)
  --expect  the pull request's declared expectations, one "expect <component> <change type>" per line
  --images  also write before, after and diff crops of each changed component to
            build/touchstone/review (open index.html there); for reviewers only

Exit code: 0 pass, 1 fail, 2 needs-review.''';
