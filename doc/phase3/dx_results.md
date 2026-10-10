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

After the sessions Sagar chose to fix the layout before measure 3 (405bd62,
5d9563c, 4492942), and looked at before and after reports of the same session
changes:
- each distinct change is on its own line, and other fields recording the
  same change are left out rather than counted;
- a line longer than 100 columns breaks before its arrow, then between
  words, so Flutter's own wrapping never applies;
- a count of items by type sits under the verdict, and a blank line
  separates items.

What is detected and how changes are attributed is unchanged: the joined
wording each change carries is the same, and the scoring tools read the
structured report, not this text.

## Measure 3: reviewing pull requests that change baselines

Run by Sagar on 2026-10-10, between about 13:00 and 13:16 UTC, with `run_dx.sh reviews`
(times from opening each pull request to the decision typed in the
terminal). What each description showed:
- #5 (item 01): the review output with the overview first (e0f8160), 22
  lines, then each snapshot's report folded under a `<details>` (499 lines).
- #8 (item 07): each snapshot's report in the new layout (4492942), with no
  overview: rewriting its description was blocked on the tooling side.
- #6 and #7 (items 03, 06): re-recorded golden PNGs.

| Engineer | Item | Arm | Seconds | Cause or decision as written | Right |
| --- | --- | --- | --- | --- | --- |
| Sagar | 01 | snapshot | 189 | too much to review | No: no decision (intended, approve) |
| Sagar | 03 | golden | 47 | approve | Yes |
| Sagar | 07 | snapshot | 59 | Difficult to review the changes | Not counted (not blind); padding not named |
| Sagar | 06 | golden | 26 | approve | Yes |

Measure 3, counted items only:
- Golden arm: median 36.5 s, 2 of 2 decisions right.
- Snapshot arm: 189 s for one item, 0 of 1 right; no decision was reached.

Both golden items are intended changes, so approving is right whether or
not the change was understood; in the sessions the golden arm named no
cause on any item. The snapshot arm's result is about volume: Sagar found
the 22-line overview itself "too much to review", and #8 "even this is
difficult".

During the run, after seeing #5, Sagar chose "Five lines" (13:12 UTC): the
review now opens with a summary of at most five lines of at most 100
characters (doc/phase3/review_summary_expectations.md). Items 01 and 07 are no longer
blind, so the summary cannot be measured on them.

Item 07 (#8) is not a blind review: a sample of terminal colour sent to
Sagar on 2026-10-10 showed #8's first scenes, including the undeclared
SectionHeader padding change it is meant to catch. Its time and decision are
recorded but not counted; the other three items are unaffected.
