#!/usr/bin/env bash
# stdmembergatecheck.sh — a C++ call named like a standard container or string member, on a receiver nothing typed, never
# binds to an in-tree namesake by its name alone.
#
#   test/stdmembergatecheck.sh                          # uses build/ripwire on test/stdmembergatefix
#   RIPWIRE_BIN=asan/ripwire test/stdmembergatecheck.sh
#   test/stdmembergatecheck.sh build_base/ripwire       # the RED run (a pre-change binary)
#
# THE DEFECT. A C++ member call whose receiver no rule typed — `out.push_back( c )` on a `std::vector<char>&` parameter,
# `s.size()` on a `std::string`, `getV().empty()` — is name-only, and the ladder kept every same-file, same-directory and
# included-file definition of the name as a via="name" row. For standard container names those rows were almost all
# calls on the standard types: on this repository's own map 14 of the top 20 PageRank rows were such names
# (svector::push_back, WidePath::c_str, ElixirResolver::append, every `empty` and `find` under src/), and
# `--callees=escapeXml` listed 8 svector/TreeIndexMemo/HunkBuffer rows beside its 4 real callees.
#
# THE FIX (graph.h StdMemberGate; the names are data, src/externalnames.h kCppStdMemberNames). Such a call is DECLINED
# after the ladder decided it — no edge, the header's declined=, declined_calls= on every definition it would have bound,
# a legend clause of its own — and the caller's --callees answer names those calls once in a <stdm n= calls=> line. A
# receiver a rule types (Rule 1/2/2b, `this`, an implicit-this call, FE-B's proof) is never touched, and neither is one
# whose written non-std type reaches a candidate (an alias of the in-tree container).
#
# THE FIXTURE (test/stdmembergatefix/, see its README). Arms:
#   (A) typed receivers keep their edges, unhedged: a typed local, parameter, pointer, member field, a smart pointer's `->`,
#       `this->` and an implicit-this call inside the class, `Solo so; so.append()` (the tree's ONLY append) and `Pool& p`
#   (B) std-written or untyped receivers are declined and disclosed: std::vector local / parameter / field, `auto`, a call
#       result, a std::string's append (ONE in-tree definition), a std::vector's empty (reaching an anonymous-namespace class
#       in another file), a local declared with an alias of a standard map — each callees answer has no in-tree row, the
#       exact declined_calls= and the exact <stdm> line; a call the ladder itself declines (tier 3, far/) is on the line too
#   (C) a local declared with an alias of the in-tree Vec keeps the ladder's via="name" hedge (the alias's cone reaches Vec)
#   (D) controls: a name outside the table (`grow`) keeps the ladder; a bare `size( b )` binds the free function; a C
#       function-pointer call (C has no member functions) and the Rust by-name split (stated scope) are unchanged
#   (E) the callers side: Vec::push_back keeps exactly its typed callers and counts the five declined calls; the one-def
#       Solo::append keeps soloTyped and counts stdAppend; Pool::clear keeps poolTyped and counts two
#   (F) disclosure surfaces: the map header's declined= equals the census's declined bucket, the full map legend, the
#       callers legend and the callees legend each carry their clause, the compact callees legend defines stdm, the
#       columnar callees form carries neither the line nor its sentence, JSON and the MCP find_symbol twin carry "stdm"
#   (G) dead-code safety: on a copy outside the fixture paths (which are never dead by design), --quality-delta counts the
#       definitions whose only callers were declined as declined-call-excluded=, and --safe-delete=Shelf::empty carries
#       declined_calls="3" with dead_code_candidate="0"
#   (S) 0 bytes on a tree the gate never declined in: test/builtinbindfix's map and callers legends carry no C++ clause
#   (K) the predicates can fail: a via="name" row and a missing <stdm> line are both caught
#   (L) determinism x2, xmllint on every answer whose new clause rides, no degrade alert on stderr
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"   # a gate that builds a repo must not inherit GIT_DIR/GIT_WORK_TREE (gitenvhermeticcheck D)
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
CORPUS="$ROOT/test/stdmembergatefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "stdmembergatecheck: BIN=$BIN  CORPUS=$CORPUS"

cd "$CORPUS" || exit 2                               # every file:name selector below is relative to the root `.`
rw(){ "$BIN" . --no-cache "$@" 2>/dev/null; }

# ── helpers ───────────────────────────────────────────────────────────────────────────────────────────────────
root_tag(){ grep -oE "<$2( [^>]*)?>" "$1" | head -1; }                               # first <TAG …> start tag
attr(){ printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E 's/^[^"]*"([^"]*)"$/\1/'; }
# the <s> rows of a callers/callees document as sorted "p=:n=" items, "~" appended to a via="name" row
rows(){ grep -oE '<s [^>]*/>' "$1" | python3 -c '
import re, sys
out = set()
for line in sys.stdin:
    n = re.search( r" n=\"([^\"]*)\"", line ); p = re.search( r" p=\"([^\"]*)\"", line )
    if n and p:
        out.add( p.group( 1 ) + ":" + n.group( 1 ) + ( "~" if " via=\"name\"" in line else "" ) )
print( " ".join( sorted( out ) ) )'; }
# the <stdm> line as "names:calls" ("" when absent)
stdm(){ local t; t="$( grep -oE '<stdm [^>]*/>' "$1" | head -1 )"; [ -n "$t" ] && printf '%s:%s' "$( attr "$t" n )" "$( attr "$t" calls )"; }
# hier(verb, selector, want rows, want declined_calls, want stdm): the exact rows, declined_calls= and <stdm> line
hier(){
    local verb="$1" sel="$2" want="$3" wantd="$4" wants="$5" doc="$TMP/hier.xml"
    rw --"$verb"="$sel" >"$doc"
    local R; R="$( root_tag "$doc" "$verb" )"
    HIER_GOT="rows [$( rows "$doc" )] declined_calls=\"$( attr "$R" declined_calls )\" stdm=\"$( stdm "$doc" )\""
    [ -n "$R" ] && [ "$( rows "$doc" )" = "$want" ] && [ "$( attr "$R" declined_calls )" = "$wantd" ] && [ "$( stdm "$doc" )" = "$wants" ]
}
check(){   # label | verb | selector | want rows | want declined_calls | want stdm
    if hier "$2" "$3" "$4" "$5" "$6"; then ok "$1"; else no "$1 — got $HIER_GOT"; fi
}
stats(){ grep -oE '<!-- files=[^>]*-->' "$1" | head -1; }
gauge(){ printf '%s' "$1" | grep -oE " $2=[0-9]+" | head -1 | grep -oE '[0-9]+$'; }
disp_in(){ grep -m1 '^# dispositions ' "$1" | grep -oE " $2=[0-9]+" | head -1 | grep -oE '[0-9]+$'; }
mcp_text(){
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$1" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load( sys.stdin )
print( "__ERROR__:" + r[ "error" ].get( "message", "" ) if "error" in r else r[ "result" ][ "content" ][ 0 ][ "text" ] )
'
}
call(){ printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2"; }

# the census and the full-legend map the header arms read — written FIRST, so no arm reads a file that does not exist yet
"$BIN" . --no-cache --pin-census="$TMP/c.tsv" --legend=full >"$TMP/map.xml" 2>"$TMP/err" || no "(F) the map run exited non-zero"
[ -s "$TMP/c.tsv" ] || no "the census run wrote no census — the census arm below would be vacuous"
[ -s "$TMP/map.xml" ] || no "the map run wrote nothing — every header arm below would be vacuous"

PB='lib/vec.h:8:push_back lib/vec.h:9:push_back'   # Vec's two push_back overloads, as a callees answer lists them

# ── (A) typed receivers keep their edges ──────────────────────────────────────────────────────────────────────
echo "=== (A) a receiver a rule types keeps its edge, unhedged ==="
check "(A) typed local Vec<int> v; v.push_back()"              callees typedLocal          "$PB" '' ''
check "(A) typed parameter Vec<int>& v"                        callees typedParam          "$PB" '' ''
check "(A) typed pointer Vec<int>* p; p->push_back()"          callees typedPtr            "$PB" '' ''
check "(A) member field Vec<int> items_ (Rule 2b)"             callees app/use.cpp:add     "$PB" '' ''
check "(A) smart pointer field owned_->push_back() (Rule 2b, ->)" callees app/use.cpp:addOwned "$PB" '' ''
check "(A) implicit-this and this-> calls inside Vec"          callees pushTwice           "$PB" '' ''
check "(A) Solo so; so.append() keeps the tree's only append"  callees soloTyped           'lib/vec.h:27:append' '' ''
check "(A) Pool& p; p.clear()"                                 callees poolTyped           'lib/vec.h:22:clear' '' ''

# ── (B) std-written or untyped receivers are declined and disclosed ───────────────────────────────────────────
echo "=== (B) a receiver written in std, or typed by nothing, binds no in-tree namesake ==="
check "(B) std::vector<int> v; v.push_back()"                  callees stdLocal            '' 1 'push_back:1'
check "(B) std::vector<char>& out / const std::string& s: push_back, reserve(s.size()), clear" \
                                                               callees stdParam            '' 3 'clear,push_back,size:3'
check "(B) auto v = std::vector<int>(); v.push_back()"         callees autoLocal           '' 1 'push_back:1'
check "(B) getV().push_back() — the call result binds no Vec, getV stays" \
                                                               callees chained             'app/use.cpp:28:getV' 1 'push_back:1'
check "(B) std::string& s; s.append() — ONE in-tree append, still declined" \
                                                               callees stdAppend           '' 1 'append:1'
check "(B) std::vector field raw_.push_back() (a field written in std)" \
                                                               callees app/use.cpp:addRaw  '' 1 'push_back:1'
check "(B) w.empty() on a std::vector reaches neither Vec/Pool nor another file's anonymous-namespace Shelf" \
                                                               callees stdEmpty            '' 1 'empty:1'
check "(B) StdMap m (an alias of std::map); m.clear() — the alias's cone reaches no candidate" \
                                                               callees stdAliasClear       '' 1 'clear:1'
check "(B) same-file anonymous-namespace Shelf::empty is not bound by w.empty() on a std::vector" \
                                                               callees anyEmpty            '' 1 'empty:1'
check "(B) the ladder's own tier-3 decline (no namesake in reach) is named on the <stdm> line too" \
                                                               callees farEmpty            '' 1 'empty:1'

# ── (C) an alias of the in-tree container keeps the hedge ────────────────────────────────────────────────────
echo "=== (C) a written non-std type whose cone reaches a candidate keeps the ladder's hedge ==="
check "(C) SmallV<int> a (an alias of Vec); a.push_back() stays via=\"name\" on Vec" \
                                                               callees aliasTyped          'lib/vec.h:8:push_back~ lib/vec.h:9:push_back~' '' ''

# ── (D) controls ──────────────────────────────────────────────────────────────────────────────────────────────
echo "=== (D) controls: outside the table, bare calls, C and Rust keep the ladder ==="
check "(D) v.grow() — grow is no standard member name, the ladder is unchanged" \
                                                               callees notInTable          'lib/vec.h:14:grow~' '' ''
check "(D) size( b ) — a bare call binds the free size, never gated" \
                                                               callees bareFree            'lib/vec.h:34:size' '' ''
check "(D) C o->size( o ) — C has no member functions, no gate" callees viaPointer         'c/ops.c:8:size~' '' ''
check "(D) Rust v.push() — stated scope, the by-name split is unchanged" \
                                                               callees std_vec             'rs/lib.rs:3:push~ rs/lib.rs:7:push~' '' ''

# ── (E) the callers side ──────────────────────────────────────────────────────────────────────────────────────
echo "=== (E) callers: the typed callers stay, the declined ones are counted ==="
check "(E) --callers=Vec::push_back is exactly its typed callers + the alias hedge; declined_calls=\"5\"" \
      callers Vec::push_back 'app/use.cpp:10:typedPtr app/use.cpp:16:add app/use.cpp:17:addOwned app/use.cpp:22:aliasTyped~ app/use.cpp:8:typedLocal app/use.cpp:9:typedParam lib/vec.h:15:pushTwice' 5 ''
check "(E) --callers=lib/vec.h:append (one definition) keeps soloTyped; declined_calls=\"1\"" \
      callers lib/vec.h:append 'app/use.cpp:20:soloTyped' 1 ''
check "(E) --callers=Pool::clear keeps poolTyped; declined_calls=\"2\"" callers Pool::clear 'app/use.cpp:21:poolTyped' 2 ''

# ── (F) disclosure surfaces ───────────────────────────────────────────────────────────────────────────────────
echo "=== (F) the header, the legends, the dialects ==="
S="$( stats "$TMP/map.xml" )"; hdrd="$( gauge "$S" declined )"; censd="$( disp_in "$TMP/c.tsv" declined )"
if [ -n "$hdrd" ] && [ "$hdrd" -ge 11 ] && [ "$hdrd" = "${censd:-x}" ]; then ok "(F) header declined=$hdrd (>= the 11 gated calls) equals the census's declined bucket"
else no "(F) header declined=\"$hdrd\" census declined=\"$censd\" — want >= 11 and equal"; fi
grep -q 'hdr:declined=also-counts-C++-calls-on-an-untyped-receiver' "$TMP/map.xml" \
    && ok "(F) the full map legend carries the C++ standard-member declined= clause" || no "(F) the full map legend lacks the C++ clause"
rw --callers=Vec::push_back --legend=full >"$TMP/cl.xml"
grep -q 'It also counts a C++ call written on a receiver nothing typed' "$TMP/cl.xml" \
    && ok "(F) the callers legend carries the declined_calls= C++ sentence" || no "(F) the callers legend lacks the C++ sentence"
rw --callees=stdParam --legend=full >"$TMP/ce.xml"
grep -q '<stdm n= calls=>: of declined_calls=' "$TMP/ce.xml" \
    && ok "(F) the full callees legend defines <stdm n= calls=>" || no "(F) the full callees legend does not define <stdm>"
rw --callees=stdParam >"$TMP/cec.xml"
grep -q 'stdm n= calls=: of declined_calls=' "$TMP/cec.xml" \
    && ok "(F) the compact callees legend defines stdm n= calls=" || no "(F) the compact callees legend does not define stdm"
rw --callees=typedLocal --legend=full >"$TMP/cen.xml"
grep -q 'stdm' "$TMP/cen.xml" && no "(F) a callees answer with no declined standard-member call mentions stdm" \
    || ok "(F) a callees answer with no such call carries neither the line nor its sentence"
rw --callees=stdParam --format=columnar --legend=full >"$TMP/col.xml"
[ -s "$TMP/col.xml" ] && ! grep -q 'stdm' "$TMP/col.xml" \
    && ok "(F) the columnar callees form carries neither the line nor its sentence (rows only, as with <vrs>)" \
    || no "(F) the columnar callees form: $( grep -o 'stdm[^>]*' "$TMP/col.xml" | head -2 )"
rw --callees=stdParam --json >"$TMP/ce.json"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("stdm")=={"n":["clear","push_back","size"],"calls":3} and d.get("declined_calls")==3 else 1)' "$TMP/ce.json" \
    && ok "(F) --json callees carries \"stdm\":{\"n\":[clear,push_back,size],\"calls\":3}" || no "(F) --json callees: $( head -c 300 "$TMP/ce.json" )"
M="$( mcp_text "$( call find_symbol '{"path":"'"$CORPUS"'","symbol":"stdParam"}' )" )"
printf '%s' "$M" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("stdm")=={"n":["clear","push_back","size"],"calls":3} else 1)' \
    && ok "(F) MCP find_symbol (the callees direction) carries the same \"stdm\"" || no "(F) MCP find_symbol: $( printf '%s' "$M" | head -c 300 )"
M="$( mcp_text "$( call find_referencing_symbols '{"path":"'"$CORPUS"'","symbol":"stdParam"}' )" )"
printf '%s' "$M" | grep -q '"stdm"' && no "(F) MCP find_referencing_symbols (callers) carries stdm" \
    || ok "(F) MCP find_referencing_symbols (the callers direction) carries no stdm"

# ── (G) dead-code safety ──────────────────────────────────────────────────────────────────────────────────────
echo "=== (G) a definition whose only callers were declined is no dead-code candidate ==="
# a fixture path is never dead by design (quality.h isFixturePath), so the dead-set arm runs on a copy in $TMP
QD="$TMP/qd"; rm -rf "$QD"; mkdir -p "$QD"; cp -R app lib far "$QD/" 2>/dev/null
( cd "$QD" && git init -q && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -qm base ) >/dev/null 2>&1
printf '\n' >>"$QD/app/local.cpp"
( cd "$QD" && "$BIN" . --no-cache --quality-delta >"$TMP/qd.xml" 2>/dev/null )
QR="$( root_tag "$TMP/qd.xml" quality-delta )"
if [ -n "$( attr "$QR" declined-call-excluded )" ] && [ "$( attr "$QR" declined-call-excluded )" -ge 1 ] 2>/dev/null; then
    ok "(G) --quality-delta keeps the gated calls' targets out of the dead set: declined-call-excluded=\"$( attr "$QR" declined-call-excluded )\""
else
    no "(G) --quality-delta carries no declined-call-excluded= count: ${QR:-no <quality-delta> root}"
fi
rw --safe-delete=Shelf::empty >"$TMP/sd.xml"
R="$( root_tag "$TMP/sd.xml" safe-delete )"
[ "$( attr "$R" declined_calls )" = "3" ] && [ "$( attr "$R" dead_code_candidate )" = "0" ] \
    && ok "(G) --safe-delete=Shelf::empty: declined_calls=\"3\" (two gated, one tier-3), dead_code_candidate=\"0\"" || no "(G) --safe-delete root: $R"

# ── (S) zero bytes elsewhere ──────────────────────────────────────────────────────────────────────────────────
echo "=== (S) a tree the gate never declined in carries no C++ clause ==="
BB="$ROOT/test/builtinbindfix"
"$BIN" "$BB" --no-cache --legend=full >"$TMP/bbmap.xml" 2>/dev/null
"$BIN" "$BB" --no-cache --legend=full --callers=py/pool.py:get >"$TMP/bbcl.xml" 2>/dev/null
[ -s "$TMP/bbmap.xml" ] && [ -s "$TMP/bbcl.xml" ] && ! grep -q -e 'also-counts-C++' -e 'C++ call written on a receiver' -e 'stdm' "$TMP/bbmap.xml" "$TMP/bbcl.xml" \
    && ok "(S) builtinbindfix's map and callers legends carry no C++ standard-member clause" || no "(S) a C++ clause rides a tree with no C++ decline"

# ── (K) the predicates can fail ───────────────────────────────────────────────────────────────────────────────
echo "=== (K) the predicates can fail ==="
printf '<callees of="x" count="2"><s t="method" n="push_back" p="lib/vec.h:8" via="name"/></callees>' >"$TMP/k.xml"
[ "$( rows "$TMP/k.xml" )" = 'lib/vec.h:8:push_back~' ] && [ -z "$( stdm "$TMP/k.xml" )" ] \
    && ok "(K) a via=\"name\" row reads as one and a missing <stdm> line reads as empty" || no "(K) the row/stdm readers are blind"

# ── (L) determinism, well-formedness, stderr ──────────────────────────────────────────────────────────────────
echo "=== (L) determinism x2, xmllint, stderr ==="
rw --legend=full >"$TMP/map2.xml"
"$BIN" . --no-cache --legend=full >"$TMP/map3.xml" 2>/dev/null
rw --callees=stdParam --legend=full >"$TMP/ce2.xml"
if cmp -s "$TMP/map2.xml" "$TMP/map3.xml" && cmp -s "$TMP/ce.xml" "$TMP/ce2.xml"; then ok "(L) map and callees byte-identical across two runs"
else no "(L) nondeterministic output"; fi
if command -v xmllint >/dev/null 2>&1; then
    for f in map.xml cl.xml ce.xml cec.xml col.xml; do
        if xmllint --noout "$TMP/$f" 2>/dev/null; then ok "(L) xmllint $f"; else no "(L) xmllint $f is not well-formed"; fi
    done
else
    echo "  SKIP  (L) xmllint not installed"
fi
grep -q -i -e 'DISCLOSE' -e 'buildGraph:' "$TMP/err" && no "(L) a degrade alert on stderr: $( head -c 200 "$TMP/err" )" || ok "(L) no degrade alert on stderr"

if [ "$fail" -ne 0 ]; then echo "SOME FAILED"; exit 1; fi
echo "ALL PASS"
