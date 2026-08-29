---
name: ripwire-efficient
description: >
  A token + accuracy DISCIPLINE for ANY read, not a moment: map before you open files. Reach for it the
  instant you catch yourself about to open more than ~2 files to figure something out — anywhere in a task.
  Also the moment you catch yourself typing "let me search the codebase", "let me read that file", or
  "let me look at a few files first": that sentence IS the trigger. File reads dominate an agent's token
  cost, and less context is measurably MORE accurate, not just
  cheaper; a small ranked map beats a fan-out of whole-file reads on both. Code-repair accuracy fell
  29% → 3% as context grew 32K → 256K tokens (LongCodeBench), so "read a few more files to be safe" is
  the instinct this replaces, not a safe default. The reflex is one line: run the
  cheapest verb that answers the question, then read only the 2-3 files it ranks highest. Fires ALONGSIDE
  the moment skills (orient, navigate, change-check…), never instead of them. Backed by ripwire
  (deterministic, on PATH).
allowed-tools: Bash, Read
---

# Be token-efficient with ripwire

> Routing — this is the cross-cutting discipline; for the specific MOMENT, use its skill:
> • Cold-start / "how does X work / where is Y" (the understand moment) → **ripwire-orient**.
> • Tracing one call graph / locating a literal → **ripwire-navigate**.
> • Not sure which skill at all → **ripwire-router**.

Reading files is the single biggest token sink in an agent loop, and exploratory reads
snowball — every verbose read inflates every later step. `ripwire` (on PATH) replaces exploratory reads with
a deterministic, PageRank-ranked map. The discipline is one line: **map before you read.**

## Why this isn't just about cost — it's about accuracy

This is the load-bearing fact, not a nice-to-have: **less context is more accurate, not just cheaper.**
- Code-repair accuracy **collapses with context size**: Claude 3.5 Sonnet went **29% → 3%** on LongSWE-Bench
  as context grew 32K → 256K tokens (LongCodeBench, arXiv:2505.07897). A newer, independent result agrees:
  with localization held constant, compressed source reached the same editing accuracy at roughly 3.7×
  fewer tokens than whole-file context (arXiv:2607.09691).
- A **~300-token** focused prompt **beat** a **~113K-token** full-file dump on the same task (Chroma
  context-rot study, 2025) — more context didn't just cost more, it made the model worse.
- Position matters: actionable content at the END of a long input measured **up to +30%** (Anthropic) — the
  evidence behind `--order=important-last` (formerly `--most-important-last`, still a working alias)
  for large maps.
- On the public Loc-Bench benchmark (n=560), `--for`'s focused bundle put the right file in the top-10
  **~4.5×** as often as raw `--query` BM25 — a small ranked map beats a flat lexical dump on someone else's
  scoreboard too.

A small ranked map isn't a compromise for speed — it's *more likely to get the right answer* than pasting in
everything that might be relevant. The "just `cat` three files to be safe" instinct is the one this evidence
contradicts.

## Defaults to break

An affirmative catalog of verbs competes badly with a habit: an agent that already knows how to open a
file does not weigh a list of alternatives against it. So the discipline is stated as prohibitions, and
the table below is what you reach for *instead*.

- **Do NOT open a file you have not located first.** Rank with `--for`/`--grep`, then read what it names.
- **Do NOT read a whole file to understand one symbol.** `--expand=SYM` returns the body plus its callees'
  signatures; the file it happens to live in is not the unit of an answer.
- **Do NOT Read whole-file just because you're about to Edit.** The CLI is the default write path: pipe or
  name the complete definition with `ripwire ROOT --replace-symbol-body=SYM --edit-payload=FILE|-` (or
  `--insert-before-symbol` / `--insert-after-symbol`). It uses ripwire's ambiguity, freshness, symlink,
  mode-preservation and atomic-rename checks, so no preparatory whole-file Read is needed. Add
  `--edit-target-file=PATH` only to disambiguate. If an MCP session is already warm, its same-named edit
  verbs use the same engine; see ripwire-mcp. For several edits, put 1–64 operations in one JSON manifest
  and preflight the whole transaction with `--edit-plan=FILE --dry-run`; use the same plan with `--apply`
  only after the receipt is right. Every target and payload is checked before the first per-file atomic
  write, same-file spans may not overlap, and the receipt explicitly discloses that a crash between files
  is not multi-file atomic.
- **Do NOT fan reads across several files to learn one thing.** `--pack-task="<task>"` answers in ONE
  budgeted call.
- **Do NOT hand-translate a stack trace into a search query.** `--from-trace=FILE` takes it verbatim.
- **Do NOT infer structure by reading build files and imports.** `--deps`/`--report` derive it.

The tell that you need this is linguistic, not architectural: if you just thought *"let me search the
codebase"*, *"let me read that file"*, or *"let me look at a few files first"*, that sentence is the
trigger. The same prohibitions ship in the always-loaded `ripwire wrap` primer (`src/wrap.h`), so an agent
that never opens this file still meets them.

## The reflex
Before you open more than ~2 files to answer a question, run the cheapest verb that answers it — THEN read
only the files it surfaces.

| You need… | Cheapest move (not a file read) |
|---|---|
| the code for a specific task | `ripwire <dir> --for="<task in words>"`  ·  `--report` — header says `weak="1"` when the top match's lexical evidence is thin; reformulate rather than trust that ranking |
| a symbol you can NAME | `ripwire <dir> --for="theExactName"` — auto-routes to name-exact BM25 (recall@1 ~99%) |
| recall what's already known | `ripwire <dir> --recall="<task>"` (docs/plans/memory, full bodies) |
| who calls / what it calls | `--callers=SYM` · `--callees=SYM` |
| the recorded uses of a name (read/write/import; a floor — see counts_floor=) | `--uses=SYM` |
| a literal / regex / code-shape | `--grep=STR` · `--regex=PAT` · `--pattern='foo($X, ...)'` (shape as CODE) · `--match='(<tree-sitter>)'`. Add `--handles` to grep/regex when the next action is a safe CLI edit: each unambiguous enclosing symbol gets a content-addressed target accepted directly by the edit verbs; ambiguous/uneditable rows say why and mint no unsafe handle. |
| you HAVE a stack trace / sanitizer report / compiler error | `--from-trace=FILE` (`-`=stdin) — pipe the raw text in, don't hand-translate frames into a query |
| a question the fixed verbs don't have | `--graph-query='and(callers(name("X"),2),kind(all,fn))'` |
| ONE symbol in full | `--expand=SYM` (body + inline callee sigs) — not its whole file. Add `--compress` for ~20-35% off the body |
| signatures only | `--pack-signatures` (bodies already elided — `--compress` is a no-op here; it affects SERVED BODIES: `--expand`/`--outline`, `--for`'s auto/anchor and `--detail=N` bodies, `--pack-task`, `--from-trace`, `--exemplar` — disclosed as `compress="1"` on the `<bodies>` element) |
| a FLAT-LIST verb's output, cheaper | `--format=columnar` on `--callers`/`--callees`/`--uses`/`--impact`/`--pr-context` — a `<paths>` table + parallel name/line/kind arrays instead of repeated per-row markup, ~50%+ fewer tokens, same data. The map itself is unaffected — this only reshapes the flat-list verbs. |
| `--for`/grep/regex schema prose is already known | `--legend=compact` — keep the evidence rows and emit a versioned schema id instead of repeating the full legend. Default/`--legend=full` remains byte-compatible; compact is for a consumer that already knows that schema version. |
| `--for`/`--query` returning more than you need | `--adaptive` — cuts the ranked result at the relevance CLIFF (largest relative score gap) instead of a fixed top-k; a sharp query returns few, a flat/broad one still hits the ceiling. Prints `[adaptive: kept K of N ...]` so you can see the cut. |
| readable bodies for ONLY the relevant head of `--for` | `--detail=N` — full bodies for the top-N ranked symbols + signatures for the rest, in ONE call (measured +63% tokens for the 3 relevant heads vs +355% for all-bodies). Spend body detail on the head the rank identifies; composes with `--max-tokens` (bounds the bodies) and `--adaptive`. |
| SEVERAL lookups a task needs at once, in one shot | `--batch=FILE` (`-`=stdin): newline `verb:arg` sub-queries (`for`/`grep`/`impact`/`uses`/`callers`/`callees`/`mentions`/…) answered in ONE deduped `<batch>` — the deterministic one-turn context sweep. Identical payloads collapse to `<dup-of q="i"/>` so a symbol surfaced by two sub-queries is emitted once. The MCP `batch` verb is the round-trip-saving form for agents. |
| the WHOLE orientation for a task, budgeted, in ONE call | `--pack-task="<task in words>"` — assembles the usual 3-5 call dance (`--for` ranking → top-K full bodies → their 1-hop callers → their field notes → `tests_to_run`) under ONE deterministic budget (default 6K tokens; `--token-budget=N` overrides), in a FIXED section order. Each section truncates rank-adaptively and the header REPORTS every truncation (no silent caps); a tiny budget degrades to ranking-only. Reach for it as the first move on a new task instead of firing `--for` then `--expand` then `--callers` then `--affected` yourself — one call, one budget, one round-trip. |
| the same task about to FAN OUT to N parallel agents | `--pack-task="<task>" --partition=N` (N=2..16) — one call returns a shared common core plus N per-agent slices carved along the call graph's communities, instead of N agents each re-deriving the same orientation. `--token-budget` becomes ONE AGENT's budget (core + its slice); each `<bundle>` is handed to one agent verbatim. Check `overlap_max` / `split` / `partitions` vs `requested` on the wrapper before trusting the split — a task whose surface sits in one module is not partitionable and says so. |
| the same fan-out, but you need to know which lanes would COLLIDE | `--plan-lanes=N --task="<goal>"`, or `--plan-lanes --brief=FILE` with one line per lane — a deterministic JSON plan: per-lane claimed symbols/files, predicted `conflicts` (same claim key on two lanes), `same_file_risk`, `contract_touch` (a claim inside another lane's blast radius — NOT a merge conflict), `landing_order`, and per-lane `tests_to_run`. `--partition` splits the work; this predicts the collisions BEFORE a line is written. Read `warnings[]` first: `lane-claims-coincide` means the carve handed the same symbols to two lanes and its conflicts are an artifact, not work. Prefer `--brief` when your task has enumerable parts — the auto-carve balances the RANKING and can leave a part in no lane. |
| a SCRIPT/CI step parsing the output, not an agent reading it | `--json` — the same content as the XML, machine-parseable (keys mirror the XML attr names 1:1), for the default map, `--for`, `--pack-task`, `--callers`/`--callees`/`--impact`, `--quality-delta`, `--test-gate`. Every other verb refuses loudly (stderr + exit 1) rather than silently falling back to XML. Pipe it straight to `jq`: `ripwire . --quality-delta --json \| jq '.regressions'`. |
| a VISUAL of the bundle's own anchor neighborhood | `--with-graph` (with `--for`/`--pack-task`) — appends a small `<graph fmt="mermaid">` block (top-8 ranked anchors + their 1-hop call edges) right before `</ctx>`. It's PURE ADD — more tokens on top of the sigs you already paid for — so only reach for it when the calling agent actually renders mermaid (a multimodal/diagram-aware reader); a text-only reader gets no benefit from the extra bytes. Off by default. |

Choosing HOW MUCH detail to pull (the full skeleton→outline→body ladder, `--compress`'s exact scope, when
NOT to compress, and the default credential redaction on emitted bodies / `--no-redact` opt-out) →
**[`compress-ladder.md`](compress-ladder.md)**. Load it once you've picked the file(s) from the map above and
are deciding how much of them to read.

## Cost calibration (stay honest)
- **First call on a tree parses (~1s); every call after is warm (~instant).** A follow-up query is nearly
  free — chain several rather than reading one big file.
- **Portable indexes for a cold team/CI:** `ripwire <dir> --index-out=BASE` cold-parses once, writes
  `BASE.lean.ripwirecache` + `BASE.rich.ripwirecache`, exits without a map. Restore lean for
  map/navigation/PR-context work, rich for exemplar/metrics/uses, via `--cache=PATH`. A plain `--cache=PATH`
  stays useful for a repeated local query; `--index-out` is the generate-once artifact workflow.
- Budget a large map: `--max-tokens=8000` or `--top-k=50`. `est_tokens` is calibrated per language against
  real tokenizer output, not a flat chars/4 guess, and `--max-tokens` fits to 90%-of-budget headroom — a
  ceiling, never a target you pad against.
- **CI/hook budget gate, not a shaping flag:** `--token-budget=N[K|M|G]` asserts instead of fitting — exit 3
  if `est_tokens` exceeds N, map unchanged. Use it to fail a build/hook on drift; `--max-tokens` SHAPES
  instead. Composable: set either, both, or neither.
- **A high-cardinality verb paginates**: `--deps`/`--callers`/`--callees`/`--hotspots`/`--tree`/`--lint` take
  `--limit=N --offset=M` — sorted results, so `--offset=N` after `--limit=N` is the exact continuation, no
  drops/dupes. Default (no `--limit`) is the whole result; reach for pagination on a big monorepo instead.
- **Spans a service+client split?** `ripwire dir1 dir2 <verb>` merges 2..16 checkouts into ONE labeled map —
  cheaper than reading each repo separately and cross-referencing an include/import by hand.
- ripwire shines on **specific technical** asks. For a **broad common-word** question, plain `rg` + one read
  can still win — use judgment, don't force it.
- Trust the calibration: `amb="K"` / header `ambiguous=N` = the resolver guessed on K calls → read the source
  before relying on a high-`amb` edge.

> For a cold-start *understand-this-whole-repo* task specifically, **`ripwire-orient`** has the full top-down
> recipe (it owns the understand moment). This skill is the cross-cutting token *discipline* for **any**
> information need — reach for it even mid-task, the moment you're about to open several files just to learn
> something.
