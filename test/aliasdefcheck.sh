#!/usr/bin/env bash
# aliasdefcheck.sh — INDEX-ALIAS-CONST gate: C++ alias forms (`using X = Y`, templated and class-scope `using`, `namespace L = lib`,
# function-type and pointer typedefs) are definitions whose written target the defs verb prints (to= / to_next=); the near misses
# stay out. TypeScript module consts stay as they are on main (the TS arm is carded, TS-CONST-DEFS): the TS arms here pin that.
#
# WHY: `--defs=ColumnPtr` found 0 on ClickHouse although `using ColumnPtr = COW<IColumn>::Ptr;` sits in IColumn_fwd.h, so a
# name-exact route had nothing to land on. src/aliasdef.h is the one reader (C++ node kinds, one arm per language).
#
# RED-BEFORE-FIX: every [RED] arm fails on the base binary (main 824847bd; recorded in reports/index-alias-const.md); the
# unmarked arms hold on base and head alike (each negative has a positive twin in the same fixture).
# Fixtures are built at runtime (nothing under a .gitignored path). Every arm reads a command whose exit code it checks.
#
# Usage: test/aliasdefcheck.sh [BIN]      (BIN falls back to RIPWIRE_BIN, then build/ripwire)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "aliasdefcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
if [ ! -x "$BIN" ]; then echo "  FAIL  no binary at $BIN"; exit 1; fi

F="$TMP/fx"; mkdir -p "$F/c" "$F/t"
cat > "$F/c/alias.h" <<'EOF'
namespace lib { struct Real { void run(); }; template <class T> struct COW { using Ptr = T*; }; }
struct IColumn {};
using RealAlias = lib::Real;
using ColumnPtr = lib::COW<IColumn>::Ptr;
template <class T> using Vec = lib::COW<T>;
typedef struct S { int x; } S2;
typedef void (*Callback)(int);
typedef int FnType(int);
typedef struct S *SPtr;
namespace L = lib;
using namespace lib;
using lib::Real;
class Holder { public: using value_type = IColumn; };
using LongAlias = lib::COW<lib::COW<lib::COW<lib::COW<lib::COW<lib::COW<lib::COW<lib::COW<lib::COW<lib::COW<lib::COW<lib::COW<lib::COW<lib::COW<lib::COW<lib::COW<IColumn>>>>>>>>>>>>>>>>;
inline void f() { using LocalAlias = int; LocalAlias v = 0; (void)v; }
inline int h() { struct LocalShape { int a; }; LocalShape s{ 1 }; return s.a; }
using Trailing = lib::Real /* trail */ ;
using Spaced = lib::Real
    ;
using LineComment = lib::COW<int, // key
    lib::Real>;
namespace LC = lib /* ns */;
EOF
cat > "$F/t/mod.ts" <<'EOF'
import * as m from './other';
export const aliasIdent = m;
export const aliasMember = m.inner.leaf;
export const loaded = require('./other');
export const lazyMod = import('./other');
export const shape = { a: 1, b: 2 } as const;
export const handlers = { open() { return 1; }, close: () => 2 };
export const list = [aliasIdent, aliasMember];
const { destructA, destructB } = m;
let counter = 0;
counter = counter + 1;
function g() { const localConst = m.inner; return localConst; }
export const called = m.make();
export const notLoader = resolve('./other');
export const greeting = "hello";
export const emptyBag = {};
const SCREAMING_ALIAS = m.thing;
EOF
defs(){ # defs ROOTDIR NAME -> the answer body in $TMP/rows (legend stripped); rc in $drc (never in a subshell)
    ( cd "$1" && "$BIN" . --no-cache --defs="$2" ) > "$TMP/out" 2> "$TMP/err"; drc=$?
    sed 's/.*<defs /<defs /' "$TMP/out" > "$TMP/rows"
}
row(){ grep -oE '<d [^>]*>' "$TMP/rows" | head -1; }

# [RED] C++ alias forms are definitions with their target (positive arms)
check_cpp(){ # name t= to= to_next=
    local r; defs "$F/c" "$1"; r=$( row )
    if [ "$drc" -ne 0 ]; then no "[RED] --defs=$1 exited $drc (a found alias exits 0)"; return; fi
    case "$r" in *"t=\"$2\""*) ;; *) no "[RED] --defs=$1: want t=\"$2\", got: ${r:-<no row>}"; return;; esac
    if [ -n "$3" ]; then case "$r" in *" to=\"$3\""*) ;; *) no "[RED] --defs=$1: want to=\"$3\", got: $r"; return;; esac; fi
    if [ -z "$3" ]; then case "$r" in *" to="*) no "[RED] --defs=$1: a typedef row carries no to=, got: $r"; return;; esac; fi
    if [ -n "$4" ]; then case "$r" in *" to_next=\"$4\""*) ;; *) no "[RED] --defs=$1: want to_next=\"$4\", got: $r"; return;; esac; fi
    ok "[RED] --defs=$1 t=$2${3:+ to=$3}${4:+ to_next=$4}"
}
check_cpp RealAlias  alias    'lib::Real'                     '--defs=Real'
check_cpp ColumnPtr  alias    'lib::COW&lt;IColumn&gt;::Ptr'  '--defs=COW::Ptr'
check_cpp Vec        alias    'lib::COW&lt;T&gt;'             '--defs=COW'
check_cpp L          alias    'lib'                           ''
check_cpp value_type alias    'IColumn'                       '--defs=IColumn'
check_cpp Callback   functype ''                              ''
check_cpp FnType     functype ''                              ''
check_cpp SPtr       struct   ''                              ''
# the to_next hop is itself an alias row with a target: the chain is followable call by call
check_cpp COW::Ptr   alias    'T*'                            ''
# [RED on 67efef80] a comment or a line break before `;` keeps the target, with no trailing space and no comment text (N1, N2, CR)
check_cpp Trailing    alias   'lib::Real'                     '--defs=Real'
check_cpp Spaced      alias   'lib::Real'                     '--defs=Real'
check_cpp LineComment alias   'lib::COW&lt;int, lib::Real&gt;' '--defs=COW'
check_cpp LC          alias   'lib'                           ''
# the runaway guard (kAliasTargetCap = 160): a longer target is cut with an ellipsis, to_capped="1" says so, to_bytes= names its full size
defs "$F/c" LongAlias; r=$( row )
case "$r" in *'…" to_capped="1" to_bytes="'*) ok "[RED] --defs=LongAlias: to= cut at the cap, to_capped=\"1\" to_bytes= present";; *) no "[RED] --defs=LongAlias: rc=$drc want to_bytes= and a cut to=, got: ${r:-<no row>}";; esac
# typedef rows keep their old shape: no to= (the target precedes the name)
defs "$F/c" S2; r=$( row ); if [ "$drc" -eq 0 ] && [ -n "$r" ] && ! printf '%s' "$r" | grep -q ' to='; then ok "typedef S2 is a def with no to= (unchanged shape)"; else no "typedef S2: rc=$drc row=${r:-<none>}"; fi

# [RED] the map's kind clause: a C/C++ alias or functype row reads the C/C++ clause, never the Go named-type one
( cd "$F/c" && "$BIN" . --no-cache ) > "$TMP/map" 2>/dev/null; mrc=$?
if [ "$mrc" -eq 0 ] && grep -q 't=alias|functype-in-C++-and-.h' "$TMP/map" && ! grep -q 'a-Go-named-type' "$TMP/map"; then ok "[RED] C++ map: the C++ alias clause, no Go clause"; else no "[RED] C++ map clause: rc=$mrc cpp=$( grep -c 'functype-in-C++-and-.h' "$TMP/map" ) go=$( grep -c 'a-Go-named-type' "$TMP/map" )"; fi
# [RED on 67efef80] the map of a tree with C++ alias rows is well-formed XML: no legend comment holds two hyphens in a row (CI
# windows-package found it; test/regression.sh's xmllint arm reads test/fixture, which has no alias row, so this arm is the cover)
if [ "$mrc" -eq 0 ] && python3 -c 'import sys, xml.etree.ElementTree as E; E.parse(sys.argv[1])' "$TMP/map" 2> "$TMP/xmlerr"; then ok "[RED] C++ map parses as XML (python3 ElementTree)"; else no "[RED] C++ map is not well-formed XML: rc=$mrc $( tail -c 300 "$TMP/xmlerr" )"; fi

# a Go `type A = B` stays a t="alias" def with no to= (Go records no target; LangFacts::aliasTargetDefs is C/C++ only)
mkdir -p "$F/g"; printf 'package p\n\ntype Real struct{}\n\ntype GoAlias = Real\n' > "$F/g/a.go"
defs "$F/g" GoAlias; r=$( row )
if [ "$drc" -eq 0 ] && printf '%s' "$r" | grep -q 't="alias"' && ! printf '%s' "$r" | grep -q ' to'; then ok "Go type alias: t=alias, no to= (unchanged)"; else no "Go type alias: rc=$drc row=${r:-<none>}"; fi
( cd "$F/g" && "$BIN" . --no-cache ) > "$TMP/gmap" 2>/dev/null
if grep -q 'a-Go-named-type' "$TMP/gmap" && ! grep -q 'functype-in-C++-and-.h' "$TMP/gmap" && python3 -c 'import sys, xml.etree.ElementTree as E; E.parse(sys.argv[1])' "$TMP/gmap" 2>/dev/null; then ok "Go map: the Go clause only, well-formed"; else no "Go map clause: go=$( grep -c 'a-Go-named-type' "$TMP/gmap" ) cpp=$( grep -c 'functype-in-C++-and-.h' "$TMP/gmap" )"; fi

# NOT aliases: a function-local alias; `using namespace` and a using-declaration add no definition
absent(){ # dir name why
    local r; defs "$1" "$2"; r=$( row )
    if [ "$drc" -eq 1 ] && [ -z "$r" ] && grep -q 'not found' "$TMP/err" "$TMP/out" 2>/dev/null; then ok "$3: --defs=$2 not found"; else no "$3: --defs=$2 rc=$drc row=${r:-<none>}"; fi
}
absent "$F/c" LocalAlias "a function-local alias is no definition"
defs "$F/c" LocalShape; r=$( row )
if [ "$drc" -eq 0 ] && [ -n "$r" ]; then ok "a function-local struct stays a def (only alias captures take the local rule)"; else no "function-local struct: rc=$drc row=${r:-<none>}"; fi
# a function with a body is no alias row: no to= (the target transport rides alias rows only)
defs "$F/c" h; r=$( row )
if [ "$drc" -eq 0 ] && [ -n "$r" ] && ! printf '%s' "$r" | grep -q ' to'; then ok "a function row carries no to="; else no "function row: rc=$drc row=${r:-<none>}"; fi
defs "$F/c" Real; n=$( grep -oE '<name q="Real" defs="[0-9]+"' "$TMP/rows" | grep -oE '[0-9]+"$' | tr -d '"' )
if [ "$drc" -eq 0 ] && [ "${n:-x}" = "1" ]; then ok "using lib::Real; adds no second Real (defs=1)"; else no "using-declaration: rc=$drc defs=${n:-<none>}"; fi
absent "$F/c" lib "using namespace lib; is no definition of lib"

# TypeScript module consts are NOT definitions here (as on main): neither alias- nor table-shaped values, nor the near misses
for n in aliasIdent aliasMember loaded lazyMod shape handlers list destructA counter localConst called notLoader greeting emptyBag ambientThing; do
    absent "$F/t" "$n" "TS const (TS arm carded)"
done
# a SCREAMING const stays a def exactly as on main: no to= (the alias target rides C++ rows only)
defs "$F/t" SCREAMING_ALIAS; r=$( row )
if [ "$drc" -eq 0 ] && [ -n "$r" ] && ! printf '%s' "$r" | grep -q ' to'; then ok "TS SCREAMING const: a def with no to= (unchanged)"; else no "TS SCREAMING const: rc=$drc row=${r:-<none>}"; fi
if command -v xmllint >/dev/null 2>&1; then
    ( cd "$F/c" && "$BIN" . --no-cache --defs=ColumnPtr ) > "$TMP/x" 2>/dev/null
    if [ $? -eq 0 ] && xmllint --noout "$TMP/x" 2>/dev/null; then ok "[RED] the --defs answer carrying to= is well-formed"; else no "--defs to= answer not well-formed or failed"; fi
else
    echo "  SKIP  xmllint arms (xmllint not on PATH)"
fi

# a pathological 10 MB single-line C++ header beside an alias: never hangs (skipped by the crawl's size ceiling), the alias is indexed
mkdir -p "$F/big"; python3 -c "
import sys
open(sys.argv[1],'w').write('int big[] = {' + ','.join(['0']*5_000_000) + '};\n')" "$F/big/huge.h"
printf 'namespace other { struct Thing {}; }\nusing Keep = other::Thing;\n' > "$F/big/small.h"
( cd "$F/big" && "$BIN" . --no-cache --defs=Keep ) > "$TMP/big" 2>&1; brc=$?
if [ "$brc" -eq 0 ] && grep -q 'to="other::Thing"' "$TMP/big"; then ok "[RED] 10 MB one-line header beside an alias: the run finishes and indexes the alias"; else no "10 MB file: rc=$brc"; fi

# [RED on 67efef80 for the mutants named] the JSON row carries the same target keys (mutant: defRowJson without aliasTargetAttrsJson)
( cd "$F/c" && "$BIN" . --no-cache --defs=ColumnPtr --json ) > "$TMP/j" 2>/dev/null; jrc=$?
if [ "$jrc" -eq 0 ] && grep -qF '"to":"lib::COW<IColumn>::Ptr"' "$TMP/j" && grep -qF '"to_next":"--defs=COW::Ptr"' "$TMP/j"; then ok "--defs --json: \"to\" and \"to_next\""; else no "--defs --json: rc=$jrc $( head -c 300 "$TMP/j" )"; fi
( cd "$F/c" && "$BIN" . --no-cache --defs=LongAlias --json ) > "$TMP/j" 2>/dev/null; jrc=$?
if [ "$jrc" -eq 0 ] && grep -qF '"to_capped":1,"to_bytes":' "$TMP/j"; then ok "--defs --json: \"to_capped\" and \"to_bytes\" on a cut target"; else no "--defs --json cap: rc=$jrc $( head -c 300 "$TMP/j" )"; fi

# the warm cache carries the target start (RawDef bodyByte through ingest_cache.h): a second, cached run prints the same to=, and an
# edit that shifts the alias's offset prints the target at its new place
W="$TMP/w"; mkdir -p "$W/src"; cp "$F/c/alias.h" "$W/src/alias.h"; C="$TMP/w.cache"
( cd "$W/src" && "$BIN" . --cache="$C" --defs=ColumnPtr ) > /dev/null 2>&1
( cd "$W/src" && "$BIN" . --cache="$C" --defs=ColumnPtr ) > "$TMP/w1" 2>/dev/null; wrc=$?
if [ "$wrc" -eq 0 ] && [ -s "$C" ] && grep -q 'to="lib::COW&lt;IColumn&gt;::Ptr"' "$TMP/w1"; then ok "warm cache: to= survives the reload"; else no "warm cache: rc=$wrc cache=$( [ -s "$C" ] && echo yes || echo no ) $( grep -oE '<d n="[^>]*>' "$TMP/w1" | head -1 )"; fi
{ printf '// a new first line shifts every offset\n'; cat "$F/c/alias.h"; } > "$W/src/alias.h"
( cd "$W/src" && "$BIN" . --cache="$C" --defs=ColumnPtr ) > "$TMP/w2" 2>/dev/null; wrc=$?
if [ "$wrc" -eq 0 ] && grep -q 'p="alias.h:5"' "$TMP/w2" && grep -q 'to="lib::COW&lt;IColumn&gt;::Ptr"' "$TMP/w2"; then ok "warm cache after an offset-shifting edit: to= read at the new place"; else no "warm cache after edit: rc=$wrc $( grep -oE '<d n="[^>]*>' "$TMP/w2" | head -1 )"; fi
# to_unread: the cached row's file can no longer be read (mutant: the to_unread attribute never written); skipped when chmod does not bite
chmod 000 "$W/src/alias.h"
if [ -r "$W/src/alias.h" ]; then
    echo "  SKIP  to_unread arms (chmod 000 does not stop this user reading)"
else
    ( cd "$W/src" && "$BIN" . --cache="$C" --defs=ColumnPtr ) > "$TMP/u" 2>/dev/null; urc=$?
    ( cd "$W/src" && "$BIN" . --cache="$C" --defs=ColumnPtr --json ) > "$TMP/uj" 2>/dev/null; ujrc=$?
    if [ "$urc" -eq 0 ] && grep -q 't="alias"[^>]* to_unread="1"' "$TMP/u" && ! grep -q ' to="' "$TMP/u"; then ok "an unreadable file: to_unread=\"1\", no to="; else no "to_unread XML: rc=$urc $( grep -oE '<d n="[^>]*>' "$TMP/u" | head -1 )"; fi
    if [ "$ujrc" -eq 0 ] && grep -qF '"to_unread":1' "$TMP/uj"; then ok "an unreadable file: JSON \"to_unread\":1"; else no "to_unread JSON: rc=$ujrc $( head -c 300 "$TMP/uj" )"; fi
fi
chmod 644 "$W/src/alias.h"

# [RED on 67efef80] a multi-root workspace keeps the alias-target side table (workspace.h mergeWorkspaceIngests re-offsets it)
mkdir -p "$TMP/ws/a" "$TMP/ws/b"; printf 'struct Other {};\n' > "$TMP/ws/a/o.h"
printf 'namespace other { struct Thing {}; }\nusing Keep = other::Thing;\n' > "$TMP/ws/b/k.h"
( cd "$TMP/ws" && "$BIN" a b --no-cache --defs=Keep ) > "$TMP/ws.xml" 2>/dev/null; xrc=$?
( cd "$TMP/ws" && "$BIN" a b --no-cache --defs=Keep --json ) > "$TMP/ws.json" 2>/dev/null; jrc=$?
if [ "$xrc" -eq 0 ] && grep -q 'n="Keep" t="alias"[^>]* to="other::Thing" to_next="--defs=Thing"' "$TMP/ws.xml"; then ok "[RED] multi-root --defs: to= and to_next="; else no "[RED] multi-root --defs: rc=$xrc $( grep -oE '<d n="[^>]*>' "$TMP/ws.xml" | head -1 )"; fi
if [ "$jrc" -eq 0 ] && grep -qF '"to":"other::Thing"' "$TMP/ws.json"; then ok "[RED] multi-root --defs --json: \"to\""; else no "[RED] multi-root --defs --json: rc=$jrc $( head -c 300 "$TMP/ws.json" )"; fi

# [RED on 67efef80] a class-scope alias's literal row names its class as in= (as main did), never its own alias row (S4)
mkdir -p "$F/e/cpp"; printf 'template <class T> struct Ptr { T* p; };\nstruct Widget { int n; };\nstruct Holder {\n    using WidgetRef = Ptr<Widget>;\n};\nint getWidgetRefCount();\n' > "$F/e/cpp/h.h"
( cd "$F/e" && "$BIN" . --no-cache --for="what does WidgetRef expand to? the defs lookup is empty" ) > "$TMP/e" 2>/dev/null; erc=$?
if [ "$erc" -eq 0 ] && grep -q '<ld p="cpp/h.h" l="4" shape="using" in="Holder::Holder">' "$TMP/e"; then ok "[RED] class-scope using: the literal row's in= names its class"; else no "[RED] class-scope using in=: rc=$erc $( grep -oE '<ld [^>]*>' "$TMP/e" | head -1 )"; fi

echo "aliasdefcheck: $( [ "$fail" -eq 0 ] && echo PASS || echo FAIL )"
exit "$fail"
