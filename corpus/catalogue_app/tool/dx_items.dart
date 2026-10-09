// The developer-experience protocol's twelve changes
// (doc/phase3/dx_protocol.md), as JSON: each one's source edits and its
// answer key, taken from the frozen history and the mutation catalog.
//
//   dart run tool/dx_items.dart > items.json

import 'dart:convert';

import 'catalogs.dart' as catalogs;
import 'history.dart' as h1;
import 'history_phase3.dart' as h3;

/// Item number to its source: `h<change>` or the catalog entry's id.
const Map<int, String> items = <int, String>{
  1: 'h1',
  2: 'clip',
  3: 'h3',
  4: 'icon',
  5: 'h5',
  6: 'h7',
  7: 'h9',
  8: 'padding-1px',
  9: 'selected-state',
  10: 'widget-removed',
  11: 'enabled-state',
  12: 'column-insert-start',
};

List<Map<String, Object>> _edits(List<catalogs.Edit> edits) => <Map<String, Object>>[
  for (final catalogs.Edit e in edits)
    <String, Object>{'file': e.file, 'find': e.find, 'replace': e.replace, 'all': e.all},
];

void main() {
  final out = <String, Object>{};
  for (final MapEntry<int, String> item in items.entries) {
    final String source = item.value;
    if (source.startsWith('h')) {
      final int n = int.parse(source.substring(1));
      if (n <= 6) {
        final h1.Change c = h1.history.firstWhere((h1.Change c) => c.number == n);
        out['${item.key}'] = <String, Object>{
          'source': 'history change $n',
          'title': c.title,
          'edits': _edits(c.edits),
          'answer': c.expected,
        };
      } else {
        final h3.Change c = h3.historyPhase3.firstWhere((h3.Change c) => c.number == n);
        out['${item.key}'] = <String, Object>{
          'source': 'history change $n',
          'title': c.title,
          'edits': _edits(c.edits),
          'answer': c.expected,
        };
      }
    } else {
      final catalogs.Entry e = <catalogs.Entry>[
        ...catalogs.mutations,
        ...catalogs.cascades,
      ].firstWhere((catalogs.Entry e) => e.id == source);
      out['${item.key}'] = <String, Object>{
        'source': 'catalog $source',
        'title': e.kind,
        'edits': _edits(e.edits),
        'answer': '${e.expectNode}: ${e.expectTypes.join(', ')} on ${e.scenes.join(', ')}',
      };
    }
  }
  // ignore: avoid_print
  print(const JsonEncoder.withIndent('  ').convert(out));
}
