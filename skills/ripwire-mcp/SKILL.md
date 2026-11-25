---
name: ripwire-mcp
description: >
  Wire ripwire into an agent as an MCP server — `ripwire wrap AGENT` (Claude Code, Cursor, Codex,
  Gemini…) — and choose the server verb mid-task. Also tool HEALTH: an expected symbol missing from the
  ranked output, the index stale after a rebase, 'is my ripwire setup broken?'
allowed-tools: Bash, Read
---

# ripwire as an MCP server

> Routing: auditing somebody else's `.mcp.json` for safety → **ripwire-security-scan**.

## The one call — `ripwire wrap <agent>` prints the recipe

```
ripwire wrap claude      # → claude mcp add ripwire -- ripwire --mcp --mcp-tools=no-edit
ripwire wrap cursor      # → JSON mcpServers stanza for .cursor/mcp.json (also: windsurf, gemini)
ripwire wrap codex       # → TOML stanza for ~/.codex/config.toml
ripwire wrap --all       # → auto-detect installed agents, one config each
```

`wrap` prints and never edits config; you review and run. It first security-scans `./skills` and `.agents/skills`: a
CRITICAL finding blocks the recipe (exit 1) unless `--force`. Bare `ripwire wrap` lists every supported agent.

The server exposes **34 MCP verbs**: 18 read verbs, 13 flagship-reflex verbs and 3 edit verbs —
`ripwire wrap codex --force` prints the live count.

## Choosing the verb mid-task

Tools are named `ripwire:<verb>` (server:tool). Start with `ripwire:explore`; an error → `ripwire:from_trace`; before changing a symbol `ripwire:impact` + `ripwire:uses`; after an edit `ripwire:edit_check`;
before done `ripwire:quality_delta`; several independent reads → `ripwire:batch`. Every verb takes `path` (the repo root; a split
checkout passes `paths: [dir1, dir2]`). `ripwire:find_symbol` and `ripwire:find_referencing_symbols` return a stable `handle=`, not the
body — `ripwire:fetch_body` it only when you need it.

## Tool health — is the answer trustworthy?

- An expected symbol missing from the ranked output: `ripwire <dir> --skipped --legend=compact` (a size ceiling dropped its file?), then
  `ripwire <dir> --doctor --legend=compact`.
- A stale index after a rebase, or the wrong binary answering: `--doctor` (binary-vs-PATH staleness, grammar compile,
  cache health); Codex: `ripwire <repo> --doctor --agent=codex`.
- "no project root": `$HOME`, `/` and system directories are never a root over MCP — pass the project directory.
  "memory limit reached" / `_memory_stop`: point `path=` at a smaller root or raise `--max-memory`.

## The legend over MCP

The session's first answer defines its attributes inline; later answers carry a definition only the first time the
session meets it. On the CLI the saving is opt-in: read the core once (`ripwire --legend-dict=core`, 13 definitions,
about 1.5 KB) and pass its `have=` as `--legend-have=`, or name the definitions you received with `--legend-seen=FILE`
(`session-legend.md`).

## Stop rule

Wiring is one `wrap` call; a health question is one `--doctor` run. Read a reference only for the verb or transport you
use.

## Reference files

`wiring.md` every wrap target, the Codex surface audit, memory-guard and root refusals · `read-verbs.md` each read verb
and when it beats the CLI · `transports.md` remote `--listen` (Streamable HTTP) and editor `--lsp` · `read-verbs-lazy.md`
names by default, bodies by handle · `session-legend.md` the per-session legend · `edit-verbs.md` the 3 edit verbs and
their safety contract (full detail: `mcp-reference.md`).
