#!/usr/bin/env bash
# morecontractcheck.sh — the gate for the `<more N=/>` TRUNCATION CONTRACT (r27 P0.5).
#
#   test/morecontractcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/morecontractcheck.sh
#
# The claim being pinned is one sentence: NOTHING IS DROPPED WITHOUT A NUMBER. A capped list prints at most
# `cap` rows and, whenever it holds more than that, exactly one `<more X=/>` whose X is the count it did not
# print — so rows_printed + X == the total the header already stated.
#
# Both emitters shipped the same wrong idiom:
#
#     std::size_t shown = 0;
#     for( const T& t : list ) { if( shown++ >= cap ) break; print( t ); }
#     if( list.size() > shown ) print( "<more n=\"%zu\">", list.size() - shown );
#
# `shown` leaves that loop at cap+1, not cap, which fails in two distinct ways:
#   * total >  cap+1 — the <more/> under-reports the drop BY ONE (60 rows shown of 81, "<more hits=20/>");
#   * total == cap+1 — `total > shown` is FALSE, so the <more/> element VANISHES and the one un-printed row
#                      disappears with no marker at all. That is the dangerous case: the output looks whole.
#
# So the boundary is the test. Three totals per verb, chosen around the cap:
#   cap-1 / cap   -> no <more/> at all (nothing was dropped)
#   cap+1         -> <more n="1"/>     (the vanishing case)
#   cap+K         -> <more n="K"/>     (the off-by-one case)
#
# Two verbs are covered here because they shipped the same defect in the same round: `--flags` (per gate,
# read sites, cap 8) and `--doc-drift` (per doc, drifted anchors, cap 12). Both corpora are synthesized into
# a temp dir rather than committed, so the caps can be straddled exactly without a fixture that has to be
# re-counted by hand whenever it is edited.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "morecontractcheck: BIN=$BIN"

FLAGS_CAP=8      # darkflags.h kMaxSitesShown
DRIFT_CAP=12     # docdrift.h  kMaxAnchorsShown

# ── 1) --flags: read sites per gate ───────────────────────────────────────────────────────────────────
# One gate per total, each declared once and then TESTED from `total` distinct `#if` lines. Every `#if`
# region mentioning the gate is a read site, so the count is exactly the number of `#if` lines written.
FIX="$TMP/flagsfix"; mkdir -p "$FIX"
{
    echo '#pragma once'
    for total in 7 8 9 11; do
        echo "#ifndef MORE_GATE_$total"
        echo "#define MORE_GATE_$total 0"
        echo '#endif'
    done
} >"$FIX/gates.h"
{
    echo '#include "gates.h"'
    for total in 7 8 9 11; do
        i=0
        while [ "$i" -lt "$total" ]; do
            echo "#if MORE_GATE_$total"
            echo "int moreUse_${total}_${i} = 1;"
            echo '#endif'
            i=$(( i + 1 ))
        done
    done
} >"$FIX/uses.cpp"

"$BIN" "$FIX" --flags --no-cache >"$TMP/flags" 2>/dev/null
FL="$( cat "$TMP/flags" )"

# ONE element of the document "$1" — the span from the open tag matching "$2" to the close tag "$3", a tag
# per line — so a per-element count can never be satisfied by a neighbouring element's rows. Both verbs'
# assertions go through this; a gate row and a doc row differ only in which open tag names them.
element(){ printf '%s' "$1" | tr '>' '\n' | sed -n "/$2/,/<\/$3/p"; }
gate(){ element "$FL" "<gate name=\"$1\"" gate; }
gate_reads_attr(){ gate "$1" | sed -n 's/.*reads="\([0-9]*\)".*/\1/p' | head -1; }
gate_rows(){ gate "$1" | grep -c '<read p=' || true; }
gate_more(){ gate "$1" | sed -n 's/.*<more reads="\([0-9]*\)".*/\1/p' | head -1; }

for total in 7 8 9 11; do
    G="MORE_GATE_$total"
    declared="$( gate_reads_attr "$G" )"
    rows="$( gate_rows "$G" )"
    more="$( gate_more "$G" )"
    [ -z "$more" ] && more=0
    want_rows="$total"; [ "$total" -gt "$FLAGS_CAP" ] && want_rows="$FLAGS_CAP"
    want_more=$(( total - want_rows ))

    [ "$declared" = "$total" ] \
        && ok "flags $G: header declares reads=\"$total\"" \
        || no "flags $G: header says reads=\"$declared\", fixture wrote $total read sites"
    [ "$rows" = "$want_rows" ] \
        && ok "flags $G: printed $rows <read/> rows (cap $FLAGS_CAP)" \
        || no "flags $G: printed $rows <read/> rows, expected $want_rows"
    [ "$more" = "$want_more" ] \
        && ok "flags $G: <more reads=\"$want_more\"/> — printed + more == declared" \
        || no "flags $G: <more reads=\"$more\"/>, expected $want_more (printed $rows of $total)"
    [ $(( rows + more )) = "$total" ] \
        && ok "flags $G: nothing dropped without a number ($rows + $more = $total)" \
        || no "flags $G: $rows printed + $more more != $total declared — rows vanished unmarked"
done

# the vanishing case gets its own named assertion, because it is the one that LOOKS fine
gate "MORE_GATE_9" | grep -q '<more reads=' \
    && ok "flags: at exactly cap+1 the <more/> element is PRESENT (the vanishing case)" \
    || no "flags: at exactly cap+1 the <more/> element vanished — one read site dropped unmarked"

# --detail lifts the cap entirely: every row printed, no <more/> anywhere
"$BIN" "$FIX" --flags --detail=1 --no-cache >"$TMP/flagsdetail" 2>/dev/null
grep -q '<more reads=' "$TMP/flagsdetail" \
    && no "flags --detail=1 still truncated (a lifted cap must print every row)" \
    || ok "flags --detail=1: cap lifted, no <more/> at all"

# ── 2) --doc-drift: drifted anchors per doc ───────────────────────────────────────────────────────────
# Each doc names ONE real symbol (so its file:line anchors are checked, not skipped) at a line far past the
# end of a two-line file — every anchor is past-eof, i.e. drift, and the count is exactly what we wrote.
DFIX="$TMP/driftfix"; mkdir -p "$DFIX"
printf '#pragma once\nvoid moreAnchorTarget();\n' >"$DFIX/code.h"
for total in 11 12 13 15; do
    {
        echo "# Anchor budget doc ($total)"
        echo
        i=0
        while [ "$i" -lt "$total" ]; do
            echo "- \`moreAnchorTarget\` is at code.h:$(( 900 + i ))."
            i=$(( i + 1 ))
        done
    } >"$DFIX/doc$total.md"
done

"$BIN" "$DFIX" --doc-drift --no-cache >"$TMP/drift" 2>/dev/null
DR="$( cat "$TMP/drift" )"

doc(){ element "$DR" "<doc p=\"doc$1.md\"" doc; }
doc_drift_attr(){ doc "$1" | sed -n 's/.*drift="\([0-9]*\)".*/\1/p' | head -1; }
doc_rows(){ doc "$1" | grep -c '<a k=' || true; }
doc_more(){ doc "$1" | sed -n 's/.*<more drift="\([0-9]*\)".*/\1/p' | head -1; }

for total in 11 12 13 15; do
    declared="$( doc_drift_attr "$total" )"
    rows="$( doc_rows "$total" )"
    more="$( doc_more "$total" )"
    [ -z "$more" ] && more=0
    want_rows="$total"; [ "$total" -gt "$DRIFT_CAP" ] && want_rows="$DRIFT_CAP"
    want_more=$(( total - want_rows ))

    [ "$declared" = "$total" ] \
        && ok "doc-drift doc$total.md: element declares drift=\"$total\"" \
        || no "doc-drift doc$total.md: declares drift=\"$declared\", fixture wrote $total drifting anchors"
    [ "$rows" = "$want_rows" ] \
        && ok "doc-drift doc$total.md: printed $rows <a/> rows (cap $DRIFT_CAP)" \
        || no "doc-drift doc$total.md: printed $rows <a/> rows, expected $want_rows"
    [ "$more" = "$want_more" ] \
        && ok "doc-drift doc$total.md: <more drift=\"$want_more\"/> — printed + more == declared" \
        || no "doc-drift doc$total.md: <more drift=\"$more\"/>, expected $want_more (printed $rows of $total)"
    [ $(( rows + more )) = "$total" ] \
        && ok "doc-drift doc$total.md: nothing dropped without a number ($rows + $more = $total)" \
        || no "doc-drift doc$total.md: $rows printed + $more more != $total declared — rows vanished unmarked"
done

doc "13" | grep -q '<more drift=' \
    && ok "doc-drift: at exactly cap+1 the <more/> element is PRESENT (the vanishing case)" \
    || no "doc-drift: at exactly cap+1 the <more/> element vanished — one anchor dropped unmarked"

"$BIN" "$DFIX" --doc-drift --detail=1 --no-cache >"$TMP/driftdetail" 2>/dev/null
grep -q '<more drift=' "$TMP/driftdetail" \
    && no "doc-drift --detail=1 still truncated (a lifted cap must print every row)" \
    || ok "doc-drift --detail=1: cap lifted, no <more/> at all"

# ── 3) both outputs stay well-formed and deterministic ────────────────────────────────────────────────
for pair in "flagsfix --flags" "driftfix --doc-drift"; do
    set -- $pair
    "$BIN" "$TMP/$1" "$2" --no-cache >"$TMP/det1" 2>/dev/null
    "$BIN" "$TMP/$1" "$2" --no-cache >"$TMP/det2" 2>/dev/null
    cmp -s "$TMP/det1" "$TMP/det2" && ok "$2: byte-identical run to run" || no "$2 is non-deterministic"
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$TMP/det1" 2>/dev/null && ok "$2: G4 xmllint clean" || no "$2: output is not well-formed XML"
    fi
done

[ $fail -eq 0 ] && echo "morecontractcheck: ALL PASS" || echo "morecontractcheck: FAILURES"
exit $fail
