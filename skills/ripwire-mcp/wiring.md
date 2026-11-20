# ripwire-mcp — reference: wiring (read on demand; the recipe is in SKILL.md)

# ripwire as an MCP server

> Auditing somebody's `.mcp.json` for safety instead → **ripwire-security-scan**.

Trigger: "wire ripwire into my agent", "set up the ripwire MCP server", or "which ripwire MCP verb
answers this?".

**The 33 verbs, at a glance**: 17 read verbs (`analyze`, `rank_by` — the same map, ranked by
authority/hub/rrf instead of plain PageRank — `for`, `find_symbol`,
`find_referencing_symbols`, `grep`, `cochange`, `memory_recall`, `situational_awareness`, `mentions`,
`owners`, `lego`, `batch` — N read sub-queries in ONE call — `fetch_body`, and `flags` — what is BUILT but
DARK here: every compile / CMake `option()` / `getenv` gate with its default and the size of the code it
guards, the answer to "why don't I see feature X?", and `doc_drift` — which of the repo's markdown claims
are now FALSE: dead `file:line` anchors, deleted symbols, `= N` constants and `[N]` extents the code has
since changed; call it before trusting a design doc or audit you did not just write, and `slice` — per-line
def-use rows of ONE variable inside ONE definition, `flow=back|fwd|both` for the transitive data-flow
slice, `@FILE:LINE` seeds by location and pre-picks the variable the seed line names) + 13 flagship-reflex verbs
(`exemplar`, `quality_delta`, `quality_baseline`, `impact`, `uses`, `affected` — which tests transitively
reach a changed file/symbol, the pre-PR "what do I run?" reflex — `path_between`, `connect` — the
minimal joining subgraph over N task symbols — the L4 one-call/B11-parity trio `explore`, `from_trace`,
`edit_check` — so an MCP-only agent gets the same write & done reflexes as the CLI — and the CROSS-BRANCH
pair `whereis` / `stray_content`, which answer "where does this content live?" across every branch: the
question `git cherry` cannot, since it compares commit ancestry and every other verb indexes one worktree.
`stray_content` marks a branch `superseded` when the live line re-implemented its work, which is exactly
the case `git cherry` calls unmerged forever; `whereis` lists the definitions and counts the references
(`listing="defs"` on the root) when that page lists MORE definitions than the whole list would under the same row
cap, or the same ones in strictly fewer bytes — `listing:"all"` asks for every row) + the 3 span-addressed
edit verbs (`replace_symbol_body`, `insert_before_symbol`, `insert_after_symbol`; `ripwire wrap claude` omits these three with `--mcp-tools=no-edit`, since Claude Code edits through its native Edit). Only `find_symbol` and
`find_referencing_symbols` attach a stable `handle=` instead of the body (fetch it only when you need it,
via `fetch_body`); the edit verbs enforce a safety contract (staleness refusal, ambiguity refusal, atomic
writes) detailed below and in full in [`mcp-reference.md`](mcp-reference.md).

The server exposes **33 MCP verbs**: 17 read verbs (incl. `rank_by`/`fetch_body`/`flags`/`slice`), 13 flagship-reflex
verbs (`affected`/`connect`/`explore`/`from_trace`/`edit_check` and the cross-branch pair `whereis`/`stray_content`) and
3 edit verbs — `ripwire wrap codex --force` prints the live count.

## Wiring — `ripwire wrap <agent>` prints the recipe

```
ripwire wrap claude      # → claude mcp add ripwire -- ripwire --mcp --mcp-tools=no-edit
ripwire wrap cursor      # → JSON mcpServers stanza for .cursor/mcp.json (also: windsurf, gemini)
ripwire wrap codex       # → TOML stanza for ~/.codex/config.toml
ripwire wrap opencode    # → CLI first (AGENTS.md is read automatically); its config key is "mcp", NOT mcpServers
ripwire wrap aider       # → no MCP: ripwire . --for="<task>" > .ripwire-map.txt; aider --read .ripwire-map.txt
ripwire wrap --all       # → auto-detect installed agents, emit each one's config in one run
```

`wrap` never edits config itself — it prints; you review and run. Before printing it security-scans
`./skills` and `.agents/skills`: a CRITICAL finding blocks the recipe (exit 1) unless you pass
`--force`; WARNs print and continue. Bare `ripwire wrap` lists the supported agents.

### Audit the active Codex surface

Run `ripwire <repo> --doctor --agent=codex` after install/update or when Codex appears to be using a stale
binary, missing a skill, skipping the advisory CLI-first hooks, or starting the wrong MCP executable. This
extends the ordinary six-check doctor with four read-only checks over the LIVE environment: PATH binary
agreement, exact parity between the installed skills and `.ripwire-manifest-v1`, executability of all three
Codex hook roles, and the configured `mcp_servers.ripwire` command plus `--mcp` argument. Failing rows give
the exact installer/wrap repair command. The report deliberately emits no config contents or full shell
commands, so it is safe to paste for diagnosis; `--agent=codex` alone refuses because it modifies doctor.

### "no project root" / "memory limit reached" / `_memory_stop`

`$HOME`, `/` and system directories are never a project root over MCP — not as the launch directory and not as
`path=`: pass the project directory itself (a server started as `ripwire ~ --mcp` still answers about `~`). A tool call refused with "memory limit reached", or an answer carrying `_memory_stop`
in its envelope, means the memory guard cut or refused the work on a tree too large for the machine: point
`path=` at a smaller root, or raise the limit with `--max-memory=<N>[K|M|G]` (or `RIPWIRE_MAX_MEMORY`) on the
server's command line. The default (65% of RAM) is silent on real projects.
