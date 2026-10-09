# Phase 3 step 4: results

Run on 2026-10-09 on Linux x64, Flutter 3.47.6, at 92536d2. Scored against
[gates_expectations.md](gates_expectations.md) as written.

Data:
- Every catalog report: [catalogs.json](catalogs.json), from
  `dart run tool/run_catalogs.dart`.
- Generated summary: [generated.json](generated.json), from seeds 0 to 9,999
  of `test/generated`.
- Repeats: the `a3-repeats` workflow on 5a76f43 (43 checks green, including
  10 shards of 100 on each of macOS arm64, macOS Intel, Linux x64 and Linux
  arm64).

## Gates

| Gate | Target | Result | Met |
| --- | --- | --- | --- |
| Missed changes, mutation catalog | 0 | 0 of 32 entries | yes |
| Correct component and change type | at least 99% | 30 of 32 as written; 32 of 32 with the accepted corrections | yes |
| Correct root cause on cascade mutations | at least 95% | 17 of 19 as written; 19 of 19 with the accepted corrections | yes |
| Wrong root causes stated as certain | 0 | `stack-resize-first` as written (an accepted correction); 0 of 863 generated single causes | yes |
| Fail verdicts on no-op refactors | 0 | 0 of 6; all 6 pass | yes |
| Missed changes, 10,000 generated | 0 | 0, at verdict level and at snapshot level | yes |
| Differing snapshots in 1,000 repeats per image | 0 | 0 on all four images | yes |

## Against the expected results

1. **Catalogs: as expected.** Every entry's verdict and scores are the same
   as in Phase 2. Extra top-level items went down in four entries:
   `lazy-list-insert-first` and `lazy-list-remove-first` lost five items each
   (rows at the edge of the list's built range, now consequences),
   `list-remove-first` lost `Paint AppButton#primary`, and in
   `custom-painter` the extra item is now `Semantics AppButton#loading`
   (the progress value) instead of `Content AppButton#loading`.
   `padding-1px` still lists `Paint SettingsScreen`, as the expectation
   allowed.
2. **Generated: as expected on the gate, with one finding.** 0 missed. 7,923
   of 10,000 snapshots changed, 6,785 where the oracle saw a change; the
   1,138 others are needs-review on changes the pixels and semantics do not
   show, as in Phase 2. The change type was an accepted one in 6,908 of
   7,125 scored (97.0%; Phase 2: 97.0%), with no gate. The largest group of
   unaccepted types: removing a `CustomPainter` inside `AppButton` is
   reported as Layout in 100 of 200, where Paint or Style was expected. The
   render object that stopped drawing moves its keys to the layout side.
   This was not predicted and is recorded here as found.
3. **Repeats: as expected.** 0 differing snapshots on every image.

Every step 4 gate is met.
