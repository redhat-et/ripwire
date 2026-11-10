#!/usr/bin/env bash
# parentcachecheck.sh — parentOf (src/infra/tsparent.h) answers exactly what ts_node_parent answers.
#
# THE CHANGE. ts_node_parent descends from the tree root on every call, so the ingest climbs (a call's argument list and
# receiver, a C++/Rust qualifier chain, a scope climb from a side-walk visitor) paid one descent per step. parentOf answers
# from one cached root-descent path per file and resumes the descent at the deepest cached ancestor that holds the node.
# It is a pure cost change: every answer must be byte-identical, and RIPWIRE_NO_PARENT_CACHE=1 (any value) is the A/B
# handle that runs the same binary on plain ts_node_parent.
#
# ARMS (fixture test/parentcachefix + deep.py, written into a temp copy at run time: the shapes a wrong parent changes)
#   (A) facts a wrong parent would move, on the default run: C++ nested namespace / class members keep their scopes and
#       the qualified + nested calls keep their caller and sites; a Rust method in an impl inside a mod, and a call from a
#       nested mod; Go calls in a `for` header and a `select` communication case; a Python call nested 600 deep (deeper
#       than the cache's 512-entry chain, so its tail is descended uncached); C calls on both sides of a statement whose
#       `;` is MISSING (a zero-width node, which takes ts_node_parent itself); TS member calls in a method and a closure.
#   (B) the fixture's map, --deps and --callers answers are byte-identical with the cache off (RIPWIRE_NO_PARENT_CACHE=1).
#   (C) the same differential over other parent-sensitive fixtures (Go scopes, C++ qualified calls and template calls).
#   (D) cold and warm (cached) runs answer the same, cache on.
# The proof that the rule holds on real trees is the checked build (-DTSPARENT_CHECK_AGAINST_TS, the header note): it
# checks every answer against ts_node_parent and is run per grammar on large repos, not here.
#
# Usage: test/parentcachecheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/parentcachefix"
# deep.py is GENERATED, never committed: its 600-deep call nest trips the value walk's depth cap (ingest_valuerefs.h
# kVrMaxDepth), whose plain-build DISCLOSE line would then ride every whole-repo run's stderr (readabilitycheck (H),
# xmlwellformed --owners 2>&1 caught it on #604).
if [ -d "$ROOT/test/parentcachefix" ] && cp -R "$ROOT/test/parentcachefix" "$FIX"; then
    python3 -c 'import sys
open( sys.argv[ 1 ], "w" ).write( "def leaf(x):\n    return x\n\ndef deep():\n    return " + "leaf(" * 600 + "1" + ")" * 600
    + "\n\n\nclass Outer:\n    class Inner:\n        def m(self, a, b=2):\n            return leaf(a)\n\n    def call(self):\n        self.Inner().m(1, b=3)\n" )' "$FIX/deep.py" \
        || { echo "could not write the generated deep.py"; exit 2; }
fi
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "parentcachecheck: BIN=$BIN  FIX=$FIX"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

# run DIR OUT ARGS... → the answer in OUT, rc in $rc (cache on); runoff: the same with RIPWIRE_NO_PARENT_CACHE=1
run(){    local d="$1" o="$2"; shift 2; "$BIN" "$d" --no-cache "$@" >"$o" 2>"$o.err"; rc=$?; }
runoff(){ local d="$1" o="$2"; shift 2; RIPWIRE_NO_PARENT_CACHE=1 "$BIN" "$d" --no-cache "$@" >"$o" 2>"$o.err"; rc=$?; }

echo "=== (A) facts a wrong parent moves ==="
run "$FIX" "$TMP/map.xml"
map_rc=$rc
rows="$( grep -o '<s t="' "$TMP/map.xml" | wc -l | tr -d ' ' )"
if [ "$map_rc" -eq 0 ] && [ "${rows:-0}" -ge 30 ]; then ok "(A0) map ran: rc=0, $rows rows"; else no "(A0) map rc=$map_rc rows=${rows:-0}: $( head -c 300 "$TMP/map.xml.err" )"; fi
# a map row of kind T and name N whose sc= is exactly SC
for spec in "fn helper inner" "method close Lid" "cls Lid Lid" "method make S" "method grow S" "method reach deeper" "cls S shapes" \
            "fn m Inner" "fn call Outer"; do
    set -- $spec
    if grep -qE "<s t=\"$1\" n=\"$2\" sc=\"$3\"[ >]" "$TMP/map.xml"; then ok "(A) t=$1 $2 sc=\"$3\""; else no "(A) no t=$1 $2 row with sc=\"$3\""; fi
done
# callers_has SYM COUNT ROW... → --callers=SYM answers count="COUNT" and each ROW (a literal substring of one <s> row)
callers_has(){
    local sym="$1" count="$2"; shift 2
    run "$FIX" "$TMP/c.xml" --callers="$sym"
    local root; root="$( grep -o '<callers [^>]*>' "$TMP/c.xml" | head -1 )"
    case "$root" in *" count=\"$count\""*) ok "(A) --callers=$sym count=\"$count\"" ;; *) no "(A) --callers=$sym wanted count=\"$count\" (rc=$rc): $root" ;; esac
    local want
    for want in "$@"; do
        if grep -qF "$want" "$TMP/c.xml"; then ok "(A) --callers=$sym has: $want"; else no "(A) --callers=$sym lacks: $want"; fi
    done
}
callers_has helper 1 'n="caller" p="shapes.cpp:21" sites_at="shapes.cpp:25 shapes.cpp:26"'
callers_has close  1 'n="caller" p="shapes.cpp:21"'
callers_has make   2 'n="deeper::reach" p="shapes.rs:8"' 'n="run" p="shapes.rs:11"'
callers_has use    1 'n="loop" p="shapes.go:8" of_def="2" sites_at="shapes.go:10 shapes.go:14"'
callers_has next   1 'n="loop" p="shapes.go:8"'
callers_has feed   1 'n="loop" p="shapes.go:8" sites_at="shapes.go:13"'
callers_has leaf   2 'n="Inner.m" p="deep.py:10"' 'n="deep" p="deep.py:4" sites_at="deep.py:5"'
callers_has h      1 'n="g" p="missing.c:3" sites_at="missing.c:5 missing.c:6"'
callers_has k      1 'n="g" p="missing.c:3" sites_at="missing.c:6"'
callers_has render 2 'n="Panel.refresh" p="shapes.ts:3" sites_at="shapes.ts:5"' 'n="mount" p="shapes.ts:9" sites_at="shapes.ts:11"'

# same DIR LABEL ARGS... → the answer is byte-identical with the cache on and off, and not empty
same(){
    local d="$1" label="$2"; shift 2
    run "$d" "$TMP/on.xml" "$@";  local r1=$rc
    runoff "$d" "$TMP/off.xml" "$@"; local r2=$rc
    if [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && [ -s "$TMP/on.xml" ] && cmp -s "$TMP/on.xml" "$TMP/off.xml"; then ok "$label $* : identical cache on/off ($( wc -c <"$TMP/on.xml" | tr -d ' ' ) B)"
    else no "$label $* : rc on=$r1 off=$r2, answers differ or are empty"; fi
}

echo "=== (B) the fixture answers the same with the cache off ==="
same "$FIX" "(B)"
same "$FIX" "(B)" --deps
for sym in helper close make grow reach use next feed leaf m h k render refresh; do
    same "$FIX" "(B)" --callers="$sym"
done

echo "=== (C) the same differential on other parent-sensitive fixtures ==="
for d in goscopefix cppqualfix cppqualtmplfix cppqualdeffix; do
    if [ -d "$ROOT/test/$d" ]; then
        same "$ROOT/test/$d" "(C) $d"
        same "$ROOT/test/$d" "(C) $d" --deps
    else
        no "(C) fixture test/$d is missing"
    fi
done

echo "=== (D) cold and warm runs agree, cache on ==="
"$BIN" "$FIX" --cache="$TMP/cache" >"$TMP/cold.xml" 2>/dev/null; c1=$?
"$BIN" "$FIX" --cache="$TMP/cache" >"$TMP/warm.xml" 2>/dev/null; c2=$?
if [ "$c1" -eq 0 ] && [ "$c2" -eq 0 ] && [ -s "$TMP/warm.xml" ] && cmp -s "$TMP/cold.xml" "$TMP/warm.xml" && cmp -s "$TMP/cold.xml" "$TMP/map.xml"; then
    ok "(D) cold == warm == --no-cache map"
else
    no "(D) cold rc=$c1 warm rc=$c2; the maps differ or are empty"
fi

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES ABOVE"; fi
exit "$fail"
