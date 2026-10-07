# Assumption register

The tech spec lists fourteen assumptions that carry the design. Each entry
records the experiment, the data and the date. An assumption that fails takes
its fallback; it is never patched with a tolerance.

A phase starts only after the previous phase's exit gate is recorded here.

| ID | Assumption | Status | Last data |
| --- | --- | --- | --- |
| A1 | A custom recording context captures each node's own paint, including opacity and layer effects | Holds on fixtures, with per-node fallback for 5 node kinds | 2026-10-07 |
| A2 | Paths, images and text can be fingerprinted without rasterizing | Holds on fixtures; text without a readable source falls back | 2026-10-07 |
| A3 | Snapshots are byte-identical across macOS machines | Not yet tested (Phase 1) | |
| A4 | Equal hashes imply equal pixels | 0 capture gaps on fixtures | 2026-10-07 |
| A5 | Node identity survives refactors | Not yet tested (Phase 2) | |
| A6 | Keeping only app-owned widgets gives a recognisable tree | Not yet tested (Phase 1) | |
| A7 | A change in the widget-test environment is a change users see | Not yet tested (Phase 3) | |
| A8 | Cascade grouping names the true root cause | Not yet tested (Phase 2) | |
| A9 | Affected-test selection never skips a changed test | Not yet tested (Phase 4) | |
| A10 | Capture and diff are cheap enough for every pull request | First numbers recorded | 2026-10-07 |
| A11 | Pairwise variants catch what the full matrix catches | Not yet tested (Phase 4) | |
| A12 | A Flutter upgrade can be absorbed without re-reviewing every baseline | Not yet tested (Phase 3) | |
| A13 | Existing golden tests can be made deterministic | Not yet tested (Phase 1) | |
| A14 | The schema is not Flutter-shaped | Not yet tested (Phase 1) | |

## Phase 0: feasibility spikes

**Exit gate (spec):** a recorded decision per node kind, recorded paint or pixel
hash, and 0 capture gaps on fixtures.

**Result, 2026-10-07: met on Linux.** 58 mutations over 10 fixture screens, 0
capture gaps, 0 missed changes. The decision per node kind is in
[phase0/node_kinds.md](phase0/node_kinds.md); every mutation is in
[phase0/mutations.md](phase0/mutations.md); raw data in
[phase0/report.json](phase0/report.json).

### Environment

| Item | Value |
| --- | --- |
| Flutter | 3.47.6 stable, framework 5fc346839b, engine b8c8d3d8d5 |
| Dart | 3.13.5 |
| Host | Linux x64 (cloud container) |
| Renderer | Skia software, as `flutter test` runs by default |
| Fonts | Default test font (FlutterTest) |
| Viewport | 390 x 844 logical, device pixel ratio 3.0 |
| Harness | [corpus/fixture_app/test/phase0](../corpus/fixture_app/test/phase0/phase0_test.dart) |

**Which renderer widget tests use.** The spec asks Phase 0 to confirm this
before any pixel hash is trusted. `flutter test` starts `flutter_tester` with
`--enable-software-rendering --skia-deterministic-rendering` unless
`--enable-impeller` is passed (flutter_tools,
`lib/src/test/flutter_tester_device.dart`). So widget tests render with Skia
software, deterministically. Running the same suite with `--enable-impeller`
gave different pixels (a ShaderMask gradient differs by 1 to 2 levels per
channel) and, for 2 of 10 screens with no opaque node, a different recording:
under Impeller, Material's scroll views build a stretch overscroll effect with
an extra `ImageFilter` render object, so the widget tree itself depends on the
renderer. See open decision 1.

### A1: custom recording context

**Experiment.** A `PaintingContext` that gives each render object its own op
stream ([paint_recorder.dart](../lib/src/recorder/paint_recorder.dart)). A child
leaves a marker in its parent's stream and is painted at its own origin, so its
ops do not change when only its position changes. Clip, transform, opacity,
colour filter and every pushed layer are recorded with their type and
parameters. Run every paint mutation on the fixture app.

**Pass criterion.** Every paint mutation changes the node's paint hash; 0
capture gaps in the shadow audit.

**Data.** Of 50 paint mutations, 48 changed the subtree hash of the edited
widget and 47 changed an own paint hash inside it. Paint order is the one
caught by child order rather than own paint. The two with no change drew
nothing different: shadow blur (not drawn in tests, see finding 3) and a
same-length label painted by a `CustomPainter` under the box font (see A2).
0 capture gaps.

**Findings that shaped the recorder.**

1. Opacity is not pushed through the context. `RenderOpacity` and
   `RenderAnimatedOpacity` are repaint boundaries whose `OpacityLayer` comes
   from `updateCompositedLayer`, and the real `paintChild` composites it. The
   recorder reads that layer (`debugLayer`) for every repaint boundary and
   records its type and parameters in the child's own paint. Without this,
   opacity 0.5 and 0.6 recorded identically.
2. Recording mutates real layers. Render objects set properties on the layers
   they own before calling `pushLayer`; `RenderShaderMask` sets `maskRect` from
   the paint offset. Recording each node at its own origin left the real
   ShaderMask layer's mask at (0, 0), and a rasterization taken after recording
   showed the mask in the wrong place. Capture therefore rasterizes before
   recording and then marks every recorded render object as needing paint and
   pumps one frame, which restores the layers (`PaintRecorder.restore`).
3. `flutter_test` sets `debugDisableShadows`, so box shadows are drawn without
   blur. A blur radius change draws nothing different and the recording is
   rightly unchanged. This belongs in the coverage report as a test-environment
   limit, beside the box font.

### A2: fingerprints without rasterizing

**Experiment.** Paths: bounds, fill type, and per contour its length, closure
and the tangent at 17 equally spaced offsets. Images: SHA-256 of the decoded
RGBA bytes, plus size. Text: the source span (text and full style, read from
the `RenderParagraph` or `RenderEditable` that painted it) plus paragraph and
line metrics and the boxes of the whole range. Run shape, image and text
mutations; repeat every capture.

**Pass criterion.** 0 missed mutations and 0 fingerprint changes across
repeats.

**Data.** 0 missed mutations (data point, curve control point, clip path,
stroke width, image pixel, image fit, text colour, letter spacing, decoration,
span colour, font weight, text length, truncation). 5 repeats per screen in one
process, and the whole suite in 3 separate processes: identical root hashes
every time.

**Where it falls back.** A `ui.Paragraph` does not expose its text, so a
paragraph painted by anything other than `RenderParagraph` or `RenderEditable`
(a `CustomPainter` using `TextPainter`) has no readable source and its node is
pixel-hashed. With the default test font a same-length label change in such a
painter is invisible to both the recording and the pixel oracle ("painter
label" in the mutation table); with real fonts the pixel hash would see it.

**Values that print lossily.** `Color`, `Rect`, `Offset` and `MaskFilter`
print fixed decimals. The recorder never uses those strings: colours are
written from their four stored components, geometry from exact doubles. A
`MaskFilter` or `ColorFilter.mode` is written only when a candidate rebuilt
from the printed or contextual value compares equal with `==`; `Paint` stores
mask sigma as a float32, so candidates are also tried at float32 precision.
Anything that cannot be verified marks the node opaque.

### A4: equal hashes imply equal pixels

**Experiment.** Shadow pixel audit over every fixture screen and mutation: the
whole view rasterized at device pixel ratio 3 and compared exactly.

**Pass criterion.** 0 capture gaps.

**Data.** 0 capture gaps in 58 mutations. One false alarm, built on purpose: a
header colour alpha step (0xCC to 0xCD) blended over a near-white background
rounds to the same 8-bit pixels, so the value changed and no pixel did. Four
changes sit outside the oracle's sight (same-length text or icon glyph changes
under the box font); three of them were recorded, and the fourth is the
`CustomPainter` label above.

This is a small, hand-written corpus. Phase 1 adds the mutation generator, and
Phase 3 the catalogue history, before A4 is trusted on real code.

### A10: first numbers

Per fixture screen, mean of 5 captures, milliseconds, on the container above.
"Pump" is the same pump and settle without capture. "Raster" is one full-view
rasterization, which the pixel oracle needs and which opaque nodes reuse.

| Screen | Nodes | Opaque | Snapshot ops (bytes) | Pump | Raster | Record | Resolve hashes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| text | 48 | 0 | 2863 | 21 | 15.7 | 3.5 | 4.2 |
| decorated | 66 | 0 | 2045 | 24 | 11.6 | 1.0 | 1.6 |
| effects | 87 | 1 | 8591 | 23 | 15.6 | 3.1 | 5.9 |
| images | 55 | 0 | 1584 | 24 | 12.6 | 0.9 | 1.8 |
| lists | 311 | 0 | 25402 | 45 | 12.1 | 3.3 | 3.5 |
| chart | 46 | 1 | 5229 | 21 | 13.2 | 0.8 | 31.2 |
| platform_view | 48 | 1 | 1741 | 22 | 23.9 | 0.7 | 212.0 |
| themed | 128 | 0 | 9007 | 41 | 10.3 | 1.5 | 1.3 |
| overlay | 60 | 0 | 5641 | 29 | 46.3 | 1.1 | 1.5 |
| kinds | 147 | 2 | 7684 | 28 | 13.6 | 1.3 | 23.0 |

Recording and hashing a screen with no opaque node costs 2 to 7 ms against a
20 to 45 ms pump. An opaque node costs a rasterization plus hashing its region,
which is what dominates: the platform-view placeholder covers the whole screen
and its 11.8 MB region takes about 200 ms to hash. The share of opaque nodes is
at most 2.2% on any screen. These are per-node paint records; the Phase 1
snapshot format, its size and the "under 20% of test time" budget are measured
from Phase 1 on.

### Decision per node kind

64 render object kinds were painted. 60 are recorded by value. The rest:

| Node kind | Decision | Why |
| --- | --- | --- |
| `TextureBox` | Pixel hash | A texture's pixels do not exist in a widget test |
| `PlatformViewRenderBox` | Pixel hash | Same, for platform views |
| `RenderShaderMask` | Pixel hash | Its shader comes from a callback as a `ui.Gradient`, which keeps no readable fields |
| `RenderCustomPaint` | Recorded; pixel hash per node | Only when the painter uses a gradient or fragment shader, or paints `TextPainter` text |

A gradient in a `BoxDecoration` or `ShapeDecoration` is recorded by value, from
the decoration that built it.

### Open decisions for Sagar

These came out of Phase 0 and would change the spec, so they are not built.

1. **Renderer in the toolchain fingerprint.** The widget tree differs between
   Skia and Impeller in widget tests, not only the pixels. Proposal: add the
   renderer to `toolchain`, so a baseline from one renderer routes a run on the
   other to migration.
2. **Material and Cupertino in 3.47.** The spec says they ship as standalone
   packages from 3.47. In 3.47.6 they are still in the Flutter SDK
   (`package:flutter/material.dart`). The core imports only foundation,
   painting, rendering and widgets either way, so nothing changes in the design.
3. **Shadows in tests.** Should the coverage report declare that box-shadow blur
   is not drawn in widget tests (`debugDisableShadows`)?
