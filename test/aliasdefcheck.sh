#!/usr/bin/env bash
# aliasdefcheck.sh — INDEX-ALIAS-CONST gate: C++ alias forms and TS alias/table-shaped module consts are definitions whose written
# target the defs verb prints (to= / to_next=); the near misses stay out and the TS ones are COUNTED (consts_skipped=).
#
# WHY: `--defs=ColumnPtr` found 0 on ClickHouse although `using ColumnPtr = COW<IColumn>::Ptr;` sits in IColumn_fwd.h, and TS
# module tables (`const forEachChildTable = {…}`, `export const optionDeclarations = [...]`) were no definitions at all, so a
# name-exact route had nothing to land on. src/aliasdef.h is the one reader (C++ node kinds; the TS value ALLOWLIST).
#
# RED-BEFORE-FIX: every [RED] arm fails on the base binary (main 824847bd; recorded in reports/index-alias-const.md).
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

F="$TMP/fx"; mkdir -p "$F/c" "$F/t" "$F/m"
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
export const greeting = "hello";
export const emptyBag = {};
const SCREAMING_ALIAS = m.thing;
EOF
printf 'export const make = () => 1;\nexport const makeCast = ((a: number) => a) as Fn;\nexport const Sub = Base.extend(\x27Sub\x27, {});\n' > "$F/t/other.ts"
printf 'declare const ambientThing: number;\nexport declare const ambientVersion: string;\n' > "$F/t/decl.d.ts"
# a minified TS bundle: module consts of alias shape, no whitespace to speak of (counted, never indexed)
python3 -c "
import sys
body=';'.join('const minA%d=minB.c%d' % (i,i) for i in range(400))
open(sys.argv[1],'w').write('const minB={c0:1};'+body+';\n')" "$F/m/bundle.ts"

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

# [RED] TS alias- and table-shaped module consts (positives) and their targets
check_ts(){ # name to= (empty: a table, no to=)
    local r; defs "$F/t" "$1"; r=$( row )
    if [ "$drc" -ne 0 ] || [ -z "$r" ]; then no "[RED] TS --defs=$1 rc=$drc row=${r:-<none>}"; return; fi
    if [ -n "$2" ]; then case "$r" in *" to=\"$2\""*) ok "[RED] TS --defs=$1 to=$2";; *) no "[RED] TS --defs=$1: want to=\"$2\", got $r";; esac
    else case "$r" in *" to="*) no "TS table $1 carries to=: $r";; *) ok "[RED] TS table --defs=$1 (no to=)";; esac; fi
}
check_ts aliasIdent  'm'
check_ts aliasMember 'm.inner.leaf'
check_ts loaded      'require(&apos;./other&apos;)'
check_ts lazyMod     'import(&apos;./other&apos;)'
check_ts shape       ''
check_ts handlers    ''
check_ts list        ''
check_ts SCREAMING_ALIAS 'm.thing'
# TS near misses: not definitions
absent "$F/t" destructA  "a destructuring const"
absent "$F/t" counter    "a module let"
absent "$F/t" localConst "a function-local const"
absent "$F/t" called     "a call-valued const"
absent "$F/t" greeting   "a string const"
absent "$F/t" emptyBag   "an empty object const"
absent "$F/t" ambientThing "a .d.ts declare const"
absent "$F/m" minA7      "a const in a minified-suspect file"

# [RED] the skipped TS consts are COUNTED: called, greeting, emptyBag (3) — not the arrow const, the cast arrow or the class factory
# in other.ts, which other patterns index (a function, a function, a class); the minified file's 401 module consts
sk(){ ( cd "$1" && "$BIN" . --no-cache --skipped ) > "$TMP/sk" 2> "$TMP/skerr"; src=$?; v=$( grep -oE 'consts_skipped="[0-9]+"' "$TMP/sk" | head -1 ); }
sk "$F/t"; if [ "$src" -eq 0 ] && [ "$v" = 'consts_skipped="3"' ]; then ok "[RED] --skipped consts_skipped=\"3\" (call, string, empty object)"; else no "consts_skipped on the TS fixture: rc=$src got '${v:-<absent>}'"; fi
sk "$F/m"; if [ "$src" -eq 0 ] && [ "$v" = 'consts_skipped="401"' ]; then ok "[RED] minified bundle: consts_skipped=\"401\""; else no "minified bundle: rc=$src got '${v:-<absent>}'"; fi
sk "$F/c"; if [ "$src" -eq 0 ] && [ -z "$v" ]; then ok "C++ fixture: consts_skipped absent at zero"; else no "C++ fixture: rc=$src consts_skipped='${v}'"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/sk" 2>/dev/null; then ok "the --skipped answer carrying the clause is well-formed"; else no "--skipped answer not well-formed"; fi
    ( cd "$F/c" && "$BIN" . --no-cache --defs=ColumnPtr ) > "$TMP/x" 2>/dev/null
    if [ $? -eq 0 ] && xmllint --noout "$TMP/x" 2>/dev/null; then ok "the --defs answer carrying to= is well-formed"; else no "--defs to= answer not well-formed or failed"; fi
else
    echo "  SKIP  xmllint arms (xmllint not on PATH)"
fi

# a pathological 10 MB single-line TS file: never hangs (skipped by the crawl's size ceiling), and the run says so
mkdir -p "$F/big"; python3 -c "
import sys
open(sys.argv[1],'w').write('export const big = [' + ','.join(['x']*5_000_000) + '];\n')" "$F/big/huge.ts"
printf 'export const keep = other.thing;\n' > "$F/big/small.ts"
( cd "$F/big" && "$BIN" . --no-cache --defs=keep ) > "$TMP/big" 2>&1; brc=$?
if [ "$brc" -eq 0 ] && grep -q 'to="other.thing"' "$TMP/big"; then ok "10 MB one-line file beside an alias: the run finishes and indexes the alias"; else no "10 MB file: rc=$brc"; fi

echo "aliasdefcheck: $( [ "$fail" -eq 0 ] && echo PASS || echo FAIL )"
exit "$fail"
