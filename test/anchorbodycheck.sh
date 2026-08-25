#!/usr/bin/env bash
# anchorbodycheck.sh — the T3 auto-body allowance serves the ANCHOR's own body, or NO body at all.
# It never SUBSTITUTES a smaller, lower-relevance namesake for the symbol the query actually named.
#
# The measured problem (PLAN_HARVEST_REPORTS_2026-08-20/t3-allowance-memo.md §2, re-derived in
# PLAN_HARVEST_REPORTS_2026-08-20/t3-anchor-lane.md). Over the r10 class-A set, 19 body blocks were
# served across 12 name-exact queries; 8 were the anchor's own body and 11 (43.9% of all served body
# bytes) were something else. The mechanism was "walk the ranked candidates and serve whichever FITS",
# so on exactly the queries where the real answer is large — the ones a caller most needs a body for —
# the anchor was dropped over budget and a smaller candidate took its place. What shipped instead of a
# webpack class body was a CHANGELOG.md "Patch Changes" section (8,605 B, the whole allowance) that
# mentions the class name; elsewhere a `types.d.ts` one-line stub, a `lib/index.js` re-export shim, and
# two copies of a doc's "Project overview" heading.
#
# THE RULE THIS GATE PINS. When the route names an anchor (the `anchors: NAME(path)` clause of a
# name-exact reason), the auto-body candidate set is exactly that anchor — matched by lowercased NAME
# *and* by the anchor's own defining FILE. A namesake in another file is not the anchor. If the
# anchor's body does not fit the allowance, the bundle serves NOTHING and says so through the surface
# that already existed for it (`bodies="0" reason="budget"`, `<bodies shown="0" total="N" capped="1">`,
# and the per-item `<!-- body omitted (over budget): NAME -->` comment). Routes that name no anchor
# (subtoken+body — a conceptual query) are untouched: nothing anchored them, so there is nothing to
# restrict to.
#
# The name/file pairing is the load-bearing half, and the fixture is built to prove it: the bystander
# shares the anchor's NAME exactly, so a name-only rule would leave it in place.
#
# Asserts:
#   (0) PRESENCE GUARD: the fixture can actually observe the defect — the oversized anchor really is
#       dropped over budget, and the same-named bystander really is a ranked, positively-scoring
#       candidate in a different file. Green on both binaries; that is its job.
#   (1) NO SUBSTITUTION: with the anchor over budget, no body is served at all — no <b> block, and
#       none of the bystander's prose anywhere in the bundle.
#   (2) DISCLOSED, not silent: bodies="0" reason="budget" on the root, the <bodies shown="0"> shell
#       kept (R9: a zero means none found), and the omitted anchor named in the comment.
#   (3) AN ANCHOR THAT FITS IS STILL SERVED: the small-anchor sandbox serves the anchor's own body,
#       whole, in CDATA — this change may never cost a body that was already the right answer.
#   (3b) …and ONLY the anchor: the same-named bystander that used to ride alongside it is gone.
#   (4) INERT WITHOUT A BYSTANDER: an anchor with no namesake is served exactly as before (bodies="1").
#   (5) CONCEPTUAL ROUTES UNTOUCHED by THIS rule: a subtoken+body query names no anchor, so under
#       --auto-bodies (which is where the body walk lives on that route since the compact round) it still escalates to
#       several bodies. This is the arm that keeps the rule scoped to what the memo measured.
#   (6) determinism x3 + xmllint-clean (G4) on every shape above.
#   (7) THE ANCHOR-RESOLVED ALLOWANCE (docs/EVALS.md, the T3 body-budget round, 2026-08-25). When the
#       route resolved an anchor, there is no explicit --token-budget, and the candidate set is exactly
#       ONE definition, that one body is funded at kForAnchorBodyBudgetBytes (22,800 B) instead of the
#       fixed six-candidate pool. (7)/(7b) prove the mid-sized anchor is now served, alone, from its own
#       file; (7b2) proves the RAISE did not reopen substitution, which matters because a larger
#       allowance is exactly the condition under which the original defect fired; (7c) proves an explicit
#       --token-budget is still a hard ceiling; (7d) proves the raise is BOUNDED (the 36 KB anchor still
#       refuses, so whole-body-or-nothing survives); (7e) proves a MULTI-candidate anchored bundle gets
#       no raise at all — the guard that stops this becoming a general per-item budget increase.
#
# MUTATION EVIDENCE (red-first, recorded 2026-08-22): against the lane's base binary (origin/main
# 3702693, pre-fix) arms (1)(1b)(2)(3b) FAIL — that binary answers the oversized-anchor query with the
# z_notes.md section body (bodies="1") and the fitting-anchor query with TWO bodies (bodies="2", the
# anchor plus its namesake). (0), (3), (4), (5) and (6) are green on both binaries by construction:
# (0) is the presence guard, and (3)/(4)/(5)/(6) are the no-regression arms. Reproduce with:
#     bash test/anchorbodycheck.sh /path/to/base/build/ripwire
#
# MUTATION EVIDENCE for the (7) arms (red-first, recorded 2026-08-25): against this lane's base binary
# (518fe0d, pre-rule) arms (7) and (7b) FAIL — that binary answers --for=widgetMidProbe with
# bodies="0" reason="budget", because the mid-sized body (~17.1 KB) is above the fixed pool's hard
# maximum of 13,500 B. (7pre), (7b2), (7c), (7d) and (7e) are green on BOTH binaries by construction:
# (7pre) is the presence guard and the other three are the bounds, which a pre-rule binary satisfies
# trivially by never raising anything. That is the point of stating it here rather than leaving the
# reader to assume five red arms — an arm that cannot fail on the base binary is not evidence the rule
# works, it is evidence the rule did not overreach, and the two are different claims.
#   (7e) additionally carries MUTATION evidence against the rule's most likely mis-implementation:
# with the size()==1 guard removed (candidate set of 2 allowed to take the raise), the first twin body
# fits 22,800 B and the bundle reports bodies="1" — verified red, then restored.
#
# Usage:
#   bash test/anchorbodycheck.sh                       # uses build/ripwire
#   bash test/anchorbodycheck.sh path/to/ripwire       # explicit binary (the mutation arm)
#   RIPWIRE_BIN=asan/ripwire bash test/anchorbodycheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "anchorbodycheck: BIN=$BIN"

# ── the sandbox ─────────────────────────────────────────────────────────────────────────────────────
# a_src/ sorts before z_notes.md, so the CODE definition is the first def in NodeId order and therefore
# the file the route's `anchors:` clause names. That is deliberate: the bystander must be the namesake,
# never the anchor, or the arms below would assert the opposite of the contract.
SB="$TMP/anchorsandbox"
mkdir -p "$SB/a_src"
python3 - "$SB" <<'PY'
import sys, os
d = sys.argv[ 1 ]

# (a) the OVERSIZED anchor: its own body is far larger than the whole default body allowance
#     (kForPayloadBudgetBytes leftover + kForAutoBodyBudgetBytes), so it is dropped whole and disclosed.
with open( os.path.join( d, "a_src", "big.py" ), "w" ) as fh:
    fh.write( "def widgetAnchorProbe( n ):\n" )
    fh.write( '    """The anchor. Its own body is deliberately larger than the whole auto-body allowance."""\n' )
    fh.write( "    total = 0\n" )
    for i in range( 420 ):
        fh.write( "    total += ( n * %d ) %% 97          # a line of the oversized anchor body, row %03d\n" % ( i, i ) )
    fh.write( "    return total\n" )

# (b) the FITTING anchor: small enough that the allowance holds it comfortably.
with open( os.path.join( d, "a_src", "small.py" ), "w" ) as fh:
    fh.write( "def widgetFitProbe( n ):\n" )
    fh.write( '    """The anchor. Its own body fits the allowance easily."""\n' )
    fh.write( "    return ( n * 3 ) % 97\n" )

# (b2) the MID-SIZED anchor (docs/EVALS.md, the T3 body-budget round): ABOVE the fixed pool a
#      six-candidate allowance can ever offer (kForPayloadBudgetBytes 7500 + kForAutoBodyBudgetBytes
#      6000 = 13,500 B even with a zero-byte signature side) and BELOW kForAnchorBodyBudgetBytes
#      (22,800 B). ~17.1 KB, so ~3.6 KB of clearance under the old ceiling and ~5.7 KB under the new
#      one — neither margin is close enough for a path-length or corpus-stats wobble to flip it.
#      This is the ONLY shape that can observe the anchor-resolved allowance; big.py (36,163 B) is
#      deliberately above BOTH ceilings, which is why arms (0)/(1)/(2) stay green and stay meaningful.
with open( os.path.join( d, "a_src", "mid.py" ), "w" ) as fh:
    fh.write( "def widgetMidProbe( n ):\n" )
    fh.write( '    """The anchor. Larger than the fixed pool, smaller than the anchor-resolved allowance."""\n' )
    fh.write( "    total = 0\n" )
    for i in range( 200 ):
        fh.write( "    total += ( n * %d ) %% 97          # a line of the mid-sized anchor body, row %03d\n" % ( i, i ) )
    fh.write( "    return total\n" )

# (b3) TWO mid-sized definitions sharing ONE name in ONE file — the multi-candidate anchor. Both
#      survive restrictBodiesToRouteAnchor (same name, same defining file), so the candidate set is 2
#      and the anchor-resolved raise must NOT apply: an anchored bundle serving a SET is funded by the
#      fixed pool, which holds neither of these. An implementation that relaxed the size()==1 guard
#      would raise the allowance to 22,800 B, the first body (~17.1 KB) would fit, and arm (7e) goes red.
with open( os.path.join( d, "a_src", "twin.py" ), "w" ) as fh:
    for which in ( "first", "second" ):
        fh.write( "def widgetTwinProbe( n ):\n" )
        fh.write( '    """The %s of two same-named mid-sized definitions in one file."""\n' % which )
        fh.write( "    total = 0\n" )
        for i in range( 200 ):
            fh.write( "    total += ( n * %d ) %% 97          # the %s twin body, row %03d\n" % ( i, which, i ) )
        fh.write( "    return total\n\n" )

# (c) an anchor with NO namesake anywhere — the inertness arm.
with open( os.path.join( d, "a_src", "solo.py" ), "w" ) as fh:
    fh.write( "def widgetSoloProbe( n ):\n" )
    fh.write( '    """An anchor nothing else in this corpus shares a name with."""\n' )
    fh.write( "    return n - 1\n" )

# (d) material for a CONCEPTUAL (subtoken+body) query: no single query word is a whole symbol name,
#     so the route names no anchor and the allowance keeps its rank-first walk.
with open( os.path.join( d, "a_src", "concept.py" ), "w" ) as fh:
    fh.write( "def sweepExpiredCacheSlots( store ):\n" )
    fh.write( '    """Walk the cache store and reclaim the slots whose lease has expired."""\n' )
    fh.write( "    return [ s for s in store if s.expired ]\n\n" )
    fh.write( "def pickReclaimVictimSlot( store ):\n" )
    fh.write( '    """Choose which cache slot to reclaim when the store is full and nothing has expired."""\n' )
    fh.write( "    return min( store, key=lambda s: s.hits )\n\n" )
    fh.write( "def reclaimLeaseForSlot( slot ):\n" )
    fh.write( '    """Reclaim one cache slot lease and return the freed byte count."""\n' )
    fh.write( "    return slot.bytes\n" )

# (e) the BYSTANDERS: doc sections whose names are EXACTLY the two anchors' names, in another file.
#     A name-only rule would keep these; the contract is name AND defining file.
with open( os.path.join( d, "z_notes.md" ), "w" ) as fh:
    fh.write( "# Fixture notes\n\n## widgetAnchorProbe\n\n"
              "ZZBYSTANDERPROSE — a short note that merely MENTIONS the anchor's name.\n"
              "It is not the code the query asked for.\n\n"
              "## widgetFitProbe\n\n"
              "ZZBYSTANDERPROSE — the same shape, beside an anchor that DOES fit.\n\n"
              "## widgetMidProbe\n\n"
              "ZZBYSTANDERPROSE — the same shape again, beside the anchor whose body the "
              "anchor-resolved allowance newly funds. A RAISED allowance is exactly the "
              "condition under which the old substitution defect used to fire, so this "
              "bystander is what arm (7b) proves is still refused.\n" )
PY

rw(){ "$BIN" "$SB" --no-cache "$@" 2>/dev/null; }
bodycount(){ printf '%s' "$1" | grep -o '<b t=' | wc -l | tr -d ' '; }
rootbodies(){ printf '%s' "$1" | grep -o 'bundle="auto" bodies="[0-9]*"' | head -1 | sed -E 's/.*bodies="([0-9]*)"/\1/'; }

BIG="$( rw --for=widgetAnchorProbe )"
FIT="$( rw --for=widgetFitProbe )"
SOLO="$( rw --for=widgetSoloProbe )"
MID="$( rw --for=widgetMidProbe )"                        # the anchor-resolved allowance's own shape
MIDCAP="$( rw --for=widgetMidProbe --token-budget=6000 )" # …with an explicit ceiling: stays hard
TWIN="$( rw --for=widgetTwinProbe )"                      # multi-candidate anchor: no raise
# COMPACT conceptual serving (docs/EVALS.md, the T3 route-narrowing round) moved the rank-first BODY
# walk on this route behind --auto-bodies. That flag is where arm (5b)'s claim now lives: this gate is
# about the anchor-only rule not LEAKING past name-exact routes, and the walk it must not have shrunk is
# the one --auto-bodies serves. Without the flag the conceptual bundle serves <hops>, which would make
# (5b) read zero bodies for a reason that has nothing to do with the rule under test — green (or here,
# red) while inert, the failure mode CONTRIBUTING §2 names.
CONC="$( rw --for="reclaim an expired cache slot lease" --auto-bodies )"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (0) presence guard: the substitution this gate forbids is actually reachable here ==="
# ═══════════════════════════════════════════════════════════════════════════
printf '%s' "$BIG" | grep -q '<!-- body omitted (over budget): widgetAnchorProbe -->' \
    && ok "(0) the oversized anchor really is dropped over budget (the case where substitution used to happen)" \
    || no "(0) the anchor's body FITS in this fixture — re-author a_src/big.py larger; the arms below cannot observe anything"
# the output is ONE minified line, so every per-row assertion below extracts the rows first (grep -o)
NAMESAKES="$( rw --for=widgetAnchorProbe --format=candidates --top-k=20 | grep -oE '<cand [^>]*>' | grep 'n="widgetAnchorProbe"' )"
printf '%s' "$NAMESAKES" | grep -q 'z_notes\.md' \
    && ok "(0b) the same-named bystander in z_notes.md is a ranked candidate — a substitute really is available" \
    || no "(0b) the bystander is not a ranked candidate — this fixture cannot observe a substitution at all"
{ [ "$( printf '%s\n' "$NAMESAKES" | grep -c . )" = "2" ] && ! printf '%s' "$NAMESAKES" | grep -q 's="0"'; } \
    && ok "(0c) both same-named candidates score above zero (the relevance floor cannot be what removes the bystander)" \
    || no "(0c) expected exactly 2 positively-scoring namesakes; the floor, not this rule, would decide this fixture"
printf '%s' "$BIG" | grep -q 'anchors: widgetAnchorProbe(' \
    && ok "(0d) the route names the anchor, so the rule is in scope for this query" \
    || no "(0d) no anchors: clause on this query — the route did not go name-exact (re-author the fixture)"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (1) no substitution: the anchor did not fit, so NOTHING is served ==="
# ═══════════════════════════════════════════════════════════════════════════
[ "$( bodycount "$BIG" )" = "0" ] \
    && ok "(1) zero <b> blocks when the anchor's own body does not fit" \
    || no "(1) $( bodycount "$BIG" ) body block(s) served in the anchor's place — the substitution is still live"
printf '%s' "$BIG" | grep -q 'ZZBYSTANDERPROSE' \
    && no "(1b) the bystander's prose is in the bundle — a namesake in another file was substituted for the anchor" \
    || ok "(1b) none of the bystander's prose reached the bundle"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (2) the zero is disclosed, through the surface that already exists for it ==="
# ═══════════════════════════════════════════════════════════════════════════
printf '%s' "$BIG" | grep -q 'bundle="auto" bodies="0" reason="budget"' \
    && ok "(2) the root says bodies=\"0\" reason=\"budget\"" \
    || no "(2) missing bodies=\"0\" reason=\"budget\" — a bundle that serves nothing must say so"
printf '%s' "$BIG" | grep -qE '<bodies shown="0" total="[1-9][0-9]*" capped="1">' \
    && ok "(2b) the <bodies shown=\"0\"> shell is kept (a zero means none found, never none exists)" \
    || no "(2b) the <bodies> element vanished or lost its counts"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (3) an anchor that FITS is still served — and now it is served ALONE ==="
# ═══════════════════════════════════════════════════════════════════════════
printf '%s' "$FIT" | grep -q '<b t="fn" [^>]*p="a_src/small\.py" n="widgetFitProbe"><!\[CDATA\[' \
    && ok "(3) the fitting anchor's own body is served whole, in CDATA, from its own file" \
    || no "(3) the fitting anchor's body was LOST — this rule may never cost a body that was already right"
{ [ "$( bodycount "$FIT" )" = "1" ] && [ "$( rootbodies "$FIT" )" = "1" ]; } \
    && ok "(3b) exactly one body, the anchor's — the same-named bystander no longer rides along" \
    || no "(3b) expected 1 body, got $( bodycount "$FIT" ) (root says bodies=\"$( rootbodies "$FIT" )\")"
printf '%s' "$FIT" | grep -q 'ZZBYSTANDERPROSE' \
    && no "(3c) the bystander's prose still rides beside the anchor" \
    || ok "(3c) no bystander prose beside the served anchor"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (4) inert when there is no namesake at all ==="
# ═══════════════════════════════════════════════════════════════════════════
{ [ "$( bodycount "$SOLO" )" = "1" ] && printf '%s' "$SOLO" | grep -q 'n="widgetSoloProbe"><!\[CDATA\['; } \
    && ok "(4) an anchor with no namesake is served exactly as before (bodies=\"1\")" \
    || no "(4) the no-namesake anchor changed shape ($( bodycount "$SOLO" ) bodies) — the rule must be inert here"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (5) conceptual routes name no anchor, so they are untouched ==="
# ═══════════════════════════════════════════════════════════════════════════
printf '%s' "$CONC" | grep -q 'anchors: ' \
    && no "(5) presence: the conceptual query routed name-exact — re-author it, this arm proves nothing" \
    || ok "(5) presence: the conceptual query routed subtoken+body (no anchors: clause)"
[ "$( bodycount "$CONC" )" -ge 2 ] \
    && ok "(5b) the conceptual bundle still escalates to $( bodycount "$CONC" ) bodies (rank-first walk intact)" \
    || no "(5b) the conceptual bundle collapsed to $( bodycount "$CONC" ) body — the rule leaked past name-exact routes"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (7) the ANCHOR-RESOLVED allowance: one certain answer is funded at a one-body rate ==="
# ═══════════════════════════════════════════════════════════════════════════
# Registered in docs/EVALS.md, "The anchor-resolved body allowance — T3 body-budget round".
# (7) and (7b) are RED on any binary built before that rule; (7c), (7d) and (7e) are the bounds
# that keep the raise from becoming a general budget increase, and (7e) is red under the one
# implementation mistake the rule is most likely to be written with.
printf '%s' "$MID" | grep -q 'anchors: widgetMidProbe(' \
    && ok "(7pre) presence: the mid-sized query routes name-exact and names its anchor" \
    || no "(7pre) no anchors: clause — the rule is out of scope for this query, so (7)..(7c) prove nothing"
printf '%s' "$MID" | grep -q '<b t="fn" [^>]*p="a_src/mid\.py" n="widgetMidProbe"><!\[CDATA\[' \
    && ok "(7) the mid-sized anchor's own body is served whole, from its own file" \
    || no "(7) the mid-sized anchor is still dropped over budget — the anchor-resolved allowance is not in effect"
{ [ "$( bodycount "$MID" )" = "1" ] && [ "$( rootbodies "$MID" )" = "1" ]; } \
    && ok "(7b) exactly one body, the anchor's — the raise funded the answer, not a set" \
    || no "(7b) expected 1 body, got $( bodycount "$MID" ) (root says bodies=\"$( rootbodies "$MID" )\")"
printf '%s' "$MID" | grep -q 'ZZBYSTANDERPROSE' \
    && no "(7b2) the bystander's prose rode in on the RAISED allowance — substitution reopened at the new ceiling" \
    || ok "(7b2) no bystander prose in the newly-funded bundle"
printf '%s' "$MIDCAP" | grep -q 'bundle="auto" bodies="0" reason="budget"' \
    && ok "(7c) an explicit --token-budget stays a HARD ceiling — the raise does not apply to it" \
    || no "(7c) the raise leaked into the explicit --token-budget regime (root: $( rootbodies "$MIDCAP" ) bodies)"
{ [ "$( bodycount "$BIG" )" = "0" ] && printf '%s' "$BIG" | grep -q '<!-- body omitted (over budget): widgetAnchorProbe -->'; } \
    && ok "(7d) the oversized anchor STILL refuses at the raised ceiling — whole-body-or-nothing survives, bounded" \
    || no "(7d) the raise is unbounded: the 36 KB anchor now fits, so the allowance is no longer a ceiling"
{ [ "$( bodycount "$TWIN" )" = "0" ] && printf '%s' "$TWIN" | grep -q 'bundle="auto" bodies="0" reason="budget"'; } \
    && ok "(7e) a MULTI-candidate anchor gets no raise — an anchored SET is still funded by the fixed pool" \
    || no "(7e) the raise reached a $( rootbodies "$TWIN" )-body multi-candidate bundle — the size()==1 guard is missing or relaxed"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (6) determinism x3 and well-formedness on every shape above ==="
# ═══════════════════════════════════════════════════════════════════════════
det=1
for Q in widgetAnchorProbe widgetFitProbe widgetSoloProbe widgetMidProbe widgetTwinProbe; do
    rw --for="$Q" >"$TMP/d1"; rw --for="$Q" >"$TMP/d2"; rw --for="$Q" >"$TMP/d3"
    { diff -q "$TMP/d1" "$TMP/d2" >/dev/null && diff -q "$TMP/d2" "$TMP/d3" >/dev/null; } || { echo "    nondeterministic: $Q"; det=0; }
done
[ "$det" = 1 ] && ok "(6) byte-identical across three runs on every shape" || no "(6) NON-deterministic output"

if command -v xmllint >/dev/null 2>&1; then
    lint=1
    for V in BIG FIT SOLO CONC MID MIDCAP TWIN; do
        eval "printf '%s' \"\$$V\"" >"$TMP/lint.xml"
        xmllint --noout "$TMP/lint.xml" 2>/dev/null || { echo "    malformed: $V"; lint=0; }
    done
    [ "$lint" = 1 ] && ok "(6b) all shapes well-formed XML (G4)" || no "(6b) malformed XML"
else
    printf '  SKIP  xmllint (not installed)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
