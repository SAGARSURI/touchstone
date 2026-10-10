// The report's short wording (lib/src/diff/summary.dart) and the folding of
// repeated changes (lib/src/diff/report.dart).

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/src/diff/summary.dart';
import 'package:touchstone/touchstone.dart';

const String grey = 'Color(alpha: 0.1216, red: 0.1059, green: 0.1059, blue: 0.1294, colorSpace: ColorSpace.sRGB)';
const String accent =
    'brand.accent (Color(alpha: 1.0000, red: 0.2235, green: 0.2863, blue: 0.6706, colorSpace: ColorSpace.sRGB))';

void main() {
  test('layout sizes are rounded to two places, or more when two would hide the change', () {
    expect(shortenSize('size 86.927734375x60 -> 88.927734375x62'), 'size 86.93x60 -> 88.93x62');
    expect(shortenSize('size 10.001x5 -> 10.004x5'), 'size 10.001x5 -> 10.004x5');
    expect(shortenSize('size 163.625x140 -> 163.625x142'), 'size 163.63x140 -> 163.63x142');
    expect(shortenSize('size -> 2x2'), 'size -> 2x2');
  });

  group('summarizeFields', () {
    test('fields with the same change are one entry, named by the public widget field, the rest left out', () {
      expect(
        summarizeFields(<String, String>{
          'RenderPhysicalShape.color': '$grey -> $accent',
          '_MaterialInterior.color': '$grey -> $accent',
          'Material.color': '$grey -> $accent',
          'FilledButton.enabled': 'disabled -> (none)',
        }),
        'Material.color: #1F1B1B21 -> brand.accent; FilledButton.enabled: disabled -> (none)',
      );
    });

    test('a render object field with the same change is not counted as a further change', () {
      expect(
        summarizeFields(<String, String>{'RenderOpacity.opacity': '(none) -> 0.6', 'Opacity.opacity': '(none) -> 0.6'}),
        'Opacity.opacity: (none) -> 0.6',
      );
    });

    test('a colour with the same token on both sides keeps the token and shows the values that changed', () {
      expect(
        shortenValue(
          'positive (Color(alpha: 1.0000, red: 0.1176, green: 0.5569, blue: 0.2431, colorSpace: ColorSpace.sRGB)) -> '
          'positive (Color(alpha: 1.0000, red: 0.1176, green: 0.5569, blue: 0.2471, colorSpace: ColorSpace.sRGB))',
        ),
        'positive #FF1E8E3E -> #FF1E8E3F',
      );
    });

    test('a colour outside sRGB is left as written', () {
      const p3 = 'Color(alpha: 1.0000, red: 1.0000, green: 0.0000, blue: 0.0000, colorSpace: ColorSpace.displayP3)';
      expect(shortenValue('$p3 -> (none)'), '$p3 -> (none)');
    });

    test('a constructor call with one changed argument is narrowed to it', () {
      expect(
        summarizeFields(<String, String>{
          'Container.bg':
              'BoxDecoration(color: $grey, borderRadius: BorderRadius.circular(4.0)) -> '
              'BoxDecoration(color: $accent, borderRadius: BorderRadius.circular(4.0))',
        }),
        'Container.bg.color: #1F1B1B21 -> brand.accent',
      );
    });

    test('a call with two changed arguments, or positional ones, is kept whole', () {
      const two = 'BoxDecoration(color: A, shape: B) -> BoxDecoration(color: C, shape: D)';
      const positional = 'EdgeInsets(16.0, 24.0, 16.0, 8.0) -> EdgeInsets(16.0, 24.0, 16.0, 9.0)';
      expect(summarizeFields(<String, String>{'x': two}), 'x: $two');
      expect(summarizeFields(<String, String>{'x': positional}), 'x: $positional');
    });

    test('commas inside quotes do not split arguments', () {
      expect(
        summarizeFields(<String, String>{'t': 'Tip(text: "a, b", size: 1) -> Tip(text: "a, b", size: 2)'}),
        't.size: 1 -> 2',
      );
    });
  });

  group('report', () {
    Widget row(Color c) => SizedBox(width: 100, height: 20, child: ColoredBox(color: c));

    testWidgets('the same change on several instances is one line naming each', (WidgetTester tester) async {
      final options = SnapshotOptions(policy: ComponentPolicy(include: <Type>{Swatch}));
      Widget app(Color c) => Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: <Widget>[
            Swatch(child: row(c)),
            Swatch(child: row(c)),
            Swatch(child: row(c)),
          ],
        ),
      );
      await tester.pumpWidget(app(const Color(0xFF000000)));
      final Snapshot a = await captureSnapshot(tester, 'x', options: options);
      await tester.pumpWidget(app(const Color(0xFF0000FF)));
      final Snapshot b = await captureSnapshot(tester, 'x', options: options);
      final ChangeReport r = diffSnapshots(a, b);
      expect(r.items, hasLength(3));
      final String text = renderReport(r, Policy.defaults().decide(r));
      expect(text, contains('Style     Swatch in 3 places        ColoredBox.color: #FF000000 -> #FF0000FF'));
      expect(text, contains('at: Swatch@0, Swatch@1, Swatch@2'));
      expect(text, isNot(contains('\n2  ')));
    });
  });
}

class Swatch extends StatelessWidget {
  const Swatch({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
