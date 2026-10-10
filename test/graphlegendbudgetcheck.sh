#!/usr/bin/env bash
# graphlegendbudgetcheck.sh — G4: --callers/--impact/--uses must not re-inflate their shared legend essay.
#
#   test/graphlegendbudgetcheck.sh                        # uses build/ripwire on the repo itself
#   RIPWIRE_BIN=asan/ripwire test/graphlegendbudgetcheck.sh
#
# WHY (density audit, lane/fa-legend 2026-08-28, finding C1). Measured on a real, unambiguous, well-connected
# symbol (rootRelPathsLegend, a real function in src/graphlegend.h — NOT `main`, which has 76 in-corpus
# definitions in this tree and collapses the payload), the pre-fix legend bytes OUT-WEIGHED the payload on
# all three verbs:
#     --callers=rootRelPathsLegend   4474 B total, 3179 B legend, 1295 B payload (71.1%)
#     --impact=rootRelPathsLegend    6510 B total, 3683 B legend, 2827 B payload (56.6%)
#     --uses=rootRelPathsLegend      6330 B total, 4303 B legend, 2027 B payload (68.0%)
# Root cause: three near-duplicate prose essays in src/graphlegend.h — kCallHierarchyLegendOpen,
# kImpactLegendOpen/kImpactImportTierLegend, kUsesLegendOpen — PLUS the shared graphCountDisclosure()
# (kGraphCountFloorLegend + kCallCountUnitLegend), which every one of these verbs pays for in full even
# though CLAUDE.md pairs --impact + --uses back to back for a single blast-radius check, so a reader pays for
# the SAME ~2.3 KB floor+unit essay twice in one workflow. docs/EVALS.md §5 has the full before/after table
# and the payload-byte-identical proof (the fix touches explanatory prose only, never a fact or a row).
#
# SHAPE CHOSEN: compact the DEFAULT (the --quality-panel shape), not an opt-in --legend=compact flag — these
# five graph-count verbs (--uses/--callers/--callees/--impact/--edit-check, plus --graph-query/--pr-context
# which share graphCountDisclosure()) have no compact-legend flag today, and CLAUDE.md's own "prefer the
# --quality-panel shape" guidance says a compact-by-default legend beats adding a flag surface across seven
# verbs for one lane's fix.
#
# THE RATCHET IS ABSOLUTE BYTES, not legend<=payload: the payload here is real row content (call/use sites)
# whose size is corpus-dependent, not near-zero the way an empty --test-gate diff is, so unlike
# testgatelegendbudgetcheck.sh a relative arm is meaningful here and is asserted too (informational once
# uses/callers still lead their own payload — the essay is large enough that legend<=payload is aspirational,
# not yet reached, and is reported as such rather than silently dropped).
# Exits non-zero on a budget or honesty-marker failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
info(){ printf '  INFO  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN (build first)"; exit 1; }

measure(){    # $1=file -> prints "total legend payload" (bytes)
    python3 - "$1" <<'PY'
import re, sys
doc = open( sys.argv[1], 'rb' ).read().decode( 'utf-8' )
m = re.match( r'\A(?:\s*<!--.*?-->)+', doc, re.S )
lead = m.group( 0 ) if m else ''
rest = doc[ len( lead ): ]
print( len( doc.encode() ), len( lead.encode() ), len( rest.encode() ) )
PY
}

# ── (a) the absolute byte ratchet, ONE budget per verb, with headroom above today's measurement and well
#        below the pre-fix numbers cited above (3179 / 3683 / 4303 B) so this gate is RED on the 1dc7b01
#        binary and GREEN here. ────────────────────────────────────────────────────────────────────────
#
# RAISED ONCE, 2026-09-03, for round-4 finding F-02 — callers 2700 -> 3050, impact 3100 -> 3450. The +311 B
# is graphlegend.h's kTestedLensBlindSpotLegend: the tested= lens sees a caller only through a call edge from
# an indexed test symbol, so a shell/CLI test driving the built binary as a subprocess is invisible to it and
# a repo tested that way (this one: ~500 test/*.sh gates) reads radius_untested="48" with nothing in the
# legend saying what "untested" meant. This ratchet exists to stop the shared PROSE ESSAY re-inflating, not
# to stop a missing honesty fact from being stated — non-negotiable 3 outranks it, and the clause was written
# to the shortest honest form (311 B) before the budgets moved rather than after. The ratchet's original
# purpose is intact: both new budgets still sit BELOW the pre-fix numbers above (3050 < 3179, 3450 < 3683),
# so the gate is still red on the 1dc7b01 binary. `uses` is untouched: it carries no tested lens, so it pays
# 0 bytes for the clause — which is the "0 bytes when inert" placement rule, checked here by its budget not
# needing to move.
# bash 3.2 (macOS system /bin/bash) has no associative arrays — a case statement is the portable budget table.
budgetFor(){
    case "$1" in
        # RE-PINNED +200 (2026-09-04, capture-audit M15): the shared floor essay grew ONE sentence defining the
        # graph_ambiguous=/graph_unresolved= gauge pair every graph-floored root now carries (the magnitude of
        # the floor, which no graph verb disclosed). New content on every first screen, not the essay re-inflating.
        # RE-PINNED impact +70 (2026-09-05, capture-audit wave-3, lane L7 P3): kImpactLegendOpen grew ONE sentence
        # defining next= (68 B: the safe-delete read of SYM — the one pasteable follow-up every impact root now
        # carries). Measured 3674 B against 3650; 3720 leaves 46 B, the posture the previous pin held. callers'
        # own next= sentence (87 B) fits its 3250 unchanged.
        # RE-PINNED +179 on all three (2026-09-08, issue #66): the shared essay gained ONE sentence defining
        # graph_unindexed=, the THIRD gauge — files no grammar could read, the blind spot that made
        # `count="0"` indistinguishable from "none exists" on @snrmwg's .astro tree. Same shape as the M15
        # re-pin above: new content on every first screen, not the essay re-inflating, and each verb keeps
        # exactly the headroom it had (callers 107 B, impact 48 B, uses 25 B).
        #
        # READ THIS BEFORE ASSUMING THE ESSAY GREW ON EVERY CORPUS: the sentence is CONDITIONAL
        # (graphlegend.h graphUnindexedLegend( bool ) — it is emitted exactly when the attribute is, which is
        # this header's own rootRelPathsLegend rule: "a legend that defines an attribute the document did not
        # emit is the mirror-image false claim"). These budgets are measured on THIS repository, whose tree
        # does contain unindexed extensions, so they see the sentence. A corpus with nothing unindexed pays
        # 0 B — which is what keeps test/defaultceilingcheck.sh's 120-file --pr-context fixture (about three
        # tokens of slack under its 8000-token default budget) from going over a ceiling it would then have
        # had to disclose. Two earlier drafts that were UNCONDITIONAL, at 135 B and at 57 B folded into the
        # gauge sentence, both broke that fixture; the conditional form is why this one does not.
        # RE-PINNED uses +81 (2026-09-20, issue #60): the in_id= clause CORRECTED a now-false sentence. It read
        # "absent at file scope", which stopped being true when ingest_model.h mintModuleScopeOwners started
        # giving a top-level statement and an anonymous callback body a caller node — those sites now carry
        # in_id=<file-scope>, and a legend that says an attribute is absent where the document emits it is the
        # same false claim as a legend defining one the document cannot emit. Measured 4035 B against 3979;
        # 4060 leaves 25 B, the exact headroom the #66 re-pin left this verb. Same shape as every re-pin above:
        # a correction stated in the shortest honest form (the clause that went is 22 B, the clause that came
        # is 78 B), not the essay re-inflating — and 4060 still sits below the 4303 B pre-fix number cited at
        # the top, so this gate is still RED on the 1dc7b01 binary.
        # RE-PINNED impact +75 and uses +54 (2026-09-23, cut-fix C, lane/cutfix-navlists): two sentences restate what
        # CHANGED about the rows, compressed to their shortest honest form first (the drafts were +55 and +54 B over the
        # base). uses: "by path within a tier" -> "within a tier by the enclosing symbol's callers, then path" (+37 B) —
        # the rows are ranked before the cap now, and a legend that still says "by path" is the false claim. impact: the
        # import-tier clause "limit=/offset= window the symbol rows only" -> "most-imported first; limit= sizes it, offset=
        # windows the symbol rows only" (+32 B) — --limit now reaches that tier, and the old sentence said it could not.
        # Measured on the base binary 3894 / 4052 B, on this lane 3926 / 4089 B; each keeps the headroom its #66 re-pin
        # left (impact 48 B, uses 25 B). callers' own sentence (+28 B) fits its 3429 unchanged. uses 4114 still sits below
        # the 4303 B pre-fix number at the top, so the gate stays RED on the 1dc7b01 binary.
        # RE-PINNED impact +362 (2026-09-27, lane impact-depth-065, depth-labelled --impact): the full legend gains
        # graphlegend.h kImpactDepthLegend, the one definition of the rows' d= (run-length hop depth), the root's
        # by_depth= and the new depth-first row order a cut relies on — attributes the answer now emits, present only
        # when reaches>0. Measured on this probe: 3926 B on main (3fcd515f), 4288 B on this lane (+362 B, exactly the
        # clause); 4336 keeps impact's 48 B headroom. The gate's RED-on-1dc7b01 property rests on the uses pin (4114 <
        # 4303), which does not move.
        # RE-PINNED callers +340 (2026-10-09, lane callers-sites-first-call, CALLSITE-AT): every caller row now carries
        # sites_at=, its call sites as file:line, and the full legend defines it (graphlegend.h kCallSitesAtLegend, present
        # only when a row carries it). Measured on this probe: 3403 B on main (0852bc0f), 3743 B on this lane (+340 B,
        # exactly the clause); 3769 keeps callers' 26 B headroom. The OLD 3429 stays as a twin below: the legend with that
        # one sentence cut out must still fit it, so the rest of the essay cannot re-inflate under the new headroom.
        callers) echo 3769 ;;
        impact)  echo 4336 ;;
        uses)    echo 4114 ;;
    esac
}
VERBS="callers impact uses"

for v in $VERBS; do
    # L1 (2026-09-19): the CLI default legend is compact; (a) budgets and (b) reads the FULL legend, so it is asked for.
    "$BIN" "$ROOT" "--$v=rootRelPathsLegend" --legend=full >"$TMP/$v.xml" 2>/dev/null
    read -r total legend payload <<<"$( measure "$TMP/$v.xml" )"
    budget="$( budgetFor "$v" )"
    if [ "$legend" -le "$budget" ]; then
        ok "(a) --$v legend is $legend B (<= $budget B budget; total=$total payload=$payload)"
    else
        no "(a) --$v legend is $legend B (> $budget B budget) — the shared essay re-inflated"
    fi
    if [ "$legend" -le "$payload" ]; then
        ok "(a2) --$v: legend ($legend B) <= payload ($payload B) on this symbol"
    else
        info "(a2) --$v: legend ($legend B) still exceeds payload ($payload B) on this symbol — aspirational, not asserted"
    fi
done

# (a-twin) the pre-CALLSITE-AT callers pin: the --callers full legend minus the sites_at= sentence still fits 3429 B. The
# cut is taken only when a row carries sites_at= AND the sentence occurs once, start to end; any other premise FAILs.
twin="$( python3 - "$TMP/callers.xml" <<'PY'
import re, sys
doc  = open( sys.argv[1], 'rb' ).read().decode( 'utf-8', 'replace' )
m    = re.match( r'\A(?:\s*<!--.*?-->)+', doc, re.S )
leg  = m.group( 0 ) if m else ''
if not leg or 'sites_at="' not in doc[ len( leg ): ]:
    print( 'NOPREMISE no row carries sites_at=' ); sys.exit( 0 )
a, z = 'sites_at= on a caller row', '(an aliased import). '
i = leg.find( a ); j = leg.find( z, i + 1 ) if i >= 0 else -1
if i < 0 or j < 0 or leg.count( a ) != 1:
    print( 'NOPREMISE sentence-not-found-once' ); sys.exit( 0 )
print( len( ( leg[ :i ] + leg[ j + len( z ): ] ).encode() ) )
PY
)"
case "$twin" in
    NOPREMISE*) no "(a-twin) --callers legend twin cannot measure: ${twin#NOPREMISE }" ;;
    *)  if [ -n "$twin" ] && [ "$twin" -eq "$twin" ] 2>/dev/null && [ "$twin" -le 3429 ]; then
            ok "(a-twin) --callers legend minus the sites_at= sentence is $twin B <= 3429 B (the pre-CALLSITE-AT pin)"
        else
            no "(a-twin) --callers legend minus the sites_at= sentence is ${twin:-?} B > 3429 B — the rest re-inflated"
        fi ;;
esac

# ── (b) the honesty vocabulary a reader must meet on all three, unchanged by the trim (test/floormarkcheck.sh
#        already gates the exact cross-verb anchors; this arm is the lane's own quick check that the shared
#        constants still carry the attribute-defining words a reader relies on). ─────────────────────────
for v in $VERBS; do
    L="$( sed -n '1,/-->/p' "$TMP/$v.xml" )"
    for phrase in 'counts_floor="1"' 'is a FLOOR, never a total' 'COUNTING UNIT' 'most-vexing-parse'; do
        case "$L" in
            *"$phrase"*) ok "(b) --$v legend keeps: $phrase" ;;
            *)           no "(b) --$v legend lost: $phrase" ;;
        esac
    done
done
case "$( sed -n '1,/-->/p' "$TMP/callers.xml" )" in
    *'role="macro"'*) ok "(b) --callers legend still defines the macro row shape" ;;
    *)                no "(b) --callers legend lost the macro row shape" ;;
esac
case "$( sed -n '1,/-->/p' "$TMP/uses.xml" )" in
    *'role=call|macro|read|write|import|extends|type'*) ok "(b) --uses legend still defines the role= vocabulary" ;;
    *)                                                    no "(b) --uses legend lost the role= vocabulary" ;;
esac
case "$( sed -n '1,/-->/p' "$TMP/impact.xml" )" in
    *'transitive blast radius'*) ok "(b) --impact legend still defines the transitive blast radius" ;;
    *)                           no "(b) --impact legend lost the transitive blast radius framing" ;;
esac

# ── (c) well-formed + deterministic, unchanged by a prose-only edit. ──────────────────────────────────
for v in $VERBS; do
    if command -v xmllint >/dev/null 2>&1; then
        if xmllint --noout "$TMP/$v.xml" 2>/dev/null; then ok "(c) --$v is well-formed XML"; else no "(c) --$v fails xmllint"; fi
    fi
    "$BIN" "$ROOT" "--$v=rootRelPathsLegend" --legend=full >"$TMP/$v.2.xml" 2>/dev/null
    if diff -q "$TMP/$v.xml" "$TMP/$v.2.xml" >/dev/null; then ok "(c) --$v deterministic (byte-identical twice)"; else no "(c) --$v differs across two runs"; fi
done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
