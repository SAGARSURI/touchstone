# Phase 3 step 8: the developer-experience protocol

Written on 2026-10-09. Plan step 8 in [plan.md](plan.md). The spec, "How
developer experience is measured": in Phase 3 the team measures three things
on the catalogue, against the same changes handled with conventional golden
tests:

1. Median time from a failed run to the developer naming the cause.
2. Share of failures understood from terminal output alone.
3. Review time for pull requests that change baselines.

These need people to time themselves, so this file fixes how; the numbers
come from the engineer who runs it, and go in `dx_results.md` beside it. No
number here is a gate: the spec lists them as measurements, and adopters
report the same three after release.

## Who

One engineer: Sagar (2026-10-10; the second engineer first planned is no
longer on the project). He did not write the changes: they were frozen
before this protocol, and the engineer who prepared them (Claude) does not
take part. He has read the history write-ups and this file, so he knows
which twelve changes are in play, though not which branch carries which;
that makes every time shorter in both arms, and is reported with the
numbers.

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
| 2 | An icon drawn at 60% opacity on the empty and error states | catalog `opacity` |
| 3 | Add a promo banner above the watchlist | history change 3 |
| 4 | A longer title on a settings row | catalog `text` |
| 5 | Longer strings for a new locale | history change 5 |
| 6 | A design-library upgrade that shifts default paddings | history change 7 |
| 7 | A refactor, an intended restyle and an accidental 1 px padding in one pull request | history change 9 |
| 8 | Padding by 1 px | catalog `padding-1px` |
| 9 | Selected state | catalog `selected-state` |
| 10 | A widget removed | catalog `widget-removed` |
| 11 | Enabled state | catalog `enabled-state` |
| 12 | Insert near the start of a column | catalog `column-insert-start` |

Two changes first chosen fail no golden test, found by the `dx-check`
workflow on macOS before any session ([dx_check_run2.txt](dx_check_run2.txt)),
and were replaced from the same catalog:

- **A clip on the detail header image** (catalog `clip`): the conventional
  test hands the image over as bytes and settles, and the image is never
  decoded in the test's fake time, so the golden has no image to clip.
- **An icon changed in a settings row** (catalog `icon`): the test font
  draws every glyph, icon glyphs included, as the same box, so the golden
  is the same.

The snapshot tests fail on both. That the golden arm misses them is itself
a result for the comparison, and goes in `dx_results.md` beside the timings.

Each change has a written answer key before any session: the component, the
change type and the cause, as the catalogs and the history expectations
already state.

## Two arms

With one engineer, each change is seen once, in one arm: seeing a change in
both arms, or in a session and then in a review, would give the second
sighting its answer. So the four changes that have review pull requests
(1, 3, 6 and 7, measure 3) are left out of measures 1 and 2, and the other
eight are split so that changes of a similar kind land in different arms:

| Measure | Snapshot arm | Golden arm |
| --- | --- | --- |
| 1 and 2 | 2 opacity, 5 locale, 8 padding, 9 selected | 4 text, 10 removed, 11 enabled, 12 insert |
| 3 | 1 colour token, 7 mixed pull request | 3 promo banner, 6 library upgrade |

Each item in measures 1 and 2 is one branch off the same commit,
`dx-session/<nn>-snapshot` or `dx-session/<nn>-golden`, where that arm's
tests fail. The
order alternates arms (snapshot, golden, snapshot, ...) so practice does
not favour one arm. Four items per arm is a small sample: the numbers are
reported as they are, with no claim of a difference unless it is large.

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
the baselines for one change, in the arm the table above gives it: changes 1
and 7 with re-recorded snapshot files and the review command's output in the
description, changes 3 and 6 with re-recorded golden PNGs. CI does not run
on them, since a red or green check would give the answer.

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

The eight `dx-session/<nn>-<arm>` branches above with their `DX.md` (the command to
run and nothing about the cause), the four review pull requests, and the
answer key (`tool/dx_items.dart`), which is on the base commit as it always
was: the branches ask not to open `tool/` before writing a cause down.
