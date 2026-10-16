#!/usr/bin/env bash
# legotransitivecheck.sh — the --lego verb's IMPLEMENTOR CLOSURE and the edges that feed it.
#
#   test/legotransitivecheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# Corpus test/legotransitivefix (in-tree, outside test/fixture):
#   py/formatters.py  BaseFormatter <- {SimpleFormatter <- {Default, Pylint, FilenameOnly}, Nothing}
#   py/diamond.py     Top <- {Left, Right} <- Bottom (both) <- Deepest; Alone <- OnlyChild (direct rows only)
#   rb/*.rb           Rake::Task <- {FileTask <- FileCreationTask, MultiTask}; Rake::DSL mixed in
#   js/*.js, ts/*     Node.extend('BinOp', …) class factories (+ near misses); Loader defined in code AND as a docs heading
#   ns/{py,js,cpp,java,rb}  fix 1 NAMESAKES: each language holds a base, a Mid extending it, an UNRELATED same-named Mid
#                     with a Leaf below it, and a true Leaf below the right Mid (by import, scope, namespace or package);
#                     Python dotted / subscript / keyword bases, a package re-export, a star import; the debug-logger idiom
#
# (S1) the TARGETED --lego lists implementors below a direct one, each once at its shallowest depth, as
#      <impl via= depth=>; transitive=N on the <iface>; implementors= still counts the direct rows alone;
#      --limit/--offset (MCP limit/offset) page the deeper rows, a cut says has_more="1" + a next= that pages on.
#      An interface with no deeper row carries none of it (byte identity with the direct-only answer).
# (S2) every <impl> row of the TARGETED answer says where the class is: p="file:LINE" (the --uses/--callers spelling); the
#      <iface> row and the ranked --for <lego> section keep their bare p=.
# (M1) a Ruby module mixed in with include/extend (the @reference.mixin capture, ingest_ruby.h emitCapturedRubyMixinBase) is an implements edge: --lego=DSL lists TaskLib.
# (M2) a JS/TS class factory `const Sub = Base.extend('Sub', …)` is a class definition extending its receiver.
# (M3) a bare name resolves to a CODE definition whenever one matched, never to a markdown heading sorted first.
# (NS) fix 1: the closure descends only through extends edges the index PROVES (a same-file declaration in scope, an import,
#      an include, the package, a qualifier). A name-only edge's row is hedged base_by="name" and not walked; an edge the
#      evidence binds to ANOTHER same-named type adds no row and is counted transitive_other_base=. Python's `A.B` base is
#      B (inside A), `Generic[K]`'s type argument and `metaclass=M` are no base. Red on 4d59c804 (the namesake rows listed).
# (UW) fix 2 (rule 5): a DIRECT row whose own extends clause is not proven (a cross-package Java import, a Kotlin import, a C#
#      using, an ES import of a CommonJS base) is not walked below, and the answer SAYS so: the row carries unwalked="1", the
#      <iface> counts those rows transitive_unwalked=N and names the first one's --lego as unwalked_next=; a present-only
#      legend clause (full) and terms (compact), CLI and MCP. A direct name-only row with no subtype and a proven tree carry
#      none of it. Red on d339adf0 (the stop was silent). Corpus uw/{java,kt,cs,js}.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/legotransitivefix"
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
fail=0
# every verdict is an if/else: a failed write of a PASS line must never print FAIL for an arm that passed (gateexitcheck G2)
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "legotransitivecheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }

# lego SEL [extra flags…] — the answer, one tag per line, in $OUT; returns non-zero (and FAILs) when the run failed or
# printed no <lego> root, so an absence arm never reads a crashed or empty run as "not listed".
OUT=""
lego(){
    local sel="$1"; shift
    if ! "$BIN" "$FIX" --no-cache --lego="$sel" "$@" >"$DIR/out" 2>"$DIR/err"
    then
        no "--lego=$sel $* exited non-zero: $( head -3 "$DIR/err" )"; OUT=""; return 1
    fi
    OUT="$( sed 's/></>\n</g' "$DIR/out" )"
    if ! printf '%s\n' "$OUT" | grep -q '^<lego'
    then
        no "--lego=$sel $* printed no <lego> root"; return 1
    fi
    return 0
}
has(){ printf '%s\n' "$OUT" | grep -qF -- "$1"; }
count(){ printf '%s\n' "$OUT" | grep -cF -- "$1"; }
iface(){ printf '%s\n' "$OUT" | grep -m1 '^<iface'; }

echo "=== (S1) the closure: deeper implementors with via= and depth= ==="
if lego BaseFormatter
then
    for n in SimpleFormatter Nothing Default Pylint FilenameOnly
    do
        if has "<impl n=\"$n\""; then ok "--lego=BaseFormatter lists $n"; else no "--lego=BaseFormatter does not list $n: $( iface )"; fi
    done
    if printf '%s\n' "$OUT" | grep '<impl n="Default"' | grep -q 'via="SimpleFormatter" depth="2"'; then ok "Default carries via=\"SimpleFormatter\" depth=\"2\""; else no "Default row lacks via/depth: $( printf '%s\n' "$OUT" | grep '<impl n="Default"' )"; fi
    if printf '%s\n' "$OUT" | grep '<impl n="SimpleFormatter"' | grep -q 'via=\|depth='; then no "a DIRECT row carries via=/depth="; else ok "the direct rows carry neither via= nor depth="; fi
    if iface | grep -q 'implementors="2" transitive="3"'; then ok "implementors=\"2\" counts the direct rows, transitive=\"3\" the deeper ones"; else no "counts wrong: $( iface )"; fi
    if iface | grep -q 'has_more=\|transitive_shown='; then no "an uncut closure says it was cut: $( iface )"; else ok "an uncut closure carries no cut attribute"; fi
fi
if lego Top
then
    if [ "$( count '<impl n="Bottom"' )" = 1 ]; then ok "a diamond lists Bottom once"; else no "Bottom listed $( count '<impl n="Bottom"' ) times"; fi
    if printf '%s\n' "$OUT" | grep '<impl n="Bottom"' | grep -q 'via="Left" depth="2"'; then ok "…at its shallowest depth, via the first parent in id order (Left)"; else no "Bottom row: $( printf '%s\n' "$OUT" | grep '<impl n="Bottom"' )"; fi
    if printf '%s\n' "$OUT" | grep '<impl n="Deepest"' | grep -q 'via="Bottom" depth="3"'; then ok "Deepest is depth 3 via Bottom"; else no "Deepest row: $( printf '%s\n' "$OUT" | grep '<impl n="Deepest"' )"; fi
    if iface | grep -q 'implementors="2" transitive="2"'; then ok "Top: implementors=\"2\" transitive=\"2\""; else no "Top counts: $( iface )"; fi
fi
if lego Alone
then
    if iface | grep -q 'transitive="'; then no "an interface with direct rows only carries transitive: $( iface )"; else ok "an interface with direct rows only carries no transitive attribute"; fi
    if [ "$( count ' via="' )" = 0 ]; then ok "…and no via= row"; else no "Alone has via= rows"; fi
fi
if lego OnlyChild
then
    if iface | grep -q 'implementors="0"' && ! has 'transitive="'; then ok "a leaf class answers implementors=\"0\" with no closure attribute"; else no "leaf: $( iface )"; fi
fi

echo "=== (S2) every TARGETED impl row carries its definition's line ==="
if lego BaseFormatter
then
    if has '<impl n="SimpleFormatter" p="py/formatters.py:7"/>'; then ok "a direct row: p=\"py/formatters.py:7\" (the class line)"; else no "direct row: $( printf '%s\n' "$OUT" | grep '<impl n="SimpleFormatter"' )"; fi
    if has '<impl n="Pylint" p="py/formatters.py:15" via='; then ok "a deeper row: p=\"py/formatters.py:15\""; else no "deeper row: $( printf '%s\n' "$OUT" | grep '<impl n="Pylint"' )"; fi
    if iface | grep -q 'p="py/formatters.py"'; then ok "the <iface> row keeps its bare p= (unchanged)"; else no "iface p= changed: $( iface )"; fi
fi
# the ranked --for <lego> section is NOT the targeted answer: its rows keep the bare p= (byte identity outside the verb)
if "$BIN" "$FIX" --no-cache --for="formatter base class" --sections=lego,compose >"$DIR/for" 2>"$DIR/err"
then
    if grep -q '<impl n="[A-Za-z]*" p="[^"]*"' "$DIR/for"; then
        if grep -q '<impl n="[A-Za-z]*" p="[^"]*:[0-9]' "$DIR/for"; then no "a --for <lego> row gained :LINE"; else ok "--for <lego> rows keep p=\"file\""; fi
    else
        no "--for printed no <impl> row to check: $( head -c 300 "$DIR/for" )"
    fi
else
    no "--for exited non-zero: $( head -2 "$DIR/err" )"
fi

echo "=== (S1) the page: --limit/--offset window the deeper rows; next= pages on ==="
if lego BaseFormatter --limit=2
then
    I="$( iface )"
    if printf '%s' "$I" | grep -q 'transitive="3" transitive_shown="2" has_more="1"'; then ok "a cut page says transitive_shown=\"2\" has_more=\"1\""; else no "cut page: $I"; fi
    N="$( printf '%s' "$I" | sed -n 's/.* next="\([^"]*\)".*/\1/p' )"
    if [ "$N" = "--lego=py/formatters.py:BaseFormatter --limit=2 --offset=2" ]; then ok "next= replays the verb on the iface's file:name with the next offset"; else no "next= is '$N'"; fi
    if has '<impl n="SimpleFormatter"' && has '<impl n="Nothing"'; then ok "the direct rows ride every page"; else no "a direct row is missing from the page"; fi
    if [ "$( count ' via="' )" = 2 ]; then ok "two deeper rows on the page"; else no "deeper rows on page 1: $( count ' via="' )"; fi
fi
# replay the next= exactly as printed (its value is shell-safe by construction: nextFlag quotes what a shell would split)
N2="${N:---lego=py/formatters.py:BaseFormatter --limit=2 --offset=2}"
# shellcheck disable=SC2086
if lego ${N2#--lego=}
then
    I="$( iface )"
    if printf '%s' "$I" | grep -q 'transitive_shown="1" transitive_offset="2"'; then ok "page 2: transitive_shown=\"1\" transitive_offset=\"2\""; else no "page 2: $I"; fi
    if printf '%s' "$I" | grep -q 'has_more'; then no "the last page says has_more: $I"; else ok "the last page carries no has_more"; fi
    if has '<impl n="FilenameOnly"' && ! has '<impl n="Default"'; then ok "page 2 holds the third deeper row only"; else no "page 2 rows wrong"; fi
fi
if "$BIN" "$FIX" --no-cache --lego=BaseFormatter --limit=abc >/dev/null 2>"$DIR/err"
then
    no "--limit=abc beside --lego was accepted"
else
    if grep -q -- '--limit' "$DIR/err"; then ok "--limit=abc beside --lego is refused naming the flag"; else no "refusal text: $( head -2 "$DIR/err" )"; fi
fi
if "$BIN" "$FIX" --no-cache --lego=BaseFormatter --max-tokens=50 >"$DIR/out" 2>"$DIR/err"
then
    if grep -q 'not read by --lego' "$DIR/err" && grep -q 'transitive="3"' "$DIR/out"; then ok "--max-tokens without a page is still the not-read notice, full answer"; else no "--max-tokens notice changed: $( head -2 "$DIR/err" )"; fi
else
    no "--lego --max-tokens (no page) now refuses: $( head -2 "$DIR/err" )"
fi

echo "=== (S1) MCP lego pages the same way ==="
mcp(){ printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"lego\",\"arguments\":{\"path\":\"$FIX\",\"type\":\"BaseFormatter\"$1}}}" | "$BIN" --mcp 2>/dev/null; }
M="$( mcp ',"limit":2' )"
if printf '%s' "$M" | grep -q 'transitive_shown=\\"2\\" has_more=\\"1\\"'; then ok "MCP limit:2 cuts the deeper rows the same way"; else no "MCP limit:2: $( printf '%s' "$M" | head -c 300 )"; fi
M="$( mcp '' )"
if printf '%s' "$M" | grep -q 'transitive=\\"3\\"' && ! printf '%s' "$M" | grep -q 'has_more'; then ok "MCP without a window: the whole closure"; else no "MCP default: $( printf '%s' "$M" | head -c 300 )"; fi
M="$( mcp ',"offset":-1' )"
if printf '%s' "$M" | grep -q '"error"'; then ok "MCP offset:-1 is refused"; else no "MCP offset:-1 accepted: $( printf '%s' "$M" | head -c 300 )"; fi

echo "=== (M1) a Ruby module mixed in is an implements edge: include / extend ==="
if lego DSL
then
    if has '<impl n="TaskLib" p="rb/tasklib.rb:2"/>'; then ok "--lego=DSL lists TaskLib (include Rake::DSL) at rb/tasklib.rb:2"; else no "--lego=DSL: no TaskLib row: $( iface )"; fi
    if has '<impl n="MakefileLoader"'; then ok "--lego=DSL lists MakefileLoader"; else no "--lego=DSL: no MakefileLoader"; fi
    if has '<impl n="Singleton"'; then ok "--lego=DSL lists Singleton (extend Rake::DSL)"; else no "--lego=DSL: no Singleton (extend)"; fi
    if iface | grep -q 'implementors="3"'; then ok "implementors=\"3\": the top-level self.extend adds no row"; else no "DSL count: $( iface )"; fi
    if iface | grep -q 'implementors_floor'; then no "the bound include still reads as an unbound floor: $( iface )"; else ok "no implementors_floor once the include binds"; fi
fi
if lego Helpers
then
    if iface | grep -q 'implementors="0"'; then ok "an include inside a method body is no edge (Helpers lists nobody)"; else no "Helpers: $( iface )"; fi
fi
if lego Ping
then
    if [ "$( count '<impl n="Pong"' )" = 1 ] && [ "$( count '<impl n="Pinged"' )" = 1 ] && ! has '<impl n="Ping"'; then ok "a module cycle (Ping <-> Pong) lists each type once and never the interface itself"; else no "Ping cycle rows: $( printf '%s\n' "$OUT" | grep '^<impl' | tr '\n' ' ' )"; fi
fi
if lego Pong
then
    if printf '%s\n' "$OUT" | grep '<impl n="Pinged"' | grep -q 'via="Ping" depth="2"'; then ok "--lego=Pong reaches Pinged through Ping (depth 2)"; else no "Pong closure: $( printf '%s\n' "$OUT" | grep '^<impl' | tr '\n' ' ' )"; fi
fi

echo "=== (M2) the JS/TS class factory: const Sub = Base.extend('Sub', …) ==="
if lego BinOp
then
    ok "--lego=BinOp resolves (it said type not found before)"
    if has '<impl n="Add" p="js/nodes.js:8"/>' && has '<impl n="Sub" p="js/nodes.js:9"/>'; then ok "BinOp lists Add (var, single-quoted) and Sub (const, double-quoted)"; else no "BinOp rows: $( printf '%s\n' "$OUT" | grep '^<impl' | tr '\n' ' ' )"; fi
fi
if lego Node
then
    for n in Value BinOp Inner; do
        if printf '%s\n' "$OUT" | grep "<impl n=\"$n\"" | grep -qv ' via="'; then ok "--lego=Node lists $n directly"; else no "--lego=Node: no direct $n"; fi
    done
    if printf '%s\n' "$OUT" | grep '<impl n="Add"' | grep -q 'via="BinOp" depth="2"'; then ok "Add is depth 2 via BinOp (a factory of a factory)"; else no "Add row: $( printf '%s\n' "$OUT" | grep '<impl n="Add"' )"; fi
    if iface | grep -q 'implementors="3" transitive="2"'; then ok "Node: implementors=\"3\" transitive=\"2\" — no near miss counted"; else no "Node counts: $( iface )"; fi
fi
# near misses are no class at all: an object merge, a name that is not the binding's, another method, a spread
for t in settings Renamed Merged Spread TOther
do
    if "$BIN" "$FIX" --no-cache --lego="$t" >/dev/null 2>"$DIR/err"
    then
        no "--lego=$t resolved — the near miss became a class"
    elif grep -q -- "--lego type not found: $t" "$DIR/err"
    then
        ok "--lego=$t is not a type (near miss)"
    else
        no "--lego=$t failed some other way: $( head -2 "$DIR/err" )"
    fi
done
if lego TNode
then
    if has '<impl n="TBin" p="ts/nodes.ts:5"/>'; then ok "a TypeScript factory (with a type argument) lists under TNode"; else no "TNode rows: $( printf '%s\n' "$OUT" | grep '^<impl' | tr '\n' ' ' )"; fi
    # fix 1 (ruling 2): view.tsx's receiver is IMPORTED and the call hands no class body — the parser cannot show TView is a
    # class, so it is not one (the stated floor; jc.js JBody below is the cross-file factory that does show it)
    if has '<impl n="TView"'; then no "TView (imported receiver, no class body) is still a class"; else ok "TView (imported receiver, no class body) is no class — the stated floor"; fi
fi
# the debug package's sub-logger and a string-first merge have the factory SHAPE but no class evidence (fix 1, ruling 2)
for t in error verbose merged JTrue
do
    if "$BIN" "$FIX" --no-cache --lego="$t" >/dev/null 2>"$DIR/err"
    then
        no "--lego=$t resolved — '$t' (no class receiver, no class body) became a class"
    elif grep -q -- "--lego type not found: $t" "$DIR/err"
    then
        ok "--lego=$t is not a type (no class receiver in the file, no class body)"
    else
        no "--lego=$t failed some other way: $( head -2 "$DIR/err" )"
    fi
done
if lego JBody
then
    ok "--lego=JBody resolves: an imported receiver handed a class body (a method) is a class"
fi

echo "=== (NS) fix 1: the closure walks PROVEN extends edges only — namesakes in every by-name language ==="
# nsarm SEL TRUE_ROW FALSE_ROW VIA LABEL — the true subtype is a plain depth-2 row via VIA, the namesake's row is absent
nsarm(){
    if lego "$1"
    then
        if printf '%s\n' "$OUT" | grep "<impl n=\"$2\"" | grep -q "via=\"$4\" depth=\"2\"/>"; then ok "$5: --lego=$1 lists $2 via=\"$4\" depth=\"2\", unhedged"; else no "$5: --lego=$1 true row: $( printf '%s\n' "$OUT" | grep "<impl n=\"$2\"" )"; fi
        if has "<impl n=\"$3\""; then no "$5: --lego=$1 lists the namesake's $3: $( printf '%s\n' "$OUT" | grep "<impl n=\"$3\"" )"; else ok "$5: --lego=$1 does not list $3 (it extends an unrelated $4)"; fi
        if iface | grep -q 'transitive_other_base="[1-9]'; then ok "$5: the left-out namesake row is counted (transitive_other_base=)"; else no "$5: no transitive_other_base: $( iface )"; fi
    fi
}
nsarm PBase  PTrue  PLeaf  PMid  "Python (from-import vs same-file class)"
nsarm JRoot  JTrue2 JLeaf2 JNode "JavaScript (require alias vs same-file class)"
nsarm CBase  CTrue  CLeaf  CMid  "C++ (namespace ca reopened vs namespace cb)"
nsarm JvBase JvTrue JvLeaf JvMid "Java (package a vs package b)"
if lego JRoot
then
    if has '<impl n="JLeaf"'; then no "JavaScript: the namesake's factory JLeaf is listed under JRoot"; else ok "JavaScript: the namesake's factory JLeaf (same-file JNode) is not listed under JRoot"; fi
    if printf '%s\n' "$OUT" | grep '<impl n="JBody"' | grep -q 'via="JNode" depth="2"/>'; then ok "JavaScript: the class-body factory JBody is a proven depth-2 row"; else no "JBody row: $( printf '%s\n' "$OUT" | grep '<impl n="JBody"' )"; fi
fi
if lego CBase
then
    if printf '%s\n' "$OUT" | grep '<impl n="CQual"' | grep -q 'via="CMid" depth="2"/>'; then ok "C++: a qualified base ca::CMid is proven through its namespace"; else no "CQual row: $( printf '%s\n' "$OUT" | grep '<impl n="CQual"' )"; fi
fi
# Ruby already bound its bases by constant scope (resolve.h RubyBaseScope): the arm stays right both ways
if lego RTask
then
    if printf '%s\n' "$OUT" | grep '<impl n="RTrue"' | grep -q 'via="RMid" depth="2"/>'; then ok "Ruby: RTrue (RA::RMid) is a proven depth-2 row"; else no "Ruby RTrue: $( printf '%s\n' "$OUT" | grep '<impl n="RTrue"' )"; fi
    if has '<impl n="RLeaf"'; then no "Ruby lists RB::RLeaf under RA::RTask"; else ok "Ruby: RB::RLeaf (under RB::RMid) is not listed"; fi
fi
# each namesake still answers its OWN direct rows (the map's contract is unchanged)
if lego ns/py/ns_pb.py:PMid
then
    if has '<impl n="PLeaf"'; then ok "the namesake ns_pb.py:PMid still lists its own PLeaf"; else no "ns_pb.py:PMid: $( iface )"; fi
fi
# a re-export: `from pkg import PExp`, pkg/__init__.py re-exporting pkg._impl.PExp, beside an unrelated PExp
if lego PExpBase
then
    if printf '%s\n' "$OUT" | grep '<impl n="PExpLeaf"' | grep -q 'via="PExp" depth="2"/>'; then ok "Python: a package re-export proves PExpLeaf (depth 2, unhedged)"; else no "PExpLeaf row: $( printf '%s\n' "$OUT" | grep '<impl n="PExpLeaf"' )"; fi
fi
# a name-only edge: a star import names nothing this tool reads, so PStar's PMid is unproven — listed HEDGED, never asserted
if lego PBase
then
    if printf '%s\n' "$OUT" | grep '<impl n="PStar"' | grep -q 'via="PMid" depth="2" base_by="name"/>'; then ok "a name-only edge's row rides hedged: PStar base_by=\"name\""; else no "PStar row: $( printf '%s\n' "$OUT" | grep '<impl n="PStar"' )"; fi
    if printf '%s\n' "$OUT" | grep '<impl n="PTrue"' | grep -q 'base_by'; then no "a proven row carries base_by"; else ok "a proven row carries no base_by"; fi
fi
if "$BIN" "$FIX" --no-cache --lego=PBase --legend=full >"$DIR/full" 2>"$DIR/err"
then
    if grep -q 'base_by=\\"name\\" on a deeper row' "$DIR/full" || grep -q 'base_by="name" on a deeper row' "$DIR/full"; then ok "the full legend defines base_by= and transitive_other_base= where they ride"; else no "full legend lacks the hedge clause"; fi
else
    no "--lego=PBase --legend=full exited non-zero: $( head -2 "$DIR/err" )"
fi
if "$BIN" "$FIX" --no-cache --lego=BaseFormatter --legend=full >"$DIR/full" 2>"$DIR/err" && ! grep -q 'base_by' "$DIR/full"; then ok "an answer with no hedged row carries no hedge clause"; else no "the hedge clause rides an answer without a hedged row"; fi

echo "=== (NS) Python base expressions: a dotted base is ONE base; a type argument or a keyword is none ==="
if lego POuter
then
    if iface | grep -q 'implementors="0"'; then ok "class PInner(POuter.PChanged) is no subtype of POuter"; else no "POuter: $( iface ) $( printf '%s\n' "$OUT" | grep '^<impl' | tr '\n' ' ' )"; fi
fi
if lego PChanged
then
    if has '<impl n="PInner"'; then ok "…it is PChanged's (the last attribute)"; else no "PChanged lists no PInner"; fi
fi
if lego PKey
then
    if iface | grep -q 'implementors="0"'; then ok "class PBox(Generic[PKey]): a type argument is no base"; else no "PKey: $( iface )"; fi
fi
if lego PBase2
then
    if has '<impl n="PSub"'; then ok "class PSub(PBase2[int]): the subscript's value is the base"; else no "PBase2 lists no PSub"; fi
fi
if lego PMeta
then
    if iface | grep -q 'implementors="0"'; then ok "metaclass=PMeta is no base"; else no "PMeta: $( iface )"; fi
fi

echo "=== (UW) fix 2: the walk's stop below an unproven DIRECT row is disclosed, never silent ==="
# uwarm ROOT MID LABEL — MID is ROOT's only direct row, bound by name; its subtype is not walked, and the answer says so
uwarm(){
    if lego "$1"
    then
        if printf '%s\n' "$OUT" | grep "<impl n=\"$2\"" | grep -q 'unwalked="1"/>'; then ok "$3: --lego=$1 marks $2 unwalked=\"1\""; else no "$3: $2 row: $( printf '%s\n' "$OUT" | grep "<impl n=\"$2\"" )"; fi
        if iface | grep -q 'transitive_unwalked="1"'; then ok "$3: the <iface> counts it (transitive_unwalked=\"1\")"; else no "$3: no transitive_unwalked: $( iface )"; fi
        if iface | grep -q "unwalked_next=\"--lego=[^\"]*:$2\""; then ok "$3: unwalked_next= names $2's own --lego"; else no "$3: unwalked_next: $( iface )"; fi
    fi
}
uwarm UwKRoot  UwKMid  "Kotlin (import; the leaf in the same file)"
uwarm UwCRoot  UwCMid  "C# (using; the leaf in the same file)"
uwarm UwJsRoot UwJsMid "JavaScript (ES import of a CommonJS base)"
if lego UwJRoot
then
    if iface | grep -q 'transitive_unwalked="2" unwalked_next="--lego=uw/java/a/UwJMid.java:UwJMid"'; then ok "Java: two unwalked direct rows counted, the first named (UwJMid)"; else no "Java UwJRoot: $( iface )"; fi
    if printf '%s\n' "$OUT" | grep '<impl n="UwJMid2"' | grep -q 'unwalked="1"/>'; then ok "Java: the second unwalked row UwJMid2 is marked too"; else no "UwJMid2 row: $( printf '%s\n' "$OUT" | grep '<impl n="UwJMid2"' )"; fi
    # near misses: a name-only direct row with NO subtype, and a proven direct row (same package) that IS walked
    if printf '%s\n' "$OUT" | grep '<impl n="UwJAlone"' | grep -q 'unwalked'; then no "UwJAlone (no subtype) is marked unwalked"; else ok "a name-only direct row with no subtype (UwJAlone) is not marked"; fi
    if printf '%s\n' "$OUT" | grep '<impl n="UwJNear"' | grep -q 'unwalked'; then no "the proven UwJNear is marked unwalked"; else ok "a proven direct row (UwJNear, same package) is not marked"; fi
    if printf '%s\n' "$OUT" | grep '<impl n="UwJNearLeaf"' | grep -q 'via="UwJNear" depth="2"/>' && iface | grep -q 'transitive="1"'; then ok "…and its subtype is walked (transitive=\"1\" beside the unwalked count)"; else no "UwJNearLeaf: $( iface )"; fi
    if has '<impl n="UwJLeaf"' || has '<impl n="UwJLeaf2"'; then no "an unproven row's subtype is listed as a deeper row"; else ok "the unproven rows' subtypes stay off this answer (the stop is kept)"; fi
fi
# the named call walks below: --lego=<that row> lists its subtype
if lego uw/java/a/UwJMid.java:UwJMid
then
    if has '<impl n="UwJLeaf"'; then ok "unwalked_next (--lego=uw/java/a/UwJMid.java:UwJMid) lists UwJLeaf"; else no "the unwalked_next call: $( iface )"; fi
fi
# a fully proven tree and a name-only one with no subtype carry none of it
for t in BaseFormatter Top PBase
do
    if lego "$t"
    then
        if has 'unwalked'; then no "--lego=$t (every direct row proven or childless) carries an unwalked attribute"; else ok "--lego=$t carries no unwalked attribute"; fi
    fi
done
if "$BIN" "$FIX" --no-cache --lego=UwJRoot --legend=full >"$DIR/full" 2>"$DIR/err"
then
    if grep -q 'ripwire lego: transitive_unwalked=N' "$DIR/full"; then ok "the full legend defines transitive_unwalked= where it rides"; else no "full legend lacks the unwalked clause"; fi
else
    no "--lego=UwJRoot --legend=full exited non-zero: $( head -2 "$DIR/err" )"
fi
if "$BIN" "$FIX" --no-cache --lego=UwKRoot --legend=compact >"$DIR/compact" 2>"$DIR/err"
then
    if grep -q 'transitive_unwalked=N: ' "$DIR/compact" && grep -q 'unwalked_next=: ' "$DIR/compact" && grep -q 'unwalked=1: ' "$DIR/compact"; then ok "the compact legend reads transitive_unwalked=, unwalked_next= and unwalked="; else no "compact legend lacks the unwalked terms: $( head -c 600 "$DIR/compact" )"; fi
else
    no "--lego=UwKRoot --legend=compact exited non-zero: $( head -2 "$DIR/err" )"
fi
if "$BIN" "$FIX" --no-cache --lego=BaseFormatter --legend=full >"$DIR/full" 2>"$DIR/err" && ! grep -q 'unwalked' "$DIR/full"; then ok "an answer with no unwalked row carries no unwalked clause"; else no "the unwalked clause rides an answer without an unwalked row"; fi
M="$( printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"lego\",\"arguments\":{\"path\":\"$FIX\",\"type\":\"UwCRoot\"}}}" | "$BIN" --mcp 2>/dev/null )"
if printf '%s' "$M" | grep -q 'transitive_unwalked=\\"1\\" unwalked_next=\\"--lego=uw/cs/UwCMid.cs:UwCMid\\"' && printf '%s' "$M" | grep -q 'unwalked=\\"1\\"/>'; then ok "MCP lego carries the same count, next and row mark"; else no "MCP lego UwCRoot: $( printf '%s' "$M" | head -c 400 )"; fi

echo "=== (M3) the focus is a CODE definition whenever one matched ==="
if lego Loader
then
    if iface | grep -q 'p="js/loader.js"'; then ok "--lego=Loader picks js/loader.js over the docs/api.md heading"; else no "--lego=Loader picked: $( iface )"; fi
    if has '<impl n="FileSystemLoader"'; then ok "…and lists its implementor FileSystemLoader"; else no "Loader lists no FileSystemLoader"; fi
    if iface | grep -q 'defs="2"'; then ok "defs=\"2\" still counts the heading beside the class"; else no "Loader defs: $( iface )"; fi
fi
if lego js/docs/api.md:Loader
then
    if iface | grep -q 'p="js/docs/api.md"'; then ok "a file:name selector still reaches the heading"; else no "docs selector: $( iface )"; fi
fi
if lego Guide
then
    if iface | grep -q 'p="js/docs/api.md"'; then ok "a name only a heading defines still resolves to it"; else no "Guide: $( iface )"; fi
fi
if "$BIN" "$FIX" --no-cache --around=Loader >"$DIR/around" 2>"$DIR/err"
then
    if grep -o '<s [^>]*n="Loader"[^>]*>' "$DIR/around" | grep -q 'js/loader.js\|t="cls"'; then ok "--around=Loader centres on the class (the same resolver)"; else no "--around=Loader rows: $( grep -o '<s [^>]*n="Loader"[^>]*>' "$DIR/around" | head -2 )"; fi
else
    no "--around=Loader exited non-zero: $( head -2 "$DIR/err" )"
fi

echo "=== well-formed ==="
if command -v xmllint >/dev/null 2>&1
then
    for a in "--lego=BaseFormatter" "--lego=BaseFormatter --legend=full" "--lego=BaseFormatter --limit=1 --legend=full" "--lego=Top --legend=full" "--lego=PBase --legend=full" "--lego=JRoot --legend=full" "--lego=UwJRoot --legend=full" "--lego=UwJRoot --limit=1 --legend=full"
    do
        # shellcheck disable=SC2086
        if "$BIN" "$FIX" --no-cache $a 2>/dev/null | xmllint --noout - 2>/dev/null; then ok "xml well-formed: $a"; else no "xml malformed: $a"; fi
    done
else
    echo "  SKIP  xmllint absent"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
