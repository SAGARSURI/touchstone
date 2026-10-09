// Turns failed tests in a `flutter test --file-reporter json:<file>` log into
// GitHub annotations, so failures are readable from the checks API without
// downloading the job log: dart annotate_failures.dart <file>

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final names = <int, String>{};
  final errors = <int, String>{};
  final printed = <int, StringBuffer>{};
  for (final String line in File(args.first).readAsLinesSync()) {
    if (!line.startsWith('{')) continue;
    final event = jsonDecode(line) as Map<String, Object?>;
    switch (event['type']) {
      case 'testStart':
        final test = event['test']! as Map<String, Object?>;
        names[test['id']! as int] = test['name']! as String;
      case 'print':
        (printed[event['testID']! as int] ??= StringBuffer()).writeln(event['message']);
      case 'error':
        // flutter_test prints the exception and reports a generic error.
        final int id = event['testID']! as int;
        final error = event['error']! as String;
        errors.putIfAbsent(
          id,
          () => error.startsWith('Test failed. See exception logs above') ? '${printed[id] ?? error}' : error,
        );
    }
  }
  var shown = 0;
  for (final MapEntry<int, String> e in errors.entries) {
    final String message = e.value.replaceAll('%', '%25').replaceAll('\r', '').replaceAll('\n', '%0A');
    final String clipped = message.length > 3000 ? '${message.substring(0, 3000)}…' : message;
    stdout.writeln('::error title=${names[e.key]}::$clipped');
    if (++shown == 10) break;
  }
  stdout.writeln('::notice title=failed tests::${errors.length}: ${errors.keys.map((int k) => names[k]).join(', ')}');
}
