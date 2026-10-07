import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Values a fixture screen reads, so one edit can be applied by overriding a
/// single knob.
class Knobs {
  const Knobs(this._values);

  final Map<String, Object?> _values;

  T call<T>(String name) {
    assert(_values.containsKey(name), 'Unknown knob $name');
    return _values[name] as T;
  }

  Knobs override(Map<String, Object?> changes) {
    for (final String key in changes.keys) {
      assert(_values.containsKey(key), 'Unknown knob $key');
    }
    return Knobs(<String, Object?>{..._values, ...changes});
  }
}

/// What a mutation is expected to change.
enum MutationKind {
  /// Changes what is drawn: colour, opacity, clip, text, icon, image, path,
  /// paint order, painter output, theme.
  paint,

  /// Changes size or position only.
  layout,

  /// Changes the tree: a widget added, removed or reordered.
  structure,

  /// Changes semantics only; pixels stay the same.
  semantics,
}

/// Whether the pixel oracle can see a mutation in the widget-test
/// environment (spec, Oracles: the oracle is ground truth for the test
/// environment only, and the default test font draws glyphs as boxes).
enum PixelExpectation { changes, unchanged, outsideOracle }

class Mutation {
  const Mutation(
    this.name,
    this.changes, {
    required this.target,
    this.kind = MutationKind.paint,
    this.pixels = PixelExpectation.changes,
  });

  final String name;
  final Map<String, Object?> changes;

  /// Key of the widget whose render subtree must report the change.
  final String target;
  final MutationKind kind;
  final PixelExpectation pixels;
}

/// Shared inputs a fixture may use, prepared by the harness before pumping.
class FixtureAssets {
  const FixtureAssets({required this.imageA, required this.imageB, this.program});

  /// PNG bytes of two images that differ in one pixel.
  final Uint8List imageA;
  final Uint8List imageB;

  /// The compiled `shaders/tint.frag`, when the test environment loads it.
  final ui.FragmentProgram? program;
}

class FixtureScreen {
  const FixtureScreen({
    required this.name,
    required this.defaults,
    required this.build,
    required this.mutations,
    this.usesImages = false,
  });

  final String name;
  final Map<String, Object?> defaults;
  final Widget Function(Knobs knobs, FixtureAssets assets) build;
  final List<Mutation> mutations;

  /// Whether the harness must decode images before capture.
  final bool usesImages;

  Knobs get knobs => Knobs(defaults);
}

/// Wraps [child] so a key string can locate it.
Widget tagged(String key, Widget child) => KeyedSubtree(key: ValueKey<String>(key), child: child);
