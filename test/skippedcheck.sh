#!/usr/bin/env bash
# skippedcheck.sh — `--skipped` itemizes the map header's skipped_oversize= count.
#
# SCOPE, since §L1 widened the verb: this gate owns the OVERSIZE class and the root's accounting join,
# and nothing else. The other drop reasons (excluded / unsupported-ext) and the indexed-but-suspect
# parse-health rows are test/skipreasoncheck.sh and test/parsehealthcheck.sh. That is why every assertion
# below matches its row by `why="oversize"` and matches root attributes INDIVIDUALLY rather than pinning
# the whole `<skipped …>` open tag: a sibling class landing a new counter must not red this gate, and a
# change to the oversize rows themselves still must.
#
# Why this gate exists. The header discloses HOW MANY otherwise-indexable files the crawl dropped for
# exceeding a size ceiling (skipped_oversize=N), but nothing anywhere named WHICH files — a reader could
# know the corpus was truncated without being able to say what was absent from it. That is a disclosure
# gap in the tool's own doctrine ("every truncation is disclosed"): the count kept the accounting honest
# (files= + skipped_oversize= = the population the crawl considered) while the population's missing
# members stayed anonymous. `--skipped` names them: one <f p= bytes= limit=/> row per dropped file, where
# limit= is the ceiling that dropped it (--max-file-size, or the fixed .json config ceiling that
# --max-file-size does not raise).
#
# Arms:
#   (0) presence guards — the fixture files this gate greps for actually exist AND actually exceed the
#       ceilings the arms assume (a fixture that shrinks must red here, not pass blind downstream)
#   (1) generic ceiling — under --max-file-size=1K both oversize files are listed with limit="1024",
#       exact bytes=, and the under-ceiling file is NOT listed
#   (2) json lane — under the DEFAULT ceiling only the >256KB .json is listed, with limit="262144"
#   (3) accounting join — the verb's oversize= equals the map header's skipped_oversize= under the same
#       flags, and files= + oversize= = the fixture's candidate population
#   (4) zero means none found — a corpus with nothing oversized reports oversize="0" and no rows
#   (5) purely additive (G5) + header unchanged (G4) — the default map emits no <skipped element and no
#       new header attribute; the verb is only reachable by asking for it
#   (6) determinism — two runs, byte-identical
#   (7) well-formedness (G4) — pipes clean through xmllint when xmllint is available
#   (8) multi-root — a 2-root workspace lists the dropped file under its <label>/./<rel> spelling
#
# Usage:  bash test/skippedcheck.sh      [RIPWIRE_BIN=path/to/binary]
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
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
[ "$smallBytes" -lt 1024 ]   && ok "(0) small.cpp is under the 1K ceiling ($smallBytes B)"   || no "(0) small.cpp is NOT under 1024 B ($smallBytes B) — fixture broken"
[ "$bigBytes" -gt 1024 ]     && ok "(0) big.cpp exceeds the 1K ceiling ($bigBytes B)"        || no "(0) big.cpp does NOT exceed 1024 B ($bigBytes B) — fixture broken"
[ "$jsonBytes" -gt 262144 ]  && ok "(0) data.json exceeds the 256KB json ceiling ($jsonBytes B)" || no "(0) data.json does NOT exceed 262144 B ($jsonBytes B) — fixture broken"

cd "$TMP"   # crawl arg `corpus` → rows spell p="corpus/..." machine-independently

# ── (1) generic ceiling: both oversize files listed with limit="1024", exact bytes= ──────────────────────
"$BIN" corpus --skipped --max-file-size=1K --no-cache > "$TMP/one.xml" 2>/dev/null
rc=$?
[ "$rc" -eq 0 ] && ok "(1) --skipped exits 0 (a report, not a gate)" || no "(1) --skipped exited $rc, expected 0"
grep -q "<f p=\"corpus/big.cpp\" why=\"oversize\" bytes=\"$bigBytes\" limit=\"1024\"/>" "$TMP/one.xml" \
    && ok "(1) big.cpp row carries its exact bytes= and the generic limit=\"1024\"" \
    || { no "(1) big.cpp row missing or wrong (want bytes=\"$bigBytes\" limit=\"1024\")"; head -c 400 "$TMP/one.xml"; echo; }
grep -q "<f p=\"corpus/data.json\" why=\"oversize\" bytes=\"$jsonBytes\" limit=\"1024\"/>" "$TMP/one.xml" \
    && ok "(1) data.json over BOTH ceilings is counted once, at the generic ceiling tested first" \
    || no "(1) data.json row missing or wrong (want bytes=\"$jsonBytes\" limit=\"1024\" — generic ceiling wins)"
grep -q 'p="corpus/small.cpp"' "$TMP/one.xml" \
    && no "(1) small.cpp is listed but was never dropped" \
    || ok "(1) the under-ceiling file is not listed"
grep -q 'oversize="2"' "$TMP/one.xml" && grep -q 'max_file_size="1024"' "$TMP/one.xml" && grep -q 'json_ceiling="262144"' "$TMP/one.xml" \
    && ok "(1) root reports oversize=\"2\" and both effective ceilings" \
    || { no "(1) root element wrong (want oversize=\"2\" max_file_size=\"1024\" json_ceiling=\"262144\")"; head -c 400 "$TMP/one.xml"; echo; }

# ── (2) json lane: default ceiling → only data.json, at the fixed json ceiling ───────────────────────────
"$BIN" corpus --skipped --no-cache > "$TMP/two.xml" 2>/dev/null
grep -q "<f p=\"corpus/data.json\" why=\"oversize\" bytes=\"$jsonBytes\" limit=\"262144\"/>" "$TMP/two.xml" \
    && ok "(2) >256KB .json is dropped by the json lane and says so (limit=\"262144\")" \
    || { no "(2) data.json row missing or wrong under the default ceiling"; head -c 400 "$TMP/two.xml"; echo; }
grep -q 'p="corpus/big.cpp"' "$TMP/two.xml" \
    && no "(2) big.cpp listed under the default 4MB ceiling it does not exceed" \
    || ok "(2) big.cpp is not listed under the default ceiling"
grep -q 'oversize="1"' "$TMP/two.xml" && ok "(2) root reports oversize=\"1\"" || no "(2) root does not report oversize=\"1\""

# ── (3) accounting join: verb count == map header count, and files= + oversize= = population ─────────────
"$BIN" corpus --max-file-size=1K --no-cache > "$TMP/map.xml" 2>/dev/null
mapSkipped="$( grep -o 'skipped_oversize=[0-9]*' "$TMP/map.xml" | head -1 | cut -d= -f2 )"
mapFiles="$(   grep -o 'files=[0-9]*'            "$TMP/map.xml" | head -1 | cut -d= -f2 )"
[ "${mapSkipped:-}" = "2" ] && ok "(3) map header says skipped_oversize=2 — same count the verb itemizes" \
    || no "(3) map header skipped_oversize=${mapSkipped:-<absent>}, verb said 2 — the two surfaces disagree"
[ "${mapFiles:-0}" = "1" ] && ok "(3) files=1 + oversize=2 = the 3-file candidate population" \
    || no "(3) files=${mapFiles:-<absent>}, expected 1 (small.cpp only)"

# ── (4) zero means none found ────────────────────────────────────────────────────────────────────────────
mkdir -p "$TMP/clean"; printf 'int keep( void ) { return 1; }\n' > "$TMP/clean/small.cpp"
"$BIN" clean --skipped --no-cache > "$TMP/zero.xml" 2>/dev/null
grep -q 'oversize="0"' "$TMP/zero.xml" && ok "(4) clean corpus reports oversize=\"0\"" || no "(4) clean corpus does not report oversize=\"0\""
grep -q '<f p="' "$TMP/zero.xml" && no "(4) zero-count report still emits rows" || ok "(4) zero-count report emits no rows"

# ── (5) purely additive (G5) + default header unchanged (G4) ─────────────────────────────────────────────
grep -q 'files=' "$TMP/map.xml" || no "(5) presence guard: default map did not run (no files= header)"
grep -q '<skipped' "$TMP/map.xml" && no "(5) default map emits a <skipped element without being asked" || ok "(5) the verb is purely additive — no <skipped element in the default map"
grep -q 'json_ceiling=' "$TMP/map.xml" && no "(5) default map header gained a new attribute (json_ceiling=)" || ok "(5) default map header carries only the existing skipped_oversize= count"

# ── (6) determinism — same input, byte-identical report ──────────────────────────────────────────────────
"$BIN" corpus --skipped --max-file-size=1K --no-cache > "$TMP/one2.xml" 2>/dev/null
cmp -s "$TMP/one.xml" "$TMP/one2.xml" && ok "(6) two runs, byte-identical" || no "(6) two runs differ"

# ── (7) well-formedness (G4) ─────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/one.xml" 2>/dev/null && ok "(7) report is well-formed XML" || no "(7) report fails xmllint"
else
    ok "(7) xmllint not available — skipped (regression.sh's own gate covers the toolchain that has it)"
fi

# ── (8) multi-root: the dropped file keeps its <label>/./<rel> spelling ──────────────────────────────────
mkdir -p "$TMP/alpha" "$TMP/beta"
cp "$TMP/corpus/big.cpp" "$TMP/alpha/big.cpp"
printf 'int beta_fn( void ) { return 2; }\n' > "$TMP/beta/lib.cpp"
"$BIN" alpha beta --skipped --max-file-size=1K --no-cache > "$TMP/multi.xml" 2>/dev/null
grep -q "<f p=\"alpha/./big.cpp\" why=\"oversize\" bytes=\"$bigBytes\" limit=\"1024\"/>" "$TMP/multi.xml" \
    && ok "(8) multi-root row carries the labeled <label>/./<rel> spelling" \
    || { no "(8) multi-root row missing or unlabeled (want p=\"alpha/./big.cpp\")"; head -c 400 "$TMP/multi.xml"; echo; }
grep -q 'oversize="1"' "$TMP/multi.xml" && ok "(8) multi-root count sums across roots" || no "(8) multi-root count wrong (want oversize=\"1\")"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }
