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
# FIXTURE test/impactimportfix — lib/Widget.js is imported by FIVE siblings and CALLED by exactly one:
#   alpha.js, beta.js, gamma.js  `require("./Widget")`, never call it   → import tier only
#   user.js                      `require("./Widget")` + `new Widget()` → BOTH tiers (file vs symbol)
#   delta.js                     ESM `import Widget from "./Widget.js"` → same tier as the requires
#   orphan.js                    imported by nobody                     → the importers="0" witness
# So the pre-fix binary shows reaches="1" and nothing else, and the post-fix binary must show reaches="1"
# STILL, plus importers="5".
#
# Usage:  bash test/impactimportcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/impactimportcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/impactimportfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
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
{ [ "$req_n" = 4 ] && [ "$esm_n" = 1 ]; } \
    && ok "fixture guard: 4 CommonJS require sites + 1 ESM import site of ./Widget on disk" \
    || no "fixture guard: expected 4 require + 1 ESM importer of ./Widget, found $req_n + $esm_n"
grep -q 'new Widget(' "$FIX/lib/user.js" \
    && ok "fixture guard: user.js is the one importer that also CALLS Widget" \
    || no "fixture guard: user.js no longer constructs Widget — the two-tier case is inert"

i(){ perl -e 'alarm 30; exec @ARGV' "$BIN" "$FIX" --impact="$1" --no-cache 2>/dev/null; }
attr(){ printf '%s' "$2" | grep -oE "(^|[^_a-z])$1=\"[^\"]*\"" | head -1 | grep -oE '"[^"]*"' | tr -d '"'; }

OUT_W="$( i Widget )"

# ── #1 EXTRACTION: `require("./x")` is a file→file dependency edge ─────────────────────────────────────
# The fixture is five importers of one module; pre-fix the whole dependency graph over it was empty.
DEPS="$( perl -e 'alarm 30; exec @ARGV' "$BIN" "$FIX" --deps --no-cache 2>/dev/null )"
DEPS_FILES="$( printf '%s' "$DEPS" | grep -oE '<deps files="[0-9]+"' | grep -oE '[0-9]+' )"
[ "${DEPS_FILES:-0}" -ge 5 ] \
    && ok "--deps sees the require() edges: files=$DEPS_FILES (>=5 importers with a dependency edge)" \
    || no "--deps files=${DEPS_FILES:-unset} — require(\"./Widget\") is not producing an include edge"

# ── #2 the import tier exists, is complete, and is COUNTED SEPARATELY ─────────────────────────────────
IMPORTERS="$( attr importers "$OUT_W" )"
REACHES="$(   attr reaches   "$OUT_W" )"
[ "$IMPORTERS" = 5 ] \
    && ok "--impact=Widget: importers=5 (alpha, beta, gamma, user, delta — require AND import, one tier)" \
    || no "--impact=Widget: importers='$IMPORTERS', expected 5"
[ "$REACHES" = 1 ] \
    && ok "--impact=Widget: reaches=1 — CALL reach is unchanged, the two reach kinds are never summed" \
    || no "--impact=Widget: reaches='$REACHES', expected 1 (import reach must not leak into it)"

for f in alpha beta gamma user delta; do
    printf '%s' "$OUT_W" | grep -qE "<f via=\"import\" p=\"lib/$f\.js\"/>" \
        && ok "--impact=Widget: import-tier row for lib/$f.js" \
        || no "--impact=Widget: missing <f via=\"import\" p=\"lib/$f.js\"/>"
done
printf '%s' "$OUT_W" | grep -qE '<f via="import" p="lib/Widget\.js"/>' \
    && no "--impact=Widget: the DEFINING file is listed as its own importer" \
    || ok "--impact=Widget: the defining file is not listed as an importer of itself"

# ── #3 the two tiers stay distinct in the ROW space too ───────────────────────────────────────────────
# user.js is in both: as the SYMBOL `build` in the call-reach rows, as the FILE in the import rows. The
# symbol-row count must still equal shown=, i.e. no <f> row was counted into the primary listing.
S_ROWS="$( printf '%s' "$OUT_W" | grep -oE '<s t=' | wc -l | tr -d ' ' )"
SHOWN="$( attr shown "$OUT_W" )"
{ [ "$S_ROWS" = "$SHOWN" ] && [ "$S_ROWS" = 1 ]; } \
    && ok "--impact=Widget: shown=1 and exactly 1 <s> row — import rows are outside the paged listing" \
    || no "--impact=Widget: <s> rows=$S_ROWS vs shown=$SHOWN (expected 1 and 1)"
printf '%s' "$OUT_W" | grep -qE '<s t="fn" n="build" p="lib/user\.js:7"/>' \
    && ok "--impact=Widget: user.js appears as the SYMBOL build in the call tier" \
    || no "--impact=Widget: the call-reach row for build (lib/user.js:7) is gone"

# ── #4 pageview.h rule 6: a secondary listing discloses shown_<noun>=/<noun>_capped=, always paired ────
SI="$( attr shown_importers "$OUT_W" )"
IC="$( attr importers_capped "$OUT_W" )"
{ [ "$SI" = 5 ] && [ "$IC" = 0 ]; } \
    && ok "--impact=Widget: shown_importers=5 importers_capped=0 (complete listing, pair always emitted)" \
    || no "--impact=Widget: shown_importers='$SI' importers_capped='$IC', expected 5 and 0"

# ── #5 an EMPTY import tier is a measurement, not a missing attribute ─────────────────────────────────
OUT_O="$( i lonely )"
{ [ "$( attr importers "$OUT_O" )" = 0 ] && [ "$( attr shown_importers "$OUT_O" )" = 0 ] \
    && [ "$( attr importers_capped "$OUT_O" )" = 0 ]; } \
    && ok "--impact=lonely: importers=0 shown_importers=0 importers_capped=0 (nobody imports orphan.js)" \
    || no "--impact=lonely: the zero case must still emit all three attributes — got: $( printf '%s' "$OUT_O" | grep -oE '<impact [^>]*>' )"
printf '%s' "$OUT_O" | grep -qE '<f via="import"' \
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
{ printf '%s' "$JS_OUT" | grep -q '"importers":5' \
    && printf '%s' "$JS_OUT" | grep -q '"shown_importers":5' \
    && printf '%s' "$JS_OUT" | grep -q '"importers_capped":false' \
    && printf '%s' "$JS_OUT" | grep -q '"reaches":1' \
    && printf '%s' "$JS_OUT" | grep -q '"import_reach":\[' \
    && printf '%s' "$JS_OUT" | grep -q '{"via":"import","p":"lib/alpha.js"}'; } \
    && ok "--json: importers/shown_importers/importers_capped/import_reach mirror the XML attrs" \
    || no "--json: the import tier is missing or renamed — got: $( printf '%s' "$JS_OUT" | head -c 400 )"
if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$JS_OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null \
        && ok "--json: parses as JSON" || no "--json: invalid JSON"
fi

# ── #8 --format=columnar discloses the COUNT (its row form is the symbol table only) ──────────────────
COL="$( perl -e 'alarm 30; exec @ARGV' "$BIN" "$FIX" --impact=Widget --format=columnar --no-cache 2>/dev/null )"
[ "$( attr importers "$COL" )" = 5 ] \
    && ok "--format=columnar: importers=5 on the root (count disclosed even where rows are not emitted)" \
    || no "--format=columnar: importers= missing from the columnar root"
printf '%s' "$COL" | grep -q 'import-tier rows are not emitted in this form' \
    && ok "--format=columnar: the legend says the count is there and the rows are not" \
    || no "--format=columnar: nothing in band explains that the import ROWS are absent in this form"
printf '%s' "$COL" | grep -q '<f via="import"' \
    && no "--format=columnar: emitted <f> rows the columnar legend says are absent" \
    || ok "--format=columnar: no <f> rows, as the legend states"

# ── #9 the cap is a DEFAULT that discloses, measured on this repo (src/model.h has 60+ includers) ─────
OUT_CAP="$( perl -e 'alarm 60; exec @ARGV' "$BIN" "$ROOT" --impact=IngestResult 2>/dev/null )"
CAP_N="$( attr importers "$OUT_CAP" )"
CAP_S="$( attr shown_importers "$OUT_CAP" )"
CAP_C="$( attr importers_capped "$OUT_CAP" )"
if [ -n "$CAP_N" ] && [ "$CAP_N" -gt 40 ]; then
    { [ "$CAP_S" = 40 ] && [ "$CAP_C" = 1 ]; } \
        && ok "cap: importers=$CAP_N over 40 → shown_importers=40 importers_capped=1 (default, disclosed)" \
        || no "cap: importers=$CAP_N but shown_importers=$CAP_S importers_capped=$CAP_C (expected 40 / 1)"
    ROWS_CAP="$( printf '%s' "$OUT_CAP" | grep -oE '<f via="import"' | wc -l | tr -d ' ' )"
    [ "$ROWS_CAP" = 40 ] && ok "cap: exactly 40 import rows printed" || no "cap: printed $ROWS_CAP import rows, expected 40"
else
    no "cap arm inert: --impact=IngestResult on this repo reported importers='$CAP_N', so the >40 case was never exercised"
fi

# ── #10 determinism + well-formedness ─────────────────────────────────────────────────────────────────
A="$( i Widget )"; B="$( i Widget )"
[ "$A" = "$B" ] && ok "determinism: --impact=Widget byte-identical run-to-run" || no "non-deterministic --impact output"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OUT_W" | xmllint --noout - 2>/dev/null && ok "xml well-formed" || no "xml malformed"
    printf '%s' "$COL"   | xmllint --noout - 2>/dev/null && ok "xml well-formed (columnar)" || no "xml malformed (columnar)"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
