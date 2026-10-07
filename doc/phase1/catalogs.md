# Mutation and no-op catalogs on the catalogue

The spec's mutation catalog and no-op refactor catalog, as source edits on the
catalogue app ([catalogs.dart](../../corpus/catalogue_app/tool/catalogs.dart)).
Each edit is applied, the listed scenes are captured with the oracle (whole-view
pixels and the semantics tree), and the source is restored
([run_catalogs.dart](../../corpus/catalogue_app/tool/run_catalogs.dart)).
Expected oracle results were written before the run. Data: [catalogs.json](catalogs.json).

The gates on these catalogs (0 missed, 0 fail verdicts on no-ops, attribution)
are Phase 2 gates, because verdicts need the diff engine. Phase 1 records what
the snapshot layer sees.

## Mutations: 17 edits, 0 missed

| Entry | Kind | Oracle expected | Oracle saw | Snapshot changed | Missed | Lands on the edited component |
| --- | --- | --- | --- | --- | --- | --- |
| colour-token | colour or token | pixels | pixels | yes | no | yes |
| text | text | pixels | pixels | yes | no | yes |
| padding-1px | padding by 1 px | pixels | pixels | yes | no | yes |
| size | size | pixels | pixels | yes | no | yes |
| widget-added | widget added | pixels | pixels | yes | no | yes |
| widget-removed | widget removed | pixels | pixels | yes | no | yes |
| widget-reordered | widget reordered | pixels | pixels | yes | no | yes |
| opacity | opacity | pixels | pixels | yes | no | yes |
| clip | clip | pixels | pixels | yes | no | yes |
| font-weight | font weight | none | none | yes | no | yes |
| icon | icon | pixels | none | yes | no | yes |
| image | image | pixels | pixels | yes | no | yes |
| enabled-state | enabled state | pixels | pixels | yes | no | yes |
| selected-state | selected state | pixels | pixels | yes | no | yes |
| semantics-label | semantics label | semantics | semantics | yes | no | yes |
| custom-painter | CustomPainter output | pixels | pixels | yes | no | yes |
| theme | theme | pixels | pixels | yes | no | n/a |

- Paint order is not in this catalog: levels 1 to 3 have no overlapping
  sibling components. The fixture app's paint-order mutation covers it.
- **Expectation wrong: icon.** Changing `Icons.language` to `Icons.translate`
  was expected to change pixels; it does not, because icon fonts are not
  loaded in widget tests and every glyph is drawn the same. The snapshot
  still changes (the code point is recorded). The coverage limit now says
  so. Per the register's rule the expectation is recorded as wrong, not
  edited.
- Font weight is invisible to the oracle for the same reason (the FlutterTest
  font) and was expected to be; the snapshot sees it.
- "Lands on the edited component" means the edited component is among the
  nodes whose own paint or semantics changed, or that were added or removed.
  The first differing node in tree order is often the parent screen, because
  a framework widget the screen owns (a Divider) moves. Grouping those
  consequences under one cause is Phase 2 work (A8).

## No-op refactors: pixels and semantics identical in all 6

| Entry | Kind | Oracle changed | Snapshot changed | Node changes |
| --- | --- | --- | --- | --- |
| extract-widget | extract a widget | no | yes | 12 added, 12 paint+style |
| inline-widget | inline a widget | no | yes | 7 paint+style, 7 removed |
| wrap-layout-neutral | wrap in a layout-neutral widget | no | yes | 13 paint |
| add-const | add const | no | no | identical |
| stateless-to-stateful | convert stateless to stateful | no | no | identical |
| rename-class | rename a class | no | yes | 12 added, 12 paint, 12 removed |

What Phase 2 has to turn into a pass:

- Extract, inline and rename change identity: a component appears or
  disappears, and the parent's paint changes because commands move between
  the parent and the new child. The paint is the same once child markers are
  expanded. This is A5 territory (second matching pass).
- Wrapping in a `RepaintBoundary` changes the parent's paint text: a composite
  step and a new coordinate origin for what is inside, with identical pixels.
  Either the diff treats this as neutral or the paint text elides pass-through
  render objects. Recorded as an open point in [schema_v1.md](../schema_v1.md).
- Adding `const` and converting stateless to stateful produce byte-identical
  snapshots.
