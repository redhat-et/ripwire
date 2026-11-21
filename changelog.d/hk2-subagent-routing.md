### Added — routing for Claude Code subagents: a paste-ready brief block and a SubagentStart note (lane HK2)

Claude Code's built-in Explore and Plan subagents do not load CLAUDE.md, so the use-when block pasted there never
reaches the agent that searches the codebase. Stored sessions (lane RO1, observational) also show that what a subagent
acts on is its brief: ripwire was the first source action in 5% of implementer lanes whose brief said nothing (n=369),
in 34-39% of lanes whose brief carried the routing (n=38, n=66), and in 6% (13 of 215) of lanes that had the protocol
in CLAUDE.md and a silent brief. No token saving is shown by any of it.

- `ripwire wrap claude`: the paste block's parallel-agents line now ends with a three-moment block for an orchestrator
  to copy into every subagent brief that reads source: `--for` before reading source; `--expand`, `--callers` or
  `--impact` before the first edit; commit, then `--quality-delta=BASE..HEAD` and `--test-gate` before reporting done.
  The block is 320 B. The paste block stays 20 lines and grows from 3,085 B to 3,485 B. It is a column of the agent
  table (`AgentTarget::subagentBrief`), set for Claude Code only; no other agent's recipe changes.
- `skills/install.sh --hook` (Claude) also registers `hooks/ripwire-nudge.sh --subagent-start` on `SubagentStart`. It
  adds a 348 B factual note (which call ranks files for a task, which prints one symbol, which names the tests) to
  each new Explore or Plan subagent. Every other subagent type loads CLAUDE.md and gets nothing.
  `RIPWIRE_SUBAGENT_ROUTE=0` turns it off and `=all` sends it to every type. It is silent without ripwire or jq on
  PATH, outside a git work tree, and in the meter's control arm. It writes no row and no file unless
  `RIPWIRE_SUBAGENT_ROUTE_LOG` names one. A machine that ran `--hook` before gains the entry on a re-run; a second run
  does not add a second entry. This note is ambient context, the kind RO1 measured at 6%: a floor for the two agent
  types that get nothing today, not the lever. Whether Claude Code delivers it into the subagent's own context has not
  been run live.
- `ripwire --doctor --agent=claude` has a `claude-subagent-route` row (`installed`, `refs`, `events_ok`, `exec`, `jq`).
  Absent is `ok="1" installed="0"`. `claude-hooks` still counts its two nudge entries; the SubagentStart entry is not
  a third.
- `hooks/ripwire-nudge.sh --agent-brief` is a probe arm that nothing installs: a PreToolUse hook for the Agent/Task
  tool that returns `updatedInput` with the same block appended to the spawn prompt. Whether Claude Code applies
  `updatedInput` to an Agent call is not documented and has not been run live.

The opt-in subagent primer (`--hook-subagent-primer`, lane AR1) is unchanged. With both hooks registered, an Explore or
Plan subagent receives both texts.

Gate: `test/subagentroutecheck.sh`.
