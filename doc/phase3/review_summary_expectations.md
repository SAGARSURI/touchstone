# Review summary: expectations

Written on 2026-10-10, before any code or run. Sagar found the overview
(doc/phase3/review_overview_expectations.md) still too much to review: on
pull request #5 (DX item 01) it is 22 lines, many of them wrapped, full of
colour values and component lists. On the decision card he chose "Five
lines".

## The change

`touchstone:review` (and `update`) opens with a summary of at most five
lines, each at most 100 characters, so it never wraps:

1. The counts and the verdict, as today's first line.
2. "Check first:" with the unexplained items by change and component type,
   and in how many snapshots. Left out when nothing is unexplained.
3. One line per cause shared between snapshots: the cause, then how many
   components and snapshots, without the component list. As many as the
   five lines allow.
4. "Also:" with every other change by change and component type, and any
   shared cause that did not get a line of its own.

Each line names as many items as fit and ends with "+N more" for the rest,
so every distinct change is either named or counted. Today's overview
follows unchanged, under "All changes:", then each snapshot's report, then
the verdict line as the last line.

## Expected results

1. Verdicts, exit codes, each snapshot's report and the overview are
   unchanged, byte for byte, on the DX review branches for items 01 and 07.
2. Item 01's summary is at most five lines, none over 100 characters.
3. Item 07's summary names `Layout SectionHeader` on its "Also:" line.
4. Every change type and component type in the overview appears in the
   summary, or is counted in a "+N more".
5. The test suite passes; catalogue and history gate numbers are unchanged,
   since no gate reads the summary.

## Results

Run on 2026-10-10 with 749d5ea and 87252a9, against the DX review branches
at base c22b4f3.

1. Met. On items 01 and 07, everything from "All changes:" on (the overview,
   each snapshot's report, the last verdict line) is byte for byte what
   review-summary (3b1c9e6) prints after its first blank line; exit codes
   (2) match.
2. Met. Item 01's summary is five lines, the longest 100 characters.
3. Met. Item 07's "Also:" line opens with `Layout SectionHeader (17
   snapshots)`.
4. Met. Item 01's summary names all 5 change and component types of its
   overview; item 07's names 3 of 6 and counts the other 3 as "+3 more".
   A first version wrote "(1 snapshot)" after each name, which cut item
   01's "Also:" line to two names; the count is now shown only when it is
   more than one.
5. Pending: the suite passes (141 tests); the gate runs are in progress.
