### Added — an opt-in SubagentStart primer, and the two-line subagent brief (lane AR1)

No ripwire routing reached a subagent. SessionStart does not fire for one, the prompt router runs on the parent side,
and the PreToolUse advice that does fire inside subagents was retired on 2026-09-02. In the 83 subagents of one
measured orchestrator session, none received any hook output. One had a ripwire navigation call among its first
five tool calls. The generic guidance (CLAUDE.md, MCP instructions, deferred tools) was present and not acted on.

- `skills/install.sh --hook-subagent-primer` registers `hooks/ripwire-subagent-primer.sh` on `SubagentStart`. It
  adds ~470 B to each new subagent's context: orient first with `ripwire <dir> --for="…" --legend=compact`, and run
  `--quality-delta --legend=compact` then `--test-gate` before calling it done. It cannot block a subagent. It is
  silent outside a git work tree or without ripwire. `RIPWIRE_SUBAGENT_PRIMER=0` turns it off, and `=auto`
  randomizes per subagent. One row per subagent start goes to `~/.ripwire/subagent_primer.jsonl` (ids and arm, never
  text), and `RIPWIRE_SUBAGENT_METER=0` stops it. The plain `--hook` does not install this hook.
- `skills/ripwire-orient/subagent-brief.md` has the same two lines for an orchestrator to paste into every brief.
  The router's fan-out moment points to it.
- `docs/EVALS.md` pre-registers the live A/B: plain brief, hook, or brief lines; 16 tasks × 3 arms, paired by task,
  with keep, move and remove bands. It has not been run.

Gate: `test/subagentprimercheck.sh`.
