# Briefing a subagent: the three moments to paste

A subagent starts with an empty context and your brief. It gets no SessionStart primer and no prompt router of its
own, and the generic guidance it does inherit (CLAUDE.md, the MCP server's instructions, deferred ripwire tools)
was in 81 of 83 subagent contexts in one measured orchestrator session. Those subagents still oriented with reads
(69% of orientation tokens) and grep. A median of one ripwire navigation call came before the first edit, and 12 of
25 implementers made none (lane SUB1, 2026-11-19). What changes behaviour is a short, specific instruction in the
brief itself: in stored sessions an implementer's first source action was ripwire in 5% of lanes whose brief said
nothing (n=369) and in 34-39% of lanes whose brief carried the routing (n=38, n=66), and a verification verb the
brief NAMED was run in 90% of lanes against 47% unnamed (lane RO1, 2026-11-21, observational; no token saving shown).

**Put this block in every brief that reads source.** It is the block `ripwire wrap claude` prints, byte for byte.
Fill in `<dir>`. Leave the task text to the subagent. A lane that reads no source (prose, counting stored results)
does not get it:

```text
ripwire is on PATH — before reading source, `ripwire <dir> --for="<task>"`, Read its ranges in one turn; before the first edit, `--expand=SYM --legend=compact`, `--callers=SYM --legend=compact` or `--impact=SYM --legend=compact`; before reporting done, commit, then `--quality-delta=BASE..HEAD --legend=compact` and `--test-gate --legend=compact`.
```

The three moments, each with its call:

1. **Before reading source:** `ripwire <dir> --for="<task>"`. Paste paths and symbols from the brief verbatim into
   the task; then read every range it lists (`path:L-E`, and the page's `<act read=>`) in ONE turn of parallel
   ranged Reads, not one per turn and not whole files, and search only for what it marks missing.
2. **Before the first edit:** `--expand=SYM --legend=compact` for the body, `--callers=SYM --legend=compact` for who
   calls it, or `--impact=SYM --legend=compact` for everything a change reaches.
3. **Before reporting done:** commit, then `--quality-delta=BASE..HEAD --legend=compact` and
   `--test-gate --legend=compact`, and run the gates it names. BASE is where the branch started.

- `<dir>` is the tree the subagent will change. For a worktree lane, that is the worktree, not the main checkout.
- `--for` page 1 named every file a commit later changed in 39 of 52 pilot tasks (SUB1). `--pack-task` did so in
  20 of 52, so for orientation use `--for`.
- The check runs on a committed range, after the last edit. `BASE..HEAD` sees a regression made in two steps
  that a working-tree diff against the last commit misses. A check followed by another edit proves nothing about
  that edit. Run `--quality-delta` before `--test-gate`: clean code that runs the wrong tests still regresses.
- Splitting one task across N subagents? Run `--pack-task="<task>" --partition=N` once and hand each subagent its
  slice (`partition-zoom.md`). Keep the block in each brief too.

**Not briefing by hand?** Two Claude Code `SubagentStart` hooks exist, and neither replaces the brief. Both add
context beside it, and context beside the brief is what the stored sessions show subagents not acting on.
`skills/install.sh --hook` registers a short routing note for the Explore and Plan subagents, the two built-in types
that do not load CLAUDE.md (`RIPWIRE_SUBAGENT_ROUTE=0` turns it off). `skills/install.sh --hook-subagent-primer`
registers the opt-in primer (`hooks/ripwire-subagent-primer.sh`): two steps, orient and check, for every subagent
type; `RIPWIRE_SUBAGENT_PRIMER=0` turns it off and `auto` randomizes per subagent for its registered A/B. Write the
block into the brief either way.

**One page instead of the block alone:** `ripwire <dir> --brief="TASK" --legend=compact` prints a size-capped brief (3.5 / 5 / 7 KB by repo
size; `--brief-bytes=N` overrides) whose last section IS this block, after layout (`(skip)` marks vendored and generated
dirs), build and test commands quoted from manifests and docs (`none found` when there are none; never guessed), entry
points, the task's `--for` act ranges, edges, where-else and convention headings. Paste it under the task line. MCP: `brief`.
