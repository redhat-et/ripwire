#!/usr/bin/env bash
# defoverdeclcheck.sh — the definition-over-declaration tiebreak on the NAME-EXACT route.
#
#   test/defoverdeclcheck.sh                         # uses build/ripwire on test/defoverdeclfix
#   RIPWIRE_BIN=asan/ripwire test/defoverdeclcheck.sh
#
# THE DEFECT THIS PINS (docs/EVALS.md §4, "Definition-over-declaration tiebreak on the name-exact
# route"; upstream: the E6 demotion corpus's class-2b rows H18/H31 on duckdb and H22 on rocksdb).
# Whole-name BM25 scores a symbol against its NAME, so a bare `class Widget;` forward declaration and
# the real `class Widget { … }` definition are the same one-token document and score bit-for-bit
# identically. The tie then breaks on symbol id, i.e. crawl/path order — so in a header-heavy C++ tree
# the eighty-five headers that forward-declare a type fill every ranked row and every body slot with
# copies of the name the caller already typed, and the definition is never emitted at all.
#
# The fix is a TIEBREAK, not a score change and not a filter: inside an EXACT tie that holds both a
# body-carrying symbol and a bodyless one, the body-carrying ones sort first. Everything else about the
# ranking — every non-tied row, every other route — must be byte-identical, and that invariance is a
# registered criterion that outranks the round's own band. Hence the control arms below, which are the
# larger half of this gate: (c) and (d) fire if the rule is implemented as a blanket demotion of
# declarations, and (g) fires if it leaks off the name-exact route.
#
# ARMS
#   (a) RED-FIRST — --for=Widget: both definition rows outrank both bodyless declarations, all four
#       still at one score. This is the arm the fixture is built to fail before the fix exists.
#   (b) REORDER, NOT FILTER — both declarations survive in the export, in their original order.
#   (c) NO-TIE DECLARATION CONTROL — --for=Gadget: a declaration whose name nothing defines is not
#       demoted; it stays rank 1. (A blanket "declarations lose" rule goes red here.)
#   (d) ALL-DECLARATION TIE CONTROL — --for=Sprocket: a tie with no body-carrying member is not
#       touched, and the two declarations keep their id-ascending order.
#   (e) ROUTE SCOPE — all three name queries actually take the name-exact route, so the arms above are
#       measuring the route the rule is scoped to.
#   (f) THE THING THE DEFECT COSTS — the plain --for=Widget bundle's body slot holds the DEFINITION.
#       Before the fix its entire content is the bodyless `class Widget` from a_headers.hpp.
#   (g) C13 ANALOGUE / OFF-ROUTE INVARIANCE — a CONCEPTUAL query that explicitly asks for forward
#       declarations still gets them, in the exact subtoken+body order it had before the rule existed.
#       This is the local form of growth's C13, the armed kill tripwire the E6 round left behind for
#       precisely this change: an unconditional bodyless demotion empties those slots.
#   (h) determinism — two runs byte-identical.
#
# The fixture is copied to a tmp dir OUTSIDE any git repo and scanned via a RELATIVE path, so no churn
# or co-change attribute and no absolute path can reach the assertions.
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "defoverdeclcheck: BIN=$BIN"

mkdir -p "$TMP/defoverdeclfix"
cp "$ROOT"/test/defoverdeclfix/*.hpp "$TMP/defoverdeclfix/"
cd "$TMP"

# candidate ids, one per line, rank order: "<file>::<scope>::<name>"
cands(){ "$BIN" defoverdeclfix --for="$1" --format=candidates --top-k="$2" 2>/dev/null \
    | tr '>' '\n' | sed -n 's/.*<cand r="[0-9]*" s="\([^"]*\)" n="[^"]*" id="\([^"]*\)".*/\1 \2/p' \
    | sed 's#defoverdeclfix/##'; }

# ── (a) RED-FIRST: the definitions take the tie ───────────────────────────────────────────────────
W="$( cands Widget 4 )"
w1="$( printf '%s\n' "$W" | sed -n 1p | awk '{print $2}' )"
w2="$( printf '%s\n' "$W" | sed -n 2p | awk '{print $2}' )"
w3="$( printf '%s\n' "$W" | sed -n 3p | awk '{print $2}' )"
w4="$( printf '%s\n' "$W" | sed -n 4p | awk '{print $2}' )"
case "$w1$w2" in
    z_widget.hpp*z_widget.hpp*) ok "name-exact tie: both z_widget.hpp DEFINITIONS rank above the declarations (1:$w1 2:$w2)" ;;
    *) no "name-exact tie: rank 1/2 are not the definitions — got 1:$w1 2:$w2 (the def-over-decl tiebreak is not in effect)" ;;
esac

# the tie is real: all four Widget rows must still carry ONE score. If they do not, something changed
# the SCORES rather than their order, which is the thing this round registered it would not do.
wscores="$( printf '%s\n' "$W" | awk '{print $1}' | sort -u | wc -l | tr -d ' ' )"
[ "$wscores" = "1" ] \
    && ok "the four Widget rows still report a single score — a tiebreak, not a score change" \
    || no "the four Widget rows report $wscores distinct scores — the tie was broken by RESCORING, not by ordering"

# ── (b) REORDER, NOT FILTER ───────────────────────────────────────────────────────────────────────
if [ "$w3" = "a_headers.hpp::Widget::Widget" ] && [ "$w4" = "m_more.hpp::Widget::Widget" ]; then
    ok "both declarations survive, in their original id-ascending order (3:$w3 4:$w4)"
else
    no "declarations were dropped or reordered among themselves — got 3:$w3 4:$w4"
fi

# ── (c) NO-TIE DECLARATION CONTROL ────────────────────────────────────────────────────────────────
g1="$( cands Gadget 1 | sed -n 1p | awk '{print $2}' )"
[ "$g1" = "a_headers.hpp::Gadget::Gadget" ] \
    && ok "a declaration nothing defines keeps rank 1 (--for=Gadget)" \
    || no "--for=Gadget no longer ranks its only declaration first (got $g1) — the rule is demoting declarations unconditionally"

# ── (d) ALL-DECLARATION TIE CONTROL ───────────────────────────────────────────────────────────────
s1="$( cands Sprocket 2 | sed -n 1p | awk '{print $2}' )"
s2="$( cands Sprocket 2 | sed -n 2p | awk '{print $2}' )"
if [ "$s1" = "a_headers.hpp::Sprocket::Sprocket" ] && [ "$s2" = "m_more.hpp::Sprocket::Sprocket" ]; then
    ok "a tie with no body-carrying member is left alone, id order intact (--for=Sprocket)"
else
    no "--for=Sprocket reordered an all-declaration tie — got 1:$s1 2:$s2"
fi

# ── (e) ROUTE SCOPE ───────────────────────────────────────────────────────────────────────────────
for q in Widget Gadget Sprocket; do
    "$BIN" defoverdeclfix --for="$q" 2>/dev/null | grep -q 'routed: name-exact' \
        && ok "--for=$q takes the name-exact route (the route this rule is scoped to)" \
        || no "--for=$q no longer routes name-exact — the arms above are measuring the wrong ranker"
done

# ── (f) THE THING THE DEFECT COSTS: the body slot holds the definition ────────────────────────────
"$BIN" defoverdeclfix --for=Widget >"$TMP/lens" 2>/dev/null
body="$( tr '>' '\n' <"$TMP/lens" | sed -n 's/.*<b t="[^"]*" l="\([0-9]*\)" p="\([^"]*\)".*/\2:\1/p' | head -1 )"
case "$body" in
    defoverdeclfix/z_widget.hpp:*|z_widget.hpp:*) ok "the emitted body is the DEFINITION ($body)" ;;
    "") no "no body was emitted at all for --for=Widget" ;;
    *)  no "the emitted body is a bodyless declaration ($body) — the class-2b defect, verbatim" ;;
esac

# ── (g) C13 ANALOGUE / OFF-ROUTE INVARIANCE ───────────────────────────────────────────────────────
# Growth's C13 in local form. The conceptual route is a different entry point (lexicalScoresTiered)
# and this rule must not reach it, so the order below is pinned exactly as the pre-rule binary emits
# it. Scores are distinct here, so nothing in this arm is a tie: any movement means the rule leaked.
CQ="forward declared widget and sprocket types"
"$BIN" defoverdeclfix --for="$CQ" 2>/dev/null | grep -q 'routed: subtoken+body' \
    && ok "the declaration-seeking conceptual query still routes subtoken+body" \
    || no "the declaration-seeking conceptual query changed route"
want='a_headers.hpp::Sprocket::Sprocket
m_more.hpp::Sprocket::Sprocket
a_headers.hpp::Gadget::Gadget
m_more.hpp::Widget::Widget
a_headers.hpp::Widget::Widget'
got="$( cands "$CQ" 5 | awk '{print $2}' )"
if [ "$got" = "$want" ]; then
    ok "C13 analogue: a query that asks for forward declarations still gets all five, in the pre-rule order"
else
    no "C13 analogue TRIPPED — the conceptual route's declaration rows moved:"
    printf '%s\n' "--- want ---" "$want" "--- got ---" "$got"
fi

# ── (h) determinism ───────────────────────────────────────────────────────────────────────────────
"$BIN" defoverdeclfix --for=Widget >"$TMP/d1" 2>/dev/null
"$BIN" defoverdeclfix --for=Widget >"$TMP/d2" 2>/dev/null
cmp -s "$TMP/d1" "$TMP/d2" \
    && ok "deterministic: two --for=Widget runs byte-identical" \
    || no "two --for=Widget runs differ"

[ "$fail" -eq 0 ] && echo "defoverdeclcheck: ALL PASS" || echo "defoverdeclcheck: FAILURES"
exit "$fail"
