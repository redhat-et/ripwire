# ripwire-mcp — reference: edit-verbs (read on demand; the recipe is in SKILL.md)

## The 3 MCP edit verbs — the warm-server counterpart to the preferred CLI

`replace_symbol_body`, `insert_before_symbol`, `insert_after_symbol` — the last 3 of the 30 (see above),
ripwire's MCP WRITE verbs. The preferred shell front door is
`ripwire ROOT --replace-symbol-body=SYM --edit-payload=FILE|-` (or the matching insert flag); use MCP when
the server is already warm or a client has no shell. Both fronts call the same safety engine. (Claude Code
reads before it edits, so `ripwire wrap claude` registers the server with `--mcp-tools=no-edit`: it takes the
symbol's line range from ripwire, Reads that range, then uses the native Edit; `--mcp-tools=full` restores these.) Each locates
a symbol's definition in the parsed index and splices text at its byte span: `replace_symbol_body`
swaps signature-through-closing-brace verbatim, `insert_before_symbol`/`insert_after_symbol` splice text at
the def's first/final byte (auto-adding the separating newline so you don't have to guess).

**The receipt already answers "what now?"** — it carries `lines={start,end}` for the applied text,
`edit_check` (status / callers / incompatible / each broken caller's call lines) and `tests_to_run` with the
run recipe: the same answers a separate `edit_check` verb and `--affected` would give, computed on the index
the edit just refreshed. Do not spend two more calls on them. `post_check:false` (CLI `--no-post-check`)
opts out — reach for it only when the next thing you do is another edit to the same tree.

Read **[`mcp-reference.md`](mcp-reference.md)** before calling one of these 3 (full args table + the exact
newline rule + the safety contract for not-found / ambiguous / stale-index / insane-span failures + the
atomic-write guarantee) or when you need server internals (`--mcp` implies `--stable`, `_index` staleness
stamps, warm content-hash rebuilds, working-set PageRank personalization, the background `qsnap` HEAD-warm on
large workspaces). Short version: every edit-verb failure leaves the file byte-for-byte unchanged, writes are
atomic (`tmp` + `rename(2)`), and the server never goes stale silently — it rebuilds warm from mtime checks
before every verb call. **Lead with this MCP form when the body already came from `fetch_body` this
session AND your server lists the edit verbs** (the default `ripwire wrap claude` server omits them with `--mcp-tools=no-edit`:
there, take the ranged-Read plus native-Edit route, or the CLI `--replace-symbol-body` below); after a CLI `--expand`, keep the
zero-standing-schema CLI path and use `--edit-payload=-`.
Several harnesses' native Edit tool
needs a fresh Read of the file immediately before the edit, even when you already have the body from
elsewhere in the session — these verbs check their own staleness hash instead of requiring one, so under any
harness the file gets read at most once, never twice.

**Workspace pin (stdio, D3/D4):** when the server was started `ripwire <root> --mcp`, an omitted
`path` on ANY verb (read or edit) defaults to that startup root; the 3 edit verbs above additionally
REFUSE (file byte-identical, same contract as every other refusal above) if an explicit `path` resolves
outside it — `path outside workspace; start the server on that root or pass an absolute in-root path`.
Read verbs stay unrestricted at any `path`. A bare `ripwire --mcp` with no startup root is unchanged: every
verb still requires its own `path`.
