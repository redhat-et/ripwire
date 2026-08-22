#!/usr/bin/env bash
# langcheck.sh — TypeScript / Rust / ObjC ingest coverage gate.
#
# ripwire --help advertises TypeScript, Rust, and ObjC/ObjC++ as supported languages, but
# (before this gate) no fixture anywhere in test/ actually exercised them. This gate has a
# fixture with one small file per language, each with two functions/methods where one calls
# the other, and pins assertions to what the binary ACTUALLY does — verified by running it
# and reading the output before writing any assertion (see the findings below).
#
# Fixture (test/langfix/):
#   a.ts — addOne(), addTwo() calls addOne()
#   b.rs — square(), sum_of_squares() calls square()
#   c.m  — @interface/@implementation Calculator with doubleValue:, quadrupleValue:, and a
#          DECLARE-ONLY tripleValue: (no @implementation). quadrupleValue: calls
#          [self doubleValue:...] twice (nested self-call).
#   d.h  — standalone ObjC header with @interface HeaderOnly; there is no .m/.mm companion,
#          so this pins the .h content-sniff reroute and query prewarm path.
#
# FINDINGS from running `ripwire test/langfix` and inspecting the raw output:
#   - a.ts:  2 symbols extracted (addOne, addTwo), t="fn" both; call edge addTwo -> addOne present.
#   - b.rs:  2 symbols extracted (square, sum_of_squares), t="fn" both; call edge
#            sum_of_squares -> square present.
#   - c.m:   ObjC contributes exactly FOUR <s> nodes — doubleValue, quadrupleValue, tripleValue
#            (t="method"), and Calculator (t="cls"). Each appears ONCE. This is the FIXED
#            behavior: the same-file decl/def collapse (ingest.cpp "3a-bis") merges each method's
#            @interface DECLARATION into its @implementation DEFINITION, so a method no longer
#            doubles. BEFORE the fix ObjC doubled every symbol (doubleValue/quadrupleValue/
#            Calculator each x2 = six nodes, plus a doubled call edge) — this gate PINNED that as
#            a KNOWN-GAP; it is now the correct single-node assertion.
#   - c.m escape hatch: tripleValue: is DECLARED in @interface with NO @implementation. It has
#            no definition anywhere in the file, so the collapse's "no def anywhere keeps the
#            decl" escape hatch keeps it — exactly one tripleValue node survives (mirroring a C++
#            extern/pure-virtual decl with no def). A regression that dropped it would be a real
#            over-collapse bug.
#   - c.m self-call edge: quadrupleValue's node carries the self-call edge to doubleValue as
#            EXACTLY ONE <c n="doubleValue"/> child. The body calls [self doubleValue:...] twice
#            but both resolve to the single (collapsed) doubleValue def and dedup to one edge
#            (pre-fix there were TWO, one per doubleValue duplicate). Confirmed independently via
#            `--callees=quadrupleValue` (count=1, doubleValue) and `--callers=doubleValue`
#            (count=1, quadrupleValue).
#   - No language in this fixture extracts NOTHING — TS, Rust, and ObjC all produce symbols
#     and call edges. (If a future regression makes one of them extract zero symbols, check
#     2 below fails loudly and this comment block is the place to update.)
#   - d.h: standalone ObjC headers must parse as ObjC, not C++; HeaderOnly and headerValue
#            are present. This catches an optimization that skips ObjC query prewarm for .h files.
#
# Usage:
#   test/langcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/langcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/langfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for XML/JSON assertions"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "langcheck: BIN=$BIN  FIX=$FIX"

MAP_OUT="$TMP/map.xml"
$BIN "$FIX" >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
[ "$MAP_EXIT" -eq 0 ] && ok "default map: exits 0 on TS/Rust/ObjC fixture" || no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"

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
echo "=== a.ts (TypeScript): 2 symbols, addTwo -> addOne edge ==="
# ═══════════════════════════════════════════════════════════════════════════

python3 - "$TMP/parsed.json" <<'PYEOF' >"$TMP/ts_check"
import json, sys
d = json.load(open(sys.argv[1]))
syms = d.get("a.ts", [])
names = [s["n"] for s in syms]
has_addone = "addOne" in names
has_addtwo = "addTwo" in names
all_fn = all(s["t"] == "fn" for s in syms) if syms else False
edge = any(s["n"] == "addTwo" and "addOne" in s["calls"] for s in syms)
print("SYMS:%d" % len(syms))
print("HAS_ADDONE:%s HAS_ADDTWO:%s ALL_FN:%s EDGE:%s" % (has_addone, has_addtwo, all_fn, edge))
PYEOF
cat "$TMP/ts_check"

if grep -q "SYMS:0" "$TMP/ts_check"; then
    no "a.ts (TypeScript): extracted ZERO symbols — REAL FINDING: TS ingest may be broken"
else
    ok "a.ts (TypeScript): extracted $( grep -o 'SYMS:[0-9]*' "$TMP/ts_check" | cut -d: -f2 ) symbol(s)"
fi
grep -q "HAS_ADDONE:True" "$TMP/ts_check" && ok "a.ts: addOne symbol present" || no "a.ts: addOne symbol missing"
grep -q "HAS_ADDTWO:True" "$TMP/ts_check" && ok "a.ts: addTwo symbol present" || no "a.ts: addTwo symbol missing"
grep -q "ALL_FN:True" "$TMP/ts_check" && ok "a.ts: both symbols tagged t=\"fn\"" || no "a.ts: symbols not tagged t=\"fn\" as expected"
grep -q "EDGE:True" "$TMP/ts_check" && ok "a.ts: intra-file call edge addTwo -> addOne present" || no "a.ts: call edge addTwo -> addOne MISSING"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== b.rs (Rust): 2 symbols, sum_of_squares -> square edge ==="
# ═══════════════════════════════════════════════════════════════════════════

python3 - "$TMP/parsed.json" <<'PYEOF' >"$TMP/rs_check"
import json, sys
d = json.load(open(sys.argv[1]))
syms = d.get("b.rs", [])
names = [s["n"] for s in syms]
has_square = "square" in names
has_sos = "sum_of_squares" in names
all_fn = all(s["t"] == "fn" for s in syms) if syms else False
edge = any(s["n"] == "sum_of_squares" and "square" in s["calls"] for s in syms)
print("SYMS:%d" % len(syms))
print("HAS_SQUARE:%s HAS_SOS:%s ALL_FN:%s EDGE:%s" % (has_square, has_sos, all_fn, edge))
PYEOF
cat "$TMP/rs_check"

if grep -q "SYMS:0" "$TMP/rs_check"; then
    no "b.rs (Rust): extracted ZERO symbols — REAL FINDING: Rust ingest may be broken"
else
    ok "b.rs (Rust): extracted $( grep -o 'SYMS:[0-9]*' "$TMP/rs_check" | cut -d: -f2 ) symbol(s)"
fi
grep -q "HAS_SQUARE:True" "$TMP/rs_check" && ok "b.rs: square symbol present" || no "b.rs: square symbol missing"
grep -q "HAS_SOS:True" "$TMP/rs_check" && ok "b.rs: sum_of_squares symbol present" || no "b.rs: sum_of_squares symbol missing"
grep -q "ALL_FN:True" "$TMP/rs_check" && ok "b.rs: both symbols tagged t=\"fn\"" || no "b.rs: symbols not tagged t=\"fn\" as expected"
grep -q "EDGE:True" "$TMP/rs_check" && ok "b.rs: intra-file call edge sum_of_squares -> square present" || no "b.rs: call edge sum_of_squares -> square MISSING"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== c.m (ObjC): same-file decl/def collapse — 1 node per method, decl-only survives ==="
# ═══════════════════════════════════════════════════════════════════════════

python3 - "$TMP/parsed.json" <<'PYEOF' >"$TMP/m_check"
import json, sys
d = json.load(open(sys.argv[1]))
syms = d.get("c.m", [])
n_double = sum(1 for s in syms if s["n"] == "doubleValue")
n_quad   = sum(1 for s in syms if s["n"] == "quadrupleValue")
n_triple = sum(1 for s in syms if s["n"] == "tripleValue")
n_cls    = sum(1 for s in syms if s["n"] == "Calculator" and s["t"] == "cls")
methods_are_method_t = all(s["t"] == "method" for s in syms if s["n"] in ("doubleValue", "quadrupleValue", "tripleValue"))
# the self-call edge count: quadrupleValue's single node must carry EXACTLY ONE doubleValue edge
# (the two [self doubleValue:] sites dedup to one edge now that doubleValue is a single node).
quad_dbl_edges = sum(s["calls"].count("doubleValue") for s in syms if s["n"] == "quadrupleValue")
edge = quad_dbl_edges >= 1
print("SYMS:%d" % len(syms))
print("N_DOUBLE:%d N_QUAD:%d N_TRIPLE:%d N_CLS:%d METHOD_T:%s EDGE:%s QUAD_DBL_EDGES:%d" %
      (n_double, n_quad, n_triple, n_cls, methods_are_method_t, edge, quad_dbl_edges))
PYEOF
cat "$TMP/m_check"

if grep -q "SYMS:0" "$TMP/m_check"; then
    no "c.m (ObjC): extracted ZERO symbols — REAL FINDING: ObjC ingest is BROKEN for this fixture"
else
    ok "c.m (ObjC): extracted $( grep -o 'SYMS:[0-9]*' "$TMP/m_check" | cut -d: -f2 ) symbol(s) (non-zero — ObjC ingest works)"
fi

# FIXED behavior (was a KNOWN-GAP that pinned doubling): the same-file decl/def collapse merges
# each method's @interface decl into its @implementation def, so a method is ONE node, not two.
# Expected c.m shape: doubleValue x1, quadrupleValue x1, tripleValue x1 (decl-only), Calculator x1
# — 4 <s> nodes total (t="method" for the three methods, t="cls" for the class).
grep -q "N_DOUBLE:1" "$TMP/m_check" \
    && ok "c.m: doubleValue appears ONCE — @interface decl collapsed into @implementation def" \
    || no "c.m: expected doubleValue x1 (decl collapsed into def), got: $( grep N_DOUBLE "$TMP/m_check" )"
grep -q "N_QUAD:1" "$TMP/m_check" \
    && ok "c.m: quadrupleValue appears ONCE — @interface decl collapsed into @implementation def" \
    || no "c.m: expected quadrupleValue x1 (decl collapsed into def), got: $( grep N_QUAD "$TMP/m_check" )"
grep -q "N_CLS:1" "$TMP/m_check" \
    && ok "c.m: Calculator class appears ONCE — @interface collapsed into @implementation" \
    || no "c.m: expected Calculator x1 (t=cls), got: $( grep N_CLS "$TMP/m_check" )"

# ESCAPE HATCH: tripleValue: is declared in @interface with NO @implementation. With no def
# anywhere in the file, the collapse must KEEP the decl — exactly one tripleValue node survives.
grep -q "N_TRIPLE:1" "$TMP/m_check" \
    && ok "c.m: tripleValue (declared-only, no @implementation) SURVIVES — no-def-anywhere escape hatch" \
    || no "c.m: tripleValue over-collapsed or missing (expected x1 decl-only survivor): $( grep N_TRIPLE "$TMP/m_check" )"

grep -q "METHOD_T:True" "$TMP/m_check" \
    && ok "c.m: doubleValue/quadrupleValue/tripleValue tagged t=\"method\"" \
    || no "c.m: methods not tagged t=\"method\" as expected"

# The self-call edge quadrupleValue -> doubleValue IS present and now SINGLE (the two [self ...]
# sites resolve to the one collapsed doubleValue and dedup). If a future ingest change drops it,
# that's a real ObjC call-graph regression, not fixture noise.
grep -q "EDGE:True" "$TMP/m_check" \
    && ok "c.m: self-call edge quadrupleValue -> doubleValue ([self ...]) IS present" \
    || no "c.m: self-call edge quadrupleValue -> doubleValue MISSING (real ObjC call-graph regression)"
grep -q "QUAD_DBL_EDGES:1" "$TMP/m_check" \
    && ok "c.m: exactly ONE quadrupleValue -> doubleValue edge (no longer doubled by decl+def)" \
    || no "c.m: expected a single quadrupleValue -> doubleValue edge: $( grep QUAD_DBL_EDGES "$TMP/m_check" )"

# cross-check via --callees / --callers directly (independent of the raw-XML parse above). count=1
# now (was 2 pre-fix, one edge per doubleValue duplicate).
CALLEES_OUT="$( $BIN "$FIX" --callees=quadrupleValue 2>/dev/null )"
echo "$CALLEES_OUT" | grep -q 'count="1"' && echo "$CALLEES_OUT" | grep -q 'n="doubleValue"' \
    && ok "c.m: --callees=quadrupleValue reports count=1, doubleValue" \
    || no "c.m: --callees=quadrupleValue did not match expected shape (count=1, doubleValue): $CALLEES_OUT"

CALLERS_OUT="$( $BIN "$FIX" --callers=doubleValue 2>/dev/null )"
echo "$CALLERS_OUT" | grep -q 'n="quadrupleValue"' \
    && ok "c.m: --callers=doubleValue reports quadrupleValue as a caller" \
    || no "c.m: --callers=doubleValue did not list quadrupleValue: $CALLERS_OUT"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== d.h (ObjC header): .h content sniff reroutes to ObjC grammar ==="
# ═══════════════════════════════════════════════════════════════════════════

python3 - "$TMP/parsed.json" <<'PYEOF' >"$TMP/h_check"
import json, sys
d = json.load(open(sys.argv[1]))
syms = d.get("d.h", [])
n_cls = sum(1 for s in syms if s["n"] == "HeaderOnly" and s["t"] == "cls")
n_method = sum(1 for s in syms if s["n"] == "headerValue" and s["t"] == "method")
print("SYMS:%d N_CLS:%d N_METHOD:%d" % (len(syms), n_cls, n_method))
PYEOF
cat "$TMP/h_check"

if grep -q "SYMS:0" "$TMP/h_check"; then
    no "d.h (ObjC header): extracted ZERO symbols — .h ObjC reroute/query prewarm is broken"
else
    ok "d.h (ObjC header): extracted $( grep -o 'SYMS:[0-9]*' "$TMP/h_check" | cut -d: -f2 ) symbol(s)"
fi
grep -q "N_CLS:1" "$TMP/h_check" \
    && ok "d.h: HeaderOnly class captured via ObjC grammar" \
    || no "d.h: HeaderOnly class missing (likely parsed as C++ instead of ObjC): $( grep N_CLS "$TMP/h_check" )"
grep -q "N_METHOD:1" "$TMP/h_check" \
    && ok "d.h: headerValue method captured via ObjC grammar" \
    || no "d.h: headerValue method missing (ObjC header method lost): $( grep N_METHOD "$TMP/h_check" )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== determinism: default map twice, byte-identical ==="
# ═══════════════════════════════════════════════════════════════════════════

$BIN "$FIX" >"$TMP/det_a.xml" 2>/dev/null
$BIN "$FIX" >"$TMP/det_b.xml" 2>/dev/null
diff -q "$TMP/det_a.xml" "$TMP/det_b.xml" >/dev/null \
    && ok "determinism: default map byte-identical across two runs" \
    || no "determinism: default map differs across runs"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
