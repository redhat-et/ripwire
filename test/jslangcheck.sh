#!/usr/bin/env bash
# jslangcheck.sh — JavaScript / Bash ingest coverage gate.
#
# ripwire --help now advertises JavaScript (.js/.jsx/.mjs/.cjs) and Bash (.sh/.bash/.zsh).
# This gate has one small file per language, each with two functions where one calls the
# other, and pins assertions to what the binary ACTUALLY does — verified by running it and
# reading the output before writing any assertion (see the findings below).
#
# Fixture (test/jslangfix/):
#   a.js — addOne(), addTwo() (arrow-fn const) calls addOne(); module.exports = {...}
#   b.sh — square(), sum_of_squares() calls square() (via $( square .. ))
#
# FINDINGS from running `ripwire test/jslangfix` and inspecting the raw output:
#   - a.js:  2 symbols (addOne, addTwo), t="fn" both. addOne is a function_declaration;
#            addTwo is a `const addTwo = (x) => {..}` arrow-fn bound to a const (the
#            lexical_declaration→variable_declarator→arrow_function tags.scm rule). The
#            intra-file call edge addTwo -> addOne is present (single <c n="addOne"/>).
#   - b.sh:  2 symbols (square, sum_of_squares), t="fn" both (Bash function_definition →
#            @definition.function). The call edge sum_of_squares -> square is present.
#            Bash built-ins used in the bodies (echo, local) are (command ..) references that
#            resolve to NO def and produce NO phantom symbol nodes — only the two functions
#            appear. (If a future change indexes bash variables/commands as symbols, checks 1
#            below fail loudly and this block is the place to update.)
#   - determinism: two runs are byte-identical (sorted files → stable ids → stable output).
#   - MUTATION: renaming the callee AT THE CALL SITE (addOne→addOneX / square→squareX) makes
#            the edge vanish — the gate tests a real edge, not a tautology.
#
# Usage:
#   test/jslangcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/jslangcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/jslangfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for XML assertions"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "jslangcheck: BIN=$BIN  FIX=$FIX"

MAP_OUT="$TMP/map.xml"
$BIN "$FIX" --no-cache >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
[ "$MAP_EXIT" -eq 0 ] && ok "default map: exits 0 on JS/Bash fixture" || no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"

command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$MAP_OUT" && ok "default map: passes xmllint --noout" || no "default map: xmllint failed"; }

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
echo "=== a.js (JavaScript): 2 symbols, addTwo -> addOne edge ==="
# ═══════════════════════════════════════════════════════════════════════════

python3 - "$TMP/parsed.json" <<'PYEOF' >"$TMP/js_check"
import json, sys
d = json.load(open(sys.argv[1]))
syms = d.get("a.js", [])
names = [s["n"] for s in syms]
has_addone = "addOne" in names
has_addtwo = "addTwo" in names
all_fn = all(s["t"] == "fn" for s in syms) if syms else False
edge = any(s["n"] == "addTwo" and "addOne" in s["calls"] for s in syms)
edge_n = sum(s["calls"].count("addOne") for s in syms if s["n"] == "addTwo")
print("SYMS:%d" % len(syms))
print("HAS_ADDONE:%s HAS_ADDTWO:%s ALL_FN:%s EDGE:%s EDGE_N:%d" % (has_addone, has_addtwo, all_fn, edge, edge_n))
PYEOF
cat "$TMP/js_check"

if grep -q "SYMS:0" "$TMP/js_check"; then
    no "a.js (JavaScript): extracted ZERO symbols — REAL FINDING: JS ingest may be broken"
else
    ok "a.js (JavaScript): extracted $( grep -o 'SYMS:[0-9]*' "$TMP/js_check" | cut -d: -f2 ) symbol(s)"
fi
grep -q "SYMS:2" "$TMP/js_check" && ok "a.js: exactly 2 symbols (addOne, addTwo — no phantom nodes)" || no "a.js: expected 2 symbols, got: $( grep SYMS "$TMP/js_check" )"
grep -q "HAS_ADDONE:True" "$TMP/js_check" && ok "a.js: addOne symbol present" || no "a.js: addOne symbol missing"
grep -q "HAS_ADDTWO:True" "$TMP/js_check" && ok "a.js: addTwo (arrow-fn const) symbol present" || no "a.js: addTwo symbol missing"
grep -q "ALL_FN:True" "$TMP/js_check" && ok "a.js: both symbols tagged t=\"fn\"" || no "a.js: symbols not tagged t=\"fn\" as expected"
grep -q "EDGE:True" "$TMP/js_check" && ok "a.js: intra-file call edge addTwo -> addOne present" || no "a.js: call edge addTwo -> addOne MISSING"
grep -q "EDGE_N:1" "$TMP/js_check" && ok "a.js: exactly ONE addTwo -> addOne edge (dedup)" || no "a.js: expected a single addTwo -> addOne edge: $( grep EDGE_N "$TMP/js_check" )"

# cross-check via --callees / --callers (independent of the raw-XML parse)
JS_CE="$( $BIN "$FIX" --callees=addTwo 2>/dev/null )"
echo "$JS_CE" | grep -q 'count="1"' && echo "$JS_CE" | grep -q 'n="addOne"' \
    && ok "a.js: --callees=addTwo reports count=1, addOne" \
    || no "a.js: --callees=addTwo did not match (count=1, addOne): $JS_CE"
JS_CR="$( $BIN "$FIX" --callers=addOne 2>/dev/null )"
echo "$JS_CR" | grep -q 'n="addTwo"' \
    && ok "a.js: --callers=addOne lists addTwo" \
    || no "a.js: --callers=addOne did not list addTwo: $JS_CR"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== b.sh (Bash): 2 symbols, sum_of_squares -> square edge ==="
# ═══════════════════════════════════════════════════════════════════════════

python3 - "$TMP/parsed.json" <<'PYEOF' >"$TMP/sh_check"
import json, sys
d = json.load(open(sys.argv[1]))
syms = d.get("b.sh", [])
names = [s["n"] for s in syms]
has_square = "square" in names
has_sos = "sum_of_squares" in names
all_fn = all(s["t"] == "fn" for s in syms) if syms else False
edge = any(s["n"] == "sum_of_squares" and "square" in s["calls"] for s in syms)
# no phantom nodes from bash built-ins (echo/local) — the two functions are the only symbols
phantom = [n for n in names if n not in ("square", "sum_of_squares")]
print("SYMS:%d" % len(syms))
print("HAS_SQUARE:%s HAS_SOS:%s ALL_FN:%s EDGE:%s PHANTOM:%s" % (has_square, has_sos, all_fn, edge, ",".join(phantom) or "none"))
PYEOF
cat "$TMP/sh_check"

if grep -q "SYMS:0" "$TMP/sh_check"; then
    no "b.sh (Bash): extracted ZERO symbols — REAL FINDING: Bash ingest may be broken"
else
    ok "b.sh (Bash): extracted $( grep -o 'SYMS:[0-9]*' "$TMP/sh_check" | cut -d: -f2 ) symbol(s)"
fi
grep -q "SYMS:2" "$TMP/sh_check" && ok "b.sh: exactly 2 symbols (square, sum_of_squares — bash built-ins not indexed)" || no "b.sh: expected 2 symbols, got: $( grep SYMS "$TMP/sh_check" )"
grep -q "HAS_SQUARE:True" "$TMP/sh_check" && ok "b.sh: square symbol present" || no "b.sh: square symbol missing"
grep -q "HAS_SOS:True" "$TMP/sh_check" && ok "b.sh: sum_of_squares symbol present" || no "b.sh: sum_of_squares symbol missing"
grep -q "ALL_FN:True" "$TMP/sh_check" && ok "b.sh: both symbols tagged t=\"fn\"" || no "b.sh: symbols not tagged t=\"fn\" as expected"
grep -q "PHANTOM:none" "$TMP/sh_check" && ok "b.sh: no phantom symbol nodes from bash built-ins (echo/local)" || no "b.sh: phantom nodes present: $( grep PHANTOM "$TMP/sh_check" )"
grep -q "EDGE:True" "$TMP/sh_check" && ok "b.sh: intra-file call edge sum_of_squares -> square present" || no "b.sh: call edge sum_of_squares -> square MISSING"

SH_CE="$( $BIN "$FIX" --callees=sum_of_squares 2>/dev/null )"
echo "$SH_CE" | grep -q 'count="1"' && echo "$SH_CE" | grep -q 'n="square"' \
    && ok "b.sh: --callees=sum_of_squares reports count=1, square" \
    || no "b.sh: --callees=sum_of_squares did not match (count=1, square): $SH_CE"

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
# a.js: rename the call `addOne( addOne( x ) )` → `addOneX( addOneX( x ) )` (leave the def intact)
sed 's/return addOne( addOne( x ) )/return addOneX( addOneX( x ) )/' "$FIX/a.js" >"$MUT/a.js"
# b.sh: rename the calls `square "$1"` / `square "$2"` → `squareX ...` (leave the def intact)
sed 's/\$( square /\$( squareX /g' "$FIX/b.sh" >"$MUT/b.sh"

MUT_OUT="$TMP/mut.xml"
$BIN "$MUT" --no-cache >"$MUT_OUT" 2>/dev/null
python3 - "$MUT_OUT" <<'PYEOF' >"$TMP/mut_check"
import sys, re
xml = open(sys.argv[1], encoding='utf-8').read()
# after mutation, addTwo must NOT call addOne and sum_of_squares must NOT call square
js_edge = bool(re.search(r'n="addTwo"[^>]*>.*?<c n="addOne"', xml, re.S))
sh_edge = bool(re.search(r'n="sum_of_squares"[^>]*>.*?<c n="square"', xml, re.S))
print("JS_EDGE_GONE:%s SH_EDGE_GONE:%s" % (not js_edge, not sh_edge))
PYEOF
cat "$TMP/mut_check"
grep -q "JS_EDGE_GONE:True" "$TMP/mut_check" \
    && ok "mutation: renamed JS call site → addTwo -> addOne edge vanished (non-tautological)" \
    || no "mutation: JS edge survived a renamed call site — the edge assertion is a tautology"
grep -q "SH_EDGE_GONE:True" "$TMP/mut_check" \
    && ok "mutation: renamed Bash call site → sum_of_squares -> square edge vanished (non-tautological)" \
    || no "mutation: Bash edge survived a renamed call site — the edge assertion is a tautology"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
