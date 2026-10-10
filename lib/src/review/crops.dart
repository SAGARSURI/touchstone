// Before and after crops of the changed components (spec: Advantage over
// pixel goldens, "Reviewing a baseline change"; Developer experience,
// Review; Budgets). Baselines store no pixels, so the review command renders
// the target branch's version of each changed snapshot once, in a temporary
// git worktree, and the working tree's version, both on this machine. Crops
// are for reviewers only and never affect a verdict; a snapshot that passes
// renders nothing.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../diff/changes.dart';
import '../diff/diff.dart';
import '../diff/policy.dart';
import '../diff/report.dart';
import 'png.dart';
import 'review.dart';

/// Margin around a changed component's bounds, in logical pixels.
const double cropMargin = 8;

/// A full render of one snapshot and its device pixel ratio.
class Render {
  Render(this.image, this.dpr);

  final Rgba image;
  final double dpr;

  /// Reads `<dir>/<id>.png` and `<dir>/<id>.json`, or null when [id] was not
  /// rendered.
  static Render? read(String dir, String id) {
    final png = File('$dir/$id.png');
    final json = File('$dir/$id.json');
    if (!png.existsSync() || !json.existsSync()) {
      return null;
    }
    final Object? meta = jsonDecode(json.readAsStringSync());
    final double dpr = meta is Map<String, Object?> && meta['dpr'] is num ? (meta['dpr']! as num).toDouble() : 1;
    return Render(decodePng(png.readAsBytesSync()), dpr);
  }
}

/// A rectangle in logical pixels.
typedef LogicalRect = ({double left, double top, double right, double bottom});

/// The area to crop for [changes]: every changed copy's bounds before and
/// after, joined, with [margin] around them. Null when none has bounds.
LogicalRect? cropArea(List<Change> changes, {double margin = cropMargin}) {
  final List<Bounds> all = <Bounds>[
    for (final Change c in changes) ...<Bounds?>[c.before?.bounds, c.after?.bounds].whereType<Bounds>(),
  ];
  if (all.isEmpty) {
    return null;
  }
  return (
    left: all.map((Bounds b) => b.x).reduce(math.min) - margin,
    top: all.map((Bounds b) => b.y).reduce(math.min) - margin,
    right: all.map((Bounds b) => b.x + b.w).reduce(math.max) + margin,
    bottom: all.map((Bounds b) => b.y + b.h).reduce(math.max) + margin,
  );
}

/// [area] of [render], at its device pixel ratio, edges rounded outwards and
/// clipped to the image.
Rgba crop(Render render, LogicalRect area) {
  final Rgba image = render.image;
  final int left = (area.left * render.dpr).floor().clamp(0, image.width);
  final int top = (area.top * render.dpr).floor().clamp(0, image.height);
  final int right = (area.right * render.dpr).ceil().clamp(left, image.width);
  final int bottom = (area.bottom * render.dpr).ceil().clamp(top, image.height);
  final out = Rgba.blank(right - left, bottom - top);
  for (var y = 0; y < out.height; y++) {
    out.pixels.setRange(y * out.width * 4, (y + 1) * out.width * 4, image.pixels, ((top + y) * image.width + left) * 4);
  }
  return out;
}

/// [after] in faded grey, with every pixel that differs from [before] in
/// red: light for a small change (a shade), dark for a large one (something
/// moved), so a 1 px change shows. Null when the two are not the same size.
Rgba? diffImage(Rgba before, Rgba after) {
  if (before.width != after.width || before.height != after.height) {
    return null;
  }
  final out = Rgba.blank(after.width, after.height);
  final Uint8List a = before.pixels;
  final Uint8List b = after.pixels;
  final Uint8List o = out.pixels;
  for (var i = 0; i < b.length; i += 4) {
    var delta = 0;
    for (var k = 0; k < 4; k++) {
      delta = math.max(delta, (a[i + k] - b[i + k]).abs());
    }
    if (delta > 0) {
      // Square root, so a change of a few levels is still clearly pink.
      final double t = math.sqrt(delta / 255);
      final int gb = (diffLight.$2 + (diffDark.$2 - diffLight.$2) * t).round();
      o
        ..[i] = (diffLight.$1 + (diffDark.$1 - diffLight.$1) * t).round()
        ..[i + 1] = gb
        ..[i + 2] = gb
        ..[i + 3] = 255;
    } else {
      // Grey over white, then faded, so only changes have colour.
      final double alpha = b[i + 3] / 255;
      final double lum = 0.299 * b[i] + 0.587 * b[i + 1] + 0.114 * b[i + 2];
      final int v = 255 - ((255 - lum) * alpha * 0.3).round();
      o
        ..[i] = v
        ..[i + 1] = v
        ..[i + 2] = v
        ..[i + 3] = 255;
    }
  }
  return out;
}

/// The diff colour of the smallest change, as (red, green and blue).
const (int, int) diffLight = (255, 175);

/// The diff colour of the largest change, as (red, green and blue).
const (int, int) diffDark = (190, 0);

/// The crops written for one report item.
class ItemCrops {
  ItemCrops(
    this.snapshotId,
    this.number,
    this.type,
    this.component, {
    this.before,
    this.after,
    this.diff,
    this.note,
    this.sameAs,
  });

  final String snapshotId;
  final int number;
  final String type;
  final String component;

  /// Paths of the PNGs written, relative to the output directory.
  final String? before;
  final String? after;
  final String? diff;

  /// Why an image is missing, or what it does not show.
  final String? note;

  /// The earlier item whose crops cover the same area, when one does; this
  /// item then has the same files.
  final int? sameAs;
}

/// Writes crops for [report]'s items from the [before] and [after] renders
/// into `<out>/<snapshot id>/`. Shifts get none: they follow the item that
/// caused them.
List<ItemCrops> writeCrops(ChangeReport report, Render? before, Render? after, String out) {
  final String id = report.snapshotId;
  final crops = <ItemCrops>[];
  final written = <LogicalRect, ItemCrops>{};
  for (final ({int number, String type, String component, List<Change> changes}) item in numberedItems(report)) {
    if (item.changes.isEmpty) {
      continue;
    }
    final LogicalRect? area = cropArea(item.changes);
    if (area == null) {
      crops.add(ItemCrops(id, item.number, item.type, item.component, note: 'no bounds to crop'));
      continue;
    }
    final String? semantics = item.type == 'Semantics'
        ? 'semantics has no pixels; any red here comes from other items'
        : null;
    if (written[area] case final ItemCrops first) {
      crops.add(
        ItemCrops(
          id,
          item.number,
          item.type,
          item.component,
          before: first.before,
          after: first.after,
          diff: first.diff,
          note: semantics,
          sameAs: first.number,
        ),
      );
      continue;
    }
    final String stem = '$id/${item.number}-${item.type.toLowerCase()}';
    String? write(String name, Rgba? image) {
      if (image == null || image.width == 0 || image.height == 0) {
        return null;
      }
      final file = File('$out/$stem-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(encodePng(image));
      return '$stem-$name.png';
    }

    final Rgba? b = before == null ? null : crop(before, area);
    final Rgba? a = after == null ? null : crop(after, area);
    final Rgba? d = b != null && a != null ? diffImage(b, a) : null;
    // Judged on the component's own bounds: the margin may show a neighbour
    // that changed.
    final LogicalRect own = cropArea(item.changes, margin: 0)!;
    final bool invisible = before != null && after != null && _same(crop(before, own), crop(after, own));
    crops.add(
      ItemCrops(
        id,
        item.number,
        item.type,
        item.component,
        before: write('before', b),
        after: write('after', a),
        diff: write('diff', d),
        note: switch ((b, a)) {
          (null, null) => 'not rendered',
          (null, _) => 'no before render',
          (_, null) => 'no after render',
          _ when invisible => 'no pixel changed here: the change is not visible (such as semantics)',
          _ => semantics,
        },
      ),
    );
    written[area] = crops.last;
  }
  return crops;
}

bool _same(Rgba a, Rgba b) {
  if (a.pixels.length != b.pixels.length) {
    return false;
  }
  for (var i = 0; i < a.pixels.length; i++) {
    if (a.pixels[i] != b.pixels[i]) {
      return false;
    }
  }
  return true;
}

/// Renders every snapshot in [result] that needs review or fails, at
/// [result]'s base and in the working tree, by running [tests] with
/// `flutter test` in render mode (render.dart), and writes the crops and an
/// `index.html` into [out]. [root] is the package directory.
Future<List<ItemCrops>> renderCrops(
  ReviewResult result, {
  String root = '.',
  String tests = 'test',
  String out = 'build/touchstone/review',
  void Function(String) log = _stderr,
}) async {
  final List<SnapshotReview> shown = <SnapshotReview>[
    for (final SnapshotReview r in result.reviews)
      if (r.report case final ChangeReport report
          when report.kind == ReportKind.diff && r.decision.verdict != Verdict.pass)
        r,
  ];
  if (shown.isEmpty) {
    return <ItemCrops>[];
  }
  final List<String> ids = <String>[for (final SnapshotReview r in shown) r.report!.snapshotId];
  final Directory tmp = Directory.systemTemp.createTempSync('touchstone_review');
  final String top = _run('git', <String>['rev-parse', '--show-toplevel'], root).trim();
  final String prefix = _run('git', <String>['rev-parse', '--show-prefix'], root).trim();
  final worktree = '${tmp.path}/base';
  try {
    log('Rendering ${ids.length} snapshots in the working tree...');
    await _render(root, tests, '${tmp.path}/after', ids);
    log('Rendering them at ${result.base}...');
    _run('git', <String>['worktree', 'add', '--quiet', '--detach', worktree, result.base], top);
    final String basePackage = '$worktree/$prefix';
    _useThisTouchstone(basePackage);
    await _render(basePackage, tests, '${tmp.path}/before', ids);

    final outDir = Directory(out);
    if (outDir.existsSync()) {
      outDir.deleteSync(recursive: true);
    }
    final crops = <ItemCrops>[];
    for (final SnapshotReview r in shown) {
      final String id = r.report!.snapshotId;
      crops.addAll(
        writeCrops(r.report!, Render.read('${tmp.path}/before', id), Render.read('${tmp.path}/after', id), out),
      );
    }
    File('$out/index.html')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(indexHtml(result.base, shown, crops));
    return crops;
  } finally {
    if (Directory(worktree).existsSync()) {
      Process.runSync('git', <String>['worktree', 'remove', '--force', worktree], workingDirectory: top);
    }
    tmp.deleteSync(recursive: true);
  }
}

void _stderr(String line) => stderr.writeln(line);

Future<void> _render(String package, String tests, String dir, List<String> ids) async {
  final Process p = await Process.start(
    'flutter',
    <String>['test', tests],
    workingDirectory: package,
    environment: <String, String>{'TOUCHSTONE_RENDER_DIR': dir, 'TOUCHSTONE_RENDER_IDS': ids.join(',')},
    runInShell: Platform.isWindows,
  );
  // Render mode compares nothing, so the exit code says only whether other
  // tests failed; what matters is which renders were written.
  await Future.wait(<Future<void>>[p.stdout.drain<void>(), p.stderr.drain<void>()]);
  await p.exitCode;
}

/// Points [package]'s touchstone dependency at the touchstone running this
/// command, so the target branch renders with a version that has render mode.
void _useThisTouchstone(String package) {
  final pubspec = File('$package/pubspec.yaml');
  if (!pubspec.existsSync() ||
      RegExp(r'^name:\s*touchstone\s*$', multiLine: true).hasMatch(pubspec.readAsStringSync())) {
    return;
  }
  final Uri? library = Isolate.resolvePackageUriSync(Uri.parse('package:touchstone/touchstone.dart'));
  if (library == null) {
    return;
  }
  final String root = File.fromUri(library).parent.parent.path;
  final overrides = File('$package/pubspec_overrides.yaml');
  final String entry = '  touchstone:\n    path: $root\n';
  // Drop any touchstone override the package already has, then add this one.
  final String existing = (overrides.existsSync() ? overrides.readAsStringSync() : '').replaceAll(
    RegExp(r'^  touchstone:.*\n(?:    .*\n)*', multiLine: true),
    '',
  );
  final RegExp section = RegExp(r'^dependency_overrides:[ \t]*\n', multiLine: true);
  overrides.writeAsStringSync(
    section.hasMatch(existing)
        ? existing.replaceFirstMapped(section, (Match m) => '${m[0]}$entry')
        : '${existing.isEmpty || existing.endsWith('\n') ? existing : '$existing\n'}dependency_overrides:\n$entry',
  );
}

String _run(String executable, List<String> args, String dir) {
  final ProcessResult r = Process.runSync(executable, args, workingDirectory: dir);
  if (r.exitCode != 0) {
    throw ProcessException(executable, args, '${r.stderr}'.trim(), r.exitCode);
  }
  return r.stdout as String;
}

/// A page with each snapshot's report items, each above its crops: before
/// and after in one frame with a slider and a flip button, and the diff.
String indexHtml(String base, List<SnapshotReview> reviews, List<ItemCrops> crops) {
  const HtmlEscape esc = HtmlEscape();
  final out = StringBuffer()
    ..writeln('<!doctype html><html><head><meta charset="utf-8"><title>Touchstone review</title><style>')
    ..writeln(_css)
    ..writeln('</style></head><body>')
    ..writeln('<h1>Snapshot review against ${esc.convert(base)}</h1>')
    ..writeln(
      '<p class="lead">Crops are rendered on this machine for reviewers; they never affect a verdict. '
      'Drag the slider, click the image or press F over it to flip between before and after. '
      'In the diff, changed pixels are red: light for a small change such as a shade, dark for a large one.</p>',
    );
  for (final SnapshotReview r in reviews) {
    final String id = r.report!.snapshotId;
    final List<String> head = r.text.split('\n\n').first.split('\n');
    out
      ..writeln(
        '<section><h2>${esc.convert(id)} <span class="verdict">${esc.convert(r.decision.verdict.label)}</span></h2>',
      )
      ..writeln('<p class="count">${esc.convert(head.length > 1 ? head[1] : '')}</p>');
    for (final MapEntry<int, String> item in itemTexts(r.text).entries) {
      final ItemCrops? c = crops.where((ItemCrops c) => c.snapshotId == id && c.number == item.key).firstOrNull;
      out
        ..writeln('<div class="item">')
        ..writeln('<pre class="text">${esc.convert(item.value)}</pre>')
        ..writeln('<div class="images">');
      if (c?.note != null) {
        out.writeln('<div class="note">${esc.convert(c!.note!)}</div>');
      }
      if (c != null && c.sameAs != null) {
        out.writeln('<div class="note">Same crops as item ${c.sameAs}.</div>');
      } else if (c != null) {
        if (c.before != null && c.after != null) {
          out.writeln(
            '<figure><div class="compare" tabindex="0">'
            '<img class="b" src="${esc.convert(c.before!)}" alt="before">'
            '<img class="a" src="${esc.convert(c.after!)}" alt="after">'
            '<span class="label">after</span></div>'
            '<input type="range" min="0" max="100" value="100" aria-label="before or after">'
            '<figcaption>before &#8596; after <button type="button">Flip</button></figcaption></figure>',
          );
        } else {
          for (final (String label, String? path) in <(String, String?)>[('before', c.before), ('after', c.after)]) {
            if (path != null) {
              out.writeln(
                '<figure><img src="${esc.convert(path)}" alt="$label"><figcaption>$label</figcaption></figure>',
              );
            }
          }
        }
        if (c.diff != null) {
          out.writeln('<figure><img src="${esc.convert(c.diff!)}" alt="diff"><figcaption>diff</figcaption></figure>');
        }
      }
      out.writeln('</div></div>');
    }
    out.writeln('<details><summary>Full report</summary><pre>${esc.convert(r.text)}</pre></details></section>');
  }
  out
    ..writeln('<script>$_script</script>')
    ..writeln('</body></html>');
  return out.toString();
}

/// The report's items by number, from its text: items are separated by a
/// blank line and start with their number (report.dart).
Map<int, String> itemTexts(String report) {
  final out = <int, String>{};
  for (final String block in report.split('\n\n')) {
    final RegExpMatch? m = RegExp(r'^(\d+)\s').firstMatch(block);
    if (m != null) {
      out[int.parse(m[1]!)] = block.trimRight();
    }
  }
  return out;
}

const String _css = '''
body{font:14px/1.45 system-ui,sans-serif;margin:24px;color:#1f2328;background:#fff}
h2{margin-top:32px}
.verdict{font-size:13px;padding:2px 8px;border-radius:10px;background:#fff8c5;vertical-align:middle}
.lead,.count{color:#59636e}
.item{border-top:1px solid #d0d7de;padding:16px 0}
.text{margin:0 0 12px;font-size:13px;overflow-x:auto}
.images{display:flex;gap:16px;flex-wrap:wrap;align-items:flex-start}
figure{margin:0}
figure img,.compare{display:block;max-width:360px;border:1px solid #d0d7de;image-rendering:pixelated}
figcaption{color:#59636e;font-size:12px;margin-top:4px}
.compare{position:relative;cursor:pointer;line-height:0}
.compare img{border:0;max-width:100%}
.compare .a{position:absolute;inset:0;width:100%}
.compare .label{position:absolute;top:4px;left:4px;font:11px/1.4 system-ui;background:#1f2328;color:#fff;padding:1px 6px;border-radius:8px}
input[type=range]{width:100%;max-width:360px;display:block}
.note{color:#9a6700;font-size:13px;max-width:360px}
details{margin-top:16px}
details pre{background:#f6f8fa;padding:12px;overflow:auto}
''';

const String _script = r'''
for (const fig of document.querySelectorAll('figure')) {
  const box = fig.querySelector('.compare');
  if (!box) continue;
  const after = box.querySelector('.a'), label = box.querySelector('.label');
  const range = fig.querySelector('input'), flip = fig.querySelector('button');
  const show = (v) => {
    range.value = v;
    after.style.clipPath = 'inset(0 ' + (100 - v) + '% 0 0)';
    label.textContent = v >= 100 ? 'after' : v <= 0 ? 'before' : 'before | after';
  };
  const toggle = () => show(+range.value > 0 ? 0 : 100);
  range.addEventListener('input', () => show(+range.value));
  box.addEventListener('click', toggle);
  flip.addEventListener('click', toggle);
  show(100);
}
document.addEventListener('keydown', (e) => {
  if (e.key !== 'f' && e.key !== 'F') return;
  const box = document.querySelector('.compare:hover') || document.activeElement.closest('.compare');
  if (box) box.click();
});
''';
