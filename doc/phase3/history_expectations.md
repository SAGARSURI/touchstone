# Phase 3: how the catalogue history is scored

Written on 2026-10-09, before changes 7 to 10 ran and before any change ran
through the diff. The expected result of each change is in
`corpus/catalogue_app/tool/history.dart` (changes 1 to 6, frozen 2026-10-07)
and `corpus/catalogue_app/tool/history_phase3.dart` (changes 7 to 10, frozen
2026-10-09). This file fixes how they are scored.

## The run

- Changes apply in order, each on top of the ones before it. Changes 6 and
  9 are expected to fail, so they are not merged: the next change applies on
  top of the one before them.
- For each change, every one of the 44 snapshots is captured before and
  after on one Linux host, together with the pixel and semantics oracle (the
  whole view rasterized at device pixel ratio 3, and the semantics tree).
- Each pair is diffed and given a verdict by the default policy, plus the
  change's declared expectations where it has them (change 9).
- Change 10 needs two Flutter releases and runs separately (plan step 6).

## What is scored

1. **Capture gaps (A4 on real code; exit gate: 0).** A snapshot whose pixels
   or semantics changed while its root hash did not.
2. **Each change's expected result, as written.** Each sentence that names
   a component, a change type, a grouping or a verdict is checked against the
   reports and marked met or not met. A wrong expectation is marked wrong
   and left unedited.
3. **Untouched snapshots stay identical.** A snapshot the change cannot
   affect must have the same root hash before and after.
4. **Unexplained rate (tracked, target under 5%).** Over every report item
   in every changed snapshot of changes 1 to 9: the share flagged as
   unexplained paint or as a shift of unknown cause.
5. **Wrong root causes stated as certain (0).** A shift group with a single
   cause that is not the edited component or one it sits in.

Snapshots outside the edit's reach whose oracle also stayed unchanged count
for item 3 only.
