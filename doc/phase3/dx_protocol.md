# Phase 3 step 8: the developer-experience protocol

Written on 2026-10-09. Plan step 8 in [plan.md](plan.md). The spec, "How
developer experience is measured": in Phase 3 the team measures three things
on the catalogue, against the same changes handled with conventional golden
tests:

1. Median time from a failed run to the developer naming the cause.
2. Share of failures understood from terminal output alone.
3. Review time for pull requests that change baselines.

These need people to time themselves, so this file fixes how; the numbers
come from the engineers who run it, and go in `dx_results.md` beside it. No
number here is a gate: the spec lists them as measurements, and adopters
report the same three after release.

## Who

Two engineers: Sagar and the second engineer who reviews A6. Neither may
have written the change they are timed on. The changes below were frozen
before this protocol, so the engineer who prepared them (Claude) does not
take part.

## The changes

Twelve changes, each visible in pixels on a scene that both a snapshot test
(`test/snapshots_test.dart`) and a conventional golden test
(`test/dx/goldens_test.dart`, `matchesGoldenFile` on goldens recorded on
macOS, pumped as A13's conventional tests pump) cover,
so both arms fail. Changes that leave pixels unchanged (a refactor, a
semantics label, a font weight drawn with the test font) are left out: a
golden test does not fail on them, so there is no failure to time.
`tool/dx_items.dart` prints each one's edits and answer key:

| # | Change | Source |
| --- | --- | --- |
| 1 | Change one colour token | history change 1 |
| 2 | A clip changed on the detail header image | catalog `clip` |
| 3 | Add a promo banner above the watchlist | history change 3 |
| 4 | An icon changed in a settings row | catalog `icon` |
| 5 | Longer strings for a new locale | history change 5 |
| 6 | A design-library upgrade that shifts default paddings | history change 7 |
| 7 | A refactor, an intended restyle and an accidental 1 px padding in one pull request | history change 9 |
| 8 | Padding by 1 px | catalog `padding-1px` |
| 9 | Selected state | catalog `selected-state` |
| 10 | A widget removed | catalog `widget-removed` |
| 11 | Enabled state | catalog `enabled-state` |
| 12 | Insert near the start of a column | catalog `column-insert-start` |

Each change has a written answer key before any session: the component, the
change type and the cause, as the catalogs and the history expectations
already state.

## Two arms, crossed

Each change is prepared twice, as two branches off the same commit:
`dx/<nn>-snapshot`, where the snapshot tests fail, and `dx/<nn>-golden`,
where the golden tests fail. Each engineer gets six changes in each arm, and
never the same change in both, so every change is measured once per arm:

| Engineer | Snapshot arm | Golden arm |
| --- | --- | --- |
| A | 1, 3, 5, 7, 9, 11 | 2, 4, 6, 8, 10, 12 |
| B | 2, 4, 6, 8, 10, 12 | 1, 3, 5, 7, 9, 11 |

The order inside a session alternates arms (snapshot, golden, snapshot, ...)
so practice does not favour one arm.

## Measures 1 and 2: naming the cause

For each change, the engineer:

1. Checks out the branch, on a Mac (the baselines are macOS baselines),
   and runs the test command in the branch's `DX.md`; the clock starts when
   the run ends. The branch's last commit is the change, as if they had
   written it.
2. Works out the cause, using anything they like: the terminal output first,
   then golden failure images, the snapshot files, the code, the diff.
3. Stops the clock when they write down the cause: which component, what
   changed, and why, in one sentence.
4. Records whether they opened anything other than the terminal output
   before writing it (yes or no).

A cause counts as named only if it matches the answer key on the component
and the change. A wrong cause is recorded with its time and is not in the
median. Measure 1 is the median time over named causes, per arm. Measure 2
is, per arm, the share of changes named correctly without opening anything
but the terminal output.

## Measure 3: reviewing a pull request that changes baselines

Four pull requests on the repository, drafts never merged, each re-recording
the baselines for one change: changes 1, 3, 6 and 7. Each exists twice, one
with re-recorded snapshot files and the review command's output in its
description, one with re-recorded golden PNGs. Each engineer reviews two in
each arm, crossed as above, and never the same change twice.

The clock runs from opening the pull request to a decision: approve, or
request changes with the reason. The decision is checked against the answer
key: changes 1, 3 and 6 are intended, and 7 carries an accidental 1 px
padding that should be caught. Measure 3 is the median review time per arm,
reported with how many decisions were right.

## What is recorded

One row per session item, in `dx_results.md`:

| Engineer | Item | Arm | Seconds | Cause or decision as written | Right | Terminal only |
| --- | --- | --- | --- | --- | --- | --- |

## What Claude prepares

The 24 `dx/<nn>-<arm>` branches with their `DX.md` (the command to run and
nothing about the cause), the eight review pull requests, and the answer
key, kept outside the branches until the sessions are over.
