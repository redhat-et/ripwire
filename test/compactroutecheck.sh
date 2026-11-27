#!/usr/bin/env bash
# compactroutecheck.sh — COMPACT CONCEPTUAL SERVING (pre-registered: docs/EVALS.md, the T3
# route-narrowing round).
#
# The contract, in one sentence: on the CONCEPTUAL route — a `--for` query the router sends to the
# subtoken+body ranker, the route that names no anchor — the default bundle serves the ranked map plus
# the candidate head's ONE-HOP EDGE CONTEXT and NO bodies, discloses that it did, and names the
# continuation that gets a body. Everywhere else nothing moves.
#
# Arms:
#   1) CONCEPTUAL DEFAULT IS COMPACT: zero <b> body blocks, no <bodies> section, and the <ctx> root
#      says bundle="compact" bodies="0" reason="compact-route".
#   2) THE EDGE CONTEXT IS REAL: a <hops shown= total= capped=> section (pageview.h's rule-1/2/3 triple,
#      like <bodies>) carrying at least one <h> row whose <calls> child holds at least one <c> callee
#      signature. An empty shell would satisfy arm 1 and answer nothing — this is the arm that stops
#      "compact" from meaning "signatures-only wearing a new name".
#   3) THE CONTINUATION IS DISCLOSED: the legend defines the three root attributes a reader meets
#      (bundle/bodies/reason) AND names the expand verb, so map-then-expand is a surface, not a guess.
#   4) NAME-EXACT UNTOUCHED: a name-exact query still serves its anchor's own body inline under
#      bundle="auto", and never emits <hops>.
#   5) THE OPT-OUT RESTORES: --auto-bodies on the conceptual query brings back the rank-first body walk
#      (bundle="auto", 2+ bodies, no <hops>) — and refuses loudly without --for, with --signatures-only,
#      and with --detail=N.
#   6) --signatures-only STILL OPTS ALL THE WAY OUT on this route: no bundle= attribute, no <bodies>,
#      no <hops> — the pre-T3 shape, unchanged by this round.
#   7) --no-route IS NOT COMPACT: with routing off there is no route decision to condition on, and the
#      un-routed path's golden neutrality (src/main.cpp) still holds.
#   8) deterministic (x3 byte-identical) and xmllint-clean (G4) in both the compact and opt-out shapes.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/compactroutecheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
cd "$ROOT"
echo "compactroutecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# for-body-slot (train 28; rule 4, by design): the question no longer opens with "how are" — an explanatory cue now carries
# ONE owner body beside the hops (forbodyslotcheck owns that contract; arm (1d) below reads the cue form). The compact
# contract pinned here is the conceptual route WITHOUT that cue, the same words otherwise.
CONC="identifiers split into subtokens for ranking"   # multi-word, no word is a whole symbol name, no explanatory cue
CONC_CUE="how are identifiers split into subtokens for ranking"
NAME="pageRankDouble"                                          # name-exact: a small, stable anchor

rw(){ "$BIN" src --no-cache "$@" 2>/dev/null; }
# body-fold (train 31; rule 4, by design): the compact answer now ENDS with <fold kind="bodies">, the top ranked bodies appended
# after the unchanged answer (forbodyfoldcheck owns that contract). The compact contract pinned here is the answer BEFORE the fold:
# bodycount reads it without the <fold> element, and arm (1e) pins the old whole-answer reading on the fold-off twin.
bodycount(){ python3 -c 'import re,sys; t=open(sys.argv[1]).read(); print(len(re.findall(r"<b t=", re.sub(r"<fold .*?</fold>", "", t, flags=re.S))))' "$1"; }

# L1 (2026-09-19): the CLI default legend is compact; arm (3) reads the FULL legend's prose (concfull), and arm (6) greps
# sigonly for bundle= which the compact legend spells inside its comment — both ask for the full legend.
# AF1-fix (2026-11-18): the default --for answer is served in 12 KB PAGES (src/forpages.h), and on src this compact answer's
# <hops> and <fold> start past page 1's cut (its 12 KB of <sigs>/<tail> rows come first). Every arm below is about the
# ANSWER's content, so it reads --page-bytes=0, the whole answer in one call — row-identical to the joined pages
# (forpagescheck P2). Arm (P) holds the DEFAULT page to present-or-disclosed-deferred for both sections.
rw --for="$CONC"                  >"$TMP/concpage"
rw --for="$CONC" --page-bytes=0   >"$TMP/conc"
rw --for="$CONC" --legend=full    >"$TMP/concfull"
rw --for="$CONC" --auto-bodies --page-bytes=0 >"$TMP/optout"
rw --for="$CONC" --signatures-only --legend=full >"$TMP/sigonly"
rw --for="$CONC" --no-route       >"$TMP/noroute"
rw --for="$NAME"                  >"$TMP/name"

# ── (0) presence guards: the two routes really are the two routes ───────────────────────────────────────
grep -q 'anchors: ' "$TMP/conc" \
    && no "(0) the conceptual query routed name-exact — re-author it, every arm below is unobservable" \
    || ok "(0) the conceptual query routes subtoken+body (names no anchor)"
grep -q 'anchors: ' "$TMP/name" \
    && ok "(0b) the name-exact query does name an anchor" \
    || no "(0b) no anchors: clause on $NAME — arm 4 cannot observe the route it is about"

# ── (P) the default PAGE: each section it does not hold is named on its root (deferred=/continued=) beside a next= ──────
for SEC in hops fold; do
    if grep -q "<$SEC " "$TMP/concpage"; then ok "(P) the default page carries <$SEC>"
    elif python3 -c 'import re,sys; r=re.match(r"<ctx\b[^>]*>",open(sys.argv[1]).read()); r=r.group(0) if r else ""; n=" ".join(re.findall(r"\s(?:deferred|continued)=\"([^\"]*)\"",r)).split(); sys.exit(0 if sys.argv[2] in n and " next=" in r else 1)' "$TMP/concpage" "$SEC"; then
        ok "(P) the default page does not hold <$SEC> and says so: deferred= names it, next= reaches it"
    else no "(P) the default page neither carries <$SEC> nor names it in deferred=/continued= (a silent drop)"; fi
done
grep -q 'bundle="compact" bodies="0" reason="compact-route"' "$TMP/concpage" \
    && ok '(P) the default page keeps the whole answer'"'"'s bundle="compact" bodies="0" reason="compact-route" root disclosure' \
    || no '(P) the default page lost the bundle= bodies= reason= root disclosure'

# ── (1) the conceptual default is compact, and says so ──────────────────────────────────────────────────
[ "$( bodycount "$TMP/conc" )" = "0" ] \
    && ok "(1) zero <b> body blocks on the conceptual route" \
    || no "(1) $( bodycount "$TMP/conc" ) body block(s) served on the conceptual route — the default is not compact"
grep -q '<bodies ' "$TMP/conc" \
    && no "(1b) a <bodies> section is still emitted on the conceptual route" \
    || ok "(1b) no <bodies> section on the conceptual route"
grep -q 'bundle="compact" bodies="0" reason="compact-route"' "$TMP/conc" \
    && ok '(1c) the root discloses bundle="compact" bodies="0" reason="compact-route"' \
    || no '(1c) missing the bundle="compact" bodies="0" reason="compact-route" disclosure (every removal is disclosed)'
RIPWIRE_NO_BODY_FOLD=1 "$BIN" src --no-cache --for="$CONC" --page-bytes=0 2>/dev/null >"$TMP/concoff"
if [ "$( grep -o '<b t=' "$TMP/concoff" | wc -l | tr -d ' ' )" = "0" ] && grep -q '<fold ' "$TMP/conc"; then
    ok "(1e) fold-off twin: zero <b> in the whole answer; the default carries its bodies only inside <fold>"
else
    no "(1e) RIPWIRE_NO_BODY_FOLD=1 still serves a body, or the default carries no <fold>"
fi
rw --for="$CONC_CUE" --page-bytes=0 >"$TMP/conccue"
n_cue="$( bodycount "$TMP/conccue" )"
if grep -q '<sigs' "$TMP/conccue" && { { [ "$n_cue" = 1 ] && grep -q 'bundle="compact" bodies="1" reason="owner"' "$TMP/conccue"; } \
       || { [ "$n_cue" = 0 ] && grep -q 'bundle="compact" bodies="0" reason="compact-route"' "$TMP/conccue"; }; }; then
    ok "(1d) with an explanatory cue the compact route carries at most ONE body (the owner's, reason=owner): $n_cue"
else
    no "(1d) the explanatory-cue form served $n_cue body block(s) without the owner disclosure"
fi

# ── (2) the one-hop edge context is really served ───────────────────────────────────────────────────────
grep -qE '<hops shown="[0-9]+" total="[0-9]+" capped="[01]"( noedge="[0-9]+")?>' "$TMP/conc" \
    && ok "(2) <hops shown= total= capped=> present with the rule-1/2/3 triple" \
    || no "(2) <hops> missing or malformed — the compact route must still carry the edge context"
HSHOWN=$( grep -o '<hops shown="[0-9]*"' "$TMP/conc" | head -1 | sed -E 's/.*shown="([0-9]*)"/\1/' )
HROWS=$( grep -o '<h l=' "$TMP/conc" | wc -l | tr -d ' ' )
{ [ -n "${HSHOWN:-}" ] && [ "$HSHOWN" -ge 1 ] && [ "$HSHOWN" = "$HROWS" ]; } \
    && ok "(2b) shown=\"$HSHOWN\" is arithmetic — it equals the $HROWS <h> rows actually emitted" \
    || no "(2b) shown=\"${HSHOWN:-}\" disagrees with the $HROWS emitted <h> rows (the disclosure must be arithmetic)"
grep -q '<h [^>]*><calls total="[0-9]*"[^>]*><c n=' "$TMP/conc" \
    && ok "(2c) at least one <h> row carries a real <calls> list naming a callee" \
    || no "(2c) no <h> row names any callee — an empty shell is not edge context"

# ── (3) the continuation is a disclosed surface, not a guess ────────────────────────────────────────────
# the LEADING comment block — the legend the reader actually meets first. Extracted with python3, not
# sed: the document is one minified line only until a CDATA body introduces newlines, and sed's per-line
# model then walks the extraction straight into the source code (a real red-first false negative here).
LEGEND="$( python3 -c 'import sys
s=open(sys.argv[1],encoding="utf-8",errors="replace").read()
a=s.find("<!--"); b=s.find("-->",a)
sys.stdout.write(s[a+4:b] if a>=0 and b>=0 else "")' "$TMP/concfull" )"
for A in 'bundle=' 'bodies=' 'reason=' 'hops' 'calls'; do
    case "$LEGEND" in
        *"$A"*) ok "(3) the legend defines/names '$A'" ;;
        *)      no "(3) the legend never mentions '$A' — a first-screen attribute with no definition" ;;
    esac
done
case "$LEGEND" in
    *expand*) ok "(3b) the legend names the expand continuation" ;;
    *)        no "(3b) the legend does not name the continuation — the agent has to guess how to get a body" ;;
esac
# a literal "--flag" inside an XML comment is ill-formed (G4); the legend must not spell one
case "$LEGEND" in
    *--*) no "(3c) the legend contains '--' — ill-formed inside an XML comment" ;;
    *)    ok "(3c) the legend spells no '--' (XML-comment safe)" ;;
esac

# ── (4) the name-exact route is untouched ───────────────────────────────────────────────────────────────
grep -q '<hops ' "$TMP/name" \
    && no "(4) the name-exact route emitted <hops> — compact leaked past the conceptual route" \
    || ok "(4) no <hops> on the name-exact route"
{ grep -q 'bundle="auto" bodies="1"' "$TMP/name" && grep -q "<b [^>]*n=\"$NAME\"[^>]*><!\[CDATA\[" "$TMP/name"; } \
    && ok "(4b) the name-exact route still serves the anchor's own body inline under bundle=\"auto\"" \
    || no "(4b) the name-exact route lost its anchor body or its bundle=\"auto\" disclosure"

# ── (5) the opt-out restores today's behaviour, and is guarded ──────────────────────────────────────────
OB=$( bodycount "$TMP/optout" )
{ [ "$OB" -ge 2 ] && grep -q "bundle=\"auto\" bodies=\"$OB\"" "$TMP/optout" && ! grep -q '<hops ' "$TMP/optout"; } \
    && ok "(5) --auto-bodies restores the rank-first walk on the conceptual route ($OB bodies, bundle=\"auto\", no <hops>)" \
    || no "(5) --auto-bodies did not restore the auto bundle (bodies=$OB)"
"$BIN" src --auto-bodies --no-cache >/dev/null 2>"$TMP/e1"; rc=$?
{ [ "$rc" != 0 ] && grep -qi 'auto-bodies' "$TMP/e1" && ! grep -qi 'unknown flag' "$TMP/e1"; } \
    && ok "(5b) --auto-bodies without --for refuses loudly" \
    || no "(5b) --auto-bodies without --for did not refuse (rc=$rc)"
"$BIN" src --for="$CONC" --auto-bodies --signatures-only --no-cache >/dev/null 2>"$TMP/e2"; rc=$?
{ [ "$rc" != 0 ] && grep -qi 'auto-bodies' "$TMP/e2" && ! grep -qi 'unknown flag' "$TMP/e2"; } \
    && ok "(5c) --auto-bodies + --signatures-only refuses loudly (contradictory)" \
    || no "(5c) --auto-bodies + --signatures-only did not refuse (rc=$rc)"
"$BIN" src --for="$CONC" --auto-bodies --detail=3 --no-cache >/dev/null 2>"$TMP/e3"; rc=$?
{ [ "$rc" != 0 ] && grep -qi 'auto-bodies' "$TMP/e3" && ! grep -qi 'unknown flag' "$TMP/e3"; } \
    && ok "(5d) --auto-bodies + --detail=N refuses loudly (--detail is the explicit body knob)" \
    || no "(5d) --auto-bodies + --detail=N did not refuse (rc=$rc)"

# ── (6) --signatures-only still opts all the way out on this route ──────────────────────────────────────
{ ! grep -q 'bundle=' "$TMP/sigonly" && ! grep -q '<bodies ' "$TMP/sigonly" && ! grep -q '<hops ' "$TMP/sigonly"; } \
    && ok "(6) --signatures-only keeps the pre-T3 shape on the conceptual route (no bundle=, no <bodies>, no <hops>)" \
    || no "(6) --signatures-only no longer restores the signatures-only bundle on this route"

# ── (7) --no-route is not compact ───────────────────────────────────────────────────────────────────────
{ ! grep -q '<hops ' "$TMP/noroute" && ! grep -q 'bundle="compact"' "$TMP/noroute"; } \
    && ok "(7) --no-route is not compact — no route decision, so nothing to condition on" \
    || no "(7) --no-route went compact: the un-routed path's golden neutrality is broken"

# ── (8) determinism + well-formedness ───────────────────────────────────────────────────────────────────
for V in conc concpage optout sigonly noroute name; do
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$TMP/$V" 2>/dev/null \
            && ok "(8) $V is well-formed XML" \
            || no "(8) $V failed xmllint"
    fi
done
rw --for="$CONC" >"$TMP/d2"; rw --for="$CONC" >"$TMP/d3"
{ cmp -s "$TMP/concpage" "$TMP/d2" && cmp -s "$TMP/concpage" "$TMP/d3"; } \
    && ok "(8b) the compact bundle is byte-identical across 3 runs" \
    || no "(8b) the compact bundle is not deterministic"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES PRESENT"; exit 1
