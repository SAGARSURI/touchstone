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
toolchain	flutter="3.47.6"	framework="5fc346839b"	engine="692136cb65"	dart="3.13.5"	renderer="skia"	library="0.0.1-dev.0"	fonts="FlutterTest"
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
| `inputs` | `viewport` (logical size and device pixel ratio), `platform`, `locale`, `textScale`, `brightness`, `theme` and `state` as declared by the test |
| `toolchain` | Flutter version, framework and engine revisions, Dart version, renderer (Skia or Impeller), library version, fonts (`FlutterTest`, or a hash of fonts loaded through `SnapshotFonts.load`) |
| `limit` lines | Declared coverage limits that applied to this capture (box font, shadows disabled, unbuilt list items, platform views and textures) |
| `opaque` lines | Each node whose paint is a pixel hash, with its reasons |
| `rootHash` | The root node's `sub` |
| `nodes` | The component tree |

## Node fields

| Field | Layer | Content |
| --- | --- | --- |
| id | Detection | `Type#key` for a `ValueKey` of a string, number, boolean or enum; otherwise `Type@n`, the n-th sibling component of that type. The full id joins segments from the root with `/` |
| `bounds` | Detection | `x,y,width,height` of the component's top render object in global logical pixels, exact doubles |
| `paint` | Detection | SHA-256 of the component's own paint text (below) |
| `sem` | Detection | The semantics nodes the component owns: rect, transform, label, value, hint, tooltip, role, flags, actions and every other non-default `SemanticsData` field, as canonical JSON |
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

`captureSnapshot` runs after the last pump: it fails if a frame is scheduled or
an `Image` has not decoded, enables semantics, records paint, repaints to undo
what recording touched, rasterizes the view only if a node is opaque, then
builds the component tree and hashes bottom-up.

`expectSnapshot` compares the root hash with the baseline (a different
toolchain is reported, not compared). With `--update-goldens` it writes the
baseline only after the determinism gate: 3 captures with every widget
rebuilt, relaid out and repainted in between must be byte-identical; otherwise
the first differing node and its likely cause are reported. Outside
`withFixedClock`, any read of `package:clock` time during the rebuild fails the
gate and names the reading frame.

## Open points before freezing v1

- A14: every required field must have a web equivalent.
- A6: whether class-declaration scanning picks the tree developers recognise,
  measured on the catalogue app.
- The style field's size and usefulness, measured in A10 and Phase 2.
