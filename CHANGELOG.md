## 0.0.1-dev.0 (unreleased)

* Phase 0 feasibility spikes: per-node paint recorder, fingerprints for paths,
  images and text, pixel oracle, fixture app and Phase 0 harness.
* Phase 0 review fixes: opaque nodes are pixel-hashed over every pixel their
  paint can reach rather than their paint bounds; nodes that draw or clip with
  paths fall back to a pixel hash (A2 fails for paths); follower transforms,
  gradient text direction, exact mixed alignments and the device pixel ratio
  are recorded; ten review cases and four reach guards are regression tests.
