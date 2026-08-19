#!/usr/bin/env bash
# lintdedupcheck.sh — §P6.1 gate: --lint must never emit two byte-identical <f> rows.
#
# The reported case: bench/bench_convergence.cpp:47 has `h ^= h >> 33; ... h ^= h >> 33;` —
# two DISTINCT number_literal AST nodes (different startByte) with the same value "33", on the
# same line, in the same function (shardOf). --lint's row shape carries only file:line (no
# column), so both captures render as the identical row
#   <f rule="magic-number" p="./bench/bench_convergence.cpp:47" in="shardOf">33</f>
# twice — a reader sees a "duplicate" finding with no way to tell the two apart or act on them
# differently. The fix collapses rows that would render byte-identically (same rule, sev,
# file:line, enclosing symbol, text) to ONE, keeping findings=/rule count= truthful (they count
# distinct VISIBLE findings, not raw AST captures) — see src/main.cpp's §P6.1 comment.
#
#   RIPWIRE_BIN=build/ripwire bash test/lintdedupcheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/lintdedupcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIXTURE="$ROOT/test/lintdedupfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]     || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIXTURE" ] || { echo "no test/lintdedupfix dir — fixture missing"; exit 2; }

echo "lintdedupcheck: BIN=$BIN  FIXTURE=$FIXTURE"

# ── 1) minimal fixture: the repeated-value line must yield exactly ONE row, not two ─────────────
# cd into the fixture/root so p= comes out root-relative ("./dup.cpp", "./bench/...") — matches
# the shape the reported bug was described in, and keeps this script location-independent.
( cd "$FIXTURE" && "$BIN" . --lint --no-cache >"$TMP/fixture_out" 2>"$TMP/fixture_err" )
FIX_RC=$?
[ "$FIX_RC" -eq 0 ] && ok "--lint exits 0 on fixture" || no "--lint exited $FIX_RC on fixture"

# RE-PINNED 2026-08-19 (R-E CORRECTION): with the crawl root spelled ".", p= used to read "./dup.cpp";
# root-relative p= drops that prefix, so the row is p="dup.cpp:8". Nothing about the dedup moved.
DUP33_COUNT=$( grep -o '<f rule="magic-number" p="dup\.cpp:8" in="scramble">33</f>' "$TMP/fixture_out" | wc -l | tr -d ' ' )
[ "$DUP33_COUNT" = "1" ] \
    && ok "the shardOf-class duplicate (two same-value literals, one line) collapses to exactly 1 row (got $DUP33_COUNT)" \
    || no "expected exactly 1 collapsed row for dup.cpp:8 magic-number 33, got $DUP33_COUNT"

# ── 2) no byte-identical <f>...</f> row appears twice anywhere in the fixture's output ──────────
FIXTURE_DUPES=$( grep -oE '<f [^>]*>[^<]*</f>' "$TMP/fixture_out" | sort | uniq -d | wc -l | tr -d ' ' )
[ "$FIXTURE_DUPES" = "0" ] \
    && ok "no byte-identical <f> rows in fixture output" \
    || { no "found $FIXTURE_DUPES byte-identical <f> row group(s) in fixture output"; grep -oE '<f [^>]*>[^<]*</f>' "$TMP/fixture_out" | sort | uniq -d | head -5; }

# ── 3) findings= header and the magic-number rule count= must match the deduped row count ───────
HEADER_FINDINGS=$( grep -o 'findings="[0-9]*"' "$TMP/fixture_out" | head -1 | grep -o '[0-9]*' )
ROW_COUNT=$( grep -oE '<f rule=' "$TMP/fixture_out" | wc -l | tr -d ' ' )
[ "$HEADER_FINDINGS" = "$ROW_COUNT" ] \
    && ok "findings=\"$HEADER_FINDINGS\" matches the actual emitted row count ($ROW_COUNT)" \
    || no "findings=\"$HEADER_FINDINGS\" does NOT match emitted row count ($ROW_COUNT) — count/row mismatch"

# ── 4) xmllint-clean ──────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    ( cd "$FIXTURE" && "$BIN" . --lint --no-cache 2>/dev/null ) | xmllint --noout - \
        && ok "fixture --lint output is xmllint-clean" \
        || no "fixture --lint output failed xmllint"
fi

# ── 5) determinism: run twice, diff ──────────────────────────────────────────────────────────
( cd "$FIXTURE" && "$BIN" . --lint --no-cache >"$TMP/out1" 2>/dev/null )
( cd "$FIXTURE" && "$BIN" . --lint --no-cache >"$TMP/out2" 2>/dev/null )
diff -q "$TMP/out1" "$TMP/out2" >/dev/null \
    && ok "deterministic (byte-identical run-to-run)" \
    || { no "non-deterministic output"; diff "$TMP/out1" "$TMP/out2" | head -8; }

# ── 6) real-world proof: the whole repo's --lint output (the originally reported corpus) has
#      zero byte-identical <f> rows, including the exact reported bench_convergence.cpp:47 case ──
( cd "$ROOT" && "$BIN" . --lint --no-cache >"$TMP/repo_out" 2>/dev/null )
REPO_DUPES=$( grep -oE '<f [^>]*>[^<]*</f>' "$TMP/repo_out" | sort | uniq -d | wc -l | tr -d ' ' )
[ "$REPO_DUPES" = "0" ] \
    && ok "whole-repo --lint output has zero byte-identical <f> rows" \
    || { no "whole-repo --lint output has $REPO_DUPES byte-identical <f> row group(s)"; grep -oE '<f [^>]*>[^<]*</f>' "$TMP/repo_out" | sort | uniq -d | head -5; }

REPORTED_COUNT=$( grep -o '<f rule="magic-number" p="bench/bench_convergence\.cpp:47" in="shardOf">33</f>' "$TMP/repo_out" | wc -l | tr -d ' ' )
[ "$REPORTED_COUNT" = "1" ] \
    && ok "the originally-reported bench_convergence.cpp:47 shardOf/33 row now appears exactly once (got $REPORTED_COUNT)" \
    || no "expected exactly 1 occurrence of the reported row, got $REPORTED_COUNT"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
