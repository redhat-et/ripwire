#!/usr/bin/env bash
# impactimportcheck.sh — LB-H (r10 GitNexus round, PLAN_HARVEST_REPORTS_2026-08-20/r10-gitnexus.md §5):
# `--impact` on a class/module reported CALL reach only. On webpack, `--impact=ChunkGraph` returned 25
# reaching symbols and no trace of the 8 files that `require("./ChunkGraph")` — not the files, and not a
# count saying they were uncounted. The competitor carried them as a first-class `imports` edge class.
#
# Two facts are gated here, because the round's own premise was wrong about the first one:
#
#   1. EXTRACTION — CommonJS `require("./x")` is an include/import directive. Pre-fix it was invisible:
#      `--deps` over webpack's whole 695-file CommonJS `lib/` reported files="0" (ZERO file→file edges),
#      so the import data LB-H wanted to surface did not exist in the graph at all. `--uses` did not have
#      it either. Only ESM `import … from` was captured.
#
#   2. DISCLOSURE — `--impact` emits the importer files as their OWN tier: `importers=` on the root
#      (always, even when 0), `shown_importers=`/`importers_capped=` per pageview.h rule 6 (a SECONDARY
#      listing discloses through its own noun-prefixed pair, never the paging half), and one
#      `<f via="import" p="…"/>` row per file. reaches= must NOT move: call reach and import reach are
#      two different measurements over two different units and are never summed into one number
#      (CLAUDE.md non-negotiable #3).
#
# FIXTURE test/impactimportfix — lib/Widget.js is imported by SEVEN siblings and CALLED by exactly one:
#   alpha.js, beta.js, gamma.js  `require("./Widget")`, never call it   → import tier only
#   user.js                      `require("./Widget")` + `new Widget()` → BOTH tiers (file vs symbol)
#   delta.js                     ESM `import Widget from "./Widget.js"` → same tier as the requires
#   lazyimporter.js              `require("./Widget")` INSIDE a function body, never at top level →
#                                 import tier, lazy="1" (kParserVer 72, fnbody-require lane)
#   barrel.js                    `get Widget() { return require("./Widget"); }` — a lazy getter NAMED
#                                 "Widget" (same name as the symbol under test), i.e. a def file that is
#                                 ALSO a genuine importer of a DIFFERENT def file → import tier, lazy="1"
#                                 (barrel-exclusion lane, PLAN_HARVEST_REPORTS_2026-08-20/
#                                 barrel-exclusion-lane.md; the webpack lib/index.js `ChunkGraph` shape)
#   orphan.js                    imported by nobody                     → the importers="0" witness
# So the pre-71 binary shows reaches="1" and nothing else; kParserVer 71 (top-level require only) shows
# importers="5" with no lazy="…" attribute at all; kParserVer 72 (fnbody-require lane) added lazyimporter.js
# for importers="6" but — deliberately, per that lane's own fixture comment — dodged the same-named-getter
# collision; the barrel-exclusion fix adds barrel.js on top for importers="7": the six pre-existing rows
# unchanged, plus lib/barrel.js at lazy="1", with lib/Widget.js STILL never listed as its own importer
# (defs="2" — Widget.js's class AND barrel.js's getter both match the unqualified name — but only ONE of
# those two def files, barrel.js, is also a genuine importer of the OTHER).
#
# LB-H's own webpack re-check (r10-gitnexus.md §5) measured `--impact=ChunkGraph` returning importers="…"
# with no trace of lib/index.js — kParserVer 71 fixed the TOP-LEVEL half of that omission (require() as a
# call expression was invisible at ANY depth) and left the function-body half as a disclosed floor
# (ingest.cpp's kJsImportContainers comment, pre-72: "a require inside a function body stays uncaptured").
# webpack's own lib/index.js is a LAZY-GETTER BARREL — every export is `get X() { return require("./X"); }`
# — which is exactly why the floor mattered: the file the round wanted --impact to name was the one shape
# kParserVer 71 could not reach. This gate's `lazyimporter.js` arm is the minimal reproduction of that shape
# (see the file's own header comment for why it avoids the getter's-name == the module's-name collision
# that keeps the REAL lib/index.js off ChunkGraph's importer tier for an orthogonal, undiagnosed reason).
#
# Usage:  bash test/impactimportcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/impactimportcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/impactimportfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/impactimportfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "impactimportcheck: BIN=$BIN  CORPUS=test/impactimportfix"

# ── #0 PRESENCE GUARDS (CONTRIBUTING §2, "a gate that cannot observe what it asserts") ─────────────────
# Every assertion below is about files that must literally spell a require/import of ./Widget. If the
# fixture ever loses them the gate would pass by measuring nothing, so assert the fixture first.
req_n="$( grep -lE 'require\("\./Widget"\)' "$FIX"/lib/*.js 2>/dev/null | wc -l | tr -d ' ' )"
esm_n="$( grep -lE 'import Widget from "\./Widget\.js"' "$FIX"/lib/*.js 2>/dev/null | wc -l | tr -d ' ' )"
{ [ "$req_n" = 6 ] && [ "$esm_n" = 1 ]; } \
    && ok "fixture guard: 6 CommonJS require sites + 1 ESM import site of ./Widget on disk" \
    || no "fixture guard: expected 6 require + 1 ESM importer of ./Widget, found $req_n + $esm_n"
grep -q 'new Widget(' "$FIX/lib/user.js" \
    && ok "fixture guard: user.js is the one importer that also CALLS Widget" \
    || no "fixture guard: user.js no longer constructs Widget — the two-tier case is inert"
# lazyimporter.js's require sits INSIDE lazyBuild()'s body, never at the top level — the presence guard a
# gate that "cannot observe what it asserts" needs (CONTRIBUTING §2): assert the require is NOT a top-level
# statement before trusting any lazy="…" assertion built on it.
grep -qE '^\s*const\s+Widget\s*=\s*require\("\./Widget"\);' "$FIX/lib/lazyimporter.js" \
    && no "fixture guard: lazyimporter.js's require is at the TOP LEVEL — the lazy arm below is inert" \
    || ok "fixture guard: lazyimporter.js's require is not a top-level statement"
grep -qE '^\s*cachedWidget = require\("\./Widget"\);\s*$' "$FIX/lib/lazyimporter.js" \
    && ok "fixture guard: lazyimporter.js's require sits on its own line inside lazyBuild()'s body" \
    || no "fixture guard: lazyimporter.js drifted — the lazy arm below cannot trust its shape"
# barrel.js's getter must be literally named "Widget" (the same-named-symbol-definition half of the bug)
# AND its require must sit inside that getter's body, never at the top level (the genuine-import half).
grep -qE '^\s*get Widget\(\)' "$FIX/lib/barrel.js" \
    && ok "fixture guard: barrel.js defines a getter literally named Widget" \
    || no "fixture guard: barrel.js's getter is not named Widget — the same-named-def half is inert"
grep -qE '^\s*const\s+Widget\s*=\s*require\("\./Widget"\);' "$FIX/lib/barrel.js" \
    && no "fixture guard: barrel.js's require is at the TOP LEVEL — the getter-body arm below is inert" \
    || ok "fixture guard: barrel.js's require is not a top-level statement"
grep -qE '^\s*return require\("\./Widget"\);\s*$' "$FIX/lib/barrel.js" \
    && ok "fixture guard: barrel.js's require sits on its own line inside the getter's body" \
    || no "fixture guard: barrel.js drifted — the barrel arm below cannot trust its shape"

i(){ perl -e 'alarm 30; exec @ARGV' "$BIN" "$FIX" --impact="$1" --no-cache "${@:2}" 2>/dev/null; }
# The legend now SPELLS the row shape (`<f via="import" p="…"/>`), so a naive grep for a row matches the
# documentation of the row. Every row-level assertion runs against the ELEMENT, not the whole document.
body(){ printf '%s' "$1" | sed 's/^.*<impact /<impact /'; }
attr(){ printf '%s' "$2" | grep -oE "(^|[^_a-z])$1=\"[^\"]*\"" | head -1 | grep -oE '"[^"]*"' | tr -d '"'; }

OUT_W="$( i Widget )"

# ── #1 EXTRACTION: `require("./x")` is a file→file dependency edge, top-level OR function-body ─────────
# The fixture is seven importers of one module; pre-71 the whole dependency graph over it was empty.
# L1 (2026-09-19): the CLI default legend is compact, whose root tag leads with schema=; #1 pins `<deps files=`, and #6/#8
# read the FULL legend's prose — those three documents ask for the full legend.
DEPS="$( perl -e 'alarm 30; exec @ARGV' "$BIN" "$FIX" --deps --no-cache --legend=full 2>/dev/null )"
DEPS_FILES="$( printf '%s' "$DEPS" | grep -oE '<deps files="[0-9]+"' | grep -oE '[0-9]+' )"
[ "${DEPS_FILES:-0}" -ge 7 ] \
    && ok "--deps sees the require() edges: files=$DEPS_FILES (>=7 importers with a dependency edge)" \
    || no "--deps files=${DEPS_FILES:-unset} — require(\"./Widget\") is not producing an include edge"

# ── #2 the import tier exists, is complete, and is COUNTED SEPARATELY ─────────────────────────────────
IMPORTERS="$( attr importers "$OUT_W" )"
REACHES="$(   attr reaches   "$OUT_W" )"
[ "$IMPORTERS" = 7 ] \
    && ok "--impact=Widget: importers=7 (alpha, beta, gamma, user, delta, lazyimporter, barrel — one tier)" \
    || no "--impact=Widget: importers='$IMPORTERS', expected 7"
[ "$REACHES" = 1 ] \
    && ok "--impact=Widget: reaches=1 — CALL reach is unchanged, the two reach kinds are never summed" \
    || no "--impact=Widget: reaches='$REACHES', expected 1 (import reach must not leak into it)"

for f in alpha beta gamma user delta; do
    body "$OUT_W" | grep -qE "<f via=\"import\" p=\"lib/$f\.js\" lazy=\"0\"/>" \
        && ok "--impact=Widget: import-tier row for lib/$f.js, lazy=\"0\" (top-level require/import)" \
        || no "--impact=Widget: missing <f via=\"import\" p=\"lib/$f.js\" lazy=\"0\"/>"
done
# ── #2b kParserVer 72: the FUNCTION-BODY require gets its own row, marked lazy="1" ──────────────────────
body "$OUT_W" | grep -qE '<f via="import" p="lib/lazyimporter\.js" lazy="1"/>' \
    && ok "--impact=Widget: import-tier row for lib/lazyimporter.js, lazy=\"1\" (function-body require)" \
    || no "--impact=Widget: missing <f via=\"import\" p=\"lib/lazyimporter.js\" lazy=\"1\"/> — the lazy require was not captured, or not marked lazy"
body "$OUT_W" | grep -qE '<f via="import" p="lib/Widget\.js"' \
    && no "--impact=Widget: the DEFINING file is listed as its own importer" \
    || ok "--impact=Widget: the defining file is not listed as an importer of itself"
# ── #2c barrel-exclusion lane: a def file (defines a getter named Widget) that ALSO genuinely imports a
# DIFFERENT def file (the real Widget.js) must still appear as an importer — the red-first case this lane
# fixes. defs="2" confirms the resolver treated barrel.js's getter as a second definition of "Widget" (the
# condition that used to trigger the wholesale exclusion); the row below confirms it is no longer excluded.
DEFS="$( attr defs "$OUT_W" )"
[ "$DEFS" = 2 ] \
    && ok "--impact=Widget: defs=2 — Widget.js's class AND barrel.js's getter both match the unqualified name" \
    || no "--impact=Widget: defs='$DEFS', expected 2 (barrel.js's getter no longer resolves as a same-named def — fixture drifted)"
body "$OUT_W" | grep -qE '<f via="import" p="lib/barrel\.js" lazy="1"/>' \
    && ok "--impact=Widget: import-tier row for lib/barrel.js, lazy=\"1\" — a same-named-def file that also imports the OTHER def file" \
    || no "--impact=Widget: missing <f via=\"import\" p=\"lib/barrel.js\" lazy=\"1\"/> — the barrel-getter-named-after-reexport misfire is back"
# ── #2d no double-count: barrel.js earns exactly ONE row, not two (once as "importer", once for its own def) ─
BARREL_ROWS="$( body "$OUT_W" | grep -oE '<f via="import" p="lib/barrel\.js"[^/]*/>' | wc -l | tr -d ' ' )"
[ "$BARREL_ROWS" = 1 ] \
    && ok "--impact=Widget: lib/barrel.js appears exactly once in the import tier (no double-count)" \
    || no "--impact=Widget: lib/barrel.js appears $BARREL_ROWS times in the import tier, expected 1"

# ── #3 the two tiers stay distinct in the ROW space too ───────────────────────────────────────────────
# user.js is in both: as the SYMBOL `build` in the call-reach rows, as the FILE in the import rows. The
# symbol-row count must still equal shown=, i.e. no <f> row was counted into the primary listing.
S_ROWS="$( body "$OUT_W" | grep -oE '<s t=' | wc -l | tr -d ' ' )"
SHOWN="$( attr shown "$OUT_W" )"
{ [ "$S_ROWS" = "$SHOWN" ] && [ "$S_ROWS" = 1 ]; } \
    && ok "--impact=Widget: shown=1 and exactly 1 <s> row — import rows are outside the paged listing" \
    || no "--impact=Widget: <s> rows=$S_ROWS vs shown=$SHOWN (expected 1 and 1)"
# 0.6.5: the listing's first row states its hop depth (d="1": build calls Widget directly) — test/impactdepthcheck.sh.
printf '%s' "$OUT_W" | grep -qE '<s t="fn" n="build" p="lib/user\.js:7" d="1"/>' \
    && ok "--impact=Widget: user.js appears as the SYMBOL build in the call tier" \
    || no "--impact=Widget: the call-reach row for build (lib/user.js:7) is gone"

# ── #4 pageview.h rule 6: a secondary listing discloses shown_<noun>=/<noun>_capped=, always paired ────
SI="$( attr shown_importers "$OUT_W" )"
IC="$( attr importers_capped "$OUT_W" )"
{ [ "$SI" = 7 ] && [ "$IC" = 0 ]; } \
    && ok "--impact=Widget: shown_importers=7 importers_capped=0 (complete listing, pair always emitted)" \
    || no "--impact=Widget: shown_importers='$SI' importers_capped='$IC', expected 7 and 0"

# ── #5 an EMPTY import tier is a measurement, not a missing attribute ─────────────────────────────────
OUT_O="$( i lonely --legend=full )"
{ [ "$( attr importers "$OUT_O" )" = 0 ] && [ "$( attr shown_importers "$OUT_O" )" = 0 ] \
    && [ "$( attr importers_capped "$OUT_O" )" = 0 ]; } \
    && ok "--impact=lonely: importers=0 shown_importers=0 importers_capped=0 (nobody imports orphan.js)" \
    || no "--impact=lonely: the zero case must still emit all three attributes — got: $( printf '%s' "$OUT_O" | grep -oE '<impact [^>]*>' )"
body "$OUT_O" | grep -qE '<f via="import"' \
    && no "--impact=lonely: emitted an import row for a file nothing imports" \
    || ok "--impact=lonely: no import rows"

# ── #6 the legend names the tier IN BAND (G4/honesty: the reader must not need --help) ────────────────
# Asserted on the ZERO-importer output on purpose: that run emits no <f> row at all, so a `via="import"`
# anywhere in it can only have come from the legend. A legend check on OUT_W would pass off the rows.
{ printf '%s' "$OUT_O" | grep -q 'via="import"' \
    && printf '%s' "$OUT_O" | grep -q 'not call reach'; } \
    && ok "legend: the import tier is described in band, and says it is not call reach" \
    || no "legend: --impact's doc comment does not describe the import tier as a separate, weaker reach"

# ── #7 JSON dialect carries the same facts under the same names (§A3a: ONE keyset) ────────────────────
JS_OUT="$( perl -e 'alarm 30; exec @ARGV' "$BIN" "$FIX" --impact=Widget --json --no-cache 2>/dev/null )"
{ printf '%s' "$JS_OUT" | grep -q '"importers":7' \
    && printf '%s' "$JS_OUT" | grep -q '"shown_importers":7' \
    && printf '%s' "$JS_OUT" | grep -q '"importers_capped":false' \
    && printf '%s' "$JS_OUT" | grep -q '"reaches":1' \
    && printf '%s' "$JS_OUT" | grep -q '"import_reach":\[' \
    && printf '%s' "$JS_OUT" | grep -q '{"via":"import","p":"lib/alpha.js","lazy":false}'; } \
    && ok "--json: importers/shown_importers/importers_capped/import_reach mirror the XML attrs" \
    || no "--json: the import tier is missing or renamed — got: $( printf '%s' "$JS_OUT" | head -c 400 )"
# ── #7b kParserVer 72: the JSON dialect's per-row lazy carries JSON booleans, not XML's "0"/"1" ─────────
printf '%s' "$JS_OUT" | grep -q '{"via":"import","p":"lib/lazyimporter.js","lazy":true}' \
    && ok "--json: lazyimporter.js's row carries \"lazy\":true" \
    || no "--json: lazyimporter.js's row missing or not \"lazy\":true — got: $( printf '%s' "$JS_OUT" | grep -oE '\{"via":"import"[^}]*\}' )"
# ── #7c barrel-exclusion lane: the JSON dialect must not diverge from XML on the barrel row either ──────
printf '%s' "$JS_OUT" | grep -q '{"via":"import","p":"lib/barrel.js","lazy":true}' \
    && ok "--json: barrel.js's row carries \"lazy\":true" \
    || no "--json: barrel.js's row missing or not \"lazy\":true — got: $( printf '%s' "$JS_OUT" | grep -oE '\{"via":"import"[^}]*\}' )"
if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$JS_OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null \
        && ok "--json: parses as JSON" || no "--json: invalid JSON"
fi

# ── #8 --format=columnar discloses the COUNT (its row form is the symbol table only) ──────────────────
COL="$( perl -e 'alarm 30; exec @ARGV' "$BIN" "$FIX" --impact=Widget --format=columnar --no-cache --legend=full 2>/dev/null )"
[ "$( attr importers "$COL" )" = 7 ] \
    && ok "--format=columnar: importers=7 on the root (count disclosed even where rows are not emitted)" \
    || no "--format=columnar: importers= missing from the columnar root"
printf '%s' "$COL" | grep -q 'import-tier rows are not emitted in this form' \
    && ok "--format=columnar: the legend says the count is there and the rows are not" \
    || no "--format=columnar: nothing in band explains that the import ROWS are absent in this form"
body "$COL" | grep -q '<f via="import"' \
    && no "--format=columnar: emitted <f> rows the columnar legend says are absent" \
    || ok "--format=columnar: no <f> rows, as the legend states"

# ── #8b the MCP twin carries the tier too (the §B4 echo-site class: a marker landing on one surface) ──
MCP_OUT="$( printf '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"impact","arguments":{"path":"%s","symbol":"Widget"}}}\n' "$FIX" \
            | perl -e 'alarm 60; exec @ARGV' "$BIN" --mcp 2>/dev/null | tail -1 )"
{ printf '%s' "$MCP_OUT" | grep -q 'importers=\\"7\\"' \
    && printf '%s' "$MCP_OUT" | grep -q 'shown_importers=\\"7\\"' \
    && printf '%s' "$MCP_OUT" | grep -q 'importers_capped=\\"0\\"' \
    && printf '%s' "$MCP_OUT" | grep -q 'p=\\"lib/alpha.js\\"' \
    && printf '%s' "$MCP_OUT" | grep -q 'p=\\"lib/lazyimporter.js\\" lazy=\\"1\\"' \
    && printf '%s' "$MCP_OUT" | grep -q 'p=\\"lib/barrel.js\\" lazy=\\"1\\"'; } \
    && ok "MCP impact verb: same importers=/shown_importers=/importers_capped=/lazy= and the same rows" \
    || no "MCP impact verb diverges from the CLI on the import tier — got: $( printf '%s' "$MCP_OUT" | head -c 400 )"

# ── #9 the cap is a DEFAULT that discloses, measured on this repo (src/model.h has 60+ includers) ─────
OUT_CAP="$( perl -e 'alarm 60; exec @ARGV' "$BIN" "$ROOT" --impact=IngestResult 2>/dev/null )"
CAP_N="$( attr importers "$OUT_CAP" )"
CAP_S="$( attr shown_importers "$OUT_CAP" )"
CAP_C="$( attr importers_capped "$OUT_CAP" )"
if [ -n "$CAP_N" ] && [ "$CAP_N" -gt 40 ]; then
    { [ "$CAP_S" = 40 ] && [ "$CAP_C" = 1 ]; } \
        && ok "cap: importers=$CAP_N over 40 → shown_importers=40 importers_capped=1 (default, disclosed)" \
        || no "cap: importers=$CAP_N but shown_importers=$CAP_S importers_capped=$CAP_C (expected 40 / 1)"
    ROWS_CAP="$( body "$OUT_CAP" | grep -oE '<f via="import"' | wc -l | tr -d ' ' )"
    if [ "$ROWS_CAP" = 40 ]; then ok "cap: exactly 40 import rows printed"; else no "cap: printed $ROWS_CAP import rows, expected 40"; fi
else
    no "cap arm inert: --impact=IngestResult on this repo reported importers='$CAP_N', so the >40 case was never exercised"
fi

# ── #9b RANK BEFORE THE CAP + --limit REACH (cut-fix C, 2026-09-23) ─────────────────────────────────────
# The tier used to sort by path and cut at 40, and --limit could not reach it, so on a >40 tier the files that
# survived were the alphabetically-first ones and the rest were one guess away. Now the most-imported importers
# lead (each file's own importer count), and --limit sizes the tier like the symbol rows. The sandbox makes path
# order and relevance disagree: 45 leaf importers pkg/a_NN.py (nobody imports them) sort before 3 pkg/z_N.py,
# each imported by 4 other files. RED on 60b65f02 (the three arms below); GREEN on cut-fix C.
# lane lean-trio (idea #6): 60 unrelated importers (pkg/x_NN.py, importing pkg/other.py) keep hub.py BELOW the umbrella
# line (imported by fewer than half the files that import anything), so these arms keep their premise; arm #9e builds the
# same sandbox WITHOUT them, where hub.py is an umbrella and the tier becomes a count.
mkhub(){ # $1 dir  $2 extra unrelated importers
mkdir -p "$1/pkg"
python3 - "$1" "$2" <<'PY'
import os, sys
d = os.path.join( sys.argv[1], "pkg" )
open( os.path.join( d, "other.py" ), "w" ).write( "def otherFn( x ):\n    return x\n" )
for k in range( int( sys.argv[2] ) ):
    open( os.path.join( d, "x_%02d.py" % k ), "w" ).write( "from pkg.other import otherFn\n\ndef use_x_%02d( ):\n    return otherFn( %d )\n" % ( k, k ) )
open( os.path.join( d, "__init__.py" ), "w" ).write( "" )
open( os.path.join( d, "hub.py" ), "w" ).write( "def importHubFn( x ):\n    return x\n" )
for i in range( 45 ):
    open( os.path.join( d, "a_%02d.py" % i ), "w" ).write( "from pkg.hub import importHubFn\n\ndef use_a_%02d( ):\n    return importHubFn( %d )\n" % ( i, i ) )
for i in range( 3 ):
    open( os.path.join( d, "z_%d.py" % i ), "w" ).write( "from pkg.hub import importHubFn\n\ndef use_z_%d( ):\n    return importHubFn( %d )\n" % ( i, i ) )
for j in range( 4 ):
    open( os.path.join( d, "d_%d.py" % j ), "w" ).write( "".join( "from pkg.z_%d import use_z_%d\n" % ( i, i ) for i in range( 3 ) ) )
PY
}
RS="$( mktemp -d )"
mkhub "$RS" 60
ri(){ perl -e 'alarm 30; exec @ARGV' "$BIN" "$RS" --impact=importHubFn --no-cache "$@" 2>/dev/null; }
R_DEF="$( ri )"
R_ALL="$( ri --limit=100 )"
zRows(){ body "$1" | grep -oE '<f via="import" p="pkg/z_[0-9]\.py"' | wc -l | tr -d ' '; }
{ [ "$( attr importers "$R_DEF" )" = 48 ] && [ "$( attr shown_importers "$R_DEF" )" = 40 ] && [ "$( attr importers_capped "$R_DEF" )" = 1 ]; } \
    && ok "rank: presence guard — importers=48 over the 40 cap, shown_importers=40 importers_capped=1" \
    || no "rank: fixture broken — importers=$( attr importers "$R_DEF" ) shown_importers=$( attr shown_importers "$R_DEF" )"
[ "$( zRows "$R_DEF" )" = 3 ] \
    && ok "rank: the default 40-file page keeps all 3 most-imported importers (they sort LAST by path)" \
    || no "rank: the default page kept $( zRows "$R_DEF" ) of the 3 most-imported importers — the cap cut the head"
body "$R_DEF" | grep -oE '<f via="import" p="[^"]*"' | head -3 | grep -c 'pkg/z_' | grep -qx 3 \
    && ok "rank: the most-imported importers lead the tier" \
    || no "rank: the tier does not lead with the most-imported files: $( body "$R_DEF" | grep -oE '<f via="import" p="[^"]*"' | head -1 )"
{ [ "$( attr shown_importers "$R_ALL" )" = 48 ] && [ "$( attr importers_capped "$R_ALL" )" = 0 ] \
  && [ "$( body "$R_ALL" | grep -oE '<f via="import"' | wc -l | tr -d ' ' )" = 48 ]; } \
    && ok "reach: --limit=100 serves the whole 48-file tier (shown_importers=48 importers_capped=0) — the cut is one known call away" \
    || no "reach: --limit=100 left the tier at shown_importers=$( attr shown_importers "$R_ALL" ) — --limit cannot reach it"
# ── #9e UMBRELLA (lane lean-trio, idea #6): the same hub with no unrelated importers — imported by 48 of the 52 files
# that import anything — is an umbrella: its importers are a COUNT (shown_importers=0, importers_umbrella=1), the cut
# names its call, and an explicit --limit still lists the rows. RED on main 0852bc0f: 40 rows, no importers_umbrella=.
RU="$( mktemp -d )"
mkhub "$RU" 0
U_DEF="$( perl -e 'alarm 30; exec @ARGV' "$BIN" "$RU" --impact=importHubFn --no-cache 2>/dev/null )"
U_ALL="$( perl -e 'alarm 30; exec @ARGV' "$BIN" "$RU" --impact=importHubFn --no-cache --limit=100 2>/dev/null )"
{ [ "$( attr importers "$U_DEF" )" = 48 ] && [ "$( attr shown_importers "$U_DEF" )" = 0 ] && [ "$( attr importers_umbrella "$U_DEF" )" = 1 ] \
  && [ "$( attr importers_next "$U_DEF" )" = "--impact=importHubFn --limit=48" ] && [ "$( body "$U_DEF" | grep -c '<f via="import"' )" = 0 ]; } \
    && ok "umbrella: importers=48 is a count (shown_importers=0 importers_umbrella=1), importers_next= names the listing call" \
    || no "umbrella: expected a counted tier; got importers=$( attr importers "$U_DEF" ) shown_importers=$( attr shown_importers "$U_DEF" ) umbrella=$( attr importers_umbrella "$U_DEF" )"
[ "$( body "$U_ALL" | grep -oE '<f via="import"' | wc -l | tr -d ' ' )" = 48 ] \
    && ok "umbrella: an explicit --limit=100 lists all 48 importer rows" \
    || no "umbrella: --limit=100 did not list the 48 rows"
[ -z "$( attr importers_umbrella "$R_DEF" )" ] \
    && ok "umbrella: a hub imported by under half the importing files is not one (no importers_umbrella=)" \
    || no "umbrella: the 60-extra sandbox was called an umbrella"
rm -rf "$RU"
# ── #9f FILE ROLLUP (lane lean-trio, idea #6): beside a CUT symbol window, <files files= shown_files= files_capped=>
# rolls the WHOLE reach set up by file before the symbol rows: files= counts every reaching file, the default page lists
# 20 rf rows with files_next= when cut, and pasting files_next= names every file (as rf rows while the symbol window is
# still cut, as the symbol rows' own p= once it is not). An UNCUT symbol window carries no rollup: its rows already name
# every file. Noun-prefixed counts only, so the root's bare shown=/capped= stay the only ones (emittertruthcheck reads
# the last shown= on the line). RED on main 0852bc0f: no <files> element.
F_ROOT="$( body "$R_DEF" | grep -o '<files [^>]*>' | head -1 )"
F_N="$( attr files "$F_ROOT" )"; F_SH="$( attr shown_files "$F_ROOT" )"
F_DEF="$( body "$R_DEF" | grep -o '<rf ' | wc -l | tr -d ' ' )"
if [ "$( attr capped "$R_DEF" )" = 1 ] && [ -n "$F_N" ] && [ "$F_N" -gt 20 ] && [ "$F_SH" = 20 ] && [ "$F_DEF" = 20 ] \
   && [ "$( attr files_capped "$F_ROOT" )" = 1 ] && [ "$( attr files_next "$F_ROOT" )" = "--impact=importHubFn --limit=$F_N" ] \
   && ! printf '%s' "$F_ROOT" | grep -qE ' (shown|capped|n)="'; then
    ok "rollup: a cut window opens with <files files=$F_N shown_files=20 files_capped=1> and files_next= names the listing call"
else
    no "rollup: expected <files files>20 shown_files=20 files_capped=1 files_next=> beside a cut window; got '$F_ROOT' with $F_DEF rf rows"
fi
R_FN="$( ri --limit="${F_N:-0}" )"
if [ "$( attr capped "$R_FN" )" = 1 ]; then
    F_PASTE="$( body "$R_FN" | grep -o '<rf ' | wc -l | tr -d ' ' )"
else
    F_PASTE="$( body "$R_FN" | grep -oE '<s [^>]*p="[^":]*' | sed 's/.*p="//' | sort -u | wc -l | tr -d ' ' )"
fi
[ -n "$F_N" ] && [ "$F_PASTE" = "$F_N" ] \
    && ok "rollup: pasting files_next= names all $F_N files" \
    || no "rollup: pasting files_next= named $F_PASTE files (want ${F_N:-?})"
body "$R_DEF" | grep -o '<rf [^>]*>' | head -1 | grep -qE 'syms="[0-9]+" d="1"' \
    && ok "rollup: the first rf row is a depth-1 file (ordered by d= first)" \
    || no "rollup: the first rf row is not depth 1: $( body "$R_DEF" | grep -o '<rf [^>]*>' | head -1 )"
[ "$( body "$R_DEF" | sed 's/<s t=.*//' | grep -c '<files ' )" = 1 ] \
    && ok "rollup: the files element precedes the symbol rows" \
    || no "rollup: the files element does not precede the symbol rows"
{ [ "$( attr capped "$R_ALL" )" = 0 ] && ! body "$R_ALL" | grep -q '<files '; } \
    && ok "rollup: an uncut symbol window (--limit=100) carries no files element" \
    || no "rollup: --limit=100 capped=$( attr capped "$R_ALL" ), files element present=$( body "$R_ALL" | grep -c '<files ' )"
ri --json | grep -qE '"files":\{"files":[0-9]+,"shown_files":20,"files_capped":true,"files_next":"--impact=importHubFn --limit=' \
    && ok "rollup: the --json dialect carries the same rollup object" \
    || no "rollup: --json lacks the files object beside a cut window"
ri --limit=100 --json | grep -q '"files":{' \
    && no "rollup: --json carries a files object beside an uncut window" \
    || ok "rollup: --json carries no files object beside an uncut window"

# ── #9c THE CUT NAMES ITS CALL (cut-fix E, 2026-09-24) ──────────────────────────────────────────────────
# A cut tier was a DEAD-END cut (answer-completeness §1.3/§5.8): counted, and no call named that serves the rest.
# importers_next= on a cut root (the root's next= is --safe-delete's), in the XML and the JSON dialect; pasting it
# serves the whole tier; absent on an uncut tier. RED on 9936ba4e (no importers_next= anywhere).
INX="$( attr importers_next "$R_DEF" )"
[ "$INX" = "--impact=importHubFn --limit=48" ] \
    && ok "next: the cut tier names its call, importers_next=\"$INX\"" \
    || no "next: the cut tier carries importers_next='$INX' (want --impact=importHubFn --limit=48)"
R_NX="$( perl -e 'alarm 30; exec @ARGV' "$BIN" "$RS" $INX --no-cache 2>/dev/null )"
{ [ "$( attr shown_importers "$R_NX" )" = 48 ] && [ "$( attr importers_capped "$R_NX" )" = 0 ] && [ -z "$( attr importers_next "$R_NX" )" ]; } \
    && ok "next: pasting importers_next= serves all 48 importers, and that uncut answer carries no importers_next=" \
    || no "next: pasting importers_next= gave shown_importers=$( attr shown_importers "$R_NX" ) importers_next='$( attr importers_next "$R_NX" )'"
ri --json | grep -q '"importers_next":"--impact=importHubFn --limit=48"' \
    && ok "next: the --json dialect carries the same importers_next" \
    || no "next: --json lacks \"importers_next\" on the cut tier"
# --format=columnar serves the import tier as its count only, and its lens= names what it withholds that the XML root
# carries. importers_next= is on the XML root only when the tier is cut, so lens= names it exactly then. RED on
# 17963410: the cut tier's lens= named only shown_importers,importers_capped.
LCUT="$( attr lens "$( ri --format=columnar )" )"; LALL="$( attr lens "$( ri --limit=100 --format=columnar )" )"
{ [ "$LCUT" = "shown_importers,importers_capped,importers_next" ] && [ "$LALL" = "shown_importers,importers_capped" ]; } \
    && ok "next: --format=columnar's lens= names importers_next on the cut tier, and not on the uncut one" \
    || no "next: --format=columnar lens='$LCUT' on the cut tier (want shown_importers,importers_capped,importers_next), lens='$LALL' uncut (want shown_importers,importers_capped)"
rm -rf "$RS"

# ── #9d A LONG SELECTOR KEEPS ITS CALL (knob-honesty-068) ───────────────────────────────────────────────
# sizeImportTier offered importers_next= only while the invocation was <= kNextAttrMaxBytes (120 B), so a cut tier
# whose symbol name is long lost its ONLY continuation with no marker: importers_capped="1" and nothing that serves
# the rest — the silent drop the 2026-09-25 ruling (138b383c: "emit the FULL next=") removed everywhere else. Same
# 48-importer shape as #9b with a 110-character function name: `--impact=NAME --limit=48` is 130 B. RED on 255dc199
# (no importers_next= on the XML root, the --json dialect, or the MCP twin).
LS="$( mktemp -d )"; mkdir -p "$LS/pkg"
LONGN="importHubFn_$( printf 'x%.0s' $( seq 1 98 ) )"
python3 - "$LS" "$LONGN" <<'PY'
import os, sys
d, n = os.path.join( sys.argv[1], "pkg" ), sys.argv[2]
open( os.path.join( d, "__init__.py" ), "w" ).write( "" )
open( os.path.join( d, "hub.py" ), "w" ).write( "def %s( x ):\n    return x\n" % n )
for i in range( 48 ):
    open( os.path.join( d, "a_%02d.py" % i ), "w" ).write( "from pkg.hub import %s\n\ndef use_a_%02d( ):\n    return %s( %d )\n" % ( n, i, n, i ) )
PY
rl(){ perl -e 'alarm 30; exec @ARGV' "$BIN" "$LS" --impact="$LONGN" --no-cache "$@" 2>/dev/null; }
L_DEF="$( rl )"
WANT_L="--impact=$LONGN --limit=48"
{ [ "${#LONGN}" = 110 ] && [ "${#WANT_L}" -gt 120 ] && [ "$( attr importers_capped "$L_DEF" )" = 1 ]; } \
    && ok "long: presence guard — a ${#LONGN}-char selector, a ${#WANT_L} B call (> 120), importers_capped=1" \
    || no "long: fixture broken — name ${#LONGN} chars, call ${#WANT_L} B, importers_capped='$( attr importers_capped "$L_DEF" )'"
[ "$( attr importers_next "$L_DEF" )" = "$WANT_L" ] \
    && ok "long: the cut tier still names its call (importers_next= is ${#WANT_L} B, never dropped for length)" \
    || no "long: importers_next='$( attr importers_next "$L_DEF" )' on a cut tier (want the full ${#WANT_L} B call)"
L_NX="$( perl -e 'alarm 30; exec @ARGV' "$BIN" "$LS" $( attr importers_next "$L_DEF" ) --no-cache 2>/dev/null )"
{ [ "$( attr shown_importers "$L_NX" )" = 48 ] && [ "$( attr importers_capped "$L_NX" )" = 0 ]; } \
    && ok "long: pasting the long importers_next= serves all 48 importers" \
    || no "long: pasting importers_next= gave shown_importers='$( attr shown_importers "$L_NX" )'"
rl --json | grep -qF "\"importers_next\":\"$WANT_L\"" \
    && ok "long: the --json dialect carries the same full importers_next" \
    || no "long: --json lacks the full \"importers_next\" on the cut tier"
L_MCP="$( printf '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"impact","arguments":{"path":"%s","symbol":"%s"}}}\n' "$LS" "$LONGN" \
          | perl -e 'alarm 60; exec @ARGV' "$BIN" --mcp 2>/dev/null | tail -1 )"
printf '%s' "$L_MCP" | grep -qF "importers_next=\\\"$WANT_L\\\"" \
    && ok "long: the MCP impact twin carries the same full importers_next" \
    || no "long: MCP impact lacks importers_next on the cut tier: $( printf '%s' "$L_MCP" | grep -oE 'importers_[a-z]+=[^ ]+' | tr '\n' ' ' | cut -c1-200 )"
# negative twin: an UNCUT long tier carries no importers_next= (the follow-up rides a cut only)
[ -z "$( attr importers_next "$( rl --limit=100 )" )" ] \
    && ok "long: the uncut tier (--limit=100) carries no importers_next=" \
    || no "long: an uncut tier carries importers_next="
rm -rf "$LS"

# ── #10 determinism + well-formedness ─────────────────────────────────────────────────────────────────
A="$( i Widget )"; B="$( i Widget )"
if [ "$A" = "$B" ]; then ok "determinism: --impact=Widget byte-identical run-to-run"; else no "non-deterministic --impact output"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$OUT_W" | xmllint --noout - 2>/dev/null; then ok "xml well-formed"; else no "xml malformed"; fi
    if printf '%s' "$COL"   | xmllint --noout - 2>/dev/null; then ok "xml well-formed (columnar)"; else no "xml malformed (columnar)"; fi
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
