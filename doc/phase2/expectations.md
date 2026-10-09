# Phase 2 expectations, written before the diff engine

These are the expected results and the scoring rules for Phase 2's gates.
They were committed before any diff, matching, cascade or policy code
existed, and are not edited to match what the tool reports. An expectation
that turns out wrong is recorded as wrong in the results, as in Phase 1.

## Mutation catalog: component and change type

Gate (spec, Metrics and release gates): at least 99% correct component and
change type, and 0 missed changes.

Each entry in `corpus/catalogue_app/tool/catalogs.dart` now carries
`expectTypes`, the spec's change types (Added, Removed, Moved, Reordered,
Identity, Layout, Style, Content, Semantics, Paint) the report should give
the edited component.

| Entry | Component | Expected types |
| --- | --- | --- |
| colour-token | ChangeBadge | Style |
| text | SettingsTile | Content |
| padding-1px | SectionHeader | Layout, and a shift caused by it |
| size | SettingsIcon | Layout, no shift |
| widget-added | SettingsTile | Added, and a shift caused by it |
| widget-removed | SettingsTile | Removed, and a shift caused by it |
| widget-reordered | SettingsTile | Reordered |
| opacity | StatusView | Style |
| clip | HeaderImage | Style |
| font-weight | PriceLabel | Style |
| icon | SettingsIcon | Content |
| image | HeaderImage | Content |
| enabled-state | AppButton | Style and Semantics |
| selected-state | SettingsTile | Style and Semantics |
| semantics-label | HeaderImage | Semantics |
| custom-painter | _Spinner | Paint (unexplained) |
| theme | (screen components) | Style |

Scoring:
- **Correct** when the report has a top-level item (one that is not folded
  under a cause) on a component of the expected type that carries every
  expected change type. For `theme`, which has no single component, correct
  when every top-level item is a Style change.
- **Missed** when the pixel or semantics oracle saw a change and the verdict
  is pass.
- Other top-level items in the same report are counted and listed as extra
  items. They do not make an entry incorrect, but they are reported, because
  each one is something a reviewer has to read.

## No-op refactor catalog (A5)

Gate: 0 fail verdicts. A5's pass criterion is stricter: each refactor yields
no change, or info-level identity changes only, and so a pass verdict.

The six entries are unchanged from Phase 1. Phase 1 found that four of them
change the snapshot (extract, inline, wrap in a layout-neutral widget, rename a
class), so A5 is expected to be tested hard by these four. A needs-review
verdict on a no-op is not a gate failure, but it is a false alarm under the
spec's definition and is counted as one.

## Cascade mutations (A8)

Gate: at least 95% correct root cause on cascade mutations, and 0 wrong root
causes stated as certain.

The new `cascades` list in `catalogs.dart` has 15 entries: insert, remove and
resize near the start of columns (the sign-in form, the text styles screen),
lists (settings, buttons, the lazy watchlist) and a stack. The catalogue has
no stack, so `test/support/cascade_stack.dart` adds one built from catalogue
components; it is an experiment scene and never a baseline. The catalog
entries `padding-1px`, `size`, `widget-added` and `widget-removed` are scored
the same way.

Each entry names the root-cause component (`expectNode`), its change type
(`expectTypes`) and whether other components should shift (`expectShift`).

Scoring:
- **Correct root cause** when `expectShift` is true and every shift group in
  the report names a component of the expected type as its single root cause,
  or when `expectShift` is false and the report has no shift group.
- **Wrong root cause stated as certain** when any shift group names a single
  root cause that is not the expected component. This is a gate failure on
  its own.
- A group reported with several possible causes, or with no cause, is not
  correct and not a wrong certain claim.

## Generated mutations

Gate: 0 missed in 10,000 generated mutations, now measured on verdicts: a
miss is a pass verdict when the pixel or semantics oracle saw a change.

Also reported, with no gate: whether the mutated render object's owner is a
top-level item or the cause of a group, and whether its change type is one of
the types accepted for the mutation kind:

| Mutation kind | Accepted types |
| --- | --- |
| decoration colour, decoration radius, text colour, font weight, shape colour, opacity, clip radius | Style |
| text | Content |
| padding 1px, size 1px, flex alignment, transform | Layout or Style |
| image (invertColors) | Content or Style |
| custom painter removed | Paint or Style |
| semantics label | Semantics |
| reorder children | any type |

Generated mutations that produce a shift group also count toward A8: the
group should name the mutated component, or the component it sits in, as its
single root cause.
