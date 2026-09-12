# Agent integration, verified live — one agent, one report, FAILs included

You are verifying that ripwire's published wiring for **one coding agent you actually use** works
against the real agent: **Cursor, Windsurf, Gemini CLI, opencode, or aider**. The deliverable is a
filled verification report — FAIL lines included — plus a fix, with a gate written red first, for
every recipe that fails.

Pick one agent. A report on one agent that someone really ran is worth more than a table of five
that nobody did.

Work in a git worktree, not the main checkout. Back up the agent's own config file before phase 2
touches it.

---

## Why it matters

`ripwire wrap <agent>` prints the configuration for nine agent names. The installers activate skills
for four of them. CI checks all of that **against the filesystem**: what the recipe prints, which
keys the JSON has, what the installer links. **Nothing in CI starts the agent.** Every sentence
about what Cursor, Windsurf, Gemini CLI, opencode or aider will *do* with that output is a claim
nobody in this repository has checked.

A wrong recipe is worse than none. `test/opencodewrapcheck.sh` says it best: the failure mode is not
a crash, but a config that "parses, installs, looks right, and silently does nothing". The user
believes they are wired, and the agent never calls the tool.

It has already happened once. [#48](https://github.com/redhat-et/ripwire/issues/48): someone running
opencode against ripwire 0.4.0 found that opencode rejected a tool with *"input_schema does not
support oneOf, allOf, or anyOf at the top level"*. No gate had seen it; one person with the real
agent did, and it was fixed. [#68](https://github.com/redhat-et/ripwire/issues/68) (openclaw) and
[#69](https://github.com/redhat-et/ripwire/issues/69) (Hermes) already ask for this check on two
agents. As #68 puts it: **a FAIL is the useful outcome.** It is the only way the project learns that
a recipe it publishes does not work.

---

## Background — what exists, with file pointers

| File | What it tells you |
| --- | --- |
| `src/wrap.h`, `kAgentTargets` | One row per agent: context file, skills root, primary interface (CLI, MCP, or repo-map), MCP stanza shape, caveat. `wrapEmitAgent` dispatches on the row |
| `src/wrap.h`, `wrapMcpJson` / `wrapMcpJsonOpencode` | The two JSON stanzas: `mcpServers` for Cursor, Windsurf and Gemini CLI; `mcp` with `type: local` and a command array for opencode |
| `src/wrap.h`, `wrapCommandToken` | How the recipe spells the server command (see claim P below) |
| `scripts/verify-agent-integration.sh` | Phase 1 runs in a throwaway `HOME`; phase 2 is two prompts you paste; the last section is the report block |
| `test/agenttablecheck.sh` | Reads `kAgentTargets` as its own input and checks every row's on-disk claims |
| `test/opencodewrapcheck.sh` | Checks the opencode stanza against a **vendored** copy of opencode's published schema (`test/fixtures/opencode-config.schema.json`), not a running opencode |
| `test/wrapverbscheck.sh`, `test/codexwrapcheck.sh`, `test/skillinstallcheck.sh` | The rest of the recipe surface |
| `bench/agentloop/run_agentloop.py` | Maintainers drive `claude-code-p`, `codex-exec` and `opencode` here. Its `ripwire_cli` arm is the shipped wrap recipe, and it explicitly forbids a ripwire MCP server — so opencode's CLI path is exercised, its MCP alternative is not |
| `INSTALL.md`, "Connect your coding agent" | What users are told, and the uninstall steps for each agent's config |
| Issues #68 and #69 | The report shape to copy: the claims least likely to survive, stated before anyone runs anything |

### What the recipes print today

Captured from a build of `main` at `766913d0`. Re-capture from your binary; do not trust this table
over it.

| Agent | Primary | Config the recipe names | Stanza | Rules file | Skills line |
| --- | --- | --- | --- | --- | --- |
| Cursor | MCP | `.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (global) | `{"mcpServers":{"ripwire":{"command":"ripwire","args":["--mcp"]}}}` | `.cursor/rules` (a `.mdc` file) | none |
| Windsurf | MCP | `~/.codeium/windsurf/mcp_config.json` | same as Cursor | `.windsurfrules` | none |
| Gemini CLI | MCP | `~/.gemini/settings.json` | same as Cursor | `GEMINI.md` | none |
| opencode | CLI first, MCP alternative | `opencode.json` or `~/.config/opencode/opencode.json` | `{"mcp":{"ripwire":{"type":"local","command":["ripwire","--mcp"]}}}` | `AGENTS.md` (also `~/.config/opencode/AGENTS.md`) | none |
| aider | ranked repo map, no MCP | none | none — `ripwire . --for="<your task>" --token-budget=2000 > .ripwire-map.txt`, then `aider --read .ripwire-map.txt` | `CONVENTIONS.md` | none |

Every MCP recipe advertises **31 tools**. A `tools/list` over the server's stdio answers 31 tools in
41,908 bytes on that build.

**What phase 1 checks for these five agents today:** that `ripwire wrap <agent>` exits 0, and a note
that there is no skills line. That is all. For every one of them, the script's automated half proves
the binary can print, and nothing about the agent.

---

## The claims least likely to survive contact

State these in your plan before you run anything, then answer each one with evidence.

**P — every MCP agent: the command is a PATH lookup.** `wrapCommandToken` prints the bare word
`ripwire` whenever *the shell that ran `wrap`* finds an executable named ripwire on PATH. It prints an
absolute path only when nothing on PATH is named ripwire. The Codex branch of the same file prints
an absolute path on purpose, because "Codex Desktop may not inherit the shell PATH". A GUI editor
launched from the Dock or a desktop launcher may not see `~/.local/bin` either. Test the editor launched
**both** from a terminal and from the desktop, and record whether the server starts in each.

**Cursor**

1. **The stanza has no `type`.** Cursor's MCP documentation lists a `type` field (`"stdio"`) for a
   stdio server ([cursor.com/docs/context/mcp](https://cursor.com/docs/context/mcp)). ripwire's
   stanza is `command` plus `args` only. Does Cursor load it, and does it show ripwire's tools?
2. **The rules file.** The recipe says to paste the block into `.cursor/rules` as a `.mdc` file.
   Does Cursor apply it, and does the agent answer phase 2's first prompt from it?
3. **Tool count.** How many ripwire tools does Cursor list, and does it warn about a count? The docs
   point at the MCP Logs output channel for connection errors; paste what it says.

**Windsurf**

1. **Which agent reads the config?** The path matches Windsurf's documentation, but that page
   (`docs.windsurf.com/windsurf/cascade/mcp`, which now redirects to
   [docs.devin.ai/desktop/cascade/mcp](https://docs.devin.ai/desktop/cascade/mcp)) warns that this
   MCP configuration applies to the **legacy Cascade agent only**. It says the default agent for new
   tabs reads MCP servers from different config files. Test the agent a new user actually gets.
2. **A tool budget.** The same page states a limit of **100 total tools** at any time. ripwire alone
   registers 31. Record what happens alongside the user's other servers.
3. **`.windsurfrules`.** Is it still read?

**Gemini CLI**

1. **Project scope.** Gemini reads `~/.gemini/settings.json` (user) and `.gemini/settings.json`
   (project) ([gemini-cli MCP docs](https://github.com/google-gemini/gemini-cli/blob/main/docs/tools/mcp-server.md)).
   The recipe names only the user file. Record whether a project file overrides it.
2. **Schema rewriting.** The same page says Gemini sanitizes tool parameter schemas: it removes
   `$schema` and strips `additionalProperties`. #48 proves schema acceptance is client-specific. Does
   `/mcp` (or `gemini mcp list`) show all 31 tools as available, and does a tool call **with
   arguments** succeed?
3. **`GEMINI.md`.** Does the agent answer from it?

**opencode**

1. **The MCP alternative has never been run by a maintainer.** The stanza matches opencode's
   documentation ([opencode.ai/docs/mcp-servers](https://opencode.ai/docs/mcp-servers/)): key `mcp`,
   `type: local`, and a command array. The gate checks it only against a pinned schema. Register it,
   and paste `opencode mcp list`.
2. **#48's class, on the current release.** Is every tool accepted, with no schema error?
3. **Project wins.** The recipe says project and global configs merge per key, with the project
   winning. Test with both present.

**aider**

1. **The rules block is never read as printed.** The recipe tells you to paste the block into
   `CONVENTIONS.md`, but its command passes only `--read .ripwire-map.txt`. aider loads a conventions
   file only through `--read`, `/read` or `read:` in `.aider.conf.yml`
   ([aider conventions docs](https://aider.chat/docs/usage/conventions.html)). **Expect a FAIL here,**
   and prove it: does aider know what ripwire is without being told?
2. **Phase 2 does not fit aider.** The script's step 3 passes when the agent *runs* ripwire. In this
   recipe aider never runs it; it receives a map. The honest pass criterion is that the answer is
   grounded in files and symbols the map named.
3. **The map file lands in the repository root.** ripwire does not index it back (a `--grep` over a
   fixture lists `.ripwire-map.txt` under `<unindexed>` with `files="0"`). It is still an untracked
   file in the user's tree. Record what `git status` and aider make of it, and whether the recipe
   should say so.

---

## How to reproduce and measure

1. **Identify everything.** `ripwire --version`, the agent's version from the agent itself, OS and
   architecture, and how each was installed.
2. **Run phase 1:** `bash scripts/verify-agent-integration.sh <agent>`. It installs into a throwaway
   `HOME` unless you pass its live option. Keep the output.
3. **Add the checks phase 1 can make without the agent** — the script lacks them for these five
   agents, and they are the part that will keep working after you are gone:
   - **Parse the printed stanza as JSON.** Assert the key the agent reads (`mcpServers`, or `mcp` for
     opencode) and the fields its documentation requires.
   - **Resolve the command the way the agent will.** If the token is an absolute path, it exists and
     is executable. If it is the bare word, report whether it still resolves under a minimal `PATH` of
     the kind a desktop app gets. Report; do not "fix" by editing your own `PATH`.
   - **Handshake with the server.** Pipe newline-delimited JSON-RPC to `ripwire --mcp`, the same framing
     `test/batchcheck.sh` uses: `initialize`, then `tools/list`. Assert the tool count equals the
     number the recipe printed (read it from the recipe, never a literal), and that no tool's input
     schema carries `oneOf`, `allOf` or `anyOf` at the top level — #48's class. Look for an existing
     gate that already covers that before adding a second one.
   - **aider:** in a scratch git repository, run the recipe's map line and assert the file exists and
     is non-empty; once the rules-file fix lands, assert the recipe loads the file it tells you to edit.
4. **Run phase 2 by hand, in the real agent,** in a real repository, with the prompts pasted
   **verbatim**. Use pass criteria that fit the agent: a ripwire **MCP tool call** visible in the
   transcript for Cursor, Windsurf and Gemini CLI; a ripwire **command run** for opencode's CLI path; an
   answer **grounded in the map** for aider.
5. **Paste the report block** the script prints, filled in, FAIL lines included. A step you did not run
   is marked not run — never ticked.

---

## Design space and constraints

- **One agent per PR.** Each report is independent evidence. Mixing agents makes a FAIL hard to
  attribute.
- **Do not reshape the environment to make the recipe look right.** If the recipe only works after you
  move a directory onto `PATH` or add a field by hand, that is the FAIL. Record the edit that made it
  work as the proposed fix.
- **A recipe change is a table change.** `kAgentTargets` is the single source every `wrap` output and
  `test/agenttablecheck.sh` derive from. Change the row or the emitter, never special-case one agent in
  a branch the table cannot see.
- **Gate before code.** For each recipe fix, write the gate arm first, against a binary without the fix,
  and watch it fail (CONTRIBUTING.md §2). A control must mutate real input and re-run the identical
  extraction; assert the mutation took before trusting the outcome.
- **Gates never reach the network or a host-installed agent.** `test/opencodewrapcheck.sh` states the
  rule: no gate in this tree reaches the network, and G3 forbids host-installed dependencies. Anything
  that needs the real agent lives in `scripts/verify-agent-integration.sh`, never in `test/`.
- **Honesty in output.** A check that examined nothing is not a pass. The script already carries the
  scar: a `~` that did not expand made "every skill resolves" pass having looked at zero files (the
  comment in phase 1). Every new check proves it saw its subject first.
- **Phase 1 stays read-mostly.** It never writes the real `HOME` unless the live option is passed —
  that is the script's contract, and your extensions keep it.
- **No timing assertions.** House rule: no performance-budget gates.

---

## Acceptance criteria

1. The script's report block for **one** agent, filled in, with ripwire version, agent version and OS,
   and every FAIL line kept.
2. Every claim above for that agent answered with evidence — the agent's own tool list, log line or
   transcript excerpt — including claim P tested from both a terminal and a desktop launch.
3. For every FAIL: a fix in `src/wrap.h`, `INSTALL.md` or the script, with a gate arm observed red
   first, **or** an issue on the agent's own tracker when the bug is theirs, linked from the report.
4. `scripts/verify-agent-integration.sh` gains the agent-independent phase 1 checks for this agent
   (stanza parse, command resolution, handshake and tool count, the aider map), each shown firing on a
   deliberately broken recipe.
5. Phase 2's pass criteria fit the agent: an MCP tool call, a CLI run, or a map-grounded answer.
6. `INSTALL.md` states what was verified live, on which versions, and when — the way #131 corrected
   the Hermes paragraph — and nothing it does not know.
7. Gates green in the foreground: `test/agenttablecheck.sh`, `test/wrapverbscheck.sh`,
   `test/opencodewrapcheck.sh` (for opencode), `test/deckcheck.sh` (it scans `INSTALL.md`),
   `test/ripwirepubliccheck.sh`, `test/manifestcheck.sh`, and `bash -n` on the script.

---

## Known traps

1. **A green phase 1 is not a verified agent.** Everything below the script's phase 2 line is a claim
   the project cannot verify alone. That sentence is in the script's header for a reason.
2. **Your shell's PATH is not the app's PATH.** Claim P. Launch the editor from the desktop at least
   once.
3. **A config that parses and is silently ignored.** A familiar shape under the wrong key loads
   without error in opencode and does nothing. Confirm from the **agent's own list of servers and tools**,
   never from the absence of an error.
4. **Two configs, one winner.** Cursor has project and global files, Gemini has user and project
   settings, and opencode merges per key with the project winning. Test with exactly one present, then
   both, and record which won.
5. **Two agents behind one product name.** Windsurf's documentation now distinguishes the legacy
   Cascade agent from the default agent for new tabs, and they read MCP servers from different
   places.
6. **Reading the docs is not running the agent.** #69 records a review of the Hermes source
   contradicting a merged MCP spelling — only a live run can settle which one registers. Your reading of
   a docs page is a hypothesis; the agent's behaviour is the result.
7. **Empty equals agreement.** A new phase 1 check that parses nothing, lists zero tools or resolves no
   path must fail, not pass. CONTRIBUTING.md §2 lists the six ways an arm stops being able to fail;
   check yours against them.
8. **Personal data in a report.** Your agent's config and your `HOME` path are yours. Redact them
   before pasting; `test/ripwirepubliccheck.sh` rejects absolute home paths in anything committed.
9. **Changing a recipe moves documentation.** `INSTALL.md` quotes the recipes and is scanned by
   `test/deckcheck.sh`; any competitor or agent flag you add to prose must be real, or allowlisted with
   a reason.

---

## What the PR description should contain

- The agent, its version and how it was installed; `ripwire --version`; OS and architecture.
- The report block, verbatim, FAIL lines first.
- Each claim with its answer and the evidence (tool list output, log excerpt, transcript line).
- Each fix with the gate arm that was red before it, or the upstream issue you filed.
- What you did **not** test: project scope, a second OS, the desktop launch, the other agent in the same
  product.
- Every file you changed in the agent's own configuration, and how to undo it.

---

**Write the plan — the agent, its claims, the phase 1 checks to add, the phase 2 criteria, and how you
will undo your config changes — then STOP for my go-ahead.**
