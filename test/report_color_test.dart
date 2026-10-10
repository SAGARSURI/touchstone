// Terminal colour in the change report (ansi.dart): only the part of a value
// that differs is coloured, and without the escapes the text is the
// uncoloured report.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/src/diff/ansi.dart';

const Ansi _on = Ansi(true);

String _red(String s) => '\x1B[31m$s\x1B[0m';
String _green(String s) => '\x1B[32m$s\x1B[0m';

void main() {
  test('only the argument that changed is coloured', () {
    expect(
      highlightChange('Padding.padding: EdgeInsets(16.0, 24.0, 16.0, 8.0) -> EdgeInsets(16.0, 24.0, 16.0, 9.0)', _on),
      'Padding.padding: EdgeInsets(16.0, 24.0, 16.0, ${_red('8.0')}) -> EdgeInsets(16.0, 24.0, 16.0, ${_green('9.0')})',
    );
  });

  test('a token name written once before both colours stays plain', () {
    expect(
      highlightChange('Material.color: brand.accent #FF3949AB -> #FF3F51B5', _on),
      'Material.color: brand.accent ${_red('#FF3949AB')} -> ${_green('#FF3F51B5')}',
    );
  });

  test('a size with no field name colours only the numbers', () {
    expect(highlightChange('size 358x49 -> 358x50', _on), 'size ${_red('358x49')} -> ${_green('358x50')}');
  });

  test('in text, the words both sides share stay plain', () {
    expect(
      highlightChange('label: "Name, email, phone" -> "Name, E-Mail-Adresse, Telefonnummer"', _on),
      'label: "Name, ${_red('email, phone')}" -> "Name, ${_green('E-Mail-Adresse, Telefonnummer')}"',
    );
  });

  test('a field name with ": " inside quotes is not taken for the field name', () {
    expect(
      highlightChange('label: "Note: a" -> "Note: b"', _on),
      'label: "Note: ${_red('a')}" -> "Note: ${_green('b')}"',
    );
  });

  test('off, or with no arrow, the text is unchanged', () {
    expect(highlightChange('size 358x49 -> 358x50', const Ansi(false)), 'size 358x49 -> 358x50');
    expect(highlightChange('unexplained (pixel hash changed)', _on), 'unexplained (pixel hash changed)');
  });

  test('visible length leaves out the escapes', () {
    final String s = highlightChange('size 358x49 -> 358x50', _on);
    expect(visibleLength(s), 'size 358x49 -> 358x50'.length);
    expect(stripAnsi(s), 'size 358x49 -> 358x50');
  });

  test('a long coloured line keeps its spaces from being broken by the error dump', () {
    final String colored = '   ${_red('x' * 50)} -> ${_green('y' * 50)}';
    final String kept = keepColoredLines('short\n$colored\n${'plain ' * 20}');
    final List<String> lines = kept.split('\n');
    expect(lines[0], 'short');
    expect(lines[1], startsWith('   \x1B'), reason: 'the indent stays');
    expect(lines[1].substring(3), isNot(contains(' ')));
    expect(lines[2], 'plain ' * 20, reason: 'a plain line is left for Flutter as before');
  });
}
