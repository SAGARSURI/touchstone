// Review crops (crops.dart, png.dart, render.dart): render mode writes the
// view's pixels and compares nothing; each changed component gets before,
// after and diff crops; a change with no pixels says so.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/src/review/crops.dart';
import 'package:touchstone/src/review/png.dart';
import 'package:touchstone/src/snapshot/render.dart';
import 'package:touchstone/touchstone.dart';

class Row2 extends StatelessWidget {
  const Row2({super.key, required this.hint});
  final String hint;
  @override
  Widget build(BuildContext context) => Semantics(
    label: hint,
    child: const SizedBox(width: 120, height: 40, child: Text('Row')),
  );
}

class Box extends StatelessWidget {
  const Box({super.key, required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(width: 40, height: 40, child: ColoredBox(color: color));
}

class Button extends StatelessWidget {
  const Button({super.key, required this.pad, required this.color});
  final double pad;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(pad),
    child: ColoredBox(color: color, child: const SizedBox(width: 60, height: 20)),
  );
}

final _options = SnapshotOptions(policy: ComponentPolicy(include: <Type>{Row2, Box}));

Widget _app(String hint, Color color) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row2(hint: hint),
        Box(color: color),
      ],
    ),
  ),
);

/// Whether [image], a diff, marks a change: only changes have colour.
bool _hasRed(Rgba image) {
  for (var i = 0; i < image.pixels.length; i += 4) {
    if (image.pixels[i] != image.pixels[i + 1]) {
      return true;
    }
  }
  return false;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('touchstone_crops'));
  tearDown(() {
    debugRenderDirectory = null;
    debugRenderIds = null;
    tmp.deleteSync(recursive: true);
  });

  test('PNG written here reads back pixel for pixel', () {
    final image = Rgba(3, 2, Uint8List.fromList(List<int>.generate(24, (int i) => i * 10)));
    final Rgba back = decodePng(encodePng(image));
    expect((back.width, back.height), (3, 2));
    expect(back.pixels, image.pixels);
  });

  testWidgets("Flutter's PNG encoder output reads back as its raw pixels", (WidgetTester tester) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    for (var x = 0; x < 16; x++) {
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), 0, 1, 9),
        Paint()..color = Color.fromARGB(255, x * 16, 255 - x * 9, x * 3),
      );
    }
    final (Uint8List png, Uint8List raw) = (await tester.runAsync(() async {
      final ui.Image image = await recorder.endRecording().toImage(16, 9);
      final ByteData p = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final ByteData r = (await image.toByteData())!;
      image.dispose();
      return (p.buffer.asUint8List(), r.buffer.asUint8List());
    }))!;
    final Rgba decoded = decodePng(png);
    expect((decoded.width, decoded.height), (16, 9));
    expect(decoded.pixels, raw);
  });

  testWidgets('render mode writes pixels for the named snapshots and compares nothing', (WidgetTester tester) async {
    debugRenderDirectory = tmp.path;
    debugRenderIds = <String>{'crops_wanted'};
    await tester.pumpWidget(_app('a', const Color(0xFF000000)));
    await expectSnapshot(tester, 'crops_wanted', options: _options);
    await expectSnapshot(tester, 'crops_skipped', options: _options);
    expect(File('${tmp.path}/crops_wanted.png').existsSync(), isTrue);
    expect(File('${tmp.path}/crops_wanted.json').readAsStringSync(), '{"dpr":${tester.view.devicePixelRatio}}');
    expect(File('${tmp.path}/crops_skipped.png').existsSync(), isFalse);
    expect(Directory('test/snapshots').listSync().where((FileSystemEntity f) => f.path.contains('crops_')), isEmpty);
  });

  testWidgets('a colour change gets red pixels in its diff; a semantics change says it has none', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    debugRenderDirectory = '${tmp.path}/before';
    await tester.pumpWidget(_app('a', const Color(0xFF000000)));
    await expectSnapshot(tester, 'x', options: _options);
    final Snapshot a = await captureSnapshot(tester, 'x', options: _options);
    debugRenderDirectory = '${tmp.path}/after';
    await tester.pumpWidget(_app('b', const Color(0xFFFFFFFF)));
    await expectSnapshot(tester, 'x', options: _options);
    final Snapshot b = await captureSnapshot(tester, 'x', options: _options);
    h.dispose();

    final List<ItemCrops> crops = writeCrops(
      diffSnapshots(a, b),
      Render.read('${tmp.path}/before', 'x'),
      Render.read('${tmp.path}/after', 'x'),
      '${tmp.path}/out',
    );
    final ItemCrops box = crops.singleWhere((ItemCrops c) => c.component.startsWith('Box'));
    final ItemCrops row = crops.singleWhere((ItemCrops c) => c.component.startsWith('Row2'));
    expect(box.note, isNull);
    expect(<String?>[box.before, box.after, box.diff], everyElement(isNotNull));
    final Rgba diff = decodePng(File('${tmp.path}/out/${box.diff}').readAsBytesSync());
    expect(_hasRed(diff), isTrue);
    // 40 px box plus an 8 px margin each side, at the test view's ratio.
    final double dpr = tester.view.devicePixelRatio;
    expect(diff.width, ((40 + 2 * cropMargin) * dpr).round());
    expect(row.note, contains('not visible'));
    // The row sits at the top left, so its own area starts the crop; only the
    // margin below it, over the box, may be red.
    final Rgba rowDiff = decodePng(File('${tmp.path}/out/${row.diff}').readAsBytesSync());
    final int ownWidth = (120 * dpr).round();
    final int ownHeight = (40 * dpr).round();
    final ownArea = Rgba.blank(ownWidth, ownHeight);
    for (var y = 0; y < ownHeight; y++) {
      ownArea.pixels.setRange(y * ownWidth * 4, (y + 1) * ownWidth * 4, rowDiff.pixels, y * rowDiff.width * 4);
    }
    expect(_hasRed(ownArea), isFalse);
    expect(_hasRed(rowDiff), isTrue);
  });

  test('a crop near the edge is clipped to the image', () {
    final render = Render(Rgba.blank(10, 10), 1);
    final Rgba c = crop(render, (left: -8, top: 2, right: 4, bottom: 30));
    expect((c.width, c.height), (4, 8));
  });

  test('unchanged transparent pixels show white in the diff', () {
    final Rgba d = diffImage(Rgba.blank(1, 1), Rgba.blank(1, 1))!;
    expect(d.pixels, <int>[255, 255, 255, 255]);
  });

  testWidgets('two items on the same component share one set of crops', (WidgetTester tester) async {
    Widget app(double pad, Color color) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: Button(pad: pad, color: color),
      ),
    );
    final options = SnapshotOptions(policy: ComponentPolicy(include: <Type>{Button}));
    debugRenderDirectory = '${tmp.path}/before';
    await tester.pumpWidget(app(12, const Color(0xFF3949AB)));
    await expectSnapshot(tester, 'x', options: options);
    final Snapshot a = await captureSnapshot(tester, 'x', options: options);
    debugRenderDirectory = '${tmp.path}/after';
    await tester.pumpWidget(app(13, const Color(0xFF3F51B5)));
    await expectSnapshot(tester, 'x', options: options);
    final Snapshot b = await captureSnapshot(tester, 'x', options: options);
    final List<ItemCrops> crops = writeCrops(
      diffSnapshots(a, b),
      Render.read('${tmp.path}/before', 'x'),
      Render.read('${tmp.path}/after', 'x'),
      '${tmp.path}/out',
    );
    expect(crops.map((ItemCrops c) => c.type), <String>['Layout', 'Style']);
    expect(crops.first.sameAs, isNull);
    expect(crops.last.sameAs, crops.first.number);
    expect(crops.last.diff, crops.first.diff);
  });

  test('a small change is light red and a large one dark red; the rest is grey', () {
    Rgba pixel(int r, int g, int b) => Rgba(1, 1, Uint8List.fromList(<int>[r, g, b, 255]));
    final Rgba shade = diffImage(pixel(0x39, 0x49, 0xAB), pixel(0x3F, 0x51, 0xB5))!;
    final Rgba moved = diffImage(pixel(255, 255, 255), pixel(0x39, 0x49, 0xAB))!;
    final Rgba same = diffImage(pixel(230, 30, 30), pixel(230, 30, 30))!;
    expect(shade.pixels[0], greaterThan(moved.pixels[0]));
    expect(shade.pixels[1], greaterThan(moved.pixels[1]));
    expect(shade.pixels[1], lessThan(shade.pixels[0]), reason: 'still red');
    final Rgba full = diffImage(pixel(0, 0, 0), pixel(255, 255, 255))!;
    expect(full.pixels.sublist(0, 3), <int>[diffDark.$1, diffDark.$2, diffDark.$2]);
    // An unchanged red pixel is grey, so it is not read as a change.
    expect(same.pixels[0], same.pixels[1]);
  });

  test('images of different sizes get no diff', () {
    expect(diffImage(Rgba.blank(2, 2), Rgba.blank(3, 2)), isNull);
  });
}
