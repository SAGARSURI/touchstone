# A6 follow-up: results

Run on 2026-10-10 on Linux x64 with Flutter 3.47.6, at a33365e. The results
are scored against [a6_followup_expectations.md](a6_followup_expectations.md)
as it was written.

Data:
- **Catalogs.** From `dart run tool/run_catalogs.dart`, in [a6_followup_catalogs.json](a6_followup_catalogs.json). The scores are the
  same as in [catalogs.json](catalogs.json) except where noted below.
- **Generated.** Seeds 0 to 9,999 of `test/generated`. The summary is below and in [a6_followup_generated.json](a6_followup_generated.json).

## Against the expected results

1. **Detection is unchanged: as expected.** Every catalogue scene has the
   same root hash with and without the changes (9 of 9 base scenes compared
   at 8d07441 and at the new code). The root suite passes: 108 tests, plus 5
   new ones in `test/a6_followup_test.dart`.
2. **Row 3, `padding-1px`: as expected.** Each scene's report is one item.
   - On buttons/all: `SectionHeader in 4 places` with "5 components shifted
     down 1 to 4 px".
   - On settings/default: `SectionHeader in 3 places` with "14 components
     shifted down 1 to 3 px" and "repainted only to follow it:
     SettingsScreen around it".
   - Neither has an unexplained item, a Shift item or "possible causes".
   - Its root cause, which was an accepted correction in
     [gates.md](gates.md), is now correct as written.
3. **Row 4, `size`: partly wrong.**
   - "paint changed with the new size" is gone, as expected.
   - I expected the `SettingsTile around it` line to become proven. **It did
     not.** The tile lays out its title and subtitle 1 px narrower (258 to
     257) because the icon grew, so its own text boxes changed. The glyphs
     are the same, but nothing proves that from the recording. The line
     stays "not verified".
4. **Row 6, `widget-removed`: as expected, except for one detail.**
   - The top-level Semantics item is gone.
   - The removal carries the shift, a short style line and "Semantics
     SettingsScreen@0: nodes: 6 -> 5 semantics nodes (went with the child)".
   - **Not as expected:** the scroll child count (14 to 12) does not appear.
     The count is a geometry field, which is left out of the comparison.
5. **The gates hold.**
   - **Catalogs.** 0 missed. The component and type scores are unchanged.
     The root cause is correct in 18 of 19 as written, against 17 before.
     The one left is `stack-resize-first`, the accepted correction in
     gates.md.
   - **Generated.** 0 missed, at verdict and at snapshot level. There are
     863 single causes, all correct, so 0 wrong causes are stated as
     certain. The one-cause rule did not apply to any generated seed,
     because each seed makes one change.
6. **Unexplained does not rise: met on the catalogs, wrong on the generated
   set.**
   - **Catalogs.** No report has an unexplained item; before, one did
     (`padding-1px`).
   - **Generated.** Unexplained paint items went from 339 to 343:
     - 10 settings scenes went down, after the ink fix;
     - 14 reorders on detail scenes went up.
   - Those 14 used to read "Content DetailScreen@0". That was a wrong
     explanation: positional pairing compared a moved container node with
     its neighbour, which made up a label change. The reading order did not
     change. They now read as unexplained paint, plus "Semantics: same
     semantics nodes in another order".

## Found on the way

The first 10,000-seed run, at 577d3fa, found two regressions. Both were
fixed, and the run was repeated:
- **The 14 detail reorders above.** No text change was found, so the paint
  fell back to unexplained (9e98382).
- **35 reorders whose reading order changed.** The reorder was counted as a
  text change and folded into the Style item around it, so the report
  stopped saying the order changed. Node order is now its own semantics
  change, `order`, and is never a text change (a33365e). The 17 reorders in
  states/empty and the overlays now name the order change. Old reports had
  no line for it.

Seven reorders that also remove a component lost a top-level Semantics
item. Their node-count change is now a consequence of the removal, as
change 2 intends.

## Generated summary

| Measure | Gate run (92536d2) | This run (a33365e) |
| --- | --- | --- |
| Missed, verdict and snapshot | 0 | 0 |
| Snapshots changed | 7,923 | 7,923 |
| Owner reported as an item | 7,864 | 7,864 |
| Accepted change type | 6,908 | 6,915 |
| Shift groups | 1,226 | 1,226 |
| Single causes, all correct | 863 | 863 |
| Wrong causes stated as certain | 0 | 0 |
| Unexplained paint items | 339 | 343 |
