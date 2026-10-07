# Touchstone

Structured UI snapshots for Flutter widget tests. Instead of comparing images,
Touchstone records each component's tree, geometry, style, semantics and paint
commands, hashes them, and reports a failure as a typed change on a named
component.

> **Experimental.** Touchstone is in Phase 0 of five and is not published. Do
> not rely on it yet. Each phase ends at a measured gate, recorded in the
> [assumption register](doc/assumption_register.md).

## Gates

| Phase | Exit gate | Status |
| --- | --- | --- |
| 0. Feasibility spikes | A decision per node kind (recorded paint or pixel hash); 0 capture gaps on fixtures | Met on Linux after review fixes, 2026-10-07; awaiting approval |
| 1. Capture | 0 differing snapshots in 1,000 repeats per OS; schema maps to web | Not passed |
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
| `lib/src/audit` | The pixel oracle |
| `corpus/fixture_app` | Fixture screens and the verification harness |
| `doc/assumption_register.md` | Every assumption, its experiment and its data |

## Running the checks

```sh
flutter test                               # unit tests
cd corpus/fixture_app && flutter test      # Phase 0 harness (writes build/phase0/) and regression cases
```

Requires Flutter 3.47 or later.

## Licence

MIT. See [LICENSE](LICENSE).
