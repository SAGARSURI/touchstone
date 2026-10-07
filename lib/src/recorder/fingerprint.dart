// Fingerprints for engine objects that arrive as handles (assumption A2):
// paths by bounds plus sampled metrics, images by decoded bytes, text by source
// span plus line metrics.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/rendering.dart';

import 'canonical.dart' as c;
import 'describe.dart';

/// Number of equally spaced samples taken along each path contour.
const int pathSamplesPerContour = 16;

/// Bounds, fill type, and per contour its length, closure and tangents at
/// [pathSamplesPerContour] + 1 equally spaced offsets.
String fingerprintPath(Path path) {
  final b = StringBuffer('path(')
    ..write(c.rect(path.getBounds()))
    ..write(';')
    ..write(path.fillType.name);
  for (final ui.PathMetric metric in path.computeMetrics()) {
    b
      ..write(';k')
      ..write(metric.contourIndex)
      ..write(':')
      ..write(c.d(metric.length))
      ..write(metric.isClosed ? 'z' : 'o');
    for (var i = 0; i <= pathSamplesPerContour; i++) {
      final ui.Tangent? t = metric.getTangentForOffset(metric.length * i / pathSamplesPerContour);
      if (t == null) {
        b.write('|-');
      } else {
        b
          ..write('|')
          ..write(c.offset(t.position))
          ..write(c.d(t.angle));
      }
    }
  }
  b.write(')');
  return b.toString();
}

/// Fingerprint of a painted paragraph.
///
/// A [ui.Paragraph] does not expose its text, so the source span is read from
/// the render object that painted it. A paragraph from any other painter (a
/// [CustomPainter] using a [TextPainter], for example) has no readable source
/// and marks the node opaque.
String fingerprintParagraph(ui.Paragraph p, DescribeContext ctx) {
  final InlineSpan? span;
  final List<Object?> extra;
  switch (ctx.owner) {
    case final RenderParagraph rp:
      span = rp.text;
      extra = <Object?>[rp.textAlign, rp.textDirection, rp.softWrap, rp.overflow, rp.maxLines];
    case final RenderEditable re:
      span = re.text;
      extra = <Object?>[re.textAlign, re.textDirection, re.obscureText, re.maxLines];
    default:
      span = null;
      extra = const <Object?>[];
  }
  final b = StringBuffer('para(');
  if (span == null) {
    ctx.markOpaque(OpaqueReason.unknownTextSource, ctx.owner.runtimeType.toString());
    b.write('src?');
  } else {
    b
      ..write(describeSpan(span, ctx))
      ..write(';')
      ..write(extra.map((Object? e) => e is Enum ? e.name : '$e').join(','));
  }
  b
    ..write(';w=')
    ..write(c.d(p.width))
    ..write(';h=')
    ..write(c.d(p.height))
    ..write(';ll=')
    ..write(c.d(p.longestLine))
    ..write(';ab=')
    ..write(c.d(p.alphabeticBaseline))
    ..write(';ib=')
    ..write(c.d(p.ideographicBaseline))
    ..write(';ex=')
    ..write(p.didExceedMaxLines);
  for (final ui.LineMetrics l in p.computeLineMetrics()) {
    b.write(
      ';L${l.lineNumber}:${l.hardBreak},${c.d(l.ascent)},${c.d(l.descent)},'
      '${c.d(l.unscaledAscent)},${c.d(l.height)},${c.d(l.width)},${c.d(l.left)},${c.d(l.baseline)}',
    );
  }
  if (span != null) {
    final int length = span.toPlainText(includeSemanticsLabels: false).length;
    for (final TextBox box in p.getBoxesForRange(0, length)) {
      b.write(';B${c.d(box.left)},${c.d(box.top)},${c.d(box.right)},${c.d(box.bottom)},${box.direction.name}');
    }
  }
  b.write(')');
  return b.toString();
}

/// Exact text for a span tree: text, style and placeholders, in order.
String describeSpan(InlineSpan span, DescribeContext ctx) {
  final b = StringBuffer();
  void visit(InlineSpan s) {
    switch (s) {
      case TextSpan():
        b
          ..write('{T')
          ..write(jsonEncode(s.text ?? ''))
          ..write(describeTextStyle(s.style, ctx));
        if (s.locale != null) {
          b.write('loc=${s.locale}');
        }
        for (final InlineSpan child in s.children ?? const <InlineSpan>[]) {
          visit(child);
        }
        b.write('}');
      case PlaceholderSpan():
        b.write('{W${s.alignment.name},${s.baseline?.name}${describeTextStyle(s.style, ctx)}}');
      default:
        b.write('{?${s.runtimeType}}');
    }
  }

  visit(span);
  return b.toString();
}

String describeTextStyle(TextStyle? s, DescribeContext ctx) {
  if (s == null) {
    return '';
  }
  String paint(Paint? p) => p == null ? '-' : describePaint(p, ctx);
  return c.rec('S', <Object?>[
    s.inherit,
    if (s.color == null) null else c.color(s.color!),
    if (s.backgroundColor == null) null else c.color(s.backgroundColor!),
    s.fontFamily,
    s.fontFamilyFallback?.join('|'),
    s.fontSize,
    s.fontWeight?.value,
    s.fontStyle,
    s.letterSpacing,
    s.wordSpacing,
    s.textBaseline,
    s.height,
    s.leadingDistribution,
    s.locale,
    paint(s.foreground),
    paint(s.background),
    s.shadows?.map((Shadow sh) => '${c.color(sh.color)}${c.offset(sh.offset)}${c.d(sh.blurRadius)}').join('|'),
    s.fontFeatures?.map((ui.FontFeature f) => '${f.feature}=${f.value}').join('|'),
    s.fontVariations?.map((ui.FontVariation v) => '${v.axis}=${c.d(v.value)}').join('|'),
    s.decoration,
    if (s.decorationColor == null) null else c.color(s.decorationColor!),
    s.decorationStyle,
    s.decorationThickness,
    s.overflow,
  ]);
}

/// Hash of an image's decoded bytes, plus its size.
///
/// Reading the bytes is asynchronous, so the recorder collects images during
/// paint and resolves them afterwards.
Future<String> fingerprintImage(ui.Image image) async {
  final ByteData? bytes = await image.toByteData();
  if (bytes == null) {
    throw StateError('Image bytes could not be read.');
  }
  final Digest digest = sha256.convert(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  return 'img(${image.width}x${image.height}:$digest)';
}
