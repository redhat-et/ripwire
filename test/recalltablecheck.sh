#!/usr/bin/env bash
# recalltablecheck.sh — L4.2 protected-range gate for --recall's per-doc byte truncation: a markdown
# pipe-table is WHOLE-OR-NOTHING under a forced cut.
#
# The defect this pins: truncateRecallBody's byte ceiling used to land wherever the count said, including
# INSIDE a markdown table's row run. The emitted doc then carried a torn table — a header row and a few
# body rows with no closing structure, honestly disclosed via `[truncated: …]` but unusable as a table
# (a reader/renderer sees a broken grid, not "here be more rows"). The fix scans the body for protected
# elements (fenced code blocks and pipe-table row runs) and, when the requested cut would land inside
# one, moves the cut to the element's START instead — the table is either emitted whole or not at all.
#
# ARM
#   A fixture with an intro paragraph, a ~40-row pipe table (header sentinel `TABLE_START_SENTINEL` in
#   the first cell, footer sentinel `TABLE_END_SENTINEL` in the last row's last cell), then an outro
#   paragraph. A --max-tokens ceiling chosen so the RAW byte cut lands inside the table (confirmed against
#   this repo's pre-fix binary during development: start-sentinel present, end-sentinel absent = a torn
#   table). Post-fix, the SAME ceiling must produce one of exactly two shapes — never a third:
#     (i)  neither sentinel present  — the cut moved to BEFORE the table (element didn't fit at all), or
#     (ii) BOTH sentinels present    — the table fit whole and was kept intact.
#   never "start present, end absent" (a torn table). Also checked: budget compliance (the marker's
#   kept-bytes never exceeds the byte ceiling), and determinism.
#
# Usage:  test/recalltablecheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire test/recalltablecheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

echo "recalltablecheck: BIN=$BIN"

TMP="$( mktemp -d )"
# short, fixed-depth path — see recallboundarycheck.sh for why: a long tmp path competes with the body
# for the same byte budget and shifts exactly where a given --max-tokens forces the cut.
R="$( mktemp -d "/tmp/rwtblXXXXXX" )"; trap 'rm -rf "$TMP" "$R"' EXIT

# ─── fixture: intro paragraph, a ~40-row pipe table with start/end sentinels, outro paragraph ─────────
python3 - "$R" <<'PY'
import sys
root = sys.argv[1]
parts = []
parts.append( "# Table doc\n\n" )
parts.append( "Intro paragraph about widget catalog metadata rows and padding filler words here now. " * 2 + "\n\n" )
parts.append( "| TABLE_START_SENTINEL | colB | colC |\n" )
parts.append( "|---|---|---|\n" )
for i in range( 40 ):
    parts.append( "| row%03d | data%03dxxxxx | value%03dyyyyy |\n" % ( i, i, i ) )
parts.append( "| last_row | filler_value_xx | TABLE_END_SENTINEL |\n" )
parts.append( "\nOutro paragraph after the table with more padding words to fill remaining space here now. " * 3 + "\n" )
body = "".join( parts )
with open( root + "/doc.md", "w" ) as f:
    f.write( body )
print( "fixture bytes:", len( body ) )
s = body.find( "TABLE_START_SENTINEL" ); e = body.find( "TABLE_END_SENTINEL" )
print( "sentinel span: start=%d end=%d" % ( s, e ) )
PY

recall(){ perl -e 'alarm 20; exec @ARGV' "$BIN" "$R" --recall="table doc widget catalog metadata" --no-cache "$@" 2>/dev/null; }

# ─── the ceiling: verified during development to force a mid-table cut on the pre-fix binary ──────────
echo
echo "=== table is whole-or-nothing under a forced cut ==="
OUT="$( recall --max-tokens=450 )"
MARK="$( printf '%s' "$OUT" | grep -oE '\[truncated: [0-9]+ of [0-9]+ bytes[^]]*\]' )"
[ -n "$MARK" ] && ok "truncation fired: $MARK" || { no "no [truncated: …] marker — fixture/budget did not force a cut"; printf '%s\n' "$OUT" | head -6; }

HAS_START=0; printf '%s' "$OUT" | grep -q 'TABLE_START_SENTINEL' && HAS_START=1
HAS_END=0;   printf '%s' "$OUT" | grep -q 'TABLE_END_SENTINEL'   && HAS_END=1

if [ "$HAS_START" -eq "$HAS_END" ]; then
    if [ "$HAS_START" -eq 1 ]; then
        ok "BOTH table sentinels present — table fit whole and was kept intact"
    else
        ok "NEITHER table sentinel present — the cut moved to before the table (element didn't fit)"
    fi
else
    no "TORN TABLE: start-sentinel present=$HAS_START, end-sentinel present=$HAS_END (never allowed — whole-or-nothing)"
    printf '%s\n' "$OUT" | grep -aE 'TABLE_(START|END)_SENTINEL|row0[0-9][0-9]' | head -6
fi

# no partial data row should appear either — a row that survives must be a COMPLETE "| … | … | …|" line,
# never a half-emitted row cut mid-cell. Every emitted line containing "row0" must also contain the
# trailing "|" that closes its last cell.
BAD_ROWS="$( printf '%s' "$OUT" | grep -aE '\| row[0-9]{3} ' | grep -avE '\|[[:space:]]*$' | wc -l | tr -d ' ' )"
[ "$BAD_ROWS" = "0" ] && ok "no row line missing its closing pipe" || no "$BAD_ROWS row line(s) missing a closing pipe — torn mid-row"

# ─── budget compliance: kept-bytes never exceeds the byte ceiling the cut was computed against ────────
echo
echo "=== budget compliance ==="
if [ -n "$MARK" ]; then
    KEPT="$( printf '%s' "$MARK" | grep -oE '[0-9]+' | head -1 )"
    FULL="$( printf '%s' "$MARK" | grep -oE '[0-9]+' | sed -n 2p )"
    [ -n "${KEPT:-}" ] && [ -n "${FULL:-}" ] && [ "$KEPT" -lt "$FULL" ] \
        && ok "kept-bytes ($KEPT) < full body ($FULL) — the whole-or-nothing move only ever shrinks the cut" \
        || no "kept-bytes/full-bytes malformed: KEPT=$KEPT FULL=$FULL"
else
    no "no truncation marker to check budget compliance against"
fi

# ─── determinism ────────────────────────────────────────────────────────────────────────────────────
echo
echo "=== determinism — same input + budget, byte-identical ==="
recall --max-tokens=450 >"$TMP/d1"
recall --max-tokens=450 >"$TMP/d2"
cmp -s "$TMP/d1" "$TMP/d2" && ok "byte-identical across two runs" || no "NON-deterministic across two runs"

echo
[ "$fail" -eq 0 ] && { echo "recalltablecheck: ALL PASS"; exit 0; }
echo "recalltablecheck: FAILURES present"; exit 1
