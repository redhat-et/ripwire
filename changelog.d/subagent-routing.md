### Added — routing for Claude Code subagents: a paste-ready brief block, a SubagentStart note, and an opt-in SubagentStart primer

No ripwire routing reached a subagent. SessionStart does not fire for one, the prompt router runs on the parent side,
the PreToolUse advice that does fire inside subagents was retired on 2026-09-02, and Claude Code's built-in Explore and
Plan subagents do not load CLAUDE.md, so the use-when block pasted there never reaches the agent that searches the
codebase. In the 83 subagents of one measured multi-agent session, none received any hook output, and one had a ripwire
navigation call among its first five tool calls; the generic guidance (CLAUDE.md, MCP instructions, deferred tools) was
present and not acted on. An observational study of stored sessions also shows that what a subagent acts on is its brief:
ripwire was the first source action in 5% of implementer sessions whose brief said nothing (n=369), in 34-39% of those
whose brief carried the routing (n=38, n=66), and in 6% (13 of 215) of those that had the protocol in CLAUDE.md and a
silent brief. No token saving is shown by any of it.

- **The brief block.** `ripwire wrap claude`: the paste block's parallel-agents line now ends with a three-moment block
  for the coordinating agent to copy into every subagent brief that reads source: `--for` before reading source;
  `--expand`, `--callers` or `--impact` before the first edit; commit, then `--quality-delta=BASE..HEAD` and `--test-gate`
  before reporting done. The block is 320 B. The paste block stays 20 lines and grows from 3,085 B to 3,485 B. It is a
  column of the agent table (`AgentTarget::subagentBrief`), set for Claude Code only; no other agent's recipe changes.
  `skills/ripwire-orient/subagent-brief.md` carries the same block, byte for byte, and the router's fan-out moment
  points to it.
- **The SubagentStart note.** `skills/install.sh --hook` (Claude) also registers `hooks/ripwire-nudge.sh --subagent-start`
  on `SubagentStart`. It adds a 348 B factual note (which call ranks files for a task, which prints one symbol, which names
  the tests) to each new Explore or Plan subagent. Every other subagent type loads CLAUDE.md and gets nothing.
  `RIPWIRE_SUBAGENT_ROUTE=0` turns it off and `=all` sends it to every type. It is silent without ripwire or jq on PATH and
  outside a git work tree. It does not follow the meter's arm: the subagents of a control-arm session get it too (the
  SessionStart primer's control-arm silence is unchanged). It writes no row and no file unless `RIPWIRE_SUBAGENT_ROUTE_LOG`
  names one. A machine that ran `--hook` before gains the entry on a re-run; a second run does not add a second entry. This
  note is ambient context, the kind the study above measured at 6%: a floor for the two agent types that get nothing today,
  not the lever. Whether Claude Code delivers it into the subagent's own context has not been run live.
  `ripwire --doctor --agent=claude` has a `claude-subagent-route` row (`installed`, `refs`, `events_ok`, `exec`, `jq`).
  Absent is `ok="1" installed="0"`. `claude-hooks` still counts its two nudge entries; the SubagentStart entry is not a third.
- **The opt-in primer.** `skills/install.sh --hook-subagent-primer` registers `hooks/ripwire-subagent-primer.sh` on
  `SubagentStart`. It adds ~660 B to each new subagent's context. It says to orient first with `ripwire <dir> --for="…"`.
  After the last edit and before reporting, it says to commit, run `--quality-delta=BASE..HEAD --legend=compact` and then
  `--test-gate --legend=compact`, and run the gates that names. A committed range catches a regression made in two steps.
  It cannot block a subagent. It is silent outside a git work tree or without ripwire. `RIPWIRE_SUBAGENT_PRIMER=0` turns
  it off, and `=auto` randomizes per subagent. One row per subagent start goes to `~/.ripwire/subagent_primer.jsonl` (ids
  and arm, never text), and `RIPWIRE_SUBAGENT_METER=0` stops it. The plain `--hook` does not install this hook. With both
  hooks registered, an Explore or Plan subagent receives both texts. `docs/EVALS.md` pre-registers the live A/B: plain
  brief, hook, or brief lines; 16 tasks × 3 arms, paired by task, with keep, move and remove bands. It has not been run.
- **A probe nothing installs.** `hooks/ripwire-nudge.sh --agent-brief` is a PreToolUse hook for the Agent/Task tool that
  returns `updatedInput` with the same block appended to the spawn prompt. Whether Claude Code applies `updatedInput` to an
  Agent call is not documented and has not been run live.

Gates: `test/subagentroutecheck.sh`, `test/subagentprimercheck.sh`.
