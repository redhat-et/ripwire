### Added — an opt-in check of the symbol before the first edit of a session

With `first_edit=1` in `~/.ripwire/meter.conf` (or `RIPWIRE_FIRST_EDIT=1`), `hooks/ripwire-nudge.sh` adds context the first time a session edits an existing source file (Edit, Write or MultiEdit). The context is a short `--edit-check` of the definition the edit touches. It gives the contract status, the callers (any call site that provably no longer fits is flagged), and the tests that reach the symbol (`--affected`). When an Edit's `old_string` sits inside one definition, the status is a preview of the pending bytes (`--edit-payload --dry-run`), so an edit that adds a parameter reads `status=contract-change` before anything is written. A Write, a MultiEdit, or a preview the binary refuses gets the check of the current tree, and the text says which one it is.

- It is off by default. An unconfigured install behaves exactly as before, so the live primer A/B is unchanged.
- It runs once per session. A non-source file, a missing file and a new file do not use up the check.
- It has a hard deadline: 2000 ms by default, set by `RIPWIRE_FIRST_EDIT_MS`. The check runs in its own process group. One watchdog (a single `sleep`, then one kill of that group) stops it at the deadline. The edit is never held up.
- The plain check comes first. The current-tree check and the tests are finished and saved before the preview starts, because the preview can take much longer on a large file (15.36 s on `src/graph.h`). If the deadline falls inside the preview, the agent still gets the plain check, with a "preview did not finish" note (`nudge=first-edit-plain`). Only a deadline that falls before the plain check finishes gives the one `skipped: timeout` line.
- Its output is at most 1536 B: two definitions, five callers each and three tests. A cut is disclosed.
- It never returns a permission decision. The `(15)` sweep now includes an Edit payload with the check opted in, and PD5 requires the hook to speak on it.
- When it is on, it follows the meter arms. The treatment arm speaks. The control arm stays silent and logs the same moment as `nudge=first-edit-control`. Delivered rows read `first-edit` or `first-edit-plain` (both `nudged=1`), `first-edit-timeout` or `first-edit-nosym`.
- The Codex wrapper (`ripwire-codex-nudge.sh`) carries the same text.
- It sees only structured edits. A first change made through the shell (`sed -i`, a redirect) gets no check.

The idea comes from Patel et al., *PAUSE* (arXiv 2610.29870), and Varun, *Before the First Edit?* (arXiv 2610.35992). Gate: `test/hookcheck.sh` section (16), arms FE1–FE9.
