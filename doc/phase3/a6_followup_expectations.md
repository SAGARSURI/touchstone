# A6 follow-up: expectations

Written on 2026-10-10, before any of the changes below were made or run.

Sagar reviewed the A6 sheet alone (decided 2026-10-10 01:21Z). He marked 64
of 67 rows Yes. He marked three catalogue rows Unsure, all about how
readable the report is. None of the three disputes which widget the change
is reported on.

- **Row 3, `padding-1px`.** "How will a developer review or understand what
  to do?" The settings report opens with `Paint SettingsScreen@0 unexplained`,
  then has two shift lines with "possible causes" naming three copies of the
  same SectionHeader change.
- **Row 4, `size`.** "How helpful is it to show paint changed due to
  movement? Can the developer do something about it?"
- **Row 6, `widget-removed`.** "Can understand the change but the output is
  verbose."

## Changes

1. **The shape leaves out draws that draw nothing.** A draw whose paint is
   fully transparent, uses srcOver, does not invert colours, and has no
   mask, colour filter, image filter or shader leaves every pixel as it was.
   Material paints a transparent ink rectangle at each list tile's bounds.
   So when the tiles move, the screen's own paint text changes even though
   nothing it draws changed. `shape` is an explanation field and is not
   hashed, so detection is unaffected.
2. **Semantics nodes are matched, not compared by position.** A component's
   semantics nodes are aligned on what they say, so one node going away is
   reported as one fewer node. A semantics change on a parent that only
   loses or gains nodes, or changes its scroll child count, beside exactly
   one added or removed child, came or went with that child.
3. **Wrapper-only consequences are shortened.** A style or layout
   consequence in which properties only came or went with a child lists the
   property names once, without values or per-child indexes.
4. **Proven paint consequences are counted, not listed.**
   - "paint changed with the new size" on the resized component itself is
     no longer printed. The resize line above it already says this.
   - Consequences proven by the shape ("its content moved; nothing it draws
     changed") are summed into one line per item.
   - Consequences marked "not verified" are still printed one by one.
5. **One cause (Sagar, 2026-10-10 01:50Z).** When every candidate cause of a
   shift, or of content that moved inside a component, is the same change
   on copies of one component, the candidates count as one cause. The
   shifts become that change's consequences, and the folded "in N places"
   line carries them.

## Expected results

1. **Detection is unchanged.** Every catalogue scene's root hash is the same
   before and after the changes. The committed baselines stay valid, and the
   root test suite still passes (108 tests, plus the new ones).
2. **Row 3: `padding-1px` on settings/default.**
   - The `Paint SettingsScreen@0 unexplained` line is gone.
   - The report has one Layout item, `SectionHeader in 3 places`. Its
     consequences are the shifts and the content moving inside
     SettingsScreen.
   - It has no Shift item and no "possible causes".
   - The same holds on buttons/all: one `SectionHeader in 4 places` item.
3. **Row 4: `size`.**
   - The "paint changed with the new size" line is gone.
   - I expect the `SettingsTile around it` paint line to become proven,
     because the tile also paints a transparent ink rectangle. It would then
     be counted rather than listed. I am not sure of this.
4. **Row 6: `widget-removed`.**
   - There is no top-level Semantics item.
   - The removal has three consequences:
     - the shift;
     - one semantics line on SettingsScreen, about one fewer node and the
       scroll child count going from 14 to 12;
     - one short style line naming the property names.
5. **The gates hold.** On the catalogs (`tool/run_catalogs.dart` and
   `tool/check_catalogs.dart`) the following stay as in
   [gates.md](gates.md):
   - 0 missed;
   - the correct component and type scores;
   - the root-cause scores;
   - 0 wrong causes stated as certain.

   On generated seeds 0 to 9,999, there are 0 missed and 0 wrong single
   causes. The one-cause change may move some generated groups from
   "possible causes" to a single cause. Any of those that names the wrong
   change counts against the gate.
6. **Unexplained does not rise.** The number of unexplained items on the
   catalogs goes down by at least the one in `padding-1px` and rises
   nowhere.
