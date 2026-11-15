#!/usr/bin/env bash
# pathambigcheck.sh — PATH-AMBIG-VERDICT: --path never gives a definite verdict from many unlisted candidate pairs, and a
# qualified Owner.method endpoint narrows, never refuses (src/pathpairs.h nearest_of=, src/pathgaps.h pathEndpointFittedDefs).
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
[ "$premB" = 1 ] && ok "(b) premise: bare _make resolves (from_defs=3: two Svc copies + Other)" || no "(b) premise: bare _make resolves with 3 definitions (rc=$rb0): $RB0"
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

# every answer above parses as XML
if command -v xmllint >/dev/null 2>&1; then
    bad=0; n=0
    for f in A AF A1 W B0 B1 B2 B4 B5; do n=$(( n + 1 )); xmllint --noout "$TMP/$f.out" 2>/dev/null || { bad=1; no "(x) $f.out is not well-formed XML"; }; done
    [ "$bad" = 0 ] && [ "$n" -gt 0 ] && ok "(x) $n answers parse as XML"
fi

[ "$fail" = 0 ] && echo "pathambigcheck: PASS" || echo "pathambigcheck: FAIL"
exit "$fail"
