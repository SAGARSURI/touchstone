# Assumption register

The tech spec lists fourteen assumptions that carry the design. Each entry
records the experiment, the data and the date. An assumption that fails takes
its fallback; it is never patched with a tolerance.

A phase starts only after the previous phase's exit gate is recorded here.

| ID | Assumption | Status | Last data |
| --- | --- | --- | --- |
| A1 | A custom recording context captures each node's own paint, including opacity and layer effects | Holds on fixtures; 3 of 50 paint mutations change no own paint hash, each explained below | 2026-10-07 |
| A2 | Paths, images and text can be fingerprinted without rasterizing | Fails for paths: fallback taken (pixel hash for nodes that draw paths). Holds for images, and for text with a readable source | 2026-10-07 |
| A3 | Snapshots are byte-identical across macOS machines | Fails: macOS arm64 and Intel differ on the pixel hashes of path-drawn nodes in 12 of 15 scenes. Fallback taken (baselines pinned to one host, recorded in the fingerprint) | 2026-10-08 |
| A4 | Equal hashes imply equal pixels | 0 capture gaps on fixtures and on the 14 review cases, after the review fixes | 2026-10-07 |
| A5 | Node identity survives refactors | Not yet tested (Phase 2) | |
| A6 | Keeping only app-owned widgets gives a recognisable tree | Review sheet ready; waiting on two engineers' review | 2026-10-08 |
| A7 | A change in the widget-test environment is a change users see | Not yet tested (Phase 3) | |
| A8 | Cascade grouping names the true root cause | Not yet tested (Phase 2) | |
| A9 | Affected-test selection never skips a changed test | Not yet tested (Phase 4) | |
| A10 | Capture and diff are cheap enough for every pull request | First numbers recorded, after the review fixes | 2026-10-07 |
| A11 | Pairwise variants catch what the full matrix catches | Not yet tested (Phase 4) | |
| A12 | A Flutter upgrade can be absorbed without re-reviewing every baseline | Not yet tested (Phase 3) | |
| A13 | Existing golden tests can be made deterministic | Holds: the gate fails 4 of 15 conventional goldens and names a node and a cause for each | 2026-10-08 |
| A14 | The schema is not Flutter-shaped | Holds: every field has a web source; 5 web captures parse as schema v1 | 2026-10-07 |

## Phase 0: feasibility spikes

**Exit gate (spec):** a recorded decision per node kind, recorded paint or pixel
hash, and 0 capture gaps on fixtures.

**Result, 2026-10-07: met on Linux, after the review below.** 58 mutations over
10 fixture screens and 14 regression cases from the review: 0 capture gaps, 0
missed changes. The first run also reported 0 gaps, but the review then built
10 cases that were gaps; the recorder was fixed and the cases are now permanent
tests. The decision per node kind is in [phase0/node_kinds.md](phase0/node_kinds.md);
every mutation is in [phase0/mutations.md](phase0/mutations.md); raw data in
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
widget and 47 changed an own paint hash inside it, so the pass criterion as
written holds for 47. The other three: paint order changes which child is
painted first, which the subtree hash records through child order, not own
paint; shadow blur and a same-length label in a `CustomPainter` draw nothing
different in the test environment (finding 3 below, and A2). None of the three
is a capture gap.

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

**Paths fail.** The review built two paths with the same bounds, contour
length and tangents at all 17 samples (a notch moved between two samples), and
a stroked path whose zero-length contour, drawn as a round-cap dot, moved
without changing any sampled value. Both changed pixels and not the
fingerprint. Sampling more densely only moves the problem, so the spec's
fallback applies: a node that draws a path, clips with a path or casts a
path shadow is pixel-hashed. The fingerprint stays in the recording for
attribution. Material's `PhysicalShape` (cards, chips, buttons with a shape),
`ClipPath`, `ClipOval` and a decoration with a border on some sides only all
draw paths, so they fall back; their cost is in A10.

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

An opaque node's pixel hash covers its reach: every pixel its own paint can
change. The recorder tracks the transform and clip in effect for every call and
takes the union of what each call draws, widened for stroke, mask blur and
glyph overhang, inside the clip. Effects with no bounded geometry (draw paint,
an image-filtered layer, an unknown layer) reach the whole clip; under an
image filter, a node reaches the clip where the filter was entered, since the
filter can move its pixels; and a node that overlaps a backdrop filter's
region takes that region too. Each node's composed transform is checked
against `RenderObject.getTransformTo`; a node where they differ is hashed over
the whole view. On the fixtures every node verified.

This is a small, hand-written corpus. Phase 1 adds the mutation generator, and
Phase 3 the catalogue history, before A4 is trusted on real code.

### A10: first numbers

Per fixture screen, mean of 5 captures, milliseconds, on the container above.
"Pump" is the same pump and settle without capture, also a mean of 5. "Raster"
is one full-view rasterization, which the pixel oracle needs and which opaque
nodes reuse. "Restore" marks recorded nodes for repaint and pumps the frame
that puts back the layer state recording touched. "Opaque area" is the summed
area of opaque regions as a share of the view (it can exceed 100% when regions
overlap).

| Screen | Nodes | Opaque | Opaque area | Snapshot ops (bytes) | Pump | Raster | Record | Resolve hashes | Restore |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| text | 48 | 0 | 0% | 2887 | 23.0 | 16.0 | 7.2 | 4.7 | 1.8 |
| decorated | 66 | 0 | 0% | 2073 | 18.0 | 9.9 | 2.1 | 1.9 | 1.3 |
| effects | 87 | 1 | 1% | 8615 | 21.0 | 8.8 | 4.1 | 4.2 | 1.9 |
| images | 55 | 0 | 0% | 1608 | 20.0 | 8.2 | 1.4 | 2.0 | 1.4 |
| lists | 311 | 16 | 6% | 27186 | 52.3 | 11.4 | 8.6 | 14.5 | 3.3 |
| chart | 46 | 2 | 21% | 5368 | 14.3 | 11.4 | 1.4 | 38.2 | 1.4 |
| platform_view | 48 | 1 | 36% | 1766 | 12.8 | 19.9 | 1.0 | 59.6 | 1.7 |
| themed | 128 | 3 | 11% | 9365 | 32.4 | 13.9 | 3.5 | 27.4 | 2.6 |
| overlay | 60 | 1 | 8% | 5781 | 15.4 | 27.4 | 1.1 | 19.4 | 1.0 |
| kinds | 147 | 4 | 27% | 8000 | 37.7 | 39.6 | 3.2 | 51.8 | 9.0 |

Hashing pixels is what costs: resolve time follows opaque area, about 1.7 ms
per 1% of the view at device pixel ratio 3. On screens with no opaque node,
recording, hashing and restoring cost 5 to 14 ms against an 18 to 23 ms pump.
The share of opaque nodes is at most 5.1% on any screen (the lists screen's 16
one-sided dividers). The rasterization is needed for the pixel oracle anyway;
in production capture it would only be needed when an opaque node exists.
These are per-node paint records; the Phase 1 snapshot format, its size and
the "under 20% of test time" budget are measured from Phase 1 on.

### Decision per node kind

64 render object kinds were painted. 56 are always recorded by value. The rest:

| Node kind | Decision | Why |
| --- | --- | --- |
| `TextureBox` | Pixel hash | A texture's pixels do not exist in a widget test |
| `PlatformViewRenderBox` | Pixel hash | Same, for platform views |
| `RenderShaderMask` | Pixel hash, over its mask rect | Its shader comes from a callback as a `ui.Gradient`, which keeps no readable fields |
| `RenderPhysicalShape` | Pixel hash | Draws and clips its shape as a path (A2) |
| `RenderClipPath` | Pixel hash | Clips with a path (A2) |
| `RenderClipOval` | Pixel hash | Clips with an oval path (A2) |
| `RenderDecoratedBox` | Recorded; pixel hash per node | Only when the decoration paints a path (a border on some sides only, a non-rectangular shape) or a gradient that cannot be read back |
| `RenderCustomPaint` | Recorded; pixel hash per node | Only when the painter draws a path, a gradient, a fragment shader, or `TextPainter` text |

A gradient in a decoration is recorded by value from the decoration that built
it, with the ambient text direction, and only when the decoration and its
border or shape are stock painting-library types, and only for the first
gradient the box paints.

### Phase 0 review

Sagar asked for a review of Phase 0 for wrong assumptions and critical bugs
before approving it. The review read the recorder against the Flutter 3.47.6
source and built pairs of trees meant to hash equal while rendering different
pixels. Ten were real capture gaps. Each is now a test in
[corpus/fixture_app/test/regression](../corpus/fixture_app/test/regression/review_gaps_test.dart),
which requires both a pixel change and a hash change.

| Case | Cause | Fix |
| --- | --- | --- |
| Opaque node draws outside its paint bounds | The pixel hash covered `paintBounds`, which a painter may exceed | Hash the node's tracked reach (A4 above) |
| Opaque backdrop filter, blur with bounds | Same: a backdrop changes pixels across its clip, not its child's bounds | Unbounded and undescribable effects reach the whole clip |
| Opaque backdrop filter, composed filter | Same | Same |
| Follower linked to a different leader | Only the follower's own offsets were recorded, not where its leader is | Record the follower's composed transform |
| Directional gradient under LTR and RTL | `AlignmentDirectional` was recorded without the text direction it resolves against | Record the box's text direction with the gradient |
| Second gradient in one box | Any gradient in a decorated box was described as the decoration's | Only stock decorations, only the first gradient; others are opaque |
| Mixed alignment | A mixed alignment printed with one decimal | Write it resolved under each text direction |
| Path notch between samples | A2 fails for paths | Spec fallback: pixel hash |
| Path zero-length contour | Same | Same |
| Device pixel ratio | Nothing recorded the device pixel ratio | Record the view's ratio and size at the root |

The review also added four guards for the new reach rules (a node far from the
origin, an image filter moving a node out of its inner clip, a colour-filtered
layer, a node under a backdrop blur). The image filter case is a gap if reach
does not account for the filter. The platform-view fixture was changed so its
texture no longer covers the header, whose changes were otherwise caught by
the texture's pixel hash rather than the header's own recording; the mutation
table now says, for each change, whether it was caught by value or only by a
pixel hash (3 of 58: shader mask, chart gradient, fragment uniform).

### Decisions from the first Phase 0 report

Sagar decided these on 2026-10-07, and the spec was updated to match.

1. **Renderer in the toolchain fingerprint: yes.** The widget tree differs
   between Skia and Impeller in widget tests, not only the pixels, so the
   toolchain field records the renderer and a run on the other renderer is
   routed to migration. Built in Phase 1 with the toolchain fingerprint.
2. **Material and Cupertino in 3.47: spec corrected.** They still ship inside
   the Flutter SDK in 3.47.6. The core imports only foundation, painting,
   rendering and widgets, so the design is unchanged.
3. **Shadows in tests: declared.** The coverage limits now state that
   `flutter_test` sets `debugDisableShadows`, so shadow blur is invisible to
   both the snapshot and the pixel oracle. Built in Phase 1 with the coverage
   report.

## Phase 1: capture

**Exit gate (spec):** 0 differing snapshots in 1,000 repeats per operating
system, and the schema maps to web with no missing required field.

**Result (2026-10-08): passes.** PR #2, branch `phase1-capture`.

- **Repeats.** The A3 workflow ran 1,000 repeats of each of the 15 catalogue
  scenes on four hosts: macOS arm64 (`macos-latest`), macOS Intel
  (`macos-15-intel`), Linux x64 (`ubuntu-latest`) and Linux ARM
  (`ubuntu-24.04-arm`). That is 15,000 captures per host, with 0 scenes
  showing more than one snapshot on any host.
- **Web mapping.** A14 holds ([a14_web_mapping.md](phase1/a14_web_mapping.md)).

Built: schema v1 draft ([schema_v1.md](schema_v1.md)), the capture pipeline,
the determinism gate, the toolchain fingerprint, the coverage report, the
mutation and no-op catalogs, and the mutation generator.

### A3: identical across Macs

**Fails.** Each host is stable on its own, but the hosts disagree with each
other:

- Every pair of hosts differs on 12 of the 15 scenes, Mac arm64 against Mac
  Intel included.
- The 3 scenes with no path-drawn node are identical on all four.
- On `settings/default` and `watchlist/scrolled`, the two x64 hosts agree with
  each other, and so do the two ARM hosts.

The differences are in the pixel hashes of nodes drawn as paths: Material
shapes, rows, buttons. Every other field matched.

- **Mac arm64 against Intel.** The A3 summary lists the differing nodes. Each
  one is a `paint` field on a node marked `opaque=path`: every `AppButton`,
  `LabeledField` and `WatchRow`, and the settings screen. The listing was cut
  off before the detail and states scenes, because annotations have a size
  limit.
- **Linux against macOS.** Comparing Linux-recorded baselines on macOS gave
  43 changed nodes, all opaque (40 path, 3 shader). Only their paint field
  changed. The likely cause
is that Skia's software rasterizer antialiases path edges differently by CPU
architecture and OS.

The fallback in the spec is taken: "Pin baselines to one CI image and record
it in the fingerprint". Sagar chose this on 2026-10-08:

- The toolchain fingerprint records the host (`macos_arm64`).
- Catalogue baselines are recorded on macOS CI by the `record-baselines`
  workflow.
- Other hosts run everything except the baseline comparisons, which are
  tagged `baseline`.
- A developer Mac with another CPU architecture reports "not compared"
  instead of a diff.

No measurement on developer Macs was needed: the CI hosts already disagree.

### A6: a recognisable tree

Two engineers are to review the sheet, which has not happened yet. The sheet
([a6_review.md](phase1/a6_review.md)) covers every catalog mutation and a
seeded sample of 50 generated mutations.

Data so far:
- Every catalog mutation that has one component to land on landed on it.
- In the 10,000 generated mutations, 99.5% changed a field of the owning
  component.
- The other 47 are a screen-owned padding or size that only moves the
  components below it. That is cascade grouping, which belongs to Phase 2.

### A13: conventional goldens made deterministic

**Holds** ([a13.md](phase1/a13.md)). The gate fails 4 of 15 conventional golden
tests and names a node and a cause for each:
- three image decode races, on `HeaderImage`;
- one running shimmer.

Re-run on 2026-10-08 after the review fixes, with the same result. Across
hosts, all 15 conventional goldens recorded on macOS fail on Linux, while the
3 snapshots with no path-drawn node are identical.

### A14: schema not Flutter-shaped

**Holds** ([a14_web_mapping.md](phase1/a14_web_mapping.md)). Every field has a
web source, and five Chromium captures parse as schema v1.

### Release gates measured in Phase 1

- **0 misses in 10,000 generated mutations: met.** 7,407 of the 10,000 changed
  pixels or semantics, and every one changed the snapshot
  ([generated.md](phase1/generated.md)). The first full run had a generator bug
  (size mutations were no-ops), so it was fixed and re-run.
- **0 missed mutations: met on the mutation catalog.** 17 edits, 0 missed
  ([catalogs.md](phase1/catalogs.md)).
- **0 fails on no-op refactors: Phase 2.** Verdicts need the diff engine. The
  no-op catalog's pixels and semantics were unchanged in all 6 entries; 4 of
  them change the snapshot, which Phase 2's diff must absorb.
- **0 differing snapshots in 1,000 repeats per OS: met** (above).

### Phase 1 review

An adversarial review on 2026-10-08 found 11 capture gaps. All are fixed, each
with a regression test in `test/capture_gaps_test.dart`:
- Semantics of text spans with a recognizer were lost. The same fix also
  records each scrollable's position and actions, which were missing.
- Images loading in decorations, and with `gaplessPlayback`, were captured as
  placeholders.
- A failed image with an error widget could never be captured.
- Reading order (sort keys) was not recorded.
- Hint overrides were recorded with a run-dependent id.
- Sibling ids could collide.
- Class names in strings, in comments and on non-widget classes became
  components.
- A clock read in a `State` class named no node.
- Fonts loaded outside `SnapshotFonts.load` were missing from the
  fingerprint.

The review also corrected two harness claims:
- The A3 summary now fails on a missing or short host.
- The A13 note wrongly credited history change 6 with covering the clock path.
