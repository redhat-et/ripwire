#!/usr/bin/env bash
# ccheck.sh — L3 plain-C ingest coverage gate (grammar + tags.scm + Cpp<->C cross-file resolution).
#
# Modeled on csharpcheck.sh: a small fixture, assertions pinned to what the binary ACTUALLY does
# (verified by running it and reading the output before writing any assertion below), plus a
# mutation check so the edge assertions are non-tautological.
#
# Fixture (test/cfix/): a header prototype + a .c definition + a cross-file caller, exercising the
# deliberate `.h` stays C++-owned / `.c` is its own language split (L3):
#   util.h  declares  int add_one( int x );                          (prototype only, no body)
#   util.c  #include "util.h"
#           struct Point { int x; int y; }                            (def -> t="cls")
#           typedef struct Point PointT;                               (def -> t="struct", type bucket)
#           enum Color { RED, GREEN, BLUE };                           (def -> t="struct", type bucket)
#           #define SQUARE( n ) ( (n) * (n) )                          (def -> t="fn", macro bucket)
#           int add_one( int x ) { return x + 1; }                     (def -> t="fn")
#           int add_two( int x ) { return add_one( x ) + 1; }          (def -> t="fn"; calls add_one, same file)
#   main.c  #include "util.h"
#           int run( void )     { return add_one( 41 ); }              (calls add_one, CROSS-FILE, CROSS-LANG)
#           int compute( void ) { return add_two( 1 ); }               (calls add_two, cross-file)
#
# FINDINGS from running `ctxpack test/cfix` and inspecting the raw output:
#   - files=3 symbols=9 edges=3 ambiguous=0 unresolved=0, clean stderr (no ABI/degrade).
#   - util.h: add_one (t="fn") — the body-less PROTOTYPE, Lang::Cpp (`.h` stays C++-owned, L3 decided).
#   - util.c: add_one/add_two/SQUARE (t="fn"), Point (t="cls"), PointT/Color (t="struct") — Lang::C.
#   - main.c's run()/compute() are Lang::Cpp?? NO — main.c is `.c` too, so Lang::C. The point of this
#     fixture: run()'s call to add_one must resolve to util.c's DEFINITION (the one with a body), not
#     stall on util.h's decl-only stub AND not go ambiguous between the two — this is graph.h's
#     langCompatible(Cpp,C) bridge (mirrors the existing Cpp<->ObjC bridge) doing its job: without it
#     a `.c` call could never even SEE a `.h`-declared/`.c`-defined symbol as a candidate.
#   - `--callees=run` / `--callees=compute` / `--callers=add_one` corroborate the same edges
#     independent of the raw-XML parse.
#   - `#include "util.h"` is captured as a physical dependency (`--deps` -> `<inc t="util.h"/>` on both
#     main.c and util.c) AND as an import-role use-site (`--uses=util` -> role="import" at both files;
#     `importName` strips the `.h` extension, so the query is the STEM "util", not "util.h").
#   - determinism: three runs are byte-identical (det-gate x3).
#
# Usage:
#   bash test/ccheck.sh
#   CTXPACK_BIN=build/ctxpack bash test/ccheck.sh
#   CTXPACK_BIN=asan/ctxpack  bash test/ccheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
FIX="$ROOT/test/cfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for XML assertions"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "ccheck: BIN=$BIN  FIX=$FIX"

MAP_OUT="$TMP/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
[ "$MAP_EXIT" -eq 0 ] && ok "default map: exits 0 on the C fixture" || no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"

command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$MAP_OUT" && ok "default map: passes xmllint --noout" || no "default map: xmllint failed"; }

# no degrade / ABI-mismatch warning must reach stderr on the clean fixture (proves grammarAbiOk passed)
[ -s "$TMP/map.err" ] && no "default map: unexpected stderr (ABI/degrade?): $( cat "$TMP/map.err" )" || ok "default map: clean stderr (no ABI mismatch / degrade)"

# ─── parse the per-file symbol + edge structure once, reuse for all checks ────
python3 - "$MAP_OUT" <<'PYEOF' >"$TMP/parsed.json"
import sys, re, json
xml = open(sys.argv[1], encoding='utf-8').read()
files = re.findall(r'<f p="([^"]+)"[^>]*>(.*?)</f>', xml, re.S)
out = {}
for path, body in files:
    name = path.split('/')[-1]
    syms = []
    for sm in re.finditer(r'<s t="(\w+)" n="([^"]*)"[^>]*>(.*?)</s>|<s t="(\w+)" n="([^"]*)"[^>]*/>', body, re.S):
        if sm.group(1) is not None:
            t, n, inner = sm.group(1), sm.group(2), sm.group(3)
        else:
            t, n, inner = sm.group(4), sm.group(5), ""
        calls = re.findall(r'<c n="([^"]*)"', inner)
        syms.append({"t": t, "n": n, "calls": calls})
    out[name] = syms
print(json.dumps(out))
PYEOF

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== structure: 9 symbols across 3 files, tags + edges match the fixture ==="
# ═══════════════════════════════════════════════════════════════════════════

grep -q 'symbols=9' "$MAP_OUT" && ok "header: symbols=9 (util.h:add_one, util.c:5, main.c:2)" || no "header: expected symbols=9: $( grep -o 'symbols=[0-9]*' "$MAP_OUT" )"
grep -q 'edges=3' "$MAP_OUT" && ok "header: edges=3 (add_two->add_one, run->add_one, compute->add_two)" || no "header: expected edges=3: $( grep -o 'edges=[0-9]*' "$MAP_OUT" )"
grep -q 'ambiguous=0' "$MAP_OUT" && ok "header: ambiguous=0 (util.h's decl-only add_one never splits the cross-lang candidate set)" || no "header: expected ambiguous=0: $( grep -o 'ambiguous=[0-9]*' "$MAP_OUT" )"
grep -q 'unresolved=0' "$MAP_OUT" && ok "header: unresolved=0" || no "header: expected unresolved=0: $( grep -o 'unresolved=[0-9]*' "$MAP_OUT" )"

python3 - "$TMP/parsed.json" <<'PYEOF' >"$TMP/struct_check"
import json, sys
d = json.load(open(sys.argv[1]))

hh = d.get("util.h", [])
has_h_decl = any(s["n"] == "add_one" and s["t"] == "fn" for s in hh)

uc = d.get("util.c", [])
has_point   = any(s["n"] == "Point"  and s["t"] == "cls"    for s in uc)
has_pointt  = any(s["n"] == "PointT" and s["t"] == "struct" for s in uc)
has_color   = any(s["n"] == "Color"  and s["t"] == "struct" for s in uc)
has_square  = any(s["n"] == "SQUARE" and s["t"] == "fn"     for s in uc)
has_addone  = any(s["n"] == "add_one" and s["t"] == "fn"    for s in uc)
has_addtwo  = any(s["n"] == "add_two" and s["t"] == "fn"    for s in uc)
addtwo_edge = any(s["n"] == "add_two" and "add_one" in s["calls"] for s in uc)

mc = d.get("main.c", [])
has_run     = any(s["n"] == "run"     and s["t"] == "fn" for s in mc)
has_compute = any(s["n"] == "compute" and s["t"] == "fn" for s in mc)
run_edge     = any(s["n"] == "run"     and "add_one" in s["calls"] for s in mc)
compute_edge = any(s["n"] == "compute" and "add_two" in s["calls"] for s in mc)

print("H_DECL:%s POINT:%s POINTT:%s COLOR:%s SQUARE:%s ADDONE:%s ADDTWO:%s ADDTWO_EDGE:%s RUN:%s COMPUTE:%s RUN_EDGE:%s COMPUTE_EDGE:%s" %
      (has_h_decl, has_point, has_pointt, has_color, has_square, has_addone, has_addtwo, addtwo_edge, has_run, has_compute, run_edge, compute_edge))
PYEOF
cat "$TMP/struct_check"

grep -q "H_DECL:True"      "$TMP/struct_check" && ok "util.h: body-less prototype add_one still emitted, t=\"fn\""      || no "util.h: add_one prototype missing or wrong tag"
grep -q "POINT:True"       "$TMP/struct_check" && ok "util.c: struct Point tagged t=\"cls\""                            || no "util.c: Point missing or not t=\"cls\""
grep -q "POINTT:True"      "$TMP/struct_check" && ok "util.c: typedef PointT tagged t=\"struct\" (type-alias bucket)"   || no "util.c: PointT missing or wrong tag"
grep -q "COLOR:True"       "$TMP/struct_check" && ok "util.c: enum Color tagged t=\"struct\" (type bucket)"             || no "util.c: Color missing or wrong tag"
grep -q "SQUARE:True"      "$TMP/struct_check" && ok "util.c: #define SQUARE tagged t=\"fn\" (macro bucket)"            || no "util.c: SQUARE macro missing or wrong tag"
grep -q "ADDONE:True"      "$TMP/struct_check" && ok "util.c: add_one() definition tagged t=\"fn\""                     || no "util.c: add_one missing or wrong tag"
grep -q "ADDTWO:True"      "$TMP/struct_check" && ok "util.c: add_two() definition tagged t=\"fn\""                     || no "util.c: add_two missing or wrong tag"
grep -q "ADDTWO_EDGE:True" "$TMP/struct_check" && ok "util.c: same-file call edge add_two -> add_one present"           || no "util.c: add_two -> add_one edge MISSING"
grep -q "RUN:True"         "$TMP/struct_check" && ok "main.c: run() tagged t=\"fn\""                                    || no "main.c: run missing or wrong tag"
grep -q "COMPUTE:True"     "$TMP/struct_check" && ok "main.c: compute() tagged t=\"fn\""                                || no "main.c: compute missing or wrong tag"
grep -q "RUN_EDGE:True"     "$TMP/struct_check" && ok "main.c: CROSS-FILE edge run -> add_one (resolves to util.c's DEF, not util.h's decl)" || no "main.c: run -> add_one edge MISSING"
grep -q "COMPUTE_EDGE:True" "$TMP/struct_check" && ok "main.c: cross-file edge compute -> add_two"                      || no "main.c: compute -> add_two edge MISSING"

# cross-check via --callees / --callers (independent of the raw-XML parse)
CE="$( "$BIN" "$FIX" --callees=run --no-cache 2>/dev/null )"
echo "$CE" | grep -q 'count="1"'      && ok "--callees=run reports count=1"          || no "--callees=run did not report count=1: $CE"
echo "$CE" | grep -q 'n="add_one"'    && echo "$CE" | grep -q 'util.c'               \
    && ok "--callees=run resolves add_one to util.c (the definition, not util.h's decl)" \
    || no "--callees=run did not resolve to util.c's add_one: $CE"

CR="$( "$BIN" "$FIX" --callers=add_one --no-cache 2>/dev/null )"
echo "$CR" | grep -q 'count="2"'  && ok "--callers=add_one reports count=2 (run, add_two)" || no "--callers=add_one did not report count=2: $CR"
echo "$CR" | grep -q 'n="run"'     && ok "--callers=add_one lists run"     || no "--callers=add_one missing run: $CR"
echo "$CR" | grep -q 'n="add_two"' && ok "--callers=add_one lists add_two" || no "--callers=add_one missing add_two: $CR"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== #include \"util.h\" -> physical dep + import use-site (captureIncludes, C-family) ==="
# ═══════════════════════════════════════════════════════════════════════════

DEPS="$( "$BIN" "$FIX" --deps --no-cache 2>/dev/null )"
echo "$DEPS" | grep -q '<inc t="util.h"/>' \
    && ok "--deps: <inc t=\"util.h\"/> present on the .c includers" \
    || no "--deps: util.h include missing: $DEPS"

USES="$( "$BIN" "$FIX" --uses=util --no-cache 2>/dev/null )"
echo "$USES" | grep -q 'role="import"' && echo "$USES" | grep -q 'count="2"' \
    && ok "--uses=util: role=\"import\" use-sites at both .c includers (count=2; importName strips .h)" \
    || no "--uses=util: import use-sites missing/wrong: $USES"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== determinism: default map thrice, byte-identical (det-gate x3) ==="
# ═══════════════════════════════════════════════════════════════════════════

"$BIN" "$FIX" --no-cache >"$TMP/det_a.xml" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/det_b.xml" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/det_c.xml" 2>/dev/null
diff -q "$TMP/det_a.xml" "$TMP/det_b.xml" >/dev/null && diff -q "$TMP/det_b.xml" "$TMP/det_c.xml" >/dev/null \
    && ok "determinism: default map byte-identical across three runs" \
    || no "determinism: default map differs across runs"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== mutation: rename the callee AT THE CALL SITE -> edge must vanish ==="
# ═══════════════════════════════════════════════════════════════════════════
# Proves the edge assertions above are non-tautological: if we break the call, the gate notices.
MUT="$TMP/mut"
cp -R "$FIX" "$MUT"
# util.c: rename the call `add_one( x )` -> `add_one_x( x )` inside add_two (leave the def intact)
sed 's/return add_one( x ) + 1;/return add_one_x( x ) + 1;/' "$FIX/util.c" >"$MUT/util.c"
# main.c: rename the CROSS-FILE call `add_one( 41 )` -> `add_one_x( 41 )` inside run (leave the def intact)
sed 's/return add_one( 41 );/return add_one_x( 41 );/' "$FIX/main.c" >"$MUT/main.c"

MUT_OUT="$TMP/mut.xml"
"$BIN" "$MUT" --no-cache >"$MUT_OUT" 2>/dev/null
python3 - "$MUT_OUT" <<'PYEOF' >"$TMP/mut_check"
import sys, re
xml = open(sys.argv[1], encoding='utf-8').read()
addtwo_edge = bool(re.search(r'n="add_two"[^>]*>.*?<c n="add_one"', xml, re.S))
run_edge = bool(re.search(r'n="run"[^>]*>.*?<c n="add_one"', xml, re.S))
print("ADDTWO_EDGE_GONE:%s RUN_EDGE_GONE:%s" % (not addtwo_edge, not run_edge))
PYEOF
cat "$TMP/mut_check"
grep -q "ADDTWO_EDGE_GONE:True" "$TMP/mut_check" \
    && ok "mutation: renamed util.c call site -> add_two -> add_one edge vanished (non-tautological)" \
    || no "mutation: add_two -> add_one edge survived a renamed call site — the edge assertion is a tautology"
grep -q "RUN_EDGE_GONE:True" "$TMP/mut_check" \
    && ok "mutation: renamed main.c CROSS-FILE call site -> run -> add_one edge vanished (non-tautological)" \
    || no "mutation: run -> add_one edge survived a renamed call site — the edge assertion is a tautology"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
