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
  host OS and CPU architecture, coverage limits, and test helpers for a fixed
  clock, settling, images and seeds.
* Catalogue app levels 1 to 3 with 15 snapshots recorded on macOS, the
  mutation and no-op catalogs, a seeded render-level mutation generator with
  a pixel and semantics oracle, A13 and A3 experiments, the A14 web
  prototype, and the frozen catalogue history changes 1 to 6.
* Phase 2 diff and policy: typed change report (added, removed, moved,
  reordered, identity, layout, style, content, semantics, unexplained paint)
  with the second matching pass and cascade grouping; the policy engine with
  project rules, declared expectations and the spec's limits on rules;
  `expectSnapshot` failures print the change report; dynamic components skip
  content comparison only; `dart run touchstone:review` and
  `dart run touchstone:update`.
* Phase 2 capture changes (baselines re-recorded): child component markers
  hold an index instead of an id; an opaque node's pixel region is written
  relative to its own origin, so a move alone keeps its paint; repaint
  boundaries and pass-through render objects leave no trace in paint; the
  style field describes nested values, text span styles, the framework
  widgets inside each component, drawn image fingerprints, and layout-only
  render objects under a `layout.` prefix.
* A5 flattened matching (spec amended 2026-10-09; baselines re-recorded): each
  node records `flat`, its subtree's output with component boundaries
  removed. Nodes still unmatched after the second pass are paired by bounds
  and flattened output, so a renamed class is an identity change, and a
  component added, removed or renamed inside a component whose bounds and
  flattened output are unchanged is one info-level identity change.
* Shorter change report, after the A6 review: fields that changed to the same
  value are one entry, colours are tokens or hex, a constructor call shows only
  its changed argument, and the same change on several instances of one
  component is one line naming every instance. `Change.detail` keeps the full
  wording.
* An opaque node that drew only outside its clip (a row cut off by the end
  of a list) hashes no pixels, instead of every pixel of its clip; changes
  elsewhere in the list no longer change its paint (baselines re-recorded).
