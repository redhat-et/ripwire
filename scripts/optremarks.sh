#!/usr/bin/env bash
# scripts/optremarks.sh — configure, build, and triage a clang optimization-remarks tree.
#
# One command for the whole loop. It exists mostly to make three things impossible to get wrong:
#
#   1. THE TREE IS build_remarks/, NEVER build/. build/ripwire is what every gate and every bench
#      number in this repo is measured against; the remarks flags would leave it carrying ~850 MB of
#      opt-record YAML. CMakeLists.txt refuses -DRIPWIRE_OPT_REMARKS=ON inside build/ or asan/, and
#      this script only ever names build_remarks/.
#   2. NO BUILD TYPE IS PASSED. Remarks only mean something in an optimized build, but Release
#      defines NDEBUG and compiles the degrade-path alert macro out (CONTRIBUTING.md §5). None is needed:
#      RIPWIRE_ARCH_FLAGS already puts the plain configuration at -O2, so this tree reports on the
#      same codegen the shipping binary has, with the degrade paths still compiled in.
#   3. THE BUILD LOG IS REDIRECTED. -Rpass=.* -Rpass-missed=.* -Rpass-analysis=.* over src/main.cpp
#      writes ~340 MB to stderr. It goes to build_remarks/remarks.stderr.log, not your terminal.
#
# Usage:
#   scripts/optremarks.sh                      # configure + build + summary triage
#   scripts/optremarks.sh --triage-only        # re-triage an existing tree (no rebuild)
#   scripts/optremarks.sh --passes 'inline|loop-vectorize|licm'
#                                              # narrow BOTH the stderr remarks and the YAML record to
#                                              # those passes. The unfiltered record for src/main.cpp
#                                              # alone passes 800 MB (the per-function-per-pass
#                                              # bookkeeping classes — size-info, asm-printer,
#                                              # prologepilog — grow with functions x passes, and that
#                                              # TU has thousands of functions). Run wide ONCE to learn
#                                              # which classes fire, then narrow to triage.
#   scripts/optremarks.sh --clean              # remove build_remarks/ entirely
#
# Everything after `--` is forwarded to scripts/optremarks.py:
#   scripts/optremarks.sh --triage-only -- --hot --pass loop-vectorize --sites 40
#
# A remark is an OBSERVATION, not a defect. docs/OPTREMARKS.md and skills/clang-opt-remarks/SKILL.md
# carry the triage rules and the measured outcomes; do not act on a remark without a bench number.

set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
TREE="$ROOT/build_remarks"
LOG="$TREE/remarks.stderr.log"
JOBS="${RIPWIRE_OPT_REMARKS_JOBS:-6}"
PASSES=""
triageOnly=0
forward=()

while [ $# -gt 0 ]; do
    case "$1" in
        --triage-only)  triageOnly=1; shift ;;
        --passes)       PASSES="${2:-}"; shift 2 ;;
        --clean)        rm -rf "$TREE"; echo "removed $TREE"; exit 0 ;;
        --)             shift; forward=( "$@" ); break ;;
        -h|--help)      sed -n '2,32p' "$0"; exit 0 ;;
        *)              echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
    esac
done

command -v cmake >/dev/null || { echo "cmake required" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 2; }

if [ "$triageOnly" -eq 0 ]; then
    # Narrowing is one cache variable, applied to the -Rpass* trio AND the YAML record alike, so the
    # stderr log and the opt-record never disagree about what was collected.
    filter="${PASSES:-.*}"
    [ -n "$PASSES" ] && echo "optremarks: narrowing remarks to passes matching '$PASSES'"
    cmake -S "$ROOT" -B "$TREE" -DRIPWIRE_OPT_REMARKS=ON -DRIPWIRE_OPT_REMARKS_FILTER="$filter" >"$TREE.cfg.log" 2>&1 || {
        echo "configure failed — see $TREE.cfg.log" >&2; tail -20 "$TREE.cfg.log" >&2; exit 1; }
    rm -f "$TREE.cfg.log"
    # Stale records from a previous, differently-filtered run would be triaged as if they belonged to
    # this one — and a TU that does not need recompiling never rewrites its .opt.yaml.
    find "$TREE" -name '*.opt.yaml' -delete
    echo "optremarks: building (stderr remarks -> $LOG; this is slow and the log is large)"
    cmake --build "$TREE" -j "$JOBS" --target ripwire >"$LOG" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "build failed rc=$rc — real errors are in $LOG, mixed into the remark stream:" >&2
        grep -m 20 -E '\berror\b' "$LOG" >&2
        exit "$rc"
    fi
    echo "optremarks: build ok — log $( du -h "$LOG" | cut -f1 ), records $( du -sh "$TREE"/CMakeFiles/ripwire.dir 2>/dev/null | cut -f1 )"
fi

[ -d "$TREE" ] || { echo "no $TREE — run without --triage-only first" >&2; exit 2; }
exec python3 "$ROOT/scripts/optremarks.py" --build-dir "$TREE" "${forward[@]+"${forward[@]}"}"
