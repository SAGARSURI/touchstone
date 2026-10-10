// Short wording for the change report (spec: Diff engine, "Report shape"):
// one line per change, as in `background: brand.primary -> brand.accent`.
//
// A change's full wording stays in Change.detail and the snapshot file keeps
// every field. The report shortens it in three ways:
//
// 1. Fields that changed to the same value are one entry, named by the field
//    a developer is likeliest to recognise (a public widget's over a render
//    object's or a private one's). The others are left out: they record the
//    same change, and counting them read as a further change (DX sessions,
//    doc/phase3/dx_results.md).
// 2. Colours are written as their token, or as #AARRGGBB when they have none.
//    When both sides have the same token, it is written once, before the two
//    values: `brand.accent #FF3949AB -> #FF4050B0`.
// 3. When a value is a constructor call and one named argument changed, only
//    that argument is written: `bg.color: #1F1E8E3E -> #1F1E8E3F`.
// 4. A layout's size is rounded to two decimal places, or to as many as it
//    takes for before and after to still differ: `size 86.93x60 -> 88.93x62`.

final RegExp _color = RegExp(
  r'Color\(alpha: ([\d.]+), red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+), colorSpace: ColorSpace\.sRGB\)',
);
final RegExp _token = RegExp(r'([A-Za-z][\w.]*) \((#[0-9A-F]{8})\)');

/// [fields] (each "old -> new") as one short line.
String summarizeFields(Map<String, String> fields) => summarizeFieldList(fields).join('; ');

/// [fields] (each "old -> new") as short entries, one per distinct change.
List<String> summarizeFieldList(Map<String, String> fields) {
  final Map<String, List<String>> byValue = <String, List<String>>{};
  for (final MapEntry<String, String> e in fields.entries) {
    final (String key, String value) = _narrow(e.key, shortenValue(e.value));
    (byValue[value] ??= <String>[]).add(key);
  }
  return <String>[
    for (final MapEntry<String, List<String>> e in byValue.entries)
      '${(e.value..sort(_byRecognisable)).first}: ${e.key}',
  ];
}

/// What changed in [fields], without the fields' names: the same change on
/// several components, under whichever fields each one records it.
String fieldValues(Map<String, String> fields) => (<String>{
  for (final MapEntry<String, String> e in fields.entries) _narrow(e.key, shortenValue(e.value)).$2,
}.toList()..sort()).join('; ');

/// [text] with colours written as tokens or hex.
String shortenValue(String text) {
  final String hex = text.replaceAllMapped(_color, (Match m) {
    String byte(int i) => (double.parse(m[i]!) * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#${byte(1)}${byte(2)}${byte(3)}${byte(4)}';
  });
  final List<RegExpMatch> tokens = _token.allMatches(hex).toList();
  if (tokens.length == 2 && tokens[0][1] == tokens[1][1]) {
    // Same token on both sides: the value it resolves to changed. The token
    // is written once, as the cause.
    var first = true;
    return hex.replaceAllMapped(_token, (Match m) {
      final String out = first ? '${m[1]} ${m[2]}' : m[2]!;
      first = false;
      return out;
    });
  }
  return hex.replaceAllMapped(_token, (Match m) => m[1]!);
}

final RegExp _size = RegExp(r'size ([\d.]+)x([\d.]+) -> ([\d.]+)x([\d.]+)');

/// [text] with each `size WxH -> WxH` rounded (rule 4 above).
String shortenSize(String text) => text.replaceAllMapped(_size, (Match m) {
  final (String w0, String w1) = _rounded(m[1]!, m[3]!);
  final (String h0, String h1) = _rounded(m[2]!, m[4]!);
  return 'size ${w0}x$h0 -> ${w1}x$h1';
});

/// [a] and [b] to two decimal places, or more when two would make them equal
/// though they differ.
(String, String) _rounded(String a, String b) {
  for (var digits = 2; digits <= 6; digits++) {
    final String ra = _fixed(double.parse(a), digits);
    final String rb = _fixed(double.parse(b), digits);
    if (ra != rb || a == b) {
      return (ra, rb);
    }
  }
  return (a, b);
}

String _fixed(double v, int digits) {
  final String s = v.toStringAsFixed(digits);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

int _byRecognisable(String a, String b) {
  int rank(String k) {
    final String head = k.split('.').first;
    return (head.startsWith('_') ? 2 : 0) + (head.startsWith('Render') ? 1 : 0);
  }

  final int byRank = rank(a).compareTo(rank(b));
  if (byRank != 0) {
    return byRank;
  }
  final int byLength = a.length.compareTo(b.length);
  return byLength != 0 ? byLength : a.compareTo(b);
}

final RegExp _call = RegExp(r'^(\w+)\((.*)\)$');

/// `Foo(a: 1, b: 2) -> Foo(a: 1, b: 3)` on [key] as `key.b: 2 -> 3`.
(String, String) _narrow(String key, String value) {
  final List<String> sides = value.split(' -> ');
  if (sides.length != 2) {
    return (key, value);
  }
  final RegExpMatch? b = _call.firstMatch(sides[0]);
  final RegExpMatch? a = _call.firstMatch(sides[1]);
  if (b == null || a == null || b[1] != a[1]) {
    return (key, value);
  }
  final List<String> bArgs = _topLevel(b[2]!);
  final List<String> aArgs = _topLevel(a[2]!);
  if (bArgs.length != aArgs.length) {
    return (key, value);
  }
  final List<int> differ = <int>[
    for (var i = 0; i < bArgs.length; i++)
      if (bArgs[i] != aArgs[i]) i,
  ];
  if (differ.length != 1) {
    return (key, value);
  }
  final String bArg = bArgs[differ.single];
  final String aArg = aArgs[differ.single];
  final int bColon = bArg.indexOf(': ');
  final int aColon = aArg.indexOf(': ');
  if (bColon < 1 || aColon < 1 || bArg.substring(0, bColon) != aArg.substring(0, aColon)) {
    return (key, value);
  }
  final String name = bArg.substring(0, bColon);
  if (!RegExp(r'^\w+$').hasMatch(name)) {
    return (key, value);
  }
  return ('$key.$name', '${bArg.substring(bColon + 2)} -> ${aArg.substring(aColon + 2)}');
}

/// [s] split on commas outside brackets and quotes.
List<String> _topLevel(String s) {
  final out = <String>[];
  final cur = StringBuffer();
  var depth = 0;
  String? quote;
  for (var i = 0; i < s.length; i++) {
    final String ch = s[i];
    if (quote != null) {
      if (ch == quote && (i == 0 || s[i - 1] != r'\')) {
        quote = null;
      }
    } else if (ch == '"' || ch == "'") {
      quote = ch;
    } else if ('([{'.contains(ch)) {
      depth++;
    } else if (')]}'.contains(ch)) {
      depth--;
    } else if (ch == ',' && depth == 0) {
      out.add(cur.toString().trim());
      cur.clear();
      continue;
    }
    cur.write(ch);
  }
  out.add(cur.toString().trim());
  return out;
}
