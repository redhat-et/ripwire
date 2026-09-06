#!/usr/bin/env bash
# recallbudgetcheck.sh — §P2 gate: --recall's two budget flags must actually work.
#
# --recall is the LARGEST output the tool produces (116 KB / ~29K tokens for a plain ripwire-shaped query
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
#   3. a budget far above the artifact is inert: exit 0, byte-identical to an explicit full-budget run
#   4. the header carries an honest est_tokens covering the WHOLE payload (§P9.3), within 2x of bytes/2.5
#   5. budgeted runs are deterministic (byte-identical run to run)
#   6. an UNFLAGGED run has the documented 8K-token ceiling, discloses its cut, and an explicit high
#      --max-tokens restores the full selected bodies. With RIPWIRE_BASE_BIN set to a reference binary,
#      the body payload is asserted BYTE-IDENTICAL to that binary's AT EQUAL FLAGS, at BOTH operating
#      points (unflagged and explicit-full) — the ceiling BOUNDS recall, it never CHANGES what recall says.
#      (This arm read "head --max-tokens=1000000 vs base UNFLAGGED" while the reference was pre-ceiling and
#      its unflagged run WAS the full artifact; that spelling is unpassable against any post-ceiling
#      reference, so the comparison is now flag-symmetric by construction. See §6b.)
#
#   RIPWIRE_BIN=build/ripwire bash test/recallbudgetcheck.sh
#   RIPWIRE_BIN=build_base/ripwire bash test/recallbudgetcheck.sh    # must FAIL (pre-fix binary)
#   RIPWIRE_BASE_BIN=/tmp/ripwire_base RIPWIRE_BIN=build/ripwire bash test/recallbudgetcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
BASE_BIN="${RIPWIRE_BASE_BIN:-}"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
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

# ── baseline: the explicit-full artifact; default is intentionally bounded ──────────────────────────
run --max-tokens=1000000 > "$TMP/plain.out"; PLAIN_RC=$?
PLAIN_B=$( wc -c < "$TMP/plain.out" | tr -d ' ' )
[ "$PLAIN_RC" = 0 ] && [ "$PLAIN_B" -gt 100000 ] \
    && ok "baseline: explicit-full --recall emits $PLAIN_B bytes, exit 0 (the artifact under test)" \
    || no "baseline: explicit-full --recall exit=$PLAIN_RC bytes=$PLAIN_B (expected exit 0, >100 KB)"

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
run --max-tokens=1000000 --token-budget=2000 > "$TMP/tb.out"; TB_RC=$?
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
# Wave-1-verifier N3 PIN UPDATE: the note's number was spelled `est_tokens=`, the same
# name the header uses for a DIFFERENT quantity — the header's est_tokens= is normatively what THIS RUN
# printed, the note's is the rejected bundle's pre-cut size. One name, two meanings, in adjacent lines. The
# note now says withheld_est_tokens=; the arm below pins the distinct name, and the two arms after it pin
# what the rename bought: the header's est_tokens= is a MEASUREMENT of the ~260 emitted bytes (it read
# 98069 beside shown=0 before), and the pre-cut number is still reachable under its own name.
grep -q 'withheld: withheld_est_tokens=' "$TMP/tb.out" \
    && ok "--token-budget=2000: stdout carries a 'withheld: withheld_est_tokens=...' clause (distinct name)" \
    || no "--token-budget=2000: stdout is missing the withheld: withheld_est_tokens= clause"
TB_BYTES=$( wc -c < "$TMP/tb.out" | tr -d ' ' )
# verify-wave2 F4 PROBE RE-PIN: withheld_est_tokens= moved from the note ONTO the header line (so a parser
# reads the budget, the withheld price and the emitted price side by side), and `est_tokens=` is a SUFFIX of
# it — the old unanchored grep started returning TWO numbers and every numeric test after it silently broke.
# Anchored on the leading space, the same disambiguation withHeaderField uses in recall.h.
TB_EST="$( printf '%s' "$TB_HEADER" | grep -oE ' est_tokens=[0-9]+' | grep -oE '[0-9]+' )"
{ [ -n "$TB_EST" ] && [ "$TB_EST" -le $(( TB_BYTES * 10 / 25 * 2 )) ]; } \
    && ok "N3: withheld header's est_tokens=$TB_EST describes the EMITTED payload ($TB_BYTES bytes, <=2x bytes/2.5)" \
    || no "N3: withheld header's est_tokens=$TB_EST is not a measurement of the $TB_BYTES bytes actually emitted"
# F4: the same number now appears TWICE in the document — as a header ATTRIBUTE (for a parser) and in the
# withheld PROSE clause (for a reader). head -1 takes the header's; the arm below pins that they agree.
WITHHELD_EST="$( grep -oE 'withheld_est_tokens=[0-9]+' "$TMP/tb.out" | grep -oE '[0-9]+' | head -1 )"
WITHHELD_N="$(   grep -oE 'withheld_est_tokens=[0-9]+' "$TMP/tb.out" | sort -u | wc -l | tr -d ' ' )"
[ "$WITHHELD_N" = 1 ] \
    && ok "N3: the header attribute and the withheld clause state ONE withheld number, not two" \
    || no "N3: withheld_est_tokens= is spelled with $WITHHELD_N different values in one document"
{ [ -n "$WITHHELD_EST" ] && [ -n "$TB_EST" ] && [ "$WITHHELD_EST" -gt "$TB_EST" ]; } \
    && ok "N3: the PRE-cut estimate survives under its own name ($WITHHELD_EST) and is distinct from the emitted one" \
    || no "N3: withheld_est_tokens=$WITHHELD_EST vs emitted est_tokens=$TB_EST — the two numbers are not distinguished"

# ── 3. a budget above the artifact TRIMS NOTHING ────────────────────────────────────────────────────
# RE-PIN 2026-09-05 (capture-audit verify-wave2 F4, lane V2) — to the new contract stated precisely, not to a
# loosened assertion. This arm used to demand BYTE-IDENTICAL, which was a stronger claim than the invariant
# it names: --token-budget is a ceiling the run APPLIED and passed, and H9's rule ("a ceiling applied is a
# ceiling named") makes it a header attribute exactly as --for/--pack-task/--from-trace already name theirs
# when they are inside them. What must not change is the ARTIFACT: same exit, same payload, no trim. So the
# comparison normalises away the one attribute the flag legitimately adds and asserts byte-identity on
# everything else — which is strictly more than the old arm, because it now also pins that the attribute
# carries the value that was passed and that NOTHING ELSE moved.
run --max-tokens=1000000 --token-budget=1000000 > "$TMP/tbbig.out"; TBB_RC=$?
grep -q ' budget_tokens=1000000' "$TMP/tbbig.out" \
    && ok "--token-budget=1000000: the header names the ceiling it applied and passed" \
    || no "--token-budget=1000000: applied a ceiling and named none (H9: a ceiling applied is a ceiling named)"
sed -E 's/ budget_tokens=[0-9]+//; s/ est_tokens=[0-9]+//' "$TMP/tbbig.out" >"$TMP/tbbig.norm"
sed -E 's/ est_tokens=[0-9]+//'                             "$TMP/plain.out" >"$TMP/plain.norm"
[ "$TBB_RC" = 0 ] && cmp -s "$TMP/tbbig.norm" "$TMP/plain.norm" \
    && ok "--token-budget=1000000: exit 0 and the ARTIFACT is byte-identical to the explicit-full run (nothing trimmed)" \
    || no "--token-budget=1000000: exit=$TBB_RC / the artifact differs from the explicit-full run beyond the budget_tokens= attribute"

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

# ── 6. the UNFLAGGED run is bounded by default; explicit high --max-tokens restores full bodies ─────
run > "$TMP/default.out"; DEFAULT_RC=$?
DEFAULT_B=$( wc -c < "$TMP/default.out" | tr -d ' ' )
# §B9.2 PIN UPDATE: the denominator's noun moved from "docs" (which --doc-drift's docs= also claims, over a
# DIFFERENT predicate) to "document files", which is what docFileMask actually counts.
head -1 "$TMP/default.out" | grep -qE "^ripwire recall — \"$Q\" — [0-9]+ relevant of [0-9]+ document files, best-first" \
    && ok "unflagged: header prefix ('K relevant of N document files, best-first') intact" \
    || no "unflagged: header prefix changed: $( head -c 160 "$TMP/default.out" )"
[ "$DEFAULT_RC" = 0 ] && [ "$DEFAULT_B" -le 30000 ] \
    && ok "unflagged: default 8K-token ceiling bounds output to $DEFAULT_B bytes" \
    || no "unflagged: exit=$DEFAULT_RC bytes=$DEFAULT_B (expected exit 0 and <= 30000)"
grep -qE 'truncated|capped=1|omitted' "$TMP/default.out" \
    && ok "unflagged: default ceiling's cut is disclosed" \
    || no "unflagged: default ceiling cut has no disclosure"
grep -q 'max_tokens=8000' "$TMP/default.out" \
    && ok "unflagged: header discloses the effective max_tokens=8000 policy" \
    || no "unflagged: header does not disclose max_tokens=8000"
MISSING=""
for s in SENTINEL_TAIL_BIG SENTINEL_TAIL_EXIT SENTINEL_TAIL_QD; do
    grep -q "$s" "$TMP/plain.out" || MISSING="$MISSING $s"
done
[ -z "$MISSING" ] && ok "explicit-full: every selected doc's FULL body is present (tail sentinels)" \
                  || no "explicit-full: missing doc tails:$MISSING"

# ── 6b. reference-binary byte identity, AT EQUAL FLAGS, at BOTH ceilings ────────────────────────────
# What this arm exists to catch: the default ceiling must BOUND recall, never CHANGE what recall says.
# It was written in the round that ADDED the 8K default, when the reference binary was PRE-ceiling: an
# unflagged base run WAS the full artifact, so "base unflagged" vs "head --max-tokens=1000000" was the
# flag-symmetric comparison of that moment. It stopped being one the instant the ceiling shipped — against
# any post-ceiling reference the same two commands compare a bounded payload with a full one (16,918 B vs
# 262,287 B here) and the arm can never pass again, for a reason that has nothing to do with a regression.
# Restated so it survives its own subject landing: compare base and head UNDER THE SAME FLAGS, at BOTH
# operating points — the default ceiling AND explicit-full. That is strictly stronger than the original
# single comparison: it pins the bounded payload (which the original never compared at all, since the
# pre-ceiling base had none) as well as the full one, and it is the comparison that stays meaningful for
# every future reference binary. Bodies only (line 1 dropped) so a new HEADER disclosure field is an
# expected difference and a changed doc SELECTION, ORDER or BODY is not.
if [ -n "$BASE_BIN" ] && [ -x "$BASE_BIN" ]; then
    base_run(){ perl -e 'alarm 60; exec @ARGV' "$BASE_BIN" "$R" --recall="$Q" --no-cache "$@" 2>/dev/null; }
    base_run --max-tokens=1000000 > "$TMP/base_full.out"
    base_run                      > "$TMP/base_def.out"
    for pair in "base_full:plain:explicit-full (--max-tokens=1000000 on BOTH)" \
                "base_def:default:unflagged (the 8K default ceiling on BOTH)"; do
        B_F="${pair%%:*}"; REST="${pair#*:}"; H_F="${REST%%:*}"; LABEL="${REST#*:}"
        tail -n +2 "$TMP/$B_F.out" > "$TMP/$B_F.body"
        tail -n +2 "$TMP/$H_F.out" > "$TMP/$H_F.body"
        cmp -s "$TMP/$B_F.body" "$TMP/$H_F.body" \
            && ok "$LABEL: body payload BYTE-IDENTICAL to the reference binary ($BASE_BIN)" \
            || no "$LABEL: body payload differs from the reference binary ($BASE_BIN) — recall's content moved, not just its bound"
    done
else
    echo "  SKIP  reference-binary byte-identity (set RIPWIRE_BASE_BIN=<reference ripwire> to enable)"
fi

# ── 7. MCP parity: memory_recall is bounded by the SAME default ceiling, budget_tokens raises it ────
# The CLI's 8K default landed alone in the first round and left the MCP front door unbounded — the same
# broad docs query could stream hundreds of KB through one tools/call. Both doors, one policy, disclosed.
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize"}'
DCALL='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"memory_recall","arguments":{"path":"'"$R"'","task":"quality delta gating exit codes"}}}'
FCALL='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"memory_recall","arguments":{"path":"'"$R"'","task":"quality delta gating exit codes","budget_tokens":1000000}}}'
printf '%s\n%s\n%s\n' "$INIT" "$DCALL" "$FCALL" | perl -e 'alarm 60; exec @ARGV' "$BIN" --mcp >"$TMP/mcp.out" 2>/dev/null
MCP_DEF="$( grep '"id":2' "$TMP/mcp.out" )"
MCP_FULL="$( grep '"id":3' "$TMP/mcp.out" )"
MCP_DEF_B="$( printf '%s' "$MCP_DEF" | wc -c | tr -d ' ' )"
case "$MCP_DEF" in
    *max_tokens=8000*) ok "MCP default: header discloses the effective max_tokens=8000 policy" ;;
    *) no "MCP default: no max_tokens=8000 disclosure in the reply" ;;
esac
[ -n "$MCP_DEF" ] && [ "$MCP_DEF_B" -le 60000 ] \
    && ok "MCP default: reply bounded to $MCP_DEF_B bytes (JSON-escaped ~8K-token body)" \
    || no "MCP default: reply is $MCP_DEF_B bytes (expected <= 60000) — the ceiling is not applied over MCP"
case "$MCP_DEF" in
    *SENTINEL_TAIL_BIG*) no "MCP default: the huge doc's tail survived — no cut happened" ;;
    *) ok "MCP default: the huge doc is cut under the ceiling" ;;
esac
case "$MCP_FULL" in
    *SENTINEL_TAIL_BIG*) ok "MCP budget_tokens=1000000: full bodies restored (tail sentinel present)" ;;
    *) no "MCP budget_tokens=1000000: tail sentinel missing — explicit budget did not lift the ceiling" ;;
esac

# ── 8. SPREAD: the budget is divided across the matched documents, not handed to document #1 ────────
# Harvest-B card C4. The §P2 arms above froze that --max-tokens BOUNDS the artifact; they never froze
# WHO gets the bytes. buildRecall's budget loop was greedy first-fit — the first document was given all
# the remaining room, truncated to fill it, and the loop then `break`ed — so ONE long top hit erased the
# whole rest of the corpus at every budget:
#
#   157-doc agent-memory dir, --top-k=6 --max-tokens=5000  →  total=157 shown=1 truncated=1
#   this corpus (1 huge + 5 small, ALL on-topic), --max-tokens=2000/5000/8000 → shown=1, shown=1, shown=1
#
# The count of documents an agent gets back was decided by the SIZE OF THE TOP HIT, not by the budget:
# tripling the budget bought more of document #1 and never a second document. Five 150-byte documents
# that would have cost 750 bytes of a 20,000-byte budget were dropped as "capped".
#
# The property frozen here is a RANGE, deliberately — not a fixed shown=. Too little spreading is the
# defect above; too MUCH spreading is the opposite failure (dividing a budget by --top-k when only one
# document matched, so a single-hit query returns one 240-byte stub and wastes 90% of the ceiling).
# Arms 8.1/8.2 pin the floor, 8.4 pins the ceiling, 8.9 pins monotonicity between them.
#
# FAMILY (rule 4): the population is every front door onto the ranked-then-budgeted recall bundle —
# derived from src/ here, not hard-coded, so a THIRD door added later fails 8.7 loudly instead of
# silently keeping the old allocator. Today: verbs_for.h (CLI --recall) + mcpverbs.h (MCP memory_recall).
echo "  ---- §8 spread (harvest-B C4) ----"
S="$TMP/spread"; mkdir -p "$S"
{
    echo "# Quality delta gating exit codes"
    for i in $( seq 1 2600 ); do
        echo "The quality delta gate reports gating findings and the exit codes it returns; gating exit code $i."
    done
    echo "SENTINEL_SPREAD_BIG"
} > "$S/big_gating.md"
for n in a b c d e; do
    {
        echo "# Quality delta gating note $n"
        echo "The quality delta gating exit codes note $n explains gating and exit codes for delta quality."
        echo "SENTINEL_SPREAD_$n"
    } > "$S/small_$n.md"
done
srun(){ perl -e 'alarm 60; exec @ARGV' "$BIN" "$S" --recall="$Q" --no-cache "$@" 2>"$TMP/serr"; }
shown_of(){ head -1 "$1" | grep -oE ' shown=[0-9]+' | grep -oE '[0-9]+'; }

srun --max-tokens=5000 > "$TMP/sp5.out"; SP5_RC=$?
SP5_SHOWN="$( shown_of "$TMP/sp5.out" )"; SP5_B=$( wc -c < "$TMP/sp5.out" | tr -d ' ' )
{ [ "$SP5_RC" = 0 ] && [ -n "$SP5_SHOWN" ] && [ "$SP5_SHOWN" -ge 4 ]; } \
    && ok "8.1 spread: --max-tokens=5000 over 6 matched docs emits shown=$SP5_SHOWN (>=4) — the top hit does not take the whole budget" \
    || no "8.1 spread: --max-tokens=5000 emits shown=$SP5_SHOWN of 6 matched (expected >=4, exit=$SP5_RC) — greedy first-fit: document #1 consumed the budget"
SP_MISSING=""
for n in a b c d e; do
    grep -q "SENTINEL_SPREAD_$n" "$TMP/sp5.out" || SP_MISSING="$SP_MISSING small_$n"
done
SP_PRESENT=$(( 5 - $( printf '%s' "$SP_MISSING" | wc -w | tr -d ' ' ) ))
[ "$SP_PRESENT" -ge 3 ] \
    && ok "8.2 spread: $SP_PRESENT of 5 small on-topic docs reached the reader under a 5000-token budget" \
    || no "8.2 spread: only $SP_PRESENT of 5 small on-topic docs emitted (missing:$SP_MISSING) — ~750 bytes of matched prose dropped from a ~12000-byte budget"
SP_LIMIT=18750   # 5000 tok * 2.5 B/tok * 1.5 slack, the same outer bound arm 1 uses
[ "$SP5_B" -le "$SP_LIMIT" ] \
    && ok "8.3 spread: the artifact is still BOUNDED ($SP5_B <= $SP_LIMIT bytes) — spreading did not raise the ceiling" \
    || no "8.3 spread: $SP5_B bytes exceeds $SP_LIMIT — the per-doc share overspent the budget"

# 8.4 the opposite failure: ONE matching doc must still receive the WHOLE budget, never budget/top-k.
O="$TMP/onehit"; mkdir -p "$O"
{
    echo "# Quality delta gating exit codes"
    for i in $( seq 1 2600 ); do
        echo "The quality delta gate reports gating findings and the exit codes it returns; gating exit code $i."
    done
} > "$O/big_gating.md"
{
    echo "# Unrelated glyph rasterization"
    echo "Bezier tessellation, subpixel antialiasing and hinting for the text render layer."
} > "$O/render.md"
perl -e 'alarm 60; exec @ARGV' "$BIN" "$O" --recall="$Q" --no-cache --max-tokens=5000 > "$TMP/one.out" 2>/dev/null
ONE_B=$( wc -c < "$TMP/one.out" | tr -d ' ' )
ONE_SHOWN="$( shown_of "$TMP/one.out" )"
{ [ "$ONE_SHOWN" = 1 ] && [ "$ONE_B" -ge 6000 ]; } \
    && ok "8.4 no over-spread: a single matched doc still gets the whole budget (shown=1, $ONE_B bytes)" \
    || no "8.4 no over-spread: single-hit corpus emitted shown=$ONE_SHOWN in $ONE_B bytes (expected shown=1, >=6000) — the budget was divided by --top-k instead of by the MATCH count"

# 8.5 H9 ("a ceiling applied is a ceiling named"): the per-document share IS a ceiling. Named when it
# bound a document; ABSENT when it bound nothing, the same silence-means-nothing-happened rule
# truncated=/generated_demoted=/over_ceiling= already follow on this header.
grep -qE ' share_bytes=[0-9]+' "$TMP/sp5.out" \
    && ok "8.5 disclosure: the header names the per-document share it applied (share_bytes=)" \
    || no "8.5 disclosure: a per-document ceiling was applied and named none — H9 violated: $( head -c 220 "$TMP/sp5.out" )"
srun --max-tokens=1000000 > "$TMP/spfull.out"
grep -qE ' share_bytes=' "$TMP/spfull.out" \
    && no "8.5b disclosure: share_bytes= appears on an unbounded run where no share bound anything" \
    || ok "8.5b disclosure: share_bytes= is absent when the share bound nothing (silence = it did not happen)"

# 8.6 inert when the budget is not binding: every body whole, exactly as before this change.
SPF_SHOWN="$( shown_of "$TMP/spfull.out" )"
SPF_MISSING=""
for s in SENTINEL_SPREAD_BIG SENTINEL_SPREAD_a SENTINEL_SPREAD_b SENTINEL_SPREAD_c SENTINEL_SPREAD_d SENTINEL_SPREAD_e; do
    grep -q "$s" "$TMP/spfull.out" || SPF_MISSING="$SPF_MISSING $s"
done
{ [ "$SPF_SHOWN" = 6 ] && [ -z "$SPF_MISSING" ]; } \
    && ok "8.6 inert at a non-binding budget: shown=6, every body whole (all tail sentinels present)" \
    || no "8.6 inert at a non-binding budget: shown=$SPF_SHOWN, missing tails:$SPF_MISSING — spreading truncated a run it had no reason to touch"

# 8.7 FAMILY: derive the front doors from src/, then exercise EVERY one of them at the same budget.
DOORS="$( grep -rlE '(^|[^[:alnum:]_])recallFor\(' "$ROOT/src" | grep -v '/recall\.h$' | LC_ALL=C sort | xargs -n1 basename | tr '\n' ' ' )"
DOOR_N=$( printf '%s' "$DOORS" | wc -w | tr -d ' ' )
[ "$DOOR_N" = 2 ] \
    && ok "8.7 family: exactly the 2 known recall front doors exist ($DOORS)" \
    || no "8.7 family: src/ has $DOOR_N recall front doors ($DOORS) — a door was added and this gate does not exercise it"
SINIT='{"jsonrpc":"2.0","id":1,"method":"initialize"}'
SCALL='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"memory_recall","arguments":{"path":"'"$S"'","task":"'"$Q"'","budget_tokens":5000}}}'
printf '%s\n%s\n' "$SINIT" "$SCALL" | perl -e 'alarm 60; exec @ARGV' "$BIN" --mcp >"$TMP/spmcp.out" 2>/dev/null
MCP_SP="$( grep '"id":2' "$TMP/spmcp.out" )"
MCP_SP_SHOWN="$( printf '%s' "$MCP_SP" | grep -oE ' shown=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
{ [ -n "$MCP_SP_SHOWN" ] && [ "$MCP_SP_SHOWN" = "$SP5_SHOWN" ] && [ "$MCP_SP_SHOWN" -ge 4 ]; } \
    && ok "8.7b family: MCP memory_recall spreads identically to the CLI (shown=$MCP_SP_SHOWN on both doors)" \
    || no "8.7b family: MCP memory_recall shown=$MCP_SP_SHOWN vs CLI shown=$SP5_SHOWN (both must be >=4) — the two doors do not share the allocator"

# 8.8 determinism of the spread allocation (it is arithmetic over a sorted list; nothing may make it drift)
srun --max-tokens=5000 > "$TMP/sp5b.out"
cmp -s "$TMP/sp5.out" "$TMP/sp5b.out" \
    && ok "8.8 spread allocation is deterministic (byte-identical run to run)" \
    || no "8.8 spread allocation is NOT deterministic"

# 8.9 monotonicity: a bigger budget may never return FEWER documents, AND somewhere on the scale it must
# buy an additional one. This is what made the defect so hard to see from the outside — 2000, 5000 and 8000
# tokens all returned exactly one document, so the flag looked like it was working (the artifact really did
# grow) while the answer's SHAPE never moved. The low point is 400 tokens deliberately: too small for even
# one readable share, so it exercises the last-resort floor at the same time (one document, not zero).
srun --max-tokens=400  > "$TMP/sp04.out"
srun --max-tokens=2000 > "$TMP/sp2.out"
SP04_SHOWN="$( shown_of "$TMP/sp04.out" )"; SP2_SHOWN="$( shown_of "$TMP/sp2.out" )"
{ [ -n "$SP04_SHOWN" ] && [ -n "$SP2_SHOWN" ] && [ "$SP04_SHOWN" -ge 1 ] && [ "$SP04_SHOWN" -le "$SP2_SHOWN" ] \
      && [ "$SP2_SHOWN" -le "$SP5_SHOWN" ] && [ "$SP5_SHOWN" -gt "$SP04_SHOWN" ]; } \
    && ok "8.9 monotone in the budget: shown=$SP04_SHOWN (400) <= $SP2_SHOWN (2K) <= $SP5_SHOWN (5K), and 5K > 400" \
    || no "8.9 not monotone in the budget: shown=$SP04_SHOWN (400) / $SP2_SHOWN (2K) / $SP5_SHOWN (5K) — a bigger budget bought no additional document (or a starved one served none)"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
