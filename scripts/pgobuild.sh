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
# TRAINING (train_workload below — the one list both the build and --check-training run). TWO groups, each
# written to its own raw profile, merged WEIGHTED so coverage never outvotes the hot paths:
#   CORE (weight RIPWIRE_PGO_CORE_WEIGHT, default 4) — the original nine runs on this checkout, unchanged: cold
#     map, a src/ and a test/ crawl, cold+cache-write, warm map, --for, --pack-task, --callers, --impact. These
#     are the crawl/parse/resolve/emit paths every real run spends its time in.
#   COVERAGE (weight 1) — paths the core never reaches. On this checkout: page 2 of a paged map, --lint,
#     --clones, --expand, --grep, --for by exact name and by path + Type::method. On a SYNTHETIC tree
#     scripts/pgocorpus.py writes at build time (seeded, deterministic, no network): namespaces sharing the class
#     names Base/Impl/A/B, deep namesake inheritance, overloads, call-result chains — the class-identity /
#     guarded-walk / memo paths an llvm-sized run lives in — plus one slice of every other language family,
#     whose extractors the checkout never runs; there it runs the full verb list.
# Why weighted: the same coverage runs merged at weight 1 alongside the core measured ~2% MORE instructions on
# four held-out benchmark corpora — their counts diluted the general paths. The weight keeps the core dominant.
# On this checkout every run must exit 0 — a run that fails trains nothing for its verb, so the build FAILS
# rather than ship a profile with a hole in it (on a --corpus tree, where ripwire's own symbol names may not
# exist, a failed run is reported and the build goes on).
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
CORE_WEIGHT="${RIPWIRE_PGO_CORE_WEIGHT:-4}"
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
        -h|--help)        sed -n '2,43p' "$0"; exit 0 ;;
        *)                echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
    esac
done

[ -d "$CORPUS" ] || { echo "training corpus not found: $CORPUS" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 required (scripts/pgocorpus.py writes the synthetic training corpus)" >&2; exit 2; }

# ── the training workload ──────────────────────────────────────────────────────────────────────────────
# train_tree TREE CACHE PHRASE TASK [EXPAND CALLERS IMPACT GREP NAME PATHQ]: the full verb list on one tree (the
# synthetic corpus); the symbol-named runs need names that exist in TREE.
train_tree(){
    local tree="$1" cache="$2" phrase="$3" task="$4"
    local expand="${5:-}" callers="${6:-}" impact="${7:-}" grep="${8:-}" name="${9:-}" pathq="${10:-}"
    run "$tree" --no-cache
    run "$tree" --cache="$cache"
    run "$tree" --cache="$cache"
    run "$tree" --page-bytes=6000:2 --cache="$cache"
    run "$tree" --for="$phrase" --cache="$cache"
    run "$tree" --pack-task="$task" --cache="$cache"
    run "$tree" --lint --cache="$cache"
    run "$tree" --clones --cache="$cache"
    [ -n "$expand" ] || return 0
    run "$tree" --for="$name" --cache="$cache"
    run "$tree" --for="$pathq" --cache="$cache"
    run "$tree" --expand="$expand" --cache="$cache"
    run "$tree" --grep="$grep" --cache="$cache"
    run "$tree" --callers="$callers" --cache="$cache"
    run "$tree" --impact="$impact" --cache="$cache"
}

# train_workload BIN [PROFDIR]: every training run, with BIN. Each group's counters go to PROFDIR/<group>/ (the
# instrumented build passes $GEN/prof; --check-training's plain binary writes none). Returns non-zero when a run
# failed on this checkout (each one is named).
train_workload(){
    BIN="$1"
    local profdir="${2:-}"
    TRAIN="$( mktemp -d )"
    local fails=0 runs=0 t0="$SECONDS" strict=1
    [ "$CORPUS" = "$ROOT" ] || strict=0
    run(){
        runs=$(( runs + 1 ))
        "$BIN" "$@" >/dev/null 2>"$TRAIN/err"
        local rc=$?
        [ "$rc" -eq 0 ] && return 0
        echo "pgobuild: training run exited $rc: $*" >&2
        sed -n '1,3p' "$TRAIN/err" >&2
        [ "$strict" -eq 1 ] && fails=$(( fails + 1 ))
        return 0
    }
    # ── CORE: the original nine runs, verbatim ──
    [ -z "$profdir" ] || export LLVM_PROFILE_FILE="$profdir/core/default_%m.profraw"
    run "$CORPUS" --no-cache
    run "$CORPUS/src" --no-cache
    run "$CORPUS" --cache="$TRAIN/c.bin"
    run "$CORPUS" --cache="$TRAIN/c.bin"
    run "$CORPUS" --for="resolve references into the call graph" --cache="$TRAIN/c.bin"
    run "$CORPUS" --pack-task="add a new language grammar" --cache="$TRAIN/c.bin"
    run "$CORPUS" --callers=ingest --cache="$TRAIN/c.bin"
    run "$CORPUS" --impact=buildGraph --cache="$TRAIN/c.bin"
    run "$CORPUS/test" --no-cache
    # ── COVERAGE: paths the core never reaches ──
    [ -z "$profdir" ] || export LLVM_PROFILE_FILE="$profdir/coverage/default_%m.profraw"
    run "$CORPUS" --page-bytes=6000:2 --cache="$TRAIN/c.bin"
    run "$CORPUS" --lint --cache="$TRAIN/c.bin"
    run "$CORPUS" --clones --cache="$TRAIN/c.bin"
    if [ "$CORPUS" = "$ROOT" ]; then
        run "$CORPUS" --expand=buildGraph --cache="$TRAIN/c.bin"
        run "$CORPUS" --grep=ENSURES --cache="$TRAIN/c.bin"
        run "$CORPUS" --for=guardedBaseWalk --cache="$TRAIN/c.bin"
        run "$CORPUS" --for="src/resolve.h Narrower::guardedBaseWalk receiver narrowing" --cache="$TRAIN/c.bin"
    fi
    if python3 "$ROOT/scripts/pgocorpus.py" "$TRAIN/synthetic" >/dev/null; then
        train_tree "$TRAIN/synthetic" "$TRAIN/s.bin" "call-result chain through the builder and the context" "add an override of visit to every Impl" \
            dispatchAll run step checksum visit "cpp/mod3/Impl.cpp Builder::add overload picked by argument type"
    else
        echo "pgobuild: scripts/pgocorpus.py failed" >&2; fails=$(( fails + 1 ))
    fi
    unset LLVM_PROFILE_FILE
    rm -rf "$TRAIN"
    echo "pgobuild: training workload — $runs runs, $fails failed, $(( SECONDS - t0 )) s"
    [ "$fails" -eq 0 ]
}

if [ -n "$check_bin" ]; then
    [ -x "$check_bin" ] || { echo "--check-training needs an executable ripwire (got '$check_bin')" >&2; exit 2; }
    checkProf="$( mktemp -d )"   # the groups' LLVM_PROFILE_FILE is set exactly as in a build; a plain binary writes nothing there
    train_workload "$check_bin" "$checkProf/prof"; checkRc=$?
    rm -rf "$checkProf"
    exit "$checkRc"
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
    echo "pgobuild: [3/4] training: core on $CORPUS, coverage on it + the scripts/pgocorpus.py tree"
    train_workload "$GEN/ripwire" "$GEN/prof" || exit 1

    rawCore=$( ls "$GEN"/prof/core/*.profraw 2>/dev/null | wc -l | tr -d ' ' )
    rawCov=$( ls "$GEN"/prof/coverage/*.profraw 2>/dev/null | wc -l | tr -d ' ' )
    # A zero here is the failure that must never pass quietly: -fprofile-use on an empty merge produces a
    # perfectly ordinary binary, and the next person benchmarks it as "PGO bought nothing". Each GROUP must have
    # written counters: an empty coverage group is the old profile under a new name.
    [ "$rawCore" -gt 0 ] && [ "$rawCov" -gt 0 ] || { echo "pgobuild: training produced NO .profraw for a group (core=$rawCore coverage=$rawCov) — the instrumented binary wrote no counters" >&2; exit 1; }
    raw=$(( rawCore + rawCov ))
    echo "pgobuild: $raw raw profile(s) collected (core=$rawCore at weight $CORE_WEIGHT, coverage=$rawCov at weight 1)"
    weighted=()
    for f in "$GEN"/prof/core/*.profraw; do weighted+=( "-weighted-input=$CORE_WEIGHT,$f" ); done
    for f in "$GEN"/prof/coverage/*.profraw; do weighted+=( "-weighted-input=1,$f" ); done
    "$PROFDATA" merge -output="$PROFILE" "${weighted[@]}" || { echo "llvm-profdata merge failed" >&2; exit 1; }
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
