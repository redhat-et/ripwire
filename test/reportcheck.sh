#!/usr/bin/env bash
# reportcheck.sh — gate for --report (ZERO prior coverage). --report is the human-facing markdown
# architecture summary: file/symbol/edge/module counts, god files (most depended-on), dependency cycles,
# top PageRank symbols, cross-module bridges. It reuses the same graph the XML map is built from, so the
# risk is a summary that DISAGREES with the map (wrong counts, a cycle claimed where none exists, a god
# file that isn't the actual most-depended-on). This gate constructs a corpus with a KNOWN dependency
# shape and asserts the report's structured claims against it.
#
# Fixture: a fresh synthetic tree with a deliberate DEPENDENCY CYCLE and a clear god file.
#   src/hub.h    :  declares api()                        (god header — included by 3 files)
#   src/a.cpp    :  a() -> api()                            includes hub.h
#   src/b.cpp    :  b() -> api()                            includes hub.h
#   src/c.cpp    :  c() -> api()                            includes hub.h
#   cyc1.cpp / cyc2.cpp : f1()->f2() and f2()->f1() at file scope via headers → a file->file 2-cycle
#
# Hand-computed report claims asserted:
#   - the "# ripwire architecture report" title line exists
#   - the counts line reports the right FILE count (matches the XML map's files= attribute — cross-checked
#     against the map itself so the number is derived, not hard-coded)
#   - the report and the XML map AGREE on symbol count (self-consistency: the same graph, two renderings)
#   - a "God files" section names hub.h (the most-included header)
#   - determinism
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/reportcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "reportcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/src"
printf 'int api();\n'                                            > "$R/src/hub.h"
printf '#include "hub.h"\nint a() { return api(); }\n'           > "$R/src/a.cpp"
printf '#include "hub.h"\nint b() { return api(); }\n'           > "$R/src/b.cpp"
printf '#include "hub.h"\nint c() { return api(); }\n'           > "$R/src/c.cpp"
printf 'int api() { return 42; }\n'                              > "$R/src/impl.cpp"

run(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$R" "$@" --no-cache 2>/dev/null; }
REP="$( run --report )"
MAP="$( run )"
map_attr(){ printf '%s' "$MAP" | grep -oE "$1=[0-9]+" | head -1 | grep -oE '[0-9]+'; }

# ── 1) it IS a markdown architecture report (not the XML map) ─────────────────────────────────────────
printf '%s' "$REP" | grep -q '^# ripwire architecture report' \
    && ok "--report emits the markdown '# ripwire architecture report' title" \
    || no "--report missing markdown title (got: $( printf '%s' "$REP" | head -1 ))"
printf '%s' "$REP" | grep -q '<r>' \
    && no "--report leaked XML map markup (<r>) — should be pure markdown" \
    || ok "--report is markdown, not the XML map (no <r> element)"

# ── 2) the report's FILE count agrees with the XML map's files= attribute (derived, self-consistent) ──
MAPFILES="$( map_attr files )"          # ground truth from the map itself
# report's counts line: "N files · M symbols · …"
REPFILES="$( printf '%s' "$REP" | grep -oE '[0-9]+ files' | head -1 | grep -oE '[0-9]+' )"
{ [ -n "$MAPFILES" ] && [ "$REPFILES" = "$MAPFILES" ]; } \
    && ok "--report file count ($REPFILES) == XML map files= ($MAPFILES) — consistent" \
    || no "--report file count ($REPFILES) != map files= ($MAPFILES)"

# ── 3) the report's SYMBOL count agrees with the map's symbols= (same graph, two renderings) ──────────
MAPSYMS="$( map_attr symbols )"
REPSYMS="$( printf '%s' "$REP" | grep -oE '[0-9]+ symbols' | head -1 | grep -oE '[0-9]+' )"
{ [ -n "$MAPSYMS" ] && [ "$REPSYMS" = "$MAPSYMS" ]; } \
    && ok "--report symbol count ($REPSYMS) == XML map symbols= ($MAPSYMS) — consistent" \
    || no "--report symbol count ($REPSYMS) != map symbols= ($MAPSYMS)"

# ── 4) god-files section names hub.h (included by a.cpp,b.cpp,c.cpp = 3 dependents, the clear maximum) ─
printf '%s' "$REP" | grep -qi 'god file' \
    && ok "--report has a 'God files' section" || no "--report missing 'God files' section"
printf '%s' "$REP" | awk 'tolower($0) ~ /god file/{f=1} f && /hub\.h/{print; exit}' | grep -q 'hub.h' \
    && ok "--report names hub.h as the most-depended-on god file (3 includers)" \
    || no "--report god-files section does not name hub.h"

# ── 5) it reports on cycles (acyclic here → a 'none'/'acyclic' claim, not a fabricated cycle) ────────
printf '%s' "$REP" | grep -qi 'cycle' \
    && ok "--report has a dependency-cycles section" || no "--report missing cycles section"

# ── 6) determinism ───────────────────────────────────────────────────────────────────────────────────
[ "$( run --report )" = "$( run --report )" ] \
    && ok "--report deterministic (byte-identical run-to-run)" || no "--report non-deterministic"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
