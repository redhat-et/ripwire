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
ok(){ printf '  PASS  %s\n' "$*"; }
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
# the runaway guard (kAliasTargetCap = 160): a longer target is cut with an ellipsis and to_bytes= names its full size
defs "$F/c" LongAlias; r=$( row )
case "$r" in *' to_bytes="'*'"'*'…"'*|*'…" to_bytes="'*) ok "[RED] --defs=LongAlias: to= cut at the cap, to_bytes= present";; *) no "[RED] --defs=LongAlias: rc=$drc want to_bytes= and a cut to=, got: ${r:-<no row>}";; esac
# typedef rows keep their old shape: no to= (the target precedes the name)
defs "$F/c" S2; r=$( row ); if [ "$drc" -eq 0 ] && [ -n "$r" ] && ! printf '%s' "$r" | grep -q ' to='; then ok "typedef S2 is a def with no to= (unchanged shape)"; else no "typedef S2: rc=$drc row=${r:-<none>}"; fi

# NOT aliases: a function-local alias; `using namespace` and a using-declaration add no definition
absent(){ # dir name why
    local r; defs "$1" "$2"; r=$( row )
    if [ "$drc" -eq 1 ] && [ -z "$r" ] && grep -q 'not found' "$TMP/err" "$TMP/out" 2>/dev/null; then ok "$3: --defs=$2 not found"; else no "$3: --defs=$2 rc=$drc row=${r:-<none>}"; fi
}
absent "$F/c" LocalAlias "a function-local alias is no definition"
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

echo "aliasdefcheck: $( [ "$fail" -eq 0 ] && echo PASS || echo FAIL )"
exit "$fail"
