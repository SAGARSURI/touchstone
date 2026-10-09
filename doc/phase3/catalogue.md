# Phase 3: catalogue levels 4 and 5

Step 1 of the [plan](plan.md). The spec's catalogue (Catalogue scenarios,
"Screens") has 13 screens in five levels. Levels 1 to 3 were built in
Phase 1. This step adds levels 4 and 5.

| Level | Screen | Snapshots | What it exercises |
| --- | --- | --- | --- |
| 4 | Overlays: a dialog, a bottom sheet, a snackbar and a dropdown menu over a position screen | `overlays/dialog`, `overlays/sheet`, `overlays/snackbar`, `overlays/dropdown` | Layers, scrim opacity, paint order |
| 4 | Theme and locale matrix over the settings screen and the sign-in form | `matrix/<screen>_<variant>` for dark, rtl, text_2x, small (320 x 568) and large (1024 x 1366) | Variants, overflow |
| 5 | Chart: a line series with a gradient fill and a candlestick series, both drawn by a `CustomPainter`, and a tooltip | `chart/default`, `chart/tooltip` | Path fingerprints, shaders, the pixel-hash fallback |
| 5 | Live prices that tick every second and flash on change | `live/initial`, `live/ticked`, `live/flashing` (at a pumped time) | Dynamic content (`LivePrice`), timers, a fixed clock |
| 5 | Map placeholder (a platform view) under a blurred header, with pins and a card | `map/default` | Platform views, backdrop filters, the coverage report |
| 5 | Order flow in four steps with page transitions and a reorderable list | `order/symbol`, `order/amount`, `order/review`, `order/done`, `order/transition` (at a pumped time), `order/dragging` (a drag held) | Captures at pumped times, drag state, state across screens |

Choices the spec leaves open:

- **Right-to-left** uses the app's own locales, English and Arabic, through
  `flutter_localizations`. The screens' text stays English; the layout
  direction and the framework's strings follow the locale. Levels 1 to 3
  keep their original host, so their snapshots are unchanged.
- **The variants are set on the platform** (locale, text scale, viewport) and
  are therefore recorded in the snapshot's inputs, as an app's would be.
- **The chart's data is a fixed list** of 30 days in the source, so a single
  data point can be edited (scripted change 8).
- **A13 stays on levels 1 to 3**, the scenes it was measured on.

## What the new scenes found

All 29 new scenes pass the determinism gate. The repeat gate (A3) failed on
three order-flow scenes: the back button's tooltip links its semantics node
to an overlay portal through `traversalParentIdentifier`, and the capture
wrote that identifier's text, which holds a run-dependent hash. A traversal
link is now written as `link <n>`, numbered in the order met. A regression
test is in `test/capture_gaps_test.dart`. No committed baseline held a
traversal link, so none changed.
