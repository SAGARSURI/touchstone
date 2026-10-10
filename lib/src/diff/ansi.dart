// Terminal colour for the change report, asked for after the DX sessions
// (doc/phase3/dx_results.md): the verdict, the change type and the component
// stand out, and in each "before -> after" only the part that differs is
// coloured, red before and green after.
//
// Colour is for a terminal only. The report text that pull requests, files
// and the catalogue tools use is uncoloured, and so is any output when
// NO_COLOR (https://no-color.org) is set or the run is on CI.
// TOUCHSTONE_COLOR=always or never overrides the choice.

import 'dart:io';

final RegExp _escape = RegExp('\x1B\\[[0-9;]*m');

/// [s] as a terminal shows it: without colour escapes.
String stripAnsi(String s) => s.replaceAll(_escape, '');

/// How many columns [s] takes on a terminal.
int visibleLength(String s) => s.length - _escape.allMatches(s).fold(0, (int n, Match m) => n + m.end - m.start);

/// Colour escapes, or none when [on] is false.
class Ansi {
  const Ansi(this.on);

  final bool on;

  String _wrap(String code, String s) => on && s.isNotEmpty ? '\x1B[${code}m$s\x1B[0m' : s;
  String bold(String s) => _wrap('1', s);
  String dim(String s) => _wrap('2', s);
  String red(String s) => _wrap('31', s);
  String green(String s) => _wrap('32', s);
  String yellow(String s) => _wrap('33', s);
  String cyan(String s) => _wrap('36', s);
  String boldRed(String s) => _wrap('1;31', s);
  String boldGreen(String s) => _wrap('1;32', s);
  String boldYellow(String s) => _wrap('1;33', s);
}

/// Whether a report printed to [out] is coloured. Inside `flutter test` the
/// test's output is never a terminal (the flutter tool relays it), so with no
/// [out] colour is on when TERM names a terminal.
bool useColor({Stdout? out}) {
  final Map<String, String> env = Platform.environment;
  switch (env['TOUCHSTONE_COLOR']) {
    case 'always':
      return true;
    case 'never':
      return false;
  }
  if (env.containsKey('NO_COLOR') || env.containsKey('CI')) {
    return false;
  }
  if (out != null) {
    return out.hasTerminal && out.supportsAnsiEscapes;
  }
  final String? term = env['TERM'];
  return term != null && term.isNotEmpty && term != 'dumb';
}

/// [text] for Flutter's error dump, which wraps a test failure's message at
/// 100 characters counting colour escapes, breaking at spaces: in a coloured
/// line that long, the spaces after its indent become no-break spaces, so a
/// line that fits the terminal is not broken in two. Plain lines are left as
/// they are.
String keepColoredLines(String text) => <String>[
  for (final String line in text.split('\n'))
    if (line.length < 96 || line.length == visibleLength(line))
      line
    else
      line.replaceFirstMapped(RegExp(r'^( *)(.*)$'), (Match m) => '${m[1]}${m[2]!.replaceAll(' ', '\u00A0')}'),
].join('\n');

final RegExp _tokens = RegExp(r'[\w.#]+|\s+|.');
final RegExp _namedColor = RegExp(r'^[A-Za-z][\w.]* #[0-9A-F]{8}$');

/// [entry] with the part of its "before -> after" that differs coloured, red
/// before the arrow and green after it; the words naming the field and what
/// both sides share are left plain. Unchanged when it has no arrow.
String highlightChange(String entry, Ansi a) {
  final int arrow = entry.indexOf(' -> ');
  if (!a.on || arrow < 0) {
    return entry;
  }
  final String left = entry.substring(0, arrow);
  final List<String> after = _split(entry.substring(arrow + 4));
  final List<String> leftTokens = _split(left);
  final int start = _valueStart(left, leftTokens, after.length);
  final List<String> label = leftTokens.sublist(0, start);
  final List<String> before = leftTokens.sublist(start);
  var p = 0;
  while (p < before.length && p < after.length && before[p] == after[p]) {
    p++;
  }
  var s = 0;
  while (s < before.length - p &&
      s < after.length - p &&
      before[before.length - 1 - s] == after[after.length - 1 - s]) {
    s++;
  }
  String side(List<String> t, String Function(String) colour) =>
      t.sublist(0, p).join() + colour(t.sublist(p, t.length - s).join()) + t.sublist(t.length - s).join();
  return '${label.join()}${side(before, a.red)} -> ${side(after, a.green)}';
}

List<String> _split(String s) => <String>[for (final Match m in _tokens.allMatches(s)) m[0]!];

/// The index in [tokens] (of [left]) where the before value starts: after
/// the last ": " outside quotes and brackets, which ends the field's name;
/// with none, as many tokens from the end as the after value has. A colour's
/// token name before it is skipped.
int _valueStart(String left, List<String> tokens, int afterCount) {
  var depth = 0;
  var quoted = false;
  int? start;
  for (var i = 0; i < tokens.length; i++) {
    final String t = tokens[i];
    if (t == '"') {
      quoted = !quoted;
    } else if (!quoted && '([{'.contains(t)) {
      depth++;
    } else if (!quoted && ')]}'.contains(t) && depth > 0) {
      depth--;
    } else if (!quoted && depth == 0 && t == ':' && i + 1 < tokens.length && tokens[i + 1] == ' ') {
      start = i + 2;
    }
  }
  final int from = start ?? (tokens.length - afterCount).clamp(0, tokens.length);
  // A colour's token, written once before both values (summary.dart), is
  // part of the field's name here.
  final String value = tokens.sublist(from).join();
  return _namedColor.hasMatch(value) ? from + 2 : from;
}
