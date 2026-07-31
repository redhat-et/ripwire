#!/usr/bin/env bash
# tokenbudgetcheck.sh — T1 gate: the calibrated est_tokens estimate + the --max-tokens headroom fit,
# PLUS (AUDIT3 §D#7 / §E item 16) the --token-budget=N repomix-style CI exit-code gate.
#
# WHAT T1 CHANGED (RESEARCH_agentQuality2026 §2f): est_tokens used a single chars/4 divisor over a
# name-length PROXY — MEASURED ~50-80% under the real token count (the map is majority terse markup, not
# raw code, and tokenizes at ~2.4-2.6 B/tok, NOT 4). T1 replaces it with a per-language constexpr
# calibration table (src/serialize.h kTokenCalib) over an accurate envelope+content byte model. We do NOT
# vendor a BPE table — Claude's tokenizer isn't public — so this gate validates the ESTIMATE'S PROPERTIES
# (determinism, a real ceiling under --max-tokens with headroom), not bit-exactness. The MAPE-vs-tiktoken
# number is REPORTED by the agent in the T1 write-up (tiktoken isn't a build dependency).
#
# WHAT --token-budget ADDS: a CI CONTRACT, not a shaping tool. --max-tokens binary-searches top-K to FIT
# a target; --token-budget ASSERTS the emitted map's est_tokens against a ceiling and exits 3 if it's over
# (distinct from --arch/--quality-delta's exit 2, so a CI script can tell "map too big" apart from "new
# debt"). It reads the SAME calibrated est_tokens the header already prints — never a second counter — so
# checks #7-#13 below also double as a regression guard against that value drifting from the header's.
#
# §P6.8 FIX (this round): before this fix, an over-budget run still streamed the WHOLE map to stdout before
# exiting 3 — a CI log received the exact artifact the gate just rejected. #7 now asserts full BYTE-IDENTITY
# with the unflagged map (not just non-empty), and new checks #8b/#8c assert the over-budget run's stdout is
# small (< 2KB) and carries NO withheld map content — mirroring the fix --recall already had for the same
# class (measure into a buffer, decide, THEN write — never write-then-decide). See src/main.cpp's
# runDefaultMap (the out/memBuf/memSz block right before the token-budget check) and its §P6.8 comment.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/tokenbudgetcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
# W3FIX: $1 was ignored here — the file bound BIN from RIPWIRE_BIN alone, so `test/tokenbudgetcheck.sh
# asan/ripwire` (the form every sibling gate accepts, and the form the suite's asan pass uses) silently tested
# build/ripwire instead. Same seam the wave-1 orchestrator fixed in B1's four gates, one file over.
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

TMP_TB_DIR="$( mktemp -d )"
trap 'rm -rf "$TMP_TB_DIR"' EXIT
TMP_TB_A="$TMP_TB_DIR/generous.xml"
TMP_TB_A_ERR="$TMP_TB_DIR/generous.err"
TMP_TB_B="$TMP_TB_DIR/tiny.xml"
TMP_TB_B_ERR="$TMP_TB_DIR/tiny.err"
TMP_TB_B2_ERR="$TMP_TB_DIR/tiny2.err"
TMP_TB_COMPOSE_ERR="$TMP_TB_DIR/compose.err"

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
cd "$ROOT"

echo "tokenbudgetcheck: BIN=$BIN"

est(){ "$BIN" "$1" --no-cache 2>/dev/null | grep -oE 'est_tokens=[0-9]+' | grep -oE '[0-9]+'; }
outbytes(){ "$BIN" "$@" --no-cache 2>/dev/null | wc -c | tr -d ' '; }

# ── #1: est_tokens is present, positive, and DETERMINISTIC (byte-identical run-to-run) ────────────────
E1="$( est src )"; E2="$( est src )"
{ [ -n "$E1" ] && [ "$E1" -gt 0 ] 2>/dev/null && [ "$E1" = "$E2" ]; } \
    && ok "est_tokens present, positive ($E1), deterministic" \
    || no "est_tokens missing / non-positive / non-deterministic (got '$E1' then '$E2')"

# ── #2: the calibrated estimate is materially LARGER than the old chars/4 proxy would give. The old
#    proxy on src measured est_tokens=4434 (name-length proxy /4); the calibrated one must be ≥ 1.3× that
#    (it corrects a ~50-80% under-read). This locks in that the fix actually landed (guards a revert). ──
ESRC="$( est src )"
{ [ -n "$ESRC" ] && [ "$ESRC" -ge 5764 ] 2>/dev/null; } \
    && ok "calibrated est_tokens on src ($ESRC) >= 1.3x the old chars/4 proxy (4434) — the T1 correction landed" \
    || no "est_tokens on src ($ESRC) too close to the old under-reading proxy (4434) — T1 may be reverted"

# ── #3: --max-tokens is a real CEILING with headroom. For budgets above the map's fixed envelope floor,
#    the ACTUAL output byte count must stay under budget*minBytesPerToken (2.36) — i.e. the packed map
#    tokenizes to <= the requested budget for ANY language mix. We check bytes (a build-dep-free proxy for
#    tokens via the densest 2.36 B/tok rate) so tiktoken isn't required here. ──────────────────────────
budget_ok=1
for N in 500 1000 2000 5000; do
    B="$( outbytes src --max-tokens=$N )"
    # worst-case tokens <= B / 2.36 ; require that to be <= N (integer math: B*100 <= N*236)
    if [ $(( B * 100 )) -gt $(( N * 236 )) ]; then
        echo "    over budget at N=$N: $B bytes → up to $(( B * 100 / 236 )) tokens > $N"; budget_ok=0
    fi
done
[ "$budget_ok" = 1 ] && ok "--max-tokens=N: packed map stays under N tokens (worst-case 2.36 B/tok) for N in {500,1000,2000,5000}" \
    || no "--max-tokens exceeded its budget for some N (headroom/ceiling broken)"

# ── #4: a bigger budget never packs FEWER symbols (monotone fit) — the binary search must be monotone ──
S500="$( "$BIN" src --max-tokens=500  --no-cache 2>/dev/null | grep -oE 'shown=[0-9]+' | grep -oE '[0-9]+' )"
S5000="$( "$BIN" src --max-tokens=5000 --no-cache 2>/dev/null | grep -oE 'shown=[0-9]+' | grep -oE '[0-9]+' )"
{ [ -n "$S500" ] && [ -n "$S5000" ] && [ "$S5000" -ge "$S500" ] 2>/dev/null; } \
    && ok "monotone fit: shown at 5000 ($S5000) >= shown at 500 ($S500)" \
    || no "non-monotone --max-tokens fit (shown 500=$S500 5000=$S5000)"

# ── #5: --max-tokens output is well-formed XML ────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    "$BIN" src --max-tokens=1500 --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed under --max-tokens" || no "xml malformed under --max-tokens"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── #6: (optional) tiktoken MAPE report — informational, never gates (tiktoken isn't a build dep) ──────
if python3 -c 'import tiktoken' >/dev/null 2>&1; then
    python3 - "$BIN" <<'PY'
import sys, subprocess, os, re, statistics, tiktoken
b=sys.argv[1]; enc=tiktoken.get_encoding("o200k_base")
corpora=["test/metricsfix","test/resolvefix","test/rankbyfix","test/skillfix","test/regexfix","test/fixture","test/swiftfix","test/usesfix"]
errs=[]
for p in corpora:
    if not os.path.isdir(p): continue
    out=subprocess.run([b,p,"--no-cache"],capture_output=True).stdout.decode('utf-8','replace')
    real=len(enc.encode(out)); m=re.search(r'est_tokens=(\d+)',out)
    if not m: continue
    est=int(m.group(1)); errs.append(abs(est-real)/real)
if errs:
    print(f"  INFO  calibrated est_tokens MAPE vs tiktoken o200k = {statistics.mean(errs)*100:.1f}%  (N={len(errs)}; target <=10%)")
PY
else
    printf '  SKIP  tiktoken MAPE report (tiktoken not installed)\n'
fi

# ── AUDIT3 §D#7: --token-budget=N — the repomix-style CI EXIT-CODE gate (distinct from --max-tokens,
# which SHAPES a map to fit; this one ASSERTS the result and fails). Gates on the SAME est_tokens the
# header already reports — never a second counter (checked explicitly in #9 below). ──────────────────

# ── #7: a generous budget → exit 0, map on stdout BYTE-IDENTICAL to the unflagged run (§P6.8: the flag
#    must never SHAPE the map when the budget is not exceeded — it only asserts, or withholds) ───────────
"$BIN" src --token-budget=999999 --no-cache >"$TMP_TB_A" 2>"$TMP_TB_A_ERR"
rc_generous=$?
"$BIN" src --no-cache >"$TMP_TB_DIR/unflagged.xml" 2>/dev/null
{ [ "$rc_generous" -eq 0 ] && [ -s "$TMP_TB_A" ]; } \
    && ok "--token-budget=999999 (generous): exit 0, map emitted" \
    || no "--token-budget=999999 (generous): expected exit 0 + non-empty stdout, got exit=$rc_generous size=$(wc -c <"$TMP_TB_A" 2>/dev/null)"
cmp -s "$TMP_TB_A" "$TMP_TB_DIR/unflagged.xml" \
    && ok "--token-budget=999999: stdout is BYTE-IDENTICAL to the unflagged map (never shapes)" \
    || no "--token-budget=999999: stdout differs from the unflagged map — the flag is shaping, not just gating"

# ── #8: a tiny budget → exit 3 (distinct from --arch/--quality-delta's exit 2), stderr names actual vs budget ──
"$BIN" src --token-budget=1 --no-cache >"$TMP_TB_B" 2>"$TMP_TB_B_ERR"
rc_tiny=$?
[ "$rc_tiny" -eq 3 ] \
    && ok "--token-budget=1 (tiny): exit 3" \
    || no "--token-budget=1 (tiny): expected exit 3, got $rc_tiny"
if grep -qE 'est_tokens=[0-9]+ > budget=1$' "$TMP_TB_B_ERR" 2>/dev/null; then
    ok "--token-budget=1: stderr names actual est_tokens vs the budget"
else
    no "--token-budget=1: stderr missing actual-vs-budget message (got: $(cat "$TMP_TB_B_ERR" 2>/dev/null))"
fi

# ── #8b (§P6.8): the REJECTED map must NOT reach stdout — a CI log that captures stdout on exit 3 must
#    never receive the artifact the gate just refused. stdout stays small (< 2KB); the 20+ KB map body
#    (grep for a real symbol name that only appears inside map rows) is absent. ───────────────────────────
TB_B_BYTES="$( wc -c < "$TMP_TB_B" | tr -d ' ' )"
[ "$TB_B_BYTES" -lt 2048 ] \
    && ok "--token-budget=1: stdout is small on exit 3 ($TB_B_BYTES bytes < 2KB — map withheld)" \
    || no "--token-budget=1: stdout is $TB_B_BYTES bytes (>= 2KB) — the rejected map is still leaking to stdout"
grep -q '<s t="' "$TMP_TB_B" \
    && no "--token-budget=1: stdout still contains <s t=\"...\"> map row content — not actually withheld" \
    || ok "--token-budget=1: stdout carries no map row content"

# ── #8c (§P6.8): a MID-size budget (over the generous run, under the full map) also withholds — not just
#    the degenerate budget=1 case — and reproduces the exact repro from PLAN_outputAudit_2026-07-28.md §P6.8 ──
"$BIN" . --token-budget=100 --no-cache >"$TMP_TB_DIR/mid.xml" 2>"$TMP_TB_DIR/mid.err"
rc_mid=$?
MID_BYTES="$( wc -c < "$TMP_TB_DIR/mid.xml" | tr -d ' ' )"
{ [ "$rc_mid" -eq 3 ] && [ "$MID_BYTES" -lt 2048 ]; } \
    && ok "--token-budget=100 on repo root: exit 3, stdout $MID_BYTES bytes (< 2KB — the PLAN's own repro)" \
    || no "--token-budget=100 on repo root: expected exit 3 + stdout < 2KB, got exit=$rc_mid bytes=$MID_BYTES"
grep -qE 'est_tokens=[0-9]+ > budget=100$' "$TMP_TB_DIR/mid.err" \
    && ok "--token-budget=100: stderr names actual est_tokens vs budget=100" \
    || no "--token-budget=100: stderr missing actual-vs-budget message (got: $(cat "$TMP_TB_DIR/mid.err" 2>/dev/null))"

# ── #9: the gate's actual number MUST equal the map header's own est_tokens (never a second counter) ───
HDR_EST="$( grep -oE 'est_tokens=[0-9]+' "$TMP_TB_A" | grep -oE '[0-9]+' )"
GATE_EST="$( grep -oE 'est_tokens=[0-9]+' "$TMP_TB_B_ERR" | grep -oE '[0-9]+' )"
{ [ -n "$HDR_EST" ] && [ -n "$GATE_EST" ] && [ "$HDR_EST" = "$GATE_EST" ]; } \
    && ok "gate value ($GATE_EST) == map header's est_tokens ($HDR_EST) — one counter, not two" \
    || no "gate/header est_tokens MISMATCH (header=$HDR_EST gate=$GATE_EST) — a second counter crept in"

# ── #10: determinism — the same command re-run twice gives the same exit code + the same est_tokens ───
"$BIN" src --token-budget=1 --no-cache >/dev/null 2>"$TMP_TB_B2_ERR"; rc_tiny2=$?
GATE_EST2="$( grep -oE 'est_tokens=[0-9]+' "$TMP_TB_B2_ERR" | grep -oE '[0-9]+' )"
{ [ "$rc_tiny" = "$rc_tiny2" ] && [ "$GATE_EST" = "$GATE_EST2" ]; } \
    && ok "--token-budget deterministic: exit ($rc_tiny) and est_tokens ($GATE_EST) match across re-runs" \
    || no "--token-budget non-deterministic across re-runs (exit $rc_tiny vs $rc_tiny2; est $GATE_EST vs $GATE_EST2)"

# ── #11: --token-budget accepts a K suffix (reuses --max-file-size's N[K|M|G] grammar) ─────────────────
"$BIN" src --token-budget=16K --no-cache >/dev/null 2>/dev/null
rc_ksuffix=$?
[ "$rc_ksuffix" -eq 0 ] || [ "$rc_ksuffix" -eq 3 ] \
    && ok "--token-budget=16K: K suffix parses (exit $rc_ksuffix, not a parse error)" \
    || no "--token-budget=16K: K suffix rejected (exit $rc_ksuffix)"

# ── #12: composes with --max-tokens — shaping to a small map, then asserting a smaller budget still fails ──
"$BIN" src --max-tokens=500 --token-budget=10 --no-cache >/dev/null 2>"$TMP_TB_COMPOSE_ERR"
rc_compose=$?
[ "$rc_compose" -eq 3 ] \
    && ok "--max-tokens=500 --token-budget=10: composes (shapes to ~500, still exceeds budget=10, exit 3)" \
    || no "--max-tokens + --token-budget composition: expected exit 3, got $rc_compose"

# ── #13: a bad --token-budget value is a clean parse error (exit 1), not a crash ────────────────────────
"$BIN" src --token-budget=abc --no-cache >/dev/null 2>/dev/null
rc_bad=$?
[ "$rc_bad" -eq 1 ] \
    && ok "--token-budget=abc: clean parse-error exit 1" \
    || no "--token-budget=abc: expected exit 1, got $rc_bad"

# ── D10 (AUDIT5): --for/--pack-task/--from-trace SHAPE instead of gate (always exit 0) — only the --for
# carve-out was documented before this round, and the shaped bundle carried no est_tokens at all, so a
# caller couldn't tell whether the shape actually fit. Checks #14-#16 close that gap for --for. ─────────

# ── #14: the --for lens header reports its OWN est_tokens=N — present, positive, deterministic ─────────
FOR_A="$( "$BIN" src --for="parse arguments" --no-cache 2>/dev/null )"
FOR_B="$( "$BIN" src --for="parse arguments" --no-cache 2>/dev/null )"
FOR_EST_A="$( printf '%s' "$FOR_A" | grep -oE 'est_tokens="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
FOR_EST_B="$( printf '%s' "$FOR_B" | grep -oE 'est_tokens="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
{ [ -n "$FOR_EST_A" ] && [ "$FOR_EST_A" -gt 0 ] 2>/dev/null && [ "$FOR_EST_A" = "$FOR_EST_B" ]; } \
    && ok "--for header reports est_tokens (present, positive: $FOR_EST_A, deterministic)" \
    || no "--for header est_tokens missing/non-positive/non-deterministic (got '$FOR_EST_A' then '$FOR_EST_B')"

# ── #15: --for's est_tokens tracks a --token-budget override — a tighter budget shapes to fewer tokens ──
FOR_TIGHT="$( "$BIN" src --for="parse arguments" --token-budget=200 --no-cache 2>/dev/null )"
FOR_TIGHT_EST="$( printf '%s' "$FOR_TIGHT" | grep -oE 'est_tokens="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
{ [ -n "$FOR_TIGHT_EST" ] && [ "$FOR_TIGHT_EST" -gt 0 ] 2>/dev/null && [ "$FOR_TIGHT_EST" -le "$FOR_EST_A" ] 2>/dev/null; } \
    && ok "--for --token-budget=200 shapes to fewer/equal est_tokens ($FOR_TIGHT_EST <= $FOR_EST_A default)" \
    || no "--for --token-budget=200 did not shrink est_tokens (tight=$FOR_TIGHT_EST default=$FOR_EST_A)"

# ── #16: --for always exits 0 under a tiny --token-budget — SHAPES, never gates (contrast #8 above) ────
"$BIN" src --for="parse arguments" --token-budget=1 --no-cache >/dev/null 2>/dev/null
rc_for_tiny=$?
[ "$rc_for_tiny" -eq 0 ] \
    && ok "--for --token-budget=1: exit 0 (shapes to fit, never the map/--query exit-3 gate)" \
    || no "--for --token-budget=1: expected exit 0 (shaping), got $rc_for_tiny"

# ── #17 (W3FIX H2): the ABSOLUTE ceiling, not only the RELATIVE shape ──────────────────────────────────
# #15/#16 are relative arms — a tighter budget shapes to fewer-or-equal tokens, and shaping never gates — and a
# FLOOR satisfies both perfectly: --for on a 900-char task delivered 5.3x its own stated ceiling at EVERY
# budget, which is monotone, exits 0, and shrinks as the budget shrinks. Every relative arm in this file passed
# it, which is precisely why an absolute one has to exist. The bar is the ceiling PLUS the single-entry
# overshoot the design allows (src/serialize.h kCeilingFirstEntryTolerance = 1.15 — the ranking section emits
# its first entry whole): the delivered document either fits that, or SAYS over_ceiling. Never neither.
TB_LONG_TASK="$( python3 -c "print(('budget accounting for the ranked lens header attributes '*20)[:900])" 2>/dev/null )"
if [ -z "$TB_LONG_TASK" ]; then
    no "#17: python3 unavailable — the absolute-ceiling arm could not build its 900-char task"
else
    for TB_B in 600 1200 2400; do
        "$BIN" src --for="$TB_LONG_TASK" --token-budget=$TB_B --no-cache >"$TMP_TB_DIR/abs.$TB_B" 2>/dev/null
        TB_BYTES="$( wc -c < "$TMP_TB_DIR/abs.$TB_B" | tr -d ' ' )"
        TB_ALLOW="$( python3 -c "print(int($TB_B*2.36*1.15))" )"
        # the disclosure lives in the header COMMENT — a body that quotes the word must not satisfy this arm
        TB_HDR="$( head -c 6000 "$TMP_TB_DIR/abs.$TB_B" | sed -e 's/-->.*//' )"
        if [ "$TB_BYTES" -le "$TB_ALLOW" ]; then
            ok "#17 --for 900-char task --token-budget=$TB_B: $TB_BYTES B fits the $TB_ALLOW B allowance"
        elif printf '%s' "$TB_HDR" | grep -q 'over_ceiling'; then
            ok "#17 --for 900-char task --token-budget=$TB_B: $TB_BYTES B over $TB_ALLOW B and DISCLOSES over_ceiling"
        else
            no "#17 --for 900-char task --token-budget=$TB_B: $TB_BYTES B past the $TB_ALLOW B allowance in SILENCE"
        fi
    done
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
