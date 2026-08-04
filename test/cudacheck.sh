#!/usr/bin/env bash
# cudacheck.sh — the gate for CUDA (.cu/.cuh) coverage on the tree-sitter-cuda grammar.
#
#   test/cudacheck.sh
#   RIPWIRE_BIN=asan/ripwire test/cudacheck.sh
#
# THE FAILURE THIS PINS: measured before the grammar was added (2026-08-04, the probe that decided the
# design): under the plain C++ grammar a `.cu` file's DEFINITIONS all survived error recovery, but every
# `kernel<<<grid, block>>>( args )` launch site produced NO call reference — `--callers=rk_reduceSum`
# returned count=0, so the host→kernel half of the call graph was invisible (the exact failure mode
# metalcheck.sh pins for MSL, where error recovery happened to be enough; for CUDA it measurably is not).
# `.cu`/`.cuh` are therefore indexed with the VENDORED tree-sitter-cuda grammar (a generated superset of
# tree-sitter-cpp: `kernel_call_expression` is ALIASED to `call_expression` with a `function:` field, so
# the C++ tags.scm needs no CUDA patterns) under Lang::Cpp — same deliberate choice as Metal: host and
# device share ONE call namespace through dual-compile headers, and a separate Lang would drop out of
# every C-family behaviour for no benefit. See kLangTable's comment in src/ingest.cpp.
#
# The fixture test/cudafix/ is the smallest thing that carries every construct that decision rests on:
#   reduceKernels.cu  — `__global__`/`__device__`/`__forceinline__` qualifiers, an UNINITIALIZED
#                       `__constant__` module table plus `__device__`/`__managed__` module globals (the
#                       memory-space extraction policy §7b pins), `__shared__` tile memory,
#                       `__launch_bounds__`, a templated kernel, and host-side wrappers with `<<<>>>`
#                       launches (2-arg, 3-arg, and template-kernel).
#   reduceShared.cuh  — the DUAL-COMPILE header: `#ifdef __CUDACC__` guard, a `__host__ __device__`
#                       helper (rk_normalize), and the wrapper declarations both halves share.
#   hostMain.cpp      — the pure-host half, calling the wrappers and the dual-compile helper.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/cudafix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "cudacheck: BIN=$BIN  FIX=$FIX"

"$BIN" "$FIX" --no-cache >"$TMP/map" 2>/dev/null
MAP="$( cat "$TMP/map" )"

# ── 1) both CUDA extensions are crawled at all (the whole premise) ────────────────────────────────────
printf '%s' "$MAP" | grep -q 'f p="[^"]*reduceKernels\.cu"' \
    && ok ".cu is crawled and indexed" \
    || { no ".cu file absent from the map — the extension is not registered"; printf '%s\n' "$MAP" | head -c 800; }
printf '%s' "$MAP" | grep -q 'f p="[^"]*reduceShared\.cuh"' \
    && ok ".cuh is crawled and indexed" \
    || no ".cuh file absent from the map — the extension is not registered"

# ── 2) each CUDA qualifier flavour yields a real definition (no error-recovery roulette) ──────────────
for sym in rk_warpReduce rk_clampScale rk_reduceSum rk_reduceMax rk_fill rk_normalize host_runPipeline; do
    printf '%s' "$MAP" | grep -q "n=\"$sym\"" \
        && ok "definition extracted: $sym" \
        || no "definition MISSING: $sym"
done

# ── 3) NO garbage symbols: a CUDA keyword must never become a symbol name ─────────────────────────────
junk=0
for kw in __global__ __device__ __host__ __constant__ __managed__ __shared__ __forceinline__ __launch_bounds__ dim3; do
    printf '%s' "$MAP" | grep -q "n=\"$kw\"" && { no "keyword leaked in as a symbol name: $kw"; junk=1; }
done
[ $junk -eq 0 ] && ok "no CUDA keyword leaked in as a symbol name (__global__/__device__/__constant__/…)"

# ── 4) THE ACCEPTANCE CASE: `<<<>>>` launch sites are call edges (count=0 under the C++ grammar) ──────
"$BIN" "$FIX" --no-cache --callers=rk_reduceSum >"$TMP/c1" 2>/dev/null
grep -q 'reduceKernels\.cu' "$TMP/c1" \
    && ok "--callers=rk_reduceSum names the launching wrapper (was count=0 before the CUDA grammar)" \
    || { no "--callers=rk_reduceSum has no caller — the <<<>>> launch edge is lost"; head -c 600 "$TMP/c1"; }
"$BIN" "$FIX" --no-cache --callers=rk_reduceMax >"$TMP/c2" 2>/dev/null
grep -q 'rk_launchReduce' "$TMP/c2" \
    && ok "--callers=rk_reduceMax sees the 3-argument launch (<<<grid, block, 0>>>)" \
    || no "--callers=rk_reduceMax lost the 3-argument launch form"
"$BIN" "$FIX" --no-cache --callers=rk_fill >"$TMP/c3" 2>/dev/null
grep -q 'rk_launchFill' "$TMP/c3" \
    && ok "--callers=rk_fill sees the template-kernel launch (rk_fill<float><<<…>>>)" \
    || no "--callers=rk_fill lost the template-kernel launch form"

# ── 5) device-internal call edges still resolve (the part the C++ grammar already got right) ──────────
"$BIN" "$FIX" --no-cache --callers=rk_warpReduce >"$TMP/c4" 2>/dev/null
grep -q 'rk_reduceSum' "$TMP/c4" \
    && ok "device-internal call edge resolves (rk_warpReduce <- rk_reduceSum)" \
    || no "device-internal call edge missing"

# ── 6) dual-compile: the .cuh helper is reachable from the pure-host half ─────────────────────────────
"$BIN" "$FIX" --no-cache --callers=rk_normalize >"$TMP/c5" 2>/dev/null
grep -q 'hostMain\.cpp' "$TMP/c5" \
    && ok "--callers=rk_normalize names the pure-host caller (both halves reach the shared .cuh)" \
    || { no "--callers=rk_normalize has no host caller"; head -c 600 "$TMP/c5"; }
"$BIN" "$FIX" --no-cache --uses=rk_reduceSum >"$TMP/u1" 2>/dev/null
grep -q 'role="call" p="[^"]*reduceKernels\.cu:[0-9]' "$TMP/u1" \
    && ok "--uses=rk_reduceSum reports the launch use-site (role=call, file:line)" \
    || { no "--uses=rk_reduceSum missing the launch use-site"; head -c 600 "$TMP/u1"; }

# ── 7) the .cu -> .cuh include edge exists (what physically links the halves) ─────────────────────────
"$BIN" "$FIX" --no-cache --deps >"$TMP/deps" 2>/dev/null
tr '<' '\n' < "$TMP/deps" | grep -A3 'reduceKernels\.cu"' | grep -q 'inc t="reduceShared\.cuh"' \
    && ok '#include "reduceShared.cuh" became an include edge from the .cu' \
    || { no "the .cu -> .cuh include edge is missing"; head -c 600 "$TMP/deps"; }

# ── 7b) the C-family behaviours .cu/.cuh inherit through Lang::Cpp actually engage ────────────────────
#     constexpr SCREAMING_SNAKE module constants extract (the constcheck convention, in a .cuh), and a
#     .cuh struct is layout-modelled (isCFamilyPath gained .cu/.cuh — a TypeScript class has no byte
#     layout, a CUDA parameter block does). The 2026-08-04 KNOWN LIMIT is now CLOSED and pinned positive:
#     an UNINITIALIZED `__constant__ float T[64];` module table (the cudaMemcpyToSymbol idiom — the old
#     pattern required an init_declarator, so it could never match) extracts REGARDLESS of case — the
#     memory-space qualifier, not the name, is the evidence (the Rust const_item rationale). Mutable
#     device globals (`__device__`/`__managed__`) stay behind the SCREAMING_SNAKE convention gate:
#     a SCREAMING table indexes, a lower-case accumulator does not.
printf '%s' "$MAP" | grep -q 'n="RK_TILE_WIDTH"' \
    && ok "constexpr module constant extracts from the .cuh (RK_TILE_WIDTH)" \
    || no "constexpr module constant missing from the .cuh"
printf '%s' "$MAP" | grep -q 'n="rk_scaleTable"' \
    && ok "__constant__ module table extracts, case-blind (rk_scaleTable — the closed 2026-08-04 limit)" \
    || no "__constant__ module table missing (rk_scaleTable) — the 7b limit has regressed to open"
printf '%s' "$MAP" | grep -q 'n="rk_tileWeights"' \
    && ok "2-D __constant__ table extracts (rk_tileWeights — the cuda-samples c_Table shape)" \
    || no "2-D __constant__ table missing (rk_tileWeights)"
printf '%s' "$MAP" | grep -q 'n="rk_biasTable"' \
    && ok "INITIALIZED __constant__ extracts case-blind (rk_biasTable — the dxtc kColorMetric shape)" \
    || no "initialized lower-case __constant__ missing (rk_biasTable) — init path still convention-gated"
printf '%s' "$MAP" | grep -q 'n="rk_guardTable"' \
    && ok "__constant__ inside a preprocessor conditional extracts (rk_guardTable — the header-guard idiom)" \
    || no "preproc-wrapped __constant__ missing (rk_guardTable) — preproc wrappers absent"
printf '%s' "$MAP" | grep -q 'n="RK_DEV_LUT"' \
    && ok "SCREAMING __device__ module table extracts (RK_DEV_LUT)" \
    || no "SCREAMING __device__ module table missing (RK_DEV_LUT)"
printf '%s' "$MAP" | grep -q 'n="RK_MANAGED_SEED"' \
    && ok "SCREAMING __managed__ module binding extracts (RK_MANAGED_SEED)" \
    || no "SCREAMING __managed__ module binding missing (RK_MANAGED_SEED)"
printf '%s' "$MAP" | grep -q 'n="rk_devAccum"' \
    && no "lower-case mutable __device__ global leaked past the convention gate (rk_devAccum)" \
    || ok "lower-case mutable __device__ global stays unindexed (rk_devAccum)"
"$BIN" "$FIX" --no-cache --uses=rk_scaleTable >"$TMP/u2" 2>/dev/null
grep -q 'role="read" p="[^"]*reduceKernels\.cu:[0-9]' "$TMP/u2" \
    && ok "--uses=rk_scaleTable names the device-side read site (the payoff of indexing the table)" \
    || { no "--uses=rk_scaleTable missing the read site"; head -c 400 "$TMP/u2"; }
"$BIN" "$FIX" --no-cache --layout=RkReduceParams >"$TMP/lay" 2>/dev/null
grep -q 'RkReduceParams' "$TMP/lay" && grep -q 'scale' "$TMP/lay" \
    && ok "--layout models the .cuh parameter block (isCFamilyPath covers .cu/.cuh)" \
    || { no "--layout does not model the .cuh struct"; head -c 400 "$TMP/lay"; }

# ── 8) bodies are the VERBATIM source (no scrub; the launch syntax survives into --expand) ────────────
"$BIN" "$FIX" --no-cache --expand=rk_launchReduce >"$TMP/exp" 2>/dev/null
grep -q 'rk_reduceSum<<<grid, block>>>' "$TMP/exp" \
    && ok "--expand returns the verbatim launch site (<<<grid, block>>> is not rewritten)" \
    || { no "--expand body text was rewritten"; head -c 600 "$TMP/exp"; }
"$BIN" "$FIX" --no-cache --expand=rk_reduceSum >"$TMP/exp2" 2>/dev/null
grep -q '__global__ void rk_reduceSum' "$TMP/exp2" \
    && ok "--expand returns the verbatim __global__ qualifier" \
    || no "--expand lost the __global__ qualifier"

# ── 9) determinism + G4 well-formedness + minification ────────────────────────────────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/b" 2>/dev/null
cmp -s "$TMP/a" "$TMP/b" && ok "determinism (two cold runs byte-identical)" || no "non-deterministic on a .cu corpus"
"$BIN" "$FIX" >"$TMP/w1" 2>/dev/null; "$BIN" "$FIX" >"$TMP/w2" 2>/dev/null
cmp -s "$TMP/w1" "$TMP/w2" && ok "determinism (warm/cached runs byte-identical)" || no "warm run differs from itself"
cmp -s "$TMP/a" "$TMP/w2" && ok "warm run matches the cold run (cache carries .cu/.cuh facts correctly)" \
                          || no "warm .cu run differs from cold — cache/parserVer mismatch"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/a" 2>/dev/null && ok "G4: .cu map XML well-formed" || no "G4: malformed XML on a .cu corpus"
else
    ok "xmllint unavailable — G4 skipped"
fi
[ "$( grep -c '' "$TMP/a" )" -le 1 ] && ok "output is minified (no stray newlines)" || no "newlines outside CDATA"

# ── 10) the user-visible language list names CUDA (doc/binary agreement) ──────────────────────────────
"$BIN" --help 2>&1 | grep -qi 'CUDA' \
    && ok "--help advertises CUDA" || no "--help does not mention CUDA"
grep -qi 'CUDA' "$ROOT/README.md" \
    && ok "README advertises CUDA" || no "README does not mention CUDA"

[ $fail -eq 0 ] && echo "cudacheck: ALL PASS" || echo "cudacheck: FAILURES"
exit $fail
