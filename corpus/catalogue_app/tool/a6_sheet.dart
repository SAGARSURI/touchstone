// Builds the A6 review sheet: dart run tool/a6_sheet.dart <generated results>
//
// A6 asks whether keeping only app-owned widgets gives a tree developers
// recognise. Two engineers review, for every catalog mutation and a seeded
// sample of generated mutations, whether the change is attributed to the
// nearest app-owned widget without looking at the raw element tree. This
// tool writes the sheet they fill in.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'catalogs.dart';

String _nodes(List<Map<String, Object?>> nodes) {
  final own = <String>[];
  var consequences = 0;
  for (final n in nodes) {
    final List<Object?> fields = (n['fields'] as List<Object?>?) ?? const <Object?>[];
    if (n['change'] != 'changed') {
      own.add('`${n['node']}` ${n['change']}');
    } else if (fields.contains('paint') || fields.contains('semantics')) {
      own.add('`${n['node']}` ${fields.where((Object? f) => f != 'style' && f != 'type').join('+')}');
    } else {
      consequences++;
    }
  }
  return '${own.join('<br>')}${consequences > 0 ? '<br>+ $consequences moved or resized only' : ''}';
}

void main(List<String> args) {
  final catalog = (jsonDecode(File('build/catalogs/report.json').readAsStringSync()) as List<Object?>)
      .cast<Map<String, Object?>>();
  final out = StringBuffer()
    ..writeln('# A6 review sheet')
    ..writeln()
    ..writeln('For each change: is it attributed to the nearest app-owned widget, and can you tell what changed')
    ..writeln('without the raw element tree? Mark yes or no, with a note for every no.')
    ..writeln()
    ..writeln('## Catalog mutations')
    ..writeln()
    ..writeln('| # | Edit | Reported on | Reviewer A | Reviewer B |')
    ..writeln('| --- | --- | --- | --- | --- |');
  var i = 0;
  for (final Entry e in mutations) {
    final r = catalog.firstWhere((Map<String, Object?> r) => r['id'] == e.id);
    final nodes = <Map<String, Object?>>[
      for (final s in (r['scenes']! as List<Object?>).cast<Map<String, Object?>>())
        ...((s['nodes'] as List<Object?>?) ?? const <Object?>[]).cast<Map<String, Object?>>(),
    ];
    final String edit = e.edits
        .map(
          (Edit x) =>
              '`${x.file.split('/').last}`: ${x.find.trim().split('\n').first} → ${x.replace.trim().split('\n').first}',
        )
        .join('; ');
    out.writeln('| ${++i} | ${e.kind}: ${edit.replaceAll('|', '\\|')} | ${_nodes(nodes)} |  |  |');
  }
  if (args.isNotEmpty) {
    final generated = (jsonDecode(File(args.first).readAsStringSync()) as List<Object?>)
        .cast<Map<String, Object?>>()
        .where((Map<String, Object?> r) => r['snapshotChanged'] == true)
        .toList();
    final random = Random(6); // A6
    final sample = <Map<String, Object?>>[];
    while (sample.length < 50 && generated.isNotEmpty) {
      sample.add(generated.removeAt(random.nextInt(generated.length)));
    }
    sample.sort((Map<String, Object?> a, Map<String, Object?> b) => (a['seed']! as int).compareTo(b['seed']! as int));
    out
      ..writeln()
      ..writeln('## Generated mutations (50 sampled with seed 6)')
      ..writeln()
      ..writeln(
        'Each replays with `flutter test test/generated --dart-define=GEN_START=<seed> --dart-define=GEN_COUNT=1`.',
      )
      ..writeln()
      ..writeln(
        '| Seed | Scene | Mutation | Mutated render object belongs to | First node reported | Reviewer A | Reviewer B |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
    for (final r in sample) {
      out.writeln(
        '| ${r['seed']} | ${r['scene']} | ${r['mutation'].toString().replaceAll('|', '\\|')} on ${r['target']} | '
        '`${r['owner']}` | `${r['firstNode']}` |  |  |',
      );
    }
  }
  File('build/a6_review.md').writeAsStringSync(out.toString());
  stdout.writeln('wrote build/a6_review.md');
}
