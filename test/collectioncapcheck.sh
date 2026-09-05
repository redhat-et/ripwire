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
#   (F) tier_budget= (verify-wave1 N2; H8's enumeration named it, the arms above did not implement it): the
#       grep span-tier classification stopped under its file/byte budget, so suppressed_comment=/
#       suppressed_string=/tier_parsed= are FLOORS — the root carries counts_floor="1". NOT capped="1": every
#       hit row was served, only the classification is partial, so it does not ride pageDisclosure's
#       collectionCapped path (which would claim rows no page holds). CLI --regex on this repo + the MCP grep
#       twin (spelled ONCE even beside hits_capped), each with a no-tier control that carries no floor.
#   (G) defs_capped= (N2): --context-ratio's defs_per_name_cap= is a published CONSTANT, always present, so it
#       cannot itself be the fired marker; the cap FIRING (a name with more definitions than the cap, its extra
#       candidates uncounted) is now disclosed as defs_capped="1" and floors the root. A 9-definition fixture
#       fires it; a 2-definition control carries neither attribute.
#   (H) rows_capped= (N2, the enumeration's third name) is NOT a floor marker and the arm says so: on the --lint
#       <rule> row it is rule 3's noun-prefixed window bit over a count= the legend calls "the true total"; on
#       --skipped it marks a 500-row SAMPLE while "every count stays exact". Both are asserted to carry NO
#       counts_floor= (a floor claimed over exact counts is the same lie in the other direction), and each
#       legend must still state the count is exact.
#   (D) also sweeps the JSON spellings ("hits_capped":/"findings_capped":/"tier_budget":) and the two new XML
#       markers, so an MCP twin can no longer emit a cap marker without the floor.
#
# RED-FIRST: against the audited binary (A) and (B) fail on all three shapes and (C) fails the select arm;
# (D) fails on every emitter. (F)/(G) are RED on e3b52d3+wave-1 (tier_budget without a floor on --regex='e\w+'
# and on MCP grep; no defs_capped= at all). Usage: bash test/collectioncapcheck.sh [BIN]   (RIPWIRE_BIN honoured).

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
# N2: the XML fragments (marker=\") AND the JSON spellings (\"marker\":) — an MCP twin is an emitter too
MARK = re.compile( r'(hits_capped|findings_capped|tier_budget|defs_capped)(=\\"|\\":)' )
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
        if not re.search( r'(hits_capped|findings_capped)=\\"%[du]\\"|" (hits_capped|findings_capped|defs_capped)=\\"1\\"'
                          r'|" tier_budget=\\""|,\\"(hits_capped|findings_capped|tier_budget)\\":', stmt ): continue
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
echo "=== (F) tier_budget= — a partial span-tier classification floors the root (CLI + MCP), rows still whole ==="
"$BIN" . --regex='e\w+' --no-cache >"$TMP/grep_tier.xml" 2>/dev/null
GT="$( rootOf "$TMP/grep_tier.xml" )"
if [ -z "$( attr "$GT" tier_budget )" ]; then
    no "(F) presence guard — tier_budget= did not fire on --regex='e\\w+' over this repo; the arm asserts nothing ($GT)"
else
    ok "(F) presence guard — tier_budget=\"$( attr "$GT" tier_budget )\" fired on --regex='e\\w+'"
    [ "$( attr "$GT" counts_floor )" = "1" ] \
        && ok "(F) tier_budget= ⇒ counts_floor=\"1\" on the <grep> root (suppressed_*/tier_parsed= are floors)" \
        || no "(F) tier_budget=\"$( attr "$GT" tier_budget )\" fired with NO counts_floor=\"1\" — 90% of the hits were never span-classified and the root says the opposite by omission: $GT"
    [ "$( printf '%s' "$GT" | grep -o 'counts_floor=' | wc -l | tr -d ' ' )" -le 1 ] \
        && ok "(F) counts_floor= is spelled at most once on the root" \
        || no "(F) counts_floor= is spelled more than once on the root: $GT"
fi
# control: a small literal grep — no tier_budget, hits_capped="0" — carries no floor
"$BIN" . --grep=kGraphCountFloorAttrXml --no-cache >"$TMP/grep_small.xml" 2>/dev/null
GS="$( rootOf "$TMP/grep_small.xml" )"
if [ -z "$( attr "$GS" tier_budget )" ] && [ "$( attr "$GS" hits_capped )" = "0" ]; then
    case "$GS" in
        *'counts_floor="1"'*) no "(F) control: a grep with no fired marker carries counts_floor=\"1\" — the floor is unconditional: $GS" ;;
        *)                    ok "(F) control: no tier_budget=, hits_capped=\"0\" ⇒ no counts_floor= on the root" ;;
    esac
else
    no "(F) control: --grep=kGraphCountFloorAttrXml tripped a cap on this corpus — pick a rarer literal: $GS"
fi
# the MCP twin: the same two shapes, and the key spelled ONCE (a floor beside hits_capped must not double up)
python3 - "$BIN" >"$TMP/mcp_tier.out" 2>&1 <<'PY'
import json, subprocess, sys
binPath = sys.argv[ 1 ]
def call( pattern ):
    reqs = [ { "jsonrpc": "2.0", "id": 1, "method": "initialize" },
             { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": "grep", "arguments": { "path": ".", "pattern": pattern } } } ]
    out = subprocess.run( [ binPath, "--mcp" ], input = "".join( json.dumps( r ) + "\n" for r in reqs ).encode(),
                          stdout = subprocess.PIPE, stderr = subprocess.DEVNULL ).stdout.decode( "utf-8", "replace" ).strip().split( "\n" )[ -1 ]
    text = json.loads( out )[ "result" ][ "content" ][ 0 ][ "text" ]
    seen = {}
    def hook( pairs ):
        for k, _ in pairs: seen[ k ] = seen.get( k, 0 ) + 1
        return dict( pairs )
    d = json.loads( text, object_pairs_hook = hook )
    return d, seen
d, seen = call( "e" )
if "tier_budget" not in d:
    print( "FAIL (F) MCP presence guard — tier_budget absent on grep 'e' over this repo" )
else:
    print( "PASS (F) MCP presence guard — tier_budget=%r fired on grep 'e'" % d[ "tier_budget" ] )
    print( ( "PASS (F) MCP tier_budget ⇒ \"counts_floor\":true" ) if d.get( "counts_floor" ) is True else
           ( "FAIL (F) MCP tier_budget=%r with no \"counts_floor\":true (hits_capped=%r)" % ( d[ "tier_budget" ], d.get( "hits_capped" ) ) ) )
    print( ( "PASS (F) MCP counts_floor spelled once" ) if seen.get( "counts_floor", 0 ) <= 1 else ( "FAIL (F) MCP counts_floor spelled %d times" % seen[ "counts_floor" ] ) )
c, _ = call( "kGraphCountFloorAttrXml" )
if "tier_budget" in c or c.get( "hits_capped" ) is True:
    print( "FAIL (F) MCP control tripped a cap — pick a rarer literal: %s" % { k: c.get( k ) for k in ( "tier_budget", "hits_capped" ) } )
else:
    print( ( "FAIL (F) MCP control carries counts_floor with no fired marker" ) if "counts_floor" in c else ( "PASS (F) MCP control: no marker ⇒ no counts_floor" ) )
PY
while IFS= read -r line; do
    case "$line" in PASS\ *) ok "${line#PASS }" ;; FAIL\ *) no "${line#FAIL }" ;; *) no "(F) MCP probe crashed: $line" ;; esac
done <"$TMP/mcp_tier.out"

echo
echo "=== (G) defs_capped= — a name with more definitions than defs_per_name_cap= floors --context-ratio ==="
FIX9="$TMP/defs9"; mkdir -p "$FIX9"
for i in 1 2 3 4 5 6 7 8 9; do printf 'int dup( int x ) { return x + %d; }\n' "$i" >"$FIX9/dup$i.cpp"; done
printf 'int dup( int x );\nint use() { return dup( 1 ); }\n' >"$FIX9/use.cpp"
"$BIN" "$FIX9" --context-ratio --no-cache >"$TMP/cr9.xml" 2>/dev/null
CR9="$( rootOf "$TMP/cr9.xml" )"
CAPV="$( attr "$CR9" defs_per_name_cap )"
[ -n "$CAPV" ] && [ "$CAPV" -lt 9 ] 2>/dev/null \
    && ok "(G) presence guard — defs_per_name_cap=\"$CAPV\" < 9 definitions of dup: the cap must have fired" \
    || no "(G) presence guard — defs_per_name_cap=\"$CAPV\" is not below the fixture's 9 definitions; the arm asserts nothing"
[ "$( attr "$CR9" defs_capped )" = "1" ] \
    && ok "(G) defs_capped=\"1\" discloses that a name's definitions were cut at the cap" \
    || no "(G) 9 definitions of one name against a cap of $CAPV and the root carries no defs_capped=\"1\" — the cap fired invisibly: $CR9"
[ "$( attr "$CR9" counts_floor )" = "1" ] \
    && ok "(G) defs_capped=\"1\" ⇒ counts_floor=\"1\" on the root (the uncounted candidates make ents=/rtok= floors)" \
    || no "(G) the cap fired and the root carries no counts_floor=\"1\": $CR9"
perl -0pe 's#-->#-->\n#g' "$TMP/cr9.xml" | grep -q 'defs_capped=' \
    && ok "(G) the legend defines defs_capped=" \
    || no "(G) defs_capped= is emitted but the legend never defines it"
# control: two definitions — under the cap — carry neither attribute
FIX2="$TMP/defs2"; mkdir -p "$FIX2"
for i in 1 2; do printf 'int dup( int x ) { return x + %d; }\n' "$i" >"$FIX2/dup$i.cpp"; done
printf 'int dup( int x );\nint use() { return dup( 1 ); }\n' >"$FIX2/use.cpp"
"$BIN" "$FIX2" --context-ratio --no-cache >"$TMP/cr2.xml" 2>/dev/null
CR2="$( rootOf "$TMP/cr2.xml" )"
case "$CR2" in
    *defs_capped=*|*'counts_floor="1"'*) no "(G) control: 2 definitions under the cap and the root carries a fired marker or a floor: $CR2" ;;
    *) ok "(G) control: under the cap ⇒ no defs_capped=, no counts_floor=" ;;
esac

echo
echo "=== (H) rows_capped= is a SAMPLE over EXACT counts — never counts_floor (the control the enumeration needed) ==="
"$BIN" . --lint --limit=3 --no-cache >"$TMP/lint_rows.xml" 2>/dev/null
RC_ROWS="$( grep -oE '<rule [^>]*rows_capped="1"[^>]*/>' "$TMP/lint_rows.xml" | wc -l | tr -d ' ' )"
if [ "$RC_ROWS" = "0" ]; then
    no "(H) presence guard — no <rule> row carries rows_capped=\"1\" under --lint --limit=3 on this repo"
else
    ok "(H) presence guard — $RC_ROWS <rule> row(s) carry rows_capped=\"1\" under --limit=3"
    [ "$( grep -oE '<rule [^>]*rows_capped="1"[^>]*/>' "$TMP/lint_rows.xml" | grep -c 'counts_floor' )" = "0" ] \
        && ok "(H) no rows_capped=\"1\" <rule> row carries counts_floor= (its count= is the true total)" \
        || no "(H) a <rule> row with rows_capped=\"1\" carries counts_floor= — an exact count presented as a floor"
    grep -q 'count= stays the true total' "$TMP/lint_rows.xml" \
        && ok "(H) the --lint legend states that count= stays the true total beside rows_capped=" \
        || no "(H) the --lint legend no longer says count= stays the true total"
fi
# --skipped (verbs_report.h's crawl-disclosure verb): 501 files of an unsupported extension overflow its 500-row list
FIXR="$TMP/rep501"; mkdir -p "$FIXR"
printf 'int a() { return 1; }\n' >"$FIXR/a.cpp"
python3 -c 'import sys,os
d=sys.argv[1]
for i in range(501): open(os.path.join(d,"blob%03d.zzz"%i),"w").write("x\n")' "$FIXR"
"$BIN" "$FIXR" --skipped --no-cache >"$TMP/rep501.md" 2>/dev/null
REL="$( grep -oE '<[a-zA-Z_-]+ [^>]*rows_capped="1"[^>]*>' "$TMP/rep501.md" | head -1 )"
if [ -z "$REL" ]; then
    no "(H) presence guard — --skipped on 501 unsupported files carries no rows_capped=\"1\" element ($( grep -oE 'unsupported="[0-9]+"' "$TMP/rep501.md" | head -1 ))"
else
    ok "(H) presence guard — the --skipped root carries rows_capped=\"1\" on 501 unsupported files"
    case "$REL" in
        *counts_floor*) no "(H) --skipped's rows_capped=\"1\" root carries counts_floor= — a SAMPLE marker over exact counts presented as a floor: $REL" ;;
        *)              ok "(H) --skipped's rows_capped=\"1\" root carries no counts_floor= (every count stays exact)" ;;
    esac
    grep -q 'every count stays exact' "$TMP/rep501.md" \
        && ok "(H) the --skipped legend states every count stays exact beside rows_capped=" \
        || no "(H) the --skipped legend no longer says every count stays exact"
fi

echo
echo "=== (G4) well-formedness ==="
if command -v xmllint >/dev/null 2>&1; then
    for f in match_bare match_all match_page match_small lint_bare lint_all lint_page lint_select lint_ignore lint_keep grep_tier grep_small cr9 cr2 lint_rows; do
        [ -s "$TMP/$f.xml" ] || continue
        xmllint --noout "$TMP/$f.xml" 2>/dev/null && ok "(G4) $f.xml is well-formed" || no "(G4) $f.xml FAILED xmllint"
    done
else
    no "(G4) xmllint is NOT INSTALLED — the arm could not run"
fi

echo
[ "$fail" -eq 0 ] && { echo "collectioncapcheck: ALL PASS"; exit 0; }
echo "collectioncapcheck: FAILURES"; exit 1
