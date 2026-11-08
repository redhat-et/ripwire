#!/usr/bin/env bash
# endpointfitcheck.sh — a --path endpoint whose spelling several definitions fit (none chosen) is answered by trying each of them
# (src/pathgaps.h resolvePathEndpoint fitOut, ENDPOINT-REFUSED), and still refuses, unchanged, when no pair reaches.
#
# THE DEFECT. `--path=ApplicationRef.tick,refreshView` on angular answered found=0 refused=3 ("3 definitions fit, none chosen") and
# exit 1, so the --for path rung printed nothing either, while the file-qualified spelling prints the full 8-hop chain. The
# refusal was right that the spelling cannot pick ONE definition; it was wrong to stop there, since --path already lists every
# reaching definition pair of a many-definition name (TRACE-EP, src/pathpairs.h) instead of picking.
#
# THE CONTRACT. Such an endpoint stands for every fitted definition the index places; from_fit=N / to_fit=N (the refusal's N) rides
# on the root beside from_defs=/to_defs= (the ones tried). One reaching pair prints that chain; two or more print every pair
# (pairs_reaching=, <pair>); NONE reaching keeps today's refusal byte for byte (stdout and stderr, exit 1). The --for path rung
# (graph_verb block) follows: a block when a pair reaches, no block (and no stray stderr) when none does. MCP path_between agrees.
#
# ARMS
#   (A) one reaches: three AppRef.tick (TS, no scope on the methods), only c/ reaches refreshView — the THIRD fitted definition, so
#       a "first definition" pick goes red: rc 0, reachable=1, from_fit=3, from_defs=3, from_p= c/app.ts, no pairs_reaching=.
#   (Z) none reaches: two AppRef.tick, neither calls refreshView: stdout and stderr equal the refusal text (refused="2", exit 1).
#   (B) two reach: pairs_reaching=2, both <pair>s (b/app.ts:3 and a/app.ts:3) — never one silently.
#   (F) --for "path from AppRef.tick to refreshView": a graph_verb block with from_fit= on A; on Z no graph_verb block and no
#       "endpoint not found" line on stderr.
#   (M) MCP path_between: A carries from_fit="3" and reachable="1"; Z is the not-found refusal (a JSON-RPC error naming from=).
#   (L) the legend clause (full) / the compact from_fit reading rides exactly when from_fit= prints.
#   (S) siblings that resolve today keep their bytes' meaning (no from_fit=, reachable=1): Go Server.Run namesakes in two packages,
#       a Python subclass override (Child.handle; bare handle), a C++ header declaration beside its .cc definition (Engine.start
#       binds the .cc body; eng.h:Engine.start binds the declaration alone, from_defs=1, untouched here).
#   (C) every arm reads the exit code of the command it inspects; a binary that prints nothing turns the gate red.
#
# Usage: test/endpointfitcheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "endpointfitcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

app_quiet(){ printf 'export class AppRef {\n  tick(): void {\n    console.log("%s");\n  }\n}\n' "$1"; }
app_reach(){ printf "import { refreshView } from '%s';\nexport class AppRef {\n  tick(): void {\n    this.detect();\n  }\n  detect(): void {\n    refreshView(1);\n  }\n}\n" "$1"; }
view(){ printf 'export function refreshView(n: number): number {\n  return n + 1;\n}\n'; }

mkdir -p "$TMP/one/a" "$TMP/one/b" "$TMP/one/c" "$TMP/none/a" "$TMP/none/b" "$TMP/two/a" "$TMP/two/b"
app_quiet a > "$TMP/one/a/app.ts"; app_quiet b > "$TMP/one/b/app.ts"; app_reach ./view > "$TMP/one/c/app.ts"; view > "$TMP/one/c/view.ts"
app_quiet a > "$TMP/none/a/app.ts"; app_quiet b > "$TMP/none/b/app.ts"; view > "$TMP/none/a/view.ts"
app_reach ./view > "$TMP/two/a/app.ts"; view > "$TMP/two/a/view.ts"
printf "import { refreshView } from '../a/view';\nexport class AppRef {\n  tick(): void {\n    refreshView(2);\n  }\n}\n" > "$TMP/two/b/app.ts"

# run DIR ARGS... → $TMP/out, $TMP/err, $rc
run(){ local d="$1"; shift; ( cd "$TMP/$d" || exit 99; "$BIN" "$TMP/$d" --no-cache "$@" > "$TMP/out" 2> "$TMP/err" ); rc=$?; }
root(){ grep -o '<path [^>]*>' "$TMP/out" | head -1; }

echo "(A) one fitted definition reaches (the third)"
run one --path=AppRef.tick,refreshView
r="$( root )"
if [ "$rc" -eq 0 ] && [[ "$r" == *'from_fit="3"'* ]] && [[ "$r" == *'from_defs="3"'* ]] && [[ "$r" == *'reachable="1"'* ]] \
   && [[ "$r" == *'from_p="c/app.ts:3"'* ]] && [[ "$r" != *pairs_reaching=* ]] && grep -q 'n="refreshView"' "$TMP/out"; then
    ok "(A) rc 0, from_fit=3, from_defs=3, from_p=c/app.ts:3, the chain to refreshView, no pairs_reaching="
else no "(A) rc=$rc root: ${r:-<none>}"; fi
run one --legend=full --path=AppRef.tick,refreshView
if [ "$rc" -eq 0 ] && grep -q 'from_fit=N / to_fit=N' "$TMP/out"; then ok "(L) the full from_fit legend clause rides"; else no "(L) no from_fit legend clause (rc=$rc)"; fi
run one --legend=compact --path=AppRef.tick,refreshView
if [ "$rc" -eq 0 ] && grep -q 'from_fit=N: from=' "$TMP/out"; then ok "(L) the compact from_fit reading rides"; else no "(L) compact: no from_fit reading (rc=$rc)"; fi

echo "(Z) no fitted definition reaches: today's refusal"
run none --path=AppRef.tick,refreshView
want_err="ripwire: --path endpoint not found: AppRef.tick (2 definitions fit 'AppRef.tick' and the spelling cannot tell which, so none is chosen; qualify it with its file, e.g. --path=FILE:AppRef.tick)"
if [ "$rc" -eq 1 ] && [ "$( cat "$TMP/err" )" = "$want_err" ] && grep -q '<path schema="ripwire.path/v1" from="AppRef.tick" to="refreshView" found="0" refused="2" missing="from"/>' "$TMP/out" \
   && ! grep -q 'from_fit=' "$TMP/out"; then
    ok "(Z) rc 1, the refusal text on stderr and the found=0 refused=2 document, no from_fit="
else no "(Z) rc=$rc err=$( head -c 300 "$TMP/err" ) out=$( grep -o '<path [^>]*>' "$TMP/out" )"; fi

echo "(B) two fitted definitions reach: both print"
run two --path=AppRef.tick,refreshView
r="$( root )"
np="$( grep -o '<pair ' "$TMP/out" | wc -l | tr -d ' ' )"
if [ "$rc" -eq 0 ] && [[ "$r" == *'pairs_reaching="2"'* ]] && [[ "$r" == *'from_fit="2"'* ]] && [ "$np" = 2 ] \
   && grep -q '<pair from_p="b/app.ts:3"' "$TMP/out" && grep -q '<pair from_p="a/app.ts:3"' "$TMP/out"; then
    ok "(B) pairs_reaching=2, two <pair>s (b/app.ts:3, a/app.ts:3), from_fit=2"
else no "(B) rc=$rc pairs=$np root: ${r:-<none>}"; fi

echo "(F) the --for path rung"
run one "--for=path from AppRef.tick to refreshView"
if [ "$rc" -eq 0 ] && grep -q '<graph_verb endpoints="subject" verb="--path=AppRef.tick,refreshView"' "$TMP/out" && grep -q 'from_fit="3"' "$TMP/out"; then
    ok "(F) one: a graph_verb block carrying from_fit=3"
else no "(F) one: rc=$rc, no graph_verb block with from_fit="; fi
run none "--for=path from AppRef.tick to refreshView"
if [ "$rc" -eq 0 ] && [ -s "$TMP/out" ] && ! grep -q '<graph_verb' "$TMP/out" && ! grep -q 'endpoint not found' "$TMP/err"; then
    ok "(F) none: an answer, no graph_verb block, no refusal line on stderr"
else no "(F) none: rc=$rc bytes=$( wc -c < "$TMP/out" ) graph_verb=$( grep -c '<graph_verb' "$TMP/out" )"; fi

echo "(M) MCP path_between"
python3 - "$BIN" "$TMP" <<'PY'
import json, subprocess, sys
binp, tmp = sys.argv[1], sys.argv[2]
reqs = [ { "jsonrpc": "2.0", "id": 0, "method": "initialize", "params": { "protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": { "name": "g", "version": "1" } } } ]
for i, d in enumerate( ( "one", "none" ) ):
    reqs.append( { "jsonrpc": "2.0", "id": i + 1, "method": "tools/call", "params": { "name": "path_between", "arguments": { "path": tmp + "/" + d, "from": "AppRef.tick", "to": "refreshView" } } } )
p = subprocess.run( [ binp, "--mcp" ], input = "".join( json.dumps( r ) + "\n" for r in reqs ), capture_output = True, text = True, timeout = 120 )
resp = {}
for line in p.stdout.splitlines():
    try:
        o = json.loads( line )
    except ValueError:
        continue
    if isinstance( o.get( "id" ), int ) and o[ "id" ] > 0:
        if "error" in o:   # the not-found refusal is a JSON-RPC error carrying its answer
            resp[ o[ "id" ] ] = ( o[ "error" ].get( "message", "" ) + json.dumps( o[ "error" ].get( "data", {} ) ), True )
            continue
        res = o.get( "result", {} )
        resp[ o[ "id" ] ] = ( "".join( c.get( "text", "" ) for c in res.get( "content", [] ) ), bool( res.get( "isError" ) ) )
one, none = resp.get( 1, ( "", False ) ), resp.get( 2, ( "", False ) )
bad = 0
if p.returncode == 0 and 'from_fit="3"' in one[0] and 'reachable="1"' in one[0] and not one[1]:
    print( "  PASS  (M) one: path_between carries from_fit=3, reachable=1" )
else:
    print( "  FAIL  (M) one: rc=%d %r" % ( p.returncode, one[0][:300] ) ); bad = 1
if none[1] and "path endpoint not found: from='AppRef.tick'" in none[0] and "from_fit" not in none[0]:
    print( "  PASS  (M) none: the not-found refusal (an error naming from=)" )
else:
    print( "  FAIL  (M) none: %r" % ( none, ) ); bad = 1
sys.exit( bad )
PY
[ $? -eq 0 ] || fail=1

echo "(S) siblings that resolve today: no from_fit="
mkdir -p "$TMP/go/p" "$TMP/go/q" "$TMP/py" "$TMP/cpp"
printf 'package p\n\ntype Server struct{}\n\nfunc (s *Server) Run() {\n\ts.loop()\n}\n\nfunc (s *Server) loop() {\n\tLeaf()\n}\n\nfunc Leaf() {}\n' > "$TMP/go/p/s.go"
printf 'package q\n\ntype Server struct{}\n\nfunc (s *Server) Run() {\n\tprintln("q")\n}\n' > "$TMP/go/q/s.go"
printf 'class Base:\n    def handle(self):\n        return 0\n\n\nclass Child(Base):\n    def handle(self):\n        return sink()\n\n\ndef sink():\n    return 1\n' > "$TMP/py/m.py"
printf '#pragma once\nclass Engine {\npublic:\n    void start();\n};\nvoid ignite();\n' > "$TMP/cpp/eng.h"
printf '#include "eng.h"\nvoid Engine::start() {\n    ignite();\n}\nvoid ignite() {}\n' > "$TMP/cpp/eng.cc"
for c in "go Server.Run,Leaf" "py Child.handle,sink" "py handle,sink" "cpp Engine.start,ignite"; do
    set -- $c
    run "$1" "--path=$2"
    r="$( root )"
    if [ "$rc" -eq 0 ] && [[ "$r" == *'reachable="1"'* ]] && [[ "$r" != *_fit=* ]]; then ok "(S) $1 --path=$2: reachable=1, no *_fit="
    else no "(S) $1 --path=$2: rc=$rc root: ${r:-<none>}"; fi
done
# the header-qualified spelling binds the declaration alone (from_defs=1, today reachable=0): a resolved endpoint, never fitted
run cpp --path=eng.h:Engine.start,ignite
r="$( root )"
if [ "$rc" -eq 0 ] && [[ "$r" == *'from_defs="1"'* ]] && [[ "$r" != *_fit=* ]]; then ok "(S) cpp --path=eng.h:Engine.start,ignite: resolved (from_defs=1), no *_fit="
else no "(S) cpp eng.h: rc=$rc root: ${r:-<none>}"; fi

[ "$fail" -eq 0 ] && echo "endpointfitcheck: PASS" || echo "endpointfitcheck: FAIL"
exit "$fail"
