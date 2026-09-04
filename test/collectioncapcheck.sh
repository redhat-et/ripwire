#!/usr/bin/env bash
# collectioncapcheck.sh — capture-audit 2026-09-04, H8 (lens 4 HIGH/MED, lens 1 F5): an INTERNAL COLLECTION
# CAP must never be presented as a complete last page, and a root floor flag must be the OR of the children
# the document actually EMITS.
#
# THE DEFECT, quoted from the audited binary (docs/captures/COMMANDS_showcase_2026-09-04.md):
#     --match='(call_expression)' --limit=99999999
#       <match hits="5000" shown="5000" capped="0" total="5000" has_more="0" next_offset="5000" … hits_capped="1" …>
#     --lint --limit=99999999
#       <lint findings="3717" shown="3717" capped="0" total="3717" has_more="0" … findings_capped="1" …>
#     --lint --lint-select=cache-
#       <lint findings="398" shown="398" capped="0" findings_capped="1" selected="8 of 39" …>   every <rule> row uncapped
# The first two say, on ONE element, "the total is a floor" (hits_capped=/findings_capped=, pageview.h rule 4)
# and "you have seen everything" (capped="0" has_more="0") — an agent looping on has_more stops believing it
# saw every call expression in the corpus. The third inherits findings_capped="1" from the UNSELECTED
# magic-number rule, so a reader must take 398 as a floor when, by the verb's own definition, it is a total.
#
# THE RULE (pageview.h, THE TRUNCATION VOCABULARY rule 4, amended):
#   (i)  whenever a collection cap fired, the root carries counts_floor="1" (every count on this element is
#        a floor — the CAUSE is the sibling rule-4 marker) and capped="1" (rows exist that no page holds);
#        it never says has_more="0" capped="0";
#   (ii) a root floor flag derived from children == OR(child flags) over the EMITTED children, after any
#        select/ignore/scope filter.
#
# ARMS
#   (A) --match on this repo (>5000 call_expression nodes: the engine cap fires) — bare, --limit=99999999,
#       and a paged window: hits_capped="1" ⇒ counts_floor="1" ∧ capped="1"; presence-guarded.
#   (B) --lint on this repo (magic-number saturates its per-rule budget): the same three shapes on
#       findings_capped=.
#   (C) --lint --lint-select / --lint-ignore: root findings_capped == OR(<rule count_capped=>) over the
#       emitted rows, for the plain run, a select that drops the capped rule, and an ignore of it; and the
#       SARIF twin's run-level findingsCapped agrees with the XML root under the same select.
#   (D) SOURCE PROPERTY, presence-guarded: every statement in src/ that emits a rule-4 marker
#       (hits_capped= / findings_capped=) either passes the cap into pageDisclosure under the
#       /*collectionCapped=*/ annotation or splices the floor constant itself — so the next verb that grows
#       a collection cap cannot present it as a complete page without redding this arm.
#   (E) mutation — each assertion shape can fail.  (G4) every captured document is xmllint-clean.
#
# RED-FIRST: against the audited binary (A) and (B) fail on all three shapes and (C) fails the select arm;
# (D) fails on every emitter. Usage: bash test/collectioncapcheck.sh [BIN]   (RIPWIRE_BIN honoured).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "collectioncapcheck: python3 required"; exit 2; }
cd "$ROOT"
echo "collectioncapcheck: BIN=$BIN"

# rootOf FILE — the first start-tag AFTER the leading legend comments (never a legend's worded example).
rootOf(){ perl -0pe 's#<!--.*?-->##gs' "$1" | grep -oE '<[a-zA-Z][a-zA-Z_-]*( [^>]*)?>' | head -1; }
attr(){ printf '%s' "$1" | sed -nE "s/.* $2=\"([^\"]*)\".*/\1/p"; }

# capFloor LABEL ROOT MARKER — rule (i) on one root element whose rule-4 MARKER fired.
capFloor(){
    local label="$1" root="$2" marker="$3"
    local fired; fired="$( attr "$root" "$marker" )"
    if [ "$fired" != "1" ]; then
        no "$label: presence guard — $marker=\"${fired:-<absent>}\" did not fire on this corpus, the arm asserts nothing ($root)"
        return
    fi
    [ "$( attr "$root" counts_floor )" = "1" ] \
        && ok "$label: $marker=\"1\" ⇒ counts_floor=\"1\" on the root" \
        || no "$label: $marker=\"1\" but NO counts_floor=\"1\" — the total is presented as exact: $root"
    [ "$( attr "$root" capped )" = "1" ] \
        && ok "$label: $marker=\"1\" ⇒ capped=\"1\" (rows exist that no page holds)" \
        || no "$label: $marker=\"1\" beside capped=\"$( attr "$root" capped )\" — a fired cap presented as an uncut listing: $root"
    if [ "$( attr "$root" has_more )" = "0" ] && [ "$( attr "$root" capped )" = "0" ]; then
        no "$label: has_more=\"0\" capped=\"0\" on a root whose $marker fired — the complete-last-page lie"
    else
        ok "$label: never has_more=\"0\" capped=\"0\" beside a fired $marker"
    fi
}

echo
echo "=== (A) --match: the engine hit cap (kMatchMaxHits) presented honestly ==="
"$BIN" . --match='(call_expression)' >"$TMP/match_bare.xml" 2>/dev/null
"$BIN" . --match='(call_expression)' --limit=99999999 >"$TMP/match_all.xml" 2>/dev/null
"$BIN" . --match='(call_expression)' --limit=3 --offset=3 >"$TMP/match_page.xml" 2>/dev/null
capFloor "(A) match bare"           "$( rootOf "$TMP/match_bare.xml" )" hits_capped
capFloor "(A) match --limit=99999999" "$( rootOf "$TMP/match_all.xml" )"  hits_capped
capFloor "(A) match --limit=3 --offset=3" "$( rootOf "$TMP/match_page.xml" )" hits_capped
# and the un-capped control: a query well under the engine cap says hits_capped="0" and carries NO floor.
"$BIN" . --match='(namespace_definition)' >"$TMP/match_small.xml" 2>/dev/null
SMALL="$( rootOf "$TMP/match_small.xml" )"
if [ "$( attr "$SMALL" hits_capped )" = "0" ]; then
    case "$SMALL" in
        *'counts_floor="1"'*) no "(A) control: an UN-capped --match carries counts_floor=\"1\" — the floor is unconditional, not a disclosure: $SMALL" ;;
        *)                    ok "(A) control: an un-capped --match (hits_capped=\"0\") carries no counts_floor=" ;;
    esac
else
    no "(A) control: (namespace_definition) tripped the engine cap on this corpus — pick a rarer node kind: $SMALL"
fi

echo
echo "=== (B) --lint: a rule's per-rule match budget (findings_capped) presented honestly ==="
"$BIN" . --lint >"$TMP/lint_bare.xml" 2>/dev/null
"$BIN" . --lint --limit=99999999 >"$TMP/lint_all.xml" 2>/dev/null
"$BIN" . --lint --limit=3 --offset=3 >"$TMP/lint_page.xml" 2>/dev/null
capFloor "(B) lint bare"              "$( rootOf "$TMP/lint_bare.xml" )" findings_capped
capFloor "(B) lint --limit=99999999"  "$( rootOf "$TMP/lint_all.xml" )"  findings_capped
capFloor "(B) lint --limit=3 --offset=3" "$( rootOf "$TMP/lint_page.xml" )" findings_capped

echo
echo "=== (C) root findings_capped == OR(emitted <rule count_capped=>) after select/ignore ==="
# The capped rule on this corpus, read off the plain run (never hard-coded: the corpus decides).
CAPPED_RULE="$( grep -oE '<rule name="[^"]+"[^>]* count_capped="1"' "$TMP/lint_bare.xml" | head -1 | sed -E 's/<rule name="([^"]+)".*/\1/' )"
if [ -z "$CAPPED_RULE" ]; then
    no "(C) presence guard — no <rule> row carries count_capped=\"1\" on this corpus; the OR property cannot be exercised"
else
    ok "(C) presence guard — '$CAPPED_RULE' saturates its per-rule budget on this corpus"
fi
# orProperty LABEL FILE — root flag == OR(emitted rule rows' count_capped)
orProperty(){
    local label="$1" f="$2"
    local root anyChild rootFlag
    root="$( rootOf "$f" )"
    anyChild="$( grep -cE '<rule name="[^"]+"[^>]* count_capped="1"' "$f" | tr -d ' ' )"
    rootFlag="$( attr "$root" findings_capped )"; rootFlag="${rootFlag:-0}"
    if { [ "$anyChild" != "0" ] && [ "$rootFlag" = "1" ]; } || { [ "$anyChild" = "0" ] && [ "$rootFlag" = "0" ]; }; then
        ok "$label: root findings_capped=$rootFlag == OR over $anyChild capped emitted rule row(s)"
    else
        no "$label: root findings_capped=$rootFlag but $anyChild emitted rule row(s) carry count_capped=\"1\" — the flag was inherited from a row this document does not print: $root"
    fi
    # rule (i) rides on the same fact: a floor on the root ⇔ a fired marker there
    local floor; floor="$( attr "$root" counts_floor )"
    if [ "$rootFlag" = "1" ] && [ "${floor:-0}" != "1" ]; then
        no "$label: findings_capped=\"1\" without counts_floor=\"1\""
    elif [ "$rootFlag" = "0" ] && [ "${floor:-0}" = "1" ]; then
        no "$label: counts_floor=\"1\" with no fired marker — a floor claimed for nothing"
    else
        ok "$label: counts_floor= agrees with findings_capped= ($rootFlag)"
    fi
}
orProperty "(C) plain --lint" "$TMP/lint_bare.xml"
if [ -n "$CAPPED_RULE" ]; then
    # a select that DROPS the capped rule (prefix 'cache-' keeps the cache pack; the capped rule is not one of them)
    SELECT_PREFIX="cache-"
    case "$CAPPED_RULE" in cache-*) SELECT_PREFIX="atom-";; esac
    "$BIN" . --lint --lint-select="$SELECT_PREFIX" >"$TMP/lint_select.xml" 2>/dev/null
    grep -qE "<rule name=\"$CAPPED_RULE\"" "$TMP/lint_select.xml" \
        && no "(C) select presence guard — --lint-select=$SELECT_PREFIX still prints the capped rule '$CAPPED_RULE'" \
        || ok "(C) select presence guard — --lint-select=$SELECT_PREFIX drops '$CAPPED_RULE'"
    orProperty "(C) --lint-select=$SELECT_PREFIX" "$TMP/lint_select.xml"
    "$BIN" . --lint --lint-ignore="$CAPPED_RULE" >"$TMP/lint_ignore.xml" 2>/dev/null
    orProperty "(C) --lint-ignore=$CAPPED_RULE" "$TMP/lint_ignore.xml"
    # a select that KEEPS the capped rule must keep the flag (the OR must not have become "always 0")
    "$BIN" . --lint --lint-select="$CAPPED_RULE" >"$TMP/lint_keep.xml" 2>/dev/null
    orProperty "(C) --lint-select=$CAPPED_RULE" "$TMP/lint_keep.xml"
    [ "$( attr "$( rootOf "$TMP/lint_keep.xml" )" findings_capped )" = "1" ] \
        && ok "(C) selecting the capped rule alone keeps findings_capped=\"1\" (the OR is live, not a constant 0)" \
        || no "(C) selecting the capped rule alone LOST findings_capped=\"1\""
    # the SARIF twin under the same select agrees with the XML root
    "$BIN" . --lint --lint-select="$SELECT_PREFIX" --sarif >"$TMP/lint_select.sarif" 2>/dev/null
    python3 - "$TMP/lint_select.sarif" <<'PY' && ok "(C) SARIF twin under --lint-select=$SELECT_PREFIX: run-level findingsCapped is false (agrees with the XML root)" \
                                             || no "(C) SARIF twin under --lint-select=$SELECT_PREFIX still says findingsCapped:true (inherited from the dropped rule)"
import json, sys
d = json.load( open( sys.argv[1] ) )
props = d[ "runs" ][ 0 ].get( "properties", {} )
sys.exit( 0 if props.get( "findingsCapped" ) in ( False, None ) else 1 )
PY
fi

echo
echo "=== (D) SOURCE PROPERTY — every rule-4 marker emitter carries the floor through the same statement ==="
python3 - "$ROOT/src" <<'PY'
import os, re, sys
src = sys.argv[1]
MARK = re.compile( r'(hits_capped|findings_capped)=\\"' )
hits, fail = 0, 0
for fn in sorted( os.listdir( src ) ):
    if not ( fn.endswith( ".h" ) or fn.endswith( ".cpp" ) ): continue
    lines = open( os.path.join( src, fn ), encoding="utf-8", errors="replace" ).read().split( "\n" )
    for i, ln in enumerate( lines ):
        if not MARK.search( ln ) or ln.lstrip().startswith( "//" ): continue
        # the enclosing STATEMENT: back to the line that opens it (printf/fprintf/snprintf/+= /=), forward to the ';'
        b = i
        while b > 0 and not re.search( r'(printf|snprintf|fprintf)\s*\(|\+=|\bkeys\s*\+=|=\s*"', lines[ b ] ): b -= 1
        e = i
        while e < len( lines ) - 1 and not lines[ e ].rstrip().endswith( ";" ): e += 1
        stmt = "\n".join( lines[ b:e + 1 ] )
        # only EMITTERS: a format directive (hits_capped=\"%d\") or a string FRAGMENT that opens with the
        # marker (" findings_capped=\"1\""); legend prose carries the same words mid-sentence and is skipped
        if not re.search( r'(hits_capped|findings_capped)=\\"%[du]\\"|" (hits_capped|findings_capped)=\\"1\\"', stmt ): continue
        hits += 1
        if "/*collectionCapped=*/" in stmt or "kGraphCountFloorAttr" in stmt:
            print( f"  PASS  (D) {fn}:{i+1} emits a rule-4 marker and carries the floor in the same statement" )
        else:
            print( f"  FAIL  (D) {fn}:{i+1} emits a rule-4 marker with no /*collectionCapped=*/ pageDisclosure argument and no floor constant in the statement" ); fail = 1
if hits == 0:
    print( "  FAIL  (D) presence guard — no rule-4 marker emitter found in src/ (the grep is broken)" ); fail = 1
else:
    print( f"  ..    (D) {hits} rule-4 marker emitter statement(s) inspected" )
sys.exit( fail )
PY
[ $? = 0 ] || fail=1

echo
echo "=== (E) MUTATION — each assertion shape can fail ==="
MUT='<match hits="5000" shown="5000" capped="0" total="5000" has_more="0" hits_capped="1">'
[ "$( attr "$MUT" hits_capped )" = "1" ] && [ "$( attr "$MUT" counts_floor )" != "1" ] \
    && ok "(E) the audited shape (hits_capped=1, no floor, has_more=0 capped=0) IS detected" \
    || no "(E) the floor assertion cannot see the audited shape"
printf '<lint findings="3" findings_capped="1"><rule name="a" count="3" count_capped="0"/></lint>' >"$TMP/mut.xml"
[ "$( grep -cE '<rule name="[^"]+"[^>]* count_capped="1"' "$TMP/mut.xml" | tr -d ' ' )" = "0" ] \
    && ok "(E) an inherited root flag over uncapped emitted rows IS detected by the OR arm's count" \
    || no "(E) the OR arm cannot see an inherited flag"

echo
echo "=== (G4) well-formedness ==="
if command -v xmllint >/dev/null 2>&1; then
    for f in match_bare match_all match_page match_small lint_bare lint_all lint_page lint_select lint_ignore lint_keep; do
        [ -s "$TMP/$f.xml" ] || continue
        xmllint --noout "$TMP/$f.xml" 2>/dev/null && ok "(G4) $f.xml is well-formed" || no "(G4) $f.xml FAILED xmllint"
    done
else
    no "(G4) xmllint is NOT INSTALLED — the arm could not run"
fi

echo
[ "$fail" -eq 0 ] && { echo "collectioncapcheck: ALL PASS"; exit 0; }
echo "collectioncapcheck: FAILURES"; exit 1
