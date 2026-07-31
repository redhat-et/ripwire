#!/usr/bin/env bash
# test/scorecardcheck.sh — scorecard script well-formedness and sanity gate
#
# Verifies that scripts/scorecard.sh produces:
#   1. Properly formatted markdown table (pipe-delimited columns)
#   2. Correct column count (Language | Symbols | Edges | Ambiguous | Amb Rate)
#   3. Sane ambiguity rates (between 0.0000 and 1.0000, or "N/A" for zero edges)
#   4. Deterministic output (two runs produce identical tables)
#   5. At least 2 language rows (meaningful coverage)
#
# Usage:
#   bash test/scorecardcheck.sh
#   CTXPACK_BIN=build/ctxpack bash test/scorecardcheck.sh
#   CTXPACK_BIN=asan/ctxpack  bash test/scorecardcheck.sh
#
# Exits 0 on ALL PASS, non-zero on any failure.

set -uo pipefail

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
SCORECARD="$ROOT/scripts/scorecard.sh"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

fail=0
ok() { printf '  PASS  %s\n' "$*"; }
no() { printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "error: no ctxpack binary at $BIN — build first"; exit 2; }
[ -x "$SCORECARD" ] || { echo "error: no scorecard script at $SCORECARD"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 required"; exit 2; }

echo "scorecardcheck: BIN=$BIN"

# ─── Run scorecard.sh and validate output ──────────────────────────────────────────────

OUT1="$TMP/scorecard1.md"
OUT2="$TMP/scorecard2.md"

if CTXPACK_BIN="$BIN" bash "$SCORECARD" >"$OUT1" 2>"$TMP/sc1.err"; then
  ok "scorecard.sh exit 0 (first run)"
else
  no "scorecard.sh exit non-zero: $(cat "$TMP/sc1.err" | head -3)"
  exit 1
fi

# ─── Validate table format ────────────────────────────────────────────────────────────────

# Header line should be: | Language | Symbols | Edges | Ambiguous | Amb Rate |
header=$(head -1 "$OUT1")
if [ "$header" = "| Language | Symbols | Edges | Ambiguous | Amb Rate |" ]; then
  ok "header line matches expected format"
else
  no "header line mismatch, got: $header"
fi

# Separator line should be: |---|---|---|---|---|
sep=$(sed -n '2p' "$OUT1")
if [ "$sep" = "|---|---|---|---|---|" ]; then
  ok "separator line correct"
else
  no "separator line mismatch, got: $sep"
fi

# ─── Validate data rows ───────────────────────────────────────────────────────────────────

# Count data rows (all lines after the separator)
row_count=$( tail -n +3 "$OUT1" | wc -l )
if [ "$row_count" -ge 2 ]; then
  ok "table has at least 2 language rows ($row_count rows)"
else
  no "table has fewer than 2 rows ($row_count rows)"
fi

# Validate each data row with Python
python3 - "$OUT1" << 'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
  lines = f.readlines()

# Skip header and separator (lines 0-1)
data_rows = lines[2:]
fail_count = 0
for i, line in enumerate(data_rows, 1):
  line = line.strip()
  if not line:
    continue

  # Row format: | Lang | Symbols | Edges | Ambiguous | Amb Rate |
  # All cells should be separated by | and not empty (except maybe Amb Rate with "N/A")
  cells = [c.strip() for c in line.split('|')]
  cells = [c for c in cells if c]  # remove empty strings from leading/trailing |

  if len(cells) != 5:
    print(f"FAIL: row {i} has {len(cells)} cells (expected 5): {line}")
    fail_count += 1
    continue

  lang, symbols_str, edges_str, ambiguous_str, amb_rate_str = cells

  # Language should be non-empty
  if not lang:
    print(f"FAIL: row {i} has empty Language")
    fail_count += 1
    continue

  # Symbols, Edges, Ambiguous should be integers >= 0
  try:
    symbols = int(symbols_str)
    edges = int(edges_str)
    ambiguous = int(ambiguous_str)
    if symbols < 0 or edges < 0 or ambiguous < 0:
      print(f"FAIL: row {i} ({lang}) has negative counts: S={symbols} E={edges} A={ambiguous}")
      fail_count += 1
      continue
  except ValueError:
    print(f"FAIL: row {i} ({lang}) has non-integer counts: S={symbols_str} E={edges_str} A={ambiguous_str}")
    fail_count += 1
    continue

  # Amb Rate should be a float in [0,1] or "N/A"
  if amb_rate_str == "N/A":
    if edges != 0:
      print(f"FAIL: row {i} ({lang}) has Amb Rate=N/A but edges={edges} (should only be N/A if edges=0)")
      fail_count += 1
  else:
    try:
      amb_rate = float(amb_rate_str)
      if amb_rate < 0.0 or amb_rate > 1.0:
        print(f"FAIL: row {i} ({lang}) has Amb Rate={amb_rate} outside [0,1]")
        fail_count += 1
    except ValueError:
      print(f"FAIL: row {i} ({lang}) has non-numeric Amb Rate: {amb_rate_str}")
      fail_count += 1

if fail_count == 0:
  print(f"PASS: all {len(data_rows)} data rows have valid format")
  sys.exit(0)
else:
  print(f"FAIL: {fail_count} validation errors")
  sys.exit(1)
PYEOF

if [ $? -eq 0 ]; then
  ok "all data rows have valid format and sane values"
else
  no "data row validation failed"
  fail=1
fi

# ─── Determinism check ─────────────────────────────────────────────────────────────────────

if CTXPACK_BIN="$BIN" bash "$SCORECARD" >"$OUT2" 2>"$TMP/sc2.err"; then
  ok "scorecard.sh exit 0 (second run)"
else
  no "scorecard.sh exit non-zero on second run: $(cat "$TMP/sc2.err" | head -3)"
  exit 1
fi

if diff -q "$OUT1" "$OUT2" >/dev/null; then
  ok "determinism: two runs produce identical output"
else
  no "determinism: output differs between runs"
  diff "$OUT1" "$OUT2" | head -8
  fail=1
fi

# ─── Summary ──────────────────────────────────────────────────────────────────────────────

echo
if [ "$fail" -eq 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
