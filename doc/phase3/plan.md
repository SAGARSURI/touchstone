# Phase 3 plan: catalogue verification, then release

From the tech spec, "Phases and exit gates":

- **Builds:** the catalogue app grows to realistic screens with a scripted
  change history, and every gate runs on it. Once the team is confident in the
  results, the first release is published on pub.dev and promoted.
- **Assumptions tested:** A4 on real code, A7, A10, A12.
- **Exit gate:** 0 capture gaps on catalogue history. The release decision is
  recorded together with the gate results. Budgets met or renegotiated.
  Unexplained rate reported.

Phase 2 was merged on 2026-10-09 (PR #3), and its gate is recorded in the
assumption register.

## Steps, in order

Each step's expected results are committed before the step runs, as in
Phases 1 and 2. A wrong expectation is marked wrong and left unedited.

1. **Levels 4 and 5 of the catalogue** (spec, "Catalogue scenarios"): the
   overlay screen (dialog, bottom sheet, snackbar, dropdown), the theme and
   locale matrix (light and dark, right-to-left, text scale 2.0, small and
   large viewports), the chart (line and candlestick series drawn by a
   `CustomPainter`, a gradient fill, a tooltip), the live price list, the map
   placeholder under a blurred header, and the four-step order flow with
   animated transitions and a reorderable list. Each gets scenes, baselines
   recorded on macOS, and the existing determinism and repeat gates.
2. **Scripted changes 7 to 10**, frozen with their expected results before
   any of them runs, beside changes 1 to 6 (frozen 2026-10-07).
3. **Run the history**, changes 1 to 10 in order, each as one commit. Every
   change is captured, diffed and given a verdict, and the shadow pixel audit
   runs over every snapshot of every step. This measures A4 on real code (0
   capture gaps) and the unexplained rate (tracked, target under 5%).
4. **Every Verification strategy gate on the grown catalogue**: the mutation
   and no-op catalogs, 10,000 generated mutations, and 1,000 repeats per
   operating system.
5. **A10 and budgets**: test time with and without capture, snapshot size,
   share of nodes needing a pixel hash, and hash-equal comparison time, on the
   whole catalogue. Proposed budgets: capture adds under 20% to test time, and
   a hash-equal comparison takes under 1 ms per snapshot. If over budget, the
   spec says to add shards or renegotiate the budget, never the coverage.
6. **A12 and change 10**: capture on two consecutive stable releases and run
   the migration. Snapshots with identical pixels must re-baseline
   automatically with the pixel proof attached, and the rest go to review.
7. **A7**: for a sample of mutations, compare the tool's reports with device
   screenshots using real fonts.
8. **Developer experience** (spec, "How developer experience is measured"):
   on the catalogue, against the same changes handled with conventional
   golden tests, the median time from a failed run to naming the cause, the
   share of failures understood from terminal output alone, and review time
   for pull requests that change baselines.
9. **Release decision**, recorded in the register with every gate result.
   Publishing to pub.dev waits for Sagar's explicit go.

## Defaults chosen where the spec leaves a choice

- **A12 releases.** The latest two consecutive stable releases are 3.47.6
  (the current toolchain) and 3.47.7 (2026-10-08), a patch release. A12 runs
  on that pair now. When the next minor stable release ships, it runs again.
- **A7 device.** Screenshots come from an iOS simulator on the macOS CI
  runner, through `integration_test`, with the catalogue's real fonts. The
  mutations are the generated ones, applied at run time, so one build covers
  the whole sample. The sample size goes in the A7 expectations before the
  run.
- **Developer experience.** This needs people to time themselves. A protocol
  (which changes, who, and how each time is taken) is written in step 8, and
  the numbers come from the engineers who run it.

## What stays open from earlier phases

- **A6** (two engineers review the attribution of every mutation) has Unsure
  answers left. The release decision records its state.
