# Phase 3: catalogue history, first run

Run on 2026-10-09 on Linux, Flutter 3.47.6, with `tool/run_history.dart` at
012b259. The rules are in [history_expectations.md](history_expectations.md),
and the raw output is in [history_run1/](history_run1/): `results.json`, plus
one report per change.

Changes 1 to 9 ran in order. Changes 6 and 9 were undone afterwards. Change 10
runs in plan step 6. Every scene was captured before and after each change,
with its pixel and semantics oracle.

**Correction to the frozen texts.** The catalogue has 41 snapshots: 15 in
levels 1 to 3 and 26 in levels 4 and 5. The comment in `history_phase3.dart`
and the run rules say 29 and 44. Those are miscounts written before the run,
and they stay as written.

## Scores

| Item | Result | Gate |
|---|---|---|
| Capture gaps (pixels or semantics changed, root hash equal) | **0** over 9 × 41 pairs | 0: met |
| Unexplained rate, changes 1 to 9 | **7.5%** (36 of 477 items) | under 5%: **not met** |
| Wrong root causes stated as certain | **1** of 53 single-cause groups | 0: **not met** |
| Untouched snapshots identical | Met. The root hash only changed where pixels or semantics changed, except in change 2, whose identity-only changes were expected | |
| Expected results, sentence by sentence | Change by change below | |

### Unexplained items by change

| Change | Unexplained | Where |
|---|---|---|
| 1 | 5 | `_Spinner` ×2, `PriceChart@0` ×2, `MapSurface@0` |
| 3 | 1 | `WatchRow#JUN0` |
| 7 | 10 | `SignInScreen@0` ×9 (its own paint), `MapSurface@0` |
| 8 | 4 | `PriceChart@0` and `@1` in both chart scenes, as expected |
| 9 | 16 | Screen-level paint: `SettingsScreen@0` ×6, `OverlaysScreen@0` ×4, `ChartScreen@0` ×2, plus `PriceChart@0`, `AppButton@0`, `ConfirmOrderDialog@0` and the root |

## Each change against its expected result

**1. Colour token: partly met.**
- Met: there are style changes on the affected components in 31 snapshots, and nothing was added, removed or moved.
- Not met: the changes are not grouped under one cause, brand.accent.
  - Within a snapshot, identical changes are merged ("SettingsIcon in 6 places"), but nothing groups them across snapshots.
  - The token name itself is dropped. When both sides resolve to the same token, `summary.dart` writes only the hex values.
- Unexpected: an unexplained paint change on `MapSurface@0`.

**2. Extract and rename: met.**
- All three snapshots pass, with identity changes listed as info.
- Pixels and semantics are unchanged.
- `order/symbol` was also affected, because it reuses WatchRow.

**3. Promo banner: partly met.**
- Met: PromoBanner is reported as added.
- Not met, `watchlist/top`: the shift lists two possible causes instead of being folded under PromoBanner. The second candidate is `Layout WatchlistScreen@0`, and its only changed field is the sliver list's internal `KeepAlive.keepAlive.11`.
- Not met, `watchlist/top`: rows that moved into the hidden cache area are reported as Style, Semantics (`isHidden`) and Removed items, not as consequences.
- Not met, `watchlist/scrolled`: the 104 px shift is grouped under one certain cause, `Added WatchRow#RIV0`. That is wrong. The banner is off screen in that scene, and RIV0 only came into view because of the shift. **This is the 1 wrong certain cause.**

**4. Semantics label: met.**
- All three detail snapshots show a semantics change on HeaderImage, with pixels unchanged.

**5. Longer strings: met.**
- There are content changes on the relabelled tiles, the app bar title and the three Continue buttons. On the loading button, the label is in semantics only.
- Tiles whose text wraps grow, and the tiles after them are reported as shifts, with the grown tiles as possible causes.
- No button overflowed: the buttons are 358 px wide and their size did not change. So the overflow sentence was not tested.
- In `matrix/settings_text_2x`, components pushed off screen are reported as Removed.

**6. Unsettled animation: met.**
- `buttons/all` fails at the determinism gate. The failure names `AppButton#loading` and says an animation is still running.
- `sign_in/submitting`, which uses the same spinner, fails the same way.

**7. Padding defaults: met, with unexplained noise.**
- Met: layout changes on SettingsTile, TradeSheet, BranchCard, the detail list tab and LabeledField.
- Met: each one-candidate shift is grouped under the tile that changed.
- Met: the rows below the two taller fields list both fields as possible causes.
- Met: nothing was added or removed, and no content changed.
- Not expected: an unexplained paint change on `SignInScreen@0` in all 9 sign-in snapshots, and on `MapSurface@0`.

**8. Chart data and stroke: met.**
- Only `PriceChart@0` and `@1` changed in the two chart scenes, and both are flagged as unexplained paint.
- Every other snapshot is identical.

**9. Refactor, restyle and accidental padding: partly met.**
- Met: a style change on each ChangeBadge is accepted by the declared expectation.
- Met: a layout change on each SectionHeader, with the components below it shifted. The first shift is grouped under SectionHeader@0. The later ones list their possible causes.
- Met: the 17 snapshots with a SectionHeader fail, and `order/symbol` (ChangeBadges only) is needs-review.
- Not met: the refactor is reported as `Added TileTrailing@0` on each SettingsTile, together with style "consequences" listing the moved fields as gone. It should be an info-level identity change. Under the declared expectations it counts as an undeclared visible change.
- Not met: the 16 unexplained screen-level paint changes listed above.
- "Snapshots with only the refactor pass" was not tested: every snapshot with a SettingsTile also has a SectionHeader.

## What the misses point to

These are inferences from the reports. None has been confirmed by a test yet.

1. **A pixel-hashed node's hash includes whatever is painted over it.** MapSurface changed when the pins changed colour (change 1) and when the BranchCard above it grew (change 7). Likewise, PriceChart@0 in change 9 changed when the section header above it moved.
2. **A component's own paint is not folded into a shift of its children.** This covers SignInScreen@0 in change 7 and the screen-level paints in change 9. Their children moved, and the paint the screen draws directly (dividers, labels, backgrounds) moved with them. The rule "paint changed where its children moved" exists, but it is not applied to these nodes.
3. **An extracted widget that wraps non-component children is reported as Added.** The identity rule matched QuoteNames in change 2, because QuoteNames wrapped components. TileTrailing wraps only framework widgets.
4. **A newly visible row can be named as a single certain cause.** RIV0 appeared because of the shift, so it cannot also be its cause.
5. **Sliver bookkeeping and the cache area leak into the report.** Examples are `KeepAlive.keepAlive` as a layout field, and rows entering the cache area losing their children.
6. **Token causes are not carried to the report.** Nothing groups changes across snapshots by cause.

## Next

Each item gets a failing regression test first, then a fix in the diff engine
or capture. After that the history runs again from step 0, and its results go
beside these in `history_run2/`. This first run stays as recorded.

# Second run

Run on 2026-10-09 on Linux, Flutter 3.47.6, with `tool/run_history.dart` at
2c63266. The reports were rendered again at 2ee5ff3 with `--score-only`, which
reuses the recorded captures; that commit changes only how causes are grouped
across snapshots in the report text. The raw output is in
[history_run2/](history_run2/). The expected results and run rules are the
same frozen texts as for the first run.

## Fixes between the runs

Each fix has a regression test that failed before it.

| Miss in the first run | Fix | Commit |
|---|---|---|
| 4, 5: rows entering or leaving a list's built range named as causes, and list bookkeeping in the report | Changes on rows at the edge of a list's built range, and the list's own bookkeeping, are a shift's consequences, never a candidate cause. With no other candidate the shift is "cause unknown" | 3d1134d |
| 1: a pixel hash included paint of other components drawn over or inside the node | An opaque node is pixel-hashed on its own drawing, painted alone, when every opaque reason can be painted alone; otherwise the composited view as before | 8ad4591 |
| 2: a component's own content, moved by its children, reported as unexplained paint | Nodes record `shape`, the paint text without child placement. Equal shape with a different paint is a layout change ("its content moved") with the moved children's changes as possible causes | 556ce97 |
| 3: an extraction around framework widgets inside a component that moved reported as Added | `flat` places the subtree's top semantics nodes relative to the component, and a refactor matches on equal size and flat output instead of equal bounds | a53cc23 |
| 6: token name dropped and no grouping across snapshots | A colour with the same token on both sides keeps the token. The review and the runner list each style cause found in more than one snapshot once, grouped by the token that changed | 2c63266, 2ee5ff3 |

The pixel and `flat` changes alter recorded hashes, so the macOS baselines
are recorded again.

## Scores

| Item | First run | Second run | Gate |
|---|---|---|---|
| Capture gaps | 0 | **0** over 9 × 41 pairs | 0: met |
| Unexplained rate, changes 1 to 9 | 7.5% (36 of 477) | **3.8%** (16 of 417) | under 5%: **met** |
| Wrong root causes stated as certain | 1 of 53 | **0** of 60 | 0: **met** |
| Verdicts per scene | | Identical to the first run in every change | |

Every single cause in the second run is the component the change edited:
PromoBanner in `watchlist/top` (change 3), the edited SettingsTiles (changes 5
and 7) and SectionHeader@0 (change 9). This was judged by reading each one,
as in the first run.

### Unexplained items by change

| Change | First run | Second run | Where, in the second run |
|---|---|---|---|
| 1 | 5 | 4 | `_Spinner` ×2 and `PriceChart@0` ×2 |
| 3 | 1 | 1 | `watchlist/scrolled`: the shift's cause is unknown |
| 7 | 10 | 0 | |
| 8 | 4 | 4 | `PriceChart@0` and `@1` in both chart scenes, as expected |
| 9 | 16 | 7 | `SettingsScreen@0` pixel hash ×6, and the root in `overlays/dropdown`, whose content moved with no known cause |

## Each change against its expected result

Changes 2, 4, 5, 6 and 8 are met, as in the first run. In change 6 the
failure now names `AppButton#loading/_Spinner@0`, the node inside the button
that is still animating.

**1. Colour token: met, with two gaps.**
- Met: one line groups the change across snapshots: `brand.accent #FF3949AB -> #FF3F51B5: style change on 31 SymbolAvatar, 30 SettingsIcon, 17 AppButton, 1 BranchCard, 1 MapPin in 25 snapshots`.
- Not met: two more lines group theme colours that change with brand.accent but have no token (`#FF525A92 -> #FF515B92`), on 6 components in 6 snapshots.
- Not met: the spinners and the chart draw the accent colour inside a painter, which style does not record, so they are unexplained paint.
- Fixed since the first run: `MapSurface@0` is no longer changed.

**3. Promo banner: met.**
- `watchlist/top`: one Added PromoBanner, with the rows below and the rows moved into or out of the list's built range folded in as consequences.
- `watchlist/scrolled`: the 104 px shift is "cause unknown, needs review", with the rows that came into view as its consequences. That is the correct answer, since the banner is off screen in that scene. The first run's wrong certain cause is gone.

**7. Padding defaults: met.**
- The unexplained paint on `SignInScreen@0` and `MapSurface@0` is gone.

**9. Refactor, restyle and accidental padding: partly met.**
- Met: the refactor is one info-level identity change, `SettingsTile in 7 places: same output; added TileTrailing`.
- Met: the restyle and the padding change are reported as in the first run.
- Not met: in `matrix/settings_small`, `SettingsTile@4` is cut off by the bottom of the viewport. It is still reported as `Added TileTrailing@0`, which is then listed as one of three possible causes of a shift.
- Not met: 7 unexplained items. `SettingsScreen@0` changed its pixel hash in all 6 settings scenes, and in `overlays/dropdown` the root's content moved with no cause found.

## What is left

These are inferences, not yet confirmed by a test.

1. `SettingsScreen@0`'s pixel hash changes when only its children move. It is opaque, and its own drawing is not painted alone, so its hash still covers the composited view.
2. A component cut off at the viewport edge has a different `flat` when it moves, so a refactor inside it is not matched.
3. Colours a theme derives from a token (`ColorScheme.fromSeed`) carry no token, and painters do not report the colours they draw.

The gates are met on the second run, so these go into the regression set and
are not fixed before step 4 of the plan.
