# ripwire — architecture

This document is for a reader deciding whether to **trust** ripwire's output or **extend** its code.
It describes the pipeline, the data model, the determinism contract, how ranking works, and — the
part most tools leave out — the vocabulary the output uses to tell you what it does *not* know.

If you only want to use the tool, read `README.md`, `docs/COMMANDS.md`, or `./build/ripwire --help`.
If you are about to write C++ here, read `CONTRIBUTING.md` first.

---

## 1. The pipeline

```
ingest  →  graph  →  rank  →  serialize  →  cli / mcp
```

Five stages, in that order, with no back edges. Each stage's output is a plain data structure, so
any stage can be tested in isolation and every verb is a different way of reading the same graph.

### ingest — crawl and parse

A single-threaded directory crawl (`collectSources`, `src/ingest.cpp`) that produces a sorted file
list, followed by **parallel** per-file tree-sitter extraction. The crawl is the cheap half and is
deliberately not parallelized; the parse pool is where the threads are.

**Crawl order is deterministic, and that is load-bearing.** The walk *collects every candidate path
first*, sorts them lexicographically by byte, and only then assigns node IDs and parses. Node IDs are
indices into that sorted list, so they are stable across runs of the same tree; if IDs followed
directory order, node IDs, top-K cutoffs, and every diff-aware verb would churn between identical
runs. The parse itself runs one tree-sitter parser per worker thread and merges per-thread result
lists afterwards, which is safe precisely because the definitions and references are re-sorted before
they are used — collection order never reaches the output.

**`.gitignore` is not consulted.** Skipping is a fixed, committed denylist (`kCrawlSkipDirs[]` in
`src/ingest.h`, shared with the CMake walk in `darkflags.h` so the two crawlers cannot disagree about
what counts as source), not a per-repository ignore file. That is a real difference from a
`.gitignore`-aware tool in both directions: a build directory this repository happens not to ignore is
still pruned, and a directory a project ignores but that is not on the list is still indexed. What is
skipped:

- **directories by NAME:** `.git`, `.claude`, `.hg`, `.svn`, `node_modules`, `vendor`, `third_party`,
  `.cache`, `build`, `dist`, `out`, `target`, `.venv`, `venv`, `__pycache__`, `.idea`, `.vscode`,
  `asan`, `build_prof`, `CMakeFiles`, `captures`, and anything matching `cmake-build-*`;
- **any directory containing a `CMakeCache.txt`** — a build-output tree, whatever it is called;
- **paths matching a `--exclude=SUBSTR`** (repeatable), which prunes directories and drops files;
- files over 4 MB (`--max-file-size=N[K|M|G]` overrides);
- files whose first 4 KB contains a NUL byte — the binary sniff. There is no separate UTF-8 validity
  pass: the extractor slices names by byte offset and truncation backs off UTF-8 continuation bytes,
  so a codepoint is never split, but a file is not rejected for failing to decode;
- JSON over 256 KB or nested deeper than 512 levels. The JSON lane indexes *configuration keys*; a
  large or degenerately nested `.json` file is data or a test corpus. The former explodes the symbol
  table; the latter drives tree-sitter's error recovery superlinear — 43 s measured on a 100 KB
  `[[[[…` file. Both cases were found live by benchmarking against real upstream repositories.

**TOML has no lane-specific ceiling, and that is a measured decision rather than a missing sibling.**
Over 90 real public repositories (321 `.toml` files) the largest is 57 759 B — a quarter of the JSON
ceiling and 1.4% of the generic 4 MB skip — so a TOML ceiling could not sit both above the observed
maximum and below the generic one without being unreachable by construction. The substantive
difference from JSON is pathology, not size: TOML is line-oriented, so a malformed line resynchronizes
at the newline instead of nesting, and every adversarial probe stays linear (`[`×100 000 = 17.4 ms,
50 000 `[[aot]]` = 58.7 ms, a 2 MB unterminated string = 21.7 ms). `.toml` therefore rides the generic
`--max-file-size` path only, whose drops are already disclosed through `skipped_oversize=`.

**YAML gets JSON's hazard pair at its own calibration — and its nesting guard is memory-safety
load-bearing, not just a perf guard.** `.yml` wears JSON's problem (a machine-written data class
behind a config extension), but JSON's 256 KB line would drop real hand-maintained config — NeMo's
`cicd-main.yml` is 293 KB — so the YAML ceiling is **512 KB**, counted into `skipped_oversize=` like
its siblings. The nesting guard exists for a different reason than JSON's: tree-sitter-yaml's
external scanner `serialize()` writes 4 bytes per open block indent level behind a loop guard that
only proves 1 byte fits, so at ~254 levels it writes past the end of the 1024-byte serialization
buffer — SIGABRT in a plain build, a *silent* corrupting write under `NDEBUG`. ripwire refuses such
files before any parse via an O(n) indent prescan (`kMaxYamlNestDepth`, an over-approximation that
can only over-count), and the vendored scanner additionally carries the one-line bounds fix under
`third_party/patches/yaml/`, drift-gated so a grammar bump cannot silently revert it.
- **generated artifacts by filename:** `package-lock.json`, `npm-shrinkwrap.json`, `*.min.js`,
  `*_pb2.py`, `*.pb.go`.

Ingest never throws — a bad file, a missing grammar or a corrupt cache degrades and prints a one-line
`DEGRADED_PATH_ALERT` to stderr. **The ordinary denylist prunes above are silent**, deliberately: they
are the normal state of every crawl and a note per skipped directory would be noise, not evidence. The
size-ceiling drops sit between the two — silent on stderr, but *counted* into the header's
`skipped_oversize=N`, so a corpus that shrank says so in the output rather than vanishing quietly.

**Directory symlinks are not followed.** The walk is a `std::filesystem::recursive_directory_iterator`
opened with `skip_permission_denied` only — not `follow_directory_symlink` — so a symlinked directory
is never descended into and a symlink cycle cannot arise. There is no inode tracking, because with
symlink-following off there is nothing for it to do.

**Extraction is query-driven, never hand-rolled.** Each language contributes a vendored tree-sitter
`tags.scm` query plus a small `capture-name → NodeRole` table. One query engine runs over every
language, reading `@definition.*` captures as definitions and `@reference.*` captures as references,
pulling the symbol name from the query's `@name` capture. A constexpr `extension → { ts_language,
tags.scm }` table drives the whole thing. The alternative — a bespoke AST traversal per language —
is forbidden here: it is five fragile walkers that break on every grammar bump instead of one query
loop that survives them.

Concurrency: one tree-sitter parser per worker thread (parsers are not thread-safe), files
dispatched as work items.

Languages: C++, C, Objective-C/Objective-C++, Metal (parsed with the C++ grammar), CUDA (parsed
with the vendored tree-sitter-cuda grammar, a generated superset of tree-sitter-cpp), Python,
TypeScript, JavaScript, Java, Ruby, PHP (the `php/` sub-grammar, so a `.php`/`.phtml` file whose
first byte is markup still indexes), Lua, Bash, Go, Rust, Swift, C#, plus JSON, TOML and YAML
configuration keys.

Two of those carry a stated floor rather than a silence. **PHP**: dynamic dispatch — `$fn()`,
`$obj->$name()`, `call_user_func`, `__call` magic, `new $class` — names its callee at run time, so
those sites produce no edge; a `use` directive is captured for `--uses`/`--deps` but never narrows a
call, because PSR-4 maps a namespace onto a directory through a `composer.json` block this tool does
not read. **Lua**: inheritance *is* `setmetatable( D, { __index = B } )`, an ordinary runtime call
over an ordinary table, so a Lua corpus correctly reports no inheritance edges at all, and `require`
is a plain function call rather than an import directive (as in Ruby), so a `.lua` file is never a
node in the `--deps`/`--arch` graph. Both floors are asserted from the outside by
`test/phpcheck.sh` and `test/luacheck.sh` so they stay decisions rather than drift.

The three config lanes are *data*, not code: they emit `t="sec"` symbols and **zero call edges**, and
`langCompatible` keeps a config key from ever resolving a same-spelled code symbol. They differ in
where the navigable unit sits. JSON cuts at document depth — top-level and second-level object
keys. TOML cuts at the **table header**: `[tool.ruff.lint]` is one symbol under its full dotted
name, and its keys are one level below *it*, whatever the header's dotted depth. Applying JSON's
root-relative rule to TOML would capture 38.3% of keys in the 90-repo breadth corpus and miss every
key under a 2-dotted table, which is the shape 1421 of 2561 observed headers actually have. YAML
cuts at **mapping depth ≤ 2 with sequence levels transparent**: 25.3% of all real YAML keys sit
directly inside a sequence element (the `steps:` / `containers:` / `tasks:` shape) and JSON's rule
drops every one of them — sequence transparency lifts capture from 27.1% to 44.0% on the same
corpus. Block and flow mappings count alike; anchors are part of the value they annotate; aliases
and the `<<:` merge key are dropped, never expanded; each document of a multi-doc stream re-enters
at depth 1; and a block scalar is one value token, so the 384 corpus block scalars containing
key-like text can never mint symbols — the strongest argument for a real parser over a line regex.
A dotted key in any of the three keeps its dots — a `"lodash.merge"` dependency, a
`tool.ruff.lint` table and a YAML `dotted.plain.key:` are names, not scope paths.

### graph — resolve references into edges

This is the hard part, and it is **explicitly approximate**. tree-sitter is syntax-only: no types,
no name resolution, no cross-file knowledge. Linking a reference to the definitions it means is
undecidable without a per-language semantic analyzer, and ripwire does not have one.

The base rule is one fixed precedence ladder, same-language only:

1. a definition in the **same file**; else
2. a definition in the **same directory**; else
3. a **unique** same-language **global** definition; else
4. **drop the edge** — no phantom node is ever invented.

If a name resolves to *k > 1* candidates at the chosen tier, the resolver **does not pick one**: it
emits *k* edges each weighted `1/k`. PageRank tolerates the split and it removes an arbitrary
tiebreak. That `k > 1` event is what the output reports as `amb="K"` on a symbol, and what the header
totals as `ambiguous=N` — the call-graph completeness gauge.

Above that base ladder sit **precise tiers**, added per language where the syntax makes resolution
sound rather than heuristic: qualified calls of three or more segments and explicit-template calls in
C++; scoped, turbofish and `Self::` calls in Rust with a file-module guard; the `?.` family in C#;
qualified `new` in TypeScript, JavaScript and Java. Where a language's syntax does *not* support a
sound rule, the tier is not shipped and the limit is stated — Go's qualified calls are rejected and
fenced rather than guessed at. Where an external precise index exists, `--scip=FILE` overlays it and
the affected edges are marked `prov="scip"`.

**False edges are expected and acceptable.** The deliverable is an importance *ranking*, not a sound
call graph, and the first XML comment in every run says so.

### graph — the CSR

**Nodes are symbols. Files are not nodes.** A file is a serialization attribute. If files were
nodes, their high degree would dominate the ranking.

PageRank propagates rank along **incoming** edges — a node is important if important nodes point at
it — so the power iteration must multiply the transpose. The graph is therefore stored as an
**in-edge CSR**:

- `rowOffsets[]` — per-**target** start, size `nodeCount + 1`
- `colIndices[]` — **source** node IDs
- `values[]` — edge weight

This makes the sparse matrix-vector product a per-row **gather** with one sequential write per
target: race-free, cache-friendly, parallel by row. A CSR keyed by source would force a *scatter*
with random writes and write races — the opposite of what the layout rule wants.

The build is two passes: count in-degree per target and prefix-sum into `rowOffsets`, then scatter
each `(src → dst)` edge into `row = dst` at `col = src`. A separate `wOutDeg[]` (weighted out-degree
per source) carries the `1/outdeg` normalization, plus a dangling mask for `wOutDeg == 0`.

Edge rules:

- **weight** = **mean per-reference confidence × the square root of the reference count**, capped at
  8 (`src/graph.h`, `buildGraph`). Each reference contributes a confidence — its resolution tier,
  deboosted for an over-common name (defined in ≥16 places) or a leading-underscore private one, and
  split evenly when it resolves ambiguously to *k* targets. Those contributions are accumulated per
  `(src → dst)` pair as a sum and a count, and the pair's weight is `(confSum / nref) · √nref`. The
  square root is the point: repeated calls should raise a weight **sublinearly**, so a hot loop
  strengthens an edge without letting call-site multiplicity alone dominate the ranking. The cap at 8
  bounds the tail.
- **dedup is structural, not a merge pass** — the accumulator is keyed by the `(src, dst)` pair, so a
  duplicate pair was never a second entry to collapse; it is the `nref` in the formula above.
  Duplicate columns would double-count in the product, and the CSR is built from that one-entry-per-pair
  list, sorted by `(from, to)`;
- **self-loops are dropped** — in the Google matrix they act as rank sinks that inflate the recursive
  node and steal mass.

### rank — Personalized PageRank

Power iteration over the in-edge CSR, parallelized over **fixed contiguous row blocks**. Constants
live in a named configuration struct, not as literals in the loop: damping `α = 0.85`, L1 residual
tolerance `τ = 1e-6`, `maxIter = 100`, diff-teleport concentration `β = 0.7`.

The teleport vector `p` (with `Σp = 1`) is where personalization lives — and *only* there. Uniform
by default. With `--map-diff`, git-changed files are seeded: `β / changedCount` for symbols in
changed files, `(1 − β) / (nodeCount − changedCount)` elsewhere, normalized.

Boosting the initial vector has **zero** effect at convergence — power iteration forgets its start —
and post-multiplying final ranks by a constant is not personalization either. Both are forbidden;
bias enters through `p` or it does not enter.

The per-iteration update:

```
D = Σ over dangling j of r[j]                              // deterministic block reduce
g[i] = Σ over in-edges (j→i) of w(j→i) · r[j] / wOutDeg[j] // gather
r_new[i] = α·g[i] + α·D·p[i] + (1−α)·p[i]
```

The `α·D·p[i]` term **redistributes dangling mass through the teleport vector**. Code graphs are
mostly sinks — leaf functions, data structs — so without it, mass leaks every iteration, `r` stops
being a probability vector, and the top-K biases toward the dense call core while architecturally
central leaf interfaces collapse toward zero. This is the single thing naive PageRank implementations
get wrong.

Convergence is a residual stop: iterate until `‖r_new − r‖₁ < τ`, else stop at `maxIter` and use
the last iterate. Teleport makes the operator strictly positive, hence primitive, so
Perron–Frobenius guarantees a unique positive dominant eigenvector with `λ₁ = 1` — the iteration is
well-posed, not merely empirical.

#### The convergence disclosure contract

Those two exits produce documents that look identical and do not mean the same thing. The first is
the fixed point the ranking claims to be. The second is a **truncation of the computation** — a rank
vector caught mid-descent, carrying the same `k=` scores, the same ordering, the same confidence.

So the iteration reports itself, and every ranked document carries what it said:

| attribute | meaning |
| --- | --- |
| `pr_iters="N"` | how many power iterations produced this document's ordering |
| `pr_converged="0"` | that iteration stopped at `maxIter` with the residual still above `τ` |

The absence rules are load-bearing and are the same absence rules the rest of the header uses.
**No `pr_converged` means it converged** — there is no `pr_converged="1"`, because the converged
path is the overwhelming majority and must cost zero bytes. **No `pr_iters` at all** means the
document was not ordered by a power iteration: a lexical `--query`/`--for` score, or a HITS
hub/authority vector, both of which replace the PageRank vector outright. `--rank-by=rrf` does carry
it, because PageRank is one of the three vectors it fuses. The map legend defines both names where
the reader meets them; the prose explaining what to do about a truncated ranking is charged only to
the map that actually took that exit. `src/prconverge.h` owns every spelling — XML, JSON, and the
plain line the markdown report and the mermaid diagram emit instead, since neither has an attribute
grammar to hang one on.

Why bother, when the truncating exit cannot fire at the shipped configuration? Because the reason it
cannot fire is arithmetic about *these constants*, not a property of the method. The iteration is an
α-contraction in L1 — the operator is column-stochastic and dangling mass is redistributed through
the teleport prior — so `residual_k ≤ 2·α^k`, and `2·0.85^k < 1e-6` at `k = 90`, inside `maxIter =
100` for any graph whatsoever. (E2 measured 28–52 iterations across four real corpora.) Lower `τ`,
raise `α` toward 1, or hand the ranker a shape the contraction argument stops covering, and the
attribute is what tells a reader before the ranking does.

The mechanism matters as much as the attribute. `DEGRADED_PATH_ALERT` still fires on the truncating
exit and is still the only thing that names *which site* degraded — but it is `#ifndef NDEBUG`, so
on every shipped Release binary it is not code at all. Before this contract, `rankGraphTeleport`
discarded the kernel's return value, which meant a Release build emitted a ranking from an
unfinished iteration with no alert, no attribute, and exit 0. **A disclosure that lives only in an
assertion is a disclosure that does not ship.** Gate: `test/prconvergecheck.sh`, whose hard arm
asserts the attribute appears in an NDEBUG build specifically.

The same CSR and the same product kernel serve the other graph lenses: HITS hubs and authorities
(authorities are core APIs and base classes; hubs are entrypoints and orchestrators — a two-axis
importance signal, not one scalar), co-citation and bibliographic-coupling similarity computed per
query column rather than as a dense product, k-hop reach for blast radius, strongly-connected
components for cycles, and community detection for the module views.

**Retrieval ranking is a separate layer** that consumes the graph. A confidence-gated query-shape
router picks name-exact BM25 when the query names a symbol and subtoken+body BM25 otherwise, and
prints which and why. Query-mention anchoring lifts a file, module, or `Type.method` named in the
task text. A path-tier multiplier de-prioritizes fixture and generated-content paths. Every one of
those is a measured change with a held-out number — see `docs/EVALS.md`.

### serialize — minified XML

Nodes sort by **(rank DESC, nodeId ASC)**. The node-ID tiebreak is required: near-equal scores would
otherwise reorder between runs and make top-K and diff views churn. The index array is sorted with a
radix sort against float keys without moving payloads; the top-K is taken from that.

**XML escaping is a correctness requirement, not polish.** C++ identifiers routinely contain `<`,
`>`, `&`, and `"` — `vector<int>`, `operator<`, `operator&&`, `std::pair<std::string,int>` — and
paths contain `&` and spaces. One `escapeXml` runs over **every** attribute value and text node,
substituting `&` first so nothing double-escapes. A symbol named `operator<` in a path containing `&`
must round-trip and parse cleanly; that is a required unit test, not an aspiration.

The document is **streamed, never materialized**. A stack-backed writer with a 64 KB buffer writes
through to stdout on fill and on destruction: one write call per flush, no per-symbol syscall, no
string accumulation of the final document.

The schema is terse by design — a legend comment once at the top, then `<r>` root, `<f p>` files,
`<s t n k>` symbols, `<c n>` call edges. Token density is the point.

### cli / mcp — two front doors, one renderer

The argument parser is hand-rolled and table-driven. A flagless run emits the core map; every flag is
additive and gated by a `Config` field.

The MCP server exposes 30 verbs. **All of them** are a thin front door onto **the same
computation and the same renderer** as a CLI sibling — one output shape, two surfaces. That is a
deliberate constraint: a verb that rendered differently over MCP would be a second implementation to
keep honest.

The three write verbs — `replace_symbol_body`, `insert_before_symbol` and `insert_after_symbol`
(`src/mcpedit.h`) — also have CLI siblings (`--replace-symbol-body`, `--insert-before-symbol`,
`--insert-after-symbol`, with `--edit-payload`). Both front doors share the same ambiguity refusal,
staleness hash, symlink refusal, mode preservation and atomic-write transaction. CLI is the preferred
zero-standing-schema path; MCP is the warm-index alternative.

---

## 2. Data model

Four types carry everything.

| Type | What it is |
| --- | --- |
| `NodeId` | A 32-bit index into the symbol arrays. Not a pointer. IDs are assigned in sorted crawl order, so they are stable across runs of the same tree. |
| `Symbol` | One definition: kind, name, canonical id, path, line span, language, plus the derived per-symbol metrics (complexity, fan-in, tested, churn). POD. |
| `Reference` | One unresolved use site: name, kind (call / read / write / import / extends), position, and the file that contains it. Resolution turns references into edges. |
| `IngestResult` | The output of the ingest stage — the symbol table, the reference list, per-file metadata — and the input to graph construction. |

The graph itself is not an object graph. It is three parallel arrays (`rowOffsets`, `colIndices`,
`values`) plus `wOutDeg` and the dangling mask: structure-of-arrays, 32-bit handles, no nodes, no
pointers, no generic graph library. Everything else in the system is a different traversal of those
arrays.

Caching is content-keyed. The parse cache is keyed by file content hash plus a parser version; an
extraction change bumps the parser version and costs one cold re-parse. Warm output is asserted
**byte-identical** to cold output by a gate — a cache that changes the answer is a bug, not a
tradeoff.

---

## 3. The determinism contract

Output is a sorted top-K. A sort has no tolerance band, so the contract is byte-identity: the same
tree produces the same bytes, on every run, regardless of thread count or scheduling.

Four rules hold it up:

1. **Fixed contiguous row-block partitioning** — never dynamic work stealing over rows.
2. **Every global reduction** (dangling mass, residual) sums fixed per-block partials in canonical
   block order. Never an atomic float add.
3. **The rank vector is `double`.**
4. **The PageRank translation unit compiles without floating-point reassociation** (a per-file flag),
   so add order is stable. The rest of the binary keeps the fast-math baseline.

Plus the ingest rule: sort candidate paths before assigning IDs.

**Rule 1 means a compile-time constant, and a future maintainer will be tempted to make it a runtime
one. Do not.** The block size is `kReductionBlockSize = 1024`, a `constexpr` in `src/pagerank.cpp`.
The obvious "improvement" is to derive it from the machine — `hardware_concurrency()`, a core count,
a cache-size probe — so the partition matches the hardware it runs on. That change is invisible in
review, passes every test on the machine that makes it, and silently destroys the contract this
section is about.

Floating-point addition is not associative. A partition that varies by machine changes the summation
tree, which changes the low bits of the dangling-mass and residual reductions, which changes ranks in
the last digits, which reorders ties in a sort that has no tolerance band. Every symptom points away
from the cause: each run is self-consistent, each run reproduces on its own host, the ranking always
*looks* right, and only a byte-diff taken across two different machines shows anything at all — which
is precisely the diff nobody runs, because the local determinism gate is green.

This is not hypothetical. A graph-database PageRank implementation surveyed in 2026-08 uses the same
fixed-canonical-merge-order reduction strategy this one does — independent agreement that the
strategy is right — and then partitions it by `hardware_concurrency()`, inheriting exactly this
class. The strategy is only half the property; the partition has to be a property of the source.

The gate is `./build/ripwire DIR > a; ./build/ripwire DIR > b; diff -q a b`, run three times.
Anything that makes output depend on timing is a bug even when the ranking still looks right.

Tests follow from this. Float comparisons assert a **tolerance band** and the top-K **order**, never
exact scores — fast-math and threaded reductions reorder sums. But a *sort* has no band, so sorted
and serialized output uses the byte-identity gate instead.

---

## 4. The honesty contract

This is the part that distinguishes the output, and it is worth reading even if you skip everything
else.

**A zero is a measurement. Absent is not zero.**

The call graph is extracted from source text by name. Dynamic dispatch, callbacks and function
pointers, macro-generated call sites, and declarations that parse without a call expression
contribute no edge. So a count of callers is a **floor**, never a total. Output says so, in the
output, on the verbs where it is true:

- **`counts_floor="1"`** appears on `--callers`, `--callees`, `--uses`, `--impact`, `--edit-check`
  and further surfaces. Read a `0` from those verbs as **"none found"**, never as "none exists".
- **Counting units are named per verb**, and `--uses` is the one that differs. `--callers`,
  `--callees`, `--impact` and `--edit-check` count **distinct `(caller, callee)` pairs**; `--uses`
  counts **use SITES** — every read, write, import and inheritance reference with its own
  `file:line`, so the same pair appearing twice is two rows. Two different numbers, two different
  names, deliberately: `--uses` is normally the larger, and comparing it against a caller count as
  though they measured the same thing is the mistake this row exists to prevent.
- **`amb="K"`** on a symbol means K of its calls hit a name with multiple definitions and the
  resolver split the weight rather than choosing. The header's `ambiguous=N` totals it.
- **`unresolved=N`** counts call names defined only in a language-incompatible file.
- **A refusal is not an answer of zero.** A selector naming nothing indexed **refuses** with a
  did-you-mean computed from a real edit distance. A query whose names all resolve but that selects
  nothing reports `count="0"` — because *that* is a measurement.
- **Every truncation is disclosed.** Headers carry `total=` (the true relevant count), `shown=`
  (what this run emitted), `capped=`, and `truncated=`; a document cut within itself carries its own
  marker; a bundle that could not fit its own floor says `over_ceiling=1` rather than silently
  overshooting.
- **Token estimates are calibrated, never exact.** No public tokenizer matches every model, so the
  estimate is a calibrated approximation and is labelled as one. The `--pr-context` estimate in
  particular is known to under-charge against a real tokenizer; treat it as a lower bound.
- **A negative result is published as a negative result.** Two experimental ranking features are
  reachable only behind an environment variable, with `--help` entries removed, precisely because
  their own evaluations showed no confirmed lift.

The rule for anyone extending this code: **do not add a surface that quietly rounds, guesses, or
omits.** If a number cannot be a total, name it a floor. If a lens dropped something, say what and
why, in the output, where the caller reads it.

---

## 5. The two build flavours (a lesson worth inheriting)

CI builds and runs the full suite twice — once `Release`, once with no build type.

`Release` defines `NDEBUG`. Under `NDEBUG`, `VERIFY` lowers to `__builtin_assume` and
`DEGRADED_PATH_ALERT` compiles away entirely. Both facts have teeth:

- **Release catches optimizer-only bugs.** With `__builtin_assume` in play, a `VERIFY( p != nullptr )`
  followed by a defensive `if( p == nullptr ) return;` licenses the optimizer to delete the defensive
  branch. Code that is correct at `-O0` can be wrong at `-O2`, and only the Release build sees it.
- **The plain build catches degrade paths.** A gate that asserts a degrade path asserts on
  `DEGRADED_PATH_ALERT` output. Compiled out, that gate cannot observe what it asserts — it passes
  while being blind. This happened here: for three development cycles, every degrade-path gate in CI
  was green for exactly that reason, and a real fix to one of them was invisible to CI until after it
  landed.

Neither flavour subsumes the other. If you add a degrade path, the **plain** run is what proves it;
if you add an invariant, the **Release** run is what stresses it.

The same lesson generalizes, and it is the reason the gate discipline in `CONTRIBUTING.md` is written
the way it is: **a gate that cannot observe what it asserts is worse than no gate**, because it
reports confidence. Guard your probes — assert the thing you are about to search for actually exists,
then assert the property.
