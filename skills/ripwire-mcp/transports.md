# ripwire-mcp — reference: transports (read on demand; the recipe is in SKILL.md)

## Remote transport: `--listen` (Streamable HTTP) — opt-in, security posture is the feature

By default `--mcp` speaks JSON-RPC over **stdio** (one co-located agent). For a team sharing one warm
index, `--listen=HOST:PORT` serves the *same verbs* over **Streamable HTTP** (protocol `2025-11-25`)
instead — byte-identical JSON-RPC, only the transport differs, single-threaded against one warm index.

**The security posture is the whole point** (a 2026 survey found ~200K MCP servers naively bridged to the
open internet with no auth — ripwire is built so it cannot become one by default): loopback-only by
default; a routable host needs *both* the explicit host flag *and* a bearer token or the server **refuses
to start**; no TLS built in (reverse-proxy it); one listener pins to ONE workspace at startup; and the 3
edit verbs are refused over remote unless you pass `--allow-remote-edits` (which also forces the token).
Full flag/env reference, the `curl` recipe, and each refusal's exact wire behavior →
[`mcp-reference.md`](mcp-reference.md#remote-transport).

## Editor transport: `--lsp` (navigation LSP server) — read-only, Phase 1

`--mcp` answers agents and `--listen` serves a team; `--lsp` answers **editors**: a read-only,
navigation-focused LSP 3.x server over stdio — lifecycle (`initialize`/`shutdown`/`exit`) plus
`definition`, `references`, `documentSymbol` (member variables merged into the outline), workspace
symbol, and `hover`. Same warm index as `--mcp` — no second parser, no second process. Saved-state
answers only: an unsaved buffer is absent from the index, not mispositioned, and every count is a
floor, not a total (the hover text says so in place, since JSON-RPC results have no metadata channel).
UTF-8 positions; refuses to combine with `--mcp`/`--listen` — one protocol per stdin. The PoC plan and
its locked decisions live in `docs/LSP.md`.
