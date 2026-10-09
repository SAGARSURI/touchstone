# Snapshot schema v1 (draft)

This is the Phase 1 draft of the snapshot schema in the tech spec ("Snapshot
schema"). It is frozen only after A14 maps it onto the web. Code:
[snapshot.dart](../lib/src/snapshot/snapshot.dart),
[capture.dart](../lib/src/snapshot/capture.dart).

## File

One UTF-8 file per snapshot, `snapshots/<id>.snapshot` beside the test. A
header, then one node per line. Fields on a line are separated by tabs; free
text is JSON-encoded; doubles are written in shortest round-trip form with no
rounding; the tree is given by two-space indentation.

```
touchstone-snapshot 1
id	"order_ticket/idle"
inputs	viewport="390.0x844.0@3.0"	platform="android"	locale="en-US"	textScale="1.0"	brightness="light"	theme="light"	state="idle"
toolchain	flutter="3.47.6"	framework="5fc346839b"	engine="692136cb65"	dart="3.13.5"	renderer="skia"	host="macos_arm64"	library="0.0.1-dev.0"	fonts="FlutterTest"
limit	"shadows: flutter_test sets debugDisableShadows, so shadow blur is not drawn"
opaque	"root/OrderTicket@0/SparklineChart@0"	path
rootHash	9f2c…
nodes
"root"	bounds=0.0,0.0,390.0,844.0	paint=…	sem=[…]	opaque=-	type="root"	style={…}	sub=9f2c…
  "OrderTicket@0"	bounds=0.0,0.0,390.0,844.0	paint=…	sem=[]	opaque=-	type="OrderTicket (package:app/order_ticket.dart)"	style={…}	sub=…
    "PriceLabel#price"	bounds=16.0,24.0,120.0,28.0	paint=41aa…	sem=[{"rect":…,"label":"Price"}]	opaque=-	type=…	style=…	sub=77b0…
```

## Snapshot fields

| Field | Content |
| --- | --- |
| schema version | `touchstone-snapshot 1`; raised on any change to the canonical form |
| `id` | Test name plus state and variant |
| `inputs` | `viewport` (logical size and device pixel ratio), `platform`, `locale`, `textScale`, `brightness`, `theme` and `state` as declared by the test; `frameTime` (the frame's time stamp in the test's fake clock) when captured at a pumped time |
| `toolchain` | Flutter version, framework and engine revisions, Dart version, renderer (Skia or Impeller), host OS and CPU architecture (`macos_arm64`; path edges rasterize differently per host, so opaque nodes' pixel hashes differ), library version, fonts (`FlutterTest`, or a hash of fonts loaded through `SnapshotFonts.load`) |
| `limit` lines | Declared coverage limits that applied to this capture (box font and unloaded icon fonts, shadows disabled, unbuilt list items, platform views and textures) |
| `opaque` lines | Each node whose paint is a pixel hash, with its reasons |
| `rootHash` | The root node's `sub` |
| `nodes` | The component tree |

## Node fields

| Field | Layer | Content |
| --- | --- | --- |
| id | Detection | `Type#key` for a `ValueKey` of a string, number, boolean or enum, with `%`, `/`, `#` and `@` in the key percent-encoded; otherwise `Type@n`, the n-th sibling component of that type. Siblings whose segments are still equal (keys `'7'` and `7`) get `@1`, `@2` in order. The full id joins segments from the root with `/` |
| `bounds` | Detection | `x,y,width,height` of the component's top render object in global logical pixels, exact doubles |
| `paint` | Detection | SHA-256 of the component's own paint text (below) |
| `sem` | Detection | The semantics nodes the component owns: rect, transform, label, value, hint, tooltip, role, flags, actions and every other non-default `SemanticsData` field, as canonical JSON. A node belongs to the nearest component containing every render object that gave it content, not to the framework boundary that formed it (a list item's `IndexedSemantics`, for example). Nodes no render object owns (one per text span with a recognizer) go with the node that built them. Sort keys and traversal links are recorded, so reading order follows from the node. A custom action is recorded by its label, or `hint <action>: <hint>` for a hint override |
| `opaque` | Detection | Why paint is a pixel hash (`path`, `platformView`, …), `-` if none |
| `type` | Explanation | Widget class and the library that declares it |
| `style` | Explanation | Diagnostics properties of the render objects that drew the component's paint, with a token name when the project's resolver returns one |
| `sub` | Detection | SHA-256 over the detection fields and the children's `sub`, in order |

Explanation fields are written to the file, so they must be deterministic, but
they never enter a hash.

## Which widgets are components

A widget is a component when its class is declared in the app's own packages
(found by scanning `lib/` of each package root; by default the package under
test), or its type is in the test's include list. Flutter keeps no run-time
record of the library that declares a class, so the scan is the source of
truth; where a widget was created is not used, because a framework `Text`
created in app code is not a component. A synthetic `root` node owns
everything above the first component.

A component is kept only if any of its render objects was painted or it owns a
semantics node; offstage content (an `Offstage`, a route kept alive behind
another) is left out, and ordinals count only the components kept.

## Paint text

Phase 0 records each render object's own paint. A component's paint text is
the paint of every render object whose nearest component is this one, nested
in paint order:

- A framework render object's commands go to the nearest component above it.
  Its children inside the same component are written in place with their
  offset.
- A child component leaves `comp("<segment>")` in paint order. Its position is
  its `bounds`, so moving it changes the child's bounds, not the parent's
  paint.
- Paint a component reaches through another place in the render tree (an
  overlay entry) is written in the other component as `foreign("<full id>")`
  and starts an entry in its own component with its global transform.
- Where a render object's transform could not be verified against
  `getTransformTo`, offsets and transforms are written explicitly instead of
  relying on bounds.

An opaque render object's paint ends with the pixel hash of its reach (see the
Phase 0 register), so an opaque component's `paint` changes whenever its pixels
do.

## Capture

`captureSnapshot` runs after the last pump: it fails if a frame is scheduled,
if an image shown by an `Image`, an `Ink` or a decorated box is still loading
(checked against the image cache, so a gapless image waiting for its next
frame fails and a load that failed with an error widget does not), or if text
uses a font family that renders with a font not loaded through
`SnapshotFonts.load`, which the fingerprint could not record. It then enables
semantics, records paint, repaints to undo
what recording touched, rasterizes the view only if a node is opaque, then
builds the component tree and hashes bottom-up.

Content that never settles (a shimmer) is captured with
`SnapshotOptions(atPumpedTime: true)` after the test pumps an explicit time;
the capture's own pumps do not advance the clock, and `frameTime` records the
frame.

A failed capture names the node it was traced to. For a scheduled frame, the
tool captures at the current time, pumps 100 ms, captures again and reports
the first node that changed. For an image still loading, it names the
component that shows the image.

`expectSnapshot` compares the root hash with the baseline (a different
toolchain is reported, not compared). With `--update-goldens` it writes the
baseline only after the determinism gate: 3 captures with every widget
rebuilt, relaid out and repainted in between must be byte-identical; otherwise
the first differing node and its likely cause are reported. Outside
`withFixedClock`, any read of `package:clock` time during the rebuild fails the
gate and names the component whose code read it, in its widget class or its
`State` class.

The gate rebuilds but does not mount the tree again, so a value fixed when a
widget is first mounted (an unseeded `Random` in a `State` field) passes it.
The spec's control for random values is seeding through the test helper; a
baseline captured from such a value differs on the next run, so the
comparison against the baseline and the A3 repeats, which mount every scene
afresh, catch it. Images drawn by a custom painter are not checked for
loading.

## Open points before freezing v1

- A14 passed: every field has a web equivalent and five web captures parse as
  v1 ([phase1/a14_web_mapping.md](phase1/a14_web_mapping.md)).
- A6: whether class-declaration scanning picks the tree developers recognise,
  pending two engineers' review of the catalogue mutations.
- The style field's size and usefulness, measured in A10 and Phase 2.
- Paint structure under pixel-neutral refactors: wrapping a child in a
  `RepaintBoundary` changes the parent's paint text (a composite and a new
  coordinate origin) though no pixel changes. Phase 2's no-op gate decides
  whether the diff handles this or the paint text elides pass-through render
  objects.
- The `host` toolchain field (Sagar chose it on 2026-10-08): opaque nodes'
  pixel hashes differ between Linux x64 and macOS arm64, so a baseline is
  compared only on the host that recorded it. Baselines are recorded on macOS by the
  `record-baselines` workflow. A3's Intel Mac and ARM Linux runs show whether
  the OS or the CPU architecture is the cause.
