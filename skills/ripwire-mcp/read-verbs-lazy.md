# ripwire-mcp — reference: read-verbs-lazy (read on demand; the recipe is in SKILL.md)

## The lazy-body posture: names/signatures by default, bodies by handle on request

`find_symbol` and `find_referencing_symbols` attach a stable `handle` to every symbol object they return
(the focus symbol, each caller, each callee) — but **not the body**. Call `fetch_body{path, handle}` only
when you actually need to read the source, instead of the server sending bodies you didn't ask for. This is
the kit-style default-lean posture (measured ~90% cut on comparable extract-symbol calls) and matches the
`2025-11-25` MCP spec's move to stateless HANDLE semantics.

- **Handle format**: `sym#<idHash>@<contentHash>`, both 16 lowercase hex (FNV-1a-64) — `idHash` from the
  symbol's STABLE canonical id (`path::scope::name`, never the per-run `NodeId`), `contentHash` pinning the
  file's bytes at mint time.
- **Fetch when you're about to reason about the logic**, not just to confirm the symbol exists — the
  name/kind/file/line a read verb already gives you is often enough to decide relevance or pick a call site.
- **Staleness is automatic and free**: a content-hash mismatch (file changed since mint) makes `fetch_body`
  refuse rather than serve a body against shifted byte offsets — call a read verb again for a fresh handle.
  A malformed/unresolvable handle refuses the same way, never a silent wrong-symbol body.
- **Handles are content-addressed, not pinned literals**: both halves are derived hashes, so a handle you
  copied out of a prior session or a doc is almost certainly stale — call `find_symbol`/
  `find_referencing_symbols` fresh each session and read the `handle` it hands back.
