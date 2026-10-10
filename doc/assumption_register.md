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
| A4 | Equal hashes imply equal pixels | Holds on real code: 0 capture gaps over the catalogue history, 9 changes × 41 snapshots ([phase3/history.md](phase3/history.md)); 0 on fixtures and the 14 review cases | 2026-10-09 |
| A5 | Node identity survives refactors | Fails as first built (3 of 6 refactors needs-review). Fallback amended (flattened matching, Sagar 2026-10-09): 6 of 6 pass, each with no change or identity changes only; 0 mutations absorbed | 2026-10-09 |
| A6 | Keeping only app-owned widgets gives a recognisable tree | Review sheet rebuilt from Phase 2 change reports; two engineers reviewing, Unsure answers remain | 2026-10-09 |
| A7 | A change in the widget-test environment is a change users see | Holds on an iOS simulator sample: of 197 device-visible generated mutations, 0 missed with real fonts loaded; with the default test font, 3 missed, all rows pushed out of view by the test font's wrapping, and listed ([phase3/a7.md](phase3/a7.md)). Real fonts are needed for this to hold | 2026-10-09 |
| A8 | Cascade grouping names the true root cause | Holds. Generated: 748 single causes, 0 wrong. Catalog: 19 of 19 with the corrected expectations Sagar accepted (17 of 19 and 1 wrong certain as first written) | 2026-10-09 |
| A9 | Affected-test selection never skips a changed test | Not yet tested (Phase 4) | |
| A10 | Capture and diff are cheap enough for every pull request | Capture adds 16% on Linux x64 (budget 20%) after the fix; a hash-equal comparison with reading the baseline takes at most 0.48 ms on 39 of 41 snapshots and 0.78 to 1.05 ms on the two largest ([phase3/a10.md](phase3/a10.md)). macOS not measured | 2026-10-09 |
| A11 | Pairwise variants catch what the full matrix catches | Not yet tested (Phase 4) | |
| A12 | A Flutter upgrade can be absorbed without re-reviewing every baseline | Holds for 3.47.6 to 3.47.7 (a patch release): all 41 catalogue snapshots pixel-identical on macOS arm64 and Linux x64, re-baselined automatically with a pixel proof, and review passes all ([phase3/a12.md](phase3/a12.md)). Runs again on the next minor release | 2026-10-09 |
| A13 | Existing golden tests can be made deterministic | Holds: the gate fails 4 of 15 conventional goldens and names a node and a cause for each | 2026-10-08 |
| A14 | The schema is not Flutter-shaped | Holds: every field has a web source, including `flat` (added for A5); 5 web captures parse as schema v1 | 2026-10-09 |

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

Two engineers review the sheet. The Phase 1 sheet
([a6_review.md](phase1/a6_review.md)) covers every catalog mutation and a
seeded sample of 50 generated mutations.

Data so far:
- Every catalog mutation that has one component to land on landed on it.
- In the 10,000 generated mutations, 99.5% changed a field of the owning
  component.
- The other 47 are a screen-owned padding or size that only moves the
  components below it. That is cascade grouping, which belongs to Phase 2.

Phase 2 (2026-10-09): the sheet is rebuilt from the change reports
([a6_review.md](phase2/a6_review.md)) and the review is in progress in the
Claude Doc "A6 attribution review". Two causes of Unsure answers were fixed:
verbose reports (now shortened, see diff.md "Report wording") and a row
reported as changed when only another row was edited (seed 945, capture
change 5). Not yet met: Unsure answers remain.

**One reviewer (Sagar, 2026-10-10 01:21Z, "Review alone").** The spec's
experiment has two engineers review the attribution of every mutation; the
second engineer is no longer on the project, so Sagar finishes the sheet
alone. This is a deviation from the spec, and A6's result is one engineer's
judgement.

Sagar's review (2026-10-10): 64 of 67 rows Yes, and all 67 name the right
component. Rows 3, 4 and 6 are Unsure on how readable the report is. The
changes for them are in [a6_followup.md](phase3/a6_followup.md):
- proven ink;
- semantics nodes matched before comparing;
- proven paint consequences counted;
- copies of one change counted as one cause (Sagar, 2026-10-10).

The gates still hold with these changes. Rows 2 to 7 of the sheet were
regenerated for his second look. Not yet met: rows 3, 4 and 6 await that
look.

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

## Phase 2: diff and policy

**Exit gate (spec):** every mutation and no-op gate in Verification strategy.

**Result (2026-10-09), as written: not met. With three disputed expectations
corrected: met.** The results are in PR #3 on branch `phase2-diff`, with
details in [results.md](phase2/results.md).

**Review decision (Sagar, 2026-10-09 03:38Z): the three corrections are
accepted, and the gate is recorded as met.** The original expectations stay
unedited in [expectations.md](phase2/expectations.md); the numbers as first
written stay in the table below. Sagar also chose to amend the spec's A5
fallback and build flattened matching in this phase. Every gate was rerun
with it on 2026-10-09, with the same results, and A5 now holds (see A5
below).

| Gate | Target | As written | Corrections accepted |
| --- | --- | --- | --- |
| Missed changes (catalog; 10,000 generated, at verdict level) | 0 | 0; 0 | 0; 0 |
| Fail verdicts on no-op refactors | 0 | 0 of 6 | 0 of 6 (6 of 6 pass with the A5 amendment) |
| Correct component and change type | ≥99% | 30 of 32 | 32 of 32 |
| Correct root cause on cascade mutations | ≥95% | 17 of 19 | 19 of 19 |
| Wrong root causes stated as certain | 0 | 1 (catalog); 0 of 748 (generated) | 0; 0 |

The three disputed entries are `custom-painter`, `padding-1px` and
`stack-resize-first`. For each one, the report looks right and the written
expectation wrong. `results.md` shows why, and the expectations are left as
written.

Built:
- the diff engine, with the second matching pass and cascade grouping;
- the policy engine and its rules;
- the change report as the `expectSnapshot` failure message;
- dynamic components;
- the review and update commands.

The design and every interpretation of the spec are in
[diff.md](phase2/diff.md).

### A5: identity survives refactors

**First built: fails for 3 of 6.** Adding const, converting to stateful and
wrapping in a layout-neutral widget gave no change. Extracting a widget,
inlining a widget and renaming a class gave needs-review. The spec's
fallback, the second matching pass on type, bounds and paint, could not pair
them: extract and inline move paint across component boundaries, and a
rename changes the type.

**Fallback amended (Sagar, 2026-10-09 03:38Z, "Build it now"): holds for 6
of 6.** The spec's A5 fallback, its diff step and its node fields now
include flattened matching. Each node records `flat`, its subtree's output
with component boundaries removed. Unpaired nodes are then paired on bounds
and `flat`. A component added, removed or renamed inside a component whose
bounds and `flat` are unchanged makes that subtree one info-level Identity
change.

- Expectations were committed before the code
  ([a5_expectations.md](phase2/a5_expectations.md)), and all were met.
- Extract: 12 Identity lines. Inline: 7. Rename: 12. One per instance of the
  edited widget, each a pass.
- The 32 mutation and cascade entries are unchanged, and none became
  Identity. 10,000 generated mutations: 0 missed, 0 reported as Identity.
- Five adversarial tests (`test/refactor_test.dart`) each change the output
  under a refactor-shaped edit, and each gets needs-review.
- `flat` is a detection field, so catalogue baselines were re-recorded on
  macOS (8a8bf61), and the web prototype writes it too (A14 still holds).

### A8: cascade grouping

**Holds on generated mutations.** Across 1,000 shift groups, 748 named a
single cause, every one correct. The other 252 say "cause unknown" instead of
guessing.

On the catalog, 17 of 19 entries are correct as written, with 1 wrong certain
cause. Both misses are disputed expectations (see results.md).


## Phase 3: catalogue verification, then release

**Exit gate (spec):** 0 capture gaps on catalogue history. The release
decision is recorded together with the gate results. Budgets met or
renegotiated. Unexplained rate reported.

**Result (2026-10-09): the gate's measurements are met; the release decision
is pending.** Branch `phase3-catalogue`, PR #4. The plan and every step's
expectations are in [phase3/](phase3/plan.md).

### Every gate, as measured in Phase 3

The gates Sagar confirmed on 2026-10-07, on the grown catalogue (41
snapshots, levels 1 to 5):

| Gate | Target | Result | Met | Source |
| --- | --- | --- | --- | --- |
| Missed mutations, catalog | 0 | 0 of 32 entries | yes | [gates.md](phase3/gates.md) |
| Capture gaps on catalogue history | 0 | 0 over 9 × 41 snapshot pairs, both runs | yes | [history.md](phase3/history.md) |
| Fail verdicts on no-op refactors | 0 | 0 of 6; all 6 pass | yes | gates.md |
| Differing snapshots in 1,000 repeats per OS | 0 | 0 on macOS arm64, macOS Intel, Linux x64 and Linux arm64 | yes | gates.md |
| Correct component and change type | ≥99% | 32 of 32 with the corrections accepted in Phase 2 (30 of 32 as written) | yes | gates.md |
| Correct root cause on cascades | ≥95% | 19 of 19 with the accepted corrections (17 of 19 as written) | yes | gates.md |
| Wrong root causes stated as certain | 0 | 0 of 60 on history run 2 (1 of 53 on run 1); 0 of 863 generated single causes | yes | history.md, gates.md |
| Unexplained rate | under 5% | 3.8% (16 of 417) on history run 2; 7.5% on run 1 | yes | history.md |
| Capture overhead | under 20% | +16% on Linux x64 after the A10 fix (+48% as first measured); macOS not measured | yes, on Linux | [a10.md](phase3/a10.md) |
| Hash-equal comparison, with reading the baseline (Sagar, 2026-10-10) | under 1 ms per snapshot | 39 of 41 at most 0.48 ms; the two watchlist baselines 0.78 to 1.05 ms over two runs (2.4 to 3.4 ms before the parse was reworked) | at the budget on 2 of 41 | a10.md |
| Misses in 10,000 generated mutations | 0 | 0, at verdict level and at snapshot level | yes | gates.md |

Assumptions tested in Phase 3:
- **A4 on real code: holds.** 0 capture gaps on the history.
- **A7: holds with real fonts.** 0 of 197 device-visible mutations missed on
  an iOS simulator; 3 missed with the default test font, all wrapping
  ([a7.md](phase3/a7.md)).
- **A10: budgets met on Linux**, with the parse question below.
- **A12: holds for 3.47.6 to 3.47.7**, a patch release; runs again on the
  next minor release ([a12.md](phase3/a12.md)).

### Release decision

**Pending: not yet (Sagar, 2026-10-10).** Publishing to pub.dev waits for Sagar's explicit go. The spec
publishes "once the team is confident in the results"; these are open before
that call:

1. **Developer experience (step 8).** The protocol is written
   ([dx_protocol.md](phase3/dx_protocol.md)); Sagar runs the sessions
   alone (2026-10-10), and no number exists yet. The spec sets no gate on
   these numbers.
2. **A6.** Sagar reviews alone (his decision, one reviewer instead of the
   spec's two). 64 of 67 rows are Yes. Rows 3, 4 and 6 were regenerated
   after the report changes in [a6_followup.md](phase3/a6_followup.md) and
   await his second look.
3. **Schema changes inside v1: decided.** `shape`, the `flat` semantics
   change and the 128-bit pixel digest stay in v1 (Sagar, 2026-10-10).
   Nothing was published with the earlier forms; v1 is frozen as it stands
   at release.
4. **The comparison budget with the parse.** Sagar (2026-10-10): the
   budget includes reading the baseline. After the parse was reworked, 39
   of 41 snapshots take at most 0.48 ms; the two watchlist baselines sit at
   the budget, 0.78 to 1.05 ms over two runs on the Linux container.
5. **Capture overhead on macOS**, where baselines are checked, is not
   measured; +16% is from the Linux container, with a small margin.
6. **Regression set, not fixed:** `SettingsScreen@0`'s pixel hash changing
   when only its children move (detection still changes; since
   a6_followup.md the report proves it follows the moved tiles); a refactor in a tile cut off at the viewport
   edge; theme colours derived from a token carrying no token; style
   recording closure names with library numbers (seen in A12, and again
   on one toolchain when the DX goldens were recorded: three order
   snapshots' tooltip style went from `@657220820` to `@659220820`; style
   is not hashed, so no verdict changed).
