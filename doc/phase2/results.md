# Phase 2 results

Run on 2026-10-09 with Flutter 3.47.6 on Linux x64, on branch `phase2-diff`.
The expected results and scoring rules were committed first, in
[expectations.md](expectations.md) (a829e64), before any diff code existed.
They are scored here exactly as written. Where an expectation now looks
wrong, it is marked as such and left unedited.

Data:
- Every catalog report: [catalogs.json](catalogs.json).
- Generated summary: [generated.json](generated.json).
- Each report as a developer reads it: `corpus/catalogue_app/build/catalogs/<entry>/report.txt`,
  from `dart run tool/run_catalogs.dart`.

## Exit gate: every mutation and no-op gate (spec, Verification strategy)

| Gate | Target | Result as written | Met |
| --- | --- | --- | --- |
| Missed changes, mutation catalog | 0 | 0 of 32 entries | yes |
| Missed changes, 10,000 generated | 0 | 0 of 10,000, at verdict level | yes |
| Fail verdicts on no-op refactors | 0 | 0 of 6 (6 of 6 pass after the A5 amendment) | yes |
| Correct component and change type | ≥99% | 30 of 32 (93.8%) | **no** |
| Correct root cause on cascade mutations | ≥95% | 17 of 19 (89.5%) | **no** |
| Wrong root causes stated as certain | 0 | 1 of 19 catalog entries; 0 of 748 generated single causes | **no** |

Three entries account for every miss. In each, the report seems right and
the written expectation wrong. That is a judgement for review, below.

| Entry | Expected | Report says | Why the expectation looks wrong |
| --- | --- | --- | --- |
| `custom-painter` | Paint (unexplained) on `_Spinner` | Style on `_Spinner`: `CircularProgressIndicator.value: 70.0% -> 75.0%` | The expectation assumed nothing would name the cause. The style field now describes the framework widgets inside a component, and the indicator's widget reports its value. |
| `padding-1px` | Every shift has one root cause, a `SectionHeader` | Each shift of 2, 3 or 4 px lists 2, 3 or 4 `SectionHeader`s as possible causes | The edit changes every `SectionHeader`. A component below the third header moved 3 px because of three headers. The spec makes a causal claim "only when exactly one candidate exists", so listing them is the spec's behaviour. |
| `stack-resize-first` | Root cause: Layout on `AppButton#sizing` | Root cause: Layout inside the scene: `SizedBox.width: 300.0 -> 320.0`, with the button's resize as a consequence | The edit changes the `SizedBox` around the button, which belongs to the scene's own code, not to `AppButton`. The report names the edited line. This is the "wrong certain" row: certain, and different from what was written. |

Read with those three corrected, every gate is met: 32 of 32, 19 of 19 and 0
wrong.

**Review decision (Sagar, 2026-10-09 03:38Z): the three corrections are
accepted.** The gate is recorded as met in the assumption register. The
expectations in expectations.md stay as first written, and the tables below
keep scoring against them.

## Mutation catalog (component and change type)

Seventeen mutations, plus the fifteen cascade entries' own change, scored
against `expectTypes`. Every report's verdict is needs-review.

| Entry | Expected | Correct | Extra top-level items |
| --- | --- | --- | --- |
| colour-token | Style on ChangeBadge | yes | 1: `Paint WatchRow#LUM0`, the last row, whose pixel hash covers the badge drawn over it |
| text | Content on SettingsTile | yes | 0 |
| padding-1px | Layout on SectionHeader | yes | 6: five shift lines with possible causes, and `Paint SettingsScreen`, whose framework children moved under several causes |
| size | Layout on SettingsIcon | yes | 0 |
| widget-added | Added SettingsTile | yes | 0 |
| widget-removed | Removed SettingsTile | yes | 1: `Semantics SettingsScreen` (node count 6 -> 5) |
| widget-reordered | Reordered SettingsTile | yes | 0 |
| opacity | Style on StatusView | yes | 0 |
| clip | Style on HeaderImage | yes | 0 |
| font-weight | Style on PriceLabel | yes | 0 |
| icon | Content on SettingsIcon | yes | 0 |
| image | Content on HeaderImage | yes | 0 |
| enabled-state | Style and Semantics on AppButton | yes | 0 |
| selected-state | Style and Semantics on SettingsTile | yes | 0 |
| semantics-label | Semantics on HeaderImage | yes | 0 |
| custom-painter | Paint on `_Spinner` | **no** (Style, see above) | 1: `Content AppButton#loading`, its semantics value |
| theme | Style on every screen component | yes | 0 |

The 15 cascade entries: 14 correct. `stack-resize-first` is not (see above).

## Cascade mutations (A8)

| Entry | Root cause | Correct | Shift groups |
| --- | --- | --- | --- |
| padding-1px | SectionHeader | **no** | several possible causes each |
| size | SettingsIcon | yes | none expected, none found |
| widget-added | SettingsTile | yes | 1, single cause |
| widget-removed | SettingsTile | yes | 1, single cause |
| column-insert-start | SectionHeader | yes | single cause |
| column-remove-start | LabeledField | yes | single cause |
| column-resize-start | Heading | yes | single cause |
| column-insert-first | Heading | yes | single cause |
| column-remove-first | Heading | yes | single cause |
| list-insert-start | SettingsTile | yes | single cause |
| list-remove-start | SectionHeader | yes | single cause |
| list-resize-start | SettingsTile | yes | single cause |
| list-insert-first | AppButton | yes | single cause |
| list-remove-first | SectionHeader | yes | single cause |
| lazy-list-insert-first | WatchRow | yes | single cause |
| lazy-list-remove-first | WatchRow | yes | single cause |
| stack-insert-first | SectionHeader | yes | none expected, none found |
| stack-remove-first | SectionHeader | yes | none expected, none found |
| stack-resize-first | AppButton | **no**, stated as certain | single cause: the scene's `SizedBox` |

In the lazy list, the row pushed to the viewport's edge is clipped, so its
paint changes. It is shown as a consequence of the insertion, labelled "not
verified".

## No-op refactor catalog (A5)

**Rerun with flattened matching (2026-10-09): 6 of 6 pass, and A5's own
criterion holds for all six.** Sagar chose to amend the spec's A5 fallback
and build flattened matching in this phase. Its expectations were committed
first, in [a5_expectations.md](a5_expectations.md) (75040b3), and every one
of them was met as written.

| Entry | Verdict | Report |
| --- | --- | --- |
| extract-widget | pass | 12 lines, one per `WatchRow`: `Identity WatchRow#ACM0  same output; added QuoteNames` |
| inline-widget | pass | 7 lines, one per `SettingsTile`: `Identity SettingsTile@0  same output; removed SettingsIcon` |
| wrap-layout-neutral | pass | no change |
| add-const | pass | no change |
| stateless-to-stateful | pass | no change |
| rename-class | pass | 12 lines, one per avatar: `Identity WatchRow#ACM0/TickerAvatar@0  same output; renamed SymbolAvatar -> TickerAvatar` |

- Each node now records `flat`, its subtree's paint and semantics with
  component boundaries removed. A rename is paired on bounds and `flat`
  instead of type.
- An added, removed or renamed component inside a component whose bounds and
  `flat` are unchanged makes that subtree one Identity line.
- The 32 mutation and cascade entries gave exactly the same results as the
  first run. None became Identity or pass.
- Five adversarial unit tests (`test/refactor_test.dart`) make refactor-like
  edits that change the output: a colour, padding, a size, a semantics label
  and a clip. Each gets needs-review, with no Identity line over the changed
  component.

The first run, before the amendment, had 3 of 6 at needs-review: extract,
inline and rename. The spec's original fallback could not pair them.

## Generated mutations

Seeds 0 to 9,999. Each pumps a catalogue scene and applies one render-level
mutation. The pixel and semantics oracle decides whether anything changed.

Rerun with flattened matching on 2026-10-09: every number below is the same
as in the first run, and no generated mutation was reported as Identity.

- **0 missed** at verdict level. 7,407 mutations changed pixels or semantics,
  and every one got needs-review. 1,391 more changed the snapshot but not the
  oracle. 1,202 changed nothing and passed.
- **The owner is named.** In 8,798 of the 8,798 changed snapshots, the
  component that owns the mutated render object is a top-level item.
- **The type is accepted.** 7,641 of the 7,874 scored mutations got a type
  listed for their kind in expectations.md. Reorders are not scored. That is
  97.0%, with no gate.
- **Shift groups (A8).** There were 1,000 groups:
  - 748 named a single cause, and all 748 are the mutated component or one it
    sits in. 0 were wrong.
  - 252 had no candidate and say "cause unknown". Of those, 251 are reorders
    inside a component's own render objects, where the component's change is
    unexplained paint, not a candidate type. The other is a text change, whose
    Content type is not a candidate either.

| Kind | Changed | Owner named | Type accepted | Types given to the owner |
| --- | --- | --- | --- | --- |
| custom painter removed | 251 | 251 | 122 | Layout 129, Style 122 |
| decoration colour | 193 | 193 | 193 | Style 193 |
| decoration radius | 141 | 141 | 141 | Style 141 |
| flex alignment | 83 | 83 | 83 | Layout 83 |
| font weight | 1405 | 1405 | 1405 | Style 1405 |
| image | 18 | 18 | 18 | Style 18 |
| opacity | 23 | 23 | 23 | Style 23 |
| padding 1px | 1260 | 1260 | 1233 | Layout 1233, Semantics 27 |
| reorder children | 924 | 924 | (any) | Style 268, Paint and Semantics 213, Paint 149 |
| semantics label | 140 | 140 | 140 | Semantics 140 |
| shape colour | 158 | 158 | 158 | Style 158 |
| size 1px | 839 | 839 | 839 | Layout 839 |
| text | 1423 | 1423 | 1346 | Content 1346, Semantics 77 |
| text colour | 1346 | 1346 | 1346 | Style 1346 |
| transform | 594 | 594 | 594 | Layout 348, Style 246 |

There are two weak spots, with no gate on either:

- **A removed painter reads as Layout in 129 cases.** When the painter is
  removed, the render object stops drawing, so its properties count as
  layout.
- **77 text mutations are Semantics only.** The text was mutated in the render
  object, so the widget's `Text.data` still holds the old text, and the paint
  change went to the merged semantics node.

## A6

The review sheet is rebuilt from the Phase 2 reports:
[a6_review.md](a6_review.md). It covers the 17 catalog mutations and 50
generated mutations sampled with seed 6. It is what a developer now reads,
and it replaces the Phase 1 sheet. It is still waiting on two reviewers.

Reviewers fill in the Claude Doc "A6 attribution review", which holds the
same rows with a Yes, No or Unsure choice per reviewer. In its generated
section, the 42 samples whose report names only the owning component share
one row; the 7 other rows are the samples whose report names more.

On 2026-10-09 Sagar reviewed the catalog rows: most were Yes, and five were
Unsure with notes that the report was too verbose. The report now uses the
shorter wording in [diff.md](diff.md), "Report wording", which cuts the 17
catalog reports from 25,104 to 7,146 characters. The catalog rerun with it
scored every entry exactly as before, and the sheet shows the new reports.

## What the runs changed

The first catalog runs found three capture properties that blocked the
spec's cascade and identity rules. Each is fixed and explained in
[diff.md](diff.md), "Capture changes made in Phase 2":

- A component that only moved changed its paint if it was pixel-hashed.
- Child markers held the child's id.
- A repaint boundary left a command.

Fixing them changed what is hashed, so the catalogue baselines were
re-recorded on macOS (e4ea131). The fixture suite and the capture-gap
regression tests pass unchanged.
