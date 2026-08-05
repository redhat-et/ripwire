---
name: ripwire-orient
description: >
  Understand an unfamiliar codebase or subsystem FAST, before editing. Use the moment you land cold in a
  repo (new to the team, about to pick up a ticket), need the lay of the land, main subsystems and entry
  points, are asked "how does X work / where is Y / what matters here", or need an architecture OVERVIEW
  (structure: what's here, how it's organized) or a nested module map — or a gotcha worth remembering for
  the next session (--note-add). Runs ripwire (the deterministic
  "ripgrep of AI context", on PATH) to MAP the code — an escalation ladder from a one-screen report up to
  communities, nested zoom, and a rendered diagram — instead of blind grep + whole-file reads. Prefer this
  over reading many files when orienting. A NAMED symbol's deep-dive (its own contract/callers/callees, not
  the whole subsystem) → ripwire-navigate instead. For architecture HEALTH/enforcement (propagation cost,
  layering violations, CI gates) → ripwire-layers instead. Stop at the first rung that answers — the
  one-screen report usually does; climb the ladder only while the question is still open.
allowed-tools: Bash, Read
---

# Orient with ripwire

> Routing — pick the right door:
> • Tracing one call graph / locating a literal → **ripwire-navigate**.
> • Vetting your OWN diff before you push → **ripwire-change-check**.
> • Risk in code you did NOT write / an unfamiliar subsystem → **ripwire-fresh-eyes**.
> • Map-before-you-read token discipline (any info need, mid-task) → **ripwire-efficient**.
> • Deep architecture-health read (deps metrics, layering rules, --arch gate) → **ripwire-layers**.
> • Not sure which skill? → **ripwire-router**.

`ripwire` is on your PATH. First call on a tree parses (~1s even at 1500 files); every call after is warm
(auto-cached, ~instant), so chaining several rungs is nearly free. `<dir>` = the repo root or the specific
subsystem you're working in — also accepts a remote `ripwire <git-url>` (shallow-clones to a temp cache, so
you can orient in a dependency before ever cloning it) — or several roots for a split checkout,
`ripwire dir1 dir2 --report`: ONE merged, root-labeled map instead of two separate mental models.

## The escalation ladder — climb only until you feel oriented

**0. Recall what you already KNOW** — `ripwire <dir> --recall="<the task>"`
The most relevant DOCS' FULL bodies (docs only, so code never swamps them — markdown memory notes,
planning/design docs, skills, READMEs, plus `.ipynb`/`.html`/`.csv`/Office/PDF via the optional
markitdown bridge). Point it at the **memory dir** for what past sessions learned, or the **repo root** for
plans/designs — ~47× fewer tokens than loading everything. A design doc may already answer the question; if
so, stop here.

**1. Architecture summary** — `ripwire <dir> --report`
Plain markdown: file + symbol count, call-graph modules (Louvain clusters with lead symbol), god-files
ranked by `afferent` (dependents), cycle list, top PageRank symbols. **Read the god-file list carefully** —
highest-leverage, highest-risk files. For most "orient me" asks this one rung is enough.

**2. Task-relevant code** — `ripwire <dir> --for="<the task in your own words>"`
Ranked signatures + doc-comments + cx/in metrics by relevance (matches names, docs, AND bodies — not just
identifiers). This is the rung that answers "where's the code for X".
`--for` **auto-routes** (default, no flag needed): a query that *names a symbol* (`--for="buildGraph"`) gets
name-exact BM25 (recall@1 ~99% vs ~77% generic) — **know the name, query it verbatim**; a conceptual phrase
uses subtoken+body BM25 instead. The header prints which ranker fired; `--no-route` forces the plain ranker.
It also **anchors query mentions** by default — a file/module/`Type.method` literally named in the task text
gets lifted near the top (+4.9pp held-out; a task naming nothing indexed is byte-identical); disable with
`--no-mention-boost`. It also surfaces DOCS: a markdown design/plan doc that `backtick`-names one of the
query's top-resolved symbols is lifted into the bundle too (strictly below that symbol's own score) — the
doc explains it even when its own prose shares no words with your query; disable with `--no-doc-mention`.
`--adaptive` cuts the result at the relevance cliff instead of a fixed top-k. Same
routing in the MCP `for` verb. Orienting from a pasted issue/bug-report's own text? `--anchor` beats plain
`--for` on Loc-Bench (n=560) — a mild win, not a default (`bench/locbench/README.md`). `--cochange-boost` is
an experimental, off-by-default co-change prior — see `ripwire --help` before reaching for it.

**3. File-by-file map** — `ripwire <dir> --tree` — each file with its top symbols, a quick "what's where".

**4. Cohesive modules** — `ripwire <dir> --communities` — `<communities modules="N">`, each cluster with its
dominant directory and lead symbols; `<bridge>` edges show tight coupling between clusters. Use it to decide
where a new feature belongs. Each row shows only its top five members — to see one module in full,
`ripwire <dir> --community=ID` (the `id=` from a row, or from `--zoom`): its complete ranked member list
(`--limit`/`--offset` page it) plus every bridge edge that module has. That is the call to make when a
cluster looks like the one you'll be working in and five names aren't enough to judge it.

**5. Maintenance pain** — `ripwire <dir> --hotspots` — files ranked by `score = churn × ccx`; `top=` names
the gnarliest function. Plan edits around this list.

**6. Budget it** if the map is large — `--max-tokens=8000` or `--top-k=50`.

## Orienting N agents at once, not yourself — `--partition=N`

About to fan a single task out to several parallel agents? Do **not** let each one run its own
`--pack-task` — they will each re-derive the same top symbols, the same bodies, the same tests, and you
pay for the map N times. Run it **once**:

```bash
ripwire <dir> --pack-task="<the task in words>" --partition=4
```

You get one `<ctx-partitions>` document: a **shared common core** (the anchors the task is literally about,
what every agent needs) plus **N per-agent slices** carved along the call graph's own Louvain communities,
so a slice is a union of whole modules rather than an arbitrary rank cut (symbols the call graph is silent
about — edgeless data types — group by *file* instead, so one header's structs stay together). Each `<bundle>` wraps a complete,
standalone bundle — hand one bundle to one agent verbatim. `--token-budget` here means **one agent's**
budget (core + its slice), not the document's; `--json` gives the same plan machine-readably. MCP: the same
thing as a `partition` argument on the `explore` verb.

**Read the wrapper attributes before you trust the split** — the verb reports its own quality:
`overlap_max` (worst pairwise Jaccard between slices; low = the agents really are reading different code),
`split="K"` (K>0 means there were fewer modules than agents, so a module was cut at its rank median — the
slices are less semantically clean), `partitions` < `requested` (the task's surface could not supply N
separable slices at all — take fewer agents), and `core_overlap` (how much of the core a slice reaches
anyway). On a task whose whole surface sits inside one module, a partition is a rank cut, not a module
boundary — one `--pack-task` and one agent is the honest answer there.

## When a flat module list is too coarse (big repos) — zoom out

**7. Nested module hierarchy** — `ripwire <dir> --zoom` (`--zoom=DEPTH` to cap levels): multi-level Louvain,
`<module level=N id= size= dir=>`, indent = one level deeper, innermost `level="0"` lists top-ranked members.
Read top-down; a `dir=` that doesn't match its parent's is a cross-cutting concern in the wrong place.
Trailing `<bridge …>` entries name the high-traffic integration seams *between* top modules — pair with
`--seams` to see which ones no test reaches.

**8. Render it** — `ripwire <dir> --zoom --mermaid` (or `--mermaid` for the flat module graph): a
`flowchart TB`, paste at mermaid.live. For hand-exploring, `ripwire <dir> --html[=FILE]` writes a
self-contained clickable wiki (module cards → subgraphs → Sourcetrail-style node recentering, no CDN).
Working inside a `--for`/`--pack-task` bundle instead of a whole-repo pass? Add `--with-graph` to that
same call — it appends a tiny `<graph fmt="mermaid">` block (top-8 ranked anchors + their 1-hop call
edges) right in the bundle, no second call.

**9. Export it** — `ripwire <dir> --export=cc.json[:FILE]` — per-file metrics (loc, cx, fan-in/out, churn) as
a CodeCharta `cc.json` for its 3D city view; the ladder's visualization end-point, not a map to read.

## Then read, and trust the honesty signals

**Read the specific files ripwire surfaces** (god-files + hotspots first) — don't grep blindly. A symbol's
`amb="K"` means K of its calls are ambiguous (the resolver guessed) → read the source if which-target
matters. Caveat: *broad, common-word* questions can still favor plain `rg` — ripwire shines on specific
technical asks. CI-enforceable module boundaries graduate to `--arch=rules.txt` (see **ripwire-layers**).

## Leave a note for next time — the gotcha you just learned (field notes)

The most expensive thing you rebuild across sessions is **gotchas, not structure**. When you learn a
non-obvious fact about a symbol or file (a race trap, an off-by-one seam, "don't touch this without
re-running X"), pin it so the *next* orientation surfaces it automatically:

```bash
ripwire . --note-add="src/foo.cpp::Bar::compute: recompute is NOT idempotent — reset the arena first"
ripwire . --note-add="src/pool.h: 128-byte cache line on Apple, never hardcode 64"   # a file also works
```

The TARGET is a canonical id (`path::scope::name`, as `--for`/`--expand` print it in `id=`) or a file path.
Notes live in committed `.ripwire_notes` and **surface on their own** — whenever `--for`/`--expand` emit that
symbol/file, the note rides along as a `<note d="date">…</note>` child. `ripwire . --notes` lists every note
(`dangling="1"` = target no longer in the tree). `--recall=TASK` is the doc-level complement.
`--note-add` nudges (stderr, non-blocking) toward writing the decision, not a description — a note that
keeps firing on the same symbol has outgrown a comment: graduate it into a `--quality-ack` reason or a
standing `--arch` deny rule.

## Resuming — a compaction, or a new session on work already in flight

A different moment from a cold start: you are **not** cold on the repo, you are cold on **your own last
hour**. The task is known; what evaporated is the reasoning, the gotchas already paid for, and what you had
half-changed. Re-reading source rebuilds the *least* valuable of those. Run the three verbs that rebuild the
rest, in this order:

```bash
ripwire . --recall="<the task, in the words you'd use>"   # 1. what past sessions WROTE DOWN
ripwire . --situ                                          # 2. what the working tree already CHANGED
ripwire . --notes                                         # 3. gotchas already paid for
```

1. **`--recall`** returns the *full bodies* of the most relevant markdown only — memory notes,
   planning/design docs, READMEs — so code can't swamp them. This is the decisions-and-rationale layer that a
   compaction destroys and that source code never contained in the first place. Point it at your memory dir
   for past-session memory, or the repo root for the project's plans.
2. **`--situ`** (defaults to `git diff`) tells you what you had already changed, its blast radius, the tests
   to run, and the co-change partners you hadn't touched yet — i.e. where you actually stopped, and what you
   were about to break. This is the step that most often reveals work-in-flight you would otherwise redo.
3. **`--notes`** lists every pinned gotcha (`dangling="1"` = its target is gone). Anything relevant will also
   re-surface on its own once `--for`/`--expand` emit that symbol — see the section above.

Then, and only then, escalate the ladder for whatever is still missing. Two honest cautions: `--recall`
returns what the docs **claim**, not what is still true — a stale plan doc reads exactly as confidently as a
current one, so trust `--situ`'s working-tree facts over a doc when they disagree. And `--situ` carries **no
`at=` commit stamp**, so if you are resuming across a rebase or a moved HEAD, record `git rev-parse --short
HEAD` yourself before you quote anything from it.

**Before the next compaction, spend the note.** The compaction you are recovering from is the argument for
`--note-add`: a gotcha written to `.ripwire_notes` survives a context reset; one held only in context does
not. When you are deep in a task and learn something non-obvious, pin it *then* — not at the end.

## Output

Orientation summary: the 3–5 most important files (from god-files + hotspots), the main architectural
modules (from `--communities` / `--zoom`), any cycles (from `--report`), and one sentence on overall shape.
Use it to decide where a change belongs and which boundary a refactor should respect.
