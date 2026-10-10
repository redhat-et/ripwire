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
#   - 7/9: a depended-on test-layer file (test/lib/helper.sh) is counted on a layer=test line, not ranked as the
#     god file, and its --deps godfiles row says layer="test"; 8: --seams leaves README -> docs/ links out (doc_links=)
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/reportcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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

# ── 7) a test-layer helper is not the god file (seams-doc-links, 2026-10-09) ────────────────────────────
# Every gate `source`s one shell library, so on this repo test/lib/clean-env.sh (185 dependents, all tests)
# outranked src/model.h. Fixture: test/lib/helper.sh sourced by 4 test scripts; src/core.h included by 3 files;
# a near-miss dir named `testing/` (not a built-in layer name) whose helper is sourced by 2 scripts.
T="$TMP/layer"; mkdir -p "$T/src" "$T/test/lib" "$T/testing"
printf 'int core();\n'                                            > "$T/src/core.h"
for f in a b c; do printf '#include "core.h"\nint %s() { return core(); }\n' "$f" > "$T/src/$f.cpp"; done
printf 'helper() { echo hi; }\n'                                  > "$T/test/lib/helper.sh"
for n in 1 2 3 4; do printf '#!/usr/bin/env bash\n. "$ROOT/test/lib/helper.sh"\nhelper\n' > "$T/test/g${n}check.sh"; done
printf 'tool() { echo t; }\n'                                     > "$T/testing/tool.sh"
for n in 1 2; do printf '#!/usr/bin/env bash\n. "$ROOT/testing/tool.sh"\ntool\n' > "$T/testing/u$n.sh"; done
LREP="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$T" --report --no-cache 2>/dev/null )"; lrc=$?
GOD="$( printf '%s\n' "$LREP" | sed -n '/^## God files/,/^$/p' )"
if [ "$lrc" != 0 ] || [ -z "$GOD" ]; then
    no "7: --report on the layer fixture failed (rc=$lrc) or printed no God files section"
else
    FIRST="$( printf '%s\n' "$GOD" | sed -n 2p )"
    case "$FIRST" in
        '- `src/core.h` — 3 dependents') ok "7a: the first god file is the source header src/core.h, not the test helper" ;;
        *) no "7a: first god-file row is '$FIRST' (want src/core.h — 3 dependents)" ;;
    esac
    printf '%s\n' "$GOD" | grep -qxF -- '- layer=test: 1 more depended-on files under a test, tests or bench directory, not ranked above; top `test/lib/helper.sh` — 4 dependents' \
        && ok "7b: the test helper is counted on the layer=test line (4 dependents), not dropped" \
        || no "7b: no layer=test line naming test/lib/helper.sh with 4 dependents: $GOD"
    printf '%s\n' "$GOD" | grep -qxF -- '- `testing/tool.sh` — 2 dependents' \
        && ok "7c: near miss: testing/ is not a built-in layer, so its helper is still ranked" \
        || no "7c: testing/tool.sh missing from the ranked rows: $GOD"
    printf '%s\n' "$GOD" | grep -c '^- `' | grep -qx 2 \
        && printf '%s\n' "$GOD" | grep -q 'showing 2 of 2' \
        && ok "7d: the header counts the ranked files only (showing 2 of 2)" \
        || no "7d: header/rows disagree with the ranked set: $GOD"
fi
# 7e: no depended-on test-layer file → no layer=test line (the section is the single ranking it was)
printf '%s' "$REP" | grep -q '^- layer=test' \
    && no "7e: a layer=test line appeared on a corpus with no test-layer dependents" \
    || ok "7e: no layer=test line without a depended-on test-layer file"

# ── 8) --seams (same runStructureText): a README -> docs/ link is not an untested code seam ───────────────
# Two README headings link docs/EVALS.md and docs/GUIDE.md; src/main.cpp calls lib/util.cpp (a real untested seam).
D="$TMP/doclinks"; mkdir -p "$D/docs" "$D/src" "$D/lib"
printf '# Proj\n\n## Measured\n\nSee [the evals](docs/EVALS.md).\n\n## Usage\n\nRead [the guide](docs/GUIDE.md).\n' > "$D/README.md"
printf '# EVALS\n\nNumbers.\n'                                    > "$D/docs/EVALS.md"
printf '# GUIDE\n\nSteps.\n'                                      > "$D/docs/GUIDE.md"
printf 'int helper();\nint run() { return helper(); }\n'          > "$D/src/main.cpp"
printf 'int helper() { return 1; }\n'                             > "$D/lib/util.cpp"
SEAMS="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$D" --seams --no-cache 2>/dev/null )"; src_=$?
SROOT="$( printf '%s' "$SEAMS" | grep -o '<seams [^>]*>' )"
if [ "$src_" != 0 ] || [ -z "$SROOT" ]; then
    no "8: --seams on the doc-link fixture failed (rc=$src_) or printed no <seams> root"
else
    printf '%s' "$SEAMS" | grep -q '<seam from="[^"]*" to="docs"' \
        && no "8a: a doc-section -> doc-section link is still listed as an untested seam to docs" \
        || ok "8a: no <seam ... to=\"docs\"> from README section links"
    printf '%s' "$SROOT" | grep -q ' bridges="1" untested="1" doc_links="2" ' \
        && ok "8b: the two doc links are counted in doc_links=2, outside bridges=/untested=" \
        || no "8b: root counts wrong (want bridges=1 untested=1 doc_links=2): $SROOT"
    printf '%s' "$SEAMS" | grep -q '<seam from="src" to="lib" untested="1"' \
        && ok "8c: negative: the real code seam src -> lib is still reported" \
        || no "8c: the code seam src -> lib went missing"
    printf '%s' "$SEAMS" | grep -q 'doc_links=N:' \
        && ok "8d: the legend reads doc_links= where it rides" || no "8d: doc_links= rides with no legend reading"
fi
NOSEAMS="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$R" --seams --no-cache 2>/dev/null )"
{ printf '%s' "$NOSEAMS" | grep -q '<seams ' && ! printf '%s' "$NOSEAMS" | grep -q 'doc_links='; } \
    && ok "8e: no doc links -> no doc_links= attribute or legend clause (present-only)" \
    || no "8e: doc_links= appeared without doc links (or --seams printed no root)"

# ── 9) --deps <godfiles> (the same population as 7): a test-layer row says layer="test" ───────────────────
LDEPS="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$T" --deps --no-cache 2>/dev/null )"; ldrc=$?
GF="$( printf '%s' "$LDEPS" | grep -o '<godfiles [^>]*>.*</godfiles>' )"
if [ "$ldrc" != 0 ] || [ -z "$GF" ]; then
    no "9: --deps on the layer fixture failed (rc=$ldrc) or printed no <godfiles>"
else
    printf '%s' "$GF" | grep -q '<f p="test/lib/helper.sh" layer="test" afferent="4"/>' \
        && ok "9a: the test helper's godfiles row carries layer=\"test\"" || no "9a: no layer=\"test\" on test/lib/helper.sh: $GF"
    printf '%s' "$GF" | grep -q '<f p="testing/tool.sh" afferent="2"/>' \
        && ok "9b: near miss: testing/tool.sh has no layer= (not a built-in layer dir)" || no "9b: testing/tool.sh row wrong: $GF"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
