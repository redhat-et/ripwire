### Added — the `ripwire-locator` Claude Code subagent, and a main-thread sentence that routes code lookups to it (lane LC1)

In Claude Code every tool result stays in the main conversation and is sent again with each later request, so a
`--for` answer read in the main thread is paid for on every request after it. A subagent runs in its own context and
returns only its final report. The locator runs ripwire there and hands back a short list of ranges. No token saving
has been measured; a live A/B arm is specified separately and has not run.

- `skills/agents/ripwire-locator.md`: a Claude Code subagent definition. Given a task, it runs
  `ripwire <root> --for="<task>"`, reads the listed ranges in one turn of parallel ranged Reads, makes at most one
  `--expand` or `--callers` follow-up (Grep/Glob only for a name ripwire cannot place), and returns only `EDIT` /
  `READ path:start-end symbol — why` lines plus one `MISSING` line, at most 12 lines and about 300 tokens. Its tools
  are `Bash, Read, Grep, Glob`: it cannot spawn another subagent and cannot edit. It sets no `model`, so it runs on the
  main conversation's model. It sets `omitClaudeMd: true`, which Claude Code before v2.1.271 ignores. The description
  is 323 B and the prompt body 1,543 B.
- `skills/install.sh` (Claude) installs it into `${CLAUDE_CONFIG_DIR:-~/.claude}/agents/` as a symlink into the
  checkout, or as a copy where a link does not take. A file already at that path that is not ripwire's is kept and
  reported. `--codex`, `--hermes`, `--openclaw` and an explicit path install no agent. A checkout or release without the
  file installs its skills as before. The release and Windows packages now carry `skills/agents/`.
  `--no-locator-agent`, or `RIPWIRE_NO_LOCATOR_AGENT=1` in the environment, leaves it out; the curl installers pass the
  variable through when they activate the Claude skills. A copy installed earlier is left in place.
- `ripwire wrap claude`: the orient line of the paste block (and so the SessionStart primer, which re-prints it) ends
  with one 177 B sentence: "Main thread: for a code lookup, delegate to the `ripwire-locator` subagent (when installed)
  and ask it for edit ranges; run a full `--for` here only when you need the whole map." The block stays 20 lines; no
  other agent's recipe changes. The three-moment brief block and the SubagentStart note do not carry it, because they
  address subagents. `RIPWIRE_NO_LOCATOR_ROUTE=1` drops the sentence and prints the previous bytes exactly (the A/B
  handle).
- `skills/ripwire-orient/SKILL.md` says the same in three lines.

Gate: `test/locatoragentcheck.sh`.
