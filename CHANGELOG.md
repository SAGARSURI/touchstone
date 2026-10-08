## 0.0.1-dev.0 (unreleased)

* Phase 0 feasibility spikes: per-node paint recorder, fingerprints for paths,
  images and text, pixel oracle, fixture app and Phase 0 harness.
* Phase 0 review fixes: opaque nodes are pixel-hashed over every pixel their
  paint can reach rather than their paint bounds; nodes that draw or clip with
  paths fall back to a pixel hash (A2 fails for paths); follower transforms,
  gradient text direction, exact mixed alignments and the device pixel ratio
  are recorded; ten review cases and four reach guards are regression tests.
* Phase 1 capture: schema v1 draft and its canonical text, the capture
  pipeline (components from the app's own classes, per-component paint,
  semantics, style), `expectSnapshot` with the determinism gate, capture at an
  explicitly pumped time, failures traced to the node they affect (animation,
  image load, wall clock), toolchain fingerprint with the renderer and the
  host OS and CPU architecture, coverage
  limits, and test helpers for a fixed clock, settling, images and seeds.
* Catalogue app levels 1 to 3 with 15 snapshots recorded on macOS, the mutation and
  no-op catalogs, a seeded render-level mutation generator with a pixel and
  semantics oracle, A13 and A3 experiments, the A14 web prototype, and the
  frozen catalogue history changes 1 to 6.
