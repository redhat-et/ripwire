---
name: ripwire-mcp
description: >
  Wire ripwire into a coding agent as an MCP server — "ripwire wrap AGENT". Covers the 31 MCP verbs (16
  read incl. fetch_body/flags/slice + 12 flagship-reflex verbs incl. connect/explore/from_trace/edit_check and the
  cross-branch pair whereis/stray_content + 3 edit verbs) and when the persistent server beats the preferred CLI form, the lazy-body handle posture, the shared edit
  safety contract, and the server's staleness/rebuild behavior. Use when setting up ripwire for
  Claude Code / Cursor / Codex / Windsurf / Gemini / opencode / aider, when deciding which ripwire MCP verb to call
  mid-task, or when wondering whether the server's index is stale. Also the tool-health moment: a symbol
  you EXPECTED is missing from the ranked output, results look stale or wrong, "is my ripwire setup
  broken?" — the index-staleness / server-health / rebuild surface answers whether the tool's answer is
  trustworthy right now. Backed by ripwire (deterministic, on
  PATH).
allowed-tools: Bash, Read
---

# ripwire as an MCP server

> Auditing somebody's `.mcp.json` for safety instead → **ripwire-security-scan**.

Trigger: "wire ripwire into my agent", "set up the ripwire MCP server", or "which ripwire MCP verb
answers this?".

**The 31 verbs, at a glance**: 16 read verbs (`analyze`, `for`, `find_symbol`,
`find_referencing_symbols`, `grep`, `cochange`, `memory_recall`, `situational_awareness`, `mentions`,
`owners`, `lego`, `batch` — N read sub-queries in ONE call — `fetch_body`, and `flags` — what is BUILT but
DARK here: every compile / CMake `option()` / `getenv` gate with its default and the size of the code it
guards, the answer to "why don't I see feature X?", and `doc_drift` — which of the repo's markdown claims
are now FALSE: dead `file:line` anchors, deleted symbols, `= N` constants and `[N]` extents the code has
since changed; call it before trusting a design doc or audit you did not just write, and `slice` — per-line
def-use rows of ONE variable inside ONE definition, `flow=back|fwd|both` for the transitive data-flow
slice, `@FILE:LINE` seeds by location and pre-picks the variable the seed line names) + 12 flagship-reflex verbs
(`exemplar`, `quality_delta`, `quality_baseline`, `impact`, `uses`, `path_between`, `connect` — the
minimal joining subgraph over N task symbols — the L4 one-call/B11-parity trio `explore`, `from_trace`,
`edit_check` — so an MCP-only agent gets the same write & done reflexes as the CLI — and the CROSS-BRANCH
pair `whereis` / `stray_content`, which answer "where does this content live?" across every branch: the
question `git cherry` cannot, since it compares commit ancestry and every other verb indexes one worktree.
`stray_content` marks a branch `superseded` when the live line re-implemented its work, which is exactly
the case `git cherry` calls unmerged forever) + the 3 span-addressed
edit verbs (`replace_symbol_body`, `insert_before_symbol`, `insert_after_symbol`). Only `find_symbol` and
`find_referencing_symbols` attach a stable `handle=` instead of the body (fetch it only when you need it,
via `fetch_body`); the edit verbs enforce a safety contract (staleness refusal, ambiguity refusal, atomic
writes) detailed below and in full in [`mcp-reference.md`](mcp-reference.md).

## Wiring — `ripwire wrap <agent>` prints the recipe

```
ripwire wrap claude      # → claude mcp add ripwire -- ripwire --mcp
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

## The read verbs + fetch_body (and when each beats the CLI form)

Every verb takes `path` (the repo root; `memory_recall` takes the docs/memory dir). For a split
service+client checkout, pass `paths: [dir1, dir2, ...]` instead — the additive multi-root array (`path` and
`paths` together is a usage error; the 3 edit verbs accept it too, and land a write in the correct root's
real file via its label). The server keeps ONE cached workspace per canonical root set: a `paths` list is
deduped and ordered before it's used as the cache key, so calling with the same roots in a different order
still hits the warm cache instead of re-parsing; a genuinely different root set gets its own cache entry, not
a shared/stale one.

**Line-seeded addressing — `@FILE:LINE` in any resolver-backed selector.** Holding a LOCATION (a diff hunk,
a compiler error, a stack frame) instead of a name? Pass `@src/foo.cpp:120` (1-based line) as the selector
and it resolves to the innermost definition enclosing that line — accepted by `find_symbol` /
`find_referencing_symbols` / `impact` / `edit_check` / `path_between` (`from`/`to`) / `connect` (each entry) /
`lego` (`type`) / `fetch_body` (`handle`), and by `uses` (which serves the enclosing definition's NAME —
its sites stay name-matched, `of=` echoes the seed as typed). A bad seed — malformed spec, unmatched or
ambiguous path, line past EOF, a line no definition spans, two definitions sharing the line — is **refused
with the same specific diagnosis the CLI's `--at`/selector arms speak**, never guessed. The NAME-matching
scan verbs (`owners`, `mentions`) do not resolve seeds; a resolvable seed there refuses by naming the
definition it resolves to, so the retry is in the message. CLI twin: `--at=FILE:LINE` (the bare
enclosing-chain report) and `@FILE:LINE` in any SYM selector; contract gate: `test/atcheck.sh` +
`test/mcpverbscheck.sh` §7.

| Verb | CLI twin | Ask it for |
|---|---|---|
| `analyze` | `ripwire <dir>` | the ranked XML map |
| `for` (`task`) | `--for=TASK` | the task lens: signatures + cx/in metrics framed for reuse. **Auto-routes** the ranker — pass a symbol NAME verbatim as `task` to get name-exact retrieval (recall@1 ~99%); a conceptual phrase uses subtoken+body. Header prints `[routed: …]`. |
| `find_symbol` (`symbol`) | `--callers` + `--callees` | locate a symbol with its callers AND callees in one call — each symbol carries a `handle` |
| `find_referencing_symbols` (`symbol`) | `--callers=SYM` | just who references/calls it — also handle-bearing |
| `grep` (`pattern`) | `--grep=STR` | parallel literal scan + enclosing symbol + matched line |
| `cochange` (`file`) | `--cochange=FILE` | the lockstep git partners of one file |
| `memory_recall` (`task`, `top_k` + `budget_tokens` optional) | `--recall=TASK [--top-k=N] [--max-tokens=N]` | full bodies of the few relevant docs/memory notes, bounded by the SAME default 8000-token body ceiling as the CLI (the header discloses `max_tokens=` and every cut). `budget_tokens` raises the ceiling explicitly when you want everything; `top_k` (default 8) shapes how many docs |
| `situational_awareness` (`diff`/`files` optional) | `--situ` | blast radius, tests_to_run, forgotten co-change partners, hotspot alert — as JSON; defaults to `git diff HEAD` |
| `mentions` (`symbol`) | `--mentions=SYM` | which markdown plans/designs discuss a symbol |
| `owners` (`symbol` optional) | `--owners[=SYM]` | bus-factor: recency-weighted author ownership |
| `lego` (`type`) | `--lego=TYPE` | an interface's method contract + every implementor (own-language) |
| `fetch_body` (`handle`) | `--expand=SYM` | the FULL source of one symbol's definition, addressed by a `handle` from a prior read verb |
| `batch` (`queries`) | `--batch=FILE` | a one-turn context sweep: up to 16 heterogeneous read sub-queries (`for`/`grep`/`impact`/`uses`/`callers`/`callees`/`mentions`/…) answered in ONE round-trip, merged in order and deduped (`<dup-of q="i"/>`); a failing sub-query is an inline `ok="0"` entry, never a whole-batch failure. Reach for it when a task needs several lookups at once. |

**The flagship-reflex verbs** (added 2026-07 so an MCP-only agent gets the same reflexes as the CLI) — these are the moments an agent most often skips the tool for; reach for the verb, not a grep:

| Verb | CLI twin | The moment |
|---|---|---|
| `exemplar` (`kind` or `task`) | `--exemplar` | BEFORE you write a fn/class/… — the repo's best-in-class instance to imitate, chosen by ROLE (fan-in / cognitive-cx / tested), with its body |
| `quality_delta` (`path`) | `--quality-delta` | BEFORE you call it DONE — only what the working tree made WORSE vs the baseline (auto-compares vs git-HEAD; a non-empty `regressions` array is the exit-2-equivalent) |
| `quality_baseline` (`path`) | `--quality-baseline` | pin the quality floor (writes the HEAD-stamped `.ripwire_quality_baseline`) — a side-effect verb |
| `impact` (`symbol`, `limit`/`offset` optional) | `--impact=SYM [--limit=N --offset=M]` | "is it safe to change X" — the TRANSITIVE blast radius (beats `find_referencing_symbols`, which is 1-hop). `reaches=` is the true radius; the listing shows 40 by rank unless you raise it, and a paged answer carries `has_more`/`next_offset` so a loop can terminate |
| `uses` (`symbol`) | `--uses=SYM` | the resolvable USE-SITES — call/read/write/import/extends, not just calls (`count=0` is a real answer; `counts_floor="1"` — a floor, never a total) |
| `path_between` (`from`, `to`) | `--path=A,B` | does A reach B, and the shortest call path (named `path_between` — `path` is the root-arg key) |
| `connect` (`symbols`) | `--connect=A,B,C` | the minimal subgraph joining N (>2) task symbols — the shared-caller join a directed `path_between` can't see |
| `explore` (`task`, `budget_tokens` + `partition` optional) | `--pack-task=TASK [--partition=N]` | ONE-call task orientation — routed ranking + full bodies + 1-hop callers + field notes + tests_to_run, ALL under one deterministic byte budget (default 6000 tokens). Replaces the `for` → `fetch_body` → `find_referencing_symbols` → `memory_recall` dance. Also dispatchable as `pack_task` (same handler; `explore` is the one advertised in `tools/list` — the discovery-friendly name). **`partition: 2..16`** turns it into the FAN-OUT form for a multi-agent orchestrator: a shared common core plus N minimally-overlapping per-agent slices carved along the call graph's communities, so N sub-agents stop re-deriving one map — `budget_tokens` then means ONE agent's budget (core + its slice). Read `overlap_max` / `split` / `partitions` vs `requested` on the wrapper before trusting the slices |
| `from_trace` (`trace`, `budget_tokens` optional) | `--from-trace=FILE` | paste a stack trace / sanitizer report / compiler error → the frames mapped onto indexed symbols, ranked INNERMOST-first, with the innermost in-corpus symbol's FULL body. `trace` = the raw trace TEXT (no stdin/file arg over MCP — paste it, don't hand-translate it into a query) |
| `edit_check` (`symbol`) | `--edit-check=SYM` | just edited a symbol? did its CONTRACT (params/publicness) change vs git HEAD, and which 1-hop callers are now PROVABLY incompatible? Fast targeted check — for the same question over a whole diff use `quality_delta` instead |

**MCP beats the CLI when you're mid-task and will ask more than once**: the server keeps the parsed
{ingest, graph, rank} in memory, so after the first parse every verb answers warm (~ms, no shell
round-trip). **The CLI still wins for what no verb exposes** — `--expand`/`--outline`, `--around`,
`--deps`/`--hotspots`/`--clones`, `--graph-query`, `--arch`, `--pr-context`, `--scip`, `--lint-rules`,
`--export`, and the two remaining B11 verbs with no MCP twin — `--merge-scout` (multi-ref UX doesn't map
cleanly onto a single JSON-RPC call) and `--note-add`/`--notes` (a write verb; adding it needs the same
safety-contract thinking the 3 edit verbs got) — shell out for all of these even with the server running;
the on-disk warm cache keeps them fast too.

**Team/CI: commit the warm cache as an index artifact.** `ripwire <dir> --index-out=BASE` cold-parses once,
writes `BASE.lean.ripwirecache` + `BASE.rich.ripwirecache` (`--for`/`--exemplar`/`--metrics` need RICH), then
exits with no map. Generate on main, commit or CI-cache it, restore with `--cache=BASE.lean.ripwirecache` (or
`.rich.`) in PR jobs so only changed files re-parse — a same-arch SPEED cache that self-heals to a cold parse
if stale or cross-arch (correct, slower). See README "The committable index artifact".

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

## The 3 MCP edit verbs — the warm-server counterpart to the preferred CLI

`replace_symbol_body`, `insert_before_symbol`, `insert_after_symbol` — the last 3 of the 30 (see above),
ripwire's MCP WRITE verbs. The preferred shell front door is
`ripwire ROOT --replace-symbol-body=SYM --edit-payload=FILE|-` (or the matching insert flag); use MCP when
the server is already warm or a client has no shell. Both fronts call the same safety engine. Each locates
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
session**; after a CLI `--expand`, keep the zero-standing-schema CLI path and use `--edit-payload=-`.
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
