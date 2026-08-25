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
#   (f1) THE THING THE DEFECT COSTS — the plain --for=Widget bundle SERVES the definition in its ranked
#       rows, where before the fix all it served was two copies of the name.
#   (f2) THE ANCHOR-SIDE HALF — the auto-body slot is fed by the ROUTER's anchor, not by the ranking, so
#       it was a second site of the same defect. Closed by the anchor-body round (2026-08-25): this arm
#       was FLIPPED, deliberately and inside that round's registration, from pinning the declaration to
#       pinning the definition. It is the tripwire the def-over-decl round left armed for exactly this.
#   (f3) THE ANCHOR, AND WHAT MUST NOT MOVE WITH IT — the disclosed anchor path follows the definition
#       while the "+N" ambiguity count stays put. The rule writes fileId and nothing else.
#   (f4) INERT-BRANCH CONTROL — --for=Cog: the first definition in NodeId order already carries a body,
#       so there is nothing to prefer and nothing may move. The fixture twin of the registration's
#       unreachable N04/N07 rows, where an out-of-line constructor holds the claim.
#   (f5) NO-BODY-ANYWHERE CONTROL — --for=Sprocket: nothing defines it, so the first-in-NodeId anchor
#       stands exactly as before. A rule that demoted bodyless claimants unconditionally empties this.
#   (f6) UNIQUE-DEFINITION INVARIANCE — --for=Gadget: one definition, no second claimant, byte-stable
#       anchor. This is the registered criterion that outranks the round's own band.
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

# ── (f1) THE THING THE DEFECT COSTS: the definition is actually SERVED ────────────────────────────
"$BIN" defoverdeclfix --for=Widget >"$TMP/lens" 2>/dev/null
# The assertion is on the FIRST ranked row, not on mere presence. This fixture is small enough that
# every Widget row fits in the bundle either way, so a presence check would be inert here — and an
# inert arm in a gate written for a ranking change is the failure mode this suite has been bitten by
# twice. The first row is also the one that survives every budget: it is what the defect actually
# costs on a corpus where 85 declarations push the definition off the end.
first="$( tr '>' '\n' <"$TMP/lens" | sed -n 's/.*<d l="\([0-9]*\)" n="Widget" id="\([^"]*\)".*/\2:\1/p' | sed 's#defoverdeclfix/##' | head -1 )"
[ "$first" = "z_widget.hpp::Widget::Widget:10" ] \
    && ok "the FIRST ranked row is the definition (z_widget.hpp:10) — the row that survives any budget" \
    || no "the first ranked row is $first, not the definition z_widget.hpp::Widget::Widget:10"

# ── (f2) THE ANCHOR-SIDE HALF, pinned to the FIXED behaviour (registered 2026-08-25) ──────────────
#    This arm used to pin the OPPOSITE, and the flip is deliberate. The def-over-decl round moved six
#    golds into the ranked rows and not one into <bodies>, because the body that rides on a name-exact
#    --for is chosen from the ROUTER's anchor and not from the ranking: NameAnchor::fileId was "the
#    FIRST definition of this name in NodeId order", i.e. path order, so it landed on a forward
#    declaration for exactly the reason the ranking used to. That round declined to fix a second site
#    it had not registered, and left this arm asserting `a_headers.hpp:12` so that fixing it would go
#    RED and be acknowledged rather than absorbed. The anchor-body round (docs/EVALS.md §4) is that
#    acknowledgement: the anchor is claimed by the first BODY-CARRYING definition, so the body served
#    is the real one and the ranked rows and the bodies finally name the same symbol.
body="$( tr '>' '\n' <"$TMP/lens" | sed -n 's/.*<b t="[^"]*" l="\([0-9]*\)" p="\([^"]*\)".*/\2:\1/p' | head -1 | sed 's#defoverdeclfix/##' )"
case "$body" in
    z_widget.hpp:10)  ok "the auto-body slot serves the DEFINITION ($body) — ranked rows and bodies agree" ;;
    a_headers.hpp:12) no "the auto-body slot is back on the declaration ($body) — the anchor-side rule is not in effect" ;;
    "")               no "no body was emitted at all for --for=Widget" ;;
    *)                no "the auto-body slot moved to an unexpected symbol ($body)" ;;
esac

# ── (f3) THE ANCHOR ITSELF, and the count that must NOT move with it ──────────────────────────────
# The rule writes NameAnchor::fileId and nothing else, so the disclosed path moves to the definition
# while the "+N" ambiguity count — extraDefs, four Widget definitions minus the claimant — stays 3.
# A "+N" that moved would mean the rule had rewritten the anchor's own disclosure, not just its choice.
anchor="$( sed -n 's/.*anchors: Widget(\([^)]*\)).*/\1/p' "$TMP/lens" | head -1 )"
[ "$anchor" = "defoverdeclfix/z_widget.hpp+3" ] \
    && ok "the disclosed anchor is the definition, ambiguity count intact (anchors: Widget($anchor))" \
    || no "anchors: Widget($anchor) — expected defoverdeclfix/z_widget.hpp+3"

# ── (f4) INERT-BRANCH CONTROL: a claimant that ALREADY carries a body keeps the anchor ─────────────
# zy_cog.hpp DEFINES Cog and sorts before zz_cog_fwd.hpp, which re-declares it. The first definition
# in NodeId order is therefore already body-carrying and the rule has nothing to prefer. This is the
# fixture form of the registration's unreachable rows N04/N07, where an out-of-line constructor in a
# .cpp sorts ahead of the class in the header and already holds the claim — those two bundles are
# byte-pinned on the real corpora and this arm is their local twin. An implementation that prefers the
# LAST definition, or the highest-RANKED one, or a `cls` over a `method`, goes red here.
"$BIN" defoverdeclfix --for=Cog >"$TMP/cog" 2>/dev/null
cogan="$( sed -n 's/.*anchors: Cog(\([^)]*\)).*/\1/p' "$TMP/cog" | head -1 )"
cogbody="$( tr '>' '\n' <"$TMP/cog" | sed -n 's/.*<b t="[^"]*" l="\([0-9]*\)" p="\([^"]*\)".*/\2:\1/p' | head -1 | sed 's#defoverdeclfix/##' )"
[ "$cogan" = "defoverdeclfix/zy_cog.hpp+2" ] && [ "$cogbody" = "zy_cog.hpp:14" ] \
    && ok "a first-in-NodeId claimant that already carries a body keeps the anchor (Cog: $cogan, body $cogbody)" \
    || no "--for=Cog moved: anchor=$cogan body=$cogbody — expected defoverdeclfix/zy_cog.hpp+2 and zy_cog.hpp:14"

# ── (f5) NO-BODY-ANYWHERE CONTROL: the fallback is the OLD behaviour, unchanged ────────────────────
# Sprocket is declared twice and defined nowhere, so no claimant carries a body and the rule must
# leave the first-in-NodeId choice exactly as it was. A rule that demoted bodyless claimants
# unconditionally would leave this query with no anchor and no body at all.
"$BIN" defoverdeclfix --for=Sprocket >"$TMP/spr" 2>/dev/null
spran="$( sed -n 's/.*anchors: Sprocket(\([^)]*\)).*/\1/p' "$TMP/spr" | head -1 )"
sprbody="$( tr '>' '\n' <"$TMP/spr" | sed -n 's/.*<b t="[^"]*" l="\([0-9]*\)" p="\([^"]*\)".*/\2:\1/p' | head -1 | sed 's#defoverdeclfix/##' )"
[ "$spran" = "defoverdeclfix/a_headers.hpp+1" ] && [ "$sprbody" = "a_headers.hpp:21" ] \
    && ok "a name no definition gives a body to keeps its first-in-NodeId anchor (Sprocket: $spran)" \
    || no "--for=Sprocket moved: anchor=$spran body=$sprbody — expected defoverdeclfix/a_headers.hpp+1 and a_headers.hpp:21"

# ── (f6) UNIQUE-DEFINITION INVARIANCE — the registered criterion that outranks the band ────────────
# Gadget is declared once and nowhere else. There is no second claimant, so nothing about this query
# can reach the rule and its anchor must be identical to what the pre-rule binary printed, "+N" and
# all — Gadget has no "+N" at all, one definition and no disclosed ambiguity.
"$BIN" defoverdeclfix --for=Gadget >"$TMP/gad" 2>/dev/null
gadan="$( sed -n 's/.*anchors: Gadget(\([^)]*\)).*/\1/p' "$TMP/gad" | head -1 )"
gadbody="$( tr '>' '\n' <"$TMP/gad" | sed -n 's/.*<b t="[^"]*" l="\([0-9]*\)" p="\([^"]*\)".*/\2:\1/p' | head -1 | sed 's#defoverdeclfix/##' )"
[ "$gadan" = "defoverdeclfix/a_headers.hpp" ] && [ "$gadbody" = "a_headers.hpp:17" ] \
    && ok "a UNIQUE definition anchors exactly where it did (Gadget: $gadan, body $gadbody)" \
    || no "--for=Gadget moved: anchor=$gadan body=$gadbody — expected defoverdeclfix/a_headers.hpp and a_headers.hpp:17"

# ── (g) C13 ANALOGUE / OFF-ROUTE INVARIANCE ───────────────────────────────────────────────────────
# Growth's C13 in local form. The conceptual route is a different entry point (lexicalScoresTiered)
# and neither the ranking rule nor the anchor rule must reach it, so the order below is pinned exactly
# as the PRE-rule binary emits it. Scores are distinct here, so nothing in this arm is a tie: any
# movement means a rule leaked.
#
# RE-DERIVED 2026-08-25, and the reason is worth stating rather than hiding in a diff. The anchor-body
# round added zy_cog.hpp / zz_cog_fwd.hpp for arm (f4). Two more documents change BM25's corpus
# statistics for every query over this fixture, and `Gadget` moved from position 3 to position 5 —
# ON THE PRE-RULE BINARY, before a line of the anchor rule existed. So the order below was re-taken
# from that same pre-rule binary against the GROWN fixture and then verified invariant across the
# rule. A pin re-derived on the binary under test would be worthless; this one was not.
CQ="forward declared widget and sprocket types"
"$BIN" defoverdeclfix --for="$CQ" 2>/dev/null | grep -q 'routed: subtoken+body' \
    && ok "the declaration-seeking conceptual query still routes subtoken+body" \
    || no "the declaration-seeking conceptual query changed route"
want='a_headers.hpp::Sprocket::Sprocket
m_more.hpp::Sprocket::Sprocket
m_more.hpp::Widget::Widget
a_headers.hpp::Widget::Widget
a_headers.hpp::Gadget::Gadget'
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
