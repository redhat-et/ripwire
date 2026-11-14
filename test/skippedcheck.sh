#!/usr/bin/env bash
# skippedcheck.sh — `--skipped` itemizes the map header's skipped_oversize= and lexical_files= counts.
#
# SCOPE, since §L1 widened the verb: this gate owns the SIZE classes and the root's accounting join, and nothing
# else. The other drop reasons (excluded / unsupported-ext) and the parse-health rows are test/skipreasoncheck.sh and
# test/parsehealthcheck.sh. Every assertion below matches its row by why= and matches root attributes INDIVIDUALLY
# rather than pinning the whole `<skipped …>` open tag: a sibling class landing a new counter must not red this gate.
#
# RE-PINNED 2026-11-14 (NO-SKIP-INGEST, owner: "we should not be skipping files"): a size ceiling no longer DROPS a
# file. Over --max-file-size (default 64 MiB) a file is read lexically (<h why="lexical-size"/>); a .json/.yaml over its
# full-index ceiling yields bounded top-level keys (<h why="keys-bounded"/>). Only the fixed 1 GiB hard limit still
# drops a file, and that is the one <f why="oversize"/> row left — fixtured here with a SPARSE file (no disk blocks).
#
# Arms:
#   (0) presence guards — the fixture files exceed the ceilings the arms assume
#   (1) --max-file-size=1K: big.cpp is a lexical-size h row, data.json a keys-bounded h row, nothing dropped
#       (oversize="0", indexed="3"), small.cpp unlisted, root carries the effective ceilings + lexical_files="2";
#       big.cpp is NOT rowed minified-suspect (the lexical read measures whitespace too)
#   (2) default ceiling: only data.json (keys-bounded), lexical_files="1"
#   (3) accounting join: map header lexical_files= equals the verb's, files= = the whole population, no
#       skipped_oversize=
#   (4) zero means none found — a clean corpus reports oversize="0", no rows, no lexical_files=
#   (5) purely additive (G5) — the default map emits no <skipped element and no ceiling attribute
#   (6) determinism  (7) well-formedness  (8) multi-root <label>/<rel> spelling of a lexical row
#   (9) the 1 GiB hard limit: a sparse >1 GiB file is the one dropped file — f row limit="1073741824",
#       oversize="1", map skipped_oversize=1, and a stderr warning saying no option raises it (POSIX only)
#
# Usage:  bash test/skippedcheck.sh      [RIPWIRE_BIN=path/to/binary]
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "skippedcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── fixture: one under-ceiling .cpp, one >1KB .cpp, one >256KB .json ─────────────────────────────────────
mkdir -p "$TMP/corpus"
printf 'int keep( void ) { return 1; }\n' > "$TMP/corpus/small.cpp"
{ printf '// filler\n'; for i in $( seq 1 80 ); do printf 'int filler_%d( void ) { return %d; }\n' "$i" "$i"; done; } > "$TMP/corpus/big.cpp"
{ printf '{"k":"'; head -c 300000 /dev/zero | tr '\0' 'a'; printf '"}'; } > "$TMP/corpus/data.json"

# ── (0) presence guards — assert the fixture is what the arms below assume ───────────────────────────────
smallBytes="$( wc -c < "$TMP/corpus/small.cpp" | tr -d ' ' )"
bigBytes="$(   wc -c < "$TMP/corpus/big.cpp"   | tr -d ' ' )"
jsonBytes="$(  wc -c < "$TMP/corpus/data.json" | tr -d ' ' )"
if [ "$smallBytes" -lt 1024 ]; then ok "(0) small.cpp is under the 1K ceiling ($smallBytes B)"; else no "(0) small.cpp is NOT under 1024 B ($smallBytes B) — fixture broken"; fi
if [ "$bigBytes" -gt 1024 ]; then ok "(0) big.cpp exceeds the 1K ceiling ($bigBytes B)"; else no "(0) big.cpp does NOT exceed 1024 B ($bigBytes B) — fixture broken"; fi
if [ "$jsonBytes" -gt 262144 ]; then ok "(0) data.json exceeds the 256KB json ceiling ($jsonBytes B)"; else no "(0) data.json does NOT exceed 262144 B ($jsonBytes B) — fixture broken"; fi

cd "$TMP"   # crawl arg `corpus` → root="corpus" + rows spell the bare relative path, machine-independently
# RE-PINNED 2026-08-19 (R-E CORRECTION): with the crawl arg `corpus`, p= used to repeat that prefix on
# every row; root-relative p= states it ONCE as root="corpus" and rows spell the bare relative path.
# Still machine-independent — that is why this script cds into $TMP and crawls a relative arg.

# ── (1) --max-file-size=1K: both big files indexed lexically, none dropped ───────────────────────────────────
"$BIN" corpus --skipped --max-file-size=1K --no-cache > "$TMP/one.xml" 2>"$TMP/one.err"
rc=$?
if [ "$rc" -eq 0 ]; then ok "(1) --skipped exits 0 (a report, not a gate)"; else no "(1) --skipped exited $rc, expected 0"; fi
grep -q "<h p=\"big.cpp\" why=\"lexical-size\" bytes=\"$bigBytes\"/>" "$TMP/one.xml" \
    && ok "(1) big.cpp over --max-file-size is a lexical-size row with its exact bytes=" \
    || { no "(1) big.cpp lexical-size row missing or wrong (want bytes=\"$bigBytes\")"; head -c 600 "$TMP/one.xml"; echo; }
grep -q "<h p=\"data.json\" why=\"keys-bounded\" bytes=\"$jsonBytes\"/>" "$TMP/one.xml" \
    && ok "(1) data.json over BOTH ceilings is one keys-bounded row (the data lane is tested first)" \
    || no "(1) data.json keys-bounded row missing or wrong (want bytes=\"$jsonBytes\")"
grep -q '<f p="' "$TMP/one.xml" && no "(1) a file is still DROPPED under a ceiling (an <f row)" || ok "(1) no file is dropped (no <f row)"
grep -q 'p="small.cpp"' "$TMP/one.xml" && no "(1) small.cpp is listed but met no limit" || ok "(1) the under-ceiling file is not listed"
grep -q 'p="big.cpp" why="minified-suspect"' "$TMP/one.xml" && no "(1) big.cpp rowed minified-suspect — the lexical read left ws unmeasured" \
    || ok "(1) big.cpp is not misrowed minified-suspect"
grep -q 'oversize="0"' "$TMP/one.xml" && grep -q 'indexed="3"' "$TMP/one.xml" && grep -q 'lexical_files="2"' "$TMP/one.xml" \
    && grep -q 'max_file_size="1024"' "$TMP/one.xml" && grep -q 'json_ceiling="262144"' "$TMP/one.xml" \
    && ok "(1) root: indexed=\"3\" oversize=\"0\" lexical_files=\"2\" and both effective ceilings" \
    || { no "(1) root element wrong (want indexed=3 oversize=0 lexical_files=2 max_file_size=1024 json_ceiling=262144)"; head -c 600 "$TMP/one.xml"; echo; }

# ── (2) default ceiling → only data.json, keys-bounded ──────────────────────────────────────────────────────────
"$BIN" corpus --skipped --no-cache > "$TMP/two.xml" 2>/dev/null
grep -q "<h p=\"data.json\" why=\"keys-bounded\" bytes=\"$jsonBytes\"/>" "$TMP/two.xml" \
    && ok "(2) >256KB .json yields bounded keys under the default ceiling and says so" \
    || { no "(2) data.json keys-bounded row missing under the default ceiling"; head -c 600 "$TMP/two.xml"; echo; }
grep -q 'p="big.cpp" why="lexical' "$TMP/two.xml" && no "(2) big.cpp read lexically under the default 64 MiB ceiling" || ok "(2) big.cpp is parsed under the default ceiling"
if grep -q 'lexical_files="1"' "$TMP/two.xml" && grep -q 'oversize="0"' "$TMP/two.xml"; then ok "(2) root reports lexical_files=\"1\" oversize=\"0\""; else no "(2) root does not report lexical_files=\"1\" oversize=\"0\""; fi

# ── (3) accounting join: verb count == map header count; files= = the population ────────────────────────────────
# L1 (2026-09-19): the CLI default legend is compact and defines `files=` in its comment ahead of the header; (3) reads the header's values, so it asks for the full legend.
"$BIN" corpus --max-file-size=1K --no-cache --legend=full > "$TMP/map.xml" 2>/dev/null
mapLexical="$( grep -o 'lexical_files=[0-9]*' "$TMP/map.xml" | head -1 | cut -d= -f2 )"
mapFiles="$(   grep -o 'files=[0-9]*'         "$TMP/map.xml" | head -1 | cut -d= -f2 )"
[ "${mapLexical:-}" = "2" ] && ok "(3) map header says lexical_files=2 — same count the verb itemizes" \
    || no "(3) map header lexical_files=${mapLexical:-<absent>}, verb said 2 — the two surfaces disagree"
[ "${mapFiles:-0}" = "3" ] && ok "(3) files=3 = the whole 3-file candidate population" || no "(3) files=${mapFiles:-<absent>}, expected 3"
grep -q 'skipped_oversize=' "$TMP/map.xml" && no "(3) map header claims a dropped file" || ok "(3) map header has no skipped_oversize= (nothing dropped)"

# ── (4) zero means none found ────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$TMP/clean"; printf 'int keep( void ) { return 1; }\n' > "$TMP/clean/small.cpp"
"$BIN" clean --skipped --no-cache > "$TMP/zero.xml" 2>/dev/null
if grep -q 'oversize="0"' "$TMP/zero.xml"; then ok "(4) clean corpus reports oversize=\"0\""; else no "(4) clean corpus does not report oversize=\"0\""; fi
grep -q '<f p="\|<h p="' "$TMP/zero.xml" && no "(4) zero-count report still emits rows" || ok "(4) zero-count report emits no rows"
grep -q 'lexical_files=' "$TMP/zero.xml" && no "(4) clean corpus carries lexical_files= (absent-when-zero broken)" || ok "(4) clean corpus has no lexical_files="

# ── (5) purely additive (G5) + default header unchanged (G4) ─────────────────────────────────────────────────────
grep -q 'files=' "$TMP/map.xml" || no "(5) presence guard: default map did not run (no files= header)"
grep -q '<skipped' "$TMP/map.xml" && no "(5) default map emits a <skipped element without being asked" || ok "(5) the verb is purely additive — no <skipped element in the default map"
grep -q 'json_ceiling=' "$TMP/map.xml" && no "(5) default map header gained json_ceiling=" || ok "(5) default map header carries no ceiling attribute"

# ── (6) determinism ──────────────────────────────────────────────────────────────────────────────────────────────
"$BIN" corpus --skipped --max-file-size=1K --no-cache > "$TMP/one2.xml" 2>/dev/null
if cmp -s "$TMP/one.xml" "$TMP/one2.xml"; then ok "(6) two runs, byte-identical"; else no "(6) two runs differ"; fi

# ── (7) well-formedness (G4) ─────────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/one.xml" 2>/dev/null; then ok "(7) report is well-formed XML"; else no "(7) report fails xmllint"; fi
else
    ok "(7) xmllint not available — skipped (regression.sh's own gate covers the toolchain that has it)"
fi

# ── (8) multi-root: the lexical row keeps its <label>/<rel> spelling ─────────────────────────────────────────────
mkdir -p "$TMP/alpha" "$TMP/beta"
cp "$TMP/corpus/big.cpp" "$TMP/alpha/big.cpp"
printf 'int beta_fn( void ) { return 2; }\n' > "$TMP/beta/lib.cpp"
"$BIN" alpha beta --skipped --max-file-size=1K --no-cache > "$TMP/multi.xml" 2>/dev/null
grep -q "<h p=\"alpha/big.cpp\" why=\"lexical-size\" bytes=\"$bigBytes\"/>" "$TMP/multi.xml" \
    && ok "(8) multi-root row carries the labeled <label>/<rel> spelling" \
    || { no "(8) multi-root row missing or unlabeled (want p=\"alpha/big.cpp\")"; head -c 600 "$TMP/multi.xml"; echo; }
if grep -q 'lexical_files="1"' "$TMP/multi.xml"; then ok "(8) multi-root count sums across roots"; else no "(8) multi-root count wrong (want lexical_files=\"1\")"; fi

# ── (9) the 1 GiB hard limit: the one size that still drops a file ───────────────────────────────────────────────
# A SPARSE file (truncate extends without writing blocks) — the crawl only stats it, so the arm costs no disk or time.
# Skipped where truncate may allocate real blocks (Windows shells).
case "$( uname -s 2>/dev/null )" in
MINGW*|MSYS*|CYGWIN*) ok "(9) hard-limit arm skipped on Windows (a 1 GiB sparse file is not cheap there)" ;;
*)
    mkdir -p "$TMP/hard"; printf 'int keep( void ) { return 1; }\n' > "$TMP/hard/small.c"
    python3 -c "import sys; open(sys.argv[1],'wb').truncate((1<<30)+4096)" "$TMP/hard/huge.c" 2>/dev/null \
        || perl -e 'open(my $f, ">", $ARGV[0]) or die; truncate($f, (1<<30)+4096) or die' "$TMP/hard/huge.c"
    hugeBytes="$( wc -c < "$TMP/hard/huge.c" | tr -d ' ' )"
    if [ "${hugeBytes:-0}" -gt 1073741824 ]; then ok "(9) premise: huge.c is over 1 GiB ($hugeBytes B)"; else no "(9) premise: huge.c is not over 1 GiB (${hugeBytes:-?} B)"; fi
    "$BIN" hard --skipped --no-cache > "$TMP/hard.xml" 2>"$TMP/hard.err"
    grep -q "<f p=\"huge.c\" why=\"oversize\" bytes=\"$hugeBytes\" limit=\"1073741824\"/>" "$TMP/hard.xml" \
        && ok "(9) the >1 GiB file is the one dropped file, at limit=\"1073741824\"" \
        || { no "(9) hard-limit row missing or wrong"; head -c 600 "$TMP/hard.xml"; echo; }
    grep -q 'oversize="1"' "$TMP/hard.xml" && ok "(9) root reports oversize=\"1\"" || no "(9) root does not report oversize=\"1\""
    grep -q 'huge.c (.*) exceeds the .* hard limit; not indexed (no option raises it)' "$TMP/hard.err" \
        && ok "(9) stderr warns that the hard limit dropped it" || { no "(9) no hard-limit warning on stderr"; cat "$TMP/hard.err"; }
    "$BIN" hard --no-cache --legend=full > "$TMP/hardmap.xml" 2>/dev/null
    grep -q 'skipped_oversize=1' "$TMP/hardmap.xml" && ok "(9) map header skipped_oversize=1 agrees" || no "(9) map header lacks skipped_oversize=1"
    rm -f "$TMP/hard/huge.c" ;;
esac

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }
