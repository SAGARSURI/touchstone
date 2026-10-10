# Review overview: expectations

Written on 2026-10-10, before any code or run. Sagar found measure 3 too much
to review: the description of review pull request #5 (DX item 01, one colour
token) carries 531 lines of `touchstone:review` output across 39 snapshots,
and the line that sums it up, "Causes in more than one snapshot", is at the
very end.

## The change

`touchstone:review` (and `update`, which prints the same) opens with an
overview, then each snapshot's report as today:

1. The counts and the verdict line, as today's last line.
2. Unexplained items first (spec, Default policy: "Needs-review, flagged
   first in the report"), one line per component type and change, with how
   many snapshots.
3. Causes in more than one snapshot, as today.
4. Every other visible change, one line per component type and change,
   with how many snapshots: nothing outside the lines above is left out of
   the overview, so a reviewer who reads only the overview still sees every
   distinct change once. New, removed, unreadable and migrated snapshots
   are listed here by path.

Each snapshot's report and verdict stay exactly as they are; the verdict
line is repeated as the last line.

## Expected results

1. Verdicts, exit codes and every per-snapshot report are unchanged, byte
   for byte, on the four DX review branches.
2. Item 01's overview (before the per-snapshot reports) is at most 25 lines.
3. Item 07's overview names the accidental 1 px padding on a line of its
   own.
4. The test suite passes; catalogue and history gate numbers are unchanged,
   since no verdict or attribution changes.
