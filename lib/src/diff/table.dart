// A box-drawn table for the change report, asked for after the DX sessions
// (doc/phase3/dx_results.md). Cells wrap between words to their column; a
// row can span its last columns with one text, as consequences do. Widths
// count what a terminal shows, so colour escapes (ansi.dart) do not move a
// border.

import 'dart:math' as math;

import 'ansi.dart';

/// One row: a text per column, or, with [span], the first cells followed by
/// [span] across every column from `cells.length` on.
class TableRow {
  TableRow(this.cells, {this.span});

  final List<String> cells;
  final String? span;
}

/// A column: its header, and its widest width (null for a column that shares
/// what is left).
class TableColumn {
  const TableColumn(this.header, {this.max, this.flex = false});

  final String header;
  final int? max;
  final bool flex;
}

/// [groups] of rows under [columns] in [width] columns, a rule between
/// groups.
String renderTable(List<TableColumn> columns, List<List<TableRow>> groups, {required int width, required Ansi a}) {
  final int n = columns.length;
  final List<int> widths = <int>[
    for (var i = 0; i < n; i++)
      columns[i].flex
          ? 0
          : math.min(
              columns[i].max ?? 1 << 20,
              <int>[
                visibleLength(columns[i].header),
                for (final List<TableRow> g in groups)
                  for (final TableRow r in g)
                    if (i < r.cells.length) visibleLength(r.cells[i]),
              ].reduce(math.max),
            ),
  ];
  final int flexCount = columns.where((TableColumn c) => c.flex).length;
  final int left = width - (3 * n + 1) - widths.fold(0, (int s, int w) => s + w);
  for (var i = 0, k = 0; i < n; i++) {
    if (columns[i].flex) {
      widths[i] = left ~/ flexCount + (k < left % flexCount ? 1 : 0);
      k++;
    }
  }

  final out = StringBuffer();
  String border(String s) => a.dim(s);
  // The column boundaries a row has (boundary i follows column i): every one
  // but those inside the row's span.
  Set<int> bounds(TableRow? r) => <int>{
    if (r != null)
      for (var i = 0; i < n - 1; i++)
        if (r.span == null || i < r.cells.length) i,
  };
  void rule(String l, String r, String up, String down, String cross, TableRow? above, TableRow? below) {
    final Set<int> u = bounds(above);
    final Set<int> d = bounds(below);
    final line = StringBuffer(l);
    for (var i = 0; i < n; i++) {
      line.write('─' * (widths[i] + 2));
      if (i < n - 1) {
        line.write(switch ((u.contains(i), d.contains(i))) {
          (true, true) => cross,
          (true, false) => up,
          (false, true) => down,
          (false, false) => '─',
        });
      }
    }
    line.write(r);
    out.writeln(border(line.toString()));
  }

  void row(TableRow r) {
    final int spanFrom = r.span == null ? n : r.cells.length;
    final List<int> cellWidths = <int>[
      for (var i = 0; i < spanFrom; i++) widths[i],
      if (r.span != null) widths.sublist(spanFrom).fold(0, (int s, int w) => s + w) + 3 * (n - spanFrom - 1),
    ];
    final List<String> texts = <String>[
      for (var i = 0; i < spanFrom; i++) i < r.cells.length ? r.cells[i] : '',
      if (r.span != null) r.span!,
    ];
    final List<List<String>> lines = <List<String>>[
      for (var i = 0; i < texts.length; i++) wrapCell(texts[i], cellWidths[i]),
    ];
    final int height = lines.map((List<String> l) => l.length).reduce(math.max);
    for (var y = 0; y < height; y++) {
      final line = StringBuffer(border('│'));
      for (var i = 0; i < texts.length; i++) {
        final String text = y < lines[i].length ? lines[i][y] : '';
        line
          ..write(' ')
          ..write(text)
          ..write(' ' * (cellWidths[i] - visibleLength(text)))
          ..write(' ')
          ..write(border('│'));
      }
      out.writeln(line);
    }
  }

  final header = TableRow(<String>[for (final TableColumn c in columns) c.header]);
  rule('┌', '┐', '┴', '┬', '┬', null, header);
  row(TableRow(<String>[for (final TableColumn c in columns) a.bold(c.header)]));
  TableRow above = header;
  for (final List<TableRow> g in groups) {
    rule('├', '┤', '┴', '┬', '┼', above, g.first);
    g.forEach(row);
    above = g.last;
  }
  rule('└', '┘', '┴', '┬', '┼', above, null);
  return out.toString();
}

/// [text] broken between words into lines [width] columns wide or less; a
/// word too long for a line breaks after a dot when it can, else anywhere.
/// A colour open at the end of a line is closed there and opened again on
/// the next, so it does not run into the borders.
List<String> wrapCell(String text, int width) {
  final lines = <String>[];
  var line = '';
  void push(String word) {
    if (line.isEmpty) {
      line = word;
    } else if (visibleLength(line) + 1 + visibleLength(word) <= width) {
      line = '$line $word';
    } else {
      lines.add(line);
      line = word;
    }
  }

  for (String word in text.split(' ')) {
    while (visibleLength(word) > width) {
      final int cut = _cut(word, width - (line.isEmpty ? 0 : visibleLength(line) + 1));
      if (cut <= 0) {
        lines.add(line);
        line = '';
        continue;
      }
      push(word.substring(0, cut));
      lines.add(line);
      line = '';
      word = word.substring(cut);
    }
    push(word);
  }
  lines.add(line);
  return _carryColour(lines);
}

final RegExp _escape = RegExp('\x1B\\[[0-9;]*m');

/// Where to break [word] to show at most [room] columns: after its last dot
/// in that room, else at the room's end. Escapes take no room.
int _cut(String word, int room) {
  if (room <= 0) {
    return 0;
  }
  var shown = 0;
  var i = 0;
  int? dot;
  while (i < word.length && shown < room) {
    final Match? m = _escape.matchAsPrefix(word, i);
    if (m != null) {
      i = m.end;
      continue;
    }
    if (word[i] == '.') {
      dot = i + 1;
    }
    shown++;
    i++;
  }
  return dot != null && dot > room ~/ 2 ? dot : i;
}

List<String> _carryColour(List<String> lines) {
  String? open;
  return <String>[
    for (final String l in lines)
      (() {
        var s = open == null ? l : '$open$l';
        for (final Match m in _escape.allMatches(l)) {
          open = m[0] == '\x1B[0m' ? null : m[0];
        }
        if (open != null) {
          s = '$s\x1B[0m';
        }
        return s;
      })(),
  ];
}
