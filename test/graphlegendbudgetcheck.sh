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
ok(){ printf '  PASS  %s\n' "$*"; }
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
        callers) echo 3250 ;;
        impact)  echo 3650 ;;
        uses)    echo 3800 ;;
    esac
}
VERBS="callers impact uses"

for v in $VERBS; do
    "$BIN" "$ROOT" "--$v=rootRelPathsLegend" >"$TMP/$v.xml" 2>/dev/null
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
        xmllint --noout "$TMP/$v.xml" 2>/dev/null && ok "(c) --$v is well-formed XML" || no "(c) --$v fails xmllint"
    fi
    "$BIN" "$ROOT" "--$v=rootRelPathsLegend" >"$TMP/$v.2.xml" 2>/dev/null
    diff -q "$TMP/$v.xml" "$TMP/$v.2.xml" >/dev/null && ok "(c) --$v deterministic (byte-identical twice)" || no "(c) --$v differs across two runs"
done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
