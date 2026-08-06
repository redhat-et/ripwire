#!/usr/bin/env bash
# scripts/pgobuild.sh — the whole profile-guided build, as one command.
#
#   scripts/pgobuild.sh                        # instrument -> train -> merge -> optimize
#   scripts/pgobuild.sh --corpus /path/to/repo # train on a different tree (see TRAINING below)
#   scripts/pgobuild.sh --reuse-profile        # skip instrument+train, rebuild from the existing .profdata
#   scripts/pgobuild.sh --clean
#
# Result: build_pgo/ripwire. Neither phase ever touches build/ or asan/ — CMakeLists refuses PGO in
# those trees by name, because they are what every gate and bench number in this repo is measured
# against and a silently PGO'd build/ripwire would move all of them at once.
#
# WHY THIS EXISTS. Optimization remarks said the hot path is call-bound across a translation-unit
# boundary (docs/OPTREMARKS.md F1 — the -DRIPWIRE_LTO=ON finding). PGO answers the classes LTO cannot:
# `inline/TooCostly` and `loop-vectorize/VectorizationNotBeneficial` are the cost model guessing at
# hotness, and a profile replaces the guess with counts. Measured: F2 in the same document.
#
# TRAINING. The workload below is a deliberate MIX — cold map, warm map, a --for query, a --pack-task
# bundle, two navigation verbs, and two differently-shaped corpora — not the benchmark this repo then
# quotes. Training on exactly the thing you measure is how a PGO number gets published that nobody
# else can reproduce. The published F2 numbers include a corpus that appears nowhere in this list.
#
# G3 NOTE. This is two configures and a training run, against a guardrail that asks for one build step.
# The .profdata is deliberately NOT committed: a stale committed profile is a warning, not an error,
# which trades a visible two-step build for an invisible wrong one. llvm-profdata is not a new
# dependency — it ships inside the Clang the build already requires.

set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
GEN="$ROOT/build_pgogen"
OPT="$ROOT/build_pgo"
PROFILE="$GEN/ripwire.profdata"
JOBS="${RIPWIRE_PGO_JOBS:-6}"
CORPUS="$ROOT"
reuse=0

while [ $# -gt 0 ]; do
    case "$1" in
        --corpus)         CORPUS="${2:-}"; shift 2 ;;
        --reuse-profile)  reuse=1; shift ;;
        --clean)          rm -rf "$GEN" "$OPT"; echo "removed $GEN and $OPT"; exit 0 ;;
        -h|--help)        sed -n '2,27p' "$0"; exit 0 ;;
        *)                echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
    esac
done

command -v cmake >/dev/null || { echo "cmake required" >&2; exit 2; }
[ -d "$CORPUS" ] || { echo "training corpus not found: $CORPUS" >&2; exit 2; }

# llvm-profdata: inside the active toolchain on macOS, on PATH (often versioned) on Linux.
PROFDATA="$( xcrun --find llvm-profdata 2>/dev/null || command -v llvm-profdata 2>/dev/null || true )"
if [ -z "$PROFDATA" ]; then
    for v in 21 20 19 18 17; do
        cand="$( command -v "llvm-profdata-$v" 2>/dev/null || true )"
        [ -n "$cand" ] && { PROFDATA="$cand"; break; }
    done
fi
[ -n "$PROFDATA" ] || { echo "llvm-profdata not found — it ships with Clang (try: xcrun --find llvm-profdata, or install llvm)" >&2; exit 2; }

if [ "$reuse" -eq 0 ]; then
    # ── phase 1: instrumented build ────────────────────────────────────────────────────────────────
    echo "pgobuild: [1/4] configuring the instrumented tree ($GEN)"
    rm -rf "$GEN"
    cmake -S "$ROOT" -B "$GEN" -DRIPWIRE_LTO=ON -DRIPWIRE_PGO=generate >"$GEN.cfg.log" 2>&1 || {
        echo "configure failed — see $GEN.cfg.log" >&2; tail -20 "$GEN.cfg.log" >&2; exit 1; }
    rm -f "$GEN.cfg.log"
    echo "pgobuild: [2/4] building instrumented (this binary is SLOW by design — counters on every edge)"
    cmake --build "$GEN" -j "$JOBS" --target ripwire >"$GEN/build.log" 2>&1 || {
        echo "instrumented build failed — see $GEN/build.log" >&2; tail -20 "$GEN/build.log" >&2; exit 1; }

    # ── phase 2: train ─────────────────────────────────────────────────────────────────────────────
    echo "pgobuild: [3/4] training on $CORPUS"
    BIN="$GEN/ripwire"
    TRAIN="$( mktemp -d )"
    run(){ "$BIN" "$@" >/dev/null 2>&1 || echo "pgobuild: training run returned non-zero (continuing): $*" >&2; }
    run "$CORPUS" --no-cache
    run "$CORPUS/src" --no-cache
    run "$CORPUS" --cache="$TRAIN/c.bin"
    run "$CORPUS" --cache="$TRAIN/c.bin"
    run "$CORPUS" --for="resolve references into the call graph" --cache="$TRAIN/c.bin"
    run "$CORPUS" --pack-task="add a new language grammar" --cache="$TRAIN/c.bin"
    run "$CORPUS" --callers=ingest --cache="$TRAIN/c.bin"
    run "$CORPUS" --impact=buildGraph --cache="$TRAIN/c.bin"
    run "$CORPUS/test" --no-cache
    rm -rf "$TRAIN"

    raw=$( ls "$GEN"/prof/*.profraw 2>/dev/null | wc -l | tr -d ' ' )
    # A zero here is the failure that must never pass quietly: -fprofile-use on an empty merge produces a
    # perfectly ordinary binary, and the next person benchmarks it as "PGO bought nothing".
    [ "$raw" -gt 0 ] || { echo "pgobuild: training produced NO .profraw files — the instrumented binary wrote no counters" >&2; exit 1; }
    echo "pgobuild: $raw raw profile(s) collected"
    "$PROFDATA" merge -output="$PROFILE" "$GEN"/prof/*.profraw || { echo "llvm-profdata merge failed" >&2; exit 1; }
fi

[ -s "$PROFILE" ] || { echo "no profile at $PROFILE — run without --reuse-profile" >&2; exit 2; }

# ── phase 3: the optimized build ───────────────────────────────────────────────────────────────────
echo "pgobuild: [4/4] configuring + building the optimized tree ($OPT)"
rm -rf "$OPT"
cmake -S "$ROOT" -B "$OPT" -DRIPWIRE_LTO=ON -DRIPWIRE_PGO=use -DRIPWIRE_PGO_PROFILE="$PROFILE" >"$OPT.cfg.log" 2>&1 || {
    echo "configure failed — see $OPT.cfg.log" >&2; tail -20 "$OPT.cfg.log" >&2; exit 1; }
rm -f "$OPT.cfg.log"
# The optimized tree builds EVERY target, not just `ripwire`. The instrumented phase above needs only
# the one binary it trains, but this tree has to be runnable against the full suite, and several gates
# shell out to ripwire_probe — with only `ripwire` built they exit 2 ("no ripwire_probe … build first")
# and are counted as harness errors rather than as evidence about the PGO binary.
cmake --build "$OPT" -j "$JOBS" >"$OPT/build.log" 2>&1 || {
    echo "optimized build failed — see $OPT/build.log" >&2; tail -20 "$OPT/build.log" >&2; exit 1; }

echo "pgobuild: done — $OPT/ripwire (profile: $PROFILE)"
echo "pgobuild: verify before you trust it:"
echo "  $OPT/ripwire $ROOT >a; $OPT/ripwire $ROOT >b; diff -q a b        # determinism is a contract"
echo "  diff -q <($OPT/ripwire $ROOT) <($ROOT/build/ripwire $ROOT)       # PGO must not change a byte of output"
echo "  RIPWIRE_BIN=$OPT/ripwire python3 $ROOT/test/pargates.py $ROOT $OPT/ripwire -j 6"
