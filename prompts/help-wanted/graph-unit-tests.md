# Graph unit tests — the CSR and the PageRank kernel, built and run by CI

You are writing unit tests for ripwire's CSR call graph and its PageRank power iteration, and a gate
that makes CI build and run them. The tests use small hand-built graphs whose expected values you can
check on paper. The gate turns a rejection rule that nothing can trigger into one a change can fail.

Work in a git worktree, not the main checkout. Run every gate in the foreground. Line numbers are from
`main` at `f22081b0`; if one has moved, find the symbol, not the line.

---

## Why it matters

`CONTRIBUTING.md` §2 lists what rejects a change automatically, and one entry is "the CSR property test
fails". Today nothing can make that happen:

- **No gate and no CI job builds the CSR or PageRank tests.** They exist only behind the CMake option
  `RIPWIRE_TESTS` (`CMakeLists.txt:604`, OFF by default). `.github/workflows/ci.yml` never sets it, no
  gate in `test/regression.sh` builds `ripwire_test_csr` or `ripwire_test_pagerank`, and nothing runs
  `ctest`. `test/dependencypincheck.sh` configures with `-DRIPWIRE_TESTS=ON`, but it builds nothing.
- **Because nothing builds it, the PageRank test no longer compiles.** `test/verify_pagerank.cpp:65`
  assigns `rw::pageRankDouble( … )` to a `const unsigned`. Since `2bbd134d` (2026-08-17) the function
  returns `PageRankRun`, and the target fails with `no viable conversion from 'PageRankRun' to 'const
  unsigned int'`. With only that line changed, its one test case passes 16 of 16 assertions (measured).
- `ripwire_test_csr` builds and passes: 2 test cases, 23 assertions (measured).

CLAUDE.md's first non-negotiable is why this matters here: a ranking and a call graph look plausible
whether or not they are correct. A wrong edge weight or an off-by-one in the stopping rule does not
crash. It produces an ordering an agent believes.

---

## What exists — build on it

| File | What it gives you |
| --- | --- |
| `CMakeLists.txt:604-635` | The `RIPWIRE_TESTS` option and both targets: `ripwire_test_csr` (`test/verify_csr.cpp` + `src/infra/diagnostics.cpp`) and `ripwire_test_pagerank` (`test/verify_pagerank.cpp` + `src/pagerank.cpp` + `src/infra/diagnostics.cpp`), each with `add_test`. Lines 742-744 put them on the G1 sanitizer target lists |
| `third_party/deps/doctest` | doctest 2.4.12, pinned by commit and vendored. The test framework; test-only |
| `test/verify_csr.cpp` | Random CSRs at 0, 1, 2, 100 and 10,000 nodes with an adjacency round-trip; a 70,001-edge row that catches 16-bit truncation; NaN and negative-value rejection; `buildGraph` orientation on a hand-built `IngestResult`. Keep all of it |
| `test/verify_pagerank.cpp` | The empty graph, a two-node dangling fixture checked against 20/57, all-dangling equals teleport, fractional weights keep mass, three tied callers of one hub. Keep all of it once line 65 is fixed |
| `test/strkerncheck.sh` | **The template.** It configures a scratch tree with `-DRIPWIRE_TESTS=ON -DRIPWIRE_ASAN=ON -DFETCHCONTENT_FULLY_DISCONNECTED=ON`, builds one doctest target, runs it with the sanitizer options, parses doctest's tally lines against floors, and has a mutation arm that must go red. It is pinned in `test/binoverridecheck.sh`'s `EXEMPT` table because it never runs `build/ripwire` |
| `test/dynmapsimdcheck.sh` | SIMD-versus-scalar parity for `sparseCsr`'s kernels: `blockReduceDot` and `scaleVec` at sizes 0 to 2051, across the 1024 seam; `spmvRow` and `applyInto` at row lengths 0 to 40; `dominantEigenvector` on a 2×2. Do not repeat it |
| `test/prconvergecheck.sh` | The non-convergence disclosure end to end on the binary, including an NDEBUG binary, and the `RIPWIRE_TEST_PR_MAXITERS` strings `100 100000 0 "" 2x x2 " 2" -2` |

Two other help-wanted kits overlap with this one. Do not duplicate them; link them from your PR.

- **correctness-fuzzers** covers random-input oracles: graph invariants over random CSRs, rank mass,
  input-order invariance. Its acceptance criterion 7 asks for the same gate this kit specifies. If this
  work lands first, say so on that kit's PR. This kit owns hand-derived fixtures; that one owns random
  inputs.
- **certified-ranking-order** returns the final residual from `pageRankDouble` and certifies how far
  down the order is provably right, which will likely add a field to `PageRankRun`. Read results by
  member name (`run.iterationCount`, `run.hasConverged`), never by comparing whole structs, so that
  change does not break these tests.

---

## Facts the expected values depend on

1. **The shipped damping is `double( 0.85f )`, not 0.85.** `rankGraphTeleport` takes `float alpha =
   0.85f` (`src/graph.h:3265`) and passes `double( alpha )` (`:3288`), which is
   0.85000002384185791015625. `PageRankConfig`'s default is the double `0.85` (`src/pagerank.h:13`), so
   a test that calls `pageRankDouble` with `{}` uses a damping production never uses. Write the shipped
   value as `double( 0.85f )`. The two fixed points differ by about 3e-9, below every band in this kit.
2. **The stopping rule.** The tolerance is `1e-6` and the ceiling `100` (`src/pagerank.h:14-15`). The
   loop stops when the L1 residual is strictly below the tolerance (`src/pagerank.cpp:180`), and the
   converging iteration is counted (`:182`). If the loop runs out, it returns `maxIterationCount` with
   `hasConverged == false`. A run that converges on its last allowed iteration returns
   `{ maxIterationCount, true }`.
3. **At the shipped settings the ceiling of 100 is never reached.** The iteration starts at the
   teleport vector, so the residual after iterate k is at most 2α^k. Every valid input therefore
   converges within 90 iterations (ln 2e6 / ln(1/α) = 89.27). Fixture K12 needs exactly 90. "Valid"
   means `wOutDeg[j]` equals the sum of column j's values: `buildGraph` guarantees that, and the kernel
   does not check it. A unit test reaches the non-convergence branch through `PageRankConfig`, with a
   lower `maxIterationCount` or a larger `alpha`. It needs no environment hook.
4. **Which tolerance bands are safe.** After convergence, ‖x − x*‖₁ ≤ α/(1−α) · residual < 5.67 τ. At
   τ = 1e-6, a per-score band of **1e-5** is provably safe and 1e-6 is not; the largest error measured
   on the fixtures below is 2.7e-7. With τ = 1e-13 and a ceiling of 400 (the *precise* config), a band of
   **1e-12** is safe; the largest measured error is 2.8e-14.
5. **Assert an exact iteration count only when it has margin.** The residual one iteration before the
   stop should be at least 1% above τ, and the final one at least 1% below. Every count in the tables
   below qualifies except K15 at N = 2049 (0.05% margin), where the test asserts `≤ 90` instead.
6. **Floating point in this build.** Every translation unit is compiled with `-ffast-math
   -fno-finite-math-only` (`cmake/PortableFlags.cmake`), except `src/pagerank.cpp`, which gets
   `-fno-fast-math` (`CMakeLists.txt:506`). NaN and infinity checks in test code are real, but sums may
   be reassociated or contracted. Contraction reaches the kernel too. On arm64 AppleClang the kernel
   matched the Python reference below on every iteration count, and its scores within two ulps, but not
   bit for bit. **Never assert bit equality against the reference, across translation units or across
   platforms.** Bit equality is valid only between two calls of the same kernel on bit-identical inputs.
7. **The kernel is single-threaded and uses fixed blocks.** It has no threads and no thread setting.
   Every reduction folds `kReductionBlockSize = 1024` blocks in index order (`src/pagerank.cpp:27`).
   "Identical across thread counts" does not apply. What applies is identical results across repeated
   runs, and correct results across the 1024-element block seam.
8. **`VERIFY` is not a test oracle.** In a plain or ASan build a failed `VERIFY` calls the assert
   handler, which ends the process. Under `NDEBUG` it becomes an optimizer assumption
   (`src/infra/Diagnostics.h:89-141`), so a violated precondition in a Release build is undefined
   behaviour. doctest has no death tests. Never give a test an input that violates a `VERIFY`; test the
   predicate (`verifyCsr`) directly.
9. **`DEGRADED_PATH_ALERT` logs once per call site per process** (`Diagnostics.h:170-176`). In a test
   binary, the non-convergence alert prints on the first truncated run and never again. The part you can
   test is the returned `PageRankRun`.
10. **`RIPWIRE_TEST_PR_MAXITERS` is read once per process** (`src/pagerank.cpp:56`). A test cannot vary
    it inside one process; see E1.
11. **The doctest binaries print a PROFILE REPORT when they exit,** once they include `graph.h`.
    `PROFILE_ENABLED` is defined only for the `ripwire` and `ripwire_probe` targets, and
    `src/infra/profileScope.h:47-53` turns profiling on whenever `NDEBUG` is unset. Parse doctest's
    `[doctest]` lines, not the end of the output.
12. **`buildGraph` counts every `Reference` it is given.** Two identical references on the same line
    give `nref = 2` (measured). Deduplicating references is not its job.

---

## Coverage inventory

| Function | Branch or condition | Why it matters | Test |
| --- | --- | --- | --- |
| `sparseCsr` constructor, `src/infra/sparseCsr.h:200` | `anew( 0 )` returns null (`:57`), so with `nnz == 0` the column and value arrays are null | `verifyCsr` must accept null arrays when there are no edges | C2, C3 |
| same | `if( m_rowOff )` before the memset (`:206`) is always true, since `rows + 1 ≥ 1` | offsets start at zero; the guard is dead | C3 |
| default constructor, `:197` | all three pointers null | `verifyCsr` rejects it even for 0 nodes; only the three-argument constructor makes a valid empty CSR | C1 |
| move constructor and move assignment, `:219`, `:227` | the source is reset; self-move check `this != &o` (`:229`) | a moved-from CSR must fail verification, and must not hold freed arrays | C4 |
| `applyInto`, `:256` | float path: 8-wide unroll (`:272`), prefetch guard `k + PF + 4 < m_nnz` both true and false (`:274`), scalar tail (`:285`) | its production caller is `hits` (`src/graph.h:3331`) | C6: one hand-computed value; parity stays in dynmapsimdcheck |
| `spmvRow`, `blockReduceDot`, `scaleVec`, `:79-188` | NEON and SSE2 lanes, and their tails | reduction determinism | `test/dynmapsimdcheck.sh`; not repeated |
| `dominantEigenvector`, `:318` | `N == 0` (`:322`); residual break (`:353`) versus running out silently | no production caller; only `test/dynmapsimd_harness.cpp` uses it | out of scope; note it in the plan |
| `verifyCsr`, `src/infra/csrverify.h:16` | `rows != nodeCount`; `cols != nodeCount` | shape | C5a, C5b |
| same, `:16` | `nnz > UINT32_MAX` | 32-bit handles | **untestable**: needs a four-billion-entry allocation |
| `:24` | `rowOffsets == nullptr` | default-constructed or moved-from | C1, C4 |
| `:24` | `nnz != 0` with a null column or value array | — | **unreachable through the public API**: `anew` never returns null when n > 0 |
| `:28` | `rowOffsets[0] != 0`; `rowOffsets[n] != nnz` | — | C5c, C5d |
| `:35` | offsets decrease; an interior offset exceeds `nnz` | — | C5e, C5f |
| `:42` | column ≥ node count; NaN; infinity; negative value | edge values feed a probability computation | C5g to C5j |
| `:42` | `-0.0f` passes, because `-0.0f < 0` is false | a boundary worth pinning | C5k |
| `buildGraph`, `src/graph.h:2742-2755` | self-loop: a target equal to the caller is not counted; `nReal == 0` (`:2751`) records the call as a `Self` disposition with no edge | `docs/ARCHITECTURE.md`: self-loops are rank sinks and are dropped | G3 |
| `:2782`, `:2785` | split: `base = conf / nReal`, skipping the caller inside the split | a k-way split must conserve the reference's confidence | G6 |
| `:2056`, `:2734`, `:2738` | same-file tier confidence 1.0; × 0.1 for a name defined 16 or more times; × 0.1 for a leading underscore | inputs to edge weight | G1, G7; the 16-definition deboost is not specified (see G7) |
| `:2790-2792` | the accumulator is keyed by `( from << 32 ) \| to`, so repeated references become `nref` | dedup by construction: no duplicate columns | G2, G10 |
| `:2828-2832` | weight `( confSum / nref ) · √nref`; cap `w > 8.f` | repeat calls weigh sublinearly; the tail is bounded | G2, G5 |
| `:2836` | `radixSortByFromTo` | sources in a row are ascending, whatever order the references arrived in | G4, G10 |
| `:2839-2869` | out-edge offsets, targets and values; `wOutDeg[from] += w` | `wOutDeg` must equal the column sums: the kernel's mass conservation depends on it, and the kernel does not check | G8, G10 |
| `:2893-2907` | in-degree count, `uint32` prefix sum, scatter | this builds the in-edge CSR; the prefix sum has no overflow guard before `:2909` | G1, G4, G8; overflow **untestable** at unit scale |
| `:2909` | `VERIFY( verifyCsr( … ) )` | a post-condition that `NDEBUG` compiles out | G10 calls `verifyCsr` explicitly |
| `buildGraph` overall | `N == 0`; a callee that resolves to nothing | — | G0, G9 |
| `pageRankDouble`, `src/pagerank.cpp:99-121` | eleven `VERIFY` preconditions: shape, alpha range, tolerance, ceiling, aliasing, finite non-negative inputs, teleport mass within 1e-9 | a violation ends a plain build and is undefined under `NDEBUG` | **not tested in-process** (fact 8) |
| `:108-109` | the environment ceiling can only lower `maxIterationCount` | — | E1 (optional) |
| `:110-113` | `nodeCount == 0` returns `{ 0, true }` and leaves `rank` alone | "vacuously converged" (`src/pagerank.h:28-30`) | K0 |
| `:144`, `:151` | `wOutDeg > 0 ? … : …`: dangling rank counts toward the dangling mass, and its scaled rank is zero | dangling redistribution, which naive PageRank gets wrong | K1, K3, K4, K6, K9 |
| `:155`, `:163` | `teleportScale = α·D + (1 − α)`, applied to the teleport | personalization enters only here | K9, K10, K11 |
| `:156-164` | the in-edge gather, including empty rows | — | K3 to K9 |
| `:138`, `:168` | block folds that reach a second block (`nodeCount > 1024`) | the determinism contract's fixed partition | K15 |
| `:180-185` | `residual < tolerance` (strict), with the count incremented before `break` | the off-by-one that decides `pr_iters=` | K12 |
| `:192-195` | running out; `DEGRADED_PATH_ALERT` | the disclosure must survive `NDEBUG` | K13, K14; gate arm 2 |
| `:196` | the newer iterate is copied out | a truncated rank is x_k, not x_(k−1) | K14 |
| `:103` | `alpha == 0` is accepted | — | K11 |
| kernel inputs | a self-loop in the CSR is used, not dropped | dropping self-loops is `buildGraph`'s job | K2 |
| `testIterationCeiling`, `:54-75` | unset, empty, longer than 9 characters, a non-digit, `0`, a valid number | strict parsing | E1; `test/prconvergecheck.sh` arm C covers most of these strings |
| `biasPrior`, `src/graph.h:3228` | the weight vector's size differs from the prior's (`:3231`): the prior is returned | — | B2 |
| `:3238` | the weighted sum is not positive: the prior is returned **silently**, with no alert | a degrade path without `DEGRADED_PATH_ALERT` | B3 |
| `:3242-3246` | renormalize to Σ = 1, in float | — | B1 |
| `rankGraphTeleport`, `:3265` | `N == 0` skips the kernel (`:3273`) | — | R4 |
| `:3280` | the `teleportMass > 0` guard | its else branch would hand an unnormalized vector to the kernel's mass `VERIFY`; every shipped prior builder already falls back to uniform, so it is unreachable today | **not tested**; note it |
| `:3288`, then narrowing to `float` | `double( 0.85f )` reaches the kernel | — | R1, R3 |
| `takeRank`, `:3299` | fills the disclosure with `isPageRank = true` | — | R2 |
| `rankGraph`, `:3306` | uniform prior; an empty graph | — | R4, R5 |

**Degrade paths.** The kernel has exactly one `DEGRADED_PATH_ALERT` (`src/pagerank.cpp:194`). There is
none in `sparseCsr.h`, in `csrverify.h`, in the CSR section of `buildGraph`, in `biasPrior` or in
`rankGraphTeleport`. `biasPrior`'s fallback is silent.

**Nearby, out of scope.** These read the CSR but are not in scope; they are listed so nobody assumes
they are covered: `fanInFromInEdges` raises `DEGRADED_PATH_ALERT` when the CSR has no offsets
(`src/graph.h:3915`), and `computeImpure` silently skips propagation when the CSR shape mismatches
(`:4590`).

---

## The tests

All expected scores were computed two ways: an exact rational solve of the fixed point, and the
reference below. They were then checked against the real kernel and the real `buildGraph` in a scratch
build. **Write each expected value in the test as its closed form, using `double( 0.85f )`,** and keep
the numbers here as a cross-check. Never compute an expected value by calling the code under test.

### The independent reference

This is plain Python in IEEE double, and it follows `src/pagerank.cpp`'s loop in the same fold order.
Use it to check a value or to add a fixture. Do not paste its output as bit-exact literals (fact 6).

```python
import struct

def f32( x ):
    return struct.unpack( '<f', struct.pack( '<f', x ) )[0]

ALPHA = f32( 0.85 )       # double( 0.85f ) = 0.85000002384185791015625
BLOCK = 1024              # kReductionBlockSize

def in_edge_csr( n, edges ):                       # edges: (source, target, weight)
    edges = sorted( edges )                        # buildGraph sorts by (from, to)
    ro = [ 0 ] * ( n + 1 )
    for s, t, w in edges:
        ro[ t + 1 ] += 1
    for i in range( n ):
        ro[ i + 1 ] += ro[ i ]
    cur, ci, val, wdeg = ro[ :n ], [ 0 ] * len( edges ), [ 0.0 ] * len( edges ), [ 0.0 ] * n
    for s, t, w in edges:
        k = cur[ t ]
        cur[ t ] += 1
        ci[ k ], val[ k ] = s, f32( w )
        wdeg[ s ] += f32( w )
    return ro, ci, val, wdeg

def block_sum( values ):
    total = 0.0
    for b in range( 0, len( values ), BLOCK ):
        part = 0.0
        for v in values[ b:b + BLOCK ]:
            part += v
        total += part
    return total

def pagerank( n, ro, ci, val, wdeg, tele, alpha=ALPHA, tol=1e-6, max_iter=100 ):
    if n == 0:
        return [], 0, True
    r = list( tele )
    for iteration in range( 1, max_iter + 1 ):
        dangling = block_sum( [ 0.0 if wdeg[ i ] > 0.0 else r[ i ] for i in range( n ) ] )
        scaled = [ r[ i ] / wdeg[ i ] if wdeg[ i ] > 0.0 else 0.0 for i in range( n ) ]
        scale = alpha * dangling + ( 1.0 - alpha )
        nxt = [ 0.0 ] * n
        for t in range( n ):
            incoming = 0.0
            for k in range( ro[ t ], ro[ t + 1 ] ):
                incoming += val[ k ] * scaled[ ci[ k ] ]
            nxt[ t ] = alpha * incoming + scale * tele[ t ]
        residual = block_sum( [ abs( nxt[ i ] - r[ i ] ) for i in range( n ) ] )
        r = nxt
        if residual < tol:                         # print residual / tol here to check margins
            return r, iteration, True
    return r, max_iter, False

ro, ci, val, wdeg = in_edge_csr( 2, [ ( 0, 1, 1.0 ) ] )
print( pagerank( 2, ro, ci, val, wdeg, [ 0.5, 0.5 ] ) )                    # K3: 17 iterations, converged
print( pagerank( 2, ro, ci, val, wdeg, [ 0.5, 0.5 ], tol=1e-13, max_iter=400 ) )   # K3 precise: 35
```

### CSR structure — `test/verify_csr.cpp`

| ID | Input | Expected |
| --- | --- | --- |
| C1 | `sparseCsr<float> csr;` | `rows()`, `cols()` and `nnz()` are 0; all three pointers are null; `verifyCsr( csr, 0 ) == false` |
| C2 | `sparseCsr<float>( 0, 0, 0 )` | `rowOffsets()` is non-null with `[0] == 0`; `colIndices()` and `values()` are null; `verifyCsr( csr, 0 ) == true` |
| C3 | `sparseCsr<float>( 3, 3, 0 )` | offsets `{ 0, 0, 0, 0 }`; column and value arrays null; `verifyCsr( csr, 3 ) == true` |
| C4 | move-construct from C5's base; move-assign into a non-empty CSR; self-move-assign through a reference | the source has all counts 0, `rowOffsets() == nullptr` and `verifyCsr( source, 0 ) == false`; the destination verifies at 3; after the self-move it still verifies at 3; the ASan arm shows no leak or double free |
| C5 | base: 3 nodes, edges 0→2 (1.0), 1→2 (2.0), 2→0 (0.5), giving offsets `{ 0, 1, 1, 3 }`, columns `{ 2, 0, 1 }`, values `{ 0.5, 1, 2 }`. First assert the base verifies at 3, then check one mutated copy per arm | a: node count 2 → false · b: the same arrays in a `( 3, 4, 3 )` matrix → false · c: `offsets[0] = 1` → false · d: `offsets[3] = 2` → false · e: offsets `{ 0, 2, 1, 3 }` → false · f: a 2-node matrix with offsets `{ 0, 5, 2 }`, columns `{ 0, 1 }`, nnz 2 → false · g: `columns[0] = 3` → false · h: `values[0] = NaN` → false · i: `values[0] = +inf` → false · j: `values[0] = -1` → false · **k: `values[0] = -0.0f` → true** |
| C6 | `applyInto` on a 3 × 10 float matrix with nnz 49: row 0 has 40 entries (column `i % 10`, value 1); row 1 is empty; row 2 has 9 entries (column `i`, value `i + 1`); `x[i] = i` | `y == { 180, 0, 240 }` exactly, since integer-valued floats sum exactly in any order. Row 0 exercises the prefetch guard both ways |

### The graph `buildGraph` produces — `test/verify_csr.cpp`

Build the `IngestResult` the way the orientation test does: one file, every symbol `Lang::Cpp` and
`SymKind::Function`, every reference `RefRole::Call` from a symbol in that file. CSR arrays are exact.
Weights of 1.0, 0.5 and 8.0 are exact. Any other weight gets a relative band of 1e-6, because
`buildGraph` compiles in a fast-math translation unit.

| ID | Input | Expected |
| --- | --- | --- |
| G0 | an empty `IngestResult` | `inEdges.rows() == 0`, `nnz() == 0`, `rowOffsets()[0] == 0`, `verifyCsr( inEdges, 0 )`; `wOutDeg` empty; `outOff == { 0 }` |
| G1 | symbols `caller` and `callee`; one call | offsets `{ 0, 0, 1 }`, columns `{ 0 }`, values `{ 1.0f }`; `wOutDeg == { 1.0, 0.0 }`; `outOff == { 0, 1, 1 }`, `outTargets == { 1 }`, `outVals == { 1.0f }`. This extends the existing orientation test |
| G2 | the same pair with two references, on lines 11 and 12; then again with both on line 11 | both cases: one entry, value `std::sqrt( 2.0f )` = 1.41421354; `wOutDeg[0] == double( value )` |
| G3 | `recur` calls `recur` | `nnz() == 0`, offsets `{ 0, 0 }`, `wOutDeg == { 0.0 }`, `outOff == { 0, 0 }` |
| G4 | `alpha`, `bravo`, `charlie`, `hub`; references added in the order charlie→hub, alpha→hub, bravo→hub | offsets `{ 0, 0, 0, 0, 3 }`, columns `{ 0, 1, 2 }`, values `{ 1, 1, 1 }`; `wOutDeg == { 1, 1, 1, 0 }`; `outOff == { 0, 1, 2, 3, 3 }`, `outTargets == { 3, 3, 3 }` |
| G5 | `caller` calls `callee` 63, 64, 65 and 100 times, in four graphs | 63: `std::sqrt( 63.0f )` = 7.93725395 · 64: exactly 8.0f (√64, not capped) · 65 and 100: exactly 8.0f, which is not `std::sqrt( 65.0f )` = 8.06225777. Only 65 and 100 prove the cap |
| G6 | `caller`, plus two symbols both named `callee` in the same file; one call | two entries: offsets `{ 0, 0, 1, 2 }`, columns `{ 0, 0 }`, values `{ 0.5f, 0.5f }`; `wOutDeg == { 1.0, 0, 0 }`; `outTargets == { 1, 2 }`. **This depends on the resolver.** Also assert what a resolver change must preserve: the `outVals` of one reference's edges sum to that reference's confidence |
| G7 | `caller` calls `_priv` | value 0.1f; `wOutDeg[0] == double( 0.1f )`. `priorWeight[1]` comes out as 0.5, from the name-quality model; do not pin it here. The deboost for a name with 16 or more definitions is not specified: it needs 16 same-name definitions and ties the fixture to the resolver's tier choice, so say in the plan whether you add it |
| G8 | `alpha`→`bravo`, `alpha`→`charlie`, `bravo`→`charlie` | offsets `{ 0, 0, 1, 3 }`, columns `{ 0, 0, 1 }`, values `{ 1, 1, 1 }`; `wOutDeg == { 2, 1, 0 }`; `outOff == { 0, 2, 3, 3 }`, `outTargets == { 1, 2, 2 }` |
| G9 | `alpha` calls `nosuchname` | no edge: `nnz() == 0`, `wOutDeg == { 0, 0 }` |
| G10 | an invariant helper, run on G0 to G9 | `verifyCsr( inEdges, N )`; `outOff.size() == N + 1` and `outOff.back() == nnz()`; the (source, target, weight) triples read from the out-edge arrays match those read from the in-edge CSR; columns strictly increase within each in-edge row; no entry's column equals its row; for every source j, the double sum of column j's values equals `wOutDeg[j]` within 1e-12 × max(1, `wOutDeg[j]`) |

### The PageRank kernel — `test/verify_pagerank.cpp`

Define `kShippedAlpha = double( 0.85f )`. The *shipped* config is `{ .alpha = kShippedAlpha }`
(τ = 1e-6, ceiling 100) with a band of 1e-5. The *precise* config is `{ .alpha = kShippedAlpha,
.tolerance = 1e-13, .maxIterationCount = 400 }` with a band of 1e-12. Below, α means `double( 0.85f )`
and `{ n, b }` means `iterationCount == n` and `hasConverged == b`. Margins are the residual one
iteration before the stop, then at the stop, as multiples of τ. Every K result also goes through an
invariant helper: every score is finite and ≥ 0, and |Σ − 1| ≤ 1e-12, whether the run converged or was
truncated.

| ID | Input | Expected |
| --- | --- | --- |
| K0 | empty: `sparseCsr<float>( 0, 0, 0 )` with empty spans; then again with `maxIterationCount = 1` | `{ 0, true }`, and `rank` stays empty. This is the case at line 65 that no longer compiles |
| K1 | 1 node, no edges, `wOutDeg { 0 }`, teleport `{ 1 }` | `{ 1, true }`; rank exactly `{ 1.0 }`, because α·1 + (1 − α) is exactly 1 for this α |
| K2 | 1 node with a self-loop: offsets `{ 0, 1 }`, columns `{ 0 }`, values `{ 1 }`, `wOutDeg { 1 }`, teleport `{ 1 }` | `{ 1, true }`; rank exactly `{ 1.0 }`. The kernel uses a self-loop it is given |
| K3 | chain 0→1: offsets `{ 0, 0, 1 }`, columns `{ 0 }`, values `{ 1 }`, `wOutDeg { 1, 0 }`, teleport `{ 0.5, 0.5 }` | x* = ( 1/(2+α), (1+α)/(2+α) ) = ( 0.350877190047, 0.649122809953 ). Shipped `{ 17, true }` (margins 1.133, 0.482); precise `{ 35, true }`. The existing 20/57 check is the fixed point for α = 0.85, so keep it under a config that passes 0.85 explicitly |
| K4 | 3 nodes, no edges, teleport `{ 0.6, 0.3, 0.1 }` | `{ 1, true }`; rank equals teleport within 1e-12 (the existing test) |
| K5 | cycle 0→1→2→0: offsets `{ 0, 1, 2, 3 }`, columns `{ 2, 0, 1 }`, values 1, `wOutDeg { 1, 1, 1 }`, uniform teleport | `{ 1, true }`; each score within 1e-15 of 1/3 |
| K6 | three callers of a dangling hub: offsets `{ 0, 0, 0, 0, 3 }`, columns `{ 0, 1, 2 }`, values 1, `wOutDeg { 1, 1, 1, 0 }`, teleport 0.25 each | each caller 1/(4+3α) = 0.152671754058; hub (1+3α)/(4+3α) = 0.541984737826. Shipped `{ 32, true }` (1.303, 0.831); precise `{ 68, true }`. The three caller scores are bit-identical to each other. Sorted with `sortutil::lessByScoreDescId` on the narrowed floats, the order is `{ 3, 0, 1, 2 }`, and it stays the same over three runs. This extends the existing test |
| K7 | fan-out 0→1 with weight 1, 0→2 with weight 3: offsets `{ 0, 0, 1, 2 }`, columns `{ 0, 0 }`, values `{ 1, 3 }`, `wOutDeg { 4, 0, 0 }`, teleport 1/3 each | c = 1/(3+α) = 0.259740258132; (1 + α/4)·c = 0.314935064533; (1 + 3α/4)·c = 0.425324677335. Shipped `{ 11, true }` (2.778, 0.787); precise `{ 24, true }`; order `{ 2, 1, 0 }` |
| K8 | the existing fractional fixture: values `{ 0.1f, 0.2f }`, `wOutDeg { double( 0.1f ) + double( 0.2f ) }` | with w1 = 0.1f and w2 = 0.2f: c = 1/(3+α) = 0.259740258132; (1 + α·w1/(w1+w2))·c = 0.333333333333; (1 + α·w2/(w1+w2))·c = 0.406926408535. Shipped `{ 11, true }` (2.223, 0.630); precise `{ 24, true }`. Today this test checks only mass |
| K9 | personalization on chain 0→1→2: offsets `{ 0, 0, 1, 2 }`, columns `{ 0, 1 }`, values 1, `wOutDeg { 1, 1, 0 }`, teleport `{ 1, 0, 0 }` | r0 = 1/(1+α+α²) = 0.388726909612; r1 = α·r0 = 0.330417882438; r2 = α²·r0 = 0.280855207950. Nodes with zero teleport still get rank. Shipped `{ 90, true }` (1.046, 0.889); precise `{ 189, true }` |
| K10 | outside the teleport's support: chain 0→1, teleport `{ 0, 1 }` | `{ 1, true }`; rank **exactly** `{ 0.0, 1.0 }` |
| K11 | α = 0 on K3's graph, teleport `{ 0.25, 0.75 }` | `{ 1, true }`; rank exactly equal to teleport |
| K12 | the worst case: 0→1 and 1→0, offsets `{ 0, 1, 2 }`, columns `{ 1, 0 }`, values 1, `wOutDeg { 1, 1 }`, teleport `{ 1, 0 }` | The error shrinks by exactly α per iteration, and every iterate has a closed form: x_k[0] = (1 + (−1)^k · α^(k+1)) / (1+α), and x_k[1] = 1 − x_k[0]. Shipped: `{ 90, true }`, the largest count any valid input can produce, with x_90[0] = 0.54054073772537781 within 1e-14. With `maxIterationCount = 90`: `{ 90, true }`, converging on the last allowed iteration. With `maxIterationCount = 89`: `{ 89, false }` and x_89[0] = 0.54054029339663212 within 1e-14. Precise: `{ 189, true }` |
| K13 | K12's graph at α = 0.9, τ = 1e-6, ceiling 100 | `{ 100, false }`: non-convergence from a legal config, with no hook. x_100[0] = (1 + 0.9^101)/1.9 = 0.52632837118894671 within 1e-14; mass is 1 within 1e-12. Also assert x_100[0] is **not** within 1e-5 of the fixed point 10/19: they are 1.26e-5 apart, so a band can see the truncation |
| K14 | K3 with `maxIterationCount = 1`, then 2 | With 1: `{ 1, false }`, rank **exactly** `{ 0.5 − α/4, 0.5 + α/4 }` = `{ 0.28749999403953552, 0.71250000596046448 }`, because every operation in the first iteration is exact for this α. With 2: `{ 2, false }`, rank[0] = 0.5 − α/4 + α²/8 = 0.3778124991059304 within 1e-15 |
| K15 | the block seam: N − 1 callers of one dangling hub, for N ∈ { 1023, 1024, 1025, 2049 }, with the hub at id N − 1 and again at id 0; uniform teleport 1/N | each caller c = 1/(N + (N−1)α), the hub c·(1 + (N−1)α), within 1e-5. For N = 1025: c = 5.2759311339e-4, hub 0.459744651889. For N = 2049: c = 2.6386616368e-4, hub 0.459602096783. Count: `{ 89, true }` for N ≤ 1025 (1.127, 0.957); for N = 2049 assert only converged and `iterationCount ≤ 90`. All callers are bit-identical to each other. The hub-first and hub-last runs agree within 1e-15 per score, not bitwise: their fold order differs |
| K16 | outputs and inputs: run K7 twice, into buffers pre-filled with NaN, and compare copies of the CSR arrays, `wOutDeg` and the teleport before and after | the two outputs are bit-identical (`std::memcmp`) and match a run without the pre-fill; the inputs are unchanged |
| K17 | defaults | `PageRankConfig{}` is `{ 0.85, 1e-6, 100 }` and `PageRankRun{}` is `{ 0, true }`, so a changed default shows up as a test diff (`docs/METHODOLOGY.md` §9) |

### The rank wrappers — `test/verify_pagerank.cpp`

| ID | Input | Expected |
| --- | --- | --- |
| B1 | `rw::Graph g;` with `g.priorWeight = { 1, 1, 0.5f, 0 }`; prior `{ 0.25f, 0.25f, 0.25f, 0.25f }` | `biasPrior` returns exactly `{ 0.4f, 0.4f, 0.2f, 0.0f }`; every operation is exact in float here |
| B2 | `priorWeight` of size 3 with a prior of size 4 | the prior, bit for bit |
| B3 | `priorWeight { 0, 0 }` with prior `{ 0.5f, 0.5f }` | the prior, bit for bit, and no alert. The plan should say whether the silence is intended |
| R1 | a hand-built `Graph`: K3's CSR, `wOutDeg { 1, 0 }`, `priorWeight { 1, 1 }`; call `rankGraphTeleport( g, { 0.5f, 0.5f } )` | `{ 17, true }`, and each `rank[i] == float( r[i] )` exactly, where `r` is `pageRankDouble` on teleport `{ 0.5, 0.5 }` with `alpha = double( 0.85f )`. It is exact because every step from the float prior to the kernel's teleport is exact here, so the kernel sees bit-identical inputs |
| R2 | `takeRank( rankGraphTeleport( g, … ), disclosure )` on R1's graph | the vector equals R1's rank, and `disclosure` is `{ 17, true, isPageRank = true }` |
| R3 | R1's graph with `priorWeight { 3, 1 }` | rank equals the `float` of the kernel on teleport `{ 0.75, 0.25 }`, exactly |
| R4 | `rankGraph( rw::Graph{} )` | an empty rank and `{ 0, true }` |
| R5 | K6's star as a `Graph`, with `priorWeight` all 1, through `rankGraph` | ids sorted with `sortutil::lessByScoreDescId` come out `{ 3, 0, 1, 2 }`, the same on three runs |

Do not write a test that claims to catch "0.85 instead of `double( 0.85f )`" from float output. For R1's
fixture on arm64 the two dampings happened to round to different floats for one score. That is a
rounding accident, not a property.

### Optional: the environment ceiling

**E1.** The gate runs `ripwire_test_pagerank -tc="E1*"` once per value of `RIPWIRE_TEST_PR_MAXITERS`,
passing the expected result in a second variable the test reads, so the expectation lives in the gate
rather than in the C++ under test. On K12's graph with the shipped config:
- unset → `{ 90, true }`
- `2` → `{ 2, false }`
- `000000002` (9 characters) → `{ 2, false }`
- `0000000002` (10 characters, ignored) → 90
- `0`, `12x` or `999999999` → 90; the hook can only lower the ceiling.

The 9- and 10-character strings are new coverage; `test/prconvergecheck.sh` arm C covers the rest on the
binary. In a normal run with the variables unset, E1 has nothing to assert. The gate must therefore
check that its own E1 runs executed assertions.

---

## Harness

- **Extend the two existing files.** Put CSR structure and `buildGraph` tests in `test/verify_csr.cpp`,
  and kernel and wrapper tests in `test/verify_pagerank.cpp`. The wrappers need `#include "graph.h"`
  there. That target already links `src/pagerank.cpp`, and `graph.h` needs nothing else at link time:
  the CSR target links it with only `diagnostics.cpp`. Do not call `rankGraphTeleport` from
  `verify_csr.cpp` unless you add `src/pagerank.cpp` to that target.
- **Use doctest only.** Add no dependency and no second framework (G3). If you split out a third
  target, add it to the three lists at `CMakeLists.txt:742-744`, or it builds without the sanitizers.
- **Write one `TEST_CASE` per ID, titled with the ID**, so the gate can filter with `-tc` and a failure
  names its row.
- **Tolerance checks** are `std::fabs( got - want ) <= band` with the band named (`kShippedBand = 1e-5`,
  `kPreciseBand = 1e-12`), the style the existing files use. Avoid `doctest::Approx`: its default
  epsilon is relative and unstated.
- **Exact checks** use `==` or `std::memcmp`, and only where a table says *exactly*.
- Build `rw::Graph` directly for the B and R tests; its members are public.

---

## CI wiring

1. **CMake needs nothing new.** `RIPWIRE_TESTS` already exists. Fix line 65 in its own first commit.
2. **The gate:** `test/csrpagerankcheck.sh` (a proposed name), shaped like `test/strkerncheck.sh`.
   - **Arm 0, presence.** Both target names appear in `CMakeLists.txt` and both sources exist. A missing
     target must FAIL, not silently run zero tests.
   - **Arm 1, G1 sanitizers.** Configure a `mktemp -d` scratch tree with `-DRIPWIRE_TESTS=ON
     -DRIPWIRE_ASAN=ON -DFETCHCONTENT_FULLY_DISCONNECTED=ON` and build
     `--target ripwire_test_csr ripwire_test_pagerank`. Run each binary with `ASAN_OPTIONS` (with
     `detect_leaks=0` on Darwin and `1` elsewhere, as strkerncheck does),
     `UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1`, and
     `LSAN_OPTIONS=suppressions=$ROOT/lsan_suppressions.txt`. FAIL on a non-zero exit, a non-zero
     failed count, or a case or assertion count below its floor. Floors are the counts the PR lands
     with, named `MIN_…`: minimums, never exact counts.
   - **Arm 2, NDEBUG.** Compile `test/verify_pagerank.cpp`, `src/pagerank.cpp` (with `-fno-fast-math`,
     as CMake does) and `src/infra/diagnostics.cpp` directly with `$CXX -DNDEBUG -O2`, using the target's
     include paths (`src/infra`, `third_party`, `src`, `third_party/deps/doctest`). Run K12, K13 and K14.
     The truncation contract exists because `DEGRADED_PATH_ALERT` vanishes under `NDEBUG`
     (`src/pagerank.h:22-26`); this arm is where a unit test proves the returned value survives.
   - **Arm 3, can go red.** Copy `src/` into the scratch directory, mutate the copy with `sed`, prove the
     mutation took with `cmp -s`, build the affected target against the copy, and require failures that
     name the expected IDs. At least:
     - **M1** deletes `++iterationCount;` in the converged branch: K1, K3 and K12 must fail.
     - **M2** drops the `config.alpha * danglingMass +` term: K3's and K6's values, and mass, must fail.
     - **M3** removes `|| values[edgeIndex] < T( 0 )` from `csrverify.h`: C5j must fail.

     Copy the whole `src/` tree, not one header: `graph.h` includes `infra/csrverify.h` relative to
     itself, so a single shadowed header gets included twice under two paths.
   - End with `exit "$fail"`; `test/gateexitcheck.sh` checks that failures reach the exit status.
3. **Register the gate in the same commit.**
   - Append the gate's name to the `for _g in …` loop in `test/regression.sh`.
   - Add a row to the `EXEMPT` table in `test/binoverridecheck.sh`. The gate never runs `build/ripwire`,
     so binoverridecheck fails without that row.
   - Run `python3 docs/gatecount_build.py` and commit what it rewrites (`README.md`, `docs/EVALS.md`,
     `present/deck5_ripwire_build.js`).

   `.github/pargates-shard-weights.json` needs no entry; an unlisted gate gets the median weight.
4. **Where CI runs it.** The `release` job in `.github/workflows/ci.yml` runs `test/pargates.py` over
   that loop on six legs, macOS 14 AppleClang, Ubuntu gcc and Ubuntu clang, each as `Release` and as
   `plain`. Every leg is split into four shards, so the gate runs once per leg: six times per push.
   **A leg's build flavour does not reach the gate's build.** The gate configures its own scratch trees,
   which is why arm 1 builds with ASan itself and arm 2 builds with `NDEBUG` itself. On the gcc legs the
   ASan configure gets GCC's smaller sanitizer set and announces it. The `asan` job runs named steps,
   not the loop, and needs no change. No workflow edit is required, and do not add the gate to
   `.github/pargates-macos-plain-skip.txt`.
5. **Correctness only.** No timing assertions, wall-clock budgets or speed checks. The iteration counts
   above are facts of the stopping rule, not speed targets. `test/pargates.py`'s 300-second default
   timeout, multiplied by 4 on CI, is a hang tripwire. `test/strkerncheck.sh` has the same shape and
   declares no override, so declare none unless the gate actually hangs.

---

## Build and verify

```bash
cmake -S . -B build && cmake --build build -j          # plain dev build: never -DCMAKE_BUILD_TYPE=Release
cmake -S . -B ../ripwire-tests-build -DRIPWIRE_TESTS=ON
cmake --build ../ripwire-tests-build --target ripwire_test_csr ripwire_test_pagerank -j
../ripwire-tests-build/ripwire_test_csr && ../ripwire-tests-build/ripwire_test_pagerank

export PYTHONDONTWRITEBYTECODE=1
bash test/csrpagerankcheck.sh
bash test/manifestcheck.sh && bash test/gatecountcheck.sh && bash test/binoverridecheck.sh && bash test/gateexitcheck.sh
bash test/strkerncheck.sh && bash test/dependencypincheck.sh    # both configure RIPWIRE_TESTS too
bash test/formatgatecheck.sh                                    # clang-format 22 on the gated files; skips without it
./build/ripwire . > a; ./build/ripwire . > b; diff -q a b       # determinism; src/ is unchanged
```

Keep extra build trees outside the checkout. A gitignored directory inside it is still counted by the
gates that crawl the live repository. Run the full suite on CI, not locally.

**Never edit the tree while a build is running.** `graph.h` pulls in `src/model.h`. After a branch
switch, rebuild with `--clean-first`: an incremental build can mix objects that disagree about
`sizeof( Symbol )`. The `static_assert` at `src/model.h:389` cannot catch that, because it passes in
each translation unit on its own. CLAUDE.md's "Build" section tells the story. The gate's scratch trees
are fresh every time; your local test tree is not.

---

## Style

Follow `CONTRIBUTING.md` §3; the rules that come up most in tests:

- Allman braces, braces on every control-statement body, spaces inside parentheses, lines wrapped at
  160-200 columns.
- Blank-line groups, each led by a comment.
- Index and count stay visibly distinct: `nodeIndex` and `nodeCount`, `edgeIndex` and `edgeCount`,
  `rowOffset` and `rowCount`. §3 calls mixing them the number-one off-by-one source in CSR code.
- Float comparisons use a tolerance band; for PageRank, assert scores within a band and the top-K order
  exactly.
- No `std::map` or `std::unordered_map`.
- C++23. `scripts/formatcheck.sh` gates only the files in its `GATED` block. That list includes
  `src/infra/csrverify.h`, `src/pagerank.cpp` and `src/pagerank.h`, but no test file. Its `--advisory`
  mode reports on `test/*.cpp` and always exits 0, so style in the test files is the house style above,
  applied by hand.

---

## Known traps

1. **The damping.** A test built on `PageRankConfig{}` checks a damping production never runs (fact 1).
2. **Bit equality.** Only between two calls of the same kernel on bit-identical inputs (fact 6).
3. **A precondition is not a branch you can test** in-process (fact 8).
4. **Once per process:** the alert and the environment ceiling (facts 9 and 10).
5. **An oracle that calls the code under test agrees with it.** Take expected values from closed forms
   or the reference. The correctness-fuzzers kit's second trap is the same one.
6. **Fixtures tied to the resolver.** G6 and G7 depend on today's resolver tiers and deboosts. Pin the
   invariant alongside the value: a split conserves confidence, and every weight is positive and at most
   8. A resolver change that moves them is a deliberate expectation update, reviewed as one.
7. **An arm that cannot fail** (`CONTRIBUTING.md` §2). A `-tc` filter that matches nothing runs zero
   cases and exits 0, printing `test cases: 0`, so assert the count. E1 has the same shape in a normal
   run.
8. **The PROFILE REPORT at exit** (fact 11).
9. **If a test finds a real defect, stop.** Record it, and land the fix separately with a test that fails
   first. This PR changes no behaviour under `src/`.

---

## Acceptance criteria

1. `test/verify_pagerank.cpp` compiles again, in its own commit, before any new test.
2. Every ID above exists as a test case with the stated expectation, or the plan says why it changed or
   was dropped. No expected value comes from running the code under test.
3. The gate has arms 0 to 3. Each mutation in arm 3 was seen to fail, and the failing IDs are recorded
   in the gate's header comment.
4. In the same commit, the gate is listed in `test/regression.sh`, pinned in
   `test/binoverridecheck.sh`, and the gate count is regenerated.
5. The rule in `CONTRIBUTING.md` §2, "the CSR property test fails", names the gate, so it points at
   something that runs.
6. No performance assertion anywhere.
7. Green in the foreground: the new gate, `test/manifestcheck.sh`, `test/gatecountcheck.sh`,
   `test/binoverridecheck.sh`, `test/gateexitcheck.sh`, `test/strkerncheck.sh`,
   `test/dependencypincheck.sh`, `test/formatgatecheck.sh` and the determinism diff. The full suite is
   green on CI.

---

## What the PR description should contain

- **The tests as landed:** the IDs, and which existing assertions were kept, extended or retitled.
- **The failing runs:** each mutation, and the IDs that failed.
- **The floors,** and the case and assertion counts they came from.
- **The CI legs** that ran the gate, with one job link per leg.
- **Every expectation that needed judgement:** G6, G7, K15 at N = 2049, and E1 if you took it.
- **What stays uncovered, and why:** the `VERIFY` preconditions, `nnz > UINT32_MAX`, overflow of the
  `uint32` prefix sum, `dominantEigenvector`, `hits`, and `rankGraphTeleport`'s unreachable zero-mass
  branch.

---

**Write a plan and stop.** The plan covers:
- the tests you will add, extend or drop;
- the gate's arms and mutations;
- where each test and helper goes;
- anything in this kit that turned out wrong when you read the code.

Then STOP until a maintainer approves it, before writing any code.
