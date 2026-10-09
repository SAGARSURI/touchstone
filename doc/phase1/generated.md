# Generated mutations (Phase 1)

Release gate: 0 misses in 10,000 generated mutations. Run on 2026-10-08 with
Flutter 3.47.6 on Linux x64, seeds 0 to 9,999, after the review fixes
(commit e719973) and the size-mutation fix below.

`test/generated/generated_mutations_test.dart` pumps a catalogue scene, applies
one seeded render-level mutation and compares the snapshot with an unmutated
capture. The pixel and semantics oracle is the ground truth: a mutation is
missed when the oracle changed and the snapshot did not.

**Result: 0 missed of 10,000.** 7,407 mutations changed pixels or semantics,
and every one changed the snapshot. 1,391 changed the snapshot but not the
oracle (a font weight under the test font, a reorder of identical boxes, a
transform or clip with no visible effect). 1,202 changed neither (an
alignment with nothing to move, a size the parent's tight constraints undo).

| Kind | Applied | Oracle changed | Snapshot changed | Snapshot only | Missed |
| --- | --- | --- | --- | --- | --- |
| custom painter removed | 251 | 122 | 251 | 129 | 0 |
| decoration colour | 223 | 76 | 193 | 117 | 0 |
| decoration radius | 148 | 68 | 141 | 73 | 0 |
| flex alignment | 396 | 83 | 83 | 0 | 0 |
| font weight | 1468 | 1002 | 1405 | 403 | 0 |
| image | 27 | 18 | 18 | 0 | 0 |
| opacity | 23 | 23 | 23 | 0 | 0 |
| padding 1px | 1528 | 1187 | 1260 | 73 | 0 |
| reorder children | 924 | 690 | 924 | 234 | 0 |
| semantics label | 140 | 140 | 140 | 0 | 0 |
| shape colour | 158 | 126 | 158 | 32 | 0 |
| size 1px | 1076 | 774 | 839 | 65 | 0 |
| text | 1423 | 1423 | 1423 | 0 | 0 |
| text colour | 1412 | 1311 | 1346 | 35 | 0 |
| transform | 803 | 364 | 594 | 230 | 0 |

## Attribution (A6 input, informative)

Of the 8,798 mutations that changed the snapshot, 8,751 (99.5%) changed a
field of the component that owns the mutated render object. The other 47 are
a padding or a fixed size owned by a screen (`SignInScreen`,
`TextStylesScreen`) whose only effect is to move the components below it:
only their bounds change. Naming the screen as the cause is the cascade
grouping that Phase 2 (A8) builds.

## A generator bug found and fixed

The first full run had 1,076 size mutations that never changed anything: the
mutator used `BoxConstraints.tighten`, which clamps the new size to the old
maximum. Those seeds were no-ops, so the 0 misses of that run did not cover
size changes. The mutator now sets the tight size directly, and this run is
the one recorded here; 774 of its size mutations change the oracle.
