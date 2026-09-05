#!/usr/bin/env bash
# prbudgetcheck.sh — A4-R4 lever 4: --pr-context respects --max-tokens by degrading
# gracefully, DEPTH-first, instead of emitting an unbounded payload (26.3K tokens on a 15-file diff was the
# measured worst case; a 213-file diff far worse).
#
# The contract this gate enforces:
#   1) UNBUDGETED (no --max-tokens) is byte-identical to the pre-budget output — no est_tokens/truncated attrs.
#   2) BUDGETED: the emitted est_tokens is <= the budget (unless even the structural floor overflows, in which
#      case truncated= says so honestly — then est may exceed and that's the honest ceiling).
#   3) EVERY changed file is still present structurally (same <file> count budgeted vs unbudgeted) — the budget
#      trims DEPTH per file, never drops a file.
#   4) truncated= is honest: "none" only when nothing was trimmed; a drop summary otherwise.
#   5) deterministic under a fixed budget; xmllint-clean.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/prbudgetcheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
cd "$ROOT"
echo "prbudgetcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# --pr-context needs a git diff. Wave-45 fix: the gate used to diff THIS repo's last commits, which
# made its "a large budget never truncates" assertion hostage to whatever landed most recently (a 7.6K-line
# bench-data merge legitimately trips the per-section list caps at any budget). Build a SCRATCH repo with a
# known, modest diff instead — the assertions below are about the budget machinery, not about this repo.
FIX="$TMP/fixrepo"; mkdir -p "$FIX/src"
( cd "$FIX" && git init -q && git config user.email t@t && git config user.name t )
for i in 1 2 3 4 5; do
    printf 'int helper%d( int v ) { return v + %d; }\nint caller%d() { return helper%d( %d ); }\n' \
           "$i" "$i" "$i" "$i" "$i" > "$FIX/src/mod$i.cpp"
done
( cd "$FIX" && git add -A >/dev/null && git commit -qm base )
for i in 1 2 3; do
    printf 'int helper%d( int v ) { return v * %d; }\nint caller%d() { return helper%d( %d ); }\nint extra%d() { return caller%d(); }\n' \
           "$i" "$i" "$i" "$i" "$i" "$i" "$i" > "$FIX/src/mod$i.cpp"
done
( cd "$FIX" && git add -A >/dev/null && git commit -qm change )
ROOT="$FIX"
BASE=HEAD~1

# helper: pull an attribute value out of the <pr-context …> open tag
attr(){ grep -oE "<pr-context[^>]*>" "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E "s/.*=\"([^\"]*)\"/\1/"; }
filecount(){ grep -o '<file ' "$1" | wc -l | tr -d ' '; }

# ── #0: the invocation itself must actually have worked — otherwise "no est_tokens=" and "0 changed
#    files" are both trivially true of EMPTY output from a broken/crashed binary, and every assertion
#    below it would pass (or SKIP) vacuously. Require the real success shape first: exit 0 and a
#    well-formed <pr-context> root tag (binoverridecheck.sh wave-4 item #10).
UNC_RC=0
"$BIN" "$ROOT" --pr-context="$BASE" --no-cache >"$TMP/unc" 2>"$TMP/unc.err" || UNC_RC=$?
if [ "$UNC_RC" -ne 0 ] || ! grep -q '<pr-context' "$TMP/unc"; then
    no "prbudgetcheck: --pr-context invocation failed or produced no <pr-context> root (rc=$UNC_RC) — $( tail -c 300 "$TMP/unc.err" )"
    exit "$fail"
fi

# ── #1: RE-PINNED 2026-09-05 (capture-audit P4, lane L7): a run with NO explicit budget is budgeted by DEFAULT
#    (src/prcontext.h kPrDefaultBudgetTokens = 8000) and says so — budget_tokens="8000" budget_default="1" plus the
#    est_tokens=/trim_level=/truncated= ledger every budgeted run carries. The pre-P4 contract ("unbudgeted ==
#    byte-identical to the pre-budget output") is what let a 217-file diff answer with 660 KB at exit 0. ──────────
UROOT="$( grep -oE '<pr-context [^>]*>' "$TMP/unc" | head -1 )"
case "$UROOT" in
    *'budget_tokens="8000"'*'budget_default="1"'*) ok "no explicit budget: the default 8000-token ceiling is in force and disclosed (budget_default=\"1\")";;
    *) no "no explicit budget: root lacks budget_tokens=\"8000\" budget_default=\"1\": $UROOT";;
esac
grep -q 'est_tokens=' "$TMP/unc" && ok "default-budget run carries the est_tokens=/truncated= ledger" || no "default-budget run carries no est_tokens="
UNC_FILES=$( filecount "$TMP/unc" )
[ "$UNC_FILES" -gt 0 ] || { echo "  SKIP  prbudgetcheck (no changed indexed files vs $BASE)"; exit 0; }

# ── #2: a LARGE budget fits at level 0: truncated="none", est<=budget, files all present ────────────────
"$BIN" "$ROOT" --pr-context="$BASE" --max-tokens=100000 --no-cache >"$TMP/big" 2>/dev/null
BE=$( attr "$TMP/big" est_tokens ); BT=$( attr "$TMP/big" truncated ); BF=$( filecount "$TMP/big" )
ALL_FILES=$( attr "$TMP/big" files )
{ [ -n "$BE" ] && [ "$BE" -le 100000 ] && [ "$BT" = "none" ] && [ "$BF" = "$ALL_FILES" ] && [ -z "$( attr "$TMP/big" budget_default )" ]; } \
    && ok "large budget: level 0, truncated=none, est=${BE}<=100000, all $BF files present, no budget_default=" \
    || no "large budget mishandled (est=$BE truncated=$BT files=$BF vs files=$ALL_FILES)"

# ── #3: SMALL budgets — est_tokens <= budget AND all files still present structurally ───────────────────
underok=1; filesok=1
for T in 20000 8000 4000 2000; do
    "$BIN" "$ROOT" --pr-context="$BASE" --max-tokens=$T --no-cache >"$TMP/c_$T" 2>/dev/null
    E=$( attr "$TMP/c_$T" est_tokens ); TR=$( attr "$TMP/c_$T" truncated ); FC=$( filecount "$TMP/c_$T" )
    # RE-PINNED (P4, L7): files are windowed ONLY when even the structural floor exceeds the budget, and then the
    # cut is disclosed — shown= (the plain quintet) equals the <file> count and capped="1" + next= ride the root.
    # Otherwise every changed file is present, as before.
    FS=$( attr "$TMP/c_$T" shown ); ALLF=$( attr "$TMP/c_$T" files )
    if [ "$FC" = "$ALLF" ]; then :;
    elif [ "$FC" = "$FS" ] && [ "$( attr "$TMP/c_$T" capped )" = 1 ] && grep -q ' next="--pr-context' "$TMP/c_$T"; then
        echo "    budget=$T: floor over budget — files windowed and disclosed (shown=$FS of $ALLF, next= present)";
    else echo "    budget=$T dropped files silently ($FC of $ALLF; shown='$FS' capped='$( attr "$TMP/c_$T" capped )')"; filesok=0; fi
    # est must be <= budget UNLESS the floor itself overflows (then truncated says budget-floor-exceeded)
    if [ -n "$E" ] && [ "$E" -le "$T" ]; then :;
    elif printf '%s' "$TR" | grep -q 'budget-floor-exceeded'; then :;   # honest floor overflow
    else echo "    budget=$T: est=$E > budget and no floor-exceeded marker (truncated=$TR)"; underok=0; fi
done
[ "$underok" = 1 ] && ok "budgeted est_tokens <= budget at every tested budget (or honest floor-exceeded)" \
    || no "a budgeted run exceeded its budget without the floor-exceeded marker"
[ "$filesok" = 1 ] && ok "every changed file present at every budget, or the file window disclosed (shown=/capped=1/next=) when the floor exceeded it" \
    || no "a budgeted run dropped a changed file SILENTLY (a cut must be disclosed with shown=/capped=1/next=)"

# ── #4: truncation marker HONEST — a trimmed run names a non-"none" drop; a level-0 run says "none" ─────
TT=$( attr "$TMP/c_2000" truncated ); TL=$( attr "$TMP/c_2000" trim_level )
if [ "$TL" = "0" ]; then
    [ "$TT" = "none" ] && ok "trim_level=0 reports truncated=none (honest)" || no "trim_level=0 but truncated=$TT (dishonest)"
else
    { [ -n "$TT" ] && [ "$TT" != "none" ]; } \
        && ok "trimmed run (trim_level=$TL) names what it dropped: truncated=\"$TT\"" \
        || no "trimmed run left truncated=\"$TT\" (must name the dropped detail)"
fi

# ── #5: DETERMINISM — a fixed budget is byte-identical run-to-run ───────────────────────────────────────
"$BIN" "$ROOT" --pr-context="$BASE" --max-tokens=4000 --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$ROOT" --pr-context="$BASE" --max-tokens=4000 --no-cache >"$TMP/d2" 2>/dev/null
diff -q "$TMP/d1" "$TMP/d2" >/dev/null && ok "budgeted --pr-context deterministic (byte-identical twice)" \
    || no "budgeted --pr-context NON-deterministic under a fixed budget"

# ── #6: monotonic — a smaller budget never emits MORE tokens than a larger one ──────────────────────────
E20=$( attr "$TMP/c_20000" est_tokens ); E2=$( attr "$TMP/c_2000" est_tokens )
{ [ -n "$E20" ] && [ -n "$E2" ] && [ "$E2" -le "$E20" ]; } \
    && ok "monotonic: est(2000-budget)=${E2} <= est(20000-budget)=${E20}" \
    || no "non-monotonic degradation (est went UP as budget dropped: $E2 vs $E20)"

# ── #7: xmllint-clean (budgeted + unbudgeted) ──────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    lint=1
    for F in "$TMP/unc" "$TMP/big" "$TMP/c_2000" "$TMP/c_4000"; do
        xmllint --noout "$F" 2>/dev/null || { echo "    malformed: $F"; lint=1; lint=0; }
    done
    [ "$lint" = 1 ] && ok "budgeted + unbudgeted --pr-context well-formed XML" || no "a --pr-context payload was malformed XML"
else
    printf '  SKIP  xmllint (not installed)\n'
fi

# ── #8 (F4, terminality round A 2026-09-05): the EMPTY-DIFF root carries the same budget tail ───────────
# --pr-context has three root emitters (empty diff / no-budget sub-bundle / budgeted) and the empty one was
# built inline from two attributes, so a clean tree answered
#   <pr-context base="working-tree" … files="0" skipped_mode_only="0" at=… >
# with NO budget_tokens=, est_tokens=, trim_level=, truncated= or budget_default= — the ledger every other
# root carries, missing in the one case a caller cannot otherwise tell apart from a crash. "Three call sites
# which must not drift on which disclosures they carry" is prRootOpenText's own header sentence; this arm is
# that sentence made mechanical. Derived, not hardcoded: the required set is the NON-EMPTY working-tree root's
# own attribute names, minus a DECLARED exemption list of the ones that exist only when there is a cut.
printf 'int probeEmptyRoot() { return 1; }\n' >> "$ROOT/src/mod4.cpp"
"$BIN" "$ROOT" --pr-context --no-cache >"$TMP/wt_dirty" 2>/dev/null
( cd "$ROOT" && git checkout -- src/mod4.cpp )
"$BIN" "$ROOT" --pr-context --no-cache >"$TMP/wt_clean" 2>/dev/null

rootattrs(){ grep -oE '<pr-context [^>]*>' "$1" | head -1 | grep -oE '[a-z_]+="' | sed 's/="$//' | LC_ALL=C sort -u; }
EXEMPT='^(shown|capped|total|has_more|next_offset|offset|limit|next)$'   # the page window: only when a cut happened

if [ "$( attr "$TMP/wt_dirty" files )" = "0" ] || [ "$( attr "$TMP/wt_clean" files )" != "0" ]; then
    no "(F4) the fixture did not produce a dirty root (files>0) AND a clean root (files=0): dirty=$( attr "$TMP/wt_dirty" files ) clean=$( attr "$TMP/wt_clean" files )"
else
    ok "(F4 fixture) same base (working-tree): one root with a change, one on a clean tree"
    MISSING="$( comm -23 <( rootattrs "$TMP/wt_dirty" ) <( rootattrs "$TMP/wt_clean" ) | grep -Ev "$EXEMPT" | tr '\n' ' ' )"
    [ -z "$MISSING" ] \
        && ok "(F4) the empty-diff root carries every attribute the non-empty root carries (bar the declared page-window set)" \
        || no "(F4) the empty-diff root is MISSING attributes the non-empty root carries: $MISSING"
    for a in budget_tokens est_tokens trim_level truncated budget_default; do
        [ -n "$( attr "$TMP/wt_clean" "$a" )" ] \
            && ok "(F4) empty-diff root carries $a=\"$( attr "$TMP/wt_clean" "$a" )\"" \
            || no "(F4) empty-diff root carries no $a= — the ledger every other --pr-context root carries"
    done
    EB="$( attr "$TMP/wt_clean" budget_tokens )"; EE="$( attr "$TMP/wt_clean" est_tokens )"
    { [ -n "$EB" ] && [ -n "$EE" ] && [ "$EE" -le "$EB" ]; } \
        && ok "(F4) empty-diff est_tokens=$EE is inside its own budget_tokens=$EB" \
        || no "(F4) empty-diff est_tokens='$EE' is not inside budget_tokens='$EB'"
    { [ "$( attr "$TMP/wt_clean" truncated )" = "none" ] && [ "$( attr "$TMP/wt_clean" trim_level )" = "0" ]; } \
        && ok "(F4) empty-diff root reports truncated=\"none\" trim_level=\"0\" (nothing was cut, and it says so)" \
        || no "(F4) empty-diff root claims a trim it did not make (trim_level=$( attr "$TMP/wt_clean" trim_level ) truncated=$( attr "$TMP/wt_clean" truncated ))"
    { [ -n "$EE" ] && [ "$EE" -gt 0 ]; } \
        && ok "(F4) empty-diff est_tokens is PRICED, not zero (the document still costs its legend)" \
        || no "(F4) empty-diff est_tokens is '$EE' — a document that ships a legend cannot cost nothing"
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$TMP/wt_clean" 2>/dev/null && ok "(F4) empty-diff --pr-context well-formed XML" || no "(F4) empty-diff --pr-context malformed XML"
    fi
fi

# ── #9 (V1 / wave-1 verifier R2+N4, 2026-09-05): est_tokens PRICES THE DOCUMENT --pr-context EMITS ──────
# F4 gave the empty-diff root the budget ledger, but the number in it was MODELLED, not priced: est_tokens
# came from ceil( (BODY bytes + a fixed 560-byte kPrHeaderOverheadBytes) / 2.36 ), and the ~4.7 KB legend
# that IS the document on a clean tree was outside both terms. Measured on ripwire's own tree at 044d4d0d:
#     empty-diff root      est_tokens=  278   emitted 4,808 B   = 17.3 B/tok   (7.3x UNDER)
#     budgeted root        est_tokens=5,969   emitted 18,271 B  =  3.1 B/tok   (1.30x under, N4)
# against --for, whose est_tokens x 2.50 recounts its delivered bytes exactly. A number that reads as the
# document's price and is 7x under it is exactly what non-negotiable #3 forbids, and it is read against
# budget_tokens="8000" by every caller that budgets the call.
#
# The property, family-wide over every --pr-context root that carries the attribute: est_tokens is the
# EMITTED byte count converted at the tool's ONE markup rate, kBytesPerTokenDefault = 2.50 B/tok
# (serialize.h tokensForEmittedBytes — the same conversion pricedRootAttr applies for --for, --pack-task,
# --handoff and MCP for). Asserted as a RECOUNT of the bytes on disk, not as a pinned number, so a later
# emitter that appends unpriced bytes reds this arm. Tolerance is 1 token: the conversion rounds to
# nearest, and the shell recount below rounds the same way, so anything larger is a real divergence.
RATE_LABEL='2.50 B/tok (kBytesPerTokenDefault)'
priced(){   # $1 label, $2 file
    local label="$1" f="$2" B E EXP D
    B=$( wc -c < "$f" | tr -d ' ' )
    E=$( attr "$f" est_tokens )
    if [ -z "$E" ] || [ "$B" = 0 ]; then
        no "(#9) $label: root carries no est_tokens= (or emitted nothing) — cannot recount its price"
        return
    fi
    EXP=$(( ( 4 * B + 5 ) / 10 ))            # round( B / 2.50 ), integer-only
    D=$(( E > EXP ? E - EXP : EXP - E ))
    if [ "$D" -le 1 ]; then
        ok "(#9) $label: est_tokens=$E prices the $B B it emitted at $RATE_LABEL (recount $EXP, delta $D)"
    else
        no "(#9) $label: est_tokens=$E but the document is $B B = $EXP tokens at $RATE_LABEL — off by $D (implied $(( B * 100 / E / 100 )).$(( B * 100 / E % 100 )) B/tok)"
    fi
}
priced "empty-diff root (clean tree)"          "$TMP/wt_clean"
priced "working-tree root (one changed file)"  "$TMP/wt_dirty"
priced "default-budget root (8000)"            "$TMP/unc"
priced "large-budget root (100000)"            "$TMP/big"
for T in 20000 8000 4000 2000; do
    priced "budgeted root (--max-tokens=$T)"   "$TMP/c_$T"
done

# and the legend must DEFINE the attribute the way the recount reads it — a definition that is true of the
# budgeted root and false of the empty one is the drift prRootOpenText exists to prevent (§B7 class).
if grep -q 'est_tokens= prices the WHOLE document this bundle emits' "$TMP/wt_clean" \
   && grep -q 'est_tokens= prices the WHOLE document this bundle emits' "$TMP/unc"; then
    ok "(#9) both roots' legends define est_tokens as the price of the emitted document"
else
    no "(#9) the legend does not define est_tokens as the price of the whole emitted document — the number and its definition disagree"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
