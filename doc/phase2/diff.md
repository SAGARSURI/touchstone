# Phase 2: the diff engine, policy and commands

This records how the spec's Diff engine and Policy sections were built. It also
lists every point where the spec left a choice open and which choice was made.
Each choice is listed under "Interpretations" so it can be reviewed on its own.

## Where comparison happens

The spec has two comparisons.

| When | What is compared | Verdict |
| --- | --- | --- |
| Test time, `expectSnapshot` | The capture with its committed baseline | Pass when equal. Any difference fails ("capture differs from the committed baseline"), and the failure message is the change report. The one difference that passes is content of a component declared dynamic. |
| Review time, `dart run touchstone:review --base <target>` | The committed baseline with the target branch's baseline | Decided by the policy: pass, needs-review or fail. |

An equal root hash passes without a diff, as the spec's architecture says.

## Steps (spec: Diff engine)

1. **Toolchain.** If the fingerprints differ, the report is a migration and
   nothing is compared.
2. **Root hash.** Equal root hashes with equal inputs make the report empty.
3. **Descend by id.** Children are paired by id. Equal subtree hashes pair
   whole subtrees.
4. **Sibling pairing.** Siblings that were not paired by id, or whose output
   changed, are paired when one sibling on each side has the same type and the
   same shape: its size, own paint, semantics and the shapes of its children.
   Of the paired siblings, those outside the longest run that kept its order
   are **Reordered**. A pair with different ids is an **Identity** change.
5. **Second matching pass (spec, amended for A5 on 2026-10-09).** Nodes still
   unpaired anywhere are paired when exactly one node on each side has the
   same type, bounds and paint hash. Those still unpaired are then paired
   when exactly one node on each side has the same bounds and flattened
   output (`flat`), whatever its type. The pair is an **Identity** change
   under the same parent, otherwise **Moved**.
6. **Classify** each pair, and report unpaired nodes as **Added** or
   **Removed** (the top-most only, with a count of components inside).
7. **Collapse refactors (A5).** A component added, removed or renamed inside
   a paired component whose bounds and flattened output are unchanged is a
   refactor. Every change in the nearest such component's subtree is
   replaced by one **Identity** change on it, such as `same output; added
   QuoteNames`. Equal flattened output means the subtree draws the same
   commands and exposes the same semantics, so nothing in it is visible (A4).
8. **Group cascades** (below).
9. **Label unexplained**: a paint change with no named cause is **Paint**,
   flagged and listed first.

## Classifying a pair

| Change type | Reported when |
| --- | --- |
| Layout | The component's size changed. The detail adds any layout properties that changed (`SizedBox.height: 40.0 -> 50.0`). |
| Style | The paint changed and a style property changed. |
| Content | The paint changed, and only content changed: text (`RenderParagraph.plainText`, `Text.data`, the semantics label or value), an icon or an image. |
| Semantics | A label, role, flag or action changed with no paint change, or alongside one. |
| Paint | The paint changed and nothing above names why. |

The `style` field explains changes and is never hashed. Phase 2 extended it:

- A diagnosticable value is described one level down
  (`RenderDecoratedBox.decoration.color`).
- Text spans' styles are described (`RenderParagraph.text.style.fontWeight`).
- The widget that created each render object is described too, because some
  render objects report none of their paint parameters. For example, the
  private render object behind `ColoredBox` reports no colour, but
  `ColoredBox.color` names it.
- Render objects that draw nothing and only place their children are described
  under a `layout.` prefix (`layout.RenderPadding.padding`). Their properties
  explain layout, not style.
- The framework widgets between a component and each of its render objects
  are described once each (`Switch.value: on`). A state is often held by a
  widget whose render object does not report it. Render object widgets are
  described with their own render object, and parent data widgets
  (`Positioned`, `Expanded`) count as layout.
- The fingerprint of each image a render object drew is recorded as
  `<type>.images`, which the diff reads as content.
- Semantics, pointer and scroll-position objects are left out, along with
  sliver geometry and child delegates. Semantics has its own field. A scroll
  position's description includes the viewport size, and sliver geometry is
  the sliver's size, both outputs of layout. The children a delegate
  describes are compared as components.
- A property whose value is a widget is left out, because its description
  includes the child's text.

Changing `style` changes no hash. It does change the bytes of every snapshot
file, so committed baselines must be re-recorded.

## Cascade grouping (spec: "Cascade attribution")

- **Shift group.** Components under one parent whose size is unchanged, whose
  own fields are unchanged apart from identity, and whose position moved by the
  same vector. Only the top-most moved components are members. Their
  descendants that moved with them are counted.
- **Candidate cause.** A component earlier in layout order under that parent,
  or the parent itself, that was added, removed, resized or restyled. Each
  candidate is named by its root cause.
- **One candidate** gives a certain root cause, and the group becomes a
  consequence line under that change. **Several candidates** give "possible
  causes". **None** gives "cause unknown, needs review", flagged.
- **Upward growth.** A parent whose size changed by the same amount as exactly
  one changed child is that child's consequence, and chains fold to the
  deepest cause.
  - Interpretation (2026-10-10, at Sagar's ask to fold a parent's resize
    under its cause): "the same amount" is per axis.
  - A parent whose own layout properties did not change matches a child when,
    on each axis where the parent's size changed, it changed by the child's
    amount.
  - For example, a button whose padding grew by 1 grows 2x2. Its card grows
    0x2, because a wider sibling holds the card's width.

## Policy (spec: Policy and verdicts)

- The rules file is `touchstone.rules` at the package root, or the file given
  with `--rules`. One rule per line, and `#` starts a comment:
  - `pass <component> <change type>`
  - `forbid <component or *> <change type or *>`
- Declared expectations use the same form with `expect` lines, in the file
  given with `--expect`. When any are given, a visible change outside them
  fails.
- A component is named by its type, its id segment (`AppButton#submit`) or the
  end of its full id.
- The parser rejects these rules:
  - a pass or expect rule with `*`;
  - any rule with more than three words, so a rule cannot carry a size or
    tolerance;
  - an unknown change type.
- A pass rule passes a change only when nothing else is folded under it. A
  rule written for a component's paint does not pass the shift it caused.
- An input change (theme, locale, state, the dynamic list) makes the verdict
  needs-review.

## Report wording

After Sagar's A6 review found the catalog reports hard to read, each line
carries a change's short wording (`lib/src/diff/summary.dart`). The spec's
illustrative line, `Style OrderButton#submit background: brand.primary ->
brand.accent`, has this shape.

- Fields that changed to the same value are one entry, named by the field a
  developer is likeliest to recognise: a public widget's over a render
  object's or a private one's, then the shortest. The rest are counted:
  `Material.color: #1F1B1B21 -> brand.accent (and 4 more fields)`.
- A colour is written as its token, or as `#AARRGGBB` when it has none or both
  sides have the same token. Colours outside sRGB are left as captured.
- When a value is a constructor call and one named argument changed, only that
  argument is written: `Container.bg.color: #1F1E8E3E -> #1F1E8E3F`.
- The same change on several instances of one component, with the same
  consequences, is one line (`PriceLabel in 12 places`) followed by an `at:`
  line naming every instance.

`Change.detail` keeps the full wording and `Change.fields` every changed
field, and the snapshot file diff shows every field. Change types, verdicts
and grouping do not depend on the wording.

## Commands

- `dart run touchstone:review [--base <ref>] [--rules <file>] [--expect <file>] [--images]`
  compares every `.snapshot` file with its version at the base ref. It prints
  the summary line, then an overview, then each snapshot's report, and the
  summary line again last. The exit code is 0 for pass, 1 for fail and 2 for
  needs-review. A new or removed snapshot file is needs-review.
- The overview lists every distinct change once, so a reviewer can decide
  from it and open a snapshot's report only for detail
  ([expectations](../phase3/review_overview_expectations.md)):
  - unexplained items first, as the default policy flags them;
  - causes shared by more than one snapshot, such as a token;
  - every other change, one line per change type, component type and
    values, with the snapshot it is in or how many. A layout change is
    listed by what changed (a padding), not by its new size, which differs
    with the screen. Long values are cut; the report has them whole.
- `--images` adds the spec's review crops: before, after and diff images of
  each changed component, in `build/touchstone/review/` with an `index.html`.
  - It runs the tests in render mode (`TOUCHSTONE_RENDER_DIR`), where
    `expectSnapshot` writes the view's pixels and compares nothing. It runs
    them once in the working tree and once in a temporary git worktree at the
    base.
  - Only snapshots that need review or fail are rendered.
  - Each crop is the component's bounds before and after, joined, plus 8
    logical pixels.
  - In the diff image, changed pixels are red. Items on the same area share
    one set of crops, and a semantics item says it has no pixels.
  - Crops never change the verdict or the exit code.
  - In CI, upload the folder so reviewers can open it from the checks. The
    checkout needs the base ref, so use `fetch-depth: 0`:
    ```yaml
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0
    - run: dart run touchstone:review --base origin/${{ github.base_ref }} --images
    - uses: actions/upload-artifact@v4
      if: always()
      with:
        name: touchstone-review
        path: build/touchstone/review/
    ```
- `dart run touchstone:update [--images] [flutter test arguments]` runs
  `flutter test --update-goldens`. That rewrites a baseline only after the
  determinism gate passes, and prints each rewritten snapshot's change report.
  The command then prints what review will show against HEAD; with
  `--images`, it also writes that review's crops.
- A failing `expectSnapshot` writes the after crop of each changed component
  to `failures/<snapshot id>/` beside the test, as golden tests do, and lists
  the files in the message. This is an amendment to the spec's "A test
  fails", agreed with Sagar on 2026-10-10. The baseline keeps no pixels, so
  before and diff images come from `dart run touchstone:update --images`.
- The spec's "scoped update" (accepting only style changes on one component) is
  marked "Proposed" in the spec and is not built.

## Capture changes made in Phase 2

The catalog runs found three capture properties that kept the diff from
working as the spec describes, the A5 amendment added a fourth field, and the
A6 review found a fifth.
Each is a change to what is hashed, so committed baselines are re-recorded
on macOS.

1. **Child markers carry an index, not an id** (interpretation 1 below).
2. **A move alone keeps a pixel-hashed paint.**
   - An opaque node's paint ends with the pixel hash of its region. Phase 1
     wrote that region in global coordinates, so a node that only moved
     changed its paint.
   - A shift group needs "paint unchanged", so every button and row with a
     rounded shape broke the cascade into one unexplained paint per
     component.
   - The region is now written relative to the node's own origin. The pixels
     are still read from the same place, and the position is the node's
     bounds. A node whose transform could not be verified keeps global
     coordinates.
3. **Layout-neutral wrappers leave no trace.**
   - A repaint boundary's plain offset layer recorded `composite(Offset)`.
     That layer only places the child, which the child's offset already
     records, so the command is no longer written.
   - A component's render object that draws nothing and holds one child at
     its own origin is flattened out of the paint text.
   - The spec's no-op "wrap in a layout-neutral widget" then leaves the
     snapshot as it was (A5). The fixture suite and the capture-gap
     regression tests pass unchanged.

4. **Each node records its flattened output** (`flat`, added with the A5
   amendment). It hashes the subtree's paint as if it were one component,
   and the subtree's semantics in semantics tree order. It is a detection
   field, so it feeds the subtree hash. The fields it is built from are the
   same ones the paint and semantics hashes cover. See
   [schema_v1.md](../schema_v1.md).

5. **A node that drew only outside its clip hashes no pixels.** Found in the
   A6 review (generated seed 945). The last watchlist row is cut off by the
   viewport, and its bottom border is a path drawn below the visible area.
   Nothing it drew was inside its clip, and the region fell back to the
   clip it was given, which is the whole list. Any change in another row
   then changed this row's paint, reported as "pixel hash changed". Such a
   node now writes `pixels(none)`: no visible pixel of its can change. A
   node that drew nothing at all keeps the fallback, since an effect with
   no geometry can reach anywhere in its clip.

## Interpretations

Each of these is a choice the spec leaves open, or a small addition. None
changes a gate or a definition.

1. **Child markers carry an index, not an id.**
   - The spec says a child component "leaves a marker instead of its
     commands". Phase 1 wrote the child's id in the marker.
   - So any id change also changed the parent's paint hash, and an identity
     change could never be info only, as the spec's verdict table requires.
   - The marker now holds the child's index among the component's children
     (`comp(2)`).
   - Paint order is still recorded. Children are listed in the snapshot in
     order, and when paint order differs from child order, the markers record
     it. `test/snapshot_test.dart` checks both cases, including a `Flow` that
     paints in reverse.
   - This changes paint hashes, so baselines are re-recorded.
2. **A resized box's paint follows its size.** When a component's size changed
   and its paint changed with no style or content change, the paint change is
   a consequence of the Layout change, not a separate unexplained Paint.
3. **Layout inside a component.** When a component keeps its bounds but a
   render object inside it that only places children changed (padding,
   alignment, a size box), the change is Layout with the detail
   `inside: ...`. The spec defines Layout as "Bounds changed". Here the bounds
   of framework children inside the component changed.
4. **Reordered and moved components are candidate causes.**
   - The spec's list of candidates is added, removed, resized or restyled.
   - When two siblings swap, one is reported Reordered and the other only
     shifts. Under the spec's list, that shift would be "cause unknown".
   - Reordered and moved components were added as candidates, so the shift
     becomes a consequence of the reorder. This is a candidate-set extension,
     so it is listed for review.
5. **A parent's paint where its children changed.**
   - A parent's own paint records where its framework children sit, and the
     paint order of its child components.
   - When a component's only change is unexplained Paint, and its direct
     children were added, removed, reordered, resized or shifted, that paint
     change is folded under the children's single root cause, when there is
     one.
   - The consequence line says "not verified: paint is compared by hash".
6. **The parent's wrappers come and go with a child.**
   - Adding a child to a list adds framework render objects to the parent
     component: a keep-alive, an indexed semantics wrapper, a divider drawn
     per child.
   - A parent's style change, or layout change inside it at the same size,
     in which every property only appeared or disappeared, is folded under
     the one child added or removed beside it. The consequence line says
     "(came or went with the child)".
   - Without the fold, the parent becomes a second candidate cause of the
     shift, and no single cause can be named.
7. **The shift group's ancestor did not move.**
   - The spec groups components "under a common ancestor".
   - The group's ancestor is the nearest one that did not itself move by the
     group's vector.
   - A row that moved with its children but also changed (clipped at the
     viewport's edge) is then not where its children's shift is attributed.
     The shift is attributed to whatever moved the row.
8. **Test-time verdict.**
   - At test time any difference is a failure. The report is printed with the
     verdict `fail`, and the default policy is not applied.
   - The spec's "Pass, with identity changes listed as info" applies at review
     time. A refactor (an extracted, inlined or renamed widget, or a renamed
     id) still needs its baseline updated, because the file's bytes changed.
     The spec's verdict table makes any difference from the committed
     baseline a fail. Review then shows the update as identity changes only,
     which pass.
