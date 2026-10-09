# A14: schema v1 on the web

Assumption A14: "The schema is not Flutter-shaped". Experiment: map it onto
DOM, computed style and the accessibility tree, and prototype 5 fixture
screens on web before freezing schema v1. Pass criterion: no required field
lacks a web equivalent.

**Result (7 Oct 2026): passes.** Every field has a web source, five fixture
screens were captured from Chromium into schema v1 text, and
`Snapshot.parse` in package:touchstone reads all five with every hash
recomputing ([web_schema_test.dart](../../test/web_schema_test.dart)).

## Field mapping

| Field | Flutter source | Web source used by the prototype |
| --- | --- | --- |
| schema version, `id` | Same | Same |
| `inputs.viewport` | View size and device pixel ratio | `innerWidth` x `innerHeight` @ `devicePixelRatio` |
| `inputs.platform` | `defaultTargetPlatform` | `navigator.platform` |
| `inputs.locale` | Platform dispatcher locale | `<html lang>`, else `navigator.language` |
| `inputs.textScale` | Text scale factor | The browser's `medium` font size over 16 px |
| `inputs.brightness` | Platform brightness | `prefers-color-scheme` |
| `inputs.theme`, `inputs.state` | Declared by the test | Declared by the test |
| `toolchain` | Flutter, framework, engine, Dart, renderer, library, fonts | Browser and version, engine (Blink), renderer, library, fonts (platform fonts used for every text node, from CDP `CSS.getPlatformFontsForNode`) |
| `limit` | Declared coverage limits | Declared coverage limits (script-drawn canvas, cross-origin frames) |
| `opaque` | Node kinds whose paint is a pixel hash | `<canvas>`, and in a full adapter video, WebGL and cross-origin frames |
| node `id` | `Type#key` or `Type@n` among component siblings | The same rule over elements marked as components (`data-component`, `data-key`) |
| `bounds` | Top render object's global rect | `getBoundingClientRect()` of the component's element |
| `paint` | The component's own paint commands | The component's own boxes and text runs in document order: each owned element's tag, rect relative to the component, paint-relevant computed style (colour, background, border, radius, shadow, transform, filter, clip, mask, opacity, font, z-index and others), pseudo-elements, image sources, text content with its line rects; child components leave a marker |
| `semantics` | `SemanticsData` of the nodes the component owns | Accessibility tree from CDP `Accessibility.getFullAXTree`: role, name, value, description and every property (level, modal, focusable, checked and so on), grouped by the component that owns the DOM node |
| `type` | Widget class and declaring library | Component name and the module that declares it |
| `style` | Diagnostics properties, with token names | Non-default computed style of the component's element; token names from CSS custom properties are a natural fit for the resolver |
| `subtreeHash`, `rootHash` | SHA-256 over detection fields and children | Identical rule, so the same parser verifies both |

## Prototype

[corpus/web_prototype](../../corpus/web_prototype) rebuilds five fixture
screens in HTML (text, decorated, effects, lists, overlay) and
[capture.mjs](../../corpus/web_prototype/capture.mjs) captures them with
Playwright's Chromium at 390 x 844 @3x.

| Screen | Nodes | Two captures identical | Missing fields | Mutations: pixels changed, snapshot changed, on the expected node |
| --- | --- | --- | --- | --- |
| text | 5 | yes | 0 | 3 of 3 |
| decorated | 6 | yes | 0 | 3 of 3 |
| effects | 11 | yes | 0 | 4 of 4 (opacity, clip radius, paint order, canvas output) |
| lists | 33 | yes | 0 | 2 of 2 |
| overlay | 5 | yes | 0 | 3 of 3 (scrim opacity, sheet height, dialog label) |

## Differences that do not block the schema

- What a component is. Flutter scans the app's own library for widget
  classes; the prototype uses a `data-component` attribute. A real web
  adapter would take components from the framework (React or Vue component
  instances, custom elements). The id rule itself carries over unchanged.
- Paint is described, not recorded. Browsers expose no paint command
  stream, so the web paint text is computed style plus geometry. A visual
  input outside that list would be a capture gap, which is why the web
  adapter needs its own shadow pixel audit (it starts with its own register,
  as the spec says).
- Off-screen content. A Flutter lazy list does not build rows outside the
  viewport, so they are absent and declared as a limit. The web keeps them
  in the DOM, so the lists screen has all 30 rows.
- Fonts. The web fingerprint names the platform fonts actually used, which
  is stronger than Flutter's (a hash of fonts loaded by the test).

These are adapter design points for after Phase 4. None needs a field the
schema lacks, so schema v1 is not labelled Flutter-only.
