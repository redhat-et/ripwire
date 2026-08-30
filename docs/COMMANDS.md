# ripwire — every flag, generated from the binary

**This file is generated. Do not hand-edit it.** Regenerate with:

```bash
python3 docs/docs_commands_build.py --bin build/ripwire
```

The flag surface below is read from `ripwire --help`, so it cannot disagree with the shipped
binary. `test/docscommandscheck.sh` fails if it ever does — in either direction.

Sample output is lifted from a real recorded run (`docs/captures/COMMANDS_showcase_2026-08-22.md`), trimmed to the first few lines and
scrubbed of local paths. It is illustrative, not a golden: run the command yourself for the
current shape.

> ripwire — the "ripgrep of AI context": parse a codebase, rank symbols by Personalized PageRank,
> stream a deterministic minified XML map to stdout. Zero runtime deps. Languages: C++, C, ObjC/ObjC++,
> Metal (MSL, .metal — C++ grammar), CUDA (.cu/.cuh — tree-sitter-cuda, <<<>>> launches are call edges),
> Python, TypeScript, JavaScript, Java, Ruby, PHP (.php/.phtml), Lua, Bash, Go, Rust, Swift, C#;
> JSON, TOML, YAML (config keys); Markdown (.md/.markdown — headings are section symbols with spans).
> usage: ripwire <dir> [flags]            # default = the ranked map of <dir> on stdout

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

**understand a codebase cold** — [`--top-k`](#top-k-n) · [`--max-tokens`](#max-tokens-n) · [`--token-budget`](#token-budget-n-k-m-g) · [`--help-task`](#help-task-task) · [`--for`](#for-task) · [`--signatures-only`](#signatures-only) · [`--auto-bodies`](#auto-bodies) · [`--no-route`](#no-route) · [`--adaptive`](#adaptive) · [`--no-mention-boost`](#no-mention-boost) · [`--no-doc-mention`](#no-doc-mention) · [`--lego`](#lego-type) · [`--exemplar`](#exemplar-task-kind) · [`--recall`](#recall-task) · [`--tree`](#tree) · [`--html`](#html-file) · [`--color-by`](#color-by-mode) · [`--order`](#order-mode) · [`--no-stable`](#no-stable)

**navigate / answer a question** — [`--around`](#around-sym) · [`--callers`](#callers-sym) · [`--callees`](#callees-sym) · [`--uses`](#uses-sym) · [`--graph-query`](#graph-query-expr) · [`--external-surface`](#external-surface) · [`--path`](#path-src-dst) · [`--connect`](#connect-a-b-c) · [`--impact`](#impact-sym) · [`--verify`](#verify-claim) · [`--mentions`](#mentions-sym) · [`--affected`](#affected-f1-f2-sym) · [`--exercises`](#exercises-testfile) · [`--situ`](#situ-f1-f2) · [`--handoff`](#handoff) · [`--test-gate`](#test-gate-f1-f2) · [`--grep`](#grep-str-regex-pat) · [`--grep-scope`](#grep-scope-line-file) · [`--grep-in`](#grep-in-code-any) · [`--handles`](#handles) · [`--match`](#match-query) · [`--pattern`](#pattern-pat) · [`--query`](#query-terms)

**zoom the detail ladder** — [`--detail`](#detail-n) · [`--pack-signatures`](#pack-signatures) · [`--outline`](#outline-a-b) · [`--expand`](#expand-a-b) · [`--compress`](#compress) · [`--pack-top-n`](#pack-top-n-n) · [`--no-redact`](#no-redact)

**assess quality / structure** — [`--metrics`](#metrics) · [`--deps`](#deps) · [`--hotspots`](#hotspots) · [`--clones`](#clones) · [`--readability`](#readability) · [`--nonlocal-state`](#nonlocal-state) · [`--ensemble`](#ensemble) · [`--quality-panel`](#quality-panel-preset) · [`--context-ratio`](#context-ratio) · [`--naming-calibration`](#naming-calibration) · [`--naming-consistency`](#naming-consistency) · [`--naming-locals`](#naming-locals) · [`--comment-coherence`](#comment-coherence) · [`--cochange`](#cochange-file) · [`--cochange-recur`](#cochange-recur-k) · [`--cochange-groups`](#cochange-groups) · [`--since`](#since-rev-date) · [`--arch`](#arch-file) · [`--lint`](#lint) · [`--lint-catalog`](#lint-catalog) · [`--lint-rules`](#lint-rules-dir) · [`--sarif`](#sarif) · [`--with-profile`](#with-profile-file) · [`--communities`](#communities) · [`--community`](#community-id) · [`--zoom`](#zoom-depth) · [`--report`](#report) · [`--seams`](#seams) · [`--mermaid`](#mermaid) · [`--owners`](#owners-sym) · [`--dead-code`](#dead-code-dir) · [`--quality-baseline`](#quality-baseline) · [`--quality-delta`](#quality-delta) · [`--quality-delta`](#quality-delta-rev-a-b) · [`--dmm`](#dmm-rev-a-b) · [`--quality-ack`](#quality-ack-reason) · [`--edit-check`](#edit-check-sym) · [`--replace-symbol-body`](#replace-symbol-body-target) · [`--insert-before-symbol`](#insert-before-symbol-target) · [`--insert-after-symbol`](#insert-after-symbol-target) · [`--edit-payload`](#edit-payload-file) · [`--edit-target-file`](#edit-target-file-path) · [`--edit-plan`](#edit-plan-file) · [`--dry-run`](#dry-run-apply) · [`--safe-delete`](#safe-delete-sym) · [`--slice`](#slice-sym-var) · [`--pr-context`](#pr-context-baseref) · [`--stray-content`](#stray-content-substr) · [`--plan`](#plan) · [`--abi`](#abi) · [`--whereis`](#whereis-sym) · [`--flags`](#flags-substr) · [`--flip`](#flip-name) · [`--layout`](#layout-struct) · [`--field-affinity`](#field-affinity-struct) · [`--doc-drift`](#doc-drift-substr) · [`--with-history`](#with-history) · [`--plan-lint`](#plan-lint-file) · [`--from-trace`](#from-trace-file) · [`--run-trace`](#run-trace-cmd) · [`--run-timeout`](#run-timeout-seconds) · [`--notes`](#notes) · [`--pack-task`](#pack-task-task) · [`--partition`](#partition-n) · [`--with-graph`](#with-graph) · [`--export`](#export-cc-json-file) · [`--batch`](#batch-file)

**self-diagnosis** — [`--doctor`](#doctor) · [`--agent`](#agent-codex) · [`--skipped`](#skipped)

**security — scan skill files for injection / exfiltration patterns (exit 2 = CRITICAL, 1 = WARN,** — [`--scan-skill`](#scan-skill-file) · [`--scan-skills`](#scan-skills-dir) · [`--force`](#force)

**knobs / modes** — [`--rank-by`](#rank-by-pagerank-authority-hub-rrf-churn-churn-decay) · [`--format`](#format-candidates) · [`--legend`](#legend-full-compact) · [`--json`](#json) · [`--exclude`](#exclude-substr) · [`--map-diff`](#map-diff) · [`--cache`](#cache-path) · [`--index-out`](#index-out-base) · [`--no-cache`](#no-cache) · [`--max-file-size`](#max-file-size-n-k-m-g) · [`--refetch`](#refetch) · [`--scip`](#scip-index-scip) · [`--mcp`](#mcp) · [`--listen`](#listen-host-port) · [`--mcp-token`](#mcp-token-t) · [`--allow-remote-edits`](#allow-remote-edits) · [`--eval-stray`](#eval-stray-file) · [`--eval`](#eval) · [`--eval-retrieval`](#eval-retrieval) · [`--eval-mined`](#eval-mined-file) · [`--eval-skills`](#eval-skills-file)

---

## understand a codebase cold

### `--top-k=N`

**Answers:** keep the N highest-ranked symbols (default 200) — applies to the default map, plain --query, and --format=candidates (incl.

with --for). --for's OWN signature/lego/compose bundle self-limits via --pack-top-n instead — --top-k is INERT there (documented, not fixed — a real fix is a behavior change). --pack-task/--from-trace/--run-trace/--situ self-budget via --token-budget, not --top-k. --top-k=0 emits NO ranked map at all — ONLY the payload you asked for (--expand/--outline/--pack-signatures/--pack-top-n). Use it when you want the body and not the ~200-symbol map that otherwise rides along with it.

**Try it**

_Same map, capped to the 5 highest-ranked symbols._

```
$ ./build/ripwire . --top-k=5
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1329 symbols=11493 edges=14084 shown=5 est_tokens=609 ambiguous=5555 unresolved=3233 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:18,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="609" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0165">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0083">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" k="0.0082">
</s>
... [6 more line(s); run it to see the whole thing]
```

**Shaped by:** `--token-budget`, `--recall`, `--graph-query`, `--pack-signatures`, `--expand`, `--from-trace`, `--run-trace`, `--format`

**Caveats (stated by the binary):**

- --for's OWN signature/lego/compose bundle self-limits via --pack-top-n instead — --top-k is INERT there (documented, not fixed — a real fix is a behavior change).

### `--max-tokens=N`

**Answers:** budget the map to ~N tokens (binary-search top-K) — SHAPES the map to fit.

THE FIT IS A BYTE CEILING, and it is deliberately CONSERVATIVE: N is converted at 2.36 B/tok (the densest calibrated language, so N holds for any corpus) times a 0.90 headroom factor. The map's own est_tokens uses THIS corpus's language-weighted rate instead, so a conformant fit REPORTS a number below the N you asked for — expect ~10-20% of N unused. The shaped map discloses both: max_tokens=N (asked) and fit_bytes=B (honoured). Consequence for composing it with --token-budget=N below: the two Ns are different units, so the same N on both is NOT a tautology. At a SMALL N the map's fixed floor (envelope + legend) can exceed fit_bytes with even one symbol emitted — that map says over_ceiling=1 rather than overshoot in silence, and its est_tokens can then exceed N. XML only: the --json map carries no max_tokens=/fit_bytes= keys yet, and its fit is measured in XML bytes. On --recall it SHAPES the doc bundle the same way: docs are dropped from the BOTTOM of the ranking and the last one may be cut within itself — every cut is DISCLOSED (header total=/shown=/capped=/truncated=, a per-doc [truncated: X of Y bytes] marker, and a closing (capped: …) note). Selection order never changes.

**Try it**

_SHAPE the map to fit ~1500 tokens (binary-search top-K)._

```
$ ./build/ripwire . --max-tokens=1500
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- max_tokens=asked fit_bytes=honoured: fit_bytes = max_tokens x 2.36 (densest-language B/tok) x 0.90 headroom, a CONSERVATIVE cap, so est_tokens (this corpus's own rate) lands ~10-20% BELOW max_tokens by design; the token-budget gate compares against est_tokens, not fit_bytes; over_ceiling=floor-alone-exceeded-fit_bytes(absent=cap-held) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1329 symbols=11493 edges=14084 shown=15 est_tokens=1247 ambiguous=5555 unresolved=3233 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:18,tsv:16,lock:6,xml:4" unindexed_exts=17 max_tokens=1500 fit_bytes=3186 order=important-first -->
<r root="." est_tokens="1247" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0165">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0083">
</s>
<s t="method" n="push_back" id="./src/infra/svector.h::svector::push_back" overloads="2" amb="2" k="0.0070">
<c n="buf"/>
<c n="buf"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--token-budget`, `--recall`, `--detail`, `--pr-context`, `--from-trace`, `--run-trace`, `--json`

**Caveats (stated by the binary):**

- THE FIT IS A BYTE CEILING, and it is deliberately CONSERVATIVE: N is converted at 2.36 B/tok (the densest calibrated language, so N holds for any corpus) times a 0.90 headroom factor.
- Consequence for composing it with --token-budget=N below: the two Ns are different units, so the same N on both is NOT a tautology.
- At a SMALL N the map's fixed floor (envelope + legend) can exceed fit_bytes with even one symbol emitted — that map says over_ceiling=1 rather than overshoot in silence, and its est_tokens can then exceed N.

### `--token-budget=N[K|M|G]`

**Answers:** two personalities depending on the verb: - default map / --query / --recall: a CI GATE — exit 3 if the emitted DOCUMENT's est_tokens exceeds N.

That is the map PLUS every block appended after it (<sigs>/<src>/<bodies>/<outline>), each charged from the bytes it actually emits at the calibrated rate for what those bytes are — so --pack-top-n=3 --token-budget=600 gates on the ~67KB it would stream, not on the map alone. (test/tokenbudgetcheck.sh reports the live MAPE vs tiktoken o200k when tiktoken is installed; the estimate is calibrated, never exact — Claude's tokenizer is not public.) Within budget: exit 0, output unchanged. ASSERTS and fails, vs --max-tokens which shapes to fit — composable: set neither, either, or both (e.g. --max-tokens=16000 --token-budget=16K), but see --max-tokens above: the two Ns are measured in different units. Over budget, nothing of the artifact reaches stdout — only a small record naming withheld_est_tokens= vs budget=, the same vocabulary --recall uses, since est_tokens= is normatively about what a run PRINTED. On --recall the check likewise runs BEFORE a byte of the bundle is emitted: stdout gets the header line naming what was withheld, never the artifact just rejected. --json GATES AT A DIFFERENT NUMBER for the same request, and by design: the flag measures the DOCUMENT that was emitted, and the JSON encoding of the same map is smaller than the XML one (MEASURED on src/ --top-k=200: est_tokens 577 XML vs 435 JSON, ~25% apart). So the same N can pass under --json and fail without it — pick the budget for the dialect you emit. - --for / --pack-task / --from-trace / --run-trace: SHAPES instead of gating — overrides that lens's own default payload budget and trims to fit, always exit 0. --for's header reports est_tokens="N" so its fit is checkable; --pack-task/--from-trace report their budget ledger in the header report line instead. On --for's auto bundle the ceiling is SPLIT, not handed to the signatures first: the sig side's claim caps at the default sig budget and the rest flows to the inline bodies, so a wider ceiling never serves fewer of them (see --for below). Its VERBATIM task echo is bytes no trim can shrink, so past some task length the header floor alone exceeds the ceiling: the lens drops the comment's DUPLICATE echo first (task_echo: dropped (ceiling); task= keeps the verbatim copy), then labels it over_ceiling (--recall: over_ceiling=1) — never a trim it did not actually do.

**Try it**

_GATE form: exit 3 if the map's own est_tokens exceeds the budget (over-budget failure shape)._

```
$ ./build/ripwire . --token-budget=100
<r withheld_est_tokens="9039" budget="100" withheld="1"/>
```

**Shaped by:** `--top-k`, `--max-tokens`, `--for`, `--recall`, `--handoff`, `--from-trace`, `--run-trace`, `--pack-task`

**Caveats (stated by the binary):**

- That is the map PLUS every block appended after it (<sigs>/<src>/<bodies>/<outline>), each charged from the bytes it actually emits at the calibrated rate for what those bytes are — so --pack-top-n=3 --token-budget=600 gates on the ~67KB it would stream, not on the map alone.
- the estimate is calibrated, never exact — Claude's tokenizer is not public.) Within budget: exit 0, output unchanged.
- On --recall the check likewise runs BEFORE a byte of the bundle is emitted: stdout gets the header line naming what was withheld, never the artifact just rejected.

### `--help-task=TASK`

**Answers:** deterministic enhanced help: recommend ONE executable Ripwire CLI command for this repository and task, or abstain when evidence/applicability is insufficient.

Reports the intent, integer score/margin and repository facts; never calls a model, executes the recommendation, or accesses the network. Structured claims/traces/symbols outrank lexical cues. Recommendation only; pipe trace text to stdin for --from-trace=-.

**Try it**

_The honest half of the contract: a task with no ripwire-shaped evidence ABSTAINS with zero commands rather than guessing._

```
$ ./build/ripwire . --help-task="write a cheerful release announcement"
<task-route status="abstain" confidence="none" score="0" margin="0"><facts git="1" dirty="0" trace="0" resolved_symbols="0"/></task-route>
```

**Caveats (stated by the binary):**

- never calls a model, executes the recommendation, or accesses the network.

### `--for=TASK`

**Answers:** the task lens: ranked signatures + metrics framed for reuse.

The bundle enforces a ~7.5KB default payload budget (tail entries trim first; <sigs capped="1"> marks it) — an explicit --token-budget=N overrides the default at the conservative byte rate (SHAPES, exit 0; see --token-budget above) and the header reports the delivered est_tokens. TERMINAL BY DEFAULT: after the signatures, the top-ranked symbols' FULL bodies ride inline (CDATA + callee signatures, the --expand shape) under a fixed extra body allowance — whole-body-or-not-at-all, rank-first, capped at the --pack-task candidate cap (6). The <ctx> root discloses it: bundle="auto" bodies="N" (bodies="0" reason="budget" when none fit) — on EVERY auto-mode run: a ceiling the signatures alone exhaust still carries the attribute (legend and empty <bodies> shell dropped there; only the attribute has reserved bytes), and --for --json, which serves no bodies by design, says so with "bundle":"sigs". Only the caller-chosen postures (--signatures-only, --detail=N) are attribute-free. ANCHOR-ONLY when the route names one: a query that NAMES a symbol gets THAT symbol's own body or NO body — never a same-named doc section, type stub or re-export shim from another file standing in for it. If the anchor's own body does not fit, the bundle serves nothing and says so, and the per-item over-budget comment names what was dropped. COMPACT ON THE CONCEPTUAL ROUTE: a query that anchors nothing (subtoken+body) gets the ranked map plus a <hops> section — the same candidate head's ONE-HOP callee signatures, the <calls> block a body carries — and NO body CDATA, disclosed as bundle="compact" bodies="0" reason="compact-route". Read the map, then --expand=SYM the one you want. --auto-bodies restores the body walk there. That shape discloses on every run too: a ceiling the signatures alone exhaust carries bundle="compact" bodies="0" reason="budget" — three distinct reasons, never collapsed (compact-route = the route chose edges, no_candidates = nothing scored, budget = the ceiling was spent). An explicit --token-budget=N is a hard ceiling, split so a wider ceiling never buys less: the signature side's claim is capped at the DEFAULT ~7.5KB sig budget and every byte beyond it flows to the enrichment — at any ceiling at or above the default's effective total the <sigs> block is byte-identical to the default run's, so every body (or hop row) the default serves still fits. An explicit --pack-top-n is an explicit SIG posture and keeps the whole-ceiling sig claim. --compress composes: the served bodies (auto/anchor and --detail=N alike) go through the same comment-strip --expand uses, disclosed as compress="1" on the <bodies> element (nothing to strip on the compact route). RANKING CONFIDENCE, disclosed not scored: the <ctx> root always carries confidence="high|low" margin_pct="N" — derived from the SAME relevance-cliff gap statistic --adaptive cuts at (no new scorer, no behavior change; the --json dialect carries the same two keys). low means the ranking is FLAT (no material score cliff and more positive matches than the head shows) — treat the set as a starting point, not an answer; high means a material cliff inside the served head (margin_pct= is that drop as a whole percent) or every positive match already shown

**Try it**

_Name-shaped query: the router picks name-exact BM25 (header says which/why)._

```
$ ./build/ripwire . --for="rankGraphTeleport"
<ctx task="rankGraphTeleport" route=" [routed: name-exact BM25 — query names a symbol (rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)]" root="." bundle="auto" bodies="1">
<!-- ripwire lens for "rankGraphTeleport" [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced] [relevance floor: kept 3 of 40 - the other 37 scored zero on this query, so the bundle shrank instead of padding]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="1554" -->
<sigs>
<f p="src/graph.h">
<d l="2135" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="35" amp="116">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
</f>
<f p="docs/ARCHITECTURE.md">
<d l="234" n="The convergence disclosure contract" id="./docs/ARCHITECTURE.md::rank — Personalized PageRank::The convergence disclosure contract" cx="0" ccx="0" in="0" churn="8" amp="48">#### The convergence disclosure contract</d>
</f>
<f p="docs/EVALS.md">
<d l="2483" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" id="./docs/EVALS.md::6. Correctness and quality instruments::Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" cx="0" ccx="0" in="0" churn="237" amp="426">### Wave-2 adversarial … [line truncated: 63 more bytes on this line]
</f>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--token-budget`, `--signatures-only`, `--auto-bodies`, `--no-route`, `--adaptive`, `--no-mention-boost`, `--no-doc-mention`

**Caveats (stated by the binary):**

- <sigs capped="1"> marks it) — an explicit --token-budget=N overrides the default at the conservative byte rate (SHAPES, exit 0;
- TERMINAL BY DEFAULT: after the signatures, the top-ranked symbols' FULL bodies ride inline (CDATA + callee signatures, the --expand shape) under a fixed extra body allowance — whole-body-or-not-at-all, rank-first, capped at the --pack-task candidate cap (6).
- ANCHOR-ONLY when the route names one: a query that NAMES a symbol gets THAT symbol's own body or NO body — never a same-named doc section, type stub or re-export shim from another file standing in for it.

### `--signatures-only`

**Answers:** (with --for) opt out of the terminal-by-default bundle: no auto bodies, no bundle="auto" attribute — the signatures-only lens exactly as before.

Contradicts --detail=N (refused together); --detail=N remains the explicit body knob and supersedes the automatic pick

**Try it**

_T3 opt-out: the signatures-only lens (no auto bodies, no bundle="auto" attribute) — contrast with the terminal default above._

```
$ ./build/ripwire . --for="rankGraphTeleport" --signatures-only
<ctx task="rankGraphTeleport" route=" [routed: name-exact BM25 — query names a symbol (rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)]" root=".">
<!-- ripwire lens for "rankGraphTeleport" [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced] [relevance floor: kept 3 of 40 - the other 37 scored zero on this query, so the bundle shrank instead of padding]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="776" -->
<sigs>
<f p="src/graph.h">
<d l="2135" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="35" amp="116">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
</f>
<f p="docs/ARCHITECTURE.md">
<d l="234" n="The convergence disclosure contract" id="./docs/ARCHITECTURE.md::rank — Personalized PageRank::The convergence disclosure contract" cx="0" ccx="0" in="0" churn="8" amp="48">#### The convergence disclosure contract</d>
</f>
<f p="docs/EVALS.md">
<d l="2483" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" id="./docs/EVALS.md::6. Correctness and quality instruments::Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" cx="0" ccx="0" in="0" churn="237" amp="426">### Wave-2 adversarial … [line truncated: 63 more bytes on this line]
</f>
... [2 more line(s); run it to see the whole thing]
```

**Shaped by:** `--for`, `--auto-bodies`

**Caveats (stated by the binary):**

- Contradicts --detail=N (refused together);

### `--auto-bodies`

**Answers:** (with --for) opt out of COMPACT conceptual serving: restore the rank-first auto <bodies> walk on the subtoken+body route (bundle="auto", up to 6 full bodies) instead of the <hops> edge section.

Inert on the name-exact route, where the allowance already runs. Contradicts --signatures-only and --detail=N (refused with either)

**Shaped by:** `--for`

**Caveats (stated by the binary):**

- Inert on the name-exact route, where the allowance already runs.
- Contradicts --signatures-only and --detail=N (refused with either)

### `--no-route`

**Answers:** (with --for/--query) force plain subtoken+body BM25.

Routing is now the DEFAULT: a deterministic, confidence-gated query-shape router picks name-exact BM25 when the query NAMES a symbol (identifier syntax, or every content word is a symbol name) else subtoken+body, and prints which/why in the header. It only routes with a query (the plain map is unaffected). --no-route restores the old behavior. A name-exact header also names its EVIDENCE: anchors: word(defining/file) per anchoring word, +N when N further definitions share that name, or word(syntax) when the word routed on camel/snake SHAPE and names nothing. Paths deeper than two segments print top/.../basename. Discount a one-use test helper yourself. Routing also carries the QUERY-SHAPE document demotion: when the task text parses as a stack trace, sanitizer report or compiler diagnostic, or as a pasted issue-template form, the DOCUMENT tier scores down (repo meta-prose - issue templates, CONTRIBUTING, changelogs - twice as hard) and route= names the shape, its evidence and both factors. Demotion, never exclusion, and the mention anchor still lifts a document the task NAMES. --no-route has no route= to disclose it in, so it does not demote either.

**Try it**

_Same query with routing forced OFF (plain subtoken+body BM25) — contrast with the routed run._

```
$ ./build/ripwire . --for="rankGraphTeleport" --no-route
<ctx task="rankGraphTeleport" root="." bundle="auto" bodies="5">
<!-- ripwire lens for "rankGraphTeleport" [doc mentions: 4 docs discussing 3 top-ranked symbols surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="4865" -->
<sigs capped="1">
<f p="src/graph.h">
<d l="34" n="Graph" id="./src/graph.h::Graph::Graph" cx="0" ccx="0" in="0" churn="35" amp="110">struct Graph</d>
<d l="2098" n="biasPrior" id="./src/graph.h::rw::biasPrior" cx="5" ccx="4" in="1" churn="35" amp="111">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</d>
<d l="2126" n="RankedGraph" id="./src/graph.h::RankedGraph::RankedGraph" cx="0" ccx="0" in="0" churn="35" amp="110">
<doc>What a rank call hands back: the vector, and the power iteration&apos;s own account of itself. Struct…</doc>struct RankedGraph</d>
<d l="2135" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="35" amp="116">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quali…</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="2169" n="takeRank" id="./src/graph.h::rw::takeRank" cx="1" ccx="0" in="1" churn="35" amp="111">inline std::vector&lt;float&gt; takeRank( RankedGraph ranked, RankDisclosure&amp; disclosureOut )</d>
<d l="2176" n="rankGraph" id="./src/graph.h::rw::rankGraph" cx="2" ccx="1" in="9" churn="35" amp="119">
<doc>uniform-teleport PageRank (the default</doc>inline RankedGraph rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
... [17 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- Demotion, never exclusion, and the mention anchor still lifts a document the task NAMES.

### `--adaptive`

**Answers:** (with --for/--query) cut the result at the relevance CLIFF — the largest relative score gap (Adaptive-k), floor 5, ceiling = the existing top-k;

a sharp query returns few, a flat/broad one hits the ceiling. Prints [adaptive: kept K of N ...] in the header. Without it, output is unchanged.

**Try it**

_Cut the result at the relevance cliff (Adaptive-k)._

```
$ ./build/ripwire . --for="tree-sitter parse of a source file" --adaptive
<ctx task="tree-sitter parse of a source file" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]" root="." bundle="auto" bodies="4">
<!-- ripwire lens for "tree-sitter parse of a source file" [adaptive: kept 40 of 40 - no relevance cliff (broad query saturates the score); capped at the ceiling]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="4163" -->
<sigs capped="1">
<f p="src/ingest.h">
<d l="33" n="kDefaultMaxFileBytes" id="./src/ingest.h::rw::kDefaultMaxFileBytes" cx="0" ccx="0" in="0" churn="21" amp="48" pure="1">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="92" n="kMaxYamlNestDepth" id="./src/ingest.h::rw::kMaxYamlNestDepth" cx="0" ccx="0" in="0" churn="21" amp="48" pure="1">constexpr std::uint32_t kMaxYamlNestDepth = 64u</d>
<d l="266" n="AstQuerySpec" id="./src/ingest.h::AstQuerySpec::AstQuerySpec" cx="0" ccx="0" in="0" churn="21" amp="48">struct AstQuerySpec</d>
<d l="300" n="AstWalk" id="./src/ingest.h::rw::AstWalk" cx="0" ccx="0" in="0" churn="21" amp="48">enum class AstWalk : std::uint8_t</d>
<d l="441" n="SpanTier" id="./src/ingest.h::rw::SpanTier" cx="0" ccx="0" in="1" churn="21" amp="49">enum class SpanTier : std::uint8_t</d>
<d l="448" n="SpanTierMap" id="./src/ingest.h::SpanTierMap::SpanTierMap" cx="0" ccx="0" in="0" churn="21" amp="48">struct SpanTierMap</d>
</f>
<f p="src/ingest.cpp">
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--for`, `--detail`

**Caveats (stated by the binary):**

- (with --for/--query) cut the result at the relevance CLIFF — the largest relative score gap (Adaptive-k), floor 5, ceiling = the existing top-k;

### `--no-mention-boost`

**Answers:** (with --for) disable the query-mention anchor.

By DEFAULT, a file, dotted module, or Scope.symbol literally NAMED in the task text (a path, `pkg.module`, `Type.method` — even inside a URL) is lifted to just below the top hit; the header says what anchored. Inert (byte-identical) when the text names nothing indexed. RIPWIRE_NO_MENTION=1 disables it everywhere (incl. MCP `for`).

**Try it**

_Same task with the anchor disabled — the contrast the flag exists for._

```
$ ./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25" --no-mention-boost
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]" root="." bundle="auto" bodies="1">
<!-- ripwire lens for "why does src/lexical.h chooseForRanker pick name-exact BM25" [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="4773" -->
<sigs capped="1">
<f p="src/eval.h">
<d l="155" n="printEvalRankerNote" id="./src/eval.h::rw::printEvalRankerNote" cx="1" ccx="0" in="1" churn="9" amp="24">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="168" n="runEval" id="./src/eval.h::rw::runEval" cx="44" ccx="66" in="1" churn="9" amp="24">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="252" n="fileDir" id="./src/eval.h::rw::fileDir" cx="1" ccx="0" in="0" churn="9" amp="23">std::vector&lt;std::string&gt; fileDir( F )</d>
<d l="498" n="runEvalRetrieval" id="./src/eval.h::rw::runEvalRetrieval" cx="15" ccx="25" in="1" churn="9" amp="24">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="901" n="runEvalMined" id="./src/eval.h::rw::runEvalMined" cx="25" ccx="38" in="1" churn="9" amp="24">inline int runEvalMined( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; path )</d>
</f>
<f p="src/packtask.h">
<d l="42" n="LensRanking" id="./src/packtask.h::LensRanking::LensRanking" cx="0" ccx="0" in="0" churn="15" amp="35">
... [17 more line(s); run it to see the whole thing]
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
<ctx root="."><lego><iface n="Vehicle" p="test/legofix/vehicle.rs" methods="0" caveat="not-extracted-for-lang" implementors="2"><impl n="Car" p="test/legofix/vehicle.rs"/><impl n="Bike" p="test/legofix/vehicle.rs"/></iface></lego></ctx>
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
<!-- ripwire exemplar for "format byte sizes for humans" (task -> kind=fn, low-confidence: weak match, fell back to fn): the repo's best-in-class fn to imitate — chosen by ROLE, NEVER by text similarity to your task: candidates are first filtered to cognitive complexity at or under the ccx ceiling (4x the complexity bar), then ordered non-fixture path before test-fixture path, tested before untested, higher fan-in, lower complexity, fewer lines, lowest id. low_confidence=1 marks a weak task-to-kind match that fell back to fn; over_ccx_bar=1 marks a corpus where nothing was under the ceiling, so the pick is the least bad rather than a clean one; candidates= counts the ELIGIBLE instances of the kind (post-ceiling), not every instance. On the root, the three attributes that ARE that ordering's evidence: in=reuse-count (callers), ccx=cognitive complexity, tested=1 when a test reaches it (OMITTED, never 0, when none does). The body follows in a bodies section, its callee signatures in a calls child; both disclose truncation the house way: total= is how many qualified, shown= how many are printed, capped=1 when the two differ (calls omits shown= and capped= when its list is complete). Copy its shape, not its text. -->
<exemplar kind="fn" candidates="6215" n="min" p="src/infra/fastmath.h:51" in="110" ccx="1" root="." tested="1" low_confidence="1">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="51" p="src/infra/fastmath.h" n="min">
<![CDATA[[[nodiscard]] ALWAYS_INLINE constexpr T min( T a, T b ) noexcept { return b < a ? b : a; }]]>
</b>
</bodies>
</exemplar>
```

**Shaped by:** `--compress`, `--metrics`, `--json`, `--index-out`

### `--recall=TASK`

**Answers:** recall the most relevant DOCS — memory/plans/designs, full bodies (md, .ipynb/.html/.csv, plus Office/PDF via the optional markitdown bridge).

This is the tool's LARGEST output: its header reports est_tokens + total=/shown=/capped=, where total= is the TRUE relevant count (score > 0) and shown= is what this run actually emitted. The header's "of N document files" denominator counts every file the index carries as a DOCUMENT — .md plus the docparse'd .ipynb/.html/.csv — so it is a SUPERSET of --doc-drift's docs=, which is an extension test (markdown only). Two populations, two names, deliberately. --top-k=N shapes HOW MANY docs are emitted (default 8, not the general --top-k default of 200). Recall defaults to an 8000-token body ceiling; --max-tokens=N overrides it and shapes to fit (disclosing each cut), while --token-budget=N gates the finished artifact (exit 3, nothing streamed). GENERATED documents rank LAST by default — a doc that declares itself generated in its first lines, or is BOTH >=5x the median doc's size AND mostly ```-fenced quoted output (a capture/API dump quotes every term, so BM25 hands it every query). Never dropped: it still wins when nothing else matches. Each one says [generated_demoted: marker|size+fences] on its own line and the header tallies generated_demoted=N

**Try it**

_Most relevant DOCS' full bodies (markdown only) — recall what is already written down._

```
$ ./build/ripwire . --recall="quality delta gating exit codes"
ripwire recall — "quality delta gating exit codes" — 72 relevant of 138 document files, best-first — total=72 shown=8 capped=1 generated_demoted=1 est_tokens=80494

━━ ./skills/ripwire-quality-bar/SKILL.md  (relevance 6.614) ━━  [sections: 8 of 10, section-granular; whole doc 28422 B; lines="54-137,138-223,224-252,253-273,274-305,306-315,316-326,327-332"]
## Before you converge: the wide-angle read — `--quality-panel`

`ripwire <dir> --quality-panel[=strict|default|lenient]` is THE SINGLE COMMAND for "does what I just
touched still look rotten" — one ranked report over **six** evidence families (the four `--ensemble`
joins — `structural`, `lexical`, `confusion`, `historical` — plus `colocation` and `state`; the full
per-family breakdown lives in **ripwire-fresh-eyes**). Point it at the file or symbol you just edited for
a multi-angle second opinion the single `--quality-delta` number can't give you on its own.

**Read it correctly: it is a lens, never a gate.** `--help` says so in the flag's own text and the
contract is enforced in code — `--quality-panel` exits 0 unconditionally, on every preset, on every repo.
It does not compare against a baseline and it cannot fail a commit. The gate for "did MY change make this
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
<!-- ripwire tree: each file + its top symbols by rank, files ordered by their best symbol's rank (path breaks ties) — a session-start orientation map. files= is the indexed corpus; rows list files WITH symbols; files_unlisted= holds the symbol-less remainder — files equals files_unlisted plus the LISTABLE file set, which is what the rows below enumerate before any paging window is applied; under explicit paging (limit=/offset=) that listable count is emitted as total= and shown= says how many of it these rows are. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<tree files="1329" files_unlisted="67" pr_iters="32" root=".">
<file p="src/infra/svector.h" symbols="68">
<s t="method" n="size"/>
<s t="method" n="buf"/>
<s t="method" n="buf"/>
</file>
<file p="src/notes.h" symbols="25">
<s t="method" n="empty"/>
<s t="method" n="find"/>
<s t="fn" n="sortNotes"/>
</file>
<file p="src/scipoverlay.h" symbols="6">
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

**Shaped by:** `--color-by`

### `--color-by=MODE`

**Answers:** (with --html) node colour: lang (default) | community | cx | churn | tested — the page embeds all five and keeps a live selector;

the flag only sets the initial mode

### `--order=MODE`

**Answers:** emit order: stable (path/id order — provider KV-cache hits across re-runs) | important-first (rank order, the default;

no auto-flip) | important-last (highest-rank content emitted last — recency bias for an LLM). Large default maps auto-flip to important-last past ~50% of a nominal 32K window (est_tokens>16000) unless MODE is explicitly given.

**Try it**

_Stable (path/id) emit order — provider KV-cache hits across re-runs._

```
$ ./build/ripwire . --order=stable --top-k=5
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<r root="." pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2">
</s>
<s t="method" n="size" id="./src/infra/svector.h::svector::size">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty">
</s>
</f>
... [6 more line(s); run it to see the whole thing]
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
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- files=1329 symbols=11493 edges=14084 shown=211 est_tokens=26091 ambiguous=5555 unresolved=3233 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:18,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="26091">
<f p="src/graph.h">
<s t="fn" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" amb="6" k="1.0000">
<c n="biasPrior"/>
<c n="PROFILE_SCOPE_DESCRIBE"/>
<c n="PROFILE_SCOPE_DESCRIBE"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
<c n="end"/>
<c n="size"/>
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
<!-- ripwire callers/callees: the 1-hop call hierarchy read straight off the call graph. The callers form lists the symbols that CALL of=; the callees form lists the symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS that name resolved to (the rows UNION every def's neighbours), and count= the number of DISTINCT neighbour symbols (a floor, per counts_floor=), which the rows window with limit= and offset=. A neighbour that is an indexed function-like #define is a macro row (t="macro", role="macro" on the XML row): the edge crosses a macro expansion, not a plain call — rows carry no role= otherwise. Rows are ordered SOURCE first, then test/bench, then docs, and by path within a tier. When emitted by callees, bodyless_defs= (when present) counts how many of the defs= are declarations with no body (header-only or forward-declared); zero callees may mean no body to read callees from rather than truly no dependencies. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<callees of="rankGraphTeleport" defs="1" count="9" root="." counts_floor="1">
<s t="fn" n="biasPrior" p="src/graph.h:2098"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1322" role="macro"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1336" role="macro"/>
<s t="method" n="begin" p="src/infra/svector.h:269"/>
<s t="method" n="end" p="src/infra/svector.h:270"/>
<s t="method" n="begin" p="src/infra/svector.h:271"/>
<s t="method" n="end" p="src/infra/svector.h:272"/>
<s t="method" n="size" p="src/infra/svector.h:285"/>
<s t="fn" n="pageRankDouble" p="src/pagerank.cpp:95"/>
</callees>
```

**Shaped by:** `--impact`, `--exercises`, `--rank-by`, `--json`

**Caveats (stated by the binary):**

- file:name disambiguates like --callers

### `--uses=SYM`

**Answers:** the statically resolvable use-sites of SYM (role=call|macro|read|write|import|extends|type, file:line);

external="1" if SYM has no in-corpus def. file:name narrows defs= AND the role="call" sites (kept only where the call RESOLVES to a chosen def — --callers' own narrowing); read/write/import/extends carry no resolution and stay name-matched. narrowed_roles=/defs_of_name=/call_sites_of_name= (file: qualifier only) disclose what narrowed and the un-narrowed totals; a file: qualifier naming a file with no such def REFUSES, like --callers/--impact

**Try it**

_The resolvable use-sites (call/read/write/import/extends) with file:line; count= is a floor._

```
$ ./build/ripwire . --uses=rankGraphTeleport
<!-- ripwire uses: the STATICALLY RESOLVABLE use-sites of SYM (role=call|macro|read|write|import|extends|type; p=file:line) — a floor, see counts_floor below. That role list is the whole vocabulary. role="type" is a bare TYPE mention — SYM named as a type in a signature, a declaration or a template argument — and it carries no call edge: a type dependency is real, but it is not an invocation, so it never reaches the call graph, PageRank or the ranked map. It is captured for C/C++/ObjC only, and only where the type is spelled as a plain leaf name, so a mention written through a qualified or aliased spelling still contributes no row. A base clause is role="extends" rather than role="type" (that relation is modelled separately), and a type's own DEFINITION is never a use of itself. role="macro" is the call-shaped invocation of a name that uniquely names an indexed function-like #define — never labelled role="call", because an expansion is not a plain call; a name shared with a non-macro definition stays role="call" for the resolver. Rows are ordered SOURCE first, then test/bench, then docs, and by path within a tier. Reference-name-based (same heuristic level as call edges) — verify in source if a name is overloaded. external="1" ⇒ SYM has no definition in the indexed tree under ANY spelling (stdlib/third-party) — never merely none in the file you qualified with (that spelling refuses instead). A "file:name" SYM narrows defs= AND the role="call" sites, which are kept only where the call RESOLVES to a chosen def (the callers verb's own narrowing, read the other way, so the two agree); read/write/import/extends carry no resolution and stay name-matched across every def sharing the name. narrowed_roles= names what narrowed, and defs_of_name=/call_sites_of_name= (file: qualifier only) are the un-narrowed totals. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<uses of="rankGraphTeleport" defs="1" external="0" count="9" root="." counts_floor="1">
<u role="call" p="src/eval.h:322" in_id="./src/eval.h::rw::runEval"/>
<u role="call" p="src/graph.h:2179" in_id="./src/graph.h::rw::rankGraph"/>
<u role="call" p="src/graph.h:2556" in_id="./src/graph.h::rw::anchoredLexicalRank"/>
<u role="call" p="src/main.cpp:12948" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:12949" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:12959" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:12965" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:13136" in_id="runDefaultMap"/>
<u role="call" p="src/mcpindex.h:1041" in_id="./src/mcpindex.h::rw::getIndex"/>
</uses>
```

**Shaped by:** `--impact`, `--naming-consistency`, `--edit-check`, `--safe-delete`, `--rank-by`, `--json`, `--index-out`

**Caveats (stated by the binary):**

- a file: qualifier naming a file with no such def REFUSES, like --callers/--impact

### `--graph-query=EXPR`

**Answers:** composable node-set query over the call graph: sources name("X")/all;

filters kind|cx|fanin|file|layer; bounded closure callers|callees(SET[,depth]); joins and|or|not.  e.g. and(callers(name("foo"),2),kind(all,fn)); file() regex example: file("src/.*\\.cpp") (or in bash, use single quotes: file('src/.*\.cpp')) layer(SET,NAME) keeps the architecture layer NAME (game|infra|render|math|audio|ai|test) — the SAME built-in directory-name taxonomy the map prints as layer= on a file node, so the two cannot disagree. It does NOT read a --arch=FILE rules file: --arch is a verb and outranks --graph-query, so the two never run together. An unknown layer word, or ANY layer() against a tree where no path names a layer, is REFUSED (exit 1) rather than answered count="0" — 0 there would read as "no such code". a name("X") literal matching NO indexed symbol refuses with a did-you-mean (a typo is not a count=0); a query whose names all resolve but that selects nothing still reports count="0" — that IS a measurement (including a VALID layer with no members in a tree that does have layers). Ranked result set is capped at --top-k (default 200); --limit overrides that cap (raise or lower it), --offset pages past it — see --limit=N --offset=M above

**Try it**

_Composable node-set query: functions within 2 caller-hops of rankGraphTeleport._

```
$ ./build/ripwire . --graph-query='and(callers(name("rankGraphTeleport"),2),kind(all,fn))'
<!-- ripwire graph-query: a fixed-operator node-set query over the call graph (sources name/all; filters kind/cx/fanin/file/layer; bounded closure callers/callees; joins and/or/not), ranked by importance + capped at the top-k limit (default 200); narrow the query or raise top-k for more. NOT Datalog. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<query expr="and(callers(name(&quot;rankGraphTeleport&quot;),2),kind(all,fn))" count="45" shown="45" capped="0" counts_floor="1" root="." pr_iters="32">
<s t="fn" n="getIndex" p="src/mcpindex.h:950"/>
<s t="fn" n="emitCommunitiesReport" p="src/main.cpp:10078"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:2512"/>
<s t="fn" n="emitCommunityDrill" p="src/main.cpp:10238"/>
<s t="fn" n="rankGraph" p="src/graph.h:2176"/>
<s t="fn" n="computeLensRanking" p="src/main.cpp:2317"/>
<s t="fn" n="fetchBody" p="src/mcpverbs.h:3020"/>
<s t="fn" n="runEvalRetrieval" p="src/eval.h:498"/>
<s t="fn" n="runEvalMined" p="src/eval.h:901"/>
<s t="fn" n="dispatchMcpLine" p="src/mcp.h:499"/>
<s t="fn" n="fetchBodyByName" p="src/mcpverbs.h:2951"/>
<s t="fn" n="symbolQueryJson" p="src/mcpverbs.h:474"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--exercises`, `--json`

**Caveats (stated by the binary):**

- file() regex example: file("src/.*\\.cpp") (or in bash, use single quotes: file('src/.*\.cpp')) layer(SET,NAME) keeps the architecture layer NAME (game|infra|render|math|audio|ai|test) — the SAME built-in directory-name taxonomy the map prints as layer= on a file node, so the two cannot disagree.
- It does NOT read a --arch=FILE rules file: --arch is a verb and outranks --graph-query, so the two never run together.
- An unknown layer word, or ANY layer() against a tree where no path names a layer, is REFUSED (exit 1) rather than answered count="0" — 0 there would read as "no such code".

### `--external-surface`

**Answers:** names referenced but never defined in-corpus (the stdlib/third-party surface), by ref count;

each row's lang= is the REFERENCING file's language — a name called from several languages (e.g. printf: C stdio call vs Bash builtin) gets one row PER language, not a merged count

**Try it**

_Names referenced but never defined in-corpus (stdlib/third-party surface). NOW carries names/shown/capped (total= joins them only under --limit/--offset)._

```
$ ./build/ripwire . --external-surface
<!-- ripwire external-surface: names CALLED/IMPORTED/EXTENDED but never defined in the indexed tree = the stdlib/third-party surface the code depends on (refs=use-sites, calls=of-which-calls) -->
<external-surface names="1319" shown="1319" capped="0">
<x n="grep" lang="sh" refs="5864" calls="5864"/>
<x n="printf" lang="sh" refs="5009" calls="5009"/>
<x n="echo" lang="sh" refs="4472" calls="4472"/>
<x n="exit" lang="sh" refs="1692" calls="1692"/>
<x n="head" lang="sh" refs="1202" calls="1202"/>
<x n="cat" lang="sh" refs="1055" calls="1055"/>
<x n="cd" lang="sh" refs="928" calls="928"/>
<x n="c_str" lang="cpp" refs="852" calls="852"/>
<x n="tr" lang="sh" refs="847" calls="847"/>
<x n="string" lang="cpp" refs="754" calls="754"/>
<x n="fprintf" lang="cpp" refs="743" calls="743"/>
<x n="python3" lang="sh" refs="652" calls="652"/>
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
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<path from="main" to="rankGraphTeleport" from_p="src/main.cpp:14473" to_p="src/graph.h:2135" from_defs="71" to_defs="1" reachable="1" hops="2" root=".">
<s t="fn" n="main" p="src/main.cpp:14473"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:13039"/>
<s t="fn" n="rankGraphTeleport" p="src/graph.h:2135"/>
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
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<connect terminals="3" nodes="3" edges="2" radius="6" groups="1" est_tokens="352" root=".">
<g terminals="3">
<t n="runEval" t="fn" p="src/eval.h:168"/>
<t n="rankGraphTeleport" t="fn" p="src/graph.h:2135"/>
<t n="getIndex" t="fn" p="src/mcpindex.h:950"/>
<e f="runEval" t="rankGraphTeleport"/>
<e f="getIndex" t="rankGraphTeleport"/>
</g>
</connect>
```

**Shaped by:** `--from-trace`, `--json`

### `--impact=SYM`

**Answers:** transitive blast radius — the indexed symbols that reach SYM (a floor, see counts_floor).

file:name disambiguates like --callers importers= is a SECOND, weaker reach beside it: the files that directly include/import a file defining SYM, emitted as <f via="import" lazy="0|1"> rows (format=columnar carries the count only). NEVER added to reaches= — files and symbols are different units, and an importer may use a different symbol from that file, or none at all. lazy="1" (TS/JS only): every one of that importer's edges is a require()/import() written inside a function body, not at module load time — still a real dependency, weaker than a top-level one counts_floor="1"           on --callers/--callees/--uses/--impact/--edit-check every count is a FLOOR, never a total: the call graph is extracted from source text by name, so dynamic dispatch and declarations that parse without a call expression (C++ most-vexing-parse) contribute no edge; a call through a function pointer/callback is an edge only when ONE function is bound to that variable in scope (reassigned/table-indexed/lambda-bound/escaped — address-taken or reference-bound — pointers stay edge-less, C-family); a macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (t="macro"); a shared name stays a plain call, an unindexed macro's site is no edge. Read a 0 as "none found", never as "none exists". Those five verbs also count DISTINCT (caller,callee) pairs, while --uses counts call SITES — see each verb's own legend pr_iters="N"               on every PageRank-ordered document (the map, and the tree, seams, communities, zoom, impact, graph-query and exercises verbs, plus their MCP twins): how many power iterations produced that ordering. The iteration stops when the L1 residual between successive rank vectors falls below tolerance, or at a fixed iteration ceiling, whichever comes first. pr_converged="0" is emitted ONLY on that second exit and means the ranking is a rank vector that stopped SHORT of tolerance, not the fixed point it approximates. ABSENCE MEANS IT CONVERGED (there is no pr_converged="1": the converged path is the normal one and must cost zero bytes), and absence of pr_iters= itself means the document was not ordered by a power iteration at all (a lexical query score, or a hub or authority HITS vector), never that the count is unknown

**Try it**

_Transitive blast radius — everything that reaches SYM. NOW carries shown/capped._

```
$ ./build/ripwire . --impact=rankGraphTeleport
<!-- ripwire impact: transitive blast radius — symbols that reach SYM via calls (review before changing SYM). raise the default cap with limit=N (offset=M pages); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<impact of="rankGraphTeleport" defs="1" reaches="51" root="." shown="40" capped="1" counts_floor="1" pr_iters="32">
<s t="fn" n="getIndex" p="src/mcpindex.h:950"/>
<s t="fn" n="emitCommunitiesReport" p="src/main.cpp:10078"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:2512"/>
<s t="fn" n="emitCommunityDrill" p="src/main.cpp:10238"/>
<s t="fn" n="rankGraph" p="src/graph.h:2176"/>
<s t="fn" n="computeLensRanking" p="src/main.cpp:2317"/>
<s t="fn" n="fetchBody" p="src/mcpverbs.h:3020"/>
<s t="fn" n="runEvalRetrieval" p="src/eval.h:498"/>
<s t="fn" n="runEvalMined" p="src/eval.h:901"/>
<s t="fn" n="dispatchMcpLine" p="src/mcp.h:499"/>
<s t="fn" n="fetchBodyByName" p="src/mcpverbs.h:2951"/>
<s t="fn" n="symbolQueryJson" p="src/mcpverbs.h:474"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--uses`, `--metrics`, `--safe-delete`, `--rank-by`, `--json`

**Caveats (stated by the binary):**

- transitive blast radius — the indexed symbols that reach SYM (a floor, see counts_floor).
- file:name disambiguates like --callers importers= is a SECOND, weaker reach beside it: the files that directly include/import a file defining SYM, emitted as <f via="import" lazy="0|1"> rows (format=columnar carries the count only).
- NEVER added to reaches= — files and symbols are different units, and an importer may use a different symbol from that file, or none at all.

### `--verify="CLAIM"`

**Answers:** VERIFY A CLAIM about the code in ONE call: a CLOSED claim language in, a three-valued verdict out (confirmed / refuted / not-established) with the evidence rows inline — the collapse of the manual verification grep-chain.

Shapes: calls(A,B) does A transitively call B; uses(SYM) / unused(SYM) is SYM referenced anywhere / nowhere; contains(FILE, "LIT") do FILE's indexed bytes contain the literal; defines(FILE, SYM) does FILE define SYM; reaches(SYM, "FILE"|LAYER) does code in that file/layer transitively call SYM (LAYER unquoted: game|infra|render|math|audio|ai|test). refuted appears ONLY with complete evidence: a clean literal-scan absence carries complete=, and an unused claim is refuted by printed witness sites. A graph or reference ZERO can never refute — it yields not-established with limit= naming the floor (call-graph-floor, reference-floor, collection-ceiling, scan-degraded, extraction-floor); see counts_floor above for why. An unknown shape refuses loudly with the whole vocabulary; SYM takes the shared selector grammar (name, file:name, canonical id), FILE is a path substring

**Caveats (stated by the binary):**

- A graph or reference ZERO can never refute — it yields not-established with limit= naming the floor (call-graph-floor, reference-floor, collection-ceiling, scan-degraded, extraction-floor);
- see counts_floor above for why.
- An unknown shape refuses loudly with the whole vocabulary;

### `--mentions=SYM`

**Answers:** markdown docs (plans/designs) that name SYM in a `backtick` (doc↔code) the pre-PR family — plumbing (--affected) to mid-task report (--situ) to gate (--test-gate):

**Try it**

_Markdown docs that name SYM in a backtick (doc<->code edges)._

```
$ ./build/ripwire . --mentions=rankGraphTeleport
<!-- ripwire mentions: markdown FILES that name this symbol in a `backtick` (doc<->code; NOT a call edge). docs= is the row count (distinct files); sections= counts the underlying markdown-section mentions before file-collapse (docs <= sections). Each row's mentions= is its own section-mention count. No line locator: the doc edge is stored at file granularity — a fabricated always-1 l= was removed; absent beats fake -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<mentions of="rankGraphTeleport" defs="1" docs="2" sections="2" root=".">
<doc p="docs/ARCHITECTURE.md" mentions="1"/>
<doc p="docs/EVALS.md" mentions="1"/>
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
<affected changed="src/graph.h" seeded_by="file" seeds="113" tests="6" reached="557" script_gates_unmodelled="468">
<test p="./test/cloneband_harness.cpp" run="bash test/clonebandcheck.sh"/>
<test p="./test/clonelex_harness.cpp" run="bash test/clonelexcheck.sh"/>
<test p="./test/connectcore_harness.cpp" run="bash test/connectcorecheck.sh"/>
<test p="./test/includeprecise_unit.cpp" run="bash test/includeprecisecheck.sh"/>
<test p="./test/rustimport_unit.cpp" run="bash test/rustimportprecisecheck.sh"/>
<test p="./test/type3clone_harness.cpp" run="bash test/type3clonecheck.sh"/>
</affected>
```

**Shaped by:** `--mentions`, `--exercises`, `--test-gate`, `--edit-target-file`

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
<!-- ripwire exercises: the NON-TEST symbols this test transitively calls into — what it covers (the inverse of the affected verb). <t> = the seed test files the pattern matched; <s> = the covered symbols, PageRank desc. harness=script|mixed says the seed set contains shell gates, whose subprocess coverage this walk cannot see. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<exercises of="test/regression.sh" seed_files="1" shown_seed_files="1" seed_files_capped="0" test_symbols="3" reaches="0" harness="script" note="a shell gate invokes the compiled binary as a subprocess; script-to-binary edges are not modelled, so reaches= counts call-graph reach only and cannot see  … [line truncated: 72 more bytes on this line]
<t p="test/regression.sh"/>
</exercises>
```

**Shaped by:** `--test-gate`, `--json`

**Caveats (stated by the binary):**

- Ranked by PageRank, capped at 40 rows (raise with --limit;

### `--situ[=F1,F2]`

**Answers:** situational awareness for a change: blast radius + tests + co-change (default = git diff)

**Try it**

_Mid-task situational report for the current git diff — recorded against a CLEAN tree (contrast with the sandbox run below)._

```
$ ./build/ripwire . --situ
ripwire situational-awareness — 0 changed file(s), 0 symbols in them
root: .
  (no indexed symbols in the changed files — nothing to analyze)
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

_Pre-PR gate on a CLEAN tree: no obligations, exit 0._

```
$ ./build/ripwire . --test-gate
<!-- ripwire test-gate (TDAD-parity, arXiv 2603.17973): the tests to run for this change + the UNTESTED blast radius. A queryable call-graph+test map cut agent-caused regressions -70% (6.08%->1.82%); this gate names the obligations, the agent runs the tests then relies on green. exit 4 if tests OR untested is non-empty. TWO INDEPENDENT LISTINGS, each with its own row count: shown_tests= counts the <t> tests-to-run rows and shown_untested= counts the <u> blast-radius rows (a single shown= could only ever have described one of them). The <t> rows are the COMPLETE obligation and are never windowed, so they REPEAT VERBATIM on every page — a walker that concatenates pages must take them from one page only; offset=/limit= window the <u> rows alone. The <u> listing shows 25 rows by default: raise the default cap with limit=N (offset=M pages). script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) - script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=. UNIT: untested= here counts impacted SYMBOLS. The seams verb spells untested= over cross-directory call EDGES and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. -->
<test-gate changed="0" impacted="0" tests="0" untested="0" shown_tests="0" tests_capped="0" shown_untested="0" untested_capped="0" script_gates_unmodelled="468" at="061dcf667">
</test-gate>
```

**Shaped by:** `--mentions`, `--affected`, `--quality-delta`, `--json`

**Caveats (stated by the binary):**

- NO run= means NOT DERIVABLE -- never a guessed suite command

### `--grep=STR | --regex=PAT`

**Answers:** literal / regex search + enclosing symbol + the matched line.

SPAN-TIERED by default (see --grep-in below): the scan itself is exhaustive, the ANSWER serves one tier and discloses what it held back. --grep-in=any is the exhaustive VIEW -- every hit, no tiering. For task-ranked retrieval use --for=TASK (ranks by PageRank + task relevance). --grep-context=N | --grep-before=N / --grep-after=N   ripgrep-style N lines of source around each hit --and=STR (repeatable)   modifies --grep=STR: keep only hits where STR is ALSO present (literal-only, no --regex) --not=STR (repeatable)   modifies --grep=STR: drop hits where STR IS present (literal-only, no --regex)

**Try it**

_Regex search + enclosing symbol._

```
$ ./build/ripwire . --regex='fnv1a\w+'
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), matched text (m) and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached). SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. raise the default cap with limit=N (offset=M pages); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="fnv1a\w+" root="." files="17" hits="69" shown="69" capped="0" hits_capped="0" suppressed_comment="37" suppressed_string="10" tier_parsed="25" corpus_oversize="15" unindexed_files_scanned="104" unindexed_files_skipped="1">
<f p="src/arch.h">
<hit l="507" in="rw::fnv1a64">
<m>
<![CDATA[inline std::uint64_t fnv1a64( std::string_view s ) noexcept]]>
</m>
</hit>
<hit l="512" in="rw::fnv1a64">
<m>
<![CDATA[        h = hashutil::fnv1aAbsorb( h, c );]]>
</m>
</hit>
<hit l="585" in="rw::archViolHash">
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--grep-scope`, `--handles`, `--expand`, `--no-redact`, `--insert-after-symbol`, `--legend`, `--json`

### `--grep-scope=line|file`

**Answers:** modifies --and=/--not=: line (default) requires the SAME matched line;

file requires anywhere in the same file. Second occurrence of --grep=/--regex= itself REFUSES (naming --and= as the AND spelling) rather than silently overwriting the pattern.

**Caveats (stated by the binary):**

- Second occurrence of --grep=/--regex= itself REFUSES (naming --and= as the AND spelling) rather than silently overwriting the pattern.

### `--grep-in=code|any`

**Answers:** SPAN TIERS: which tree-sitter span a hit must sit in to print.

code (default) serves the CODE tier when any hit is code, and otherwise comment AND string TOGETHER (tier= "comment+string"), disclosing what it held back (suppressed_comment=/suppressed_string=); a pattern living only in prose is still answered, never silently emptied. any turns tiering off entirely -- the exhaustive view. Hit files are parsed on demand under a fixed budget; tier_budget= says so when it stops, and hits it never classified are emitted, never suppressed.

**Shaped by:** `--grep`

**Caveats (stated by the binary):**

- a pattern living only in prose is still answered, never silently emptied.
- tier_budget= says so when it stops, and hits it never classified are emitted, never suppressed.

### `--handles`

**Answers:** (with --grep/--regex) add h= to each unique editable enclosing-symbol row: a stable identity plus the file-content hash pinned when grep ran.

Ambiguous or document-only rows get no handle; a later edit must refuse after any file change rather than retarget stale coordinates.

**Shaped by:** `--insert-after-symbol`

**Caveats (stated by the binary):**

- Ambiguous or document-only rows get no handle;
- a later edit must refuse after any file change rather than retarget stale coordinates.

### `--match=QUERY`

**Answers:** tree-sitter structural (shape) query

**Try it**

_Tree-sitter structural query WITHOUT a capture — a bare node query gets a capture AUTO-ADDED (auto_captured="1") instead of silently matching nothing._

```
$ ./build/ripwire . --match='(if_statement)'
<!-- ripwire match: tree-sitter structural query; each hit = a captured node + its enclosing symbol. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (engine match limit reached). auto_captured="1" ⇒ the query bound no @capture and ripwire appended `@m` to its single top-level pattern. grammars= names every grammar the query compiled against; eligible_files=/of_files= are corpus files in that language set vs total indexed files. raise the default cap with limit=N (offset=M pages) -->
<match hits="5000" shown="100" capped="1" hits_capped="1" auto_captured="1" grammars="cpp,c,python,go,typescript,swift,objc,javascript,bash,java,csharp,php,lua" eligible_files="1087" of_files="1329" root=".">
<m p="bench/agentloop/analyze.py:37" in="load_results">if data.get( "schema" ) != SCHEMA:         raise SystemExit( f"{path}: unexpected schema {data.get('schema')!r} (expecte</m>
<m p="bench/agentloop/analyze.py:48" in="load_results">if not str( data.get( "tasks_lock_content_sha256", "" ) ).startswith( "questions:" ):         train_repos = select_tasks</m>
<m p="bench/agentloop/analyze.py:50" in="load_results">if train_repos:             raise SystemExit(                 f"{path}: records from repo(s) that re-derive to LocBench </m>
<m p="bench/agentloop/analyze.py:72" in="pair_by_task_seed">if base and ctx and base["status"] == "ok" and ctx["status"] == "ok":             paired.append( ( instance_id, base["re</m>
<m p="bench/agentloop/analyze.py:101" in="clustered_bootstrap_lower">if not repos: return 0.0, []</m>
<m p="bench/agentloop/analyze.py:117" in="loc_hit_delta">if base["localization_hit"] is None or ctx["localization_hit"] is None: return 0.0</m>
<m p="bench/agentloop/analyze.py:126" in="paired_ratio">if bv: ratios.append( cv / bv - 1 )</m>
<m p="bench/agentloop/analyze.py:127" in="paired_ratio">if not ratios: return None, None</m>
<m p="bench/agentloop/analyze.py:144" in="substitution_rate">if rw is None or native is None:         return None</m>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-redact`, `--sarif`, `--json`

### `--pattern=PAT`

**Answers:** structural search written in CODE, not in node kinds: --pattern='foo($X, ...)'.

$NAME binds one node (repeat it and both sites must match structurally); $_ binds nothing; ... (or $$$) is an ellipsis over siblings, matched by ONE first-match-wins probe under a hard cap -- both facts on the element. Comments are transparent, everything else is kind- and text-exact ($A + $B does not match a - b). Served: c cpp objc java csharp javascript typescript python go rust swift; ruby, bash and the data tiers are named in unsupported= instead of answered. A pattern no served grammar resolves, or that collapses to a bare token, is REFUSED -- never reported as hits=0.

**Shaped by:** `--json`

**Caveats (stated by the binary):**

- A pattern no served grammar resolves, or that collapses to a bare token, is REFUSED -- never reported as hits=0.

### `--query=TERMS`

**Answers:** raw BM25 ranking (debug);

use --for

**Try it**

_Raw BM25 ranking (debug lens; --for is the real verb)._

```
$ ./build/ripwire . --query="teleport pagerank" --top-k=5
<!-- routed: subtoken+body BM25 (-for's default) — no strong name hit; broad query, plain rg may also win -->
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- files=1329 symbols=11493 edges=14084 shown=5 est_tokens=777 ambiguous=5555 unresolved=3233 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:18,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="777">
<f p="src/main.cpp">
<s t="fn" n="churnRankedGraph" amb="4" k="13.8138">
<c n="resolveSinceScope"/>
<c n="churnTeleport"/>
<c n="churnTeleportWorkspace"/>
<c n="churnDecayTeleport"/>
<c n="churnDecayTeleportWorkspace"/>
<c n="churnWindowStamp"/>
<c n="rankGraphTeleport"/>
... [17 more line(s); run it to see the whole thing]
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
<ctx task="pagerank power iteration" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]" root=".">
<!-- ripwire lens for "pagerank power iteration" [doc mentions: 4 docs discussing 3 top-ranked symbols surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="4606" -->
<sigs capped="1">
<f p="scripts/optremarks.py">
<d l="40" n="HOT_FILES" cx="0" ccx="0" in="0" churn="3" amp="37">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix entry points &quot;src/infra/radixSort…</d>
</f>
<f p="src/prconverge.h">
<d l="51" n="RankDisclosure" id="./src/prconverge.h::RankDisclosure::RankDisclosure" cx="0" ccx="0" in="0" churn="2" amp="17">
<doc>What a ranked document discloses about the power iteration that ordered it. `isPageRank == false…</doc>struct RankDisclosure</d>
<d l="73" n="renderDisclosure" id="./src/prconverge.h::rw::renderDisclosure" cx="12" ccx="15" in="10" churn="2" amp="27">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
</f>
<f p="src/graph.h">
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--for`, `--signatures-only`, `--auto-bodies`, `--compress`, `--owners`, `--plan`, `--abi`, `--flip`

### `--pack-signatures`

**Answers:** body-elided decl skeletons — ~59-68% fewer element bytes than the same symbols' full --expand bodies (68% at the top-50 sigs payload cap — the sigs payload is top-50 whatever --top-k is set to, and --top-k's own default is 200), measured at top-10/50/100 on this repo with the corpus-root prefix subtracted from both sides: that prefix repeats inside every element, is charged in both forms, and is not what this elides — count it and the figure becomes a function of how deep your checkout sits (the same corpus reads 60% from a relative root and 41% from a 130-byte absolute one).

The share RISES with the result size. Like the --format=columnar sibling, a small result can invert it — a signature plus its doc comment can be bigger than a short body.

**Try it**

_Body-elided decl skeletons — recounted on this corpus. Measured as element bytes: the <d> signature+doc elements --pack-signatures emits, against the SAME symbols' full <b> bodies from --expand, with the CORPUS-ROOT PREFIX SUBTRACTED FROM BOTH SIDES. That subtraction is the whole methodology and the figure is meaningless without it: the root repeats inside every element's id= and p=, it is not what this verb elides, and counting it makes the headline a function of how deep the checkout happens to sit on disk — on one corpus, three spellings of the same root read 18.6 points apart before the subtraction and agree exactly after it. Root-neutralised on THIS repo: 86.5% fewer bytes at top-10, 81.4% at top-50, 81.6% at top-100 (V1, 2026-08-15: --expand's <b> bodies now carry sibs=/inc= file-context attributes — see docs/COMMANDS.md's --expand entry — which grows the body side of this ratio and moved the figure up from 70.0/61.0/63.8). top-50 is the number to quote, because the sigs payload is top-50 regardless of --top-k and is therefore what THIS command emits. A single small/trivial body can still invert it (signature+doc bigger than the body), like the --format=columnar sibling below. test/showcasecapturecheck.sh (C) re-derives all three from this repo every run, in the same quantity, and fails if the caption and the recount drift apart._

```
$ ./build/ripwire . --pack-signatures --top-k=10
<ctx>
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1329 symbols=11493 edges=14084 shown=10 est_tokens=4366 ambiguous=5555 unresolved=3233 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:18,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="4366" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0165">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0083">
</s>
<s t="method" n="push_back" id="./src/infra/svector.h::svector::push_back" overloads="2" amb="2" k="0.0070">
<c n="buf"/>
<c n="buf"/>
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
<ctx root="."><outline><o t="fn" l="2135" p="src/graph.h" n="rankGraphTeleport"><![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    PageRankRun         run{};   // an N == 0 graph never enters the kernel: { 0, converged } — see PageRankRun
    if( N )
    {
  ...
    }
    std::vector<float> r( N, 0.f );
    std::transform( rankDouble.begin(), rankDouble.end(), r.begin(), []( double value ) { return float( value ); } );
... [3 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--expand`, `--compress`, `--no-redact`, `--json`

### `--expand=A,B,...`

**Answers:** full bodies of A,B,...

Selector grammar per item (the tail after the LAST ':' decides; a tail STARTING WITH A DIGIT is a range, anything else is a name): NAME                every def of that name  |  FILE:NAME           that file's def NAME:START-END      body slice              |  FILE:NAME:START-END selector + slice FILE:LINE:NAME      paste a row's p="path:line" straight from --callers/--lint/--grep (NOT --hotspots: its p= is a BARE path — build FILE:LINE:NAME from its own p=/top_l=/top= instead, since top= is just the worst function's name) path::scope::name   the canonical id= --for/--pack-task emit (START-END is 1-based within the def's OWN body — lines="lo-hi/total" marks the slice partial; out-of-range clamps. FILE matches any path substring, like --callers/--lego.) EXACT-NAME DEFAULT (one token, one unambiguous match, no explicit --top-k): the ranked map defaults to top-k=0 — you already named the exact symbol, so the ~200-row orientation map is pure overhead in front of the one body it exists to summarize. Disclosed on the root as topk_default="0" (self-describing: the change is visible without reading source). A MULTI-match name (an ambiguous bare name) or a multi-token --expand keeps the map — there IS something to disambiguate. An EXPLICIT --top-k=N (0 included) always overrides this default. Each body also carries sibs="a,b,..." sibs_total="N" [sibs_capped="1"] (the file's OTHER symbols, names only, capped at 40) and inc="x.h,..." inc_total="N" [inc_capped="1"] (the file's own #include/import targets, capped at 24) — both absent when the count is 0 (a documented zero, not a degrade), so a body no longer needs a second --outline call just to learn what else lives in its file. CHEAPEST-COMPLETE-ANSWER SERVING (no explicit --top-k, no range slice): the verb ALSO measures the (possibly map-less) bundle against the requested symbols' whole FILE(s) and emits the SMALLER, disclosed on the root as mode="bundle|whole-file" reason="the two byte counts" — on a small file the old bundle was 5.65x the file itself; on a big file the bundle saves ~26x. The whole-file form is <src p= sym="name:line,..."> with the file CDATA-wrapped (redacted as usual) and every requested symbol's line anchor kept. An EXPLICIT --top-k=N (including 0) opts out of BOTH the exact-name default and mode= auto-selection and keeps the classic undecorated shape; a SYM:START-END slice opts out of mode= auto-selection only (serving the whole file would invert an explicit narrowing) but still gets the exact-name top-k=0 default when it applies.

**Try it**

_NEW since the last capture: --top-k=0 means PAYLOAD-ONLY — no ranked map rides along with the body you asked for._

```
$ ./build/ripwire . --top-k=0 --expand=rankGraphTeleport
<ctx root=".">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2135" p="src/graph.h" n="rankGraphTeleport" sibs="Graph,langCompatible,namespaceCompatible,kCommonNameMul,kCommonNameDefThreshold,kPrivateNameMul,kSpecificNameMul,kSpecificMinLen,kSpecificMinWords,wordCount,weight,decodeJniName,splitSegments,isTemplateSegment,pathsMatch,methodsCompatibl … [line truncated: 570 more bytes on this line]
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    PageRankRun         run{};   // an N == 0 graph never enters the kernel: { 0, converged } — see PageRankRun
    if( N )
    {
        double teleportMass = 0.0;
... [18 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--for`, `--pack-signatures`, `--outline`, `--compress`, `--hotspots`, `--edit-check`, `--run-timeout`

**Caveats (stated by the binary):**

- FILE matches any path substring, like --callers/--lego.) EXACT-NAME DEFAULT (one token, one unambiguous match, no explicit --top-k): the ranked map defaults to top-k=0 — you already named the exact symbol, so the ~200-row orientation map is pure overhead in front of the one body it exists to summarize.
- A MULTI-match name (an ambiguous bare name) or a multi-token --expand keeps the map — there IS something to disambiguate.

### `--compress`

**Answers:** strip comments + collapse blank runs from SERVED BODIES (~20-35% token cut): --expand/ --outline, --for's auto/anchor and --detail=N bodies, --pack-task, --from-trace and --exemplar.

Disclosed per bundle as compress="1" on the <bodies> element; without the flag, output is byte-identical. String literals survive; the ranked SET never changes.

**Try it**

_Comments stripped + blank runs collapsed — compressBody is the function that implements --compress itself, chosen because it is comment-heavy enough to show a real reduction (the previously captioned symbol had no comments or blank runs, so before/after were byte-identical under a caption promising a difference)._

```
$ ./build/ripwire . --expand=compressBody --top-k=0 --compress
<ctx root=".">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2272" p="src/serialize.h" n="compressBody" sibs="xmlSafeByte,xmlScrubIsLossy,xmlControlCharRef,escapeXml,xmlCommentText,ctxRootOpen,ctxRootJsonScrubKeys,appendCdataSafe,XmlWriter,XmlWriter,XmlWriter,operator=,write,flush,hadWriteError,kCap,appendOneNote,appendOneNote,renderNoteChildren, … [line truncated: 689 more bytes on this line]
<![CDATA[inline std::string compressBody( std::string_view src )
{


    std::string out;
    out.reserve( src.size() );

    const std::size_t N = src.size();
    std::size_t       i = 0;

    while( i < N )
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--for`

**Caveats (stated by the binary):**

- the ranked SET never changes.

### `--pack-top-n=N`

**Answers:** pack the N top symbols' bodies  [--pack-budget-bytes=B]

**Try it**

_Pack the top-3 ranked symbols' full bodies (deprecated verb; see stderr)._

```
$ ./build/ripwire . --pack-top-n=3 --top-k=0
<ctx root="."><src p="./src/infra/svector.h"><![CDATA[#pragma once

// svector.h — rw::svector: a small-vector with N INLINE slots that spills to the heap only past N.
// 16 bytes at <uint32,2>, with a BRANCH-FREE size(). Both, not one or the other.
//
// ── THE DESIGN, AND WHY IT IS THIS ONE ───────────────────────────────────────────────────────────────
// The shape the host tree leans on hardest is `Map<K, svector<V,N>>` — many tiny id-lists (byName /
// canonByName / shard maps, and ~100 more structures after the conversion wave): WRITE-ONCE during the
// parse/merge, then READ-HOT during resolve.
//
// Three things matter for that shape, and the layout below gets all three:
//   • no per-list malloc — the N small lists that would each allocate are inline;
//   • a BRANCH-FREE size() — `return sz_`, because the size lives in its own field;
//   • 16 BYTES per instance — because `inl_` and `heap_` are never both live, so they share storage.
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--token-budget`, `--for`

### `--no-redact`

**Answers:** emit source/doc text VERBATIM, redacting nothing REDACTED by default (high-confidence credential SHAPES only, precision over recall): emitted symbol BODIES, doc/markdown bodies and doc-comment excerpts, the --outline skeleton, and SIGNATURES — a default argument carries whatever literal was written.

NOT redacted, and a deliberate residual: --grep/--regex/--match hit lines and their --grep-context neighbours, and --note-add/--notes text. --grep is the exception on purpose — auditing a repo FOR secrets needs the hit you searched for shown verbatim.

**Try it**

_--no-redact: emit bodies verbatim (credential redaction is on by default)._

```
$ ./build/ripwire . --expand=readAckRecords --top-k=0 --no-redact
<ctx root=".">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2931" p="src/quality.h" n="readAckRecords" sibs="kBaselineFile,kMinCloneTokens,kCcxBar,kLocBar,kNestBar,kParamBar,kShortHorizonDays,kShortHorizonMinCommits,kReusedHelperMinFanin,kMinorCcxDelta,kMinorLocDelta,kMinorParamDelta,kAcksFile,rootQualifiedSidecar,baselinePath,acksPath,insertScr … [line truncated: 688 more bytes on this line]
<![CDATA[inline gtl::btree_map<std::string, AckRecord> readAckRecords( const std::string& path )
{
    gtl::btree_map<std::string, AckRecord> out;
    std::ifstream f( path );
    if( !f )
    {
        return out;
    }
    std::string line;
    while( std::getline( f, line ) )
    {
... [17 more line(s); run it to see the whole thing]
```

---

## assess quality / structure

### `--metrics`

**Answers:** annotate fan-in/out + complexity (descriptive;

coupling is the validated signal, complexity is a size-correlated one). also surfaces amp= (--metrics/--for/--exemplar): amp = |direct callers| (symbol-level, the in-edge CSR) + |co-change partners of the symbol's FILE| (file-level, mined from git history) — a deliberate GRANULARITY MIX, not a graph-only count; degrades to callers-only (still valid) when git/history is unavailable. NOT the same quantity as --impact's reaches=: reaches= is the TRANSITIVE blast radius over the call graph alone (everything that reaches SYM, any hop count); amp= is DIRECT callers plus a historical co-edit signal the call graph cannot see at all — the two numbers on the same symbol routinely differ several-fold (one seen case: 4.6x apart) because they measure different things, not because one is wrong. ppalt=N (C-family/C#): the body contains N alternative preprocessor branches (#else/#elif) — code that never coexists at compile time. cx/ccx/nest/loc/locals are summed over ALL branches (deterministic, but an over-count vs any single build; ~2x seen on a real SSE/scalar pair), so discount them accordingly. ripwire never guesses which branch your build compiles — it discloses the count instead. A bare #if with no #else adds no alternative and no ppalt=. Absent when 0. ev=N essential complexity (McCabe: 1=fully structured, 2+=jumps block extract-method cleanly — the jump makes it a rewrite, not a mechanical lift); ev_why=tag:count names which jumps raised it (guard-return, loop-escape, ...). A FLOOR (ev_floor=1): noreturn calls/macro-hidden exits go unseen; absent on a cx row means exactly 1, and Rust ?/ yield/await/defer are not counted, so Bash carries no ev at all. humps=/deep=/locals= are the nesting PROFILE nest= alone cannot give: nest= is a max, so one deep line and a body that is deep throughout report the same number. humps= counts regions reaching the nesting bar, deep= the lines inside them (a floor), and locals= the local-variable-declaration count (a floor, C/C++ only). Read the three together — a tangle (many humps, few deep lines each) and a long blocked-sequential body (one hump, many deep lines) have the same nest= but opposite refactors. Absent exactly when nest is below the bar (not-deep), never a hidden 0.

**Try it**

_Fan-in/out + complexity annotations on the map._

```
$ ./build/ripwire . --metrics --top-k=10
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- metrics: in=fan-in out=fan-out cx=cyclomatic ccx=cognitive loc=lines params=count nest=MAX-depth humps=regions-reaching-the-nesting-bar deep=lines-inside-them(floor,see deep_floor) (humps/deep are the PROFILE nest= cannot give: nest= is a max, so one deep line and a body that is deep throughout report the same number; deep/loc is the fraction. Both absent exactly when nest<bar — not-deep, never a hidden 0. deep counts LINES and humps counts REGIONS, and two regions can share a line, so deep BELOW humps is legal: a one-line if/else at the bar is 2 regions on 1 line) locals=local-var-decl-count(floor,C/C++-only,see locals_floor) ppalt=preproc-alternative-branches-in-body(#else/#elif; metrics sum ALL branches, no single build compiles them all) ev=essential-cx(McCabe: 1=fully structured, 2+=jumps block extract-method; absent on a cx row means exactly 1; floor per ev_floor — noreturn calls/macro-hidden exits unseen; not counted: &&/||, Rust ? and yield/await/defer, hence Bash carries no ev) ev_why=which-jumps-raised-it tag:count cbo=coupling lcom4=cohesion amp=change-amplification tested=1 role=hub(fan-in 8+; uses spells role call|macro|read|write|import|extends). Absent=N/A, never 0. -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1329 symbols=11493 edges=14084 shown=10 est_tokens=1782 ambiguous=5555 unresolved=3233 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:18,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="1782" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" in="539" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" locals="0" locals_floor="1" cbo="0" amp="562" tested="1" k="0.0165">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" in="29" out="0" cx="2" ccx="1" role="hub" loc="1" params="0" nest="1" locals="0" locals_floor="1" cbo="0" amp="52" tested="1" k="0.0083">
</s>
<s t="method" n="push_back" id="./src/infra/svector.h::svector::push_back" overloads="2" in="473" out="3" cx="2" ccx="1" role="hub" loc="5" params="1" nest="1" locals="1" locals_floor="1" cbo="3" amp="496" tested="1" amb="2" k="0.0070" ev="2" ev_floor="1" ev_why="guard-return:1">
<c n="buf"/>
<c n="buf"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--json`, `--index-out`

**Caveats (stated by the binary):**

- also surfaces amp= (--metrics/--for/--exemplar): amp = |direct callers| (symbol-level, the in-edge CSR) + |co-change partners of the symbol's FILE| (file-level, mined from git history) — a deliberate GRANULARITY MIX, not a graph-only count;
- degrades to callers-only (still valid) when git/history is unavailable.
- amp= is DIRECT callers plus a historical co-edit signal the call graph cannot see at all — the two numbers on the same symbol routinely differ several-fold (one seen case: 4.6x apart) because they measure different things, not because one is wrong.

### `--deps`

**Answers:** file->file dependency graph (god-files, cycles — validated);

its nccd (Lakos) is a design heuristic, not independently outcome-validated. instab= (Martin's I=Ce/(Ca+Ce)) counts project includes ONLY -- system/third-party headers are excluded from Ce, matching stabledeps' gap= so gap == consumer's instab - provider's instab always. <health>'s ccd/acd/nccd/shape are computed over dep_files= (files whose language has #include/import syntax) not files= (the raw corpus, incl. .sh/.md/.json/etc, which can't participate in the graph) -- --arch's propagation_cost uses the same N

**Try it**

_File->file dependency graph (god-files, cycles)._

```
$ ./build/ripwire . --deps
<!-- ripwire deps: file-to-file #include/import view, heaviest transitive cone first. files= (root) = files with at least one dependency edge (this listing's own denominator); health files= = the whole indexed corpus; health dep_files= = the dependency-CAPABLE subset of it (the ccd/acd/nccd denominator). raise the default cap with limit=N (offset=M pages). -->
<deps files="306" shown="40" capped="1" root=".">
<health files="1329" dep_files="616" ccd="3243" acd="5.3" nccd="0.64" shape="horizontal"/>
<godfiles total="214" shown="12" capped="1">
<f p="src/model.h" afferent="70"/>
<f p="src/infra/Diagnostics.h" afferent="43"/>
<f p="src/serialize.h" afferent="31"/>
<f p="src/graph.h" afferent="28"/>
<f p="src/ingest.h" afferent="21"/>
<f p="src/arch.h" afferent="19"/>
<f p="src/infra/jsonesc.h" afferent="18"/>
<f p="src/quality.h" afferent="16"/>
<f p="src/graphlegend.h" afferent="12"/>
<f p="src/infra/hashutil.h" afferent="12"/>
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
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<hotspots window="12mo" files="1329" ranked="336" unranked_no_churn="0" unranked_no_complexity="993" shown="40" capped="1" root="." at="061dcf667">
<f p="src/main.cpp" churn="156" ccx="4286" score="668616" top="main" top_ccx="391" top_l="14473"/>
<f p="src/ingest.cpp" churn="100" ccx="4107" score="410700" top="ingest" top_ccx="722" top_l="10154"/>
<f p="src/serialize.h" churn="47" ccx="1685" score="79195" top="packSignatures" top_ccx="201" top_l="2741"/>
<f p="src/graph.h" churn="35" ccx="1531" score="53585" top="buildGraph" top_ccx="764" top_l="722"/>
<f p="src/quality.h" churn="65" ccx="769" score="49985" top="computeDelta" top_ccx="236" top_l="3249"/>
<f p="src/cli.h" churn="92" ccx="419" score="38548" top="parseArgs" top_ccx="187" top_l="3297"/>
<f p="src/mcpverbs.h" churn="36" ccx="790" score="28440" top="runBatchSub" top_ccx="100" top_l="3340"/>
<f p="src/mcp.h" churn="23" ccx="487" score="11201" top="dispatchMcpLine" top_ccx="427" top_l="499"/>
<f p="src/search.h" churn="19" ccx="557" score="10583" top="grepCollect" top_ccx="49" top_l="1384"/>
<f p="src/lexical.h" churn="20" ccx="529" score="10580" top="lexicalScoresTiered" top_ccx="366" top_l="116"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--expand`, `--since`, `--json`

### `--clones`

**Answers:** token-normalized duplicate bodies

**Try it**

_Token-normalized duplicate bodies._

```
$ ./build/ripwire . --clones
<!-- ripwire clones: function bodies with similar normalized token streams (identifiers/literals normalized, so renamed copies match). type=2 exact/renamed (Type-1/2); type=3 gapped near-miss (an inserted/changed statement, similarity in [0.80,1.0)). Reuse don't reimplement; a fix to one likely belongs in all. groups= and type3= are the two GROUP-TYPE totals (each capped independently, so neither is the row count); total= is the true row total (groups + type3-group-count) and is ALWAYS present, paged or not; shown= is the number of group rows that follow this run. capped="1" means rows were dropped. exempt= on a group ⇒ every member is on a path the quality-delta verb's duplication kind deliberately ignores (fixture dirs / shell test-runners repeat boilerplate by convention) — a fact here, never a gate there; exempt_groups= counts them over ALL groups. gid= on a row is its CLONE COMPONENT: the Type-3 pass reports PAIRS, so three functions that are all near-copies of each other arrive as three rows of two; rows sharing a gid are one cluster, and clone_groups= counts the clusters (union-find over the pair graph, over ALL detected rows, not just the shown ones). dup_pct=duplicated-LOC/total-LOC as a percentage, where duplicated-LOC sums, per cluster, every member's loc EXCEPT the largest member's (one instance is the code you keep, the rest is the redundancy — so a 3-clone cluster counts its lines TWICE) and total-LOC is every function/method body the detector considered; dup_loc= and total_loc= are those two operands. counts_floor="1": the Type-3 pair list is capped upstream, so a dropped pair is a cluster left unmerged — clone_groups/dup_loc/dup_pct are floors, never totals. raise the default cap with limit=N (offset=M pages). -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<clones groups="53" type3="252" total="305" exempt_groups="121" clone_groups="180" dup_loc="3486" total_loc="111518" dup_pct="3.1" counts_floor="1" shown="80" capped="1" root=".">
<group type="2" gid="155" tokens="207" n="4" exempt="shell-runner">
<f n="batch_sub" p="test/mcpclidiffcheck.sh:63"/>
<f n="batch_sub" p="test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" gid="172" tokens="149" n="3" exempt="shell-runner">
<f n="monotonic_check" p="test/pyimportprecisecheck.sh:89"/>
<f n="monotonic_check" p="test/rustimportprecisecheck.sh:124"/>
<f n="monotonic_check" p="test/tsimportprecisecheck.sh:88"/>
</group>
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

Per function, which of SIX evidence families fire -- structural (shape), lexical (identifier text), confusion (syntactic construct), historical (git churn), colocation (what you must read from outside this file), state (this function's OWN BODY touching non-local mutable state) -- ranked by the COUNT of distinct families, NEVER by a weighted composite, each row carrying its own evidence. PRESET selects and cuts, never weights: strict (the four families measured steady enough to gate on, 2 must agree) | default (all six, 2; the bare form) | lenient (all six, 1 -- a reading order, not a verdict). historical and colocation are out of strict: each is a fixed-size worst-40 cut over a ranking whose population moves, so both re-shuffle on code that did not change (docs/EVALS.md section 9.9). A family that could not be measured here is UNAVAILABLE, never 'did not fire', and of= drops with it. A lens: exit 0. Pages limit=N (offset=M). WHY NO COMPOSITE, in full (the emitted legend is deliberately terse and points here): averaging correlated metrics re-weights one signal and calls it six, and a single quotable number is wrong the moment it is quoted -- fam= is ORDINAL, and every row carries its own evidence so a reader can see WHY without a second command. The families are partitioned by KIND of evidence so that corroboration means the lenses failed DIFFERENTLY, not that one weakness echoed six times: the first four are the ensemble join, called through its own entry point and unchanged; colocation and state passed the same orthogonality test on the same corpora before being enabled. Every threshold is REUSED from the lens it came from, none is new: four absolute structural bars (cognitive complexity, lines, nesting, params), and three rankings with no defensible absolute cut, each firing for the worst decile of its OWN ranking (at least one row, at most that lens's default window of 40) -- an ordinal cut is RELATIVE, 'worst in THIS corpus', never 'bad in absolute terms'. The state family fires on the presence of a direct access site and deliberately uses the OWN-BODY half of the lens, not the callee closure: the panel's unit is one function's own comprehensibility, and the closure is a fact about its callees. UNAVAILABLE is never silent: an empty unavailable= means every family was measured, an empty ranking or empty language coverage counts as NOT measured, and the coverage denominators behind each verdict are published so it can be checked instead of trusted. The join=deep+untested annotation puts two facts already in the report side by side (sustained depth, no reaching test) because that pair is where a refactor is most wanted and least safe; counting it would be one family wearing a second hat.

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
<!-- ripwire cochange: file pairs that change together in git but share no transitive static dependency (surprising=1) = hidden coupling. together= is the number of commits in window= that touched BOTH files (3 or more, or the pair is not reported); deg= is that count over the commit count of the LESS-CHANGED of the two files, so 1.00 means the quieter file never changed without the other. conf_ab= is that same fraction over a='s OWN commit count and conf_ba= over b='s, which is the asymmetric form: conf_ab=1.00 means a never changed without b. deg= is by construction the larger of the two, and driver= names which side it came from ("a" or "b") — the file whose changes most reliably imply the other's, and therefore the one to look at first. driver= is OMITTED when the two directions are equal, because a tie is not a finding. recur= is how many of sub_windows= the pair actually co-changed in: the mined window is cut into that many equal-COMMIT-COUNT slices (not equal time — a calendar slice can hold 400 commits or 4), so recur=1 at any together= is one burst of activity and not a persistent coupling, which is the distinction a single window cannot make. sub_windows= is the denominator and is never omitted; it is smaller than the nominal 3 only when the window holds fewer commits than that. min_recur= appears when cochange-recur=K (the flag) filtered the rows, so a short list is explained rather than silent. window= is the mining window: the default 18 months, or the since=REV|DATE value when one resolved. surprising= is only defined where BOTH sides could carry a static dependency at all (the same dependency-capable predicate deps <health dep_files=> uses: source languages yes; sh, md, json, ruby and binary/unknown files no). A pair with a dep-incapable side keeps its row and carries dep_capable=0 instead, because for it "shares no static dependency" is vacuously true. raise the default cap with limit=N (offset=M pages) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<cochange pairs="490" window="18mo" sub_windows="3" shown="30" capped="1" root="." at="061dcf667">
<pair a="src/cli.h" b="src/lintrules.h" together="3" deg="1.00" conf_ab="0.03" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/clones.h" b="src/lintrules.h" together="3" deg="1.00" conf_ab="0.27" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/clones.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.27" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/ingest.cpp" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.03" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/serialize.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.07" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/quality.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.05" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/arch.h" b="src/clones.h" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.27" driver="a" recur="2" surprising="1"/>
<pair a="src/lintrules.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="1.00" conf_ba="1.00" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.03" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="bench/agentloop/analyze.py" b="bench/agentloop/run_agentloop.py" together="7" deg="0.88" conf_ab="0.88" conf_ba="0.50" driver="a" recur="3" surprising="1"/>
... [21 more line(s); run it to see the whole thing]
```

**Shaped by:** `--cochange-recur`, `--cochange-groups`, `--since`, `--json`

### `--cochange-recur=K`

**Answers:** (with --cochange) report only pairs whose co-change RECURS in K or more of the mined window's sub-windows, so a one-off refactor sprint stops reading like an eighteen-month structural defect (Clio, ICSE 2011).

Every row carries recur= with or without this flag; the header publishes sub_windows= (the denominator) and min_recur= when the filter is on

### `--cochange-groups`

**Answers:** (with --cochange, repo-wide only) emit Modularity Violation GROUPS instead of pairs: "X co-changes with {A,B,C}, none of which it depends on" is ONE row that names the file to fix (Mo/Cai/Kazman, IEEE TSE 2019).

A greedy cover, disclosed as greedy — set cover is NP-hard, so the group count is an upper bound on the minimum, not the minimum

### `--since=REV|DATE`

**Answers:** scope --hotspots/--cochange/--rank-by=churn|churn-decay to commits after this point: a revision (HEAD~20, a tag/sha — deterministic) or a git approxidate ("2 weeks ago" — wall-clock-relative).

e.g. --hotspots --since="1 week ago" ranks by RECENT churn (the regression lens). Absent ⇒ each verb's OWN bounded default window, NOT all history: --hotspots 12 months, --rank-by=churn 18 months, --cochange 18 months (--rank-by=churn-decay is the ONE exception: its default IS all history, because the 90-day half-life makes a cut-off unnecessary — it stamps that too). All of them STAMP the window they used (window="12mo"/"18mo", or the resolved --since value) — --cochange gained its window= in the same round that gave it sub_windows=, and this clause used to say it had none. An UNRESOLVABLE value is refused by --hotspots (exit 1 — its window is part of the measurement) and degrades to the verb's own default window elsewhere

**Try it**

_Hotspots scoped to RECENT churn (the regression lens)._

```
$ ./build/ripwire . --hotspots --since="2 weeks ago"
<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=2 weeks ago). churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. unranked_no_complexity= is a file with commits but no function or method to score (a pure declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the join could not match), which scores zero for a reason that is not about the file. Treat it as an upper bound on quietness, not a measure of it. raise the default cap with limit=N (offset=M pages) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<hotspots window="2 weeks ago" files="1329" ranked="239" unranked_no_churn="571" unranked_no_complexity="519" shown="40" capped="1" root="." at="061dcf667">
<f p="src/main.cpp" churn="107" ccx="4286" score="458602" top="main" top_ccx="391" top_l="14473"/>
<f p="src/ingest.cpp" churn="66" ccx="4107" score="271062" top="ingest" top_ccx="722" top_l="10154"/>
<f p="src/serialize.h" churn="29" ccx="1685" score="48865" top="packSignatures" top_ccx="201" top_l="2741"/>
<f p="src/graph.h" churn="26" ccx="1531" score="39806" top="buildGraph" top_ccx="764" top_l="722"/>
<f p="src/quality.h" churn="42" ccx="769" score="32298" top="computeDelta" top_ccx="236" top_l="3249"/>
<f p="src/mcpverbs.h" churn="28" ccx="790" score="22120" top="runBatchSub" top_ccx="100" top_l="3340"/>
<f p="src/cli.h" churn="52" ccx="419" score="21788" top="parseArgs" top_ccx="187" top_l="3297"/>
<f p="src/mcp.h" churn="15" ccx="487" score="7305" top="dispatchMcpLine" top_ccx="427" top_l="499"/>
<f p="src/search.h" churn="11" ccx="557" score="6127" top="grepCollect" top_ccx="49" top_l="1384"/>
<f p="src/lexical.h" churn="10" ccx="529" score="5290" top="lexicalScoresTiered" top_ccx="366" top_l="116"/>
... [17 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- Absent ⇒ each verb's OWN bounded default window, NOT all history: --hotspots 12 months, --rank-by=churn 18 months, --cochange 18 months (--rank-by=churn-decay is the ONE exception: its default IS all history, because the 90-day half-life makes a cut-off unnecessary — it stamps that too).
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
<metrics modules="268" typed_modules="95" zone_pain="76" zone_useless="1" zone_ok="18" zone_na="173" propagation_cost="0.009" note="Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — directory-level estimate from na … [line truncated: 408 more bytes on this line]
<m path="." ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.codex-plugin" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.github/workflows" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench" ca="0" ce="1" types="20" abstract="2" I="1.00" A="0.10" D="0.10" zone="ok" reachable="1"/>
<m path="./bench/agentloop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/fixtures/grader" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/results" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/cppbench" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--graph-query`, `--deps`

**Caveats (stated by the binary):**

- the Martin Ca/Ce/I/A/D block it emits is a design heuristic, not independently outcome-validated (never gates).

### `--lint`

**Answers:** built-in AST checks (c-cast, goto, unsafe-c-fn, naming-*, cache-* data-layout, ...).

naming-uninformative is ONE-SIDED by design: it fires only when a name's subtokens are ALL corpus-common (BM25 idf over the identifier-name corpus) AND its body clears a size floor — a high-idf (distinctive) name is never penalised, unlike the withdrawn name<->body rule. Each <rule> row's applicability is per-LANGUAGE, not per-file-content: a rule whose registered languages (see --lint-catalog) intersect NONE of the corpus' languages carries applicable="0" (its count="0" is then structural inertness, not a measurement), and the root tallies inert_rules="N"; see --lint-catalog for the full registry

**Try it**

_Built-in AST checks (c-cast, goto, unsafe-c-fn, ...)._

```
$ ./build/ripwire . --lint
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one rule is a floor. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages). On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed them, absent an explicit limit=) — a different fact from the per-rule capped="1" above, which is a MATCH-BUDGET floor on one rule's own count=; findings= is always the true total either way. A rule row's applicable="0" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this corpus at all — its count="0" is structural inertness, never a measurement; the root's inert_rules=N tallies how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a family (e.g. cache-); the root then carries selected="K of N" plus the raw select=/ignore= you passed. Each rule row's own shown_rows=/rows_capped= is how many of THAT rule's rows fall inside the printed <f> window (the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the cut carries shown_rows="0" rows_capped="1" while its count= stays the true total — never confuse a capped-away rule with one that measured zero); this is a DIFFERENT fact from the row's own bare capped="1" above (that rule's own raw-capture stream hit its per-rule match budget) — the two can disagree on the same row. -->
<lint findings="3301" shown="693" capped="1" findings_capped="1" root=".">
<rule name="c-style-cast" count="294" shown_rows="107" rows_capped="1"/>
<rule name="goto" count="2" shown_rows="1" rows_capped="1"/>
<rule name="do-while" count="4" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="12" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="456" shown_rows="296" rows_capped="1" capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="206" shown_rows="42" rows_capped="1"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--expand`, `--naming-calibration`, `--naming-locals`, `--lint-catalog`, `--lint-rules`, `--sarif`, `--with-profile`

**Caveats (stated by the binary):**

- naming-uninformative is ONE-SIDED by design: it fires only when a name's subtokens are ALL corpus-common (BM25 idf over the identifier-name corpus) AND its body clears a size floor — a high-idf (distinctive) name is never penalised, unlike the withdrawn name<->body rule.
- Each <rule> row's applicability is per-LANGUAGE, not per-file-content: a rule whose registered languages (see --lint-catalog) intersect NONE of the corpus' languages carries applicable="0" (its count="0" is then structural inertness, not a measurement), and the root tallies inert_rules="N";

### `--lint-catalog`

**Answers:** the built-in rule registry: one row per rule with sev=/category=/rationale/lang=/since= — no corpus needed.

Every built-in rule from every pack (base checks, atoms-*, cache-*, naming-*, the symbol-level checks) has exactly one row; lang= is the SAME token spelling --lint-rules' language: field accepts, so it round-trips into a user rule

**Shaped by:** `--lint`

### `--lint-rules=DIR`

**Answers:** load user lint rules (YAML, ast-grep style) from DIR — runs with, or instead of, --lint --lint-select=PREFIX[,...] (with --lint / --lint-rules) run ONLY rules whose name starts with one of these PREFIXes (or '*' for all) — comma-separated, e.g.

cache- selects the whole cache-* family. The root then carries selected="K of N" plus the raw select=/ignore= you passed, so a filtered zero is never confusable with an unfiltered one. An unresolvable PREFIX (matches no rule) refuses (exit 1), naming the nearest rule/family by edit distance --lint-ignore=PREFIX[,...] (with --lint / --lint-rules) DROP rules whose name starts with one of these PREFIXes (or '*' to drop everything, e.g. paired with --lint-select elsewhere to isolate one family) — applied AFTER --lint-select narrows the set; same unresolvable-PREFIX refusal and root disclosure as --lint-select

**Try it**

_User lint rules (YAML, ast-grep style) from a directory._

```
$ ./build/ripwire . --lint-rules=test/lintrulesfix/rules
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one rule is a floor. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages). On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed them, absent an explicit limit=) — a different fact from the per-rule capped="1" above, which is a MATCH-BUDGET floor on one rule's own count=; findings= is always the true total either way. A rule row's applicable="0" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this corpus at all — its count="0" is structural inertness, never a measurement; the root's inert_rules=N tallies how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a family (e.g. cache-); the root then carries selected="K of N" plus the raw select=/ignore= you passed. Each rule row's own shown_rows=/rows_capped= is how many of THAT rule's rows fall inside the printed <f> window (the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the cut carries shown_rows="0" rows_capped="1" while its count= stays the true total — never confuse a capped-away rule with one that measured zero); this is a DIFFERENT fact from the row's own bare capped="1" above (that rule's own raw-capture stream hit its per-rule match budget) — the two can disagree on the same row. -->
<lint findings="5" shown="5" capped="0" root=".">
<rule name="broken-query" sev="error" count="0" shown_rows="0" rows_capped="0"/>
<rule name="no-printf" sev="warn" count="5" shown_rows="5" rows_capped="0"/>
<f rule="no-printf" sev="warn" p="test/coplintfix/position.cpp:41" in="demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/coplintfix/safe.cpp:15" in="safe_demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/coplintfix/safe.cpp:27" in="safe_demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/lintrulesfix/sample.cpp:8" in="greet">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/usesfix/store.cpp:24" in="run">use LOG() instead of printf</f>
</lint>
```

**Shaped by:** `--lint-catalog`, `--sarif`

**Caveats (stated by the binary):**

- The root then carries selected="K of N" plus the raw select=/ignore= you passed, so a filtered zero is never confusable with an unfiltered one.
- An unresolvable PREFIX (matches no rule) refuses (exit 1), naming the nearest rule/family by edit distance --lint-ignore=PREFIX[,...] (with --lint / --lint-rules) DROP rules whose name starts with one of these PREFIXes (or '*' to drop everything, e.g.

### `--sarif`

**Answers:** (with --lint / --lint-rules) the SAME findings as SARIF 2.1.0 instead of the native XML <lint> block — the shape github/codeql-action/upload-sarif consumes for code scanning.

Pure re-serialization (zero new analysis); results count == the native run's findings count. Levels: user severity error/warn/info -> SARIF error/warning/note; a built-in finding (a fact, never a gate) has no severity of its own and also maps to note. Fields with no SARIF home (per-rule capped= floor, enclosing symbol, raw sev=) ride in properties rather than being dropped; URIs are relative to the scanned root. Always the FULL result set — refuses loudly alongside limit=/offset= paging, --match and --with-profile

**Caveats (stated by the binary):**

- a built-in finding (a fact, never a gate) has no severity of its own and also maps to note.
- Fields with no SARIF home (per-rule capped= floor, enclosing symbol, raw sev=) ride in properties rather than being dropped;
- Always the FULL result set — refuses loudly alongside limit=/offset= paging, --match and --with-profile

### `--with-profile=FILE`

**Answers:** (with --lint) join MEASURED heat onto findings: FILE is a RIPWIRE_PROFILE build's report (its #PROF_TSV block);

a finding whose enclosing symbol contains a PROFILE_SCOPE site gains heat_* attributes (scope, calls, total_ms, and whichever counter columns the profiled run armed — l1d_mpki etc.). Static shape x measured weight; joins nothing silently — a missing file or a FILE with no #PROF_TSV block refuses loudly

**Try it**

_Join MEASURED heat onto --lint findings — runs in a tiny fabricated demo corpus (one cache-pointer-chase-loop finding under a PROFILE_SCOPE site) because a real report needs a RIPWIRE_PROFILE build; the finding inside the profiled scope gains heat_* columns from the report's #PROF_TSV row._

```
$ ./build/ripwire . --lint --with-profile=report.txt
#PROF_TSV_BEGIN	one row per scope, aggregated across threads; counters are RAW integers
scope	file	line	calls	total_ms	l1d_mpki
walk: chase pass	x.cpp	9	12	48.500	7.250
#PROF_TSV_END
```

**Shaped by:** `--sarif`

**Caveats (stated by the binary):**

- joins nothing silently — a missing file or a FILE with no #PROF_TSV block refuses loudly

### `--communities`

**Answers:** cluster the call graph into cohesive modules (each row's id= drills down below;

drill= names the verb)

**Try it**

_Cluster the call graph into cohesive modules._

```
$ ./build/ripwire . --communities
<!-- ripwire communities: cohesive call-graph modules (Louvain); bridge=cross-module edges; isolated=call-graph-edgeless symbols; drill= names the verb that takes an id= from a row below. On each module row size= is its TRUE member count while shown=/capped= describe the member list printed here: this listing is fixed at the 5 top-ranked members and is NOT widened by limit=/offset= (those page the MODULE rows). capped=1 means members were dropped; drill= names the verb that pages the full member list of one module. raise the default cap with limit=N (offset=M pages). pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<communities drill="--community=ID" modules="874" shown_modules="30" modules_capped="1" bridges="1239" shown_bridges="12" bridges_capped="1" isolated="6857" isolated_decl="1624" isolated_header="719" isolated_source="2304" isolated_doc="2210" connected_singletons="0" symbols="11493" pr_iters="32" ro … [line truncated: 7 more bytes on this line]
<community id="2543" size="589" dir="src" label="src::min@infra/fastmath.h:51:2347 [run,write,pack]" shown="5" capped="1">
<member t="method" n="empty" p="src/notes.h:396"/>
<member t="method" n="empty" p="src/scipoverlay.h:93"/>
<member t="method" n="clear" p="src/renamemine.h:225"/>
<member t="fn" n="min" p="src/infra/fastmath.h:51"/>
<member t="fn" n="escapeXml" p="src/serialize.h:122"/>
</community>
<community id="2567" size="347" dir="src" label="src::assign@infra/svector.h:342:19905 [compute,resolve,apply]" shown="5" capped="1">
<member t="method" n="size" p="src/infra/svector.h:285"/>
<member t="fn" n="max" p="src/infra/fastmath.h:54"/>
<member t="method" n="end" p="src/infra/svector.h:270"/>
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
<!-- ripwire community: ONE module from the communities/zoom partition — its ranked members and its bridge edges to other modules. size= is the module's TRUE member count; shown=/capped= are this page. partition= is the FULL label space (every id 0..partition-1, incl. isolated singletons) — the range the id= argument ranges over; modules= counts the NON-isolated communities (size>=2), the SAME predicate the communities-listing verb's modules= uses, so parent and child agree. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<community id="0" size="1" dir=".codex-plugin" label=".codex-plugin::name@plugin.json:2:4" bridges="0" shown_bridges="0" bridges_capped="0" partition="7731" modules="874" shown="1" capped="0" pr_iters="32" root=".">
<member t="sec" n="name" p=".codex-plugin/plugin.json:2"/>
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
<!-- ripwire zoom: NESTED module hierarchy (multi-level Louvain); indent = one level deeper; module = dominant-dir(symbol-count); leaf lists top-ranked symbols; bridge = cross-top-module call traffic. symbols= is the whole corpus; isolated= is the symbols in NO top-level module (a group of one — the same rule that makes top_modules= count only groups of 2 or more), and they reconcile exactly: symbols= equals isolated= plus the sum of the TOP-LEVEL size= values, every one of them, including any this page did not print. On a level-0 module size= is its true member count and shown=/capped= describe the member list printed here, which is fixed at the 5 top-ranked members and is not widened by limit=/offset= (those page the TOP-LEVEL modules); the community drill verb pages one module's full member list by its level-0 id. A module above level 0 lists every child module, so it carries no shown=/capped= pair. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<zoom levels="4" top_modules="321" symbols="11493" isolated="6857" pr_iters="32">
<module level="3" id="430" size="2707" dir="./src">
<module level="2" id="431" size="2473" dir="./src">
<module level="1" id="463" size="1997" dir="./src">
<module level="0" id="2543" size="589" dir="./src" shown="5" capped="1">
<member t="method" n="empty" p="./src/notes.h:396"/>
<member t="method" n="empty" p="./src/scipoverlay.h:93"/>
<member t="method" n="clear" p="./src/renamemine.h:225"/>
<member t="fn" n="min" p="./src/infra/fastmath.h:51"/>
<member t="fn" n="escapeXml" p="./src/serialize.h:122"/>
</module>
<module level="0" id="2567" size="347" dir="./src" shown="5" capped="1">
<member t="method" n="size" p="./src/infra/svector.h:285"/>
... [17 more line(s); run it to see the whole thing]
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

1329 files · 11493 symbols · 14084 edges · 874 modules (6857 call-graph isolated)

Root: `.`

Call-graph isolate provenance: 1624 declaration, 719 header, 2304 source, 2210 document; 0 connected Louvain singletons

## Modules (call-graph clusters; showing 12 of 874)
- **src::min@infra/fastmath.h:51:2347 [run,write,pack]** — 589 symbols
- **src::assign@infra/svector.h:342:19905 [compute,resolve,apply]** — 347 symbols
- **src::PROFILE_SCOPE_DESCRIBE@infra/profileScope.h:1322:44988 [compute,collect,add]** — 294 symbols
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--json`

### `--seams`

**Answers:** cross-module call seams no test reaches (untested integration seams)

**Try it**

_Cross-module call seams no test reaches. NOW carries seam_pairs/shown/capped._

```
$ ./build/ripwire . --seams
<!-- ripwire seams: cross-directory call edges NO test reaches (untested integration seams; a fact, not a mandate). module = parent dir; seam = caller-dir -> callee-dir, spelled from= and to=. Each seam pages its own edge rows with shown=/capped=; an edge names caller= at site p= calling callee= at site cp=. UNIT: untested= here counts cross-directory call EDGES. The test gate verb spells untested= over impacted SYMBOLS and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. raise the default cap with limit=N (offset=M pages). pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<seams modules="266" bridges="4829" untested="4052" test_files="921" seam_pairs="62" shown="20" capped="1" pr_iters="32" root=".">
<seam from="src" to="src/infra" untested="3785" shown="5" capped="1">
<edge caller="popenTrimmed" p="src/quality.h:507" callee="back" cp="src/infra/svector.h:264"/>
<edge caller="popenTrimmed" p="src/quality.h:507" callee="pop_back" cp="src/infra/svector.h:340"/>
<edge caller="popenTrimmed" p="src/quality.h:507" callee="back" cp="src/infra/svector.h:263"/>
<edge caller="gitOneLine" p="src/quality.h:531" callee="shSingleQuote" cp="src/infra/jsonesc.h:268"/>
<edge caller="jsonStr" p="src/serialize.h:5201" callee="escapeMcp" cp="src/infra/jsonesc.h:186"/>
</seam>
<seam from="bench" to="src/infra" untested="87" shown="5" capped="1">
<edge caller="aggregateMax" p="bench/bench_ordered_map.cpp:85" callee="max" cp="src/infra/fastmath.h:54"/>
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="pop_back" cp="src/infra/svector.h:340"/>
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="emplace_back" cp="src/infra/svector.h:333"/>
... [17 more line(s); run it to see the whole thing]
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
    n75["src<br/>3669"]
    n76["src/infra<br/>491"]
  end
  subgraph sg1 ["test"]
    n77["test<br/>2167"]
    n141["test/expandmodefix<br/>151"]
    n184["test/massfix<br/>77"]
    n174["test/legofix<br/>60"]
    n202["test/optremarksfix<br/>59"]
    n212["test/pyshapefix<br/>58"]
    n194["test/namingconsistencyfix<br/>57"]
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
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<owners files="1329" root="." at="061dcf667">
<uniform authors="1" bf="1" share="1.00" files="812"/>
<f p=".github/workflows/ci.yml" authors="2" bf="1" top="<author>" share="0.94"/>
<f p=".github/workflows/release.yml" authors="3" bf="0" top="<author>" share="0.78"/>
<f p="CHANGELOG.md" authors="2" bf="1" top="<author>" share="0.94"/>
<f p="PLAN.md" authors="2" bf="1" top="<author>" share="0.94"/>
<f p="README.md" authors="4" bf="1" top="<author>" share="0.96"/>
<f p="SECURITY.md" authors="2" bf="0" top="<author>" share="0.50"/>
<f p="THIRD_PARTY.md" authors="2" bf="1" top="<author>" share="0.86"/>
<f p="bench/ANSWERQUALITY.md" authors="2" bf="0" top="<author>" share="0.75"/>
<f p="bench/BENCHMARK.md" authors="2" bf="0" top="<author>" share="0.75"/>
... [17 more line(s); run it to see the whole thing]
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
<dead-code count="1" confidence="high" evidence="internal-linkage+zero-callers" filter="src" root=".">
<d n="unused_helper" t="fn" p="test/archmetricsfix/src/orphan/util.cpp" l="1"/>
</dead-code>
```

**Shaped by:** `--safe-delete`, `--json`

**Caveats (stated by the binary):**

- =DIR scopes to whole path components (dir or filename) and REFUSES a filter that names nothing indexed.

### `--quality-baseline`

**Answers:** snapshot ccx/clones/dead-code to .ripwire_quality_baseline (run BEFORE a change)

**Shaped by:** `--quality-delta`

### `--quality-delta`

**Answers:** agent self-check before a PR (pair with --test-gate): report ONLY what a change made worse vs the baseline (10 kinds: complexity/verbosity/nesting/params/dup/dead/api-surface + error-masking/short-horizon-churn/reuse-decline);

every finding is classified by ORIGIN: a symbol that EXISTED at the baseline and got worse (preexisting-worse="N", no attribute on the row) vs one that exists only because the code is NEW (new-symbol="N", origin="new-symbol" on the row). A small numeric delta is additionally sev="minor". EXIT 2 ONLY on preexisting-worse AND major AND unacked — the gating="N" header count. New-symbol rows are still PRINTED (they are the debt you are adding — read them), they just never gate; exit 0 means "nothing that already existed got worse", not "clean". Clone kinds classify by member set (new-symbol only if EVERY member is new); short-horizon-churn is preexisting by construction. LIMIT: origin is canonId (path::scope::name) identity, so a RENAMED/MOVED symbol reads as new and a regression carried in with the move will not gate. Test-fixture dirs + doc sections are exempt from dead-code/churn; churn needs COMMITTED thrash evidence (rewritten across recent commits AND again by this diff), never the current edit alone WHICH FLOOR IT COMPARES AGAINST, and a side effect: the sidecar is honored only when the sha it was pinned at EQUALS the current git HEAD (strict equality — an ancestor commit describes a DIFFERENT tree, so everything committed since would read as your regression). A sidecar pinned anywhere else is STALE: this verb then DELETES it from your working tree (self-heal, so the next run does not rediscover the dead pin) and auto-compares the working tree vs git HEAD instead. Re-pin with --quality-baseline. The read-only MCP quality_delta verb applies the SAME staleness test but never deletes. Which floor was actually used is on every report as baseline=: sidecar | git-HEAD | git-HEAD (stale sidecar removed) | git-HEAD (stale sidecar ignored) — the last two say a stale sidecar existed, and 'removed' means the file is gone. A non-git root has no HEAD to fall back to, so its sidecar is always honored; without one there, the verb exits 1.

**Try it**

_On a CLEAN tree: nothing got worse, exit 0. The gating shape is in the sandbox section below._

```
$ ./build/ripwire . --quality-delta
<!-- ripwire quality-delta: only what a change made WORSE against the floor named by baseline= below. FOUR floors, and they are not interchangeable: sidecar = the pinned .ripwire_quality_baseline snapshot, honored only because it was pinned at the CURRENT git HEAD; git-HEAD = no sidecar existed, so the working tree was auto-compared against the HEAD tree; git-HEAD (stale sidecar removed) = a sidecar existed, was pinned at a DIFFERENT sha, and this run DELETED it from your working tree before falling back to HEAD (re-pin with quality-baseline); git-HEAD (stale sidecar ignored) = same staleness verdict, but the file was left on disk (the read-only MCP arm, or an unlink that failed). Only the first is a floor YOU chose; the other three compare against HEAD, so anything already committed cannot appear. A FIFTH marker, ref-pair, means none of those: the verb was given a RANGE, so it compared two COMMITTED trees and no sidecar was read, written or deleted. Those reports carry base_ref= and target_ref= (the two RESOLVED shas, at full length, because a wave number gets quoted into handoffs) and OMIT at=, since the pair is the anchor. They also carry churn set to unavailable, which is the honest statement that one of the ten kinds, short-horizon-churn, cannot be measured there at all: it needs git history at the tree being judged, and both trees are materialized OUT of the repo into temp dirs. Its silence in such a report is therefore not evidence that nothing churned. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. Findings: complexity over the ccx bar, verbosity (LOC)/nesting/params regressions, new duplication, newly-dead, new public api-surface (contract drift), error-masking, short-horizon churn, new clone of a reused helper. THREE independent axes, applied in this order: (1) acked findings are suppressed entirely (acked= counts them, honestly); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin= attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor". EXIT 2 fires only on preexisting-worse AND major, i.e. gating="N" above; new-symbol rows never gate. Clone kinds classify by their member set (a group is new-symbol only if EVERY member is new); short-horizon-churn is preexisting by construction. exit 0 is NOT a verdict on the new-symbol rows — nothing that existed got worse, but the new debt is yours: read them. LIMIT: origin is canonId identity (path::scope::name), so a RENAMED or MOVED symbol reads as new — a regression carried in with a move classifies new-symbol and will not gate. Descriptive: weigh + fix the real ones, do not game the number (a wrong abstraction beats a low score). stale="N" is a SEPARATE axis, never gating, over the .ripwire_quality_acks ledger: an ack whose target no longer applies. Each sa row's why is target-gone (the key names no symbol/group any more) or finding-gone (the target survived, this kind just does not fire on it) — hygiene disclosure only, the ledger file is never auto-edited. Each row carries kind= (which of the measured axes regressed) and sym= (the canonical id it regressed on) — except duplication rows, which name the whole clone group rather than one symbol: members= is the group's member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports) — plus p="path:line" (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when no locator resolves), and every row the header's gating= counter counts also carries a gating attribute set to 1 — those are the rows the exit code fires on, and they are now marked positively rather than by the ABSENCE of sev/origin. (This sentence deliberately spells no attribute=value literal: the header counters are parsed by grep in several gates, and a quoted numeric example here would be matched first.) -->
<quality-delta baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="17" preexisting-worse="0" new-symbol="0" gating="0" at="061dcf667">
<sa kind="complexity" key="f8f91456c234074f" why="target-gone"/>
<sa kind="complexity" key="fcc9389382ada1b0" why="target-gone"/>
<sa kind="dead-code:preexisting" key="44da49cd9a05e5cc" why="finding-gone"/>
<sa kind="dead-code:preexisting" key="b89dc1827832d2fd" why="finding-gone"/>
<sa kind="duplication" key="4a6d699a2b38f977" why="finding-gone"/>
<sa kind="duplication" key="641ef9cd77a3e4d0" why="finding-gone"/>
<sa kind="duplication" key="69ca0068a413b01f" why="finding-gone"/>
<sa kind="duplication" key="6bbb331c18a5deaf" why="finding-gone"/>
<sa kind="short-horizon-churn" key="1b8cc1b791b2c572" why="target-gone"/>
<sa kind="short-horizon-churn" key="1fb1007e9ca0c20b" why="target-gone"/>
<sa kind="short-horizon-churn" key="8bd48de4f0863ced" why="target-gone"/>
<sa kind="short-horizon-churn" key="c00a0f11de7e013b" why="target-gone"/>
... [6 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--test-gate`, `--dmm`, `--json`

**Caveats (stated by the binary):**

- New-symbol rows are still PRINTED (they are the debt you are adding — read them), they just never gate;
- LIMIT: origin is canonId (path::scope::name) identity, so a RENAMED/MOVED symbol reads as new and a regression carried in with the move will not gate.
- The read-only MCP quality_delta verb applies the SAME staleness test but never deletes.

### `--quality-delta=REV|A..B`

**Answers:** the same 10-kind report between two COMMITTED TREES instead of the working tree vs a baseline — the WAVE-level measurement (=A..B = tree B against tree A;

=REV = that commit against its FIRST PARENT; an EMPTY side of the range means HEAD). Same grammar --dmm= takes, and A...B is REFUSED rather than read as A..B. Use it to measure a whole integration branch at once (--quality-delta=<merge-base>..<head>): per-lane checks each compare against their own baseline and cannot see a regression the WAVE introduced. Identical output contract to the bare form — same kinds, gating="N", exit 2, and the same .ripwire_quality_acks ratchet (acks are keyed root-relative, so a ledger recorded from working-tree runs applies unchanged). base_ref= and target_ref= disclose the two RESOLVED shas. No sidecar is read, written or deleted by this form, and at= is omitted: the two refs ARE the anchor. A==B is a legal, empty, exit-0 comparison. ONE KIND CANNOT BE MEASURED HERE and says so as churn="unavailable": short-horizon-churn needs git history at the tree being judged, and both trees are materialized OUT of the repo into temp dirs. The other 9 kinds are computed exactly as the bare form computes them.

**Try it**

_On a CLEAN tree: nothing got worse, exit 0. The gating shape is in the sandbox section below._

```
$ ./build/ripwire . --quality-delta
<!-- ripwire quality-delta: only what a change made WORSE against the floor named by baseline= below. FOUR floors, and they are not interchangeable: sidecar = the pinned .ripwire_quality_baseline snapshot, honored only because it was pinned at the CURRENT git HEAD; git-HEAD = no sidecar existed, so the working tree was auto-compared against the HEAD tree; git-HEAD (stale sidecar removed) = a sidecar existed, was pinned at a DIFFERENT sha, and this run DELETED it from your working tree before falling back to HEAD (re-pin with quality-baseline); git-HEAD (stale sidecar ignored) = same staleness verdict, but the file was left on disk (the read-only MCP arm, or an unlink that failed). Only the first is a floor YOU chose; the other three compare against HEAD, so anything already committed cannot appear. A FIFTH marker, ref-pair, means none of those: the verb was given a RANGE, so it compared two COMMITTED trees and no sidecar was read, written or deleted. Those reports carry base_ref= and target_ref= (the two RESOLVED shas, at full length, because a wave number gets quoted into handoffs) and OMIT at=, since the pair is the anchor. They also carry churn set to unavailable, which is the honest statement that one of the ten kinds, short-horizon-churn, cannot be measured there at all: it needs git history at the tree being judged, and both trees are materialized OUT of the repo into temp dirs. Its silence in such a report is therefore not evidence that nothing churned. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. Findings: complexity over the ccx bar, verbosity (LOC)/nesting/params regressions, new duplication, newly-dead, new public api-surface (contract drift), error-masking, short-horizon churn, new clone of a reused helper. THREE independent axes, applied in this order: (1) acked findings are suppressed entirely (acked= counts them, honestly); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin= attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor". EXIT 2 fires only on preexisting-worse AND major, i.e. gating="N" above; new-symbol rows never gate. Clone kinds classify by their member set (a group is new-symbol only if EVERY member is new); short-horizon-churn is preexisting by construction. exit 0 is NOT a verdict on the new-symbol rows — nothing that existed got worse, but the new debt is yours: read them. LIMIT: origin is canonId identity (path::scope::name), so a RENAMED or MOVED symbol reads as new — a regression carried in with a move classifies new-symbol and will not gate. Descriptive: weigh + fix the real ones, do not game the number (a wrong abstraction beats a low score). stale="N" is a SEPARATE axis, never gating, over the .ripwire_quality_acks ledger: an ack whose target no longer applies. Each sa row's why is target-gone (the key names no symbol/group any more) or finding-gone (the target survived, this kind just does not fire on it) — hygiene disclosure only, the ledger file is never auto-edited. Each row carries kind= (which of the measured axes regressed) and sym= (the canonical id it regressed on) — except duplication rows, which name the whole clone group rather than one symbol: members= is the group's member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports) — plus p="path:line" (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when no locator resolves), and every row the header's gating= counter counts also carries a gating attribute set to 1 — those are the rows the exit code fires on, and they are now marked positively rather than by the ABSENCE of sev/origin. (This sentence deliberately spells no attribute=value literal: the header counters are parsed by grep in several gates, and a quoted numeric example here would be matched first.) -->
<quality-delta baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="17" preexisting-worse="0" new-symbol="0" gating="0" at="061dcf667">
<sa kind="complexity" key="f8f91456c234074f" why="target-gone"/>
<sa kind="complexity" key="fcc9389382ada1b0" why="target-gone"/>
<sa kind="dead-code:preexisting" key="44da49cd9a05e5cc" why="finding-gone"/>
<sa kind="dead-code:preexisting" key="b89dc1827832d2fd" why="finding-gone"/>
<sa kind="duplication" key="4a6d699a2b38f977" why="finding-gone"/>
<sa kind="duplication" key="641ef9cd77a3e4d0" why="finding-gone"/>
<sa kind="duplication" key="69ca0068a413b01f" why="finding-gone"/>
<sa kind="duplication" key="6bbb331c18a5deaf" why="finding-gone"/>
<sa kind="short-horizon-churn" key="1b8cc1b791b2c572" why="target-gone"/>
<sa kind="short-horizon-churn" key="1fb1007e9ca0c20b" why="target-gone"/>
<sa kind="short-horizon-churn" key="8bd48de4f0863ced" why="target-gone"/>
<sa kind="short-horizon-churn" key="c00a0f11de7e013b" why="target-gone"/>
... [6 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--test-gate`, `--dmm`, `--json`

**Caveats (stated by the binary):**

- Same grammar --dmm= takes, and A...B is REFUSED rather than read as A..B.
- Use it to measure a whole integration branch at once (--quality-delta=<merge-base>..<head>): per-lane checks each compare against their own baseline and cannot see a regression the WAVE introduced.
- ONE KIND CANNOT BE MEASURED HERE and says so as churn="unavailable": short-horizon-churn needs git history at the tree being judged, and both trees are materialized OUT of the repo into temp dirs.

### `--dmm[=REV|A..B]`

**Answers:** the DELTA MAINTAINABILITY MODEL scalar: ONE comparable number in [0,1] for a change, so quality becomes TRENDABLE across commits instead of a per-kind list (di Biase, Rastogi, Bruntink and van Deursen, TechDebt 2019;

thresholds and arithmetic from PyDriller's deltamaintainability reference implementation). Bare = the WORKING TREE vs git HEAD (what --quality-delta compares); =REV = that commit vs its FIRST PARENT (the per-commit scalar); =A..B = tree B vs tree A. A UNIT is a function/method definition with a body; its VOLUME is its line span. Per property a unit is LOW risk iff size: loc<=15, complexity: cyclomatic<=5, interfacing: params<=2. good = low-risk volume ADDED plus high-risk volume REMOVED; bad = low-risk REMOVED plus high-risk ADDED; dmm = good/(good+bad). So DELETING a god function scores 1.000 and GROWING one scores 0.000. The three sub-scores (size/complexity/interfacing) are emitted alongside the combined one because they are separately actionable; the combined one POOLS them (summed good over summed good+bad) and is labelled combine="pooled", since the paper publishes the three separately and no aggregate. IT IS A DELTA, NEVER A LEVEL: a unit you edit without changing its size, complexity or parameter count sits in the same bin with the same volume on both sides and contributes NOTHING. Touching bad code is not punished, deliberately, because a gate that punishes it is a gate people route around. dmm="UNAVAILABLE" means good+bad was 0 (a rename, a literal edit, a comment reflow): the change is outside what the model measures. That is NEVER to be read as 1.000 or 0.000, and reason= says which case it was. Same token per property. VOLUME IS PHYSICAL LINE SPAN (size_metric="physical-loc"), where the reference implementation uses non-comment non-blank lines, so a heavily commented unit crosses the size threshold here earlier. NO THRESHOLD, NO VERDICT, ALWAYS EXIT 0.

**Shaped by:** `--quality-delta`

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

A contract is PER DEFINITION, so a SYM matching several definition sites REFUSES (exit 1) and lists the file:name spellings that pick one — unlike --callers/--uses, this verb may not union overloads and disclose defs=. A .ripwire_notes entry targeting SYM (or its file) rides along as a <note> child, the same row shape --for/--expand surface.

**Try it**

_Fast per-symbol post-edit contract check vs git HEAD (unchanged on a clean tree)._

```
$ ./build/ripwire . --edit-check=rankGraphTeleport
<!-- ripwire edit-check: SYM's contract (param count + publicness) NOW vs git HEAD — unchanged/new-symbol/contract-change — plus its 1-hop callers. A caller is flagged incompatible="1" when its argument count was reliably counted and NO definition in the folded set could accept it: every one has a FIXED arity that disagrees. A variadic, defaulted or implicit-receiver definition (a Python/Ruby method, whose params counts the self/cls the call site never writes) has no fixed arity and is never flagged. That makes the ARITY half one-sided — a call the compared definitions could accept is never flagged — but it is NOT a proof that the call site binds to THIS definition. Call edges are matched by NAME, so a receiver-qualified call to a same-named callee this tool does not index (a standard-library or third-party method) is measured against the one definition it does index; a clean, compiling tree can therefore carry a nonzero incompatible= with nothing edited at all, and on a widely-shared name it can be most of that name's callers. Read incompatible= as a fact about the tree as it stands — call sites worth OPENING, not a verdict — and status= as a fact about the edit. Warm path hits the qheadsnap/qsnap cache — never a full quality-delta style recompute. defs= is how many DEFINITIONS at this site (same file, same scope, same name — the overload set) are folded into this one contract; a selector matching more than one SITE is refused instead, so defs= only ever counts overloads. params_was and params_now are the MAX over that set on each side (the same MAX the baseline snapshot stores), and publicness is the OR. That MAX has TWO consequences, in opposite directions. It can read like a break and not be one: adding a WIDER overload beside an unchanged one raises params_now with no existing definition altered, so it reports status="contract-change" with incompatible="0" and a def row still carrying the old parameter count — no seen caller breaks. And it can read like safety and not be: REMOVING an overload whose parameter count is BELOW the MAX moves neither number, because the MAX survives on both sides, while the call site that used the removed definition no longer binds. defs_was=/defs_now= is what closes that: the count of definitions sharing this symbol's CANONICAL ID on each side. That population is the one the baseline snapshot buckets by, so the two numbers answer the same question and are equal on an unedited tree — it is deliberately NOT the root's defs=, which is the same bucket narrowed to this FILE (a contract is per definition site), so where a scope-less name also exists in another file defs= is the smaller of the two. status is therefore the join of THREE was-vs-now facts — the params MAX, publicness, and the definition COUNT — and change= names which of them carried it. change= adds broken-callers when a seen caller is also flagged, but never on its own — for the reason stated at the top: incompatible= describes the TREE and status= describes the EDIT, so a headline must not turn on it. RESIDUAL: an overload whose arity changes BELOW the MAX while the COUNT stays the same moves none of the three. The root's incompatible= is the COUNT of flagged callers (a c row's incompatible="1" is the per-caller flag). p= is the definition the selector resolved to; when defs is above 1 EVERY folded definition is listed as its own def row (p=, t=, params=), which is what tells a widened single definition apart from an added overload. At defs="1" no def row is emitted: the root's own p=/t= is that definition, and params_now is its parameter count. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<edit-check sym="rankGraphTeleport" t="fn" p="src/graph.h:2135" status="unchanged" defs="1" callers="6" incompatible="0" at="061dcf667" counts_floor="1" root=".">
<c n="runEval" p="src/eval.h:168"/>
<c n="rankGraph" p="src/graph.h:2176"/>
<c n="anchoredLexicalRank" p="src/graph.h:2512"/>
<c n="churnRankedGraph" p="src/main.cpp:12924"/>
<c n="runDefaultMap" p="src/main.cpp:13039"/>
<c n="getIndex" p="src/mcpindex.h:950"/>
</edit-check>
```

**Shaped by:** `--impact`, `--edit-target-file`, `--slice`

**Caveats (stated by the binary):**

- A contract is PER DEFINITION, so a SYM matching several definition sites REFUSES (exit 1) and lists the file:name spellings that pick one — unlike --callers/--uses, this verb may not union overloads and disclose defs=.

### `--replace-symbol-body=TARGET`

**Answers:** atomically replace one uniquely-resolved definition with exact bytes from --edit-payload=FILE|-

### `--insert-before-symbol=TARGET`

**Answers:** atomically insert the payload immediately before one uniquely-resolved definition

### `--insert-after-symbol=TARGET`

**Answers:** atomically insert the payload immediately after one uniquely-resolved definition.

TARGET is a symbol name, or a freshness-pinned sym# handle emitted by --grep --handles.

### `--edit-payload=FILE|-`

**Answers:** required exact byte payload ('-' reads stdin);

empty payloads refuse, never imply deletion

**Shaped by:** `--replace-symbol-body`

**Caveats (stated by the binary):**

- empty payloads refuse, never imply deletion

### `--edit-target-file=PATH`

**Answers:** optional file-path substring disambiguating a same-named definition.

RELATIVE (matched against the indexed spelling) or ABSOLUTE (matched against the file's resolved on-disk path), so the path a receipt or a trace hands you works verbatim. These three CLI verbs reuse the MCP edit engine: freshness hash, lock, pre-rename recheck, fsync, mode preservation and atomic rename. Every refusal leaves the target byte-identical. Success prints a JSON receipt; follow with --edit-check=SYM and --affected=FILE. Single-root only.

**Caveats (stated by the binary):**

- optional file-path substring disambiguating a same-named definition.

### `--edit-plan=FILE`

**Answers:** versioned JSON multi-edit transaction: {version:1, edits:[{op,target,file?,payload}]}

### `--dry-run | --apply`

**Answers:** the plan's explicit mode: --dry-run preflights and prints the receipt without writing, --apply commits;

exactly one of the two is required. Payload paths are relative to the plan file and CONFINED to its directory: a path resolving outside it (an absolute path, a '..' escape, or a symlink pointing out) refuses, naming the path it resolved to, and the receipt's payload_path shows what each op will READ. Every target/payload/span is preflighted before any write; overlaps refuse. Apply holds sorted per-file locks and atomically renames each file, re-verifying EACH file's bytes immediately before ITS OWN write (recheck_before_each_write in the receipt) so a non-cooperating external writer is detected rather than clobbered. Prior files roll back on a later write failure or such a detection; the message says which happened and how many files it restored. A crash between file renames remains a disclosed limit.

**Caveats (stated by the binary):**

- Payload paths are relative to the plan file and CONFINED to its directory: a path resolving outside it (an absolute path, a '..' escape, or a symlink pointing out) refuses, naming the path it resolved to, and the receipt's payload_path shows what each op will READ.
- A crash between file renames remains a disclosed limit.

### `--safe-delete=SYM`

**Answers:** "can I delete this?" — ONE call composing signals the tool already computes for one already-resolved SYM: 1-hop callers=, the transitive --impact blast radius (impact_reaches=), every --uses read/write/import/call/extends site (uses=), how much of the blast radius the tested= lens covers (tested_self=/radius_tested=/radius_untested=), and --dead-code's own high-confidence shape at defs=1 (dead_code_candidate=).

ambiguous_callers= names callers whose own calls include an ambiguously-resolved one (g.ambOut) — a caveat, not a count of proven-wrong edges. FACTS only: risk= names what was found — none-found (zero callers AND zero uses), untested-radius (a radius exists and none of it is test-covered), or uses-exist (a radius exists and some of it is tested) — never a go/no-go verdict.

**Shaped by:** `--json`

**Caveats (stated by the binary):**

- ambiguous_callers= names callers whose own calls include an ambiguously-resolved one (g.ambOut) — a caveat, not a count of proven-wrong edges.
- FACTS only: risk= names what was found — none-found (zero callers AND zero uses), untested-radius (a radius exists and none of it is test-covered), or uses-exist (a radius exists and some of it is tested) — never a go/no-go verdict.

### `--slice=SYM[:VAR]`

**Answers:** NAME-BASED intra-procedural def-use slice of variable VAR inside the ONE uniquely-resolved definition SYM (statement-level def-use edges as a queryable primitive — the ARISE result, arXiv:2605.03117).

One <s l= k= t=> row per line touching VAR, source order: k=def|use|both, t=param|decl|assign|call-arg|read (strongest role on the line), CDATA = the trimmed source line; defs=/uses= count occurrences. Bare --slice=SYM lists the sliceable locals (<v n= l= t=/> rows) so a caller can pick VAR. LIMITS in the legend, not implied: no alias analysis, no flow sensitivity, nested-scope shadowing may over-include. SYM matching several definition sites REFUSES (exit 1) listing the file:name spellings that pick one, like --edit-check. Served: C/C++/ObjC (+CUDA/Metal), Python, JS/TS, Go, Java, Rust — other indexed languages refuse loudly (never an empty success). Single-root only.

**Caveats (stated by the binary):**

- LIMITS in the legend, not implied: no alias analysis, no flow sensitivity, nested-scope shadowing may over-include.
- SYM matching several definition sites REFUSES (exit 1) listing the file:name spellings that pick one, like --edit-check.
- Served: C/C++/ObjC (+CUDA/Metal), Python, JS/TS, Go, Java, Rust — other indexed languages refuse loudly (never an empty success).

### `--pr-context[=BASEREF]`

**Answers:** no-LLM review-evidence bundle for the diff (working-tree, or vs BASEREF): per changed file, its symbols + callers + blast radius + affected tests + co-change partners + owners.

With --max-tokens=N the bundle degrades to fit: per-file structural counts survive for ALL changed files, the deep detail (caller/co-change lists, per-symbol rows) trims deepest-first, and truncated= names what was dropped (est_tokens= reports the fit). ANCHORING: the BASEREF form diffs against merge-base(BASEREF,HEAD), never BASEREF's tip — "what did THIS work change since it forked", not "how do the two trees differ today". base_moved= counts the paths BASEREF moved since the fork that this work never touched (excluded, not silently); anchor="ref-tip-two-dot" = no merge-base (unrelated history). direction= always names the SIDE you are reading, and a no-ref-work row fires when BASEREF's tip IS the merge base -- it carries no divergent work, so every row is HEAD's. --merge-scout=REF[,REF...] read-only cross-branch overlap: for each REF, the symbols it changed vs its merge-base with HEAD (git-archive TEMP copies — never checked out, never mutates a ref); the dirty working tree joins as an implicit extra arm. Pairwise: a changed symbol on TWO arms is a same-symbol conflict, two arms touching different symbols in the same file is a textual risk; <landing order=...> is the fewest-conflicts-first greedy land order (ties: ref name asc). An unresolvable REF refuses loudly (exit 1, names the ref) before any archive work. ANCHORING: every arm is diffed against its OWN merge-base with HEAD, never against live HEAD — a file an arm never opened can never show up because the live line moved. head_conflicts= is what that anchor hides, kept as its own row class: symbols this arm changed that the LIVE LINE also changed since the arm forked (HEAD is not an arm, so no pairwise comparison can see it). Single-root only. --plan-lanes=N --task=GOAL PRE-HOC lane plan: BEFORE a line is written, if this task is split across N isolated worktrees (N=2..16), which lanes would COLLIDE and in what order should they land. Where --merge-scout says "these branches already conflict", this says "these lanes WOULD conflict if assigned this way" — no ref to resolve, no archive, no re-ingest. JSON on stdout, always (redirect it: > .ripwire_lanes.json); ripwire writes no file. Exit 0 whenever a plan was produced, INCLUDING when conflicts are predicted (conflicts are data, and the landing order exists to handle them); exit 1 only for refusals. A claim keys on path+scope+name, never on id= (id degrades to a bare NAME when no scope was captured, so free functions in different files would collide); id= is carried per row for addressability, null when it would be bare, with id_addressable saying so. Three separate pair classes: conflicts[] (same claim key on both lanes — git will fight), same_file_risk[] (different keys, same file, aggregated per file), contract_touch[] (one lane's claim sits in another's blast radius — an adaptation, NOT a merge conflict). The conflict test runs on CLAIMS, never on blast radii. warnings[] carries every honest limit in band with a stable code. Single-root only. AUTO-CARVE SPLITS THE RANKED SURFACE, NOT YOUR SENTENCE: if your task has enumerable parts, use --brief and write one line per part. --plan-lanes --brief=FILE  the explicit form of the above: one non-blank line per lane, N = the line count. Each line is ranked on its own — no community carve, no bin packing — so the lane boundaries are the ones you wrote. This is the mode whose precision is defensible; prefer it when you can. Lane isolation is a QUALITY argument, not a speed one (CAID, arXiv 2603.21489: 63.3% vs 55.5% shared, largest gains on weaker lane models — and wall clock got WORSE).

**Try it**

_No-LLM review-evidence bundle for the working-tree diff (clean tree = empty)._

```
$ ./build/ripwire . --pr-context
<!-- ripwire pr-context: no-LLM review-evidence bundle per changed file — defined symbols, their callers, blast radius (transitive dependents), affected tests, co-change partners not in the diff, and owners. base=working-tree. skipped_mode_only=diffs that changed a file's MODE and nothing else (e.g. chmod) excluded from the changed set; a pure RENAME is content-identical too but is NOT excluded — it is a changed file, listed at its new path. files= means two different things by DEPTH here and is deliberately not renamed (15 consumers read the root one): on the ROOT it is the CHANGED file count; on each <impact/> child it is the distinct files dependents= reaches (changed + non-changed), so dependents="0" implies files="0" and vice versa — never an impossible-looking dependents>0/files=0. files_other= on the same <impact/> is the non-changed subset (a changed file's dependents inside OTHER changed files have no <f> row of their own — they are already shown as their own <file> section); it is NOT the <f> row count — see the row-cap sentence below. Files are ordered by BLAST RADIUS (transitive dependents descending, path breaking ties), not alphabetically. sections= on changed-symbols counts a doc file's headings, collapsed into that number instead of one callers-zero row each; count= still counts every INDEXED symbol, sections included, so count minus sections is the number of rows that follow. Every nested list below is a TOP-N subset of its element's own total, fixed per element (impact <f> at 20, per-symbol <caller> at 12, cochange <partner> at 12, tests <test> at 40, owners <author> at 5 — the L0 defaults; max-tokens only lowers these further via the trim ladder, nothing raises them past L0): each capped element carries its own shown=/capped= pair so the cut is never silent — for the untrimmed list use impact=SYM/callers=SYM (blast radius/callers), affected=FILE or situ (tests), cochange (partners), or owners (authors) instead. direction= names which SIDE this bundle reviews (worktree-since-head, head-since-fork, head-since-ref-tip); a no-ref-work row says the base ref's tip IS the merge base, i.e. it carries no divergent work of its own. deterministic. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<pr-context base="working-tree" root="." direction="worktree-since-head" files="0" skipped_mode_only="0" at="061dcf667" counts_floor="1">
<!-- no changed files in the index (clean tree, or the diff touched only non-indexed files) -->
</pr-context>
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
<!-- ripwire stray-content: per ref, the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. v="superseded" means the live line removed the same base code this ref removed (redone/del) — it re-implemented the work, the case `git cherry` cannot see; v="unmerged" means the work is genuinely absent; merged refs are omitted. Read-only: git cat-file/diff/ls-tree only, one batched cat-file for the whole sweep, every blob reduced once per sha. Line-granular, not semantic: see the ripwire help text for the limits. ANCHORING is a deliberate hybrid: the SCOPE is base anchored (only lines the ref itself authored vs its merge base are ever considered, so a file the ref never opened cannot appear because the live line moved), while the ABSENCE test is HEAD anchored on purpose (does the live line have this content TODAY is the question being asked, and it is only answerable against live HEAD). v="unknown" with ok="0" means this ref could NOT be analysed at all because it has no merge base with HEAD, which on a SHALLOW clone (the checkout default in CI) is every ref: it is not a claim that the ref is merged, and the fix is to deepen the clone. The four buckets are exhaustive, so unmerged plus superseded plus merged plus unknown always equals refs. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that there is nothing here to be stray FROM; refs= is that fact as a number. TRUNCATION: a ref row ends with a more element (more files=N) when its own file listing was capped; shown plus that number equals the ref's files= total, always. That inner listing is a SECONDARY listing (it repeats complete and identical on every page) and is capped by detail, not by limit / offset, which page the OUTER ref listing and report their own shown= / capped=. -->
<stray-content head="061dcf667" head_ref="lane/t3-anchor-only" refs="45" blobs="7" unmerged="1" superseded="0" merged="44" unknown="0">
<ref name="lane/lbround-instrument" tip="a0204cac2" date="2026-08-22" base="3702693f6" ok="1" v="unmerged" stray="787" files="6" superseded="0">
<file p="bench/recalleval/run_extcorpus.py" v="unmerged" stray="259" authored="259" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/recalleval/REGISTRATION-lbround-draft.md" v="unmerged" stray="190" authored="190" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/recalleval/labels_extcorpus_django.tsv" v="unmerged" stray="137" authored="137" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/recalleval/labels_extcorpus_webpack.tsv" v="unmerged" stray="135" authored="135" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/recalleval/extcorpus.lock" v="unmerged" stray="52" authored="52" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/recalleval/run_recalleval.py" v="unmerged" stray="14" authored="14" del="2" redone="0" sim="0.09" head-touched="0"/>
</ref>
</stray-content>
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
<landing-plan head="061dcf667" refs="0" unmerged="0" superseded="0" merged="0" undetermined="0" scouted="0" bounded="0" scout-ok="1" at="061dcf667">
</landing-plan>
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
<!-- ripwire abi: the cross-branch ABI-BREAK gate — layout(STRUCT) crossed with stray-content(BRANCH). Scope is what each ref AUTHORED: the paths `diff base..tip` reports against its own merge base, never `diff HEAD..tip` (a file the branch never opened cannot be a break the branch introduced, and on a long-lived tree that one distinction took 487 drift rows to 4). For each such path the SAME field-offset model layout uses is run LEXICALLY on the ref's git blob (never indexed) and compared against HEAD's computed fields. LISTED kinds: drift = the byte contract differs (the bug this check exists for, the only kind that exits 2); unknown = the ref-side copy could not be modelled (see ref_caveat) and is NEVER reported as unchanged; absent = the ref does not define the struct at that path. COUNTED but not listed (pass detail=N to print them): rename = identical slots and field types under different field NAMES, so every byte stayed where it was (a same-type field REORDER is lexically identical to a rename and lands here too); spelling and stub mirror layout's own harmless cases; head-moved = the ref's copy equals its own merge-base copy, so the LIVE LINE is what changed. head_only= counts candidate sites on paths only the live line touched (outside the authored scope); unmodelable= counts sites skipped because HEAD's own copy carries no baseline; every excluded row is on a counter, nothing is dropped silently. Structs that match are omitted entirely; a ref with no rows at all is counted in quiet=, and a ref whose every row is an excluded kind is counted in excluded_refs= and prints under detail=N. LIMITS: HEAD's own side is the WORKING TREE's layout answer, not a re-fetched git blob at HEAD's commit; a nested field type that ALSO changed on the ref resolves via HEAD's copy, not the ref's; the ref-side locator is index-free and file-scope (one namespace deep) only, so a struct nested in a class or wrapped in an extern C block reads absent rather than compared; the authorship anchor is per PATH, so a branch changing struct S in one file while the live line changes S's mirror in another is a merge hazard only layout(S) on the merged result can see. Single-root; read-only (cat-file/diff/merge-base only). -->
<abi head="061dcf667" head_ref="lane/t3-anchor-only" refs="45" candidates="781" compared="0" blobs="0" rows="0" shown="0" capped="0" dropped="0" excluded="0" head_only="15614" unmodelable="0" unrelated="0" broken_refs="0" quiet="45" excluded_refs="0" root=".">
</abi>
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
<!-- ripwire whereis: every LOCAL ref whose TREE contains this symbol, HEAD first, and within a ref SOURCE files before test files before docs, then definitions before references, then path and line. The doc demotion is ORDER ONLY: a doc line that quotes a signature still reads as a definition to the heuristic below and still says kind="def", it is simply printed after the code. kind= is answered by TWO different mechanisms, and head_labels= says which one answered for HEAD: with head_labels="index" a HEAD row is kind="def" iff the PARSED index puts a definition there (one row per index def site), while every NON-HEAD row — and every row when head_labels="lexical" (no index was supplied, the index knows no def of this name, or the working tree has drifted from HEAD) — is a LEXICAL shape heuristic over raw blob text that was never ingested: it reads a quoted signature in a doc as a definition and can miss an unusual declarator. refs_scanned= is the SCAN DENOMINATOR (how many refs besides HEAD were read), NOT a count of refs that matched — hits= and the rows are the matched set. on-head="0" alongside ref hits is the case this verb exists for: content that lives only on a branch. A TREE scan can only find content some ref still carries, so hits="0" on its own does not distinguish a name this repo never had from one it deleted; run with the with_history flag and the fate row says which, naming the commit that removed it. ANCHORING: none, by design. This verb runs no diff at all — it scans each ref's FULL tree, which is what lets it find content a branch merely INHERITED (exactly what a merge base anchored diff would exclude), so nothing here can fire merely because HEAD moved. at= is sha-only here (never +dirty): a tree scan reads committed blobs, so the working tree's cleanliness does not enter the answer. SELECTOR: this verb takes a BARE symbol name, not the file:name spelling that callers, uses, impact, around, lego and edit_check accept. A file:name spelling is searched as a LITERAL string, no tree contains it, and the result is a true but useless hits="0" shaped exactly like a name this repo never had. When that is what happened, a selector-note element says so and its retry= is the bare name to re-run with. Its absence beside hits="0" means the zero IS a measurement. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that this verb sees essentially one tree; refs_scanned= is that fact as a number, so read it before reading hits=. TRUNCATION: the trailing more element (more hits=N) is the rows AFTER this page, so shown plus more equals the rows from this page's offset on. It is not a second cap, and not a second vocabulary to page by: it is the SAME fact shown= / capped= / next_offset= carry, restated from the other end (what this page did not print). Page with limit= and offset=; the more element is absent exactly when this page reached the end of the hit list. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: every occurrence of the symbol in every TEXT blob of every scanned ref's full tree is printed above — nothing was capped or paged out, and no blob was oversized (over the 2 MB blob ceiling), missing or cut short by the stream. The denominator is refs_scanned= plus HEAD, under SCOPE above (local heads only), so with complete= present a ref absent from the rows genuinely lacks the symbol in its committed tree. Binary blobs are outside the claim (a text symbol cannot occur in one); an oversized TEXT blob suppresses the claim instead of being silently skipped. Its ABSENCE claims nothing. raise the default cap with limit=N (offset=M pages) -->
<whereis sym="rankGraphTeleport" on-head="1" refs_scanned="119" blobs="3553" hits="59618" head_labels="index" shown="60" capped="1" at="061dcf667">
<hit ref="HEAD" tip="061dcf667" date="2026-08-22" p="src/graph.h" l="2135" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="HEAD" tip="061dcf667" date="2026-08-22" p="present/deck5_ripwire_build.js" l="479" kind="ref" t="s.addText(&quot;$ ripwire . --callers=rankGraphTeleport&quot;, { x: 8.68, y: 2.1, w: 3.8, h: 0.3, fontFace: MONO, fontSize: 10, color: MUTED, margin: 0 });"/>
<hit ref="HEAD" tip="061dcf667" date="2026-08-22" p="present/deck5_ripwire_build.js" l="481" kind="ref" t="{ text: &quot;&lt;callers of=\&quot;rankGraphTeleport\&quot;\n  defs=\&quot;1\&quot; count=\&quot;6\&quot; &quot;, options: { color: TEXT } },"/>
<hit ref="HEAD" tip="061dcf667" date="2026-08-22" p="src/crossref.h" l="1602" kind="ref" t="// code above the real definition: `--whereis=rankGraphTeleport` opened with three kind=&quot;def&quot; rows into"/>
<hit ref="HEAD" tip="061dcf667" date="2026-08-22" p="src/eval.h" l="322" kind="ref" t="const std::vector&lt;float&gt; r = rankGraphTeleport( g, diffTeleport( ing, seedMask ) ).rank;"/>
<hit ref="HEAD" tip="061dcf667" date="2026-08-22" p="src/graph.h" l="90" kind="ref" t="// renormalized to Σ=1 in rankGraphTeleport — so every teleport-based"/>
... [23 more line(s); run it to see the whole thing]
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
<flags gates="66" dark_gates="59" compile="12" cmake="12" env="42" files="1333">
<gate name="FIXTURE_DARK_FEATURE" kind="compile" default="0" dark="1" regions="2" loc="13" reads="2" p="test/flagsfix/wiringFlags.h" l="10">
<read p="test/flagsfix/feature.cpp" l="10"/>
<read p="test/flagsfix/sub/nested.cpp" l="5"/>
</gate>
<gate name="PROFILE_PMC_VERBOSE" kind="compile" default="0" dark="1" regions="2" loc="10" reads="2" p="src/infra/profilePmc.h" l="76">
<read p="src/infra/profilePmc.h" l="79"/>
<read p="src/infra/profilePmc.h" l="435"/>
</gate>
<gate name="ALIASFIX_ALL" kind="compile" default="0" dark="1" regions="0" loc="0" reads="2" p="test/flagsaliasfix/aliases.h" l="7">
<aliases n="2" regions="2" loc="8"/>
<read p="test/flagsaliasfix/aliases.h" l="11"/>
<read p="test/flagsaliasfix/aliases.h" l="15"/>
... [17 more line(s); run it to see the whole thing]
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
<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an identifier, and a number is compared only against a declaration shaped literal the corpus binds uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say what was not proved. Read why="undefined" precisely: it says the name is defined NOWHERE in this repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is expected rather than rot. Run with the with_history flag to have git history separate the two: the lane then reports why="deleted" with the commit that removed the name, and downgrades a name this repo never had to unchecked r="never in history". A failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated= rather than drift=: an audit finding, a ledger row or an as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root element and is the commit the run was measured against (short sha, plus dirty when the tree had uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious reason that kind= is already taken on the same element; note that in the ranked map the same k= spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the same key. Prose claims, Status lines and dates are NOT checked. A `path:A-B` RANGE gets one more structural check: why="range-straddles" fires when A's innermost symbol does not reach B (got= then names whatever occupies B instead, tgt= that site), regardless of whether the doc names a symbol. weak-file-line, the one unchecked reason that names no symbol, gets a FREE disclosure instead of a verdict: <weak-file-line p= n=> groups, one per doc, list every such anchor whose line DOES sit inside an indexed symbol, and each <w> row's resolves-to= names it — the verb still does not know if that is the symbol the doc meant. This section sits beside, not inside, the <doc> rows: a doc can appear in it while still counting toward clean=, and every row it lists still counts once in the unchecked r="weak-file-line" tally below. FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. corpus= is the file population the anchors were checked AGAINST, and it is its OWN population rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, .metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still refuses, and a file the index lists but this run cannot open is counted by one and not the other. Neither number is wrong. corpus="0" means the corpus scan never ran at all, which happens only when the docs raised no anchor SHAPE whatsoever — prose ones included — so anchors="0" beside a non-zero prose= still scanned, and still reports the corpus it scanned. -->
<doc-drift docs="135" clean="120" anchors="1537" checked="597" unchecked="940" drift="44" dated="19" prose="9" corpus="1356" at="061dcf667">
<doc p="docs/COMMANDS.md" anchors="74" checked="21" drift="21" dated="0">
<a k="const" l="2372" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2373" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2374" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2375" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2376" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="const" l="2377" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2378" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2379" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2380" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2381" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2382" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--recall`, `--comment-coherence`, `--with-history`, `--plan-lint`, `--json`

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
<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an identifier, and a number is compared only against a declaration shaped literal the corpus binds uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say what was not proved. Read why="undefined" precisely: it says the name is defined NOWHERE in this repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is expected rather than rot. Run with the with_history flag to have git history separate the two: the lane then reports why="deleted" with the commit that removed the name, and downgrades a name this repo never had to unchecked r="never in history". A failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated= rather than drift=: an audit finding, a ledger row or an as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root element and is the commit the run was measured against (short sha, plus dirty when the tree had uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious reason that kind= is already taken on the same element; note that in the ranked map the same k= spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the same key. Prose claims, Status lines and dates are NOT checked. A `path:A-B` RANGE gets one more structural check: why="range-straddles" fires when A's innermost symbol does not reach B (got= then names whatever occupies B instead, tgt= that site), regardless of whether the doc names a symbol. weak-file-line, the one unchecked reason that names no symbol, gets a FREE disclosure instead of a verdict: <weak-file-line p= n=> groups, one per doc, list every such anchor whose line DOES sit inside an indexed symbol, and each <w> row's resolves-to= names it — the verb still does not know if that is the symbol the doc meant. This section sits beside, not inside, the <doc> rows: a doc can appear in it while still counting toward clean=, and every row it lists still counts once in the unchecked r="weak-file-line" tally below. FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. corpus= is the file population the anchors were checked AGAINST, and it is its OWN population rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, .metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still refuses, and a file the index lists but this run cannot open is counted by one and not the other. Neither number is wrong. corpus="0" means the corpus scan never ran at all, which happens only when the docs raised no anchor SHAPE whatsoever — prose ones included — so anchors="0" beside a non-zero prose= still scanned, and still reports the corpus it scanned. -->
<doc-drift docs="135" clean="124" anchors="1537" checked="589" unchecked="948" drift="42" dated="13" prose="9" corpus="1356" at="061dcf667">
<history probed="1" head="061dcf667" commits="739" removed-names="23094"/>
<doc p="docs/COMMANDS.md" anchors="74" checked="21" drift="21" dated="0">
<a k="const" l="2372" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2373" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2374" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2375" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2376" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="const" l="2377" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2378" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2379" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2380" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2381" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--whereis`, `--doc-drift`

**Caveats (stated by the binary):**

- Memoized per (repo, HEAD sha) — a commit is immutable, so the cache cannot go stale — and the blob covers the WHOLE repo, so a second question on the same commit costs a cache load, and --whereis reuses whatever --doc-drift already built.
- LIMITS: it walks HEAD's own history, so a name that only ever lived on an unmerged branch reads as never here (use --whereis's tree scan for that);
- A repo deeper than the walk bound reports truncated="1" and answers unknown — never "never" — for anything it did not reach.

### `--plan-lint=FILE`

**Answers:** the house PLAN/DESIGN format's STRUCTURE check (P3.2) — never semantics, that stays --doc-drift's job.

FILE is read directly (like --from-trace's FILE, not through the crawled index), so it need not live inside any indexed root. GRAMMAR, narrow and opt-in on purpose (this repo's own ~20 plan/design documents do not converge on one dialect): a card is exactly an H3 heading opening with a task id ("T" + 1-4 digits + up to 3 letters, e.g. T5 / T10 / T7b); a status ledger is exactly one heading (any level) whose text, stripped of a leading section mark, reads "Status" case-insensitively. A file showing NEITHER is reported dialect="0" with nothing further checked — not a failing lint, since most of this repo's own plans are exactly that file. Once dialect="1": every card's terminal line (the LAST non-blank line of its own body) must carry a status glyph, else status="missing"; an hourglass terminal line whose git-blamed commit sits more than stale_commits= commits behind HEAD is stale="1" (never claimed outside a git repo — see git=); a task id named in the ledger's own body with no matching card is a ledger-orphan (the REVERSE — a card the ledger never mentions — is not checked); a literal owed/OWED mention with no check-mark or cross anywhere LATER in the SAME document is undischarged (no cross-document tracking — a successor plan's discharge is invisible here, a stated limit, and this is substring matching with no semantic disambiguation: a doc that merely QUOTES the words reads the same as a real marker). Every gating row carries gating="1"; NOT CHECKED AT ALL: whether a card's claims are true, any heading level other than three for a card, a ledger heading spelled any other way. Exit 2 when dialect="1" and gating is non-zero (unlike --doc-drift's always-0 report — nothing here has a legitimate "dated on purpose" reading); exit 0 clean or dialect="0"; exit 1 only when FILE could not be read.

**Caveats (stated by the binary):**

- the house PLAN/DESIGN format's STRUCTURE check (P3.2) — never semantics, that stays --doc-drift's job.
- A file showing NEITHER is reported dialect="0" with nothing further checked — not a failing lint, since most of this repo's own plans are exactly that file.
- an hourglass terminal line whose git-blamed commit sits more than stale_commits= commits behind HEAD is stale="1" (never claimed outside a git repo — see git=);

### `--from-trace=FILE`

**Answers:** map a stack trace / sanitizer report / compiler-error text ('-'=stdin) onto the indexed symbols: table-driven frame extraction (python / asan / node / compiler / generic), ranked INNERMOST-first over in-corpus frames only (out-of-corpus frames are listed and counted, never ranked).

Each frame binds by its own NAME first (resolved_by="name") and falls back to the def enclosing its line (resolved_by="line") only when the name is absent/unknown/ambiguous — a trace older than the checkout therefore lands on the symbol it names, and a name-vs-line disagreement is disclosed as line_encloses=, never silently rebound. The counters close: in_corpus = suspects + merged + unresolved, with one <unresolved> row per file-matched frame no resolver could place. p= on a frame is the TRACE's own path:line; definition sites are the <sigs> l= values. Emits the same bundle shape as --for — top suspects' signatures + the innermost in-corpus symbol's FULL body; composes with --token-budget, and HONORS --max-tokens=N (it bounds the bodies) — one of the six shapes that do, alongside the default map, --recall, --connect, --pr-context and --for --detail=N. --top-k is NOT read here (the frame order is the trace's, not a rank). TEST-TO-SOURCE HOP: when the innermost in-corpus frame is a TEST symbol — a failing-test trace names the assertion, not the subject — a <test_hop> block also serves the source symbols reached from it: via="callee" is a real 1-hop call edge into non-test code, via="basename" the naming-convention source pair (foo_test.go/foo.go) used only where no call edge landed there. Labelled heuristic="1"; the frame map is unchanged and the innermost frame keeps rank 1, but the hop rows rank in <sigs> ahead of the remaining frames and the top one's body is served beside it. A non-test trace is unaffected. Unparseable input refuses loudly (never an empty map).

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

**Shaped by:** `--top-k`, `--token-budget`, `--help-task`, `--compress`, `--plan-lint`, `--run-trace`, `--json`

**Caveats (stated by the binary):**

- map a stack trace / sanitizer report / compiler-error text ('-'=stdin) onto the indexed symbols: table-driven frame extraction (python / asan / node / compiler / generic), ranked INNERMOST-first over in-corpus frames only (out-of-corpus frames are listed and counted, never ranked).
- The counters close: in_corpus = suspects + merged + unresolved, with one <unresolved> row per file-matched frame no resolver could place.
- --top-k is NOT read here (the frame order is the trace's, not a rank).

### `--run-trace="CMD"`

**Answers:** EXEC-MODE --from-trace — the whole fix-loop entry in ONE call.

Runs CMD under `sh -c` (the make trust model: your user, your environment, stdin=/dev/null, NO sandbox), captures stdout+stderr interleaved, and on a NON-ZERO exit serves the --from-trace bundle for the captured text (frames mapped innermost-first, the innermost in-corpus symbol's FULL body) plus a token-frugal <lines view="relevant"> cut of the error / frame-shaped output lines — shown=/relevant=/total= all disclosed, the cut never silent. The command's own exit code is ALWAYS disclosed on <run exit=>; a command that exits 0 gets a minimal success record (exit, measured duration_ms, a disclosed tail of output) and NO bundle — nothing failed, so there is nothing to map. The <run> record and captured lines are MEASURED (not deterministic, not claimed to be); the MAPPING of the captured text is byte-deterministic, and the document says which part is which. Composes with --token-budget (it bounds the bundle half, like --from-trace); --top-k / --max-tokens are not read here. ripwire's exit: 0 = the command succeeded; 4 = it failed or timed out (the report is on stdout either way); 1 = ripwire itself could not spawn it.

**Shaped by:** `--top-k`, `--token-budget`, `--run-timeout`

### `--run-timeout=SECONDS`

**Answers:** cap for --run-trace's command (default 600 s;

always disclosed as timeout_s=). A command still running at the cap has its whole process group killed and is reported timed_out="1" — an honest TIMEOUT, never an empty success. Modifies --run-trace only; refused loudly alone. --note-add="TARGET: text"  pin a field note (write-side memory) to TARGET — a canonical id (path::scope::name, as --for/--expand emit it) or a file path — in the committed, sorted .ripwire_notes at the repo root. The date is git's committer clock (HEAD), not wall time, so the line is deterministic; prints the exact written line. Also STAMPS the writing repo's HEAD sha + branch onto the note (a "done"/"fixed" claim is then anchored to the commit it was true at) — a non-git root or an unresolvable HEAD writes the plain unstamped line rather than a wrong sha. MUTATES one file; single-root only. text with no causal/decision marker ("because"/"chose"/"over"/"instead"/etc.) gets a gentle stderr tip toward the decision shape — never a refusal, the add always proceeds.

**Caveats (stated by the binary):**

- A command still running at the cap has its whole process group killed and is reported timed_out="1" — an honest TIMEOUT, never an empty success.
- text with no causal/decision marker ("because"/"chose"/"over"/"instead"/etc.) gets a gentle stderr tip toward the decision shape — never a refusal, the add always proceeds.

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

--token-budget overrides), the whole orientation dance in FIXED order — (1) routed+anchored ranking, (2) top-K full bodies, (3) their 1-hop caller signatures, (4) their field notes, (5) tests_to_run for the top files, emitted in FIXED order ranking>bodies>callers>notes>tests. Each section holds a FIXED, up-front proportional quota of the budget (rank40/body30/caller15/note5/test10, percent); an under-spent section's leftover quota ROLLS FORWARD to the next section, so a small budget still zeroes a section eventually but never past its own fair share. Each section truncates rank-adaptively and the header reports EVERY truncation (no silent caps). A tiny budget degrades to ranking-only WITH the truncation note. Refuses loudly without a task string.

**Try it**

_ONE budget-shared bundle: ranking + top bodies + caller sigs + notes + tests_to_run. CHANGED: <d> rows now carry n=/id=._

```
$ ./build/ripwire . --pack-task="add a new output format flag to the CLI"
<ctx task="add a new output format flag to the CLI" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]" root=".">
<!-- ripwire task bundle for "add a new output format flag to the CLI": one-call orientation under ONE budget — sections in FIXED order ranking > bodies > callers > notes > tests, quotas per section are FIXED (rank40/body30/caller15/note5/test10, percent of budget), unused quota ROLLS FORWARD to the next section — a small budget still zeroes a section, but never past its own share. each truncates rank-adaptively; every truncation reported here (no silent caps): on every section shown=rows kept, total=rows that qualified, capped=1 when they differ. bodies fill rank-first, so a bigger budget can keep FEWER, larger bodies — the count is not a quality measure. Row keys: n=name (chain it), id=canonical(when scoped), in=reuse-count (absent = not measured, never a false 0), l=line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller|callee; far=ranked but over 1 hop out; of_top denominator is per-section. callers: sorted by shared desc (ties=site order); shared=# of top-K anchors reached, omitted at 1. budget=12744 bytes (6000-token target, ceiling 14160) | ranking: full | bodies: 6 of 6 | callers: 3 of 3 | notes: none | tests: none | far: 6 of 6 -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<sigs>
<f p="src/tracein.h">
<d l="103" n="toUint" id="./src/tracein.h::detail::toUint" cx="3" ccx="3" in="3">
<doc>F7: a hostile/garbled frame line number (e.g. a fuzzed or truncated trace) can exceed UINT32_MAX; unchecked `v*10+d` wraps mod 2^32 (4294967297 -&gt; 1), which then confidently maps to a REAL line in the</doc>inline std::uint32_t toUint( std::string_view s, bool&amp; overflowed ) noexcept</d>
</f>
<f p="src/mcprefusal.h">
<d l="64" n="kMcpRequiredFields" id="./src/mcprefusal.h::rw::mcprefuse::kMcpRequiredFields" cx="0" ccx="0" in="0" pure="1">inline constexpr McpFieldSpec kMcpRequiredFields[] =</d>
<d l="235" n="McpValueSpec" id="./src/mcprefusal.h::McpValueSpec::McpValueSpec" cx="0" ccx="0" in="0">
<doc>verifier N2/N3/N11: the bad-VALUE refusal table</doc>struct McpValueSpec</d>
</f>
<f p="src/main.cpp">
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--token-budget`, `--for`, `--test-gate`, `--expand`, `--compress`, `--partition`, `--with-graph`

**Caveats (stated by the binary):**

- an under-spent section's leftover quota ROLLS FORWARD to the next section, so a small budget still zeroes a section eventually but never past its own fair share.
- Each section truncates rank-adaptively and the header reports EVERY truncation (no silent caps).
- A tiny budget degrades to ranking-only WITH the truncation note.

### `--partition=N`

**Answers:** (with --pack-task, N=2..16) FAN-OUT form: instead of one bundle, emit ONE shared common core plus N per-agent slices, so N parallel agents stop re-deriving the same orientation.

The task's ranked surface is carved along the call graph's own Louvain communities — a partition is a union of WHOLE modules (largest-first packing) so it reads coherently; when there are fewer modules than agents the widest is cut at its rank median and split="K" says so. The core is exactly the anchors a plain --pack-task would have bodied. --token-budget then means ONE AGENT's budget (core + its partition), not the document's — total_bytes reports the rest. Each inner <ctx> is byte-identical to a standalone call with that slice, so an orchestrator hands one bundle to one agent verbatim. LIMITS: overlap_mean/overlap_max are pairwise Jaccard over the ids each partition NAMES (window + bodies + their 1-hop neighbors) measured BEFORE budget trimming — a ceiling, not the trimmed truth; and on a task whose surface sits inside one module the split is a rank cut, not a semantic one (read split= and overlap_max before trusting the slices). Refuses loudly without --pack-task, or outside 2..16; --with-graph does not compose with it (N+1 bundles, no single graph — says so on stderr).

**Try it**

_Fan-out form: one shared core + 3 per-agent slices carved along call-graph communities._

```
$ ./build/ripwire . --pack-task="add a new output format flag to the CLI" --partition=3
<ctx-partitions partitions="3" requested="3" core_symbols="6" surface="42" modules="18" split="0" budget_per_agent_tokens="6000" core_budget_tokens="2040" partition_budget_tokens="3960" total_bytes="28479" overlap_mean="0.041" overlap_max="0.123" shared_symbols="10" union_symbols="100" core_overlap= … [line truncated: 8 more bytes on this line]
<!-- ripwire partitioned task bundle: ONE shared common core plus N minimally overlapping per agent slices, carved along the call graph's own community structure. Each bundle wraps one ctx document, exactly what a standalone pack task call with that slice would emit, so an orchestrator hands one bundle to one agent verbatim. budget_per_agent_tokens is the budget for core PLUS one partition, not the whole document; total_bytes is the bundles' combined size. overlap_mean/overlap_max are pairwise Jaccard over the ids each partition names (ranking window, bodies, and their 1 hop neighbors), measured BEFORE budget trimming, so they are a ceiling. shared_symbols counts the ids TWO OR MORE partitions name — NOT the ids every partition names; an id two of sixteen slices both carry is already duplicated work — and union_symbols the ids ANY partition names: one GLOBAL at-least-two over at-least-one pair, not an average. That ratio and overlap_mean (an average of PAIRWISE Jaccard) therefore answer different questions. They COINCIDE at partitions=2, where there is one pair and at-least-two IS its intersection while at-least-one IS its union, so the ratio equals that pair's Jaccard by identity; from 3 partitions on the two genuinely diverge, and neither is wrong. The remaining root counters, one clause each. requested= is the partition count N asked for and partitions= the bundles actually carved; partitions is lower only where the plan could not reach N, which is either a ranked surface that fit entirely in the shared core (partitions=0, nothing left to carve) or a surface holding fewer separable modules than N even after splitting. modules= is the distinct groups found on the assignable surface BEFORE any cut (a call-graph community, or the FILE where that surface carries no call edges), and split= the community cuts forced because those modules numbered fewer than N, so modules + split is the group count the bundles were packed from and split=0 means no cut was needed. core_symbols= is the shared core's size — the body anchors a plain pack task would have expanded, held out of every partition — and surface= is core_symbols plus the assignable remainder, i.e. the whole positive-rank window this plan carved up. core_budget_tokens= and partition_budget_tokens= are budget_per_agent_tokens split between the two halves one agent receives, and they sum to it. core_overlap is the share of the core bundle's own surface a partition reaches anyway. On each bundle, est_tokens and tokens are the SAME number: tokens is the original name kept for compatibility, est_tokens is the spelling the rest of the tool uses and the one to read. Both are that bundle's own bytes= divided by 2.36 B/tok — the DENSEST calibrated language rate — which is a different (deliberately conservative) currency from the default map's est_tokens, where the divisor is that corpus's own language-weighted rate: measured over real emitted bytes either way, but a bundle's number reads slightly HIGH, which is the safe direction for a per-agent budget. On this root element the unit is carried in the NAME instead (budget_per_agent_tokens, total_bytes) rather than by a separate unit attribute, which is a deliberate exception to the est_tokens convention and not a second estimator. -->
<bundle role="core" symbols="6" bytes="4046" tokens="1714" est_tokens="1714">
<ctx task="add a new output format flag to the CLI" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]" root=".">
<!-- ripwire task bundle for "add a new output format flag to the CLI": one-call orientation under ONE budget — sections in FIXED order ranking > bodies > callers > notes > tests, quotas per section are FIXED (rank40/body30/caller15/note5/test10, percent of budget), unused quota ROLLS FORWARD to the next section — a small budget still zeroes a section, but never past its own share. each truncates rank-adaptively; every truncation reported here (no silent caps): on every section shown=rows kept, total=rows that qualified, capped=1 when they differ. bodies fill rank-first, so a bigger budget can keep FEWER, larger bodies — the count is not a quality measure. Row keys: n=name (chain it), id=canonical(when scoped), in=reuse-count (absent = not measured, never a false 0), l=line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller|callee; far=ranked but over 1 hop out; of_top denominator is per-section. callers: sorted by shared desc (ties=site order); shared=# of top-K anchors reached, omitted at 1. budget=4332 bytes (2040-token target, ceiling 4814) | ranking: capped | bodies: kept 4 of 6 (capped) | callers: kept 2 of 3 | notes: none | tests: none | far: none -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<sigs capped="1">
<f p="src/tracein.h">
<d l="103" n="toUint" id="./src/tracein.h::detail::toUint" cx="3" ccx="3" in="3">
<doc>F7: a hostile/garbled frame line number (e.g. a fuzzed or truncated trace) can exceed UINT32_MAX…</doc>inline std::uint32_t toUint( std::string_view s, bool&amp; overflowed ) noexcept</d>
</f>
<f p="src/mcprefusal.h">
<d l="235" n="McpValueSpec" id="./src/mcprefusal.h::McpValueSpec::McpValueSpec" cx="0" ccx="0" in="0">
<doc>verifier N2/N3/N11: the bad-VALUE refusal table</doc>struct McpValueSpec</d>
... [17 more line(s); run it to see the whole thing]
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
<ctx task="pagerank power iteration" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]" root="." bundle="auto" bodies="2">
<!-- ripwire lens for "pagerank power iteration" [doc mentions: 4 docs discussing 3 top-ranked symbols surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="5042" -->
<sigs capped="1">
<f p="scripts/optremarks.py">
<d l="40" n="HOT_FILES" cx="0" ccx="0" in="0" churn="3" amp="37">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix entry points &quot;src/infra/radixSort…</d>
</f>
<f p="src/prconverge.h">
<d l="51" n="RankDisclosure" id="./src/prconverge.h::RankDisclosure::RankDisclosure" cx="0" ccx="0" in="0" churn="2" amp="17">
<doc>What a ranked document discloses about the power iteration that ordered it. `isPageRank == false…</doc>struct RankDisclosure</d>
<d l="73" n="renderDisclosure" id="./src/prconverge.h::rw::renderDisclosure" cx="12" ccx="15" in="10" churn="2" amp="27">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
</f>
<f p="src/graph.h">
... [17 more line(s); run it to see the whole thing]
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
<doctor checks="6" passed="5" at="061dcf667">
<c n="binary-path" ok="0" self="./build/ripwire" which="/opt/homebrew/bin/ripwire" on_path="1" same_file="0" self_mtime="1787400181" self_size="41669736" which_mtime="1786573138" which_size="38785080" hint="STALE: /opt/homebrew/bin/ripwire is older tha … [line truncated: 206 more bytes on this line]
<c n="grammars" ok="1" loaded="21" expected="21"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="4096" bytes="913092491" many="1" truncated="0"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="061dcf667"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="21"/>
<c n="tracked-binaries" ok="1" tracked="1685" binaries="6" non_git="0" truncated="0" stale="0"/>
</doctor>
```

**Shaped by:** `--agent`

**Caveats (stated by the binary):**

- "Dependent source" is a NAMING heuristic (same dir, same filename stem, e.g.
- A FAILING row (ok="0") also carries hint=, the derived verdict (which of self=/which= is stale and the fix, which grammar(s) failed to compile, why the cache dir isn't writable, ...) — a passing row never carries hint=.

### `--agent=codex`

**Answers:** (with --doctor) also inspect Codex's LIVE CLI-first integration: PATH binary, exact installed-skill manifest parity, advisory hook executability, and the secondary mcp_servers.ripwire command/--mcp args.

Read-only; emits fixed repair commands and never prints config contents or shell command lines. Other values refuse.

**Caveats (stated by the binary):**

- emits fixed repair commands and never prints config contents or shell command lines.

### `--skipped`

**Answers:** WHY the index does not contain a file, and which files it DOES contain but cannot vouch for.

<f p= why= bytes=/> per DROPPED file: why=oversize (limit= names the ceiling — --max-file-size, or the fixed .json/.yaml config ceilings it does not raise), why=excluded (--exclude hit), why=unsupported-ext (ext= has no grammar in this build — the class that hides a whole LANGUAGE). <h p= why= err= err_ratio= ws_freq=/> per INDEXED-but-suspect file, nothing dropped: why=degraded-parse (the parse holds ERROR/MISSING nodes — a parser-state fact, never a syntax verdict) and/or why=minified-suspect (ws_freq under 0.070 over the leading 4KB). <e x= files=/> per unindexed extension — what the map header rolls up as unindexed=. <lang n= files= symbols=/> per LANGUAGE this build DID extract from — the mirror of unindexed= (which names what it could NOT read at all); sorted files DESC then name ASC, absent means the language contributed nothing, never a printed zero; files= is a floor (a file with zero extracted symbols is not attributed to any language), symbols= is exact. The root states the ACCOUNTING INVARIANT indexed= + oversize= + excluded= = the enumerated candidate population, plus unsupported_ext=, excluded_dirs= (SUBTREES --exclude pruned: contents UNKNOWN, not zero), pruned_dirs= (SUBTREES this build always prunes by policy — the committed noise/vendor/build denylist and any dir holding a CMakeCache.txt — contents likewise UNKNOWN), degraded_parse=, minified_suspect=, unmeasured= (indexed files this run never parsed) and the effective ceilings, so a zero-row report still states its bounds. rows_capped="1" ⇒ rows are a sample of an exact count. Rows sort by path; composes with --max-file-size/--exclude and multi-root (rows carry the <label>/./<rel> spelling). Read-only; exit 0 always: a report, not a gate.

**Caveats (stated by the binary):**

- WHY the index does not contain a file, and which files it DOES contain but cannot vouch for.
- <f p= why= bytes=/> per DROPPED file: why=oversize (limit= names the ceiling — --max-file-size, or the fixed .json/.yaml config ceilings it does not raise), why=excluded (--exclude hit), why=unsupported-ext (ext= has no grammar in this build — the class that hides a whole LANGUAGE).
- <h p= why= err= err_ratio= ws_freq=/> per INDEXED-but-suspect file, nothing dropped: why=degraded-parse (the parse holds ERROR/MISSING nodes — a parser-state fact, never a syntax verdict) and/or why=minified-suspect (ws_freq under 0.070 over the leading 4KB).

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

### `--rank-by=pagerank|authority|hub|rrf|churn|churn-decay`

**Answers:** ranking signal (churn = git change-frequency prior, and stamps its own map with rank_by/window/at so it cannot pass for the structural one;

churn-decay = the same prior with each commit weighted 0.5^(age_days/90) instead of counted equally, so recent edits outweigh old ones. Its age clock is HEAD's OWN commit timestamp, never the wall clock, so the default (whole-history) run is byte-stable for a fixed tree; the half-life is disclosed in window=. default pagerank) --format=xml|columnar|rows output shape for the FLAT list verbs (--callers/--callees/--uses/--impact): xml (default, byte-identical) or columnar (a <paths> table + parallel arrays: fields= path,name,line,kind on --callers/--callees/--impact, path,line,role,in_id on --uses — the emitted block's own legend states the zip/n=/&#44;-escape contract; ~15-60% fewer tokens on multi-row results, by de-duplicating the repeated per-row markup + paths; results of a few rows can be LARGER — the paths/cols scaffold has a fixed cost). rows is an alias for columnar. Any OTHER verb refuses (exit 1) — it has no row list to re-encode. Map is unaffected.

**Try it**

_Rank by git change-frequency prior instead of PageRank._

```
$ ./build/ripwire . --rank-by=churn --top-k=5
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- rank_by=churn: k= is a git CHANGE-FREQUENCY prior over window=, not call-graph importance; the same corpus ranked by pagerank orders differently -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1329 symbols=11493 edges=14084 shown=5 est_tokens=761 ambiguous=5555 unresolved=3233 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:18,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r at="061dcf667" root="." rank_by="churn" window="18mo" est_tokens="761" pr_iters="28">
<f p="src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" k="0.0151">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0149">
</s>
... [8 more line(s); run it to see the whole thing]
```

**Shaped by:** `--since`

**Caveats (stated by the binary):**

- ranking signal (churn = git change-frequency prior, and stamps its own map with rank_by/window/at so it cannot pass for the structural one;
- Its age clock is HEAD's OWN commit timestamp, never the wall clock, so the default (whole-history) run is byte-stable for a fixed tree;
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

### `--legend=full|compact`

**Answers:** output legend posture for --for and --grep/--regex only.

full is byte-identical to the default; compact keeps every data/completeness attribute, adds a versioned schema id, and shortens repeated explanatory prose. Unsupported verbs refuse.

**Caveats (stated by the binary):**

- Unsupported verbs refuse.

### `--json`

**Answers:** machine-parseable JSON instead of XML, SAME content, keys mirror the XML attr names 1:1 — supported for the default map, --for, --pack-task, --callers/--callees/ --impact, --quality-delta, --test-gate (the CI/scripting verbs).

Every other verb (and --format=columnar/candidates, --detail, --map-diff, --scip composed with it) refuses loudly on stderr + exit 1 rather than silently falling back to XML. Deterministic: same 2-run byte-diff + stable key order contract as the XML. --limit=N --offset=M       paginate a high-cardinality verb. HONORED by: --deps --callers --callees --tree --lint --hotspots --clones --cochange --owners --communities --community --doc-drift --whereis --grep/--regex --match --pattern --impact --uses --exercises --seams --zoom --external-surface --dead-code --mentions --graph-query --stray-content --test-gate --readability --ensemble --quality-panel --context-ratio --nonlocal-state --comment-coherence --naming-consistency --safe-delete. Emit at most N rows, skipping the first M; N overrides the verb's own display cap (40 hotspot files, 30 co-change pairs, 60 whereis hits, 100 grep/match hits, 40 impact rows, 20 seam pairs, 40 readability rows, 40 ensemble symbol rows, 40 context-ratio symbol rows, 40 nonlocal-state rows, 200 graph-query rows / --top-k). With --offset alone (no --limit) the verb's own default page size applies and the root discloses limit="0" — on OUTPUT that 0 means 'no explicit --limit', never a zero-row page (the flag itself refuses --limit=0). Deterministic seams (rows are already sorted) so --offset=N is the exact continuation of the previous --limit=N page. The root element then carries shown= capped= total= has_more= next_offset= offset= limit= — loop until has_more="0" — EXCEPT the verbs with TWO INDEPENDENT listings, which carry the noun-prefixed form instead (one shown= could only describe one): --test-gate shown_tests=/tests_capped= + shown_untested=/untested_capped=, --communities shown_modules=/modules_capped= + shown_bridges=/bridges_capped=, --ensemble and --context-ratio shown_syms=/syms_capped= + shown_files=/files_capped=; the window takes the PRIMARY listing (--test-gate's <u> rows; its <t> rows repeat on every page, complete). Any verb NOT in that list REFUSES both flags (exit 1) rather than accepting and ignoring them: budget/top-k verbs (--for/--recall/--pack-task/--from-trace/ --expand/--outline/--pack-signatures/--format=candidates) are shaped by --top-k/--max-tokens/--token-budget, not a page; the rest (--path/--connect/ --around/--exemplar/--report/--mermaid/--map-diff/--metrics and the default map) answer with a single fixed-shape result that has no row list to window at all.

**Try it**

_JSON refusal shape: an unsupported verb refuses loudly instead of silently falling back to XML._

```
$ ./build/ripwire . --hotspots --json
(empty)
```

**Shaped by:** `--max-tokens`, `--token-budget`, `--for`

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
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1159 symbols=9317 edges=13135 shown=5 est_tokens=601 ambiguous=5513 unresolved=1740 precise=3 unindexed="scm:18,txt:11,xml:4,arch:2,cmake:2,jsonl:2" unindexed_exts=13 order=important-first -->
<r root="." est_tokens="601" pr_iters="33">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0192">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0097">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" k="0.0095">
</s>
... [6 more line(s); run it to see the whole thing]
```

**Shaped by:** `--skipped`, `--index-out`

### `--map-diff`

**Answers:** the FULL map, re-ranked with a PageRank teleport toward git-changed files (working tree vs HEAD) — changed files and their neighbours float up, but every file can still appear;

this is NOT a filter to only-changed symbols. changed="N" in the header names the seed file count (0 on a clean tree or no-git — teleport degrades to uniform; ranked CONTENT is then identical to the plain default map, but not byte-identical: the map-diff header keeps its changed= and at= stamp). Want only-changed instead? --pr-context.

**Try it**

_Full map re-ranked with teleport toward git-changed files — clean tree, so changed=0 and it degrades to the plain map._

```
$ ./build/ripwire . --map-diff --top-k=5
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1329 symbols=11493 edges=14084 shown=5 est_tokens=692 ambiguous=5555 unresolved=3233 precise=3 changed=0 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:18,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r at="061dcf667" root="." est_tokens="692" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0165">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0083">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" k="0.0082">
... [7 more line(s); run it to see the whole thing]
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
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1329 symbols=11493 edges=14084 shown=3 est_tokens=524 ambiguous=5555 unresolved=3233 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:18,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="524" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0165">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0083">
</s>
</f>
</r>
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
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1329 symbols=11493 edges=14084 shown=3 est_tokens=524 ambiguous=5555 unresolved=3233 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:18,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="524" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0165">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0083">
</s>
</f>
</r>
```

### `--max-file-size=N[K|M|G]`

**Answers:** skip files larger than N bytes (default 4MB;

raise for repos with big hand-authored source, e.g. --max-file-size=100M; suffix = 1024^n). .json carries a SECOND, fixed 256KB ceiling this flag does not raise (that size of .json is data, not config, and explodes the symbol table); files it drops are counted in the header's skipped_oversize=

**Try it**

_Skip files above a size bound before parsing (note the corpus shrink in the header)._

```
$ ./build/ripwire . --max-file-size=8K --top-k=3
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=785 symbols=3349 edges=877 shown=3 est_tokens=563 ambiguous=37 unresolved=269 precise=3 skipped_oversize=559 unindexed="jsonl:25,txt:22,scm:18,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="563" pr_iters="42">
<f p="test/regexfix/beta.py" layer="test">
<s t="fn" n="open" id="./test/regexfix/beta.py::Widget::open" k="0.0040">
</s>
</f>
<f p="src/infra/fastmath.h" layer="infra">
<s t="fn" n="max" id="./src/infra/fastmath.h::fastmath::max" k="0.0029">
</s>
</f>
<f p="src/alloccount.cpp">
... [4 more line(s); run it to see the whole thing]
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
<!-- ripwire callers/callees: the 1-hop call hierarchy read straight off the call graph. The callers form lists the symbols that CALL of=; the callees form lists the symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS that name resolved to (the rows UNION every def's neighbours), and count= the number of DISTINCT neighbour symbols (a floor, per counts_floor=), which the rows window with limit= and offset=. A neighbour that is an indexed function-like #define is a macro row (t="macro", role="macro" on the XML row): the edge crosses a macro expansion, not a plain call — rows carry no role= otherwise. Rows are ordered SOURCE first, then test/bench, then docs, and by path within a tier. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<callers of="rankGraphTeleport" defs="1" count="6" root="." counts_floor="1">
<s t="fn" n="runEval" p="src/eval.h:168"/>
<s t="fn" n="rankGraph" p="src/graph.h:2176"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:2512"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:12924"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:13039"/>
<s t="fn" n="getIndex" p="src/mcpindex.h:950"/>
</callers>
```

**Shaped by:** `--json`

**Caveats (stated by the binary):**

- consume a SCIP index as a PRECISION overlay: precise call edges replace name-based guesses (tagged prov="scip"), ambiguous= drops.
- Missing/corrupt index → degrades to name-based (never fails).

### `--mcp`

**Answers:** persistent index server (parse once, many warm queries) over stdio

**Shaped by:** `--no-stable`, `--agent`, `--listen`

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
ripwire --eval  (co-change recovery, averaged over 80 historical commits)
  ranker     recall@5  recall@10  recall@20
  ripwire        1.4%       3.3%      10.5%
  BM25          14.8%      20.1%      24.0%
  BM25sub       21.4%      23.8%      31.1%
  BM25body      23.7%      39.9%      48.0%
  fused          6.9%      12.4%      28.6%
  anchored      23.7%      39.9%      48.0%
  same-dir       2.2%       4.8%       5.8%
  random         0.4%       0.8%       1.5%   <- floor (random ranking over F=1329 files)
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
  subtoken  name         0.609     49.3%     75.3%     84.7%
  subtoken  doc-phrase   0.745     70.0%     78.7%     82.0%
  name-exact name         0.836     76.0%     94.7%     98.0%
  name-exact doc-phrase   0.022      1.3%      2.7%      3.3%
  anchored  name         0.608     50.0%     72.7%     80.0%
  anchored  doc-phrase   0.742     70.0%     78.0%     80.0%
  routed    name         0.838     76.0%     94.7%     99.3%
  routed    doc-phrase   0.743     70.0%     78.0%     81.3%
  note: routing chose name-exact on 148/150 NAME queries (a NAME query is always identifier-shaped);
        the confidence gate routes doc-phrase queries to name-exact ONLY when EVERY content word names a symbol
        (or an explicit camel/snake token appears) AND every matched name is specific enough to anchor on —
        a common name (many definitions, or a subtoken carried by many symbol names) declines the route — so
... [2 more line(s); run it to see the whole thing]
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
