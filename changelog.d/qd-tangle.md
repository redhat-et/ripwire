### Added — `--quality-delta` reports `tangle`, the thirteenth kind, with a best-since-tag ratchet and an `<improved>` section

A long function whose nesting goes past 3, whose deep regions take a growing share, or whose steering locals (a
primitive set in one step and read by a branch 10 or more statements later) multiply, scores a tangle: T from those
three inputs, S = T x log2(lines / 50), so a function of 50 lines or fewer scores 0 and a long orchestrator of named
steps scores 0 too. The row is report-only (always `sev="minor"`) and carries `why=` (the inputs that rose), `fix=`
(the shape the rise calls for, with lines) and `locals=` (the steering locals); `--metrics` gains `steer=` and
`tangle=`. Short arms of a 4+-arm switch or else-if chain are left out of the deep share, so a flat dispatcher reads
flat. A function above its best since the last tag gets `ratchet="TAG"` (the history is read on the first-parent
line, at most 512 versions; a ref-pair range reads no history and gets no ratchet), and an `<improved>` section (JSON
`"improved"`) lists what the change made better, never as a row and never gating. Measured on 44 hand labels across
ripwire, tmux, textual and envoy: AUC 0.986 for S (0.728 for the cx metric, 0.882 for ccx). The ingest
cache moves to 54 and the warm snapshot to 4 (the definition record carries the steering byte), so both rebuild once.
