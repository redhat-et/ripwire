# ripwire MCP reference — edit-verb safety contract + server internals

Reference for `ripwire-mcp`. Load this when you're about to call one of the 3 edit verbs (need the exact
failure-mode contract) or need to reason about server staleness/rebuild/personalization internals.

## The 3 MCP edit verbs — span-addressed writes, no read-then-diff

CLI is the preferred front door when a shell is available:

```bash
ripwire ROOT --replace-symbol-body=SYM --edit-payload=FILE
printf '%s' "$BLOCK" | ripwire ROOT --insert-before-symbol=SYM --edit-payload=-
```

`--insert-after-symbol` is the third form; `--edit-target-file=PATH` disambiguates same-named definitions.
These flags and the MCP verbs below call the same transaction-safe edit engine. MCP is useful when its
workspace is already warm or the client has no shell.

`replace_symbol_body`, `insert_before_symbol`, `insert_after_symbol` — ripwire's WRITE verbs (31
verbs total: the 16 read verbs incl. `fetch_body`/`slice` + the 12 flagship-reflex verbs (incl.
`explore`/`from_trace`/`edit_check`) + these 3 edit). Each locates a symbol's definition in the
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

**When to reach for these vs your normal editor tool** — lead with the harness-independent case: **if you
already have the body** — `fetch_body` or `--expand` served it this session — these verbs never re-read the
file. They splice directly at the already-known span, checked against their own staleness hash (see above),
not a fresh Read. Several coding-agent harnesses require their native edit tool to Read a file immediately
before an Edit on it, even when the agent already has the text from a prior call in the same session — under
that kind of harness, a served body plus a native Edit still pays for the file twice. `replace_symbol_body`/
`insert_before_symbol`/`insert_after_symbol` were never routed through the native edit tool, so they don't
inherit that requirement under any harness. Reach for the edit verb over native Edit whenever the body
already arrived via ripwire this session; once you've opened the file in your own editor tool anyway, the
advantage is gone. (Whether your specific harness enforces a pre-edit Read is worth checking against its own
behavior rather than assuming — this reasoning holds either way, since the edit verbs skip a Read regardless
of whether one would otherwise be required.)

The other unique value: a **span-addressed edit without reading the file first at all** — you already know
the symbol name from a prior ripwire call (e.g. `--callers` told you who to fix), so you can edit it in one
round-trip instead of read → locate → edit. The trade-off: **name ambiguity needs the `file` arg** — if the
codebase has multiple symbols with that name (overloads, same-named methods on different types), the first
call will refuse and hand you the candidate list; a native editor tool addressed by file:line doesn't have
this failure mode. Prefer your editor tool when you're already looking at the file, or when the edit isn't a
whole-definition replace/insert (a mid-body tweak isn't representable — `replace_symbol_body` is
signature-through-closing-brace or nothing).

## Remote transport — `--listen` reference {#remote-transport}

```
ripwire . --listen=127.0.0.1:8765                       # loopback only; no token needed
ripwire . --listen=0.0.0.0:8765 --mcp-token=SECRET      # off-host: REQUIRES a token or it refuses to start
ripwire . --listen=127.0.0.1:8765 --mcp-token=S --allow-remote-edits   # opt in to remote edits (forces the token)
# POST a JSON-RPC body to /mcp:
curl -s -X POST http://127.0.0.1:8765/mcp -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"task":"parse http"}}}'
```

- **Loopback by default.** A bare `--listen=PORT` or `127.0.0.1:PORT` binds loopback only — reachable by a
  local agent, nothing off-box, no token required.
- **Non-loopback needs TWO opt-ins.** Binding a routable host (e.g. `0.0.0.0:8765`) requires *both* the
  explicit host *and* a shared bearer token (`--mcp-token=SECRET` or `RIPWIRE_MCP_TOKEN` env). Missing the
  token → the server **refuses to start** (exit 1, loud stderr banner). A token, once set, gates *every*
  request (`Authorization: Bearer …`, constant-time compare) → missing/wrong = HTTP 401.
- **No TLS built in — reverse-proxy it.** The token is a tripwire, not a security boundary; for any real
  exposure put ripwire behind your own proxy for TLS + auth.
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
- **`_reingest` tells you what that rebuild COST** — a second envelope sibling, present only on a response
  whose handling actually brought an existing index up to date: `"_reingest":3` means the pass re-extracted
  3 files. It is a count, so the three states stay distinct. **Absent** — no incremental pass ran (the warm
  index answered as-is, or this was the server's first build of that root; an initial build is not an
  incremental pass). **`0`** — a pass ran and re-extracted nothing: something moved an mtime, or a file was
  deleted, but no surviving file's content changed. **`N`** — a pass ran and re-extracted exactly N files.
  The number tracks the DRIFT your session caused, not the tree size: one edit costs one file whatever the
  corpus, which is what makes "the server rebuilds warm" checkable instead of merely claimed. Deliberately
  NOT a fact about the tree — two servers at the identical tree state legitimately disagree on it — so never
  diff it across calls the way you would diff `_index`.
- **`_fresh` answers the question you actually have** — a third envelope sibling, on EVERY response that
  reads the index. `_index` and `_reingest` both need a second data point to interpret (one stamp means
  nothing alone; a cost means nothing without knowing a pass ran). `_fresh` is self-contained: **`"ok"`** —
  the per-request re-validation ran and found nothing moved, so this answer describes the tree as it is;
  **`"reindexed"`** — it found the tree had moved and the index was rebuilt *before* the verb answered. There
  is no `"stale"`: this server re-indexes rather than serving-and-flagging, so a stale serve is not one of
  the states. **You do not need to ask whether the map is current — read `_fresh`.**
  `"reindexed"` brings two counts, and the pair is where the honesty is. **`_stale_files`** is how many
  INDEXED files' recorded `(mtime, size, ctime)` moved; **`_changed_files`** is how many files actually differ in
  CONTENT from the index that was replaced. They disagree in both directions, on purpose: adding a file is
  `_stale_files:0, _changed_files:1` (no indexed file moved — its directory did), and a bare `touch` with no
  edit is `_stale_files:1, _changed_files:0` (a stat moved and not one byte). So `_changed_files:0` is your
  signal that a rebuild happened and nothing about the code changed — do not re-read anything. Like
  `_reingest`, these are facts about what THIS server did, not about the tree, so never diff them across
  calls. The limit that used to sit here — a content edit preserving BOTH the mtime and the exact byte
  length being invisible to a stat-keyed check — is CLOSED: the check compares `st_ctime` too, which moves on
  the `touch -r`/`cp -p` that restores an mtime and which no unprivileged writer can set back
  (`test/freshnesscheck.sh` arms 6-7). What is left is narrow and worth knowing: a system clock moved
  backward, raw block-device writes, and filesystems with no distinct ctime (FAT/exFAT, some SMB mounts),
  where the check degrades to its `(mtime, size)` behaviour. The edit verbs' own per-write byte-hash guard
  covers writes independently of any of this.
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
