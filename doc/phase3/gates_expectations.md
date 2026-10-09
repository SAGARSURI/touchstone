# Phase 3 step 4: every Verification strategy gate on the grown catalogue

Written on 2026-10-09 and committed before step 4 runs. Plan step 4 in [plan.md](plan.md). The scoring rules are
Phase 2's, in [../phase2/expectations.md](../phase2/expectations.md), with
the three corrections Sagar accepted on 2026-10-09 (`custom-painter`,
`padding-1px`, `stack-resize-first`; [../phase2/results.md](../phase2/results.md)).
Nothing here loosens a gate.

## What runs

The code is the head of `phase3-catalogue` after the history fixes: opaque
nodes hashed alone, `shape`, the position-free `flat`, and the report
changes. Each of these changes what is captured or how it is diffed, so every
gate runs again.

| Gate | How | Target |
| --- | --- | --- |
| Mutation catalog: missed changes | `dart run tool/run_catalogs.dart`, all 39 entries | 0 |
| Mutation catalog: correct component and change type | the same run | at least 99% |
| Cascade mutations: correct root cause | the same run | at least 95% |
| Wrong root causes stated as certain | the same run, and every generated single cause | 0 |
| No-op refactors: fail verdicts | the same run | 0 |
| Generated mutations: missed changes, at verdict level | 10,000 seeds, `test/generated`, in chunks of 1,000 | 0 |
| Repeats: differing snapshots | the `a3-repeats` workflow, 1,000 repeats of every snapshot on each of the four runner images | 0 |

## Expected results

1. **Catalogs.** The same scores as Phase 2 read with the accepted
   corrections: 32 of 32 correct component and type, 19 of 19 correct root
   causes, 0 wrong certain causes, 6 of 6 no-ops pass, 0 missed. The catalogs
   edit levels 1 to 3 only, and the history fixes did not touch their
   outcomes in the history runs, so no entry is expected to change its
   verdict. Fewer extra top-level items are expected where a screen's own
   paint moved with its children (`padding-1px`'s `Paint SettingsScreen`),
   but the history's second run still shows that item, so it may stay.
2. **Generated.** 0 missed in 10,000. The seeds now draw from every scene in
   `test/support/scenes.dart`, levels 4 and 5 included, which Phase 2 never
   sampled. The accepted-type rate is reported with no gate, as in Phase 2;
   the chart and spinner scenes are expected to give Paint on mutations
   inside a painter.
3. **Repeats.** 0 differing snapshots on every image. The run on 5a76f43,
   with the new baselines, already passed on all four images; it is cited, not
   repeated.

Results go in `gates.md` beside this file, scored against this text as
written.
