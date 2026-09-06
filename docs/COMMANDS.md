# ripwire — every flag, generated from the binary

**This file is generated. Do not hand-edit it.** Regenerate with:

```bash
python3 docs/docs_commands_build.py --bin build/ripwire
```

The flag surface below is read from `ripwire --help`, so it cannot disagree with the shipped
binary. `test/docscommandscheck.sh` fails if it ever does — in either direction.

Sample output is lifted from a real recorded run (`docs/captures/COMMANDS_showcase_2026-09-05.md`), trimmed to the first few lines and
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

**navigate / answer a question** — [`--around`](#around-sym) · [`--callers`](#callers-sym) · [`--callees`](#callees-sym) · [`--uses`](#uses-sym) · [`--graph-query`](#graph-query-expr) · [`--external-surface`](#external-surface) · [`--path`](#path-src-dst) · [`--connect`](#connect-a-b-c) · [`--impact`](#impact-sym) · [`--verify`](#verify-claim) · [`--mentions`](#mentions-sym) · [`--affected`](#affected-f1-f2-sym) · [`--exercises`](#exercises-testfile) · [`--situ`](#situ-f1-f2) · [`--handoff`](#handoff) · [`--test-gate`](#test-gate-f1-f2) · [`--grep`](#grep-str-regex-pat) · [`--grep-context`](#grep-context-n-grep-before-n-grep-after-n) · [`--and`](#and-str) · [`--not`](#not-str) · [`--grep-scope`](#grep-scope-line-file) · [`--grep-in`](#grep-in-code-any) · [`--handles`](#handles) · [`--match`](#match-query) · [`--pattern`](#pattern-pat) · [`--query`](#query-terms)

**zoom the detail ladder** — [`--detail`](#detail-n) · [`--pack-signatures`](#pack-signatures) · [`--outline`](#outline-a-b) · [`--expand`](#expand-a-b) · [`--compress`](#compress) · [`--pack-top-n`](#pack-top-n-n) · [`--no-redact`](#no-redact)

**assess quality / structure** — [`--metrics`](#metrics) · [`--deps`](#deps) · [`--hotspots`](#hotspots) · [`--clones`](#clones) · [`--readability`](#readability) · [`--nonlocal-state`](#nonlocal-state) · [`--ensemble`](#ensemble) · [`--quality-panel`](#quality-panel-preset) · [`--context-ratio`](#context-ratio) · [`--naming-calibration`](#naming-calibration) · [`--naming-consistency`](#naming-consistency) · [`--naming-locals`](#naming-locals) · [`--comment-coherence`](#comment-coherence) · [`--cochange`](#cochange-file) · [`--cochange-recur`](#cochange-recur-k) · [`--cochange-groups`](#cochange-groups) · [`--since`](#since-rev-date) · [`--arch`](#arch-file) · [`--arch`](#arch-file-baseline) · [`--arch`](#arch-file-baseline-update) · [`--lint`](#lint) · [`--lint-catalog`](#lint-catalog) · [`--lint-rules`](#lint-rules-dir) · [`--lint-select`](#lint-select-prefix) · [`--lint-ignore`](#lint-ignore-prefix) · [`--sarif`](#sarif) · [`--with-profile`](#with-profile-file) · [`--communities`](#communities) · [`--community`](#community-id) · [`--zoom`](#zoom-depth) · [`--report`](#report) · [`--seams`](#seams) · [`--mermaid`](#mermaid) · [`--owners`](#owners-sym) · [`--dead-code`](#dead-code-dir) · [`--quality-baseline`](#quality-baseline) · [`--allow-dirty`](#allow-dirty) · [`--quality-delta`](#quality-delta) · [`--quality-delta`](#quality-delta-rev-a-b) · [`--dmm`](#dmm-rev-a-b) · [`--quality-ack`](#quality-ack-reason) · [`--ack-only`](#ack-only-substr-substr) · [`--scope`](#scope-glob-glob) · [`--edit-check`](#edit-check-sym) · [`--replace-symbol-body`](#replace-symbol-body-target) · [`--insert-before-symbol`](#insert-before-symbol-target) · [`--insert-after-symbol`](#insert-after-symbol-target) · [`--edit-payload`](#edit-payload-file) · [`--edit-target-file`](#edit-target-file-path) · [`--no-post-check`](#no-post-check) · [`--edit-plan`](#edit-plan-file) · [`--dry-run`](#dry-run-apply) · [`--safe-delete`](#safe-delete-sym) · [`--slice`](#slice-sym-var) · [`--slice-flow`](#slice-flow-back-fwd-both) · [`--slice-depth`](#slice-depth-n) · [`--at`](#at-file-line) · [`--pr-context`](#pr-context-baseref) · [`--merge-scout`](#merge-scout-ref-ref) · [`--plan-lanes`](#plan-lanes-n-task-goal) · [`--plan-lanes`](#plan-lanes-brief-file) · [`--stray-content`](#stray-content-substr) · [`--plan`](#plan) · [`--abi`](#abi) · [`--whereis`](#whereis-sym) · [`--flags`](#flags-substr) · [`--flip`](#flip-name) · [`--layout`](#layout-struct) · [`--field-affinity`](#field-affinity-struct) · [`--doc-drift`](#doc-drift-substr) · [`--doc-drift`](#doc-drift-gateability) · [`--with-history`](#with-history) · [`--plan-lint`](#plan-lint-file) · [`--from-trace`](#from-trace-file) · [`--run-trace`](#run-trace-cmd) · [`--run-timeout`](#run-timeout-seconds) · [`--note-add`](#note-add-target-text) · [`--notes`](#notes) · [`--pack-task`](#pack-task-task) · [`--partition`](#partition-n) · [`--with-graph`](#with-graph) · [`--export`](#export-cc-json-file) · [`--batch`](#batch-file)

**self-diagnosis** — [`--doctor`](#doctor) · [`--agent`](#agent-codex-claude) · [`--skipped`](#skipped)

**security — scan skill files for injection / exfiltration patterns (exit 2 = CRITICAL, 1 = WARN,** — [`--scan-skill`](#scan-skill-file) · [`--scan-skills`](#scan-skills-dir) · [`--force`](#force)

**knobs / modes** — [`--rank-by`](#rank-by-pagerank-authority-hub-rrf-churn-churn-decay) · [`--format`](#format-xml-columnar-rows) · [`--format`](#format-candidates) · [`--legend`](#legend-full-compact) · [`--json`](#json) · [`--limit`](#limit-n-offset-m) · [`--exclude`](#exclude-substr) · [`--map-diff`](#map-diff) · [`--cache`](#cache-path) · [`--index-out`](#index-out-base) · [`--no-cache`](#no-cache) · [`--no-ignore`](#no-ignore) · [`--max-file-size`](#max-file-size-n-k-m-g) · [`--refetch`](#refetch) · [`--scip`](#scip-index-scip) · [`--pin-census`](#pin-census-file) · [`--mcp`](#mcp) · [`--listen`](#listen-host-port) · [`--mcp-token`](#mcp-token-t) · [`--allow-remote-edits`](#allow-remote-edits) · [`--eval-stray`](#eval-stray-file) · [`--eval`](#eval) · [`--eval-retrieval`](#eval-retrieval) · [`--eval-mined`](#eval-mined-file) · [`--eval-skills`](#eval-skills-file) · [`-h`](#h-help) · [`-v`](#v-version)

---

## understand a codebase cold

### `--top-k=N`

**Answers:** keep the N highest-ranked symbols (default 200) — applies to the default map, plain --query, and --format=candidates (incl.

with --for). --for's OWN signature/lego/compose bundle self-limits via --pack-top-n instead — --top-k is INERT there (documented, not fixed — a real fix is a behavior change). --pack-task/--from-trace/--run-trace/--situ self-budget via --token-budget, not --top-k. --top-k=0 emits NO ranked map at all — ONLY the payload you asked for (--expand/--outline/--pack-signatures/--pack-top-n). Use it when you want the body and not the ~200-symbol map that otherwise rides along with it; the <ctx> root then carries est_tokens= (the payload's price, the number --token-budget gates on), since no map header is there to carry it.

**Try it**

_Same map, capped to the 5 highest-ranked symbols._

```
$ ./build/ripwire . --top-k=5
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1590 symbols=13896 edges=17115 shown=5 est_tokens=736 ambiguous=6100 unresolved=3097 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=20 order=important-first -->
<r root="." est_tokens="736" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2" k="0.0071">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
... [6 more line(s); run it to see the whole thing]
```

**Shaped by:** `--token-budget`, `--recall`, `--graph-query`, `--pack-signatures`, `--expand`, `--from-trace`, `--run-trace`, `--format`

**Caveats (stated by the binary):**

- --for's OWN signature/lego/compose bundle self-limits via --pack-top-n instead — --top-k is INERT there (documented, not fixed — a real fix is a behavior change).

### `--max-tokens=N`

**Answers:** budget the map to ~N tokens (binary-search top-K) — SHAPES the map to fit.

THE FIT IS A BYTE CEILING, and it is deliberately CONSERVATIVE: N is converted at 2.36 B/tok (the densest calibrated language, so N holds for any corpus) times a 0.90 headroom factor. The map's own est_tokens uses THIS corpus's language-weighted rate instead, so a conformant fit REPORTS a number below the N you asked for — expect ~10-20% of N unused. The shaped map discloses both: max_tokens=N (asked) and fit_bytes=B (honoured). Consequence for composing it with --token-budget=N below: the two Ns are different units, so the same N on both is NOT a tautology. At a SMALL N the map's fixed floor (envelope + legend) can exceed fit_bytes with even one symbol emitted — that map says over_ceiling=1 rather than overshoot in silence, and its est_tokens can then exceed N. XML only: the --json map carries no max_tokens=/fit_bytes= keys yet, and its fit is measured in XML bytes. On --recall it SHAPES the doc bundle, and the ceiling is SPLIT ACROSS the docs rather than handed to the top hit: the budget serves the longest rank PREFIX it can give each doc a readable slice, then divides the bytes equally — a doc needing LESS than its share takes only what it needs and the surplus flows to the ones needing more. One long top hit no longer erases the rest of the corpus, and a bigger ceiling never returns FEWER docs. Docs past the prefix are dropped from the BOTTOM of the ranking; selection ORDER never changes. Every cut is DISCLOSED (header total=/shown=/capped=/truncated=/share_bytes=, a per-doc [truncated: X of Y bytes] marker, and a closing (capped: …) note); share_bytes= is that per-doc ceiling and is ABSENT when it bound no doc.

**Try it**

_SHAPE the map to fit ~1500 tokens (binary-search top-K)._

```
$ ./build/ripwire . --max-tokens=1500
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- max_tokens=asked fit_bytes=honoured: fit_bytes = max_tokens x 2.36 (densest-language B/tok) x 0.90 headroom, a CONSERVATIVE cap, so est_tokens (this corpus's own rate) lands ~10-20% BELOW max_tokens by design; the token-budget gate compares against est_tokens, not fit_bytes; over_ceiling=floor-alone-exceeded-fit_bytes(absent=cap-held) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1590 symbols=13896 edges=17115 shown=13 est_tokens=1239 ambiguous=6100 unresolved=3097 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=20 max_tokens=1500 fit_bytes=3186 order=important-first -->
<r root="." est_tokens="1239" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2" k="0.0071">
</s>
<s t="method" n="push_back" id="src/infra/svector.h::svector::push_back" overloads="2" amb="2" k="0.0054">
<c n="buf"/>
<c n="buf"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--token-budget`, `--recall`, `--detail`, `--pr-context`, `--from-trace`, `--run-trace`, `--limit`

**Caveats (stated by the binary):**

- THE FIT IS A BYTE CEILING, and it is deliberately CONSERVATIVE: N is converted at 2.36 B/tok (the densest calibrated language, so N holds for any corpus) times a 0.90 headroom factor.
- Consequence for composing it with --token-budget=N below: the two Ns are different units, so the same N on both is NOT a tautology.
- At a SMALL N the map's fixed floor (envelope + legend) can exceed fit_bytes with even one symbol emitted — that map says over_ceiling=1 rather than overshoot in silence, and its est_tokens can then exceed N.

### `--token-budget=N[K|M|G]`

**Answers:** two personalities depending on the verb: - default map / --query / --recall: a CI GATE — exit 3 if the emitted DOCUMENT's est_tokens exceeds N.

That is the map PLUS every block appended after it (<sigs>/<src>/<bodies>/<outline>), each charged from the bytes it actually emits at the calibrated rate for what those bytes are — so --pack-top-n=3 --token-budget=600 gates on the ~67KB it would stream, not on the map alone. (test/tokenbudgetcheck.sh reports the live MAPE vs tiktoken o200k when tiktoken is installed; the estimate is calibrated, never exact — Claude's tokenizer is not public.) Within budget: exit 0, output unchanged. ASSERTS and fails, vs --max-tokens which shapes to fit — composable: set neither, either, or both (e.g. --max-tokens=16000 --token-budget=16K), but see --max-tokens above: the two Ns are measured in different units. Over budget, nothing of the artifact reaches stdout — only a small record naming withheld_est_tokens= vs budget=, the same vocabulary --recall uses, since est_tokens= is normatively about what a run PRINTED. On --recall the check likewise runs BEFORE a byte of the bundle is emitted: stdout gets the header line naming what was withheld, never the artifact just rejected. --json GATES AT A DIFFERENT NUMBER for the same request, and NOT by a fixed factor: the flag measures the DOCUMENT that was emitted, and whether JSON or XML is smaller flips with RESULT SIZE on this corpus. Small: JSON wins (MEASURED on src --top-k=20: est_tokens 1146 XML vs 899 JSON, ~22% smaller). Large: XML wins instead (MEASURED on src --top-k=200: est_tokens 9405 XML vs 9724 JSON, ~3% LARGER) — the crossover sits near top-k~100-150 here, so the same N can pass or fail differently under --json depending on dialect AND size — never assume one direction, measure the request you actually gate. - --for / --pack-task / --from-trace / --run-trace: SHAPES instead of gating — overrides that lens's own default payload budget and trims to fit, always exit 0. --for's header reports est_tokens="N" so its fit is checkable; --pack-task/--from-trace report their budget ledger in the header report line instead. On --for's auto bundle the ceiling is SPLIT, not handed to the signatures first: the sig side's claim caps at the default sig budget and the rest flows to the inline bodies, so a wider ceiling never serves fewer of them (see --for below). Its VERBATIM task echo is bytes no trim can shrink, so past some task length the header floor alone exceeds the ceiling: the lens drops the comment's DUPLICATE echo first (task_echo: dropped (ceiling); task= keeps the verbatim copy), then labels it over_ceiling (--recall: over_ceiling=1) — never a trim it did not actually do.

**Try it**

_GATE form: exit 3 if the map's own est_tokens exceeds the budget (over-budget failure shape)._

```
$ ./build/ripwire . --token-budget=100
<r withheld_est_tokens="9090" budget="100" withheld="1"/>
```

**Shaped by:** `--top-k`, `--max-tokens`, `--for`, `--recall`, `--handoff`, `--pr-context`, `--from-trace`, `--run-trace`

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
<task-route status="abstain" confidence="none" score="0" margin="0"><facts git="1" dirty="1" trace="0" resolved_symbols="0"/></task-route>
```

**Caveats (stated by the binary):**

- never calls a model, executes the recommendation, or accesses the network.

### `--for=TASK`

**Answers:** the task lens: ranked signatures + metrics framed for reuse.

The bundle enforces a ~7.5KB default payload budget (tail entries trim first; <sigs shown=S total=T capped="1"> marks it: T rows handed to the trim, S printed). The r=1 (top-ranked) <d> row carries next="--expand=FILE:NAME" — the one pasteable follow-up, the body that ends the search (defined here, not in the bundle's own header, which the token ladder does not charge). An explicit --token-budget=N overrides the default at the conservative byte rate (SHAPES, exit 0; see --token-budget above) and the header reports the delivered est_tokens. TERMINAL BY DEFAULT: after the signatures, the top-ranked symbols' FULL bodies ride inline (CDATA + callee signatures, the --expand shape) under a fixed extra body allowance — whole-body-or-not-at-all, rank-first, capped at the --pack-task candidate cap (6). The <ctx> root discloses it: bundle="auto" bodies="N" (bodies="0" reason="budget" when none fit) — on EVERY auto-mode run: a ceiling the signatures alone exhaust still carries the attribute (legend and empty <bodies> shell dropped there; only the attribute has reserved bytes), and --for --json, which serves no bodies by design, says so with "bundle":"sigs". Only the caller-chosen postures (--signatures-only, --detail=N) are attribute-free. ANCHOR-ONLY when the route names one: a query that NAMES a symbol gets THAT symbol's own body or NO body — never a same-named doc section, type stub or re-export shim from another file standing in for it. If the anchor's own body does not fit, the bundle serves nothing and says so, and the per-item over-budget comment names what was dropped. COMPACT ON THE CONCEPTUAL ROUTE: a query that anchors nothing (subtoken+body) gets the ranked map plus a <hops> section — the same candidate head's ONE-HOP callee signatures, the <calls> block a body carries — and NO body CDATA, disclosed as bundle="compact" bodies="0" reason="compact-route". Read the map, then --expand=SYM the one you want. --auto-bodies restores the body walk there. That shape discloses on every run too: a ceiling the signatures alone exhaust carries bundle="compact" bodies="0" reason="budget" — three distinct reasons, never collapsed (compact-route = the route chose edges, no_candidates = nothing scored, budget = the ceiling was spent). An explicit --token-budget=N is a hard ceiling, split so a wider ceiling never buys less: the signature side's claim is capped at the DEFAULT ~7.5KB sig budget and every byte beyond it flows to the enrichment — at any ceiling at or above the default's effective total the <sigs> block is byte-identical to the default run's, so every body (or hop row) the default serves still fits. An explicit --pack-top-n is an explicit SIG posture and keeps the whole-ceiling sig claim. --compress composes: the served bodies (auto/anchor and --detail=N alike) go through the same comment-strip --expand uses, disclosed as compress="1" on the <bodies> element (nothing to strip on the compact route). RANKING CONFIDENCE, disclosed not scored: the <ctx> root always carries confidence="high|low" margin_pct="N" — derived from the SAME relevance-cliff gap statistic --adaptive cuts at (no new scorer, no behavior change; the --json dialect carries the same two keys). low means the ranking is FLAT (no material score cliff and more positive matches than the head shows) — treat the set as a starting point, not an answer; high means a material cliff inside the served head (margin_pct= is that drop as a whole percent) or every positive match already shown

**Try it**

_Name-shaped query: the router picks name-exact BM25 (header says which/why)._

```
$ ./build/ripwire . --for="rankGraphTeleport"
<ctx task="rankGraphTeleport" route="routed: name-exact BM25 — query names a symbol (rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)" root="." confidence="high" margin_pct="45" at="5f71cb4fd+dirty" doc_mentions="2" bundle="auto" bodies="1" est_tokens="1892">
<!-- ripwire lens for "rankGraphTeleport" [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced; doc_mentions= on the root repeats the doc count] [relevance floor: kept 3 of 40 - the other 37 scored zero on this query, so the bundle shrank instead of padding] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). est_tokens= prices this bundle in tokens -->
<sigs>
<d l="2501" n="rankGraphTeleport" id="src/graph.h::rw::rankGraphTeleport" p="src/graph.h" cx="5" ccx="8" in="6" churn="60" amp="201" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="248" n="The convergence disclosure contract" id="docs/ARCHITECTURE.md::rank — Personalized PageRank::The convergence disclosure contract" p="docs/ARCHITECTURE.md" cx="0" ccx="0" in="0" churn="15" amp="87" r="2">#### The convergence disclosure contract</d>
<d l="5542" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" id="docs/EVALS.md::6. Correctness and quality instruments::Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" p="docs/EVALS.md" cx="0" ccx="0" in="0" churn="493" amp="683" r="3"> … [line truncated: 85 more bytes on this line]
</sigs>
<tail total="0" shown="0" capped="0">
</tail>
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2501" p="src/graph.h" n="rankGraphTeleport">
... [18 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--token-budget`, `--signatures-only`, `--auto-bodies`, `--no-route`, `--adaptive`, `--no-mention-boost`, `--no-doc-mention`

**Caveats (stated by the binary):**

- <sigs shown=S total=T capped="1"> marks it: T rows handed to the trim, S printed).
- TERMINAL BY DEFAULT: after the signatures, the top-ranked symbols' FULL bodies ride inline (CDATA + callee signatures, the --expand shape) under a fixed extra body allowance — whole-body-or-not-at-all, rank-first, capped at the --pack-task candidate cap (6).
- ANCHOR-ONLY when the route names one: a query that NAMES a symbol gets THAT symbol's own body or NO body — never a same-named doc section, type stub or re-export shim from another file standing in for it.

### `--signatures-only`

**Answers:** (with --for) opt out of the terminal-by-default bundle: no auto bodies, no bundle="auto" attribute — the signatures-only lens exactly as before.

Contradicts --detail=N (refused together); --detail=N remains the explicit body knob and supersedes the automatic pick

**Try it**

_T3 opt-out: the signatures-only lens (no auto bodies, no bundle="auto" attribute) — contrast with the terminal default above._

```
$ ./build/ripwire . --for="rankGraphTeleport" --signatures-only
<ctx task="rankGraphTeleport" route="routed: name-exact BM25 — query names a symbol (rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)" root="." confidence="high" margin_pct="45" at="5f71cb4fd+dirty" doc_mentions="2" est_tokens="1115">
<!-- ripwire lens for "rankGraphTeleport" [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced; doc_mentions= on the root repeats the doc count] [relevance floor: kept 3 of 40 - the other 37 scored zero on this query, so the bundle shrank instead of padding] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). est_tokens= prices this bundle in tokens -->
<sigs>
<d l="2501" n="rankGraphTeleport" id="src/graph.h::rw::rankGraphTeleport" p="src/graph.h" cx="5" ccx="8" in="6" churn="60" amp="201" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="248" n="The convergence disclosure contract" id="docs/ARCHITECTURE.md::rank — Personalized PageRank::The convergence disclosure contract" p="docs/ARCHITECTURE.md" cx="0" ccx="0" in="0" churn="15" amp="87" r="2">#### The convergence disclosure contract</d>
<d l="5542" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" id="docs/EVALS.md::6. Correctness and quality instruments::Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" p="docs/EVALS.md" cx="0" ccx="0" in="0" churn="493" amp="683" r="3"> … [line truncated: 85 more bytes on this line]
</sigs>
<tail total="0" shown="0" capped="0">
</tail>
</ctx>
```

**Shaped by:** `--for`, `--auto-bodies`

**Caveats (stated by the binary):**

- Contradicts --detail=N (refused together);

### `--auto-bodies`

**Answers:** (with --for) opt out of COMPACT conceptual serving: restore the rank-first auto <bodies> walk on the subtoken+body route (bundle="auto", up to 6 full bodies) instead of the <hops> edge section.

Inert on the name-exact route, where the allowance already runs. Contradicts --signatures-only and --detail=N (refused with either)

**Try it**

_Opt OUT of compact conceptual serving: restore the rank-first auto <bodies> walk (bundle="auto")._

```
$ ./build/ripwire . --for="tree-sitter parse of a source file" --auto-bodies
<ctx task="tree-sitter parse of a source file" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="5f71cb4fd+dirty" bundle="auto" bodies="4" est_tokens="5435">
<!-- ripwire lens for "tree-sitter parse of a source file" [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="12" est_tokens= prices this bundle in tokens -->
<sigs shown="28" total="40" capped="1">
<d l="40" n="kDefaultMaxFileBytes" id="src/ingest.h::rw::kDefaultMaxFileBytes" p="src/ingest.h" cx="0" ccx="0" in="0" churn="26" amp="77" pure="1" r="1" next="--expand=src/ingest.h:kDefaultMaxFileBytes">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1064" n="parseTree" p="src/ingest_sidecap.h" cx="1" ccx="0" in="1" churn="3" amp="37" tested="1" r="2">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="310" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="7" amp="40" r="3">inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="789" n="FileHealth" id="src/model.h::FileHealth::FileHealth" p="src/model.h" cx="0" ccx="0" in="0" churn="57" amp="156" r="4">
<doc>errNodes/errBytes are a PARSER-STATE fact, never a syntax verdict: tree-sitter error recovery fi…</doc>struct FileHealth</d>
<d l="342" n="AstWalk" id="src/ingest.h::rw::AstWalk" p="src/ingest.h" cx="0" ccx="0" in="0" churn="26" amp="77" r="5">enum class AstWalk : std::uint8_t</d>
... [20 more line(s); run it to see the whole thing]
```

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
<ctx task="rankGraphTeleport" root="." confidence="low" margin_pct="0" at="5f71cb4fd+dirty" doc_mentions="6" bundle="auto" bodies="5" est_tokens="5420">
<!-- ripwire lens for "rankGraphTeleport" [doc mentions: 6 docs discussing 4 top-ranked symbols surfaced; doc_mentions= on the root repeats the doc count] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="20" est_tokens= prices this bundle in tokens -->
<sigs shown="20" total="40" capped="1">
<d l="2542" n="rankGraph" id="src/graph.h::rw::rankGraph" p="src/graph.h" cx="2" ccx="1" in="9" churn="60" amp="204" r="1" next="--expand=src/graph.h:rankGraph">
<doc>uniform-teleport PageRank (the default</doc>inline RankedGraph rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
<d l="2501" n="rankGraphTeleport" id="src/graph.h::rw::rankGraphTeleport" p="src/graph.h" cx="5" ccx="8" in="6" churn="60" amp="201" r="2">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quali…</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="983" n="churnRankedGraph" p="src/main.cpp" cx="13" ccx="18" in="1" churn="271" amp="420" r="3">inline ChurnRanking churnRankedGraph( const MainDispatch&amp; d )</d>
<d l="1582" n="kChurnRankLegend" id="src/serialize.h::rw::kChurnRankLegend" p="src/serialize.h" cx="0" ccx="0" in="0" churn="100" amp="246" pure="1" r="4">
<doc>L10 (2026-09-04): the old wording claimed &quot;the same corpus ranked by pagerank orders differently…</doc>inline constexpr const char* kChurnRankLegend = &quot;&lt;!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENCY over window= &quot; &quot;(a c…</d>
... [20 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- Demotion, never exclusion, and the mention anchor still lifts a document the task NAMES.

### `--adaptive`

**Answers:** (with --for/--query) cut the result at the relevance CLIFF — the largest relative score gap (Adaptive-k), floor 5, ceiling = the existing top-k;

a sharp query returns few, a flat/broad one hits the ceiling. Prints [adaptive: kept K of N ...] in the header. Without it, output is unchanged.

**Try it**

_Cut the result at the relevance cliff (Adaptive-k) — on a flat ranking nothing is cut and the header says so ([adaptive: kept N of N])._

```
$ ./build/ripwire . --for="tree-sitter parse of a source file" --adaptive
<ctx task="tree-sitter parse of a source file" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="5f71cb4fd+dirty" bundle="compact" bodies="0" reason="compact-route" est_tokens="3993">
<!-- ripwire lens for "tree-sitter parse of a source file" [adaptive: kept 40 of 40 - no relevance cliff (broad query saturates the score); capped at the ceiling] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=compact: conceptual query, so this map ships one-hop EDGE context, no bodies (bodies=0, reason=compact-route or no_candidates). hops rows are h l=line p=file n=name, and a row's calls child names its callees (c n= l=). hops and calls disclose total=requested shown=printed capped=1 when the BUDGET cut a listing; noedge=N counts ranked symbols with no RESOLVED callee found (never none exists). For a body: expand=p:n pasted off a row; the auto-bodies flag puts the bodies back; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="12" est_tokens= prices this bundle in tokens -->
<sigs shown="28" total="40" capped="1">
<d l="40" n="kDefaultMaxFileBytes" id="src/ingest.h::rw::kDefaultMaxFileBytes" p="src/ingest.h" cx="0" ccx="0" in="0" churn="26" amp="77" pure="1" r="1" next="--expand=src/ingest.h:kDefaultMaxFileBytes">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1064" n="parseTree" p="src/ingest_sidecap.h" cx="1" ccx="0" in="1" churn="3" amp="37" tested="1" r="2">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="310" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="7" amp="40" r="3">inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="789" n="FileHealth" id="src/model.h::FileHealth::FileHealth" p="src/model.h" cx="0" ccx="0" in="0" churn="57" amp="156" r="4">
<doc>errNodes/errBytes are a PARSER-STATE fact, never a syntax verdict: tree-sitter error recovery fi…</doc>struct FileHealth</d>
<d l="342" n="AstWalk" id="src/ingest.h::rw::AstWalk" p="src/ingest.h" cx="0" ccx="0" in="0" churn="26" amp="77" r="5">enum class AstWalk : std::uint8_t</d>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--for`, `--detail`

**Caveats (stated by the binary):**

- (with --for/--query) cut the result at the relevance CLIFF — the largest relative score gap (Adaptive-k), floor 5, ceiling = the existing top-k;

### `--no-mention-boost`

**Answers:** (with --for) disable the query-mention anchor.

By DEFAULT, a file, dotted module, or Scope.symbol literally NAMED in the task text (a path, `pkg.module`, `Type.method` — even inside a URL) has its SCORE lifted to within 5% of the top score; the header says what anchored. That is a score promise, not a rank one: on a flat/tied head the anchored hit can still land several ranks below #1. Inert (byte-identical) when the text names nothing indexed. RIPWIRE_NO_MENTION=1 disables it everywhere (incl. MCP `for`).

**Try it**

_Same task with the anchor disabled — the contrast the flag exists for._

```
$ ./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25" --no-mention-boost
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="5f71cb4fd+dirty" doc_mentions="2" bundle="compact" bodies="0" reason="com … [line truncated: 30 more bytes on this line]
<!-- ripwire lens for "why does src/lexical.h chooseForRanker pick name-exact BM25" [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced; doc_mentions= on the root repeats the doc count] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=compact: conceptual query, so this map ships one-hop EDGE context, no bodies (bodies=0, reason=compact-route or no_candidates). hops rows are h l=line p=file n=name, and a row's calls child names its callees (c n= l=). hops and calls disclose total=requested shown=printed capped=1 when the BUDGET cut a listing; noedge=N counts ranked symbols with no RESOLVED callee found (never none exists). For a body: expand=p:n pasted off a row; the auto-bodies flag puts the bodies back; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="15" est_tokens= prices this bundle in tokens -->
<sigs shown="25" total="40" capped="1">
<d l="498" n="runEvalRetrieval" id="src/eval.h::rw::runEvalRetrieval" p="src/eval.h" cx="15" ccx="25" in="1" churn="9" amp="24" r="1" next="--expand=src/eval.h:runEvalRetrieval">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="155" n="printEvalRankerNote" id="src/eval.h::rw::printEvalRankerNote" p="src/eval.h" cx="1" ccx="0" in="1" churn="9" amp="24" r="2">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="1212" n="lexicalScoresNameExactRanked" id="src/lexical.h::rw::lexicalScoresNameExactRanked" p="src/lexical.h" cx="1" ccx="0" in="4" churn="31" amp="49" r="3">
<doc>The name-exact ranker AS THE RETRIEVAL LENS SERVES IT: whole-name BM25 plus the definition-over-…</doc>inline std::vector&lt;float&gt; lexicalScoresNameExactRanked( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="91" n="kWeakLexicalScoreThreshold" id="src/lexical.h::rw::kWeakLexicalScoreThreshold" p="src/lexical.h" cx="0" ccx="0" in="0" churn="31" amp="45" pure="1" r="4">
... [21 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- That is a score promise, not a rank one: on a flat/tied head the anchored hit can still land several ranks below #1.
- Inert (byte-identical) when the text names nothing indexed.

### `--no-doc-mention`

**Answers:** (with --for) disable doc-mention surfacing.

By DEFAULT, a markdown doc that names one of the task's top-resolved symbols in a `backtick` (the same doc<->code edges --mentions=SYM reads) is lifted into the bundle, strictly below that symbol's own score — closing the "the doc explains it but shares no words with the query" gap. Inert (byte-identical) when no resolved symbol has a mentioning doc. RIPWIRE_NO_DOC_MENTION=1 disables it everywhere (incl. MCP `for`/`pack_task`).

**Try it**

_The same task with doc-mention surfacing OFF — the contrast the flag exists for (no [doc mentions] clause, one fewer row)._

```
$ ./build/ripwire . --for="quality delta acks ledger rubber stamp" --no-doc-mention
<ctx task="quality delta acks ledger rubber stamp" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="5f71cb4fd+dirty" bundle="compact" bodies="0" reason="compact-route" est_tokens="3951">
<!-- ripwire lens for "quality delta acks ledger rubber stamp" [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=compact: conceptual query, so this map ships one-hop EDGE context, no bodies (bodies=0, reason=compact-route or no_candidates). hops rows are h l=line p=file n=name, and a row's calls child names its callees (c n= l=). hops and calls disclose total=requested shown=printed capped=1 when the BUDGET cut a listing; noedge=N counts ranked symbols with no RESOLVED callee found (never none exists). For a body: expand=p:n pasted off a row; the auto-bodies flag puts the bodies back; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="15" est_tokens= prices this bundle in tokens -->
<sigs shown="25" total="40" capped="1">
<d l="3019" n="computeQualityDelta" id="src/mcpverbs.h::rw::computeQualityDelta" p="src/mcpverbs.h" cx="5" ccx="7" in="1" churn="118" amp="246" r="1" next="--expand=src/mcpverbs.h:computeQualityDelta">inline QualityDeltaOutcome computeQualityDelta( const std::string&amp; root )</d>
<d l="401" n="refuseForeignAckSelection" p="src/verbs_quality.h" cx="9" ccx="12" in="1" churn="26" amp="90" r="2">std::optional&lt;int&gt; refuseForeignAckSelection( const rw::Config&amp; cfg, const rw::quality::Scope&amp; scope, const std::vector&lt;rw::quality::Regression&gt;&amp; outOfScope, st … [line truncated: 7 more bytes on this line]
<d l="940" n="runQualityDelta" p="src/verbs_quality.h" cx="103" ccx="259" in="1" churn="26" amp="90" r="3">
<doc>runQualityViews was NOT a dispatch chain — it held two branches, one of which was 298 lines. T…</doc>std::optional&lt;int&gt; runQualityDelta( const MainDispatch&amp; d )</d>
<d l="147" n="DeltaBasis" id="src/verbs_quality.h::DeltaBasis::DeltaBasis" p="src/verbs_quality.h" cx="0" ccx="0" in="0" churn="26" amp="89" r="4">
<doc>WHAT this delta is measured AGAINST, and on WHICH tree — the one place --quality-delta decides…</doc>struct DeltaBasis</d>
... [21 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- Inert (byte-identical) when no resolved symbol has a mentioning doc.

### `--lego=TYPE`

**Answers:** the interface->impls view for ONE named interface/base: its signature, method contract, and every implementor (own-language only).

file:name disambiguates a same-named type. No contract for a language this surface cannot read soundly: methods=0 caveat=… says so.

**Try it**

_Interface -> implementors view: every existing impl of the named interface; the method contract is extracted for the C-family/Java/TS/Python tiers — for a Rust trait (this fixture) it discloses caveat="not-extracted-for-lang" rather than an empty list._

```
$ ./build/ripwire . --lego=Vehicle
<ctx root=".">
<!-- ripwire lego: ONE interface/base type — its method contract (<m>, where the language captures it soundly) and every implementor (<impl>) the extends/implements edges reach, own-language only; implementors= counts them. counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. On a NAMED target only, methods="0" caveat="not-extracted-for-lang" means the method contract itself is not read soundly for this interface's language (currently C++/ObjC only) — implementors= still stands, this caveat is about <m> rows alone. -->
<lego graph_ambiguous="6100" graph_unresolved="3097" counts_floor="1">
<iface n="Vehicle" p="test/legofix/vehicle.rs" methods="0" caveat="not-extracted-for-lang" defs="1" implementors="2">
<impl n="Car" p="test/legofix/vehicle.rs"/>
<impl n="Bike" p="test/legofix/vehicle.rs"/>
</iface>
</lego>
</ctx>
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
<exemplar kind="fn" candidates="7756" n="min" p="src/infra/fastmath.h:51" in="126" ccx="1" root="." tested="1" low_confidence="1">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="51" p="src/infra/fastmath.h" n="min">
<![CDATA[[[nodiscard]] ALWAYS_INLINE constexpr T min( T a, T b ) noexcept { return b < a ? b : a; }]]>
</b>
</bodies>
</exemplar>
```

**Shaped by:** `--compress`, `--metrics`, `--doctor`, `--limit`, `--index-out`

### `--recall=TASK`

**Answers:** recall the most relevant DOCS — memory/plans/designs, full bodies (md, .ipynb/.html/.csv, plus Office/PDF via the optional markitdown bridge).

This is the tool's LARGEST output: its header reports est_tokens + total=/shown=/capped=, where total= is the TRUE relevant count (score > 0) and shown= is what this run actually emitted. The header's "of N document files" denominator counts every file the index carries as a DOCUMENT — .md plus the docparse'd .ipynb/.html/.csv — so it is a SUPERSET of --doc-drift's docs=, which is an extension test (markdown only). Two populations, two names, deliberately. --top-k=N shapes HOW MANY docs are emitted (default 8, not the general --top-k default of 200). Recall defaults to an 8000-token body ceiling; --max-tokens=N overrides it and shapes to fit (disclosing each cut), while --token-budget=N gates the finished artifact (exit 3, nothing streamed). GENERATED documents rank LAST by default — a doc that declares itself generated in its first lines, or is BOTH >=5x the median doc's size AND mostly ```-fenced quoted output (a capture/API dump quotes every term, so BM25 hands it every query). Never dropped: it still wins when nothing else matches. Each one says [generated_demoted: marker|size+fences] on its own line and the header tallies generated_demoted=N

**Try it**

_Most relevant DOCS' full bodies (markdown only) — recall what is already written down._

```
$ ./build/ripwire . --recall="quality delta gating exit codes"
ripwire recall — "quality delta gating exit codes" — 74 relevant of 148 document files, best-first — total=74 shown=8 capped=1 truncated=5 generated_demoted=1 max_tokens=8000 share_bytes=2298 est_tokens=5554  [lines= on a doc is its SELECTED section range — pre-truncation; the per-doc trunca … [line truncated: 45 more bytes on this line]

━━ skills/ripwire-quality-bar/SKILL.md  (relevance 6.534) ━━  [sections: 8 of 10, section-granular; whole doc 31569 B; lines="54-137,138-258,259-287,288-308,309-340,341-350,351-361,362-367"]  [truncated: 1817 of 27368 bytes]
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

**Shaped by:** `--max-tokens`, `--token-budget`, `--no-redact`, `--from-trace`, `--legend`, `--limit`

**Caveats (stated by the binary):**

- This is the tool's LARGEST output: its header reports est_tokens + total=/shown=/capped=, where total= is the TRUE relevant count (score > 0) and shown= is what this run actually emitted.
- Never dropped: it still wins when nothing else matches.

### `--tree`

**Answers:** file-by-file orientation map (top symbols per file).

Default window: the 80 files with the best-ranked symbols (shown=/capped=/total=/next_offset= disclose the cut, next= pastes the next page); --limit=N/--offset=M window it explicitly (--limit=100000 = every file)

**Try it**

_File-by-file orientation map (top symbols per file)._

```
$ ./build/ripwire . --tree
<!-- ripwire tree: each file + its top symbols by rank, files ordered by their best symbol's rank (path breaks ties) — a session-start orientation map. files= is the indexed corpus; rows list files WITH symbols; files_unlisted= holds the symbol-less remainder — files equals files_unlisted plus the LISTABLE file set, which is what the rows below enumerate before any paging window is applied; under explicit paging (limit=/offset=) that listable count is emitted as total= and shown= says how many of it these rows are. The rows are a WINDOW even without explicit paging: the default prints the 80 files with the best-ranked symbols (shown=/capped=/total=/has_more=/next_offset= disclose the cut) and next= pastes the next page; limit= raises it. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<tree files="1590" files_unlisted="74" shown="80" capped="1" total="1516" has_more="1" next_offset="80" offset="0" limit="0" pr_iters="31" root="." next="--tree --offset=80">
<file p="src/infra/svector.h" symbols="68">
<s t="method" n="size"/>
<s t="method" n="buf"/>
<s t="method" n="buf"/>
</file>
<file p="src/notes.h" symbols="26">
<s t="method" n="empty"/>
<s t="method" n="find"/>
<s t="fn" n="sortNotes"/>
</file>
<file p="src/scipoverlay.h" symbols="9">
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- Default window: the 80 files with the best-ranked symbols (shown=/capped=/total=/next_offset= disclose the cut, next= pastes the next page);
- --limit=N/--offset=M window it explicitly (--limit=100000 = every file)

### `--html[=FILE]`

**Answers:** self-contained HTML force-directed call graph (no CDN — redirect or write FILE)

**Try it**

_Self-contained HTML force-directed call graph._

```
$ ./build/ripwire . --html=<scratch>/aux/map2.html
(empty)
```

**Shaped by:** `--color-by`, `--legend`

### `--color-by=MODE`

**Answers:** (with --html) node colour: lang (default) | community | cx | churn | tested — the page embeds all five and keeps a live selector;

the flag only sets the initial mode

**Try it**

_The HTML graph with the initial colour mode set to community (the page embeds all five modes and keeps a live selector)._

```
$ ./build/ripwire . --html=<scratch>/aux/map2.html --color-by=community
(empty)
```

### `--order=MODE`

**Answers:** emit order: stable (path/id order — provider KV-cache hits across re-runs) | important-first (rank order, the default;

no auto-flip) | important-last (highest-rank content emitted last — recency bias for an LLM). Large default maps auto-flip to important-last past ~50% of a nominal 32K window (est_tokens>16000) unless MODE is explicitly given.

**Try it**

_Stable (path/id) emit order — provider KV-cache hits across re-runs._

```
$ ./build/ripwire . --order=stable --top-k=5
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<r root="." pr_iters="31" lens="k,est_tokens">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2">
</s>
<s t="method" n="size" id="src/infra/svector.h::svector::size">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty">
</s>
</f>
... [6 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-stable`

### `--no-stable`

**Answers:** opt out of the stable ordering that --mcp/--listen enable by default.

Read ONLY there: on the CLI it changes nothing and says so on stderr (the map is important-first unless you pass --order=stable)

**Try it**

_--no-stable outside --mcp: what the flag does (or says) when there is no stable-by-default ordering to opt out of._

```
$ ./build/ripwire . --no-stable --top-k=3
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1590 symbols=13896 edges=17115 shown=3 est_tokens=698 ambiguous=6100 unresolved=3097 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=20 order=important-first -->
<r root="." est_tokens="698" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
</f>
<f p="src/scipoverlay.h">
... [4 more line(s); run it to see the whole thing]
```

---

## navigate / answer a question

### `--around=SYM`

**Answers:** ego graph around SYM   [--around-depth=N, default 1] [--around-fanout=K, default 32] (default depth 1 since 2026-09-05: depth 2 was 3x the whole default map on this repo;

the root's depth= says which; --around-depth=2 restores the 2-hop neighbourhood) the root echoes all three (of= depth= fanout=), so the boundary of what could appear is readable and, when a bound actually CUT, which one: depth_truncated="1" (a symbol one hop past depth= is absent) / fanout_cut="N" (N distinct symbols the fanout cap dropped, absent from the whole answer, exact not a floor). Neither is emitted when its bound cut nothing, so absent = the bound did not bind and raising it would return nothing new

**Try it**

_Ego graph around one symbol — depth 1 BY DEFAULT now (the root's depth= says so): ~6 KB where the 2-hop neighbourhood is ~64 KB on this repo._

```
$ ./build/ripwire . --around=rankGraphTeleport
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- of= is the resolved SEED this neighbourhood is centred on; depth= call hops walked and fanout= neighbours kept per hop are its whole boundary, so a row's absence means outside them, not nonexistent. defs= (only when >1) = that NAME has N definitions and the lowest-id one was walked; qualify with file:name or @FILE:LINE to pick another. -->
<!-- a bound BIT this walk, so raising it would return more: depth_truncated=1 means at least one symbol one hop past depth= is absent; fanout_cut=N means N distinct symbols were dropped by the fanout= cap and appear NOWHERE here (exact, not a floor: a neighbour another hub re-admitted is not counted). Neither attribute is emitted when its bound cut nothing, so absent means that bound did not bind and raising it returns nothing new. The knobs are around-depth=N and around-fanout=K. -->
<!-- files=1590 symbols=13896 edges=17115 shown=16 est_tokens=2747 ambiguous=6100 unresolved=3097 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=20 order=important-first -->
<r root="." of="rankGraphTeleport" depth="1" fanout="32" depth_truncated="1" est_tokens="2747">
<f p="src/graph.h">
<s t="fn" n="rankGraphTeleport" id="src/graph.h::rw::rankGraphTeleport" amb="6" k="1.0000">
<c n="biasPrior"/>
<c n="PROFILE_SCOPE_DESCRIBE"/>
<c n="PROFILE_SCOPE_DESCRIBE"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--callers`, `--layout`, `--limit`

### `--callers=SYM`

**Answers:** who calls SYM (1-hop in-edges).

file:name disambiguates a same-named symbol across files (like --around/--lego); Scope::name picks one scope's definition — the sym= spelling edit-check prints resolves everywhere

**Try it**

_Unknown-symbol REFUSAL shape (exit 1) with a did-you-mean from real edit distance._

```
$ ./build/ripwire . --callers=DoesNotExist
(empty)
```

**Shaped by:** `--callees`, `--uses`, `--impact`, `--expand`, `--edit-check`, `--slice-flow`, `--at`, `--format`

**Caveats (stated by the binary):**

- file:name disambiguates a same-named symbol across files (like --around/--lego);

### `--callees=SYM`

**Answers:** what SYM calls (1-hop out-edges).

file:name disambiguates like --callers

**Try it**

_What SYM calls (1-hop out-edges)._

```
$ ./build/ripwire . --callees=rankGraphTeleport
<!-- ripwire callers/callees: the 1-hop call hierarchy read off the call graph — the callers form lists symbols that CALL of=; the callees form lists symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS it resolved to (rows UNION every def's neighbours), count= the DISTINCT neighbour symbols (a floor, per counts_floor=), windowed by limit= and offset=. A neighbour that is an indexed function-like #define is a macro row (t="macro", role="macro" on the XML row): the edge crosses a macro expansion, not a plain call — rows carry no role= otherwise. Rows are ordered SOURCE first, then test/bench, then docs, by path within a tier. hop_tested=/hop_untested= partition count= by the tested= lens below (1-hop, never transitive). tested="1" on a row means an indexed test transitively reaches it (never 0, omitted when it does not). BLIND SPOT the test-gate legend also names: only a CALL EDGE from an INDEXED test symbol counts here, so a shell or CLI-level test running a built binary as a SUBPROCESS is invisible to it and a repo tested that way reads all-untested. Read untested= as no in-process test reaches it, not as no test covers it. callees-only: bodyless_defs= (when present) counts defs= that are bodyless declarations (header-only or forward-declared); zero callees may mean no body to read callees from, not truly no dependencies. next= is the one pasteable follow-up (expand on this selector: the body). counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<callees of="rankGraphTeleport" defs="1" count="9" root="." hop_tested="8" hop_untested="1" graph_ambiguous="6100" graph_unresolved="3097" counts_floor="1" next="--expand=rankGraphTeleport">
<s t="fn" n="biasPrior" p="src/graph.h:2464"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1322" role="macro" tested="1"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1336" role="macro" tested="1"/>
<s t="method" n="begin" p="src/infra/svector.h:269" tested="1"/>
<s t="method" n="end" p="src/infra/svector.h:270" tested="1"/>
<s t="method" n="begin" p="src/infra/svector.h:271" tested="1"/>
<s t="method" n="end" p="src/infra/svector.h:272" tested="1"/>
<s t="method" n="size" p="src/infra/svector.h:285" tested="1"/>
<s t="fn" n="pageRankDouble" p="src/pagerank.cpp:95" tested="1"/>
</callees>
```

**Shaped by:** `--impact`, `--exercises`, `--format`, `--json`, `--limit`

**Caveats (stated by the binary):**

- file:name disambiguates like --callers

### `--uses=SYM`

**Answers:** the statically resolvable use-sites of SYM (role=call|macro|read|write|import|extends|type, file:line);

external="1" if SYM has no in-corpus def. file:name narrows defs= AND the role="call" sites (kept only where the call RESOLVES to a chosen def — --callers' own narrowing); read/write/import/extends carry no resolution and stay name-matched. narrowed_roles=/defs_of_name=/call_sites_of_name= (file: qualifier only) disclose what narrowed and the un-narrowed totals; a file: qualifier naming a file with no such def REFUSES, like --callers/--impact Owner.field (also Owner::field, or the id=) — a MEMBER VARIABLE's own use-sites, RESOLVED per site: this->f/self.f/bare f inside the owner pin; v.f pins through v's recorded type, else every owner is a candidate and the row carries amb=K (never a silent pin); write = assignment/compound/++ (address-of and by-reference passing are NOT claimed). A bare field name shared by several owners REFUSES with the Owner.field spellings; C/C++/Python fields only, others refuse

**Try it**

_The resolvable use-sites (call/read/write/import/extends) with file:line; count= is a floor._

```
$ ./build/ripwire . --uses=rankGraphTeleport
<!-- ripwire uses: STATICALLY RESOLVABLE use-sites of SYM (role=call|macro|read|write|import|extends|type; p=file:line) — a floor, see counts_floor below; that role list is the whole vocabulary. role="type" is a bare TYPE mention (a signature, declaration or template argument) with NO call edge — real but not an invocation, so it never reaches the call graph, PageRank or the ranked map; captured C/C++/ObjC only, and only a plain leaf spelling (a qualified or aliased spelling contributes no row). A base clause is role="extends", never role="type"; a type's own DEFINITION is never a use of itself. role="macro" is the call-shaped invocation of a name uniquely naming an indexed function-like #define — never role="call" (an expansion is not a plain call); a name shared with a non-macro definition stays role="call". Rows are ordered SOURCE first, then test/bench, then docs, by path within a tier. A MEMBER selector (Owner.field) is resolved per site instead of name-matched — that run's legend says how. in_id=canonical id (root-relative path::scope::name) of the symbol the site sits INSIDE; a scope-less enclosing symbol degrades to its bare name; absent at file scope. Reference-name-based (same heuristic level as call edges) — verify in source if a name is overloaded. external="1" ⇒ SYM has no definition in the indexed tree under ANY spelling (stdlib/third-party) — never merely none in the file you qualified with (that spelling refuses instead). A "file:name" SYM narrows defs= AND the role="call" sites, which are kept only where the call RESOLVES to a chosen def (the callers verb's own narrowing, read the other way, so the two agree); read/write/import/extends carry no resolution and stay name-matched across every def sharing the name. narrowed_roles= names what narrowed, and defs_of_name=/call_sites_of_name= (file: qualifier only) are the un-narrowed totals. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<uses of="rankGraphTeleport" defs="1" external="0" count="9" root="." graph_ambiguous="6100" graph_unresolved="3097" counts_floor="1">
<u role="call" p="src/eval.h:322" in_id="src/eval.h::rw::runEval"/>
<u role="call" p="src/graph.h:2545" in_id="src/graph.h::rw::rankGraph"/>
<u role="call" p="src/graph.h:3135" in_id="src/graph.h::rw::anchoredLexicalRank"/>
<u role="call" p="src/main.cpp:1007" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1008" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1018" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1024" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1195" in_id="runDefaultMap"/>
<u role="call" p="src/mcpindex.h:1200" in_id="src/mcpindex.h::rw::getIndex"/>
</uses>
```

**Shaped by:** `--impact`, `--naming-consistency`, `--edit-check`, `--edit-target-file`, `--safe-delete`, `--doctor`, `--format`, `--limit`

**Caveats (stated by the binary):**

- a file: qualifier naming a file with no such def REFUSES, like --callers/--impact Owner.field (also Owner::field, or the id=) — a MEMBER VARIABLE's own use-sites, RESOLVED per site: this->f/self.f/bare f inside the owner pin;
- v.f pins through v's recorded type, else every owner is a candidate and the row carries amb=K (never a silent pin);
- A bare field name shared by several owners REFUSES with the Owner.field spellings;

### `--graph-query=EXPR`

**Answers:** composable node-set query over the call graph: sources name("X")/all;

filters kind|cx|fanin|file|layer; bounded closure callers|callees(SET[,depth]); joins and|or|not.  e.g. and(callers(name("foo"),2),kind(all,fn)); file() regex example: file("src/.*\\.cpp") (or in bash, use single quotes: file('src/.*\.cpp')) layer(SET,NAME) keeps the architecture layer NAME (game|infra|render|math|audio|ai|test) — the SAME built-in directory-name taxonomy the map prints as layer= on a file node, so the two cannot disagree. It does NOT read a --arch=FILE rules file: --arch is a verb and outranks --graph-query, so the two never run together. An unknown layer word, or ANY layer() against a tree where no path names a layer, is REFUSED (exit 1) rather than answered count="0" — 0 there would read as "no such code". a name("X") literal matching NO indexed symbol refuses with a did-you-mean (a typo is not a count=0); a query whose names all resolve but that selects nothing still reports count="0" — that IS a measurement (including a VALID layer with no members in a tree that does have layers). Ranked result set is capped at --top-k (default 200); --limit overrides that cap (raise or lower it), --offset pages past it — see --limit=N --offset=M above

**Try it**

_Composable node-set query: functions within 2 caller-hops of rankGraphTeleport._

```
$ ./build/ripwire . --graph-query='and(callers(name("rankGraphTeleport"),2),kind(all,fn))'
<!-- ripwire graph-query: a fixed-operator node-set query over the call graph (sources name/all; filters kind/cx/fanin/file/layer; bounded closure callers/callees; joins and/or/not), ranked by importance + capped at the top-k limit (default 200); narrow the query or raise top-k for more. NOT Datalog. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<query expr="and(callers(name(&quot;rankGraphTeleport&quot;),2),kind(all,fn))" count="51" shown="51" capped="0" graph_ambiguous="6100" graph_unresolved="3097" counts_floor="1" root="." pr_iters="31">
<s t="fn" n="getIndex" p="src/mcpindex.h:1104"/>
<s t="fn" n="emitCommunitiesReport" p="src/verbs_report.h:2107"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:3091"/>
<s t="fn" n="emitCommunityDrill" p="src/verbs_report.h:2268"/>
<s t="fn" n="rankGraph" p="src/graph.h:2542"/>
<s t="fn" n="dispatchMain" p="src/main.cpp:2653"/>
<s t="fn" n="computeLensRanking" p="src/verbs_for.h:37"/>
<s t="fn" n="postCheckJson" p="src/mcpedit.h:1075"/>
<s t="fn" n="fetchBody" p="src/mcpverbs.h:3840"/>
<s t="fn" n="runEvalRetrieval" p="src/eval.h:498"/>
<s t="fn" n="runEvalMined" p="src/eval.h:901"/>
<s t="fn" n="runEditVerb" p="src/mcpedit.h:1137"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--exercises`, `--limit`

**Caveats (stated by the binary):**

- file() regex example: file("src/.*\\.cpp") (or in bash, use single quotes: file('src/.*\.cpp')) layer(SET,NAME) keeps the architecture layer NAME (game|infra|render|math|audio|ai|test) — the SAME built-in directory-name taxonomy the map prints as layer= on a file node, so the two cannot disagree.
- It does NOT read a --arch=FILE rules file: --arch is a verb and outranks --graph-query, so the two never run together.
- An unknown layer word, or ANY layer() against a tree where no path names a layer, is REFUSED (exit 1) rather than answered count="0" — 0 there would read as "no such code".

### `--external-surface`

**Answers:** names referenced but never defined in-corpus (the stdlib/third-party surface), by ref count;

each row's lang= is the REFERENCING file's language — a name called from several languages (e.g. printf: C stdio call vs Bash builtin) gets one row PER language, not a merged count. Default window: 100 rows (shown=/capped=/next_offset=, next= pastes the next page; --limit=N raises it) and the sh BUILTINS (echo printf cd exit test …) are dropped — builtins_excluded= counts them; --include-builtins keeps them

**Try it**

_Names referenced but never defined in-corpus (stdlib/third-party surface). The root carries names/shown/capped; the default is a 100-row window now, so total= and a pasteable next= join them when it bites (the explicit --limit form carries the same quintet). The sh BUILTINS (cd/echo/set…) are dropped and COUNTED as builtins_excluded= — grep/sed/git stay, they ARE the surface._

```
$ ./build/ripwire . --external-surface
<!-- ripwire external-surface: names CALLED/IMPORTED/EXTENDED but never defined in the indexed tree = the stdlib/third-party surface the code depends on (refs=use-sites, calls=of-which-calls). builtins_excluded= counts the sh BUILTIN rows (echo printf cd exit test …) dropped from names= by default — the interpreter, not a dependency; the include-builtins flag keeps them. The rows are a WINDOW (default 100; shown=/capped=/total=/has_more=/next_offset= disclose the cut, limit=/offset= page it) and next= pastes the next page. -->
<external-surface names="1430" builtins_excluded="19" shown="100" capped="1" total="1430" has_more="1" next_offset="100" offset="0" limit="0" next="--external-surface --offset=100">
<x n="grep" lang="sh" refs="7734" calls="7734"/>
<x n="head" lang="sh" refs="1636" calls="1636"/>
<x n="cat" lang="sh" refs="1360" calls="1360"/>
<x n="tr" lang="sh" refs="1077" calls="1077"/>
<x n="string" lang="cpp" refs="1031" calls="1031"/>
<x n="c_str" lang="cpp" refs="1024" calls="1024"/>
<x n="python3" lang="sh" refs="881" calls="881"/>
<x n="fprintf" lang="cpp" refs="875" calls="875"/>
<x n="sed" lang="sh" refs="841" calls="841"/>
<x n="mkdir" lang="sh" refs="825" calls="825"/>
<x n="print" lang="py" refs="761" calls="761"/>
<x n="len" lang="py" refs="675" calls="675"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- names referenced but never defined in-corpus (the stdlib/third-party surface), by ref count;
- printf: C stdio call vs Bash builtin) gets one row PER language, not a merged count.
- Default window: 100 rows (shown=/capped=/next_offset=, next= pastes the next page;

### `--path=SRC,DST`

**Answers:** shortest directed call-path SRC -> DST

**Try it**

_Shortest directed call-path SRC -> DST. CHANGED: now reports from_p/to_p/from_defs and resolves the right `main` (was reachable="0")._

```
$ ./build/ripwire . --path=main,rankGraphTeleport
<!-- ripwire path: one DIRECTED call path from= to to= (each <s> a hop); reachable= is 0 and hops= 0 when the graph holds none. counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<path from="main" to="rankGraphTeleport" from_p="src/main.cpp:2634" to_p="src/graph.h:2501" from_defs="88" to_defs="1" reachable="1" hops="4" root="." graph_ambiguous="6100" graph_unresolved="3097" counts_floor="1">
<s t="fn" n="main" p="src/main.cpp:2634"/>
<s t="fn" n="runWithCompactLegend" p="src/main.cpp:2573"/>
<s t="fn" n="dispatchMain" p="src/main.cpp:2653"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1098"/>
<s t="fn" n="rankGraphTeleport" p="src/graph.h:2501"/>
</path>
```

**Shaped by:** `--connect`, `--limit`

### `--connect=A,B,C`

**Answers:** minimal connecting subgraph over 2..16 symbols: terminals + fewest joining intermediaries + call edges in TRUE direction (finds the shared-caller join a directed --path can't)   [--connect-radius=N (1..12, default 6)]

**Try it**

_Minimal connecting subgraph over 3 symbols (finds shared-caller joins)._

```
$ ./build/ripwire . --connect=rankGraphTeleport,runEval,getIndex
<!-- ripwire connect: minimal joining subgraph over N task symbols (metric-closure 2-approx Steiner; search is undirected so SHARED-CALLER joins are found, every <e f= t=/> keeps its TRUE caller->callee direction; graph-structured navigation per CodeCompass, arXiv 2602.20048). Call edges are name-based: dynamic dispatch / callbacks may hide connections. counts_floor="1": every graph-derived count here (nodes=, edges=, groups=) is a FLOOR, never a total; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. defs= on a terminal row = that NAME has N definitions and the lowest-id one was used; qualify with file:name to pick another. Steiner rows never carry it. max_tokens= is the token ceiling this bundle was SHAPED against (the max_tokens flag; absent = none was asked for); est_tokens= is what it cost, truncated="paths" says the shaping had to cut, and over_ceiling="1" says est_tokens exceeds max_tokens anyway (the trim ran out of things to drop before it reached the ceiling; the bundle is then complete, not further trimmed) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<connect terminals="3" nodes="3" edges="2" radius="6" groups="1" est_tokens="740" root="." graph_ambiguous="6100" graph_unresolved="3097" counts_floor="1">
<g terminals="3">
<t n="runEval" t="fn" p="src/eval.h:168"/>
<t n="rankGraphTeleport" t="fn" p="src/graph.h:2501"/>
<t n="getIndex" t="fn" p="src/mcpindex.h:1104"/>
<e f="runEval" t="rankGraphTeleport"/>
<e f="getIndex" t="rankGraphTeleport"/>
</g>
</connect>
```

**Shaped by:** `--no-redact`, `--from-trace`, `--limit`

### `--impact=SYM`

**Answers:** transitive blast radius — the indexed symbols that reach SYM (a floor, see counts_floor).

file:name disambiguates like --callers importers= is a SECOND, weaker reach beside it: the files that directly include/import a file defining SYM, emitted as <f via="import" lazy="0|1"> rows (format=columnar carries the count only). NEVER added to reaches= — files and symbols are different units, and an importer may use a different symbol from that file, or none at all. lazy="1" (TS/JS only): every one of that importer's edges is a require()/import() written inside a function body, not at module load time — still a real dependency, weaker than a top-level one counts_floor="1"           on --callers/--callees/--uses/--impact/--edit-check every count is a FLOOR, never a total: the call graph is extracted from source text by name, so dynamic dispatch and declarations that parse without a call expression (C++ most-vexing-parse) contribute no edge; a call through a function pointer/callback is an edge only when ONE function is bound to that variable in scope (reassigned/table-indexed/lambda-bound/escaped — address-taken or reference-bound — pointers stay edge-less, C-family); a macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (t="macro"); a shared name stays a plain call, an unindexed macro's site is no edge. Read a 0 as "none found", never as "none exists". Those five verbs also count DISTINCT (caller,callee) pairs, while --uses counts call SITES — see each verb's own legend pr_iters="N"               on every PageRank-ordered document (the map, and the tree, seams, communities, zoom, impact, graph-query and exercises verbs, plus their MCP twins): how many power iterations produced that ordering. The iteration stops when the L1 residual between successive rank vectors falls below tolerance, or at a fixed iteration ceiling, whichever comes first. pr_converged="0" is emitted ONLY on that second exit and means the ranking is a rank vector that stopped SHORT of tolerance, not the fixed point it approximates. ABSENCE MEANS IT CONVERGED (there is no pr_converged="1": the converged path is the normal one and must cost zero bytes), and absence of pr_iters= itself means the document was not ordered by a power iteration at all (a lexical query score, or a hub or authority HITS vector), never that the count is unknown

**Try it**

_Transitive blast radius — everything that reaches SYM. NOW carries shown/capped._

```
$ ./build/ripwire . --impact=rankGraphTeleport
<!-- ripwire impact: transitive blast radius — symbols that reach SYM via calls (review before changing SYM). next= is the one pasteable follow-up (the safe-delete read of SYM). raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page. importers= is a SECOND, weaker reach: the files that directly include/import a file defining SYM, as <f via="import" p="…" lazy="0|1"/> rows after the symbol rows — not call reach, never added to reaches= (different units, files vs symbols; an importer may use a different symbol from that file, or none at all). DIRECT (one hop), never the transitive include cone. lazy="1" (TS/JS only) means every one of that importer's edges into SYM's file is a require()/import() written INSIDE A FUNCTION BODY, firing only if and when that function runs; lazy="0" means at least one edge is an ordinary top-level require/import (module-load time too). shown_importers=/importers_capped= disclose that listing's own truncation (importers= stays the full count); limit=/offset= window the symbol rows only. tested="1" on a row means an indexed test transitively reaches it (never 0, omitted when it does not). radius_tested=/radius_untested= partition reaches= by that same lens (transitive, unlike callers/callees). BLIND SPOT the test-gate legend also names: only a CALL EDGE from an INDEXED test symbol counts here, so a shell or CLI-level test running a built binary as a SUBPROCESS is invisible to it and a repo tested that way reads all-untested. Read untested= as no in-process test reaches it, not as no test covers it. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<impact of="rankGraphTeleport" defs="1" reaches="63" importers="33" shown_importers="33" importers_capped="0" radius_tested="0" radius_untested="63" root="." shown="40" capped="1" total="63" has_more="1" next_offset="40" offset="0" limit="0" graph_ambiguous="6100" graph_unresolved="3097" counts_floo … [line truncated: 59 more bytes on this line]
<s t="fn" n="getIndex" p="src/mcpindex.h:1104"/>
<s t="fn" n="emitCommunitiesReport" p="src/verbs_report.h:2107"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:3091"/>
<s t="fn" n="emitCommunityDrill" p="src/verbs_report.h:2268"/>
<s t="fn" n="rankGraph" p="src/graph.h:2542"/>
<s t="fn" n="dispatchMain" p="src/main.cpp:2653"/>
<s t="fn" n="computeLensRanking" p="src/verbs_for.h:37"/>
<s t="fn" n="postCheckJson" p="src/mcpedit.h:1075"/>
<s t="fn" n="fetchBody" p="src/mcpverbs.h:3840"/>
<s t="fn" n="receiptOperation" p="src/editplan.h:332"/>
<s t="fn" n="runEvalRetrieval" p="src/eval.h:498"/>
<s t="fn" n="runEvalMined" p="src/eval.h:901"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--uses`, `--metrics`, `--safe-delete`, `--slice-flow`, `--format`, `--json`, `--limit`

**Caveats (stated by the binary):**

- transitive blast radius — the indexed symbols that reach SYM (a floor, see counts_floor).
- file:name disambiguates like --callers importers= is a SECOND, weaker reach beside it: the files that directly include/import a file defining SYM, emitted as <f via="import" lazy="0|1"> rows (format=columnar carries the count only).
- NEVER added to reaches= — files and symbols are different units, and an importer may use a different symbol from that file, or none at all.

### `--verify="CLAIM"`

**Answers:** VERIFY A CLAIM about the code in ONE call: a CLOSED claim language in, a three-valued verdict out (confirmed / refuted / not-established) with the evidence rows inline — the collapse of the manual verification grep-chain.

Shapes: calls(A,B) does A transitively call B; uses(SYM) / unused(SYM) is SYM referenced anywhere / nowhere; contains(FILE, "LIT") do FILE's indexed bytes contain the literal; defines(FILE, SYM) does FILE define SYM; reaches(SYM, "FILE"|LAYER) does code in that file/layer transitively call SYM (LAYER unquoted: game|infra|render|math|audio|ai|test). refuted appears ONLY with complete evidence: a clean literal-scan absence carries complete=, and an unused claim is refuted by printed witness sites. A graph or reference ZERO can never refute — it yields not-established with limit= naming the floor (call-graph-floor, reference-floor, collection-ceiling, scan-degraded, extraction-floor); see counts_floor above for why. An unknown shape refuses loudly with the whole vocabulary; SYM takes the shared selector grammar (name, file:name, Scope::name, canonical id), FILE is a path substring

**Try it**

_An unparseable claim — the refusal names the accepted shapes._

```
$ ./build/ripwire . --verify="frobnicate(x)"
(empty)
```

**Caveats (stated by the binary):**

- A graph or reference ZERO can never refute — it yields not-established with limit= naming the floor (call-graph-floor, reference-floor, collection-ceiling, scan-degraded, extraction-floor);
- see counts_floor above for why.
- An unknown shape refuses loudly with the whole vocabulary;

### `--mentions=SYM`

**Answers:** markdown docs (plans/designs) that name SYM in a `backtick` (doc↔code).

An @FILE:LINE seed rebinds to the innermost enclosing definition and answers, disclosing sym= the pre-PR family — plumbing (--affected) to mid-task report (--situ) to gate (--test-gate):

**Try it**

_Markdown docs that name SYM in a backtick (doc<->code edges)._

```
$ ./build/ripwire . --mentions=rankGraphTeleport
<!-- ripwire mentions: markdown FILES that name this symbol in a `backtick` (doc<->code; NOT a call edge). docs= is the row count (distinct files); sections= counts the underlying markdown-section mentions before file-collapse (docs <= sections). Each row's mentions= is its own section-mention count. An @FILE:LINE seed rebinds to the innermost definition enclosing that line — sym= names it, of= echoes the seed as typed. No line locator: the doc edge is stored at file granularity — a fabricated always-1 l= was removed; absent beats fake -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<mentions of="rankGraphTeleport" defs="1" docs="2" sections="2" root=".">
<doc p="docs/ARCHITECTURE.md" mentions="1"/>
<doc p="docs/EVALS.md" mentions="1"/>
</mentions>
```

**Shaped by:** `--no-doc-mention`, `--at`, `--limit`

### `--affected=F1,F2|SYM`

**Answers:** test files that transitively reach the changed files -- or the changed SYMBOL.

Each item may be `path`, `./path`, `path:LINE` / `path:N-M` (paste a --hotspots/--clones/--grep/--lint/ --quality-delta row's locator verbatim; the trailing line locator is stripped, same for --situ/--test-gate), or a symbol: `NAME`, `file:NAME`, `path::scope::name`. FILE-FIRST: an item matching any indexed path is a PATH pattern (unchanged semantics -- `--affected=widget` stays the ./src/widget.cpp pattern); only an item matching NO indexed path is offered to the symbol resolver, and `file:NAME` reaches the symbol reading explicitly. seeded_by="file|symbol|mixed" + seeds=N report which reading fired and how many defs it seeded. An item matching NEITHER refuses (exit 1) naming both readings. seed_test_files=N of the matched files are TEST files: a test cannot reach a change it is part of, so its own symbols are not seeds of the caller walk, and its row carries seed_kind="test" -- it is listed because the argument matched it (it changed, run it), not because it reaches. script_gates_unmodelled= counts the script runners under test/, recursively (a path count; not every one invokes the binary) that this call's graph walk cannot see either way (script-to-binary is not a call edge) — a corpus-wide fact, not scoped to the changed set given

**Try it**

_Test files that transitively reach the changed file._

```
$ ./build/ripwire . --affected=src/graph.h
<!-- ripwire affected: test files that transitively reach the changed files/symbols (run these); seeded_by= says which reading the argument took. seed_test_files= how many of the matched files are TEST files: a test cannot reach a change it is part of, so its own symbols are not seeds of the caller walk and its row carries seed_kind="test" — it is listed because the argument matched it (it changed, run it), not because it reaches the change. script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) — script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=/reached=. counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<affected changed="src/graph.h" seeded_by="file" seeds="151" seed_test_files="0" tests="8" reached="841" script_gates_unmodelled="576" root="." graph_ambiguous="6100" graph_unresolved="3097" counts_floor="1">
<test p="test/cloneband_harness.cpp" run="bash test/clonebandcheck.sh"/>
<test p="test/clonelex_harness.cpp" run="bash test/clonelexcheck.sh"/>
<test p="test/columnarcommafix/columnar_comma_test.cpp" run="bash test/columnarcommacheck.sh"/>
<test p="test/connectcore_harness.cpp" run="bash test/connectcorecheck.sh"/>
<test p="test/includeprecise_unit.cpp" run="bash test/includeprecisecheck.sh"/>
<test p="test/rustimport_unit.cpp" run="bash test/rustimportprecisecheck.sh"/>
<test p="test/type3clone_harness.cpp" run="bash test/type3clonecheck.sh"/>
<test p="test/verify_csr.cpp" run="bash test/a9disclosurecheck.sh"/>
</affected>
```

**Shaped by:** `--mentions`, `--exercises`, `--test-gate`, `--edit-target-file`

**Caveats (stated by the binary):**

- An item matching NEITHER refuses (exit 1) naming both readings.
- seed_test_files=N of the matched files are TEST files: a test cannot reach a change it is part of, so its own symbols are not seeds of the caller walk, and its row carries seed_kind="test" -- it is listed because the argument matched it (it changed, run it), not because it reaches.
- script_gates_unmodelled= counts the script runners under test/, recursively (a path count;

### `--exercises=TESTFILE`

**Answers:** the INVERSE of --affected: the non-test symbols this test file transitively calls into -- what it actually covers.

The first question when a test fails and you have its name and nothing else. Ranked by PageRank, capped at 40 rows (raise with --limit; --offset pages). A NON-TEST path REFUSES rather than answering generically: this verb IS the test/non-test partition (it subtracts test code from the answer), which means nothing for a non-test file -- for "what does this call", use --callees=SYM or --graph-query callees(...) A shell harness carries harness=script: subprocess coverage is unmodelled, so reaches=0 there is a stated limit, not a measurement (the inverse of script_gates_unmodelled).

**Try it**

_Which symbols a TEST FILE exercises — the reverse direction of --affected._

```
$ ./build/ripwire . --exercises=test/regression.sh
<!-- ripwire exercises: the NON-TEST symbols this test transitively calls into — what it covers (the inverse of the affected verb). <t> = the seed test files the pattern matched; <s> = the covered symbols, PageRank desc. harness=script|mixed says the seed set contains shell gates, whose subprocess coverage this walk cannot see. counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<exercises of="test/regression.sh" seed_files="1" shown_seed_files="1" seed_files_capped="0" test_symbols="3" reaches="0" harness="script" note="a shell gate invokes the compiled binary as a subprocess; script-to-binary edges are not modelled, so reaches= counts call-graph reach only and cannot see  … [line truncated: 136 more bytes on this line]
<t p="test/regression.sh" run="bash test/regression.sh"/>
</exercises>
```

**Shaped by:** `--test-gate`, `--limit`

**Caveats (stated by the binary):**

- Ranked by PageRank, capped at 40 rows (raise with --limit;

### `--situ[=F1,F2]`

**Answers:** situational awareness for a change: blast radius + tests + co-change (default = git diff)

**Try it**

_Mid-task situational report for the current git diff — recorded against a DIRTY tree (contrast with the sandbox run below)._

```
$ ./build/ripwire . --situ
ripwire situational-awareness — 0 changed file(s), 0 symbols in them
root: .
at: 5f71cb4fd+dirty
  (0 changed files — working tree is clean, nothing to analyze)
```

**Shaped by:** `--top-k`, `--mentions`, `--affected`, `--test-gate`, `--legend`

### `--handoff`

**Answers:** continuation packet for the NEXT session: <verified> disk truth (branch/sha, changed files+symbols, blast radius, tests-to-run) + <heuristic> labeled suggestions (co-change partners, committed notes, plan/design doc pointers via a branch+commit-subject query).

Empty diff is fine — the packet still carries branch/sha + heuristics. Composes with --token-budget=N (drops heuristic rows tail-first, disclosed as withheld= in the header; verified rows are never dropped). Single-root only.

**Try it**

_The continuation packet for the NEXT session: <verified> disk truth (branch/sha, changed symbols, blast radius, tests) + <heuristic> labeled suggestions. Recorded against a DIRTY tree._

```
$ ./build/ripwire . --handoff
<!-- ripwire handoff: the continuation packet for the NEXT session. <verified> is disk truth (branch=/at=<sha>[+dirty]/subject=<commit subject text>, changed files+symbols via git numstat, blast_files=transitive dependent files, tests-to-run); run= is the command that discharges a test row; run_unknown="1" means none is derivable for that harness (a guess would be worse than none) — a row carries one or the other, never neither. <heuristic> is labeled non-verified suggestion (cochange=usually-edited-together deg=degree, note=committed .ripwire_notes row, doc=plan/design pointer s=lexical score for the branch+commit-subject query). branch= is git's own answer, so on a DETACHED head it reads HEAD and detached=1 says so (the commit is at=); detached= is absent when a branch is checked out. &lt;heuristic n= candidates= capped=&gt;: n= is the rows in the packet, candidates= how many the three classes produced before their own per-class caps (cochange 8, notes 8, docs 4), capped=1 when a cap dropped one — so candidates - n - withheld_rows is what the caps removed and nothing is lost silently. budget= is the token-budget cap; withheld=1 when heuristic rows were dropped to fit it, withheld_rows= how many (the map's spelling: a boolean, the count beside it) — verified rows are never dropped; est_tokens= prices the delivered packet in tokens and over_ceiling= is 1 when even the verified floor exceeds budget= (the packet is then complete, not trimmed). gitok=0 means the git diff probe failed and changed counts are floors. -->
<handoff at="5f71cb4fd+dirty" root="." branch="integration/harvest-b-2026-09-05" subject="Merge branch &apos;lane/hb-R2&apos; into integration/harvest-b-2026-09-05" gitok="1" est_tokens="1011">
<verified changed="0" blast_files="0">
<tests n="0">
</tests>
</verified>
<heuristic n="5" candidates="98" capped="1">
<note target="test/manifestcheck.sh" txt="README.md&apos;s single &apos;&lt;N&gt; gate scripts&apos; claim (~line 1305) is NOT enforced — the derived-vs-stated sibling loop here covers docs/EVALS.md only. It drifted 407→451 unnoticed (fixed 2026-08-23). To close: grep both files (&apos;file:line … [line truncated: 47 more bytes on this line]
<doc p="docs/SUBSTITUTION_METER.md" s="12.002"/>
<doc p="docs/COMMANDS.md" s="10.750"/>
<doc p="docs/EVALS.md" s="10.674"/>
<doc p="skills/CONSOLIDATION.md" s="9.830"/>
</heuristic>
</handoff>
```

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
<!-- ripwire test-gate (TDAD-parity, arXiv 2603.17973, -70% agent-caused regressions): tests to run for this change + the UNTESTED blast radius; exit 4 if tests OR untested is non-empty, else run them and rely on green. shown_tests=/shown_untested= are TWO INDEPENDENT row counts: the <t> tests-to-run rows and the <u> blast-radius rows. script_gates_unmodelled= is the legacy test/*.sh corpus path count; script_gates_registered= counts suite members; script_gates_mapped= those with exact dependency evidence; script_gates_unresolved_dynamic= is the registered remainder, disclosed rather than guessed. Shell <t> rows join tests= only via evidence=script_literal (script text contains the changed path) or evidence=manifest_declared (RIPWIRE_TEST_DEPS metadata). counts_floor=1 keeps these static evidence counts honest about shell expansion and generated paths they cannot resolve; graph_ambiguous=/graph_unresolved= are the map header's ambiguous=/unresolved= (the resolver gauge: calls split over several defs / calls whose in-repo defs were all language-filtered). next= is the one pasteable follow-up: the first <t> row's run= (a shell line), else a ripwire invocation. ccx_bar= is the cognitive-complexity bar a <u> row's ccx= is read against (quality-delta's own). UNIT: untested= here counts impacted SYMBOLS. The seams verb spells untested= over cross-directory call EDGES and the flip verb over the defs a gate lights — three different things, never compared or summed across verbs. -->
<test-gate changed="0" impacted="0" tests="0" untested="0" shown_tests="0" tests_capped="0" shown_untested="0" untested_capped="0" script_gates_unmodelled="576" script_gates_registered="557" script_gates_mapped="129" script_gates_unresolved_dynamic="428" ccx_bar="15" graph_ambiguous="6100" graph_unr … [line truncated: 67 more bytes on this line]
</test-gate>
```

**Shaped by:** `--mentions`, `--affected`, `--quality-delta`, `--edit-target-file`, `--json`, `--limit`

**Caveats (stated by the binary):**

- NO run= means NOT DERIVABLE -- never a guessed suite command

### `--grep=STR | --regex=PAT`

**Answers:** literal / regex search + enclosing symbol + the matched line.

SPAN-TIERED by default (see --grep-in below): the scan itself is exhaustive, the ANSWER serves one tier and discloses what it held back. --grep-in=any is the exhaustive VIEW -- every hit, no tiering. For task-ranked retrieval use --for=TASK (ranks by PageRank + task relevance).

**Try it**

_Regex search + enclosing symbol._

```
$ ./build/ripwire . --regex='fnv1a\w+'
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. tier_partial= (value 1, present only then) qualifies that label: it was elected over the CLASSIFIED hits ALONE while tier_unclassified= hits were never classified, so read it as the tightest tier PROVEN present, never as proof that no hit is code. Nothing past the budget is suppressed, so the partiality narrows what the LABEL may be read to mean, never which rows you got; its absence beside a tier= means the label is a fact. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then — and the root then also carries counts_floor="1": the tier counts are floors while hits= stays exact and every row is served), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="fnv1a\w+" root="." files="19" hits="77" shown="77" capped="0" hits_capped="0" suppressed_comment="49" suppressed_string="10" tier_parsed="32" tier_unclassified="0" corpus_oversize="15" unindexed_hits="23" unindexed_files_scanned="169" unindexed_files_skipped="1" next="--at=src/arch.h: … [line truncated: 5 more bytes on this line]
<f p="src/arch.h">
<hit l="507" in="rw::fnv1a64">
<![CDATA[inline std::uint64_t fnv1a64( std::string_view s ) noexcept]]>
</hit>
<hit l="512" in="rw::fnv1a64">
<![CDATA[        h = hashutil::fnv1aAbsorb( h, c );]]>
</hit>
<hit l="620" in="rw::archViolHash">
<![CDATA[            h = hashutil::fnv1aAbsorb( h, c );]]>
</hit>
<hit l="623" in="rw::archViolHash">
<![CDATA[        h = hashutil::fnv1aMultiply( h ); // NUL separator byte]]>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--and`, `--not`, `--grep-scope`, `--handles`, `--expand`, `--no-redact`, `--insert-after-symbol`

### `--grep-context=N | --grep-before=N / --grep-after=N`

**Answers:** ripgrep-style N lines of source around each hit

**Try it**

_Same search with one line of source context either side._

```
$ ./build/ripwire . --grep=DEGRADED_PATH_ALERT --grep-context=1
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. tier_partial= (value 1, present only then) qualifies that label: it was elected over the CLASSIFIED hits ALONE while tier_unclassified= hits were never classified, so read it as the tightest tier PROVEN present, never as proof that no hit is code. Nothing past the budget is suppressed, so the partiality narrows what the LABEL may be read to mean, never which rows you got; its absence beside a tier= means the label is a fact. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then — and the root then also carries counts_floor="1": the tier counts are floors while hits= stays exact and every row is served), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" root="." files="66" hits="236" shown="100" capped="1" total="236" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="103" suppressed_string="33" tier_parsed="97" tier_unclassified="0" corpus_oversize="15" unindexed_hits="29" un … [line truncated: 120 more bytes on this line]
<f p="src/abicheck.h" parse_degraded="1">
<hit l="482" in="abicheck::collectAuthoredSites">
<b>
<![CDATA[        {]]>
</b>
<![CDATA[            DEGRADED_PATH_ALERT( "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
<a>
<![CDATA[            ++result.unrelated;]]>
</a>
</hit>
</f>
<f p="src/arch.h">
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-redact`

### `--and=STR`

**Answers:** (repeatable)   modifies --grep=STR: keep only hits where STR is ALSO present (literal-only, no --regex)

**Try it**

_Boolean grep: hits where BOTH literals share the matched line (--grep-scope=line is the default)._

```
$ ./build/ripwire . --grep=DEGRADED_PATH_ALERT --and=cache
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. terms= (present only with and/not) restates the whole boolean query as it was EVALUATED: the base pattern, then each and term prefixed +, each not term prefixed -. scope=line (default) requires every term on the SAME matched line as the base pattern; scope=file requires every term ANYWHERE in the file, independent of which line matched. terms_suppressed= counts the raw hits the boolean filter REJECTED — a different axis from hits_capped= (a collection-budget ceiling): hits=/shown=/etc. already read the FILTERED count, so terms_suppressed= exists only so a reader can recover how many the un-filtered scan would have shown. SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. tier_partial= (value 1, present only then) qualifies that label: it was elected over the CLASSIFIED hits ALONE while tier_unclassified= hits were never classified, so read it as the tightest tier PROVEN present, never as proof that no hit is code. Nothing past the budget is suppressed, so the partiality narrows what the LABEL may be read to mean, never which rows you got; its absence beside a tier= means the label is a fact. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then — and the root then also carries counts_floor="1": the tier counts are floors while hits= stays exact and every row is served), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" root="." terms="DEGRADED_PATH_ALERT +cache" scope="line" terms_suppressed="339" files="6" hits="28" shown="28" capped="0" hits_capped="0" suppressed_comment="1" suppressed_string="4" tier_parsed="8" tier_unclassified="0" corpus_oversize="15" unindexed_hits="29" un … [line truncated: 88 more bytes on this line]
<f p="src/gitoracle.h">
<hit l="321" in="gitoracle::saveOracleCache">
<![CDATA[        DEGRADED_PATH_ALERT( "gitoracle: cannot write the history cache — the probe stays correct but re-runs cold" );]]>
</hit>
<hit l="329" in="gitoracle::saveOracleCache">
<![CDATA[        DEGRADED_PATH_ALERT( "gitoracle: history cache write/rename failed — the probe stays correct but re-runs cold" );]]>
</hit>
</f>
<f p="src/ingest_cache.h">
<hit l="1027" in="openCacheFrame">
<![CDATA[            DEGRADED_PATH_ALERT( "ingest: cache blob is a different format version — rejected and rebuilt (full reparse)" );]]>
</hit>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--grep-scope`

### `--not=STR`

**Answers:** (repeatable)   modifies --grep=STR: drop hits where STR IS present (literal-only, no --regex)

**Try it**

_Drop every hit in a file that ALSO contains the --not literal anywhere (file scope)._

```
$ ./build/ripwire . --grep=DEGRADED_PATH_ALERT --not=test --grep-scope=file
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. terms= (present only with and/not) restates the whole boolean query as it was EVALUATED: the base pattern, then each and term prefixed +, each not term prefixed -. scope=line (default) requires every term on the SAME matched line as the base pattern; scope=file requires every term ANYWHERE in the file, independent of which line matched. terms_suppressed= counts the raw hits the boolean filter REJECTED — a different axis from hits_capped= (a collection-budget ceiling): hits=/shown=/etc. already read the FILTERED count, so terms_suppressed= exists only so a reader can recover how many the un-filtered scan would have shown. SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. tier_partial= (value 1, present only then) qualifies that label: it was elected over the CLASSIFIED hits ALONE while tier_unclassified= hits were never classified, so read it as the tightest tier PROVEN present, never as proof that no hit is code. Nothing past the budget is suppressed, so the partiality narrows what the LABEL may be read to mean, never which rows you got; its absence beside a tier= means the label is a fact. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then — and the root then also carries counts_floor="1": the tier counts are floors while hits= stays exact and every row is served), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" root="." terms="DEGRADED_PATH_ALERT -test" scope="file" terms_suppressed="355" files="7" hits="8" shown="8" capped="0" hits_capped="0" suppressed_comment="9" tier_parsed="10" tier_unclassified="0" corpus_oversize="15" unindexed_hits="29" unindexed_files_scanned="1 … [line truncated: 71 more bytes on this line]
<f p="src/commentcoherence.h" parse_degraded="1">
<hit l="204" in="rw::computeCommentCoherence">
<![CDATA[                DEGRADED_PATH_ALERT( "comment-coherence: an indexed file could not be read — its functions are absent from the report" );]]>
</hit>
</f>
<f p="src/infra/Diagnostics.h">
<hit l="158" in="DEGRADED_PATH_ALERT">
<![CDATA[#define DEGRADED_PATH_ALERT(msg)                                                \]]>
</hit>
<hit l="166" in="DEGRADED_PATH_ALERT">
<![CDATA[#define DEGRADED_PATH_ALERT(msg)        do { } while (0)]]>
</hit>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--grep-scope`, `--no-redact`, `--legend`

### `--grep-scope=line|file`

**Answers:** modifies --and=/--not=: line (default) requires the SAME matched line;

file requires anywhere in the same file. Second occurrence of --grep=/--regex= itself REFUSES (naming --and= as the AND spelling) rather than silently overwriting the pattern.

**Try it**

_Drop every hit in a file that ALSO contains the --not literal anywhere (file scope)._

```
$ ./build/ripwire . --grep=DEGRADED_PATH_ALERT --not=test --grep-scope=file
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. terms= (present only with and/not) restates the whole boolean query as it was EVALUATED: the base pattern, then each and term prefixed +, each not term prefixed -. scope=line (default) requires every term on the SAME matched line as the base pattern; scope=file requires every term ANYWHERE in the file, independent of which line matched. terms_suppressed= counts the raw hits the boolean filter REJECTED — a different axis from hits_capped= (a collection-budget ceiling): hits=/shown=/etc. already read the FILTERED count, so terms_suppressed= exists only so a reader can recover how many the un-filtered scan would have shown. SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. tier_partial= (value 1, present only then) qualifies that label: it was elected over the CLASSIFIED hits ALONE while tier_unclassified= hits were never classified, so read it as the tightest tier PROVEN present, never as proof that no hit is code. Nothing past the budget is suppressed, so the partiality narrows what the LABEL may be read to mean, never which rows you got; its absence beside a tier= means the label is a fact. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then — and the root then also carries counts_floor="1": the tier counts are floors while hits= stays exact and every row is served), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" root="." terms="DEGRADED_PATH_ALERT -test" scope="file" terms_suppressed="355" files="7" hits="8" shown="8" capped="0" hits_capped="0" suppressed_comment="9" tier_parsed="10" tier_unclassified="0" corpus_oversize="15" unindexed_hits="29" unindexed_files_scanned="1 … [line truncated: 71 more bytes on this line]
<f p="src/commentcoherence.h" parse_degraded="1">
<hit l="204" in="rw::computeCommentCoherence">
<![CDATA[                DEGRADED_PATH_ALERT( "comment-coherence: an indexed file could not be read — its functions are absent from the report" );]]>
</hit>
</f>
<f p="src/infra/Diagnostics.h">
<hit l="158" in="DEGRADED_PATH_ALERT">
<![CDATA[#define DEGRADED_PATH_ALERT(msg)                                                \]]>
</hit>
<hit l="166" in="DEGRADED_PATH_ALERT">
<![CDATA[#define DEGRADED_PATH_ALERT(msg)        do { } while (0)]]>
</hit>
... [17 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- Second occurrence of --grep=/--regex= itself REFUSES (naming --and= as the AND spelling) rather than silently overwriting the pattern.

### `--grep-in=code|any`

**Answers:** SPAN TIERS: which tree-sitter span a hit must sit in to print.

code (default) serves the CODE tier when any hit is code, and otherwise comment AND string TOGETHER (tier= "comment+string"), disclosing what it held back (suppressed_comment=/suppressed_string=); a pattern living only in prose is still answered, never silently emptied. any turns tiering off entirely -- the exhaustive view. Hit files are parsed on demand under a fixed budget; tier_budget= says so when it stops, and hits it never classified are emitted, never suppressed.

**Try it**

_Span tiers off: the exhaustive view — the comment and string hits the default tier held back (suppressed_comment=96 / suppressed_string=29 in the plain --grep block above) now print alongside the code hits; hits= grows accordingly._

```
$ ./build/ripwire . --grep=DEGRADED_PATH_ALERT --grep-in=any
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" root="." files="97" hits="372" shown="100" capped="1" total="372" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" corpus_oversize="15" unindexed_hits="29" unindexed_files_scanned="169" unindexed_files_skipped="1" next="--grep=DEGRADED_PATH_ALER … [line truncated: 33 more bytes on this line]
<f p=".github/workflows/ci.yml">
<hit l="115" in="release">
<![CDATA[    #   Release — defines NDEBUG, which compiles DEGRADED_PATH_ALERT out; the optimizer-visible build.]]>
</hit>
<hit l="116" in="release">
<![CDATA[    #   plain   — NDEBUG off, so DEGRADED_PATH_ALERT compiles in and the degrade-path gates can observe]]>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="108">
<![CDATA[#include "infra/Diagnostics.h"  // VERIFY / DEGRADED_PATH_ALERT]]>
</hit>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--grep`

**Caveats (stated by the binary):**

- a pattern living only in prose is still answered, never silently emptied.
- tier_budget= says so when it stops, and hits it never classified are emitted, never suppressed.

### `--handles`

**Answers:** (with --grep/--regex) add h= to each unique editable enclosing-symbol row: a stable identity plus the file-content hash pinned when grep ran.

Ambiguous or document-only rows get no handle; a later edit must refuse after any file change rather than retarget stale coordinates.

**Try it**

_h= on each editable enclosing-symbol row: a freshness-pinned identity an edit verb can target and must refuse on after any file change._

```
$ ./build/ripwire . --grep=DEGRADED_PATH_ALERT --handles
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. tier_partial= (value 1, present only then) qualifies that label: it was elected over the CLASSIFIED hits ALONE while tier_unclassified= hits were never classified, so read it as the tightest tier PROVEN present, never as proof that no hit is code. Nothing past the budget is suppressed, so the partiality narrows what the LABEL may be read to mean, never which rows you got; its absence beside a tier= means the label is a fact. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then — and the root then also carries counts_floor="1": the tier counts are floors while hits= stays exact and every row is served), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<!-- ripwire grep handles: h= is sym#<stable-identity-hash>@<whole-file-content-hash>; the content half pins the exact file bytes scanned, so an edit after any file change refuses as stale. Only one editable enclosing definition receives h=. handle_omitted=ambiguous means the name grouped several definitions; non-code means a document/data section has no safe definition span; unreadable means no content hash could be proven. -->
<grep pattern="DEGRADED_PATH_ALERT" root="." files="66" hits="236" shown="100" capped="1" total="236" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="103" suppressed_string="33" tier_parsed="97" tier_unclassified="0" corpus_oversize="15" unindexed_hits="29" un … [line truncated: 120 more bytes on this line]
<f p="src/abicheck.h" parse_degraded="1">
<hit l="482" in="abicheck::collectAuthoredSites">
<![CDATA[            DEGRADED_PATH_ALERT( "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
<f p="src/arch.h">
<hit l="353" in="rw::parseArchRules">
<![CDATA[        DEGRADED_PATH_ALERT( "arch: malformed rules line — rules file rejected" );]]>
</hit>
<hit l="408" in="rw::parseArchRules">
<![CDATA[                catch( const std::regex_error& ) { pr.bad = true; DEGRADED_PATH_ALERT( "arch: malformed FROM path-regex — rule skipped" ); }]]>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--insert-after-symbol`

**Caveats (stated by the binary):**

- Ambiguous or document-only rows get no handle;
- a later edit must refuse after any file change rather than retarget stale coordinates.

### `--match=QUERY`

**Answers:** tree-sitter structural (shape) query

**Try it**

_Tree-sitter structural query WITHOUT a capture — a bare node query gets a capture AUTO-ADDED (auto_captured="1") and matches the same nodes the explicit form does._

```
$ ./build/ripwire . --match='(if_statement)'
<!-- ripwire match: tree-sitter structural query; each hit = a captured node + its enclosing symbol. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (engine match limit reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that NO page holds (the engine cap, not the window, dropped them; narrow the query), while has_more= keeps its window meaning so a loop still terminates. auto_captured="1" ⇒ the query bound no @capture and ripwire appended `@m` to its single top-level pattern. grammars= names every grammar the query compiled against; eligible_files=/of_files= are corpus files in that language set vs total indexed files. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<match hits="5000" shown="100" capped="1" total="5000" has_more="1" next_offset="100" offset="0" limit="0" counts_floor="1" hits_capped="1" auto_captured="1" grammars="cpp,c,python,go,typescript,swift,objc,javascript,bash,java,csharp,php,lua" eligible_files="1334" of_files="1590" root=".">
<m p="bench/agentloop/analyze.py:37" in="load_results">if data.get( "schema" ) != SCHEMA:         raise SystemExit( f"{path}: unexpected schema {data.get('schema')!r} (expecte</m>
<m p="bench/agentloop/analyze.py:48" in="load_results">if not str( data.get( "tasks_lock_content_sha256", "" ) ).startswith( "questions:" ):         train_repos = select_tasks</m>
<m p="bench/agentloop/analyze.py:50" in="load_results">if train_repos:             raise SystemExit(                 f"{path}: records from repo(s) that re-derive to LocBench </m>
<m p="bench/agentloop/analyze.py:72" in="pair_by_task_seed">if base and ctx and base["status"] == "ok" and ctx["status"] == "ok":             paired.append( ( instance_id, base["re</m>
<m p="bench/agentloop/analyze.py:101" in="clustered_bootstrap_lower">if not repos: return 0.0, []</m>
<m p="bench/agentloop/analyze.py:117" in="loc_hit_delta">if base["localization_hit"] is None or ctx["localization_hit"] is None: return 0.0</m>
<m p="bench/agentloop/analyze.py:126" in="paired_ratio">if bv: ratios.append( cv / bv - 1 )</m>
<m p="bench/agentloop/analyze.py:127" in="paired_ratio">if not ratios: return None, None</m>
<m p="bench/agentloop/analyze.py:146" in="substitution_rate">if rw is None or native is None:         return None</m>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-redact`, `--sarif`, `--limit`

### `--pattern=PAT`

**Answers:** structural search written in CODE, not in node kinds: --pattern='foo($X, ...)'.

$NAME binds one node (repeat it and both sites must match structurally); $_ binds nothing; ... (or $$$) is an ellipsis over siblings, matched by ONE first-match-wins probe under a hard cap -- both facts on the element. Comments are transparent, everything else is kind- and text-exact ($A + $B does not match a - b). Served: c cpp objc java csharp javascript typescript python go rust swift; ruby, bash and the data tiers are named in unsupported= instead of answered. A pattern no served grammar resolves, or that collapses to a bare token, is REFUSED -- never reported as hits=0.

**Try it**

_A pattern that collapses to a bare token is REFUSED — never reported as hits=0._

```
$ ./build/ripwire . --pattern='x'
(empty)
```

**Shaped by:** `--limit`

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
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- files=1590 symbols=13896 edges=17115 shown=5 est_tokens=914 ambiguous=6100 unresolved=3097 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=20 order=important-first -->
<r root="." est_tokens="914">
<f p="src/serialize.h">
<s t="var" n="kChurnRankLegend" id="src/serialize.h::rw::kChurnRankLegend" k="18.4617">
</s>
</f>
<f p="src/main.cpp">
<s t="fn" n="churnRankedGraph" amb="4" k="14.4490">
<c n="resolveSinceScope"/>
<c n="churnTeleport"/>
<c n="churnTeleportWorkspace"/>
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
<ctx task="pagerank power iteration" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="5f71cb4fd+dirty" doc_mentions="4" est_tokens="5133">
<!-- ripwire lens for "pagerank power iteration" [doc mentions: 4 docs discussing 3 top-ranked symbols surfaced; doc_mentions= on the root repeats the doc count] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="16" est_tokens= prices this bundle in tokens -->
<sigs shown="24" total="40" capped="1">
<d l="40" n="HOT_FILES" p="scripts/optremarks.py" cx="0" ccx="0" in="0" churn="3" amp="37" r="1" next="--expand=scripts/optremarks.py:HOT_FILES">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix ent … [line truncated: 42 more bytes on this line]
<d l="73" n="renderDisclosure" id="src/prconverge.h::rw::renderDisclosure" p="src/prconverge.h" cx="12" ccx="15" in="13" churn="2" amp="30" r="2">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
<d l="51" n="RankDisclosure" id="src/prconverge.h::RankDisclosure::RankDisclosure" p="src/prconverge.h" cx="0" ccx="0" in="0" churn="2" amp="17" r="3">
<doc>What a ranked document discloses about the power iteration that ordered it. `isPageRank == false…</doc>struct RankDisclosure</d>
<d l="2492" n="RankedGraph" id="src/graph.h::RankedGraph::RankedGraph" p="src/graph.h" cx="0" ccx="0" in="0" churn="60" amp="195" r="4">
<doc>What a rank call hands back: the vector, and the power iteration&apos;s own account of itself. Struct…</doc>struct RankedGraph</d>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--for`, `--signatures-only`, `--auto-bodies`, `--compress`, `--owners`, `--plan`, `--abi`, `--flip`

### `--pack-signatures`

**Answers:** body-elided decl skeletons — ~72-90% fewer element bytes than the same symbols' full --expand bodies (roughly 80% at the top-50 sigs payload cap — the sigs payload is top-50 whatever --top-k is set to, and --top-k's own default is 200), measured at top-10/50/100 on this repo with the corpus-root prefix subtracted from both sides: that prefix repeats inside every element, is charged in both forms, and is not what this elides — count it and the figure becomes a function of how deep your checkout sits.

test/showcasecapturecheck.sh (C) re-derives this range from the SAME repo every run and fails on drift. The share RISES with the result size. Like the --format=columnar sibling, a small result can invert it — a signature plus its doc comment can be bigger than a short body.

**Try it**

_Body-elided decl skeletons — recounted on this corpus. Measured as element bytes: the <d> signature+doc elements --pack-signatures emits, against the SAME symbols' full <b> bodies from --expand, with the CORPUS-ROOT PREFIX SUBTRACTED FROM BOTH SIDES. That subtraction is the whole methodology and the figure is meaningless without it: the root repeats inside every element's id= and p=, it is not what this verb elides, and counting it makes the headline a function of how deep the checkout happens to sit on disk — on one corpus, three spellings of the same root read 18.6 points apart before the subtraction and agree exactly after it. Root-neutralised on THIS repo: 80.9% fewer bytes at top-10, 75.6% at top-50, 73.7% at top-100 (re-derived 2026-09-05 at the capture-audit close: lane L7's P16 caps --expand's sibs= at 8 names, which SHRINKS the body side of this ratio and moved the figure down from 84.5/80.2/80.6 — the V1 2026-08-15 re-center, when sibs=/inc= first grew the body side from 70.0/61.0/63.8, in reverse; both were real re-derivations, not tolerance edits). top-50 is the number to quote, because the sigs payload is top-50 regardless of --top-k and is therefore what THIS command emits. A single small/trivial body can still invert it (signature+doc bigger than the body), like the --format=columnar sibling below. test/showcasecapturecheck.sh (C) re-derives all three from this repo every run, in the same quantity, and fails if the caption and the recount drift apart._

```
$ ./build/ripwire . --pack-signatures --top-k=10
<ctx>
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1590 symbols=13896 edges=17115 shown=10 est_tokens=4633 ambiguous=6100 unresolved=3097 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=20 order=important-first -->
<r root="." est_tokens="4633" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2" k="0.0071">
</s>
<s t="method" n="push_back" id="src/infra/svector.h::svector::push_back" amb="2" k="0.0054">
<c n="buf"/>
<c n="buf"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--limit`

### `--outline=A,B,...`

**Answers:** control-flow skeletons of A,B,...

(same selector grammar as --expand, minus the range)

**Try it**

_Control-flow skeleton of one symbol, payload-only via the new --top-k=0._

```
$ ./build/ripwire . --outline=rankGraphTeleport --top-k=0
<ctx root="." est_tokens="219"><outline><o t="fn" l="2501" p="src/graph.h" n="rankGraphTeleport"><![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
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

**Shaped by:** `--top-k`, `--expand`, `--compress`, `--no-redact`, `--limit`

### `--expand=A,B,...`

**Answers:** full bodies of A,B,...

Selector grammar per item (the tail after the LAST ':' decides; a tail STARTING WITH A DIGIT is a range, anything else is a name): NAME                every def of that name  |  FILE:NAME           that file's def NAME:START-END      body slice              |  FILE:NAME:START-END selector + slice FILE:LINE:NAME      paste a row's p="path:line" straight from --callers/--lint/--grep (NOT --hotspots: its p= is a BARE path — build FILE:LINE:NAME from its own p=/top_l=/top= instead, since top= is just the worst function's name) path::scope::name   the canonical id= --for/--pack-task emit Scope::name         the sym= spelling edit-check and grep's in= rows print — matches the name under any scope whose ::-boundary SUFFIX is Scope (Box::lid, deep::Box::lid); a wrong scope refuses, it never falls back to the bare-name union (START-END is 1-based within the def's OWN body — lines="lo-hi/total" marks the slice partial; out-of-range clamps. FILE matches any path substring, like --callers/--lego.) EXACT-NAME DEFAULT (one token, one unambiguous match, no explicit --top-k): the ranked map defaults to top-k=0 — you already named the exact symbol, so the ~200-row orientation map is pure overhead in front of the one body it exists to summarize. Disclosed on the root as topk_default="0" (self-describing: the change is visible without reading source). A MULTI-match name (an ambiguous bare name) or a multi-token --expand keeps the map — there IS something to disambiguate. An EXPLICIT --top-k=N (0 included) always overrides this default. Each body also carries sibs="a,b,..." sibs_total="N" [sibs_capped="1"] (the file's OTHER symbols, names only, capped at 40) and inc="x.h,..." inc_total="N" [inc_capped="1"] (the file's own #include/import targets, capped at 24) — both absent when the count is 0 (a documented zero, not a degrade), so a body no longer needs a second --outline call just to learn what else lives in its file. CHEAPEST-COMPLETE-ANSWER SERVING (no explicit --top-k, no range slice): the verb ALSO measures the (possibly map-less) bundle against the requested symbols' whole FILE(s) and emits the SMALLER, disclosed on the root as mode="bundle|whole-file" reason="the two byte counts" — on a small file the old bundle was 5.65x the file itself; on a big file the bundle saves ~26x. The whole-file form is <src p= sym="name:line,..."> with the file CDATA-wrapped (redacted as usual) and every requested symbol's line anchor kept. An EXPLICIT --top-k=N (including 0) opts out of BOTH the exact-name default and mode= auto-selection and keeps the classic undecorated shape; a SYM:START-END slice opts out of mode= auto-selection only (serving the whole file would invert an explicit narrowing) but still gets the exact-name top-k=0 default when it applies.

**Try it**

_NEW since the last capture: --top-k=0 means PAYLOAD-ONLY — no ranked map rides along with the body you asked for._

```
$ ./build/ripwire . --top-k=0 --expand=rankGraphTeleport
<ctx root="." est_tokens="949">
<!-- a body's sibs="a,b,..." sibs_total=N are the file's OTHER indexed symbols (this body's own name excluded), source order, capped at 8 (sibs_capped="1" when the cap fired); inc="x.h,..." inc_total=N are the file's own #include/import targets, source order, capped at 24 (inc_capped="1" when the cap fired) — both absent when the count is 0 (a documented zero, not a degrade). Each body's own calls child (1-hop callee signatures) carries total=/shown=/capped="1" the usual way: capped="1" only when shown is below total. A body's CDATA is the bytes on disk unless the element says otherwise: scrubbed="1" = a ]]> was split (]]]]>
<![CDATA[>, rejoin it) or a C0/invalid-UTF-8 byte was replaced; redacted="1" = a credential shape was rewritten to a [REDACTED:kind] marker (the no-redact flag serves the bytes; the edit verbs refuse a payload carrying MORE such markers than the bytes it would replace already do, so source that spel … [line truncated: 59 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2501" p="src/graph.h" n="rankGraphTeleport" sibs="Graph,langCompatible,namespaceCompatible,kCommonNameMul,kCommonNameDefThreshold,kPrivateNameMul,kSpecificNameMul,kSpecificMinLen" sibs_total="150" sibs_capped="1" inc="model.h,filter.h,pageview.h,graphlegend.h,lintrules.h,infra/sparseCsr … [line truncated: 228 more bytes on this line]
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    PageRankRun         run{};   // an N == 0 graph never enters the kernel: { 0, converged } — see PageRankRun
    if( N )
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--for`, `--pack-signatures`, `--outline`, `--compress`, `--no-redact`, `--hotspots`, `--edit-check`

**Caveats (stated by the binary):**

- a wrong scope refuses, it never falls back to the bare-name union (START-END is 1-based within the def's OWN body — lines="lo-hi/total" marks the slice partial;
- FILE matches any path substring, like --callers/--lego.) EXACT-NAME DEFAULT (one token, one unambiguous match, no explicit --top-k): the ranked map defaults to top-k=0 — you already named the exact symbol, so the ~200-row orientation map is pure overhead in front of the one body it exists to summarize.
- A MULTI-match name (an ambiguous bare name) or a multi-token --expand keeps the map — there IS something to disambiguate.

### `--compress`

**Answers:** strip comments + collapse blank runs from SERVED BODIES (~20-35% token cut): --expand/ --outline, --for's auto/anchor and --detail=N bodies, --pack-task, --from-trace and --exemplar.

Disclosed per bundle as compress="1" on the <bodies> element; without the flag, output is byte-identical. String literals survive; the ranked SET never changes.

**Try it**

_Comments stripped + blank runs collapsed — compressBody is the function that implements --compress itself, chosen because it is comment-heavy enough to show a real reduction (the previously captioned symbol had no comments or blank runs, so before/after were byte-identical under a caption promising a difference)._

```
$ ./build/ripwire . --expand=compressBody --top-k=0 --compress
<ctx root="." est_tokens="1671">
<!-- a body's sibs="a,b,..." sibs_total=N are the file's OTHER indexed symbols (this body's own name excluded), source order, capped at 8 (sibs_capped="1" when the cap fired); inc="x.h,..." inc_total=N are the file's own #include/import targets, source order, capped at 24 (inc_capped="1" when the cap fired) — both absent when the count is 0 (a documented zero, not a degrade). Each body's own calls child (1-hop callee signatures) carries total=/shown=/capped="1" the usual way: capped="1" only when shown is below total. A body's CDATA is the bytes on disk unless the element says otherwise: scrubbed="1" = a ]]> was split (]]]]>
<![CDATA[>, rejoin it) or a C0/invalid-UTF-8 byte was replaced; redacted="1" = a credential shape was rewritten to a [REDACTED:kind] marker (the no-redact flag serves the bytes; the edit verbs refuse a payload carrying MORE such markers than the bytes it would replace already do, so source that spel … [line truncated: 59 more bytes on this line]
<bodies shown="1" total="1" capped="0" compress="1">
<b t="fn" l="2809" p="src/serialize.h" n="compressBody" sibs="xmlSafeByte,xmlScrubIsLossy,xmlControlCharRef,escapeXml,writeMultiRootTable,kMultiRootTableLegend,multiRootTableLegend,xmlCommentText" sibs_total="212" sibs_capped="1" inc="model.h,nextverb.h,arch.h,graph.h,graphlegend.h,lintrules.h,resol … [line truncated: 180 more bytes on this line]
<![CDATA[inline std::string compressBody( std::string_view src )
{


    std::string out;
    out.reserve( src.size() );

    const std::size_t N = src.size();
    std::size_t       i = 0;
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
<ctx root="." est_tokens="17281"><src p="./src/infra/svector.h"><![CDATA[#pragma once

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

**Answers:** emit source/doc text VERBATIM, redacting nothing.

Modifies the BODY-serving verbs (--expand, --for, --pack-task, --recall, --slice, --connect, --from-trace, --batch, --mcp); the default map carries no bodies (identifiers and signatures are never redacted), so bare on the map it is refused, naming one of them REDACTED by default (high-confidence credential SHAPES only, precision over recall): emitted symbol BODIES, doc/markdown bodies and doc-comment excerpts, the --outline skeleton, and SIGNATURES — a default argument carries whatever literal was written. NOT redacted, and a deliberate residual: --grep/--regex/--match hit lines and their --grep-context neighbours, and --note-add/--notes text. --grep is the exception on purpose — auditing a repo FOR secrets needs the hit you searched for shown verbatim.

**Try it**

_--no-redact: emit bodies verbatim (credential redaction is on by default)._

```
$ ./build/ripwire . --expand=readAckRecords --top-k=0 --no-redact
<ctx root="." est_tokens="1349">
<!-- a body's sibs="a,b,..." sibs_total=N are the file's OTHER indexed symbols (this body's own name excluded), source order, capped at 8 (sibs_capped="1" when the cap fired); inc="x.h,..." inc_total=N are the file's own #include/import targets, source order, capped at 24 (inc_capped="1" when the cap fired) — both absent when the count is 0 (a documented zero, not a degrade). Each body's own calls child (1-hop callee signatures) carries total=/shown=/capped="1" the usual way: capped="1" only when shown is below total. A body's CDATA is the bytes on disk unless the element says otherwise: scrubbed="1" = a ]]> was split (]]]]>
<![CDATA[>, rejoin it) or a C0/invalid-UTF-8 byte was replaced; redacted="1" = a credential shape was rewritten to a [REDACTED:kind] marker (the no-redact flag serves the bytes; the edit verbs refuse a payload carrying MORE such markers than the bytes it would replace already do, so source that spel … [line truncated: 59 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="4087" p="src/quality.h" n="readAckRecords" sibs="kBaselineFile,kMinCloneTokens,kCcxBar,kLocBar,kNestBar,kParamBar,kShortHorizonDays,kShortHorizonMinCommits" sibs_total="211" sibs_capped="1" inc="model.h,ingest.h,graph.h,clones.h,cloneidiom.h,lintrules.h,arch.h,gitmine.h,docparse.h,filte … [line truncated: 186 more bytes on this line]
<![CDATA[inline gtl::btree_map<std::string, AckRecord> readAckRecords( const std::string& path )
{
    gtl::btree_map<std::string, AckRecord> out;
    std::ifstream f( path );
    if( !f )
    {
        return out;
    }
    std::string line;
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--insert-after-symbol`

---

## assess quality / structure

### `--metrics`

**Answers:** annotate fan-in/out + complexity (descriptive;

coupling is the validated signal, complexity is a size-correlated one). also surfaces amp= (--metrics/--for/--exemplar): amp = |direct callers| (symbol-level, the in-edge CSR) + |co-change partners of the symbol's FILE| (file-level, mined from git history) — a deliberate GRANULARITY MIX, not a graph-only count; degrades to callers-only (still valid) when git/history is unavailable. NOT the same quantity as --impact's reaches=: reaches= is the TRANSITIVE blast radius over the call graph alone (everything that reaches SYM, any hop count); amp= is DIRECT callers plus a historical co-edit signal the call graph cannot see at all — the two numbers on the same symbol routinely differ several-fold (one seen case: 4.6x apart) because they measure different things, not because one is wrong. ppalt=N (C-family/C#): the body contains N alternative preprocessor branches (#else/#elif) — code that never coexists at compile time. cx/ccx/nest/loc/locals are summed over ALL branches (deterministic, but an over-count vs any single build; ~2x seen on a real SSE/scalar pair), so discount them accordingly. ripwire never guesses which branch your build compiles — it discloses the count instead. A bare #if with no #else adds no alternative and no ppalt=. Absent when 0. ev=N essential complexity (McCabe: 1=fully structured, 2+=jumps block extract-method cleanly — the jump makes it a rewrite, not a mechanical lift); ev_why=tag:count names which jumps raised it (guard-return, loop-escape, ...). A FLOOR (ev_floor=1): noreturn calls/macro-hidden exits go unseen; absent on a cx row means exactly 1, and Rust ?/ yield/await/defer are not counted, so Bash carries no ev at all. humps=/deep=/locals= are the nesting PROFILE nest= alone cannot give: nest= is a max, so one deep line and a body that is deep throughout report the same number. humps= counts regions reaching the nesting bar, deep= the lines inside them (a floor), and locals= the local-variable-declaration count (a floor, C/C++ only). Read the three together — a tangle (many humps, few deep lines each) and a long blocked-sequential body (one hump, many deep lines) have the same nest= but opposite refactors. Absent exactly when nest is below the bar (not-deep), never a hidden 0.

**Try it**

_Fan-in/out + complexity annotations on the map._

```
$ ./build/ripwire . --metrics --top-k=10
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- metrics: in=fan-in out=fan-out cx=cyclomatic ccx=cognitive loc=lines params=count nest=MAX-depth humps=regions-reaching-the-nesting-bar deep=lines-inside-them(floor,see deep_floor) (humps/deep are the PROFILE nest= cannot give: nest= is a max, so one deep line and a body that is deep throughout report the same number; deep/loc is the fraction. Both absent exactly when nest<bar — not-deep, never a hidden 0. deep counts LINES and humps counts REGIONS, and two regions can share a line, so deep BELOW humps is legal: a one-line if/else at the bar is 2 regions on 1 line) locals=local-var-decl-count(floor,C/C++-only,see locals_floor) ppalt=preproc-alternative-branches-in-body(#else/#elif; metrics sum ALL branches, no single build compiles them all) ev=essential-cx(McCabe: 1=fully structured, 2+=jumps block extract-method; absent on a cx row means exactly 1; floor per ev_floor — noreturn calls/macro-hidden exits unseen; not counted: &&/||, Rust ? and yield/await/defer, hence Bash carries no ev) ev_why=which-jumps-raised-it tag:count cbo=coupling lcom4=cohesion amp=change-amplification tested=1 role=hub(fan-in 8+; uses spells role call|macro|read|write|import|extends). Absent=N/A, never 0. -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1590 symbols=13896 edges=17115 shown=10 est_tokens=1962 ambiguous=6100 unresolved=3097 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=20 order=important-first -->
<r root="." est_tokens="1962" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" in="641" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" locals="0" locals_floor="1" cbo="0" amp="664" tested="1" k="0.0169">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2" in="29" out="0" cx="2" ccx="1" role="hub" loc="1" params="0" nest="1" locals="0" locals_floor="1" cbo="0" amp="52" tested="1" k="0.0071">
</s>
<s t="method" n="push_back" id="src/infra/svector.h::svector::push_back" in="459" out="3" cx="2" ccx="1" role="hub" loc="5" params="1" nest="1" locals="1" locals_floor="1" cbo="3" amp="482" tested="1" amb="2" k="0.0054" ev="2" ev_floor="1" ev_why="guard-return:1">
<c n="buf"/>
<c n="buf"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--doctor`, `--json`, `--limit`, `--index-out`

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
<!-- ripwire deps: file-to-file #include/import view, heaviest transitive cone first. files= (root) = files with at least one dependency edge (this listing's own denominator); health files= = the whole indexed corpus; health dep_files= = the dependency-CAPABLE subset of it (the ccd/acd/nccd denominator). raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). -->
<deps files="370" shown="40" capped="1" total="370" has_more="1" next_offset="40" offset="0" limit="0" root=".">
<health files="1590" dep_files="750" ccd="4378" acd="5.8" nccd="0.68" shape="horizontal"/>
<godfiles total="262" shown="12" capped="1">
<f p="src/model.h" afferent="76"/>
<f p="src/infra/Diagnostics.h" afferent="44"/>
<f p="src/serialize.h" afferent="34"/>
<f p="src/graph.h" afferent="33"/>
<f p="src/ingest.h" afferent="23"/>
<f p="src/arch.h" afferent="20"/>
<f p="src/infra/jsonesc.h" afferent="20"/>
<f p="src/quality.h" afferent="19"/>
<f p="src/gitstamp.h" afferent="18"/>
<f p="src/graphlegend.h" afferent="15"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--arch`, `--limit`

**Caveats (stated by the binary):**

- its nccd (Lakos) is a design heuristic, not independently outcome-validated.

### `--hotspots`

**Answers:** complexity x recent git churn (maintenance pain);

each row's top= is the worst function's BARE name, top_ccx= its cognitive complexity, top_l= its source line (build an --expand selector from p=/top_l=/top=, not from top= alone — it no longer carries a :line suffix)

**Try it**

_Complexity x recent git churn (maintenance pain)._

```
$ ./build/ripwire . --hotspots
<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=12mo). churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. unranked_no_complexity= is a file with commits but no function or method to score (a pure declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the join could not match), which scores zero for a reason that is not about the file. Treat it as an upper bound on quietness, not a measure of it. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<hotspots window="12mo" files="1590" ranked="440" unranked_no_churn="0" unranked_no_complexity="1150" shown="40" capped="1" total="440" has_more="1" next_offset="40" offset="0" limit="0" root="." at="5f71cb4fd+dirty">
<f p="src/main.cpp" churn="271" ccx="885" score="239835" top="dispatchMain" top_ccx="405" top_l="2653"/>
<f p="src/serialize.h" churn="100" ccx="1863" score="186300" top="packSignatures" top_ccx="220" top_l="3350"/>
<f p="src/quality.h" churn="106" ccx="1182" score="125292" top="computeDelta" top_ccx="243" top_l="5284"/>
<f p="src/mcpverbs.h" churn="118" ccx="980" score="115640" top="runBatchSub" top_ccx="112" top_l="4266"/>
<f p="src/graph.h" churn="60" ccx="1851" score="111060" top="buildGraph" top_ccx="779" top_l="962"/>
<f p="src/cli.h" churn="217" ccx="501" score="108717" top="parseArgs" top_ccx="191" top_l="4156"/>
<f p="src/mcp.h" churn="52" ccx="577" score="30004" top="dispatchMcpLine" top_ccx="517" top_l="535"/>
<f p="src/verbs_navigate.h" churn="33" ccx="599" score="19767" top="runVerify" top_ccx="130" top_l="1316"/>
<f p="src/slice.h" churn="24" ccx="785" score="18840" top="sliceClassify" top_ccx="183" top_l="529"/>
<f p="src/lexical.h" churn="31" ccx="563" score="17453" top="lexicalScoresTiered" top_ccx="366" top_l="121"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--expand`, `--since`, `--limit`

### `--clones`

**Answers:** token-normalized duplicate bodies

**Try it**

_Token-normalized duplicate bodies._

```
$ ./build/ripwire . --clones
<!-- ripwire clones: function bodies with similar normalized token streams (identifiers/literals normalized, so renamed copies match). type=2 exact/renamed (Type-1/2); type=3 gapped near-miss (an inserted/changed statement, similarity in [0.80,1.0)). Reuse don't reimplement; a fix to one likely belongs in all. groups= and type3= are the two GROUP-TYPE totals (each capped independently, so neither is the row count); total= is the true row total (groups + type3-group-count) and is ALWAYS present, paged or not; shown= is the number of group rows that follow this run. capped="1" means rows were dropped. exempt= on a group ⇒ every member is on a path the quality-delta verb's duplication kind deliberately ignores (fixture dirs / shell test-runners repeat boilerplate by convention) — a fact here, never a gate there; exempt_groups= counts them over ALL groups. idiom= on a group names the RECOGNIZED SHAPE every one of its members classifies to, from a CLOSED set of three: threshold-ladder (a chain of if-compare-return and nothing else), switch-name-table (a switch whose every arm is a label plus a literal return), builder-chain (a param-struct initializer chain). demoted="1" additionally means the quality-delta verb's duplication kind reports this group as minor rather than gating on it, which happens only when the WHOLE conjunction holds: every member the same recognized idiom, no two members sharing a single non-keyword identifier, no two members sharing an enclosing context (file plus scope), and the group under 80 normalized tokens. Five cross-domain bucketing ladders that share only the idiom are noise; two ladders over the same enum, or two in one namespace, are a copy. The idiom name is printed precisely so a human can overrule the demotion by reading the members: a demoted row is annotated, never removed. idiom_groups= and demoted_groups= count each of those over ALL groups. FLOOR on the classifier, since a silence here would read as coverage: the shape is read off the body's TOKEN stream and not a parse tree, so a macro-assembled body classifies as whatever its raw tokens spell; the table arm models case-labelled switches only; and builder-chain models the field-assignment spelling, not the fluent chained-call one. gid= on a row is its CLONE COMPONENT: the Type-3 pass reports PAIRS, so three functions that are all near-copies of each other arrive as three rows of two; rows sharing a gid are one cluster, and clone_groups= counts the clusters (union-find over the pair graph, over ALL detected rows, not just the shown ones). dup_pct=duplicated-LOC/total-LOC as a percentage, where duplicated-LOC sums, per cluster, every member's loc EXCEPT the largest member's (one instance is the code you keep, the rest is the redundancy — so a 3-clone cluster counts its lines TWICE) and total-LOC is every function/method body the detector considered; dup_loc= and total_loc= are those two operands. counts_floor="1": the Type-3 pair list is capped upstream, so a dropped pair is a cluster left unmerged — clone_groups/dup_loc/dup_pct are floors, never totals. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<clones groups="75" type3="342" exempt_groups="201" idiom_groups="14" demoted_groups="10" clone_groups="220" dup_loc="4342" total_loc="136948" dup_pct="3.2" counts_floor="1" shown="80" capped="1" total="417" has_more="1" next_offset="80" offset="0" limit="0" root=".">
<group type="2" gid="194" tokens="211" n="4" exempt="shell-runner">
<f n="batch_sub" p="test/mcpclidiffcheck.sh:63"/>
<f n="batch_sub" p="test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" gid="212" tokens="149" n="3" exempt="shell-runner">
<f n="monotonic_check" p="test/pyimportprecisecheck.sh:89"/>
<f n="monotonic_check" p="test/rustimportprecisecheck.sh:124"/>
<f n="monotonic_check" p="test/tsimportprecisecheck.sh:88"/>
</group>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--limit`

### `--readability`

**Answers:** per-function readability lens, LEAST readable first: vol= Halstead volume V (N*log2(eta)), ent= Shannon token entropy E, lines= L, posnett= sigmoid(8.87 - 0.033V + 0.40L - 1.5E) (Posnett/Hindle/Devanbu, MSR 2011).

APPROXIMATION, disclosed: ONE token-class table serves every language (keywords + punctuation = operators, identifiers + literals = operands), with no per-grammar refinement, so V is cross-language and not a per-grammar Halstead count. The formula was fitted on snippets of 20 lines or fewer, so it is a RANKING lens, not a grade: read the ORDER of the rows, not the number on any one of them. Pages with limit=N (offset=M); default 40 rows. Declarations with no body are not measured.

**Try it**

_Per-function readability, LEAST readable first (Halstead volume, token entropy, lines, Posnett) — a RANKING lens, not a grade._

```
$ ./build/ripwire . --readability --limit=8
<!-- ripwire readability: the Posnett/Hindle/Devanbu (MSR 2011) closed-form lens, one row per function or method, LEAST READABLE FIRST. p=path:line n=symbol name lines=L, the definition's physical line span toks=N, the operator+operand tokens of the whole definition (signature included) ops=N1, the operator half of toks (keywords and punctuation; the rest are identifiers and literals) vocab=eta, distinct tokens vol=Halstead volume V, N*log2(eta) ent=E, Shannon entropy of the token frequency distribution, in bits posnett=P, sigmoid(8.87 - 0.033V + 0.40L - 1.5E), the paper's published fit. ONE token-class table serves every language, so V is a cross-language APPROXIMATION, not a per-grammar count. P was fitted on snippets of 20 lines or fewer: read the ORDER, not the number, and never as a grade. The sigmoid SATURATES at the least-readable extreme (a high-volume function's argument clamps at +/-40), so several head rows can print posnett="0.000" alike; those ties (and every tie) break by vol= descending, so the ORDER stays real even where P itself has run out of visible precision. functions=functions and methods measured (a declaration with no body is not measured) shown=rows printed capped=1 when rows were dropped; raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it), which also prints total= has_more= next_offset= offset= limit= unreadable_files=indexed files this pass could not read; their functions are absent, so functions= is a FLOOR -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<readability functions="8013" shown="8" capped="1" total="8013" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<fn p="src/graph.h:962" n="buildGraph" lines="1494" toks="8023" ops="5154" vocab="453" vol="70789.9" ent="6.36" posnett="0.000"/>
<fn p="src/mcp.h:535" n="dispatchMcpLine" lines="1369" toks="6674" ops="4212" vocab="597" vol="61544.9" ent="6.37" posnett="0.000"/>
<fn p="src/main.cpp:2653" n="dispatchMain" lines="1259" toks="6032" ops="3909" vocab="531" vol="54605.1" ent="6.25" posnett="0.000"/>
<fn p="src/packtask.h:1082" n="packTaskBundleText" lines="655" toks="4900" ops="2987" vocab="439" vol="43012.6" ent="6.46" posnett="0.000"/>
<fn p="src/verbs_report.h:2707" n="runStructureText" lines="529" toks="4810" ops="2936" vocab="335" vol="40346.4" ent="6.14" posnett="0.000"/>
<fn p="src/lexical.h:121" n="lexicalScoresTiered" lines="780" toks="4816" ops="3051" vocab="324" vol="40164.7" ent="6.26" posnett="0.000"/>
<fn p="src/verbs_lint.h:1182" n="runLint" lines="777" toks="4556" ops="2851" vocab="434" vol="39917.6" ent="6.42" posnett="0.000"/>
<fn p="src/verbs_for.h:1447" n="runForLens" lines="993" toks="4441" ops="2721" vocab="410" vol="38545.6" ent="6.34" posnett="0.000"/>
</readability>
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- APPROXIMATION, disclosed: ONE token-class table serves every language (keywords + punctuation = operators, identifiers + literals = operands), with no per-grammar refinement, so V is cross-language and not a per-grammar Halstead count.
- The formula was fitted on snippets of 20 lines or fewer, so it is a RANKING lens, not a grade: read the ORDER of the rows, not the number on any one of them.
- Pages with limit=N (offset=M);

### `--nonlocal-state`

**Answers:** per function, the NON-LOCAL MUTABLE STATE it can reach, MOST WRITES FIRST: writes= reads= are the distinct cells this function OR its transitive callees write / read;

direct_writes= direct_reads= are the subsets in its own body. A cell is a file/namespace-scope variable, a function-local static, or a Python module global; a const/constexpr/consteval declaration is not a cell. Each cell child names its declaration, its direction (dir=r|w|rw) and either the use site in this body (at=) or the callee it came through (via=). Lineage: Fowler's Global Data / Mutable Data smells (2018) name the hazard and ship no metric; Marinescu's ATFD (ICSM 2004) is the closest number but is one-hop, per-class, Java, and direction-blind; QMOOD DAM and MOOD AHF/MHF count DECLARED VISIBILITY and so score a class with private fields and leaked mutable internals as perfectly encapsulated; the only published measurement of externally reachable state (Potanin/Noble/Biddle 2004) is DYNAMIC, Java-only, and its tool is unmaintained. UNSOUND BY CONSTRUCTION -- it cannot see indirect calls, pointer aliasing, macro-named cells or reflection-like dispatch, and a local SHADOWING a cell name can be charged to the cell -- so every count is a FLOOR (counts_floor="1") and the blind spots are listed in the report's own legend. COVERS C++, ObjC and Python -- the languages whose read/write USE SITES the index carries. Every other indexed language is named on the root as unanalyzed_langs= and contributes no cells and no rows: that absence is NOT a measured zero. Pages with limit=N (offset=M); default 40 rows.

**Try it**

_Per function, the non-local MUTABLE state it can reach (transitively), most writes first — unsound by construction, and the legend says where._

```
$ ./build/ripwire . --nonlocal-state --limit=8
<!-- ripwire nonlocal-state: per function, the NON-LOCAL MUTABLE STATE it can reach, reads and writes kept apart. A cell is one mutable datum declared outside any local scope: a file or namespace scope variable, a function-local static (local in name only), or a Python module global. A const, constexpr or consteval declaration is NOT a cell. An INSTANCE FIELD is not a cell either, by definition: per-object state is a different hazard, answered per member by the uses verb's Owner.field selector — so a member access (o.x, this->x) and a bare name the enclosing method's own class declares as a field are never charged to a same-named global here. Rows are ordered MOST WRITES FIRST, then most reads. p=path:line n=symbol name writes=distinct cells this function or its transitive callees WRITE reads=distinct cells this function or its transitive callees READ direct_writes=the writes= subset written in this function's OWN body direct_reads=the reads= subset read in this function's OWN body cells_total=distinct cells reached (a cell both read and written counts once) cells_shown=cell children printed cells_capped=1 when a row's children were truncated. Each cell child: n=cell name p=the cell's declaration path:line dir=r for read, w for write, rw for both, taken over this function's OWN BODY AND its callee closure together at=one use site in this function's own body (direct cells; there may be more) at_dir=what the OWN-BODY sites do, which can be NARROWER than dir=: at_dir=r with dir=rw means this body only reads the cell and a callee is what writes it via=the nearest callee whose own body touches the cell (transitive cells; exactly one of at= or via= is present). cells=cells found in the corpus functions=functions reaching at least one cell shown=rows printed capped=1 when rows were dropped; raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it), which also prints total= has_more= next_offset= offset= limit= unanalyzed_langs=indexed languages this lens does NOT analyse, so their files contribute NO cells and NO rows; the analysis covers C++, ObjC and Python, the languages whose read and write use sites the index carries. Their absence is NOT a measurement of zero. unanalyzed_files=indexed files in those languages undecided_decls=declarations whose specifiers ran past the text window, so mutability could not be decided; dropped, never guessed cells_capped=1 on the ROOT when the cell universe hit its ceiling decls_capped=1 when a declaration query hit its match budget. counts_floor=1 because this analysis is UNSOUND BY CONSTRUCTION and every count here is a FLOOR (graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge: calls split over several defs / calls whose in-repo defs were all language-filtered, the map header's ambiguous=/unresolved=). It cannot see: an indirect call (a virtual, an unbound or reassigned function pointer or callback, or a macro invocation whose #define is not indexed), so the callee closure stops early; a write through a pointer or reference that ALIASES a cell without naming it; a cell named only inside a macro; reflection-like or duck-typed dispatch. It can also OVER-count in one way: a local that SHADOWS a cell's name is charged to the cell unless ingest recorded a type binding for that local, which it does for typed and constructed locals only. Read a zero as none found, never as none exists, and read a row as a place to look rather than a verdict. -->
<nonlocal_state cells="580" functions="538" shown="8" capped="1" total="538" has_more="1" next_offset="8" offset="0" limit="8" graph_ambiguous="6100" graph_unresolved="3097" counts_floor="1" unanalyzed_langs="c,go,rust,javascript,typescript,java,csharp,swift,ruby,bash" unanalyzed_files="729" root=". … [line truncated: 2 more bytes on this line]
<fn p="bench/bench_svector_wave.cpp:346" n="main" writes="8" reads="14" direct_writes="0" direct_reads="4" cells_total="14" cells_shown="12" cells_capped="1">
<cell n="kNames" p="bench/bench_svector_wave.cpp:98" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="kPush" p="bench/bench_svector_wave.cpp:99" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="kReads" p="bench/bench_svector_wave.cpp:100" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="kSamples" p="bench/bench_svector_wave.cpp:101" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="g_api" p="src/infra/profilePmc.h:137" dir="rw" via="ensure_thread_counting"/>
<cell n="g_keyOf" p="bench/bench_svector_wave.cpp:145" dir="rw" via="regenerate"/>
<cell n="g_perf" p="src/infra/profilePmc.h:284" dir="rw" via="ensure_thread_counting"/>
<cell n="g_readOf" p="bench/bench_svector_wave.cpp:146" dir="rw" via="regenerate"/>
<cell n="g_arm" p="bench/bench_svector_wave.cpp:65" dir="r" via="runArm"/>
<cell n="g_bytes" p="bench/bench_svector_wave.cpp:67" dir="r" via="runArm"/>
<cell n="g_count" p="bench/bench_svector_wave.cpp:66" dir="r" via="runArm"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- a const/constexpr/consteval declaration is not a cell.
- UNSOUND BY CONSTRUCTION -- it cannot see indirect calls, pointer aliasing, macro-named cells or reflection-like dispatch, and a local SHADOWING a cell name can be charged to the cell -- so every count is a FLOOR (counts_floor="1") and the blind spots are listed in the report's own legend.
- Every other indexed language is named on the root as unanalyzed_langs= and contributes no cells and no rows: that absence is NOT a measured zero.

### `--ensemble`

**Answers:** the FAMILY JOIN: per function, which of FOUR orthogonal evidence families fire, ranked by the COUNT of distinct families

**Try it**

_The family join: per function, which of four orthogonal evidence families fire, ranked by how many agree._

```
$ ./build/ripwire . --ensemble --limit=8
<!-- ripwire ensemble: the FAMILY JOIN over four orthogonal evidence families, ranked by the COUNT OF DISTINCT FAMILIES that fire and by nothing else. There is NO composite score here, by contract: averaging correlated metrics re-weights one signal and calls it three, and a single quotable number is wrong the moment it is quoted. fam= is ordinal and every row carries its own evidence. The four families are structural (the shape of the code), lexical (the identifier text: the naming rules), confusion (the syntactic construct: the atom rules) and historical (git change frequency, measured PER FILE: every symbol in a file carries that file's churn= and hrank= verbatim, so this family is file evidence inherited by the row, not the row's own history). families=how many families exist eligible=functions and methods with a body, the denominator ranked=eligible symbols where at least one family fired no_family=eligible symbols where none did (ranked= + no_family= = eligible= exactly, on every run). s=one joined symbol: p=path:line n=symbol name fam=how many DISTINCT families fired of=how many families could be EVALUATED at all fired=their names unavail=families that could not be measured here. e=the evidence inside one fired family: f=family name why=the measurements that crossed, space separated; a lexical or confusion rule that fired N times reads rule*N. f=the per-file rollup: p=path top=the file's most corroborated symbol top_l=its line top_fam=its family count union_fam=how many distinct families fire ANYWHERE in the file union=their names syms=symbols in the file with at least one family. top_fam= is the STRONGER claim (several families agreeing on ONE symbol); union_fam= is weaker (different families on different symbols) and the rollup is ranked by the stronger one. THRESHOLDS, all stated here. Four structural signals are ABSOLUTE bars, reused verbatim from the quality-delta bars: bar_ccx=cognitive complexity bar_loc=physical lines bar_nest=max nesting depth bar_params=parameter count; a row shows only the ones that crossed, with the value that crossed. Two signals are RANKINGS with no defensible absolute cut, so each fires for the worst decile of its own ranking, at least one row and at most 40 (each verb's own default window): rrank=the symbol's rank in the readability lens (0 is least readable) rcut=how many ranks that decile covers rmeasured=functions the readability lens measured; hrank=the file's rank by git churn (0 is most changed) churn=its in-window commit count hcut=how many ranks that decile covers hranked=files with any in-window commit window=the churn window. An ordinal cut is RELATIVE: some symbol is always in the worst decile of its own corpus, so rrank= and hrank= mean 'worst in THIS corpus', never 'bad in absolute terms'. The historical family ranks by churn ALONE, not by the hotspots score (churn x complexity), because half of that product is the structural family and two families that cannot disagree are one family counted twice. unavailable=families that could not be evaluated at all, with unavailable_why= saying why, one reason per unavailable family (§L10: both absent, never ="", when every family was measured — house convention, absent means none). UNAVAILABLE is never the same as silent: an ABSENT unavailable= means every family was measured, and a family listed there was NOT measured, so its absence from fired= is not evidence of health. An EMPTY ranking counts as not measured, so hranked=0 makes the historical family unavailable: a corpus scanned from outside the repository that tracks it mines zero churn for every file, and that silence is not a fact about the code. So does an empty LANGUAGE COVERAGE. The confusion family is the atom pack, which by design runs only on C/C++/ObjC/CUDA paths, so on a corpus with no eligible function in one it was never applicable rather than quiet: cfiles=indexed files it can read cscope=eligible symbols inside them, and cscope=0 makes it unavailable. The lexical family is the naming pack, which has no opinion about a data or doc language: lscope=eligible symbols in a language it reads, and lscope=0 makes it unavailable. The structural family has no such precondition - its bars and its readability rank are computed for every language. of= on each row is 4 minus the unavailable families, so a row NEVER counts a family that could not have been evaluated for it, and fam= cannot reach 4 on a corpus where one family was never applicable. unreadable_files=indexed files the readability lens could not read, so rrank= is a floor over what it saw. findings_capped=1 when a lexical or confusion rule spent its per-rule budget, with floor_rules= naming them: those families are then FLOORS and the root carries counts_floor=1. A naming or atom finding that lies outside every function body is not joined to any symbol and is not counted here. shown_syms=symbol rows printed syms_capped=1 when symbol rows were dropped shown_files=file rows printed files_capped=1 when file rows were dropped; the symbol listing is the one limit=N and offset=M window, which also prints total= has_more= next_offset= offset= limit= -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<ensemble families="4" eligible="8013" ranked="3411" no_family="4602" bar_ccx="15" bar_loc="60" bar_nest="4" bar_params="5" rcut="40" rmeasured="8013" hcut="40" hranked="1590" window="12mo" cfiles="500" cscope="4167" lscope="8013" shown_syms="8" syms_capped="1" shown_files="20" files_capped="1" tota … [line truncated: 89 more bytes on this line]
<s p="src/serialize.h:5878" n="packDeps" fam="4" of="4" fired="structural,lexical,confusion,historical">
<e f="structural" why="ccx=110 loc=249 nest=5 params=13 humps=4 deep=14 ev=5 rrank=21"/>
<e f="lexical" why="naming-confusable"/>
<e f="confusion" why="atom-nested-ternary*2"/>
<e f="historical" why="hrank=9 churn=100"/>
</s>
<s p="src/crossref.h:1773" n="evalStray" fam="3" of="4" fired="structural,confusion,historical">
<e f="structural" why="ccx=23 loc=86 ev=9"/>
<e f="confusion" why="atom-assign-as-value"/>
<e f="historical" why="hrank=29 churn=24"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

### `--quality-panel[=PRESET]`

**Answers:** THE SINGLE COMMAND: the whole quality panel in ONE ranked report.

Per function, which of SIX evidence families fire -- structural (shape), lexical (identifier text), confusion (syntactic construct), historical (git churn), colocation (what you must read from outside this file), state (this function's OWN BODY touching non-local mutable state) -- ranked by the COUNT of distinct families, NEVER by a weighted composite, each row carrying its own evidence. PRESET selects and cuts, never weights: strict (the four families measured steady enough to gate on, 2 must agree) | default (all six, 2; the bare form) | lenient (all six, 1 -- a reading order, not a verdict). historical and colocation are out of strict: each is a fixed-size worst-40 cut over a ranking whose population moves, so both re-shuffle on code that did not change (docs/EVALS.md section 9.9). A family that could not be measured here is UNAVAILABLE, never 'did not fire', and of= drops with it. A lens: exit 0. Pages limit=N (offset=M). WHY NO COMPOSITE, in full (the emitted legend is deliberately terse and points here): averaging correlated metrics re-weights one signal and calls it six, and a single quotable number is wrong the moment it is quoted -- fam= is ORDINAL, and every row carries its own evidence so a reader can see WHY without a second command. The families are partitioned by KIND of evidence so that corroboration means the lenses failed DIFFERENTLY, not that one weakness echoed six times: the first four are the ensemble join, called through its own entry point and unchanged; colocation and state passed the same orthogonality test on the same corpora before being enabled. Every threshold is REUSED from the lens it came from, none is new: four absolute structural bars (cognitive complexity, lines, nesting, params), and three rankings with no defensible absolute cut, each firing for the worst decile of its OWN ranking (at least one row, at most that lens's default window of 40) -- an ordinal cut is RELATIVE, 'worst in THIS corpus', never 'bad in absolute terms'. The state family fires on the presence of a direct access site and deliberately uses the OWN-BODY half of the lens, not the callee closure: the panel's unit is one function's own comprehensibility, and the closure is a fact about its callees. UNAVAILABLE is never silent: an empty unavailable= means every family was measured, an empty ranking or empty language coverage counts as NOT measured, and the coverage denominators behind each verdict are published so it can be checked instead of trusted. The join=deep+untested annotation puts two facts already in the report side by side (sustained depth, no reaching test) because that pair is where a refactor is most wanted and least safe; counting it would be one family wearing a second hat.

**Try it**

_THE single wide-angle quality read: six families in one pass, an eligible/ranked shortlist rather than a firehose._

```
$ ./build/ripwire . --quality-panel
<!-- ripwire quality-panel: THE SINGLE COMMAND, the whole panel of software-quality checks in ONE report, ranked ONLY by the COUNT OF DISTINCT EVIDENCE FAMILIES that fire; NO composite score, by contract. Rationale + worked reading: docs/COMMANDS.md quality-panel; every threshold is reused from its source lens. SIX FAMILIES, partitioned by KIND of evidence: structural (shape: complexity, size, nesting, params, readability rank) lexical (identifier text: naming rules) confusion (syntax: the atom rules) historical (git change frequency, measured PER FILE: every symbol carries its file's churn= and hrank= verbatim, file evidence inherited by the row, not the row's own history) colocation (how much you must READ outside this file) state (this function's OWN BODY touching non-local MUTABLE state). preset=the preset that produced this enabled=the families it COUNTS enabled_n=how many cut=distinct enabled families that must agree for a row families=how many exist. Presets SELECT and CUT, never weight: strict=the five families measured stable enough to stand behind a gate, cut 2 (historical is deliberately absent: a moving 12-month window re-shuffles on unchanged code) default=all six, cut 2 lenient=all six, cut 1. eligible=functions/methods with a body, the denominator ranked=rows that met the cut below_cut=fired at least one enabled family but fewer than the cut no_family=no enabled family fired (ranked= + below_cut= + no_family= = eligible=, always). s=one symbol: p=path:line n=name fam=distinct ENABLED families that fired of=enabled families EVALUABLE for it fired=their names uncounted=fired but not enabled here unavail=not measurable here. e=evidence in one fired family: f=family counted=1 when this preset counts it why=the measurements that crossed (a rule that fired N times reads rule*N). Absolute bars: bar_ccx=cognitive complexity bar_loc=physical lines bar_nest=max nesting depth bar_params=param count; a row shows only the ones that crossed. Rankings fire for the worst decile of their OWN corpus (RELATIVE: 'worst in THIS corpus', never 'bad in absolute terms'): rrank=readability rank (0 least readable) rcut=decile width rmeasured=functions measured; hrank=file churn rank (0 most changed) churn=in-window commit count hcut=decile width hranked=files with any in-window commit window=the churn window; crank=local-reasoning rank (0 reads most from outside its file) ccut=decile width cranked=functions resolving any outside definition. state has no threshold (fires on a direct access site): writes= reads= distinct cells the own body writes/reads. HONESTY: unavailable=families not evaluated at all unavailable_why=one reason each; a family listed there was NOT measured, so its absence from fired= is not evidence of health. An empty ranking or language coverage counts as not measured (hranked=0 voids historical, cranked=0 colocation); published denominators: cfiles=files the atom rules read cscope=eligible symbols in them lscope=symbols the naming rules read sfiles=files the state lens reads sscope=symbols in them cells=non-local mutable cells found. of= is enabled_n= minus the unavailable (a row never counts a family it could not evaluate); cut_reachable=0 when the cut exceeds of=, a fact about the corpus, never a clean bill of health. unreadable_files=files readability could not read (rrank= a floor); findings_capped=1 when a rule spent its per-rule budget, floor_rules=naming them (those families are FLOORS and the root carries counts_floor=1); state_floor=1 when the state lens saturated its budget (a FLOOR too). join=deep+untested is an annotation, NOT a seventh family (changes nothing: not fam=, not of=, not the order): deep= structural evidence (a body that SUSTAINS depth at bar_nest) that no indexed test reaches. tested_scope=symbols an indexed test reaches, the join's honest denominator; at tested_scope=0 the annotation is emitted on NO row. deep_untested=rows carrying it across the WHOLE set (unchanged by limit=). shown=symbol rows printed capped=1 when rows were dropped; the one limit=N offset=M window also prints total= has_more= next_offset= -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<quality_panel preset="default" families="6" enabled="structural,lexical,confusion,historical,colocation,state" enabled_n="6" cut="2" cut_reachable="1" eligible="8013" ranked="471" below_cut="3165" no_family="4377" bar_ccx="15" bar_loc="60" bar_nest="4" bar_params="5" rcut="40" rmeasured="8013" hcut … [line truncated: 294 more bytes on this line]
<s p="src/graph.h:962" n="buildGraph" fam="4" of="6" fired="structural,confusion,historical,colocation">
<e f="structural" counted="1" why="ccx=779 loc=1494 nest=8 humps=33 deep=305 ev=100 rrank=0"/>
<e f="confusion" counted="1" why="atom-embedded-crement*4"/>
<e f="historical" counted="1" why="hrank=10 churn=60"/>
<e f="colocation" counted="1" why="crank=29"/>
</s>
<s p="src/main.cpp:1098" n="runDefaultMap" fam="4" of="6" fired="structural,confusion,historical,colocation" join="deep+untested">
<e f="structural" counted="1" why="ccx=198 loc=816 nest=4 humps=2 deep=8 ev=14 rrank=8"/>
<e f="confusion" counted="1" why="atom-nested-ternary"/>
<e f="historical" counted="1" why="hrank=3 churn=271"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- PRESET selects and cuts, never weights: strict (the four families measured steady enough to gate on, 2 must agree) | default (all six, 2;
- the bare form) | lenient (all six, 1 -- a reading order, not a verdict).
- A family that could not be measured here is UNAVAILABLE, never 'did not fire', and of= drops with it.

### `--context-ratio`

**Answers:** the LOCAL-REASONING lens: to understand this symbol, how much must you know that is NOT in front of you? Per symbol (and rolled up per file) the distinct in-corpus definitions and files its reference sites resolve to, and the share of them defined OUTSIDE its own file — as an edge count (ent_ratio=) and, weighted by the tokens a reader must actually read, as read_ratio=.

ATTRIBUTION: the fraction itself is published — it is Beck and Diehl's per-class congruence (FSE 2011) flipped, with Martin's instability Ce/(Ca+Ce) as its crude ancestor. What is refined here is the READER WEIGHTING and the use of EVERY reference role (call, read, write, import, base class, member type), not calls alone. Resolution is NAME-BASED and language-gated, the same heuristic level the uses verb works at; a name with several definitions contributes each of them up to defs_per_name_cap= and amb= counts it. Names with no in-corpus definition land in ext=, which locals and parameters DOMINATE, so ext= is not a dependency count and is excluded from both ratios. ents=/files= are FLOORS. Pages with limit=N (offset=M); default 40 symbol rows and 40 file rows. An ORDERING, never a grade and never a threshold.

**Try it**

_The local-reasoning lens: to understand this symbol, how much must you know that is NOT in front of you (ent_ratio= edge share, read_ratio= token-weighted)._

```
$ ./build/ripwire . --context-ratio --limit=8
<!-- ripwire context-ratio: the LOCAL-REASONING lens — for one symbol (and the same numbers rolled up per file), how much of what you must resolve to understand it lives OUTSIDE its own file. ATTRIBUTION, because the fraction itself is published: the share of a unit's coupling that stays inside its own boundary is Beck and Diehl's per-class congruence (FSE 2011) and Martin's instability Ce/(Ca+Ce) is its crude ancestor. This verb is a REFINEMENT of that measure, not a new one. Two things are refined. First, the ratio is also taken over what a reader must READ (read_ratio=, weighted by the estimated tokens of the definitions to open) and not only over edge counts (ent_ratio=) — both are printed side by side so the weighting can be seen doing work. Second, the reference set is EVERY use site (call, value read, write, import, base class, member type), not calls alone, so a type whose whole outside context is a base class and a field is measured rather than missed. s=one measured symbol: p=path:line n=symbol name t=symbol kind. f=the same columns rolled up per file, which is a UNION over every reference site in the file — including the file-scope ones like includes and imports that belong to no symbol — and therefore NOT the sum of that file's symbol rows. sites=reference sites scanned for this unit, in every role ents=distinct in-corpus definitions those sites resolve to ents_out=how many of them are defined outside this unit's own file ent_ratio=ents_out divided by ents, the edge-count form files=distinct files holding those definitions files_out=how many of them are not this unit's own file rtok=estimated tokens of every entity definition, the whole span at 3.80 bytes per token, which is what a reader must actually read rtok_out=the outside-the-file part of rtok read_ratio=rtok_out divided by rtok, the READER-WEIGHTED form and the one this verb exists for. Both ratios print 0.000 when there is nothing to resolve (ents=0), which is not the same claim as a self-contained unit — read ents= first. ext=distinct referenced names with NO in-corpus definition. Local variables and parameters produce read and write sites, so they DOMINATE ext= on real code: it is not a count of external dependencies and it is excluded from both ratios. amb_names=distinct referenced names that resolved to more than one definition (a per-NAME tally; the map row's amb= is a per-CALL count of a different resolver), each of which is counted as an entity — resolution is NAME-BASED and language-gated, the same heuristic level the uses verb works at, never the call graph's narrowed resolution, because four of the five reference roles carry no resolution at all. defs_per_name_cap=the most definitions ONE name may contribute (the first that many in symbol id order); a corpus-ubiquitous name would otherwise swamp every row it appears in. defs_capped="1" ⇒ some name HAD more than that and its extra definitions were not counted, so the root also carries counts_floor="1" (ents=/rtok= are floors); absent ⇒ every name's definitions were all counted. body_bytes_per_token=the rate rtok= is converted at. ents= and files= are FLOORS: a name-based static scan cannot see dynamic dispatch, reflection, or a macro invocation whose #define is not indexed, so a zero means none FOUND, never none exists. units=symbols measured file_units=files measured. Rows come out most-outside-reading-first (rtok_out descending, then ents_out, then rtok, then id) — an ORDERING, never a grade, and never a threshold. shown_syms=symbol rows printed syms_capped=1 when symbol rows were dropped shown_files=file rows printed files_capped=1 when file rows were dropped; the symbol listing is the one limit=N and offset=M window, which also prints total= has_more= next_offset= offset= limit= -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<contextratio units="11391" file_units="1292" defs_per_name_cap="8" body_bytes_per_token="3.80" shown_syms="8" syms_capped="1" shown_files="40" files_capped="1" total="11391" has_more="1" next_offset="8" offset="0" limit="8" defs_capped="1" counts_floor="1" root=".">
<s p="src/main.cpp:2653" n="dispatchMain" t="fn" sites="956" ents="151" ents_out="136" ent_ratio="0.901" files="48" files_out="47" rtok="205135" rtok_out="180211" read_ratio="0.878" ext="129" amb_names="18"/>
<s p="src/main.cpp:1098" n="runDefaultMap" t="fn" sites="690" ents="74" ents_out="68" ent_ratio="0.919" files="23" files_out="22" rtok="61563" rtok_out="59006" read_ratio="0.958" ext="102" amb_names="9"/>
<s p="src/mcp.h:535" n="dispatchMcpLine" t="fn" sites="1047" ents="144" ents_out="128" ent_ratio="0.889" files="22" files_out="21" rtok="61075" rtok_out="58586" read_ratio="0.959" ext="135" amb_names="13"/>
<s p="src/mcpverbs.h:3019" n="computeQualityDelta" t="fn" sites="62" ents="30" ents_out="27" ent_ratio="0.900" files="13" files_out="12" rtok="40509" rtok_out="40301" read_ratio="0.995" ext="10" amb_names="6"/>
<s p="src/mcpverbs.h:1463" n="forTaskText" t="fn" sites="358" ents="84" ents_out="81" ent_ratio="0.964" files="22" files_out="21" rtok="39163" rtok_out="38848" read_ratio="0.992" ext="67" amb_names="12"/>
<s p="src/mcpverbs.h:3252" n="packTaskText" t="fn" sites="116" ents="31" ents_out="31" ent_ratio="1.000" files="17" files_out="17" rtok="36647" rtok_out="36647" read_ratio="1.000" ext="23" amb_names="4"/>
... [22 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- Resolution is NAME-BASED and language-gated, the same heuristic level the uses verb works at;
- Names with no in-corpus definition land in ext=, which locals and parameters DOMINATE, so ext= is not a dependency count and is excluded from both ratios.
- Pages with limit=N (offset=M);

### `--naming-calibration`

**Answers:** score the naming-* lint rules against this repo's OWN rename history: one git log pass mines old->new identifier substitutions, joins each to the symbol it became at HEAD, and scores BOTH spellings with the same predicates --lint runs.

old=fires on the abandoned spelling, new=fires on the chosen one, proxy=old/(old+new), where 0.50 is exactly chance. A NOISY PROXY, stated as one -- rebrands, moves and API changes all look like renames -- so read pairs= (the sample size) first; the group rules report scope=group-rule, not a fake 0/0. Exit 0 always: the per-rule floor lives in test/namingcalibrationcheck.sh

**Try it**

_Score the naming-* rules against this repo's own rename history: proxy=old/(old+new) per rule, 0.50 = chance; read pairs= (sample size) first._

```
$ ./build/ripwire . --naming-calibration
<!-- ripwire naming-calibration: each naming lint rule scored against this repo's OWN rename history. A NOISY PROXY, and that is the headline, not a footnote: developers rename for reasons that have nothing to do with name quality (rebrands, moves, API changes, type changes, reverts), so a pair labelled old to new is only WEAK evidence that the old spelling was the worse one. Read pairs= first; a small sample means nothing whatever the proxy says. pairs=labelled rename pairs that survived the join, the SAMPLE SIZE for every number below candidates=raw substitutions mined from the patch stream, before the join commits=commits walked hunks=diff hunks with content on both sides wide_hunks=hunks dropped for exceeding the per-side pairing cap drop_old_alive=candidates dropped because the old spelling is still an indexed name (so it was not renamed away) drop_new_absent=candidates dropped because the new spelling is no eligible indexed symbol at HEAD drop_ambiguous=candidates dropped because a name appeared on both sides of several candidates (a split, rework or revert) drop_old_skipped=candidates dropped because the lens would skip the old spelling, so no rule could ever have fired on it truncated=1 when a walk bound was hit, which makes candidates= a FLOOR probed=0 when there is no history to mine; r= says why the root's own at= is the git commit these numbers were computed at (a trailing +dirty means the working tree differed from that commit); a p row's at= below is unrelated — a path:line location, not a commit r rows: n=rule name old=pairs where the rule fired on the ABANDONED spelling new=pairs where it fired on the CHOSEN spelling fired=old+new proxy=old/fired, the crude precision proxy, absent when fired=0 (0.50 is exactly chance: a rule that fires equally on both spellings has no signal) scope=group-rule marks a rule that fires on a RELATIONSHIP between co-visible names, which one pair cannot carry evidence about; it is reported unscored rather than as a meaningless 0/0. p rows: one labelled pair. o=old spelling n=new spelling sup=distinct hunks that showed the substitution at=path:line of the symbol the pair joined to old_fires=rules that fired on the old spelling new_fires=rules that fired on the new spelling (both absent when empty) -->
<naming-calibration probed="1" pairs="37" candidates="647" commits="1413" hunks="26354" wide_hunks="340" drop_old_alive="106" drop_new_absent="495" drop_ambiguous="9" drop_old_skipped="0" at="5f71cb4fd+dirty">
<r n="naming-short" old="1" new="1" fired="2" proxy="0.500"/>
<r n="naming-wordy" old="0" new="0" fired="0"/>
<r n="naming-series" scope="group-rule"/>
<r n="naming-underscore" old="0" new="0" fired="0"/>
<r n="naming-case" old="0" new="0" fired="0"/>
<r n="naming-predicate" old="0" new="0" fired="0"/>
<r n="naming-setter" old="0" new="0" fired="0"/>
<r n="naming-confusable" scope="group-rule"/>
<p o="ARM_CTXPACK" n="ARM_RIPWIRE" sup="3" at="./bench/agentloop/analyze.py:31"/>
<p o="CTXPACK" n="RIPWIRE" sup="12" at="./bench/headtohead/r3-headroom-2026-08-03/harness.py:42"/>
<p o="CTXPACK_BASH_RE" n="RIPWIRE_BASH_RE" sup="1" at="./bench/mine_traces.py:47"/>
<p o="CTXPACK_REPO" n="RIPWIRE_REPO" sup="4" at="./bench/headtohead/r2-2026-08-03/worker.py:20"/>
... [17 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- A NOISY PROXY, stated as one -- rebrands, moves and API changes all look like renames -- so read pairs= (the sample size) first;
- the group rules report scope=group-rule, not a fake 0/0.
- Exit 0 always: the per-rule floor lives in test/namingcalibrationcheck.sh

### `--naming-consistency`

**Answers:** TIER A convention normalization (section 9.2): the corpus's OWN case-convention vote per (language, kind) group among multi-token eligible names -- a single-token name, or one split only on digit boundaries, carries no case signal and is silently excluded.

A group DECIDES only when its leading style (camel/pascal/snake/screaming) clears a 20-name sample floor AND a 90% agreement floor; short of either it reports style=UNAVAILABLE with why= naming which bar it missed, never a guessed winner. Every off-convention name in a DECIDED group (including mixed -- naming-case's own finding, a separator AND a transition in one name, which never wins a vote) gets propose=: its OWN subtokens mechanically recombined into the dominant style -- no dictionary, no synonym judgment, which is what keeps this derivable from the corpus rather than invented. propose= is a SUGGESTION, never a safe-to-blind-apply rename -- an actual rename needs --uses to prove the complete reference set first. Exit 0 always: a lens, not a gate. Pages limit=N (offset=M); default 40 rows

**Try it**

_The corpus's OWN case-convention vote per (language, kind) group; off-convention names get a mechanical propose= (a suggestion, never a blind rename)._

```
$ ./build/ripwire . --naming-consistency --limit=8
<!-- ripwire naming-consistency: TIER A convention normalization (NOTES.md section 9.2): the corpus's OWN case-convention choice, voted per (language, kind) group among MULTI-TOKEN eligible names (a single-token name, or one split only on digit boundaries, carries no case signal and is silently excluded from both voting and flagging). A group DECIDES only when its leading style clears both a sample floor and an agreement floor; short of either it reports style=UNAVAILABLE with why= naming which bar it missed, never a guessed winner. Every off-convention name in a DECIDED group gets propose=: its OWN subtokens mechanically recombined into the dominant style: no dictionary, no synonym judgment, so this is safe to suggest for that reason alone. propose= is a SUGGESTION, never a safe-to-blind-apply rename: an actual rename needs the uses verb to prove the complete reference set first. A mixed name (naming-case's own finding: a snake separator AND a camel transition inside ONE identifier) never wins a vote and is always flagged when its group has a decided convention. Exit 0 always: a lens, not a gate. groups=(language,kind) pairs with at least one styled name candidates=styled names scanned decided=groups that cleared both floors flagged=off-convention names in decided groups g rows: lang= kind=fn|var style=the group's dominant convention, or UNAVAILABLE agree=leading-style votes total=all voting-style votes in this group why=insufficient-sample|no-clear-convention when style is UNAVAILABLE (absent otherwise) f rows: p=path:line n=name lang= kind=fn|var style=this name's own convention (mixed for the internally inconsistent case) propose=the mechanically recombined form in the group's dominant style. Pages limit=N (offset=M); default 40 rows, shown= capped= disclose the cut, and a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<naming-consistency groups="26" candidates="6086" decided="6" flagged="275" shown="8" capped="1" total="275" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<g lang="cpp" kind="fn" style="camel" agree="3077" total="3273"/>
<g lang="cpp" kind="var" style="camel" agree="733" total="742"/>
<g lang="py" kind="fn" style="snake" agree="580" total="595"/>
<g lang="py" kind="var" style="UNAVAILABLE" why="no-clear-convention" total="333"/>
<g lang="ts" kind="fn" style="camel" agree="37" total="38"/>
<g lang="ts" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="5"/>
<g lang="go" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="11"/>
<g lang="go" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="2"/>
<g lang="rs" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="49"/>
<g lang="rs" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="4"/>
<g lang="swift" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="19"/>
... [24 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- A group DECIDES only when its leading style (camel/pascal/snake/screaming) clears a 20-name sample floor AND a 90% agreement floor;
- short of either it reports style=UNAVAILABLE with why= naming which bar it missed, never a guessed winner.
- propose= is a SUGGESTION, never a safe-to-blind-apply rename -- an actual rename needs --uses to prove the complete reference set first.

### `--naming-locals`

**Answers:** OPT-IN --lint MODIFIER (requires --lint;

refused alone), OFF by default: local-variable-indexing plan Phase 2 (docs/LOCALS_INDEXING.md). Runs the naming-short/naming-wordy/naming-underscore/naming-case predicates (same tags, same rule bodies as the existing Symbol-scoped checks) against LOCAL variable names too, C/C++ only, but ONLY inside a function that already clears an EXISTING size/complexity gate (loc>80 OR nest>4 OR ccx>=15 -- the shipped large-function/deep-nesting thresholds) AND has locals>=8 (measured floor: median locals=9 among this repo's own 377 gated functions) -- never a whole-corpus local-name sweep. naming-short additionally requires the local's own declDepth>=2 (nested, not the function's own outermost block). Deliberately breaks the lens's stated invariant that an un-indexed local can never be flagged -- read the WITHDRAWN note atop src/naminglens.h before relying on this. NOT default-enabled inside a plain --lint run and not a candidate for it yet: the plan's own hard blocker (a hand-curated fixture corpus AND a manual real-corpus audit for idiomatic-short-name skew -- i/j/k/buf/tmp/ err) has not run. Exit 0 always; findings ride the same naming-* tallies/floors as --lint

**Try it**

_The opt-in --lint modifier: naming predicates over LOCAL variable names too, C/C++ only, only inside functions already past a size/complexity gate._

```
$ ./build/ripwire . --lint --naming-locals
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries count_capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one PRINTED rule row is a floor (never inherited from a rule lint-select/lint-ignore dropped), and the root then also carries counts_floor="1" and capped="1": findings= and total= are floors, rows exist that no page holds. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed them, absent an explicit limit=) — a different fact from the per-rule count_capped="1" above, which is a MATCH-BUDGET floor on one rule's own count=; findings= is the true total unless findings_capped="1" floors it. A rule row's applicable="0" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this corpus at all — its count="0" is structural inertness, never a measurement; the root's inert_rules=N tallies how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a family (e.g. cache-); the root then carries selected="K of N" plus the raw select=/ignore= you passed. naming_locals="1" on the root ⇒ the opt-in naming-locals modifier was on (the naming-* rules also read local variables inside already-flagged functions); absent ⇒ off, and the naming-* counts cover declarations only. Each rule row's own shown_rows=/rows_capped= is how many of THAT rule's rows fall inside the printed <f> window (the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the cut carries shown_rows="0" rows_capped="1" while its count= stays the true total — never confuse a capped-away rule with one that measured zero); this is a DIFFERENT fact from the row's own count_capped="1" above (that rule's own raw-capture stream hit its per-rule match budget) — the two can disagree on the same row. A lint-rules row's compiled="0" ⇒ that rule's tree-sitter QUERY failed to compile for every linked grammar (a malformed or misspelled pattern) — its count="0" never ran at all, a different claim from applicable="0" above (a well-formed query whose declared language just is not in this corpus) and from an ordinary count="0" (a well-formed query that ran and found nothing); absent ⇒ the query compiled. -->
<lint findings="5045" shown="639" capped="1" total="5045" has_more="1" next_offset="639" offset="0" limit="0" counts_floor="1" findings_capped="1" naming_locals="1" root=".">
<rule name="c-style-cast" count="307" shown_rows="96" rows_capped="1"/>
<rule name="goto" count="3" shown_rows="1" rows_capped="1"/>
<rule name="do-while" count="5" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="12" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="507" shown_rows="222" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="248" shown_rows="28" rows_capped="1"/>
... [17 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- refused alone), OFF by default: local-variable-indexing plan Phase 2 (docs/LOCALS_INDEXING.md).
- Deliberately breaks the lens's stated invariant that an un-indexed local can never be flagged -- read the WITHDRAWN note atop src/naminglens.h before relying on this.
- NOT default-enabled inside a plain --lint run and not a candidate for it yet: the plan's own hard blocker (a hand-curated fixture corpus AND a manual real-corpus audit for idiomatic-short-name skew -- i/j/k/buf/tmp/ err) has not run.

### `--comment-coherence`

**Answers:** per function/method WITH A DOC COMMENT, two published content measures, MOST NAME-RESTATING FIRST: c_coeff (Steidl/Hummel/Juergens, ICPC 2013) is the fraction of the comment's words within Levenshtein distance <2 of a word in the symbol's own (split) name — HIGH c_coeff IS BAD, it means the comment mostly repeats the name and adds no information (the opposite of the naive 'high coherence sounds good' reading).

cic (Scalabrino, ICPC 2016 / JSEP 2018) is the Jaccard overlap of two preprocessed term sets: the comment's vocabulary vs every identifier the definition's own span uses (operators/keywords stripped, camelCase/snake_case split, English stopwords dropped, deduplicated). The two measure different things and are expected to disagree — both are reported, never collapsed to one number. UNAVAILABLE (not scored, never a zero) where no doc comment exists, counted in no_comment= on the root. Complements --doc-drift (which checks whether a markdown CLAIM is stale) with comment CONTENT, over a disjoint input — neither verb duplicates the other. Pages with limit=N (offset=M); default 40 rows.

**Try it**

_Functions WITH a doc comment, most name-restating first: c_coeff (high = the comment repeats the name) and cic (Jaccard of comment vs identifier vocabulary), both reported, never collapsed._

```
$ ./build/ripwire . --comment-coherence --limit=8
<!-- ripwire comment-coherence: two content measures per documented function/method, MOST NAME-RESTATING FIRST. p=path:line n=symbol name c_coeff=Steidl/Hummel/Juergens coherence coefficient (ICPC 2013): fraction of the comment's words within Levenshtein distance under 2 of a word in the symbol's own (split) name. HIGH c_coeff IS BAD: it means the comment mostly repeats the name and adds no information; this is the OPPOSITE of the naive 'high coherence sounds good' reading. words=the comment's total word count (c_coeff's denominator, UNFILTERED: stopwords kept, matching the paper) restate=the numerator, words that matched a name word cic=Scalabrino Comments-Identifiers Consistency (ICPC 2016 / JSEP 2018): Jaccard overlap of two method-local TERM SETS: the comment's vocabulary vs every identifier the definition's own span uses (parameters, locals, callees, fields), both preprocessed (operators/keywords stripped by construction, camelCase/snake_case split, English stopwords dropped, deduplicated). c_terms=|Comments(m)| i_terms=|Ids(m)| shared=size of their overlap; from these, cic = shared/(c_terms+i_terms-shared). c_coeff and cic measure DIFFERENT things and are expected to DISAGREE: report both, never collapse to one number. Fires ONLY where a doc comment actually exists immediately above the definition; a symbol with none (or one that tokenizes to zero words) is UNAVAILABLE for this measure, never scored: counted in no_comment=, never as a zero. Complements doc-drift, which checks markdown CLAIM staleness, a disjoint axis over disjoint input; this verb never checks staleness and doc-drift never checks content. documented=functions/methods measured (rows emitted) no_comment=eligible symbols with nothing to measure unreadable_files=indexed files this pass could not read; their functions are absent, so documented= is a FLOOR shown=rows printed capped=1 when rows were dropped; raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it), which also prints total= has_more= next_offset= offset= limit= -->
<comment_coherence documented="2306" no_comment="5707" shown="8" capped="1" total="2306" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<fn p="src/query.h:231" n="sourceAll" c_coeff="1.000" words="1" restate="1" cic="0.000" c_terms="1" i_terms="12" shared="0"/>
<fn p="src/verbs_quality.h:1514" n="runDmm" c_coeff="1.000" words="1" restate="1" cic="0.032" c_terms="1" i_terms="31" shared="1"/>
<fn p="src/infra/dynamic_map.hpp:1956" n="erase_rec" c_coeff="1.000" words="1" restate="1" cic="0.048" c_terms="1" i_terms="21" shared="1"/>
<fn p="test/lintfix/bad.cpp:23" n="emptyCatchFunc" c_coeff="1.000" words="2" restate="2" cic="0.400" c_terms="2" i_terms="5" shared="2"/>
<fn p="test/bm25fix/common.cpp:18" n="module_validate_handle" c_coeff="0.667" words="6" restate="4" cic="0.400" c_terms="4" i_terms="3" shared="2"/>
<fn p="test/bm25fix/common.cpp:6" n="module_startup_log" c_coeff="0.571" words="7" restate="4" cic="0.286" c_terms="5" i_terms="4" shared="2"/>
<fn p="test/bm25fix/common.cpp:12" n="module_shutdown_log" c_coeff="0.571" words="7" restate="4" cic="0.286" c_terms="5" i_terms="4" shared="2"/>
<fn p="test/jsmetricsfix/shapes.js:29" n="callsLeafAndDeep" c_coeff="0.533" words="15" restate="8" cic="0.364" c_terms="10" i_terms="5" shared="4"/>
</comment_coherence>
```

**Shaped by:** `--limit`

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
<!-- ripwire cochange: file pairs that change together in git but share no transitive static dependency (surprising=1) = hidden coupling. together= is the number of commits in window= that touched BOTH files (3 or more, or the pair is not reported); deg= is that count over the commit count of the LESS-CHANGED of the two files, so 1.00 means the quieter file never changed without the other. conf_ab= is that same fraction over a='s OWN commit count and conf_ba= over b='s, which is the asymmetric form: conf_ab=1.00 means a never changed without b. deg= is by construction the larger of the two, and driver= names which side it came from ("a" or "b") — the file whose changes most reliably imply the other's, and therefore the one to look at first. driver= is OMITTED when the two directions are equal, because a tie is not a finding. recur= is how many of sub_windows= the pair actually co-changed in: the mined window is cut into that many equal-COMMIT-COUNT slices (not equal time — a calendar slice can hold 400 commits or 4), so recur=1 at any together= is one burst of activity and not a persistent coupling, which is the distinction a single window cannot make. sub_windows= is the denominator and is never omitted; it is smaller than the nominal 3 only when the window holds fewer commits than that. min_recur= appears when cochange-recur=K (the flag) filtered the rows, so a short list is explained rather than silent. window= is the mining window: the default 18 months, or the since=REV|DATE value when one resolved. surprising= is only defined where BOTH sides could carry a static dependency at all (the same dependency-capable predicate deps <health dep_files=> uses: source languages yes; sh, md, json, ruby and binary/unknown files no). A pair with a dep-incapable side keeps its row and carries dep_capable=0 instead, because for it "shares no static dependency" is vacuously true. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<cochange pairs="1055" window="18mo" sub_windows="3" shown="30" capped="1" total="1055" has_more="1" next_offset="30" offset="0" limit="0" root="." at="5f71cb4fd+dirty">
<pair a="src/cli.h" b="src/editpreview.h" together="4" deg="1.00" conf_ab="0.02" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="bench/scip_pin_precision.py" b="src/pincensus.h" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.60" driver="a" recur="1" surprising="1"/>
<pair a="src/quality.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.03" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/sarif.h" together="3" deg="1.00" conf_ab="0.01" conf_ba="1.00" driver="b" recur="3" surprising="1"/>
<pair a="src/crossref.h" b="src/darkflags.h" together="3" deg="1.00" conf_ab="0.18" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="bench/scip_pin_precision.py" b="src/graph.h" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.06" driver="a" recur="1" surprising="1"/>
<pair a="src/fielduses.h" b="src/nonlocalstate.h" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.27" driver="a" recur="1" surprising="1"/>
<pair a="src/fieldaffinity.h" b="test/accessshapefix/walks.cpp" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/lintrules.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/serialize.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.03" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
... [21 more line(s); run it to see the whole thing]
```

**Shaped by:** `--cochange-recur`, `--cochange-groups`, `--since`, `--limit`

### `--cochange-recur=K`

**Answers:** (with --cochange) report only pairs whose co-change RECURS in K or more of the mined window's sub-windows, so a one-off refactor sprint stops reading like an eighteen-month structural defect (Clio, ICSE 2011).

Every row carries recur= with or without this flag; the header publishes sub_windows= (the denominator) and min_recur= when the filter is on

**Try it**

_Only pairs whose co-change RECURS in 2+ sub-windows of the mined window (sub_windows= is the denominator) — a one-off sprint stops reading like a structural defect._

```
$ ./build/ripwire . --cochange --cochange-recur=2
<!-- ripwire cochange: file pairs that change together in git but share no transitive static dependency (surprising=1) = hidden coupling. together= is the number of commits in window= that touched BOTH files (3 or more, or the pair is not reported); deg= is that count over the commit count of the LESS-CHANGED of the two files, so 1.00 means the quieter file never changed without the other. conf_ab= is that same fraction over a='s OWN commit count and conf_ba= over b='s, which is the asymmetric form: conf_ab=1.00 means a never changed without b. deg= is by construction the larger of the two, and driver= names which side it came from ("a" or "b") — the file whose changes most reliably imply the other's, and therefore the one to look at first. driver= is OMITTED when the two directions are equal, because a tie is not a finding. recur= is how many of sub_windows= the pair actually co-changed in: the mined window is cut into that many equal-COMMIT-COUNT slices (not equal time — a calendar slice can hold 400 commits or 4), so recur=1 at any together= is one burst of activity and not a persistent coupling, which is the distinction a single window cannot make. sub_windows= is the denominator and is never omitted; it is smaller than the nominal 3 only when the window holds fewer commits than that. min_recur= appears when cochange-recur=K (the flag) filtered the rows, so a short list is explained rather than silent. window= is the mining window: the default 18 months, or the since=REV|DATE value when one resolved. surprising= is only defined where BOTH sides could carry a static dependency at all (the same dependency-capable predicate deps <health dep_files=> uses: source languages yes; sh, md, json, ruby and binary/unknown files no). A pair with a dep-incapable side keeps its row and carries dep_capable=0 instead, because for it "shares no static dependency" is vacuously true. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<cochange pairs="638" window="18mo" sub_windows="3" min_recur="2" shown="30" capped="1" total="638" has_more="1" next_offset="30" offset="0" limit="0" root="." at="5f71cb4fd+dirty">
<pair a="src/cli.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.01" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/quality.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.03" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/crossref.h" b="src/darkflags.h" together="3" deg="1.00" conf_ab="0.18" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/lintrules.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/sarif.h" together="3" deg="1.00" conf_ab="0.01" conf_ba="1.00" driver="b" recur="3" surprising="1"/>
<pair a="src/fieldaffinity.h" b="test/accessshapefix/walks.cpp" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/ingest.cpp" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.02" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/clones.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.27" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/accessshape.h" b="test/accessshapefix/walks.cpp" together="3" deg="1.00" conf_ab="1.00" conf_ba="1.00" recur="2" surprising="1"/>
<pair a="src/serialize.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.03" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
... [21 more line(s); run it to see the whole thing]
```

### `--cochange-groups`

**Answers:** (with --cochange, repo-wide only) emit Modularity Violation GROUPS instead of pairs: "X co-changes with {A,B,C}, none of which it depends on" is ONE row that names the file to fix (Mo/Cai/Kazman, IEEE TSE 2019).

A greedy cover, disclosed as greedy — set cover is NP-hard, so the group count is an upper bound on the minimum, not the minimum

**Try it**

_Modularity-violation GROUPS instead of pairs: "X co-changes with {A,B,C}, none of which it depends on" — a greedy cover, disclosed as greedy._

```
$ ./build/ripwire . --cochange --cochange-groups
<!-- ripwire cochange groups: the surprising=1 violating pairs, collapsed around the file each group names. core= is the file to look at; each <f p=> under it is a partner it co-changes with and has no transitive static dependency on, so one group replaces its partners= pair rows. together=/recur=/conf_core= are that pair's own numbers: together= is the shared commit count, recur= how many of sub_windows= equal-commit-count slices of window= it recurs in, and conf_core= is conf(core => partner) — of the CORE's commits, the fraction that also touched this partner. groups= is a GREEDY cover, not a proven minimal one (minimum set cover is NP-hard): it is an upper bound on the smallest number of groups, and repeatedly picking the file covering the most still-uncovered pairs is what produced it. pairs_covered= is the total membership count and equals the number of surprising=1 pairs, because every violating pair lands in exactly one group. min_recur= appears when cochange-recur=K (the flag) filtered the pairs BEFORE they were grouped. Pairs that are not surprising=1, and pairs with a dep-incapable side (dep_capable=0), are not violations and are absent here — drop the cochange-groups flag for the full pair list. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<cochange groups="30" pairs_covered="196" cover="greedy" window="18mo" sub_windows="3" shown="30" capped="0" root="." at="5f71cb4fd+dirty">
<group core="src/cli.h" partners="54">
<f p="present/deck5_ripwire_build.js" together="33" recur="3" conf_core="0.15"/>
<f p="src/clones.h" together="5" recur="2" conf_core="0.02"/>
<f p="src/compactlegend.h" together="7" recur="1" conf_core="0.03"/>
<f p="src/contextratio.h" together="3" recur="2" conf_core="0.01"/>
<f p="src/crossref.h" together="8" recur="2" conf_core="0.04"/>
<f p="src/didyoumean.h" together="3" recur="3" conf_core="0.01"/>
<f p="src/editcheck.h" together="4" recur="2" conf_core="0.02"/>
<f p="src/editplan.h" together="8" recur="2" conf_core="0.04"/>
<f p="src/editpreview.h" together="4" recur="1" conf_core="0.02"/>
... [17 more line(s); run it to see the whole thing]
```

### `--since=REV|DATE`

**Answers:** scope --hotspots/--cochange/--rank-by=churn|churn-decay to commits after this point: a revision (HEAD~20, a tag/sha — deterministic) or a git approxidate ("2 weeks ago" — wall-clock-relative).

e.g. --hotspots --since="1 week ago" ranks by RECENT churn (the regression lens). Absent ⇒ each verb's OWN bounded default window, NOT all history: --hotspots 12 months, --rank-by=churn 18 months, --cochange 18 months (--rank-by=churn-decay is the ONE exception: its default IS all history, because the 90-day half-life makes a cut-off unnecessary — it stamps that too). All of them STAMP the window they used (window="12mo"/"18mo", or the resolved --since value) — --cochange gained its window= in the same round that gave it sub_windows=, and this clause used to say it had none. An UNRESOLVABLE value is refused by --hotspots (exit 1 — its window is part of the measurement) and degrades to the verb's own default window elsewhere BESIDE --slice=SYM:VAR it is not a window at all: it names the revision whose def-use slice of that variable this run is diffed against — see --slice

**Try it**

_Hotspots scoped to RECENT churn (the regression lens)._

```
$ ./build/ripwire . --hotspots --since="2 weeks ago"
<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=2 weeks ago). churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. unranked_no_complexity= is a file with commits but no function or method to score (a pure declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the join could not match), which scores zero for a reason that is not about the file. Treat it as an upper bound on quietness, not a measure of it. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<hotspots window="2 weeks ago" files="1590" ranked="224" unranked_no_churn="1048" unranked_no_complexity="318" shown="40" capped="1" total="224" has_more="1" next_offset="40" offset="0" limit="0" root="." at="5f71cb4fd+dirty">
<f p="src/main.cpp" churn="100" ccx="885" score="88500" top="dispatchMain" top_ccx="405" top_l="2653"/>
<f p="src/serialize.h" churn="45" ccx="1863" score="83835" top="packSignatures" top_ccx="220" top_l="3350"/>
<f p="src/mcpverbs.h" churn="76" ccx="980" score="74480" top="runBatchSub" top_ccx="112" top_l="4266"/>
<f p="src/cli.h" churn="119" ccx="501" score="59619" top="parseArgs" top_ccx="191" top_l="4156"/>
<f p="src/quality.h" churn="39" ccx="1182" score="46098" top="computeDelta" top_ccx="243" top_l="5284"/>
<f p="src/graph.h" churn="24" ccx="1851" score="44424" top="buildGraph" top_ccx="779" top_l="962"/>
<f p="src/verbs_navigate.h" churn="33" ccx="599" score="19767" top="runVerify" top_ccx="130" top_l="1316"/>
<f p="src/slice.h" churn="24" ccx="785" score="18840" top="sliceClassify" top_ccx="183" top_l="529"/>
<f p="src/mcp.h" churn="29" ccx="577" score="16733" top="dispatchMcpLine" top_ccx="517" top_l="535"/>
<f p="src/verbs_report.h" churn="16" ccx="1001" score="16016" top="runStructureText" top_ccx="241" top_l="2707"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--slice`

**Caveats (stated by the binary):**

- Absent ⇒ each verb's OWN bounded default window, NOT all history: --hotspots 12 months, --rank-by=churn 18 months, --cochange 18 months (--rank-by=churn-decay is the ONE exception: its default IS all history, because the 90-day half-life makes a cut-off unnecessary — it stamps that too).
- An UNRESOLVABLE value is refused by --hotspots (exit 1 — its window is part of the measurement) and degrades to the verb's own default window elsewhere BESIDE --slice=SYM:VAR it is not a window at all: it names the revision whose def-use slice of that variable this run is diffed against — see --slice

### `--arch=FILE`

**Answers:** enforce layering rules (exit 2 on violation);

the Martin Ca/Ce/I/A/D block it emits is a design heuristic, not independently outcome-validated (never gates). propagation_cost's N is dependency-capable files only, same denominator as --deps <health>. Layer substrings and regex path-rules match the ROOT-RELATIVE path (src/core/x.cpp), not the spelling you passed, so a rules file means the same thing in every checkout

**Try it**

_Enforce layering rules (exit 2 on violation) — run against the repo's own test fixture rules._

```
$ ./build/ripwire . --arch=test/archfix/rules.txt
<!-- ripwire arch: layering fitness function — edges that violate your declared rules (layer rules and regex path-rules). exit=2 if any NEW (un-baselined) violation. <metrics> = descriptive Martin Ca/Ce/I/A/D + reachability, never gates. Rules — layer substrings and regex path-rules alike — are matched against each file's ROOT-RELATIVE path (src/core/x.cpp), never the absolute or ./-prefixed spelling shown in from=/to=, so a rule means the same thing whatever directory the tree was checked out into. -->
<arch layers="2" rules="1" pathRules="0" violations="0" baselined="0" new_violations="0">
<metrics modules="302" typed_modules="115" zone_pain="96" zone_useless="1" zone_ok="18" zone_na="187" propagation_cost="0.008" note="Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — directory-level estimate from n … [line truncated: 409 more bytes on this line]
<m path="." ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.codex-plugin" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.github/workflows" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench" ca="0" ce="1" types="20" abstract="2" I="1.00" A="0.10" D="0.10" zone="ok" reachable="1"/>
<m path="./bench/agentloop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite/fixture" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite/fixture/test" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--graph-query`, `--deps`

**Caveats (stated by the binary):**

- the Martin Ca/Ce/I/A/D block it emits is a design heuristic, not independently outcome-validated (never gates).

### `--arch=FILE --baseline`

**Answers:** write .ripwire_arch_baseline (accept current debt as baseline), exit 0

**Try it**

_Enforce layering rules (exit 2 on violation) — run against the repo's own test fixture rules._

```
$ ./build/ripwire . --arch=test/archfix/rules.txt
<!-- ripwire arch: layering fitness function — edges that violate your declared rules (layer rules and regex path-rules). exit=2 if any NEW (un-baselined) violation. <metrics> = descriptive Martin Ca/Ce/I/A/D + reachability, never gates. Rules — layer substrings and regex path-rules alike — are matched against each file's ROOT-RELATIVE path (src/core/x.cpp), never the absolute or ./-prefixed spelling shown in from=/to=, so a rule means the same thing whatever directory the tree was checked out into. -->
<arch layers="2" rules="1" pathRules="0" violations="0" baselined="0" new_violations="0">
<metrics modules="302" typed_modules="115" zone_pain="96" zone_useless="1" zone_ok="18" zone_na="187" propagation_cost="0.008" note="Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — directory-level estimate from n … [line truncated: 409 more bytes on this line]
<m path="." ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.codex-plugin" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.github/workflows" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench" ca="0" ce="1" types="20" abstract="2" I="1.00" A="0.10" D="0.10" zone="ok" reachable="1"/>
<m path="./bench/agentloop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite/fixture" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite/fixture/test" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--graph-query`, `--deps`

### `--arch=FILE --baseline-update`

**Answers:** merge current violations into baseline (accept new debt), exit 0

**Try it**

_Enforce layering rules (exit 2 on violation) — run against the repo's own test fixture rules._

```
$ ./build/ripwire . --arch=test/archfix/rules.txt
<!-- ripwire arch: layering fitness function — edges that violate your declared rules (layer rules and regex path-rules). exit=2 if any NEW (un-baselined) violation. <metrics> = descriptive Martin Ca/Ce/I/A/D + reachability, never gates. Rules — layer substrings and regex path-rules alike — are matched against each file's ROOT-RELATIVE path (src/core/x.cpp), never the absolute or ./-prefixed spelling shown in from=/to=, so a rule means the same thing whatever directory the tree was checked out into. -->
<arch layers="2" rules="1" pathRules="0" violations="0" baselined="0" new_violations="0">
<metrics modules="302" typed_modules="115" zone_pain="96" zone_useless="1" zone_ok="18" zone_na="187" propagation_cost="0.008" note="Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — directory-level estimate from n … [line truncated: 409 more bytes on this line]
<m path="." ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.codex-plugin" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.github/workflows" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench" ca="0" ce="1" types="20" abstract="2" I="1.00" A="0.10" D="0.10" zone="ok" reachable="1"/>
<m path="./bench/agentloop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite/fixture" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite/fixture/test" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--graph-query`, `--deps`

### `--lint`

**Answers:** built-in AST checks (c-cast, goto, unsafe-c-fn, naming-*, cache-* data-layout, ...).

naming-uninformative is ONE-SIDED by design: it fires only when a name's subtokens are ALL corpus-common (BM25 idf over the identifier-name corpus) AND its body clears a size floor — a high-idf (distinctive) name is never penalised, unlike the withdrawn name<->body rule. Each <rule> row's applicability is per-LANGUAGE, not per-file-content: a rule whose registered languages (see --lint-catalog) intersect NONE of the corpus' languages carries applicable="0" (its count="0" is then structural inertness, not a measurement), and the root tallies inert_rules="N"; see --lint-catalog for the full registry

**Try it**

_Built-in AST checks (c-cast, goto, unsafe-c-fn, ...)._

```
$ ./build/ripwire . --lint
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries count_capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one PRINTED rule row is a floor (never inherited from a rule lint-select/lint-ignore dropped), and the root then also carries counts_floor="1" and capped="1": findings= and total= are floors, rows exist that no page holds. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed them, absent an explicit limit=) — a different fact from the per-rule count_capped="1" above, which is a MATCH-BUDGET floor on one rule's own count=; findings= is the true total unless findings_capped="1" floors it. A rule row's applicable="0" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this corpus at all — its count="0" is structural inertness, never a measurement; the root's inert_rules=N tallies how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a family (e.g. cache-); the root then carries selected="K of N" plus the raw select=/ignore= you passed. naming_locals="1" on the root ⇒ the opt-in naming-locals modifier was on (the naming-* rules also read local variables inside already-flagged functions); absent ⇒ off, and the naming-* counts cover declarations only. Each rule row's own shown_rows=/rows_capped= is how many of THAT rule's rows fall inside the printed <f> window (the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the cut carries shown_rows="0" rows_capped="1" while its count= stays the true total — never confuse a capped-away rule with one that measured zero); this is a DIFFERENT fact from the row's own count_capped="1" above (that rule's own raw-capture stream hit its per-rule match budget) — the two can disagree on the same row. A lint-rules row's compiled="0" ⇒ that rule's tree-sitter QUERY failed to compile for every linked grammar (a malformed or misspelled pattern) — its count="0" never ran at all, a different claim from applicable="0" above (a well-formed query whose declared language just is not in this corpus) and from an ordinary count="0" (a well-formed query that ran and found nothing); absent ⇒ the query compiled. -->
<lint findings="3845" shown="688" capped="1" total="3845" has_more="1" next_offset="688" offset="0" limit="0" counts_floor="1" findings_capped="1" root=".">
<rule name="c-style-cast" count="307" shown_rows="104" rows_capped="1"/>
<rule name="goto" count="3" shown_rows="1" rows_capped="1"/>
<rule name="do-while" count="5" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="12" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="507" shown_rows="308" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="248" shown_rows="45" rows_capped="1"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--expand`, `--naming-calibration`, `--naming-locals`, `--lint-catalog`, `--lint-rules`, `--lint-select`, `--lint-ignore`

**Caveats (stated by the binary):**

- naming-uninformative is ONE-SIDED by design: it fires only when a name's subtokens are ALL corpus-common (BM25 idf over the identifier-name corpus) AND its body clears a size floor — a high-idf (distinctive) name is never penalised, unlike the withdrawn name<->body rule.
- Each <rule> row's applicability is per-LANGUAGE, not per-file-content: a rule whose registered languages (see --lint-catalog) intersect NONE of the corpus' languages carries applicable="0" (its count="0" is then structural inertness, not a measurement), and the root tallies inert_rules="N";

### `--lint-catalog`

**Answers:** the built-in rule registry: one row per rule with sev=/category=/rationale/lang=/since= — no corpus needed.

Every built-in rule from every pack (base checks, atoms-*, cache-*, naming-*, the symbol-level checks) has exactly one row; lang= is the SAME token spelling --lint-rules' language: field accepts, so it round-trips into a user rule

**Try it**

_The built-in rule registry — one row per rule with sev=/category=/rationale/lang=/since=; no corpus needed._

```
$ ./build/ripwire . --lint-catalog
<!-- ripwire lint-catalog: the built-in lint rule registry, one row per rule, in the SAME order the plain lint run's own tally uses. sev/cat/rationale describe the rule; lang= is the language TOKEN SET (the spelling the lint-rules loader's own language: field accepts) whose grammar can ever satisfy this rule's query or scan — a STRUCTURAL ceiling, not which languages happen to be in any one corpus (that disclosure is the lint run's own applicable=/inert_rules=). since= is the ripwire release the rule first shipped in. -->
<lintcatalog rules="39">
<rule name="c-style-cast" sev="warn" cat="style" lang="cpp,c,objc,java,cs" since="v0.1.0">a C-style cast — cppcoreguidelines-pro-type-cstyle-cast prefers the explicit static_cast/const_cast/reinterpret_cast</rule>
<rule name="goto" sev="warn" cat="control-flow" lang="cpp,c,objc,go,cs" since="v0.1.0">a goto statement — cppcoreguidelines-avoid-goto</rule>
<rule name="do-while" sev="info" cat="style" lang="cpp,c,objc,ts,js,swift,java,cs" since="v0.1.0">a do/while loop shape (on Swift, its do/catch block shares the same grammar node and also matches)</rule>
<rule name="unsafe-c-fn" sev="error" cat="security" lang="cpp,c,objc,ts,js,go,rs" since="v0.1.0">a call to an unbounded C string function (strcpy/strcat/sprintf/gets)</rule>
<rule name="weak-crypto" sev="error" cat="security" lang="cpp,c,objc,ts,js,go,rs" since="v0.1.0">a call to a broken hash or cipher (MD5/SHA1/MD4/RC4)</rule>
<rule name="redundant-parens" sev="info" cat="style" lang="cpp,c,objc,py,ts,js,go,rs,java,cs" since="v0.1.0">a doubly-parenthesized expression — readability-redundant-parentheses</rule>
<rule name="suspicious-semicolon" sev="warn" cat="correctness" lang="cpp,c,objc" since="v0.1.0">an if-body that is just `;` — bugprone-suspicious-semicolon</rule>
<rule name="typedef-over-using" sev="info" cat="style" lang="cpp,c,objc" since="v0.1.0">a C-style typedef struct/union where `using` is preferred</rule>
<rule name="magic-number" sev="info" cat="maintainability" lang="cpp,c,objc" since="v0.1.0">a non-trivial numeric literal inside a function body, outside a const/constexpr init</rule>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--lint`

### `--lint-rules=DIR`

**Answers:** load user lint rules (YAML, ast-grep style) from DIR — runs with, or instead of, --lint

**Try it**

_User lint rules (YAML, ast-grep style) from a directory._

```
$ ./build/ripwire . --lint-rules=test/lintrulesfix/rules
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries count_capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one PRINTED rule row is a floor (never inherited from a rule lint-select/lint-ignore dropped), and the root then also carries counts_floor="1" and capped="1": findings= and total= are floors, rows exist that no page holds. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed them, absent an explicit limit=) — a different fact from the per-rule count_capped="1" above, which is a MATCH-BUDGET floor on one rule's own count=; findings= is the true total unless findings_capped="1" floors it. A rule row's applicable="0" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this corpus at all — its count="0" is structural inertness, never a measurement; the root's inert_rules=N tallies how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a family (e.g. cache-); the root then carries selected="K of N" plus the raw select=/ignore= you passed. naming_locals="1" on the root ⇒ the opt-in naming-locals modifier was on (the naming-* rules also read local variables inside already-flagged functions); absent ⇒ off, and the naming-* counts cover declarations only. Each rule row's own shown_rows=/rows_capped= is how many of THAT rule's rows fall inside the printed <f> window (the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the cut carries shown_rows="0" rows_capped="1" while its count= stays the true total — never confuse a capped-away rule with one that measured zero); this is a DIFFERENT fact from the row's own count_capped="1" above (that rule's own raw-capture stream hit its per-rule match budget) — the two can disagree on the same row. A lint-rules row's compiled="0" ⇒ that rule's tree-sitter QUERY failed to compile for every linked grammar (a malformed or misspelled pattern) — its count="0" never ran at all, a different claim from applicable="0" above (a well-formed query whose declared language just is not in this corpus) and from an ordinary count="0" (a well-formed query that ran and found nothing); absent ⇒ the query compiled. -->
<lint findings="5" shown="5" capped="0" root=".">
<rule name="broken-query" sev="error" count="0" shown_rows="0" rows_capped="0" compiled="0"/>
<rule name="no-printf" sev="warn" count="5" shown_rows="5" rows_capped="0"/>
<f rule="no-printf" sev="warn" p="test/coplintfix/position.cpp:41" in="demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/coplintfix/safe.cpp:15" in="safe_demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/coplintfix/safe.cpp:27" in="safe_demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/lintrulesfix/sample.cpp:8" in="greet">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/usesfix/store.cpp:24" in="run">use LOG() instead of printf</f>
</lint>
```

**Shaped by:** `--lint-catalog`, `--lint-select`, `--lint-ignore`, `--sarif`

### `--lint-select=PREFIX[,...]`

**Answers:** (with --lint / --lint-rules) run ONLY rules whose name starts with one of these PREFIXes (or '*' for all) — comma-separated, e.g.

cache- selects the whole cache-* family. The root then carries selected="K of N" plus the raw select=/ignore= you passed, so a filtered zero is never confusable with an unfiltered one. An unresolvable PREFIX (matches no rule) refuses (exit 1), naming the nearest rule/family by edit distance

**Try it**

_An unresolvable PREFIX refuses (exit 1) with a did-you-mean from a real edit distance (one character off cache-)._

```
$ ./build/ripwire . --lint --lint-select=cach-
(empty)
```

**Shaped by:** `--lint-ignore`

**Caveats (stated by the binary):**

- The root then carries selected="K of N" plus the raw select=/ignore= you passed, so a filtered zero is never confusable with an unfiltered one.
- An unresolvable PREFIX (matches no rule) refuses (exit 1), naming the nearest rule/family by edit distance

### `--lint-ignore=PREFIX[,...]`

**Answers:** (with --lint / --lint-rules) DROP rules whose name starts with one of these PREFIXes (or '*' to drop everything, e.g.

paired with --lint-select elsewhere to isolate one family) — applied AFTER --lint-select narrows the set; same unresolvable-PREFIX refusal and root disclosure as --lint-select

**Try it**

_DROP two families, applied after selection; the raw select=/ignore= you passed rides on the root._

```
$ ./build/ripwire . --lint --lint-ignore=naming-,cache-
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries count_capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one PRINTED rule row is a floor (never inherited from a rule lint-select/lint-ignore dropped), and the root then also carries counts_floor="1" and capped="1": findings= and total= are floors, rows exist that no page holds. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed them, absent an explicit limit=) — a different fact from the per-rule count_capped="1" above, which is a MATCH-BUDGET floor on one rule's own count=; findings= is the true total unless findings_capped="1" floors it. A rule row's applicable="0" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this corpus at all — its count="0" is structural inertness, never a measurement; the root's inert_rules=N tallies how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a family (e.g. cache-); the root then carries selected="K of N" plus the raw select=/ignore= you passed. naming_locals="1" on the root ⇒ the opt-in naming-locals modifier was on (the naming-* rules also read local variables inside already-flagged functions); absent ⇒ off, and the naming-* counts cover declarations only. Each rule row's own shown_rows=/rows_capped= is how many of THAT rule's rows fall inside the printed <f> window (the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the cut carries shown_rows="0" rows_capped="1" while its count= stays the true total — never confuse a capped-away rule with one that measured zero); this is a DIFFERENT fact from the row's own count_capped="1" above (that rule's own raw-capture stream hit its per-rule match budget) — the two can disagree on the same row. A lint-rules row's compiled="0" ⇒ that rule's tree-sitter QUERY failed to compile for every linked grammar (a malformed or misspelled pattern) — its count="0" never ran at all, a different claim from applicable="0" above (a well-formed query whose declared language just is not in this corpus) and from an ordinary count="0" (a well-formed query that ran and found nothing); absent ⇒ the query compiled. -->
<lint findings="1554" shown="729" capped="1" total="1554" has_more="1" next_offset="729" offset="0" limit="0" counts_floor="1" findings_capped="1" selected="22 of 39" ignore="naming-,cache-" root=".">
<rule name="c-style-cast" count="307" shown_rows="118" rows_capped="1"/>
<rule name="goto" count="3" shown_rows="1" rows_capped="1"/>
<rule name="do-while" count="5" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="12" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="507" shown_rows="431" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="1" rows_capped="1"/>
<rule name="large-function" count="248" shown_rows="58" rows_capped="1"/>
... [17 more line(s); run it to see the whole thing]
```

### `--sarif`

**Answers:** (with --lint / --lint-rules) the SAME findings as SARIF 2.1.0 instead of the native XML <lint> block — the shape github/codeql-action/upload-sarif consumes for code scanning.

Pure re-serialization (zero new analysis); results count == the native run's findings count. Levels: user severity error/warn/info -> SARIF error/warning/note; a built-in finding (a fact, never a gate) has no severity of its own and also maps to note. Fields with no SARIF home (per-rule capped= floor, enclosing symbol, raw sev=) ride in properties rather than being dropped; URIs are relative to the scanned root. Always the FULL result set — refuses loudly alongside limit=/offset= paging, --match and --with-profile

**Try it**

_The SAME findings as SARIF 2.1.0 (what github/codeql-action/upload-sarif consumes) — pure re-serialization, results count == the native run's._

```
$ ./build/ripwire . --lint --sarif
{"version":"2.1.0","$schema":"https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json","runs":[{"tool":{"driver":{"name":"ripwire","rules":[{"id":"c-style-cast","shortDescription":{"text":"c-style-cast"},"properties":{"builtin":true,"capped":false,"applicable": … [line truncated: 7 more bytes on this line]
{"id":"goto","shortDescription":{"text":"goto"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"do-while","shortDescription":{"text":"do-while"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"unsafe-c-fn","shortDescription":{"text":"unsafe-c-fn"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"weak-crypto","shortDescription":{"text":"weak-crypto"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"redundant-parens","shortDescription":{"text":"redundant-parens"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"suspicious-semicolon","shortDescription":{"text":"suspicious-semicolon"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"typedef-over-using","shortDescription":{"text":"typedef-over-using"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"magic-number","shortDescription":{"text":"magic-number"},"properties":{"builtin":true,"capped":true,"applicable":true}},
{"id":"empty-catch","shortDescription":{"text":"empty-catch"},"properties":{"builtin":true,"capped":false,"applicable":true}},
... [21 more line(s); run it to see the whole thing]
```

**Shaped by:** `--legend`

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
<!-- ripwire communities: cohesive call-graph modules (Louvain); bridge=cross-module edges; isolated=call-graph-edgeless symbols; drill= names the verb that takes an id= from a row below. On each module row size= is its TRUE member count while shown=/capped= describe the member list printed here: this listing is fixed at the 5 top-ranked members and is NOT widened by limit=/offset= (those page the MODULE rows). capped=1 means members were dropped; drill= names the verb that pages the full member list of one module. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<communities drill="--community=ID" modules="1088" shown_modules="30" modules_capped="1" bridges="1589" shown_bridges="12" bridges_capped="1" isolated="8154" isolated_decl="2011" isolated_header="1023" isolated_source="2722" isolated_doc="2398" connected_singletons="0" symbols="13896" total="1088" h … [line truncated: 137 more bytes on this line]
<community id="2897" size="518" dir="src" label="src::min@infra/fastmath.h:51:2347 [run,write,emit]" shown="5" capped="1">
<member t="method" n="empty" p="src/notes.h:431"/>
<member t="method" n="empty" p="src/scipoverlay.h:106"/>
<member t="fn" n="min" p="src/infra/fastmath.h:51"/>
<member t="method" n="reserve" p="src/mergescout.h:347"/>
<member t="fn" n="escapeXml" p="src/serialize.h:124"/>
</community>
<community id="2922" size="349" dir="src" label="src::VERIFY@infra/Diagnostics.h:172:8901 [apply,compute,resolve]" shown="5" capped="1">
<member t="method" n="size" p="src/infra/svector.h:285"/>
<member t="fn" n="max" p="src/infra/fastmath.h:54"/>
<member t="method" n="end" p="src/infra/svector.h:270"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--community`, `--limit`

### `--community=ID`

**Answers:** ONE module from that partition: its FULL ranked member list (40 rows by default, raise with --limit, page with --offset) plus its bridge edges to every other module it touches.

ID is an id= from --communities/--zoom; ids live in 0..partition-1 (the child's partition= — the full label space, isolated singletons included), so a single-member module is a legal drill-down and reports size="1". modules= counts the non-isolated communities (same number as the parent's modules=). An id outside 0..partition-1 REFUSES, naming the valid range and the nearest legal id -- a bad id is a typo, not an empty module

**Try it**

_Drill into ONE call-graph community by id — the drill= the --communities output itself advertises._

```
$ ./build/ripwire . --community=0
<!-- ripwire community: ONE module from the communities/zoom partition — its ranked members and its bridge edges to other modules. size= is the module's TRUE member count; shown=/capped= are this page. partition= is the FULL label space (every id 0..partition-1, incl. isolated singletons) — the range the id= argument ranges over; modules= counts the NON-isolated communities (size>=2), the SAME predicate the communities-listing verb's modules= uses, so parent and child agree. counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<community id="0" size="1" dir=".codex-plugin" label=".codex-plugin::name@plugin.json:2:4" bridges="0" shown_bridges="0" bridges_capped="0" partition="9242" modules="1088" shown="1" capped="0" pr_iters="31" root="." graph_ambiguous="6100" graph_unresolved="3097" counts_floor="1">
<member t="sec" n="name" p=".codex-plugin/plugin.json:2"/>
</community>
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- ONE module from that partition: its FULL ranked member list (40 rows by default, raise with --limit, page with --offset) plus its bridge edges to every other module it touches.
- An id outside 0..partition-1 REFUSES, naming the valid range and the nearest legal id -- a bad id is a typo, not an empty module

### `--zoom[=depth]`

**Answers:** NESTED module hierarchy (multi-level Louvain) + cross-module bridges;

--zoom --mermaid = nested diagram. Default window: the top 2 levels (levels_shown=; a module at the cut carries children= for its unprinted child modules; --zoom-levels=N prints N, 0 = all) over the 40 largest top modules (shown=/capped=/next_offset=, next= pastes the next page; --limit=N/--offset=M window them)

**Try it**

_Nested module hierarchy (multi-level Louvain) + cross-module bridges — levels_shown="2" of levels= BY DEFAULT over the 40 largest top modules (~8 KB, where the whole tree is ~220 KB); a module AT the cut carries children=._

```
$ ./build/ripwire . --zoom
<!-- ripwire zoom: NESTED module hierarchy (multi-level Louvain); indent = one level deeper; module = dominant-dir(symbol-count); leaf lists top-ranked symbols; bridge = cross-top-module call traffic. symbols= is the whole corpus; isolated= is the symbols in NO top-level module (a group of one — the same rule that makes top_modules= count only groups of 2 or more), and they reconcile exactly: symbols= equals isolated= plus the sum of the TOP-LEVEL size= values, every one of them, including any this page did not print. On a level-0 module size= is its true member count and shown=/capped= describe the member list printed here, which is fixed at the 5 top-ranked members and is not widened by limit=/offset= (those page the TOP-LEVEL modules); the community drill verb pages one module's full member list by its level-0 id. A module above level 0 lists every child module, so it carries no shown=/capped= pair. levels_shown= is how many of the levels= this document prints from the top (default 2; the zoom-levels flag sets it, 0 = all): a module AT the cut carries children= (its child modules, none printed) instead of nesting. The top-level module rows are a WINDOW (shown=/capped=/total=/next_offset=, default 40 largest; limit=/offset= page it) and next= pastes the next page. counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<zoom levels="5" levels_shown="2" top_modules="400" symbols="13896" isolated="8154" shown="40" capped="1" total="400" has_more="1" next_offset="40" offset="0" limit="0" pr_iters="31" graph_ambiguous="6100" graph_unresolved="3097" counts_floor="1" next="--zoom --offset=40">
<module level="4" id="489" size="3336" dir="./src">
<module level="3" id="489" size="3336" dir="./src" children="11">
</module>
</module>
<module level="4" id="254" size="610" dir="./bench">
<module level="3" id="254" size="294" dir="./bench/agentloop" children="5">
</module>
<module level="3" id="517" size="259" dir="./bench" children="4">
</module>
<module level="3" id="1773" size="57" dir="./bench/recalleval" children="2">
</module>
</module>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--community`, `--limit`

**Caveats (stated by the binary):**

- --zoom-levels=N prints N, 0 = all) over the 40 largest top modules (shown=/capped=/next_offset=, next= pastes the next page;
- --limit=N/--offset=M window them)

### `--report`

**Answers:** architecture summary (modules, god-files, cycles) as markdown

**Try it**

_Architecture summary (modules, god-files, cycles) as markdown._

```
$ ./build/ripwire . --report
<!-- ripwire markdown: no run of 4-or-more backticks in this output — safe to embed inside a wider fence -->

# ripwire architecture report

1590 files · 13896 symbols · 17115 edges · 1088 modules (8154 call-graph isolated)

Root: `.`

Call-graph isolate provenance: 2011 declaration, 1023 header, 2722 source, 2398 document; 0 connected Louvain singletons

## Modules (call-graph clusters; showing 12 of 1088)
- **src::min@infra/fastmath.h:51:2347 [run,write,emit]** — 518 symbols
- **src::emplace@infra/svector.h:408:22477 [parse,resolve,pack]** — 389 symbols
- **src::VERIFY@infra/Diagnostics.h:172:8901 [apply,compute,resolve]** — 349 symbols
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--legend`, `--limit`

### `--seams`

**Answers:** cross-module call seams no test reaches (untested integration seams)

**Try it**

_Cross-module call seams no test reaches. NOW carries seam_pairs/shown/capped._

```
$ ./build/ripwire . --seams
<!-- ripwire seams: cross-directory call edges NO test reaches (untested integration seams; a fact, not a mandate). module = parent dir; seam = caller-dir -> callee-dir, spelled from= and to=. Each seam pages its own edge rows with shown=/capped=; an edge names caller= at site p= calling callee= at site cp=. UNIT: untested= here counts cross-directory call EDGES. The test gate verb spells untested= over impacted SYMBOLS and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<seams modules="300" bridges="4954" untested="4167" test_files="1108" seam_pairs="40" shown="20" capped="1" total="40" has_more="1" next_offset="20" offset="0" limit="0" pr_iters="31" root="." graph_ambiguous="6100" graph_unresolved="3097" counts_floor="1">
<seam from="src" to="src/infra" untested="3964" shown="5" capped="1">
<edge caller="gitOneLine" p="src/quality.h:1013" callee="shSingleQuote" cp="src/infra/jsonesc.h:268"/>
<edge caller="popenTrimmed" p="src/gitmine.h:223" callee="readByteSafeLine" cp="src/infra/stdinline.h:44"/>
<edge caller="popenTrimmed" p="src/gitmine.h:223" callee="back" cp="src/infra/svector.h:263"/>
<edge caller="popenTrimmed" p="src/gitmine.h:223" callee="back" cp="src/infra/svector.h:264"/>
<edge caller="popenTrimmed" p="src/gitmine.h:223" callee="pop_back" cp="src/infra/svector.h:340"/>
</seam>
<seam from="bench" to="src/infra" untested="87" shown="5" capped="1">
<edge caller="aggregateMax" p="bench/bench_ordered_map.cpp:85" callee="max" cp="src/infra/fastmath.h:54"/>
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="pop_back" cp="src/infra/svector.h:340"/>
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="emplace_back" cp="src/infra/svector.h:333"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

### `--mermaid`

**Answers:** module (directory) dependency graph as a Mermaid diagram (paste/render)

**Try it**

_Module (directory) dependency graph as a Mermaid diagram._

```
$ ./build/ripwire . --mermaid
%% ripwire --mermaid: module (directory) dependency graph — node = dir (symbol count), edge = inter-module calls (>= 3). Render at mermaid.live.
flowchart LR
  subgraph sg0 ["src"]
    n83["src<br/>4614"]
    n84["src/infra<br/>498"]
  end
  subgraph sg1 ["test"]
    n85["test<br/>2744"]
    n163["test/expandmodefix<br/>151"]
    n210["test/massfix<br/>77"]
    n199["test/legofix<br/>60"]
    n230["test/optremarksfix<br/>59"]
    n269["test/sliceflowsensfix<br/>59"]
    n242["test/pyshapefix<br/>58"]
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--zoom`, `--with-graph`, `--legend`, `--limit`

### `--owners[=SYM]`

**Answers:** bus-factor: recency-weighted author ownership per file;

bf=1 = one person holds >80% of weighted commits. Files with authors=1 (deterministically bf=1 share=1.00) fold into ONE <uniform files="N"/> summary row instead of N identical rows; --detail=N restores the full listing. An @FILE:LINE seed rebinds to the innermost enclosing definition (sym= names it) and analyses exactly that definition's file

**Try it**

_Bus-factor: recency-weighted author ownership per file._

```
$ ./build/ripwire . --owners
<!-- ripwire owners: recency-weighted author ownership (half-life=6mo). bf=1 = one person holds >80% of weighted commits (bus-factor risk); authors=1 files fold into <uniform/> below; pass detail=1 for the full per-file listing. files= means two different things by DEPTH here and is deliberately not renamed: on the ROOT it is how many files were ANALYSED; on the <uniform/> fold it is how many of them collapsed into that one row. With a SYM, of= echoes it and defs= is how many DEFINITIONS that name has: this report covers the file holding the FIRST of them (lowest node id, the same pick around and lego make), so defs= above 1 means the other definitions' files were NOT analysed. Qualify with file:name to choose one. An @FILE:LINE seed rebinds to the innermost definition enclosing that line (sym= names it) and covers exactly that definition's file -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<owners files="1590" root="." at="5f71cb4fd+dirty">
<uniform authors="1" bf="1" share="1.00" files="1570"/>
<f p="CHANGELOG.md" authors="3" bf="1" top="<author>" share="0.92"/>
<f p="CLAUDE.md" authors="2" bf="1" top="<author>" share="0.82"/>
<f p="README.md" authors="2" bf="1" top="<author>" share="0.99"/>
<f p="bench/PROFILE.md" authors="2" bf="1" top="<author>" share="0.97"/>
<f p="docs/COMMANDS.md" authors="3" bf="1" top="<author>" share="0.99"/>
<f p="docs/EVALS.md" authors="2" bf="1" top="<author>" share="1.00"/>
<f p="docs/METHODOLOGY.md" authors="2" bf="1" top="<author>" share="0.87"/>
<f p="docs/README.md" authors="3" bf="1" top="<author>" share="0.84"/>
<f p="skills/ripwire-efficient/SKILL.md" authors="2" bf="1" top="<author>" share="0.93"/>
... [12 more line(s); run it to see the whole thing]
```

**Shaped by:** `--at`, `--limit`

### `--dead-code[=DIR]`

**Answers:** high-confidence internal source functions with no caller in the indexed tree;

=DIR scopes to whole path components (dir or filename) and REFUSES a filter that names nothing indexed. A symbol whose definition is produced by a SELF-REGISTERING test/benchmark macro is never reported: doctest TEST_CASE/ TEST_CASE_FIXTURE/SCENARIO, gtest TEST/TEST_F/TEST_P, Catch2, Google Benchmark — a static initializer registers them, so a name-based call graph cannot see the caller and every one of them would be a false positive. Extend the list for your own framework with `.ripwire_config`'s one key, `register_macros = NAME[, NAME...]` (one directive per line, # comments). The exemption is DISCLOSED, never silent: register-macro-excluded="N" rides the report and prints even at 0. Exempt from dead-code only — such a symbol still participates in clone detection. A LEADING ./ anchors DIR at the repo ROOT (=./src matches only the top-level src/ subtree); a bare name (=src) matches that component ANYWHERE in the tree, including nested (test/fixture/src/…)

**Try it**

_High-confidence internal functions with no caller. NOTE the filter is a path-COMPONENT match: 'src' matches any .../src/... segment; use ./src to pin the root directory._

```
$ ./build/ripwire . --dead-code=src
<!-- ripwire dead-code: high-confidence source functions with internal linkage and no caller in the indexed tree. A bare-name filter matches by path COMPONENT: filter="src" keeps any path with a src segment at any depth (test/x/src/y.cpp included); anchor with ./ (filter="./src") to pin the root-level directory only. register-macro-excluded= counts symbols excluded because their OWN definition is a registered self-registering test/benchmark macro call (doctest/Catch2 TEST_CASE family, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark BENCHMARK family, plus any name a .ripwire_config register_macros= line adds): such a symbol registers itself through a static initializer the call graph cannot see, so zero in-edges on it is not evidence of anything — never a finding, never gating, absent nothing (0 is printed, not omitted). config-warnings= counts two DISCLOSED .ripwire_config problems, each also written to stderr — an unrecognized key, and a register_macros= name matching no indexed symbol — never gating, present only when non-zero. Graph evidence is local to the indexed tree; verify before deleting. counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. -->
<dead-code count="1" confidence="high" evidence="internal-linkage+zero-callers" register-macro-excluded="0" filter="src" root="." graph_ambiguous="6100" graph_unresolved="3097" counts_floor="1">
<d n="unused_helper" t="fn" p="test/archmetricsfix/src/orphan/util.cpp" l="1"/>
</dead-code>
```

**Shaped by:** `--safe-delete`, `--limit`

**Caveats (stated by the binary):**

- =DIR scopes to whole path components (dir or filename) and REFUSES a filter that names nothing indexed.
- The exemption is DISCLOSED, never silent: register-macro-excluded="N" rides the report and prints even at 0.

### `--quality-baseline`

**Answers:** snapshot ccx/clones/dead-code to .ripwire_quality_baseline (run BEFORE a change, on a CLEAN tree).

On a tree that DIFFERS from HEAD it computes the HEAD delta FIRST and REFUSES (exit 1) rather than pin the debt already in the tree as the floor — it names how many gating findings it would absorb and the first of them. Commit, or pass --allow-dirty.

**Try it**

_REFUSES, exit 1: this sandbox tree is already regressed, and pinning here would swallow that debt into the floor so every later delta read clean. It names how many gating findings it would absorb, the first of them, and the way forward._

```
$ ./build/ripwire . --quality-baseline
(empty)
```

**Shaped by:** `--allow-dirty`, `--quality-delta`, `--legend`

**Caveats (stated by the binary):**

- On a tree that DIFFERS from HEAD it computes the HEAD delta FIRST and REFUSES (exit 1) rather than pin the debt already in the tree as the floor — it names how many gating findings it would absorb and the first of them.

### `--allow-dirty`

**Answers:** (with --quality-baseline) pin anyway: the sidecar is stamped with the dirty pin and the absorbed count, and every later --quality-delta against it carries baseline_absorbed="N" — so a green exit beside that attribute reads as "clean SINCE THE PIN", never "clean".

Refused alone.

**Try it**

_The consent form: pin anyway. The sidecar is stamped with the dirty pin and the absorbed count, so the fact outlives the process that knew it._

```
$ ./build/ripwire . --quality-baseline --allow-dirty
(empty)
```

**Shaped by:** `--quality-baseline`

**Caveats (stated by the binary):**

- (with --quality-baseline) pin anyway: the sidecar is stamped with the dirty pin and the absorbed count, and every later --quality-delta against it carries baseline_absorbed="N" — so a green exit beside that attribute reads as "clean SINCE THE PIN", never "clean".

### `--quality-delta`

**Answers:** agent self-check before a PR (pair with --test-gate): report ONLY what a change made worse vs the baseline (10 kinds: complexity/verbosity/nesting/params/dup/dead/api-surface + error-masking/short-horizon-churn/reuse-decline);

every finding is classified by ORIGIN: a symbol that EXISTED at the baseline and got worse (preexisting-worse="N", no attribute on the row) vs one that exists only because the code is NEW (new-symbol="N", origin="new-symbol" on the row). A small numeric delta is additionally sev="minor". EXIT 2 ONLY on preexisting-worse AND major AND unacked — the gating="N" header count. New-symbol rows are still PRINTED (they are the debt you are adding — read them), they just never gate; exit 0 means "nothing that already existed got worse", not "clean". Clone kinds classify by member set (new-symbol only if EVERY member is new); short-horizon-churn is preexisting by construction. LIMIT: origin is canonId (path::scope::name) identity, so a RENAMED/MOVED symbol reads as new and a regression carried in with the move will not gate. Test-fixture dirs + doc sections are exempt from dead-code/churn; churn needs COMMITTED thrash evidence (rewritten across recent commits AND again by this diff), never the current edit alone WHICH FLOOR IT COMPARES AGAINST, and a side effect: the sidecar is honored only when the sha it was pinned at EQUALS the current git HEAD (strict equality — an ancestor commit describes a DIFFERENT tree, so everything committed since would read as your regression). A sidecar pinned anywhere else is STALE: this verb then DELETES it from your working tree (self-heal, so the next run does not rediscover the dead pin) and auto-compares the working tree vs git HEAD instead. Re-pin with --quality-baseline. The read-only MCP quality_delta verb applies the SAME staleness test but never deletes. Which floor was actually used is on every report as baseline=: sidecar | git-HEAD | git-HEAD (stale sidecar removed) | git-HEAD (stale sidecar ignored) — the last two say a stale sidecar existed, and 'removed' means the file is gone. A non-git root has no HEAD to fall back to, so its sidecar is always honored; without one there, the verb exits 1.

**Try it**

_Recorded against a DIRTY tree, so any row below is a real regression in the working copy. The sandbox section below shows the same gating shape on a known, deliberate edit._

```
$ ./build/ripwire . --quality-delta
<!-- ripwire quality-delta: only what a change made WORSE against the floor baseline= names below. Descriptive: weigh and fix the real ones, do not game the number (a wrong abstraction beats a low score). TEN KINDS, and kind= on every row names which one: complexity over the ccx bar, verbosity (LOC), nesting, params, duplication, dead-code, api-surface (new public contract drift), error-masking, short-horizon-churn, new-clone-of-reused-helper. THREE independent axes, in this order: (1) acked findings are suppressed entirely (acked= counts them); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor", and minor= counts them. EXIT 2 fires only on preexisting-worse AND major, the gating= count; new-symbol rows never gate, so exit 0 is NOT a verdict on them — nothing that existed got worse, but the new debt is yours: read them. Clone kinds are new-symbol only when EVERY member is new; short-horizon-churn is preexisting by construction. preexisting-worse= and new-symbol= partition regressions=. stale= is a FOURTH axis, never gating and never counted in regressions=: rows in the .ripwire_quality_acks ledger whose target no longer applies. register-macro-excluded= is a FLOOR, not a finding: symbols this run excluded from the dead-code kind because their own definition is a registered self-registering test/benchmark macro call. Never gates, never counted in regressions=, printed even at zero (zero means none excluded, not that the check did not run). A gating row's next= is the one pasteable follow-up: expand on FILE:NAME, the body to fix (a duplication row names a SET and carries none). bar= on a complexity/verbosity/nesting/params row is the threshold now= is judged against (ccx 15, loc 60, nest 4, params 5). baseline="git-HEAD" means no sidecar existed, so the working tree was auto-compared against the HEAD tree — anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. The registered families are doctest/Catch2 TEST_CASE, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark BENCHMARK, plus any name a .ripwire_config register_macros= line adds; each registers itself through a static initializer the call graph cannot see, so zero in-edges on one is not evidence of anything. IDENTITY across a rename or a move: a finding is keyed path::scope::name, which a rename would destroy, so the baseline and the .ripwire_quality_acks ledger are both re-filed into the CURRENT tree's identity before either is read, by two EXACT mechanisms — git's own rename record, and equality of a whitespace-and-name-scrubbed body hash — never a similarity heuristic. renames= is how many rename pairs were read, rename_window_commits= how deep the commit window went, acked_by_rename= and acked_by_content= how many of the acked= suppressions each mechanism is responsible for. Three appear ONLY when true, so an absent one is not a silent no: renames_window_truncated= (history is deeper than the window), renames_truncated= (the pair cap was hit), renames_ambiguous= (an ancestor two current symbols both claim — refused rather than guessed). ORIGIN reads the re-filed baseline too, so a regression carried in with a rename is judged preexisting-worse and GATES instead of slipping through as new-symbol. FLOORS, stated because silence here would read as a guarantee: the two clone kinds key on a member-SET hash and are NOT re-filed, so a clone ack still dies on a rename; ORIGIN follows the rename record but never content, because the baseline stores no content id at all; and a move git recorded no rename for still reads as new-symbol. Each sa row carries key= (the ack identity as stored) and why=, which is target-gone (the key names no symbol or group any more) or finding-gone (the target survived, this kind just does not fire on it). sym= and p=path:line name WHICH ack it is, and are present exactly when the key still names a live symbol: on every finding-gone row, on none of the target-gone rows (there is nothing left to name), and on neither clone kind — a clone key hashes a member SET that no single symbol carries, so those rows are unnameable by construction rather than guessed at. Hygiene disclosure only — the ledger file is never auto-edited. -->
<quality-delta baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="19" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="3" at="5f71cb4fd+dirty" renames="55" rename_window_commits="400" acked_by_rename="0" acked_by_content="0" renames_window_truncated="1">
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="995375dfa4e63104" why="target-gone"/>
<sa kind="complexity" key="4b309450f25c2b44" why="finding-gone" sym="src/ingest.cpp::rw::ingest" p="src/ingest.cpp:208"/>
<sa kind="complexity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
<sa kind="duplication" key="160ac41979d9ebaf" why="finding-gone"/>
<sa kind="duplication" key="af2e342eda9648ed" why="finding-gone"/>
<sa kind="duplication" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="nesting" key="1bded1f8f88d3b85" why="finding-gone" sym="src/slice.h::slicev::sliceFlowCompute" p="src/slice.h:2286"/>
<sa kind="nesting" key="3c07d993bfdbce53" why="finding-gone" sym="src/slice.h::slicev::sliceBundleText" p="src/slice.h:2685"/>
... [8 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--test-gate`, `--allow-dirty`, `--dmm`, `--quality-ack`, `--scope`, `--json`

**Caveats (stated by the binary):**

- New-symbol rows are still PRINTED (they are the debt you are adding — read them), they just never gate;
- LIMIT: origin is canonId (path::scope::name) identity, so a RENAMED/MOVED symbol reads as new and a regression carried in with the move will not gate.
- The read-only MCP quality_delta verb applies the SAME staleness test but never deletes.

### `--quality-delta=REV|A..B`

**Answers:** the same 10-kind report between two COMMITTED TREES instead of the working tree vs a baseline — the WAVE-level measurement (=A..B = tree B against tree A;

=REV = that commit against its FIRST PARENT; an EMPTY side of the range means HEAD). Same grammar --dmm= takes, and A...B is REFUSED rather than read as A..B. Use it to measure a whole integration branch at once (--quality-delta=<merge-base>..<head>): per-lane checks each compare against their own baseline and cannot see a regression the WAVE introduced. Identical output contract to the bare form — same kinds, gating="N", exit 2, and the same .ripwire_quality_acks ratchet (acks are keyed root-relative, so a ledger recorded from working-tree runs applies unchanged). base_ref= and target_ref= disclose the two RESOLVED shas. No sidecar is read, written or deleted by this form, and at= is omitted: the two refs ARE the anchor. A==B is a legal, empty, exit-0 comparison. ONE KIND CANNOT BE MEASURED HERE and says so as churn="unavailable": short-horizon-churn needs git history at the tree being judged, and both trees are materialized OUT of the repo into temp dirs. The other 9 kinds are computed exactly as the bare form computes them.

**Try it**

_Recorded against a DIRTY tree, so any row below is a real regression in the working copy. The sandbox section below shows the same gating shape on a known, deliberate edit._

```
$ ./build/ripwire . --quality-delta
<!-- ripwire quality-delta: only what a change made WORSE against the floor baseline= names below. Descriptive: weigh and fix the real ones, do not game the number (a wrong abstraction beats a low score). TEN KINDS, and kind= on every row names which one: complexity over the ccx bar, verbosity (LOC), nesting, params, duplication, dead-code, api-surface (new public contract drift), error-masking, short-horizon-churn, new-clone-of-reused-helper. THREE independent axes, in this order: (1) acked findings are suppressed entirely (acked= counts them); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor", and minor= counts them. EXIT 2 fires only on preexisting-worse AND major, the gating= count; new-symbol rows never gate, so exit 0 is NOT a verdict on them — nothing that existed got worse, but the new debt is yours: read them. Clone kinds are new-symbol only when EVERY member is new; short-horizon-churn is preexisting by construction. preexisting-worse= and new-symbol= partition regressions=. stale= is a FOURTH axis, never gating and never counted in regressions=: rows in the .ripwire_quality_acks ledger whose target no longer applies. register-macro-excluded= is a FLOOR, not a finding: symbols this run excluded from the dead-code kind because their own definition is a registered self-registering test/benchmark macro call. Never gates, never counted in regressions=, printed even at zero (zero means none excluded, not that the check did not run). A gating row's next= is the one pasteable follow-up: expand on FILE:NAME, the body to fix (a duplication row names a SET and carries none). bar= on a complexity/verbosity/nesting/params row is the threshold now= is judged against (ccx 15, loc 60, nest 4, params 5). baseline="git-HEAD" means no sidecar existed, so the working tree was auto-compared against the HEAD tree — anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. The registered families are doctest/Catch2 TEST_CASE, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark BENCHMARK, plus any name a .ripwire_config register_macros= line adds; each registers itself through a static initializer the call graph cannot see, so zero in-edges on one is not evidence of anything. IDENTITY across a rename or a move: a finding is keyed path::scope::name, which a rename would destroy, so the baseline and the .ripwire_quality_acks ledger are both re-filed into the CURRENT tree's identity before either is read, by two EXACT mechanisms — git's own rename record, and equality of a whitespace-and-name-scrubbed body hash — never a similarity heuristic. renames= is how many rename pairs were read, rename_window_commits= how deep the commit window went, acked_by_rename= and acked_by_content= how many of the acked= suppressions each mechanism is responsible for. Three appear ONLY when true, so an absent one is not a silent no: renames_window_truncated= (history is deeper than the window), renames_truncated= (the pair cap was hit), renames_ambiguous= (an ancestor two current symbols both claim — refused rather than guessed). ORIGIN reads the re-filed baseline too, so a regression carried in with a rename is judged preexisting-worse and GATES instead of slipping through as new-symbol. FLOORS, stated because silence here would read as a guarantee: the two clone kinds key on a member-SET hash and are NOT re-filed, so a clone ack still dies on a rename; ORIGIN follows the rename record but never content, because the baseline stores no content id at all; and a move git recorded no rename for still reads as new-symbol. Each sa row carries key= (the ack identity as stored) and why=, which is target-gone (the key names no symbol or group any more) or finding-gone (the target survived, this kind just does not fire on it). sym= and p=path:line name WHICH ack it is, and are present exactly when the key still names a live symbol: on every finding-gone row, on none of the target-gone rows (there is nothing left to name), and on neither clone kind — a clone key hashes a member SET that no single symbol carries, so those rows are unnameable by construction rather than guessed at. Hygiene disclosure only — the ledger file is never auto-edited. -->
<quality-delta baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="19" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="3" at="5f71cb4fd+dirty" renames="55" rename_window_commits="400" acked_by_rename="0" acked_by_content="0" renames_window_truncated="1">
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="995375dfa4e63104" why="target-gone"/>
<sa kind="complexity" key="4b309450f25c2b44" why="finding-gone" sym="src/ingest.cpp::rw::ingest" p="src/ingest.cpp:208"/>
<sa kind="complexity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
<sa kind="duplication" key="160ac41979d9ebaf" why="finding-gone"/>
<sa kind="duplication" key="af2e342eda9648ed" why="finding-gone"/>
<sa kind="duplication" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="nesting" key="1bded1f8f88d3b85" why="finding-gone" sym="src/slice.h::slicev::sliceFlowCompute" p="src/slice.h:2286"/>
<sa kind="nesting" key="3c07d993bfdbce53" why="finding-gone" sym="src/slice.h::slicev::sliceBundleText" p="src/slice.h:2685"/>
... [8 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--test-gate`, `--allow-dirty`, `--dmm`, `--quality-ack`, `--scope`, `--json`

**Caveats (stated by the binary):**

- Same grammar --dmm= takes, and A...B is REFUSED rather than read as A..B.
- Use it to measure a whole integration branch at once (--quality-delta=<merge-base>..<head>): per-lane checks each compare against their own baseline and cannot see a regression the WAVE introduced.
- ONE KIND CANNOT BE MEASURED HERE and says so as churn="unavailable": short-horizon-churn needs git history at the tree being judged, and both trees are materialized OUT of the repo into temp dirs.

### `--dmm[=REV|A..B]`

**Answers:** the DELTA MAINTAINABILITY MODEL scalar: ONE comparable number in [0,1] for a change, so quality becomes TRENDABLE across commits instead of a per-kind list (di Biase, Rastogi, Bruntink and van Deursen, TechDebt 2019;

thresholds and arithmetic from PyDriller's deltamaintainability reference implementation). Bare = the WORKING TREE vs git HEAD (what --quality-delta compares); =REV = that commit vs its FIRST PARENT (the per-commit scalar); =A..B = tree B vs tree A. A UNIT is a function/method definition with a body; its VOLUME is its line span. Per property a unit is LOW risk iff size: loc<=15, complexity: cyclomatic<=5, interfacing: params<=2. good = low-risk volume ADDED plus high-risk volume REMOVED; bad = low-risk REMOVED plus high-risk ADDED; dmm = good/(good+bad). So DELETING a god function scores 1.000 and GROWING one scores 0.000. The three sub-scores (size/complexity/interfacing) are emitted alongside the combined one because they are separately actionable; the combined one POOLS them (summed good over summed good+bad) and is labelled combine="pooled", since the paper publishes the three separately and no aggregate. IT IS A DELTA, NEVER A LEVEL: a unit you edit without changing its size, complexity or parameter count sits in the same bin with the same volume on both sides and contributes NOTHING. Touching bad code is not punished, deliberately, because a gate that punishes it is a gate people route around. dmm="UNAVAILABLE" means good+bad was 0 (a rename, a literal edit, a comment reflow): the change is outside what the model measures. That is NEVER to be read as 1.000 or 0.000, and reason= says which case it was. Same token per property. VOLUME IS PHYSICAL LINE SPAN (size_metric="physical-loc"), where the reference implementation uses non-comment non-blank lines, so a heavily commented unit crosses the size threshold here earlier. NO THRESHOLD, NO VERDICT, ALWAYS EXIT 0.

**Try it**

_The Delta Maintainability Model scalar for the WORKING TREE vs HEAD — recorded against a DIRTY tree (the sandbox section shows a real delta). UNAVAILABLE is a stated reason, never 0 or 1._

```
$ ./build/ripwire . --dmm
<!-- ripwire dmm: the Delta Maintainability Model (di Biase, Rastogi, Bruntink, van Deursen, TechDebt 2019), ONE comparable scalar per change. Thresholds and arithmetic are PyDriller's deltamaintainability reference implementation. A UNIT is a function or method definition WITH A BODY; its VOLUME is its line span. Per property a unit is LOW risk iff size: loc at most 15, complexity: cyclomatic at most 5, interfacing: params at most 2. good=volume of low-risk code ADDED plus high-risk code REMOVED bad=volume of low-risk code REMOVED plus high-risk code ADDED dmm=good/(good+bad), in [0,1]: 1.000 means every line this change moved made the code healthier. THIS IS A DELTA, NOT A LEVEL: editing bad code without growing it moves nothing and scores nothing, which is deliberate. dmm=UNAVAILABLE means good+bad was 0, i.e. the change moved no unit's size, complexity or parameter count, and is NEVER to be read as 1.000 or 0.000; reason= says which case it was. base=the earlier tree's commit target=the later tree's commit, or working-tree base_units= target_units= units measured on each side base_volume= target_volume= their total line span combine=how the root dmm= pools the three sub-scores (pooled = summed good over summed good+bad; the paper publishes the three separately and no aggregate, so this one is ripwire's) size_metric=physical-loc: volume is the definition's PHYSICAL line span, where the reference implementation uses non-comment non-blank lines, so a heavily commented unit crosses the size threshold here earlier at= is the git commit this comparison RAN at (HEAD, not base/target — those name what was compared); a trailing +dirty means the working tree differed from that commit available=0 when no score could be produced at all low_loc=/low_cx=/low_params= are the low-risk ceilings a unit is judged against (lines / cyclomatic complexity / parameters). p=one property row k=its name (size|complexity|interfacing) d_low=change in low-risk volume d_high=change in high-risk volume. Every indexed language and every indexed path counts, tests and fixtures included; params and cyclomatic complexity come from the index, so a definition whose grammar exposes no parameter list contributes params=0 and classifies LOW on interfacing. -->
<dmm base="5f71cb4fd2f50c4d5da6f8053964f8c93ae741a2" target="working-tree" at="5f71cb4fd+dirty" available="0" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="UNAVAILABLE" good="0" bad="0" base_units="8013" base_volume="136948" target_units="8013" target_volume … [line truncated: 127 more bytes on this line]
<p k="size" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="complexity" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="interfacing" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
</dmm>
```

**Shaped by:** `--quality-delta`

**Caveats (stated by the binary):**

- IT IS A DELTA, NEVER A LEVEL: a unit you edit without changing its size, complexity or parameter count sits in the same bin with the same volume on both sides and contributes NOTHING.
- That is NEVER to be read as 1.000 or 0.000, and reason= says which case it was.

### `--quality-ack[=REASON]`

**Answers:** accept the current findings into .ripwire_quality_acks (per-finding ratchet): re-runs suppress them honestly (acked="N") until one WORSENS past its acked size.

=REASON implies the --quality-delta report it acks; the reason-less spelling needs --quality-delta beside it (refused alone). An ack with 0 findings to accept writes nothing and says so.

**Try it**

_NEW FLAG: --ack-only matching nothing REFUSES rather than falling back to acking everything._

```
$ ./build/ripwire . --quality-delta --quality-ack --ack-only=zzznope
(empty)
```

**Shaped by:** `--ack-only`, `--scope`, `--legend`

**Caveats (stated by the binary):**

- the reason-less spelling needs --quality-delta beside it (refused alone).

### `--ack-only=SUBSTR[,SUBSTR]`

**Answers:** (with --quality-ack) ack only SOME findings — those whose KIND, canonical id, or FACET contains one of these;

the pseudo-token 'gating' selects exactly what would exit 2. Bare --quality-ack accepts the WHOLE report, so accepting one deliberate change silently accepts the rest — how a ratchet turns into a rubber stamp. Prefer the facet: --ack-only=contract-change acks the deliberate arity changes WITHOUT the never-gating api-surface new-symbol rows. Matching nothing refuses (exit 1) rather than falling back to acking everything. Whatever you leave unacked stays visible.

**Try it**

_--ack-only WITHOUT --quality-ack REFUSES loudly (exit 1, the pairing named) — it used to be silently ignored._

```
$ ./build/ripwire . --ack-only=gating
(empty)
```

**Shaped by:** `--scope`

**Caveats (stated by the binary):**

- Prefer the facet: --ack-only=contract-change acks the deliberate arity changes WITHOUT the never-gating api-surface new-symbol rows.
- Matching nothing refuses (exit 1) rather than falling back to acking everything.

### `--scope=GLOB[,GLOB...]`

**Answers:** (with --quality-delta/--quality-ack) OWNERSHIP partition for a working tree that has MORE THAN ONE WRITER in it — N agent sessions sharing one checkout.

The delta compares the working tree against HEAD, so every concurrent writer's uncommitted rows land in YOUR report; this files each finding by its p= path. Rows in scope gate as usual; rows outside it are STILL PRINTED, under an out-of-scope element with a do-not-ack banner, and never gate. The header carries scope=, scoped-out= and scoped-out-gating= (how many disclosed rows WOULD have gated — do not read a green exit as a clean tree). THE POINT IS THE ACK: bare --quality-ack in a dirty shared tree accepts the WHOLE report, which silently absorbs a sibling session's debt into a committed ledger under your reason string — that is how a ratchet becomes a rubber stamp. Under --scope, an out-of-scope row is never written, and an --ack-only that NAMES one refuses (exit 1, naming the rows, writing nothing). Each row written under a scope records by=<scope>, and a later run flags an ack whose by= does not cover what it suppresses (foreign-acks= plus an sa row with why="foreign-scope"). THE GLOB, EXACTLY (a pattern that silently fails to match is worse than a documented prefix): each comma-separated pattern is matched against the ROOT-RELATIVE path p= prints, and the list is an OR. NO wildcard = a ROOT-ANCHORED path prefix ending on a / boundary (scope=alpha matches alpha/lib.h, never alphabet/lib.h and never a nested src/alpha/ — stricter than the dead-code directory filter, on purpose). With * or ? = matched against the WHOLE path, * spanning / and ? exactly one character. NOT SUPPORTED: ** (it is two stars, and one already spans /), character classes, brace expansion, negation; whitespace and XML metacharacters in a pattern are REFUSED, not mangled. FLOORS: a clone group is in scope iff ANY member matches; a finding with no locator at all is filed OUT of scope (not provably yours); a scope naming nothing indexed REFUSES (exit 1) rather than reporting a clean zero. ONE RESERVED WORD: --scope=diff is the files the WORKING TREE changes vs the baseline, expanded to one path per changed INDEXED file (the count travels with the report as scope-diff-files=). It composes by UNION: --scope=diff,src/quality.h is that set plus that file. A directory really called diff must be spelled ./diff or diff/. IT IS SUGAR FOR THE SINGLE-WRITER CASE and wrong on its own in the shared tree this flag exists for — a sibling's edits are "changed" too, so name your own paths when the tree has more than one writer. Refused, never silently widened, when there is no git, when the range form is in play (it compares two COMMITTED trees), or when it expands to nothing. An ack written under it records by=diff, which a later run does NOT sweep: an auto-scope meant one file set then and another now, so re-checking it would invent findings.

**Try it**

_OWNERSHIP partition for a shared tree: every regression here lives in src/infra/, so under a scope naming src/graph.h they ALL print under <out-of-scope> with a do-not-ack banner and never gate — scoped-out-gating= says how many would have._

```
$ ./build/ripwire . --quality-delta --scope=src/graph.h
<!-- ripwire quality-delta: only what a change made WORSE against the floor baseline= names below. Descriptive: weigh and fix the real ones, do not game the number (a wrong abstraction beats a low score). TEN KINDS, and kind= on every row names which one: complexity over the ccx bar, verbosity (LOC), nesting, params, duplication, dead-code, api-surface (new public contract drift), error-masking, short-horizon-churn, new-clone-of-reused-helper. THREE independent axes, in this order: (1) acked findings are suppressed entirely (acked= counts them); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor", and minor= counts them. EXIT 2 fires only on preexisting-worse AND major, the gating= count; new-symbol rows never gate, so exit 0 is NOT a verdict on them — nothing that existed got worse, but the new debt is yours: read them. Clone kinds are new-symbol only when EVERY member is new; short-horizon-churn is preexisting by construction. preexisting-worse= and new-symbol= partition regressions=. stale= is a FOURTH axis, never gating and never counted in regressions=: rows in the .ripwire_quality_acks ledger whose target no longer applies. register-macro-excluded= is a FLOOR, not a finding: symbols this run excluded from the dead-code kind because their own definition is a registered self-registering test/benchmark macro call. Never gates, never counted in regressions=, printed even at zero (zero means none excluded, not that the check did not run). A gating row's next= is the one pasteable follow-up: expand on FILE:NAME, the body to fix (a duplication row names a SET and carries none). bar= on a complexity/verbosity/nesting/params row is the threshold now= is judged against (ccx 15, loc 60, nest 4, params 5). baseline="git-HEAD" means no sidecar existed, so the working tree was auto-compared against the HEAD tree — anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. The registered families are doctest/Catch2 TEST_CASE, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark BENCHMARK, plus any name a .ripwire_config register_macros= line adds; each registers itself through a static initializer the call graph cannot see, so zero in-edges on one is not evidence of anything. IDENTITY across a rename or a move: a finding is keyed path::scope::name, which a rename would destroy, so the baseline and the .ripwire_quality_acks ledger are both re-filed into the CURRENT tree's identity before either is read, by two EXACT mechanisms — git's own rename record, and equality of a whitespace-and-name-scrubbed body hash — never a similarity heuristic. renames= is how many rename pairs were read, rename_window_commits= how deep the commit window went, acked_by_rename= and acked_by_content= how many of the acked= suppressions each mechanism is responsible for. Three appear ONLY when true, so an absent one is not a silent no: renames_window_truncated= (history is deeper than the window), renames_truncated= (the pair cap was hit), renames_ambiguous= (an ancestor two current symbols both claim — refused rather than guessed). ORIGIN reads the re-filed baseline too, so a regression carried in with a rename is judged preexisting-worse and GATES instead of slipping through as new-symbol. FLOORS, stated because silence here would read as a guarantee: the two clone kinds key on a member-SET hash and are NOT re-filed, so a clone ack still dies on a rename; ORIGIN follows the rename record but never content, because the baseline stores no content id at all; and a move git recorded no rename for still reads as new-symbol. Each sa row carries key= (the ack identity as stored) and why=, which is target-gone (the key names no symbol or group any more) or finding-gone (the target survived, this kind just does not fire on it). sym= and p=path:line name WHICH ack it is, and are present exactly when the key still names a live symbol: on every finding-gone row, on none of the target-gone rows (there is nothing left to name), and on neither clone kind — a clone key hashes a member SET that no single symbol carries, so those rows are unnameable by construction rather than guessed at. Hygiene disclosure only — the ledger file is never auto-edited. ROWS: sym= is the canonical id the finding regressed on; was= and now= carry the before/after value for the numeric kinds; p="path:line" is the locator (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when none resolves). churn= and surface= are per-kind classification facets (short-horizon-churn's self/ambient split; api-surface's new-symbol/contract-change tier). Every row the header's gating= counter counts also carries a gating attribute set to 1 — marked positively, never by the ABSENCE of sev or origin. CLONE ROWS name the whole group rather than one symbol: members= is the member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports). idiom= names a RECOGNIZED BODY SHAPE every member spells, out of a closed set of three (threshold-ladder, switch-name-table, builder-chain). idiom= alone changes nothing; a group that ALSO shares no non-keyword identifier between any two members, sits in pairwise-distinct enclosing contexts, and stays under 80 normalized tokens is an idiom COLLISION rather than a copy, and is reported minor instead of gating. Break any one of those and it gates as before, idiom= and all: two bucketing ladders over the SAME enum are a copy. The shape is read off the body's token stream and not a parse tree, so a macro-assembled body classifies as whatever its raw tokens spell — the name is printed so the call can be overruled by reading. SCOPE, present only when the scope flag was given, and it NARROWS WHAT THIS REPORT CLAIMS: scope= is the pattern list it was given, verbatim. Every counter above (regressions=, minor=, acked=, preexisting-worse=, new-symbol=, gating=) is then over the IN-SCOPE findings alone, and the exit code follows gating= as always. The rest are not dropped: scoped-out= counts the findings filed to somebody else, and every one of them is printed inside an out-of-scope element carrying n= (the same count), would-gate= and note= (the do-not-ack banner). scoped-out-gating= repeats would-gate= on the root because it is the number a reader must not miss: it is how many disclosed rows WOULD have fired the exit code, so exit 0 under a scope means "nothing of YOURS is broken", never "the tree is clean". Rows inside that element carry the identical attributes to the ones above it and never carry the gating attribute, since they are not what this exit code fires on. HOW A FINDING IS FILED: by its p= path, matched root-relative against the patterns; a clone kind is in scope when ANY member matches, not just the first-sorting one; and a finding with no locator at all is filed OUT of scope, because under a scope "we cannot say where this is" honestly reads as not provably yours. -->
<quality-delta baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="19" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="3" at="5f71cb4fd+dirty" renames="55" rename_window_commits="400" acked_by_rename="0" acked_by_content="0" renames_window_truncated="1" scope="src … [line truncated: 47 more bytes on this line]
<out-of-scope n="8" would-gate="4" note="not yours - do not ack: these rows lie outside the scope this run named. They are disclosed rather than hidden, they never gate this exit code, and the ack refuses to write them.">
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" sev="minor" surface="new-symbol" origin="new-symbol" p="src/infra/sortutil.h:119"/>
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:109"/>
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" sev="minor" surface="new-symbol" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:49"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:119"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:49"/>
... [23 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- rows outside it are STILL PRINTED, under an out-of-scope element with a do-not-ack banner, and never gate.
- Under --scope, an out-of-scope row is never written, and an --ack-only that NAMES one refuses (exit 1, naming the rows, writing nothing).
- NO wildcard = a ROOT-ANCHORED path prefix ending on a / boundary (scope=alpha matches alpha/lib.h, never alphabet/lib.h and never a nested src/alpha/ — stricter than the dead-code directory filter, on purpose).

### `--edit-check=SYM`

**Answers:** fast per-symbol post-edit contract check: SYM's param count + publicness NOW vs git HEAD (unchanged/new-symbol/contract-change with was/now), plus its 1-hop callers with any call-site provably incompatible with the NEW arity flagged.

A contract is PER DEFINITION, so a SYM matching several definition sites REFUSES (exit 1) and lists the file:name spellings that pick one — unlike --callers/--uses, this verb may not union overloads and disclose defs=. A .ripwire_notes entry targeting SYM (or its file) rides along as a <note> child, the same row shape --for/--expand surface. PRE-APPLY PREVIEW — add --edit-payload=FILE|- --dry-run to ask the SAME question about bytes that have NOT been written yet. The payload is spliced over SYM's definition span in memory, exactly as --replace-symbol-body would write it; that one file is re-parsed, the call graph rebuilt over the re-derived tree, and the same document emitted with preview="1" plus an <overwrite l= end= bytes=> child holding the CURRENT span the apply would replace, as on disk (over 4 KB: the head, with shown=/capped="1"/elided_lines=) — preview then apply, no Read. Nothing is written, and every other file plus the git HEAD baseline stay the real tree's. Refuses, exit 1, on a payload that is unreadable, empty, oversize or NUL-bearing, on one whose splice raises the file's parse errors, on one that does not define SYM, and on a span the file's current bytes no longer fit. Single-root, and it previews a body REPLACEMENT only.

**Try it**

_Fast per-symbol post-edit contract check vs git HEAD — recorded against a DIRTY tree, so the verdict describes the working copy, not HEAD alone._

```
$ ./build/ripwire . --edit-check=rankGraphTeleport
<!-- ripwire edit-check: SYM's contract (param count + publicness) NOW vs git HEAD — unchanged/new-symbol/contract-change — plus its 1-hop callers. A caller is flagged incompatible="1" when its argument count was reliably counted and NO definition in the folded set could accept it: every one has a FIXED arity that disagrees. A variadic, defaulted or implicit-receiver definition (a Python/Ruby method, whose params counts the self/cls the call site never writes) has no fixed arity and is never flagged. That makes the ARITY half one-sided — a call the compared definitions could accept is never flagged — but it is NOT a proof that the call site binds to THIS definition. Call edges are matched by NAME, so a receiver-qualified call to a same-named callee this tool does not index (a standard-library or third-party method) is measured against the one definition it does index; a clean, compiling tree can therefore carry a nonzero incompatible= with nothing edited at all, and on a widely-shared name it can be most of that name's callers. Read incompatible= as a fact about the tree as it stands — call sites worth OPENING, not a verdict — and status= as a fact about the edit. Warm path hits the qheadsnap/qsnap cache — never a full quality-delta style recompute. defs= is how many DEFINITIONS at this site (same file, same scope, same name — the overload set) are folded into this one contract; a selector matching more than one SITE is refused instead, so defs= only ever counts overloads. params_was and params_now are the MAX over that set on each side (the same MAX the baseline snapshot stores), and publicness is the OR. That MAX has TWO consequences, in opposite directions. It can read like a break and not be one: adding a WIDER overload beside an unchanged one raises params_now with no existing definition altered, so it reports status="contract-change" with incompatible="0" and a def row still carrying the old parameter count — no seen caller breaks. And it can read like safety and not be: REMOVING an overload whose parameter count is BELOW the MAX moves neither number, because the MAX survives on both sides, while the call site that used the removed definition no longer binds. defs_was=/defs_now= is what closes that: the count of definitions sharing this symbol's DEFINITION SITE — same file, same scope, same name — on each side. That is the population the baseline snapshot buckets by, so the two numbers answer the same question and are equal on an unedited tree. A same-named definition in ANOTHER FILE is a different contract and is counted on neither side, so defs_now= agrees with the root's defs= by construction and only defs_was= can move it. status is therefore the join of THREE was-vs-now facts — the params MAX, publicness, and the definition COUNT — and change= names which of them carried it. change= adds broken-callers when a seen caller is also flagged, but never on its own — for the reason stated at the top: incompatible= describes the TREE and status= describes the EDIT, so a headline must not turn on it. RESIDUAL: an overload whose arity changes BELOW the MAX while the COUNT stays the same moves none of the three. The root's incompatible= is the COUNT of flagged callers (a c row's incompatible="1" is the per-caller flag). sites_l= rides on a flagged row only: a c row's p= is where that CALLER is DEFINED, and sites_l= is the ascending LINE list of its call-role reference sites to this name — the lines to open, the same rows the uses verb prints, including the ones whose argument count could not be counted (so sites_l= can be wider than the evidence the flag rests on). Two calls on one line are ONE site. p= is the definition the selector resolved to; when defs is above 1 EVERY folded definition is listed as its own def row (p=, t=, params=), which is what tells a widened single definition apart from an added overload. At defs="1" no def row is emitted: the root's own p=/t= is that definition, and params_now is its parameter count. next= is the one pasteable follow-up: on a contract-change the uses verb on SYM (the call sites), otherwise the test gate on the definition's file. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<edit-check sym="rankGraphTeleport" t="fn" p="src/graph.h:2501" status="unchanged" defs="1" callers="6" incompatible="0" at="5f71cb4fd+dirty" graph_ambiguous="6100" graph_unresolved="3097" counts_floor="1" root="." next="--test-gate=src/graph.h">
<c n="runEval" p="src/eval.h:168"/>
<c n="rankGraph" p="src/graph.h:2542"/>
<c n="anchoredLexicalRank" p="src/graph.h:3091"/>
<c n="churnRankedGraph" p="src/main.cpp:983"/>
<c n="runDefaultMap" p="src/main.cpp:1098"/>
<c n="getIndex" p="src/mcpindex.h:1104"/>
</edit-check>
```

**Shaped by:** `--impact`, `--edit-target-file`, `--slice`, `--at`, `--legend`

**Caveats (stated by the binary):**

- A contract is PER DEFINITION, so a SYM matching several definition sites REFUSES (exit 1) and lists the file:name spellings that pick one — unlike --callers/--uses, this verb may not union overloads and disclose defs=.
- that one file is re-parsed, the call graph rebuilt over the re-derived tree, and the same document emitted with preview="1" plus an <overwrite l= end= bytes=> child holding the CURRENT span the apply would replace, as on disk (over 4 KB: the head, with shown=/capped="1"/elided_lines=) — preview then apply, no Read.
- Refuses, exit 1, on a payload that is unreadable, empty, oversize or NUL-bearing, on one whose splice raises the file's parse errors, on one that does not define SYM, and on a span the file's current bytes no longer fit.

### `--replace-symbol-body=TARGET`

**Answers:** atomically replace one uniquely-resolved definition with the bytes from --edit-payload=FILE|- (ONE trailing newline on the payload folds into the newline already after the span — a heredoc or echo always appends one the span never had;

disclosed as trailing_newline_folded=true; a second one, a deliberate blank line, stays)

**Try it**

_An unknown TARGET refuses and leaves every file byte-identical._

```
$ ./build/ripwire . --replace-symbol-body=DoesNotExist --edit-payload=<scratch>/aux/payload_note.h
(empty)
```

**Shaped by:** `--edit-check`, `--edit-target-file`, `--at`

**Caveats (stated by the binary):**

- atomically replace one uniquely-resolved definition with the bytes from --edit-payload=FILE|- (ONE trailing newline on the payload folds into the newline already after the span — a heredoc or echo always appends one the span never had;

### `--insert-before-symbol=TARGET`

**Answers:** atomically insert the payload immediately before one uniquely-resolved definition

**Try it**

_Insert BEFORE, with --edit-target-file pinning which same-named definition (here unambiguous — the disambiguator is simply honoured)._

```
$ ./build/ripwire . --insert-before-symbol=nonNegativeFloatDescKey --edit-payload=<scratch>/aux/payload_note.h --edit-target-file=src/infra/sortutil.h
{"applied":"insert_before_symbol","symbol":"nonNegativeFloatDescKey","file":"src/infra/sortutil.h","span":{"start":2895,"end":2983},"lines":{"start":74,"end":75},"replaced_bytes":0,"old_file_bytes":8589,"new_file_bytes":8677,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":false,"sep … [line truncated: 742 more bytes on this line]
{"n":"benchAdaptive","p":"bench/bench_radix_ab.cpp:157","l":[162]},
{"n":"radixSortNonNegativeFloatsDesc","p":"src/infra/sortutil.h:105","l":[114]},
{"n":"radixSortByScoreDescId","p":"src/infra/sortutil.h:120","l":[180]}],
"graph_ambiguous":6100,"graph_unresolved":3097,"counts_floor":true},"tests_to_run":[{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/verify_csr.cpp","run":"bash test/a9disclosurecheck.sh"},
{"p":"test/verify_radix.cpp","run":"bash test/greptiercheck.sh"}],
"tests":3,"script_gates_unmodelled":576,"graph_ambiguous":6100,"graph_unresolved":3097,"counts_floor":true,"next":"--uses=src/infra/sortutil.h:nonNegativeFloatDescKey"}
```

### `--insert-after-symbol=TARGET`

**Answers:** atomically insert the payload immediately after one uniquely-resolved definition.

Both inserts PAD the block (newlines only, never removed) so it is separated from the anchor by the same blank-line run the file already uses at that seam; separator_padded=N on the receipt is the count added (0 when the payload carried its own). A payload carrying MORE …[REDACTED:kind] markers than the bytes it would replace already do (a body copied from a redacted serve) refuses: re-fetch that body with --no-redact. TARGET is a symbol name, an @FILE:LINE line-seed (edits the innermost definition enclosing that line — paste the location from a diff hunk or error; the receipt discloses resolved_from_seed, a faulted seed refuses with a specific diagnosis, and --edit-target-file may not accompany a seed), or a freshness-pinned sym# handle emitted by --grep --handles.

**Try it**

_Insert immediately AFTER one uniquely-resolved definition; replaced_bytes=0 because the insert verbs never overwrite. The receipt carries the folded post-edit verification (lines=, edit_check, tests_to_run) so the loop closes in one call._

```
$ ./build/ripwire . --insert-after-symbol=lessByScoreDescId --edit-payload=<scratch>/aux/payload_note.h
{"applied":"insert_after_symbol","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":2375,"end":2463},"lines":{"start":56,"end":58},"replaced_bytes":0,"old_file_bytes":8413,"new_file_bytes":8501,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separator_p … [line truncated: 639 more bytes on this line]
"graph_ambiguous":6100,"graph_unresolved":3097,"counts_floor":true},"tests_to_run":[{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/verify_csr.cpp","run":"bash test/a9disclosurecheck.sh"},
{"p":"test/verify_radix.cpp","run":"bash test/greptiercheck.sh"}],
"tests":3,"script_gates_unmodelled":576,"graph_ambiguous":6100,"graph_unresolved":3097,"counts_floor":true,"next":"bash test/adaptivecutshapecheck.sh"}
```

**Caveats (stated by the binary):**

- Both inserts PAD the block (newlines only, never removed) so it is separated from the anchor by the same blank-line run the file already uses at that seam;
- A payload carrying MORE …[REDACTED:kind] markers than the bytes it would replace already do (a body copied from a redacted serve) refuses: re-fetch that body with --no-redact.
- the receipt discloses resolved_from_seed, a faulted seed refuses with a specific diagnosis, and --edit-target-file may not accompany a seed), or a freshness-pinned sym# handle emitted by --grep --handles.

### `--edit-payload=FILE|-`

**Answers:** required exact byte payload ('-' reads stdin);

empty payloads refuse, never imply deletion

**Try it**

_An unknown TARGET refuses and leaves every file byte-identical._

```
$ ./build/ripwire . --replace-symbol-body=DoesNotExist --edit-payload=<scratch>/aux/payload_note.h
(empty)
```

**Shaped by:** `--edit-check`, `--replace-symbol-body`

**Caveats (stated by the binary):**

- empty payloads refuse, never imply deletion

### `--edit-target-file=PATH`

**Answers:** optional file-path substring disambiguating a same-named definition.

RELATIVE (matched against the indexed spelling) or ABSOLUTE (matched against the file's resolved on-disk path), so the path a receipt or a trace hands you works verbatim. These three CLI verbs reuse the MCP edit engine: freshness hash, lock, pre-rename recheck, fsync, mode preservation and atomic rename. Every refusal leaves the target byte-identical. Success prints a JSON receipt whose span is the POST-EDIT byte range (where the payload now sits in the new file), NOT the region overwritten in the old one — for --replace-symbol-body those two lengths usually differ; replaced_bytes is the count of old bytes actually overwritten (0 for the two insert verbs, which never overwrite), lines={start,end} is that same region as FILE:LINE, and trailing_newline_folded / separator_padded say what the seam rules did to the payload. region={start,end,context,text} is the post-edit region as it is ON DISK (the applied lines plus context=3 each side; over 2 KB it carries head, tail, elided_lines and capped=true) and blob_sha is the git blob id of the written bytes (== git hash-object FILE) — the Read an agent would make to see what landed is already in hand. The receipt also carries the POST-EDIT VERIFICATION the tool would otherwise tell you to run: edit_check={status,callers,incompatible,sites} — the same answer --edit-check=FILE:SYM gives, sites naming each broken caller's call LINES — and tests_to_run, the same rows --affected=FILE gives, run recipe included; and exactly ONE next= (a contract-change with broken callers: --uses=FILE:SYM; else the first run= recipe; else --test-gate=FILE; under --no-post-check: --edit-check=FILE:SYM). Edit, see what landed, verify and find the tests to run is ONE call.

**Try it**

_Insert BEFORE, with --edit-target-file pinning which same-named definition (here unambiguous — the disambiguator is simply honoured)._

```
$ ./build/ripwire . --insert-before-symbol=nonNegativeFloatDescKey --edit-payload=<scratch>/aux/payload_note.h --edit-target-file=src/infra/sortutil.h
{"applied":"insert_before_symbol","symbol":"nonNegativeFloatDescKey","file":"src/infra/sortutil.h","span":{"start":2895,"end":2983},"lines":{"start":74,"end":75},"replaced_bytes":0,"old_file_bytes":8589,"new_file_bytes":8677,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":false,"sep … [line truncated: 742 more bytes on this line]
{"n":"benchAdaptive","p":"bench/bench_radix_ab.cpp:157","l":[162]},
{"n":"radixSortNonNegativeFloatsDesc","p":"src/infra/sortutil.h:105","l":[114]},
{"n":"radixSortByScoreDescId","p":"src/infra/sortutil.h:120","l":[180]}],
"graph_ambiguous":6100,"graph_unresolved":3097,"counts_floor":true},"tests_to_run":[{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/verify_csr.cpp","run":"bash test/a9disclosurecheck.sh"},
{"p":"test/verify_radix.cpp","run":"bash test/greptiercheck.sh"}],
"tests":3,"script_gates_unmodelled":576,"graph_ambiguous":6100,"graph_unresolved":3097,"counts_floor":true,"next":"--uses=src/infra/sortutil.h:nonNegativeFloatDescKey"}
```

**Shaped by:** `--insert-after-symbol`

**Caveats (stated by the binary):**

- optional file-path substring disambiguating a same-named definition.
- replaced_bytes is the count of old bytes actually overwritten (0 for the two insert verbs, which never overwrite), lines={start,end} is that same region as FILE:LINE, and trailing_newline_folded / separator_padded say what the seam rules did to the payload.
- over 2 KB it carries head, tail, elided_lines and capped=true) and blob_sha is the git blob id of the written bytes (== git hash-object FILE) — the Read an agent would make to see what landed is already in hand.

### `--no-post-check`

**Answers:** skip that folded verification (the index refresh it needs is the one the next verb call would pay for anyway;

pass this when you are about to edit again immediately). The MCP spelling is post_check:false. Single-root only.

**Try it**

_The opt-out: the same insert with the folded verification skipped — lines= still rides (it is free), edit_check/tests_to_run do not, and the two pasteable commands stay on stderr._

```
$ ./build/ripwire . --insert-after-symbol=lessByScoreDescId --edit-payload=<scratch>/aux/payload_note.h --no-post-check
{"applied":"insert_after_symbol","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":2375,"end":2463},"lines":{"start":56,"end":58},"replaced_bytes":0,"old_file_bytes":8501,"new_file_bytes":8589,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separator_p … [line truncated: 570 more bytes on this line]
```

**Shaped by:** `--edit-target-file`

**Caveats (stated by the binary):**

- skip that folded verification (the index refresh it needs is the one the next verb call would pay for anyway;

### `--edit-plan=FILE`

**Answers:** versioned JSON multi-edit transaction: {version:1, edits:[{op,target,file?,payload}]};

op is one of replace_symbol_body, insert_before_symbol, insert_after_symbol each target takes the same forms as TARGET above (a name, an @FILE:LINE seed, a handle)

**Try it**

_Neither --dry-run nor --apply: the mode is explicit, so this refuses._

```
$ ./build/ripwire . --edit-plan=<scratch>/aux/edit_plan.json
(empty)
```

### `--dry-run | --apply`

**Answers:** the plan's explicit mode: --dry-run preflights and prints the receipt without writing, --apply commits;

exactly one of the two is required. Payload paths are relative to the plan file and CONFINED to its directory: a path resolving outside it (an absolute path, a '..' escape, or a symlink pointing out) refuses, naming the path it resolved to, and the receipt's payload_path shows what each op will READ. Every target/payload/span is preflighted before any write; overlaps refuse. Apply holds sorted per-file locks and atomically renames each file, re-verifying EACH file's bytes immediately before ITS OWN write (recheck_before_each_write in the receipt) so a non-cooperating external writer is detected rather than clobbered. Prior files roll back on a later write failure or such a detection; the message says which happened and how many files it restored, and ends with the ONE call that shows the state — next: a git diff (exit-code mode) over the plan's files from <root>; exit 0 IS the claim, checked against git. A crash between file renames remains a disclosed limit.

**Try it**

_The same plan committed: per-file locks, re-verify-before-write, atomic rename, rollback on a later failure._

```
$ ./build/ripwire . --edit-plan=<scratch>/aux/edit_plan.json --apply
{"schema":"ripwire.edit-plan/v1","mode":"apply","edits":1,"files":1,"callers_union":4,"graph_ambiguous":6100,"graph_unresolved":3097,"counts_floor":true,"applied":1,"atomic_files":1,"atomic_scope":"per-file","rollback_on_write_error":true,"recheck_before_each_write":true,"multifile_crash_atomic":fal … [line truncated: 503 more bytes on this line]
{"n":"benchAdaptive","p":"bench/bench_radix_ab.cpp:157","l":[162]},
{"n":"radixSortNonNegativeFloatsDesc","p":"src/infra/sortutil.h:107","l":[116]},
{"n":"radixSortByScoreDescId","p":"src/infra/sortutil.h:122","l":[182]}],
"graph_ambiguous":6100,"graph_unresolved":3097,"counts_floor":true}}]}
```

**Shaped by:** `--edit-check`

**Caveats (stated by the binary):**

- Payload paths are relative to the plan file and CONFINED to its directory: a path resolving outside it (an absolute path, a '..' escape, or a symlink pointing out) refuses, naming the path it resolved to, and the receipt's payload_path shows what each op will READ.
- A crash between file renames remains a disclosed limit.

### `--safe-delete=SYM`

**Answers:** "can I delete this?" — ONE call composing signals the tool already computes for one already-resolved SYM: 1-hop callers=, the transitive --impact blast radius (impact_reaches=), every --uses read/write/import/call/extends site (uses=), how much of the blast radius the tested= lens covers (tested_self=/radius_tested=/radius_untested=), and --dead-code's own high-confidence shape at defs=1 (dead_code_candidate=).

ambiguous_callers= names callers whose own calls include an ambiguously-resolved one (g.ambOut) — a caveat, not a count of proven-wrong edges. FACTS only: risk= names what was found — none-found (zero callers AND zero uses), untested-radius (a radius exists and none of it is test-covered), or uses-exist (a radius exists and some of it is tested) — never a go/no-go verdict.

**Try it**

_Unknown-symbol refusal shape for --safe-delete._

```
$ ./build/ripwire . --safe-delete=DoesNotExist
(empty)
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- ambiguous_callers= names callers whose own calls include an ambiguously-resolved one (g.ambOut) — a caveat, not a count of proven-wrong edges.
- FACTS only: risk= names what was found — none-found (zero callers AND zero uses), untested-radius (a radius exists and none of it is test-covered), or uses-exist (a radius exists and some of it is tested) — never a go/no-go verdict.

### `--slice=SYM[:VAR]`

**Answers:** NAME-BASED intra-procedural def-use slice of variable VAR inside the ONE uniquely-resolved definition SYM (statement-level def-use edges as a queryable primitive — the ARISE result, arXiv:2605.03117).

One <s l= k= t=> row per line touching VAR, source order: k=def|use|both| scope = a Python global/nonlocal statement, neither read nor write; t=param|decl| assign|call-arg|read|global|nonlocal = the strongest role on the line; CDATA = the trimmed source line; defs=/uses= count occurrences. JS/TS destructuring binders (`const {a, b} = o`, `[x] = arr`, destructured parameters) are locals whose def is the pattern line. A write hidden behind a call — receiver mutation, a by-reference/out-parameter, a function-like macro — is a use, never a def (stated in the legend). Bare --slice=SYM lists the sliceable locals (<v n= l= t=/> rows) so a caller can pick VAR. LIMITS in the legend, not implied: no alias analysis. REACHING DEFINITIONS are FLOW-SENSITIVE inside the definition for C-family and Python (root reach="cfg": a def is killed by the next unconditional def on every path, defs join at if/elif/else, switch, loop back-edge, try/finally, for/while-else, match, #ifdef merges) and source-order for JS/TS/Go/Java/Rust (reach="linear", nothing joins); every use row carries rd= (the lines of the defs that reach it, "-" = none). The unit is the STATEMENT (uses read the entering state, defs apply after); a nested lambda/def body, ?:, short-circuit fold into their statement, goto is untracked, global/nonlocal is tracked like a local — each disclosed in the legend. Block scopes ARE separated: a name declared twice in the definition is two variables, each row of a shadowed name carries b= (the declaration line it binds to), the root bindings=, the inventory one <v> per binding. SYM matching several definition sites REFUSES (exit 1) listing the file:name spellings that pick one, like --edit-check. Served: C/C++/ObjC (+CUDA/Metal), Python, JS/TS, Go, Java, Rust — other indexed languages refuse loudly (never an empty success). Single-root only. PREPROCESSOR (C-family): a `#if 0` body and the `#else` of `#if 1` are DEAD — dropped, the line count disclosed as preproc_rows=; every other conditional region (`#ifdef X`, `#ifndef X`, `#if defined(X)`, `#if EXPR`) is build-dependent and cannot be decided without the build's macro set, so its rows are KEPT and flagged pp="1", and a pp def never hides the unconditional def before it in a flow (both are reaching). LINE-SEEDED: --at=FILE:LINE beside --slice (or --slice=@FILE:LINE) is the ARISE (file, line[, variable]) seed — the definition sliced is the innermost one enclosing the line (a seed narrows an otherwise-ambiguous SYM; a seed enclosed by none of SYM's definitions refuses naming both). A seed line naming exactly ONE sliceable local pre-picks it (disclosed: seed= var_from="seed"); zero or several serve the inventory with seed_vars= and the candidate rows marked seed="1", never a guess. A plain identifier spec beside --at reads as the seed's VARIABLE (--slice=VAR --at=src/f.cpp:12). SINCE: --since=REV|DATE beside --slice=SYM:VAR adds a <since> child carrying the DEPENDENCE diff of that variable against the committed tree at REV — one <sd> row per added or removed STATEMENT of the variable, one <se> row per added or removed def-use edge. The unit is the STATEMENT and the key is the ROLE, never the line and never the text, so a re-wrap, a comment edit, an insertion above the definition, and a rename of an unrelated local all come back EMPTY. Empty means no def-use edge of that variable moved, never that the commit changed nothing — git diff answers the second question. status= names each way the symbol can be absent at REV, and comparable="0" says outright that no comparison was made and the emptiness is not evidence. Refused on the bare inventory: a dependence diff needs a seed variable.

**Try it**

_Bare --slice=SYM: the INVENTORY of sliceable locals (<v n= l= t=/>), so a caller can pick VAR._

```
$ ./build/ripwire . --slice=rankGraphTeleport
<!-- ripwire slice: NAME-BASED intra-procedural def-use slice of one variable inside ONE resolved definition (ARISE, arXiv:2605.03117). ROWS: one <s> per LINE touching VAR, source order — k= def|use|both|scope (both = the line writes AND reads it, `x += y`; scope = a Python global/nonlocal statement: neither read nor write, it introduces the name and never anchors a flow), t= the strongest role on the line (param > decl > assign > call-arg > read > global/nonlocal), CDATA = the trimmed line. Bare slice=SYM lists the sliceable locals: <v n= l= t=/> per BINDING at its declaration line, vars= their count. COUNTS: counts="as-classified" — not the graph verbs' counts_floor= — defs=, uses=, vars= and steps= are exact counts of what this classifier ROWED, neither floors nor totals of the program's truth: LOW where a write hides behind a call (limit 2), HIGH where a rowed occurrence is not this variable's (a pp="1" row, or a same-spelled member/attribute a grammar exposes as a bare identifier — Python/Java `o.v`). LIMITS, stated not implied: (1) reach= on the root names the REACHING-DEFINITION rule behind rd=: cfg (C-family, Python) = flow-sensitive — the next unconditional def of a binding KILLS on every path; defs JOIN at if/elif/else, switch (cases fall through), a loop's back-edge, try handlers/finally, for/while-else, match, #ifdef; return/break/continue/throw/raise end a path. linear (JS/TS, Go, Java, Rust) = source order, nothing joins. rd= on a use row = the lines of the defs reaching it (- = none); flow and since edges are this same table. The UNIT is the STATEMENT: uses read the state entering it, its defs apply after (x += 1 reads then kills). NOT branched, per construct: ?:, short-circuit, a conditional expression/comprehension, a lambda/closure/nested def/class body fold into their statement (a def inside applies there, once); goto falls through, untracked; global/nonlocal is tracked like a local (outside writes invisible); a try handler sees the state before every statement of its innermost try body; no alias analysis — a pointer/reference alias is invisible. (2) A WRITE HIDDEN BEHIND A CALL IS NOT A DEF: receiver mutation (v.push_back(x), buf.append(s)) rows k="use" t="read", and a write through an ARGUMENT — a by-reference/pointer parameter, an out-parameter, a function-like macro (SETIT( m )) — rows k="use" t="call-arg", because proving either writes needs the callee's body or the macro's expansion, which this slicer lacks; a false def is worse than a missing one (the flow walk stops at the NEXT def), so it declines to guess — such a variable reports defs= as its introduction alone and a flow of steps="0": no provable edge, not "never written". (3) BLOCK SCOPES ARE SEPARATED: a name declared more than once inside the definition is that many variables; an occurrence binds to the innermost enclosing scope whose declaration precedes it (blocks, loop/if/switch heads, catch clauses, lambdas/closures, per family; JS/TS let/const per block, var per function; Go `v := v+1` and Rust `let v = v+1` read the previous binding in their own initializer; Python is function-scoped — one binding per name, comprehension/lambda scopes not separated). A shadowed seed carries bindings= on the root and b= on every row — the declaration line it binds to; b="0" = no declaration inside the definition binds it (an outer name, or a use before its declaration). (4) PREPROCESSOR (C-family): a conditional region starting inside the definition is decided only by its literal — the body of `#if 0` and the `#else` of `#if 1` are dead, their rows dropped and counted as preproc_rows= (absent when zero); every other conditional (`#ifdef`, `#ifndef`, `#if defined(X)`, `#if EXPR`, `#elif`) is build-dependent: its rows are kept and flagged pp="1", and in a flow a pp def does not kill the reach of the unconditional def before it (both are emitted); macro names in directive text are never occurrences. (5) JS/TS destructuring binders (`const { x, y: yy, z = 3, ...rest } = o`, `[a, b] = arr`, destructured parameters, for-of patterns) are locals defined at the pattern line; a default's right side and a computed key are reads. (6) A reserved word is never an occurrence (a degraded-parse artifact); slicing one refuses like any unknown VAR. (7) Intra-procedural: rows never cross into callees/callers (callers/uses give that half). Served: C/C++/ObjC (+CUDA/Metal), Python, JS/TS, Go, Java, Rust — any other language refuses loudly, never an empty success. -->
<slice sym="rankGraphTeleport" p="src/graph.h:2501" t="fn" lang="cpp" vars="14" at="5f71cb4fd+dirty" root="." counts="as-classified">
<v n="alpha" l="2501" t="param"/>
<v n="g" l="2501" t="param"/>
<v n="p" l="2501" t="param"/>
<v n="pw" l="2504" t="decl"/>
<v n="N" l="2505" t="decl"/>
<v n="teleport" l="2506" t="decl"/>
<v n="rankDouble" l="2507" t="decl"/>
<v n="run" l="2508" t="decl"/>
<v n="teleportMass" l="2511" t="decl"/>
<v n="value" l="2512" t="decl"/>
<v n="inverseMass" l="2518" t="decl"/>
<v n="value" l="2519" t="decl"/>
... [3 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-redact`, `--since`, `--slice-flow`, `--slice-depth`, `--at`

**Caveats (stated by the binary):**

- A write hidden behind a call — receiver mutation, a by-reference/out-parameter, a function-like macro — is a use, never a def (stated in the legend).
- LIMITS in the legend, not implied: no alias analysis.
- SYM matching several definition sites REFUSES (exit 1) listing the file:name spellings that pick one, like --edit-check.

### `--slice-flow=back|fwd|both`

**Answers:** TRANSITIVE cross-statement data-flow slice (modifies --slice=SYM:VAR;

refused alone or on the bare inventory — a flow needs a seed variable). Follows VALUE FLOW over reaching-definition def-use edges — a use of v reaches the last def of v in source order before it — by bounded BFS from the seed variable, the ARISE paper's own slicer semantics (arXiv:2605.03117: seed + direction, bounded BFS, stops at the function boundary; the inter-procedural half stays with --callers/--impact by the paper's own design). back = statements whose values feed the seed; fwd = statements the seed's value reaches; both = the union. Flow rows are <s l= k= t= v= d= f=>: v= the variable at that step, d= BFS depth (seed rows are depth 0), f= the line the step was reached from. steps= counts flow rows; depth= states the bound in force. LIMITS (in the legend too): name-based, no alias analysis, line-granular ROWS (a multi-statement line merges) over statement-anchored CHAINING (a multi-LINE statement chains as ONE unit), a shadowed name's bindings walk separately (never into each other's block), data dependence only — no control dependence (the guard deciding whether a def executes is never a row).

**Try it**

_Forward flow: which statements the seed's value reaches, at the default depth bound._

```
$ ./build/ripwire . --slice=rankGraphTeleport:teleport --slice-flow=fwd
<!-- ripwire slice: NAME-BASED intra-procedural def-use slice of one variable inside ONE resolved definition (ARISE, arXiv:2605.03117). ROWS: one <s> per LINE touching VAR, source order — k= def|use|both|scope (both = the line writes AND reads it, `x += y`; scope = a Python global/nonlocal statement: neither read nor write, it introduces the name and never anchors a flow), t= the strongest role on the line (param > decl > assign > call-arg > read > global/nonlocal), CDATA = the trimmed line. Bare slice=SYM lists the sliceable locals: <v n= l= t=/> per BINDING at its declaration line, vars= their count. COUNTS: counts="as-classified" — not the graph verbs' counts_floor= — defs=, uses=, vars= and steps= are exact counts of what this classifier ROWED, neither floors nor totals of the program's truth: LOW where a write hides behind a call (limit 2), HIGH where a rowed occurrence is not this variable's (a pp="1" row, or a same-spelled member/attribute a grammar exposes as a bare identifier — Python/Java `o.v`). LIMITS, stated not implied: (1) reach= on the root names the REACHING-DEFINITION rule behind rd=: cfg (C-family, Python) = flow-sensitive — the next unconditional def of a binding KILLS on every path; defs JOIN at if/elif/else, switch (cases fall through), a loop's back-edge, try handlers/finally, for/while-else, match, #ifdef; return/break/continue/throw/raise end a path. linear (JS/TS, Go, Java, Rust) = source order, nothing joins. rd= on a use row = the lines of the defs reaching it (- = none); flow and since edges are this same table. The UNIT is the STATEMENT: uses read the state entering it, its defs apply after (x += 1 reads then kills). NOT branched, per construct: ?:, short-circuit, a conditional expression/comprehension, a lambda/closure/nested def/class body fold into their statement (a def inside applies there, once); goto falls through, untracked; global/nonlocal is tracked like a local (outside writes invisible); a try handler sees the state before every statement of its innermost try body; no alias analysis — a pointer/reference alias is invisible. (2) A WRITE HIDDEN BEHIND A CALL IS NOT A DEF: receiver mutation (v.push_back(x), buf.append(s)) rows k="use" t="read", and a write through an ARGUMENT — a by-reference/pointer parameter, an out-parameter, a function-like macro (SETIT( m )) — rows k="use" t="call-arg", because proving either writes needs the callee's body or the macro's expansion, which this slicer lacks; a false def is worse than a missing one (the flow walk stops at the NEXT def), so it declines to guess — such a variable reports defs= as its introduction alone and a flow of steps="0": no provable edge, not "never written". (3) BLOCK SCOPES ARE SEPARATED: a name declared more than once inside the definition is that many variables; an occurrence binds to the innermost enclosing scope whose declaration precedes it (blocks, loop/if/switch heads, catch clauses, lambdas/closures, per family; JS/TS let/const per block, var per function; Go `v := v+1` and Rust `let v = v+1` read the previous binding in their own initializer; Python is function-scoped — one binding per name, comprehension/lambda scopes not separated). A shadowed seed carries bindings= on the root and b= on every row — the declaration line it binds to; b="0" = no declaration inside the definition binds it (an outer name, or a use before its declaration). (4) PREPROCESSOR (C-family): a conditional region starting inside the definition is decided only by its literal — the body of `#if 0` and the `#else` of `#if 1` are dead, their rows dropped and counted as preproc_rows= (absent when zero); every other conditional (`#ifdef`, `#ifndef`, `#if defined(X)`, `#if EXPR`, `#elif`) is build-dependent: its rows are kept and flagged pp="1", and in a flow a pp def does not kill the reach of the unconditional def before it (both are emitted); macro names in directive text are never occurrences. (5) JS/TS destructuring binders (`const { x, y: yy, z = 3, ...rest } = o`, `[a, b] = arr`, destructured parameters, for-of patterns) are locals defined at the pattern line; a default's right side and a computed key are reads. (6) A reserved word is never an occurrence (a degraded-parse artifact); slicing one refuses like any unknown VAR. (7) Intra-procedural: rows never cross into callees/callers (callers/uses give that half). Served: C/C++/ObjC (+CUDA/Metal), Python, JS/TS, Go, Java, Rust — any other language refuses loudly, never an empty success. -->
<!-- slice-flow: TRANSITIVE cross-statement data-flow — bounded BFS from the seed variable over reaching-definition edges: a use reaches exactly the defs its rd= names (limit 1's reach= rule; the ARISE slicer's rule; stops at the function boundary like the paper's). flow= back = statements whose values feed the seed | fwd = statements the seed's value reaches | both = the union (backward first, deduplicated). Seed rows are depth 0 in the v1 shape; each FLOW row adds v= the variable at that step, d= its BFS depth, f= the line it was reached FROM (b= as in v1 when v= is shadowed); rows order by (d=, l=, v=). steps= counts flow rows; depth= is the bound in force (default 8, slice-depth sets it); flow_truncated="1" = the bound suppressed at least one row — bounded here, not proven complete. steps="0" = no PROVABLE edge from this seed — its commonest cause is limit (2): receiver mutation leaves no def to anchor on — read the rows, not just the count. EXTRA LIMITS: rows are line-granular (a multi-statement line merges and may over-connect) while chaining is statement-anchored (a statement spanning lines chains as ONE unit keyed on its first line); data dependence only — no control dependence: the guard (if/loop) deciding whether a def executes is never a row. -->
<slice sym="rankGraphTeleport" p="src/graph.h:2501" t="fn" lang="cpp" var="teleport" defs="1" uses="3" reach="cfg" flow="fwd" depth="8" steps="7" at="5f71cb4fd+dirty" root="." counts="as-classified">
<s l="2506" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="2512" k="use" t="read" rd="2506">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="2519" k="use" t="read" rd="2506">
<![CDATA[for( double& value : teleport )]]>
</s>
<s l="2524" k="use" t="call-arg" rd="2506">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
... [23 more line(s); run it to see the whole thing]
```

**Shaped by:** `--slice-depth`

**Caveats (stated by the binary):**

- refused alone or on the bare inventory — a flow needs a seed variable).

### `--slice-depth=N`

**Answers:** the --slice-flow BFS depth bound, 1..32 (default 8, always disclosed as depth= on the root).

A bound that cuts a live frontier is disclosed as flow_truncated="1" — a short slice means "bounded here", never "nothing further exists". Refused without --slice-flow.

**Try it**

_--slice-depth without --slice-flow is refused loudly rather than silently ignored._

```
$ ./build/ripwire . --slice-depth=3
(empty)
```

**Caveats (stated by the binary):**

- A bound that cuts a live frontier is disclosed as flow_truncated="1" — a short slice means "bounded here", never "nothing further exists".
- Refused without --slice-flow.

### `--at=FILE:LINE`

**Answers:** the ENCLOSING-DEFINITION CHAIN at one location (1-based line), outermost->innermost — for when you hold a compiler error / diff hunk / stack frame, not a name.

<s n= t= l= el=/> rows, indexed definitions only; sym= names the innermost. The SAME seed composes into any SYM selector as @FILE:LINE (--callers=@src/f.cpp:120, --expand=@..., --edit-check=@..., --slice=@FILE:LINE:VAR, --replace-symbol-body=@... and the other edit TARGETs, ...) and resolves to that innermost definition — the no-name half of the file:line:name grammar. The NAME-scan verbs --mentions/--owners rebind a seed to that definition's name and answer, disclosing sym=. Beside --slice, the at flag is that verb's LINE SEED instead of a competing verb (see --slice). A malformed seed, an ambiguous or unmatched path, a line past EOF, a line inside no indexed definition, or two disjoint definitions sharing the line each REFUSE with a specific diagnosis (exit 1) — never a guess, never an empty chain.

**Try it**

_Hold a LOCATION, not a name: the enclosing-definition chain at FILE:LINE (a compiler error, a diff hunk, a stack frame), outermost -> innermost._

```
$ ./build/ripwire . --at=src/graph.h:1148
<!-- ripwire at: the ENCLOSING-DEFINITION CHAIN at one FILE:LINE seed. p= the resolved file, l= the 1-based seed line, sym= the innermost enclosing definition's name (what the same seed resolves to in a selector position), chain= the row count. Rows are INDEXED definitions only, outermost first, innermost last: n= the definition's name, t= its kind tag, l= its own start line, el= its end line (1-based, inclusive). A namespace or any construct the index does not carry is NOT a row, so an outer scope can be absent rather than misnamed; a seed line inside no indexed definition is refused, never served as an empty chain. The same seed composes into any SYM selector as @FILE:LINE (callers, callees, impact, around, expand, uses, edit-check, slice, safe-delete, path, connect) and resolves to the innermost row. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<at p="src/graph.h" l="1148" sym="buildGraph" chain="1" root=".">
<s n="buildGraph" t="fn" l="962" el="2455"/>
</at>
```

**Shaped by:** `--slice`

**Caveats (stated by the binary):**

- the ENCLOSING-DEFINITION CHAIN at one location (1-based line), outermost->innermost — for when you hold a compiler error / diff hunk / stack frame, not a name.
- A malformed seed, an ambiguous or unmatched path, a line past EOF, a line inside no indexed definition, or two disjoint definitions sharing the line each REFUSE with a specific diagnosis (exit 1) — never a guess, never an empty chain.

### `--pr-context[=BASEREF]`

**Answers:** no-LLM review-evidence bundle for the diff (working-tree, or vs BASEREF): per changed file, its symbols + callers + blast radius + affected tests + co-change partners + owners.

The bundle is BUDGETED by default (8000 tokens, budget_default="1" on the root; --token-budget=N or --max-tokens=N set it explicitly): per-file structural counts survive first, the deep detail (caller/co-change lists, per-symbol rows) trims deepest-first, truncated= names what was dropped and est_tokens= reports the fit. When even the structural floor of every changed file exceeds the budget, the FILES (blast-radius order) are windowed: shown=/capped=/total=/ next_offset= disclose the cut and next= pastes the next page (--offset=N / --limit=N window them explicitly). ANCHORING: the BASEREF form diffs against merge-base(BASEREF,HEAD), never BASEREF's tip — "what did THIS work change since it forked", not "how do the two trees differ today". base_moved= counts the paths BASEREF moved since the fork that this work never touched (excluded, not silently); anchor="ref-tip-two-dot" = no merge-base (unrelated history). direction= always names the SIDE you are reading, and a no-ref-work row fires when BASEREF's tip IS the merge base -- it carries no divergent work, so every row is HEAD's.

**Try it**

_No-LLM review-evidence bundle for the working-tree diff — recorded against a DIRTY tree, so it is populated rather than empty._

```
$ ./build/ripwire . --pr-context
<!-- ripwire pr-context: no-LLM review-evidence bundle per changed file — defined symbols, their callers, blast radius (transitive dependents), affected tests, co-change partners not in the diff, and owners. base=working-tree. skipped_mode_only=diffs that changed a file's MODE and nothing else (e.g. chmod) excluded from the changed set; a pure RENAME is content-identical too but is NOT excluded — it is a changed file, listed at its new path. files= means two different things by DEPTH here and is deliberately not renamed (15 consumers read the root one): on the ROOT it is the CHANGED file count; on each <impact/> child it is the distinct files dependents= reaches (changed + non-changed), so dependents="0" implies files="0" and vice versa — never an impossible-looking dependents>0/files=0. files_other= on the same <impact/> is the non-changed subset (a changed file's dependents inside OTHER changed files have no <f> row of their own — they are already shown as their own <file> section); it is NOT the <f> row count — see the row-cap sentence below. Files are ordered by BLAST RADIUS (transitive dependents descending, path breaking ties), not alphabetically. sections= on changed-symbols counts a doc file's headings, collapsed into that number instead of one callers-zero row each; count= still counts every INDEXED symbol, sections included, so count minus sections is the number of rows that follow. Every nested list below is a TOP-N subset of its element's own total, fixed per element (impact <f> at 20, per-symbol <caller> at 12, cochange <partner> at 12, tests <test> at 40, owners <author> at 5 — the L0 defaults; max-tokens only lowers these further via the trim ladder, nothing raises them past L0): each capped element carries its own shown=/capped= pair so the cut is never silent — for the untrimmed list use impact=SYM/callers=SYM (blast radius/callers), affected=FILE or situ (tests), cochange (partners), or owners (authors) instead. direction= names which SIDE this bundle reviews (worktree-since-head, head-since-fork, head-since-ref-tip); a no-ref-work row says the base ref's tip IS the merge base, i.e. it carries no divergent work of its own. deterministic. BUDGET: the bundle is budgeted by default — budget_tokens= is the ceiling in force (8000 unless token-budget/max-tokens set it; budget_default=1 says the default applied); est_tokens= prices the WHOLE document this bundle emits, this legend included, at the map's markup rate of 2.50 bytes per token, and IS the number the ladder fits, so recounting the delivered bytes reproduces it; trim_level=/truncated= what the ladder dropped. When even the structural floor of every changed file exceeds it, the FILES are windowed in blast-radius order: shown= of files=, capped=1 with total=/has_more=/next_offset=/offset=/limit= (limit=0 = the default window), and next= is the one pasteable follow-up (the next page). truncated= carrying budget-floor-exceeded means the smallest document this bundle can render is STILL over budget_tokens= — including on a clean tree, whose whole document is this legend and has no ladder to descend; est_tokens= is then the honest ceiling, never a silent overshoot. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<pr-context base="working-tree" root="." direction="worktree-since-head" files="0" skipped_mode_only="0" budget_tokens="8000" est_tokens="2126" trim_level="0" truncated="none" budget_default="1" at="5f71cb4fd+dirty" graph_ambiguous="6100" graph_unresolved="3097" counts_floor="1">
<!-- no changed files in the index (clean tree, or the diff touched only non-indexed files) -->
</pr-context>
```

**Shaped by:** `--test-gate`, `--from-trace`, `--limit`, `--map-diff`, `--index-out`

**Caveats (stated by the binary):**

- --token-budget=N or --max-tokens=N set it explicitly): per-file structural counts survive first, the deep detail (caller/co-change lists, per-symbol rows) trims deepest-first, truncated= names what was dropped and est_tokens= reports the fit.
- When even the structural floor of every changed file exceeds the budget, the FILES (blast-radius order) are windowed: shown=/capped=/total=/ next_offset= disclose the cut and next= pastes the next page (--offset=N / --limit=N window them explicitly).
- ANCHORING: the BASEREF form diffs against merge-base(BASEREF,HEAD), never BASEREF's tip — "what did THIS work change since it forked", not "how do the two trees differ today".

### `--merge-scout=REF[,REF...]`

**Answers:** read-only cross-branch overlap: for each REF, the symbols it changed vs its merge-base with HEAD (git-archive TEMP copies — never checked out, never mutates a ref);

the dirty working tree joins as an implicit extra arm. Pairwise: a changed symbol on TWO arms is a same-symbol conflict, two arms touching different symbols in the same file is a textual risk; <landing order=...> is the fewest-conflicts-first greedy land order (ties: ref name asc). An unresolvable REF refuses loudly (exit 1, names the ref) before any archive work. ANCHORING: every arm is diffed against its OWN merge-base with HEAD, never against live HEAD — a file an arm never opened can never show up because the live line moved. head_conflicts= is what that anchor hides, kept as its own row class: symbols this arm changed that the LIVE LINE also changed since the arm forked (HEAD is not an arm, so no pairwise comparison can see it). Single-root only.

**Try it**

_Pairwise cross-arm conflict sites + suggested landing order (any committish sharing a merge base with HEAD works as an arm; one that does not is reported ok="0", never compared)._

```
$ ./build/ripwire . --merge-scout=HEAD~2,HEAD~1
<!-- ripwire merge-scout: read-only cross-branch overlap for 3 arm(s) — same-symbol change on two arms = conflict, same-file/different-symbol = textual risk. landing = fewest-conflicts-first greedy (ties: ref name asc). Every tree is a git-archive TEMP COPY (read-only); the real working tree/refs are never touched. ANCHORING: every arm is diffed against its OWN merge base with HEAD (the working tree arm against HEAD itself), never against live HEAD — so a file an arm never opened can never appear here just because the live line moved. head_conflicts= is the one thing that anchor hides, kept as its own row class: symbols this arm changed that the LIVE LINE also changed since the arm forked, a merge fight no pairwise ARM comparison can see because HEAD is not an arm. A row carrying anchoring=file-level is a whole-file fallback for a file with zero real-body symbols (no tree-sitter symbol spans it) — counted and conflict-checked like any other row, just not attributed to a symbol inside it. at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit (head= is the same commit, bare sha, kept for compatibility). -->
<merge-scout arms="3" head="5f71cb4fd" at="5f71cb4fd+dirty">
<arm ref="HEAD~2" base="96298c1da" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<arm ref="HEAD~1" base="2183ab87d" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<arm ref="working-tree" base="5f71cb4fd" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<pair a="HEAD~2" b="HEAD~1" conflicts="0" risks="0"/>
<pair a="HEAD~2" b="working-tree" conflicts="0" risks="0"/>
<pair a="HEAD~1" b="working-tree" conflicts="0" risks="0"/>
... [2 more line(s); run it to see the whole thing]
```

**Shaped by:** `--plan-lanes`, `--plan`

**Caveats (stated by the binary):**

- read-only cross-branch overlap: for each REF, the symbols it changed vs its merge-base with HEAD (git-archive TEMP copies — never checked out, never mutates a ref);
- An unresolvable REF refuses loudly (exit 1, names the ref) before any archive work.
- ANCHORING: every arm is diffed against its OWN merge-base with HEAD, never against live HEAD — a file an arm never opened can never show up because the live line moved.

### `--plan-lanes=N --task=GOAL`

**Answers:** PRE-HOC lane plan: BEFORE a line is written, if this task is split across N isolated worktrees (N=2..16), which lanes would COLLIDE and in what order should they land.

Where --merge-scout says "these branches already conflict", this says "these lanes WOULD conflict if assigned this way" — no ref to resolve, no archive, no re-ingest. JSON on stdout, always (redirect it: > .ripwire_lanes.json); ripwire writes no file. Exit 0 whenever a plan was produced, INCLUDING when conflicts are predicted (conflicts are data, and the landing order exists to handle them); exit 1 only for refusals. A claim keys on path+scope+name, never on id= (id degrades to a bare NAME when no scope was captured, so free functions in different files would collide); id= is carried per row for addressability, null when it would be bare, with id_addressable saying so. Three separate pair classes: conflicts[] (same claim key on both lanes — git will fight), same_file_risk[] (different keys, same file, aggregated per file), contract_touch[] (one lane's claim sits in another's blast radius — an adaptation, NOT a merge conflict). The conflict test runs on CLAIMS, never on blast radii. warnings[] carries every honest limit in band with a stable code. Each lane also carries an advisory execution object: the current Codex model + reasoning effort, selecting rule, exact structural signals and caveats under policy=codex-lane/v1. basis=structural-only: it does NOT understand task semantics, runtime behavior or security sensitivity; the orchestrator must override those cases. Single-root only. AUTO-CARVE SPLITS THE RANKED SURFACE, NOT YOUR SENTENCE: if your task has enumerable parts, use --brief and write one line per part.

**Try it**

_Out-of-range refusal shape for the lane count._

```
$ ./build/ripwire . --plan-lanes=99 --task=x
(empty)
```

**Shaped by:** `--legend`, `--json`

**Caveats (stated by the binary):**

- Exit 0 whenever a plan was produced, INCLUDING when conflicts are predicted (conflicts are data, and the landing order exists to handle them);
- A claim keys on path+scope+name, never on id= (id degrades to a bare NAME when no scope was captured, so free functions in different files would collide);
- Three separate pair classes: conflicts[] (same claim key on both lanes — git will fight), same_file_risk[] (different keys, same file, aggregated per file), contract_touch[] (one lane's claim sits in another's blast radius — an adaptation, NOT a merge conflict).

### `--plan-lanes --brief=FILE`

**Answers:** the explicit form of the above: one non-blank line per lane, N = the line count.

Each line is ranked on its own — no community carve, no bin packing — so the lane boundaries are the ones you wrote. This is the mode whose precision is defensible; prefer it when you can. Lane isolation is a QUALITY argument, not a speed one (CAID, arXiv 2603.21489: 63.3% vs 55.5% shared, largest gains on weaker lane models — and wall clock got WORSE).

**Try it**

_NEW VERB, explicit form: one line per lane, lane boundaries are the ones you wrote (the defensible mode)._

```
$ ./build/ripwire . --plan-lanes --brief=<scratch>/aux/lanes_brief.txt
add a --since filter to the doc-drift verb
add the CLI parse arm and help text for the new filter
write regression tests for the new filter
```

**Shaped by:** `--legend`, `--json`

**Caveats (stated by the binary):**

- Lane isolation is a QUALITY argument, not a speed one (CAID, arXiv 2603.21489: 63.3% vs 55.5% shared, largest gains on weaker lane models — and wall clock got WORSE).

### `--stray-content[=SUBSTR]`

**Answers:** "where does this content live?" across ALL branches — the question `git cherry` cannot answer.

Per local ref (SUBSTR filters ref names): the lines its own divergent work AUTHORED vs its merge-base with HEAD that the live line does NOT have, and a verdict. v="unmerged" = genuinely absent; v="superseded" = the live line removed the SAME base code this ref removed, i.e. it re-implemented the work (git cherry still calls that commit unmerged, forever); v="merged" refs are omitted. Every row shows its raw del=/redone=/sim= evidence, so a verdict is auditable, not a black box. v="unknown" (ok="0") = the ref has NO merge-base with HEAD, so it could not be analysed at all — a shallow clone (the actions/checkout DEFAULT) puts every ref here. It is NOT a claim the work is merged: it is the absence of an answer, counted in its own unknown= bucket so unmerged+superseded+merged+unknown always reconciles with refs=, and surfaced by --plan as an <undetermined> row rather than silently dropped. LIMITS: line-granular, not semantic — a rewrite that shares no deleted base line reads as unmerged; binary/oversized blobs are reported diffable="0" with no counts. Read-only (cat-file/diff/ls-tree); single-root only.

**Try it**

_Which lane-* refs still hold divergent authored work vs HEAD, with verdicts._

```
$ ./build/ripwire . --stray-content=lane
<!-- ripwire stray-content: per ref, the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. v="superseded" means the live line removed the same base code this ref removed (redone/del) — it re-implemented the work, the case `git cherry` cannot see; v="unmerged" means the work is genuinely absent; merged refs are omitted. Read-only: git cat-file/diff/ls-tree only, one batched cat-file for the whole sweep, every blob reduced once per sha. Line-granular, not semantic: see the ripwire help text for the limits. ANCHORING is a deliberate hybrid: the SCOPE is base anchored (only lines the ref itself authored vs its merge base are ever considered, so a file the ref never opened cannot appear because the live line moved), while the ABSENCE test is HEAD anchored on purpose (does the live line have this content TODAY is the question being asked, and it is only answerable against live HEAD). v="unknown" with ok="0" means this ref could NOT be analysed at all because it has no merge base with HEAD, which on a SHALLOW clone (the checkout default in CI) is every ref: it is not a claim that the ref is merged, and the fix is to deepen the clone. The four buckets are exhaustive, so unmerged plus superseded plus merged plus unknown always equals refs. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that there is nothing here to be stray FROM; refs= is that fact as a number. TRUNCATION: a ref row ends with a more element (more files=N) when its own file listing was capped; shown plus that number equals the ref's files= total, always. That inner listing is a SECONDARY listing (it repeats complete and identical on every page) and is capped by detail, not by limit / offset, which page the OUTER ref listing and report their own shown= / capped=. at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit (head= is the same commit, bare sha, kept for compatibility). -->
<stray-content head="5f71cb4fd" head_ref="integration/harvest-b-2026-09-05" refs="50" blobs="53" unmerged="1" superseded="3" merged="27" unknown="19" filter="lane" at="5f71cb4fd+dirty">
<ref name="lane/ca-P15" tip="2e305e5ea" date="2026-09-04" base="b38a488f8" ok="1" v="unmerged" stray="72" files="3" superseded="0">
<file p="test/readmedriftcheck.sh" v="unmerged" stray="69" authored="79" del="0" redone="0" sim="0.78" head-touched="0"/>
<file p="README.md" v="unmerged" stray="2" authored="2" del="2" redone="0" sim="0.05" head-touched="1"/>
<file p="skills/ripwire-efficient/compress-ladder.md" v="unmerged" stray="1" authored="1" del="1" redone="0" sim="1.00" head-touched="0"/>
</ref>
<ref name="lane/ca-L4" tip="232c33796" date="2026-09-05" base="30192e6ae" ok="1" v="superseded" stray="24" files="8" superseded="24">
<file p="test/lintprecisioncheck.sh" v="superseded" stray="7" authored="7" del="2" redone="2" sim="0.82" head-touched="1"/>
<file p="test/donelegendcheck.sh" v="superseded" stray="4" authored="4" del="1" redone="1" sim="0.94" head-touched="1"/>
<file p="test/fixedbufsweep.sh" v="superseded" stray="4" authored="4" del="1" redone="1" sim="0.84" head-touched="1"/>
<file p="test/rustqualcheck.sh" v="superseded" stray="3" authored="3" del="1" redone="1" sim="1.00" head-touched="1"/>
<file p="README.md" v="superseded" stray="2" authored="3" del="3" redone="3" sim="0.05" head-touched="1"/>
<file p="test/panellegendcheck.sh" v="superseded" stray="2" authored="5" del="3" redone="3" sim="0.35" head-touched="1"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--plan`, `--abi`, `--whereis`, `--limit`, `--eval-stray`

**Caveats (stated by the binary):**

- "where does this content live?" across ALL branches — the question `git cherry` cannot answer.
- Every row shows its raw del=/redone=/sim= evidence, so a verdict is auditable, not a black box.
- It is NOT a claim the work is merged: it is the absence of an answer, counted in its own unknown= bucket so unmerged+superseded+merged+unknown always reconciles with refs=, and surfaced by --plan as an <undetermined> row rather than silently dropped.

### `--plan`

**Answers:** (with --stray-content) "of all my branches, which still hold REAL work, and in what order should I land them?" Selects the refs --stray-content calls v="unmerged", DROPS the v="superseded" ones (landing them would re-do work the live line already did — the exact waste --stray-content exists to catch), and feeds the survivors to --merge-scout's existing pairwise-conflict + fewest-conflicts-first landing-order machinery — composition only, neither verb's logic is reimplemented.

<ref scouted="0"> is unmerged work NOT fed to merge-scout THIS run (a cost bound, not a verdict); <excluded> names the superseded drops and why. COST: --stray-content is a cheap per- blob sweep, but --merge-scout is per-ARM (git-archive + full ingest of each ref's tree) — measured 27s for 9 unmerged refs on a 35-branch real C++ repo (~3s/ref). kMaxPlanScout (12) bounds it to the top-N unmerged refs BY STRAY SIZE; --detail lifts the bound to scout everything. This is an EXPLICIT opt-in "before you land" call, not a per- question one — the default map's ~0.10s path is untouched. Read-only; single-root only.

**Try it**

_Select the genuinely-unmerged refs of one family and feed them to merge-scout for a landing order (a merged family yields an empty landing set — still a measurement, disclosed on the root)._

```
$ ./build/ripwire . --stray-content=lane/ --plan
<!-- ripwire landing-plan: stray-content's cheap per-blob sweep composed with merge-scout's per-arm overlap oracle — of every local branch, which still hold REAL work (v="unmerged"), which were already re-implemented on the live line (v="superseded", EXCLUDED below — landing them re-does work that is already done) or are already merged (omitted entirely, counted in merged= on the root element), and the fewest-conflicts-first order to land what remains. scouted="0" on an unmerged ref means it was NOT fed to merge-scout this run (the cost bound, not a verdict) — it is still real, unscouted work; bounded= on the root element counts them and detail lifts the bound. merge-scout is the EXPENSIVE step here (git-archive + full ingest per arm) — stray-content's own sweep is the cheap one. An undetermined row is a ref that could NOT be analysed at all (no merge base with HEAD, which on a SHALLOW clone is every ref): it is neither scouted nor excluded nor merged, because nothing was measured — treat it as unfinished business and deepen the clone, never as a clean branch. Read-only throughout: no checkout, no ref write, no working-tree mutation. The root carries BOTH head= and at= and they are the same commit: head= is the bare 9 hex chars this verb has always printed, at= is the tool wide anchor and is head= plus a "+dirty" suffix when the working tree is not clean. Prefer at= (it is the one spelling every other repo reading verb uses, and the only one that tells you whether uncommitted work was in scope); head= is kept for callers already keyed to it. -->
<landing-plan head="5f71cb4fd" refs="50" unmerged="1" superseded="3" merged="27" undetermined="19" scouted="1" bounded="0" scout-ok="1" at="5f71cb4fd+dirty">
<ref name="lane/ca-P15" v="unmerged" stray="72" files="3" scouted="1"/>
<undetermined name="lane/af-grepfast" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/af-hookdrift" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/af-idiom" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/af-planlint" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/af-regmacro" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/af-scope" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
... [22 more line(s); run it to see the whole thing]
```

**Shaped by:** `--stray-content`, `--legend`, `--json`

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
<!-- ripwire abi: the cross-branch ABI-BREAK gate — layout(STRUCT) crossed with stray-content(BRANCH). Scope is what each ref AUTHORED: the paths `diff base..tip` reports against its own merge base, never `diff HEAD..tip` (a file the branch never opened cannot be a break the branch introduced, and on a long-lived tree that one distinction took 487 drift rows to 4). For each such path the SAME field-offset model layout uses is run LEXICALLY on the ref's git blob (never indexed) and compared against HEAD's computed fields. LISTED kinds: drift = the byte contract differs (the bug this check exists for, the only kind that exits 2); unknown = the ref-side copy could not be modelled (see ref_caveat) and is NEVER reported as unchanged; absent = the ref does not define the struct at that path. COUNTED but not listed (pass detail=N to print them): rename = identical slots and field types under different field NAMES, so every byte stayed where it was (a same-type field REORDER is lexically identical to a rename and lands here too); spelling and stub mirror layout's own harmless cases; head-moved = the ref's copy equals its own merge-base copy, so the LIVE LINE is what changed. head_only= counts candidate sites on paths only the live line touched (outside the authored scope); unmodelable= counts sites skipped because HEAD's own copy carries no baseline; every excluded row is on a counter, nothing is dropped silently. Structs that match are omitted entirely; unrelated= counts refs with no merge-base against HEAD at all (unrelated history — never even compared, so nothing for them CAN be dropped silently either) and, because such a ref never gets the chance to acquire a row, it ALSO lands in quiet= below (the two counters are not disjoint: a ref with no rows at all is counted in quiet= whether that is because nothing broke or because nothing was ever compared), and a ref whose every row is an excluded kind is counted in excluded_refs= and prints under detail=N. LIMITS: HEAD's own side is the WORKING TREE's layout answer, not a re-fetched git blob at HEAD's commit; a nested field type that ALSO changed on the ref resolves via HEAD's copy, not the ref's; the ref-side locator is index-free and file-scope (one namespace deep) only, so a struct nested in a class or wrapped in an extern C block reads absent rather than compared; the authorship anchor is per PATH, so a branch changing struct S in one file while the live line changes S's mirror in another is a merge hazard only layout(S) on the merged result can see. Single-root; read-only (cat-file/diff/merge-base only). at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit (head= is the same commit, bare sha, kept for compatibility). -->
<abi head="5f71cb4fd" head_ref="integration/harvest-b-2026-09-05" refs="50" candidates="935" compared="0" blobs="2" rows="0" shown="0" capped="0" dropped="0" excluded="0" head_only="8977" unmodelable="7" unrelated="19" broken_refs="0" quiet="50" excluded_refs="0" at="5f71cb4fd+dirty" root=".">
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
<!-- ripwire whereis: every LOCAL ref whose TREE contains this symbol, HEAD first, and within a ref SOURCE files before test files before docs, then definitions before references, then path and line. The doc demotion is ORDER ONLY: a doc line that quotes a signature still reads as a definition to the heuristic below and still says kind="def", it is simply printed after the code. kind= is answered by TWO different mechanisms, and head_labels= says which one answered for HEAD: with head_labels="index" a HEAD row is kind="def" iff the PARSED index puts a definition there (one row per index def site), while every NON-HEAD row — and every row when head_labels="lexical" (no index was supplied, the index knows no def of this name, or the working tree has drifted from HEAD) — is a LEXICAL shape heuristic over raw blob text that was never ingested: it reads a quoted signature in a doc as a definition and can miss an unusual declarator. refs_scanned= is the SCAN DENOMINATOR (how many refs besides HEAD were read), NOT a count of refs that matched — hits= and the rows are the matched set. on-head="0" alongside ref hits is the case this verb exists for: content that lives only on a branch. A TREE scan can only find content some ref still carries, so hits="0" on its own does not distinguish a name this repo never had from one it deleted; run with the with_history flag and the fate row says which, naming the commit that removed it. ANCHORING: none, by design. This verb runs no diff at all — it scans each ref's FULL tree, which is what lets it find content a branch merely INHERITED (exactly what a merge base anchored diff would exclude), so nothing here can fire merely because HEAD moved. at= is sha-only here (never +dirty): a tree scan reads committed blobs, so the working tree's cleanliness does not enter the answer. SELECTOR: this verb takes a BARE symbol name, not the file:name spelling that callers, uses, impact, around, lego and edit_check accept. A file:name spelling is searched as a LITERAL string, no tree contains it, and the result is a true but useless hits="0" shaped exactly like a name this repo never had. When that is what happened, a selector-note element says so and its retry= is the bare name to re-run with. That element has three reasons, and r= names which: qualified-selector (a file:name spelling was searched literally), line-seed (an @FILE:LINE selector was RESOLVED to the definition enclosing that line before the scan, so sym= is that definition's name and spec= is what you typed), and near-miss (the scan found nothing and the INDEX holds a name one or two edits away — the tree zero is still a measurement, the note only says which zero it is). Its absence beside hits="0" means the zero IS a measurement. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that this verb sees essentially one tree; refs_scanned= is that fact as a number, so read it before reading hits=. TRUNCATION: the trailing more element (more hits=N) is the rows AFTER this page, so shown plus more equals the rows from this page's offset on. It is not a second cap, and not a second vocabulary to page by: it is the SAME fact shown= / capped= / next_offset= carry, restated from the other end (what this page did not print). Page with limit= and offset=; the more element is absent exactly when this page reached the end of the hit list. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: every occurrence of the symbol in every TEXT blob of every scanned ref's full tree is printed above — nothing was capped or paged out, and no blob was oversized (over the 2 MB blob ceiling), missing or cut short by the stream. The denominator is refs_scanned= plus HEAD, under SCOPE above (local heads only), so with complete= present a ref absent from the rows genuinely lacks the symbol in its committed tree. Binary blobs are outside the claim (a text symbol cannot occur in one); an oversized TEXT blob suppresses the claim instead of being silently skipped. Its ABSENCE claims nothing. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). -->
<whereis sym="rankGraphTeleport" on-head="1" refs_scanned="77" blobs="4322" hits="69078" head_labels="index" shown="60" capped="1" total="69078" has_more="1" next_offset="60" offset="0" limit="0" at="5f71cb4fd">
<hit ref="HEAD" tip="5f71cb4fd" date="2026-09-05" p="src/graph.h" l="2501" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="HEAD" tip="5f71cb4fd" date="2026-09-05" p="present/deck5_ripwire_build.js" l="631" kind="ref" t="s.addText(&quot;$ ripwire . --callers=rankGraphTeleport&quot;, { x: 8.68, y: 2.1, w: 3.8, h: 0.3, fontFace: MONO, fontSize: 10, color: MUTED, margin: 0 });"/>
<hit ref="HEAD" tip="5f71cb4fd" date="2026-09-05" p="present/deck5_ripwire_build.js" l="633" kind="ref" t="{ text: &quot;&lt;callers of=\&quot;rankGraphTeleport\&quot;\n  defs=\&quot;1\&quot; count=\&quot;6\&quot; &quot;, options: { color: TEXT } },"/>
<hit ref="HEAD" tip="5f71cb4fd" date="2026-09-05" p="src/cli.h" l="72" kind="ref" t="// tokens on --around=rankGraphTeleport vs 5,860 B at depth 1; the root&apos;s"/>
<hit ref="HEAD" tip="5f71cb4fd" date="2026-09-05" p="src/crossref.h" l="1632" kind="ref" t="// code above the real definition: `--whereis=rankGraphTeleport` opened with three kind=&quot;def&quot; rows into"/>
<hit ref="HEAD" tip="5f71cb4fd" date="2026-09-05" p="src/didyoumean.h" l="238" kind="ref" t="// `--path=rankGraphTeleport,` printed &quot;endpoint not found:  (did you mean &apos;A&apos;?)&quot;. Guarded at the shared walk"/>
... [23 more line(s); run it to see the whole thing]
```

**Shaped by:** `--with-history`, `--limit`

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
<flags gates="69" dark_gates="62" compile="12" cmake="12" env="45" files="1595">
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

_Unknown-gate refusal (exit 1) with a did-you-mean from a real edit distance (one character off RIPWIRE_ASAN)._

```
$ ./build/ripwire . --flags --flip=RIPWIRE_ASA
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

_The honest refusal (exit 1): Lang is an `enum class`, not a struct — no offsets are fabricated._

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

**Try it**

_The cache-locality lens over every aggregate: fields READ TOGETHER but declared FAR APART (split-line / straddle findings, Chilimbi separation weight) — advice only, never a rewrite._

```
$ ./build/ripwire . --field-affinity
<!-- ripwire field-affinity: which fields are READ TOGETHER but declared far apart, diffed against 64-byte cache-line geometry. PRIOR ART, claimed by NOBODY here as new: the field affinity graph, the static field-access enumeration without pointer analysis, and the separation weight wt(fi,fj) = (block - dist)/block are Chilimbi, Davidson and Larus, Cache-Conscious Structure Definition, PLDI 1999 (bbcache), which also validated against UltraSPARC hardware counters; the advice-instead-of-transform posture and per-field counter attribution are Hundt, Mannarswamy and Chakrabarti, CGO 2006. What is new here is only the delivery: source level, no debug info, whole repo, ranked. TWO HONEST LIMITS. (1) Static access counts are NOT dynamic frequency: one field in a hot loop beats fifty on cold paths and nothing static can tell them apart, so fns= is a FLOOR of DISTINCT INDEXED FUNCTIONS and w= is a call-graph reachability PROXY (sum of 1 + fan-in), never a measured frequency. Only member-access syntax (dot and arrow) is counted; a bare field name inside its own method is not, because a local of the same name is indistinguishable here. (2) True sizeof and alignment are unknowable from source under templates, virtuals, bases and the target ABI: all geometry is the layout verb's LP64 standard-layout MODEL, model="lp64-approx", and a definition it refused (modeled="0") contributes its affinity graph and NO geometry finding; why=names layout's own refusal kind(s) for THIS definition (bitfield/virtual/base-class/template/…, the layout verb's own legend names the class, this the instance). Exactly two findings fire, both with a defensible direction: split-line (co-accessed by 2+ functions at wt 0.00, so no field order can share a line) and straddle (one co-accessed field crossing a line boundary). Pack-tighter and sort-by-size advice is deliberately ABSENT: tight packing can induce false sharing, which is why the Go team keeps fieldalignment out of vet and gopls. ADVICE ONLY, never a transformation. validate= names the instrumented PROFILE_SCOPE whose counters would confirm the hypothesis; see docs/FIELDAFFINITY.md. PHASE A/B (report-only): as_* counts a corpus-wide, purely static for-loop advance-shape classification (index/chase/mixed/unknown, via astQuery TSQuery patterns, never execution); a chase-shaped field is disclosed on its <f> row as chase="1" loops="N", with shape_conf="self-ref"/"tmpl-approx" only when the field's OWN declared type textually self-references its aggregate. Refusals are per-cause: as_stem_ambiguous= chase field names declared by 2+ modeled aggregates, as_stem_unowned= by NONE (forward-declared/vendored traversal target), as_stem_nonptr= a sole owner whose declared type has no pointer/reference marker (provably not a raw-pointer chase target). as_query_capped=1 means the classification hit its query budget, making every as_* count a floor. NEVER ranking-affecting yet: the required real-corpus, blind-reviewed precision floor has not run, so sepcost= is IDENTICAL with or without this disclosure. See src/accessshape.h and docs/FIELDAFFINITY.md sec 8. -->
<fieldaffinity block="64" model="lp64-approx" counts_floor="1" weighting="fanin-floor" aggregates="935" files="229" fns_scanned="4761" accesses="8462" amb_skipped="16240" structs="509" shown="20" capped="1" findings="16" min_fns="2" as_loops="1856" as_index="4" as_chase="5" as_mixed="1" as_unknown=" … [line truncated: 76 more bytes on this line]
<s n="MainDispatch" p="src/main.cpp" l="489" agg="struct" modeled="1" fields="20" touched="15" fns="21" pairs="70" sepcost="108.25" findings="12" size="160" align="8" lines="3">
<f n="multiRoot" acc="13" fns="11" sz="1" off="32" ln="0"/>
<f n="ws" acc="7" fns="7" sz="8" off="40" ln="0"/>
<f n="fanInPtr" acc="6" fns="6" sz="8" off="56" ln="0"/>
<f n="qmetrics" acc="1" fns="1" sz="8" off="64" ln="1"/>
<f n="ampPtr" acc="7" fns="7" sz="8" off="72" ln="1"/>
<f n="cboPtr" acc="2" fns="2" sz="8" off="80" ln="1"/>
<f n="testedPtr" acc="8" fns="8" sz="8" off="88" ln="1"/>
<f n="lcom4Ptr" acc="2" fns="2" sz="8" off="96" ln="1"/>
<f n="impurePtr" acc="5" fns="5" sz="8" off="104" ln="1"/>
<f n="forChurn" acc="2" fns="2" sz="8" off="112" ln="1"/>
<f n="redactCounts" acc="10" fns="6" sz="8" off="120" ln="1"/>
... [17 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- ADVICE ONLY: it never proposes a reordering and it has no rewrite mode, because pack-tighter/sort-by-size advice is NON-MONOTONIC (tight packing can induce false sharing — the reason the Go team keeps its own fieldalignment analyzer out of vet and gopls).
- LIMITS, both in the header: static access counts are NOT dynamic frequency, so fns= is a FLOOR of distinct indexed functions and w= is a call-graph reachability PROXY (1 + fan-in), never a measured count;
- a field name declared by TWO aggregates is REFUSED and tallied in amb_skipped= rather than guessed;

### `--doc-drift[=SUBSTR]`

**Answers:** which of this repo's DOC claims are now false.

Verifies the CHECKABLE anchors in every markdown file (SUBSTR filters doc paths) against the live index and prints ONLY the ones that no longer hold, four kinds: file:line refs (why="missing-file" the path is gone, "past-eof" the file is shorter than that, "line-moved" the line is no longer inside the symbol the doc names beside it — got= names the squatter); backticked symbol mentions ("undefined"); `= N` constants ("const-value"); and `[N]` array extents ("array-extent"). LIMITS, stated because a doc-drift verb that cries wolf is worse than none — every lane deliberately UNDER-reports. A backticked name is called stale only when it occurs nowhere in any non-markdown file as an identifier token, so every library name is silent, and so is any repo constant the grammar does not tag as a definition (namespace-scope constexpr in C++, for one) — those are counted as unchecked r="not-a-definition", never as drift. A number is compared only against a DECLARATION-shaped integer literal (a decl keyword on the line, or the name opening it) that the corpus binds UNIQUELY; two values in the tree means unchecked, not drift. A `NAME = N` whose NAME appears nowhere in the code is prose, counted in prose= and never claimed as an anchor. Symbol mentions inside ``` fences are skipped (illustrative code, not claims). checked + unchecked = anchors, always: whatever was not proved says so in an <unchecked> row. Read why="undefined" precisely — it says the name is defined NOWHERE in this repo, which is not the same as DELETED: in a plan or design doc naming work not yet built, that is expected rather than rot. The file:line, const and array lanes are the high-precision ones; the mention lane is the weakest — --with-history is the fix, splitting it into why="deleted" (history removed the name; got= names the commit and date, at= the file) versus unchecked r="never-in-history" (this repo never had it, so it is not rot at all). DATED RECORDS vs ROT. An audit's finding row and a live map gone stale look identical — both are "the code moved and the doc did not" — so a failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated=, leaving drift= for the LIVE rot. drift + dated is every anchor that failed: a record still prints, it is never dropped. rec= names the evidence, most specific first: "line" (the line itself hedges — an at-the-time / as-of-DATE note, or a row opening with an ISO date), "block" (the nearest heading carries an ISO date), "title" (the filename or H1 does), "stamp" (a LABELLED front-matter self-date: 'Date: …', 'Written …', 'Generated: …'). WHAT THIS LANE CANNOT DO, because both were measured and rejected: it cannot use git history — 90 of this repo's 98 stale file:line anchors were CORRECT at their own doc's last commit, audit findings and live design docs alike, because "was it true when written" is the definition of BOTH a record and rot; and it will not read a bare date in the opening prose, which on this repo alone dated three LIVE documents on a day they merely mentioned. It reads dating MARKS, so a doc that is obviously an artifact-of-a-date to a human but never writes that date machine-readably reports LIVE (this repo has two). The bias is one-directional on purpose: a wrong "record" hides real rot, a wrong "live" only over-reports. An inception or freshness date ('opened …', 'Last updated …') is a claim the doc is CURRENT and never marks a record. NOT CHECKED AT ALL: prose, Status lines, dates, 'N of M done' tallies, and whether a code block's body is still correct. Always exits 0 — a report, not a gate. Root element carries at="<sha>[+dirty]" (omitted on a non-git root) — the commit these counts were computed against, so a number quoted from this report stays comparable across a HEAD that moves mid-session.

**Try it**

_Which of this repo's doc claims are now false. CHANGED: row attribute at= renamed to tgt= (at= is now only the root sha stamp)._

```
$ ./build/ripwire . --doc-drift
<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an identifier, and a number is compared only against a declaration shaped literal the corpus binds uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say what was not proved. Read why="undefined" precisely: it says the name is defined NOWHERE in this repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is expected rather than rot. Run with the with_history flag to have git history separate the two: the lane then reports why="deleted" with the commit that removed the name, and downgrades a name this repo never had to unchecked r="never in history". A failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated= rather than drift=: an audit finding, a ledger row or an as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root element and is the commit the run was measured against (short sha, plus dirty when the tree had uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious reason that kind= is already taken on the same element; note that in the ranked map the same k= spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the same key. Prose claims, Status lines and dates are NOT checked. A `path:A-B` RANGE gets one more structural check: why="range-straddles" fires when A's innermost symbol does not reach B (got= then names whatever occupies B instead, tgt= that site), regardless of whether the doc names a symbol. weak-file-line, the one unchecked reason that names no symbol, gets a FREE disclosure instead of a verdict: <weak-file-line p= n=> groups, one per doc, list every such anchor whose line DOES sit inside an indexed symbol, and each <w> row's resolves-to= names it — the verb still does not know if that is the symbol the doc meant. This section sits beside, not inside, the <doc> rows: a doc can appear in it while still counting toward clean=, and every row it lists still counts once in the unchecked r="weak-file-line" tally below. FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. corpus= is the file population the anchors were checked AGAINST, and it is its OWN population rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, .metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still refuses, and a file the index lists but this run cannot open is counted by one and not the other. Neither number is wrong. corpus="0" means the corpus scan never ran at all, which happens only when the docs raised no anchor SHAPE whatsoever — prose ones included — so anchors="0" beside a non-zero prose= still scanned, and still reports the corpus it scanned. -->
<doc-drift docs="145" clean="126" anchors="2469" checked="965" unchecked="1504" drift="61" dated="80" prose="9" corpus="1621" at="5f71cb4fd+dirty">
<doc p="docs/COMMANDS.md" anchors="137" checked="37" drift="32" dated="0">
<a k="const" l="3609" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3610" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3611" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3612" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3613" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="const" l="3614" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3615" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3616" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3617" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3618" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3619" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--recall`, `--comment-coherence`, `--with-history`, `--plan-lint`, `--limit`

**Caveats (stated by the binary):**

- LIMITS, stated because a doc-drift verb that cries wolf is worse than none — every lane deliberately UNDER-reports.
- A `NAME = N` whose NAME appears nowhere in the code is prose, counted in prose= and never claimed as an anchor.
- Symbol mentions inside ``` fences are skipped (illustrative code, not claims).

### `--doc-drift --gateability`

**Answers:** turn "CI stays non-gating" into a finishable to-do list: for every doc that STILL has a LIVE (undated) failing anchor, prints its path and live=N (how many of its rows a date would fix), plus projected_drift= — repo-wide drift= if EVERY listed doc got the fix.

The fix is always the same one this lane already reads for rec="title"/"stamp": an ISO date in the doc's H1/filename, or a front-matter self-date line (Date:/Written:/ Generated:/Recorded:/Reviewed:/Audited:/Authored:). projected_drift= is an UPPER BOUND, not a mandate — dating a doc that is genuinely a live/current reference (not a snapshot-in-time record) would hide real rot rather than honestly classify it. Requires --doc-drift (refused loudly alone).

**Try it**

_Which of this repo's doc claims are now false. CHANGED: row attribute at= renamed to tgt= (at= is now only the root sha stamp)._

```
$ ./build/ripwire . --doc-drift
<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an identifier, and a number is compared only against a declaration shaped literal the corpus binds uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say what was not proved. Read why="undefined" precisely: it says the name is defined NOWHERE in this repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is expected rather than rot. Run with the with_history flag to have git history separate the two: the lane then reports why="deleted" with the commit that removed the name, and downgrades a name this repo never had to unchecked r="never in history". A failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated= rather than drift=: an audit finding, a ledger row or an as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root element and is the commit the run was measured against (short sha, plus dirty when the tree had uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious reason that kind= is already taken on the same element; note that in the ranked map the same k= spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the same key. Prose claims, Status lines and dates are NOT checked. A `path:A-B` RANGE gets one more structural check: why="range-straddles" fires when A's innermost symbol does not reach B (got= then names whatever occupies B instead, tgt= that site), regardless of whether the doc names a symbol. weak-file-line, the one unchecked reason that names no symbol, gets a FREE disclosure instead of a verdict: <weak-file-line p= n=> groups, one per doc, list every such anchor whose line DOES sit inside an indexed symbol, and each <w> row's resolves-to= names it — the verb still does not know if that is the symbol the doc meant. This section sits beside, not inside, the <doc> rows: a doc can appear in it while still counting toward clean=, and every row it lists still counts once in the unchecked r="weak-file-line" tally below. FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. corpus= is the file population the anchors were checked AGAINST, and it is its OWN population rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, .metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still refuses, and a file the index lists but this run cannot open is counted by one and not the other. Neither number is wrong. corpus="0" means the corpus scan never ran at all, which happens only when the docs raised no anchor SHAPE whatsoever — prose ones included — so anchors="0" beside a non-zero prose= still scanned, and still reports the corpus it scanned. -->
<doc-drift docs="145" clean="126" anchors="2469" checked="965" unchecked="1504" drift="61" dated="80" prose="9" corpus="1621" at="5f71cb4fd+dirty">
<doc p="docs/COMMANDS.md" anchors="137" checked="37" drift="32" dated="0">
<a k="const" l="3609" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3610" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3611" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3612" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3613" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="const" l="3614" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3615" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3616" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3617" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3618" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3619" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--recall`, `--comment-coherence`, `--with-history`, `--plan-lint`, `--limit`

**Caveats (stated by the binary):**

- projected_drift= is an UPPER BOUND, not a mandate — dating a doc that is genuinely a live/current reference (not a snapshot-in-time record) would hide real rot rather than honestly classify it.
- Requires --doc-drift (refused loudly alone).

### `--with-history`

**Answers:** OPT-IN: let --doc-drift and --whereis ask git HISTORY whether a name was ever in this repo, and which commit removed it.

ONE `git log -p` walk over everything reachable from HEAD, tokenizing removed lines — the pickaxe's semantics without the pickaxe's cost (`git log -S` per name is ~126 s at 247 names on a 2900-file repo; this is ~3 s, and ~0.8 s on ripwire itself). Off by default because those default paths run in 0.64 s and 0.15 s. Memoized per (repo, HEAD sha) — a commit is immutable, so the cache cannot go stale — and the blob covers the WHOLE repo, so a second question on the same commit costs a cache load, and --whereis reuses whatever --doc-drift already built. LIMITS: it walks HEAD's own history, so a name that only ever lived on an unmerged branch reads as never here (use --whereis's tree scan for that); a deletion performed ONLY as a merge resolution is not seen (merge diffs are not walked); and evidence is a removed LINE carrying the name, so a name whose last removal was from a doc rather than code is reported with that doc as its site. A repo deeper than the walk bound reports truncated="1" and answers unknown — never "never" — for anything it did not reach.

**Try it**

_Same report, with git history splitting stale mentions into deleted-by-commit vs never-existed._

```
$ ./build/ripwire . --doc-drift --with-history
<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an identifier, and a number is compared only against a declaration shaped literal the corpus binds uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say what was not proved. Read why="undefined" precisely: it says the name is defined NOWHERE in this repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is expected rather than rot. Run with the with_history flag to have git history separate the two: the lane then reports why="deleted" with the commit that removed the name, and downgrades a name this repo never had to unchecked r="never in history". A failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated= rather than drift=: an audit finding, a ledger row or an as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root element and is the commit the run was measured against (short sha, plus dirty when the tree had uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious reason that kind= is already taken on the same element; note that in the ranked map the same k= spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the same key. Prose claims, Status lines and dates are NOT checked. A `path:A-B` RANGE gets one more structural check: why="range-straddles" fires when A's innermost symbol does not reach B (got= then names whatever occupies B instead, tgt= that site), regardless of whether the doc names a symbol. weak-file-line, the one unchecked reason that names no symbol, gets a FREE disclosure instead of a verdict: <weak-file-line p= n=> groups, one per doc, list every such anchor whose line DOES sit inside an indexed symbol, and each <w> row's resolves-to= names it — the verb still does not know if that is the symbol the doc meant. This section sits beside, not inside, the <doc> rows: a doc can appear in it while still counting toward clean=, and every row it lists still counts once in the unchecked r="weak-file-line" tally below. FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. corpus= is the file population the anchors were checked AGAINST, and it is its OWN population rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, .metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still refuses, and a file the index lists but this run cannot open is counted by one and not the other. Neither number is wrong. corpus="0" means the corpus scan never ran at all, which happens only when the docs raised no anchor SHAPE whatsoever — prose ones included — so anchors="0" beside a non-zero prose= still scanned, and still reports the corpus it scanned. history probed="1" means the git-log name-history walk ran: commits= is how many it read (runProbe's own no-merges log, so a name deleted only inside a merge commit is invisible and not counted either), removed-names= how many distinct names it saw deleted at least once, and truncated="1" (absent = not hit) means the walk stopped at its own commit ceiling before reaching the root. probed="0" r= says why it did not run at all (not-a-git-repo or probe-failed) — none of the other attributes are then present. -->
<doc-drift docs="145" clean="129" anchors="2469" checked="955" unchecked="1514" drift="60" dated="71" prose="9" corpus="1621" at="5f71cb4fd+dirty">
<history probed="1" head="5f71cb4fd" commits="1413" removed-names="30032"/>
<doc p="docs/COMMANDS.md" anchors="137" checked="37" drift="32" dated="0">
<a k="const" l="3609" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3610" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3611" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3612" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3613" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="const" l="3614" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3615" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3616" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3617" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3618" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--whereis`, `--doc-drift`

**Caveats (stated by the binary):**

- Memoized per (repo, HEAD sha) — a commit is immutable, so the cache cannot go stale — and the blob covers the WHOLE repo, so a second question on the same commit costs a cache load, and --whereis reuses whatever --doc-drift already built.
- LIMITS: it walks HEAD's own history, so a name that only ever lived on an unmerged branch reads as never here (use --whereis's tree scan for that);
- A repo deeper than the walk bound reports truncated="1" and answers unknown — never "never" — for anything it did not reach.

### `--plan-lint=FILE`

**Answers:** the house PLAN/DESIGN format's STRUCTURE check — never semantics, that stays --doc-drift's job.

FILE is read directly (like --from-trace's FILE, not through the crawled index), so it need not live inside any indexed root. GRAMMAR, narrow and opt-in on purpose (real house plans do not converge on one dialect): a card is exactly an H3 heading opening with a task id ("T" + 1-4 digits + up to 3 letters, e.g. T5 / T10 / T7b); a status ledger is exactly one heading (any level) whose text, stripped of a leading section mark, reads "Status" case-insensitively. A card's status is satisfied EITHER by a glyph on the LAST non-blank line of its own body OR by a ledger line naming its id (folded by digits — a bare card "T7" is also answered by a lettered ledger mention "T7a"/"T7b") that itself carries a glyph; the card's own body wins when it has one. A file showing NEITHER an H3 card NOR a ledger heading is reported dialect="0" with nothing further checked — not a failing lint, since most real plans are exactly that file. Once dialect="1": a card whose status did not resolve is status="missing" with why="unlaunched" (a ledger exists and never names this id or a lettered sub-task of it — the mid-wave "this task was never launched" catch), why="unresolved" (the ledger names it with no glyph nearby), or why="no-glyph" (no ledger exists in this document at all); an hourglass line whose git-blamed commit sits more than stale_commits= commits behind HEAD is stale="1" (never claimed outside a git repo — see git=; blames whichever line the status resolved to, named by src="ledger" when that is the ledger); a task id named in the ledger's own body with no matching card (same digit fold) is a ledger-orphan; a literal owed/OWED mention with no check-mark or cross anywhere LATER in the SAME document is undischarged (no cross-document tracking — a successor plan's discharge is invisible here, a stated limit, and this is substring matching with no semantic disambiguation: a doc that merely QUOTES the words reads the same as a real marker). Every gating row carries gating="1"; NOT CHECKED AT ALL: whether a card's claims are true, any heading level other than three for a card, a ledger heading spelled any other way, and a document that uses card headings as plain labels with NO status mechanism anywhere (no ledger, no glyph) — every card there reads "missing" too, a known, disclosed gap. Exit 2 when dialect="1" and gating is non-zero (unlike --doc-drift's always-0 report — nothing here has a legitimate "dated on purpose" reading); exit 0 clean or dialect="0"; exit 1 only when FILE could not be read.

**Try it**

_The house PLAN/DESIGN format's STRUCTURE check — never semantics; exit 2 when a card or ledger row gates._

```
$ ./build/ripwire . --plan-lint=test/planlintfix/wave.md
<!-- ripwire plan-lint: STRUCTURE only, never semantics (the doc-drift lane already owns citation truth). A card is exactly an H3 heading opening with a task id ("T" + digits + up to three letters). A ledger is exactly one heading whose text, stripped of a leading section mark, reads "Status" case-insensitively. A card's status is satisfied EITHER by a glyph on the LAST non-blank line of its own body OR by a ledger line naming its id (folded by digits, so a bare card is also satisfied by a lettered ledger mention of the same number, e.g. a ledger entry for "T7a" answers for card "T7") that itself carries a glyph — the card's own body wins when it has one, the ledger is read only when it does not. Neither convention is universal even in this house's own plan corpus, so a file showing neither is reported dialect="0" and nothing further is checked — this lint is opt-in per file, never a directory sweep, and a plan that never adopted the convention is not a failing one. Findings, only once dialect="1": a card whose status did not resolve (status="missing", why="unlaunched" when a ledger exists and never names this id or a lettered sub-task of it, why="unresolved" when the ledger names it with no glyph nearby, why="no-glyph" when this document carries no ledger at all); an hourglass line whose blamed commit sits more than stale_commits= commits behind HEAD (never claimed outside a git repo — disclosed via git="0", or the card's own missing since=; blames whichever line the status resolved to, named by src="ledger" when that is the ledger rather than the card); a task id named in the ledger's own body with no matching card, digit-folded the same way (ledger-orphan); an owed/OWED mention with no check-mark or cross anywhere LATER in this same document (single-document only — a successor plan that discharges it is invisible here, a stated limit). Every gating row carries gating="1" and the header's own gating= sums them. NOT CHECKED AT ALL: whether any card's claims are true, a heading level other than three for a card, a ledger heading spelled any other way, any discharge outside this one document, and a document that uses card headings as plain labels with no status mechanism anywhere (no ledger, no glyph) — every one of its cards reads "missing" too, a known, disclosed gap rather than a guessed-at fix. Exit 2 when dialect="1" and gating is non-zero; exit 0 when clean or dialect="0"; exit 1 only when FILE could not be read — a usage error, never a finding. -->
<plan-lint file="test/planlintfix/wave.md" dialect="1" cards="3" ledger="1" ledger_line="21" at="5f71cb4fd+dirty" git="1" stale_commits="20" gating="3">
<card id="T1" line="10" status="check" tline="12"/>
<card id="T2" line="14" status="cross" tline="16"/>
<card id="T5" line="18" status="missing" tline="19" why="unlaunched" gating="1"/>
<ledger-orphan id="T9" line="24" gating="1"/>
<owed line="22">
<![CDATA[- 2026-08-01 — T2 owed a re-check]]>
</owed>
<owed line="24" gating="1">
<![CDATA[- 2026-08-03 — T9 owed a kickoff review, still pending]]>
</owed>
</plan-lint>
```

**Caveats (stated by the binary):**

- the house PLAN/DESIGN format's STRUCTURE check — never semantics, that stays --doc-drift's job.
- A file showing NEITHER an H3 card NOR a ledger heading is reported dialect="0" with nothing further checked — not a failing lint, since most real plans are exactly that file.
- an hourglass line whose git-blamed commit sits more than stale_commits= commits behind HEAD is stale="1" (never claimed outside a git repo — see git=;

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

**Shaped by:** `--top-k`, `--token-budget`, `--help-task`, `--compress`, `--no-redact`, `--plan-lint`, `--run-trace`, `--limit`

**Caveats (stated by the binary):**

- map a stack trace / sanitizer report / compiler-error text ('-'=stdin) onto the indexed symbols: table-driven frame extraction (python / asan / node / compiler / generic), ranked INNERMOST-first over in-corpus frames only (out-of-corpus frames are listed and counted, never ranked).
- The counters close: in_corpus = suspects + merged + unresolved, with one <unresolved> row per file-matched frame no resolver could place.
- --top-k is NOT read here (the frame order is the trace's, not a rank).

### `--run-trace="CMD"`

**Answers:** EXEC-MODE --from-trace — the whole fix-loop entry in ONE call.

Runs CMD under `sh -c` (the make trust model: your user, your environment, stdin=/dev/null, NO sandbox), captures stdout+stderr interleaved, and on a NON-ZERO exit serves the --from-trace bundle for the captured text (frames mapped innermost-first, the innermost in-corpus symbol's FULL body) plus a token-frugal <lines view="relevant"> cut of the error / frame-shaped output lines — shown=/relevant=/total= all disclosed, the cut never silent. The command's own exit code is ALWAYS disclosed on <run exit=>; a command that exits 0 gets a minimal success record (exit, measured duration_ms, a disclosed tail of output) and NO bundle — nothing failed, so there is nothing to map. The <run> record and captured lines are MEASURED (not deterministic, not claimed to be); the MAPPING of the captured text is byte-deterministic, and the document says which part is which. Composes with --token-budget (it bounds the bundle half, like --from-trace); --top-k / --max-tokens are not read here. ripwire's exit: 0 = the command succeeded; 4 = it failed or timed out (the report is on stdout either way); 1 = ripwire itself could not spawn it.

**Try it**

_A command that exits 0: a minimal success record (exit, measured duration, disclosed output tail) and NO bundle — nothing failed, nothing to map._

```
$ ./build/ripwire . --run-trace="true"
<ctx task="run-trace: true">
<!-- ripwire run-trace: executed "true" under sh -c (the make trust model: your user, inherited environment, stdin=/dev/null, NO sandbox), stdout+stderr captured interleaved. On <run>: exit= the command's OWN exit code; signal= the signal that killed it; timed_out="1" = the timeout_s= cap killed the whole process group (an honest TIMEOUT, never an empty success); duration_ms= wall clock; lines= the capture's non-empty line count; bytes= the whole capture; dropped_bytes= middle bytes the capture cap dropped (head+tail kept). duration_ms and the captured output are MEASURED, not deterministic (and not claimed to be); every byte derived FROM the captured text - the <lines> cut and any mapping - is a deterministic function of it. <lines view="tail"> = the last shown= of total= output lines; view="relevant" = shown= of the relevant= error-marked / frame-shaped lines out of total= (capped="1" = first+last halves kept, the omitted middle disclosed inline). The command exited 0: nothing failed, so there is NOTHING TO MAP - no trace bundle is served for a passing command. -->
<run exit="0" duration_ms="25" timeout_s="600" lines="0" bytes="0"/>
</ctx>
```

**Shaped by:** `--top-k`, `--token-budget`, `--run-timeout`

### `--run-timeout=SECONDS`

**Answers:** cap for --run-trace's command (default 600 s;

always disclosed as timeout_s=). A command still running at the cap has its whole process group killed and is reported timed_out="1" — an honest TIMEOUT, never an empty success. Modifies --run-trace only; refused loudly alone.

**Try it**

_--run-timeout alone is refused loudly (it only modifies --run-trace)._

```
$ ./build/ripwire . --run-timeout=5
(empty)
```

**Caveats (stated by the binary):**

- A command still running at the cap has its whole process group killed and is reported timed_out="1" — an honest TIMEOUT, never an empty success.

### `--note-add="TARGET: text"`

**Answers:** pin a field note (write-side memory) to TARGET — a SYMBOL in any spelling the read verbs resolve (bare name, file:name, Scope::name, the canonical id path::scope::name, or @FILE:LINE) or a FILE PATH — in the committed, sorted .ripwire_notes at the repo root.

A symbol is CANONICALISED to its canonical id on write (the id --for/--expand key notes by) and the rewrite is echoed on stderr; a name matching SEVERAL definitions is refused naming each, and a name matching NONE is refused with a did-you-mean. A path target is written even when nothing indexed matches it (a note on a file you are about to add is legal), with a loud stderr warning that it is stored dangling. The date is git's committer clock (HEAD), not wall time, so the line is deterministic; prints the exact written line. Also STAMPS the writing repo's HEAD sha + branch onto the note (a "done"/"fixed" claim is then anchored to the commit it was true at) — a non-git root or an unresolvable HEAD writes the plain unstamped line rather than a wrong sha. MUTATES one file; single-root only. text with no causal/decision marker ("because"/"chose"/"over"/"instead"/etc.) gets a gentle stderr tip toward the decision shape — never a refusal, the add always proceeds.

**Try it**

_Two definitions carry this name, so the write REFUSES rather than pick one: a note keys ONE canonical id, and an ambiguous selector is refused, never silently narrowed. Every candidate is named, with a runnable retry._

```
$ ./build/ripwire . --note-add="gitOneLine: which one?"
(empty)
```

**Shaped by:** `--no-redact`, `--legend`

**Caveats (stated by the binary):**

- a name matching SEVERAL definitions is refused naming each, and a name matching NONE is refused with a did-you-mean.
- text with no causal/decision marker ("because"/"chose"/"over"/"instead"/etc.) gets a gentle stderr tip toward the decision shape — never a refusal, the add always proceeds.

### `--notes`

**Answers:** list all field notes grouped by target;

a target with no matching indexed symbol/file is flagged dangling="1" (legal — surfaced nowhere, listed here). Read-only. Notes surface automatically as <note d="date" [sha="…" branch="…"]> children on the symbols/files that --for and --expand emit (and the MCP for / fetch_body verbs); the sha/branch attrs appear only on notes stamped by this version, abbreviated (7 hex) for terseness — the full sha lives in .ripwire_notes on disk. An OLDER .ripwire_notes (3 fields, pre-provenance) reads and surfaces exactly as before, with no sha/branch shown. Absent/empty file = zero effect.

**Try it**

_List all field notes (write-side memory) — the committed .ripwire_notes at the repo root, each with the sha/branch it was recorded at._

```
$ ./build/ripwire . --notes
<ctx>
<!-- ripwire field notes: notes=1 targets=1 dangling=0 (a target with no matching indexed symbol/file — legal: listed here, surfaced nowhere). Each note row: d= is the ISO date it was recorded; sha= the abbreviated commit and branch= the branch checked out at record time, both omitted entirely on a note stored before provenance stamping (absent means none recorded, never empty) -->
<notes>
<target id="test/manifestcheck.sh" dangling="0">
<note d="2026-08-23" sha="42634f5" branch="claude/fervent-volhard-ddfd9f">
<![CDATA[README.md's single '<N> gate scripts' claim (~line 1305) is NOT enforced — the derived-vs-stated sibling loop here covers docs/EVALS.md only. It drifted 407→451 unnoticed (fixed 2026-08-23). To close: grep both files ('file:line:' parsing) in the gateCountClaims arm.]]>
</note>
</target>
</notes>
</ctx>
```

**Shaped by:** `--no-redact`

### `--pack-task="TASK"`

**Answers:** the budget-shared task bundle: ONE call assembling, under ONE deterministic budget (default 6K tokens;

--token-budget overrides), the whole orientation dance in FIXED order — (1) routed+anchored ranking, (2) top-K full bodies, (3) their 1-hop caller signatures, (4) their field notes, (5) tests_to_run for the top files, emitted in FIXED order ranking>bodies>callers>notes>tests. Each section holds a FIXED, up-front proportional quota of the budget (rank40/body30/caller15/note5/test10, percent); an under-spent section's leftover quota ROLLS FORWARD to the next section, so a small budget still zeroes a section eventually but never past its own fair share. Each section truncates rank-adaptively and the header reports EVERY truncation (no silent caps). A tiny budget degrades to ranking-only WITH the truncation note. Refuses loudly without a task string.

**Try it**

_ONE budget-shared bundle: ranking + top bodies + caller sigs + notes + tests_to_run. CHANGED: <d> rows now carry n=/id=._

```
$ ./build/ripwire . --pack-task="add a new output format flag to the CLI"
<ctx task="add a new output format flag to the CLI" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." est_tokens="3670" budget_tokens="6000">
<!-- ripwire task bundle for "add a new output format flag to the CLI": one-call orientation under ONE budget — sections in FIXED order ranking > bodies > callers > notes > tests, quotas per section are FIXED (rank40/body30/caller15/note5/test10, percent of budget), unused quota ROLLS FORWARD to the next section — a small budget still zeroes a section, but never past its own share. each truncates rank-adaptively; every truncation reported here (no silent caps): on every section shown=rows kept, total=rows that qualified, capped=1 when they differ. bodies fill rank-first, so a bigger budget can keep FEWER, larger bodies — the count is not a quality measure. Row keys: n=name (chain it), id=canonical(when scoped), in=reuse-count (absent = not measured, never a false 0), l=line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller|callee, r=rank in this ranking (rows in r= order); far=ranked but over 1 hop out; of_top denominator is per-section. callers: sorted by shared desc (ties=site order); shared=# of top-K anchors reached, omitted at 1. On the root: est_tokens= prices the delivered bundle in tokens (markup at the map rate, bodies at the body rate), budget_tokens= is the token target; over_ceiling= is 1 when est_tokens exceeds it (the bundle is then complete, not trimmed). budget=12744 bytes (6000-token target, ceiling 14160) | ranking: full | bodies: 6 of 6 | callers: 13 of 13 | notes: none | tests: none | far: 6 of 6 -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<sigs>
<d l="103" n="toUint" id="src/tracein.h::detail::toUint" p="src/tracein.h" cx="3" ccx="3" in="3" r="1" next="--expand=src/tracein.h:toUint">
<doc>F7: a hostile/garbled frame line number (e.g. a fuzzed or truncated trace) can exceed UINT32_MAX; unchecked `v*10+d` wraps mod 2^32 (4294967297 -&gt; 1), which then confidently maps to a REAL line in the</doc>inline std::uint32_t toUint( std::string_view s, bool&amp; overflowed ) noexcept</d>
<d l="253" n="McpValueSpec" id="src/mcprefusal.h::McpValueSpec::McpValueSpec" p="src/mcprefusal.h" cx="0" ccx="0" in="0" r="2">
<doc>verifier N2/N3/N11: the bad-VALUE refusal table</doc>struct McpValueSpec</d>
<d l="2366" n="kJsonShapeModifiers" p="src/main.cpp" cx="0" ccx="0" in="0" pure="1" r="3">
<doc>B1.4: the output-SHAPE members of the list above, as a table rather than a second if-chain. A flag in here selects an ENCODING for rows some verb already produced, so &quot;--json is not supported for X</doc>inline constexpr std::string_view kJsonShapeModifiers[] =</d>
<d l="2772" n="kHandWrittenFlagArms" id="src/cli.h::rw::kHandWrittenFlagArms" p="src/cli.h" cx="0" ccx="0" in="0" pure="1" r="4">
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--token-budget`, `--for`, `--test-gate`, `--expand`, `--compress`, `--no-redact`, `--partition`

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
<ctx-partitions partitions="3" requested="3" core_symbols="6" surface="42" modules="19" split="0" budget_per_agent_tokens="6000" core_budget_tokens="2040" partition_budget_tokens="3960" total_bytes="22716" overlap_mean="0.016" overlap_max="0.033" shared_symbols="3" union_symbols="88" core_overlap="0 … [line truncated: 6 more bytes on this line]
<!-- ripwire partitioned task bundle: ONE shared core plus N minimally overlapping slices along call-graph communities; each <bundle> is one agent's ctx. requested=N asked, partitions= carved; modules=/split= groups found / cuts forced; core_symbols= the shared core, surface= core plus the assignable remainder; budget_per_agent_tokens= core plus ONE partition (= core_budget_tokens + partition_budget_tokens), total_bytes= all bundles; overlap_mean=/overlap_max= pairwise Jaccard over the ids partitions name, pre-trim; shared_symbols= the ids TWO OR MORE partitions name, union_symbols= ids any names (ratio and overlap_mean COINCIDE at partitions=2 only); core_overlap= the core surface a partition reaches anyway; tokens= = est_tokens= (bytes / 2.36). Each ctx carries NO legend: the task-bundle legend follows once; a trimmed slice carries one data comment. -->
<!-- ripwire task bundle (every ctx below): one-call orientation under ONE budget — sections in FIXED order ranking > bodies > callers > notes > tests, quotas per section are FIXED (rank40/body30/caller15/note5/test10, percent of budget), unused quota ROLLS FORWARD to the next section — a small budget still zeroes a section, but never past its own share. each truncates rank-adaptively; every truncation reported here (no silent caps): on every section shown=rows kept, total=rows that qualified, capped=1 when they differ. bodies fill rank-first, so a bigger budget can keep FEWER, larger bodies — the count is not a quality measure. Row keys: n=name (chain it), id=canonical(when scoped), in=reuse-count (absent = not measured, never a false 0), l=line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller|callee, r=rank in this ranking (rows in r= order); far=ranked but over 1 hop out; of_top denominator is per-section. callers: sorted by shared desc (ties=site order); shared=# of top-K anchors reached, omitted at 1. On the root: est_tokens= prices the delivered bundle in tokens (markup at the map rate, bodies at the body rate), budget_tokens= is the token target; over_ceiling= is 1 when est_tokens exceeds it (the bundle is then complete, not trimmed).  -->
<bundle role="core" symbols="6" bytes="2785" tokens="1180" est_tokens="1180">
<ctx task="add a new output format flag to the CLI" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." dropped_positive="2" est_tokens="963" budget_tokens="2040">
<!-- slice budget=4332 bytes (2040-token target, ceiling 4814) | ranking: capped | bodies: kept 4 of 6 (capped) | callers: kept 1 of 13 | notes: none | tests: none | far: none -->
<sigs shown="4" total="6" capped="1">
<d l="103" n="toUint" id="src/tracein.h::detail::toUint" p="src/tracein.h" cx="3" ccx="3" in="3" r="1" next="--expand=src/tracein.h:toUint">
<doc>F7: a hostile/garbled frame line number (e.g. a fuzzed or truncated trace) can exceed UINT32_MAX…</doc>inline std::uint32_t toUint( std::string_view s, bool&amp; overflowed ) noexcept</d>
<d l="253" n="McpValueSpec" id="src/mcprefusal.h::McpValueSpec::McpValueSpec" p="src/mcprefusal.h" cx="0" ccx="0" in="0" r="2">
<doc>verifier N2/N3/N11: the bad-VALUE refusal table</doc>struct McpValueSpec</d>
<d l="2366" n="kJsonShapeModifiers" p="src/main.cpp" cx="0" ccx="0" in="0" pure="1" r="3">
<doc>B1.4: the output-SHAPE members of the list above, as a table rather than a second if-chain. A fl…</doc>inline constexpr std::string_view kJsonShapeModifiers[] =</d>
... [18 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- LIMITS: overlap_mean/overlap_max are pairwise Jaccard over the ids each partition NAMES (window + bodies + their 1-hop neighbors) measured BEFORE budget trimming — a ceiling, not the trimmed truth;
- and on a task whose surface sits inside one module the split is a rank cut, not a semantic one (read split= and overlap_max before trusting the slices).
- Refuses loudly without --pack-task, or outside 2..16;

### `--with-graph`

**Answers:** (with --for/--pack-task) append a compact MERMAID flowchart of the bundle's top-N (<=8) ranked anchors + their 1-hop call edges among themselves — <graph fmt="mermaid"><![CDATA[ flowchart LR ...]]></graph>, right before </ctx>.

Reuses the --mermaid emitter's syntax. Costs tokens beyond the sigs it sits next to — worth it only when the reading agent renders mermaid natively. Off by default and purely additive: omitted, output is byte-identical.

**Try it**

_Task lens + a compact Mermaid flowchart of the top anchors' 1-hop edges._

```
$ ./build/ripwire . --for="pagerank power iteration" --with-graph
<ctx task="pagerank power iteration" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="5f71cb4fd+dirty" doc_mentions="4" bundle="compact" bodies="0" reason="compact-route" est_tokens="3926">
<!-- ripwire lens for "pagerank power iteration" [doc mentions: 4 docs discussing 3 top-ranked symbols surfaced; doc_mentions= on the root repeats the doc count] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=compact: conceptual query, so this map ships one-hop EDGE context, no bodies (bodies=0, reason=compact-route or no_candidates). hops rows are h l=line p=file n=name, and a row's calls child names its callees (c n= l=). hops and calls disclose total=requested shown=printed capped=1 when the BUDGET cut a listing; noedge=N counts ranked symbols with no RESOLVED callee found (never none exists). For a body: expand=p:n pasted off a row; the auto-bodies flag puts the bodies back; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="16" est_tokens= prices this bundle in tokens -->
<sigs shown="24" total="40" capped="1">
<d l="40" n="HOT_FILES" p="scripts/optremarks.py" cx="0" ccx="0" in="0" churn="3" amp="37" r="1" next="--expand=scripts/optremarks.py:HOT_FILES">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix ent … [line truncated: 42 more bytes on this line]
<d l="73" n="renderDisclosure" id="src/prconverge.h::rw::renderDisclosure" p="src/prconverge.h" cx="12" ccx="15" in="13" churn="2" amp="30" r="2">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
<d l="51" n="RankDisclosure" id="src/prconverge.h::RankDisclosure::RankDisclosure" p="src/prconverge.h" cx="0" ccx="0" in="0" churn="2" amp="17" r="3">
<doc>What a ranked document discloses about the power iteration that ordered it. `isPageRank == false…</doc>struct RankDisclosure</d>
<d l="2492" n="RankedGraph" id="src/graph.h::RankedGraph::RankedGraph" p="src/graph.h" cx="0" ccx="0" in="0" churn="60" amp="195" r="4">
<doc>What a rank call hands back: the vector, and the power iteration&apos;s own account of itself. Struct…</doc>struct RankedGraph</d>
... [20 more line(s); run it to see the whole thing]
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

**Shaped by:** `--legend`

### `--batch=FILE`

**Answers:** one-turn context sweep: FILE ('-'=stdin) is newline-delimited `verb:arg` sub-queries (for/grep/callers/callees/impact/uses/mentions/analyze/lego/owners/cochange/exemplar, path_between:FROM,TO), answered in ONE deduped <batch>;

caps at 16 (over-cap = capped=1). THE SAME `verb:arg` line is accepted by the MCP `batch` verb's queries array (queries=["for:parse the config","callers:escapeXml"]), which also takes the {verb, ...args} object form — one grammar to learn, both front doors.

**Try it**

_One-turn sweep: 4 newline-delimited verb:arg sub-queries answered in ONE deduped <batch>._

```
$ ./build/ripwire . --batch=<scratch>/aux/batch2.txt
for:incremental cache invalidation
callers:rankGraphTeleport
grep:DEGRADED_PATH_ALERT
lego:Vehicle
```

**Shaped by:** `--no-redact`

**Caveats (stated by the binary):**

- one-turn context sweep: FILE ('-'=stdin) is newline-delimited `verb:arg` sub-queries (for/grep/callers/callees/impact/uses/mentions/analyze/lego/owners/cochange/exemplar, path_between:FROM,TO), answered in ONE deduped <batch>;
- caps at 16 (over-cap = capped=1).

---

## self-diagnosis

### `--doctor`

**Answers:** environment self-check: binary-vs-PATH staleness, grammar tags.scm compile, cache-dir health, git reachability, tree-sitter version, INDEX IDENTITY, and TRACKED-BINARY staleness (a committed binary whose last commit is a git-history ANCESTOR of a same-directory/same-stem source's last commit — never mtime, which a fresh clone stamps at checkout time).

"Dependent source" is a NAMING heuristic (same dir, same filename stem, e.g. tool <-> tool.cpp) — ripwire parses no build system, so a binary built from a differently-named or differently-located source is silently out of scope, neither flagged nor cleared. Single-root only. DIAGNOSTIC, not deterministic (env-dependent by design); exit 0 iff all ok, else 1. Root reports <doctor checks=N passed=M ...>; each <c/> child row carries the BOOLEAN ok="0|1". passed= is the root's count (it was spelled ok= until the vocabulary pass, which collided with the child bool). A FAILING row (ok="0") also carries hint=, the derived verdict (which of self=/which= is stale and the fix, which grammar(s) failed to compile, why the cache dir isn't writable, ...) — a passing row never carries hint=. The index-cache row states the INDEX-VERSION CONTRACT — cache_version=, parser_ver_lean=, parser_ver_rich=, artifact_arch= — the four numbers that decide whether a committed --index-out artifact is reusable at all, and which appear in no other output. lean=/rich= then say whether THIS binary can open the artifact this root would consume (source="auto" its per-root blob, "cache-flag" the file you named, "disabled" under --no-cache), naming WHICH guard refused it: ok | absent | not-regular | unreadable | truncated | not-a-cache | format-version | parser-version | artifact-arch | checksum | corrupt-frame. BOTH families are reported because a team that commits only the lean artifact gets no warm hit on --for/--exemplar/--metrics/--uses. This is a FORMAT verdict about an artifact, never a freshness verdict about an index: every invocation re-validates each file, so a non-ok lean= costs speed, never correctness — the run cold-parses instead. Only an artifact you NAMED with --cache= and this binary cannot read is ok="0" (a missing auto blob is the ordinary cold-start miss, not sickness). The root carries TWO shas, and they answer different questions: at= is the TREE's HEAD (+dirty) right now, built_from= is the commit THIS BINARY was compiled from (byte-identical to --version's own built_from=). They differ from the moment you commit until the next build — normal, so a mismatch is reported, never gated; a stale PATH copy shadowing a fresh build is the binary-path row's job and is decided on inode/mtime/size, not on this sha.

**Try it**

_Environment self-check: binary staleness, grammars, cache dir, git, tracked-binary staleness — exit 1 when any check fails (here: the PATH install is older than ./build)._

```
$ ./build/ripwire . --doctor
<!-- doctor: checks=/passed= are the row count/how many passed; each <c name= ok=> is one check, its OTHER attributes are check-specific (see help). cache-dir's blobs= is capped at 4096 (kMaxCacheBlobCount); blobs_floor="1" means the cap fired and blobs= is AT LEAST that many, not exactly (absent = the true count); truncated="1" covers that AND an I/O error mid-scan, so blobs_floor= is the narrower, more useful claim when both matter. volatile= on a row NAMES that row's own attributes that read LIVE machine state — cache-dir scans a per-user directory every ripwire process writes into, so two runs of this deterministic binary legitimately differ in exactly those fields and in nothing else; a determinism comparison strips the named attributes, never the row. tracked-binaries' truncated="1" means the git-history scan was SKIPPED entirely (too many tracked files), so its stale="0" there means unmeasured, never a clean scan. index-cache states the INDEX-VERSION CONTRACT (cache_version/parser_ver_lean/parser_ver_rich/artifact_arch — an artifact is reusable only by a binary carrying all four) and, for the artifact this root would consume, whether THIS binary can open it: lean=/rich= are one of ok | absent | not-regular | unreadable | truncated | not-a-cache | format-version | parser-version | artifact-arch | checksum | corrupt-frame, plus disabled (the no-cache flag: nothing was consulted, which is neither ok nor absent). That is a FORMAT verdict on an artifact, NEVER a freshness verdict on the index: every invocation re-validates each file, so an answer is not stale because lean= is not ok — it is merely slower. source= says whether the artifact was named on the cache= flag or picked automatically, and only a NAMED artifact this binary cannot read is ok="0" (a missing auto blob is the ordinary cold-start miss). NB no flag below is spelled with its leading dashes: an XML comment may not contain a double hyphen, and this legend is one comment. -->
<doctor checks="7" passed="6" at="5f71cb4fd+dirty" built_from="5f71cb4fd">
<c n="binary-path" ok="0" self="./build/ripwire" which="/opt/homebrew/bin/ripwire" on_path="1" same_file="0" self_mtime="1788659328" self_size="43221048" which_mtime="1788649546" which_size="41034592" hint="STALE: /opt/homebrew/bin/ripwire is  … [line truncated: 233 more bytes on this line]
<c n="grammars" ok="1" loaded="21" expected="21"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="4096" blobs_floor="1" bytes="1573502151" many="1" truncated="1" volatile="blobs,blobs_floor,bytes,many,truncated"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="5f71cb4fd"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="21"/>
<c n="tracked-binaries" ok="1" tracked="2023" binaries="7" non_git="0" truncated="0" stale="0"/>
<c n="index-cache" ok="1" cache_version="15" parser_ver_lean="77" parser_ver_rich="78" artifact_arch="16" source="auto" lean_path="<tmp>" rich_path="<tmp> … [line truncated: 74 more bytes on this line]
</doctor>
```

**Shaped by:** `--agent`

**Caveats (stated by the binary):**

- "Dependent source" is a NAMING heuristic (same dir, same filename stem, e.g.
- A FAILING row (ok="0") also carries hint=, the derived verdict (which of self=/which= is stale and the fix, which grammar(s) failed to compile, why the cache dir isn't writable, ...) — a passing row never carries hint=.
- This is a FORMAT verdict about an artifact, never a freshness verdict about an index: every invocation re-validates each file, so a non-ok lean= costs speed, never correctness — the run cold-parses instead.

### `--agent=codex|claude`

**Answers:** (with --doctor) also inspect that agent's LIVE CLI-first integration: PATH binary, exact installed-skill manifest parity, advisory hook executability, and the secondary mcp_servers.ripwire command/--mcp args.

Read-only; emits fixed repair commands and never prints config contents or shell command lines. Other values refuse.

**Try it**

_--doctor plus a LIVE integration inspection for one agent: PATH binary, installed-skill manifest parity, hook executability, MCP wiring — read-only, fixed repair commands, never config contents; exit 1 when any check fails._

```
$ ./build/ripwire . --doctor --agent=claude
<!-- doctor: checks=/passed= are the row count/how many passed; each <c name= ok=> is one check, its OTHER attributes are check-specific (see help). cache-dir's blobs= is capped at 4096 (kMaxCacheBlobCount); blobs_floor="1" means the cap fired and blobs= is AT LEAST that many, not exactly (absent = the true count); truncated="1" covers that AND an I/O error mid-scan, so blobs_floor= is the narrower, more useful claim when both matter. volatile= on a row NAMES that row's own attributes that read LIVE machine state — cache-dir scans a per-user directory every ripwire process writes into, so two runs of this deterministic binary legitimately differ in exactly those fields and in nothing else; a determinism comparison strips the named attributes, never the row. tracked-binaries' truncated="1" means the git-history scan was SKIPPED entirely (too many tracked files), so its stale="0" there means unmeasured, never a clean scan. index-cache states the INDEX-VERSION CONTRACT (cache_version/parser_ver_lean/parser_ver_rich/artifact_arch — an artifact is reusable only by a binary carrying all four) and, for the artifact this root would consume, whether THIS binary can open it: lean=/rich= are one of ok | absent | not-regular | unreadable | truncated | not-a-cache | format-version | parser-version | artifact-arch | checksum | corrupt-frame, plus disabled (the no-cache flag: nothing was consulted, which is neither ok nor absent). That is a FORMAT verdict on an artifact, NEVER a freshness verdict on the index: every invocation re-validates each file, so an answer is not stale because lean= is not ok — it is merely slower. source= says whether the artifact was named on the cache= flag or picked automatically, and only a NAMED artifact this binary cannot read is ok="0" (a missing auto blob is the ordinary cold-start miss). NB no flag below is spelled with its leading dashes: an XML comment may not contain a double hyphen, and this legend is one comment. -->
<doctor checks="10" passed="8" agent="claude" at="5f71cb4fd+dirty" built_from="5f71cb4fd">
<c n="binary-path" ok="0" self="./build/ripwire" which="/opt/homebrew/bin/ripwire" on_path="1" same_file="0" self_mtime="1788659328" self_size="43221048" which_mtime="1788649546" which_size="41034592" hint="STALE: /opt/homebrew/bin/ripwire is  … [line truncated: 233 more bytes on this line]
<c n="grammars" ok="1" loaded="21" expected="21"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="4096" bytes="1459630038" many="1" truncated="0" volatile="blobs,blobs_floor,bytes,many,truncated"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="5f71cb4fd"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="21"/>
<c n="tracked-binaries" ok="1" tracked="2023" binaries="7" non_git="0" truncated="0" stale="0"/>
<c n="index-cache" ok="1" cache_version="15" parser_ver_lean="77" parser_ver_rich="78" artifact_arch="16" source="auto" lean_path="<tmp>" rich_path="<tmp> … [line truncated: 74 more bytes on this line]
<c n="claude-binary" ok="0" on_path="1" same_file="0" copied_heuristic="0" hint="reinstall the current build so Claude Code shell calls and this doctor resolve the same ripwire binary"/>
<c n="claude-skills" ok="1" manifest="1" declared="18" live="18"/>
<c n="claude-hooks" ok="1" configured="1" nudge_refs="2" route_hook="1"/>
</doctor>
```

**Caveats (stated by the binary):**

- emits fixed repair commands and never prints config contents or shell command lines.

### `--skipped`

**Answers:** WHY the index does not contain a file, and which files it DOES contain but cannot vouch for.

<f p= why= bytes=/> per DROPPED file: why=oversize (limit= names the ceiling — --max-file-size, or the fixed .json/.yaml config ceilings it does not raise), why=excluded (--exclude hit), why=unsupported-ext (ext= has no grammar in this build — the class that hides a whole LANGUAGE). <h p= why= err= err_ratio= ws_freq=/> per INDEXED-but-suspect file, nothing dropped: why=degraded-parse (the parse holds ERROR/MISSING nodes — a parser-state fact, never a syntax verdict) and/or why=minified-suspect (ws_freq under 0.070 over the leading 4KB). <e x= files=/> per unindexed extension — what the map header rolls up as unindexed=. <lang n= files= symbols=/> per LANGUAGE this build DID extract from — the mirror of unindexed= (which names what it could NOT read at all); sorted files DESC then name ASC, absent means the language contributed nothing, never a printed zero; files= is a floor (a file with zero extracted symbols is not attributed to any language), symbols= is exact. The root states the ACCOUNTING INVARIANT indexed= + oversize= + excluded= = the enumerated candidate population, plus unsupported_ext=, excluded_dirs= (SUBTREES --exclude pruned: contents UNKNOWN, not zero), pruned_dirs= (SUBTREES this build always prunes by policy — the committed noise/vendor/build denylist and any dir holding a CMakeCache.txt — contents likewise UNKNOWN), degraded_parse=, minified_suspect=, unmeasured= (indexed files this run never parsed) and the effective ceilings, so a zero-row report still states its bounds. rows_capped="1" ⇒ rows are a sample of an exact count. Rows sort by path; composes with --max-file-size/--exclude and multi-root (rows carry the <label>/<rel> spelling). Read-only; exit 0 always: a report, not a gate.

**Try it**

_WHY a file is not in the index (oversize / excluded / unsupported-ext / gitignored) and which indexed files it cannot vouch for (degraded-parse, minified-suspect), plus the per-language census._

```
$ ./build/ripwire . --skipped
<ctx>
<!-- ripwire skipped report: WHY the index does not contain a file, and which files it DOES contain but cannot vouch for. Two row kinds. <f p= why= bytes= .../> = a file the crawl passed over, one row per drop, why= being oversize (exceeded a size ceiling; limit= names which — the max-file-size flag's value in max_file_size=, or the fixed .json/.yaml config ceilings that flag does not raise, json_ceiling=), excluded (matched an exclude substring; ext= is its extension), or unsupported-ext (ext= has no grammar and no doc handler in this build — the class that hides a whole LANGUAGE). <h p= why= .../> = a file that IS indexed and stays indexed, flagged for the reader: why=degraded-parse means the parse contains ERROR/MISSING nodes (err= counts them, err_ratio= is the share of the file's bytes covered by top-most ERROR spans) and is a PARSER-STATE fact, never a syntax verdict — a valid file in a dialect this grammar predates reads degraded too; why=minified-suspect means whitespace frequency ws_freq= is under 0.070 across the leading 4096 bytes (files under 256 bytes are never flagged — too little text to judge). Nothing here is dropped by these two flags. <lang n= files= symbols=/> = corpus composition BY LANGUAGE: one row per language this build extracted at least one symbol OR one file for, sorted files DESC then name ASC, absent languages simply not rowed. files= is a FLOOR (derived from symbol-bearing files only — a file with zero extracted symbols is not attributed to any language); symbols= is exact, every run. unindexed= (below) is its mirror: languages this build could not read at all; this is what it DID read, broken down. HEADER: indexed= is files= on the map; the ACCOUNTING INVARIANT is indexed= + oversize= + excluded= = the candidate population the crawl ENUMERATED, at every ceiling and exclude setting. unsupported_ext= counts source/text-looking files outside that population (binary/asset extensions are deliberately not counted — an unindexed .png is a picture, not a language this build failed to read); its per-extension breakdown is the <e x= files=/> rows, which the map header rolls up as unindexed= — a TOP-6 list, and the map's unindexed_exts= beside it names how many DISTINCT such extensions exist, present exactly when that list was cut and absent when it is complete. excluded_dirs= counts SUBTREES an exclude pruned: the walk stopped at the directory, so how many files are under them is UNKNOWN, not zero, and they are in no count here. pruned_dirs= counts the subtrees this build ALWAYS prunes by policy — the committed noise/vendor/build denylist and any directory holding a CMakeCache.txt — with the same consequence: the walk stopped there, their contents are UNKNOWN rather than zero, and they are in no count here. The two are separate because the answer to "why is my tree missing" differs: one is a rule you passed, the other is a rule this build carries. degraded_parse= / minified_suspect= count the h rows. ignored= is ignored_files= on the map: files git's OWN ignore rules cover (.gitignore / .git/info/exclude / core.excludesFile), tested LAST — after the extension, the exclude and the built-in denylist — so it only ever counts a file that would OTHERWISE have been indexed, and the accounting invariant above reads indexed= + oversize= + excluded= + ignored=. ignored_dirs= counts SUBTREES those rules pruned, with the same consequence excluded_dirs= carries: the walk stopped at the directory, contents UNKNOWN rather than zero. Both classes are rowed (why="ignored" for the files, why="ignored-dir" for the subtrees, bytes="0" on a subtree because a directory has no size this verb can honestly report). ignore_mode= names WHICH rule set applied: git (consulted and applied), off (the no-ignore flag), unavailable (no git work tree at this root, or no git binary — the full walk), root-ignored (the root is ITSELF inside an ignored subtree, so honouring the rules would empty the map — the full walk). Only ignore_mode="git" can put a non-zero number beside the two counters; every other mode means nothing was consulted, which is not the same claim as nothing being ignored. unmeasured= counts indexed files this run never parsed (a doc-format file extracted by the doc pass, a binary sniff or nesting guard refusal, a read failure) — they are absent from the health counts, not clean. rows_capped="1" means a row list hit its 500-row ceiling, so the rows are a SAMPLE of the count beside them; every count stays exact. A zero means none found. -->
<skipped indexed="1590" oversize="15" excluded="0" unsupported_ext="170" excluded_dirs="0" pruned_dirs="4" ignored="0" ignored_dirs="0" ignore_mode="git" degraded_parse="64" minified_suspect="1" unmeasured="5" max_file_size="4194304" json_ceiling="262144" yaml_ceiling="524288" root=".">
<f p="bench/locbench/full560.json" why="oversize" bytes="679702" limit="262144"/>
<f p="bench/locbench/results/r1_anchorhop/heldout_baseline_release.json" why="oversize" bytes="365776" limit="262144"/>
<f p="bench/locbench/results/r1_anchorhop/heldout_candidate_release.json" why="oversize" bytes="365761" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/heldout_baseline.json" why="oversize" bytes="440937" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/heldout_candidate_w3.json" why="oversize" bytes="440925" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/train_w0.json" why="oversize" bytes="342194" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/train_w1.json" why="oversize" bytes="342123" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/train_w2.json" why="oversize" bytes="342117" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/train_w3.json" why="oversize" bytes="342138" limit="262144"/>
<f p="bench/locbench/results/r4_siblift/train_1x1.json" why="oversize" bytes="342197" limit="262144"/>
<f p="bench/locbench/results/r4_siblift/train_1x2.json" why="oversize" bytes="342194" limit="262144"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-ignore`

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

churn-decay = the same prior with each commit weighted 0.5^(age_days/90) instead of counted equally, so recent edits outweigh old ones. Its age clock is HEAD's OWN commit timestamp, never the wall clock, so the default (whole-history) run is byte-stable for a fixed tree; the half-life is disclosed in window=. default pagerank)

**Try it**

_Rank by git change-frequency prior instead of PageRank._

```
$ ./build/ripwire . --rank-by=churn --top-k=5
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENCY over window= (a churn-weighted PageRank, not a raw frequency count), so call-graph structure still shapes k=; top ranks can coincide with rank_by=pagerank when structure and churn agree, and diverge where a heavily-churned symbol has little call-graph support -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1590 symbols=13896 edges=17115 shown=5 est_tokens=996 ambiguous=6100 unresolved=3097 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=20 order=important-first -->
<r at="5f71cb4fd+dirty" root="." rank_by="churn" window="18mo" est_tokens="996" pr_iters="29">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0168">
</s>
<s t="method" n="empty" id="src/infra/svector.h::svector::empty" k="0.0090">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" k="0.0078">
</s>
... [10 more line(s); run it to see the whole thing]
```

**Shaped by:** `--since`

**Caveats (stated by the binary):**

- ranking signal (churn = git change-frequency prior, and stamps its own map with rank_by/window/at so it cannot pass for the structural one;
- Its age clock is HEAD's OWN commit timestamp, never the wall clock, so the default (whole-history) run is byte-stable for a fixed tree;

### `--format=xml|columnar|rows`

**Answers:** output shape for the FLAT list verbs (--callers/--callees/--uses/--impact): xml (default, byte-identical) or columnar (a <paths> table + parallel arrays: fields= path,name,line,kind on --callers/--callees/--impact, path,line,role,in_id on --uses — the emitted block's own legend states the zip/n=/&#44;-escape contract;

~15-60% fewer tokens on multi-row results, by de-duplicating the repeated per-row markup + paths; results of a few rows can be LARGER — the paths/cols scaffold has a fixed cost). rows is an alias for columnar. Any OTHER verb refuses (exit 1) — it has no row list to re-encode. Map is unaffected.

**Try it**

_An unknown --format value REFUSES (exit 1), named, with the supported set listed._

```
$ ./build/ripwire . --callers=rankGraphTeleport --format=bogus
(empty)
```

**Shaped by:** `--top-k`, `--pack-signatures`, `--json`, `--limit`

**Caveats (stated by the binary):**

- Any OTHER verb refuses (exit 1) — it has no row list to re-encode.

### `--format=candidates`

**Answers:** (with --for/--query) a FLAT top-K export for an EXTERNAL reranker: one <cand r= s= n= id= k= p= l=><sig>..</sig></cand> row per result — identity + score + signature only, no lens/quality extras, no doc bodies.

Composes with --top-k.

**Try it**

_An unknown --format value REFUSES (exit 1), named, with the supported set listed._

```
$ ./build/ripwire . --callers=rankGraphTeleport --format=bogus
(empty)
```

**Shaped by:** `--top-k`, `--pack-signatures`, `--json`, `--limit`

### `--legend=full|compact`

**Answers:** output legend posture for EVERY XML verb.

full is byte-identical to the default. compact keeps every row byte and every data/completeness attribute (counts_floor= capped= shown= total= has_more= next_offset= est_tokens= at= root= graph_ambiguous= …), adds a versioned schema id on the root (schema="ripwire.<verb>/v1") and replaces the explanatory prose with ONE <=400 B legend naming those attributes — the meanings live here and in the full legend. DATA comments stay (the map header, pack-task's body-omitted rows, +more). Per call this drops 2.9-5.2 KB on the navigation verbs (--edit-check 5.2 KB -> <0.4 KB); the MCP twin is the argument legend: on every XML-answering verb, where compact is the DEFAULT and legend:"full" restores this prose (M1, 2026-09-05: the ten-verb MCP edit loop pays 2,866 B of legend instead of 30,839 B). The CLI default stays full. Runs with nothing to compact refuse it, naming the verb: prose/markdown/JSON answers (--situ --recall --report --mermaid --html --plan-lanes --sarif --eval*) and the writers (edit verbs, --note-add, --quality-baseline/--quality-ack, --index-out, --export).

**Try it**

_The same gating report under --legend=compact — same rows, same exit 2, schema="ripwire.quality-delta/v1", ~4 KB of legend down to one comment: the shape an agent's edit loop should run._

```
$ ./build/ripwire . --quality-delta --legend=compact
<!-- ripwire quality-delta ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. at=: commit(+dirty). next=: the one pasteable follow-up. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="8" minor="2" acked="0" stale="19" preexisting-worse="5" new-symbol="3" gating="5" register-macro-excluded="3" at="5f71cb4fd+dirty" renames="55" rename_window_commits="400" acked_by_rename="0" acked_by_content="0" renam … [line truncated: 24 more bytes on this line]
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" sev="minor" surface="new-symbol" origin="new-symbol" p="src/infra/sortutil.h:119"/>
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:109" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" sev="minor" surface="new-symbol" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:119" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
... [22 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- Runs with nothing to compact refuse it, naming the verb: prose/markdown/JSON answers (--situ --recall --report --mermaid --html --plan-lanes --sarif --eval*) and the writers (edit verbs, --note-add, --quality-baseline/--quality-ack, --index-out, --export).

### `--json`

**Answers:** machine-parseable JSON instead of XML, keys mirror the XML attr names 1:1.

Every ROOT attribute survives; a verb that serves fewer SECTIONS than its XML form NAMES them in lens= on the root (--for --json: lens="compose,lego,routes,docs" — their *_total counts are there, their rows are not) — supported for the default map, --for, --pack-task, --callers/--callees/ --impact, --quality-delta, --test-gate, --metrics (the CI/scripting verbs), plus --plan-lanes which is JSON-native. That set is an ALLOW-list: every other verb (and --format=columnar/candidates, --detail, --map-diff, --scip composed with it) refuses loudly on stderr + exit 1 rather than silently falling back to XML — a verb added tomorrow refuses by default. Deterministic: same 2-run byte-diff + stable key order contract as the XML.

**Try it**

_JSON refusal shape: an unsupported verb refuses loudly instead of silently falling back to XML._

```
$ ./build/ripwire . --hotspots --json
(empty)
```

**Shaped by:** `--max-tokens`, `--token-budget`, `--for`

**Caveats (stated by the binary):**

- That set is an ALLOW-list: every other verb (and --format=columnar/candidates, --detail, --map-diff, --scip composed with it) refuses loudly on stderr + exit 1 rather than silently falling back to XML — a verb added tomorrow refuses by default.

### `--limit=N --offset=M`

**Answers:** paginate a high-cardinality verb.

HONORED by: --deps --callers --callees --tree --lint --hotspots --clones --cochange --owners --communities --community --doc-drift --whereis --grep/--regex --match --pattern --impact --uses --exercises --seams --zoom --external-surface --dead-code --mentions --graph-query --stray-content --test-gate --readability --ensemble --quality-panel --context-ratio --nonlocal-state --comment-coherence --naming-consistency --safe-delete --pr-context. Emit at most N rows, skipping the first M; N overrides the verb's own display cap (40 hotspot files, 30 co-change pairs, 60 whereis hits, 100 grep/match hits, 40 impact rows, 20 seam pairs, 40 readability rows, 40 ensemble symbol rows, 40 context-ratio symbol rows, 40 nonlocal-state rows, 200 graph-query rows / --top-k). With --offset alone (no --limit) the verb's own default page size applies and the root discloses limit="0" — on OUTPUT that 0 means 'no explicit --limit', never a zero-row page (the flag itself refuses --limit=0). A BARE run whose default cap cut rows (capped="1") carries the same limit="0" and the whole paging block below, so you can page from the first answer without guessing. Deterministic seams (rows are already sorted) so --offset=N is the exact continuation of the previous --limit=N page. The root element then carries shown= capped= total= has_more= next_offset= offset= limit= — loop until has_more="0". capped= compares the PAGE to the total (1 ⇔ shown < total), so a page past the end reads shown="0" capped="1" has_more="0": nothing was cut, the offset skipped everything — EXCEPT the verbs with TWO INDEPENDENT listings, which carry the noun-prefixed form instead (one shown= could only describe one): --test-gate shown_tests=/tests_capped= + shown_untested=/untested_capped=, --communities shown_modules=/modules_capped= + shown_bridges=/bridges_capped=, --ensemble and --context-ratio shown_syms=/syms_capped= + shown_files=/files_capped=; the window takes the PRIMARY listing (--test-gate's <u> rows; its <t> rows repeat on every page, complete). Any verb NOT in that list REFUSES both flags (exit 1) rather than accepting and ignoring them: budget/top-k verbs (--for/--recall/--pack-task/--from-trace/ --expand/--outline/--pack-signatures/--format=candidates) are shaped by --top-k/--max-tokens/--token-budget, not a page; the rest (--path/--connect/ --around/--exemplar/--report/--mermaid/--map-diff/--metrics and the default map) answer with a single fixed-shape result that has no row list to window at all.

**Try it**

_The family join: per function, which of four orthogonal evidence families fire, ranked by how many agree._

```
$ ./build/ripwire . --ensemble --limit=8
<!-- ripwire ensemble: the FAMILY JOIN over four orthogonal evidence families, ranked by the COUNT OF DISTINCT FAMILIES that fire and by nothing else. There is NO composite score here, by contract: averaging correlated metrics re-weights one signal and calls it three, and a single quotable number is wrong the moment it is quoted. fam= is ordinal and every row carries its own evidence. The four families are structural (the shape of the code), lexical (the identifier text: the naming rules), confusion (the syntactic construct: the atom rules) and historical (git change frequency, measured PER FILE: every symbol in a file carries that file's churn= and hrank= verbatim, so this family is file evidence inherited by the row, not the row's own history). families=how many families exist eligible=functions and methods with a body, the denominator ranked=eligible symbols where at least one family fired no_family=eligible symbols where none did (ranked= + no_family= = eligible= exactly, on every run). s=one joined symbol: p=path:line n=symbol name fam=how many DISTINCT families fired of=how many families could be EVALUATED at all fired=their names unavail=families that could not be measured here. e=the evidence inside one fired family: f=family name why=the measurements that crossed, space separated; a lexical or confusion rule that fired N times reads rule*N. f=the per-file rollup: p=path top=the file's most corroborated symbol top_l=its line top_fam=its family count union_fam=how many distinct families fire ANYWHERE in the file union=their names syms=symbols in the file with at least one family. top_fam= is the STRONGER claim (several families agreeing on ONE symbol); union_fam= is weaker (different families on different symbols) and the rollup is ranked by the stronger one. THRESHOLDS, all stated here. Four structural signals are ABSOLUTE bars, reused verbatim from the quality-delta bars: bar_ccx=cognitive complexity bar_loc=physical lines bar_nest=max nesting depth bar_params=parameter count; a row shows only the ones that crossed, with the value that crossed. Two signals are RANKINGS with no defensible absolute cut, so each fires for the worst decile of its own ranking, at least one row and at most 40 (each verb's own default window): rrank=the symbol's rank in the readability lens (0 is least readable) rcut=how many ranks that decile covers rmeasured=functions the readability lens measured; hrank=the file's rank by git churn (0 is most changed) churn=its in-window commit count hcut=how many ranks that decile covers hranked=files with any in-window commit window=the churn window. An ordinal cut is RELATIVE: some symbol is always in the worst decile of its own corpus, so rrank= and hrank= mean 'worst in THIS corpus', never 'bad in absolute terms'. The historical family ranks by churn ALONE, not by the hotspots score (churn x complexity), because half of that product is the structural family and two families that cannot disagree are one family counted twice. unavailable=families that could not be evaluated at all, with unavailable_why= saying why, one reason per unavailable family (§L10: both absent, never ="", when every family was measured — house convention, absent means none). UNAVAILABLE is never the same as silent: an ABSENT unavailable= means every family was measured, and a family listed there was NOT measured, so its absence from fired= is not evidence of health. An EMPTY ranking counts as not measured, so hranked=0 makes the historical family unavailable: a corpus scanned from outside the repository that tracks it mines zero churn for every file, and that silence is not a fact about the code. So does an empty LANGUAGE COVERAGE. The confusion family is the atom pack, which by design runs only on C/C++/ObjC/CUDA paths, so on a corpus with no eligible function in one it was never applicable rather than quiet: cfiles=indexed files it can read cscope=eligible symbols inside them, and cscope=0 makes it unavailable. The lexical family is the naming pack, which has no opinion about a data or doc language: lscope=eligible symbols in a language it reads, and lscope=0 makes it unavailable. The structural family has no such precondition - its bars and its readability rank are computed for every language. of= on each row is 4 minus the unavailable families, so a row NEVER counts a family that could not have been evaluated for it, and fam= cannot reach 4 on a corpus where one family was never applicable. unreadable_files=indexed files the readability lens could not read, so rrank= is a floor over what it saw. findings_capped=1 when a lexical or confusion rule spent its per-rule budget, with floor_rules= naming them: those families are then FLOORS and the root carries counts_floor=1. A naming or atom finding that lies outside every function body is not joined to any symbol and is not counted here. shown_syms=symbol rows printed syms_capped=1 when symbol rows were dropped shown_files=file rows printed files_capped=1 when file rows were dropped; the symbol listing is the one limit=N and offset=M window, which also prints total= has_more= next_offset= offset= limit= -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<ensemble families="4" eligible="8013" ranked="3411" no_family="4602" bar_ccx="15" bar_loc="60" bar_nest="4" bar_params="5" rcut="40" rmeasured="8013" hcut="40" hranked="1590" window="12mo" cfiles="500" cscope="4167" lscope="8013" shown_syms="8" syms_capped="1" shown_files="20" files_capped="1" tota … [line truncated: 89 more bytes on this line]
<s p="src/serialize.h:5878" n="packDeps" fam="4" of="4" fired="structural,lexical,confusion,historical">
<e f="structural" why="ccx=110 loc=249 nest=5 params=13 humps=4 deep=14 ev=5 rrank=21"/>
<e f="lexical" why="naming-confusable"/>
<e f="confusion" why="atom-nested-ternary*2"/>
<e f="historical" why="hrank=9 churn=100"/>
</s>
<s p="src/crossref.h:1773" n="evalStray" fam="3" of="4" fired="structural,confusion,historical">
<e f="structural" why="ccx=23 loc=86 ev=9"/>
<e f="confusion" why="atom-assign-as-value"/>
<e f="historical" why="hrank=29 churn=24"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--tree`, `--graph-query`, `--external-surface`, `--exercises`, `--community`, `--zoom`, `--pr-context`

**Caveats (stated by the binary):**

- Emit at most N rows, skipping the first M;
- With --offset alone (no --limit) the verb's own default page size applies and the root discloses limit="0" — on OUTPUT that 0 means 'no explicit --limit', never a zero-row page (the flag itself refuses --limit=0).
- A BARE run whose default cap cut rows (capped="1") carries the same limit="0" and the whole paging block below, so you can page from the first answer without guessing.

### `--exclude=SUBSTR`

**Answers:** drop matching paths (repeatable)   --ignore-tests

**Try it**

_Drop matching paths (repeatable) before ranking._

```
$ ./build/ripwire . --exclude=present --exclude=bench --top-k=5
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1388 symbols=11319 edges=15912 shown=5 est_tokens=725 ambiguous=6060 unresolved=2098 locality_pinned=6 external=104 precise=3 unindexed="txt:48,scm:18,xml:6,tsv:5,cmake:3,jsonl:3" unindexed_exts=15 order=important-first -->
<r root="." est_tokens="725" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0197">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2" k="0.0083">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0116">
</s>
... [6 more line(s); run it to see the whole thing]
```

**Shaped by:** `--skipped`, `--index-out`

### `--map-diff`

**Answers:** the FULL map, re-ranked with a PageRank teleport toward git-changed files (working tree vs HEAD) — changed files and their neighbours float up, but every file can still appear;

this is NOT a filter to only-changed symbols. changed="N" in the header names the seed file count (0 on a clean tree or no-git — teleport degrades to uniform; ranked CONTENT is then identical to the plain default map, but not byte-identical: the map-diff header keeps its changed= and at= stamp). Want only-changed instead? --pr-context.

**Try it**

_Full map re-ranked with teleport toward git-changed files — recorded against a DIRTY tree, so changed= counts the working copy's files and the teleport is live._

```
$ ./build/ripwire . --map-diff --top-k=5
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1590 symbols=13896 edges=17115 shown=5 est_tokens=820 ambiguous=6100 unresolved=3097 locality_pinned=6 external=788 precise=3 changed=0 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=20 order=important-first -->
<r at="5f71cb4fd+dirty" root="." est_tokens="820" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2" k="0.0071">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
... [7 more line(s); run it to see the whole thing]
```

**Shaped by:** `--json`, `--limit`

**Caveats (stated by the binary):**

- this is NOT a filter to only-changed symbols.
- changed="N" in the header names the seed file count (0 on a clean tree or no-git — teleport degrades to uniform;

### `--cache=PATH`

**Answers:** incremental cache at PATH (re-parse only changed files)

**Try it**

_Explicit incremental cache at a path OUTSIDE the repo (first call writes it)._

```
$ ./build/ripwire . --cache=<scratch>/aux/warm2.ripwirecache --top-k=3
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1590 symbols=13896 edges=17115 shown=3 est_tokens=698 ambiguous=6100 unresolved=3097 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=20 order=important-first -->
<r root="." est_tokens="698" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
</f>
<f p="src/scipoverlay.h">
... [4 more line(s); run it to see the whole thing]
```

**Shaped by:** `--doctor`, `--index-out`

### `--index-out=BASE`

**Answers:** CI generate-and-exit: cold-parse the tree and write the committable index artifact, then exit 0 with NO map on stdout.

Writes BOTH families — BASE.lean.ripwirecache (map/ nav/--pr-context) and BASE.rich.ripwirecache (--for/--exemplar/--metrics/--uses are RICH, a lean-only artifact leaves them cold). Consume in a PR job with --cache=BASE.lean.ripwirecache (or .rich.). --exclude shapes the crawl and therefore the blob content. Same-architecture speed cache: consumed on a different arch it self-heals to a full cold parse (correct, slower). NOT byte-identical run-to-run (the header stamps the blob write time); the contract is RESTORE-EQUIVALENCE (a --cache restore == a cold parse), never blob-byte-identity.

**Try it**

_CI generate-and-exit: cold-parse and write BOTH committable cache families (lean + rich), no map on stdout._

```
$ ./build/ripwire . --index-out=<scratch>/aux/ci_index
(empty)
```

**Shaped by:** `--doctor`, `--legend`

**Caveats (stated by the binary):**

- the contract is RESTORE-EQUIVALENCE (a --cache restore == a cold parse), never blob-byte-identity.

### `--no-cache`

**Answers:** disable the warm-by-default per-root TMPDIR cache (forces a cold parse)

**Try it**

_Force a cold parse (bypass the warm TMPDIR cache) — shows the cold-vs-warm cost._

```
$ ./build/ripwire . --no-cache --top-k=3
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1590 symbols=13896 edges=17115 shown=3 est_tokens=698 ambiguous=6100 unresolved=3097 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=20 order=important-first -->
<r root="." est_tokens="698" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
</f>
<f p="src/scipoverlay.h">
... [4 more line(s); run it to see the whole thing]
```

**Shaped by:** `--doctor`

### `--no-ignore`

**Answers:** crawl paths the repository's own .gitignore covers.

DEFAULT: in a git work tree the crawl honours git's ignore rules (node_modules/, .venv/, target/, build/, dist/ — whatever the repo declared), and the header discloses ignored_files= / ignored_dirs= when it dropped anything. A non-git root, a missing git binary, or a root that is ITSELF inside an ignored subtree all keep the full walk; --skipped's ignore_mode= says which of the four applied, and rows the ignored set.

**Try it**

_Crawl paths the repo's own .gitignore covers (default honours it and discloses ignored_files=/ignored_dirs= only when it dropped anything — this repo's crawl drops nothing, so the header is identical to the default map's; --skipped's ignore_mode= says which rule applied)._

```
$ ./build/ripwire . --no-ignore --top-k=3
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1590 symbols=13896 edges=17115 shown=3 est_tokens=698 ambiguous=6100 unresolved=3097 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=20 order=important-first -->
<r root="." est_tokens="698" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
</f>
<f p="src/scipoverlay.h">
... [4 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- --skipped's ignore_mode= says which of the four applied, and rows the ignored set.

### `--max-file-size=N[K|M|G]`

**Answers:** skip files larger than N bytes (default 4MB;

raise for repos with big hand-authored source, e.g. --max-file-size=100M; suffix = 1024^n). .json carries a SECOND, fixed 256KB ceiling this flag does not raise (that size of .json is data, not config, and explodes the symbol table); files it drops are counted in the header's skipped_oversize=

**Try it**

_Skip files above a size bound before parsing (note the corpus shrink in the header)._

```
$ ./build/ripwire . --max-file-size=8K --top-k=3
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=905 symbols=3832 edges=991 shown=3 est_tokens=694 ambiguous=40 unresolved=98 locality_pinned=6 external=125 precise=3 skipped_oversize=700 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=20 order=important-first -->
<r root="." est_tokens="694" pr_iters="41">
<f p="test/extvetofix/ext.py" layer="test">
<s t="fn" n="get" id="test/extvetofix/ext.py::Rep::get" k="0.0035">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="src/scipoverlay.h::ScipOverlay::empty" k="0.0029">
</s>
</f>
<f p="test/scipfix/make_index.py" layer="test">
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

_SCIP overlay with a missing index REFUSES (exit 1) naming the file — never silently serves the name-based map you named a precision index to improve on (it used to degrade in silence)._

```
$ ./build/ripwire . --scip=does_not_exist.scip --callers=rankGraphTeleport
(empty)
```

**Shaped by:** `--json`, `--pin-census`

**Caveats (stated by the binary):**

- consume a SCIP index as a PRECISION overlay: precise call edges replace name-based guesses (tagged prov="scip"), ambiguous= drops.
- Missing/corrupt index → degrades to name-based (never fails).

### `--pin-census=FILE`

**Answers:** eval-only: write a per-call-site census of WHICH mechanism resolved each call (unique/qualified/receiver-rule/cone/arity/locality/split/scip/binding) and the canonical id of every surviving target — the identity <c n="NAME"/> omits.

Under --scip it also writes the index's covered sites, so a precision join needs no protobuf reader. stdout is byte-identical with or without it.

**Try it**

_Eval-only: a per-call-site census of WHICH mechanism resolved each call, and the canonical id of every surviving target._

```
$ ./build/ripwire . --pin-census=<scratch>/aux/pin_census.tsv --top-k=3
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1590 symbols=13896 edges=17115 shown=3 est_tokens=698 ambiguous=6100 unresolved=3097 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=20 order=important-first -->
<r root="." est_tokens="698" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
</f>
<f p="src/scipoverlay.h">
... [4 more line(s); run it to see the whole thing]
```

### `--mcp`

**Answers:** persistent index server (parse once, many warm queries) over stdio

**Try it**

_initialize + tools/list: the manifest an agent host loads at session start — every verb's name, description and input schema._

```
$ ./build/ripwire '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | ./build/ripwire --mcp
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a symbol; run edit_c … [line truncated: 249 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"analyze","description":"Architecture map for a directory: signatures and the call graph for the top symbols. Use when landing cold in a repo or subdir, before reading files; for a task-scoped inventory use 'for', for one symbol's neighborhood find_ … [line truncated: 729 more bytes on this line]
{"name":"find_symbol","description":"A symbol's 1-hop neighborhood: the symbol (with a fetch_body handle) plus direct callers (calledBy) and callees (calls). Full transitive reach: 'impact'. Read/write/import sites, not just calls: 'uses'. JSON {symbol, calledBy, calls, defs, count, hop_tested, hop_ … [line truncated: 1095 more bytes on this line]
{"name":"find_referencing_symbols","description":"Direct (1-hop) callers of a symbol, each with a fetch_body handle. For the full transitive blast radius use 'impact', for read/write/import sites 'uses'. JSON {symbol, calledBy, defs, count, hop_tested, hop_untested, counts_floor}; calledBy is a FLOO … [line truncated: 797 more bytes on this line]
... [30 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-stable`, `--no-redact`, `--agent`, `--listen`

### `--listen=HOST:PORT`

**Answers:** serve the MCP server over Streamable HTTP instead of stdio (implies --mcp).

Binds 127.0.0.1 by default (bare PORT = loopback); one listener serves ONE workspace fixed at startup. A non-loopback host (e.g. 0.0.0.0:8080) REQUIRES --mcp-token and refuses to start without it. No TLS — reverse-proxy it.

**Shaped by:** `--no-stable`, `--allow-remote-edits`

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

_Labelled verdict-accuracy eval for --stray-content — three labels over REAL local refs (names resolved at capture time); exit 3 when accuracy is under the floor. Read got= against v= in the stray-content run: a ref the verb could not analyse (unknown) must never be credited as a merged hit._

```
$ ./build/ripwire . --eval-stray=<scratch>/aux/stray_labels2.tsv
# ref<TAB>verdict labels for --eval-stray (the first three local branches, resolved at capture time; a missing branch is padded with a nonexistent name on purpose)
claude/awesome-swartz-67ebab	merged
claude/determined-panini-f56633	unmerged
claude/exciting-greider-8564fe	merged
```

### `--eval`

**Answers:** self-eval (co-change recall vs BM25)

**Try it**

_Self-eval: co-change recall vs BM25._

```
$ ./build/ripwire . --eval
ripwire --eval  (co-change recovery, averaged over 80 historical commits)
  ranker     recall@5  recall@10  recall@20
  ripwire        0.4%       1.3%       2.1%
  BM25          14.7%      16.2%      20.9%
  BM25sub       12.5%      14.5%      20.5%
  BM25body      12.8%      19.5%      23.7%
  fused          1.8%       5.7%      14.0%
  anchored      12.6%      19.5%      23.7%
  same-dir       1.2%       3.9%       6.2%
  random         0.3%       0.6%       1.3%   <- floor (random ranking over F=1590 files)
  note: `ripwire` here is the DEFAULT MAP's structural-only PageRank (importance, not
        relatedness) — it is NOT what a --for/--query retrieval call ranks with. BM25 /
        BM25sub / BM25body are QUERY-TIME lexical rankers (whole-name / subtoken /
        subtoken+body); fused = RRF(ripwire, BM25sub); anchored = BM25body + anchored PPR
... [5 more line(s); run it to see the whole thing]
```

**Shaped by:** `--legend`

### `--eval-retrieval`

**Answers:** known-item retrieval eval: for symbols WITH a doc-comment, query by NAME and by a doc-comment PHRASE;

reports MRR + recall@1/5/10 per ranker (subtoken+body, name-exact, anchored, routed) per query-mode. Validates query-TIME ranker choice.

**Try it**

_Known-item retrieval eval: MRR + recall@k per ranker per query mode._

```
$ ./build/ripwire . --eval-retrieval
ripwire --eval-retrieval  (known-item, 3499 doc-commented symbols; gold is in-corpus by construction)
  sample: population=3499 scored=3499 rule=exhaustive (every qualifying symbol; path- and order-independent)
  ranker    query-mode     MRR  recall@1  recall@5 recall@10
  subtoken  name         0.724     59.3%     88.9%     93.4%
  subtoken  doc-phrase   0.930     90.8%     95.2%     95.9%
  name-exact name         0.922     85.5%     97.5%     98.4%
  name-exact doc-phrase   0.018      0.6%      2.7%      3.5%
  anchored  name         0.726     60.5%     87.6%     92.1%
  anchored  doc-phrase   0.925     90.0%     94.9%     95.8%
  routed    name         0.922     85.5%     97.5%     98.5%
  routed    doc-phrase   0.929     90.8%     95.0%     95.7%
  note: routing chose name-exact on 3497/3499 NAME queries (a NAME query is always identifier-shaped);
        the confidence gate routes doc-phrase queries to name-exact ONLY when EVERY content word names a symbol
        (or an explicit camel/snake token appears) AND every matched name is specific enough to anchor on —
... [3 more line(s); run it to see the whole thing]
```

### `--eval-mined=FILE`

**Answers:** session-trace-mined retrieval eval: consumes a minedpair.jsonl artifact from bench/mine_traces.py (real (query, gold-files) pairs mined from local Claude Code session transcripts) and reports recall@5/10/20 + Acc@k + MRR per arm (for/query/anchor/random), assisted vs unassisted.

### `--eval-skills=FILE`

**Answers:** labelled skill-ROUTING eval: ROOT is a skills directory (one SKILL.md per subdir);

FILE is TSV `prompt<TAB>skill[,skill]|none<TAB>provenance`. Scores deterministic selectors (keyword overlap = the trivial baseline, BM25 over descriptions/full text, name match, the routed --for ranker) on top-1-in- permitted-set plus positive/negative separation (AUC) — does the right skill fire, does every skill stay quiet on off-topic prompts. Ambiguous moments carry a permitted SET; `none` rows are first-class.

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

### `-h, --help`

**Answers:** this catalog

**Shaped by:** `--color-by`, `--around`, `--callers`, `--callees`, `--affected`, `--expand`, `--metrics`, `--nonlocal-state`

### `-v, --version`

**Answers:** print the version + short build info, exit 0

**Try it**

_Version + short build info._

```
$ ./build/ripwire --version
ripwire 0.3.8 (dev, AppleClang 21.0.0.21000101, built_from=5f71cb4fd)
```

**Shaped by:** `--impact`, `--verify`, `--metrics`, `--deps`, `--naming-locals`, `--arch`, `--dry-run`, `--doc-drift`

---

_Generated by `docs/docs_commands_build.py`. See `docs/README.md` for the documentation index._
