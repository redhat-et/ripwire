#!/usr/bin/env bash
# sarifcheck.sh — W1-SARIF (board Track A P0-7): --lint --sarif serializes lint findings as SARIF
# 2.1.0 (github.com/oasis-tcs/sarif-spec), the shape github/codeql-action/upload-sarif consumes for
# the code-scanning UI. Pure re-serialization of the SAME findings --lint's native XML already
# computes — no new analysis, so this gate is a PARITY + SHAPE gate, not a new-findings gate.
#
# Arms:
#   1. --lint --sarif exists and exits 0 on a real corpus
#   2. output parses as JSON (python3 json.load)
#   3. the SARIF-minimum-viable fields for GitHub code scanning are present: version, $schema,
#      runs[0].tool.driver.name, runs[0].tool.driver.rules, runs[0].results
#   4. PARITY — results count == the SAME run's native --lint findings="N" count (serialization
#      must not drop or invent findings)
#   5. deterministic — two runs byte-identical (the same contract every other lint verb carries)
#   6. relative URIs — every result's artifactLocation.uri is relative to the scanned root (no
#      leading '/', no drive letter, no '..' escape)
#   7. a known fixture (test/lintfix/bad.cpp's typedef-over-using at line 9) produces the expected
#      ruleId at the expected line
#
#   RIPWIRE_BIN=build/ripwire bash test/sarifcheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/sarifcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/lintfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]    || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/lintfix dir — fixture missing"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "sarifcheck: python3 missing (gate cannot run)"; exit 2; }

echo "sarifcheck: BIN=$BIN  CORPUS=$CORPUS"

# ── 1. flag exists, exits 0 ──────────────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --lint --sarif --no-cache >"$TMP/out1.json" 2>"$TMP/err1"; rc=$?
if [ "$rc" -eq 0 ]; then ok "--lint --sarif exits 0"
else no "--lint --sarif exit $rc"; sed 's/^/          /' "$TMP/err1"; fi

# presence guard: a later arm reading an empty/absent file must not read as a silent pass
[ -s "$TMP/out1.json" ] && ok "--lint --sarif produced non-empty stdout" \
    || { no "--lint --sarif produced EMPTY stdout — every arm below is meaningless"; printf 'sarifcheck: FAILURES ABOVE\n'; exit 1; }

# ── 2. output parses as JSON ─────────────────────────────────────────────────────────────────────
if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$TMP/out1.json" 2>"$TMP/jsonerr"; then
    ok "output parses as JSON (python3 json.load)"
else
    no "output does NOT parse as JSON:"; sed 's/^/          /' "$TMP/jsonerr"
fi

# ── 3. SARIF-minimum-viable fields present ───────────────────────────────────────────────────────
FIELDS="$( python3 - "$TMP/out1.json" <<'PY'
import json, sys
try:
    d = json.load( open( sys.argv[1] ) )
except Exception as exc:
    print( "PARSE_FAIL", exc ); sys.exit( 0 )
ok = True
def need( cond, label ):
    global ok
    print( ( "HAVE " if cond else "MISS " ) + label )
    if not cond:
        ok = False
need( d.get( "version" ) == "2.1.0", "version=2.1.0" )
need( isinstance( d.get( "$schema" ), str ) and d[ "$schema" ], "$schema" )
runs = d.get( "runs" )
need( isinstance( runs, list ) and len( runs ) >= 1, "runs[0]" )
if isinstance( runs, list ) and runs:
    r0 = runs[0]
    driver = r0.get( "tool", {} ).get( "driver", {} )
    need( isinstance( driver.get( "name" ), str ) and driver[ "name" ], "runs[0].tool.driver.name" )
    need( isinstance( driver.get( "rules" ), list ), "runs[0].tool.driver.rules" )
    results = r0.get( "results" )
    need( isinstance( results, list ), "runs[0].results" )
    if isinstance( results, list ) and results:
        r = results[0]
        need( isinstance( r.get( "ruleId" ), str ) and r[ "ruleId" ], "results[0].ruleId" )
        need( isinstance( r.get( "level" ), str ) and r[ "level" ], "results[0].level" )
        need( isinstance( r.get( "message", {} ).get( "text" ), str ), "results[0].message.text" )
        loc = r.get( "locations", [ {} ] )[0].get( "physicalLocation", {} )
        need( isinstance( loc.get( "artifactLocation", {} ).get( "uri" ), str ), "results[0].locations[0].physicalLocation.artifactLocation.uri" )
        need( isinstance( loc.get( "region", {} ).get( "startLine" ), int ), "results[0].locations[0].physicalLocation.region.startLine" )
print( "ALLOK" if ok else "SOMEMISSING" )
PY
)"
echo "$FIELDS" | sed 's/^/          /'
if echo "$FIELDS" | grep -q '^ALLOK$'; then
    ok "all SARIF-minimum-viable fields present (version, \$schema, tool.driver.name/rules, results[].ruleId/level/message/locations)"
else
    no "at least one SARIF-minimum-viable field is missing (see HAVE/MISS above)"
fi

# ── 4. PARITY — results count == native --lint findings count, same run ─────────────────────────
"$BIN" "$CORPUS" --lint --no-cache >"$TMP/native.xml" 2>/dev/null
NATIVE_N="$( grep -oE '<lint findings="[0-9]+"' "$TMP/native.xml" | head -1 | grep -oE '[0-9]+' )"
SARIF_N="$( python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(len(d['runs'][0]['results']))" "$TMP/out1.json" 2>/dev/null )"
if [ -n "${NATIVE_N:-}" ] && [ -n "${SARIF_N:-}" ] && [ "$NATIVE_N" = "$SARIF_N" ]; then
    ok "parity — SARIF results ($SARIF_N) == native --lint findings ($NATIVE_N)"
else
    no "parity FAILED — SARIF results (${SARIF_N:-unreadable}) != native --lint findings (${NATIVE_N:-unreadable})"
fi

# ── 5. deterministic — two runs byte-identical ───────────────────────────────────────────────────
"$BIN" "$CORPUS" --lint --sarif --no-cache >"$TMP/out2.json" 2>/dev/null
diff -q "$TMP/out1.json" "$TMP/out2.json" >/dev/null \
    && ok "deterministic (byte-identical run-to-run)" \
    || { no "non-deterministic SARIF output"; diff "$TMP/out1.json" "$TMP/out2.json" | head -8; }

# ── 6. relative URIs ──────────────────────────────────────────────────────────────────────────────
URI_BAD="$( python3 - "$TMP/out1.json" <<'PY'
import json, sys
d = json.load( open( sys.argv[1] ) )
bad = []
for r in d.get( "runs", [ {} ] )[0].get( "results", [] ):
    for loc in r.get( "locations", [] ):
        uri = loc.get( "physicalLocation", {} ).get( "artifactLocation", {} ).get( "uri", "" )
        if uri.startswith( "/" ) or ":" in uri.split( "/" )[0] or ".." in uri.split( "/" ):
            bad.append( uri )
print( "\n".join( bad ) )
PY
)"
if [ -z "$URI_BAD" ]; then
    ok "every result URI is relative to the scanned root"
else
    no "found non-relative URI(s):"; printf '%s\n' "$URI_BAD" | sed 's/^/          /'
fi

# ── 7. known fixture: typedef-over-using at test/lintfix/bad.cpp:9 ─────────────────────────────────
HIT="$( python3 - "$TMP/out1.json" <<'PY'
import json, sys
d = json.load( open( sys.argv[1] ) )
for r in d.get( "runs", [ {} ] )[0].get( "results", [] ):
    if r.get( "ruleId" ) != "typedef-over-using":
        continue
    for loc in r.get( "locations", [] ):
        pl = loc.get( "physicalLocation", {} )
        uri = pl.get( "artifactLocation", {} ).get( "uri", "" )
        line = pl.get( "region", {} ).get( "startLine" )
        if uri.endswith( "bad.cpp" ) and line == 9:
            print( "FOUND" ); sys.exit( 0 )
print( "MISSING" )
PY
)"
[ "$HIT" = "FOUND" ] && ok "typedef-over-using at test/lintfix/bad.cpp:9 present with the expected ruleId+line" \
    || no "typedef-over-using at bad.cpp:9 NOT found in SARIF results"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
