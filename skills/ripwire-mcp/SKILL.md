---
name: ripwire-mcp
description: >
  Wire ripwire into an agent as an MCP server — `ripwire wrap AGENT` (Claude Code, Cursor, Codex,
  Gemini…) — and choose the server verb mid-task. Also tool HEALTH: a symbol you expected is missing
  from the ranked output, the index feels stale after a rebase, 'is my ripwire setup broken?'
allowed-tools: Bash, Read
---

# ripwire as an MCP server

> Routing: auditing somebody else's `.mcp.json` for safety → **ripwire-security-scan** · unsure →
> **ripwire-router**.

## The one call — `ripwire wrap <agent>` prints the recipe

```
ripwire wrap claude      # → claude mcp add ripwire -- ripwire --mcp --mcp-tools=no-edit
ripwire wrap cursor      # → JSON mcpServers stanza for .cursor/mcp.json (also: windsurf, gemini)
ripwire wrap codex       # → TOML stanza for ~/.codex/config.toml
ripwire wrap --all       # → auto-detect installed agents, emit each one's config in one run
```

`wrap` never edits config itself — it prints; you review and run. It first security-scans `./skills` and
`.agents/skills`: a CRITICAL finding blocks the recipe (exit 1) unless `--force`. Bare `ripwire wrap` lists the
supported agents (opencode, aider and more).

The server exposes **34 MCP verbs**: 18 read verbs, 13 flagship-reflex verbs and 3 edit verbs —
`ripwire wrap codex --force` prints the live count.

## Choosing the verb mid-task

Start a task with `explore`; an error → `from_trace`; before changing a symbol `impact` + `uses`; after an edit
`edit_check`; before done `quality_delta`; several independent reads in one turn → `batch`. Every verb takes `path`
(the repo root); a split checkout passes `paths: [dir1, dir2]`. `find_symbol` and `find_referencing_symbols`
return a stable `handle=` instead of the body — `fetch_body` it only when you need it.

## Tool health — is the answer trustworthy?

- A symbol you expected is missing from the ranked output: `ripwire <dir> --skipped --legend=compact` (a size
  ceiling dropped its file?), then `ripwire <dir> --doctor --legend=compact`.
- Index feels stale after a rebase, or the wrong binary answers: `--doctor` (binary-vs-PATH staleness, grammar
  compile, cache health); Codex: `ripwire <repo> --doctor --agent=codex`.
- "no project root": `$HOME`, `/` and system directories are never a root over MCP — pass the project
  directory. "memory limit reached" / `_memory_stop`: point `path=` at a smaller root or raise `--max-memory`.

## The legend over MCP

The session's first answer defines its attributes inline; later answers carry a definition only the first time
the session meets it. On the CLI the same saving is opt-in: read the core once (`ripwire --legend-dict=core`,
13 definitions, about 1.5 KB) and pass its `have=` as `--legend-have=`, or name the definitions you received with
`--legend-seen=FILE` (both in `session-legend.md`).

## Stop rule

Wiring is one `wrap` call; a health question is one `--doctor` run. Read a reference file only for the verb
or transport you are actually using.

## Reference files

| You need | Read |
|---|---|
| every wrap target, the Codex surface audit, memory-guard and root refusals | `wiring.md` |
| each read verb and when it beats the CLI form | `read-verbs.md` |
| remote `--listen` (Streamable HTTP) and editor `--lsp` transports | `transports.md` |
| the lazy-body posture: names by default, bodies by handle | `read-verbs-lazy.md` |
| the per-session legend in full | `session-legend.md` |
| the 3 edit verbs and their safety contract | `edit-verbs.md` · full detail `mcp-reference.md` |
