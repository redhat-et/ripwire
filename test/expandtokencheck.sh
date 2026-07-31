#!/usr/bin/env bash
# expandtokencheck.sh — PHASE 1 gate (RESEARCH_outputEconomy §6): the --expand est_tokens CORRECTNESS fix.
#
# THE BUG: --expand appended a <bodies> block AFTER the ranked map, but the header's est_tokens reported
# ONLY the map (serialize() counted its own emission, the packBodies payload was never added). MEASURED:
# --expand=buildGraph reported ~10K while the real payload was ~19-24K — any --token-budget gate on an
# expand under-budgeted by ~2×. THE FIX: serialize() now takes extraBodyTokens (estimateExpandBodyTokens
# over the SAME resolved node/range set packBodies emits), so the header reports header+body.
#
# We do NOT vendor a BPE table (Claude's tokenizer isn't public), so this gate validates PROPERTIES: the
# reported est_tokens is within ~15% of a build-dep-free byte/calibration estimate of the FULL output, and
# an --expand of a large fn reports MORE than the map-alone number. tiktoken (if present) is informational.
#
# Usage:  CTXPACK_BIN=build/ctxpack bash test/expandtokencheck.sh   |   CTXPACK_BIN=asan/ctxpack bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
cd "$ROOT"
echo "expandtokencheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

est(){ "$BIN" "$@" --no-cache 2>/dev/null | grep -oE 'est_tokens=[0-9]+' | head -1 | grep -oE '[0-9]+'; }

# ── #1: map-alone est_tokens (baseline) is present and positive ───────────────────────────────────────
MAP_EST="$( est src )"
{ [ -n "$MAP_EST" ] && [ "$MAP_EST" -gt 0 ] 2>/dev/null; } \
    && ok "map-alone est_tokens present, positive ($MAP_EST)" \
    || no "map-alone est_tokens missing / non-positive (got '$MAP_EST')"

# ── #2: --expand=buildGraph (a large fn) reports MORE than the map alone — the body is now counted ─────
EXP_EST="$( est src --expand=buildGraph )"
{ [ -n "$EXP_EST" ] && [ "$EXP_EST" -gt "$MAP_EST" ] 2>/dev/null; } \
    && ok "--expand=buildGraph est_tokens ($EXP_EST) > map-alone ($MAP_EST) — the body is counted (bug fixed)" \
    || no "--expand=buildGraph est_tokens ($EXP_EST) not > map-alone ($MAP_EST) — body still uncounted (BUG)"

# ── #3: the reported est_tokens is within ~15% of a REAL estimate of the FULL output (header+map+bodies).
#    Ground truth: prefer real o200k tiktoken when installed (the honest number); else a build-dep-free
#    blended byte proxy — an --expand payload is body-HEAVY, and code bodies tokenize LEANER (~3.8 B/tok:
#    whitespace/braces merge) than the map's signature markup (~2.5), so the whole-output blends to ~2.85
#    B/tok (MEASURED: 59.5KB → 19.3K real tokens = 3.08; 2.85 is a conservative floor). |est - truth| must
#    be <= 15% of truth. Integer math on the byte path. ─────────────────────────────────────────────────
FULL_BYTES="$( "$BIN" src --expand=buildGraph --no-cache 2>/dev/null | wc -c | tr -d ' ' )"
if python3 -c 'import tiktoken' >/dev/null 2>&1; then
    "$BIN" src --expand=buildGraph --no-cache 2>/dev/null >"$TMP/exp3.xml"
    TRUTH="$( python3 -c 'import sys,tiktoken; print(len(tiktoken.get_encoding("o200k_base").encode(open(sys.argv[1],encoding="utf-8",errors="replace").read())))' "$TMP/exp3.xml" )"
    LABEL="real o200k"
else
    TRUTH=$(( FULL_BYTES * 100 / 285 ))   # bytes / 2.85 blended proxy
    LABEL="byte/2.85 proxy"
fi
DIFF=$(( EXP_EST - TRUTH )); [ "$DIFF" -lt 0 ] && DIFF=$(( -DIFF ))
LIM=$(( TRUTH * 15 / 100 ))
{ [ "$DIFF" -le "$LIM" ]; } \
    && ok "--expand est_tokens ($EXP_EST) within 15% of $LABEL ($TRUTH, |diff|=$DIFF <= $LIM)" \
    || no "--expand est_tokens ($EXP_EST) NOT within 15% of $LABEL ($TRUTH, |diff|=$DIFF > $LIM)"

# ── #4: the OLD map-alone number is materially SHORT of the full payload — proves the fix corrects a real
#    ~2× under-read (guards against a revert that silently drops the body term). ─────────────────────────
{ [ "$MAP_EST" -lt $(( TRUTH * 70 / 100 )) ] 2>/dev/null; } \
    && ok "map-alone ($MAP_EST) is <70% of the full-output truth ($TRUTH) — the pre-fix header under-read the real payload" \
    || no "map-alone ($MAP_EST) not materially short of full truth ($TRUTH) — the bug may not be exercised by this corpus"

# ── #5: determinism — the reported est_tokens is byte-identical run-to-run ─────────────────────────────
D1="$( est src --expand=buildGraph )"; D2="$( est src --expand=buildGraph )"
{ [ -n "$D1" ] && [ "$D1" = "$D2" ]; } \
    && ok "--expand est_tokens deterministic across re-runs ($D1)" \
    || no "--expand est_tokens NON-deterministic ($D1 vs $D2)"

# ── #6: full --expand output is well-formed XML ────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    "$BIN" src --expand=buildGraph --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed under --expand" || no "xml malformed under --expand"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── #7: the --token-budget gate on an --expand now uses the FULL-payload number (never a second counter).
#    A budget just under the expand est but ABOVE the map-alone est must FAIL (exit 3) — the whole point of
#    the fix: pre-fix this budget passed while the real payload blew past it. ─────────────────────────────
MID=$(( (MAP_EST + EXP_EST) / 2 ))
"$BIN" src --expand=buildGraph --token-budget=$MID --no-cache >/dev/null 2>"$TMP/tb.err"
rc=$?
{ [ "$rc" -eq 3 ] && grep -qE "est_tokens=$EXP_EST > budget=$MID\$" "$TMP/tb.err"; } \
    && ok "--token-budget=$MID (between map-alone and full) on --expand: exit 3, gate uses the full est ($EXP_EST)" \
    || no "--token-budget on --expand did not gate on the full est (exit=$rc, err='$(cat "$TMP/tb.err" 2>/dev/null)')"

# ── #8: a bare map (no --expand) est_tokens is UNCHANGED — the fix is inert without a body (golden-neutral).
BARE1="$( est src )"; BARE2="$( est src )"
{ [ "$BARE1" = "$BARE2" ] && [ "$BARE1" = "$MAP_EST" ]; } \
    && ok "no --expand: est_tokens unchanged ($BARE1) — fix is inert without a body block" \
    || no "no --expand: est_tokens drifted (got $BARE1, expected $MAP_EST)"

# ── #9: (optional) tiktoken accuracy report — informational, never gates (tiktoken isn't a build dep) ───
if python3 -c 'import tiktoken' >/dev/null 2>&1; then
    "$BIN" src --expand=buildGraph --no-cache 2>/dev/null >"$TMP/exp.xml"
    python3 - "$TMP/exp.xml" "$EXP_EST" <<'PY'
import sys, re, tiktoken
out=open(sys.argv[1],encoding='utf-8',errors='replace').read()
est=int(sys.argv[2]); enc=tiktoken.get_encoding("o200k_base")
real=len(enc.encode(out))
print(f"  INFO  --expand est_tokens={est} vs real o200k={real}  (err {abs(est-real)/real*100:.1f}%; target <=15%)")
PY
else
    printf '  SKIP  tiktoken accuracy report (tiktoken not installed)\n'
fi


# ── D7: --expand of a symbol miss must exit NON-ZERO with a "matched no symbol" stderr message, the same
#    failure contract --callers/--callees/--impact already use on a miss (they `return 1;` right after their
#    own withDidYouMean stderr line) — a resolvable-but-wrong name must never read as success. Pre-fix this
#    exited 0 with only a stderr warning while still emitting the 30 KB fallback map. The fallback map itself
#    is not SPEC-mandated so it stays (this handler is the default-map path), but the exit code no longer lies.
MISS_MSG="$( "$BIN" src --expand=totally_bogus_symbol_zzz --no-cache 2>&1 1>/dev/null )"
MISS_RC=$( "$BIN" src --expand=totally_bogus_symbol_zzz --no-cache >/dev/null 2>&1; echo $? )
{ [ "$MISS_RC" != 0 ] && printf '%s' "$MISS_MSG" | grep -qi "matched no symbol"; } \
    && ok "--expand of a nonexistent symbol exits non-zero ($MISS_RC) with a 'matched no symbol' message" \
    || no "--expand of nonexistent symbol: expected non-zero exit + 'matched no symbol' message, got exit=$MISS_RC msg='$MISS_MSG'"

# r27-emitters (PLAN_orchestrator_2026-07-27 §P2.8) REVERSED the stdout half of this contract. D7 left the
# ~22 KB fallback map on stdout and changed only the exit code, which made --expand the ONE verb that paired
# a refusal with a payload: exit 1 plus a full map of UNRELATED symbols reads to a caller as "here is your
# answer" with a stray non-zero code. The refusal now writes NOTHING, exactly like --callers/--callees/
# --impact/--lego/--around/--edit-check. The exit code and the stderr message are unchanged.
MISS_OUT="$( "$BIN" src --expand=totally_bogus_symbol_zzz --no-cache 2>/dev/null )"
[ -z "$MISS_OUT" ] \
    && ok "--expand miss writes ZERO bytes to stdout (refusal ships no payload)" \
    || no "--expand miss still emitted $( printf '%s' "$MISS_OUT" | wc -c | tr -d ' ' ) bytes of unrelated map"

# a REAL symbol under --expand still exits 0 (the fix must not regress the success path)
HIT_RC=$( "$BIN" src --expand=buildGraph --no-cache >/dev/null 2>&1; echo $? )
[ "$HIT_RC" = 0 ] && ok "--expand of a real symbol (buildGraph) still exits 0" || no "--expand=buildGraph regressed to exit $HIT_RC"

# a MIXED list (one hit, one miss) still exits non-zero — any miss in the comma list fails the call
MIX_RC=$( "$BIN" src --expand=buildGraph,totally_bogus_symbol_zzz --no-cache >/dev/null 2>&1; echo $? )
[ "$MIX_RC" != 0 ] && ok "--expand=hit,miss (mixed list) exits non-zero ($MIX_RC) — any miss fails the call" \
    || no "--expand=hit,miss (mixed list) should exit non-zero, got $MIX_RC"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
