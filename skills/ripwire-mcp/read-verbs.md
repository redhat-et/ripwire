# ripwire-mcp — reference: read-verbs (read on demand; the recipe is in SKILL.md)

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
| `for` (`task`) | `--for=TASK` | the task lens: signatures + cx/in metrics framed for reuse. **Auto-routes** the ranker — pass a symbol NAME verbatim as `task` to get name-exact retrieval (recall@1 ~99%); a conceptual phrase uses subtoken+body. Root carries `route=` as a code (`name-exact(X)` / `subtoken+body[:broad\|:declined]`). |
| `find_symbol` (`symbol`) | `--callers` + `--callees` | locate a symbol with its callers AND callees in one call — each symbol carries a `handle` |
| `find_referencing_symbols` (`symbol`) | `--callers=SYM` | just who references/calls it — also handle-bearing |
| `grep` (`pattern`) | `--grep=STR` | parallel literal scan + enclosing symbol + matched line |
| `cochange` (`file`) | `--cochange=FILE` | the lockstep git partners of one file |
| `memory_recall` (`task`, `top_k` + `budget_tokens` optional) | `--recall=TASK [--top-k=N] [--max-tokens=N]` | full bodies of the few relevant docs/memory notes, bounded by the SAME default 8000-token body ceiling as the CLI (the header discloses `max_tokens=` and every cut). `budget_tokens` raises the ceiling explicitly when you want everything; `top_k` (default 6) shapes how many docs |
| `situational_awareness` (`diff`/`files` optional) | `--situ` | blast radius, tests_to_run, forgotten co-change partners (the Shotgun Surgery check), hotspot alert — as JSON; defaults to `git diff HEAD`. In `tests_to_run`, `situational_awareness` uses `test`; `explore` and edit receipts use `p`. The field is a path string OR an **array** of paths beside `n` — several runner-less tests sharing their attributes, served as one row — and every row carries `run` or `run_unknown: true` |
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
