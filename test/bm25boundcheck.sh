#!/usr/bin/env bash
# bm25boundcheck.sh — A4 gate: the MaxScore early-termination BOUND in lexicalScoresTiered (src/lexical.h,
# the pruned branch around line ~785) must be a GENUINE upper bound for whatever (k1,b) BM25 is CONFIGURED
# with, not just the shipped defaults (k1=1.5, b=0.75). This is a real correctness gate, not a benchmark:
# if the bound understates the true achievable score for some configured (k1,b), MaxScore pruning silently
# discards candidates that belong in the top-K — no crash, no error, just a quietly worse ranking. See the
# derivation comment beside bm25ImpactBound() in src/lexical.h for the monotonicity proof this gate exists
# to keep honest.
#
# BACKGROUND (A4 lane): k1/b used to be declared TWICE (lexicalScoresTiered and
# lexicalScoresNameExactTiered each had their own `constexpr double k1 = 1.5, b = 0.75;`), and the bound
# derived its cap from its own local copy — two things that had to be kept in sync by hand forever. A4
# unifies them into one Bm25Params/resolveBm25Params()/bm25ImpactBound() definition (RIPWIRE_BM25_K1 /
# RIPWIRE_BM25_B env overrides, calibration sweeps only — the RIPWIRE_PATHTOK_W / RIPWIRE_BASENAME_W
# precedent) so the score formula and the bound can no longer drift apart.
#
# RED, demonstrated (2026-09, before this fix landed): (1) with no env-var support, setting
# RIPWIRE_BM25_K1/RIPWIRE_BM25_B changed nothing — check (1) below is exactly that arm and fails on the
# pre-fix binary. (2) with the env override wired in but bm25ImpactBound() hacked to keep reading the
# UNCONFIGURED default (k1,b) instead of the resolved value — simulating the exact "changed k1/b without
# updating the bound" defect this gate exists to catch — pruned --for output measurably DIFFERED from
# RIPWIRE_NO_PRUNE=1 (exhaustive) at several configured (k1,b) corners (e.g. k1=6.0,b=0.05), i.e. real
# candidates were being wrongly discarded. Reverting that hack restored byte-identical parity at every
# corner tried. Check (5) below is that same parity check, run permanently.
#
# Usage:  bash test/bm25boundcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/bm25boundcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/bm25fix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/bm25fix dir — fixture missing"; exit 2; }
cd "$ROOT"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

echo "bm25boundcheck: BIN=$BIN  CORPUS=test/bm25fix + src (for the pruning-bound sweep)"

q(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" --no-cache --query="$1" 2>/dev/null; }

# ── (1) THE CALIBRATION KNOB IS REAL — RIPWIRE_BM25_K1 / RIPWIRE_BM25_B measurably change scoring ──────
# (before A4, these env vars did not exist and this arm failed: the "configured" output was byte-identical
# to the baseline no matter what was set, because nothing read them).
BASE_Q="$( q "frobnicate widget" )"
CFG_Q="$( RIPWIRE_BM25_K1=8 RIPWIRE_BM25_B=0.1 q "frobnicate widget" )"
[ "$BASE_Q" != "$CFG_Q" ] \
    && ok "(1) RIPWIRE_BM25_K1/RIPWIRE_BM25_B measurably change BM25 output (the knob is real)" \
    || no "(1) RIPWIRE_BM25_K1=8 RIPWIRE_BM25_B=0.1 produced byte-identical output to the default — env override is not wired in"

# ── (2) CLAMPED, NOT UNSAFE — an out-of-range env value collapses to the documented clamp boundary ─────
# (k1 in [0.1,10.0], b in [0,1]; see resolveBm25Params()). A value BEYOND the boundary must score
# IDENTICALLY to the boundary value itself, proving the clamp is applied rather than passed through raw
# (raw k1<=0 or b outside [0,1] would send BM25 into a degenerate/undefined regime).
K1_LOW_RAW="$(  RIPWIRE_BM25_K1=-5   q "frobnicate widget" )"
K1_LOW_CLAMP="$( RIPWIRE_BM25_K1=0.1 q "frobnicate widget" )"
K1_HIGH_RAW="$(  RIPWIRE_BM25_K1=999 q "frobnicate widget" )"
K1_HIGH_CLAMP="$( RIPWIRE_BM25_K1=10.0 q "frobnicate widget" )"
B_LOW_RAW="$(  RIPWIRE_BM25_B=-1  q "frobnicate widget" )"
B_LOW_CLAMP="$( RIPWIRE_BM25_B=0  q "frobnicate widget" )"
B_HIGH_RAW="$(  RIPWIRE_BM25_B=5  q "frobnicate widget" )"
B_HIGH_CLAMP="$( RIPWIRE_BM25_B=1 q "frobnicate widget" )"
{ [ "$K1_LOW_RAW" = "$K1_LOW_CLAMP" ] && [ "$K1_HIGH_RAW" = "$K1_HIGH_CLAMP" ] \
    && [ "$B_LOW_RAW" = "$B_LOW_CLAMP" ] && [ "$B_HIGH_RAW" = "$B_HIGH_CLAMP" ]; } \
    && ok "(2) out-of-range RIPWIRE_BM25_K1/RIPWIRE_BM25_B clamp to [0.1,10.0]/[0,1] rather than passing through raw" \
    || no "(2) an out-of-range env value did not collapse to its documented clamp boundary"

# ── (3) MALFORMED ENV DOES NOT CRASH ────────────────────────────────────────────────────────────────────
RIPWIRE_BM25_K1=notanumber RIPWIRE_BM25_B=alsonotanumber "$BIN" "$FIX" --no-cache --query="frobnicate widget" >"$TMP/malformed.out" 2>"$TMP/malformed.err"
MALFORMED_EC=$?
[ "$MALFORMED_EC" = 0 ] && [ -s "$TMP/malformed.out" ] \
    && ok "(3) a malformed RIPWIRE_BM25_K1/RIPWIRE_BM25_B does not crash (exit 0, output produced)" \
    || no "(3) malformed BM25 env crashed or produced no output (exit=$MALFORMED_EC)"

# ── prime a warm rich cache over src/ once — every remaining check re-scores against it (env vars affect
#    QUERY-TIME scoring only, never the persisted ingest/postings, so this is safe and ~10x faster) ──────
SRC_Q="symbol score"                    # broad enough to match thousands of src/ symbols (checked below)
"$BIN" src --cache="$TMP/src.rich" --for="$SRC_Q" >/dev/null 2>&1

candidates(){ # $1=top-k  $2..=extra env already exported by the caller
    "$BIN" src --cache="$TMP/src.rich" --no-route --for="$SRC_Q" --format=candidates --top-k="$1" 2>/dev/null
}

# ── (4) PRUNING PREMISE — the sweep below is only meaningful if pruning is ACTUALLY discarding
#    candidates at top-k=40 (capped="1" and total > 40); otherwise every parity check would pass
#    vacuously with nothing pruned to get wrong. ──────────────────────────────────────────────────────
PREMISE="$( candidates 40 )"
TOTAL="$( printf '%s' "$PREMISE" | grep -oE 'total="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
{ printf '%s' "$PREMISE" | grep -q 'capped="1"' && [ -n "$TOTAL" ] && [ "$TOTAL" -gt 40 ] 2>/dev/null; } \
    && ok "(4) pruning premise: '$SRC_Q' top-k=40 is capped (total=$TOTAL matches > 40) — pruning is live, not a no-op" \
    || no "(4) pruning premise failed (capped/total=$TOTAL) — the parity sweep below would be vacuous"

# ── (5) THE CORE ASSERTION — pruned top-k=40 == RIPWIRE_NO_PRUNE=1 (exhaustive), byte-identical, for a
#    GRID of configured (k1,b) covering the clamp range's corners, its center, and the shipped default.
#    Any divergence here means the bound understated a real achievable score for that (k1,b) and MaxScore
#    pruning threw away a candidate that belonged in the top-K. ─────────────────────────────────────────
sweep_ok=1
for kb in "1.5 0.75" "0.1 0.0" "0.1 1.0" "10.0 0.0" "10.0 1.0" "6.0 0.05" "0.15 0.95" "9.5 0.05" "9.5 0.95"; do
    K1="${kb%% *}"; B="${kb##* }"
    PRUNED="$(    RIPWIRE_BM25_K1="$K1" RIPWIRE_BM25_B="$B"                   candidates 40 )"
    EXHAUSTIVE="$( RIPWIRE_BM25_K1="$K1" RIPWIRE_BM25_B="$B" RIPWIRE_NO_PRUNE=1 candidates 40 )"
    if [ "$PRUNED" = "$EXHAUSTIVE" ]; then
        ok "(5) k1=$K1 b=$B: pruned top-40 byte-identical to exhaustive (bound held)"
    else
        no "(5) k1=$K1 b=$B: pruned top-40 DIFFERS from exhaustive — the bound is not safe at this (k1,b)"
        sweep_ok=0
    fi
done
[ "$sweep_ok" = 1 ] && ok "(5) SUMMARY: the early-termination bound held across every (k1,b) in the sweep" \
                    || no "(5) SUMMARY: the bound was violated for at least one configured (k1,b) above"

# ── (6) DETERMINISM at a configured (non-default) (k1,b) ──────────────────────────────────────────────
D1="$( RIPWIRE_BM25_K1=4.2 RIPWIRE_BM25_B=0.33 candidates 40 )"
D2="$( RIPWIRE_BM25_K1=4.2 RIPWIRE_BM25_B=0.33 candidates 40 )"
[ "$D1" = "$D2" ] \
    && ok "(6) determinism: a configured (k1,b) run is byte-identical twice" \
    || no "(6) a configured (k1,b) run was NOT byte-identical run-to-run"

# ── (7) xml well-formed under a configured (k1,b) ───────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$D1" | xmllint --noout - 2>/dev/null && ok "(7) xml well-formed under a configured (k1,b)" || no "(7) xml malformed under a configured (k1,b)"
else
    printf '  SKIP  (7) xml well-formed (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
