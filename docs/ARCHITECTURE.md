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
TypeScript, JavaScript, Java, Ruby, Bash, Go, Rust, Swift, C#, plus JSON configuration keys.

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

Convergence is a residual stop: iterate until `‖r_new − r‖₁ < τ`, else stop at `maxIter` with a
degrade alert and use the last iterate. Teleport makes the operator strictly positive, hence
primitive, so Perron–Frobenius guarantees a unique positive dominant eigenvector with `λ₁ = 1` — the
iteration is well-posed, not merely empirical.

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

The MCP server exposes 30 verbs. **Twenty-seven of them** are a thin front door onto **the same
computation and the same renderer** as a CLI sibling — one output shape, two surfaces. That is a
deliberate constraint: a verb that rendered differently over MCP would be a second implementation to
keep honest.

**Three have no CLI sibling at all**, and they are the write verbs: `replace_symbol_body`,
`insert_before_symbol` and `insert_after_symbol` (`src/mcpedit.h`). There is no CLI flag that edits
your source, so there is nothing for them to mirror — they are the one place where the MCP surface is
genuinely larger than the command line rather than a second door onto it, and they carry their own
safety contract instead of a shared renderer.

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
