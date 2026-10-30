#!/usr/bin/env bash
# forimporterscheck.sh — EXEMPLAR importer sub-block (src/forimporters.h): a --for task that adds a new thing modeled on a NAMED one
# carries the source files importing the model's file in <importers> before </ctx>; the list-of-imports file says so and leads.
#
# ARMS
#   (f1) add a new + `Use Model as the model`: the aggregator first with aggregator="1", the plain importer after, the test importer
#        counted not listed; of=, importers=, test_importers=; closes before </ctx>; well-formed; the legend hedges "not the only"
#   (f2) "modeled after Model", a code-span name; (f3) "another ... like Model" (the other cue words)
#   (n1) add-new words but no model named: silent; (n2) a model named but no add-new words: silent; (n3) the add-new words only
#        inside a code span: silent; (n4) add ... new in another sentence: silent; (n5) a lowercase name after the cue: silent
#   (n6) the model does not resolve: silent; (n7) the model's file has only test importers: silent; (n8) no importer at all: silent
#   (n9) the model is defined only in a test path: silent
#   (c1) the cap: 6 rows, importers= the total, shown= and next=--impact=
#   (s1) --json carries no block; (s2) a token budget carries no block; (x1) MCP `for`: the same element bytes
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forimporterscheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FX="$TMP/fx"; mkdir -p "$FX/src/contrib/brackets" "$FX/src/contrib/tested" "$FX/src/contrib/lonely" "$FX/src/contrib/popular" "$FX/src/test" "$FX/src/all"
cat > "$FX/src/contrib/brackets/brackets.ts" <<'T'
export class BracketModel { run(): number { return 1; } }
T
printf "import '../contrib/brackets/brackets';\nimport '../contrib/popular/popular';\n" > "$FX/src/all/editor.all.ts"
cat > "$FX/src/user.ts" <<'T'
import { BracketModel } from './contrib/brackets/brackets';
export function makeOne(): number { return new BracketModel().run(); }
T
cat > "$FX/src/test/brackets.test.ts" <<'T'
import { BracketModel } from '../contrib/brackets/brackets';
export function caseOne(): number { return new BracketModel().run(); }
T
printf 'export class TestedModel { run(): number { return 2; } }\n' > "$FX/src/contrib/tested/tested.ts"
printf "import { TestedModel } from '../contrib/tested/tested';\nexport function caseTwo(): number { return new TestedModel().run(); }\n" > "$FX/src/test/tested.test.ts"
printf 'export class LonelyModel { run(): number { return 3; } }\n' > "$FX/src/contrib/lonely/lonely.ts"
printf 'export class PopularModel { run(): number { return 4; } }\n' > "$FX/src/contrib/popular/popular.ts"
printf 'export function helper_fn(): number { return 5; }\n' > "$FX/src/contrib/helper.ts"
printf "import { helper_fn } from './contrib/helper';\nexport function useHelper(): number { return helper_fn(); }\n" > "$FX/src/usehelper.ts"
printf 'export class SpecOnlyModel { run(): number { return 6; } }\n' > "$FX/src/test/speconly.ts"
printf "import { SpecOnlyModel } from './test/speconly';\nexport function useSpec(): number { return new SpecOnlyModel().run(); }\n" > "$FX/src/usespec.ts"
for i in 0 1 2 3 4 5 6 7; do
    printf "import { PopularModel } from './contrib/popular/popular';\nexport function pop%s(): number { return new PopularModel().run(); }\n" "$i" > "$FX/src/pop$i.ts"
done
run(){ ( cd "$FX" || exit 1; "$BIN" "$FX" --no-cache "$@" 2>/dev/null </dev/null ); }
silent(){ # arm, argv...
    local arm="$1"; shift
    if run "$@" >"$TMP/o" && ! grep -q '<importers ' "$TMP/o" && grep -q '</ctx>$' "$TMP/o"; then ok "($arm) silent: $*"; else no "($arm) must be silent: $*"; fi
}
facts(){ python3 - "$1" <<'PY'
import re, sys, xml.dom.minidom as M
s = open( sys.argv[1], encoding="utf8" ).read()
M.parseString( s )
m = re.search( r'<importers of="BracketModel" importers="2" test_importers="1"[^>]*>(.*?)</importers></ctx>$', s )
if not m: sys.exit( 1 )
rows = re.findall( r'<f [^>]*/>', m.group( 1 ) )
if rows != [ '<f p="src/all/editor.all.ts" aggregator="1"/>', '<f p="src/user.ts"/>' ]: sys.exit( 1 )
i = s.index( "<!-- ripwire for importers:" )
leg = s[ i: s.index( "-->", i ) ]
if "not the only" not in leg or "--" in leg[ 4: ]: sys.exit( 1 )
for attr in ( "of=", "importers=", "shown=", "next=", "aggregator", "test_importers=", "imports_unresolved=", "p=" ):
    if attr not in leg: sys.exit( 1 )
PY
}
run "--for=add a new editor feature. Use BracketModel as the model." >"$TMP/f1.xml"
if facts "$TMP/f1.xml"; then ok "(f1) the aggregator first, the plain importer, the test importer counted"; else no "(f1) $( grep -o '<importers.*' "$TMP/f1.xml" | head -c 400 )"; fi
run '--for=implement a new feature modeled after `BracketModel`' >"$TMP/f2.xml"
if facts "$TMP/f2.xml"; then ok "(f2) modeled after + a code-span name"; else no "(f2) $( grep -o '<importers.*' "$TMP/f2.xml" | head -c 400 )"; fi
run '--for=write another feature like BracketModel' >"$TMP/f3.xml"
if facts "$TMP/f3.xml"; then ok "(f3) another + like"; else no "(f3) $( grep -o '<importers.*' "$TMP/f3.xml" | head -c 400 )"; fi
silent n1 "--for=add a new editor feature following the existing pattern"
silent n2 "--for=how does BracketModel work, use BracketModel as the model"
silent n3 '--for=`add a new feature` like BracketModel'
silent n4 "--for=add logging. The new code should look like BracketModel"
silent n5 "--for=add a new feature like helper_fn"
silent n6 "--for=add a new feature like NoSuchModel"
silent n7 "--for=add a new feature like TestedModel"
silent n8 "--for=add a new feature like LonelyModel"
silent n9 "--for=add a new feature like SpecOnlyModel"
run "--for=add a new feature like PopularModel" >"$TMP/c1.xml"
if python3 - "$TMP/c1.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8" ).read()
m = re.search( r'<importers ([^>]*)>(.*?)</importers>', s )
sys.exit( 0 if m and 'shown="6"' in m.group( 1 ) and 'next="--impact=PopularModel"' in m.group( 1 ) and len( re.findall( r'<f ', m.group( 2 ) ) ) == 6 and int( re.search( r'importers="(\d+)"', m.group( 1 ) ).group( 1 ) ) >= 8 else 1 )
PY
then ok "(c1) the cap cuts at 6 rows and says so"; else no "(c1) $( grep -o '<importers [^>]*>' "$TMP/c1.xml" )"; fi
run "--for=write another feature like BracketModel" --json >"$TMP/s1.json"
if [ -s "$TMP/s1.json" ] && ! grep -q '<importers ' "$TMP/s1.json"; then ok "(s1) --json carries no block"; else no "(s1) --json"; fi
run "--for=write another feature like BracketModel" --token-budget=4000 >"$TMP/s2.xml"
if [ -s "$TMP/s2.xml" ] && ! grep -q '<importers ' "$TMP/s2.xml"; then ok "(s2) a token budget carries no block"; else no "(s2) budget"; fi
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"write another feature like BracketModel"}}}\n' "$FX" \
  | ( cd "$FX" || exit 1; "$BIN" --mcp 2>/dev/null ) | python3 -c '
import json, sys
for line in sys.stdin:
    d = json.loads( line )
    if d.get( "id" ) == 1:
        print( d["result"]["content"][0]["text"], end="" )
' >"$TMP/x1.xml"
if [ -n "$( grep -o '<importers .*</importers>' "$TMP/f3.xml" )" ] && [ "$( grep -o '<importers .*</importers>' "$TMP/x1.xml" )" = "$( grep -o '<importers .*</importers>' "$TMP/f3.xml" )" ]
then ok "(x1) MCP for: the same element bytes"; else no "(x1) MCP: $( grep -o '<importers.*' "$TMP/x1.xml" | head -c 300 )"; fi
[ "$fail" = 0 ] && echo "forimporterscheck: PASS" || echo "forimporterscheck: FAIL"
exit "$fail"
