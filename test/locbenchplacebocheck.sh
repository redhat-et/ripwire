#!/usr/bin/env bash
# locbenchplacebocheck.sh — the matched-budget control arms of bench/locbench/run_locbench.py
# (bench/locbench/PREREG_PLACEBO.md).
#
# WHY THIS GATE EXISTS. METHODOLOGY.md §8: a ranking win and a "having an answer of that size at all" win
# raise the same accuracy number, and only a placebo of the SAME FORMAT and the SAME BYTE COST tells them
# apart. A placebo that is 300 bytes shorter, or that a model can spot by its shape, measures a context-size
# or a format effect and gets reported as a ranking result. So the property is gated, not asserted in prose:
#   * every control arm (for-matched, placebo, placebo-shuffle, lexical) is EXACTLY the target byte size;
#   * the placebo is format-identical — same legend bytes, root attribute names, and ripwire-rendered row
#     shapes — and parses as XML at every one of 1,100 consecutive targets (no cut inside an entity);
#   * the unrelated placebo names none of the real answer's files, on a fixture whose universe DOES
#     contain them (the exclusion is live, not vacuous); builders take no gold argument;
#   * an undersized pool fails closed (PlaceboUnbuildable), never a near-miss size;
#   * on REALISTIC short signatures (16-95 chars) every arm still builds, at ONE common size B* <= the requested
#     budget with the shortfall disclosed (PREREG_PLACEBO.md ADDENDUM 2026-11-26; red on the original builder);
#   * the lexical baseline is FILE-level BM25 with identifier splitting, and counts oversize files;
#   * one arm on REAL ripwire output (test/fixture) when a binary is present.
# Red on the base commit by construction: the builders did not exist there (AttributeError -> exit 1).
set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
# The gate binary seam (lane rules 11-26): the binary is named and its version printed on the FIRST line, so a
# run cannot silently test some other build. RIPWIRE_BIN is what pargates.py and regression.sh set; $1 is the
# compatible fallback for a hand run. A binary that does not run fails the gate (exit 2) rather than being
# ignored or reported as a property failure.
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "BIN=$BIN $( "$BIN" --version 2>&1 | head -n 1 )"
command -v python3 >/dev/null 2>&1 || { echo "locbenchplacebocheck: python3 required"; exit 2; }
"$BIN" --version >/dev/null 2>&1 || { echo "locbenchplacebocheck: BIN=$BIN does not run — build first (cmake --build build -j)"; exit 2; }
python3 "$ROOT/bench/locbench/test_placebo_arms.py" "$BIN"
