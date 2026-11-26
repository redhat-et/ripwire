#!/usr/bin/env bash
# pathambigcheck.sh — PATH-AMBIG-VERDICT: --path never gives a definite verdict from many unlisted candidate pairs, and a
# qualified Owner.method endpoint narrows, never refuses (src/pathpairs.h nearest_of=, src/graph.h ownerSpellingFittedDefs).
# PATH-AMBIG-VC: --verify=calls(A,B), --connect and MCP path_between / connect bind that endpoint the same way.
#
# THE DEFECT (found in the 0.7.0 comparison rehearsal, verified on the M5 at d624cff5f).
#   1. nushell `--path=eval_call,run` answered reachable="1" hops="1" beside pairs_unlisted="833": to= names more definition
#      groups than the 16 the pair walk visits, so the one multi-source BFS's NEAREST pair was printed and nothing on the root
#      said the verdict was about that pair only, out of 4 x 833 candidates, rather than about the pair the reader meant.
#   2. vscode bare `_createInstance` (2 definitions) is searched, while the MORE specific `InstantiationService._createInstance`
#      answered rc=1 "2 definitions fit ... none is chosen": the written-spelling tier refuses two same-chain classes in two
#      files (a vendored copy), and --path, which lists every reaching pair and never picks one, inherited that refusal.
#
# THE CONTRACT.
#   (a) An answer whose pairs were NOT walked (pairs_unlisted=G) carries nearest_of="K", K = from= groups x to= groups: the
#       root's reachable=/hops= describe the nearest of K candidate pairs, not a chosen one; next= qualifies both ends; the
#       legend defines nearest_of= exactly when it prints. A walked answer (16 groups, listed pairs) carries none.
#   (b) A scope-qualified endpoint (Owner.method) that every resolution tier refused because several definitions fit it, all
#       of them named the spelling's last segment (the dot acted as the separator, #657's rule), binds those definitions:
#       the owner narrows (Other._make is not among them) and nothing is refused. A wrong owner still refuses; the one-source
#       narrowing (GV-PATH-BIND, narrowed=) still runs first.
#   (c) Unique endpoints and every answer outside (a)/(b) are unchanged: no nearest_of=, and with RIPWIRE_BASE_BIN set, the
#       control calls are byte-identical (stdout + stderr + rc) to that binary's.
#   PATH-AMBIG-VC: the same Owner.method binding on the other verbs that pick no single reading, through ONE binder
#   (src/graph.h ownerSpellingFittedDefs; src/forgraphverb.h bindPathEndpoints / ConnectTerminalSpellings, now shared by both
#   transports). (d) --verify=calls(A,B): Svc._make binds the two Svc copies on either end, a wrong owner refuses; it has no M1
#   step, so a source copy + a tests/ copy binds both (from_defs=2, no narrowed=). (e) --connect: the terminal searches the two
#   copies (t defs=2), a wrong owner refuses, the M1 narrowing runs first. (f) MCP path_between + connect: the same, path_between
#   now with the CLI's M1 narrowing (narrowed=) and the CLI's root + hop rows. (g) single definitions and the wrong owner:
#   unchanged, byte-identical (stdout + stderr + rc; MCP the whole response) to RIPWIRE_BASE_BIN when set.
# Every arm counts its premise and FAILS on zero.
#
# Usage: test/pathambigcheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire); RIPWIRE_BASE_BIN = optional base binary
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
BASE="${RIPWIRE_BASE_BIN:-}"
echo "pathambigcheck: BIN=$BIN${BASE:+ BASE=$BASE}"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

# fixtures, generated here (never committed where a whole-repo run sees them)
mkdir -p "$TMP/wide/pkg" "$TMP/walked" "$TMP/uniq" "$TMP/own/src/a" "$TMP/own/src/b" "$TMP/twin/src/a" "$TMP/twin/tests"
python3 - "$TMP" <<'PY'
import sys
t = sys.argv[1]
# (a) two start() definitions, 17 target() groups: past the 16 the pair walk visits
open( t + "/wide/k.py", "w" ).write( "".join( "class C%d:\n    def target(self):\n        return 1\n\n" % i for i in range( 17 ) )
                                     + "def start(x):\n    return x.target()\n" )
open( t + "/wide/pkg/s.py", "w" ).write( "def start(y):\n    return y.target()\n" )   # a second start() (its call is declined: it does not reach)
# (a) control: 16 groups are walked and listed
open( t + "/walked/k.py", "w" ).write( "".join( "class C%d:\n    def target(self):\n        return 1\n\n" % i for i in range( 16 ) )
                                       + "def start(x):\n    return x.target()\n" )
open( t + "/uniq/u.py", "w" ).write( "def leaf():\n    return 1\n\ndef mid():\n    return leaf()\n\ndef top():\n    return mid()\n" )
PY
# (b) TS records no Symbol::scope for a class method: two same-chain Svc classes in two files (a vendored copy) and an Other
for d in a b; do
cat > "$TMP/own/src/$d/svc.ts" <<'EOF'
import { sink } from '../sink';
export class Svc {
  _make(): number { return sink(); }
}
EOF
done
cat > "$TMP/own/src/sink.ts" <<'EOF'
export function sink(): number { return 1; }
EOF
cat > "$TMP/own/src/other.ts" <<'EOF'
export class Other {
  _make(): number { return 2; }
}
EOF
cat > "$TMP/own/src/use.ts" <<'EOF'
import { Svc } from './a/svc';
export function boot(s: Svc): number { return s._make(); }
EOF
# (b) the one-source narrowing still runs first: one source Svc._make and a copy under tests/
cat > "$TMP/twin/src/a/svc.ts" <<'EOF'
import { sink } from '../sink';
export class Svc {
  _make(): number { return sink(); }
}
EOF
cp "$TMP/own/src/sink.ts" "$TMP/twin/src/sink.ts"
cat > "$TMP/twin/tests/svc.ts" <<'EOF'
export class Svc {
  _make(): number { return 3; }
}
EOF

run(){ ( cd "$TMP/$2" || exit 1; "$1" "$TMP/$2" --no-cache "--path=$3" "${@:4}" </dev/null ); }
root(){ python3 - "$1" <<'PY'
import re, sys
m = re.search( r"<path [^>]*>", open( sys.argv[1] ).read() )
print( m.group( 0 ) if m else "" )
PY
}
attr(){ printf '%s' "$1" | python3 -c 'import re,sys; m=re.search(r" %s=\"([^\"]*)\""%sys.argv[1], sys.stdin.read()); print(m.group(1) if m else "")' "$2"; }

# ── (a) nearest_of= on an unwalked answer ────────────────────────────────────────────────────────────────────────────────
run "$BIN" wide start,target > "$TMP/A.out" 2> "$TMP/A.err"; ra=$?
RA="$( root "$TMP/A.out" )"
premA=0
if [ "$( attr "$RA" from_defs )" = "2" ] && [ "$( attr "$RA" pairs_unlisted )" = "17" ] && [ "$( attr "$RA" reachable )" = "1" ]; then premA=1; fi
[ "$premA" = 1 ] || no "(a) premise: 2 from= x 17 to= groups, reached, pairs_unlisted=17 (rc=$ra): $RA"
if [ "$premA" = 1 ] && [ "$( attr "$RA" nearest_of )" = "34" ]; then ok "(a) unwalked pairs: nearest_of=\"34\" (2 from= x 17 to= groups) beside reachable=1"
else no "(a) unwalked pairs carry nearest_of=\"34\": got '$( attr "$RA" nearest_of )'"; fi
nx="$( attr "$RA" next )"
if [ "$premA" = 1 ] && printf '%s' "$nx" | grep -qE '^--path=[^,]*:start,[^,]*:+(C[0-9]+::)?target$'; then ok "(a) next= qualifies both ends: $nx"
else no "(a) next= qualifies both ends: '$nx'"; fi
if [ "$premA" = 1 ] && grep -q 'nearest_of=' "$TMP/A.out" && sed -n '1,/-->/p' "$TMP/A.out" | grep -q 'nearest_of=K'; then ok "(a) the legend defines nearest_of= where it prints"
else no "(a) the legend defines nearest_of= where it prints"; fi
run "$BIN" wide start,target --legend=full > "$TMP/AF.out" 2>/dev/null
if [ "$premA" = 1 ] && grep -q 'nearest_of=K' "$TMP/AF.out"; then ok "(a) the full legend defines nearest_of= too"
else no "(a) the full legend defines nearest_of= too"; fi
# the reading must not promise the ORIGINAL nearest route: pathRouteVerdict can print a proven route (route_hedged=) in its place
# (CodeRabbit #665); both legends say so
if [ "$premA" = 1 ] && sed -n '1,/-->/p' "$TMP/A.out" | grep -o 'nearest_of=K[^;]*;[^;]*' | grep -q 'route_hedged=' \
   && grep -o 'nearest_of=K[^;]*;[^;]*' "$TMP/AF.out" | grep -q 'route_hedged='; then ok "(a) both nearest_of= readings allow for a route_hedged= replacement route"
else no "(a) the nearest_of= reading promises the nearest route although route_hedged= can replace it"; fi
# one from= definition: K = 1 x 17
run "$BIN" wide k.py:start,target > "$TMP/A1.out" 2>/dev/null
RA1="$( root "$TMP/A1.out" )"
if [ "$( attr "$RA1" from_defs )" = "1" ] && [ "$( attr "$RA1" pairs_unlisted )" = "17" ]; then
    if [ "$( attr "$RA1" nearest_of )" = "17" ]; then ok "(a) one from= definition: nearest_of=\"17\""; else no "(a) one from= definition: nearest_of=\"17\", got '$( attr "$RA1" nearest_of )'"; fi
else no "(a) premise: k.py:start binds one definition, 17 to= groups: $RA1"; fi
# control: 16 groups are walked, pairs listed, no nearest_of=
run "$BIN" walked start,target > "$TMP/W.out" 2>/dev/null
RW="$( root "$TMP/W.out" )"
if [ -n "$( attr "$RW" pairs_reaching )" ]; then
    if [ -z "$( attr "$RW" nearest_of )" ] && ! grep -q 'nearest_of' "$TMP/W.out"; then ok "(a) walked control: pairs listed (pairs_reaching=$( attr "$RW" pairs_reaching )), no nearest_of= and no clause"
    else no "(a) walked control carries nearest_of"; fi
else no "(a) premise: the 16-group control lists its pairs: $RW"; fi

# ── (b) Owner.method narrows, never refuses ───────────────────────────────────────────────────────────────────────────────
run "$BIN" own _make,sink > "$TMP/B0.out" 2> "$TMP/B0.err"; rb0=$?
RB0="$( root "$TMP/B0.out" )"
premB=0
[ "$rb0" = 0 ] && [ "$( attr "$RB0" from_defs )" = "3" ] && premB=1
if [ "$premB" = 1 ]; then ok "(b) premise: bare _make resolves (from_defs=3: two Svc copies + Other)"
else no "(b) premise: bare _make resolves with 3 definitions (rc=$rb0): $RB0"; fi
run "$BIN" own Svc._make,sink > "$TMP/B1.out" 2> "$TMP/B1.err"; rb1=$?
RB1="$( root "$TMP/B1.out" )"
if [ "$premB" = 1 ] && [ "$rb1" = 0 ] && [ "$( attr "$RB1" from_defs )" = "2" ] && [ "$( attr "$RB1" reachable )" = "1" ] && ! grep -q 'other.ts' "$TMP/B1.out"; then
    ok "(b) from= Svc._make narrows to the two Svc copies (from_defs=2, Other not listed), reached, rc=0"
else no "(b) from= Svc._make narrows, never refuses: rc=$rb1 $RB1 $( head -c 300 "$TMP/B1.err" )"; fi
run "$BIN" own boot,Svc._make > "$TMP/B2.out" 2> "$TMP/B2.err"; rb2=$?
RB2="$( root "$TMP/B2.out" )"
if [ "$premB" = 1 ] && [ "$rb2" = 0 ] && [ "$( attr "$RB2" to_defs )" = "2" ] && [ "$( attr "$RB2" reachable )" = "1" ]; then
    ok "(b) to= Svc._make narrows the same way (to_defs=2), reached, rc=0"
else no "(b) to= Svc._make narrows, never refuses: rc=$rb2 $RB2 $( head -c 300 "$TMP/B2.err" )"; fi
run "$BIN" own Nope._make,sink > "$TMP/B3.out" 2> "$TMP/B3.err"; rb3=$?
if [ "$premB" = 1 ] && [ "$rb3" = 1 ] && grep -q 'missing="from"' "$TMP/B3.out"; then ok "(b) a wrong owner (Nope._make) still refuses: it never widens to the bare name"
else no "(b) a wrong owner still refuses: rc=$rb3 $( root "$TMP/B3.out" )"; fi
run "$BIN" twin Svc._make,sink > "$TMP/B4.out" 2> "$TMP/B4.err"; rb4=$?
RB4="$( root "$TMP/B4.out" )"
if [ "$rb4" = 0 ] && [ -n "$( attr "$RB4" narrowed )" ] && [ "$( attr "$RB4" from_defs )" = "1" ]; then ok "(b) one source copy + a tests/ copy: the one-source narrowing still runs first (narrowed=, from_defs=1)"
else no "(b) premise/order: the GV-PATH-BIND narrowing runs first: rc=$rb4 $RB4"; fi
run "$BIN" own Other._make,sink > "$TMP/B5.out" 2>/dev/null
RB5="$( root "$TMP/B5.out" )"
if [ "$( attr "$RB5" from_defs )" = "1" ]; then ok "(b) a single-entity owner (Other._make) resolves as before (from_defs=1)"
else no "(b) Other._make resolves to one definition: $RB5"; fi

# ── (c) unique endpoints and every control unchanged ──────────────────────────────────────────────────────────────────────
premC=0
for spec in "uniq top,leaf" "uniq leaf,top" "own boot,sink" "own Other._make,sink" "walked start,target" "own Nope._make,sink"; do
    set -- $spec
    run "$BIN" "$1" "$2" > "$TMP/C.out" 2> "$TMP/C.err"; rc=$?
    premC=$(( premC + 1 ))
    if grep -q 'nearest_of' "$TMP/C.out"; then no "(c) $1 --path=$2 carries nearest_of"; fi
    if [ -n "$BASE" ]; then
        run "$BASE" "$1" "$2" > "$TMP/CB.out" 2> "$TMP/CB.err"; rcb=$?
        if [ "$rc" = "$rcb" ] && cmp -s "$TMP/C.out" "$TMP/CB.out" && cmp -s "$TMP/C.err" "$TMP/CB.err"; then ok "(c) $1 --path=$2: stdout + stderr + rc byte-identical to the base"
        else no "(c) $1 --path=$2 differs from the base (rc $rc vs $rcb)"; fi
    fi
done
RU="$( run "$BIN" uniq top,leaf 2>/dev/null | python3 -c 'import re,sys; m=re.search(r"<path [^>]*>", sys.stdin.read()); print(m.group(0) if m else "")' )"
if [ "$premC" -gt 0 ] && [ "$( attr "$RU" from_defs )" = "1" ] && [ "$( attr "$RU" to_defs )" = "1" ] && [ "$( attr "$RU" reachable )" = "1" ] && [ -z "$( attr "$RU" nearest_of )" ]; then
    ok "(c) unique ends: reached, no nearest_of= ($premC controls checked${BASE:+ against the base})"
else no "(c) premise: unique ends reach with one definition each: $RU"; fi

# ── PATH-AMBIG-VC: --verify, --connect and MCP path_between / connect bind a two-copy Owner.method as --path does ─────────────
# (d) --verify=calls(A,B), (e) --connect, (f) MCP path_between + connect: Svc._make binds the two Svc copies (Other's is not among
# them), a wrong owner (Nope._make) still refuses, the one-source narrowing still runs first (narrowed=). (g) single-definition
# calls are byte-identical (stdout + stderr + rc; MCP: the whole response) to RIPWIRE_BASE_BIN when it is set.
cli(){ ( cd "$TMP/$2" || exit 1; "$1" "$TMP/$2" --no-cache "${@:3}" </dev/null ); }
vroot(){ python3 -c 'import re,sys; m=re.search(r"<verify [^>]*>", open(sys.argv[1]).read()); print(m.group(0) if m else "")' "$1"; }
croot(){ python3 -c 'import re,sys; m=re.search(r"<connect [^>]*>", open(sys.argv[1]).read()); print(m.group(0) if m else "")' "$1"; }
# the <t> row of terminal name $2 in answer file $1
trow(){ python3 -c 'import re,sys; m=re.search(r"<t n=\"%s\"[^>]*/>"%re.escape(sys.argv[2]), open(sys.argv[1]).read()); print(m.group(0) if m else "")' "$1" "$2"; }

# ── (d) --verify=calls(A,B) ──
cli "$BIN" own "--verify=calls(_make, sink)" > "$TMP/D0.out" 2> "$TMP/D0.err"; rd0=$?
premD=0
if [ "$rd0" = 0 ] && [ "$( attr "$( vroot "$TMP/D0.out" )" from_defs )" = "3" ]; then premD=1; ok "(d) premise: --verify bare _make resolves (from_defs=3)"
else no "(d) premise: --verify bare _make resolves with 3 definitions (rc=$rd0): $( vroot "$TMP/D0.out" )"; fi
cli "$BIN" own "--verify=calls(Svc._make, sink)" > "$TMP/D1.out" 2> "$TMP/D1.err"; rd1=$?
RD1="$( vroot "$TMP/D1.out" )"
if [ "$premD" = 1 ] && [ "$rd1" = 0 ] && [ "$( attr "$RD1" from_defs )" = "2" ] && [ "$( attr "$RD1" verdict )" = "confirmed" ] && ! grep -q 'other.ts' "$TMP/D1.out"; then
    ok "(d) --verify calls(Svc._make, sink): the two Svc copies (from_defs=2, Other not listed), confirmed, rc=0"
else no "(d) --verify calls(Svc._make, sink) binds, never refuses: rc=$rd1 $RD1 $( head -c 300 "$TMP/D1.err" )"; fi
cli "$BIN" own "--verify=calls(boot, Svc._make)" > "$TMP/D2.out" 2> "$TMP/D2.err"; rd2=$?
RD2="$( vroot "$TMP/D2.out" )"
if [ "$premD" = 1 ] && [ "$rd2" = 0 ] && [ "$( attr "$RD2" to_defs )" = "2" ] && [ "$( attr "$RD2" verdict )" = "confirmed" ]; then
    ok "(d) --verify calls(boot, Svc._make): to_defs=2, confirmed, rc=0"
else no "(d) --verify calls(boot, Svc._make) binds, never refuses: rc=$rd2 $RD2 $( head -c 300 "$TMP/D2.err" )"; fi
cli "$BIN" own "--verify=calls(Nope._make, sink)" > "$TMP/D3.out" 2> "$TMP/D3.err"; rd3=$?
if [ "$premD" = 1 ] && [ "$rd3" = 1 ] && [ ! -s "$TMP/D3.out" ] && grep -q 'not found: Nope._make' "$TMP/D3.err"; then ok "(d) --verify: a wrong owner (Nope._make) still refuses"
else no "(d) --verify: a wrong owner still refuses: rc=$rd3 $( head -c 300 "$TMP/D3.err" )"; fi
cli "$BIN" twin "--verify=calls(Svc._make, sink)" > "$TMP/D4.out" 2> "$TMP/D4.err"; rd4=$?
RD4="$( vroot "$TMP/D4.out" )"
if [ "$rd4" = 0 ] && [ "$( attr "$RD4" from_defs )" = "2" ] && [ "$( attr "$RD4" verdict )" = "confirmed" ] && ! grep -q 'narrowed=' "$TMP/D4.out"; then
    ok "(d) --verify: one source copy + a tests/ copy binds both (from_defs=2, confirmed, no narrowed=: --verify has no M1 step)"
else no "(d) --verify: a source copy + a tests/ copy binds both: rc=$rd4 $RD4"; fi

# ── (e) --connect ──
cli "$BIN" own --connect=_make,sink > "$TMP/E0.out" 2> "$TMP/E0.err"; re0=$?
premE=0
if [ "$re0" = 0 ] && [ "$( attr "$( trow "$TMP/E0.out" _make )" defs )" = "3" ]; then premE=1; ok "(e) premise: --connect bare _make resolves (t defs=3)"
else no "(e) premise: --connect bare _make resolves with 3 definitions (rc=$re0): $( trow "$TMP/E0.out" _make )"; fi
cli "$BIN" own --connect=Svc._make,sink > "$TMP/E1.out" 2> "$TMP/E1.err"; re1=$?
TE1="$( trow "$TMP/E1.out" _make )"
if [ "$premE" = 1 ] && [ "$re1" = 0 ] && [ "$( attr "$TE1" defs )" = "2" ] && [ "$( attr "$( croot "$TMP/E1.out" )" groups )" = "1" ] && ! grep -q 'other.ts' "$TMP/E1.out"; then
    ok "(e) --connect=Svc._make,sink: searched the two Svc copies (t defs=2, Other not listed), one group, rc=0"
else no "(e) --connect=Svc._make,sink binds, never refuses: rc=$re1 $TE1 $( head -c 300 "$TMP/E1.err" )"; fi
cli "$BIN" own --connect=boot,Svc._make > "$TMP/E2.out" 2> "$TMP/E2.err"; re2=$?
if [ "$premE" = 1 ] && [ "$re2" = 0 ] && [ "$( attr "$( trow "$TMP/E2.out" _make )" defs )" = "2" ] && [ "$( attr "$( croot "$TMP/E2.out" )" groups )" = "1" ]; then
    ok "(e) --connect=boot,Svc._make: t defs=2, one group, rc=0"
else no "(e) --connect=boot,Svc._make binds, never refuses: rc=$re2 $( croot "$TMP/E2.out" ) $( head -c 300 "$TMP/E2.err" )"; fi
cli "$BIN" own --connect=Nope._make,sink > "$TMP/E3.out" 2> "$TMP/E3.err"; re3=$?
if [ "$premE" = 1 ] && [ "$re3" = 1 ] && [ ! -s "$TMP/E3.out" ] && grep -q 'not found: Nope._make' "$TMP/E3.err"; then ok "(e) --connect: a wrong owner (Nope._make) still refuses"
else no "(e) --connect: a wrong owner still refuses: rc=$re3 $( head -c 300 "$TMP/E3.err" )"; fi
cli "$BIN" twin --connect=Svc._make,sink > "$TMP/E4.out" 2> "$TMP/E4.err"; re4=$?
if [ "$re4" = 0 ] && [ "$( attr "$( croot "$TMP/E4.out" )" narrowed )" = "Svc._make" ]; then ok "(e) --connect: the one-source narrowing still runs first (narrowed=)"
else no "(e) --connect: the GV-PATH-BIND narrowing runs first: rc=$re4 $( croot "$TMP/E4.out" )"; fi

# ── (f) MCP path_between + connect ──
# one server session, every request; prints one line per id: "<id> ok|err <text or error answer>" (newlines folded)
mcp(){ python3 - "$1" "$TMP" <<'PY'
import json, subprocess, sys
binp, tmp = sys.argv[1], sys.argv[2]
calls = [ ( "path_between", "own", { "from": "_make", "to": "sink" } ),           # 1 premise
          ( "path_between", "own", { "from": "Svc._make", "to": "sink" } ),       # 2
          ( "path_between", "own", { "from": "boot", "to": "Svc._make" } ),       # 3
          ( "path_between", "own", { "from": "Nope._make", "to": "sink" } ),      # 4 wrong owner
          ( "path_between", "twin", { "from": "Svc._make", "to": "sink" } ),      # 5 one-source narrowing
          ( "connect", "own", { "symbols": [ "Svc._make", "sink" ] } ),           # 6
          ( "connect", "own", { "symbols": [ "Nope._make", "sink" ] } ),          # 7 wrong owner
          ( "path_between", "uniq", { "from": "top", "to": "leaf" } ),            # 8 negative: single definitions
          ( "path_between", "own", { "from": "boot", "to": "sink" } ),            # 9 negative
          ( "connect", "uniq", { "symbols": [ "top", "leaf" ] } ),                # 10 negative
          ( "connect", "own", { "symbols": [ "Other._make", "sink" ] } ),         # 11 negative: a single-entity owner
          ( "path_between", "own", { "from": "Svc._make", "to": "NoSuchSym_zz" } ) ]   # 12 refusal names only the unbound end
reqs = [ { "jsonrpc": "2.0", "id": 0, "method": "initialize", "params": { "protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": { "name": "g", "version": "1" } } } ]
for i, ( verb, d, a ) in enumerate( calls ):
    a = dict( a ); a[ "path" ] = tmp + "/" + d
    reqs.append( { "jsonrpc": "2.0", "id": i + 1, "method": "tools/call", "params": { "name": verb, "arguments": a } } )
p = subprocess.run( [ binp, "--mcp", "--mcp-legend=inline" ], input = "".join( json.dumps( r ) + "\n" for r in reqs ), capture_output = True, text = True, timeout = 300 )
for line in p.stdout.splitlines():
    try:
        o = json.loads( line )
    except ValueError:
        continue
    i = o.get( "id" )
    if not isinstance( i, int ) or i <= 0:
        continue
    content = o.get( "result", {} ).get( "content", [] )
    if "error" in o:
        print( i, "err", json.dumps( o[ "error" ] ).replace( "\n", " " ) )
    # SEP-1303 (lane mcp-metadata): a tool refusal is an isError result, and a not-found a found=0 answer whose second block
    # is the refusal sentence; both are the refusal these arms read as "err"
    elif o.get( "result", {} ).get( "isError" ):
        print( i, "err", "".join( c.get( "text", "" ) for c in content ).replace( "\n", " " ) )
    elif len( content ) > 1 and " not found" in content[ 1 ].get( "text", "" ):
        print( i, "err", content[ 1 ].get( "text", "" ).replace( "\n", " " ) )
    else:
        print( i, "ok", "".join( c.get( "text", "" ) for c in o.get( "result", {} ).get( "content", [] ) ).replace( "\n", " " ) )
PY
}
mcp "$BIN" > "$TMP/M.txt" 2> "$TMP/M.err"
mline(){ awk -v i="$1" '$1 == i { sub( /^[0-9]+ /, "" ); print; exit }' "$TMP/M.txt"; }
mpath(){ mline "$1" | python3 -c 'import re,sys; m=re.search(r"<path [^>]*>", sys.stdin.read()); print(m.group(0) if m else "")'; }
premF=0
if [ "$( mline 1 | cut -d' ' -f1 )" = ok ] && [ "$( attr "$( mpath 1 )" from_defs )" = "3" ]; then premF=1; ok "(f) premise: MCP path_between bare _make resolves (from_defs=3)"
else no "(f) premise: MCP path_between bare _make resolves with 3 definitions: $( mline 1 | head -c 300 ) $( head -c 200 "$TMP/M.err" )"; fi
MP2="$( mpath 2 )"
if [ "$premF" = 1 ] && [ "$( mline 2 | cut -d' ' -f1 )" = ok ] && [ "$( attr "$MP2" from_defs )" = "2" ] && [ "$( attr "$MP2" reachable )" = "1" ] && ! mline 2 | grep -q 'other.ts'; then
    ok "(f) MCP path_between Svc._make -> sink: from_defs=2, reached"
else no "(f) MCP path_between Svc._make binds, never refuses: $( mline 2 | head -c 400 )"; fi
MP3="$( mpath 3 )"
if [ "$premF" = 1 ] && [ "$( mline 3 | cut -d' ' -f1 )" = ok ] && [ "$( attr "$MP3" to_defs )" = "2" ] && [ "$( attr "$MP3" reachable )" = "1" ]; then
    ok "(f) MCP path_between boot -> Svc._make: to_defs=2, reached"
else no "(f) MCP path_between to= Svc._make binds, never refuses: $( mline 3 | head -c 400 )"; fi
if [ "$premF" = 1 ] && [ "$( mline 4 | cut -d' ' -f1 )" = err ] && mline 4 | grep -q 'Nope._make'; then ok "(f) MCP path_between: a wrong owner (Nope._make) still refuses"
else no "(f) MCP path_between: a wrong owner still refuses: $( mline 4 | head -c 300 )"; fi
MP5="$( mpath 5 )"
if [ "$( mline 5 | cut -d' ' -f1 )" = ok ] && [ "$( attr "$MP5" narrowed )" = "Svc._make" ] && [ "$( attr "$MP5" from_defs )" = "1" ] && mline 5 | grep -q 'narrowed=:'; then
    ok "(f) MCP path_between: the one-source narrowing runs first, as on the CLI (narrowed=, from_defs=1, its legend clause)"
else no "(f) MCP path_between: the GV-PATH-BIND narrowing runs first: $( mline 5 | head -c 400 )"; fi
# CLI parity: the MCP root and hop rows equal the CLI --path answer's (the root= value is the same directory on both)
parity=0; pn=0
for pair in "2 own Svc._make,sink" "3 own boot,Svc._make" "5 twin Svc._make,sink"; do
    set -- $pair
    pn=$(( pn + 1 ))
    run "$BIN" "$2" "$3" > "$TMP/P.out" 2>/dev/null
    cr="$( root "$TMP/P.out" )"; crow="$( grep -oE '<s [^>]*/>' "$TMP/P.out" | tr -d '\n' )"
    mr="$( mpath "$1" )"; mrow="$( mline "$1" | grep -oE '<s [^>]*/>' | tr -d '\n' )"
    if [ -n "$cr" ] && [ "$cr" = "$mr" ] && [ -n "$crow" ] && [ "$crow" = "$mrow" ]; then parity=$(( parity + 1 )); else no "(f) MCP path_between id $1 differs from CLI --path=$3: '$mr' vs '$cr'"; fi
done
if [ "$pn" -gt 0 ] && [ "$parity" = "$pn" ]; then ok "(f) MCP path_between root + hop rows equal the CLI's on $parity bound calls"; fi
if [ "$( mline 6 | cut -d' ' -f1 )" = ok ] && mline 6 | grep -qE '<t n="_make"[^>]* defs="2"' && ! mline 6 | grep -q 'other.ts'; then ok "(f) MCP connect [Svc._make, sink]: t defs=2, as on the CLI"
else no "(f) MCP connect Svc._make binds, never refuses: $( mline 6 | head -c 400 )"; fi
if [ "$( mline 7 | cut -d' ' -f1 )" = err ] && mline 7 | grep -q 'Nope._make'; then ok "(f) MCP connect: a wrong owner (Nope._make) still refuses"
else no "(f) MCP connect: a wrong owner still refuses: $( mline 7 | head -c 300 )"; fi
# CodeRabbit #676: the refusal diagnoses with the binder pathText ran, so a two-copy Svc._make that binds is never named as missing
if [ "$premF" = 1 ] && [ "$( mline 12 | cut -d' ' -f1 )" = err ] && mline 12 | grep -qF "to='NoSuchSym_zz'" && ! mline 12 | grep -qF "from='Svc._make'"; then
    ok "(f) MCP path_between Svc._make -> NoSuchSym_zz: the refusal names to= only (the bound two-copy from= is not called missing)"
else no "(f) MCP path_between refusal names only the unbound endpoint: $( mline 12 | head -c 400 )"; fi

# ── (g) single definitions: unchanged ──
premG=0
for c in "uniq --verify=calls(top, leaf)" "own --verify=calls(boot, sink)" "own --verify=calls(Other._make, sink)" "own --verify=calls(Nope._make, sink)" \
         "uniq --connect=top,leaf" "own --connect=boot,sink" "own --connect=Other._make,sink" "own --connect=Nope._make,sink"; do
    set -- $c
    shift; flag="$*"; set -- $c
    cli "$BIN" "$1" "$flag" > "$TMP/G.out" 2> "$TMP/G.err"; rc=$?
    if grep -q 'narrowed=' "$TMP/G.out"; then no "(g) $1 $flag carries narrowed="; fi
    case "$flag" in *Nope*) [ "$rc" = 1 ] || no "(g) $1 $flag: rc=$rc, the wrong owner refuses";; *) [ "$rc" = 0 ] || no "(g) $1 $flag: rc=$rc";; esac
    premG=$(( premG + 1 ))
    if [ -n "$BASE" ]; then
        cli "$BASE" "$1" "$flag" > "$TMP/GB.out" 2> "$TMP/GB.err"; rcb=$?
        if [ "$rc" = "$rcb" ] && cmp -s "$TMP/G.out" "$TMP/GB.out" && cmp -s "$TMP/G.err" "$TMP/GB.err"; then ok "(g) $1 $flag: stdout + stderr + rc byte-identical to the base"
        else no "(g) $1 $flag differs from the base (rc $rc vs $rcb)"; fi
    fi
done
if [ -n "$BASE" ]; then
    mcp "$BASE" > "$TMP/MB.txt" 2>/dev/null
    for i in 8 9 10 11; do
        premG=$(( premG + 1 ))
        a="$( mline "$i" )"; b="$( awk -v i="$i" '$1 == i { sub( /^[0-9]+ /, "" ); print; exit }' "$TMP/MB.txt" )"
        if [ -n "$a" ] && [ "$a" = "$b" ]; then ok "(g) MCP id $i: the response is byte-identical to the base"; else no "(g) MCP id $i differs from the base"; fi
    done
fi
if [ "$premG" -gt 0 ]; then ok "(g) $premG single-definition controls checked${BASE:+ against the base}"
else no "(g) premise: single-definition controls ran ($premG)"; fi

# every answer above parses as XML
if command -v xmllint >/dev/null 2>&1; then
    bad=0; n=0
    for f in A AF A1 W B0 B1 B2 B4 B5 D1 D2 D4 E1 E2 E4; do n=$(( n + 1 )); xmllint --noout "$TMP/$f.out" 2>/dev/null || { bad=1; no "(x) $f.out is not well-formed XML"; }; done
    if [ "$bad" = 0 ] && [ "$n" -gt 0 ]; then ok "(x) $n answers parse as XML"; fi
fi

[ "$fail" = 0 ] && echo "pathambigcheck: PASS" || echo "pathambigcheck: FAIL"
exit "$fail"
