### Added — `--quality-delta` names a dropped I/O or child status (`defect="unchecked-status"`)

A fifth defect-shape facet reports, as a minor row that never gates, a status the change drops: in C/C++ a
statement-level `pclose`, `rename`, `write`, `system`, `fflush` (not of stdout/stderr), `waitpid` whose status
nothing reads, and `fclose`/`close` of a stream or fd the function wrote (plain, `std::`, `os::` or `rw::os::`); in
Python `subprocess.run` without `check=` whose result is dropped or read only for its output, `subprocess.call` and
`os.system`. A `(void)` cast, `check=` and a cleanup inside a failed write's branch say "decided" and give no row. The
row's `p=` is the dropped call's line and its new `call=` attribute names the call (XML, `--json` and MCP). Replaying
three fix commits backwards gives their rows (3 of 3); a 20-site hand-check on tmux, code-review-graph and this tree
found 20 of 20 drops real and 16 worth a check. Go `_ = f()` and Rust `let _ = f()` stay out, as in error-masking.
The quality snapshot scheme moves to 37 (qd-unhandled-arm, later in the same release, takes it to 38), so an older snapshot cache is rebuilt once; the legend dictionary moves to
`dictv=ff6a8ec8438b7fe0 entries=1176` (with the other quality-delta changes in this release).
