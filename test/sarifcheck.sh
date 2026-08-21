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
#   8. SELECTION crosses over. The XML path drops a --lint-select=/--lint-ignore= deselected rule's row
#      entirely and states selected="K of N" + the raw select= on its root; the SARIF path emitted the
#      full 39-rule catalogue BYTE-IDENTICAL whether a rule was selected in or out, and said nothing at
#      the run level. A consumer reading that document could not tell a filtered run from an unfiltered
#      one. SARIF's own field for "in the catalogue but not enabled this run" is
#      defaultConfiguration.enabled — present-and-false on a deselected rule, ABSENT (SARIF's own
#      default of true) on a kept one — and the run-level mirror rides properties beside findingsCapped.
#   9. INERTNESS crosses over. A rule row's applicable="0" in the XML means NONE of its registered
#      languages exist in this corpus, so its count="0" is structural, never a measurement. In SARIF
#      those rules read as ran-and-found-nothing. properties.applicable carries the same fact, and it is
#      emitted for EVERY rule (true as well as false) so its absence can never be read as "true".
#  10. MUTATION CONTROL for 8+9 — the unfiltered run over a C-family corpus must show the negative of
#      both: no rule disabled, and the C-family rules applicable. Without it, a serializer that hard-coded
#      enabled:false / applicable:false everywhere would pass arms 8 and 9.
#
#   RIPWIRE_BIN=build/ripwire bash test/sarifcheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/sarifcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
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

# ── 8. --lint-select= crosses over: deselected rules are disabled, and the run says so ───────────────
"$BIN" "$CORPUS" --lint --lint-select=cache- --sarif --no-cache >"$TMP/sel.json" 2>/dev/null
SEL="$( python3 - "$TMP/sel.json" <<'PY'
import json, sys
try:
    d = json.load( open( sys.argv[1] ) )
except Exception as exc:
    print( "PARSE_FAIL", exc ); raise SystemExit( 0 )
run   = d[ "runs" ][ 0 ]
rules = run[ "tool" ][ "driver" ][ "rules" ]
def enabled( r ):
    return r.get( "defaultConfiguration", {} ).get( "enabled", True )
offDisabled = [ r["id"] for r in rules if not r["id"].startswith( "cache-" ) and not enabled( r ) ]
offEnabled  = [ r["id"] for r in rules if not r["id"].startswith( "cache-" ) and     enabled( r ) ]
inDisabled  = [ r["id"] for r in rules if     r["id"].startswith( "cache-" ) and not enabled( r ) ]
print( "SELECTED_OUT_DISABLED", len( offDisabled ) )
print( "SELECTED_OUT_STILL_ENABLED", len( offEnabled ) )
print( "SELECTED_IN_DISABLED", len( inDisabled ) )
props = run.get( "properties", {} )
print( "PROP_SELECTED", props.get( "selected", "<absent>" ) )
print( "PROP_SELECT", props.get( "select", "<absent>" ) )
PY
)"
echo "$SEL" | sed 's/^/          /'
n(){ printf '%s' "$SEL" | grep "^$1 " | awk '{print $2}'; }
[ "$( n SELECTED_OUT_DISABLED )" -gt 0 ] 2>/dev/null \
    && ok "8. a selected-OUT rule carries defaultConfiguration.enabled=false ($( n SELECTED_OUT_DISABLED ) of them)" \
    || no "8. NO selected-out rule is marked disabled — the catalogue reads identical filtered or not"
[ "$( n SELECTED_OUT_STILL_ENABLED )" = "0" ] \
    && ok "8. EVERY selected-out rule is marked disabled (none left reading as enabled)" \
    || no "8. $( n SELECTED_OUT_STILL_ENABLED ) selected-out rule(s) still read as enabled"
[ "$( n SELECTED_IN_DISABLED )" = "0" ] \
    && ok "8. no selected-IN (cache-*) rule was disabled — the filter is not inverted" \
    || no "8. $( n SELECTED_IN_DISABLED ) selected-IN rule(s) were marked disabled"
printf '%s' "$SEL" | grep -q '^PROP_SELECTED [0-9]* of [0-9]*$' \
    && ok "8. run properties mirror the XML root's selected=\"K of N\"" \
    || no "8. run-level properties carry no selected=\"K of N\" mirror"
printf '%s' "$SEL" | grep -q '^PROP_SELECT cache-$' \
    && ok "8. run properties echo the raw select= you passed (cache-)" \
    || no "8. run-level properties do not echo the raw select= argument"

# ── 9. a Python-only corpus marks the C-family rules structurally inert ──────────────────────────────
mkdir -p "$TMP/pyonly"
printf 'def alpha( x ):\n    return x + 1\n' > "$TMP/pyonly/a.py"
"$BIN" "$TMP/pyonly" --lint --sarif --no-cache >"$TMP/py.json" 2>/dev/null
PY_APP="$( python3 - "$TMP/py.json" <<'PY'
import json, sys
try:
    d = json.load( open( sys.argv[1] ) )
except Exception as exc:
    print( "PARSE_FAIL", exc ); raise SystemExit( 0 )
rules = { r["id"]: r for r in d[ "runs" ][ 0 ][ "tool" ][ "driver" ][ "rules" ] }
r = rules.get( "typedef-over-using" )
print( "PRESENT", "yes" if r else "no" )
if r:
    print( "APPLICABLE", r.get( "properties", {} ).get( "applicable", "<absent>" ) )
print( "MISSING_PROP", sum( 1 for x in rules.values() if "applicable" not in x.get( "properties", {} ) ) )
PY
)"
echo "$PY_APP" | sed 's/^/          /'
printf '%s' "$PY_APP" | grep -q '^PRESENT yes$' \
    && ok "9. the C-family rule typedef-over-using is in the Python-only catalogue (guard for the arm below)" \
    || no "9. typedef-over-using absent from the Python-only catalogue — the arm below would pass vacuously"
printf '%s' "$PY_APP" | grep -q '^APPLICABLE False$' \
    && ok "9. it carries properties.applicable=false — inert here, not measured-clean" \
    || no "9. properties.applicable is not false on a C-family rule over a Python-only corpus"
printf '%s' "$PY_APP" | grep -q '^MISSING_PROP 0$' \
    && ok "9. every rule carries properties.applicable — absence can never be misread as true" \
    || no "9. some rules omit properties.applicable"

# ── 10. mutation control — the unfiltered C-family run must show the NEGATIVE of both ────────────────
MUT="$( python3 - "$TMP/out1.json" <<'PY'
import json, sys
d     = json.load( open( sys.argv[1] ) )
rules = d[ "runs" ][ 0 ][ "tool" ][ "driver" ][ "rules" ]
dis   = [ r["id"] for r in rules if not r.get( "defaultConfiguration", {} ).get( "enabled", True ) ]
inert = [ r["id"] for r in rules if r.get( "properties", {} ).get( "applicable" ) is False ]
print( "DISABLED", len( dis ) )
print( "CFAMILY_INERT", 1 if "typedef-over-using" in inert else 0 )
print( "PROPS", json.dumps( d[ "runs" ][ 0 ].get( "properties", {} ), sort_keys = True ) )
PY
)"
echo "$MUT" | sed 's/^/          /'
printf '%s' "$MUT" | grep -q '^DISABLED 0$' \
    && ok "10. an unfiltered run disables nothing (enabled:false is not hard-coded)" \
    || no "10. an unfiltered run marks rules disabled — the selection mirror is not reading the selection"
printf '%s' "$MUT" | grep -q '^CFAMILY_INERT 0$' \
    && ok "10. typedef-over-using is APPLICABLE over the C-family fixture (applicable:false is not hard-coded)" \
    || no "10. typedef-over-using reads inert over a C++ corpus"
printf '%s' "$MUT" | grep -q '"selected"' \
    && no "10. an unfiltered run still emits a selected= mirror — absent must mean no selection was given" \
    || ok "10. no selection mirror on an unfiltered run (absent = nothing to say)"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
