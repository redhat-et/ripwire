#!/usr/bin/env bash
# legenddriftcheck.sh — legend drift gate (W2-G).
#
# Detects phantom flag references in ripwire's emitted XML legend comments.
# A legend can reference flags that don't exist in the binary's --help table,
# creating documentation drift invisible to --doc-drift (legends are XML, not markdown).
#
# Arm A (live): runs the checker against the built binary over a fixed small corpus
#   (the repo itself; legends are content-independent but corpus disclosed in header).
#
# Arm B (synthetic known-positive, E3 orchestrator correction): checks that the
#   gate catches a PHANTOM reference when a help table is missing a flag.
#   Uses fixture legends containing prose like "the signatures-only flag" paired
#   with a help table that lacks --signatures-only.
#
# Exit codes:
#   0 = both arms pass (no phantom flags detected)
#   2 = legend drift detected (phantom flags found)
#   4 = setup failure (binary missing, corpus unreachable, python3 unavailable)
#
# Usage:
#   bash test/legenddriftcheck.sh
#   RIPWIRE_BIN=asan/ripwire bash test/legenddriftcheck.sh
#
# References: the Wave-2 round record (2026-08-17), E3 correction note.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative RIPWIRE_BIN
CORPUS="${RIPWIRE_CORPUS:-$ROOT}"                    # default: repo itself (corpus-independent)

[ -x "$BIN" ] || { echo "⚠ ripwire binary not found: $BIN (build with: cmake --build build -j)"; exit 4; }
command -v python3 >/dev/null 2>&1 || { echo "⚠ python3 not found"; exit 4; }

TMPDIR="$( mktemp -d )"; trap 'rm -rf "$TMPDIR"' EXIT
LEGEND_CHECK="$ROOT/test/legenddriftcheck.py"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "legenddriftcheck: BIN=$BIN  CORPUS=$CORPUS"

# ── Arm A: Live check against the built binary over fixed corpus ──────────────────────────────────
#
# Run the legend checker on the built binary using the repo as corpus. Legends are
# content-independent (they describe XML structure, not symbol properties), so running
# on the repo itself exercises all legend paths without corpus-specific bias.

python3 "$LEGEND_CHECK" "$BIN" "$CORPUS" >"$TMPDIR/live_result.json" 2>"$TMPDIR/live_err.txt"
rc_live=$?

if [ $rc_live -ne 0 ]; then
    no "Arm A live check: checker exited non-zero ($rc_live)"
    head -6 "$TMPDIR/live_err.txt" 2>/dev/null || echo "(no stderr)"
    cat "$TMPDIR/live_result.json" 2>/dev/null | head -12
else
    # Parse JSON to extract verdict and phantom count
    verdict=$( python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('verdict', 'unknown'))" <"$TMPDIR/live_result.json" 2>/dev/null || echo "unknown" )
    phantoms=$( python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['findings']['phantom_flags']))" <"$TMPDIR/live_result.json" 2>/dev/null || echo "-1" )

    if [ "$verdict" = "CLEAN" ] && [ "$phantoms" -eq 0 ]; then
        ok "Arm A live check: no phantom flags (legends clean)"
    else
        no "Arm A live check: phantom flags detected (verdict=$verdict, count=$phantoms)"
        python3 -c "import json,sys; d=json.load(sys.stdin); print('  Phantoms: ' + ', '.join(d['findings']['phantom_flags']))" <"$TMPDIR/live_result.json" 2>/dev/null || true
        fail=1
    fi
fi

# ── Arm B: Synthetic known-positive (E3 correction: must catch a phantom) ──────────────────────
#
# Per the round's E3 correction (2026-08-17), the known-positive arm must
# use a SYNTHETIC FIXTURE rather than historical data. We inject:
#   - A legend text containing prose like "the signatures-only flag …"
#   - A help table that LACKS --signatures-only (or any non-existent flag)
# The checker MUST report this as a phantom; if it misses it, the gate fails.
#
# This proves the gate's catching power independently of history and binary state.

# Create a synthetic legend file with a phantom reference
cat >"$TMPDIR/synthetic_legend.txt" <<'LEGEND_EOF'
<!-- ripwire v1 t=fn|method p=path n=name k=rank c=call
The signatures-only flag opts out of including symbol bodies when no custom inline filter is active.
Use --for=task with the signatures-only flag to get names and call structure without full implementations.
See --pack-task documentation for more.
-->
LEGEND_EOF

# Create a synthetic help file that lacks --signatures-only (or contains only minimal flags for testing)
# This help text intentionally omits --signatures-only to trigger phantom detection.
cat >"$TMPDIR/synthetic_help.txt" <<'HELP_EOF'
ripwire — parse, rank, stream

usage: ripwire <dir> [flags]

Common flags:
  --help              show this help
  --for=TEXT          task lens: rank by relevance to a natural-language task description
  --grep=PATTERN      search within symbols
  --expand=NAME       full body + callees of a single symbol
  --hotspots          complexity × churn: highest-risk (changed, complex) symbols first
  --pack-task=TEXT    composable bundle: map + ranked symbols + slice metadata
  --metrics           fan-in/out, cyclomatic complexity, lines of code
  --rank-by=METRIC    reorder by churn, authority, hub, rrf (reciprocal rank fusion)
  --stable            path-ordered (cache-friendly) output; omits volatile k= rank
  --top-k=N           limit to top N results
  --no-cache          skip caching; force fresh parse
  --cache=FILE        use explicit cache file
HELP_EOF

# Run the checker against the synthetic fixtures
python3 "$LEGEND_CHECK" --legend-file="$TMPDIR/synthetic_legend.txt" --help-file="$TMPDIR/synthetic_help.txt" \
    >"$TMPDIR/synthetic_result.json" 2>"$TMPDIR/synthetic_err.txt"
rc_synthetic=$?

if [ $rc_synthetic -ne 0 ]; then
    # Synthetic check exited non-zero, which means phantoms were detected — this is the EXPECTED outcome
    verdict=$( python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('verdict', 'unknown'))" <"$TMPDIR/synthetic_result.json" 2>/dev/null || echo "unknown" )
    phantoms=$( python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['findings']['phantom_flags']))" <"$TMPDIR/synthetic_result.json" 2>/dev/null || echo "0" )

    if [ "$verdict" = "DIRTY" ] && [ "$phantoms" -gt 0 ]; then
        ok "Arm B synthetic known-positive: phantom detected as expected (count=$phantoms)"
        python3 -c "import json,sys; d=json.load(sys.stdin); print('    Found: ' + ', '.join(d['findings']['phantom_flags']))" <"$TMPDIR/synthetic_result.json" 2>/dev/null || true
    else
        no "Arm B synthetic: exited non-zero but verdict=$verdict, phantoms=$phantoms (expected DIRTY + count>0)"
        cat "$TMPDIR/synthetic_result.json" 2>/dev/null | head -20
    fi
else
    # Synthetic check exited zero (CLEAN), but we EXPECT it to fail — this is a missed phantom
    no "Arm B synthetic known-positive: phantom NOT detected (MISSED catching power)"
    echo "    Expected to find --signatures-only as phantom, but checker reported CLEAN."
    echo "    The synthetic fixture contains: 'the signatures-only flag …'"
    echo "    The help table omits: --signatures-only"
    cat "$TMPDIR/synthetic_result.json" 2>/dev/null | head -20
    fail=1
fi

# ── Summary ───────────────────────────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "FAILURES ABOVE"
    exit 2
fi
