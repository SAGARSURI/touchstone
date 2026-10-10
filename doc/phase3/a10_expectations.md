# Phase 3 step 5: A10 and budgets, written before the measurement

Written on 2026-10-09 and committed before the measurement runs. Plan step 5
in [plan.md](plan.md). The budgets are the spec's proposals ("CI time and
cost", Budgets); A10 measures them.

## What is measured, on every catalogue scene

| Number | How |
| --- | --- |
| Test time without capture | Wall time of `flutter test test/a10/a10_test.dart --dart-define=A10_MODE=plain`: one test per scene that pumps the scene exactly as `snapshots_test.dart` does, and nothing else |
| Test time with capture | The same file with `A10_MODE=capture`: each test pumps the scene, then does what `expectSnapshot` does on a pull request when the snapshot is unchanged: read the baseline file, parse it, capture, compare root hashes and toolchains |
| Per-scene cost | Inside the same runs, a stopwatch around the pump and around the capture-and-compare, so the cost can be split per screen |
| Hash-equal comparison | Parse a baseline and compare its root hash and toolchain with a capture's, timed over 1,000 rounds per snapshot; reported with and without the parse |
| Snapshot size | Bytes of every committed baseline in `test/snapshots` |
| Share of nodes needing a pixel hash | From the committed baselines: nodes with an opaque reason over all nodes, per snapshot and overall |

The baselines are macOS baselines and this runs on Linux, so the capture
mode compares against baselines written by a first `A10_MODE=record` run on
the same machine, into `build/a10/`. That keeps the hash-equal path, which is
the path the budget is about. Each mode runs three times; the median wall
time is used.

## Budgets and expected results

1. **Capture adds under 20% to test time.** Expected: met on wall time for
   the whole file, since the test runner's start-up and each test's set-up
   are paid in both modes. Per scene, the stopwatch cost of capture is
   expected to be above 20% of the pump on some screens: Phase 0 measured 5
   to 14 ms of recording against 18 to 23 ms of pumping on fixture screens,
   and opaque nodes now rasterize their own drawing. Those scenes are listed.
2. **A hash-equal comparison takes under 1 ms per snapshot.** Expected: met
   by a wide margin for the comparison of hashes, and also met with the parse
   of the baseline included, for every snapshot.
3. **Share of nodes needing a pixel hash.** No budget. Expected highest on the
   chart, map and order flow scenes (paths, a platform view, blurs), and
   under 10% overall.
4. **Snapshot size.** No budget. Reported per snapshot and in total.

If a budget is not met, the spec says to add shards or renegotiate the
budget, never the coverage. Renegotiating is Sagar's call.
