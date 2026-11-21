# ripwire-orient — reference: ladder (read on demand; the recipe is in SKILL.md)

# Orient with ripwire

> Routing — pick the right door:
> • Tracing one call graph / locating a literal → **ripwire-navigate**.
> • Vetting your OWN diff before you push → **ripwire-change-check**.
> • Risk in code you did NOT write / an unfamiliar subsystem → **ripwire-fresh-eyes**.
> • Map-before-you-read token discipline (any info need, mid-task) → this skill's companion **[`map-before-you-read.md`](map-before-you-read.md)** (folded in from the former `efficient` skill, 2026-09-07).
> • Deep architecture-health read (deps metrics, layering rules, --arch gate) → **ripwire-layers**.
> • Not sure which skill? → **ripwire-router**.

`ripwire` is on your PATH. First call on a tree parses (~1s even at 1500 files); every call after is warm
(auto-cached, ~instant), so chaining several rungs is nearly free. `<dir>` = the repo root or the specific
subsystem you're working in — also accepts a remote `ripwire <git-url>` (shallow-clones to a temp cache, so
you can orient in a dependency before ever cloning it) — or several roots for a split checkout,
`ripwire dir1 dir2 --report`: ONE merged, root-labeled map instead of two separate mental models.

**Orient ONCE per session, then look up lean.** Plain `ripwire <dir>` is the one-call orient: the ranked map with
the subsystems, the program entries and every file the ranking left out (`<inv>`). Only that call carries `<inv>`:
a `--for`, `--expand` or `--max-tokens` map does not, and `--max-tokens` drops the tier (use `--top-k` to keep it).
After it, `--expand` / `--outline` / `--whereis` / `--callers` answer with no ride-along map. If you skipped the
orient step, the `map_next=` on an `--expand` root is the call that prints it.

## The escalation ladder — climb only until you feel oriented

**0. Recall what you already KNOW** — `ripwire <dir> --recall="<the task>"`
The most relevant DOCS' FULL bodies (docs only, so code never swamps them — markdown memory notes,
planning/design docs, skills, READMEs, plus `.ipynb`/`.html`/`.csv`/Office/PDF via the optional
markitdown bridge). Point it at the **memory dir** for what past sessions learned, or the **repo root** for
plans/designs — ~47× fewer tokens than loading everything. A design doc may already answer the question; if
so, stop here. It also works unmodified as a zero-setup knowledge base over a scratch dir of dumped tool
output (a git log, fetched docs, `--help` text) — not just a source repo. Two conditions are yours to meet
when you WRITE the dump: dump it as `.md` (`.txt`/`.log`/`.json` are not documents to `--recall`, and a dir
of them answers `0 relevant of 0 document files`), and keep `##` headings in it, so a deep answer is served
as a ranked section instead of waiting behind a front-first cut. Raising `--max-tokens` then grows what ONE
already-served document gets — that per-document guarantee is not global: dump several documents into one
dir and admitting another one re-divides the shared budget, which can shrink an already-served document's
own slice (`share_bytes=` in the header discloses it). Full form in
[`map-before-you-read.md`](map-before-you-read.md); the recorded run is `docs/COMMANDS.md`'s `--recall`
pattern subsection.

**1. Architecture summary** — `ripwire <dir> --report`
Plain markdown: file + symbol count, call-graph modules (Louvain clusters with lead symbol), god-files
ranked by `afferent` (dependents), cycle list, top PageRank symbols. **Read the god-file list carefully** —
highest-leverage, highest-risk files. For most "orient me" asks this one rung is enough.

**2. Task-relevant code** — `ripwire <dir> --for="<the task in your own words>"`
Ranked signatures + doc-comments + cx/in metrics by relevance (matches names, docs, AND bodies — not just
identifiers). This is the rung that answers "where's the code for X".
**What the bundle serves depends on which way the query routed, and the root says which.**
*Named a symbol* (`bundle="auto" bodies="N"`): the anchor's FULL body rides inline, CDATA plus callee
signatures — **read it here instead of opening the file the map named**, that follow-up read is the cost
this default deletes. `bodies="0" reason="budget"` means it did not fit whole.
*Conceptual phrase* (`bundle="compact" bodies="0" reason="compact-route"`): no bodies — you get the ranked
map plus a `<hops>` section, one row per top-ranked symbol with its one-hop callee names. **Read the map,
pick ONE symbol, then `--expand=path:name`** (paste the row's own path and name — `path:L-E name` on a line row, `p=` and `n=` on an XML row; `--rows=elements` serves every row as XML; a bare name that is not
unique serves every definition, still without the map). That is the flow, and it is cheaper than the bodies were: half the bytes
of the old bundle on conceptual queries, and the edges tell you which symbol is worth the second call.
`--auto-bodies` restores inline bodies on that route if you want them; `--signatures-only` drops both
shapes; `--detail=N` picks the body count explicitly.
**Composing a selector out of a row** (the map's rows and `--for`'s alike): a scoped row carries `sc=`, its
enclosing scope, instead of repeating its whole id — the canonical id is `p::sc::n`, assembled from the
row's own `p=` (or the `<f p=>` it sits under), `sc=` and `n=` (a `--for` line row spells them `path:L-E name sc=scope`). Every selector (`--expand`, `--callers`,
`--impact`, `--uses`) accepts that composed `path::scope::name`, so paste the three parts, not a bare name.
`--for` **auto-routes** (default, no flag needed): a query that *names a symbol* (`--for="buildGraph"`) gets
name-exact BM25 (recall@1 ~99% vs ~77% generic) — **know the name, query it verbatim**; a conceptual phrase
uses subtoken+body BM25 instead. The header prints which ranker fired; `--no-route` forces the plain ranker.
**Asking in a sentence? Backtick the code.** "Which functions call `pkg.Fn` and must change?" gets `<callers by="subject">`,
and "the call chain from `A` to `B`" / "what calls both `A` and `B`" get the `<graph_verb>` path or connect block, as the bare
names do. When a sentence's answer ends with `<reask next="--callers=X"/>` (`--impact=X` for a change question, or `--path=A,B`)
instead, run that bare call: it is the one that answers the question. A hand-off marked `windows="1"` appended no page because the
verb's default call would list only the first 40 of `next_total=` rows: run its `next=` as written (`--format=columnar
--limit=<next_total>`), the one call that lists every row, instead of paging.
It also **anchors query mentions** by default — a file/module/`Type.method` literally named in the task text
gets lifted near the top (+4.9pp held-out; a task naming nothing indexed is byte-identical); disable with
`--no-mention-boost`. It also surfaces DOCS: a markdown design/plan doc that `backtick`-names one of the
query's top-resolved symbols is lifted into the bundle too (strictly below that symbol's own score) — the
doc explains it even when its own prose shares no words with your query; disable with `--no-doc-mention`.
**When the answer comes back THIN, widen before you read.** A thin `--for` answer — the head spread over
fewer than three files, or `coverage=` under 50 — says so on the root: `coverage="N"` is the IDF-weighted
share (whole percent) of your query's subtokens found in the top-ranked symbol's name, doc or body, and it
rides the root **only** on a thin answer (a confident one carries neither the attribute nor its clause).
The step then is not a body, it is a wider net: `ripwire <dir> --for="<task>" --limit=40` serves the
FILE-GRAIN page — one row per file holding any positive-score symbol, `score=`/`n=`/`sym=` per row,
`--offset=M` for the next page. A thin answer's own `next=` names that page for you; reach for it on the
FIRST call when the task is vague enough that one ranked head is unlikely to hold the answer.
`--adaptive` cuts the result at the relevance cliff instead of a fixed top-k. Same
routing in the MCP `for` verb. Orienting from a pasted issue/bug-report's own text? `--anchor` beats plain
`--for` on Loc-Bench (n=560) — a mild win, not a default (`bench/locbench/README.md`). `--cochange-boost` is
an experimental, off-by-default co-change prior — see `ripwire --help` before reaching for it.

**3. File-by-file map** — `ripwire <dir> --tree --legend=compact` — each file with its top symbols, a quick "what's where".

**4. Cohesive modules** — `ripwire <dir> --communities --legend=compact` — `<communities modules="N">`, each cluster with its
dominant directory and lead symbols; `<bridge>` edges show tight coupling between clusters. Use it to decide
where a new feature belongs. Each row shows only its top five members — to see one module in full,
`ripwire <dir> --community=ID --legend=compact` (the `id=` from a row, or from `--zoom`): its complete ranked member list
(`--limit`/`--offset` page it) plus every bridge edge that module has. That is the call to make when a
cluster looks like the one you'll be working in and five names aren't enough to judge it.

**5. Maintenance pain** — `ripwire <dir> --hotspots --legend=compact` — files ranked by `score = churn × ccx`; `top=` names
the gnarliest function. Plan edits around this list.

**6. Budget it** if the map is large — `--max-tokens=8000` or `--top-k=50`. Both shape the default map;
a positive, explicit `--top-k` is inert on plain `--for` (it warns on stderr and emits the full bundle) —
bound a `--for` call with `--signatures-only`, `--token-budget=N` or `--detail=N` instead.
When the ranked rows leave files out, the map ends with `<inv>`: the program entries (`<entry>`, by each language's entry convention)
and every unshown file, named or counted per directory (`<ls>`). Read it before concluding a file or entry point is
not there; `--no-inventory` drops it (the rows are unchanged), and so does `--max-tokens` — `--top-k` keeps it.
