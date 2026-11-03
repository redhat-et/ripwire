#!/usr/bin/env bash
# stdmembergatecheck.sh — a C++ call named like a standard container or string member, on a receiver no rule ties to an in-tree class, never
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
# whose recorded written type names an in-tree class that may define the callee (an alias of the in-tree container, the
# pointee of a smart pointer's `->`, a namespace-scope variable's type — arms C, H, W).
#
# THE FIXTURE (test/stdmembergatefix/, see its README). Arms:
#   (A) typed receivers keep their edges, unhedged: a typed local, parameter, pointer, member field, a smart pointer's `->`,
#       `this->` and an implicit-this call inside the class, `Solo so; so.append()` (the tree's ONLY append) and `Pool& p`
#   (B) std-written or untyped receivers are declined and disclosed: std::vector local / parameter / field, `auto`, a call
#       result, a std::string's append (ONE in-tree definition), a std::vector's empty (reaching an anonymous-namespace class
#       in another file), a local declared with an alias of a standard map — each callees answer has no in-tree row, the
#       exact declined_calls= and the exact <stdm> line; a call the ladder itself declines (tier 3, far/) is on the line too
#   (C) a local declared with an alias of the in-tree Vec keeps the ladder's via="name" hedge (the alias's cone reaches Vec)
#   (H) field receivers: `this->items_` and `b.items_` (Box& b) written as Vec keep the hedge, std fields are declined; a
#       subscript of a std::vector<Vec<int>> reads its element type and keeps the hedge (arm X); a dereference, a range-for
#       `auto` and a template parameter are the stated floor (declined)
#   (W) written types beyond Rule 2's tables (wrap/): a `->` through std::unique_ptr / shared_ptr / optional of ns::List, an
#       in-tree SP<T> with its own operator->, a Qt or boost pointer (a class the tree does not define), a smart-pointer root
#       one field hop off, namespace-scope / file-static / extern variables written ns::List, and a typedef or using alias of
#       a std smart pointer (or of an undefined wrapper) keep the hedge; std-argument smart pointers, raw pointers to std
#       containers (an alias of one included), `.` on std::vector<ns::List>, an in-tree class with no operator->, a
#       std-written global and a global hidden by a local or a field stay declined; call results, an iterator, an
#       unqualified template's arguments, a std::optional member field and a typedef inside a function body are the stated
#       floor (declined)
#   (X) element receivers (elem/): ONE element access — `c[ k ]`, `c.at( k )`, `c.front()`, `c.back()` — of a container whose
#       recorded written type is a std sequence container or map of EvalString keeps the hedge: a class-scoped typedef'd map
#       field through a std::unique_ptr local (`rule->bindings_[ k ].empty()`), a std::map / std::vector field, a local map, a
#       const map parameter's at(), an unordered_map, a vector's back()/front(), a typedef (and a typedef of it) of a vector,
#       an extern map, a bare and a `this->` field inside the class; near-misses stay declined: an element written in std
#       (map<string, string>, vector<string>, map<K, vector<EvalString>> — the element's own member), an element class with
#       no candidate, the container's own member, an in-tree template's own operator[], a local hiding the field; two element accesses, an iterator's ->second and a range-for `auto` are
#       the stated floor (declined)
#   (D) controls: a name outside the table (`grow`) keeps the ladder; a bare `size( b )` binds the free function; a C
#       function-pointer call (C has no member functions) and a Go call (Go's row is EMPTY) are unchanged
#   (R) the Rust row (rsgate/): `v.push()` / `v.iter()` on Vec parameters and a parameter of an undefined type are declined
#       with their <stdm> line; `self.iter()` inside the defining impl stays proven; a name outside the table and a name with no
#       in-tree definition are untouched, a qualified `Stack::push( s, 1 )` keeps its edge. FLIPPED by lane rust-receivers (Rust
#       records receiver types): a parameter, local or field WRITTEN as the in-tree Stack / Book (stack_param, stack_local,
#       rsgate/lib.rs:add's self.inner, book_iter, not_in_table's frobnicate) now BINDS that type's method, unhedged, and the
#       (R) --callers counts fall with them; vec_param / vec_iter / std_vec stay declined (their receivers are std types).
#       STATED FLOOR (lane L6): a generic bounded by an in-tree trait (generic_bound, P: Pushable) is still declined.
#   (E) the callers side: Vec::push_back keeps exactly its typed callers and hedges and counts the ten declined calls; the one-def
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

PB='lib/vec.h:8:Vec::push_back lib/vec.h:9:Vec::push_back'   # Vec's two push_back overloads, as a callees answer lists them

# ── (A) typed receivers keep their edges ──────────────────────────────────────────────────────────────────────
echo "=== (A) a receiver a rule types keeps its edge, unhedged ==="
check "(A) typed local Vec<int> v; v.push_back()"              callees typedLocal          "$PB" '' ''
check "(A) typed parameter Vec<int>& v"                        callees typedParam          "$PB" '' ''
check "(A) typed pointer Vec<int>* p; p->push_back()"          callees typedPtr            "$PB" '' ''
check "(A) member field Vec<int> items_ (Rule 2b)"             callees app/use.cpp:add     "$PB" '' ''
check "(A) smart pointer field owned_->push_back() (Rule 2b, ->)" callees app/use.cpp:addOwned "$PB" '' ''
check "(A) implicit-this and this-> calls inside Vec"          callees pushTwice           "$PB" '' ''
check "(A) Solo so; so.append() keeps the tree's only append"  callees soloTyped           'lib/vec.h:27:Solo::append' '' ''
check "(A) Pool& p; p.clear()"                                 callees poolTyped           'lib/vec.h:22:Pool::clear' '' ''

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
                                                               callees aliasTyped          'lib/vec.h:8:Vec::push_back~ lib/vec.h:9:Vec::push_back~' '' ''

# ── (H) field and expression receivers (sib/) ───────────────────────────────────────────────────────────────
echo "=== (H) a field written as the in-tree Vec keeps the hedge; std fields and expression receivers are declined ==="
check "(H) this->items_.push_back() (a field written Vec<int>) keeps the ladder's via=\"name\" hedge" \
                                                               callees sib/sib.cpp:thisField 'lib/vec.h:8:Vec::push_back~ lib/vec.h:9:Vec::push_back~' '' ''
check "(H) b.items_.push_back() on Box& b (one field hop off a typed root) keeps the hedge" \
                                                               callees fieldOfVar          'lib/vec.h:8:Vec::push_back~ lib/vec.h:9:Vec::push_back~' '' ''
check "(H) this->raw_.push_back() (a field written in std) is declined" \
                                                               callees sib/sib.cpp:thisRaw '' 1 'push_back:1'
check "(H) b.raw_.push_back() (a std field one hop off a typed root) is declined" \
                                                               callees fieldOfVarRaw       '' 1 'push_back:1'
check "(H) STATED FLOOR: ( *p ).push_back() — a dereference carries no written type, declined" \
                                                               callees derefPtr            '' 1 'push_back:1'
check "(H) vs[ 0 ].push_back() on std::vector<Vec<int>>& — the element type reaches Vec, keeps the hedge (arm X)" \
                                                               callees subscript           'lib/vec.h:8:Vec::push_back~ lib/vec.h:9:Vec::push_back~' '' ''
check "(H) STATED FLOOR: for( auto& v : vs ) v.push_back() — a range-for auto, declined" \
                                                               callees rangeFor            '' 1 'push_back:1'
check "(H) template parameter C& c; c.push_back() — the receiver may be anything, declined" \
                                                               callees tmplParam           '' 1 'push_back:1'

# ── (W) written types beyond Rule 2's tables (wrap/) ─────────────────────────────────────────────────────────
echo "=== (W) a recorded written type that names ns::List keeps the hedge; one that does not stays declined ==="
LS='wrap/list.h:9:List::size~'; LF='wrap/list.h:10:List::find~'; LR='wrap/list.h:11:List::front~'
check "(W) std::unique_ptr<ns::List> up; up->size() — the smart pointer's argument keeps the hedge"  callees uniqueLocal        "$LS" '' ''
check "(W) const std::shared_ptr<ns::List>& p; p->size()"                                          callees sharedParam        "$LS" '' ''
check "(W) std::optional<ns::List> o; o->find()"                                                    callees optionalLocal      "$LF" '' ''
check "(W) SP<ns::List>& p; p->size() — an in-tree class with its own operator->"                   callees inTreeWrapper      "$LS" '' ''
check "(W) SP<ns::List> p; p->front() (a local)"                                                    callees inTreeWrapperLocal "$LR" '' ''
check "(W) QSharedPointer<ns::List>& p; p->front() — a class the tree does not define, its -> unknown" callees qtWrapper      "$LR" '' ''
check "(W) boost::shared_ptr<ns::List>& p; p->find()"                                               callees boostWrapper       "$LF" '' ''
check "(W) std::unique_ptr<Box2> b; b->items_.size() — a smart-pointer root, one field hop"         callees smartRootField     "$LS" '' ''
check "(W) ns::List g_list; g_list.size() — a namespace-scope variable"                             callees globalVar          "$LS" '' ''
check "(W) namespace app { ns::List nsVar; } nsVar.front()"                                         callees nsGlobalVar        "$LR" '' ''
check "(W) static ns::List fileStatic; fileStatic.find()"                                           callees fileStaticVar      "$LF" '' ''
check "(W) extern ns::List g_ext (declared in the included list.h); g_ext.size()"                   callees externVar          "$LS" '' ''
check "(W) near-miss: std::unique_ptr<std::string> p; p->size() stays declined"                     callees uniqueStd          '' 1 'size:1'
check "(W) near-miss: std::vector<int>* pv; pv->size() stays declined"                              callees rawStdPtr          '' 1 'size:1'
check "(W) near-miss: std::unique_ptr<std::vector<int>> up; up->size() stays declined"              callees uniqueStdVec       '' 1 'size:1'
check "(W) near-miss: std::vector<ns::List> v; v.size() — the container's own member, declined"     callees vectorOfList       '' 1 'size:1'
check "(W) near-miss: std::vector<ns::List>* pv; pv->size() — a raw pointer to the container, declined" callees rawVectorOfListPtr '' 1 'size:1'
check "(W) near-miss: Plain* p; p->size() — an in-tree class with no operator-> reaches no candidate" callees plainPtr         '' 1 'size:1'
check "(W) near-miss: std::string g_str; g_str.size() — a namespace-scope variable written in std"   callees globalStd          '' 1 'size:1'
check "(W) near-miss: a local std::string g_list hides the namespace-scope ns::List g_list"          callees shadowedGlobal     '' 1 'size:1'
check "(W) near-miss: a std::string field g_list hides the namespace-scope ns::List g_list"          callees fieldHidesGlobal   '' 1 'size:1'
check "(W) near-miss: a std::vector field g_list (no recorded field type) hides it too"             callees stdFieldHidesGlobal '' 1 'size:1'
check "(W) STATED FLOOR: h.list().size() — a call result carries no recorded type, declined"         callees callResult         'wrap/use.cpp:53:Holder2::list~' 1 'size:1'
check "(W) v.front().size() on std::vector<ns::List>& — the element keeps the hedge (arm X); v.front() itself is the container's member" callees frontOfVector "$LS" 1 'front:1'
check "(W) STATED FLOOR: auto it = v.begin(); it->size() — an iterator, declined"                    callees iteratorArrow      '' 1 'size:1'
check "(W) STATED FLOOR: QList<ns::List>& l; l.size() — an unqualified template's arguments are not recorded" callees unqualifiedTemplate '' 1 'size:1'
check "(W) typedef std::shared_ptr<ns::List> ListSP; ListSP p; p->size() — a typedef reads its recorded alias target" callees typedefSharedLocal "$LS" '' ''
check "(W) const ListSP& p; p->size() (the typedef, a parameter)"                                    callees typedefSharedParam "$LS" '' ''
check "(W) typedef std::unique_ptr<ns::List> ListUP; ListUP p; p->front()"                          callees typedefUniqueLocal "$LR" '' ''
check "(W) ListUP& p; p->find() (the unique_ptr typedef, a parameter)"                               callees typedefUniqueParam "$LF" '' ''
check "(W) using ListUsingSP = std::shared_ptr<ns::List>; p->size() — the same rule for using"      callees usingSharedLocal   "$LS" '' ''
check "(W) using QtListSP = QSharedPointer<ns::List>; p->front() — an alias of an undefined wrapper" callees usingQtAliasLocal  "$LR" '' ''
check "(W) a field typed by a class-scoped typedef of std::shared_ptr<ns::List>; p_->size() — lane iface-peel: the alias's pointee types the member through '->' (a typed edge, no hedge)" callees typedefField 'wrap/list.h:9:List::size' '' ''
check "(W) Owner4::Ptr p; p->size() — a class-scoped typedef, a parameter"                           callees classScopedTypedef "$LS" '' ''
check "(W) accepted cost: typedef std::unique_ptr<std::string> StrUP; p->size() keeps the hedge (the record holds no argument; as using StrPtr)" callees typedefStrUP "$LS" '' ''
check "(W) near-miss: typedef std::vector<int> IntVec; IntVec v; v.size() stays declined"             callees typedefVecDot      '' 1 'size:1'
check "(W) near-miss: IntVec* p; p->size() — a raw pointer to a std alias, declined"                 callees typedefVecPtrArrow '' 1 'size:1'
check "(W) near-miss: using IntVecUsing = std::vector<int>; IntVecUsing* p; p->size() — declined by the same rule" callees usingVecPtrArrow '' 1 'size:1'
check "(W) STATED FLOOR: std::optional<ns::List> o_ (a member field); o_->size() — a field's arguments are read for unique_ptr/shared_ptr alone" callees optionalField '' 1 'size:1'
check "(W) STATED FLOOR: a typedef inside a function body records no alias target; p->size() declined" callees localTypedef     '' 1 'size:1'

# ── (X) element receivers (elem/) ────────────────────────────────────────────────────────────────────────────
echo "=== (X) one element access of a container whose recorded element type is EvalString keeps the hedge ==="
EE='elem/eval.h:14:EvalString::empty~ elem/eval.h:19:Piece::empty~'   # EvalString::empty and Piece::empty, the by-name candidates in reach
check "(X) auto rule = std::unique_ptr<Rule>(…); rule->bindings_[ k ].empty() — a class-scoped typedef of std::map<…, EvalString, …>" \
                                                               callees elem/use.cpp:ruleSubscript "$EE" '' ''
check "(X) Rule& r; r.direct_[ \"a\" ].empty() — a field written std::map<std::string, EvalString>" callees elem/use.cpp:refDirect "$EE" '' ''
check "(X) Rule& r; r.vec_[ 0 ].empty() — a field written std::vector<EvalString>" callees elem/use.cpp:refVector  "$EE" '' ''
check "(X) a local std::map<std::string, EvalString> m; m[ \"a\" ].empty()"          callees elem/use.cpp:localMap     "$EE" '' ''
check "(X) const std::map<…, EvalString>& m; m.at( \"a\" ).empty()"                  callees elem/use.cpp:constMapAt   "$EE" '' ''
check "(X) std::unordered_map<std::string, EvalString> m; m[ \"a\" ].empty()"        callees elem/use.cpp:unorderedMap "$EE" '' ''
check "(X) std::vector<EvalString>& v; v.back().empty()"                                callees elem/use.cpp:vectorBack   "$EE" '' ''
check "(X) std::vector<EvalString>& v; v.front().empty() — front itself is the container's member" callees elem/use.cpp:vectorFront "$EE" 1 'front:1'
check "(X) typedef std::vector<EvalString> EvalList; EvalList& v; v[ 0 ].empty()"       callees elem/use.cpp:typedefList  "$EE" '' ''
check "(X) typedef EvalList EvalList2; EvalList2& v; v.at( 0 ).empty() — alias to alias" callees elem/use.cpp:typedefOfTypedef "$EE" '' ''
check "(X) extern std::map<int, EvalString> g_table; g_table[ 1 ].empty()"              callees elem/use.cpp:globalTable  "$EE" '' ''
check "(X) bindings_[ k ].empty() inside Rule — a bare field of the caller's class"      callees elem/eval.h:own           "$EE" '' ''
check "(X) this->bindings_[ k ].empty() inside Rule"                                    callees elem/eval.h:ownThis       "$EE" '' ''
check "(X) near-miss: std::map<std::string, std::string> field; r.strs_[ \"a\" ].empty() stays declined" callees elem/use.cpp:mapOfString '' 1 'empty:1'
check "(X) near-miss: std::vector<std::string>& v; v[ 0 ].empty() stays declined"      callees elem/use.cpp:vectorOfString '' 1 'empty:1'
check "(X) near-miss: std::map<K, std::vector<EvalString>>& byName; byName[ k ].empty() — the element is a std vector, declined" callees elem/use.cpp:mapOfVector '' 1 'empty:1'
check "(X) near-miss: std::vector<Other> field; r.others_[ 0 ].empty() — Other's cone holds no candidate, declined" callees elem/use.cpp:elementNoMember '' 1 'empty:1'
check "(X) near-miss: r.vec_.empty() — the container's own member, declined"            callees elem/use.cpp:containerItself '' 1 'empty:1'
check "(X) near-miss: ns::Grid<EvalString>& g; g[ 0 ].empty() — an in-tree template's own operator[], not a std element, declined" callees elem/use.cpp:inTreeTemplate '' 1 'empty:1'
check "(X) near-miss: a local std::vector<std::string> bindings_ hides the field inside Rule; bindings_[ 0 ].empty() declined" callees elem/eval.h:localHidesField '' 1 'empty:1'
check "(X) STATED FLOOR: grid[ 1 ][ 0 ].empty() — two element accesses, declined"    callees elem/use.cpp:twoLevels    '' 1 'empty:1'
check "(X) STATED FLOOR: m.find( \"a\" )->second.empty() — an iterator (a call result), declined" callees elem/use.cpp:iteratorSecond '' 2 'empty,find:2'
check "(X) STATED FLOOR: for( auto& e : v ) e.empty() — a range-for auto, declined"    callees elem/use.cpp:rangeForAuto '' 1 'empty:1'

# ── (D) controls ──────────────────────────────────────────────────────────────────────────────────────────────
echo "=== (D) controls: outside the table, bare calls, C and Go keep the ladder ==="
check "(D) v.grow() — grow is no standard member name, the ladder is unchanged" \
                                                               callees notInTable          'lib/vec.h:14:Vec::grow~' '' ''
check "(D) size( b ) — a bare call binds the free size, never gated" \
                                                               callees bareFree            'lib/vec.h:34:size' '' ''
check "(D) C o->size( o ) — C has no member functions, no gate" callees viaPointer         'c/ops.c:8:size~' '' ''
# (D) used to pin Rust's by-name split here as the gate's stated scope; the Rust row (arm R) replaced that scope by design.
check "(D) Go f().Len() — Go's row is EMPTY (Len/Write/String are in-tree interface methods), the ladder is unchanged" \
                                                               callees lenOfResult         'gogate/buf.go:6:Buf.Len~' '' ''

# ── (R) the Rust row ──────────────────────────────────────────────────────────────────────────────────────────
echo "=== (R) Rust: a name-only call named like a std collection/string/Option member is declined, self-typed calls stay ==="
check "(R) v.push() on a &mut Vec<i32> parameter — declined, <stdm push>" callees vec_param '' 1 'push:1'
check "(R) x.push() on a parameter of a type the tree does not define — declined" callees unknown_param '' 1 'push:1'
check "(R) v.iter() on a &Vec<i32> parameter — declined, <stdm iter>" callees vec_iter '' 1 'iter:1'
check "(R) self.iter() inside Book — proven (FE-B self), kept unhedged" callees Book::first 'rsgate/lib.rs:16:Book::iter' '' ''
check "(R) s.frobnicate() on a &Stack<i32> parameter — no std name; the written type proves Stack's (rust-receivers)" callees not_in_table 'rsgate/lib.rs:7:Stack::frobnicate' '' ''
check "(R) m.insert() with no in-tree insert in reach — nothing to decline, nothing counted" callees map_insert '' '' ''
check "(R) s.push() on a &mut Stack<i32> parameter — the written in-tree type BINDS Stack::push (rust-receivers)" callees stack_param 'rsgate/lib.rs:5:Stack::push' '' ''
check "(R) let s: Stack<i32> = Stack { .. }; s.push() — the written local binds Stack::push" callees stack_local 'rsgate/lib.rs:5:Stack::push' '' ''
check "(R) self.inner.push() with inner: Stack<i32> — the field's written type binds Stack::push" callees rsgate/lib.rs:add 'rsgate/lib.rs:5:Stack::push' '' ''
check "(R) book.iter() on a &Book parameter — binds Book::iter (an in-tree receiver named like a std member)" callees book_iter 'rsgate/lib.rs:16:Book::iter' '' ''
check "(R) old scope fixture: let mut v = Vec::new(); v.push() — declined" callees std_vec '' 1 'push:1'
check "(R) old scope fixture: let mut s = Stack { n: 0 }; s.push() — the struct literal binds Stack::push, never Queue's (rust-receivers)" callees typed_local 'rs/lib.rs:3:Stack::push' '' ''
check "(R) near-miss: Stack::push( s, 1 ) — a qualified call, never gated, keeps its edge" callees ufcs 'rsgate/lib.rs:5:Stack::push' '' ''
check "(R) STATED FLOOR (L6): p.push() on a generic P: Pushable (an in-tree trait) — not typed, still declined" callees generic_bound '' 1 'push:1'
check "(R) --callers=rsgate/lib.rs:push keeps the qualified caller and the three typed ones (add, stack_param, stack_local) and counts the three declined calls (vec_param, unknown_param, generic_bound)" \
      callers rsgate/lib.rs:push 'rsgate/lib.rs:11:Holder::add rsgate/lib.rs:20:stack_param rsgate/lib.rs:22:stack_local rsgate/lib.rs:28:ufcs' 3 ''
check "(R) --callers=Book::iter keeps the proven self call and the typed book_iter, and counts the one declined call (vec_iter)" \
      callers Book::iter 'rsgate/lib.rs:17:Book::first rsgate/lib.rs:25:book_iter' 1 ''

# ── (E) the callers side ──────────────────────────────────────────────────────────────────────────────────────
echo "=== (E) callers: the typed callers stay, the declined ones are counted ==="
check "(E) --callers=Vec::push_back is exactly its typed callers + the alias, Vec-field and element hedges; declined_calls=\"10\"" \
      callers Vec::push_back 'app/use.cpp:10:typedPtr app/use.cpp:16:Holder::add app/use.cpp:17:Holder::addOwned app/use.cpp:22:aliasTyped~ app/use.cpp:8:typedLocal app/use.cpp:9:typedParam lib/vec.h:15:Vec::pushTwice sib/sib.cpp:10:Box::thisField~ sib/sib.cpp:13:fieldOfVar~ sib/sib.cpp:20:subscript~' 10 ''
check "(E) --callers=lib/vec.h:append (one definition) keeps soloTyped; declined_calls=\"1\"" \
      callers lib/vec.h:append 'app/use.cpp:20:soloTyped' 1 ''
check "(E) --callers=Pool::clear keeps poolTyped; declined_calls=\"2\"" callers Pool::clear 'app/use.cpp:21:poolTyped' 2 ''

# ── (F) disclosure surfaces ───────────────────────────────────────────────────────────────────────────────────
echo "=== (F) the header, the legends, the dialects ==="
S="$( stats "$TMP/map.xml" )"; hdrd="$( gauge "$S" declined )"; censd="$( disp_in "$TMP/c.tsv" declined )"
if [ -n "$hdrd" ] && [ "$hdrd" -ge 11 ] && [ "$hdrd" = "${censd:-x}" ]; then ok "(F) header declined=$hdrd (>= the 11 gated calls) equals the census's declined bucket"
else no "(F) header declined=\"$hdrd\" census declined=\"$censd\" — want >= 11 and equal"; fi
grep -q 'hdr:declined=also-counts-calls-named-like-a-standard-type-member-of-their-language' "$TMP/map.xml" \
    && ok "(F) the full map legend carries the standard-member declined= clause" || no "(F) the full map legend lacks the standard-member clause"
rw --callers=Vec::push_back --legend=full >"$TMP/cl.xml"
grep -q 'It also counts a call named like a standard-type member of its language' "$TMP/cl.xml" \
    && ok "(F) the callers legend carries the declined_calls= standard-member sentence" || no "(F) the callers legend lacks the standard-member sentence"
rw --callees=stdParam --legend=full >"$TMP/ce.xml"
grep -q '<stdm n= calls=>: of declined_calls=' "$TMP/ce.xml" \
    && ok "(F) the full callees legend defines <stdm n= calls=>" || no "(F) the full callees legend does not define <stdm>"
rw --callees=stdParam >"$TMP/cec.xml"
grep -q 'stdm n= calls=: of declined_calls=' "$TMP/cec.xml" \
    && ok "(F) the compact callees legend defines stdm n= calls=" || no "(F) the compact callees legend does not define stdm"
# every surface that defines the clause also states the Rust floor (checklist 3: what the claim does NOT mean). Lane
# rust-receivers retired the old floor ("Rust records no receiver type yet": a written in-tree type now binds, arm R) and
# states the new one: a generic bound, dyn / impl Trait, a type alias, a glob of a glob, a tuple-struct field, a non-plain
# pattern and a value behind Option / Result / Rc / Arc / RefCell / Cell / Mutex / RwLock are not typed (one list, fix round 1).
# The map states it through its own clause "on-a-receiver-no-rule-tied-to-an-in-tree-class" (a Rust receiver no rule typed is
# one; the map's bytes are budgeted, readmedriftcheck G4); the other three surfaces carry the list. Train 32a (owner bytes rule
# 2026-10-21) dropped the map's separate Rust clause, which restated that clause: the arm pins both halves.
floor_missing=""
grep -q 'hdr:declined=also-counts-calls-named-like-a-standard-type-member-of-their-language([^)]*)-on-a-receiver-no-rule-tied-to-an-in-tree-class;' "$TMP/map.xml" || floor_missing="$floor_missing map"
grep -q 'Rust-receivers-no-rule-typed-stay-declined' "$TMP/map.xml" && floor_missing="$floor_missing map(restated-clause)"
grep -q 'a Rust receiver of an in-tree type that no rule typed is declined too (Rust types a parameter, local or field written or constructed as an in-tree type by its name, path or use alias, and a call result; not a generic bound, dyn or impl Trait, a type alias, a glob of a glob, a tuple-struct field, a pattern other than a plain name, or a value behind Option, Result, Rc, Arc, RefCell, Cell, Mutex or RwLock)' "$TMP/cl.xml" || floor_missing="$floor_missing callers"
grep -q 'a Rust receiver of an in-tree type that no rule typed is listed too (Rust types a parameter, local or field written or constructed as an in-tree type by its name, path or use alias, and a call result; not a generic bound, dyn or impl Trait, a type alias, a glob of a glob, a tuple-struct field, a pattern other than a plain name, or a value behind Option, Result, Rc, Arc, RefCell, Cell, Mutex or RwLock)' "$TMP/ce.xml" || floor_missing="$floor_missing callees"
grep -q 'stdm n= calls=: [^>]*(Rust: one of an in-tree type no rule typed too: a generic bound, dyn or impl Trait, a type alias, a glob of a glob, a tuple-struct field, a non-plain pattern, behind Option / Result / Rc / Arc / RefCell / Cell / Mutex / RwLock)' "$TMP/cec.xml" || floor_missing="$floor_missing compact"
[ -z "$floor_missing" ] && ok "(F) the map, callers, full callees and compact callees legends each state the Rust floor" \
    || no "(F) the Rust floor is missing from:$floor_missing"
# the retired floor is gone from every surface (a stale "no receiver type yet" would now be false)
stale=""
for f in map.xml cl.xml ce.xml cec.xml; do grep -q 'no-receiver-type-yet\|no receiver type yet\|until Rust records receiver types' "$TMP/$f" && stale="$stale $f"; done
if [ -z "$stale" ]; then ok "(F) the retired Rust floor (no receiver type yet) is on no surface"
else no "(F) the retired Rust floor is still on:$stale"; fi
rw --callees=typedLocal --legend=full >"$TMP/cen.xml"
if [ -z "$( root_tag "$TMP/cen.xml" callees )" ]; then no "(F) --callees=typedLocal produced no <callees> root — the absence below would be vacuous"
elif grep -q 'stdm' "$TMP/cen.xml"; then no "(F) a callees answer with no declined standard-member call mentions stdm"
else ok "(F) a callees answer with no such call carries neither the line nor its sentence"; fi
rw --callees=stdParam --format=columnar --legend=full >"$TMP/col.xml"
[ -s "$TMP/col.xml" ] && ! grep -q 'stdm' "$TMP/col.xml" \
    && ok "(F) the columnar callees form carries neither the line nor its sentence (rows only, as with <vrs>)" \
    || no "(F) the columnar callees form: $( grep -o 'stdm[^>]*' "$TMP/col.xml" | head -2 )"
rw --callees=stdParam --json >"$TMP/ce.json"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("stdm")=={"n":"clear,push_back,size","calls":3} and d.get("declined_calls")==3 else 1)' "$TMP/ce.json" \
    && ok "(F) --json callees carries \"stdm\":{\"n\":\"clear,push_back,size\",\"calls\":3} (the XML attribute values)" || no "(F) --json callees: $( head -c 300 "$TMP/ce.json" )"
M="$( mcp_text "$( call find_symbol '{"path":"'"$CORPUS"'","symbol":"stdParam"}' )" )"
printf '%s' "$M" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("stdm")=={"n":"clear,push_back,size","calls":3} else 1)' \
    && ok "(F) MCP find_symbol (the callees direction) carries the same \"stdm\"" || no "(F) MCP find_symbol: $( printf '%s' "$M" | head -c 300 )"
M="$( mcp_text "$( call find_referencing_symbols '{"path":"'"$CORPUS"'","symbol":"stdParam"}' )" )"
if ! printf '%s' "$M" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if "symbol" in d else 1)' 2>/dev/null; then
    no "(F) MCP find_referencing_symbols gave no answer — the absence below would be vacuous: $( printf '%s' "$M" | head -c 200 )"
elif printf '%s' "$M" | grep -q '"stdm"'; then no "(F) MCP find_referencing_symbols (callers) carries stdm"
else ok "(F) MCP find_referencing_symbols (the callers direction) carries no stdm"; fi

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
echo "=== (S) a tree the gate never declined in carries no standard-member clause ==="
BB="$ROOT/test/builtinbindfix"
"$BIN" "$BB" --no-cache --legend=full >"$TMP/bbmap.xml" 2>/dev/null
"$BIN" "$BB" --no-cache --legend=full --callers=py/pool.py:get >"$TMP/bbcl.xml" 2>/dev/null
[ -s "$TMP/bbmap.xml" ] && [ -s "$TMP/bbcl.xml" ] && ! grep -q -e 'also-counts-C++' -e 'also-counts-calls-named-like-a-standard-type-member' -e 'It also counts a C++ call named like' -e 'It also counts a call named like a standard-type member' -e 'stdm' "$TMP/bbmap.xml" "$TMP/bbcl.xml" \
    && ok "(S) builtinbindfix's map and callers legends carry no standard-member clause" || no "(S) a standard-member clause rides a tree with no such decline"

# ── (K) the predicates can fail ───────────────────────────────────────────────────────────────────────────────
echo "=== (K) the predicates can fail ==="
printf '<callees of="x" count="2"><s t="method" n="Vec::push_back" p="lib/vec.h:8" via="name"/></callees>' >"$TMP/k.xml"
[ "$( rows "$TMP/k.xml" )" = 'lib/vec.h:8:Vec::push_back~' ] && [ -z "$( stdm "$TMP/k.xml" )" ] \
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
