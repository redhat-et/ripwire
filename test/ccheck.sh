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
# FINDINGS from running `ripwire test/cfix` and inspecting the raw output:
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
#   RIPWIRE_BIN=build/ripwire bash test/ccheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/ccheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"   # arm (f5) builds a git repo: GIT_DIR/GIT_WORK_TREE and the agent-home vars unset
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
FIX="$ROOT/test/cfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for XML assertions"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "ccheck: BIN=$BIN  FIX=$FIX"

MAP_OUT="$TMP/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
if [ "$MAP_EXIT" -eq 0 ]; then ok "default map: exits 0 on the C fixture"; else no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"; fi

command -v xmllint >/dev/null 2>&1 && { if xmllint --noout "$MAP_OUT"; then ok "default map: passes xmllint --noout"; else no "default map: xmllint failed"; fi; }

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

if grep -q 'symbols=9' "$MAP_OUT"; then ok "header: symbols=9 (util.h:add_one, util.c:5, main.c:2)"; else no "header: expected symbols=9: $( grep -o 'symbols=[0-9]*' "$MAP_OUT" )"; fi
if grep -q 'edges=3' "$MAP_OUT"; then ok "header: edges=3 (add_two->add_one, run->add_one, compute->add_two)"; else no "header: expected edges=3: $( grep -o 'edges=[0-9]*' "$MAP_OUT" )"; fi
if grep -q 'ambiguous=0' "$MAP_OUT"; then ok "header: ambiguous=0 (util.h's decl-only add_one never splits the cross-lang candidate set)"; else no "header: expected ambiguous=0: $( grep -o 'ambiguous=[0-9]*' "$MAP_OUT" )"; fi
if grep -q 'unresolved=0' "$MAP_OUT"; then ok "header: unresolved=0"; else no "header: expected unresolved=0: $( grep -o 'unresolved=[0-9]*' "$MAP_OUT" )"; fi

python3 - "$TMP/parsed.json" <<'PYEOF' >"$TMP/struct_check"
import json, sys
d = json.load(open(sys.argv[1]))

hh = d.get("util.h", [])
has_h_decl = any(s["n"] == "add_one" and s["t"] == "fn" for s in hh)

uc = d.get("util.c", [])
has_point   = any(s["n"] == "Point"  and s["t"] == "cls"    for s in uc)
has_pointt  = any(s["n"] == "PointT" and s["t"] == "struct" for s in uc)
has_color   = any(s["n"] == "Color"  and s["t"] == "struct" for s in uc)
has_square  = any(s["n"] == "SQUARE" and s["t"] == "macro"  for s in uc)   # macro-edges round: honest kind (was t="fn")
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

if grep -q "H_DECL:True"      "$TMP/struct_check"; then ok "util.h: body-less prototype add_one still emitted, t=\"fn\""; else no "util.h: add_one prototype missing or wrong tag"; fi
if grep -q "POINT:True"       "$TMP/struct_check"; then ok "util.c: struct Point tagged t=\"cls\""; else no "util.c: Point missing or not t=\"cls\""; fi
if grep -q "POINTT:True"      "$TMP/struct_check"; then ok "util.c: typedef PointT tagged t=\"struct\" (type-alias bucket)"; else no "util.c: PointT missing or wrong tag"; fi
if grep -q "COLOR:True"       "$TMP/struct_check"; then ok "util.c: enum Color tagged t=\"struct\" (type bucket)"; else no "util.c: Color missing or wrong tag"; fi
if grep -q "SQUARE:True"      "$TMP/struct_check"; then ok "util.c: #define SQUARE tagged t=\"fn\" (macro bucket)"; else no "util.c: SQUARE macro missing or wrong tag"; fi
if grep -q "ADDONE:True"      "$TMP/struct_check"; then ok "util.c: add_one() definition tagged t=\"fn\""; else no "util.c: add_one missing or wrong tag"; fi
if grep -q "ADDTWO:True"      "$TMP/struct_check"; then ok "util.c: add_two() definition tagged t=\"fn\""; else no "util.c: add_two missing or wrong tag"; fi
if grep -q "ADDTWO_EDGE:True" "$TMP/struct_check"; then ok "util.c: same-file call edge add_two -> add_one present"; else no "util.c: add_two -> add_one edge MISSING"; fi
if grep -q "RUN:True"         "$TMP/struct_check"; then ok "main.c: run() tagged t=\"fn\""; else no "main.c: run missing or wrong tag"; fi
if grep -q "COMPUTE:True"     "$TMP/struct_check"; then ok "main.c: compute() tagged t=\"fn\""; else no "main.c: compute missing or wrong tag"; fi
if grep -q "RUN_EDGE:True"     "$TMP/struct_check"; then ok "main.c: CROSS-FILE edge run -> add_one (resolves to util.c's DEF, not util.h's decl)"; else no "main.c: run -> add_one edge MISSING"; fi
if grep -q "COMPUTE_EDGE:True" "$TMP/struct_check"; then ok "main.c: cross-file edge compute -> add_two"; else no "main.c: compute -> add_two edge MISSING"; fi

# cross-check via --callees / --callers (independent of the raw-XML parse)
CE="$( "$BIN" "$FIX" --callees=run --no-cache 2>/dev/null )"
if echo "$CE" | grep -q 'count="1"'; then ok "--callees=run reports count=1"; else no "--callees=run did not report count=1: $CE"; fi
echo "$CE" | grep -q 'n="add_one"'    && echo "$CE" | grep -q 'util.c'               \
    && ok "--callees=run resolves add_one to util.c (the definition, not util.h's decl)" \
    || no "--callees=run did not resolve to util.c's add_one: $CE"

CR="$( "$BIN" "$FIX" --callers=add_one --no-cache 2>/dev/null )"
if echo "$CR" | grep -q 'count="2"'; then ok "--callers=add_one reports count=2 (run, add_two)"; else no "--callers=add_one did not report count=2: $CR"; fi
if echo "$CR" | grep -q 'n="run"'; then ok "--callers=add_one lists run"; else no "--callers=add_one missing run: $CR"; fi
if echo "$CR" | grep -q 'n="add_two"'; then ok "--callers=add_one lists add_two"; else no "--callers=add_one missing add_two: $CR"; fi

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

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== a body-less type specifier in a signature is not the function's encloser (comparison table tmux-07/tmux-15) ==="
# ═══════════════════════════════════════════════════════════════════════════
# tmux writes `static enum cmd_retval⏎cmd_set_environment_exec(…)`. The tags query captures every named
# enum_specifier as a type definition, and the body-less one in the return type then CLIMBED to the enclosing
# function_definition (the climb exists for function_declarator → function_definition) and took the WHOLE
# function's span. So `--at` chained `struct cmd_retval` around the function, `--grep` labelled hits in="cmd_retval",
# and a call inside a function with an `enum box_lines` PARAMETER was attributed to a caller `struct box_lines`.
# RED on main 953818d6 for (a)-(d); (e) pins that the real enum definition is untouched.
EN="$TMP/enumsig"
mkdir -p "$EN/cpp"
cat >"$EN/a.c" <<'EOF'
enum cmd_retval { CMD_RETURN_NORMAL, CMD_RETURN_ERROR };
enum box_lines { BOX_SINGLE, BOX_DOUBLE };

static int helper(int x)
{
	return x + 1;
}

static enum cmd_retval
cmd_split_exec(int a)
{
	helper(a);
	errmsg("ENUMSIG no current session");
	return CMD_RETURN_NORMAL;
}

int
menu_display(int a,
    enum box_lines lines)
{
	return helper(a) + (int)lines;
}
EOF
cp "$EN/a.c" "$EN/cpp/b.cpp"
EN_AT="$( "$BIN" "$EN" --no-cache --at=a.c:13 2>/dev/null )"
printf '%s' "$EN_AT" | grep -q 'sym="cmd_split_exec" chain="1"' \
    && ok "(a) --at inside a 'static enum X⏎name(' function chains the function alone" \
    || no "(a) --at chains something around cmd_split_exec: $( printf '%s' "$EN_AT" | grep -o '<at .*' | cut -c1-300 )"
EN_GREP="$( "$BIN" "$EN" --no-cache --grep="ENUMSIG no current session" 2>/dev/null )"
printf '%s' "$EN_GREP" | grep -q 'in="cmd_split_exec"' \
    && ok "(b) a --grep hit in that function names in=\"cmd_split_exec\"" \
    || no "(b) --grep in= is not the function: $( printf '%s' "$EN_GREP" | grep -o '<hit l=[^>]*>' | head -1 )"
EN_CALLERS="$( "$BIN" "$EN" --no-cache --callers=helper 2>/dev/null )"
if printf '%s' "$EN_CALLERS" | grep -q '<s t="fn" n="menu_display"' && ! printf '%s' "$EN_CALLERS" | grep -q 't="struct"'; then
    ok "(c) a call in a function with an 'enum box_lines' parameter is attributed to the function, no struct caller"
else
    no "(c) --callers=helper names a struct as a caller: $( printf '%s' "$EN_CALLERS" | grep -o '<s [^>]*>' | tr '\n' ' ' )"
fi
# (c2) the CALLEE direction of the same defect (tmux `cmd_find_target(…, enum cmd_find_type type, …)`: the 23 call
# edges of the function hung off `cmd_find_type`, so --callees=cmd_find_target read count="0"). The function owns its
# callees; the body-less parameter specifier owns none.
EN_CE="$( "$BIN" "$EN" --no-cache --callees=menu_display 2>/dev/null )"
EN_CE_ENUM="$( "$BIN" "$EN" --no-cache --callees=box_lines 2>/dev/null | grep -o '<callees [^>]*>' )"
if printf '%s' "$EN_CE" | grep -q '<s t="fn" n="helper"' && printf '%s' "$EN_CE_ENUM" | grep -q 'count="0"'; then
    ok "(c2) --callees=menu_display lists helper; the 'enum box_lines' specifier owns no callee"
else
    no "(c2) the parameter specifier still owns the function's calls: menu_display=$( printf '%s' "$EN_CE" | grep -o '<callees [^>]*>' ) box_lines=$EN_CE_ENUM"
fi
EN_CPP="$( "$BIN" "$EN/cpp" --no-cache --at=b.cpp:13 2>/dev/null )"
printf '%s' "$EN_CPP" | grep -q 'sym="cmd_split_exec" chain="1"' \
    && ok "(d) the C++ grammar (.cpp, and .h which C++ owns) gets the same span" \
    || no "(d) C++: --at chains something around cmd_split_exec: $( printf '%s' "$EN_CPP" | grep -o '<at .*' | cut -c1-300 )"
"$BIN" "$EN" --no-cache --at=a.c:1 2>/dev/null | grep -q '<s n="cmd_retval" t="struct" l="1" el="1"/>' \
    && ok "(e) the real 'enum cmd_retval { … }' definition is unchanged (t=\"struct\", its own line)" \
    || no "(e) the bodied enum definition moved"

# (f) the body-less specifier mints NO definition at all (review rv-answer-honesty-067 item 1). Keeping it as a small
# def of its own sat in the function's return-type position, wholly before the name — extentsuspect.h's R3 derailed-
# parse signature — so clean functions read extent_suspect="head" and --hotspots stopped ranking them (tmux: 0 -> 206
# flagged rows, extent_suspect_files 80, ranked 241 -> 206). It is a type USE: no def, no extent flag, one cmd_retval.
# The C++ sibling is a body-less `class Widget` in a return type (the bare class pattern); struct/union need a body
# or a declaration parent in the tags queries, so they never reach this path. RED at 6ef65b15.
cat >"$EN/cpp/w.cpp" <<'EOF'
class Widget { public: int x; };
static int wh(int a) { return a; }

class Widget *
make_widget(int a)
{
	wh(a);
	return nullptr;
}
EOF
EN_MAP="$( "$BIN" "$EN" --no-cache --top-k=100000 2>/dev/null )"
printf '%s' "$EN_MAP" | grep -q 'extent_suspect=' \
    && no "(f) a clean 'static enum X⏎fn(' / 'class W *fn(' file carries extent_suspect: $( printf '%s' "$EN_MAP" | grep -o '<s [^>]*extent_suspect[^>]*>' | head -3 | tr '\n' ' ' )" \
    || ok "(f) no extent_suspect on the enum/class return-type and enum-parameter functions"
"$BIN" "$EN" --no-cache --skipped 2>/dev/null | grep -q 'extent_suspect_files=' \
    && no "(f2) --skipped names extent_suspect_files on the clean fixture" \
    || ok "(f2) --skipped carries no extent_suspect_files"
EN_CR="$( printf '%s' "$EN_MAP" | grep -o '<s t="[a-z]*" n="cmd_retval"[^>]*>' )"
if [ -n "$EN_CR" ] && ! printf '%s' "$EN_CR" | grep -q 'overloads='; then
    ok "(f3) cmd_retval is one definition per file (no overloads=) — the return-type uses mint none"
else
    no "(f3) the return-type specifier still mints a definition: $EN_CR"
fi
printf '%s' "$EN_MAP" | grep -o '<s t="[a-z]*" n="Widget"[^>]*>' | grep -q 'overloads=' \
    && no "(f4) C++ 'class Widget *make_widget(' still mints a second Widget definition" \
    || ok "(f4) C++ body-less class in a return type mints no definition"
if command -v git >/dev/null 2>&1; then
    git -C "$EN" init -q . && git -C "$EN" -c user.email=t@t -c user.name=t add -A && git -C "$EN" -c user.email=t@t -c user.name=t commit -qm base
    EN_HOT="$( "$BIN" "$EN" --no-cache --hotspots 2>/dev/null | grep -o '<hotspots [^>]*>' )"
    printf '%s' "$EN_HOT" | grep -q 'unranked_extent_suspect=' \
        && no "(f5) --hotspots withholds files as extent-suspect: $EN_HOT" \
        || ok "(f5) --hotspots ranks every file (no unranked_extent_suspect)"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
