# Phase 3 step 7: A7, written before the run

Written on 2026-10-09 and committed before any device run. Plan step 7 in
[plan.md](plan.md). A7 in the spec's assumption table: "A change seen in the
widget-test environment is a change users see, and the reverse". Test: for a
sample of mutations, compare tool reports with device screenshots using real
fonts. Pass: with real fonts opted in, every device-visible mutation is
reported; with the default font, the only misses are wrapping, truncation and
overflow, and each is listed. Fail fallback: state the limit in the coverage
report and add a small nightly device run.

## Method

The plan's defaults: screenshots from an iOS simulator on the macOS CI
runner, through `integration_test`, with the catalogue's real fonts; the
mutations are the generated ones, applied at run time, so one build covers
the whole sample.

**Sample.** Seeds 0 to 299 of the Phase 2 mutation generator
(`test/generated/mutator.dart`): each seed picks a catalogue scene and one
render-level mutation. Seeds that apply no mutation are left out.

**Three runs of the same seeds**, each recording, per seed, the scene, the
mutation's description, and what changed:

| Run | Where | Fonts | Records |
| --- | --- | --- | --- |
| Tool, default font | `flutter test test/a7`, Linux and macOS | FlutterTest | Whether the snapshot changed, and the default policy's verdict |
| Tool, real fonts | the same, with `--dart-define=A7_FONTS=real` | Roboto and Material Icons loaded with `SnapshotFonts.load`, from the files the SDK ships | The same |
| Device | `integration_test/a7_device_test.dart` on an iOS simulator | Roboto and Material Icons bundled in the app | Whether the view's pixels changed, and whether the semantics tree changed |

"Real fonts" are the fonts the app draws with. The catalogue's theme uses
Material's Android typography (Roboto), as the widget tests do, so the device
run sets the target platform to Android, and the app bundles Roboto so the
device draws with it rather than a system fallback. Both sides use the same
font files, the ones in the Flutter SDK's `material_fonts` cache.

**Device pixels.** The device run rasterizes the app's own layer tree on the
simulator, before and after the mutation, with the same viewport as the
widget tests (390 x 844 at 3x). That is what the device's renderer (Impeller)
draws for the app. A screen capture would add the simulator's status bar,
whose clock changes between the two captures. Each scene is rasterized twice
before the mutation; a scene whose two rasters differ is noisy on the device
and is reported, not scored.

**Matching.** A seed is scored only when the three runs name the same scene
and the same mutation. Different fonts can change layout, so a mutation
chosen from the render tree could differ; mismatches are counted and listed.

**Scoring.** A mutation is device-visible when the device's pixels or
semantics changed. A miss is a device-visible mutation whose snapshot did not
change, or whose verdict was pass.

## Expected results

1. **Real fonts: 0 misses.** Every generated mutation changes a render
   object's paint, layout or semantics, and those are captured with any font.
2. **Default font: 0 misses.** The generator does not lengthen text: a text
   mutation replaces one character, and font weight and size changes are
   recorded in the paint whichever font draws them. So no mutation is
   expected to change wrapping, truncation or overflow on the device without
   changing the snapshot. Any miss is listed with whether it is one of those
   three.
3. **The reverse: tool reports a change the device does not show.** Expected
   for a few mutations: colour shifts of 1 to 8 in one channel on content
   that the device draws with a different antialiasing or blend, and changes
   under an opaque overlay. Counted and listed; the spec's pass rule does not
   gate it.
4. **Matching:** at least 95% of applied seeds match across the three runs.
5. **Noise:** no scene is noisy on the device.

A7 holds if expectations 1 and 2 hold, with any default-font miss being
wrapping, truncation or overflow and listed.
