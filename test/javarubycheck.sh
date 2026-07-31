#!/usr/bin/env bash
# javarubycheck.sh — Java / Ruby ingest coverage gate.
#
# ctxpack --help now advertises Java (.java) and Ruby (.rb). This gate has one small file
# per language, each with two methods where one calls the other, and pins assertions to
# what the binary ACTUALLY does — verified by running it and reading the output before
# writing any assertion (see the findings below).
#
# Fixture (test/javarubyfix/):
#   A.java — class A { int addOne(x); int addTwo(x) { return addOne(addOne(x)); } }
#   b.rb   — def square(x); def sum_of_squares(a,b) { square(a) + square(b) }
#
# FINDINGS from running `ctxpack test/javarubyfix` and inspecting the raw output:
#   - A.java: 3 symbols — addOne (t="method"), addTwo (t="method"), A (t="cls"). Both
#             methods are (method_declaration name:(identifier)) → @definition.method; the
#             class is (class_declaration name:(identifier)) → @definition.class (t="cls").
#             The intra-file call edge addTwo -> addOne is present (single <c n="addOne"/>).
#             `int x`/local params are NOT indexed (fields/locals deliberately skipped).
#   - b.rb:   2 symbols (square, sum_of_squares), both t="method" (top-level Ruby `def` →
#             @definition.method). The call edge sum_of_squares -> square is present.
#             `puts`, `require`-style calls resolve to NO def → NO phantom symbol nodes.
#   - determinism: two runs are byte-identical (sorted files → stable ids → stable output).
#   - MUTATION: renaming the callee AT THE CALL SITE (addOne->addOneX / square->squareX)
#             makes the edge vanish — the gate tests a real edge, not a tautology.
#
# Usage:
#   test/javarubycheck.sh
#   CTXPACK_BIN=asan/ctxpack test/javarubycheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/javarubyfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for XML assertions"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "javarubycheck: BIN=$BIN  FIX=$FIX"

MAP_OUT="$TMP/map.xml"
$BIN "$FIX" --no-cache >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
[ "$MAP_EXIT" -eq 0 ] && ok "default map: exits 0 on Java/Ruby fixture" || no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"

command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$MAP_OUT" && ok "default map: passes xmllint --noout" || no "default map: xmllint failed"; }

# no degrade / ABI-mismatch warning must reach stderr on the clean fixture
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
echo "=== A.java (Java): class A + 2 methods, addTwo -> addOne edge ==="
# ═══════════════════════════════════════════════════════════════════════════

python3 - "$TMP/parsed.json" <<'PYEOF' >"$TMP/java_check"
import json, sys
d = json.load(open(sys.argv[1]))
syms = d.get("A.java", [])
names = [s["n"] for s in syms]
has_addone = "addOne" in names
has_addtwo = "addTwo" in names
has_class  = any(s["n"] == "A" and s["t"] == "cls" for s in syms)
methods_fn = all(s["t"] == "method" for s in syms if s["n"] in ("addOne", "addTwo"))
edge = any(s["n"] == "addTwo" and "addOne" in s["calls"] for s in syms)
edge_n = sum(s["calls"].count("addOne") for s in syms if s["n"] == "addTwo")
# no phantom nodes: exactly {addOne, addTwo, A}
phantom = [n for n in names if n not in ("addOne", "addTwo", "A")]
print("SYMS:%d" % len(syms))
print("HAS_ADDONE:%s HAS_ADDTWO:%s HAS_CLASS_A:%s METHODS:%s EDGE:%s EDGE_N:%d PHANTOM:%s" %
      (has_addone, has_addtwo, has_class, methods_fn, edge, edge_n, ",".join(phantom) or "none"))
PYEOF
cat "$TMP/java_check"

if grep -q "SYMS:0" "$TMP/java_check"; then
    no "A.java (Java): extracted ZERO symbols — REAL FINDING: Java ingest may be broken"
else
    ok "A.java (Java): extracted $( grep -o 'SYMS:[0-9]*' "$TMP/java_check" | cut -d: -f2 ) symbol(s)"
fi
grep -q "SYMS:3" "$TMP/java_check" && ok "A.java: exactly 3 symbols (addOne, addTwo, class A — no field/local phantom nodes)" || no "A.java: expected 3 symbols, got: $( grep SYMS "$TMP/java_check" )"
grep -q "HAS_ADDONE:True" "$TMP/java_check" && ok "A.java: addOne method present" || no "A.java: addOne method missing"
grep -q "HAS_ADDTWO:True" "$TMP/java_check" && ok "A.java: addTwo method present" || no "A.java: addTwo method missing"
grep -q "HAS_CLASS_A:True" "$TMP/java_check" && ok "A.java: class A present, tagged t=\"cls\"" || no "A.java: class A missing or not t=\"cls\""
grep -q "METHODS:True" "$TMP/java_check" && ok "A.java: addOne/addTwo tagged t=\"method\"" || no "A.java: methods not tagged t=\"method\" as expected"
grep -q "PHANTOM:none" "$TMP/java_check" && ok "A.java: no phantom nodes (params/locals not indexed)" || no "A.java: phantom nodes present: $( grep PHANTOM "$TMP/java_check" )"
grep -q "EDGE:True" "$TMP/java_check" && ok "A.java: intra-file call edge addTwo -> addOne present" || no "A.java: call edge addTwo -> addOne MISSING"
grep -q "EDGE_N:1" "$TMP/java_check" && ok "A.java: exactly ONE addTwo -> addOne edge (dedup)" || no "A.java: expected a single addTwo -> addOne edge: $( grep EDGE_N "$TMP/java_check" )"

# cross-check via --callees / --callers (independent of the raw-XML parse)
JV_CE="$( $BIN "$FIX" --callees=addTwo 2>/dev/null )"
echo "$JV_CE" | grep -q 'count="1"' && echo "$JV_CE" | grep -q 'n="addOne"' \
    && ok "A.java: --callees=addTwo reports count=1, addOne" \
    || no "A.java: --callees=addTwo did not match (count=1, addOne): $JV_CE"
JV_CR="$( $BIN "$FIX" --callers=addOne 2>/dev/null )"
echo "$JV_CR" | grep -q 'n="addTwo"' \
    && ok "A.java: --callers=addOne lists addTwo" \
    || no "A.java: --callers=addOne did not list addTwo: $JV_CR"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== b.rb (Ruby): 2 methods, sum_of_squares -> square edge ==="
# ═══════════════════════════════════════════════════════════════════════════

python3 - "$TMP/parsed.json" <<'PYEOF' >"$TMP/ruby_check"
import json, sys
d = json.load(open(sys.argv[1]))
syms = d.get("b.rb", [])
names = [s["n"] for s in syms]
has_square = "square" in names
has_sos = "sum_of_squares" in names
all_method = all(s["t"] == "method" for s in syms) if syms else False
edge = any(s["n"] == "sum_of_squares" and "square" in s["calls"] for s in syms)
# no phantom nodes from `puts` (a resolved-to-nothing call) — the two defs are the only symbols
phantom = [n for n in names if n not in ("square", "sum_of_squares")]
print("SYMS:%d" % len(syms))
print("HAS_SQUARE:%s HAS_SOS:%s ALL_METHOD:%s EDGE:%s PHANTOM:%s" % (has_square, has_sos, all_method, edge, ",".join(phantom) or "none"))
PYEOF
cat "$TMP/ruby_check"

if grep -q "SYMS:0" "$TMP/ruby_check"; then
    no "b.rb (Ruby): extracted ZERO symbols — REAL FINDING: Ruby ingest may be broken"
else
    ok "b.rb (Ruby): extracted $( grep -o 'SYMS:[0-9]*' "$TMP/ruby_check" | cut -d: -f2 ) symbol(s)"
fi
grep -q "SYMS:2" "$TMP/ruby_check" && ok "b.rb: exactly 2 symbols (square, sum_of_squares — puts not indexed)" || no "b.rb: expected 2 symbols, got: $( grep SYMS "$TMP/ruby_check" )"
grep -q "HAS_SQUARE:True" "$TMP/ruby_check" && ok "b.rb: square method present" || no "b.rb: square method missing"
grep -q "HAS_SOS:True" "$TMP/ruby_check" && ok "b.rb: sum_of_squares method present" || no "b.rb: sum_of_squares method missing"
grep -q "ALL_METHOD:True" "$TMP/ruby_check" && ok "b.rb: both symbols tagged t=\"method\"" || no "b.rb: symbols not tagged t=\"method\" as expected"
grep -q "PHANTOM:none" "$TMP/ruby_check" && ok "b.rb: no phantom symbol nodes (puts / unresolved calls dropped)" || no "b.rb: phantom nodes present: $( grep PHANTOM "$TMP/ruby_check" )"
grep -q "EDGE:True" "$TMP/ruby_check" && ok "b.rb: intra-file call edge sum_of_squares -> square present" || no "b.rb: call edge sum_of_squares -> square MISSING"

RB_CE="$( $BIN "$FIX" --callees=sum_of_squares 2>/dev/null )"
echo "$RB_CE" | grep -q 'count="1"' && echo "$RB_CE" | grep -q 'n="square"' \
    && ok "b.rb: --callees=sum_of_squares reports count=1, square" \
    || no "b.rb: --callees=sum_of_squares did not match (count=1, square): $RB_CE"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== determinism: default map twice, byte-identical (det-gate) ==="
# ═══════════════════════════════════════════════════════════════════════════

$BIN "$FIX" --no-cache >"$TMP/det_a.xml" 2>/dev/null
$BIN "$FIX" --no-cache >"$TMP/det_b.xml" 2>/dev/null
diff -q "$TMP/det_a.xml" "$TMP/det_b.xml" >/dev/null \
    && ok "determinism: default map byte-identical across two runs" \
    || no "determinism: default map differs across runs"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== mutation: rename the callee AT THE CALL SITE → edge must vanish ==="
# ═══════════════════════════════════════════════════════════════════════════
# Proves the edge assertions above are non-tautological: if we break the call, the gate notices.
MUT="$TMP/mut"
cp -R "$FIX" "$MUT"
# A.java: rename the call `addOne( addOne( x ) )` → `addOneX( addOneX( x ) )` (leave the def intact)
sed 's/return addOne( addOne( x ) )/return addOneX( addOneX( x ) )/' "$FIX/A.java" >"$MUT/A.java"
# b.rb: rename the calls `square( a )` / `square( b )` → `squareX ...` (leave the def intact)
sed 's/square( a ) + square( b )/squareX( a ) + squareX( b )/' "$FIX/b.rb" >"$MUT/b.rb"

MUT_OUT="$TMP/mut.xml"
$BIN "$MUT" --no-cache >"$MUT_OUT" 2>/dev/null
python3 - "$MUT_OUT" <<'PYEOF' >"$TMP/mut_check"
import sys, re
xml = open(sys.argv[1], encoding='utf-8').read()
# after mutation, addTwo must NOT call addOne and sum_of_squares must NOT call square
jv_edge = bool(re.search(r'n="addTwo"[^>]*>.*?<c n="addOne"', xml, re.S))
rb_edge = bool(re.search(r'n="sum_of_squares"[^>]*>.*?<c n="square"', xml, re.S))
print("JAVA_EDGE_GONE:%s RUBY_EDGE_GONE:%s" % (not jv_edge, not rb_edge))
PYEOF
cat "$TMP/mut_check"
grep -q "JAVA_EDGE_GONE:True" "$TMP/mut_check" \
    && ok "mutation: renamed Java call site → addTwo -> addOne edge vanished (non-tautological)" \
    || no "mutation: Java edge survived a renamed call site — the edge assertion is a tautology"
grep -q "RUBY_EDGE_GONE:True" "$TMP/mut_check" \
    && ok "mutation: renamed Ruby call site → sum_of_squares -> square edge vanished (non-tautological)" \
    || no "mutation: Ruby edge survived a renamed call site — the edge assertion is a tautology"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
