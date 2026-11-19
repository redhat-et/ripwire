# Briefing a subagent: the two lines to paste

A subagent starts with an empty context and your brief. It gets no SessionStart primer and no prompt router of its
own, and the generic guidance it does inherit (CLAUDE.md, the MCP server's instructions, deferred ripwire tools)
was in 81 of 83 subagent contexts in one measured orchestrator session. Those subagents still oriented with reads
(69% of orientation tokens) and grep. A median of one ripwire navigation call came before the first edit, and 12 of
25 implementers made none (lane SUB1, 2026-11-19). What changes behaviour is a short, specific instruction in the
brief itself.

**Put these two lines in every brief that will read or change code.** Fill in `<dir>`. Leave the task text to the
subagent:

```text
Orient first: run `ripwire <dir> --for="<your task in words; paste paths and symbols from this brief verbatim>" --legend=compact` and read only the files it ranks, before any grep or whole-file read.
Before you call it done: run `ripwire <dir> --quality-delta --legend=compact`, then `ripwire <dir> --test-gate`; fix what they flag, or say in your report why not.
```

- `<dir>` is the tree the subagent will change. For a worktree lane, that is the worktree, not the main checkout.
- `--for` page 1 named every file a commit later changed in 39 of 52 pilot tasks (SUB1). `--pack-task` did so in
  20 of 52, so for orientation use `--for`.
- Run `--quality-delta` before `--test-gate`. Clean code that runs the wrong tests still regresses.
- Splitting one task across N subagents? Run `--pack-task="<task>" --partition=N` once and hand each subagent its
  slice (`partition-zoom.md`). Keep the two lines in each brief too.

**Not briefing by hand?** `skills/install.sh --hook-subagent-primer` registers an opt-in Claude Code `SubagentStart`
hook (`hooks/ripwire-subagent-primer.sh`). It injects the same two steps into every subagent's context at spawn.
`RIPWIRE_SUBAGENT_PRIMER=0` turns it off. `auto` randomizes per subagent for the registered A/B. Whether the hook's
context works as well as the same lines in the brief is the question that A/B answers. Until it reports, write the
lines into the brief too.
