#!/usr/bin/env bash
# jsonlangcheck.sh — JSON config-key ingest coverage gate.
#
# ripwire --help now advertises JSON (.json) as a DATA language: object keys become
# searchable symbols (t="sec") so package.json / tsconfig.json config is findable by
# --for / --grep with its enclosing key — but JSON emits NO call edges and a JSON key
# NEVER resolves a same-spelled code symbol (lang-incompatible with everything).
# Assertions are pinned to what the binary ACTUALLY does — verified by running it and
# reading the output before writing any assertion (see the findings below).
#
# Fixture (test/jsonfix/):
#   package.json — top-level keys (name/version/main/scripts/dependencies/devDependencies)
#                  + second-level keys (build,test / react,lodash / typescript)
#   tsconfig.json — compilerOptions{target,module,strict} + include/exclude (array values)
#
# FINDINGS from running `ripwire test/jsonfix` and inspecting the raw output:
#   - Every captured key is t="sec" (SymKind::Section — same kind as a markdown heading).
#   - TOP-LEVEL keys AND SECOND-LEVEL keys (keys inside a top-level object value) are
#     indexed; ARRAY values are not descended (include/exclude yield no child symbols).
#   - edges=0: JSON is data, so the map has ZERO call edges from the JSON files.
#   - determinism: two runs are byte-identical.
#   - CROSS-LANGUAGE ISOLATION (test/jsonxlang/): a package.json "react" key + a JS
#     react()/main() pair yields exactly ONE edge (main->react, JS-internal); the JSON
#     "react" key is NOT an edge target (langCompatible keeps Json separate). Renaming
#     the JS call site removes that edge — proving the isolation assertion is real.
#
# Usage:
#   test/jsonlangcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/jsonlangcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/jsonfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for XML assertions"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "jsonlangcheck: BIN=$BIN  FIX=$FIX"

MAP_OUT="$TMP/map.xml"
$BIN "$FIX" --no-cache >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
[ "$MAP_EXIT" -eq 0 ] && ok "default map: exits 0 on JSON fixture" || no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"

command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$MAP_OUT" && ok "default map: passes xmllint --noout" || no "default map: xmllint failed"; }

# no degrade / ABI-mismatch warning must reach stderr on the clean fixture
[ -s "$TMP/map.err" ] && no "default map: unexpected stderr (ABI/degrade?): $( cat "$TMP/map.err" )" || ok "default map: clean stderr (no ABI mismatch / degrade)"

# edges=0: JSON is data, no call graph
EDGES="$( grep -o 'edges=[0-9]*' "$MAP_OUT" | head -1 )"
[ "$EDGES" = "edges=0" ] && ok "default map: $EDGES (JSON is data — no call edges)" || no "default map: expected edges=0, got $EDGES"

# ─── parse per-file symbols once ────────────────────────────────────────────
python3 - "$MAP_OUT" <<'PYEOF' >"$TMP/parsed.json"
import sys, re, json
xml = open(sys.argv[1], encoding='utf-8').read()
files = re.findall(r'<f p="([^"]+)"[^>]*>(.*?)</f>', xml, re.S)
out = {}
for path, body in files:
    name = path.split('/')[-1]
    syms = []
    for sm in re.finditer(r'<s t="(\w+)" n="([^"]*)"[^>]*>|<s t="(\w+)" n="([^"]*)"[^>]*/>', body):
        t = sm.group(1) if sm.group(1) is not None else sm.group(3)
        n = sm.group(2) if sm.group(2) is not None else sm.group(4)
        syms.append({"t": t, "n": n})
    out[name] = syms
print(json.dumps(out))
PYEOF

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== package.json: top-level + second-level keys, all t=\"sec\" ==="
# ═══════════════════════════════════════════════════════════════════════════
python3 - "$TMP/parsed.json" <<'PYEOF' >"$TMP/pkg_check"
import json, sys
d = json.load(open(sys.argv[1]))
syms = d.get("package.json", [])
names = set(s["n"] for s in syms)
top = {"name","version","main","scripts","dependencies","devDependencies"}
# `lodash.merge` is here for the DOTTED-KEY arm: a config key's dots are part of the NAME, not a scope
# separator, so it must survive whole. It did not until the TOML round — ingest's generic def path ran
# every captured name through finalSegment(), which split on "." and indexed this dependency as `merge`
# (colliding with every `merge` function in the repo, and making `--grep=lodash.merge` miss it).
# model.h::dataConfigNameIsWhole now exempts BOTH data-config languages; queries/toml/tags.scm's sibling
# assertion lives in test/tomllangcheck.sh. Keep the two arms together — they are one property.
lvl2 = {"build","test","react","lodash","lodash.merge","typescript"}
all_sec = all(s["t"] == "sec" for s in syms) if syms else False
print("SYMS:%d" % len(syms))
print("TOP_OK:%s" % top.issubset(names))
print("LVL2_OK:%s" % lvl2.issubset(names))
print("ALL_SEC:%s" % all_sec)
print("MISSING_TOP:%s" % (",".join(sorted(top - names)) or "none"))
print("MISSING_LVL2:%s" % (",".join(sorted(lvl2 - names)) or "none"))
# non-vacuous: the whole key must be present AND the truncated tail must be absent
print("DOTTED_OK:%s" % ("lodash.merge" in names and "merge" not in names))
PYEOF
cat "$TMP/pkg_check"
grep -q "SYMS:0" "$TMP/pkg_check" && no "package.json: extracted ZERO symbols — JSON ingest may be broken" || ok "package.json: extracted $( grep -o 'SYMS:[0-9]*' "$TMP/pkg_check" | cut -d: -f2 ) key symbol(s)"
grep -q "TOP_OK:True"  "$TMP/pkg_check" && ok "package.json: all 6 top-level keys present as symbols" || no "package.json: missing top-level keys: $( grep MISSING_TOP "$TMP/pkg_check" )"
grep -q "LVL2_OK:True" "$TMP/pkg_check" && ok "package.json: second-level keys present (scripts/deps entries)" || no "package.json: missing second-level keys: $( grep MISSING_LVL2 "$TMP/pkg_check" )"
grep -q "ALL_SEC:True" "$TMP/pkg_check" && ok "package.json: every key tagged t=\"sec\"" || no "package.json: some keys not t=\"sec\""
grep -qF '"lodash.merge"' "$FIX/package.json" || no "jsonfix LOST its dotted key — the arm below would pass by finding nothing"
grep -q "DOTTED_OK:True" "$TMP/pkg_check" \
    && ok "package.json: dotted key \`lodash.merge\` survives whole (not truncated to \`merge\`)" \
    || no "package.json: dotted key truncated — finalSegment is splitting a config key's name on '.'"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --grep finds a dependency name WITH its enclosing symbol ==="
# ═══════════════════════════════════════════════════════════════════════════
# TWO hits since the fixture gained its dotted key, and they must land in DIFFERENT enclosing symbols:
# `lodash` and `lodash.merge` are separate dependencies and therefore separate config symbols. That is a
# stronger arm than the single-hit one it replaces — before dataConfigNameIsWhole (model.h) both lines
# reported in="lodash"/in="merge", and a `lodash.merge` dependency was unfindable under its real name.
GREP_OUT="$( $BIN "$FIX" --grep=lodash 2>/dev/null )"
echo "$GREP_OUT" | grep -q 'hits="2"' && echo "$GREP_OUT" | grep -q 'in="lodash"' && echo "$GREP_OUT" | grep -q 'in="lodash.merge"' \
    && ok "--grep=lodash: 2 hits in DISTINCT enclosing symbols lodash / lodash.merge (config is findable)" \
    || no "--grep=lodash did not match (hits=2, in=lodash AND in=lodash.merge): $GREP_OUT"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== cross-language isolation: JSON key never becomes a code edge target ==="
# ═══════════════════════════════════════════════════════════════════════════
XL="$TMP/jsonxlang"; mkdir -p "$XL"
cp "$FIX/package.json" "$XL/package.json"
cat > "$XL/app.js" <<'JSEOF'
function react() { return 1; }
function main() { return react(); }
JSEOF
XL_OUT="$( $BIN "$XL" --no-cache 2>/dev/null )"
XL_EDGES="$( echo "$XL_OUT" | grep -o 'edges=[0-9]*' | head -1 )"
[ "$XL_EDGES" = "edges=1" ] && ok "mixed JSON+JS: $XL_EDGES (only the JS-internal main->react edge)" || no "mixed JSON+JS: expected edges=1, got $XL_EDGES"
XL_CR="$( $BIN "$XL" --callers=react --no-cache 2>/dev/null )"
echo "$XL_CR" | grep -q 'count="1"' && echo "$XL_CR" | grep -q 'app.js' \
    && ok "--callers=react: count=1, from app.js (JSON \"react\" key is NOT a caller/target)" \
    || no "--callers=react unexpected (JSON key leaked into the graph?): $XL_CR"

# mutation: rename the JS call site → the ONLY edge must vanish (non-tautological)
sed 's/return react()/return reactX()/' "$XL/app.js" >"$XL/app.js.tmp" && mv "$XL/app.js.tmp" "$XL/app.js"
XL_MUT="$( $BIN "$XL" --no-cache 2>/dev/null | grep -o 'edges=[0-9]*' | head -1 )"
[ "$XL_MUT" = "edges=0" ] && ok "mutation: renamed JS call site → edges=0 (the edge assertion is real)" || no "mutation: expected edges=0 after rename, got $XL_MUT"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== determinism: default map twice, byte-identical ==="
# ═══════════════════════════════════════════════════════════════════════════
$BIN "$FIX" --no-cache >"$TMP/det_a.xml" 2>/dev/null
$BIN "$FIX" --no-cache >"$TMP/det_b.xml" 2>/dev/null
diff -q "$TMP/det_a.xml" "$TMP/det_b.xml" >/dev/null \
    && ok "determinism: default map byte-identical across two runs" \
    || no "determinism: default map differs across runs"

# ─── json-data ceiling: a BIG pretty-printed .json is DATA, not config — never indexed ────────────
#   Found live by the Multi-SWE C++ benchmark: nlohmann/json's historical test/benchmark trees carry
#   200KB-4MB pretty-printed .json datasets that slip under the 4MB skip + minified-line heuristic; the
#   config-key extractor turned each into tens of thousands of junk symbols (>2min ingest vs 0.3s without
#   them). The JSON lane gets its OWN ceiling (kMaxJsonConfigBytes): real config files are small.
BIGJ="$TMP/bigdatafix"; mkdir -p "$BIGJ"
cp "$ROOT/test/jsonfix/package.json" "$BIGJ/package.json"
python3 - "$BIGJ/big_dataset.json" <<'PYEOF'
import json, sys
rows = [ { "id": i, "coords": [ i, i + 1 ], "label": f"row{i}" } for i in range( 9000 ) ]
open( sys.argv[1], "w" ).write( json.dumps( rows, indent=2 ) )   # ~600KB pretty-printed -> over the JSON ceiling
PYEOF
[ "$( wc -c < "$BIGJ/big_dataset.json" )" -gt 262144 ] || no "json-data fixture too small (fixture bug)"
OBIG="$( "$BIN" "$BIGJ" --no-cache 2>/dev/null )"
printf '%s' "$OBIG" | grep -q 'big_dataset' \
    && no "json-data ceiling: >256KB .json data file was indexed (symbol-table explosion risk)" \
    || ok "json-data ceiling: >256KB .json data file skipped from the crawl"
printf '%s' "$OBIG" | grep -q 'package.json' \
    && ok "json-data ceiling: small config .json still indexed alongside" \
    || no "json-data ceiling: small config .json vanished (ceiling over-fires)"

#   Hostile nesting guard: a small file of unclosed "[" drives tree-sitter-json's error recovery
#   superlinear (43s for 100KB measured). The quote-aware depth prescan must skip it BEFORE parsing —
#   asserted structurally (skipped + stderr note) with a generous wall-clock ceiling as the hang tripwire.
python3 -c "open('$BIGJ/hostile_nest.json','w').write('['*5000)"
python3 -c "import json; open('$BIGJ/deep_string.json','w').write(json.dumps({'weird': '['*5000, 'realkey': 1}))"
START_NS=$( date +%s )
OHOST="$( "$BIN" "$BIGJ" --no-cache 2>"$TMP/hostile_err.txt" )"
ELAPSED=$(( $( date +%s ) - START_NS ))
[ "$ELAPSED" -lt 20 ] \
    && ok "hostile nesting: run completed in ${ELAPSED}s (no error-recovery blowup)" \
    || no "hostile nesting: run took ${ELAPSED}s — the depth guard is not firing before the parse"
printf '%s' "$OHOST" | grep -q 'hostile_nest' \
    && no "hostile nesting: [[[[-file was indexed (guard missed it)" \
    || ok "hostile nesting: [[[[-file skipped"
grep -q 'json nesting' "$TMP/hostile_err.txt" \
    && ok "hostile nesting: skip degrades with the one-line stderr note" \
    || no "hostile nesting: skip was silent (degrade-note style violated)"
printf '%s' "$OHOST" | grep -q 'deep_string\|realkey' \
    && ok "hostile nesting: brackets inside a JSON STRING do not count (quote-aware scan)" \
    || no "hostile nesting: quote-blind scan skipped a legitimate config file"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
