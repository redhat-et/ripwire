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

CONC="where are identifiers split into subtokens for ranking" # multi-word, no word is a whole symbol name
# fix #10: the "how" form of the same task takes the how answer (forhow.h), not the compact bundle — arms 1-8 run on
# the "where" twin above, and arm (9) asserts what the "how" form must still carry
CONC_HOW="how are identifiers split into subtokens for ranking"
NAME="pageRankDouble"                                          # name-exact: a small, stable anchor

rw(){ "$BIN" src --no-cache "$@" 2>/dev/null; }
bodycount(){ grep -o '<b t=' "$1" | wc -l | tr -d ' '; }

# L1 (2026-09-19): the CLI default legend is compact; arm (3) reads the FULL legend's prose (concfull), and arm (6) greps
# sigonly for bundle= which the compact legend spells inside its comment — both ask for the full legend.
rw --for="$CONC"                  >"$TMP/conc"
rw --for="$CONC" --legend=full    >"$TMP/concfull"
rw --for="$CONC" --auto-bodies    >"$TMP/optout"
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
for V in conc optout sigonly noroute name; do
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$TMP/$V" 2>/dev/null \
            && ok "(8) $V is well-formed XML" \
            || no "(8) $V failed xmllint"
    fi
done
rw --for="$CONC" >"$TMP/d2"; rw --for="$CONC" >"$TMP/d3"
{ cmp -s "$TMP/conc" "$TMP/d2" && cmp -s "$TMP/conc" "$TMP/d3"; } \
    && ok "(8b) the compact bundle is byte-identical across 3 runs" \
    || no "(8b) the compact bundle is not deterministic"

# ── (9) the "how" form: the how answer in place of the compact bundle, on the same route, under the compact legend ──
# Arms 1-3 do NOT hold here, by design: the how root drops bundle=/bodies=/reason= (it is not the compact bundle), its
# edge context is <path> rather than <hops> (lens= names hops as not carried), and its <b> rows are selected lines.
rw --for="$CONC_HOW" >"$TMP/how"; rw --for="$CONC_HOW" --legend=full >"$TMP/howfull"; rw --for="$CONC_HOW" >"$TMP/how2"
HROOT="$( grep -o '<ctx [^>]*>' "$TMP/how" | head -1 )"
case "$HROOT" in
    *' route="subtoken+body"'*' schema="ripwire.for/v1"'*' shape="how"'*' lens="'*hops*) ok "(9) how form: same route= and schema=, shape=\"how\", lens= names the <hops> it does not carry" ;;
    *) no "(9) how form root: want route=\"subtoken+body\" schema=\"ripwire.for/v1\" shape=\"how\" lens=…hops; got $HROOT" ;;
esac
case "$HROOT" in *' bundle='*|*' bodies='*|*' reason='*) no "(9) how form root still carries the compact bundle's bundle=/bodies=/reason=" ;;
                 *) ok "(9) how form root carries no bundle=/bodies=/reason= (it is not the compact bundle)" ;; esac
HCHK="$( python3 - "$TMP/how" <<'PY9'
import re, sys
d = open(sys.argv[1], encoding="utf-8").read()
leg = re.match(r"<ctx [^>]*><!-- (ripwire for schema=ripwire\.for/v1 shape=how:.*?)-->", d, re.S)
print("legend" if leg and all(k in leg.group(1) for k in ("route=", "lens=:", "path seeds= hops=:")) else "nolegend")
print("edges" if re.search(r"<path [^>]*>[^<]*</path><h n=[^>]*>.*?<c n=", d, re.S) else "noedges")   # the chain, then its hop rows
PY9
)"
if printf '%s\n' "$HCHK" | grep -qx legend; then ok "(9) how form: the compact legend opens the answer and defines route=, lens= and <path>"
else no "(9) how form: the compact legend is missing or does not define route=/lens=/<path>"; fi
if printf '%s\n' "$HCHK" | grep -qx edges; then ok "(9) how form: <path> carries hop rows with resolved callees (the edge context, in the how shape)"
else no "(9) how form: <path> has no <h> row with a <c> callee"; fi
if [ "$( wc -c < "$TMP/howfull" )" -gt "$( wc -c < "$TMP/how" )" ]; then ok "(9) how form: --legend=full restores the prose legend (longer than compact)"
else no "(9) how form: --legend=full is not longer than the compact answer"; fi
if cmp -s "$TMP/how" "$TMP/how2" && { ! command -v xmllint >/dev/null 2>&1 || xmllint --noout "$TMP/how" 2>/dev/null; }; then
    ok "(9) how form: byte-identical across 2 runs and well-formed"
else no "(9) how form: not deterministic or not well-formed"; fi

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES PRESENT"; exit 1
