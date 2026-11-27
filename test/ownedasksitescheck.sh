#!/usr/bin/env bash
# ownedasksitescheck.sh — `[mem] owned_sites`: which call site generates ownedBy's out-of-line asks.
#
# WHY IT EXISTS. The out-of-line ask count is the super-linear term in the resolve loop: measured
# 2026-11-27, ownedBy's asks grow x779.5 from envoy to llvm-project (41,943 -> 32,694,013) while
# files grow x7.30 and the plausibleMemo FILLS behind them grow only x4.19 (4,505 -> 18,869). The
# cost is asking, not computing, so the next change has to know WHICH site asks. These counters are
# that attribution, and this gate holds them honest.
#
# WHAT IT HOLDS. Counts only, never a time (a PROFILE_SCOPE around a ~100 ns probe called 47.5M
# times dominates its own measurement). They are RIPWIRE_STATS-only and must never reach stdout.
# The attribution must be TOTAL: every out-of-line ask lands in exactly one bucket, so the buckets
# sum to owned_asks. Arm 2 checks that sum, and arm 2 is worthless when both sides are zero, so a
# non-zero precondition is CHECKED, not assumed. Arm 3 is the anti-vacuity arm: a build that
# attributed everything to `other` would satisfy arm 2 perfectly.
#
# A WARM RUN SKIPS buildGraph ENTIRELY and emits none of these lines, so every run here passes
# --no-cache. Without it the gate is red for the wrong reason (measured while writing it: the repo
# warm emits no [mem] guarded_walk line at all).
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "BIN=$BIN $( "$BIN" --version 2>&1 | head -1 )"
[ -x "$BIN" ] || { echo "ownedasksitescheck: no binary at $BIN"; exit 2; }

WORK="$( mktemp -d )"
trap 'rm -rf "$WORK"' EXIT

# The corpora: a small fixture tree and the repo itself, both cold. Both were measured to drive
# ownedBy's out-of-line branch (6 and 34 asks); llvm-sized corpora are not a gate's business.
CORPORA="$ROOT/test/receiverevidencefix $ROOT"

statsOf(){   # statsOf <corpus> <outfile>; stdout to its own file so arm 4 can compare it
    RIPWIRE_STATS=1 "$BIN" "$1" --no-cache > "$2.out" 2> "$2.err"
}

for corpus in $CORPORA; do
    tag="$( basename "$corpus" )"
    statsOf "$corpus" "$WORK/$tag"
    line="$( grep -m1 'owned_sites' "$WORK/$tag.err" || true )"

    # ── arm 1: the line is emitted, with VALUE-shaped fields ─────────────────────────────────────
    # Match the value (k="?<digits>), never the bare key: a legend, a comment or a disclosure
    # sentence can carry the key and would pass on a build that emits no number at all.
    if [ -z "$line" ]; then
        no "(1/$tag) no [mem] owned_sites line on a cold run"
        continue
    fi
    missing=""
    for k in cone level append other; do
        printf '%s\n' "$line" | grep -qE "$k=\"?[0-9]+" || missing="$missing $k"
    done
    if [ -n "$missing" ]; then
        no "(1/$tag) owned_sites is missing a numeric value for:$missing — line was: $line"
        continue
    fi
    ok "(1/$tag) [mem] owned_sites carries a number for every bucket"

    # ── arm 2: the attribution is TOTAL (buckets sum to owned_asks) ───────────────────────────────
    asks="$( grep -m1 'plausible owned_asks=' "$WORK/$tag.err" | grep -oE 'owned_asks=[0-9]+' | cut -d= -f2 )"
    get(){ printf '%s\n' "$line" | grep -oE "$1=[0-9]+" | cut -d= -f2; }
    sum=$(( $( get cone ) + $( get level ) + $( get append ) + $( get other ) ))
    if [ -z "${asks:-}" ]; then
        no "(2/$tag) no [mem] plausible owned_asks= to check the sum against"
    elif [ "$asks" -eq 0 ]; then
        # The precondition, checked rather than assumed: 0 == 0 is not evidence of attribution.
        no "(2/$tag) owned_asks=0 — this corpus does not drive the out-of-line branch, so the sum proves nothing"
    elif [ "$sum" -ne "$asks" ]; then
        no "(2/$tag) buckets sum to $sum but owned_asks=$asks — an ask is unattributed or double-counted"
    else
        ok "(2/$tag) every one of $asks out-of-line asks is attributed exactly once"
    fi

    # ── arm 4: a counter must never reach stdout ──────────────────────────────────────────────────
    # The precondition is CHECKED, not assumed: `cmp -s` calls two EMPTY files equal, so a run that
    # printed no map at all would pass this arm trivially. (Caught by --quality-delta's
    # vacuous-assert shape on the first draft of this gate, which is the shape the gate is about.)
    "$BIN" "$corpus" --no-cache > "$WORK/$tag.plain" 2>/dev/null
    if [ ! -s "$WORK/$tag.out" ] || [ ! -s "$WORK/$tag.plain" ]; then
        no "(4/$tag) one of the two runs printed nothing — comparing empty files proves nothing"
    elif cmp -s "$WORK/$tag.out" "$WORK/$tag.plain"; then
        ok "(4/$tag) RIPWIRE_STATS moves no byte of stdout ($( wc -c < "$WORK/$tag.out" ) bytes compared)"
    else
        no "(4/$tag) stdout differs with RIPWIRE_STATS set — a counter reached output"
    fi
done

# ── arm 3: anti-vacuity — the attribution must not be entirely `other` ───────────────────────────
# Arm 2 is satisfied perfectly by a build that files every ask under `other`, which would tell us
# nothing about WHICH site asks, the one question these counters exist to answer. At least one
# named site must fire somewhere. The repo cold is the corpus with the larger ask count (34).
selfLine="$( grep -m1 'owned_sites' "$WORK/$( basename "$ROOT" ).err" 2>/dev/null || true )"
if [ -z "$selfLine" ]; then
    no "(3) no owned_sites line on the repo cold — arm 3 cannot be armed, so its silence proves nothing"
else
    named=0
    for k in cone level append; do
        v="$( printf '%s\n' "$selfLine" | grep -oE "$k=[0-9]+" | cut -d= -f2 )"
        named=$(( named + ${v:-0} ))
    done
    if [ "$named" -gt 0 ]; then
        ok "(3) a NAMED ask site fires ($named asks outside \`other\`) — the attribution distinguishes sites"
    else
        no "(3) every ask landed in \`other\` — arm 2 passes but the counters answer nothing; either the tags are unwired or the hot sites are elsewhere"
    fi
fi

[ "$fail" -eq 0 ] && echo "ownedasksitescheck: ALL PASS" || echo "ownedasksitescheck: FAILURES"
exit "$fail"
