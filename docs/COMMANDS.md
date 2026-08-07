# ripwire — every flag, generated from the binary

**This file is generated. Do not hand-edit it.** Regenerate with:

```bash
python3 docs/docs_commands_build.py --bin build/ripwire
```

The flag surface below is read from `ripwire --help`, so it cannot disagree with the shipped
binary. `test/docscommandscheck.sh` fails if it ever does — in either direction.

Sample output is lifted from a real recorded run (`docs/captures/COMMANDS_showcase_2026-08-01.md`), trimmed to the first few lines and
scrubbed of local paths. It is illustrative, not a golden: run the command yourself for the
current shape.

> ripwire — the "ripgrep of AI context": parse a codebase, rank symbols by Personalized PageRank,
> stream a deterministic minified XML map to stdout. Zero runtime deps. Languages: C++, C, ObjC/ObjC++,
> Metal (MSL, .metal — C++ grammar), CUDA (.cu/.cuh — tree-sitter-cuda, <<<>>> launches are call edges),
> Python, TypeScript, JavaScript, Java, Ruby, Bash, Go, Rust, Swift, C#; JSON (config keys).
> usage: ripwire <dir> [flags]            # default = the ranked map of <dir> on stdout
> ripwire <dir1> <dir2> ... [flags] # multi-root workspace: ONE merged graph over 2..16 checkouts

## How to read a section

- **Answers** — the question this flag exists to answer.
- **Try it** — a real invocation and the real output it produced.
- **Shaped by** — other flags that change what this one emits.
- **Caveats** — the limits the binary itself states for this flag. They are extracted from its
  own help text, so they cannot drift from the code.

Two limits apply to nearly everything here and are not repeated in every section:

1. **Call edges are heuristic and name-based.** Dynamic dispatch, callbacks and macro-generated
   call sites produce no edge, so counts on the graph verbs carry `counts_floor="1"`. **Read a 0
   as "none found", never as "none exists."**
2. **A symbol's `amb="K"`** means K of its calls hit a name with several definitions and the
   resolver split the weight rather than choosing. Read the source when which-target matters.

## Contents

**understand a codebase cold** — [`--top-k`](#top-k-n) · [`--max-tokens`](#max-tokens-n) · [`--token-budget`](#token-budget-n-k-m-g) · [`--for`](#for-task) · [`--no-route`](#no-route) · [`--adaptive`](#adaptive) · [`--no-mention-boost`](#no-mention-boost) · [`--no-doc-mention`](#no-doc-mention) · [`--lego`](#lego-type) · [`--exemplar`](#exemplar-task-kind) · [`--recall`](#recall-task) · [`--tree`](#tree) · [`--html`](#html-file) · [`--order`](#order-mode) · [`--no-stable`](#no-stable)

**navigate / answer a question** — [`--around`](#around-sym) · [`--callers`](#callers-sym) · [`--callees`](#callees-sym) · [`--uses`](#uses-sym) · [`--graph-query`](#graph-query-expr) · [`--external-surface`](#external-surface) · [`--path`](#path-src-dst) · [`--connect`](#connect-a-b-c) · [`--impact`](#impact-sym) · [`--mentions`](#mentions-sym) · [`--affected`](#affected-f1-f2-sym) · [`--exercises`](#exercises-testfile) · [`--situ`](#situ-f1-f2) · [`--handoff`](#handoff) · [`--test-gate`](#test-gate-f1-f2) · [`--grep`](#grep-str-regex-pat) · [`--match`](#match-query) · [`--query`](#query-terms)

**zoom the detail ladder** — [`--detail`](#detail-n) · [`--pack-signatures`](#pack-signatures) · [`--outline`](#outline-a-b) · [`--expand`](#expand-a-b) · [`--compress`](#compress) · [`--pack-top-n`](#pack-top-n-n) · [`--no-redact`](#no-redact)

**assess quality / structure** — [`--metrics`](#metrics) · [`--deps`](#deps) · [`--hotspots`](#hotspots) · [`--clones`](#clones) · [`--readability`](#readability) · [`--nonlocal-state`](#nonlocal-state) · [`--ensemble`](#ensemble) · [`--quality-panel`](#quality-panel-preset) · [`--context-ratio`](#context-ratio) · [`--naming-calibration`](#naming-calibration) · [`--naming-consistency`](#naming-consistency) · [`--naming-locals`](#naming-locals) · [`--comment-coherence`](#comment-coherence) · [`--cochange`](#cochange-file) · [`--cochange-recur`](#cochange-recur-k) · [`--cochange-groups`](#cochange-groups) · [`--since`](#since-rev-date) · [`--arch`](#arch-file) · [`--lint`](#lint) · [`--lint-rules`](#lint-rules-dir) · [`--communities`](#communities) · [`--community`](#community-id) · [`--zoom`](#zoom-depth) · [`--report`](#report) · [`--seams`](#seams) · [`--mermaid`](#mermaid) · [`--owners`](#owners-sym) · [`--dead-code`](#dead-code-dir) · [`--quality-baseline`](#quality-baseline) · [`--quality-delta`](#quality-delta) · [`--dmm`](#dmm-rev-a-b) · [`--quality-ack`](#quality-ack-reason) · [`--edit-check`](#edit-check-sym) · [`--pr-context`](#pr-context-baseref) · [`--stray-content`](#stray-content-substr) · [`--plan`](#plan) · [`--abi`](#abi) · [`--whereis`](#whereis-sym) · [`--flags`](#flags-substr) · [`--flip`](#flip-name) · [`--layout`](#layout-struct) · [`--field-affinity`](#field-affinity-struct) · [`--doc-drift`](#doc-drift-substr) · [`--with-history`](#with-history) · [`--from-trace`](#from-trace-file) · [`--notes`](#notes) · [`--pack-task`](#pack-task-task) · [`--partition`](#partition-n) · [`--with-graph`](#with-graph) · [`--export`](#export-cc-json-file) · [`--batch`](#batch-file)

**self-diagnosis** — [`--doctor`](#doctor) · [`--skipped`](#skipped)

**security — scan skill files for injection / exfiltration patterns (exit 2 = CRITICAL, 1 = WARN,** — [`--scan-skill`](#scan-skill-file) · [`--scan-skills`](#scan-skills-dir) · [`--force`](#force)

**knobs / modes** — [`--rank-by`](#rank-by-pagerank-authority-hub-rrf-churn) · [`--format`](#format-candidates) · [`--json`](#json) · [`--exclude`](#exclude-substr) · [`--map-diff`](#map-diff) · [`--cache`](#cache-path) · [`--index-out`](#index-out-base) · [`--no-cache`](#no-cache) · [`--max-file-size`](#max-file-size-n-k-m-g) · [`--refetch`](#refetch) · [`--scip`](#scip-index-scip) · [`--mcp`](#mcp) · [`--listen`](#listen-host-port) · [`--mcp-token`](#mcp-token-t) · [`--allow-remote-edits`](#allow-remote-edits) · [`--eval-stray`](#eval-stray-file) · [`--eval`](#eval) · [`--eval-retrieval`](#eval-retrieval) · [`--eval-mined`](#eval-mined-file) · [`--eval-skills`](#eval-skills-file)

---

## understand a codebase cold

### `--top-k=N`

**Answers:** keep the N highest-ranked symbols (default 200) — applies to the default map, plain --query, and --format=candidates (incl.

with --for). --for's OWN signature/lego/compose bundle self-limits via --pack-top-n instead — --top-k is INERT there (documented, not fixed — a real fix is a behavior change). --pack-task/--from-trace/--situ self-budget via --token-budget, not --top-k. --top-k=0 emits NO ranked map at all — ONLY the payload you asked for (--expand/--outline/--pack-signatures/--pack-top-n). Use it when you want the body and not the ~200-symbol map that otherwise rides along with it.

**Try it**

_Same map, capped to the 5 highest-ranked symbols._

```
$ ./build/ripwire . --top-k=5
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=850 symbols=6432 edges=8737 shown=5 est_tokens=428 ambiguous=2631 unresolved=662 precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="428">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0503">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0133">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0122">
</s>
</f>
... [5 more line(s); run it to see the whole thing]
```

**Shaped by:** `--token-budget`, `--recall`, `--graph-query`, `--pack-signatures`, `--from-trace`, `--format`, `--json`

**Caveats (stated by the binary):**

- --for's OWN signature/lego/compose bundle self-limits via --pack-top-n instead — --top-k is INERT there (documented, not fixed — a real fix is a behavior change).

### `--max-tokens=N`

**Answers:** budget the map to ~N tokens (binary-search top-K) — SHAPES the map to fit.

THE FIT IS A BYTE CEILING, and it is deliberately CONSERVATIVE: N is converted at 2.36 B/tok (the densest calibrated language, so N holds for any corpus) times a 0.90 headroom factor. The map's own est_tokens uses THIS corpus's language-weighted rate instead, so a conformant fit REPORTS a number below the N you asked for — expect ~10-20% of N unused. The shaped map discloses both: max_tokens=N (asked) and fit_bytes=B (honoured). Consequence for composing it with --token-budget=N below: the two Ns are different units, so the same N on both is NOT a tautology. At a SMALL N the map's fixed floor (envelope + legend) can exceed fit_bytes with even one symbol emitted — that map says over_ceiling=1 rather than overshoot in silence, and its est_tokens can then exceed N. XML only: the --json map carries no max_tokens=/fit_bytes= keys yet, and its fit is measured in XML bytes. On --recall it SHAPES the doc bundle the same way: docs are dropped from the BOTTOM of the ranking and the last one may be cut within itself — every cut is DISCLOSED (header total=/shown=/capped=/truncated=, a per-doc [truncated: X of Y bytes] marker, and a closing (capped: …) note). Selection order never changes.

**Try it**

_SHAPE the map to fit ~1500 tokens (binary-search top-K)._

```
$ ./build/ripwire . --max-tokens=1500
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- max_tokens=asked fit_bytes=honoured: fit_bytes = max_tokens x 2.36 (densest-language B/tok) x 0.90 headroom, a CONSERVATIVE cap, so est_tokens (this corpus's own rate) lands ~10-20% BELOW max_tokens by design; the token-budget gate compares against est_tokens, not fit_bytes; over_ceiling=floor-alone-exceeded-fit_bytes(absent=cap-held) -->
<!-- files=850 symbols=6432 edges=8737 shown=21 est_tokens=1255 ambiguous=2631 unresolved=662 precise=3 skipped_oversize=3 max_tokens=1500 fit_bytes=3186 order=important-first -->
<r est_tokens="1255">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0503">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0133">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0122">
</s>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--token-budget`, `--recall`, `--detail`, `--pr-context`, `--from-trace`, `--json`

**Caveats (stated by the binary):**

- THE FIT IS A BYTE CEILING, and it is deliberately CONSERVATIVE: N is converted at 2.36 B/tok (the densest calibrated language, so N holds for any corpus) times a 0.90 headroom factor.
- Consequence for composing it with --token-budget=N below: the two Ns are different units, so the same N on both is NOT a tautology.
- At a SMALL N the map's fixed floor (envelope + legend) can exceed fit_bytes with even one symbol emitted — that map says over_ceiling=1 rather than overshoot in silence, and its est_tokens can then exceed N.

### `--token-budget=N[K|M|G]`

**Answers:** two personalities depending on the verb: - default map / --query / --recall: a CI GATE — exit 3 if the emitted DOCUMENT's est_tokens exceeds N.

That is the map PLUS every block appended after it (<sigs>/<src>/<bodies>/<outline>), each charged from the bytes it actually emits at the calibrated rate for what those bytes are — so --pack-top-n=3 --token-budget=600 gates on the ~67KB it would stream, not on the map alone. (test/tokenbudgetcheck.sh reports the live MAPE vs tiktoken o200k when tiktoken is installed; the estimate is calibrated, never exact — Claude's tokenizer is not public.) Within budget: exit 0, output unchanged. ASSERTS and fails, vs --max-tokens which shapes to fit — composable: set neither, either, or both (e.g. --max-tokens=16000 --token-budget=16K), but see --max-tokens above: the two Ns are measured in different units. Over budget, nothing of the artifact reaches stdout — only a small record naming withheld_est_tokens= vs budget=, the same vocabulary --recall uses, since est_tokens= is normatively about what a run PRINTED. On --recall the check likewise runs BEFORE a byte of the bundle is emitted: stdout gets the header line naming what was withheld, never the artifact just rejected. --json GATES AT A DIFFERENT NUMBER for the same request, and by design: the flag measures the DOCUMENT that was emitted, and the JSON encoding of the same map is smaller than the XML one (MEASURED on src/ --top-k=200: est_tokens 577 XML vs 435 JSON, ~25% apart). So the same N can pass under --json and fail without it — pick the budget for the dialect you emit. - --for / --pack-task / --from-trace: SHAPES instead of gating — overrides that lens's own default payload budget and trims to fit, always exit 0. --for's header reports est_tokens="N" so its fit is checkable; --pack-task/--from-trace report their budget ledger in the header report line instead. Its VERBATIM task echo is bytes no trim can shrink, so past some task length the header floor alone exceeds the ceiling: the lens drops the comment's DUPLICATE echo first (task_echo: dropped (ceiling); task= keeps the verbatim copy), then labels it over_ceiling (--recall: over_ceiling=1) — never a trim it did not actually do.

**Try it**

_GATE form: exit 3 if the map's own est_tokens exceeds the budget (over-budget failure shape)._

```
$ ./build/ripwire . --token-budget=100
<r withheld_est_tokens="9543" budget="100" withheld="1"/>
```

**Shaped by:** `--top-k`, `--max-tokens`, `--for`, `--recall`, `--handoff`, `--from-trace`, `--pack-task`, `--partition`

**Caveats (stated by the binary):**

- That is the map PLUS every block appended after it (<sigs>/<src>/<bodies>/<outline>), each charged from the bytes it actually emits at the calibrated rate for what those bytes are — so --pack-top-n=3 --token-budget=600 gates on the ~67KB it would stream, not on the map alone.
- the estimate is calibrated, never exact — Claude's tokenizer is not public.) Within budget: exit 0, output unchanged.
- On --recall the check likewise runs BEFORE a byte of the bundle is emitted: stdout gets the header line naming what was withheld, never the artifact just rejected.

### `--for=TASK`

**Answers:** the task lens: ranked signatures + metrics framed for reuse.

The bundle enforces a ~7.5KB default payload budget (tail entries trim first; <sigs capped="1"> marks it) — an explicit --token-budget=N overrides the default at the conservative byte rate (SHAPES, exit 0; see --token-budget above) and the header reports the delivered est_tokens

**Try it**

_Name-shaped query: the router picks name-exact BM25 (header says which/why)._

```
$ ./build/ripwire . --for="rankGraphTeleport"
<ctx task="rankGraphTeleport" route=" [routed: name-exact BM25 — query names a symbol (rankGraphTeleport)]">
<!-- ripwire lens for "rankGraphTeleport" [routed: name-exact BM25 — query names a symbol (rankGraphTeleport)]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="2297" -->
<sigs>
<f p="./src/graph.h">
<d l="1277" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="7" amp="32">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt … [line truncated: 44 more bytes on this line]
</f>
<f p="./AGENTS.md">
<d l="1" n="AGENTS" cx="0" ccx="0" in="0" churn="1" amp="2"># ripwire — agent instructions This repository follows the `AGENTS.md` convention. The full agent guide is **`CLAUDE.md`**</d>
<d l="1" n="ripwire — agent instructions" cx="0" ccx="0" in="0" churn="1" amp="2"># ripwire — agent instructions</d>
<d l="9" n="Setup" cx="0" ccx="0" in="0" churn="1" amp="2">## Setup</d>
<d l="18" n="Test" cx="0" ccx="0" in="0" churn="1" amp="2">## Test</d>
... [19 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--token-budget`, `--no-route`, `--adaptive`, `--no-mention-boost`, `--no-doc-mention`, `--query`, `--detail`

**Caveats (stated by the binary):**

- <sigs capped="1"> marks it) — an explicit --token-budget=N overrides the default at the conservative byte rate (SHAPES, exit 0;

### `--no-route`

**Answers:** (with --for/--query) force plain subtoken+body BM25.

Routing is now the DEFAULT: a deterministic, confidence-gated query-shape router picks name-exact BM25 when the query NAMES a symbol (identifier syntax, or every content word is a symbol name) else subtoken+body, and prints which/why in the header. It only routes with a query (the plain map is unaffected). --no-route restores the old behavior.

**Try it**

_Same query with routing forced OFF (plain subtoken+body BM25) — contrast with the routed run._

```
$ ./build/ripwire . --for="rankGraphTeleport" --no-route
<ctx task="rankGraphTeleport">
<!-- ripwire lens for "rankGraphTeleport" [doc mentions: 1 doc discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="2996" -->
<sigs capped="1">
<f p="./src/graph.h">
<d l="32" n="Graph" id="./src/graph.h::Graph::Graph" cx="0" ccx="0" in="0" churn="7" amp="26">struct Graph</d>
<d l="1262" n="biasPrior" id="./src/graph.h::rw::biasPrior" cx="5" ccx="4" in="1" churn="7" amp="27">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</d>
<d l="1277" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="7" amp="32">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quali…</doc>inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="1303" n="rankGraph" id="./src/graph.h::rw::rankGraph" cx="2" ccx="1" in="9" churn="7" amp="35">
<doc>uniform-teleport PageRank (the default</doc>inline std::vector&lt;float&gt; rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
<d l="1552" n="anchoredLexicalRank" id="./src/graph.h::rw::anchoredLexicalRank" cx="10" ccx="10" in="4" churn="7" amp="30">
... [20 more line(s); run it to see the whole thing]
```

### `--adaptive`

**Answers:** (with --for/--query) cut the result at the relevance CLIFF — the largest relative score gap (Adaptive-k), floor 5, ceiling = the existing top-k;

a sharp query returns few, a flat/broad one hits the ceiling. Prints [adaptive: kept K of N ...] in the header. Without it, output is unchanged.

**Try it**

_Cut the result at the relevance cliff (Adaptive-k)._

```
$ ./build/ripwire . --for="tree-sitter parse of a source file" --adaptive
<ctx task="tree-sitter parse of a source file" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "tree-sitter parse of a source file" [routed: subtoken+body BM25 (-for's default) — no strong name hit, multi-word conceptual query] [adaptive: kept 5 of 40 - sharp cliff at rank 1 (23% drop), clamped up to the floor of 5]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="862" -->
<sigs>
<f p="./src/ingest.cpp">
<d l="66" n="tree_sitter_c" cx="1" ccx="0" in="0" churn="6" amp="19">const TSLanguage* tree_sitter_c( void )</d>
<d l="285" n="jsonNestsTooDeep" cx="13" ccx="20" in="1" churn="6" amp="20">
<doc>True when raw bracket/brace nesting exceeds kMaxJsonNestDepth — degenerate or hostile DATA, never config (found live by bench/multiswe: tree-sitter-json&apos;s error recovery is superlinear on unclosed n</doc>bool jsonNestsTooDeep( std::string_view bytes ) noexcept</d>
<d l="3486" n="parseTree" cx="1" ccx="0" in="1" churn="6" amp="20">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
</f>
<f p="./src/mcpindex.h">
<d l="372" n="McpIndex" id="./src/mcpindex.h::McpIndex::McpIndex" cx="0" ccx="0" in="0" churn="6" amp="12">
... [14 more line(s); run it to see the whole thing]
```

**Shaped by:** `--detail`

**Caveats (stated by the binary):**

- (with --for/--query) cut the result at the relevance CLIFF — the largest relative score gap (Adaptive-k), floor 5, ceiling = the existing top-k;

### `--no-mention-boost`

**Answers:** (with --for) disable the query-mention anchor.

By DEFAULT, a file, dotted module, or Scope.symbol literally NAMED in the task text (a path, `pkg.module`, `Type.method` — even inside a URL) is lifted to just below the top hit; the header says what anchored. Inert (byte-identical) when the text names nothing indexed. RIPWIRE_NO_MENTION=1 disables it everywhere (incl. MCP `for`).

**Try it**

_Same task with the anchor disabled — the contrast the flag exists for._

```
$ ./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25" --no-mention-boost
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "why does src/lexical.h chooseForRanker pick name-exact BM25" [routed: subtoken+body BM25 (-for's default) — no strong name hit, multi-word conceptual query] [doc mentions: 1 doc discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="3002" -->
<sigs capped="1">
<f p="./src/eval.h">
<d l="120" n="printEvalRankerNote" id="./src/eval.h::rw::printEvalRankerNote" cx="1" ccx="0" in="1" churn="5" amp="8">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="133" n="runEval" id="./src/eval.h::rw::runEval" cx="44" ccx="66" in="1" churn="5" amp="8">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="177" n="fileDir" id="./src/eval.h::rw::fileDir" cx="1" ccx="0" in="0" churn="5" amp="7">std::vector&lt;std::string&gt; fileDir( F )</d>
... [23 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- Inert (byte-identical) when the text names nothing indexed.

### `--no-doc-mention`

**Answers:** (with --for) disable doc-mention surfacing.

By DEFAULT, a markdown doc that names one of the task's top-resolved symbols in a `backtick` (the same doc<->code edges --mentions=SYM reads) is lifted into the bundle, strictly below that symbol's own score — closing the "the doc explains it but shares no words with the query" gap. Inert (byte-identical) when no resolved symbol has a mentioning doc. RIPWIRE_NO_DOC_MENTION=1 disables it everywhere (incl. MCP `for`/`pack_task`).

**Caveats (stated by the binary):**

- Inert (byte-identical) when no resolved symbol has a mentioning doc.

### `--lego=TYPE`

**Answers:** the interface->impls view for ONE named interface/base: its signature, method contract, and every implementor (own-language only).

file:name disambiguates a same-named type. No contract for a language this surface cannot read soundly: methods=0 caveat=… says so.

**Try it**

_Interface -> implementors view: method contract + every existing impl._

```
$ ./build/ripwire . --lego=Vehicle
<ctx><lego><iface n="Vehicle" p="./test/legofix/vehicle.rs" methods="0" caveat="not-extracted-for-lang" implementors="2"><impl n="Car" p="./test/legofix/vehicle.rs"/><impl n="Bike" p="./test/legofix/vehicle.rs"/></iface></lego></ctx>
```

**Shaped by:** `--callers`, `--expand`, `--layout`

**Caveats (stated by the binary):**

- file:name disambiguates a same-named type.
- No contract for a language this surface cannot read soundly: methods=0 caveat=… says so.

### `--exemplar=TASK|KIND`

**Answers:** before you write: the repo's best-in-class instance to IMITATE.

Just pass a plain task — --exemplar="format byte sizes" — and the KIND is inferred from the top match; or name a KIND directly (fn|method|class|struct|iface|var). Picks by ROLE — lowest cognitive cx under a hard ccx ceiling, then tested + highest fan-in; test-fixture paths de-prioritized — NOT text similarity (similar-snippet retrieval measurably hurts). A weak task match falls back to fn (low_confidence=1); an all-over-ceiling kind flags over_ccx_bar=1

**Try it**

_The repo's best-in-class instance to imitate before writing new code (picked by ROLE)._

```
$ ./build/ripwire . --exemplar="format byte sizes for humans"
<!-- ripwire exemplar for "format byte sizes for humans" (task -> kind=fn, low-confidence: weak match, fell back to fn): the repo's best-in-class fn to imitate — chosen by ROLE, NEVER by text similarity to your task: candidates are first filtered to cognitive complexity at or under the ccx ceiling (4x the complexity bar), then ordered non-fixture path before test-fixture path, tested before untested, higher fan-in, lower complexity, fewer lines, lowest id. low_confidence=1 marks a weak task-to-kind match that fell back to fn; over_ccx_bar=1 marks a corpus where nothing was under the ceiling, so the pick is the least bad rather than a clean one; candidates= counts the ELIGIBLE instances of the kind (post-ceiling), not every instance. On the root, the three attributes that ARE that ordering's evidence: in=reuse-count (callers), ccx=cognitive complexity, tested=1 when a test reaches it (OMITTED, never 0, when none does). Copy its shape, not its text. -->
<exemplar kind="fn" candidates="4023" n="min" p="./src/infra/platform.h:95" in="84" ccx="1" tested="1" low_confidence="1">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="95" p="./src/infra/platform.h" n="min">
<![CDATA[[[nodiscard]] ALWAYS_INLINE constexpr T min( T a, T b ) noexcept { return b < a ? b : a; }]]>
</b>
</bodies>
</exemplar>
```

**Shaped by:** `--metrics`, `--json`, `--index-out`

### `--recall=TASK`

**Answers:** recall the most relevant DOCS — memory/plans/designs, full bodies (md, .ipynb/.html/.csv, plus Office/PDF via the optional markitdown bridge).

This is the tool's LARGEST output: its header reports est_tokens + total=/shown=/capped=, where total= is the TRUE relevant count (score > 0) and shown= is what this run actually emitted. The header's "of N document files" denominator counts every file the index carries as a DOCUMENT — .md plus the docparse'd .ipynb/.html/.csv — so it is a SUPERSET of --doc-drift's docs=, which is an extension test (markdown only). Two populations, two names, deliberately. --top-k=N shapes HOW MANY docs are emitted (default 8, not the general --top-k default of 200); --max-tokens=N shapes it to fit a byte budget (disclosing each cut) and --token-budget=N gates it (exit 3, nothing streamed). GENERATED documents rank LAST by default — a doc that declares itself generated in its first lines, or is BOTH >=5x the median doc's size AND mostly ```-fenced quoted output (a capture/API dump quotes every term, so BM25 hands it every query). Never dropped: it still wins when nothing else matches. Each one says [generated_demoted: marker|size+fences] on its own line and the header tallies generated_demoted=N

**Try it**

_Most relevant DOCS' full bodies (markdown only) — recall what is already written down._

```
$ ./build/ripwire . --recall="quality delta gating exit codes"
ripwire recall — "quality delta gating exit codes" — 43 relevant of 90 document files, best-first — total=43 shown=8 capped=1 generated_demoted=1 est_tokens=53585

━━ ./skills/ripwire-quality-bar/SKILL.md  (relevance 6.219) ━━
---
name: ripwire-quality-bar
description: >
  The code-QUALITY bar for what you just wrote — not merge-safety. Needs NO setup: right before you commit /
  open a PR / tell the user it's finished, run `ripwire <dir> --quality-delta` — reports ONLY what you made
  WORSE across 10 measured kinds (complexity, verbosity, nesting, params, duplication, dead-code,
  API-surface, error-masking, short-horizon-churn, new-clone-of-reused-helper — the measured agent-code
  failure modes), exiting non-zero on new debt. Fix the real regressions, re-run, converge. Reach for this at
  every "I think this is done" moment on non-trivial work. For merge-safety / blast-radius / tests-to-run →
  **ripwire-change-check** instead (this skill judges the code, not whether it's safe to merge). Backed by
  ripwire (deterministic, on PATH).
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--max-tokens`, `--token-budget`, `--from-trace`, `--json`

**Caveats (stated by the binary):**

- This is the tool's LARGEST output: its header reports est_tokens + total=/shown=/capped=, where total= is the TRUE relevant count (score > 0) and shown= is what this run actually emitted.
- Never dropped: it still wins when nothing else matches.

### `--tree`

**Answers:** file-by-file orientation map (top symbols per file)

**Try it**

_File-by-file orientation map (top symbols per file)._

```
$ ./build/ripwire . --tree
<!-- ripwire tree: each file + its top symbols by rank, files ordered by their best symbol's rank (path breaks ties) — a session-start orientation map. files= is the indexed corpus; rows list files WITH symbols; files_unlisted= holds the symbol-less remainder — files equals files_unlisted plus the LISTABLE file set, which is what the rows below enumerate before any paging window is applied; under explicit paging (limit=/offset=) that listable count is emitted as total= and shown= says how many of it these rows are -->
<tree files="850" files_unlisted="16">
<file p="./src/svector.h" symbols="17">
<s t="method" n="size"/>
<s t="method" n="push_back"/>
<s t="method" n="buf"/>
</file>
<file p="./src/scipoverlay.h" symbols="6">
<s t="method" n="empty"/>
<s t="method" n="targetsOf"/>
<s t="method" n="isPrecise"/>
</file>
<file p="./src/notes.h" symbols="23">
<s t="method" n="empty"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--json`

### `--html[=FILE]`

**Answers:** self-contained HTML force-directed call graph (no CDN — redirect or write FILE)

**Try it**

_Self-contained HTML force-directed call graph._

```
$ ./build/ripwire . --html=<scratch>/aux/map2.html
(empty)
```

### `--order=MODE`

**Answers:** emit order: stable (path/id order — provider KV-cache hits across re-runs) | important-first (rank order, the default;

no auto-flip) | important-last (highest-rank content emitted last — recency bias for an LLM). Large default maps auto-flip to important-last past ~50% of a nominal 32K window (est_tokens>16000) unless MODE is explicitly given.

**Try it**

_Stable (path/id) emit order — provider KV-cache hits across re-runs._

```
$ ./build/ripwire . --order=stable --top-k=5
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<r>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty">
</s>
</f>
<f p="./src/svector.h">
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
... [5 more line(s); run it to see the whole thing]
```

### `--no-stable`

**Answers:** opt out of the stable ordering that --mcp enables by default

---

## navigate / answer a question

### `--around=SYM`

**Answers:** ego graph around SYM   [--around-depth=N] [--around-fanout=K]

**Try it**

_Ego graph around one symbol._

```
$ ./build/ripwire . --around=rankGraphTeleport
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=850 symbols=6432 edges=8737 shown=147 est_tokens=17779 ambiguous=2631 unresolved=662 precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="17779">
<f p="./src/graph.h">
<s t="fn" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" amb="5" k="1.0000">
<c n="biasPrior"/>
<c n="pageRankDouble"/>
<c n="size"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
<c n="end"/>
</s>
<s t="fn" n="biasPrior" id="./src/graph.h::rw::biasPrior" k="0.5000">
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--callers`, `--layout`, `--json`

### `--callers=SYM`

**Answers:** who calls SYM (1-hop in-edges).

file:name disambiguates a same-named symbol across files (like --around/--lego)

**Try it**

_Unknown-symbol failure shape._

```
$ ./build/ripwire . --callers=DoesNotExist
(empty)
```

**Shaped by:** `--callees`, `--uses`, `--impact`, `--expand`, `--edit-check`, `--rank-by`, `--json`

**Caveats (stated by the binary):**

- file:name disambiguates a same-named symbol across files (like --around/--lego)

### `--callees=SYM`

**Answers:** what SYM calls (1-hop out-edges).

file:name disambiguates like --callers

**Try it**

_What SYM calls (1-hop out-edges)._

```
$ ./build/ripwire . --callees=rankGraphTeleport
... [10 more line(s); run it to see the whole thing]
```

**Shaped by:** `--impact`, `--exercises`, `--rank-by`, `--json`

**Caveats (stated by the binary):**

- file:name disambiguates like --callers

### `--uses=SYM`

**Answers:** the statically resolvable use-sites of SYM (role=call|read|write|import|extends, file:line);

external="1" if SYM has no in-corpus def. file:name narrows defs= AND the role="call" sites (kept only where the call RESOLVES to a chosen def — --callers' own narrowing); read/write/import/extends carry no resolution and stay name-matched. narrowed_roles=/defs_of_name=/call_sites_of_name= (file: qualifier only) disclose what narrowed and the un-narrowed totals; a file: qualifier naming a file with no such def REFUSES, like --callers/--impact

**Try it**

_The resolvable use-sites (call/read/write/import/extends) with file:line; count= is a floor._

```
$ ./build/ripwire . --uses=rankGraphTeleport
... [10 more line(s); run it to see the whole thing]
```

**Shaped by:** `--impact`, `--naming-consistency`, `--edit-check`, `--rank-by`, `--json`, `--index-out`

**Caveats (stated by the binary):**

- a file: qualifier naming a file with no such def REFUSES, like --callers/--impact

### `--graph-query=EXPR`

**Answers:** composable node-set query over the call graph: sources name("X")/all;

filters kind|cx|fanin|file; bounded closure callers|callees(SET[,depth]); joins and|or|not.  e.g. and(callers(name("foo"),2),kind(all,fn)) a name("X") literal matching NO indexed symbol refuses with a did-you-mean (a typo is not a count=0); a query whose names all resolve but that selects nothing still reports count="0" — that IS a measurement. Ranked result set is capped at --top-k (default 200); --limit overrides that cap (raise or lower it), --offset pages past it — see --limit=N --offset=M above

**Try it**

_Composable node-set query: functions within 2 caller-hops of rankGraphTeleport._

```
$ ./build/ripwire . --graph-query='and(callers(name("rankGraphTeleport"),2),kind(all,fn))'
... [31 more line(s); run it to see the whole thing]
```

**Shaped by:** `--exercises`, `--json`

**Caveats (stated by the binary):**

- and(callers(name("foo"),2),kind(all,fn)) a name("X") literal matching NO indexed symbol refuses with a did-you-mean (a typo is not a count=0);
- Ranked result set is capped at --top-k (default 200);
- --limit overrides that cap (raise or lower it), --offset pages past it — see --limit=N --offset=M above

### `--external-surface`

**Answers:** names referenced but never defined in-corpus (the stdlib/third-party surface), by ref count;

each row's lang= is the REFERENCING file's language — a name called from several languages (e.g. printf: C stdio call vs Bash builtin) gets one row PER language, not a merged count

**Try it**

_Names referenced but never defined in-corpus (stdlib/third-party surface). NOW carries names/shown/capped (total= joins them only under --limit/--offset)._

```
$ ./build/ripwire . --external-surface
<!-- ripwire external-surface: names CALLED/IMPORTED/EXTENDED but never defined in the indexed tree = the stdlib/third-party surface the code depends on (refs=use-sites, calls=of-which-calls) -->
<external-surface names="936" shown="936" capped="0">
<x n="grep" lang="sh" refs="3993" calls="3993"/>
<x n="printf" lang="sh" refs="3520" calls="3520"/>
<x n="echo" lang="sh" refs="3270" calls="3270"/>
<x n="exit" lang="sh" refs="1127" calls="1127"/>
<x n="git" lang="sh" refs="917" calls="917"/>
<x n="head" lang="sh" refs="856" calls="856"/>
<x n="cat" lang="sh" refs="764" calls="764"/>
<x n="cd" lang="sh" refs="696" calls="696"/>
<x n="c_str" lang="cpp" refs="625" calls="625"/>
<x n="tr" lang="sh" refs="612" calls="612"/>
<x n="fprintf" lang="cpp" refs="610" calls="610"/>
<x n="string" lang="cpp" refs="471" calls="471"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--json`

**Caveats (stated by the binary):**

- names referenced but never defined in-corpus (the stdlib/third-party surface), by ref count;
- printf: C stdio call vs Bash builtin) gets one row PER language, not a merged count

### `--path=SRC,DST`

**Answers:** shortest directed call-path SRC -> DST

**Try it**

_Shortest directed call-path SRC -> DST. CHANGED: now reports from_p/to_p/from_defs and resolves the right `main` (was reachable="0")._

```
$ ./build/ripwire . --path=main,rankGraphTeleport
<path from="main" to="rankGraphTeleport" from_p="./src/main.cpp:8007" to_p="./src/graph.h:1277" from_defs="43" to_defs="1" reachable="1" hops="2">
<s t="fn" n="main" p="./src/main.cpp:8007"/>
<s t="fn" n="runDefaultMap" p="./src/main.cpp:7276"/>
<s t="fn" n="rankGraphTeleport" p="./src/graph.h:1277"/>
</path>
```

**Shaped by:** `--connect`, `--json`

### `--connect=A,B,C`

**Answers:** minimal connecting subgraph over 2..16 symbols: terminals + fewest joining intermediaries + call edges in TRUE direction (finds the shared-caller join a directed --path can't)   [--connect-radius=N (1..12, default 6)]

**Try it**

_Minimal connecting subgraph over 3 symbols (finds shared-caller joins)._

```
$ ./build/ripwire . --connect=rankGraphTeleport,runEval,getIndex
<!-- ripwire connect: minimal joining subgraph over N task symbols (metric-closure 2-approx Steiner; search is undirected so SHARED-CALLER joins are found, every <e f= t=/> keeps its TRUE caller->callee direction; graph-structured navigation per CodeCompass, arXiv 2602.20048). Call edges are name-based: dynamic dispatch / callbacks may hide connections -->
<connect terminals="3" nodes="3" edges="2" radius="6" groups="1" est_tokens="287">
<g terminals="3">
<t n="runEval" t="fn" p="./src/eval.h:133"/>
<t n="rankGraphTeleport" t="fn" p="./src/graph.h:1277"/>
<t n="getIndex" t="fn" p="./src/mcpindex.h:734"/>
<e f="runEval" t="rankGraphTeleport"/>
<e f="getIndex" t="rankGraphTeleport"/>
</g>
</connect>
```

**Shaped by:** `--from-trace`, `--json`

### `--impact=SYM`

**Answers:** transitive blast radius — the indexed symbols that reach SYM (a floor, see counts_floor).

file:name disambiguates like --callers counts_floor="1"           on --callers/--callees/--uses/--impact/--edit-check every count is a FLOOR, never a total: the call graph is extracted from source text by name, so dynamic dispatch, callbacks/function pointers, macro-generated call sites and declarations that parse without a call expression (C++ most-vexing- parse) contribute no edge. Read a 0 as "none found", never as "none exists". Those five verbs also count DISTINCT (caller,callee) pairs, while --uses counts call SITES — see each verb's own legend

**Try it**

_Transitive blast radius — everything that reaches SYM. NOW carries shown/capped._

```
$ ./build/ripwire . --impact=rankGraphTeleport
... [31 more line(s); run it to see the whole thing]
```

**Shaped by:** `--uses`, `--metrics`, `--rank-by`, `--json`

**Caveats (stated by the binary):**

- transitive blast radius — the indexed symbols that reach SYM (a floor, see counts_floor).
- Read a 0 as "none found", never as "none exists".

### `--mentions=SYM`

**Answers:** markdown docs (plans/designs) that name SYM in a `backtick` (doc↔code) the pre-PR family — plumbing (--affected) to mid-task report (--situ) to gate (--test-gate):

**Try it**

_Markdown docs that name SYM in a backtick (doc<->code edges)._

```
$ ./build/ripwire . --mentions=rankGraphTeleport
<!-- ripwire mentions: markdown FILES that name this symbol in a `backtick` (doc<->code; NOT a call edge). docs= is the row count (distinct files); sections= counts the underlying markdown-section mentions before file-collapse (docs <= sections). Each row's mentions= is its own section-mention count. No line locator: the doc edge is stored at file granularity — a fabricated always-1 l= was removed; absent beats fake -->
<mentions of="rankGraphTeleport" defs="1" docs="0" sections="0">
</mentions>
```

**Shaped by:** `--no-doc-mention`, `--json`

### `--affected=F1,F2|SYM`

**Answers:** test files that transitively reach the changed files -- or the changed SYMBOL.

Each item may be `path`, `./path`, `path:LINE` / `path:N-M` (paste a --hotspots/--clones/--grep/--lint/ --quality-delta row's locator verbatim; the trailing line locator is stripped, same for --situ/--test-gate), or a symbol: `NAME`, `file:NAME`, `path::scope::name`. FILE-FIRST: an item matching any indexed path is a PATH pattern (unchanged semantics -- `--affected=widget` stays the ./src/widget.cpp pattern); only an item matching NO indexed path is offered to the symbol resolver, and `file:NAME` reaches the symbol reading explicitly. seeded_by="file|symbol|mixed" + seeds=N report which reading fired and how many defs it seeded. An item matching NEITHER refuses (exit 1) naming both readings. script_gates_unmodelled= counts the script runners under test/, recursively (a path count; not every one invokes the binary) that this call's graph walk cannot see either way (script-to-binary is not a call edge) — a corpus-wide fact, not scoped to the changed set given

**Try it**

_Test files that transitively reach the changed file._

```
$ ./build/ripwire . --affected=src/graph.h
<!-- ripwire affected: test files that transitively reach the changed files/symbols (run these); seeded_by= says which reading the argument took. script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) — script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=/reached= -->
<affected changed="src/graph.h" seeded_by="file" seeds="88" tests="6" reached="422" script_gates_unmodelled="332">
<test p="./test/cloneband_harness.cpp" run="bash test/clonebandcheck.sh"/>
<test p="./test/clonelex_harness.cpp" run="bash test/clonelexcheck.sh"/>
<test p="./test/connectcore_harness.cpp" run="bash test/connectcorecheck.sh"/>
<test p="./test/includeprecise_unit.cpp" run="bash test/includeprecisecheck.sh"/>
<test p="./test/rustimport_unit.cpp" run="bash test/rustimportprecisecheck.sh"/>
<test p="./test/type3clone_harness.cpp" run="bash test/type3clonecheck.sh"/>
</affected>
```

**Shaped by:** `--mentions`, `--exercises`, `--test-gate`

**Caveats (stated by the binary):**

- An item matching NEITHER refuses (exit 1) naming both readings.
- script_gates_unmodelled= counts the script runners under test/, recursively (a path count;
- not every one invokes the binary) that this call's graph walk cannot see either way (script-to-binary is not a call edge) — a corpus-wide fact, not scoped to the changed set given

### `--exercises=TESTFILE`

**Answers:** the INVERSE of --affected: the non-test symbols this test file transitively calls into -- what it actually covers.

The first question when a test fails and you have its name and nothing else. Ranked by PageRank, capped at 40 rows (raise with --limit; --offset pages). A NON-TEST path REFUSES rather than answering generically: this verb IS the test/non-test partition (it subtracts test code from the answer), which means nothing for a non-test file -- for "what does this call", use --callees=SYM or --graph-query callees(...) A shell harness carries harness=script: subprocess coverage is unmodelled, so reaches=0 there is a stated limit, not a measurement (the inverse of script_gates_unmodelled).

**Try it**

_Which symbols a TEST FILE exercises — the reverse direction of --affected._

```
$ ./build/ripwire . --exercises=test/regression.sh
<!-- ripwire exercises: the NON-TEST symbols this test transitively calls into — what it covers (the inverse of the affected verb). <t> = the seed test files the pattern matched; <s> = the covered symbols, PageRank desc. harness=script|mixed says the seed set contains shell gates, whose subprocess coverage this walk cannot see -->
<exercises of="test/regression.sh" seed_files="1" shown_seed_files="1" seed_files_capped="0" test_symbols="2" reaches="0" harness="script" note="a shell gate invokes the compiled binary as a subprocess; script-to-binary edges are not modelled, so reaches= counts call-graph reach only and cannot see  … [line truncated: 49 more bytes on this line]
<t p="./test/regression.sh"/>
</exercises>
```

**Shaped by:** `--test-gate`, `--json`

**Caveats (stated by the binary):**

- Ranked by PageRank, capped at 40 rows (raise with --limit;

### `--situ[=F1,F2]`

**Answers:** situational awareness for a change: blast radius + tests + co-change (default = git diff)

**Try it**

_Mid-task situational report for the current git diff — recorded against a DIRTY tree (contrast with the sandbox run below)._

```
$ ./build/ripwire . --situ
ripwire situational-awareness — 4 changed file(s), 163 symbols in them
  [1] blast radius: 11 symbols across 7 files transitively depend on these changes
        ./src/main.cpp  (3 dependent symbols)
        ./src/crossref.h  (2 dependent symbols)
        ./src/mcp.h  (2 dependent symbols)
        ./bench/bench_convergence.cpp  (1 dependent symbols)
        ./src/gitoracle.h  (1 dependent symbols)
        ./src/mcpserver.h  (1 dependent symbols)
        ./src/mcpverbs.h  (1 dependent symbols)
  [2] tests to run (0): (none transitively reach these files)
        (332 test/*.sh gates are NOT modelled: script-to-binary edges are not call edges, so they never appear here — a path count, not every one invokes the binary)
  [3] co-change — usually edited with these but NOT in your diff (4):
        ./src/graph.h  (co-edited in 43% of commits)
        ./src/main.cpp  (co-edited in 43% of commits)
... [2 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--mentions`, `--affected`, `--test-gate`

### `--handoff`

**Answers:** continuation packet for the NEXT session: <verified> disk truth (branch/sha, changed files+symbols, blast radius, tests-to-run) + <heuristic> labeled suggestions (co-change partners, committed notes, plan/design doc pointers via a branch+commit-subject query).

Empty diff is fine — the packet still carries branch/sha + heuristics. Composes with --token-budget=N (drops heuristic rows tail-first, disclosed as withheld= in the header; verified rows are never dropped). Single-root only.

**Caveats (stated by the binary):**

- continuation packet for the NEXT session: <verified> disk truth (branch/sha, changed files+symbols, blast radius, tests-to-run) + <heuristic> labeled suggestions (co-change partners, committed notes, plan/design doc pointers via a branch+commit-subject query).
- Empty diff is fine — the packet still carries branch/sha + heuristics.
- Composes with --token-budget=N (drops heuristic rows tail-first, disclosed as withheld= in the header;

### `--test-gate[=F1,F2]`

**Answers:** agent self-check before a PR (pair with --quality-delta): names the tests to run + the UNTESTED blast radius;

exit 4 if either obligation is non-empty (run the tests, then rely on green). (default = git diff) run= on a test row        --affected/--situ/--test-gate/--exercises/--pr-context/--pack-task name harness FILES, not commands. A row carries run="<cmd>" when a runner is DERIVABLE from real evidence: a test-dir .sh/.py whose basename stem matches the harness's, or whose TEXT names the harness file. Spelled with the same root you scanned, so it pastes straight into a shell. NO run= means NOT DERIVABLE -- never a guessed suite command

**Try it**

_Pre-PR gate recorded against a DIRTY tree, so the obligations below are the working copy's real ones — the recorded exit code says which way it went._

```
$ ./build/ripwire . --test-gate
<!-- ripwire test-gate (TDAD-parity, arXiv 2603.17973): the tests to run for this change + the UNTESTED blast radius. A queryable call-graph+test map cut agent-caused regressions -70% (6.08%->1.82%); this gate names the obligations, the agent runs the tests then relies on green. exit 4 if tests OR untested is non-empty. TWO INDEPENDENT LISTINGS, each with its own row count: shown_tests= counts the <t> tests-to-run rows and shown_untested= counts the <u> blast-radius rows (a single shown= could only ever have described one of them). The <t> rows are the COMPLETE obligation and are never windowed, so they REPEAT VERBATIM on every page — a walker that concatenates pages must take them from one page only; offset=/limit= window the <u> rows alone. The <u> listing shows 25 rows by default: raise the default cap with limit=N (offset=M pages). script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) - script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=. UNIT: untested= here counts impacted SYMBOLS. The seams verb spells untested= over cross-directory call EDGES and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. -->
<test-gate changed="4" impacted="11" tests="0" untested="11" shown_tests="0" tests_capped="0" shown_untested="11" untested_capped="0" script_gates_unmodelled="332" at="bc09d0260+dirty">
<u sym="dispatchMcpLine" p="./src/mcp.h" ccx="428"/>
... [11 more line(s); run it to see the whole thing]
```

**Shaped by:** `--mentions`, `--affected`, `--quality-delta`, `--json`

**Caveats (stated by the binary):**

- NO run= means NOT DERIVABLE -- never a guessed suite command

### `--grep=STR | --regex=PAT`

**Answers:** literal / regex search + enclosing symbol + the matched line --grep-context=N | --grep-before=N / --grep-after=N   ripgrep-style N lines of source around each hit

**Try it**

_Regex search + enclosing symbol._

```
$ ./build/ripwire . --regex='fnv1a\w+'
<!-- ripwire grep: parallel literal/regex scan; each hit carries its matched line (m) and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached). raise the default cap with limit=N (offset=M pages); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="fnv1a\w+" files="24" hits="106" shown="100" capped="1" hits_capped="0">
<hit p="./src/arch.h:406" in="rw::fnv1a64">
<m>
<![CDATA[inline std::uint64_t fnv1a64( std::string_view s ) noexcept]]>
</m>
</hit>
<hit p="./src/arch.h:409" in="rw::fnv1a64">
<m>
<![CDATA[    for( unsigned char c : s ) { h ^= c; h = hashutil::fnv1aMultiply( h ); }]]>
</m>
</hit>
<hit p="./src/arch.h:464" in="rw::archViolHash">
<m>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--expand`, `--no-redact`, `--json`

### `--match=QUERY`

**Answers:** tree-sitter structural (shape) query

**Try it**

_Tree-sitter structural query WITHOUT a capture — a bare node query gets a capture AUTO-ADDED (auto_captured="1") instead of silently matching nothing._

```
$ ./build/ripwire . --match='(if_statement)'
<!-- ripwire match: tree-sitter structural query; each hit = a captured node + its enclosing symbol. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (engine match limit reached). auto_captured="1" ⇒ the query bound no @capture and ripwire appended `@m` to its single top-level pattern. raise the default cap with limit=N (offset=M pages) -->
<match hits="5000" shown="100" capped="1" hits_capped="1" auto_captured="1">
<m p="./bench/agentloop/analyze.py:34" in="load_results">if data.get( "schema" ) != SCHEMA:         raise SystemExit( f"{path}: unexpected schema {data.get('schema')!r} (expecte</m>
<m p="./bench/agentloop/analyze.py:50" in="pair_by_task_seed">if base and ctx and base["status"] == "ok" and ctx["status"] == "ok" \            and base["resolved"] is not None and c</m>
<m p="./bench/agentloop/analyze.py:64" in="clustered_bootstrap_lower">if not repos: return 0.0, []</m>
<m p="./bench/agentloop/analyze.py:80" in="loc_hit_delta">if base["localization_hit"] is None or ctx["localization_hit"] is None: return 0.0</m>
<m p="./bench/agentloop/analyze.py:89" in="paired_ratio">if bv: ratios.append( cv / bv - 1 )</m>
<m p="./bench/agentloop/analyze.py:90" in="paired_ratio">if not ratios: return None, None</m>
<m p="./bench/agentloop/analyze.py:100" in="analyze">if not paired:         out["note"] = "zero complete paired (baseline,ripwire_mcp) runs — nothing to analyze yet"      </m>
<m p="./bench/agentloop/analyze.py:124" in="print_report">if "note" in out:         print( f"  {out['note']}" ); return</m>
... [21 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-redact`, `--json`

### `--query=TERMS`

**Answers:** raw BM25 ranking (debug);

use --for

**Try it**

_Raw BM25 ranking (debug lens; --for is the real verb)._

```
$ ./build/ripwire . --query="teleport pagerank" --top-k=5
<!-- routed: subtoken+body BM25 (-for's default) — no strong name hit; broad query, plain rg may also win -->
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=850 symbols=6432 edges=8737 shown=5 est_tokens=587 ambiguous=2631 unresolved=662 precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="587">
<f p="./src/main.cpp">
<s t="fn" n="churnRankedGraph" amb="2" k="14.8186">
<c n="resolveSinceScope"/>
<c n="churnTeleport"/>
<c n="churnTeleportWorkspace"/>
<c n="churnWindowStamp"/>
<c n="rankGraphTeleport"/>
<c n="empty"/>
<c n="empty"/>
<c n="push_back"/>
... [26 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--token-budget`, `--no-route`, `--adaptive`, `--format`

---

## zoom the detail ladder

### `--detail=N`

**Answers:** (with --for) importance-weighted detail: FULL bodies for the top-N ranked symbols + signatures for the rest, in ONE call — spend body tokens only on the head the rank identifies.

Composes with --max-tokens (bounds the bodies) and --adaptive. 0 = off.

**Try it**

_Importance-weighted detail: FULL bodies for top-2, signatures for the rest._

```
$ ./build/ripwire . --for="pagerank power iteration" --detail=2
<ctx task="pagerank power iteration" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "pagerank power iteration" [routed: subtoken+body BM25 (-for's default) — no strong name hit, multi-word conceptual query]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="4248" -->
<sigs capped="1">
<f p="./src/pagerank.cpp">
<d l="34" n="pageRankDouble" id="./src/pagerank.cpp::rw::pageRankDouble" cx="18" ccx="33" in="1" churn="3" amp="8" tested="1">unsigned pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;doub … [line truncated: 21 more bytes on this line]
</f>
<f p="./src/infra/dynamic_map.hpp" layer="infra">
<d l="290" n="leaf_node" id="./src/infra/dynamic_map.hpp::leaf_node::leaf_node" cx="0" ccx="0" in="0" churn="1">struct alignas(16) leaf_node</d>
<d l="310" n="dynamic_map" id="./src/infra/dynamic_map.hpp::dynamic_map::dynamic_map" cx="0" ccx="0" in="0" churn="1">class dynamic_map</d>
<d l="979" n="values_begin" id="./src/infra/dynamic_map.hpp::dynamic_map::values_begin" cx="2" ccx="1" in="3" churn="1" amp="3">value_iterator values_begin()</d>
... [21 more line(s); run it to see the whole thing]
```

**Shaped by:** `--owners`, `--plan`, `--abi`, `--flip`, `--from-trace`, `--json`

### `--pack-signatures`

**Answers:** body-elided decl skeletons — ~59-68% fewer element bytes than the same symbols' full --expand bodies (68% at the top-50 sigs payload cap — the sigs payload is top-50 whatever --top-k is set to, and --top-k's own default is 200), measured at top-10/50/100 on this repo with the corpus-root prefix subtracted from both sides: that prefix repeats inside every element, is charged in both forms, and is not what this elides — count it and the figure becomes a function of how deep your checkout sits (the same corpus reads 60% from a relative root and 41% from a 130-byte absolute one).

The share RISES with the result size. Like the --format=columnar sibling, a small result can invert it — a signature plus its doc comment can be bigger than a short body.

**Try it**

_Body-elided decl skeletons — recounted on this corpus. Measured as element bytes: the <d> signature+doc elements --pack-signatures emits, against the SAME symbols' full <b> bodies from --expand, with the CORPUS-ROOT PREFIX SUBTRACTED FROM BOTH SIDES. That subtraction is the whole methodology and the figure is meaningless without it: the root repeats inside every element's id= and p=, it is not what this verb elides, and counting it makes the headline a function of how deep the checkout happens to sit on disk — on one corpus, three spellings of the same root read 18.6 points apart before the subtraction and agree exactly after it. Root-neutralised on THIS repo: 46.7% fewer bytes at top-10, 67.0% at top-50, 66.2% at top-100. top-50 is the number to quote, because the sigs payload is top-50 regardless of --top-k and is therefore what THIS command emits. '~70%' is reachable at larger N but overstates the smaller shapes people actually run, and like the --format=columnar sibling below, a single small/trivial body can invert it (signature+doc bigger than the body). test/showcasecapturecheck.sh (C) re-derives all three from this repo every run, in the same quantity, and fails if the caption and the recount drift apart._

```
$ ./build/ripwire . --pack-signatures --top-k=10
<ctx>
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=850 symbols=6432 edges=8737 shown=10 est_tokens=4687 ambiguous=2631 unresolved=662 precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="4687">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0503">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0133">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0122">
</s>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--json`

### `--outline=A,B,...`

**Answers:** control-flow skeletons of A,B,...

(same selector grammar as --expand, minus the range)

**Try it**

_Control-flow skeleton of one symbol, payload-only via the new --top-k=0._

```
$ ./build/ripwire . --outline=rankGraphTeleport --top-k=0
<ctx><outline><o t="fn" l="1277" p="./src/graph.h" n="rankGraphTeleport"><![CDATA[inline std::vector<float> rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    if( N )
    {
  ...
    }
    std::vector<float> r( N, 0.f );
    std::transform( rankDouble.begin(), rankDouble.end(), r.begin(), []( double value ) { return float( value ); } );
    return r;
... [2 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--compress`, `--no-redact`, `--json`

### `--expand=A,B,...`

**Answers:** full bodies of A,B,...

Selector grammar per item (the tail after the LAST ':' decides; a tail STARTING WITH A DIGIT is a range, anything else is a name): NAME                every def of that name  |  FILE:NAME           that file's def NAME:START-END      body slice              |  FILE:NAME:START-END selector + slice FILE:LINE:NAME      paste a row's p="path:line" straight from --callers/--lint/--grep (NOT --hotspots: its p= is a BARE path — build FILE:LINE:NAME from its own p=/top_l=/top= instead, since top= is just the worst function's name) path::scope::name   the canonical id= --for/--pack-task emit (START-END is 1-based within the def's OWN body — lines="lo-hi/total" marks the slice partial; out-of-range clamps. FILE matches any path substring, like --callers/--lego.)

**Try it**

_NEW since the last capture: --top-k=0 means PAYLOAD-ONLY — no ranked map rides along with the body you asked for._

```
$ ./build/ripwire . --top-k=0 --expand=rankGraphTeleport
<ctx><bodies shown="1" total="1" capped="0"><b t="fn" l="1277" p="./src/graph.h" n="rankGraphTeleport"><![CDATA[inline std::vector<float> rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    if( N )
    {
        double teleportMass = 0.0;
        for( const double value : teleport )
            teleportMass += value;
        if( teleportMass > 0.0 )
        {
... [10 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--pack-signatures`, `--outline`, `--compress`, `--hotspots`, `--from-trace`, `--notes`, `--json`

### `--compress`

**Answers:** strip comments + collapse blank runs from --expand/--outline body output (~20-35% token cut)

**Try it**

_Comments stripped + blank runs collapsed — compressBody is the function that implements --compress itself, chosen because it is comment-heavy enough to show a real reduction (the previously captioned symbol had no comments or blank runs, so before/after were byte-identical under a caption promising a difference)._

```
$ ./build/ripwire . --expand=compressBody --top-k=0 --compress
<ctx><bodies shown="1" total="1" capped="0"><b t="fn" l="1707" p="./src/serialize.h" n="compressBody"><![CDATA[inline std::string compressBody( std::string_view src )
{


    std::string out;
    out.reserve( src.size() );

    const std::size_t N = src.size();
    std::size_t       i = 0;

    while( i < N )
    {
        const char c = src[i];

... [17 more line(s); run it to see the whole thing]
```

### `--pack-top-n=N`

**Answers:** pack the N top symbols' bodies  [--pack-budget-bytes=B]

**Try it**

_Pack the top-3 ranked symbols' full bodies (deprecated verb; see stderr)._

```
$ ./build/ripwire . --pack-top-n=3 --top-k=0
<ctx><src p="./src/svector.h"><![CDATA[#pragma once

// svector.h — rw::svector: a small-vector with N INLINE slots that spills to the heap only past N.
//
// WHY THIS EXISTS ALONGSIDE the vendored martinus/svector (third_party/svector.h, ankerl::svector):
// it's purpose-built for the ONE shape ripwire leans on hardest — a `Map<K, svector<V,N>>` of many tiny
// id-lists (byName / shard maps): WRITE-ONCE during the parse/merge, then READ-HOT during resolve.
//
//   • build win (shared with martinus): the N small lists that would each malloc become inline — one fewer
//     heap allocation per collection, no pointer-chase to the payload.
//   • read win (the differentiator): size() is `return sz_` — BRANCH-FREE. martinus packs its size into the
//     SVO buffer to reach 16 B, so its size() branches on is_direct(); on a 4M-read hot loop that branch
//     costs ~6 ms. We keep an explicit sz_ field instead: sizeof(svector<uint32,2>) = 24 B (same as
//     std::vector), 8 B more than martinus — we spend those 8 bytes to make the hot read branch-free.
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--token-budget`

### `--no-redact`

**Answers:** emit source/doc text VERBATIM, redacting nothing REDACTED by default (high-confidence credential SHAPES only, precision over recall): emitted symbol BODIES, doc/markdown bodies and doc-comment excerpts, the --outline skeleton, and SIGNATURES — a default argument carries whatever literal was written.

NOT redacted, and a deliberate residual: --grep/--regex/--match hit lines and their --grep-context neighbours, and --note-add/--notes text. --grep is the exception on purpose — auditing a repo FOR secrets needs the hit you searched for shown verbatim.

**Try it**

_--no-redact: emit bodies verbatim (credential redaction is on by default)._

```
$ ./build/ripwire . --expand=readAckRecords --top-k=0 --no-redact
<ctx><bodies shown="1" total="1" capped="0"><b t="fn" l="2124" p="./src/quality.h" n="readAckRecords"><![CDATA[inline gtl::btree_map<std::string, AckRecord> readAckRecords( const std::string& path )
{
    gtl::btree_map<std::string, AckRecord> out;
    std::ifstream f( path );
    if( !f ) return out;
    std::string line;
    while( std::getline( f, line ) )
    {
        while( !line.empty() && ( line.back() == '\r' || line.back() == '\n' ) ) line.pop_back();   // CRLF tolerance (merged-in Windows checkout)
        if( line.empty() || line[0] == '#' ) continue;
        std::istringstream is( line );
        std::string tag, kind;
        std::uint64_t key = 0;
        std::uint32_t ackNow = 0;
... [15 more line(s); run it to see the whole thing]
```

---

## assess quality / structure

### `--metrics`

**Answers:** annotate fan-in/out + complexity (descriptive;

coupling is the validated signal, complexity is a size-correlated one). also surfaces amp= (--metrics/--for/--exemplar): amp = |direct callers| (symbol-level, the in-edge CSR) + |co-change partners of the symbol's FILE| (file-level, mined from git history) — a deliberate GRANULARITY MIX, not a graph-only count; degrades to callers-only (still valid) when git/history is unavailable. NOT the same quantity as --impact's reaches=: reaches= is the TRANSITIVE blast radius over the call graph alone (everything that reaches SYM, any hop count); amp= is DIRECT callers plus a historical co-edit signal the call graph cannot see at all — the two numbers on the same symbol routinely differ several-fold (one seen case: 4.6x apart) because they measure different things, not because one is wrong

**Try it**

_Fan-in/out + complexity annotations on the map._

```
$ ./build/ripwire . --metrics --top-k=10
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- metrics: in=fan-in out=fan-out cx=cyclomatic ccx=cognitive loc=lines params=count nest=depth cbo=coupling lcom4=cohesion amp=change-amplification tested=1 role=hub(fan-in 8+; uses spells role call|read|write|import|extends). Absent=N/A, never 0. -->
<!-- files=850 symbols=6432 edges=8737 shown=10 est_tokens=1020 ambiguous=2631 unresolved=662 precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="1020">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" in="796" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" cbo="0" amp="796" tested="1" k="0.0503">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" in="367" out="3" cx="2" ccx="1" role="hub" loc="1" params="1" nest="1" cbo="3" amp="367" tested="1" amb="2" k="0.0133">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" in="8" out="0" cx="2" ccx="1" role="hub" loc="1" params="0" nest="1" cbo="0" amp="8" tested="1" k="0.0122">
</s>
... [22 more line(s); run it to see the whole thing]
```

**Shaped by:** `--json`, `--index-out`

**Caveats (stated by the binary):**

- also surfaces amp= (--metrics/--for/--exemplar): amp = |direct callers| (symbol-level, the in-edge CSR) + |co-change partners of the symbol's FILE| (file-level, mined from git history) — a deliberate GRANULARITY MIX, not a graph-only count;
- degrades to callers-only (still valid) when git/history is unavailable.
- amp= is DIRECT callers plus a historical co-edit signal the call graph cannot see at all — the two numbers on the same symbol routinely differ several-fold (one seen case: 4.6x apart) because they measure different things, not because one is wrong

### `--deps`

**Answers:** file->file dependency graph (god-files, cycles — validated);

its nccd (Lakos) is a design heuristic, not independently outcome-validated. instab= (Martin's I=Ce/(Ca+Ce)) counts project includes ONLY -- system/third-party headers are excluded from Ce, matching stabledeps' gap= so gap == consumer's instab - provider's instab always. <health>'s ccd/acd/nccd/shape are computed over dep_files= (files whose language has #include/import syntax) not files= (the raw corpus, incl. .sh/.md/.json/etc, which can't participate in the graph) -- --arch's propagation_cost uses the same N

**Try it**

_File->file dependency graph (god-files, cycles)._

```
$ ./build/ripwire . --deps
<!-- ripwire deps: file-to-file #include/import view, heaviest transitive cone first. files= (root) = files with at least one dependency edge (this listing's own denominator); health files= = the whole indexed corpus; health dep_files= = the dependency-CAPABLE subset of it (the ccd/acd/nccd denominator). raise the default cap with limit=N (offset=M pages). -->
<deps files="202" shown="40" capped="1">
<health files="850" dep_files="398" ccd="1711" acd="4.3" nccd="0.56" shape="horizontal"/>
<godfiles total="124" shown="12" capped="1">
<f p="./src/model.h" afferent="50"/>
<f p="./src/graph.h" afferent="23"/>
<f p="./src/serialize.h" afferent="20"/>
<f p="./src/arch.h" afferent="18"/>
<f p="./src/jsonesc.h" afferent="13"/>
<f p="./src/ingest.h" afferent="12"/>
<f p="./src/quality.h" afferent="12"/>
<f p="./src/filter.h" afferent="11"/>
<f p="./src/hashutil.h" afferent="10"/>
<f p="./src/gitmine.h" afferent="9"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--arch`, `--json`

**Caveats (stated by the binary):**

- its nccd (Lakos) is a design heuristic, not independently outcome-validated.

### `--hotspots`

**Answers:** complexity x recent git churn (maintenance pain);

each row's top= is the worst function's BARE name, top_ccx= its cognitive complexity, top_l= its source line (build an --expand selector from p=/top_l=/top=, not from top= alone — it no longer carries a :line suffix)

**Try it**

_Complexity x recent git churn (maintenance pain)._

```
$ ./build/ripwire . --hotspots
<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=12mo). churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. unranked_no_complexity= is a file with commits but no function or method to score (a pure declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the join could not match), which scores zero for a reason that is not about the file. Treat it as an upper bound on quietness, not a measure of it. raise the default cap with limit=N (offset=M pages) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<hotspots window="12mo" files="850" ranked="221" unranked_no_churn="0" unranked_no_complexity="629" shown="40" capped="1" at="bc09d0260+dirty">
<f p="./src/main.cpp" churn="8" ccx="3311" score="26488" top="main" top_ccx="376" top_l="8007"/>
<f p="./src/ingest.cpp" churn="6" ccx="2713" score="16278" top="ingest" top_ccx="702" top_l="3856"/>
<f p="./src/graph.h" churn="7" ccx="1424" score="9968" top="buildGraph" top_ccx="712" top_l="379"/>
... [25 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--expand`, `--since`, `--json`

### `--clones`

**Answers:** token-normalized duplicate bodies

**Try it**

_Token-normalized duplicate bodies._

```
$ ./build/ripwire . --clones
<!-- ripwire clones: function bodies with similar normalized token streams (identifiers/literals normalized, so renamed copies match). type=2 exact/renamed (Type-1/2); type=3 gapped near-miss (an inserted/changed statement, similarity in [0.80,1.0)). Reuse don't reimplement; a fix to one likely belongs in all. groups= and type3= are the two GROUP-TYPE totals (each capped independently, so neither is the row count); total= is the true row total (groups + type3-group-count) and is ALWAYS present, paged or not; shown= is the number of group rows that follow this run. capped="1" means rows were dropped. exempt= on a group ⇒ every member is on a path the quality-delta verb's duplication kind deliberately ignores (fixture dirs / shell test-runners repeat boilerplate by convention) — a fact here, never a gate there; exempt_groups= counts them over ALL groups. raise the default cap with limit=N (offset=M pages). -->
<clones groups="39" type3="154" total="193" exempt_groups="80" shown="79" capped="1">
<group type="2" tokens="273" n="3" exempt="shell-runner">
<f n="monotonic_check" p="./test/pyimportprecisecheck.sh:88"/>
<f n="monotonic_check" p="./test/rustimportprecisecheck.sh:114"/>
<f n="monotonic_check" p="./test/tsimportprecisecheck.sh:87"/>
</group>
<group type="2" tokens="207" n="4" exempt="shell-runner">
<f n="batch_sub" p="./test/mcpclidiffcheck.sh:63"/>
<f n="batch_sub" p="./test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="./test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="./test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" tokens="142" n="2">
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--json`

### `--readability`

**Answers:** per-function readability lens, LEAST readable first: vol= Halstead volume V (N*log2(eta)), ent= Shannon token entropy E, lines= L, posnett= sigmoid(8.87 - 0.033V + 0.40L - 1.5E) (Posnett/Hindle/Devanbu, MSR 2011).

APPROXIMATION, disclosed: ONE token-class table serves every language (keywords + punctuation = operators, identifiers + literals = operands), with no per-grammar refinement, so V is cross-language and not a per-grammar Halstead count. The formula was fitted on snippets of 20 lines or fewer, so it is a RANKING lens, not a grade: read the ORDER of the rows, not the number on any one of them. Pages with limit=N (offset=M); default 40 rows. Declarations with no body are not measured.

**Shaped by:** `--json`

**Caveats (stated by the binary):**

- APPROXIMATION, disclosed: ONE token-class table serves every language (keywords + punctuation = operators, identifiers + literals = operands), with no per-grammar refinement, so V is cross-language and not a per-grammar Halstead count.
- The formula was fitted on snippets of 20 lines or fewer, so it is a RANKING lens, not a grade: read the ORDER of the rows, not the number on any one of them.
- Pages with limit=N (offset=M);

### `--nonlocal-state`

**Answers:** per function, the NON-LOCAL MUTABLE STATE it can reach, MOST WRITES FIRST: writes= reads= are the distinct cells this function OR its transitive callees write / read;

direct_writes= direct_reads= are the subsets in its own body. A cell is a file/namespace-scope variable, a function-local static, or a Python module global; a const/constexpr/consteval declaration is not a cell. Each cell child names its declaration, its direction (dir=r|w|rw) and either the use site in this body (at=) or the callee it came through (via=). Lineage: Fowler's Global Data / Mutable Data smells (2018) name the hazard and ship no metric; Marinescu's ATFD (ICSM 2004) is the closest number but is one-hop, per-class, Java, and direction-blind; QMOOD DAM and MOOD AHF/MHF count DECLARED VISIBILITY and so score a class with private fields and leaked mutable internals as perfectly encapsulated; the only published measurement of externally reachable state (Potanin/Noble/Biddle 2004) is DYNAMIC, Java-only, and its tool is unmaintained. UNSOUND BY CONSTRUCTION -- it cannot see indirect calls, pointer aliasing, macro-named cells or reflection-like dispatch, and a local SHADOWING a cell name can be charged to the cell -- so every count is a FLOOR (counts_floor="1") and the blind spots are listed in the report's own legend. COVERS C++, ObjC and Python -- the languages whose read/write USE SITES the index carries. Every other indexed language is named on the root as unanalyzed_langs= and contributes no cells and no rows: that absence is NOT a measured zero. Pages with limit=N (offset=M); default 40 rows.

**Shaped by:** `--json`

**Caveats (stated by the binary):**

- a const/constexpr/consteval declaration is not a cell.
- UNSOUND BY CONSTRUCTION -- it cannot see indirect calls, pointer aliasing, macro-named cells or reflection-like dispatch, and a local SHADOWING a cell name can be charged to the cell -- so every count is a FLOOR (counts_floor="1") and the blind spots are listed in the report's own legend.
- Every other indexed language is named on the root as unanalyzed_langs= and contributes no cells and no rows: that absence is NOT a measured zero.

### `--ensemble`

**Answers:** the FAMILY JOIN: per function, which of FOUR orthogonal evidence families fire, ranked by the COUNT of distinct families

**Shaped by:** `--json`

### `--quality-panel[=PRESET]`

**Answers:** THE SINGLE COMMAND: the whole quality panel in ONE ranked report.

Per function, which of SIX evidence families fire -- structural (shape), lexical (identifier text), confusion (syntactic construct), historical (git churn), colocation (what you must read from outside this file), state (this function's OWN BODY touching non-local mutable state) -- ranked by the COUNT of distinct families, NEVER by a weighted composite, each row carrying its own evidence. PRESET selects and cuts, never weights: strict (the four families measured steady enough to gate on, 2 must agree) | default (all six, 2; the bare form) | lenient (all six, 1 -- a reading order, not a verdict). historical and colocation are out of strict: each is a fixed-size worst-40 cut over a ranking whose population moves, so both re-shuffle on code that did not change (docs/EVALS.md section 9.9). A family that could not be measured here is UNAVAILABLE, never 'did not fire', and of= drops with it. A lens: exit 0. Pages limit=N (offset=M).

**Shaped by:** `--json`

**Caveats (stated by the binary):**

- PRESET selects and cuts, never weights: strict (the four families measured steady enough to gate on, 2 must agree) | default (all six, 2;
- the bare form) | lenient (all six, 1 -- a reading order, not a verdict).
- A family that could not be measured here is UNAVAILABLE, never 'did not fire', and of= drops with it.

### `--context-ratio`

**Answers:** the LOCAL-REASONING lens: to understand this symbol, how much must you know that is NOT in front of you? Per symbol (and rolled up per file) the distinct in-corpus definitions and files its reference sites resolve to, and the share of them defined OUTSIDE its own file — as an edge count (ent_ratio=) and, weighted by the tokens a reader must actually read, as read_ratio=.

ATTRIBUTION: the fraction itself is published — it is Beck and Diehl's per-class congruence (FSE 2011) flipped, with Martin's instability Ce/(Ca+Ce) as its crude ancestor. What is refined here is the READER WEIGHTING and the use of EVERY reference role (call, read, write, import, base class, member type), not calls alone. Resolution is NAME-BASED and language-gated, the same heuristic level the uses verb works at; a name with several definitions contributes each of them up to defs_per_name_cap= and amb= counts it. Names with no in-corpus definition land in ext=, which locals and parameters DOMINATE, so ext= is not a dependency count and is excluded from both ratios. ents=/files= are FLOORS. Pages with limit=N (offset=M); default 40 symbol rows and 40 file rows. An ORDERING, never a grade and never a threshold.

**Shaped by:** `--json`

**Caveats (stated by the binary):**

- Resolution is NAME-BASED and language-gated, the same heuristic level the uses verb works at;
- Names with no in-corpus definition land in ext=, which locals and parameters DOMINATE, so ext= is not a dependency count and is excluded from both ratios.
- Pages with limit=N (offset=M);

### `--naming-calibration`

**Answers:** score the naming-* lint rules against this repo's OWN rename history: one git log pass mines old->new identifier substitutions, joins each to the symbol it became at HEAD, and scores BOTH spellings with the same predicates --lint runs.

old=fires on the abandoned spelling, new=fires on the chosen one, proxy=old/(old+new), where 0.50 is exactly chance. A NOISY PROXY, stated as one -- rebrands, moves and API changes all look like renames -- so read pairs= (the sample size) first; the group rules report scope=group-rule, not a fake 0/0. Exit 0 always: the per-rule floor lives in test/namingcalibrationcheck.sh

**Caveats (stated by the binary):**

- A NOISY PROXY, stated as one -- rebrands, moves and API changes all look like renames -- so read pairs= (the sample size) first;
- the group rules report scope=group-rule, not a fake 0/0.
- Exit 0 always: the per-rule floor lives in test/namingcalibrationcheck.sh

### `--naming-consistency`

**Answers:** TIER A convention normalization (section 9.2): the corpus's OWN case-convention vote per (language, kind) group among multi-token eligible names -- a single-token name, or one split only on digit boundaries, carries no case signal and is silently excluded.

A group DECIDES only when its leading style (camel/pascal/snake/screaming) clears a 20-name sample floor AND a 90% agreement floor; short of either it reports style=UNAVAILABLE with why= naming which bar it missed, never a guessed winner. Every off-convention name in a DECIDED group (including mixed -- naming-case's own finding, a separator AND a transition in one name, which never wins a vote) gets propose=: its OWN subtokens mechanically recombined into the dominant style -- no dictionary, no synonym judgment, which is what keeps this derivable from the corpus rather than invented. propose= is a SUGGESTION, never a safe-to-blind-apply rename -- an actual rename needs --uses to prove the complete reference set first. Exit 0 always: a lens, not a gate. Pages limit=N (offset=M); default 40 rows

**Shaped by:** `--json`

**Caveats (stated by the binary):**

- A group DECIDES only when its leading style (camel/pascal/snake/screaming) clears a 20-name sample floor AND a 90% agreement floor;
- short of either it reports style=UNAVAILABLE with why= naming which bar it missed, never a guessed winner.
- propose= is a SUGGESTION, never a safe-to-blind-apply rename -- an actual rename needs --uses to prove the complete reference set first.

### `--naming-locals`

**Answers:** OPT-IN --lint MODIFIER (requires --lint;

a no-op alone), OFF by default: local-variable-indexing plan Phase 2 (PLAN.md 2026-08-06 evening). Runs the naming-short/naming-wordy/naming-underscore/naming-case predicates (same tags, same rule bodies as the existing Symbol-scoped checks) against LOCAL variable names too, C/C++ only, but ONLY inside a function that already clears an EXISTING size/complexity gate (loc>80 OR nest>4 OR ccx>=15 -- the shipped large-function/deep-nesting thresholds) AND has locals>=8 (measured floor: median locals=9 among this repo's own 377 gated functions) -- never a whole-corpus local-name sweep. naming-short additionally requires the local's own declDepth>=2 (nested, not the function's own outermost block). Deliberately breaks the lens's stated invariant that an un-indexed local can never be flagged -- read the WITHDRAWN note atop src/naminglens.h before relying on this. NOT default-enabled inside a plain --lint run and not a candidate for it yet: the plan's own hard blocker (a hand-curated fixture corpus AND a manual real-corpus audit for idiomatic-short-name skew -- i/j/k/buf/tmp/ err) has not run. Exit 0 always; findings ride the same naming-* tallies/floors as --lint

**Caveats (stated by the binary):**

- Deliberately breaks the lens's stated invariant that an un-indexed local can never be flagged -- read the WITHDRAWN note atop src/naminglens.h before relying on this.
- NOT default-enabled inside a plain --lint run and not a candidate for it yet: the plan's own hard blocker (a hand-curated fixture corpus AND a manual real-corpus audit for idiomatic-short-name skew -- i/j/k/buf/tmp/ err) has not run.
- findings ride the same naming-* tallies/floors as --lint

### `--comment-coherence`

**Answers:** per function/method WITH A DOC COMMENT, two published content measures, MOST NAME-RESTATING FIRST: c_coeff (Steidl/Hummel/Juergens, ICPC 2013) is the fraction of the comment's words within Levenshtein distance <2 of a word in the symbol's own (split) name — HIGH c_coeff IS BAD, it means the comment mostly repeats the name and adds no information (the opposite of the naive 'high coherence sounds good' reading).

cic (Scalabrino, ICPC 2016 / JSEP 2018) is the Jaccard overlap of two preprocessed term sets: the comment's vocabulary vs every identifier the definition's own span uses (operators/keywords stripped, camelCase/snake_case split, English stopwords dropped, deduplicated). The two measure different things and are expected to disagree — both are reported, never collapsed to one number. UNAVAILABLE (not scored, never a zero) where no doc comment exists, counted in no_comment= on the root. Complements --doc-drift (which checks whether a markdown CLAIM is stale) with comment CONTENT, over a disjoint input — neither verb duplicates the other. Pages with limit=N (offset=M); default 40 rows.

**Shaped by:** `--json`

**Caveats (stated by the binary):**

- The two measure different things and are expected to disagree — both are reported, never collapsed to one number.
- UNAVAILABLE (not scored, never a zero) where no doc comment exists, counted in no_comment= on the root.
- Pages with limit=N (offset=M);

### `--cochange[=FILE]`

**Answers:** files that change together in git (hidden coupling;

the rows' own legend defines surprising=)

**Try it**

_Files that change together in git (hidden coupling)._

```
$ ./build/ripwire . --cochange
<!-- ripwire cochange: file pairs that change together in git but share no transitive static dependency (surprising=1) = hidden coupling. together= is the number of commits in window= that touched BOTH files (3 or more, or the pair is not reported); deg= is that count over the commit count of the LESS-CHANGED of the two files, so 1.00 means the quieter file never changed without the other. window= is the mining window: the default 18 months, or the since=REV|DATE value when one resolved. surprising= is only defined where BOTH sides could carry a static dependency at all (the same dependency-capable predicate deps <health dep_files=> uses: source languages yes; sh, md, json, ruby and binary/unknown files no). A pair with a dep-incapable side keeps its row and carries dep_capable=0 instead, because for it "shares no static dependency" is vacuously true. raise the default cap with limit=N (offset=M pages) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<cochange pairs="13" window="18mo" shown="13" capped="0" at="bc09d0260+dirty">
<pair a="./src/cli.h" b="./src/mcp.h" together="3" deg="1.00" surprising="1"/>
<pair a="./src/cli.h" b="./src/graph.h" together="3" deg="0.75" surprising="1"/>
<pair a="./src/cli.h" b="./src/mcpverbs.h" together="3" deg="0.75" surprising="1"/>
<pair a="./src/main.cpp" b="./src/mcpverbs.h" together="4" deg="1.00"/>
<pair a="./src/main.cpp" b="./src/serialize.h" together="3" deg="1.00"/>
... [9 more line(s); run it to see the whole thing]
```

**Shaped by:** `--cochange-recur`, `--cochange-groups`, `--since`, `--json`

### `--cochange-recur=K`

**Answers:** (with --cochange) report only pairs whose co-change RECURS in K or more of the mined window's sub-windows, so a one-off refactor sprint stops reading like an eighteen-month structural defect (Clio, ICSE 2011).

Every row carries recur= with or without this flag; the header publishes sub_windows= (the denominator) and min_recur= when the filter is on

### `--cochange-groups`

**Answers:** (with --cochange, repo-wide only) emit Modularity Violation GROUPS instead of pairs: "X co-changes with {A,B,C}, none of which it depends on" is ONE row that names the file to fix (Mo/Cai/Kazman, IEEE TSE 2019).

A greedy cover, disclosed as greedy — set cover is NP-hard, so the group count is an upper bound on the minimum, not the minimum

### `--since=REV|DATE`

**Answers:** scope --hotspots/--cochange/--rank-by=churn to commits after this point: a revision (HEAD~20, a tag/sha — deterministic) or a git approxidate ("2 weeks ago" — wall-clock-relative).

e.g. --hotspots --since="1 week ago" ranks by RECENT churn (the regression lens). Absent ⇒ each verb's OWN bounded default window, NOT all history: --hotspots 12 months, --rank-by=churn 18 months, --cochange 18 months. All three STAMP the window they used (window="12mo"/"18mo", or the resolved --since value) — --cochange gained its window= in the same round that gave it sub_windows=, and this clause used to say it had none. An UNRESOLVABLE value is refused by --hotspots (exit 1 — its window is part of the measurement) and degrades to the verb's own default window elsewhere

**Try it**

_Hotspots scoped to RECENT churn (the regression lens)._

```
$ ./build/ripwire . --hotspots --since="2 weeks ago"
<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=2 weeks ago). churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. unranked_no_complexity= is a file with commits but no function or method to score (a pure declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the join could not match), which scores zero for a reason that is not about the file. Treat it as an upper bound on quietness, not a measure of it. raise the default cap with limit=N (offset=M pages) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<hotspots window="2 weeks ago" files="850" ranked="221" unranked_no_churn="0" unranked_no_complexity="629" shown="40" capped="1" at="bc09d0260+dirty">
<f p="./src/main.cpp" churn="8" ccx="3311" score="26488" top="main" top_ccx="376" top_l="8007"/>
<f p="./src/ingest.cpp" churn="6" ccx="2713" score="16278" top="ingest" top_ccx="702" top_l="3856"/>
<f p="./src/graph.h" churn="7" ccx="1424" score="9968" top="buildGraph" top_ccx="712" top_l="379"/>
... [25 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- Absent ⇒ each verb's OWN bounded default window, NOT all history: --hotspots 12 months, --rank-by=churn 18 months, --cochange 18 months.
- An UNRESOLVABLE value is refused by --hotspots (exit 1 — its window is part of the measurement) and degrades to the verb's own default window elsewhere

### `--arch=FILE`

**Answers:** enforce layering rules (exit 2 on violation);

the Martin Ca/Ce/I/A/D block it emits is a design heuristic, not independently outcome-validated (never gates). propagation_cost's N is dependency-capable files only, same denominator as --deps <health>. Layer substrings and regex path-rules match the ROOT-RELATIVE path (src/core/x.cpp), not the spelling you passed, so a rules file means the same thing in every checkout --arch=FILE --baseline     write .ripwire_arch_baseline (accept current debt as baseline), exit 0 --arch=FILE --baseline-update  merge current violations into baseline (accept new debt), exit 0

**Try it**

_Enforce layering rules (exit 2 on violation) — run against the repo's own test fixture rules._

```
$ ./build/ripwire . --arch=test/archfix/rules.txt
<!-- ripwire arch: layering fitness function — edges that violate your declared rules (layer rules and regex path-rules). exit=2 if any NEW (un-baselined) violation. <metrics> = descriptive Martin Ca/Ce/I/A/D + reachability, never gates. Rules — layer substrings and regex path-rules alike — are matched against each file's ROOT-RELATIVE path (src/core/x.cpp), never the absolute or ./-prefixed spelling shown in from=/to=, so a rule means the same thing whatever directory the tree was checked out into. -->
<arch layers="2" rules="1" pathRules="0" violations="0" baselined="0" new_violations="0">
<metrics modules="199" typed_modules="76" zone_pain="60" zone_useless="1" zone_ok="15" zone_na="123" propagation_cost="0.011" note="Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — directory-level estimate from na … [line truncated: 408 more bytes on this line]
<m path="." ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench" ca="0" ce="1" types="5" abstract="2" I="1.00" A="0.40" D="0.40" zone="ok" reachable="1"/>
<m path="./bench/agentloop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/cppbench" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/cppbench/results" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
... [23 more line(s); run it to see the whole thing]
```

**Shaped by:** `--deps`

**Caveats (stated by the binary):**

- the Martin Ca/Ce/I/A/D block it emits is a design heuristic, not independently outcome-validated (never gates).

### `--lint`

**Answers:** built-in AST checks (c-cast, goto, unsafe-c-fn, naming-*, ...).

naming-uninformative is ONE-SIDED by design: it fires only when a name's subtokens are ALL corpus-common (BM25 idf over the identifier-name corpus) AND its body clears a size floor — a high-idf (distinctive) name is never penalised, unlike the withdrawn name<->body rule

**Try it**

_Built-in AST checks (c-cast, goto, unsafe-c-fn, ...)._

```
$ ./build/ripwire . --lint
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one rule is a floor. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages). -->
<lint findings="1118" findings_capped="1">
<rule name="c-style-cast" count="241"/>
<rule name="goto" count="2"/>
<rule name="do-while" count="1"/>
<rule name="unsafe-c-fn" count="0"/>
<rule name="weak-crypto" count="0"/>
<rule name="redundant-parens" count="0"/>
<rule name="suspicious-semicolon" count="0"/>
<rule name="typedef-over-using" count="12"/>
<rule name="magic-number" count="612" capped="1"/>
<rule name="empty-catch" count="1"/>
<rule name="self-assign" count="4" capped="1"/>
<rule name="large-function" count="110"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--expand`, `--naming-calibration`, `--naming-locals`, `--lint-rules`, `--json`

**Caveats (stated by the binary):**

- naming-uninformative is ONE-SIDED by design: it fires only when a name's subtokens are ALL corpus-common (BM25 idf over the identifier-name corpus) AND its body clears a size floor — a high-idf (distinctive) name is never penalised, unlike the withdrawn name<->body rule

### `--lint-rules=DIR`

**Answers:** load user lint rules (YAML, ast-grep style) from DIR — runs with, or instead of, --lint

**Try it**

_User lint rules (YAML, ast-grep style) from a directory._

```
$ ./build/ripwire . --lint-rules=test/lintrulesfix/rules
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one rule is a floor. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages). -->
<lint findings="5">
<rule name="broken-query" sev="error" count="0"/>
<rule name="no-printf" sev="warn" count="5"/>
<f rule="no-printf" sev="warn" p="./test/coplintfix/position.cpp:41" in="demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="./test/coplintfix/safe.cpp:15" in="safe_demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="./test/coplintfix/safe.cpp:27" in="safe_demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="./test/lintrulesfix/sample.cpp:8" in="greet">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="./test/usesfix/store.cpp:24" in="run">use LOG() instead of printf</f>
</lint>
```

### `--communities`

**Answers:** cluster the call graph into cohesive modules (each row's id= drills down below;

drill= names the verb)

**Try it**

_Cluster the call graph into cohesive modules._

```
$ ./build/ripwire . --communities
<!-- ripwire communities: cohesive call-graph modules (Louvain); bridge=cross-module edges; isolated=call-graph-edgeless symbols; drill= names the verb that takes an id= from a row below. On each module row size= is its TRUE member count while shown=/capped= describe the member list printed here: this listing is fixed at the 5 top-ranked members and is NOT widened by limit=/offset= (those page the MODULE rows). capped=1 means members were dropped; drill= names the verb that pages the full member list of one module. raise the default cap with limit=N (offset=M pages). -->
<communities drill="--community=ID" modules="626" shown_modules="30" modules_capped="1" bridges="1196" shown_bridges="12" bridges_capped="1" isolated="3376" isolated_decl="585" isolated_header="546" isolated_source="1382" isolated_doc="863" connected_singletons="0" symbols="6432">
<community id="202" size="335" dir="./src" label="./src::isTestPath@filter.h:32:972" shown="5" capped="1">
<member t="method" n="push_back" p="./src/svector.h:76"/>
<member t="method" n="end" p="./src/svector.h:80"/>
<member t="method" n="end" p="./src/svector.h:82"/>
<member t="method" n="find" p="./src/ingest.cpp:4949"/>
<member t="method" n="reserve" p="./src/svector.h:73"/>
</community>
<community id="1066" size="239" dir="./src" label="./src::canonicalId@resolve.h:926:55347" shown="5" capped="1">
<member t="method" n="empty" p="./src/scipoverlay.h:81"/>
<member t="method" n="empty" p="./src/notes.h:337"/>
<member t="fn" n="utf8SeqLen" p="./src/jsonesc.h:51"/>
<member t="fn" n="cappedEcho" p="./src/mcprefusal.h:290"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--community`, `--json`

### `--community=ID`

**Answers:** ONE module from that partition: its FULL ranked member list (40 rows by default, raise with --limit, page with --offset) plus its bridge edges to every other module it touches.

ID is an id= from --communities/--zoom; ids live in 0..partition-1 (the child's partition= — the full label space, isolated singletons included), so a single-member module is a legal drill-down and reports size="1". modules= counts the non-isolated communities (same number as the parent's modules=). An id outside 0..partition-1 REFUSES, naming the valid range and the nearest legal id -- a bad id is a typo, not an empty module

**Try it**

_Drill into ONE call-graph community by id — the drill= the --communities output itself advertises._

```
$ ./build/ripwire . --community=0
<!-- ripwire community: ONE module from the communities/zoom partition — its ranked members and its bridge edges to other modules. size= is the module's TRUE member count; shown=/capped= are this page. partition= is the FULL label space (every id 0..partition-1, incl. isolated singletons) — the range the id= argument ranges over; modules= counts the NON-isolated communities (size>=2), the SAME predicate the communities-listing verb's modules= uses, so parent and child agree. -->
<community id="0" size="1" dir="." label=".::AGENTS@AGENTS.md:1:0" bridges="0" shown_bridges="0" bridges_capped="0" partition="4002" modules="626" shown="1" capped="0">
<member t="sec" n="AGENTS" p="./AGENTS.md:1"/>
</community>
```

**Shaped by:** `--json`

**Caveats (stated by the binary):**

- ONE module from that partition: its FULL ranked member list (40 rows by default, raise with --limit, page with --offset) plus its bridge edges to every other module it touches.
- An id outside 0..partition-1 REFUSES, naming the valid range and the nearest legal id -- a bad id is a typo, not an empty module

### `--zoom[=depth]`

**Answers:** NESTED module hierarchy (multi-level Louvain) + cross-module bridges;

--zoom --mermaid = nested diagram

**Try it**

_Nested module hierarchy (multi-level Louvain) + cross-module bridges._

```
$ ./build/ripwire . --zoom
<!-- ripwire zoom: NESTED module hierarchy (multi-level Louvain); indent = one level deeper; module = dominant-dir(symbol-count); leaf lists top-ranked symbols; bridge = cross-top-module call traffic. symbols= is the whole corpus; isolated= is the symbols in NO top-level module (a group of one — the same rule that makes top_modules= count only groups of 2 or more), and they reconcile exactly: symbols= equals isolated= plus the sum of the TOP-LEVEL size= values, every one of them, including any this page did not print. On a level-0 module size= is its true member count and shown=/capped= describe the member list printed here, which is fixed at the 5 top-ranked members and is not widened by limit=/offset= (those page the TOP-LEVEL modules); the community drill verb pages one module's full member list by its level-0 id. A module above level 0 lists every child module, so it carries no shown=/capped= pair. -->
<zoom levels="4" top_modules="228" symbols="6432" isolated="3376">
<module level="3" id="155" size="1865" dir="./src">
<module level="2" id="180" size="1568" dir="./src">
<module level="1" id="185" size="1148" dir="./src">
<module level="0" id="202" size="335" dir="./src" shown="5" capped="1">
<member t="method" n="push_back" p="./src/svector.h:76"/>
<member t="method" n="end" p="./src/svector.h:80"/>
<member t="method" n="end" p="./src/svector.h:82"/>
<member t="method" n="find" p="./src/ingest.cpp:4949"/>
<member t="method" n="reserve" p="./src/svector.h:73"/>
</module>
<module level="0" id="1066" size="239" dir="./src" shown="5" capped="1">
... [18 more line(s); run it to see the whole thing]
```

**Shaped by:** `--community`, `--json`

### `--report`

**Answers:** architecture summary (modules, god-files, cycles) as markdown

**Try it**

_Architecture summary (modules, god-files, cycles) as markdown._

```
$ ./build/ripwire . --report
<!-- ripwire markdown: no run of 4-or-more backticks in this output — safe to embed inside a wider fence -->

# ripwire architecture report

850 files · 6432 symbols · 8737 edges · 626 modules (3376 call-graph isolated)

Call-graph isolate provenance: 585 declaration, 546 header, 1382 source, 863 document; 0 connected Louvain singletons

## Modules (call-graph clusters; showing 12 of 626)
- **./src::isTestPath@filter.h:32:972** — 335 symbols
- **./src::canonicalId@resolve.h:926:55347** — 239 symbols
- **./src::escapeXml@serialize.h:112:7105** — 64 symbols
- **./src::str@ingest.cpp:887:55797** — 53 symbols
- **./src/infra::leaf_at@dynamic_map.hpp:372:18374** — 33 symbols
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--json`

### `--seams`

**Answers:** cross-module call seams no test reaches (untested integration seams)

**Try it**

_Cross-module call seams no test reaches. NOW carries seam_pairs/shown/capped._

```
$ ./build/ripwire . --seams
<!-- ripwire seams: cross-directory call edges NO test reaches (untested integration seams; a fact, not a mandate). module = parent dir; seam = caller-dir -> callee-dir, spelled from= and to=. Each seam pages its own edge rows with shown=/capped=; an edge names caller= at site p= calling callee= at site cp=. UNIT: untested= here counts cross-directory call EDGES. The test gate verb spells untested= over impacted SYMBOLS and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. raise the default cap with limit=N (offset=M pages) -->
<seams modules="199" bridges="410" untested="268" test_files="631" seam_pairs="22" shown="20" capped="1">
<seam from="./src" to="./src/infra" untested="172" shown="5" capped="1">
<edge caller="ensureFileLoaded" p="./src/layout.h:988" callee="clear" cp="./src/infra/dynamic_map.hpp:1265"/>
<edge caller="skipInert" p="./src/layout.h:179" callee="min" cp="./src/infra/platform.h:95"/>
<edge caller="getIndex" p="./src/mcpindex.h:734" callee="clear" cp="./src/infra/dynamic_map.hpp:1265"/>
<edge caller="readByteSafeLine" p="./src/stdinline.h:44" callee="clear" cp="./src/infra/dynamic_map.hpp:1265"/>
<edge caller="selectorFaultClause" p="./src/selectorrefuse.h:81" callee="min" cp="./src/infra/platform.h:95"/>
</seam>
<seam from="./bench" to="./src" untested="22" shown="5" capped="1">
<edge caller="runSorter" p="./bench/bench_sort_large.cpp:140" callee="push_back" cp="./src/svector.h:76"/>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--json`

### `--mermaid`

**Answers:** module (directory) dependency graph as a Mermaid diagram (paste/render)

**Try it**

_Module (directory) dependency graph as a Mermaid diagram._

```
$ ./build/ripwire . --mermaid
%% ripwire --mermaid: module (directory) dependency graph — node = dir (symbol count), edge = inter-module calls (>= 3). Render at mermaid.live.
flowchart LR
  subgraph sg0 ["src"]
    n49["src<br/>2265"]
    n50["src/infra<br/>291"]
  end
  subgraph sg1 ["test"]
    n51["test<br/>1504"]
    n133["test/legofix<br/>60"]
    n70["test/callformfix/cpp<br/>36"]
    n132["test/layoutfix<br/>32"]
    n177["test/rustqualfix/src<br/>27"]
    n92["test/cppqualfix<br/>23"]
    n76["test/callformfix/java<br/>22"]
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--zoom`, `--with-graph`, `--json`

### `--owners[=SYM]`

**Answers:** bus-factor: recency-weighted author ownership per file;

bf=1 = one person holds >80% of weighted commits. Files with authors=1 (deterministically bf=1 share=1.00) fold into ONE <uniform files="N"/> summary row instead of N identical rows; --detail=N restores the full listing

**Try it**

_Bus-factor: recency-weighted author ownership per file._

```
$ ./build/ripwire . --owners
<!-- ripwire owners: recency-weighted author ownership (half-life=6mo). bf=1 = one person holds >80% of weighted commits (bus-factor risk); authors=1 files fold into <uniform/> below; pass detail=1 for the full per-file listing. files= means two different things by DEPTH here and is deliberately not renamed: on the ROOT it is how many files were ANALYSED; on the <uniform/> fold it is how many of them collapsed into that one row. With a SYM, of= echoes it and defs= is how many DEFINITIONS that name has: this report covers the file holding the FIRST of them (lowest node id, the same pick around and lego make), so defs= above 1 means the other definitions' files were NOT analysed. Qualify with file:name to choose one -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<owners files="850" at="bc09d0260+dirty">
<uniform authors="1" bf="1" share="1.00" files="358"/>
<f p="./SECURITY.md" authors="2" bf="0" top="<author>" share="0.50"/>
<f p="./THIRD_PARTY.md" authors="2" bf="0" top="<author>" share="0.67"/>
<f p="./bench/ANSWERQUALITY.md" authors="2" bf="0" top="<author>" share="0.75"/>
<f p="./bench/BENCHMARK.md" authors="2" bf="0" top="<author>" share="0.50"/>
<f p="./bench/PROFILE.md" authors="2" bf="0" top="<author>" share="0.67"/>
<f p="./bench/agentloop/README.md" authors="2" bf="0" top="<author>" share="0.67"/>
<f p="./bench/agentloop/analyze.py" authors="2" bf="0" top="<author>" share="0.50"/>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--json`

### `--dead-code[=DIR]`

**Answers:** high-confidence internal source functions with no caller in the indexed tree;

=DIR scopes to whole path components (dir or filename) and REFUSES a filter that names nothing indexed. A LEADING ./ anchors DIR at the repo ROOT (=./src matches only the top-level src/ subtree); a bare name (=src) matches that component ANYWHERE in the tree, including nested (test/fixture/src/…)

**Try it**

_High-confidence internal functions with no caller. NOTE the filter is a path-COMPONENT match: 'src' matches any .../src/... segment; use ./src to pin the root directory._

```
$ ./build/ripwire . --dead-code=src
<!-- ripwire dead-code: high-confidence source functions with internal linkage and no caller in the indexed tree. A bare-name filter matches by path COMPONENT: filter="src" keeps any path with a src segment at any depth (test/x/src/y.cpp included); anchor with ./ (filter="./src") to pin the root-level directory only. Graph evidence is local to the indexed tree; verify before deleting -->
<dead-code count="1" confidence="high" evidence="internal-linkage+zero-callers" filter="src">
<d n="unused_helper" t="fn" p="./test/archmetricsfix/src/orphan/util.cpp" l="1"/>
</dead-code>
```

**Shaped by:** `--json`

**Caveats (stated by the binary):**

- =DIR scopes to whole path components (dir or filename) and REFUSES a filter that names nothing indexed.

### `--quality-baseline`

**Answers:** snapshot ccx/clones/dead-code to .ripwire_quality_baseline (run BEFORE a change)

**Shaped by:** `--quality-delta`

### `--quality-delta`

**Answers:** agent self-check before a PR (pair with --test-gate): report ONLY what a change made worse vs the baseline (10 kinds: complexity/verbosity/nesting/params/dup/dead/api-surface + error-masking/short-horizon-churn/reuse-decline);

every finding is classified by ORIGIN: a symbol that EXISTED at the baseline and got worse (preexisting-worse="N", no attribute on the row) vs one that exists only because the code is NEW (new-symbol="N", origin="new-symbol" on the row). A small numeric delta is additionally sev="minor". EXIT 2 ONLY on preexisting-worse AND major AND unacked — the gating="N" header count. New-symbol rows are still PRINTED (they are the debt you are adding — read them), they just never gate; exit 0 means "nothing that already existed got worse", not "clean". Clone kinds classify by member set (new-symbol only if EVERY member is new); short-horizon-churn is preexisting by construction. LIMIT: origin is canonId (path::scope::name) identity, so a RENAMED/MOVED symbol reads as new and a regression carried in with the move will not gate. Test-fixture dirs + doc sections are exempt from dead-code/churn; churn needs COMMITTED thrash evidence (rewritten across recent commits AND again by this diff), never the current edit alone WHICH FLOOR IT COMPARES AGAINST, and a side effect: the sidecar is honored only when the sha it was pinned at EQUALS the current git HEAD (strict equality — an ancestor commit describes a DIFFERENT tree, so everything committed since would read as your regression). A sidecar pinned anywhere else is STALE: this verb then DELETES it from your working tree (self-heal, so the next run does not rediscover the dead pin) and auto-compares the working tree vs git HEAD instead. Re-pin with --quality-baseline. The read-only MCP quality_delta verb applies the SAME staleness test but never deletes. Which floor was actually used is on every report as baseline=: sidecar | git-HEAD | git-HEAD (stale sidecar removed) | git-HEAD (stale sidecar ignored) — the last two say a stale sidecar existed, and 'removed' means the file is gone. A non-git root has no HEAD to fall back to, so its sidecar is always honored; without one there, the verb exits 1.

**Try it**

_Recorded against a DIRTY tree, so any row below is a real regression in the working copy. The sandbox section below shows the same gating shape on a known, deliberate edit._

```
$ ./build/ripwire . --quality-delta
... [4 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--test-gate`, `--dmm`, `--json`

**Caveats (stated by the binary):**

- New-symbol rows are still PRINTED (they are the debt you are adding — read them), they just never gate;
- LIMIT: origin is canonId (path::scope::name) identity, so a RENAMED/MOVED symbol reads as new and a regression carried in with the move will not gate.
- The read-only MCP quality_delta verb applies the SAME staleness test but never deletes.

### `--dmm[=REV|A..B]`

**Answers:** the DELTA MAINTAINABILITY MODEL scalar: ONE comparable number in [0,1] for a change, so quality becomes TRENDABLE across commits instead of a per-kind list (di Biase, Rastogi, Bruntink and van Deursen, TechDebt 2019;

thresholds and arithmetic from PyDriller's deltamaintainability reference implementation). Bare = the WORKING TREE vs git HEAD (what --quality-delta compares); =REV = that commit vs its FIRST PARENT (the per-commit scalar); =A..B = tree B vs tree A. A UNIT is a function/method definition with a body; its VOLUME is its line span. Per property a unit is LOW risk iff size: loc<=15, complexity: cyclomatic<=5, interfacing: params<=2. good = low-risk volume ADDED plus high-risk volume REMOVED; bad = low-risk REMOVED plus high-risk ADDED; dmm = good/(good+bad). So DELETING a god function scores 1.000 and GROWING one scores 0.000. The three sub-scores (size/complexity/interfacing) are emitted alongside the combined one because they are separately actionable; the combined one POOLS them (summed good over summed good+bad) and is labelled combine="pooled", since the paper publishes the three separately and no aggregate. IT IS A DELTA, NEVER A LEVEL: a unit you edit without changing its size, complexity or parameter count sits in the same bin with the same volume on both sides and contributes NOTHING. Touching bad code is not punished, deliberately, because a gate that punishes it is a gate people route around. dmm="UNAVAILABLE" means good+bad was 0 (a rename, a literal edit, a comment reflow): the change is outside what the model measures. That is NEVER to be read as 1.000 or 0.000, and reason= says which case it was. Same token per property. VOLUME IS PHYSICAL LINE SPAN (size_metric="physical-loc"), where the reference implementation uses non-comment non-blank lines, so a heavily commented unit crosses the size threshold here earlier. NO THRESHOLD, NO VERDICT, ALWAYS EXIT 0.

**Caveats (stated by the binary):**

- IT IS A DELTA, NEVER A LEVEL: a unit you edit without changing its size, complexity or parameter count sits in the same bin with the same volume on both sides and contributes NOTHING.
- That is NEVER to be read as 1.000 or 0.000, and reason= says which case it was.

### `--quality-ack[=REASON]`

**Answers:** accept the current findings into .ripwire_quality_acks (per-finding ratchet): re-runs suppress them honestly (acked="N") until one WORSENS past its acked size --ack-only=SUBSTR[,SUBSTR] (with --quality-ack) ack only SOME findings — those whose KIND, canonical id, or FACET contains one of these;

the pseudo-token 'gating' selects exactly what would exit 2. Bare --quality-ack accepts the WHOLE report, so accepting one deliberate change silently accepts the rest — how a ratchet turns into a rubber stamp. Prefer the facet: --ack-only=contract-change acks the deliberate arity changes WITHOUT the never-gating api-surface new-symbol rows. Matching nothing refuses (exit 1) rather than falling back to acking everything. Whatever you leave unacked stays visible.

**Try it**

_NEW FLAG: --ack-only matching nothing REFUSES rather than falling back to acking everything._

```
$ ./build/ripwire . --quality-delta --quality-ack --ack-only=zzznope
(empty)
```

**Caveats (stated by the binary):**

- Prefer the facet: --ack-only=contract-change acks the deliberate arity changes WITHOUT the never-gating api-surface new-symbol rows.
- Matching nothing refuses (exit 1) rather than falling back to acking everything.

### `--edit-check=SYM`

**Answers:** fast per-symbol post-edit contract check: SYM's param count + publicness NOW vs git HEAD (unchanged/new-symbol/contract-change with was/now), plus its 1-hop callers with any call-site provably incompatible with the NEW arity flagged.

A contract is PER DEFINITION, so a SYM matching several definition sites REFUSES (exit 1) and lists the file:name spellings that pick one — unlike --callers/--uses, this verb may not union overloads and disclose defs=.

**Try it**

_Fast per-symbol post-edit contract check vs git HEAD — recorded against a DIRTY tree, so the verdict describes the working copy, not HEAD alone._

```
$ ./build/ripwire . --edit-check=rankGraphTeleport
... [9 more line(s); run it to see the whole thing]
```

**Shaped by:** `--impact`

**Caveats (stated by the binary):**

- A contract is PER DEFINITION, so a SYM matching several definition sites REFUSES (exit 1) and lists the file:name spellings that pick one — unlike --callers/--uses, this verb may not union overloads and disclose defs=.

### `--pr-context[=BASEREF]`

**Answers:** no-LLM review-evidence bundle for the diff (working-tree, or vs BASEREF): per changed file, its symbols + callers + blast radius + affected tests + co-change partners + owners.

With --max-tokens=N the bundle degrades to fit: per-file structural counts survive for ALL changed files, the deep detail (caller/co-change lists, per-symbol rows) trims deepest-first, and truncated= names what was dropped (est_tokens= reports the fit). ANCHORING: the BASEREF form diffs against merge-base(BASEREF,HEAD), never BASEREF's tip — "what did THIS work change since it forked", not "how do the two trees differ today". base_moved= counts the paths BASEREF moved since the fork that this work never touched (excluded, not silently); anchor="ref-tip-two-dot" = no merge-base (unrelated history). direction= always names the SIDE you are reading, and a no-ref-work row fires when BASEREF's tip IS the merge base -- it carries no divergent work, so every row is HEAD's. --merge-scout=REF[,REF...] read-only cross-branch overlap: for each REF, the symbols it changed vs its merge-base with HEAD (git-archive TEMP copies — never checked out, never mutates a ref); the dirty working tree joins as an implicit extra arm. Pairwise: a changed symbol on TWO arms is a same-symbol conflict, two arms touching different symbols in the same file is a textual risk; <landing order=...> is the fewest-conflicts-first greedy land order (ties: ref name asc). An unresolvable REF refuses loudly (exit 1, names the ref) before any archive work. ANCHORING: every arm is diffed against its OWN merge-base with HEAD, never against live HEAD — a file an arm never opened can never show up because the live line moved. head_conflicts= is what that anchor hides, kept as its own row class: symbols this arm changed that the LIVE LINE also changed since the arm forked (HEAD is not an arm, so no pairwise comparison can see it). Single-root only. --plan-lanes=N --task=GOAL PRE-HOC lane plan: BEFORE a line is written, if this task is split across N isolated worktrees (N=2..16), which lanes would COLLIDE and in what order should they land. Where --merge-scout says "these branches already conflict", this says "these lanes WOULD conflict if assigned this way" — no ref to resolve, no archive, no re-ingest. JSON on stdout, always (redirect it: > .ripwire_lanes.json); ripwire writes no file. Exit 0 whenever a plan was produced, INCLUDING when conflicts are predicted (conflicts are data, and the landing order exists to handle them); exit 1 only for refusals. A claim keys on path+scope+name, never on id= (id degrades to a bare NAME when no scope was captured, so free functions in different files would collide); id= is carried per row for addressability, null when it would be bare, with id_addressable saying so. Three separate pair classes: conflicts[] (same claim key on both lanes — git will fight), same_file_risk[] (different keys, same file, aggregated per file), contract_touch[] (one lane's claim sits in another's blast radius — an adaptation, NOT a merge conflict). The conflict test runs on CLAIMS, never on blast radii. warnings[] carries every honest limit in band with a stable code. Single-root only. AUTO-CARVE SPLITS THE RANKED SURFACE, NOT YOUR SENTENCE: if your task has enumerable parts, use --brief and write one line per part. --plan-lanes --brief=FILE  the explicit form of the above: one non-blank line per lane, N = the line count. Each line is ranked on its own — no community carve, no bin packing — so the lane boundaries are the ones you wrote. This is the mode whose precision is defensible; prefer it when you can. Lane isolation is a QUALITY argument, not a speed one (CAID, arXiv 2603.21489: 63.3% vs 55.5% shared, largest gains on weaker lane models — and wall clock got WORSE).

**Try it**

_No-LLM review-evidence bundle for the working-tree diff — recorded against a DIRTY tree, so it is populated rather than empty._

```
$ ./build/ripwire . --pr-context
... [31 more line(s); run it to see the whole thing]
```

**Shaped by:** `--test-gate`, `--from-trace`, `--map-diff`, `--index-out`

**Caveats (stated by the binary):**

- With --max-tokens=N the bundle degrades to fit: per-file structural counts survive for ALL changed files, the deep detail (caller/co-change lists, per-symbol rows) trims deepest-first, and truncated= names what was dropped (est_tokens= reports the fit).
- ANCHORING: the BASEREF form diffs against merge-base(BASEREF,HEAD), never BASEREF's tip — "what did THIS work change since it forked", not "how do the two trees differ today".
- base_moved= counts the paths BASEREF moved since the fork that this work never touched (excluded, not silently);

### `--stray-content[=SUBSTR]`

**Answers:** "where does this content live?" across ALL branches — the question `git cherry` cannot answer.

Per local ref (SUBSTR filters ref names): the lines its own divergent work AUTHORED vs its merge-base with HEAD that the live line does NOT have, and a verdict. v="unmerged" = genuinely absent; v="superseded" = the live line removed the SAME base code this ref removed, i.e. it re-implemented the work (git cherry still calls that commit unmerged, forever); v="merged" refs are omitted. Every row shows its raw del=/redone=/sim= evidence, so a verdict is auditable, not a black box. v="unknown" (ok="0") = the ref has NO merge-base with HEAD, so it could not be analysed at all — a shallow clone (the actions/checkout DEFAULT) puts every ref here. It is NOT a claim the work is merged: it is the absence of an answer, counted in its own unknown= bucket so unmerged+superseded+merged+unknown always reconciles with refs=, and surfaced by --plan as an <undetermined> row rather than silently dropped. LIMITS: line-granular, not semantic — a rewrite that shares no deleted base line reads as unmerged; binary/oversized blobs are reported diffable="0" with no counts. Read-only (cat-file/diff/ls-tree); single-root only.

**Try it**

_Which lane-* refs still hold divergent authored work vs HEAD, with verdicts._

```
$ ./build/ripwire . --stray-content=lane
... [3 more line(s); run it to see the whole thing]
```

**Shaped by:** `--plan`, `--abi`, `--whereis`, `--json`, `--eval-stray`

**Caveats (stated by the binary):**

- "where does this content live?" across ALL branches — the question `git cherry` cannot answer.
- Every row shows its raw del=/redone=/sim= evidence, so a verdict is auditable, not a black box.
- It is NOT a claim the work is merged: it is the absence of an answer, counted in its own unknown= bucket so unmerged+superseded+merged+unknown always reconciles with refs=, and surfaced by --plan as an <undetermined> row rather than silently dropped.

### `--plan`

**Answers:** (with --stray-content) "of all my branches, which still hold REAL work, and in what order should I land them?" Selects the refs --stray-content calls v="unmerged", DROPS the v="superseded" ones (landing them would re-do work the live line already did — the exact waste --stray-content exists to catch), and feeds the survivors to --merge-scout's existing pairwise-conflict + fewest-conflicts-first landing-order machinery — composition only, neither verb's logic is reimplemented.

<ref scouted="0"> is unmerged work NOT fed to merge-scout THIS run (a cost bound, not a verdict); <excluded> names the superseded drops and why. COST: --stray-content is a cheap per- blob sweep, but --merge-scout is per-ARM (git-archive + full ingest of each ref's tree) — measured 27s for 9 unmerged refs on a 35-branch real C++ repo (~3s/ref). kMaxPlanScout (12) bounds it to the top-N unmerged refs BY STRAY SIZE; --detail lifts the bound to scout everything. This is an EXPLICIT opt-in "before you land" call, not a per- question one — the default map's ~0.10s path is untouched. Read-only; single-root only.

**Try it**

_Select the genuinely-unmerged refs and feed them to merge-scout for a landing order._

```
$ ./build/ripwire . --stray-content=r27 --plan
<!-- ripwire landing-plan: stray-content's cheap per-blob sweep composed with merge-scout's per-arm overlap oracle — of every local branch, which still hold REAL work (v="unmerged"), which were already re-implemented on the live line (v="superseded", EXCLUDED below — landing them re-does work that is already done) or are already merged (omitted entirely, counted in merged= on the root element), and the fewest-conflicts-first order to land what remains. scouted="0" on an unmerged ref means it was NOT fed to merge-scout this run (the cost bound, not a verdict) — it is still real, unscouted work; bounded= on the root element counts them and detail lifts the bound. merge-scout is the EXPENSIVE step here (git-archive + full ingest per arm) — stray-content's own sweep is the cheap one. An undetermined row is a ref that could NOT be analysed at all (no merge base with HEAD, which on a SHALLOW clone is every ref): it is neither scouted nor excluded nor merged, because nothing was measured — treat it as unfinished business and deepen the clone, never as a clean branch. Read-only throughout: no checkout, no ref write, no working-tree mutation. The root carries BOTH head= and at= and they are the same commit: head= is the bare 9 hex chars this verb has always printed, at= is the tool wide anchor and is head= plus a "+dirty" suffix when the working tree is not clean. Prefer at= (it is the one spelling every other repo reading verb uses, and the only one that tells you whether uncommitted work was in scope); head= is kept for callers already keyed to it. -->
... [2 more line(s); run it to see the whole thing]
```

**Shaped by:** `--pr-context`, `--stray-content`

**Caveats (stated by the binary):**

- <ref scouted="0"> is unmerged work NOT fed to merge-scout THIS run (a cost bound, not a verdict);
- This is an EXPLICIT opt-in "before you land" call, not a per- question one — the default map's ~0.10s path is untouched.

### `--abi`

**Answers:** (with --stray-content) the CROSS-BRANCH ABI-BREAK gate `--layout` and `--stray-content` each miss alone: a branch that adds one field to a dual-compile uniform struct merges textually clean and reads as a harmless "+1 field" to a line-granular diff.

SCOPE is what each ref AUTHORED — the paths `git diff base..tip` reports against its own MERGE BASE, never `diff HEAD..tip`. A file the branch never opened cannot be a break the branch introduced, and on a long-lived shared tree that one distinction is nearly all the noise: measured on a 35-branch C++ repo, 487 drift rows fell to 4 (the rest were the live line's own evolution reflected back at the reader). For each authored path this runs --layout's OWN field-offset arithmetic lexically on that ref's git blob (never indexed) and compares it against HEAD's computed fields. LISTED by default: kind="drift" (the byte contract differs — the only kind that exits 2), kind="unknown" (a ref-side copy this module could not model; its caveats ride along in ref_caveat and it is NEVER reported as unchanged), kind="absent" (the ref does not define the struct at that path at all). EXCLUDED by default, each on its own header counter — add --detail=N to print them: kind="rename" (identical slots and field TYPES under different field NAMES: every byte stayed where it was, so it is a source change, not a byte-contract one — note a same-type field REORDER is lexically indistinguishable from a rename and lands here too), kind="spelling"/"stub" (--layout's own harmless cases), and kind="head-moved" (the ref's copy equals its own merge-base copy, so the LIVE LINE changed, not the branch). head_only= counts candidate sites on paths only the live line touched; unmodelable= counts sites skipped because HEAD's own copy carries no baseline; rows=/ shown=/dropped=/excluded= reconcile the body against the sweep (capped="0|1" is the tool-wide truncation BIT; dropped= is the count). Nothing is dropped without a number. Structs that match are omitted (report only differences); a ref with no rows at all counts into quiet=, a ref whose every row is an excluded kind counts into excluded_refs= (and prints under --detail=N), and broken_refs= counts REFS (not rows). Rows are ranked by SIZE DELTA so the biggest contract break leads, capped at 12 per ref with an explicit <more structs="N"/>; --detail=N lifts the cap. LIMITS: HEAD's own side is the WORKING TREE's --layout answer, not a re-fetched git blob at HEAD's commit (the same scope --layout itself claims); a nested field's OWN type resolves through HEAD's copy even when the ref also changed it; the ref-side locator is index-free and file-scope (one namespace deep) only, so a struct nested in a class or an extern "C" block reads absent rather than compared; a HEAD-side struct --layout itself cannot model at all (pragma pack, bitfields, ...) has no baseline and is counted in unmodelable=, not compared; the authorship anchor is per PATH, so a branch changing struct S in one file while the live line changes S's mirror in another is a merge hazard only `--layout=S` on the merged result can see. Read-only; single-root only.

**Try it**

_Cross-branch ABI-break gate: struct byte-contract drift on each ref's AUTHORED paths._

```
$ ./build/ripwire . --stray-content=lane --abi
... [3 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- SCOPE is what each ref AUTHORED — the paths `git diff base..tip` reports against its own MERGE BASE, never `diff HEAD..tip`.
- A file the branch never opened cannot be a break the branch introduced, and on a long-lived shared tree that one distinction is nearly all the noise: measured on a 35-branch C++ repo, 487 drift rows fell to 4 (the rest were the live line's own evolution reflected back at the reader).
- For each authored path this runs --layout's OWN field-offset arithmetic lexically on that ref's git blob (never indexed) and compares it against HEAD's computed fields.

### `--whereis=SYM`

**Answers:** which REF's tree defines or mentions SYM — HEAD first, then every local branch, with on-head="0" naming the case the verb exists for: content that lives only on a branch.

Each distinct blob is read ONCE (content-addressed), so N branches cost ~one tree. kind="def" on a HEAD row is the PARSED index's answer (head_labels="index"); on a REF row it is a LEXICAL heuristic — ref blobs are raw text, never ingested, so a doc quoting a signature still reads as a definition. head_labels="lexical" ⇒ HEAD fell back to that heuristic too (no indexed def of the name, or a working tree that drifted from HEAD). refs_scanned= is the SCAN denominator (refs read besides HEAD), not a matched count. Read-only; single-root only. LIMITS: a TREE scan finds only what some ref STILL carries, so hits="0" alone cannot tell a name this repo never had from one it deleted, and content dropped by every tree is invisible. Add --with-history: a <fate> row then says v="never" or v="removed" with the commit, date and file that removed it. Remote-tracking refs are excluded (they mirror local ones); refs are capped, narrow with --stray-content=SUBSTR.

**Try it**

_Which ref's tree defines or mentions SYM — HEAD first, then every local branch._

```
$ ./build/ripwire . --whereis=rankGraphTeleport
... [31 more line(s); run it to see the whole thing]
```

**Shaped by:** `--with-history`, `--json`

**Caveats (stated by the binary):**

- on a REF row it is a LEXICAL heuristic — ref blobs are raw text, never ingested, so a doc quoting a signature still reads as a definition.
- head_labels="lexical" ⇒ HEAD fell back to that heuristic too (no indexed def of the name, or a working tree that drifted from HEAD).
- refs_scanned= is the SCAN denominator (refs read besides HEAD), not a matched count.

### `--flags[=SUBSTR]`

**Answers:** the dark-content dashboard: what is BUILT but OFF in this repo.

Harvests all three gate patterns — #ifndef/#define header gates, CMake option(), and getenv() reads — and reports gate, kind (compile/cmake/env), default, the size of the code it guards (#if regions and their LOC), and its read sites. When a name is BOTH a header gate and a CMake option the CMake default WINS (that is what the build actually passes) and both sites are listed. A gate whose default IS another gate's name (#define F_WALLS F_ALL) is resolved: it inherits the master's default and rolls its guarded size up, so a master switch shows <aliases n=..> rather than a misleading loc="0". LIMITS: lexical, not preprocessed — a gate computed at configure time or set only in a CI script shows its in-repo default, never the value your build used. A gate needs a VALUE (#ifndef F / #define F 0) to be a gate: valueless pairs are include guards and are excluded, and a gate read as a VALUE (constexpr bool k = F != 0, then if constexpr) reports regions="0" honestly — its code is a C++ branch, not an #if region. Pair it with --flip=NAME below to size ONE gate instead of listing them all.

**Try it**

_The dark-content dashboard: gates BUILT but OFF. CHANGED: no longer invents gates from comments/heredocs, so the count only reflects real ifndef/define, CMake option(), and getenv gates._

```
$ ./build/ripwire . --flags
<!-- ripwire flags: what is BUILT but DARK here. Three gate patterns in one report: ifndef/define header gates (kind="compile"), CMake option() switches (kind="cmake"), and getenv reads (kind="env", default unset). dark="1" means the default keeps the guarded code out of the build; regions/loc size what it turns off. When one name is BOTH a header gate and a CMake option the CMake default wins (that is what the build passes) and the header shows as an also row. Lexical, not preprocessed: this reports the in-repo default, never the value your build used. dark_gates on this root is the COUNT of dark gates; it was spelled dark until that collided with the child bool. files= is THIS verb's own harvest scan (source + CMakeLists files it read looking for gates) — a wider crawl than the map's indexed corpus, so it will not equal the map's files= -->
<flags gates="45" dark_gates="39" compile="11" cmake="10" env="24" files="853">
<gate name="FIXTURE_DARK_FEATURE" kind="compile" default="0" dark="1" regions="2" loc="13" reads="2" p="test/flagsfix/wiringFlags.h" l="10">
<read p="test/flagsfix/feature.cpp" l="10"/>
<read p="test/flagsfix/sub/nested.cpp" l="5"/>
</gate>
<gate name="PROFILE_PMC_VERBOSE" kind="compile" default="0" dark="1" regions="2" loc="10" reads="2" p="src/infra/profilePmc.h" l="78">
<read p="src/infra/profilePmc.h" l="81"/>
<read p="src/infra/profilePmc.h" l="416"/>
</gate>
<gate name="ALIASFIX_ALL" kind="compile" default="0" dark="1" regions="0" loc="0" reads="2" p="test/flagsaliasfix/aliases.h" l="7">
<aliases n="2" regions="2" loc="8"/>
... [19 more line(s); run it to see the whole thing]
```

**Shaped by:** `--flip`

**Caveats (stated by the binary):**

- LIMITS: lexical, not preprocessed — a gate computed at configure time or set only in a CI script shows its in-repo default, never the value your build used.
- A gate needs a VALUE (#ifndef F / #define F 0) to be a gate: valueless pairs are include guards and are excluded, and a gate read as a VALUE (constexpr bool k = F != 0, then if constexpr) reports regions="0" honestly — its code is a C++ branch, not an #if region.

### `--flip=NAME`

**Answers:** (with --flags) the BLAST RADIUS of turning ONE gate ON: which code becomes live, how much, which SYMBOLS hold it, what those transitively reach, and which TESTS cover it — the actionable sequel to --flags' list.

Reports #if regions AND the C++ branch sites a value-style gate governs (constexpr bool k = F != 0, then if constexpr( k )): the binding is followed, so the family --flags honestly sizes at regions="0" gets a real radius here. Alias chains run BOTH ways — flipping a MASTER rolls up every child that #defines to it (<member> rows), flipping a CHILD lights only that child and names the <parent> plus the siblings its flip would add. kind=cmake means the switch becomes a -DNAME=1 compile definition, so the C++ radius is identical, but it ALSO steers the build graph (an if(NAME) target_sources can add whole files) — those CMake sites are listed as <c> rows and deliberately NOT followed. kind=env is RUNTIME (runtime="1"): there is no delimited region, so the hosts are the symbols that consult the variable and every row is conditional at its read. --detail lifts the per-list row caps. LIMITS: lexical and single-line, never preprocessed. A binding split across two lines is missed, and block comments are only skipped line-by-line. The value lane reads C-family source only and treats a file that declares its OWN constant of the same name as shadowing the gate's (C++ scoping) — but a third header's same-named constant, included rather than redeclared, would still be counted. A lit site inside no indexed def (a guarded member field, a file-scope constexpr, a test-macro body) counts into filescope= instead of a host. Single-root only (the harvest reads on-disk paths, which a merged workspace relabels) — run it per root. Exit 0 always otherwise: a report, not a gate; an unknown gate name refuses (exit 1) and names the near-misses.

**Try it**

_Unknown-gate refusal (exit 1) naming the near-misses._

```
$ ./build/ripwire . --flags --flip=NoSuchGate
(empty)
```

**Shaped by:** `--flags`

**Caveats (stated by the binary):**

- kind=env is RUNTIME (runtime="1"): there is no delimited region, so the hosts are the symbols that consult the variable and every row is conditional at its read.
- LIMITS: lexical and single-line, never preprocessed.
- A binding split across two lines is missed, and block comments are only skipped line-by-line.

### `--layout=STRUCT`

**Answers:** the CPU/GPU contract view for ONE struct/class: its fields in declaration order with COMPUTED offsets/sizes/padding, every static_assert in the index that mentions it, and EVERY same-name definition compared field-by-field (the mirror/stub drift check that a dual-compile uniform block needs on every edit).

file:name disambiguates a same-named struct (like --around/--lego). Exit 2 when the contract is BROKEN: mirror="mismatch" (two definitions of the name disagree) or agree="0" (a sizeof tripwire contradicts the computed size). Multi-root aware: the mirror check spans every merged root. LIMITS, read them: the offsets are a MODEL, not the ABI — a lexical walk under standard- layout assumptions on a 64-bit Apple/LP64 target (natural alignment, interior padding, trailing pad to the aggregate's own alignment). It is NOT a compiler: #pragma pack, bitfields, virtuals, base classes, nested/anonymous aggregates, #if-conditional members, templates, pointer-to-member fields and any field type it cannot size all set modeled="0" with a named caveat instead of printing a number, and one unsized field un-places every field after it. alignas(N) and attribute packed ARE modelled. Array extents and macro type names resolve against the DEFINING FILE's own #define/constexpr constants only, and a macro with two definitions is accepted only when both agree on the size (the dual-compile half/__fp16 case). Definitions and asserts come from the INDEXED C-FAMILY files only (a TypeScript/Swift class has no byte layout) — .metal IS one of them (indexed under the C++ grammar, see kLangTable), so a Metal struct's layout is modelled like any other C-family aggregate.

**Try it**

_The honest-degrade case: Lang is an `enum class`, not a struct._

```
$ ./build/ripwire . --layout=Lang
(empty)
```

**Shaped by:** `--abi`, `--field-affinity`

**Caveats (stated by the binary):**

- file:name disambiguates a same-named struct (like --around/--lego).
- LIMITS, read them: the offsets are a MODEL, not the ABI — a lexical walk under standard- layout assumptions on a 64-bit Apple/LP64 target (natural alignment, interior padding, trailing pad to the aggregate's own alignment).
- It is NOT a compiler: #pragma pack, bitfields, virtuals, base classes, nested/anonymous aggregates, #if-conditional members, templates, pointer-to-member fields and any field type it cannot size all set modeled="0" with a named caveat instead of printing a number, and one unsized field un-places every field after it.

### `--field-affinity[=STRUCT]`

**Answers:** the CACHE-LOCALITY lens: which fields are READ TOGETHER but declared FAR APART.

Builds a static field CO-ACCESS affinity graph (one observation per indexed C-family function body) and diffs it against the DECLARED field order and 64-byte cache-line geometry, reusing --layout's LP64 offset model. Bare = every aggregate in the repo, ranked by separation cost; =STRUCT narrows the report to one. Pairs carry Chilimbi's separation weight wt = (64 - dist)/64 (Cache-Conscious Structure Definition, PLDI 1999) — CITED, not invented here, along with the affinity graph and the points-to-free access enumeration; the advice-not-transform posture is Hundt et al., CGO 2006. Exactly TWO findings fire, both with a direction you can defend in one sentence: split-line (two fields co-accessed by 2+ functions at wt 0.00, so NO field order puts them on one line) and straddle (one co-accessed field crossing a line boundary). ADVICE ONLY: it never proposes a reordering and it has no rewrite mode, because pack-tighter/sort-by-size advice is NON-MONOTONIC (tight packing can induce false sharing — the reason the Go team keeps its own fieldalignment analyzer out of vet and gopls). LIMITS, both in the header: static access counts are NOT dynamic frequency, so fns= is a FLOOR of distinct indexed functions and w= is a call-graph reachability PROXY (1 + fan-in), never a measured count; only dot/arrow member syntax is counted (a bare field name inside its own method is indistinguishable from a local); a field name declared by TWO aggregates is REFUSED and tallied in amb_skipped= rather than guessed; and all geometry is the LP64 MODEL, so a definition --layout marks modeled="0" contributes its affinity graph and NO geometry finding. validate= names the instrumented PROFILE_SCOPE whose hardware counters would confirm the hypothesis (see docs/FIELDAFFINITY.md for the worked example). C/C++/ObjC only. Exit 0 always: a report, not a gate.

**Caveats (stated by the binary):**

- ADVICE ONLY: it never proposes a reordering and it has no rewrite mode, because pack-tighter/sort-by-size advice is NON-MONOTONIC (tight packing can induce false sharing — the reason the Go team keeps its own fieldalignment analyzer out of vet and gopls).
- LIMITS, both in the header: static access counts are NOT dynamic frequency, so fns= is a FLOOR of distinct indexed functions and w= is a call-graph reachability PROXY (1 + fan-in), never a measured count;
- a field name declared by TWO aggregates is REFUSED and tallied in amb_skipped= rather than guessed;

### `--doc-drift[=SUBSTR]`

**Answers:** which of this repo's DOC claims are now false.

Verifies the CHECKABLE anchors in every markdown file (SUBSTR filters doc paths) against the live index and prints ONLY the ones that no longer hold, four kinds: file:line refs (why="missing-file" the path is gone, "past-eof" the file is shorter than that, "line-moved" the line is no longer inside the symbol the doc names beside it — got= names the squatter); backticked symbol mentions ("undefined"); `= N` constants ("const-value"); and `[N]` array extents ("array-extent"). LIMITS, stated because a doc-drift verb that cries wolf is worse than none — every lane deliberately UNDER-reports. A backticked name is called stale only when it occurs nowhere in any non-markdown file as an identifier token, so every library name is silent, and so is any repo constant the grammar does not tag as a definition (namespace-scope constexpr in C++, for one) — those are counted as unchecked r="not-a-definition", never as drift. A number is compared only against a DECLARATION-shaped integer literal (a decl keyword on the line, or the name opening it) that the corpus binds UNIQUELY; two values in the tree means unchecked, not drift. A `NAME = N` whose NAME appears nowhere in the code is prose, counted in prose= and never claimed as an anchor. Symbol mentions inside ``` fences are skipped (illustrative code, not claims). checked + unchecked = anchors, always: whatever was not proved says so in an <unchecked> row. Read why="undefined" precisely — it says the name is defined NOWHERE in this repo, which is not the same as DELETED: in a plan or design doc naming work not yet built, that is expected rather than rot. The file:line, const and array lanes are the high-precision ones; the mention lane is the weakest — --with-history is the fix, splitting it into why="deleted" (history removed the name; got= names the commit and date, at= the file) versus unchecked r="never-in-history" (this repo never had it, so it is not rot at all). DATED RECORDS vs ROT. An audit's finding row and a live map gone stale look identical — both are "the code moved and the doc did not" — so a failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated=, leaving drift= for the LIVE rot. drift + dated is every anchor that failed: a record still prints, it is never dropped. rec= names the evidence, most specific first: "line" (the line itself hedges — an at-the-time / as-of-DATE note, or a row opening with an ISO date), "block" (the nearest heading carries an ISO date), "title" (the filename or H1 does), "stamp" (a LABELLED front-matter self-date: 'Date: …', 'Written …', 'Generated: …'). WHAT THIS LANE CANNOT DO, because both were measured and rejected: it cannot use git history — 90 of this repo's 98 stale file:line anchors were CORRECT at their own doc's last commit, audit findings and live design docs alike, because "was it true when written" is the definition of BOTH a record and rot; and it will not read a bare date in the opening prose, which on this repo alone dated three LIVE documents on a day they merely mentioned. It reads dating MARKS, so a doc that is obviously an artifact-of-a-date to a human but never writes that date machine-readably reports LIVE (this repo has two). The bias is one-directional on purpose: a wrong "record" hides real rot, a wrong "live" only over-reports. An inception or freshness date ('opened …', 'Last updated …') is a claim the doc is CURRENT and never marks a record. NOT CHECKED AT ALL: prose, Status lines, dates, 'N of M done' tallies, and whether a code block's body is still correct. Always exits 0 — a report, not a gate. Root element carries at="<sha>[+dirty]" (omitted on a non-git root) — the commit these counts were computed against, so a number quoted from this report stays comparable across a HEAD that moves mid-session. --doc-drift --gateability  turn "CI stays non-gating" into a finishable to-do list: for every doc that STILL has a LIVE (undated) failing anchor, prints its path and live=N (how many of its rows a date would fix), plus projected_drift= — repo-wide drift= if EVERY listed doc got the fix. The fix is always the same one this lane already reads for rec="title"/"stamp": an ISO date in the doc's H1/filename, or a front-matter self-date line (Date:/Written:/ Generated:/Recorded:/Reviewed:/Audited:/Authored:). projected_drift= is an UPPER BOUND, not a mandate — dating a doc that is genuinely a live/current reference (not a snapshot-in-time record) would hide real rot rather than honestly classify it. Requires --doc-drift (refused loudly alone).

**Try it**

_Which of this repo's doc claims are now false. CHANGED: row attribute at= renamed to tgt= (at= is now only the root sha stamp)._

```
$ ./build/ripwire . --doc-drift
... [31 more line(s); run it to see the whole thing]
```

**Shaped by:** `--recall`, `--comment-coherence`, `--with-history`, `--json`

**Caveats (stated by the binary):**

- LIMITS, stated because a doc-drift verb that cries wolf is worse than none — every lane deliberately UNDER-reports.
- A `NAME = N` whose NAME appears nowhere in the code is prose, counted in prose= and never claimed as an anchor.
- Symbol mentions inside ``` fences are skipped (illustrative code, not claims).

### `--with-history`

**Answers:** OPT-IN: let --doc-drift and --whereis ask git HISTORY whether a name was ever in this repo, and which commit removed it.

ONE `git log -p` walk over everything reachable from HEAD, tokenizing removed lines — the pickaxe's semantics without the pickaxe's cost (`git log -S` per name is ~126 s at 247 names on a 2900-file repo; this is ~3 s, and ~0.8 s on ripwire itself). Off by default because those default paths run in 0.64 s and 0.15 s. Memoized per (repo, HEAD sha) — a commit is immutable, so the cache cannot go stale — and the blob covers the WHOLE repo, so a second question on the same commit costs a cache load, and --whereis reuses whatever --doc-drift already built. LIMITS: it walks HEAD's own history, so a name that only ever lived on an unmerged branch reads as never here (use --whereis's tree scan for that); a deletion performed ONLY as a merge resolution is not seen (merge diffs are not walked); and evidence is a removed LINE carrying the name, so a name whose last removal was from a doc rather than code is reported with that doc as its site. A repo deeper than the walk bound reports truncated="1" and answers unknown — never "never" — for anything it did not reach.

**Try it**

_Same report, with git history splitting stale mentions into deleted-by-commit vs never-existed._

```
$ ./build/ripwire . --doc-drift --with-history
... [31 more line(s); run it to see the whole thing]
```

**Shaped by:** `--whereis`, `--doc-drift`

**Caveats (stated by the binary):**

- Memoized per (repo, HEAD sha) — a commit is immutable, so the cache cannot go stale — and the blob covers the WHOLE repo, so a second question on the same commit costs a cache load, and --whereis reuses whatever --doc-drift already built.
- LIMITS: it walks HEAD's own history, so a name that only ever lived on an unmerged branch reads as never here (use --whereis's tree scan for that);
- A repo deeper than the walk bound reports truncated="1" and answers unknown — never "never" — for anything it did not reach.

### `--from-trace=FILE`

**Answers:** map a stack trace / sanitizer report / compiler-error text ('-'=stdin) onto the indexed symbols: table-driven frame extraction (python / asan / node / compiler / generic), ranked INNERMOST-first over in-corpus frames only (out-of-corpus frames are listed and counted, never ranked).

Each frame binds by its own NAME first (resolved_by="name") and falls back to the def enclosing its line (resolved_by="line") only when the name is absent/unknown/ambiguous — a trace older than the checkout therefore lands on the symbol it names, and a name-vs-line disagreement is disclosed as line_encloses=, never silently rebound. The counters close: in_corpus = suspects + merged + unresolved, with one <unresolved> row per file-matched frame no resolver could place. p= on a frame is the TRACE's own path:line; definition sites are the <sigs> l= values. Emits the same bundle shape as --for — top suspects' signatures + the innermost in-corpus symbol's FULL body; composes with --token-budget, and HONORS --max-tokens=N (it bounds the bodies) — one of the six shapes that do, alongside the default map, --recall, --connect, --pr-context and --for --detail=N. --top-k is NOT read here (the frame order is the trace's, not a rank). Unparseable input refuses loudly (never an empty map). --note-add="TARGET: text"  pin a field note (write-side memory) to TARGET — a canonical id (path::scope::name, as --for/--expand emit it) or a file path — in the committed, sorted .ripwire_notes at the repo root. The date is git's committer clock (HEAD), not wall time, so the line is deterministic; prints the exact written line. Also STAMPS the writing repo's HEAD sha + branch onto the note (a "done"/"fixed" claim is then anchored to the commit it was true at) — a non-git root or an unresolvable HEAD writes the plain unstamped line rather than a wrong sha. MUTATES one file; single-root only. text with no causal/decision marker ("because"/"chose"/"over"/"instead"/etc.) gets a gentle stderr tip toward the decision shape — never a refusal, the add always proceeds.

**Try it**

_Map a pasted stack trace onto indexed symbols. CHANGED: in_corpus= now reports the real count (was 0)._

```
$ ./build/ripwire . --from-trace=-
AddressSanitizer:DEADLYSIGNAL
=================================================================
==41337==ERROR: AddressSanitizer: SEGV on unknown address 0x000000000018 (pc 0x000102f4a1c8 bp 0x00016d2f1a40 sp 0x00016d2f19e0 T0)
    #0 0x102f4a1c8 in rw::rankGraphTeleport(Graph const&, std::vector<float> const&, float) src/graph.h:1148
    #1 0x102f3e884 in rw::rankGraph(Graph const&, float) src/graph.h:1174
    #2 0x102e11f30 in runDefaultMap(MainDispatch const&) src/main.cpp:5155
    #3 0x102e01a44 in main src/main.cpp:5594
    #4 0x1a2b3c0dc in start+0x9dc (dyld:arm64e+0x60dc)
==41337==ABORTING
```

**Shaped by:** `--top-k`, `--token-budget`, `--json`

**Caveats (stated by the binary):**

- map a stack trace / sanitizer report / compiler-error text ('-'=stdin) onto the indexed symbols: table-driven frame extraction (python / asan / node / compiler / generic), ranked INNERMOST-first over in-corpus frames only (out-of-corpus frames are listed and counted, never ranked).
- The counters close: in_corpus = suspects + merged + unresolved, with one <unresolved> row per file-matched frame no resolver could place.
- --top-k is NOT read here (the frame order is the trace's, not a rank).

### `--notes`

**Answers:** list all field notes grouped by target;

a target with no matching indexed symbol/file is flagged dangling="1" (legal — surfaced nowhere, listed here). Read-only. Notes surface automatically as <note d="date" [sha="…" branch="…"]> children on the symbols/files that --for and --expand emit (and the MCP for / fetch_body verbs); the sha/branch attrs appear only on notes stamped by this version, abbreviated (7 hex) for terseness — the full sha lives in .ripwire_notes on disk. An OLDER .ripwire_notes (3 fields, pre-provenance) reads and surfaces exactly as before, with no sha/branch shown. Absent/empty file = zero effect.

**Try it**

_List all field notes (write-side memory). This repo still has no .ripwire_notes._

```
$ ./build/ripwire . --notes
<ctx><!-- ripwire field notes: notes=0 targets=0 dangling=0 (a target with no matching indexed symbol/file — legal: listed here, surfaced nowhere) --><notes></notes></ctx>
```

**Shaped by:** `--no-redact`

### `--pack-task="TASK"`

**Answers:** the budget-shared task bundle: ONE call assembling, under ONE deterministic budget (default 6K tokens;

--token-budget overrides), the whole orientation dance in FIXED order — (1) routed+anchored ranking, (2) top-K full bodies, (3) their 1-hop caller signatures, (4) their field notes, (5) tests_to_run for the top files. Allocation order is ranking>bodies>callers>notes>tests; each section truncates rank-adaptively and the header reports EVERY truncation (no silent caps). A tiny budget degrades to ranking-only WITH the truncation note. Refuses loudly without a task string.

**Try it**

_ONE budget-shared bundle: ranking + top bodies + caller sigs + notes + tests_to_run. CHANGED: <d> rows now carry n=/id=._

```
$ ./build/ripwire . --pack-task="add a new output format flag to the CLI"
<ctx task="add a new output format flag to the CLI" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire task bundle for "add a new output format flag to the CLI" [routed: subtoken+body BM25 (-for's default) — no strong name hit, multi-word conceptual query]: one-call orientation under ONE budget — sections in FIXED order ranking > bodies > callers > notes > tests, each truncates rank-adaptively; every truncation reported here (no silent caps): on every section shown=rows kept, total=rows that qualified, capped=1 when they differ. bodies fill rank-first, so a bigger budget can keep FEWER, larger bodies — the count is not a quality measure. Row keys: n=name (chain it), id=canonical(when scoped), in=reuse-count (absent = not measured, never a false 0), l=line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller|callee; far=ranked but over 1 hop out; of_top denominator is per-section. budget=12744 bytes (6000-token target, ceiling 14160) | ranking: full | bodies: kept 5 of 6 (capped) | callers: kept 11 of 16 | notes: none | tests: none | far: 6 of 6 -->
<sigs>
<f p="./src/main.cpp">
<d l="7850" n="ReportVerbSlot" id="./src/main.cpp::ReportVerbSlot::ReportVerbSlot" cx="0" ccx="0" in="0">
<doc>B11.4 — THE REPORT-VERB PRECEDENCE TABLE, in ripwire&apos;s real DISPATCH order (main()&apos;s handler chain, then each handler&apos;s own arm order). One row per verb-selecting flag, so adding a verb is adding</doc>struct ReportVerbSlot</d>
... [25 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--token-budget`, `--test-gate`, `--expand`, `--partition`, `--with-graph`, `--json`

**Caveats (stated by the binary):**

- each section truncates rank-adaptively and the header reports EVERY truncation (no silent caps).
- A tiny budget degrades to ranking-only WITH the truncation note.
- Refuses loudly without a task string.

### `--partition=N`

**Answers:** (with --pack-task, N=2..16) FAN-OUT form: instead of one bundle, emit ONE shared common core plus N per-agent slices, so N parallel agents stop re-deriving the same orientation.

The task's ranked surface is carved along the call graph's own Louvain communities — a partition is a union of WHOLE modules (largest-first packing) so it reads coherently; when there are fewer modules than agents the widest is cut at its rank median and split="K" says so. The core is exactly the anchors a plain --pack-task would have bodied. --token-budget then means ONE AGENT's budget (core + its partition), not the document's — total_bytes reports the rest. Each inner <ctx> is byte-identical to a standalone call with that slice, so an orchestrator hands one bundle to one agent verbatim. LIMITS: overlap_mean/overlap_max are pairwise Jaccard over the ids each partition NAMES (window + bodies + their 1-hop neighbors) measured BEFORE budget trimming — a ceiling, not the trimmed truth; and on a task whose surface sits inside one module the split is a rank cut, not a semantic one (read split= and overlap_max before trusting the slices). Refuses loudly without --pack-task, or outside 2..16; --with-graph does not compose with it (N+1 bundles, no single graph — says so on stderr).

**Try it**

_Fan-out form: one shared core + 3 per-agent slices carved along call-graph communities._

```
$ ./build/ripwire . --pack-task="add a new output format flag to the CLI" --partition=3
<ctx-partitions partitions="3" requested="3" core_symbols="6" surface="42" modules="26" split="0" budget_per_agent_tokens="6000" core_budget_tokens="2040" partition_budget_tokens="3960" total_bytes="26395" overlap_mean="0.053" overlap_max="0.104" shared_symbols="8" union_symbols="84" core_overlap="0 … [line truncated: 6 more bytes on this line]
... [30 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- LIMITS: overlap_mean/overlap_max are pairwise Jaccard over the ids each partition NAMES (window + bodies + their 1-hop neighbors) measured BEFORE budget trimming — a ceiling, not the trimmed truth;
- and on a task whose surface sits inside one module the split is a rank cut, not a semantic one (read split= and overlap_max before trusting the slices).
- Refuses loudly without --pack-task, or outside 2..16;

### `--with-graph`

**Answers:** (with --for/--pack-task) append a compact MERMAID flowchart of the bundle's top-N (<=8) ranked anchors + their 1-hop call edges among themselves — <graph fmt="mermaid"><![CDATA[ flowchart LR ...]]></graph>, right before </ctx>.

Reuses the --mermaid emitter's syntax. Costs tokens beyond the sigs it sits next to — worth it only when the reading agent renders mermaid natively. Off by default (G5): omitted, output is byte-identical.

**Try it**

_Task lens + a compact Mermaid flowchart of the top anchors' 1-hop edges._

```
$ ./build/ripwire . --for="pagerank power iteration" --with-graph
<ctx task="pagerank power iteration" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "pagerank power iteration" [routed: subtoken+body BM25 (-for's default) — no strong name hit, multi-word conceptual query]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="3057" -->
<sigs capped="1">
<f p="./src/pagerank.cpp">
<d l="34" n="pageRankDouble" id="./src/pagerank.cpp::rw::pageRankDouble" cx="18" ccx="33" in="1" churn="3" amp="8" tested="1">unsigned pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;doub … [line truncated: 21 more bytes on this line]
</f>
<f p="./src/infra/dynamic_map.hpp" layer="infra">
<d l="290" n="leaf_node" id="./src/infra/dynamic_map.hpp::leaf_node::leaf_node" cx="0" ccx="0" in="0" churn="1">struct alignas(16) leaf_node</d>
<d l="310" n="dynamic_map" id="./src/infra/dynamic_map.hpp::dynamic_map::dynamic_map" cx="0" ccx="0" in="0" churn="1">class dynamic_map</d>
<d l="979" n="values_begin" id="./src/infra/dynamic_map.hpp::dynamic_map::values_begin" cx="2" ccx="1" in="3" churn="1" amp="3">value_iterator values_begin()</d>
... [21 more line(s); run it to see the whole thing]
```

**Shaped by:** `--partition`

### `--export=cc.json[:FILE]`

**Answers:** export per-file metrics (loc/symbols/cx/cognitive_cx/fan-in/fan-out/churn) as CodeCharta cc.json (apiVersion 1.3) — write FILE or redirect stdout;

feeds a CodeCharta 3D city

**Try it**

_Per-file metrics as CodeCharta cc.json._

```
$ ./build/ripwire . --export=cc.json:<scratch>/aux/ripwire2.cc.json
(empty)
```

### `--batch=FILE`

**Answers:** one-turn context sweep: FILE ('-'=stdin) is newline-delimited `verb:arg` sub-queries (for/grep/callers/callees/impact/uses/mentions/analyze/lego/owners/cochange/exemplar, path_between:FROM,TO), answered in ONE deduped <batch>;

caps at 16 (over-cap = capped=1)

**Try it**

_One-turn sweep: 4 newline-delimited verb:arg sub-queries answered in ONE deduped <batch>._

```
$ ./build/ripwire . --batch=<scratch>/aux/batch2.txt
for:incremental cache invalidation
callers:rankGraphTeleport
grep:DEGRADED_PATH_ALERT
lego:Vehicle
```

**Caveats (stated by the binary):**

- one-turn context sweep: FILE ('-'=stdin) is newline-delimited `verb:arg` sub-queries (for/grep/callers/callees/impact/uses/mentions/analyze/lego/owners/cochange/exemplar, path_between:FROM,TO), answered in ONE deduped <batch>;
- caps at 16 (over-cap = capped=1)

---

## self-diagnosis

### `--doctor`

**Answers:** environment self-check: binary-vs-PATH staleness, grammar tags.scm compile, cache-dir health, git reachability, tree-sitter version, and TRACKED-BINARY staleness (a committed binary whose last commit is a git-history ANCESTOR of a same-directory/same-stem source's last commit — never mtime, which a fresh clone stamps at checkout time).

"Dependent source" is a NAMING heuristic (same dir, same filename stem, e.g. tool <-> tool.cpp) — ripwire parses no build system, so a binary built from a differently-named or differently-located source is silently out of scope, neither flagged nor cleared. Single-root only. DIAGNOSTIC, not deterministic (env-dependent by design); exit 0 iff all ok, else 1. Root reports <doctor checks=N passed=M ...>; each <c/> child row carries the BOOLEAN ok="0|1". passed= is the root's count (it was spelled ok= until the vocabulary pass, which collided with the child bool). A FAILING row (ok="0") also carries hint=, the derived verdict (which of self=/which= is stale and the fix, which grammar(s) failed to compile, why the cache dir isn't writable, ...) — a passing row never carries hint=.

**Try it**

_Environment self-check: binary staleness, grammars, cache dir, git, tracked-binary staleness._

```
$ ./build/ripwire . --doctor
<doctor checks="6" passed="6" at="bc09d0260+dirty">
<c n="binary-path" ok="1" self="./build/ripwire" which="" on_path="0"/>
<c n="grammars" ok="1" loaded="13" expected="13"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="34029" bytes="209325954" many="1"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="bc09d0260"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="13"/>
<c n="tracked-binaries" ok="1" tracked="1093" binaries="2" non_git="0" truncated="0" stale="0"/>
</doctor>
```

**Caveats (stated by the binary):**

- "Dependent source" is a NAMING heuristic (same dir, same filename stem, e.g.
- A FAILING row (ok="0") also carries hint=, the derived verdict (which of self=/which= is stale and the fix, which grammar(s) failed to compile, why the cache dir isn't writable, ...) — a passing row never carries hint=.

### `--skipped`

**Answers:** itemize the map header's skipped_oversize= count: one <f p= bytes= limit=/> row per otherwise-indexable file the crawl DROPPED for exceeding a size ceiling — the files absent from files= and every other surface (files= + oversize= = the population the crawl considered).

limit= is the ceiling that dropped the row: --max-file-size, or the fixed 256KB .json config ceiling --max-file-size does not raise; the root repeats both effective ceilings (max_file_size= json_ceiling=) so a zero-row report still states its bounds, and oversize="0" means nothing was dropped at them. Rows sort by path; composes with --max-file-size/--exclude and multi-root (rows carry the <label>/./<rel> spelling). Read-only; exit 0 always: a report, not a gate.

**Caveats (stated by the binary):**

- itemize the map header's skipped_oversize= count: one <f p= bytes= limit=/> row per otherwise-indexable file the crawl DROPPED for exceeding a size ceiling — the files absent from files= and every other surface (files= + oversize= = the population the crawl considered).
- limit= is the ceiling that dropped the row: --max-file-size, or the fixed 256KB .json config ceiling --max-file-size does not raise;
- exit 0 always: a report, not a gate.

---

## security — scan skill files for injection / exfiltration patterns (exit 2 = CRITICAL, 1 = WARN,

### `--scan-skill=FILE`

**Answers:** scan a single skill file before installing (any file, not just .md)

**Try it**

_Scan a single skill file for injection/exfiltration patterns before installing._

```
$ ./build/ripwire --scan-skill=skills/ripwire-orient/SKILL.md
<skillscan files="1" findings="0" verdict="clean"></skillscan>
```

### `--scan-skills[=DIR]`

**Answers:** scan DIR (or .agents/skills/ + ~/.claude/skills/ + ${CODEX_HOME:-~/.codex}/skills/).

EVERY text file, .md and .sh alike — a skill dir's executables are the files most worth scanning. skipped= counts what it could not scan (binary content, or unreadable); denylisted subtrees (.git, node_modules, build, ...) are not descended and the stderr tally says how many for vulnerabilities

**Try it**

_Scan a whole skills directory (exit 2 = CRITICAL, 1 = WARN). Explicit-DIR form only._

```
$ ./build/ripwire --scan-skills=skills
<skillscan files="24" findings="0" verdict="clean"></skillscan>
```

**Caveats (stated by the binary):**

- skipped= counts what it could not scan (binary content, or unreadable);

### `--force`

**Answers:** (wrap) proceed even if CRITICAL findings are found

---

## knobs / modes

### `--rank-by=pagerank|authority|hub|rrf|churn`

**Answers:** ranking signal (churn = git change-frequency prior, and stamps its own map with rank_by/window/at so it cannot pass for the structural one;

default pagerank) --format=xml|columnar|rows output shape for the FLAT list verbs (--callers/--callees/--uses/--impact): xml (default, byte-identical) or columnar (a <paths> table + parallel arrays: fields= path,name,line,kind on --callers/--callees/--impact, path,line,role,in_id on --uses — the emitted block's own legend states the zip/n=/&#44;-escape contract; ~15-60% fewer tokens on multi-row results, by de-duplicating the repeated per-row markup + paths; results of a few rows can be LARGER — the paths/cols scaffold has a fixed cost). rows is an alias for columnar. Any OTHER verb refuses (exit 1) — it has no row list to re-encode. Map is unaffected.

**Try it**

_Rank by git change-frequency prior instead of PageRank._

```
$ ./build/ripwire . --rank-by=churn --top-k=5
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- rank_by=churn: k= is a git CHANGE-FREQUENCY prior over window=, not call-graph importance; the same corpus ranked by pagerank orders differently -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- files=850 symbols=6432 edges=8737 shown=5 est_tokens=582 ambiguous=2631 unresolved=662 precise=3 skipped_oversize=3 order=important-first -->
<r at="bc09d0260+dirty" rank_by="churn" window="18mo" est_tokens="582">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0582">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0147">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0131">
... [7 more line(s); run it to see the whole thing]
```

**Shaped by:** `--since`

**Caveats (stated by the binary):**

- ranking signal (churn = git change-frequency prior, and stamps its own map with rank_by/window/at so it cannot pass for the structural one;
- Any OTHER verb refuses (exit 1) — it has no row list to re-encode.

### `--format=candidates`

**Answers:** (with --for/--query) a FLAT top-K export for an EXTERNAL reranker: one <cand r= s= n= id= k= p= l=><sig>..</sig></cand> row per result — identity + score + signature only, no lens/quality extras, no doc bodies.

Composes with --top-k.

**Try it**

_CHANGED: unknown --format value named + supported set listed._

```
$ ./build/ripwire . --callers=rankGraphTeleport --format=bogus
(empty)
```

**Shaped by:** `--top-k`, `--pack-signatures`, `--rank-by`, `--json`

### `--json`

**Answers:** machine-parseable JSON instead of XML, SAME content, keys mirror the XML attr names 1:1 — supported for the default map, --for, --pack-task, --callers/--callees/ --impact, --quality-delta, --test-gate (the CI/scripting verbs).

Every other verb (and --format=columnar/candidates, --detail, --map-diff, --scip composed with it) refuses loudly on stderr + exit 1 rather than silently falling back to XML. Deterministic: same 2-run byte-diff + stable key order contract as the XML. --limit=N --offset=M       paginate a high-cardinality verb. HONORED by: --deps --callers --callees --tree --lint --hotspots --clones --cochange --owners --communities --community --doc-drift --whereis --grep/--regex --match --impact --uses --exercises --seams --zoom --external-surface --dead-code --mentions --graph-query --stray-content --test-gate --readability --ensemble --quality-panel --context-ratio --nonlocal-state --comment-coherence --naming-consistency. Emit at most N rows, skipping the first M; N overrides the verb's own display cap (40 hotspot files, 30 co-change pairs, 60 whereis hits, 100 grep/match hits, 40 impact rows, 20 seam pairs, 40 readability rows, 40 ensemble symbol rows, 40 context-ratio symbol rows, 40 nonlocal-state rows, 200 graph-query rows / --top-k). With --offset alone (no --limit) the verb's own default page size applies and the root discloses limit="0" — on OUTPUT that 0 means 'no explicit --limit', never a zero-row page (the flag itself refuses --limit=0). Deterministic seams (rows are already sorted) so --offset=N is the exact continuation of the previous --limit=N page. The root element then carries shown= capped= total= has_more= next_offset= offset= limit= — loop until has_more="0" — EXCEPT the verbs with TWO INDEPENDENT listings, which carry the noun-prefixed form instead (one shown= could only describe one): --test-gate shown_tests=/tests_capped= + shown_untested=/untested_capped=, --communities shown_modules=/modules_capped= + shown_bridges=/bridges_capped=, --ensemble and --context-ratio shown_syms=/syms_capped= + shown_files=/files_capped=; the window takes the PRIMARY listing (--test-gate's <u> rows; its <t> rows repeat on every page, complete). Any verb NOT in that list REFUSES both flags (exit 1) rather than accepting and ignoring them: budget/top-k verbs (--for/--recall/--pack-task/--from-trace/ --expand/--outline/--pack-signatures/--format=candidates) are shaped by --top-k/--max-tokens/--token-budget, not a page; the rest (--path/--connect/ --around/--exemplar/--report/--mermaid/--map-diff/--metrics and the default map) answer with a single fixed-shape result that has no row list to window at all.

**Try it**

_JSON refusal shape: an unsupported verb refuses loudly instead of silently falling back to XML._

```
$ ./build/ripwire . --hotspots --json
(empty)
```

**Shaped by:** `--max-tokens`, `--token-budget`

**Caveats (stated by the binary):**

- Every other verb (and --format=columnar/candidates, --detail, --map-diff, --scip composed with it) refuses loudly on stderr + exit 1 rather than silently falling back to XML.
- --limit=N --offset=M       paginate a high-cardinality verb.
- Emit at most N rows, skipping the first M;

### `--exclude=SUBSTR`

**Answers:** drop matching paths (repeatable)   --ignore-tests

**Try it**

_Drop matching paths (repeatable) before ranking._

```
$ ./build/ripwire . --exclude=present --exclude=bench --top-k=5
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=782 symbols=5651 edges=8292 shown=5 est_tokens=420 ambiguous=2619 unresolved=272 precise=3 order=important-first -->
<r est_tokens="420">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0552">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0142">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0133">
</s>
</f>
... [5 more line(s); run it to see the whole thing]
```

**Shaped by:** `--skipped`, `--index-out`

### `--map-diff`

**Answers:** the FULL map, re-ranked with a PageRank teleport toward git-changed files (working tree vs HEAD) — changed files and their neighbours float up, but every file can still appear;

this is NOT a filter to only-changed symbols. changed="N" in the header names the seed file count (0 on a clean tree or no-git — teleport degrades to uniform; ranked CONTENT is then identical to the plain default map, but not byte-identical: the map-diff header keeps its changed= and at= stamp). Want only-changed instead? --pr-context.

**Try it**

_Full map re-ranked with teleport toward git-changed files — recorded against a DIRTY tree, so changed= counts the working copy's files and the teleport is live._

```
$ ./build/ripwire . --map-diff --top-k=5
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- files=850 symbols=6432 edges=8737 shown=5 est_tokens=563 ambiguous=2631 unresolved=662 precise=3 changed=4 skipped_oversize=3 order=important-first -->
<r at="bc09d0260+dirty" est_tokens="563">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0326">
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0159">
</s>
</f>
<f p="./src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" k="0.0144">
... [10 more line(s); run it to see the whole thing]
```

**Shaped by:** `--json`

**Caveats (stated by the binary):**

- this is NOT a filter to only-changed symbols.
- changed="N" in the header names the seed file count (0 on a clean tree or no-git — teleport degrades to uniform;

### `--cache=PATH`

**Answers:** incremental cache at PATH (re-parse only changed files)

**Try it**

_Explicit incremental cache at a path OUTSIDE the repo (first call writes it)._

```
$ ./build/ripwire . --cache=<scratch>/aux/warm2.ripwirecache --top-k=3
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=850 symbols=6432 edges=8737 shown=3 est_tokens=393 ambiguous=2631 unresolved=662 precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="393">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0503">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0133">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0125">
... [3 more line(s); run it to see the whole thing]
```

**Shaped by:** `--index-out`

### `--index-out=BASE`

**Answers:** CI generate-and-exit: cold-parse the tree and write the committable index artifact, then exit 0 with NO map on stdout.

Writes BOTH families — BASE.lean.ripwirecache (map/ nav/--pr-context) and BASE.rich.ripwirecache (--for/--exemplar/--metrics/--uses are RICH, a lean-only artifact leaves them cold). Consume in a PR job with --cache=BASE.lean.ripwirecache (or .rich.). --exclude shapes the crawl and therefore the blob content. Same-architecture speed cache: consumed on a different arch it self-heals to a full cold parse (correct, slower). NOT byte-identical run-to-run (the header stamps the blob write time); the contract is RESTORE-EQUIVALENCE (a --cache restore == a cold parse), never blob-byte-identity.

**Caveats (stated by the binary):**

- the contract is RESTORE-EQUIVALENCE (a --cache restore == a cold parse), never blob-byte-identity.

### `--no-cache`

**Answers:** disable the warm-by-default per-root TMPDIR cache (forces a cold parse)

**Try it**

_Force a cold parse (bypass the warm TMPDIR cache) — shows the cold-vs-warm cost._

```
$ ./build/ripwire . --no-cache --top-k=3
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=850 symbols=6432 edges=8737 shown=3 est_tokens=393 ambiguous=2631 unresolved=662 precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="393">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0503">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0133">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0125">
... [3 more line(s); run it to see the whole thing]
```

### `--max-file-size=N[K|M|G]`

**Answers:** skip files larger than N bytes (default 4MB;

raise for repos with big hand-authored source, e.g. --max-file-size=100M; suffix = 1024^n). .json carries a SECOND, fixed 256KB ceiling this flag does not raise (that size of .json is data, not config, and explodes the symbol table); files it drops are counted in the header's skipped_oversize=

**Try it**

_Skip files above a size bound before parsing (note the corpus shrink in the header)._

```
$ ./build/ripwire . --max-file-size=8K --top-k=3
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=518 symbols=2011 edges=732 shown=3 est_tokens=381 ambiguous=60 unresolved=60 precise=3 skipped_oversize=335 order=important-first -->
<r est_tokens="381">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0125">
</s>
</f>
<f p="./test/scipfix/make_index.py" layer="test">
<s t="fn" n="varint" k="0.0042">
</s>
</f>
<f p="./src/infra/platform.h" layer="infra">
<s t="fn" n="max" id="./src/infra/platform.h::fastmath::max" k="0.0038">
</s>
... [2 more line(s); run it to see the whole thing]
```

**Shaped by:** `--skipped`

**Caveats (stated by the binary):**

- skip files larger than N bytes (default 4MB;
- files it drops are counted in the header's skipped_oversize=

### `--refetch`

**Answers:** when the root is a git URL, force a fresh clone instead of reusing the cached one (default: reuse forever;

stderr notes the cached clone's age)

### `--scip=index.scip`

**Answers:** consume a SCIP index as a PRECISION overlay: precise call edges replace name-based guesses (tagged prov="scip"), ambiguous= drops.

Missing/corrupt index → degrades to name-based (never fails). Zero deps (hand-rolled reader).

**Try it**

_SCIP overlay with a missing index: degrades to name-based, never fails._

```
$ ./build/ripwire . --scip=does_not_exist.scip --callers=rankGraphTeleport
... [9 more line(s); run it to see the whole thing]
```

**Shaped by:** `--json`

**Caveats (stated by the binary):**

- consume a SCIP index as a PRECISION overlay: precise call edges replace name-based guesses (tagged prov="scip"), ambiguous= drops.
- Missing/corrupt index → degrades to name-based (never fails).

### `--mcp`

**Answers:** persistent index server (parse once, many warm queries) over stdio

**Shaped by:** `--no-stable`, `--listen`

### `--listen=HOST:PORT`

**Answers:** serve the MCP server over Streamable HTTP instead of stdio (implies --mcp).

Binds 127.0.0.1 by default (bare PORT = loopback); one listener serves ONE workspace fixed at startup. A non-loopback host (e.g. 0.0.0.0:8080) REQUIRES --mcp-token and refuses to start without it. No TLS — reverse-proxy it.

**Shaped by:** `--allow-remote-edits`

**Caveats (stated by the binary):**

- 0.0.0.0:8080) REQUIRES --mcp-token and refuses to start without it.

### `--mcp-token=T`

**Answers:** shared bearer token gating every HTTP request (or set RIPWIRE_MCP_TOKEN);

a missing/wrong token gets a 401. Required for a non-loopback bind.

**Shaped by:** `--listen`

### `--allow-remote-edits`

**Answers:** permit the edit verbs over --listen (refused by default: a remote file-writer is a different trust contract);

forces the token requirement even on loopback

**Caveats (stated by the binary):**

- permit the edit verbs over --listen (refused by default: a remote file-writer is a different trust contract);

### `--eval-stray=FILE`

**Answers:** labelled verdict-accuracy eval for --stray-content: FILE is TSV `ref<TAB>verdict` (merged|superseded|unmerged, '#' comments ok).

Emits per-case want=/got= plus an accuracy, and exits 3 if any labelled case regressed — MEASURE a supersession- threshold change against real labels instead of eyeballing it. A ref absent from the report scores as merged (merged refs are omitted by design).

**Try it**

_Labelled verdict-accuracy eval for --stray-content (3 hand-labelled refs)._

```
$ ./build/ripwire . --eval-stray=<scratch>/aux/stray_labels2.tsv
# ref<TAB>verdict labels for --eval-stray
lane-notes	merged
lane-abi	merged
lane-docdrift	unmerged
```

### `--eval`

**Answers:** self-eval (co-change recall vs BM25)

**Try it**

_Self-eval: co-change recall vs BM25._

```
$ ./build/ripwire . --eval
ripwire --eval  (co-change recovery, averaged over 41 historical commits)
  ranker     recall@5  recall@10  recall@20
  ripwire        4.5%       5.5%       6.9%
  BM25           6.9%      12.0%      16.3%
  BM25sub        7.8%      11.6%      16.4%
  BM25body      12.6%      20.3%      26.4%
  fused          3.5%       6.5%       9.8%
  anchored      12.3%      20.8%      26.1%
  same-dir      17.6%      24.8%      29.8%
  random         0.6%       1.2%       2.4%   <- floor (random ranking over F=850 files)
  note: `ripwire` here is the DEFAULT MAP's structural-only PageRank (importance, not
        relatedness) — it is NOT what a --for/--query retrieval call ranks with. BM25 /
        BM25sub / BM25body are QUERY-TIME lexical rankers (whole-name / subtoken /
        subtoken+body); fused = RRF(ripwire, BM25sub); anchored = BM25body + anchored PPR
... [5 more line(s); run it to see the whole thing]
```

### `--eval-retrieval`

**Answers:** known-item retrieval eval: for symbols WITH a doc-comment, query by NAME and by a doc-comment PHRASE;

reports MRR + recall@1/5/10 per ranker (subtoken+body, name-exact, anchored, routed) per query-mode. Validates query-TIME ranker choice.

**Try it**

_Known-item retrieval eval: MRR + recall@k per ranker per query mode._

```
$ ./build/ripwire . --eval-retrieval
ripwire --eval-retrieval  (known-item, 150 doc-commented symbols; gold is in-corpus by construction)
  ranker    query-mode     MRR  recall@1  recall@5 recall@10
  subtoken  name         0.697     56.7%     86.0%     92.7%
  subtoken  doc-phrase   0.817     78.0%     85.3%     86.7%
  name-exact name         0.894     84.0%     96.7%     99.3%
  name-exact doc-phrase   0.001      0.0%      0.0%      0.0%
  anchored  name         0.707     58.7%     85.3%     89.3%
  anchored  doc-phrase   0.813     78.7%     84.0%     85.3%
  routed    name         0.894     84.0%     96.7%     99.3%
  routed    doc-phrase   0.816     78.0%     85.3%     86.7%
  note: routing chose name-exact on 150/150 NAME queries (a NAME query is always identifier-shaped);
        the confidence gate routes doc-phrase queries to name-exact ONLY when EVERY content word names a symbol
        (or an explicit camel/snake token appears), so conceptual prose falls back to subtoken+body — routed tracks
        the better ranker on BOTH modes (routed==name-exact on name, ~=subtoken+body on doc-phrase).
```

### `--eval-mined=FILE`

**Answers:** session-trace-mined retrieval eval: consumes a minedpair.jsonl artifact from bench/mine_traces.py (real (query, gold-files) pairs mined from local Claude Code session transcripts) and reports recall@5/10/20 + Acc@k + MRR per arm (for/query/anchor/random), assisted vs unassisted.

### `--eval-skills=FILE`

**Answers:** labelled skill-ROUTING eval: ROOT is a skills directory (one SKILL.md per subdir);

FILE is TSV `prompt<TAB>skill[,skill]|none<TAB>provenance`. Scores deterministic selectors (keyword overlap = the trivial baseline, BM25 over descriptions/full text, name match, the routed --for ranker) on top-1-in- permitted-set plus positive/negative separation (AUC) — does the right skill fire, does every skill stay quiet on off-topic prompts. Ambiguous moments carry a permitted SET; `none` rows are first-class. -h, --help                 this catalog -v, --version              print the version + short build info, exit 0

**Try it**

_Labelled skill-ROUTING eval over the repo's own skills/ directory (4 hand-labelled prompts)._

```
$ ./build/ripwire skills --eval-skills=<scratch>/aux/skills_labels2.tsv
orient in an unfamiliar codebase fast	ripwire-orient	judged
who calls this function and what is the blast radius	ripwire-navigate	judged
plan parallel worktrees so the lanes do not collide	ripwire-change-check	judged
what is the weather in Paris	none	neg
```

**Caveats (stated by the binary):**

- Ambiguous moments carry a permitted SET;

---

_Generated by `docs/docs_commands_build.py`. See `docs/README.md` for the documentation index._
