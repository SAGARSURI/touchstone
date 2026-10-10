# Phase 3 step 6: A12 and change 10, written before the run

Written on 2026-10-09 and committed before migration runs on any release
pair. Plan step 6 in [plan.md](plan.md). A12 in the spec's assumption table:
"A Flutter upgrade can be absorbed without re-reviewing every baseline".
Test: capture on two consecutive stable releases and run the migration. Pass:
snapshots with identical pixels re-baseline automatically with the pixel proof
attached; the rest go to review. Fail fallback: pin the SDK per baseline set
and re-baseline with full review.

The releases are 3.47.6 (framework 5fc346839b, engine 692136cb65, Dart
3.13.5) and 3.47.7 (framework abaf9c5237, engine deb287481e, Dart 3.13.5),
as the plan's defaults say. Change 10 in
`corpus/catalogue_app/tool/history_phase3.dart` is this upgrade.

## How migration works

The spec says a toolchain mismatch is routed to migration and that
pixel-identical snapshots re-baseline automatically, but not where the old
pixels come from: a baseline holds hashes, not pixels. The default chosen
here keeps schema v1 as it is: the old pixels come from rendering again on
the old release.

1. **Prove, on the old release.** `flutter test
   --dart-define=TOUCHSTONE_MIGRATION=prove` runs each snapshot test as usual.
   A snapshot that matches its baseline also rasterizes the whole test view
   and writes a pending proof to `build/touchstone/migration/<id>.proof`: the
   toolchain, the baseline's root hash, the image size and its pixel digest.
   A snapshot that does not match its baseline fails as it does today, and
   gets no proof.
2. **Apply, on the new release.** `flutter test
   --dart-define=TOUCHSTONE_MIGRATION=apply` takes every snapshot whose
   baseline was recorded with another toolchain, runs the determinism gate,
   rasterizes the view the same way, and rewrites the baseline. Beside it, it
   writes `snapshots/<id>.migration`: both toolchains, both root hashes, the
   image size, both pixel digests, and whether the pixels are identical. With
   no pending proof that matches the old baseline, the file says so. The
   test passes either way; the outcome is decided in review.
3. **Review.** For a snapshot whose report is a migration, review reads the
   `.migration` file beside it. It passes when the file names the old and new
   baselines' toolchains and root hashes exactly and the pixels are
   identical, and says so with the digest. Every other migration needs
   review, with the reason: pixels differ, or no proof.
4. `dart run touchstone:migrate --from <old flutter executable> [flutter test
   arguments]` runs steps 1 and 2 and prints what review will show.

The alternative, a whole-view pixel digest stored in every snapshot so the
old release is not needed, adds a field the spec does not list. It is not
built.

## What runs

| Run | Baselines | Where |
| --- | --- | --- |
| macOS | The committed catalogue baselines, `test/snapshots_test.dart` | A workflow on `macos-latest` that proves on 3.47.6, applies on 3.47.7, and commits the rewritten baselines and `.migration` files to its branch |
| Linux | Baselines recorded on 3.47.6 in a scratch copy of the catalogue | This container |

Each run reports, per snapshot: pixels identical or not, whether the root
hash changed, and which node fields changed. Review runs against the
pre-migration commit.

## Expected results

1. **Every snapshot is routed to migration**, on both hosts: the framework
   and engine revisions are in the fingerprint, and both changed. No snapshot
   is diffed.
2. **Every snapshot has identical pixels on 3.47.6 and 3.47.7**, on both
   hosts, so all 41 re-baseline automatically and review passes them all.
   3.47.7 is a patch release; its engine change is not expected to touch
   Skia's software rasterizer in widget tests.
3. **Root hashes do not change** on most snapshots, since nothing in a patch
   release is expected to change layout, semantics or recorded paint. Where
   one does change with identical pixels, that is the case migration exists
   for, and it is listed with the fields that changed.
4. A12 holds if expectations 1 and 2 hold: no snapshot needed review. If some
   snapshots differ in pixels, A12 still holds if they, and only they, went
   to review with their difference stated; the share is reported.
