# ctxpack MCP reference — edit-verb safety contract + server internals

Reference for `ctxpack-mcp`. Load this when you're about to call one of the 3 edit verbs (need the exact
failure-mode contract) or need to reason about server staleness/rebuild/personalization internals.

## The 3 edit verbs — span-addressed writes, no read-then-diff

`replace_symbol_body`, `insert_before_symbol`, `insert_after_symbol` — ctxpack's WRITE verbs (26
verbs total: the read verbs + `fetch_body` + the 10 flagship-reflex verbs (incl. `explore`/`from_trace`/
`edit_check`) + these 3 edit). Each locates a symbol's definition in the
already-parsed index and splices text at its byte span:

| Verb | Args | Does |
|---|---|---|
| `replace_symbol_body` | `path, symbol, new_body, file?` | replaces signature-through-closing-brace with `new_body` verbatim; bytes outside the span are untouched |
| `insert_before_symbol` | `path, symbol, text, file?` | inserts `text` at the def's first byte |
| `insert_after_symbol` | `path, symbol, text, file?` | inserts `text` past the def's final byte |

**Newline rule** (so you don't have to guess): `replace_symbol_body` adds/removes nothing — `new_body` must
be a complete, well-formed definition. `insert_before_symbol` appends a `\n` to `text` only if it lacks a
trailing one, so the inserted block and the definition land on separate lines. `insert_after_symbol`
prepends a `\n` only if `text` lacks a leading one — same separation, other direction. Verified: inserting
`"int sub(...) {...}"` (no trailing newline) after `add` in a fixture produced `add`'s body immediately
followed by `\nint sub(...) {...}` on its own line, with every other byte of the file unchanged.

**Safety contract — every failure path leaves the file byte-for-byte unchanged:**
- **Not found** → JSON-RPC error listing the nearest symbol names by shared-prefix score (a typo hint),
  e.g. `symbol 'nosuchsymbolxyz' not found; nearest: normalCaller, makesWidget, PoolThing, ...`.
- **Ambiguous** (>1 definition with that name) → error listing every candidate as `file:line`; retry the
  call with `file` set to a disambiguating path substring.
- **Stale index** → the server hashes each indexed file's bytes at index-build time; if a fresh read of the
  target file no longer matches that hash (edited outside this session, or by a prior call), the edit
  refuses rather than splicing at offsets that no longer address the right bytes. Call any read verb first
  — that refreshes the index — then retry the edit.
- **Insane span** (`a>=b` or `b>filesize`) or an unreadable file → refuses; never splices out of bounds.
- **Atomic write**: the new bytes are written to `<path>.<pid>.tmp` then `rename(2)`d over the original — a
  reader never sees a torn file, and a crash mid-write leaves the original intact.
- **On success**: the in-memory index is invalidated (`valid=false`), so the very next verb call — read or
  edit — rebuilds from the just-written disk state. The response JSON includes the applied `span`,
  `old_file_bytes`/`new_file_bytes`, the pre-edit `stale_index` stamp, and a note that the index will refresh.

**When to reach for these vs your normal editor tool**: unique value is a **span-addressed edit without
reading the file first** — you already know the symbol name from a prior ctxpack call (e.g. `--callers`
told you who to fix), so you can edit it in one round-trip instead of read → locate → edit. The trade-off:
**name ambiguity needs the `file` arg** — if the codebase has multiple symbols with that name (overloads,
same-named methods on different types), the first call will refuse and hand you the candidate list; a
native editor tool addressed by file:line doesn't have this failure mode. Prefer your editor tool when
you're already looking at the file, or when the edit isn't a whole-definition replace/insert (a mid-body
tweak isn't representable — `replace_symbol_body` is signature-through-closing-brace or nothing).

## Remote transport — `--listen` reference {#remote-transport}

```
ctxpack . --listen=127.0.0.1:8765                       # loopback only; no token needed
ctxpack . --listen=0.0.0.0:8765 --mcp-token=SECRET      # off-host: REQUIRES a token or it refuses to start
ctxpack . --listen=127.0.0.1:8765 --mcp-token=S --allow-remote-edits   # opt in to remote edits (forces the token)
# POST a JSON-RPC body to /mcp:
curl -s -X POST http://127.0.0.1:8765/mcp -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"task":"parse http"}}}'
```

- **Loopback by default.** A bare `--listen=PORT` or `127.0.0.1:PORT` binds loopback only — reachable by a
  local agent, nothing off-box, no token required.
- **Non-loopback needs TWO opt-ins.** Binding a routable host (e.g. `0.0.0.0:8765`) requires *both* the
  explicit host *and* a shared bearer token (`--mcp-token=SECRET` or `CTXPACK_MCP_TOKEN` env). Missing the
  token → the server **refuses to start** (exit 1, loud stderr banner). A token, once set, gates *every*
  request (`Authorization: Bearer …`, constant-time compare) → missing/wrong = HTTP 401.
- **No TLS built in — reverse-proxy it.** The token is a tripwire, not a security boundary; for any real
  exposure put ctxpack behind your own proxy for TLS + auth.
- **One listener = ONE workspace, pinned at startup.** A request whose `path`/`paths` names a *different*
  tree is refused (a remote client cannot make the server read arbitrary host paths); omit `path` and it
  defaults to the pinned workspace.
- **Edit verbs refused over the remote transport by default.** A remote *file-writer* is a different trust
  contract than a remote *reader*: the 3 edit verbs return a JSON-RPC error (file byte-identical) unless you
  pass **`--allow-remote-edits`**, which also *forces* the token requirement even on loopback. The common
  team deployment (read verbs over a shared warm index) therefore carries no write surface at all.
- **Hostile input degrades, never crashes.** Any malformed HTTP → a clean 4xx and the server lives; an
  oversized body (> 8 MB) → 413; a stalled/partial request → a read timeout closes just that connection.

## Server behavior worth knowing

- **`--mcp` implies `--stable`** (path-ordered output → stable prefix → provider KV-cache hits on
  re-analyze). Opt out with `--no-stable` if you want important-first ordering.
- **Staleness is automatic**: before each verb the server checks every indexed file's mtime AND each
  parent directory's mtime (so edits, adds, and deletes are all caught). Fresh → instant reuse, no parse.
- **Stale → a WARM rebuild**, through the per-root content-hash cache: only changed files re-parse.
  You never restart the server after editing code.
- **Every response carries an `_index` staleness stamp** — a sibling of `content` in the JSON-RPC result,
  not appended to the verb's own text (so JSON/XML payloads a caller parses stay intact):
  `"_index":"[index: files=N symbols=M hash=XXXXXXXX]"`. Two results with a matching stamp came from the
  identical index state; a differing stamp means the tree (or the working set — see below) changed between
  calls. Useful for an agent chaining several verb calls to notice "the index moved under me" without a
  side channel. **Two related but distinct staleness signals**: `_index` tells you the WHOLE index moved
  (tree-wide); a `fetch_body` refusal tells you ONE handle's file moved (symbol-scoped) — check `_index`
  when deciding whether to re-run a broad query, check a handle's own staleness when deciding whether to
  re-fetch one body.
- **Working-set personalization (Cody-style)**: the PageRank prior is teleport-biased toward files with
  **uncommitted changes** (`git diff --name-only HEAD`) — β=0.7 of the mass on changed-file symbols, same
  weighting `--map-diff` uses. Ranks auto-shift toward what you're actively editing; a clean tree or a
  non-git root both degrade to the plain uniform prior (byte-identical to no personalization). `git diff` is
  only re-run as part of a staleness-triggered rebuild (not on every call — that would erase the warm-path
  win), so the working set can lag by up to one edit before it's picked up; it self-corrects on the next
  mtime-triggered rebuild.
- **Background `qsnap` HEAD-warm on large workspaces**: when the server observes git HEAD has moved (a
  commit landed), it silently warms the HEAD-snapshot `qsnap` cache on one background thread so the *next*
  `quality_delta` after a commit is fast instead of paying a cold HEAD ingest — a purely internal,
  deterministic file-cache warm (no new flag, output byte-identical whether or not it fires; gated off on
  small repos where the cold path is already cheap).
- Errors are graceful: unknown symbol / missing file → a JSON-RPC error, never a dead server.
