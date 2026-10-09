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
