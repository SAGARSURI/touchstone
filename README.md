# Touchstone

Structured UI snapshots for Flutter widget tests. Instead of comparing images,
Touchstone records each component's tree, geometry, style, semantics and paint
commands, hashes them, and reports a failure as a typed change on a named
component.

> **Experimental.** Touchstone is in Phase 1 of five and is not published. Do
> not rely on it yet. Each phase ends at a measured gate, recorded in the
> [assumption register](doc/assumption_register.md).

```dart
testWidgets('settings', (WidgetTester tester) async {
  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle();
  await expectSnapshot(tester, 'settings/default');
});
```

`flutter test --update-goldens` writes `snapshots/settings/default.snapshot`
beside the test, after three captures with every widget rebuilt in between
are byte-identical. The format is in [doc/schema_v1.md](doc/schema_v1.md).

## Gates

| Phase | Exit gate | Status |
| --- | --- | --- |
| 0. Feasibility spikes | A decision per node kind (recorded paint or pixel hash); 0 capture gaps on fixtures | Met on Linux after review fixes; approved 2026-10-07 |
| 1. Capture | 0 differing snapshots in 1,000 repeats per OS; schema maps to web | Schema maps to web (A14 passed); 1,000-repeat runs in CI ([a3-repeats](.github/workflows/a3.yml)); awaiting review |
| 2. Diff and policy | Every mutation and no-op gate | Not passed |
| 3. Catalogue verification, then release | 0 capture gaps on catalogue history; budgets met | Not passed |
| 4. CI savings | 30 days with 0 selection misses and 0 variant escapes | Not passed |

Gates not yet passed: missed changes on the mutation catalog, fail verdicts on
the no-op catalog, 1,000-repeat determinism per OS, attribution and root-cause
accuracy, capture gaps on catalogue history, selection misses, and generated
mutations.

## Layout

| Path | What |
| --- | --- |
| `lib/src/recorder` | The per-node paint recorder and fingerprints |
| `lib/src/snapshot` | Components, capture, schema v1, determinism gate, `expectSnapshot`, toolchain fingerprint |
| `lib/src/testing` | Helpers for a fixed clock, settling, preloaded images and seeded data |
| `lib/src/audit` | The pixel oracle |
| `corpus/fixture_app` | Fixture screens and the Phase 0 harness |
| `corpus/catalogue_app` | Catalogue levels 1 to 3, snapshot baselines, catalogs, generator, frozen history |
| `corpus/web_prototype` | Five fixture screens in HTML captured as schema v1 (A14) |
| `doc/assumption_register.md` | Every assumption, its experiment and its data |

## Running the checks

```sh
flutter test                               # unit tests, and the web snapshots parse as schema v1
cd corpus/fixture_app && flutter test      # Phase 0 harness (writes build/phase0/) and regression cases
cd corpus/catalogue_app && flutter test    # snapshots, A13, 100 generated mutations, A3 smoke, history
cd corpus/catalogue_app && dart run tool/run_catalogs.dart                   # mutation and no-op catalogs
cd corpus/catalogue_app && flutter test test/generated --dart-define=GEN_COUNT=10000
cd corpus/web_prototype && npm install && node capture.mjs                   # A14 web captures
```

Requires Flutter 3.47 or later.

## Licence

MIT. See [LICENSE](LICENSE).
