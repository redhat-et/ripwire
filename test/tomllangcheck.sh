#!/usr/bin/env bash
# tomllangcheck.sh — TOML config-key ingest coverage gate.
#
# ripwire indexes TOML (.toml) as a DATA language, the same posture as JSON: table headers
# and keys become searchable symbols (t="sec") so pyproject.toml / Cargo.toml config is
# findable by --for / --grep with its enclosing table as the symbol — but TOML emits NO call
# edges and a TOML key NEVER resolves a same-spelled code symbol (lang-incompatible with
# everything, graph.h::langCompatible).
#
# THE ONE THING THIS GATE EXISTS TO PIN — and the reason it is not a copy of jsonlangcheck:
#   JSON's depth rule is "top-level + second-level object keys". Applied literally to TOML it
#   captures 38.3% of keys and misses EVERY key under a 2-dotted table: `[tool.ruff.lint]`
#   puts its keys at root-relative depth 4. In TOML the navigable unit is the TABLE HEADER,
#   and key depth is measured RELATIVE TO THE HEADER. The "keys under a depth-3 header" arm
#   below is red against any literal port of JSON's rule.
#
# Measured on the breadth corpus (90 public repos, /…/bench-assets/r4/repos) — the numbers
# that chose this design, recorded so a future reader can re-derive it:
#   321 .toml files; real parse-failure rate ~0.3% (50 of 51 "failures" are cpython's
#   test_tomllib/data/invalid/ deliberate fixtures). Sizes p50 277 B, p90 3 578 B, p99 21 449 B,
#   MAX 57 759 B. Shapes: plain `key =` 6 594 · `[table]` 2 561 · array value 1 270 ·
#   `[[aot]]` 300 · inline table 213 · dotted key 197. Header dotted depth 1:446 2:1421 3:415
#   4:191 5:87 6:1. No adversarial pathology: `[`x100 000 = 17.4 ms, 50 000 `[[aot]]` = 58.7 ms,
#   unterminated string 2 MB = 21.7 ms — all linear. Hence NO TOML-specific size or nest
#   ceiling (see ingest.h's note); the generic --max-file-size path is the only ceiling.
#
# Fixture (test/tomlfix/pyproject.toml): every construct above, with deliberately UNIQUE key
# spellings so a presence assertion can never be satisfied by a same-spelled key elsewhere.
#
# Usage:
#   test/tomllangcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/tomllangcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/tomlfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for XML assertions"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "tomllangcheck: BIN=$BIN  FIX=$FIX"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== presence guards: the fixture really contains what the arms below assert ==="
# ═══════════════════════════════════════════════════════════════════════════
# CONTRIBUTING §2 / METHODOLOGY §1 "vanished probe target": every arm below searches the map
# for a construct. If the fixture ever stops SPELLING that construct, the arm would pass by
# finding nothing on both sides. Assert the probe target exists before asserting the property.
PY="$FIX/pyproject.toml"
[ -f "$PY" ] || { echo "fixture file $PY missing"; exit 2; }
guard(){ grep -qF -- "$1" "$PY" && ok "fixture contains $2" || { no "fixture LOST $2 — every arm below would pass by finding nothing"; }; }
guard '[tool.ruff.lint]'          'a depth-3 table header  [tool.ruff.lint]'
guard '[[tool.mypy.overrides]]'   'an array-of-tables header  [[tool.mypy.overrides]]'
guard 'dottedkey.subpart ='       'a dotted key  dottedkey.subpart ='
guard '{ inlinegit ='             'an inline table  { inlinegit = … }'
guard 'toplevelkey ='             'a plain top-level key  toplevelkey ='
guard 'selectrule ='              'a key under the depth-3 header  selectrule ='
[ "$( grep -c '^\[\[tool\.mypy\.overrides\]\]' "$PY" )" -eq 2 ] \
    && ok "fixture has 2 [[tool.mypy.overrides]] headers (the per-header-not-per-index arm has something to count)" \
    || no "fixture no longer has exactly 2 [[tool.mypy.overrides]] headers"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== default map: exits 0, well-formed, clean stderr, edges=0 ==="
# ═══════════════════════════════════════════════════════════════════════════
MAP_OUT="$TMP/map.xml"
$BIN "$FIX" --no-cache >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
[ "$MAP_EXIT" -eq 0 ] && ok "default map: exits 0 on TOML fixture" || no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"

command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$MAP_OUT" && ok "default map: passes xmllint --noout" || no "default map: xmllint failed"; }

# no degrade / ABI-mismatch warning must reach stderr on the clean fixture
[ -s "$TMP/map.err" ] && no "default map: unexpected stderr (ABI/degrade?): $( cat "$TMP/map.err" )" || ok "default map: clean stderr (no ABI mismatch / degrade)"

# edges=0: TOML is data, no call graph
EDGES="$( grep -o 'edges=[0-9]*' "$MAP_OUT" | head -1 )"
[ "$EDGES" = "edges=0" ] && ok "default map: $EDGES (TOML is data — no call edges)" || no "default map: expected edges=0, got $EDGES"

# ─── parse per-file symbols once ────────────────────────────────────────────
python3 - "$MAP_OUT" <<'PYEOF' >"$TMP/parsed.json"
import sys, re, json
xml = open(sys.argv[1], encoding='utf-8').read()
files = re.findall(r'<f p="([^"]+)"[^>]*>(.*?)</f>', xml, re.S)
out = {}
for path, body in files:
    name = path.split('/')[-1]
    syms = []
    for sm in re.finditer(r'<s t="(\w+)" n="([^"]*)"([^>]*)', body):
        t, n, rest = sm.group(1), sm.group(2), sm.group(3)
        # same-name defs are MERGED into one row carrying overloads="N" (see the map legend), so the
        # def count for a name is 1 unless the row says otherwise.
        ov = re.search(r'overloads="(\d+)"', rest)
        syms.append({"t": t, "n": n, "defs": int(ov.group(1)) if ov else 1})
    out[name] = syms
print(json.dumps(out))
PYEOF

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== the design table: headers by full dotted name, keys relative to their header ==="
# ═══════════════════════════════════════════════════════════════════════════
python3 - "$TMP/parsed.json" <<'PYEOF' >"$TMP/toml_check"
import json, sys
d = json.load(open(sys.argv[1]))
syms  = d.get("pyproject.toml", [])
names = [s["n"] for s in syms]
nset  = set(names)

# a [table] header is a symbol named by its FULL dotted header — `--grep=tool.ruff` must land
headers = {"project", "tool.ruff", "tool.ruff.lint", "tool.mypy.overrides",
           "tool.poetry.dependencies", "tool.black", "build-system"}
# keys, one level below their header REGARDLESS of the header's dotted depth
keys_d3 = {"selectrule", "ignorerule"}            # under [tool.ruff.lint] — the central case
keys_other = {"toplevelkey", "tomlversion",       # plain top-level
              "requires-python", "line-length",   # under 1-deep / 2-deep headers
              "modulepat", "modulepat2",          # under [[aot]] headers
              "requests", "buildrequires"}
# an inline table is NOT descended: the owning key `requests` is the symbol, its members are not
inline_members = {"inlinegit", "inlinerev"}
# a dotted key is ONE symbol under its full dotted spelling — never split into `dottedkey`
dotted_full, dotted_head = "dottedkey.subpart", "dottedkey"

all_sec = all(s["t"] == "sec" for s in syms) if syms else False
print("SYMS:%d" % len(syms))
print("ALL_SEC:%s" % all_sec)
print("HEADERS_OK:%s"  % headers.issubset(nset));    print("MISSING_HEADERS:%s"  % (",".join(sorted(headers - nset)) or "none"))
print("KEYS_D3_OK:%s"  % keys_d3.issubset(nset));    print("MISSING_KEYS_D3:%s"  % (",".join(sorted(keys_d3 - nset)) or "none"))
print("KEYS_OTH_OK:%s" % keys_other.issubset(nset)); print("MISSING_KEYS_OTH:%s" % (",".join(sorted(keys_other - nset)) or "none"))
# non-vacuous on purpose: the owning key must BE there for "its members are not" to mean anything
print("INLINE_OK:%s"   % ("requests" in nset and not (inline_members & nset))); print("LEAKED_INLINE:%s" % (",".join(sorted(inline_members & nset)) or "none"))
print("DOTTED_OK:%s"   % (dotted_full in nset and dotted_head not in nset))
# [[aot]]: TWO headers of the same name are two DEFS. The default map merges same-name defs into one
# ROW carrying overloads="2" — so the honest question is "how many defs", not "how many rows".
print("AOT_DEFS:%d"    % sum(s["defs"] for s in syms if s["n"] == "tool.mypy.overrides"))
PYEOF
cat "$TMP/toml_check"

grep -q "SYMS:0" "$TMP/toml_check" \
    && no "pyproject.toml: extracted ZERO symbols — .toml is not indexed at all" \
    || ok "pyproject.toml: extracted $( grep -o '^SYMS:[0-9]*' "$TMP/toml_check" | cut -d: -f2 ) symbol(s)"
grep -q "ALL_SEC:True" "$TMP/toml_check" \
    && ok "pyproject.toml: every symbol tagged t=\"sec\"" \
    || no "pyproject.toml: some symbols are not t=\"sec\""
grep -q "HEADERS_OK:True" "$TMP/toml_check" \
    && ok "[table] headers are symbols named by their FULL dotted header" \
    || no "missing/renamed table headers: $( grep '^MISSING_HEADERS:' "$TMP/toml_check" )"
grep -q "KEYS_D3_OK:True" "$TMP/toml_check" \
    && ok "keys under the DEPTH-3 header [tool.ruff.lint] are present (depth is header-relative)" \
    || no "keys under [tool.ruff.lint] are MISSING: $( grep '^MISSING_KEYS_D3:' "$TMP/toml_check" ) — this is JSON's root-relative depth rule ported literally"
grep -q "KEYS_OTH_OK:True" "$TMP/toml_check" \
    && ok "plain top-level keys and keys under 1-/2-deep and [[aot]] headers are present" \
    || no "missing keys: $( grep '^MISSING_KEYS_OTH:' "$TMP/toml_check" )"
grep -q "INLINE_OK:True" "$TMP/toml_check" \
    && ok "inline table NOT descended — the owning key \`requests\` is the symbol" \
    || no "inline-table members leaked in as symbols: $( grep '^LEAKED_INLINE:' "$TMP/toml_check" )"
grep -q "DOTTED_OK:True" "$TMP/toml_check" \
    && ok "dotted key is ONE symbol \`dottedkey.subpart\` (not split into \`dottedkey\`)" \
    || no "dotted key wrong: expected \`dottedkey.subpart\` present and \`dottedkey\` absent"
grep -q "^AOT_DEFS:2$" "$TMP/toml_check" \
    && ok "[[array-of-tables]]: one symbol per header (2 headers -> 2 defs), elements not index-numbered" \
    || no "[[aot]] def count wrong: $( grep '^AOT_DEFS:' "$TMP/toml_check" ) (expected 2)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --grep lands on a dotted table header (the navigable unit) ==="
# ═══════════════════════════════════════════════════════════════════════════
# A dotted header must survive as ONE name all the way to a verb's enclosing-symbol field: ingest's
# generic def path runs every captured name through finalSegment(), which splits on "." and would report
# this hit as in="lint" — a name that collides with every other `lint` in a repo.
GREP_OUT="$( $BIN "$FIX" --grep=tool.ruff.lint --no-cache 2>/dev/null )"
echo "$GREP_OUT" | grep -q 'in="tool.ruff.lint"' \
    && ok "--grep=tool.ruff.lint (cold): enclosing symbol in=\"tool.ruff.lint\" (config is navigable)" \
    || no "--grep=tool.ruff.lint (cold) did not report in=\"tool.ruff.lint\": $GREP_OUT"

# ...and again WARM, through a cache round-trip, in a cache dir this gate owns. Worth its own arm: the
# name is persisted and reloaded rather than recomputed, so a serialization that dropped or re-split it
# would be invisible to every --no-cache arm above. The private TMPDIR (the warm cache is
# $TMPDIR/ripwire — see --doctor's cache-dir check) is what makes the arm honest in both directions: it
# cannot be satisfied by a developer's warm cache, and it cannot be POISONED by one either. This gate's
# own iteration hit exactly that — an intermediate build wrote a blob at the SAME kParserVer with the old
# truncated names, and the warm answer stayed `lint` long after the fix landed and every cold arm passed.
CACHEDIR="$TMP/tmpdir"; mkdir -p "$CACHEDIR"
TMPDIR="$CACHEDIR" $BIN "$FIX" >/dev/null 2>&1                               # cold: populate
GREP_WARM="$( TMPDIR="$CACHEDIR" $BIN "$FIX" --grep=tool.ruff.lint 2>/dev/null )"
echo "$GREP_WARM" | grep -q 'in="tool.ruff.lint"' \
    && ok "--grep=tool.ruff.lint (warm): the dotted name survives the cache round-trip" \
    || no "--grep=tool.ruff.lint (warm) did not report in=\"tool.ruff.lint\": $GREP_WARM"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== cross-language isolation: a TOML key never becomes a code edge target ==="
# ═══════════════════════════════════════════════════════════════════════════
# Mirrors jsonlangcheck's isolation arm, INCLUDING its mutation: without the mutation, an
# "edges=1" assertion is satisfied for free by a build in which TOML contributes nothing.
XL="$TMP/tomlxlang"; mkdir -p "$XL"
cat > "$XL/Cargo.toml" <<'TOMLEOF'
[package]
name = "xlang"

[dependencies]
serde = "1.0"
TOMLEOF
cat > "$XL/app.js" <<'JSEOF'
function serde() { return 1; }
function main() { return serde(); }
JSEOF
XL_OUT="$( $BIN "$XL" --no-cache 2>/dev/null )"
XL_EDGES="$( echo "$XL_OUT" | grep -o 'edges=[0-9]*' | head -1 )"
[ "$XL_EDGES" = "edges=1" ] && ok "mixed TOML+JS: $XL_EDGES (only the JS-internal main->serde edge)" || no "mixed TOML+JS: expected edges=1, got $XL_EDGES"
# the TOML side must actually be in the map, or the isolation claim is vacuous
echo "$XL_OUT" | grep -q 'Cargo.toml' && ok "mixed TOML+JS: Cargo.toml IS indexed (isolation arm is not vacuous)" || no "mixed TOML+JS: Cargo.toml absent from the map"
XL_CR="$( $BIN "$XL" --callers=serde --no-cache 2>/dev/null )"
echo "$XL_CR" | grep -q 'count="1"' && echo "$XL_CR" | grep -q 'app.js' \
    && ok "--callers=serde: count=1, from app.js (the TOML \`serde\` key is NOT a caller/target)" \
    || no "--callers=serde unexpected (TOML key leaked into the graph?): $XL_CR"

# mutation: rename the JS call site → the ONLY edge must vanish (non-tautological)
sed 's/return serde()/return serdeX()/' "$XL/app.js" >"$XL/app.js.tmp" && mv "$XL/app.js.tmp" "$XL/app.js"
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

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== no TOML-specific ceiling: the largest REAL .toml in 90 repos is 57 759 B ==="
# ═══════════════════════════════════════════════════════════════════════════
# The JSON lane needed its own 256 KB ceiling because >200 KB pretty-printed .json is
# essentially always DATA. TOML has no such class: it is a hand-authored config format, the
# corpus max is 57 KB, and the adversarial probes are all linear (see the header). Adding a
# ceiling anyway would be theatre — so this arm pins the DECISION: a .toml comfortably larger
# than any observed real file is still indexed, and the generic --max-file-size path is the
# only thing that can drop it.
BIGT="$TMP/bigtoml"; mkdir -p "$BIGT"
python3 - "$BIGT/big_config.toml" <<'PYEOF'
import sys
with open(sys.argv[1], "w") as f:
    f.write("bigmarker = 1\n")
    for i in range(4000):                     # ~150 KB — 2.6x the corpus max, still config
        f.write("\n[tool.pkg%d]\nversion = \"1.0\"\ndeepsentinel%d = true\n" % (i, i))
PYEOF
BIGSZ="$( wc -c < "$BIGT/big_config.toml" )"
[ "$BIGSZ" -gt 57759 ] || no "big-toml fixture ($BIGSZ B) is not larger than the corpus max 57759 B (fixture bug)"
OBIG="$( "$BIN" "$BIGT" --no-cache 2>/dev/null )"
printf '%s' "$OBIG" | grep -q 'big_config' \
    && ok "no TOML ceiling: a ${BIGSZ}-byte .toml (>2x the corpus max) is still indexed" \
    || no "no TOML ceiling: a ${BIGSZ}-byte .toml was dropped — an undocumented TOML ceiling exists"

# adversarial shapes: measured linear on the probe corpus, so they must merely COMPLETE.
# A wall-clock tripwire, not a perf budget (no-perf-budget-gates): generous by two orders.
python3 -c "open('$BIGT/hostile_brackets.toml','w').write('['*100000)"
python3 -c "open('$BIGT/hostile_unterminated.toml','w').write('k = \"' + 'x'*200000)"
START_S=$( date +%s )
"$BIN" "$BIGT" --no-cache >/dev/null 2>"$TMP/hostile_err.txt"
ELAPSED=$(( $( date +%s ) - START_S ))
[ "$ELAPSED" -lt 20 ] \
    && ok "adversarial TOML ('['x100000 + a 200 KB unterminated string) completed in ${ELAPSED}s" \
    || no "adversarial TOML took ${ELAPSED}s — error recovery is not linear; a nest guard IS needed"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
