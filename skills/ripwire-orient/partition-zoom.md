# ripwire-orient — reference: partition-zoom (read on demand; the recipe is in SKILL.md)

## Orienting N agents at once, not yourself — `--partition=N`

About to fan a single task out to several parallel agents? Do **not** let each one run its own
`--pack-task` — they will each re-derive the same top symbols, the same bodies, the same tests, and you
pay for the map N times. Run it **once**:

```bash
ripwire <dir> --pack-task="<the task in words>" --legend=compact --partition=4
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

**7. Nested module hierarchy** — `ripwire <dir> --zoom --legend=compact` (`--zoom=DEPTH` to cap levels; the default prints the top 2
levels of the 40 largest modules — `shown_levels=`/`shown=` disclose it, `next=` pastes the next page, `--zoom-levels=0`
prints every level): multi-level Louvain,
`<module level=N id= size= dir=>`, indent = one level deeper, innermost `level="0"` lists top-ranked members.
Read top-down; a `dir=` that doesn't match its parent's is a cross-cutting concern in the wrong place.
Trailing `<bridge …>` entries name the high-traffic integration seams *between* top modules — pair with
`--seams` to see which ones no test reaches.

**8. Render it** — `ripwire <dir> --zoom --mermaid` (or `--mermaid` for the flat module graph): a
`flowchart TB`, paste at mermaid.live. For hand-exploring, `ripwire <dir> --html[=FILE]` writes a
self-contained clickable wiki (module cards → subgraphs → Sourcetrail-style node recentering, no CDN);
`--color-by=community|cx|churn|tested` sets its initial node-colour lens (a live selector covers the rest).
Working inside a `--for`/`--pack-task` bundle instead of a whole-repo pass? Add `--with-graph` to that
same call — it appends a tiny `<graph fmt="mermaid">` block (top-8 ranked anchors + their 1-hop call
edges) right in the bundle, no second call.

**9. Export it** — `ripwire <dir> --export=cc.json[:FILE]` — per-file metrics (loc, cx, fan-in/out, churn) as
a CodeCharta `cc.json` for its 3D city view; the ladder's visualization end-point, not a map to read.
