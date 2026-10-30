#!/usr/bin/env bash
# fordeclrowcheck.sh — DECL-ROW (src/fordeclrow.h): a --for task about one C/C++/Go function's signature, or the function's bare
# name, carries the function's definition and declaration rows in <decl_rows> before </ctx>; the answer before it is unchanged.
#
# ARMS
#   (w1) task word in prose + identifier-shaped subject: both rows, the header row decl_only="1"; the block closes before </ctx>
#   (w2) task word + code-span subject (a qualified spelling falls back to its last segment)
#   (b1) bare subject fires; (b2) a bare name binding several definitions is silent, (b3) the same name WITH a task word fires
#   (n1) no prototype: silent, task word or bare; (n2) no task word: silent; (n3) the task word only inside a code span: silent
#   (n4) Python subject: silent; (n5) a prototype only in a test path: silent; (n6) a same-named struct, no callable: silent
#   (c1) the runaway cap: 8 rows, rows= the total, shown= and next=--defs=
#   (a1) additive: head minus legend + block == the answer's own bytes before them (est_tokens does not move); well-formed
#   (s1) --json carries no block; (s2) a token budget carries no block; (x1) MCP `for`: the same element bytes
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "fordeclrowcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FX="$TMP/fx"; mkdir -p "$FX/tests"
cat > "$FX/api.h" <<'C'
int run_it( int a );
int dup_fn( int a );
struct type_only;
C
cat > "$FX/api.c" <<'C'
#include "api.h"
int run_it( int a ) { return a + 1; }
static int solo_fn( int x ) { return x; }
int use_all( void ) { return run_it( 1 ) + solo_fn( 2 ); }
C
printf '#include "api.h"\nint dup_fn( int a ) { return a; }\n' > "$FX/dup_a.c"
printf 'int dup_fn( int a, int b ) { return a + b; }\n' > "$FX/dup_b.c"
printf 'int only_tested( int a );\nint case_one( void ) { return only_tested( 1 ); }\n' > "$FX/tests/t_case.c"
printf 'int only_tested( int a ) { return a; }\n' > "$FX/impl.c"
printf 'struct type_only { int a; };\n' > "$FX/types.c"
printf 'def py_fn(a):\n    return a\n\ndef py_user():\n    return py_fn(1)\n' > "$FX/mod.py"
: > "$FX/many.h"
for i in 0 1 2 3 4 5 6 7 8 9; do
    printf 'static int many_fn( int a ) { return a + %s; }\n' "$i" > "$FX/many_$i.c"
    printf 'int many_fn( int a, int b%s );\n' "$i" >> "$FX/many.h"
done
run(){ ( cd "$FX" || exit 1; "$BIN" "$FX" --no-cache "$@" 2>/dev/null </dev/null ); }
silent(){ # arm, argv...
    local arm="$1"; shift
    if run "$@" >"$TMP/o" && ! grep -q 'decl_rows' "$TMP/o" && grep -q '</ctx>$' "$TMP/o"; then ok "($arm) silent: $*"; else no "($arm) must be silent: $*"; fi
}
two_rows(){ # file, subject: rows="2", the definition row, the header row decl_only, closes before </ctx>
    python3 - "$1" "$2" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8" ).read()
m = re.search( r'<decl_rows of="([^"]*)" rows="(\d+)">(.*?)</decl_rows></ctx>$', s )
if not m or m.group( 1 ) != sys.argv[2] or m.group( 2 ) != "2": sys.exit( 1 )
rows = re.findall( r'<d [^>]*/>', m.group( 3 ) )
if len( rows ) != 2: sys.exit( 1 )
if not re.search( r'p="api\.c:\d+"', rows[0] ) or "decl_only" in rows[0]: sys.exit( 1 )
if not re.search( r'p="api\.h:1"', rows[1] ) or 'decl_only="1"' not in rows[1]: sys.exit( 1 )   # --defs folds this tied prototype into row 0
PY
}
run "--for=add a new argument to run_it" >"$TMP/w1.xml"
if two_rows "$TMP/w1.xml" run_it; then ok "(w1) prose task word + identifier-shaped subject: both rows, before </ctx>"; else no "(w1) $( grep -o '<decl_rows.*' "$TMP/w1.xml" | head -c 400 )"; fi
run '--for=which prototypes change if `app::run_it(int)` changes' >"$TMP/w2.xml"
if two_rows "$TMP/w2.xml" run_it; then ok "(w2) code-span subject, the last segment of a qualified spelling"; else no "(w2) $( grep -o '<decl_rows.*' "$TMP/w2.xml" | head -c 400 )"; fi
run "--for=run_it" >"$TMP/b1.xml"
if two_rows "$TMP/b1.xml" run_it; then ok "(b1) bare subject fires"; else no "(b1) $( grep -o '<decl_rows.*' "$TMP/b1.xml" | head -c 400 )"; fi
silent b2 "--for=dup_fn"
run "--for=change the signature of dup_fn" >"$TMP/b3.xml"
if grep -q '<decl_rows of="dup_fn" rows="[234]">' "$TMP/b3.xml"; then ok "(b3) several definitions with a task word: fires"; else no "(b3) $( grep -o '<decl_rows.*' "$TMP/b3.xml" | head -c 300 )"; fi
silent n1 "--for=change the signature of solo_fn"
silent n1 "--for=solo_fn"
silent n2 "--for=fix the off by one in run_it"
silent n3 '--for=explain run_it and `signature` handling'
silent n4 "--for=add a new argument to py_fn"
silent n4 "--for=py_fn"
silent n5 "--for=add a new argument to only_tested"
silent n6 "--for=change the signature of type_only"
run "--for=change the signature of many_fn" >"$TMP/c1.xml"
if python3 - "$TMP/c1.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8" ).read()
m = re.search( r'<decl_rows ([^>]*)>(.*?)</decl_rows>', s )
sys.exit( 0 if m and 'rows="20"' in m.group( 1 ) and 'shown="8"' in m.group( 1 ) and 'next="--defs=many_fn"' in m.group( 1 ) and len( re.findall( r'<d ', m.group( 2 ) ) ) == 8 else 1 )
PY
then ok "(c1) the cap cuts at 8 rows and says so"; else no "(c1) $( grep -o '<decl_rows [^>]*>' "$TMP/c1.xml" )"; fi
run "--for=run_it" --legend=full >"$TMP/a1.xml"
if python3 - "$TMP/b1.xml" <<'PY'
import re, sys, xml.dom.minidom as M
s = open( sys.argv[1], encoding="utf8" ).read()
M.parseString( s )
i = s.index( "<!-- ripwire for decl_rows:" )
leg = s[ i: s.index( "-->", i ) ]
if "--" in leg[ 4: ]: sys.exit( 1 )
for attr in ( "of=", "rows=", "shown=", "next=", "decl_only", "sel=", "sel_proven", "lang=", "class=", "in=", "p=" ):
    if attr not in leg: sys.exit( 1 )
if not s[ :i ].count( "<ctx" ) == 1 or "<decl_rows" in s[ :i ]: sys.exit( 1 )
PY
then ok "(a1) well formed, the block's own legend defines its attributes, nothing of it before the legend"; else no "(a1) block legend or shape"; fi
run "--for=run_it" --json >"$TMP/s1.json"
if [ -s "$TMP/s1.json" ] && ! grep -q 'decl_rows' "$TMP/s1.json"; then ok "(s1) --json carries no block"; else no "(s1) --json"; fi
run "--for=run_it" --token-budget=4000 >"$TMP/s2.xml"
if [ -s "$TMP/s2.xml" ] && ! grep -q 'decl_rows' "$TMP/s2.xml"; then ok "(s2) a token budget carries no block"; else no "(s2) budget"; fi
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"add a new argument to run_it"}}}\n' "$FX" \
  | ( cd "$FX" || exit 1; "$BIN" --mcp 2>/dev/null ) | python3 -c '
import json, sys
for line in sys.stdin:
    d = json.loads( line )
    if d.get( "id" ) == 1:
        print( d["result"]["content"][0]["text"], end="" )
' >"$TMP/x1.xml"
if [ -n "$( grep -o '<decl_rows.*</decl_rows>' "$TMP/w1.xml" )" ] && [ "$( grep -o '<decl_rows.*</decl_rows>' "$TMP/x1.xml" )" = "$( grep -o '<decl_rows.*</decl_rows>' "$TMP/w1.xml" )" ]
then ok "(x1) MCP for: the same element bytes"; else no "(x1) MCP: $( grep -o '<decl_rows.*' "$TMP/x1.xml" | head -c 300 )"; fi
[ "$fail" = 0 ] && echo "fordeclrowcheck: PASS" || echo "fordeclrowcheck: FAIL"
exit "$fail"
