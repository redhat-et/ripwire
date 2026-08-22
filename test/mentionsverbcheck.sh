#!/usr/bin/env bash
# mentionsverbcheck.sh — §A8.4 gate: --mentions=SYM's docs= counted
# markdown SECTIONS while the rows printed FILES — a doc with several backtick mentions of SYM under
# different headings inflated docs= (main.cpp uniques g.mentions' section NodeIds, one per enclosing
# Section, then prints each one's FILE path) and repeated the same p= across rows, both wrong: the
# attribute name says "docs" but the number was sections, and a reader summing rows double(triple)-
# counted one file.
#
# THE FIX: rows collapse to one per FILE, carrying mentions="N" (that file's own section-mention count).
# The root's docs= now names what it prints (the row count, distinct files) and sections= keeps the old
# section-node tally so nothing measured is lost. V2-2: NO l= — the doc edge is stored at file granularity
# (graph.h keeps the doc FILE node, line always 1), so an emitted l= read as a locator while carrying zero
# information; a row must not carry a fake locator.
#
# Fixture: pkg/alpha.py defines widget_pipeline_process. multi.md backtick-mentions it THREE times: once
# in body prose under no specific heading (attributes to the file-level Section — every ripwire markdown
# file gets one, spanning the whole file) and twice more directly ON a heading's own line ("## `sym`
# details" — a heading span covers only its own line, so a backtick THERE binds a DIFFERENT enclosing
# Section than body prose below it). That is 3 distinct (def, enclosing-Section) edges in ONE file — the
# exact shape that inflated docs=3x pre-fix. single.md mentions it once, for a plain 1x control.
#
# Usage:  bash test/mentionsverbcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/mentionsverbcheck.sh
#         RIPWIRE_BIN=build_base/ripwire bash test/mentionsverbcheck.sh    # must FAIL (pre-fix binary)
# Exits non-zero on any failure. Self-contained (own temp dir). Does NOT edit test/regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "mentionsverbcheck: BIN=$BIN"

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
FIX="$WORK/fix"; mkdir -p "$FIX/pkg"

cat > "$FIX/pkg/alpha.py" <<'EOF'
def widget_pipeline_process(records):
    return records
EOF
cat > "$FIX/multi.md" <<'EOF'
# Overview

Body prose mentioning `widget_pipeline_process` once, under no specific heading.

## `widget_pipeline_process` details

More prose here, unrelated to any specific backtick.

## Another note about `widget_pipeline_process`

Final prose.
EOF
cat > "$FIX/single.md" <<'EOF'
# Single doc

Just one mention of `widget_pipeline_process` here.
EOF

OUT="$( "$BIN" "$FIX" --mentions=widget_pipeline_process --no-cache 2>/dev/null )"
[ -n "$OUT" ] || { echo "no output — binary or fixture broken"; exit 2; }

# ── 1) exactly ONE row per file — no duplicate p= (the 3x-overcount bug's most visible symptom) ────────
n_multi_rows="$( printf '%s' "$OUT" | grep -oE '<doc p="[^"]*multi\.md"' | wc -l | tr -d ' ' )"
[ "$n_multi_rows" = 1 ] \
    && ok "multi.md collapses to exactly one <doc> row (was 3 duplicate rows, pre-fix)" \
    || no "expected exactly 1 row for multi.md, got $n_multi_rows"
n_single_rows="$( printf '%s' "$OUT" | grep -oE '<doc p="[^"]*single\.md"' | wc -l | tr -d ' ' )"
[ "$n_single_rows" = 1 ] \
    && ok "single.md is exactly one <doc> row" \
    || no "expected exactly 1 row for single.md, got $n_single_rows"

# ── 2) each row carries the right per-file mentions= (its own section-mention count) ────────────────────
multiRow="$( printf '%s' "$OUT" | grep -oE '<doc p="[^"]*multi\.md"[^/]*/>' )"
singleRow="$( printf '%s' "$OUT" | grep -oE '<doc p="[^"]*single\.md"[^/]*/>' )"
printf '%s' "$multiRow" | grep -q 'mentions="3"' \
    && ok "multi.md row carries mentions=\"3\" (3 distinct section mentions collapsed into it)" \
    || no "multi.md row missing mentions=\"3\": $multiRow"
printf '%s' "$singleRow" | grep -q 'mentions="1"' \
    && ok "single.md row carries mentions=\"1\"" \
    || no "single.md row missing mentions=\"1\": $singleRow"

# ── 3) V2-2: NO row carries l= — the stored doc edge has no real line, and a fake locator (always 1)
# ──         is worse than none. The legend must say why the locator is absent.
printf '%s' "$multiRow"  | grep -qE ' l="' && no "multi.md row still carries the fake l=" || ok "multi.md row carries no l= (V2-2)"
printf '%s' "$singleRow" | grep -qE ' l="' && no "single.md row still carries the fake l=" || ok "single.md row carries no l= (V2-2)"
printf '%s' "$OUT" | grep -q "No line locator" && ok "legend explains the absent locator" || no "legend does not explain the absent locator"

# ── 4) root docs= is the ROW COUNT (distinct files, 2), not the section tally ────────────────────────────
rowCount="$( printf '%s' "$OUT" | grep -o '<doc p=' | wc -l | tr -d ' ' )"
docsAttr="$( printf '%s' "$OUT" | grep -oE '<mentions[^>]*>' | grep -oE ' docs="[0-9]+"' | grep -oE '"[0-9]+"' | tr -d '"' )"
{ [ "$docsAttr" = "2" ] && [ "$rowCount" = "2" ] && [ "$docsAttr" = "$rowCount" ]; } \
    && ok "root docs=\"$docsAttr\" == the $rowCount emitted rows (distinct files)" \
    || no "docs=\"$docsAttr\" should equal the row count (got $rowCount rows)"

# ── 5) root sections= keeps the OLD section-node tally (nothing measured is lost) ────────────────────────
sectionsAttr="$( printf '%s' "$OUT" | grep -oE '<mentions[^>]*>' | grep -oE ' sections="[0-9]+"' | grep -oE '"[0-9]+"' | tr -d '"' )"
[ "$sectionsAttr" = "4" ] \
    && ok "root sections=\"4\" == the pre-collapse section-mention tally (3 + 1)" \
    || no "root sections= wrong (got '$sectionsAttr', expected 4)"

# ── 6) xml well-formed + determinism ─────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OUT" | xmllint --noout - 2>/dev/null && ok "xml well-formed" || no "xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi
OUT2="$( "$BIN" "$FIX" --mentions=widget_pipeline_process --no-cache 2>/dev/null )"
[ "$OUT" = "$OUT2" ] && ok "deterministic (byte-identical run-to-run)" || no "non-deterministic output"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
