# PLAN — external-tool survey: what to borrow, in priority order (2026-08-08)

Seven parallel deep-reads over the owner's candidate list (call-resolution: SVF/Doop/Phasar; macro:
Frama-C/CBMC; clones: PMD-CPD/jscpd; co-change: churn/cqmetrics; arch: ArchUnit/ArchUnitNET/
jQAssistant; dead code: vulture/deadcode/Depends; competitors: Code-Graph-RAG/Joern/Code
Pathfinder), each grounded in ripwire's own source before reading the external repo. Constraints
applied throughout: G1–G5 (zero deps, tree-sitter only, no compiler/IR/LLM, deterministic, fast),
the honesty contract, and the owner rules (best tool first; improve before publish; advice-not-
transform stance on record).

Two naming corrections baked in: r7's opponent `@colbymchenry/codegraph` (npm) is NOT
`vitali87/code-graph-rag` (Python/Memgraph) — two different tools, near-identical names; and
`github.com/codepathfinder/codepathfinder` 404s — the real repo is `shivasurya/code-pathfinder`.

## P0 — small, high-yield, mostly extensions of shipped machinery

1. **RTA-lite: instantiation-filtered CHA cone** (SVF/Doop lineage; src/graph.h §B2.1).
   ripwire already ships CHA-lite (receiver-type cone narrowing). Add the Rapid Type Analysis
   refinement: intersect the cone with the set of classes provably constructed somewhere in the
   corpus (`new T`, `T()`, `T{}` — evidence already in ing.references); empty intersection ⇒ keep
   cone (degrade, never guess). Effort S. Sharpens `amb=`/`ambiguous=`, the resolver's core trust
   surface. Gate: 3 sibling overriders, 1 instantiated → edge lands on it; factory-only-constructed
   class stays ambiguous.
2. **Macro-invocation → definition edges (`role="macro"`) + macro-body symbols** (the most-repeated
   disclosed gap in the tool — "a macro-generated call site contributes no edge" appears in nearly
   every verb legend). Second identifier pass over call-shaped tokens matching a known macro name;
   macro bodies that are real statements/exprs become disclosed-degraded symbols so the new edges
   have destinations (closes ensemble.h:491's named macro-only-header hole). Effort S/M each,
   pair them. Gate: function-like #define invoked with no call node → `--uses`/`--callees` emits a
   role="macro" row distinct from role="call".
3. **Function-pointer/callback binding edges (points-to-lite, one hop)** (SVF's core idea stripped
   to AST scale). Extend the existing local Binding table (var→type, P2-D Rule 2) with var→function
   bindings (`fn = &foo`, `cb = lambda`); resolve `fn()` through it, tombstone on double-assignment.
   Effort S-M. Closes the second named resolver gap (callbacks/function pointers). Gate: fixture
   edge exists; unresolved floor drops on a dispatch-table corpus with zero hand-check false edges.
4. **Time-decayed churn** (generalizes ripwire's own S5-C owner decay — exp(-λ·age), 6-month
   half-life, already shipped and tested in --owners). Apply to the churn tally behind
   --hotspots/--rank-by=churn alongside the raw count (cliff → signal). Effort S. Gate: two
   synthetic histories, same count, different recency → decayed rank differs, raw rank unchanged.
5. **`layer(NAME)` filter in --graph-query** (jQAssistant's concept→constraint pattern minus the
   Cypher). arch.h already computes layer classification; query.h just can't see it. One new filter
   case. Effort S. Gate: known-answer query joining layer+fanin.
6. **Type-3 clone-class grouping + repo/dir duplication% metric** (PMD-CPD's classes; jscpd's
   headline number). Union-find over the existing Type-3 pair graph; % = clone-covered tokens ÷
   indexed body tokens, from counts both passes already compute. Effort S each. Gates: 3 mutual
   near-miss fns → 1 group of 3 (extend test/type3clonecheck.sh); fixture with known 40% → matches.
7. **SARIF export for --lint** (Code Pathfinder's distribution lesson). Pure serialization of
   existing findings → GitHub code-scanning UI. Effort S, zero analysis risk. Gate: schema-validate
   output; smoke the upload action.
8. **LINEAGE.md hygiene (near-free, honesty-contract debt):** B2.1/B2.2 implement CHA + arity
   filtering with no citation row (Dean/Grove/Chambers CHA; Bacon/Sweeney RTA when #1 lands);
   --dead-code is the one measured lens with no prior-art row (cite x/tools deadcode's
   reachability framing + vulture's confidence precedent, with explicit deltas); §3b must
   disambiguate CodeGraph(npm) from Code-Graph-RAG. Mind readmedriftcheck arms E6/E7 (no name may
   appear in both §3a and §3b).

## P1 — real design work; schedule as normal feature rounds

9. **`cyclefree LAYER` arch rule kind** — Tarjan SCC (src/graph.h:2590) already computes cycles;
   --arch never gates on them. Wire SCC-restricted-to-layer into the existing baseline-hash/exit-2
   machinery. Effort M. The single most-asked arch-fitness rule (ArchUnit/ArchUnitNET ship it
   first-class).
10. **Fix-vs-feature churn** (Mockus & Votta 2000 — uncited anywhere; fix-churn out-predicts raw
    churn). Keyword-classify subjects in the existing single-pass commit walk; surface
    `churn_fix=`/`churn_feat=`. Effort S/M. Gate: dogfood on ripwire's own conventional-commit
    history as ground truth.
11. **Confidence-tiered --dead-code + ack workflow** — replace the fixed `confidence="high"` literal
    with tiers derived from ripwire's OWN evidence (linkage + in-degree + amb on incoming edges) —
    explicitly NOT vulture's self-described-rough 60/90/100 numbers; plus canonId-keyed acks with
    `acked=N` header disclosure (pattern exists in --quality-ack). Effort M + S.
12. **Field-typed member narrowing (P2-D Rule 2b)** — (className,fieldName)→type table; resolve
    `this->handler->onEvent()` through the field's declared type, tombstone on conflicting ctor
    assignments. Effort M. Closes the docs' own dispatch-hub trust caveat for the
    field-holds-interface shape.
13. **Symbol-level churn attribution** (danmayer/churn's granularity) — map diff hunks onto
    enclosing symbols via the existing OwnerIndex::ownerOf; second tally keyed by symbol. Effort
    M/L. Fixes hot-function-in-cold-file inheritance of file churn.
14. **Per-branch ppalt attribution** — tag cx/loc/nest increments with #if-branch index in the
    existing single walk; emit per-branch breakdown next to the (kept) blended total. Effort S.
    Closes the disclosed ~2× ppalt over-count without a dual parse.
15. **Watch-mode incremental reingest for the MCP server** (Code-Graph-RAG's one operational win) —
    FS-event-triggered per-file cache invalidation, reusing the content-hash cache. Effort M. Gate:
    touch → query → byte-identical to cold reingest.

## P2 — own pre-registered rounds or owner decisions first

16. **`--unreachable-from=ENTRY[,..]` transitive reachability** (x/tools deadcode's framing) — the
    one dead-code change that catches new things (dead islands A→B→C). arch.h already does this at
    file level. Effort L; needs entry-point design + dynamic-dispatch disclosure. Own round.
17. **`--slice=SYM`** (Joern CPG slicing analogue) — fuse --nonlocal-state cells + call reach into
    a minimal causal subgraph. Effort M-L. Own round.
18. **Top-N #ifdef dual-parse** (Kästner partial-preprocessing lineage, driven by the existing
    --flags ranking) — fully fixes ppalt AND the private validation tree's feature-guard gap; real determinism/
    symbol-ID risk. Effort L. Own pre-registered round with a promoted synthetic fixture
    (the private validation tree stays validation-only per memory).
19. **Sub-function block clones** (CPD's Karp-Rabin core) — the biggest true clone-detection gap;
    O(N²) risk needs the same care Type-3 got. Effort L.
20. **--graph-query power extensions** — `reachUntil(pred)` bounded-until (Joern), CodeQL-flavored
    FROM/WHERE/SELECT sugar (Pathfinder). Effort M each, minority-use. Bundle as one round if at
    all.
21. **Style-consistency metrics** (cqmetrics) — indentation variance + spacing-rule densities
    across 13 languages. Effort L, doesn't feed ranking. Lowest.
22. **Owner-stance decisions (explicitly NOT tasks):** AST structural rewrite mode conflicts the
    recorded advice-never-transform stance; name-based source/sink taint lens conflicts LINEAGE's
    CodeQL-row ("approximating dataflow from syntax produces noise and costs trust"). Neither
    proceeds without the owner reversing those rows on record.

## Head-to-head queue (improve-first: after the current fix-round backlog)

- **Code-Graph-RAG (vitali87) first** — directly comparable on the frozen LocBench harness; pins
  its LLM/config like every prior arm. Question: deterministic --for vs LLM→Cypher retrieval at
  what token/wall/stack cost.
- **Joern second** — needs a new CWE-seeded harness (LocBench gold isn't dataflow-labeled).
- **Pathfinder last** — tests a capability ripwire declined on record; lowest marginal information.
- r9 (Serena) stays queued per its own prompt; run on a quiet machine.

## Sequencing note

P0 items 1–3 form a natural "resolver precision round" (one prereg, three levers, per-lever
accept/reject — the LB-3 lesson: IDF-style guards and ≥2-wide bands, no point predictions). Items
4–7 are independent singles safe to land between rounds. P0-8 (LINEAGE) can land today.
