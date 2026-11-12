### Fixed — `--exemplar` hedges an off-task pick, `--help-task` abstains with a next step, `--pattern` counts member calls

Three answers that were confident-wrong or ended with nothing to do next. Found by the Fable answer audit and confirmed by the Opus audit verify (2026-11-11).

- `--exemplar=TASK`: when the task matched the corpus but the role pick shares no word with the task or the names it matched (hono `'a middleware'` → `useState`), the pick now carries `low_confidence="1" off_task="1"`. The pick itself is unchanged. `test/exemplarconfcheck.sh` arm 5, with a positive arm where a real `middleware/` family is picked and not hedged.
- `--help-task`: an abstain carries `next="--for='<task>'"`, or `reason="system-event"` for a harness report. A recommend whose command stands on a plain word that the task names only after `of` reads `confidence="low"` (nushell `'… a pipeline of commands'` → `--expand='commands'` used to read high). `test/taskroutecheck.sh` HT-a/HT-b, with the corpus recommend count pinned so a route lost fails.
- `--pattern='f($X)'`: member and attribute calls (`obj.f(x)`, `self.f(x)`) whose called name is the pattern's are counted as `unmatched_member=N` with `next="--pattern='$O.f($X)'"`, through a per-grammar call-shape table (C, C++, Go, Rust, JS/TS, Python, C#). They are still not hits. textual `post_message($X)` read `hits="0"` with nothing else, and now adds `unmatched_member="173"`, which the next= pattern hits exactly. `test/patterncheck.sh` 7b.

The new compact readings move the session legend dictionary to `dictv=abedef5f1f52c7fb entries=1062` (docs/COMMANDS.md and the showcase capture are re-recorded).
