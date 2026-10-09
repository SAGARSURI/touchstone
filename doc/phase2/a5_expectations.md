# A5 flattened matching: expectations, written before the code

On 2026-10-09 Sagar chose to amend the spec's A5 fallback and build flattened
matching in Phase 2, after the first measurement found that extracting a
widget, inlining one and renaming a class each gave needs-review
([results.md](results.md)). These expectations are committed before any of
the code. They are scored exactly as written, and any that turn out wrong are
marked wrong, never edited.

## What will be built

- **A flattened output per node.** Capture records, for every component, a
  hash of its subtree's output with component boundaries removed. The paint
  is written as if the whole subtree were one component: child components'
  commands are written in place of their markers, at their paint offsets, and
  a render object that only passes its one child through is left out
  wherever it is. The semantics are the subtree's semantics nodes in
  semantics-tree order, whichever component owns each one. The field is used
  only for matching. It feeds no hash, because the paint hashes already cover
  every command in it.
- **Matching on output.** After the spec's second pass on type, bounds and
  paint hash, nodes still unpaired are paired when exactly one node on each
  side has the same bounds and flattened output, whatever its type. Under the
  same parent the pair is an Identity change, so a renamed class is reported
  as `Identity`, not a removal plus an addition.
- **Refactors inside an unchanged component.** When a component was added,
  removed or renamed inside a paired component whose bounds and flattened
  output are unchanged, every change in that component's subtree is reported
  as one Identity change on it, naming the components that came or went. The
  nearest such ancestor is used. Equal flattened output means the subtree
  draws the same commands and exposes the same semantics, so nothing in it is
  visible (A4).

## Expected results

### No-op refactor catalog

| Entry | Expected verdict | Expected report |
| --- | --- | --- |
| extract-widget | pass | One `Identity` item per `WatchRow` (12), naming the added `QuoteNames`. No other item. |
| inline-widget | pass | One `Identity` item per `SettingsTile` (7), naming the removed `SettingsIcon`. No other item. |
| rename-class | pass | One `Identity` item per avatar (12), `SymbolAvatar` to `TickerAvatar`. No other item. |
| wrap-layout-neutral | pass | No change, as before. |
| add-const | pass | No change, as before. |
| stateless-to-stateful | pass | No change, as before. |

A5's criterion, "no change or one info-level identity change" per refactor,
is read per component the refactor touched: one Identity line for each
instance of the edited widget.

### Mutation catalog and cascades

Unchanged from the accepted Phase 2 results: every entry needs-review, 32 of
32 correct component and type, 19 of 19 correct root causes, 0 wrong certain.
No mutation is reported as Identity.

### Generated mutations

- 0 missed in 10,000 at verdict level, as before.
- No mutation that changed pixels or semantics is reported as Identity only.
  That would be a miss, and a capture gap in the flattened output.
- The owner is named in every changed snapshot, as before.

### Adversarial unit tests

Each of these looks like a refactor but changes the output. Each must get
needs-review, with no Identity item covering the changed component:

1. Extract a widget and change a colour inside it.
2. Extract a widget that adds padding.
3. Rename a class and change its size.
4. Inline a widget whose semantics label differs.
5. Move a child into a new wrapper component that also clips it.
