#!/usr/bin/env bash
# recallbudgetcheck.sh — §P2 gate: --recall's two budget flags must actually work.
#
# --recall is the LARGEST output the tool produces (116 KB / ~29K tokens for a plain ctxpack-shaped query
# on this repo, 493 KB before the docs/captures relocation) and, before this gate, neither budget flag
# bounded it:
#   --recall=Q --max-tokens=2000     → 170,493 bytes — ~85x the asked-for budget (whole-doc-or-stop with
#                                      an "always emit at least the top hit" escape, at a wrong 4 B/tok rate)
#   --recall=Q --token-budget=2000   → the full artifact, exit 0 — the gate personality never ran
# A verb whose selling point is "~47x fewer tokens than loading everything" with no enforceable ceiling is
# a footgun. The documented two-personality rule (--help, D10) says --max-tokens SHAPES and --token-budget
# GATES; this gate freezes both for recall, plus the honest-shape disclosure that must accompany a cut.
#
# Invariants frozen here:
#   1. --max-tokens=N SHAPES to fit N (bytes <= N * 2.5 B/tok * 1.5 slack) and DISCLOSES every cut
#   2. --token-budget=N GATES: exit 3, stderr names actual vs budget, and stdout does NOT carry the
#      artifact it just rejected (§P6.8's lesson — a CI log must not receive the 116 KB it failed on)
#   3. a budget far above the artifact is inert: exit 0, byte-identical to the unbudgeted run
#   4. the header carries an honest est_tokens covering the WHOLE payload (§P9.3), within 2x of bytes/2.5
#   5. budgeted runs are deterministic (byte-identical run to run)
#   6. an UNFLAGGED run is unchanged: same selection, same full bodies, no cut markers, legacy header
#      prefix intact. With CTXPACK_BASE_BIN set to a pre-change binary, the body payload (everything
#      after the header line) is asserted BYTE-IDENTICAL to that binary's.
#
#   CTXPACK_BIN=build/ctxpack bash test/recallbudgetcheck.sh
#   CTXPACK_BIN=build_base/ctxpack bash test/recallbudgetcheck.sh    # must FAIL (pre-fix binary)
#   CTXPACK_BASE_BIN=/tmp/ctxpack_base CTXPACK_BIN=build/ctxpack bash test/recallbudgetcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
BASE_BIN="${CTXPACK_BASE_BIN:-}"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
echo "recallbudgetcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R"

# ── the corpus: one HUGE on-topic doc (the "always emit the top hit" escape hatch) + smaller relatives.
# The huge doc alone is ~200 KB, so a working --max-tokens must truncate WITHIN it, not just drop the tail.
{
    echo "# Quality delta gating exit codes"
    for i in $( seq 1 2600 ); do
        echo "The quality delta gate reports gating findings and the exit codes it returns; gating exit code $i."
    done
    echo "SENTINEL_TAIL_BIG"
} > "$R/big_gating.md"
{
    echo "# Exit codes reference"
    echo "The gating exit codes: 0 clean, 2 new debt, 3 budget exceeded, 4 test gate."
    echo "SENTINEL_TAIL_EXIT"
} > "$R/exitcodes.md"
{
    echo "# Quality delta design"
    echo "Quality delta compares against HEAD and reports only what a change made worse."
    echo "SENTINEL_TAIL_QD"
} > "$R/qualitydelta.md"
{
    echo "# Unrelated glyph rasterization"
    echo "Bezier tessellation, subpixel antialiasing and hinting for the text render layer."
    echo "SENTINEL_TAIL_GLYPH"
} > "$R/render.md"

Q="quality delta gating exit codes"
run(){ perl -e 'alarm 60; exec @ARGV' "$BIN" "$R" --recall="$Q" --no-cache "$@" 2>"$TMP/err"; }

# ── baseline: the unbudgeted artifact ────────────────────────────────────────────────────────────────
run > "$TMP/plain.out"; PLAIN_RC=$?
PLAIN_B=$( wc -c < "$TMP/plain.out" | tr -d ' ' )
[ "$PLAIN_RC" = 0 ] && [ "$PLAIN_B" -gt 100000 ] \
    && ok "baseline: unbudgeted --recall emits $PLAIN_B bytes, exit 0 (the artifact under test)" \
    || no "baseline: unbudgeted --recall exit=$PLAIN_RC bytes=$PLAIN_B (expected exit 0, >100 KB)"

# ── 1. --max-tokens=2000 SHAPES to fit, and DISCLOSES the cut ────────────────────────────────────────
# ceiling = 2000 tok * 2.5 B/tok * 1.5 slack. The tool sizes its own budget at the denser conservative
# rate (kMinBytesPerToken * kBudgetHeadroom), so this is a generous outer bound, not the tool's target.
LIMIT=7500
run --max-tokens=2000 > "$TMP/mt.out"; MT_RC=$?
MT_B=$( wc -c < "$TMP/mt.out" | tr -d ' ' )
[ "$MT_RC" = 0 ] && [ "$MT_B" -le "$LIMIT" ] \
    && ok "--max-tokens=2000: $MT_B bytes <= $LIMIT (was $PLAIN_B unbudgeted)" \
    || no "--max-tokens=2000: $MT_B bytes exceeds $LIMIT (exit=$MT_RC) — the budget does not bound the output"
grep -qE 'truncated|capped' "$TMP/mt.out" \
    && ok "--max-tokens=2000: the cut is DISCLOSED in the output (truncated/capped marker)" \
    || no "--max-tokens=2000: output was cut with NO disclosure — a silent cut"
grep -qE 'shown=' "$TMP/mt.out" \
    && ok "--max-tokens=2000: header reports shown= (honest total/shown/capped shape)" \
    || no "--max-tokens=2000: header has no shown= field"

# ── 1b. a budget too small for ANY doc is a CAP, never "no relevant documents" (§P0.1 honest-limit rule)
run --max-tokens=1 > "$TMP/tiny.out"; TINY_RC=$?
{ [ "$TINY_RC" = 0 ] && ! grep -q 'no relevant documents' "$TMP/tiny.out" && grep -q 'capped' "$TMP/tiny.out"; } \
    && ok "--max-tokens=1: reports a CAP, not an empty corpus (the ranking did find docs)" \
    || no "--max-tokens=1 (exit $TINY_RC): $( sed -n '3p' "$TMP/tiny.out" ) — a starved budget must not read as 'no relevant documents'"

# ── 2. --token-budget=2000 GATES, and does NOT stream the artifact it rejected ───────────────────────
run --token-budget=2000 > "$TMP/tb.out"; TB_RC=$?
TB_B=$( wc -c < "$TMP/tb.out" | tr -d ' ' )
[ "$TB_RC" = 3 ] && ok "--token-budget=2000: exit 3 (the map family's over-budget code)" \
                 || no "--token-budget=2000: exit $TB_RC (expected 3) — the gate personality did not fire"
[ "$TB_B" -lt 20000 ] && [ "$TB_B" -lt "$PLAIN_B" ] \
    && ok "--token-budget=2000: stdout is $TB_B bytes, not the $PLAIN_B-byte artifact it rejected" \
    || no "--token-budget=2000: stdout is $TB_B bytes (expected < 20000 and < $PLAIN_B) — it streamed the rejected artifact"
grep -q 'token-budget exceeded' "$TMP/err" \
    && ok "--token-budget=2000: stderr names actual vs budget" \
    || no "--token-budget=2000: stderr does not carry a 'token-budget exceeded' line: $( head -c 200 "$TMP/err" )"

# ── 2b. §A8.3: the withheld run's HEADER must describe what IT printed (0 rows), not the bundle it
# rejected. Pre-fix, the header line streamed here was formatted for the accepted (never-emitted) bundle
# and claimed shown=8 while zero rows followed — shown= is normatively "rows THIS run printed".
TB_HEADER="$( head -1 "$TMP/tb.out" )"
printf '%s' "$TB_HEADER" | grep -q ' shown=0 ' \
    && ok "--token-budget=2000: withheld run's header carries shown=0 (it printed zero rows)" \
    || no "--token-budget=2000: withheld header does not say shown=0: $TB_HEADER"
printf '%s' "$TB_HEADER" | grep -qE ' total=[0-9]+ ' \
    && ok "--token-budget=2000: withheld header still carries total= (the rejected bundle's honest size)" \
    || no "--token-budget=2000: withheld header lost total="
# Wave-1-verifier N3 PIN UPDATE (PLAN_outputAudit3): the note's number was spelled `est_tokens=`, the same
# name the header uses for a DIFFERENT quantity — the header's est_tokens= is normatively what THIS RUN
# printed, the note's is the rejected bundle's pre-cut size. One name, two meanings, in adjacent lines. The
# note now says withheld_est_tokens=; the arm below pins the distinct name, and the two arms after it pin
# what the rename bought: the header's est_tokens= is a MEASUREMENT of the ~260 emitted bytes (it read
# 98069 beside shown=0 before), and the pre-cut number is still reachable under its own name.
grep -q 'withheld: withheld_est_tokens=' "$TMP/tb.out" \
    && ok "--token-budget=2000: stdout carries a 'withheld: withheld_est_tokens=...' clause (distinct name)" \
    || no "--token-budget=2000: stdout is missing the withheld: withheld_est_tokens= clause"
TB_BYTES=$( wc -c < "$TMP/tb.out" | tr -d ' ' )
TB_EST="$( printf '%s' "$TB_HEADER" | grep -oE 'est_tokens=[0-9]+' | grep -oE '[0-9]+' )"
{ [ -n "$TB_EST" ] && [ "$TB_EST" -le $(( TB_BYTES * 10 / 25 * 2 )) ]; } \
    && ok "N3: withheld header's est_tokens=$TB_EST describes the EMITTED payload ($TB_BYTES bytes, <=2x bytes/2.5)" \
    || no "N3: withheld header's est_tokens=$TB_EST is not a measurement of the $TB_BYTES bytes actually emitted"
WITHHELD_EST="$( grep -oE 'withheld_est_tokens=[0-9]+' "$TMP/tb.out" | grep -oE '[0-9]+' )"
{ [ -n "$WITHHELD_EST" ] && [ -n "$TB_EST" ] && [ "$WITHHELD_EST" -gt "$TB_EST" ]; } \
    && ok "N3: the PRE-cut estimate survives under its own name ($WITHHELD_EST) and is distinct from the emitted one" \
    || no "N3: withheld_est_tokens=$WITHHELD_EST vs emitted est_tokens=$TB_EST — the two numbers are not distinguished"

# ── 3. a budget above the artifact is INERT ─────────────────────────────────────────────────────────
run --token-budget=1000000 > "$TMP/tbbig.out"; TBB_RC=$?
[ "$TBB_RC" = 0 ] && cmp -s "$TMP/tbbig.out" "$TMP/plain.out" \
    && ok "--token-budget=1000000: exit 0, byte-identical to the unbudgeted run (inert when within budget)" \
    || no "--token-budget=1000000: exit=$TBB_RC / output differs from the unbudgeted run"

# ── 4. est_tokens is present and honest over the WHOLE payload ──────────────────────────────────────
est_of(){ head -1 "$1" | grep -oE 'est_tokens=[0-9]+' | grep -oE '[0-9]+'; }
for f in plain mt; do
    E="$( est_of "$TMP/$f.out" )"
    B=$( wc -c < "$TMP/$f.out" | tr -d ' ' )
    if [ -z "$E" ]; then
        no "--recall ($f): header carries no est_tokens"
    else
        # honest band: within 2x either way of bytes/2.5
        LO=$(( B * 10 / 25 / 2 ));  HI=$(( B * 10 / 25 * 2 ))
        [ "$E" -ge "$LO" ] && [ "$E" -le "$HI" ] \
            && ok "--recall ($f): est_tokens=$E within 2x of bytes/2.5 ($B bytes -> $LO..$HI)" \
            || no "--recall ($f): est_tokens=$E outside $LO..$HI for $B bytes"
    fi
done

# ── 5. determinism under a budget ───────────────────────────────────────────────────────────────────
run --max-tokens=2000 > "$TMP/mt2.out"
cmp -s "$TMP/mt.out" "$TMP/mt2.out" \
    && ok "--max-tokens=2000 deterministic (byte-identical run to run)" \
    || no "--max-tokens=2000 non-deterministic"

# ── 6. the UNFLAGGED run is unchanged — no default behavior change ──────────────────────────────────
# §B9.2 PIN UPDATE: the denominator's noun moved from "docs" (which --doc-drift's docs= also claims, over a
# DIFFERENT predicate) to "document files", which is what docFileMask actually counts. Shape unchanged.
head -1 "$TMP/plain.out" | grep -qE "^ctxpack recall — \"$Q\" — [0-9]+ relevant of [0-9]+ document files, best-first" \
    && ok "unflagged: header prefix ('K relevant of N document files, best-first') intact" \
    || no "unflagged: header prefix changed: $( head -c 160 "$TMP/plain.out" )"
grep -qE 'truncated|capped=1|omitted' "$TMP/plain.out" \
    && no "unflagged: output carries a cut marker — the default path must not cut" \
    || ok "unflagged: no cut markers (the default path emits full bodies)"
MISSING=""
for s in SENTINEL_TAIL_BIG SENTINEL_TAIL_EXIT SENTINEL_TAIL_QD; do
    grep -q "$s" "$TMP/plain.out" || MISSING="$MISSING $s"
done
[ -z "$MISSING" ] && ok "unflagged: every selected doc's FULL body is present (tail sentinels)" \
                  || no "unflagged: missing doc tails:$MISSING"

if [ -n "$BASE_BIN" ] && [ -x "$BASE_BIN" ]; then
    perl -e 'alarm 60; exec @ARGV' "$BASE_BIN" "$R" --recall="$Q" --no-cache > "$TMP/base.out" 2>/dev/null
    tail -n +2 "$TMP/base.out"  > "$TMP/base.body"
    tail -n +2 "$TMP/plain.out" > "$TMP/plain.body"
    cmp -s "$TMP/base.body" "$TMP/plain.body" \
        && ok "unflagged: body payload BYTE-IDENTICAL to the pre-change binary ($BASE_BIN)" \
        || no "unflagged: body payload differs from the pre-change binary ($BASE_BIN)"
else
    echo "  SKIP  pre-change byte-identity (set CTXPACK_BASE_BIN=<pre-change ctxpack> to enable)"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
