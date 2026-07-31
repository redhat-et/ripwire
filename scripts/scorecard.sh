#!/usr/bin/env bash
# scripts/scorecard.sh — per-language resolution honesty scorecard
#
# For each language supported by ctxpack, runs the binary on a representative test fixture,
# extracts resolution statistics (symbols, edges, ambiguous edge count), computes the
# ambiguity rate (ambiguous/edges), and emits a markdown table sorted by language name.
#
# The table documents ctxpack's honesty about its call-graph precision: where dynamic
# dispatch, callbacks, or multi-definition scenarios make the name-based resolver uncertain,
# the amb= counter reports it explicitly so users know when to drop to reading source.
#
# Output is deterministic (same table on every run of the same tree).
#
# Usage:
#   scripts/scorecard.sh              # uses build/ctxpack
#   CTXPACK_BIN=./asan/ctxpack scripts/scorecard.sh
#
# Exits 0 on success (table emitted), non-zero on failure (missing binary, corrupt output, etc.).

set -uo pipefail
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "error: no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 required for XML parsing"; exit 2; }

# ─── Language fixture map (language name → representative test fixture) ───────────────────
# Where multiple fixtures cover a language, we pick the one most specific to that language.
# Store as space-separated lines: "language fixture" to avoid bash array key issues with special chars.
read -r -d '' FIXTURES << 'FIXTURE_EOF' || true
C++ baselinefix
C# csharpfix
Go multirootfix
Java javarubyfix
JavaScript jslangfix
ObjC langfix
Python pyimportprecisefix
Ruby javarubyfix
Rust langfix
Swift swiftfix
TypeScript langfix
FIXTURE_EOF

# ─── Extract resolution statistics from a fixture ─────────────────────────────────────────
# Given a fixture path, run ctxpack, parse the XML header comment, and emit:
#   language symbols edges ambiguous amb_rate
# where amb_rate = ambiguous / edges (or "N/A" if edges=0).

extract_stats() {
  local fixture="$1"
  local lang="$2"

  # Run ctxpack on the fixture
  local output="$TMP/${lang}.xml"
  if ! "$BIN" "$fixture" >"$output" 2>"$TMP/${lang}.err"; then
    echo "error: ctxpack failed on $fixture: $(cat "$TMP/${lang}.err")" >&2
    return 1
  fi

  # Parse the XML header comment for statistics
  # Header format: <!-- ctxpack v1 ...legend...--> <!-- files=N symbols=M edges=E shown=... est_tokens=... ambiguous=A unresolved=... -->
  # We need to extract: symbols=, edges=, ambiguous=
  python3 - "$output" "$lang" <<'PYEOF'
import sys, re
xml_file = sys.argv[1]
lang = sys.argv[2]

with open(xml_file, 'r', encoding='utf-8') as f:
  content = f.read()

# Find the second comment (header comment with stats)
# It matches: <!-- files=... symbols=... edges=... ambiguous=... -->
match = re.search(r'<!-- files=(\d+) symbols=(\d+) edges=(\d+).*?ambiguous=(\d+)', content)
if not match:
  print(f"error: could not parse header from {xml_file}", file=sys.stderr)
  sys.exit(1)

files, symbols, edges, ambiguous = match.groups()
symbols = int(symbols)
edges = int(edges)
ambiguous = int(ambiguous)

# Compute amb_rate = ambiguous / edges, guarding against division by zero
if edges == 0:
  amb_rate_str = "N/A"
else:
  amb_rate = ambiguous / edges
  amb_rate_str = f"{amb_rate:.4f}"

print(f"{lang} {symbols} {edges} {ambiguous} {amb_rate_str}")
PYEOF
}

# ─── Main ─────────────────────────────────────────────────────────────────────────────────

# Build the results table (temporarily unsorted)
# Store results in a temp file: "language symbols edges ambiguous amb_rate"
results_file="$TMP/results.txt"
> "$results_file"  # initialize empty file

while read -r lang fixture; do
  [ -z "$lang" ] && continue  # skip empty lines
  full_fixture="$ROOT/test/$fixture"

  if [ ! -d "$full_fixture" ]; then
    echo "warning: fixture not found for $lang at $full_fixture — skipping" >&2
    continue
  fi

  result=$( extract_stats "$full_fixture" "$lang" ) || { echo "error: extraction failed for $lang"; exit 1; }
  echo "$result" >> "$results_file"
done <<< "$FIXTURES"

# Sort results by language name (first field)
sort "$results_file" > "$results_file.sorted"

# Emit the markdown table
echo "| Language | Symbols | Edges | Ambiguous | Amb Rate |"
echo "|---|---|---|---|---|"
while read -r lang symbols edges ambiguous amb_rate; do
  printf "| %s | %d | %d | %d | %s |\n" "$lang" "$symbols" "$edges" "$ambiguous" "$amb_rate"
done < "$results_file.sorted"

exit 0
