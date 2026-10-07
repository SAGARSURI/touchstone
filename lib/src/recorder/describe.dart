// By-value descriptions of engine objects that reach a canvas or a layer.
//
// Several `dart:ui` objects are engine handles whose `toString` is lossy
// (colours and rects are printed with fixed decimals) or opaque (gradients keep
// no readable fields). A description is emitted only when it is exact: either
// the object prints exact values, or a candidate rebuilt from the printed or
// contextual values compares equal with `==`. Anything else marks the node
// opaque, so it falls back to a pixel hash (spec: "Fail closed").

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'canonical.dart' as c;

/// Why a node's paint could not be recorded by value.
///
/// The spec names platform view, fragment shader and unknown layer; the other
/// values make the "call it cannot describe" case of the recorder specific.
enum OpaqueReason {
  platformView,
  texture,
  fragmentShader,
  unknownLayer,
  unknownShader,
  unknownFilter,
  unknownMaskFilter,
  picture,
  vertices,
  unknownTextSource,

  /// A path was drawn, used as a clip or cast a shadow. Path fingerprints are
  /// lossy (two different paths can share every sampled value), so the spec's
  /// A2 fallback applies: the node is pixel-hashed.
  path,
}

/// Context the describers may use to verify a value exactly.
class DescribeContext {
  DescribeContext(this.owner, this.markOpaque);

  /// The render object whose paint is being recorded.
  final RenderObject owner;

  /// Called when a value cannot be described exactly.
  final void Function(OpaqueReason reason, String detail) markOpaque;

  /// Gradient shaders already described for [owner]. Only the first is the
  /// decoration's background; any other was built by something else (a
  /// custom border, for example) and cannot be read back.
  int gradientShaders = 0;
}

String describePaint(Paint p, DescribeContext ctx) {
  return c.rec('P', <Object?>[
    c.color(p.color),
    p.blendMode,
    p.style,
    p.strokeWidth,
    p.strokeCap,
    p.strokeJoin,
    p.strokeMiterLimit,
    p.isAntiAlias,
    p.filterQuality,
    p.invertColors,
    if (p.maskFilter != null) describeMaskFilter(p.maskFilter!, ctx) else null,
    if (p.colorFilter != null) describeColorFilter(p.colorFilter!, ctx) else null,
    if (p.imageFilter != null) describeImageFilter(p.imageFilter!, ctx) else null,
    if (p.shader != null) describeShader(p.shader!, ctx) else null,
  ]);
}

final RegExp _maskFilterText = RegExp(r'^MaskFilter\.blur\(BlurStyle\.(\w+), (-?[\d.]+)\)$');

String describeMaskFilter(MaskFilter filter, DescribeContext ctx) {
  // `MaskFilter.toString` prints sigma with one decimal, so the value is only
  // trusted when a rebuilt candidate compares equal.
  final Match? m = _maskFilterText.firstMatch(filter.toString());
  if (m != null) {
    final BlurStyle style = BlurStyle.values.byName(m.group(1)!);
    // Paint stores sigma as a float32 and its getter rebuilds the filter from
    // that, so each candidate is also tried at float32 precision.
    final candidates = <double>[
      for (final double sigma in <double>[double.parse(m.group(2)!), ..._contextSigmas(ctx.owner)]) ...<double>[
        sigma,
        Float32List.fromList(<double>[sigma])[0],
      ],
    ];
    for (final sigma in candidates) {
      if (MaskFilter.blur(style, sigma) == filter) {
        return 'MF.blur(${style.name},${c.d(sigma)})';
      }
    }
  }
  ctx.markOpaque(OpaqueReason.unknownMaskFilter, filter.toString());
  return 'MF?';
}

Iterable<double> _contextSigmas(RenderObject owner) sync* {
  final List<BoxShadow>? shadows = switch (owner) {
    RenderDecoratedBox(decoration: BoxDecoration(:final boxShadow)) => boxShadow,
    RenderDecoratedBox(decoration: ShapeDecoration(:final shadows)) => shadows,
    _ => null,
  };
  for (final BoxShadow shadow in shadows ?? const <BoxShadow>[]) {
    yield shadow.blurSigma;
  }
}

final RegExp _colorText = RegExp(
  r'Color\(alpha: ([\d.]+), red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+), colorSpace: ColorSpace\.(\w+)\)',
);
final RegExp _modeText = RegExp(r', BlendMode\.(\w+)\)$');

String describeColorFilter(ColorFilter filter, DescribeContext ctx) {
  final text = filter.toString();
  if (text.startsWith('ColorFilter.matrix(') ||
      text == 'ColorFilter.linearToSrgbGamma()' ||
      text == 'ColorFilter.srgbToLinearGamma()') {
    // Matrix values are a List<double>, printed in shortest round-trip form.
    return 'CF.$text';
  }
  if (text.startsWith('ColorFilter.mode(')) {
    final Match? cm = _colorText.firstMatch(text);
    final Match? mm = _modeText.firstMatch(text);
    if (cm != null && mm != null) {
      final BlendMode mode = BlendMode.values.byName(mm.group(1)!);
      final ui.ColorSpace space = ui.ColorSpace.values.byName(cm.group(5)!);
      final List<double> v = <double>[for (var i = 1; i <= 4; i++) double.parse(cm.group(i)!)];
      final candidates = <Color>[
        // 8-bit colours, the common case, survive the four-decimal print.
        Color.from(
          alpha: (v[0] * 255).round() / 255,
          red: (v[1] * 255).round() / 255,
          green: (v[2] * 255).round() / 255,
          blue: (v[3] * 255).round() / 255,
          colorSpace: space,
        ),
        if (space == ui.ColorSpace.sRGB)
          Color.fromARGB((v[0] * 255).round(), (v[1] * 255).round(), (v[2] * 255).round(), (v[3] * 255).round()),
        Color.from(alpha: v[0], red: v[1], green: v[2], blue: v[3], colorSpace: space),
      ];
      for (final candidate in candidates) {
        if (ColorFilter.mode(candidate, mode) == filter) {
          return 'CF.mode(${c.color(candidate)},${mode.name})';
        }
      }
    }
  }
  ctx.markOpaque(OpaqueReason.unknownFilter, text);
  return 'CF?';
}

final RegExp _exactImageFilter = RegExp(
  r'^ImageFilter\.(blur\([^,]+, [^,]+, \w+\)|dilate\(.*\)|erode\(.*\)|matrix\(\[.*\], FilterQuality\.\w+\))$',
);

String describeImageFilter(ui.ImageFilter filter, DescribeContext ctx) {
  if (filter is ColorFilter) {
    return describeColorFilter(filter, ctx);
  }
  // blur without bounds, dilate, erode and matrix print raw doubles. A blur
  // with bounds prints a fixed-decimal Rect and a compose prints its inner
  // colour filters lossily, so both are opaque.
  final text = filter.toString();
  if (_exactImageFilter.hasMatch(text)) {
    return 'IF.${text.substring('ImageFilter.'.length)}';
  }
  ctx.markOpaque(OpaqueReason.unknownFilter, text);
  return 'IF?';
}

String describeShader(Shader shader, DescribeContext ctx) {
  if (shader is ui.FragmentShader) {
    ctx.markOpaque(OpaqueReason.fragmentShader, 'FragmentShader');
    return 'SH.fragment';
  }
  if (shader is ui.Gradient && ctx.gradientShaders++ == 0) {
    // A ui.Gradient keeps no readable fields. A decorated box builds its
    // background shader from its decoration's gradient, the box rect and the
    // ambient text direction, so those describe it. Only decorations whose
    // every other part is a stock type are trusted: a custom border or shape
    // may build shaders of its own.
    final RenderObject owner = ctx.owner;
    if (owner is RenderDecoratedBox) {
      final Gradient? gradient = switch (owner.decoration) {
        final BoxDecoration d when d.runtimeType == BoxDecoration && _stockBorder(d.border) => d.gradient,
        final ShapeDecoration d when d.runtimeType == ShapeDecoration && _stockShape(d.shape) => d.gradient,
        _ => null,
      };
      final String? text = gradient == null ? null : describeGradient(gradient);
      if (text != null) {
        return 'SH.$text@${c.textDirection(owner.configuration.textDirection) ?? '-'}';
      }
    }
  }
  ctx.markOpaque(OpaqueReason.unknownShader, shader.runtimeType.toString());
  return 'SH?';
}

bool _stockBorder(BoxBorder? border) =>
    border == null || border.runtimeType == Border || border.runtimeType == BorderDirectional;

/// Shape borders from the painting library, which paint only with
/// [BorderSide] colours.
bool _stockShape(ShapeBorder shape) => switch (shape.runtimeType) {
  const (Border) ||
  const (BorderDirectional) ||
  const (RoundedRectangleBorder) ||
  const (RoundedSuperellipseBorder) ||
  const (CircleBorder) ||
  const (OvalBorder) ||
  const (StadiumBorder) ||
  const (BeveledRectangleBorder) ||
  const (ContinuousRectangleBorder) ||
  const (StarBorder) ||
  const (LinearBorder) => true,
  _ => false,
};

/// Exact text for a painting-library gradient, or null when it holds a value
/// with no exact form (an unknown [GradientTransform]).
String? describeGradient(Gradient g) {
  final String? transform = switch (g.transform) {
    null => '-',
    GradientRotation(:final radians) => 'rot(${c.d(radians)})',
    _ => null,
  };
  if (transform == null) {
    return null;
  }
  final String stops = g.stops == null ? '-' : c.ds(g.stops!);
  return switch (g) {
    LinearGradient(:final begin, :final end, :final tileMode) => c.rec('LG', <Object?>[
      c.alignment(begin),
      c.alignment(end),
      c.colors(g.colors),
      stops,
      tileMode,
      transform,
    ]),
    RadialGradient(:final center, :final radius, :final tileMode, :final focal, :final focalRadius) => c.rec(
      'RG',
      <Object?>[
        c.alignment(center),
        radius,
        c.colors(g.colors),
        stops,
        tileMode,
        if (focal == null) null else c.alignment(focal),
        focalRadius,
        transform,
      ],
    ),
    SweepGradient(:final center, :final startAngle, :final endAngle, :final tileMode) => c.rec('SG', <Object?>[
      c.alignment(center),
      startAngle,
      endAngle,
      c.colors(g.colors),
      stops,
      tileMode,
      transform,
    ]),
    _ => null,
  };
}
