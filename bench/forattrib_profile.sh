#!/usr/bin/env bash
# bench/forattrib_profile.sh — collect the `--for` answer's phase map from a PROFILE build and print
# a ranked, parent-checked attribution table (lane/verbfor-attrib, 2026-11-27).
#
# WHAT THIS IS FOR. A warm `--for` on a large tree spent ~80% of its time in one unlabelled bucket
# inside verbs_for.h. src/verbs_for.h and src/forpage.h now carry a PROFILE_SCOPE at the entry of
# each phase; this script runs them and turns the #PROF_TSV blocks into shares.
#
# TWO ARMS, and the difference between them is the point:
#   cli  — one `--for` per process. Every scope reads calls=1, which makes attribution unambiguous,
#          and the on-disk warm snapshot + ingest cache are reused, so this is the WARM arm.
#   mcp  — one process, N `for` requests. This is the only arm that can separate a cost paid ONCE
#          per process from one paid per ANSWER: a per-answer cost reads calls=N.
#
# The mcp arm writes every request up front, closes stdin, sends stdout to /dev/null and reads the
# numbers from the server's own stderr at exit. Nothing waits for a reply: two earlier lanes
# deadlocked a reply-waiting harness against this server, and the profile report is printed at
# static destruction anyway, so a reply is not the thing being measured.
#
# SHARES, NOT PUBLISHABLE WALL CLOCK. This is a dev build with PROFILE_ENABLED=1; every scope entry
# pays two counter reads. The shares are the deliverable; the totals carry an instrumentation tax
# and the shipped PGO build inlines differently, so both can move there.
#
# Usage: bash bench/forattrib_profile.sh PROF_BIN CORPUS OUTDIR [cli|mcp] [REPS] [TASK]

set -u

PROF_BIN="${1:?usage: forattrib_profile.sh PROF_BIN CORPUS OUTDIR [cli|mcp] [REPS] [TASK]}"
CORPUS="${2:?corpus directory}"
OUT="${3:?output directory}"
ARM="${4:-cli}"
REPS="${5:-5}"
TASK="${6:-resolve a symbol reference into the call graph}"

[ -x "$PROF_BIN" ] || { echo "no profile binary at $PROF_BIN" >&2; exit 2; }
[ -d "$CORPUS" ]   || { echo "no corpus at $CORPUS" >&2; exit 2; }
mkdir -p "$OUT" || exit 2

echo "arm=$ARM bin=$PROF_BIN corpus=$CORPUS reps=$REPS"
"$PROF_BIN" --version | head -1

case "$ARM" in
cli)
    # One unmeasured warm-up first: it is the run that may build the snapshot, and a run that writes
    # the snapshot is not the warm arm. Its report is kept, labelled, so the cold/warm difference is
    # readable rather than discarded.
    "$PROF_BIN" "$CORPUS" --for="$TASK" > /dev/null 2> "$OUT/cli_warmup.err"
    for i in $( seq 1 "$REPS" ); do
        "$PROF_BIN" "$CORPUS" --for="$TASK" > /dev/null 2> "$OUT/cli_rep$i.err"
    done
    ;;
mcp)
    # Every request up front, then EOF. ids start at 1; the first `for` is the index build and is
    # reported separately by its own calls= arithmetic, not discarded.
    {
        printf '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n'
        for i in $( seq 1 "$REPS" ); do
            printf '{"jsonrpc":"2.0","id":%d,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' \
                   $(( i + 1 )) "$CORPUS" "$TASK"
        done
    } | RIPWIRE_MCP_TIMINGS=1 "$PROF_BIN" --mcp > /dev/null 2> "$OUT/mcp.err"
    echo "mcp arm: server exited rc=$? (stdin closed after $REPS for-requests)"
    ;;
*)
    echo "unknown arm '$ARM' (cli|mcp)" >&2; exit 2 ;;
esac

# ── the table ────────────────────────────────────────────────────────────────────────────────────────
# One row per scope: calls summed and total_ms summed across every #PROF_TSV block in the arm's files,
# then a per-REP mean. Reading the server's/binary's own output is the only way to know how a run
# ended, so the row count and the block count are printed, not assumed.
for f in "$OUT"/${ARM}_rep*.err "$OUT"/mcp.err; do
    [ -f "$f" ] || continue
    printf '%s: #PROF_TSV blocks=%s\n' "$( basename "$f" )" "$( grep -c '^#PROF_TSV_BEGIN' "$f" )"
done

echo
echo "scope<TAB>calls<TAB>total_ms<TAB>per_rep_ms   (arm=$ARM, reps=$REPS; shares, not publishable wall clock)"
cat "$OUT"/${ARM}_rep*.err "$OUT"/mcp.err 2>/dev/null | awk -F'\t' -v reps="$REPS" '
    /^#PROF_TSV_BEGIN/ { f = 1; next }
    /^#PROF_TSV_END/   { f = 0; next }
    f && $1 == "scope" { next }
    f && NF >= 5 { calls[$1] += $4; ms[$1] += $5 }
    END {
        for ( s in ms ) { printf "%s\t%d\t%.1f\t%.1f\n", s, calls[s], ms[s], ms[s] / reps }
    }' | sort -t"$( printf '\t' )" -k4 -rn
