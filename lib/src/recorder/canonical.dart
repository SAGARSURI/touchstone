// Canonical, by-value text for the values that reach a canvas.
//
// Every double is written with Dart's shortest round-trip form
// (`double.toString`), never rounded: rounding would move instability to
// bucket edges (spec, assumption A3).

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Shortest round-trip text for [value].
String d(double value) => value.toString();

/// Writes doubles in a list, comma separated.
String ds(Iterable<double> values) => values.map(d).join(',');

String offset(Offset o) => '(${d(o.dx)},${d(o.dy)})';

String size(Size s) => '(${d(s.width)}x${d(s.height)})';

String rect(Rect r) => '[${d(r.left)},${d(r.top)},${d(r.right)},${d(r.bottom)}]';

String radius(Radius r) => '${d(r.x)}/${d(r.y)}';

String rrect(RRect r) =>
    'rr[${d(r.left)},${d(r.top)},${d(r.right)},${d(r.bottom)};'
    '${radius(r.tlRadius)};${radius(r.trRadius)};'
    '${radius(r.brRadius)};${radius(r.blRadius)}]';

String rsuperellipse(RSuperellipse r) =>
    'rse[${d(r.left)},${d(r.top)},${d(r.right)},${d(r.bottom)};'
    '${radius(r.tlRadius)};${radius(r.trRadius)};'
    '${radius(r.brRadius)};${radius(r.blRadius)}]';

/// Exact colour: the four components as stored, plus the colour space.
///
/// `Color.toString` rounds to four decimals, so it is not used.
String color(Color c) => 'c(${d(c.a)},${d(c.r)},${d(c.g)},${d(c.b)},${c.colorSpace.name})';

String colors(Iterable<Color> cs) => cs.map(color).join(',');

String float64s(Float64List m) => '{${ds(m)}}';

String float32s(Float32List m) => '{${m.map((double v) => d(v)).join(',')}}';

String int32s(Int32List m) => '{${m.join(',')}}';

String alignment(AlignmentGeometry a) {
  if (a is Alignment) {
    return 'A(${d(a.x)},${d(a.y)})';
  }
  if (a is AlignmentDirectional) {
    return 'AD(${d(a.start)},${d(a.y)})';
  }
  // Mixed alignments only arise from arithmetic; their text is exact.
  return 'A?(${a.runtimeType}:$a)';
}

String? textDirection(TextDirection? t) => t?.name;

/// Wraps a list of fields into one canonical record.
String rec(String name, List<Object?> fields) => '$name(${fields.map(_field).join(';')})';

String _field(Object? v) {
  if (v == null) {
    return '-';
  }
  if (v is double) {
    return d(v);
  }
  if (v is Enum) {
    return v.name;
  }
  return v.toString();
}

/// Text for a [ui.PointMode] list.
String points(List<Offset> pts) => pts.map(offset).join('');
