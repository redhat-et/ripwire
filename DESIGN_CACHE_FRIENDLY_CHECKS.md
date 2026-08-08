# DESIGN — cache-friendliness static checks (2026-08-07)

Origin: a code-review automation ask — the team checks cache-friendliness by hand (spatial/temporal
locality, out-of-order jumps, structures-vs-cache-line, hot/cold splitting, sequential-vs-random
access, pointer chasing, loop order) and wants ripwire to automate what is honestly automatable.
Grounded in a multi-source research pass (Drepper "What Every Programmer Should Know About Memory"
§6 via LWN 255364; Agner Fog `optimizing_cpp.pdf` §7/§9; Game Programming Patterns "Data Locality";
Sutter "Eliminate False Sharing"; Meyers "CPU Caches and Why You Care"; Mike Acton CppCon 2014;
Baeldung cache-friendly-code; Intel cache-blocking notes) — 24 distinct patterns catalogued, each
with a syntactic signature and a static-detectability grade.

## 0. Where the questions land — the coverage map

| Review question | Status | Where |
| --- | --- | --- |
| Hot/cold data splitting | **already shipped** | `--field-affinity` split-line findings (Chilimbi wt=0 pairs: co-accessed fields that can never share a line) |
| Struct vs cache line (straddle/fit) | **already shipped** | `--field-affinity` straddle findings (a field crossing the 64 B boundary); `--layout` per-field offsets/padding |
| Pointer chasing (for-loop update clause) | **already shipped** | `accessshape.h` index/chase/mixed/unknown classification feeding `--field-affinity`'s chase-pointer colocation boost |
| Pointer chasing (everywhere else) | **NEW — shipped** | `cache-pointer-chase-loop` (`p = p->next` in any loop body incl. while/do/range-for, the shapes Phase A discloses as `unknown`) |
| Data-structure choice (node containers, vector-of-pointers, vector-of-vectors) | **NEW — shipped** | `cache-node-container`, `cache-vector-of-raw-ptr`, `cache-vector-of-indirect` |
| Sequential vs random access (gather `a[b[i]]`) | **NEW — shipped** | `cache-gather-subscript` (loop-fenced) |
| Allocation discipline in loops | **NEW — shipped** | `cache-heap-alloc-in-loop` (loop-fenced) |
| shared_ptr refcount traffic | **NEW — shipped** | `cache-shared-ptr-by-value` |
| Manual prefetch hygiene | **NEW — shipped** | `cache-manual-prefetch` (flags EXISTING calls for re-measurement; never suggests adding one) |
| Loop order / interchange (the matrix-multiply classic) | **wave 2** | §3.1 — the highest-value unshipped check |
| Missing `vector::reserve` before a growth loop | **wave 2** | §3.2 |
| False sharing (adjacent hot fields written by different threads) | **wave 2** | §3.3 — the inverse of field-affinity, same layout arithmetic |
| AoS scanned for few fields (SoA candidate) | **wave 2** | §3.4 |
| Dead-element guard loops (existence-based processing) | **wave 2** | §3.5 |
| Out-of-order jumps / branch predictability | **mostly OUT of scope** | §4 — runtime property + compiler-handled; only the opaque-invariant subcase is honest to flag |
| Temporal locality (operation interleaving), loop blocking profitability, "hot" anything | **out of scope** | needs profiling; pair lint rows with `--hotspots`/churn instead of guessing |

## 1. What shipped: the cachelint pack (`src/cachelint.h`, built into `--lint`)

Eight rules, all in the binary (no config files), same astQuery engine as every built-in, C-family
files only (a `new` in a JavaScript loop is idiomatic GC allocation, not a finding). Fold-in point:
`mergeCachePack` beside `mergeAtomsPack`/`mergeNamingLens` in `src/main.cpp`. Facts, not verdicts —
`--lint` stays descriptive and non-gating.

| Rule | Shape | Loop-fenced |
| --- | --- | --- |
| `cache-node-container` | `map/multimap/list/forward_list/set/multiset/unordered_*` template type | no (decl site) |
| `cache-vector-of-raw-ptr` | `vector<T*>` | no |
| `cache-vector-of-indirect` | `vector<unique_ptr/shared_ptr/vector<…>>`, qualified or not | no |
| `cache-heap-alloc-in-loop` | `new` / `malloc/calloc/realloc/strdup` (bare or `std::`) | **yes** |
| `cache-pointer-chase-loop` | `x = x->field` (capture-equality `#eq?`) | **yes** |
| `cache-gather-subscript` | `a[ b[i] ]` (subscript inside a subscript's index) | **yes** |
| `cache-shared-ptr-by-value` | by-value `shared_ptr` parameter (bare-identifier declarator — `&`/`*` don't match) | no |
| `cache-manual-prefetch` | `_mm_prefetch` / `__builtin_prefetch` call | no |

Mechanics worth knowing before touching it:
- **Loop fence** — tree-sitter queries can't say "an ancestor is a loop", so loop regions
  (`for/while/do/range-for`) come back as their own capture stream and containment is span algebra
  (binary search over per-file sorted spans + prefix-max ends). A truncated loop stream can only
  UNDER-report; saturation is still disclosed as a floor on the three fenced rules.
- **Aux-capture collapse** — every spec captures the whole interesting node as its widest capture;
  inner predicate captures are removed by strict-containment sweep so one source site = one row.
- **Budget honesty** — pack pays its own astQuery pass at a 100 k budget (atoms-pack precedent),
  then truncates per rule to `kLintMaxPerRule` so `capped="1"` means the same thing tally-wide.

Validation: `test/cachefix/` is TWO-SIDED — `unfriendly.cpp` pins every rule to exact lines
(recall), `friendly.cpp` does the same jobs cache-consciously and must be silent (precision), so
each rule is measured against its own fix. Gate: `test/cachelintcheck.sh` (registered in
`regression.sh`; suite green at 361 gates; ASAN clean). Own-repo calibration: node-container 15,
vector-of-raw-ptr 23, vector-of-indirect 143, gather 166 (ripwire is a CSR codebase — `colIdx[rowPtr[i]]`
is the honest-gather case the rule's framing anticipates), alloc-in-loop/chase/shared-ptr-by-value
hits land ONLY in benches and fixtures, zero in shipping `src/` — the precision story matches G2.

## 2. The research catalog — agreement map and the myths list

Strongest multi-source agreement (≥4 sources): row-major loop order (Agner §7.10/§9.9, Meyers,
Drepper, SO 9936132, Baeldung); contiguous-vs-node containers / pointer chasing (Agner §9.7, GPP,
Drepper, Baeldung, SO); false sharing + alignas fix (Sutter, Meyers, Drepper, Lei Mao); AoS/SoA
by USE (Acton, GPP, Drepper, Agner — NB Agner Ex. 9.1 runs the transform the OTHER way when fields
are co-used: the criterion is use, not a direction). Measured anchors worth quoting in messages:
Drepper's matmul i-k-j ≈ 77 % time cut; Agner's MSVC vector grew through 7 reallocations for ten
`push_back`s; GPP's ~50× de-pointering anecdote.

**Verify-before-claiming list (checks we must NOT ship naively)** — compilers already hoist
provable loop invariants (LICM, -O2) and unswitch provable invariant branches (-O3); branchy loops
often become `cmov`/vectorized; iterator overhead is usually optimized out (Agner §9.7); manual
prefetch was a 2007 win and is often a wash now; power-of-2 column counts get OPPOSITE advice in
Agner §7.10 vs §9.10 (address math vs critical stride) so any such rule must gate on size or stay
silent; templates cost nothing (Agner). These are why `--lint` has no "branch in loop" rule.

## 3. Wave 2 — the checks that need real analysis (specs)

Each follows the access-shape plan's validation discipline (PLAN.md 2026-08-06): fixture gate with
labelled discriminating pairs, a blind real-corpus precision pass, and a declared precision floor
before anything leaves report-only status.

### 3.1 Loop interchange / stride order (the matrix classic) — HIGHEST VALUE
Detector: for each C-style loop nest, bind each level's induction variable (init/cond/update — the
machinery accessshape.h's Phase A already queries), then for every multi-subscript chain
`a[e1][e2]…[ek]` or linearized `a[e1*STRIDE + e2]` in the innermost body, compute which loop level
each subscript position varies with. FLAG when the innermost variable appears in a non-last
subscript position while an outer variable holds the last (i.e. the inner stride is the row size).
The linearized form counts `iv * expr` in the index as non-unit stride. Discriminating pairs the
fixture must pin: `m[i][j]` inner-j (silent) vs inner-i (fires); `res[i][j] += mul1[i][k]*mul2[k][j]`
with k innermost (fires on `mul2[k][j]` exactly — Drepper's example); `grid[i*cols+j]` inner-j
(silent) vs `grid[j*cols+i]` inner-j (fires); a triangular loop (bounds depend on outer var —
still classifiable); an iterator loop (unknown → silent, fails closed). Home: extend cachelint.h
with its own re-query pass; report the offending subscript's row, name both variables in the text.

### 3.2 Missing `reserve()` before a growth loop
`push_back/emplace_back` on receiver R inside a loop, where the enclosing function contains no
`R.reserve(`/`R.resize(`/`R.assign(` before the loop's start byte and R is declared in-function.
The receiver-match is textual on the same spelling (conservative: a different alias → silent).
clang-tidy's `performance-inefficient-vector-operation` is the shipping precedent. Fires `info` —
amortized growth is often fine; the row is a prompt, not a defect.

### 3.3 False-sharing advisor (the inverse of field-affinity)
Same modeled layout arithmetic (`layout.h`), inverted question: two fields on the SAME 64 B line
where at least one is `std::atomic<…>`/a mutex type and the pair is written from ≥2 distinct
functions — advise `alignas(std::hardware_destructive_interference_size)` separation. lshaz is the
adjacent shipping tool (Linux-only, needs LLVM + compile_commands); a source-only advisor beside
`--field-affinity` completes the pair of questions that header explicitly leaves split. Honesty:
static analysis cannot prove concurrent writers — say "written from N functions", never "raced".

### 3.4 AoS→SoA candidate (member-touch ratio)
Per loop over a container/array of struct T: distinct T-members accessed in the body ÷ T's modeled
field count (layout.h gives the field list AND the byte waste per line). Fire only under a low
ratio on a >1-line struct, report the ratio and the per-line useful-byte percentage à la Acton.
MEDIUM detectability: needs element-type inference from the range expression — refuse (silent) when
the type can't be pinned, matching the accessshape stem-ambiguity convention.

### 3.5 Dead-element guard loop (existence-based processing)
A loop whose whole body is one `if` testing a member/getter of the element, with no
`break/return/goto` in the consequence (that exclusion separates it from a search loop — the
discriminating pair the fixture must pin). GPP's packed-pool prescription goes in the row text.

### Explicitly rejected for any wave
Branch-predictability scoring (runtime), loop blocking profitability (needs sizes), temporal-locality
interleaving (needs dataflow across statements), prefetch insertion advice (measure first), global
"hotness" claims (pair with `--hotspots`), and any rule on the verify-before-claiming list in §2.

## 4. Out-of-order jumps — the honest position
The article's advice ("avoid many if-then-else branches") is 90 % a runtime/predictability story the
compiler and branch predictor already own. The one static, honest slice: an `if` inside a loop whose
condition references no loop-assigned variable AND contains an opaque call — the compiler can't
prove it invariant, a human can hoist it. Wave-2-optional; ship only with the compiler-handled
caveat in the row text, per §2.

## 5. Relation to the Baeldung starting point
Its seven checkable claims all land: contiguity/data-structure choice → §1 container rules;
loop order → §3.1; recursion/function-stack → call-graph self-edges (queryable today via
`--callers`; a `cache-recursion` rule is cheap if wanted); branches → §4; prefetching → the
`cache-manual-prefetch` re-measure stance; hot/cold + line-fit — beyond the article — were already
shipped as `--field-affinity`. The article's "checks" are reading heuristics; everything above is
the mechanized, floor-disclosed version.
