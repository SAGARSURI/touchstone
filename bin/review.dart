// dart run touchstone:review [--base <git ref>] [--rules <file>] [--expect <file>]
//
// Compares every snapshot file in this package with its version at the base
// ref (the pull request's target branch) and prints each change report with
// its verdict. Exit code: 0 pass, 1 fail, 2 needs-review.

import 'dart:io';

import 'package:touchstone/review.dart';

void main(List<String> args) {
  final Map<String, String> options;
  try {
    options = parseOptions(args, const <String>{'base', 'rules', 'expect'});
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n$usage');
    exit(64);
  }
  try {
    final Policy policy = loadPolicy(rules: options['rules'], expectations: options['expect']);
    final ReviewResult result = review(base: options['base'] ?? 'HEAD', policy: policy);
    stdout.write(result.render());
    exit(result.exitCode);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exit(64);
  } on ProcessException catch (e) {
    stderr.writeln('git ${e.arguments.join(' ')}: ${e.message}');
    exit(69);
  }
}

const String usage = '''
Usage: dart run touchstone:review [--base <git ref>] [--rules <file>] [--expect <file>]

  --base    the ref to compare with, normally the target branch (default HEAD)
  --rules   project rules (default touchstone.rules, when present)
  --expect  the pull request's declared expectations, one "expect <component> <change type>" per line

Exit code: 0 pass, 1 fail, 2 needs-review.''';
