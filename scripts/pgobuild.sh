#!/usr/bin/env bash
# scripts/pgobuild.sh — the whole profile-guided build, as one command.
#
#   scripts/pgobuild.sh                        # instrument -> train -> merge -> optimize
#   scripts/pgobuild.sh --corpus /path/to/repo # train on a different tree instead of this checkout (see TRAINING)
#   scripts/pgobuild.sh --reuse-profile        # skip instrument+train, rebuild from the existing .profdata
#   scripts/pgobuild.sh --check-training BIN   # run the training workload with BIN, no build: every run must exit 0
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
# TRAINING (train_workload below — the one list both the build and --check-training run). TWO corpora:
#   1. this checkout — the C++ extractor at production size, ripwire's own hubs, its shell/Python test tree;
#   2. a SYNTHETIC tree scripts/pgocorpus.py writes at build time (seeded, deterministic, no network): many
#      namespaces sharing the class names Base/Impl/A/B, deep namesake inheritance, out-of-line members,
#      overloads, call-result chains, plus one slice of every other language family. Ripwire's own source
#      has few namesakes, so without it the class-identity / guarded-walk / memo paths that dominate an
#      llvm-sized run are profiled as nearly cold, and most extractors are never profiled at all.
# On EACH corpus: cold map, cold+cache-write, warm map, page 2 of a paged map, --for in three shapes (a
# phrase, an exact symbol name, a path + Type::method mention), --pack-task, --lint, --expand on a hub,
# --grep, --clones, --callers, --impact. Every run must exit 0 — a run that fails trains nothing for its
# verb, so the build FAILS rather than ship a profile with a hole in it.
# What it never trains on: a benchmark corpus. Training on exactly the thing you measure is how a PGO number
# gets published that nobody else can reproduce; the published F2 numbers include a corpus that appears
# nowhere in this list, and test/optremarkscheck.sh refuses a benchmark repo's name in this file.
#
# G3 NOTE. This is two configures and a training run, against a guardrail that asks for one build step.
# The .profdata is deliberately NOT committed: a stale committed profile is a warning, not an error,
# which trades a visible two-step build for an invisible wrong one. llvm-profdata is not a new
# dependency — it ships inside the Clang the build already requires; python3 (the corpus generator,
# standard library only) is already on every runner the release workflow uses.

set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
GEN="$ROOT/build_pgogen"
OPT="$ROOT/build_pgo"
PROFILE="$GEN/ripwire.profdata"
JOBS="${RIPWIRE_PGO_JOBS:-6}"
CORPUS="$ROOT"
reuse=0
check_bin=""

cmake_extra=()   # --cmake-extra ARG (repeatable): appended to BOTH configures — the release
                 # pipeline passes -DCMAKE_BUILD_TYPE=Release (through 0.6.1 the macOS x64 cross leg also
                 # passed its OSX arch)
while [ $# -gt 0 ]; do
    case "$1" in
        --corpus)         CORPUS="${2:-}"; shift 2 ;;
        --cmake-extra)    cmake_extra+=( "${2:-}" ); shift 2 ;;
        --reuse-profile)  reuse=1; shift ;;
        --check-training) check_bin="${2:-}"; shift 2 ;;
        --clean)          rm -rf "$GEN" "$OPT"; echo "removed $GEN and $OPT"; exit 0 ;;
        -h|--help)        sed -n '2,39p' "$0"; exit 0 ;;
        *)                echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
    esac
done

[ -d "$CORPUS" ] || { echo "training corpus not found: $CORPUS" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 required (scripts/pgocorpus.py writes the synthetic training corpus)" >&2; exit 2; }

# ── the training workload ──────────────────────────────────────────────────────────────────────────────
# train_tree TREE TAG [EXPAND CALLERS IMPACT GREP NAME PATHQ]: the per-corpus run list. The symbol-named runs
# need names that exist in TREE, so a --corpus tree (names unknown) gets the name-free runs only.
train_tree(){
    local tree="$1" cache="$TRAIN/$2.bin" phrase="$3" task="$4"
    local expand="${5:-}" callers="${6:-}" impact="${7:-}" grep="${8:-}" name="${9:-}" pathq="${10:-}"
    run "$tree" --no-cache                                  # cold map: crawl, parse, extract, resolve, rank, emit
    run "$tree" --cache="$cache"                            # cold again, writing the cache
    run "$tree" --cache="$cache"                            # warm map: the cache load + graph rebuild path
    run "$tree" --page-bytes=6000:2 --cache="$cache"        # a paged bare map, page 2
    run "$tree" --for="$phrase" --cache="$cache"            # --for, conceptual phrase (subtoken+body route)
    run "$tree" --pack-task="$task" --cache="$cache"
    run "$tree" --lint --cache="$cache"
    run "$tree" --clones --cache="$cache"
    [ -n "$expand" ] || return 0
    run "$tree" --for="$name" --cache="$cache"              # --for, an exact symbol name (name-exact route)
    run "$tree" --for="$pathq" --cache="$cache"             # --for, a path + Type::method mention (anchors)
    run "$tree" --expand="$expand" --cache="$cache"
    run "$tree" --grep="$grep" --cache="$cache"
    run "$tree" --callers="$callers" --cache="$cache"
    run "$tree" --impact="$impact" --cache="$cache"
}

# train_workload BIN: every training run, with BIN. Returns non-zero when any run failed (each one is named).
train_workload(){
    BIN="$1"
    TRAIN="$( mktemp -d )"
    local fails=0 runs=0 t0="$SECONDS"
    run(){
        runs=$(( runs + 1 ))
        "$BIN" "$@" >/dev/null 2>"$TRAIN/err"
        local rc=$?
        [ "$rc" -eq 0 ] && return 0
        fails=$(( fails + 1 ))
        echo "pgobuild: training run exited $rc: $*" >&2
        sed -n '1,3p' "$TRAIN/err" >&2
    }
    python3 "$ROOT/scripts/pgocorpus.py" "$TRAIN/synthetic" || { echo "pgobuild: scripts/pgocorpus.py failed" >&2; rm -rf "$TRAIN"; return 1; }
    if [ "$CORPUS" = "$ROOT" ]; then
        train_tree "$ROOT" self "resolve references into the call graph" "add a new language grammar" \
            buildGraph ingest buildGraph DEGRADED_PATH_ALERT guardedBaseWalk "src/resolve.h Narrower::guardedBaseWalk receiver narrowing"
        run "$ROOT/src" --no-cache                         # a sub-tree crawl of the same code
        run "$ROOT/test" --no-cache                        # the shell + Python gate tree: the Bash and Python extractors
    else
        train_tree "$CORPUS" self "resolve references into the call graph" "add a new feature"
    fi
    train_tree "$TRAIN/synthetic" synthetic "call-result chain through the builder and the context" "add an override of visit to every Impl" \
        dispatchAll run step checksum visit "cpp/mod3/Impl.cpp Builder::add overload picked by argument type"
    rm -rf "$TRAIN"
    echo "pgobuild: training workload — $runs runs, $fails failed, $(( SECONDS - t0 )) s"
    [ "$fails" -eq 0 ]
}

if [ -n "$check_bin" ]; then
    [ -x "$check_bin" ] || { echo "--check-training needs an executable ripwire (got '$check_bin')" >&2; exit 2; }
    train_workload "$check_bin"
    exit $?
fi

command -v cmake >/dev/null || { echo "cmake required" >&2; exit 2; }

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
    cmake -S "$ROOT" -B "$GEN" -DRIPWIRE_LTO=ON -DRIPWIRE_PGO=generate ${cmake_extra[@]+"${cmake_extra[@]}"} >"$GEN.cfg.log" 2>&1 || {
        echo "configure failed — see $GEN.cfg.log" >&2; tail -20 "$GEN.cfg.log" >&2; exit 1; }
    rm -f "$GEN.cfg.log"
    echo "pgobuild: [2/4] building instrumented (this binary is SLOW by design — counters on every edge)"
    cmake --build "$GEN" -j "$JOBS" --target ripwire >"$GEN/build.log" 2>&1 || {
        echo "instrumented build failed — see $GEN/build.log" >&2; tail -20 "$GEN/build.log" >&2; exit 1; }

    # ── phase 2: train ─────────────────────────────────────────────────────────────────────────────
    echo "pgobuild: [3/4] training on $CORPUS and the synthetic corpus (scripts/pgocorpus.py)"
    train_workload "$GEN/ripwire" || exit 1

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
cmake -S "$ROOT" -B "$OPT" -DRIPWIRE_LTO=ON -DRIPWIRE_PGO=use -DRIPWIRE_PGO_PROFILE="$PROFILE" ${cmake_extra[@]+"${cmake_extra[@]}"} >"$OPT.cfg.log" 2>&1 || {
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
echo "  t=\$(mktemp -d); $OPT/ripwire $ROOT >\"\$t/a\"; $OPT/ripwire $ROOT >\"\$t/b\"; diff -q \"\$t/a\" \"\$t/b\"   # determinism is a contract (outputs outside the tree)"
echo "  diff -q <($OPT/ripwire $ROOT) <($ROOT/build/ripwire $ROOT)       # PGO must not change a byte of output"
echo "  RIPWIRE_BIN=$OPT/ripwire python3 $ROOT/test/pargates.py $ROOT $OPT/ripwire -j 6"
