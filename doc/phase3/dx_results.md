# Phase 3 step 8: developer-experience results

Run on 2026-10-10 by Sagar, alone, on his Mac, following
[dx_protocol.md](dx_protocol.md) with the helper `run_dx.sh`, which checks
out each branch, runs its tests, times and records. Scored by Claude against
the answer key in `corpus/catalogue_app/tool/dx_items.dart`. No number here
is a gate.

## A first run that does not count

The first run was on Flutter 3.47.5. The baselines were recorded on 3.47.6,
so:
- the snapshot tests reported every scene as recorded with a different
  toolchain ("migration") and compared nothing;
- 3.47.5 also draws settings/default 32 px differently, so every golden item
  had an extra failure unrelated to its change.

None of its rows are used. The helper now refuses any Flutter other than
3.47.6. Sagar saw each change once in that run, as a failure that did not
show it; the golden items' failure images were on screen, so the golden times
below may be second sightings, which favours the golden arm.

## Measures 1 and 2: naming the cause

Run on Flutter 3.47.6, order as recorded.

| Engineer | Item | Arm | Seconds | Cause or decision as written | Right | Terminal only |
| --- | --- | --- | --- | --- | --- | --- |
| Sagar | 02 opacity | snapshot | 265 | two tests failed due to Opacity changes but what is "1 more field" | No: change and both scenes right, component not named | yes |
| Sagar | 04 text | golden | 154 | I cannot tell which widget failed | No | yes |
| Sagar | 05 locale | snapshot | 160 | The output is not well formatted. Making it difficult to read and understand | No | yes |
| Sagar | 10 removed | golden | 26 | No idea why these tests failed | No | yes |
| Sagar | 08 padding | snapshot | 264 | I can understand what was the reason the test failed but the ouput is not well formatted or laid out to easily read it | No: no cause written | yes |
| Sagar | 11 enabled | golden | 14 | not clear what caused the test failure | No | yes |
| Sagar | 09 selected | snapshot | 64 | I can understand what changed and reason for test failure but similar layout/formatting problem | No: no cause written | yes |
| Sagar | 12 insert | golden | 13 | No idea why these tests failed | No | yes |

Answer key for the items: 02 StatusView, Style, on states/empty and
states/error; 04 SettingsTile, Content; 05 Content on each relabelled
component; 08 SectionHeader, Layout; 09 SettingsTile, Style and Semantics; 10
SettingsTile, Removed; 11 AppButton, Style and Semantics; 12 SectionHeader,
Added on sign_in/empty.

- **Measure 1, median time to a named cause.** No cause was named as the
  protocol counts it (component and change) in either arm, so there is no
  median for either.
- **Measure 2, share named from the terminal alone.** 0 of 4 in each arm.
  Every item was answered from the terminal alone.

What the rows do show, as written and not scored:
- **Golden arm.** On all four items the answer is that the failure could not
  be explained, given after 13 to 154 seconds. The terminal names only the
  scene and the share of pixels that differ.
- **Snapshot arm.** On three of four items the answer says the change was
  understood (02 names the change and both scenes; 08 and 09 say the reason
  was understood but do not write it down). On all four the answer is about
  how hard the output is to read.

## Readability findings from the snapshot arm

Raised by Sagar during the sessions, from the terminal output:
1. **"(and N more fields)" reads as a hidden change.** It counts other
   fields that changed to the same value, such as `RenderOpacity.opacity`
   beside `Opacity.opacity` (`lib/src/diff/summary.dart`), so nothing else
   changed; but the wording suggests a further change the terminal does not
   show.
2. **The layout is hard to read.** Long values wrap with no indent, so a
   continuation reads as a new row; one item packs several fields onto one
   line; there is no summary before the list; Flutter's stack trace sits
   between one scene's report and the next.

These are not changed during the measurement, so every item was measured on
the same output.

## Measure 3: reviewing pull requests that change baselines

Not run yet.
