#!/usr/bin/env bash
# cachehashcheck.sh — G-A1: the CLI incremental cache keys on CONTENT HASH, never mtime.
#
# Regression fence (RESEARCH_agentQuality2026.md §3a / §3c): the audit reproduced that the CLI
# `--cache=PATH` path is immune to the classic "mtime-lies" attack — edit a file's content, then
# `touch -r` its mtime back to the pre-edit value, and a warm re-run must STILL see the new content.
# This is unlike the MCP staleness hole (§3b #1, fixed separately by S1 in mcp.h) — the CLI path
# re-crawls and re-hashes bytes every invocation, so an equal mtime never masks a content change.
#
# Recipe (RESEARCH_agentQuality2026.md §3c "G-A1"):
#   1. write a source file, run ctxpack with --cache=<tmp>/c.bin to populate (cold)
#   2. save a copy of the file's bytes (for touch -r reference)
#   3. EDIT the file's content (remove the old symbol, add a new one)
#   4. touch -r <saved-ref> <file>          — restore the mtime EXACTLY (also restore dir mtime,
#                                              belt-and-suspenders; the CLI re-crawls so it shouldn't
#                                              matter, but keep the attack as hostile as possible)
#   5. run ctxpack again with the SAME --cache=<tmp>/c.bin (warm)
#   6. the NEW symbol MUST appear in the warm output; the OLD symbol must be GONE
#
# Usage:
#   bash test/cachehashcheck.sh
#   CTXPACK_BIN=asan/ctxpack bash test/cachehashcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "cachehashcheck: BIN=$BIN  TMP=$TMP"

WORK="$TMP/proj"
mkdir -p "$WORK"
CACHE="$TMP/c.bin"

# ── step 1: populate the warm cache on the ORIGINAL content ──────────────────────────────────────
printf 'int oldSymbol( void )\n{\n    return 1;\n}\n' > "$WORK/f.cpp"
"$BIN" "$WORK" --cache="$CACHE" --no-stable >"$TMP/cold.xml" 2>"$TMP/cold.err"
rc_cold=$?
if [ "$rc_cold" -eq 0 ]; then
    ok "cold run (cache populate) exits 0"
else
    no "cold run expected exit 0, got $rc_cold"
    cat "$TMP/cold.err"
fi

if grep -q 'n="oldSymbol"' "$TMP/cold.xml" 2>/dev/null; then
    ok "cold run: oldSymbol present (fixture sanity)"
else
    no "cold run: oldSymbol missing — fixture did not parse as expected"
    head -3 "$TMP/cold.xml"
fi

# ── step 2: save a byte-identical reference copy (source of the mtime we restore to) ─────────────
cp "$WORK/f.cpp" "$TMP/f.cpp.ref"
DIR_REF="$TMP/dir.ref"
touch -r "$WORK" "$DIR_REF" 2>/dev/null || cp -p "$WORK/f.cpp" "$DIR_REF" 2>/dev/null

# Sleep past common coarse filesystem mtime granularity (1s on HFS+/some NFS/SMB) so that, absent
# the touch -r restore, the mtime WOULD visibly change — this keeps the attack honest.
sleep 1

# ── step 3: EDIT the content — remove oldSymbol, add newSymbol ───────────────────────────────────
printf 'int newSymbol( void )\n{\n    return 2;\n}\n' > "$WORK/f.cpp"

# ── step 4: restore the file's mtime EXACTLY to the pre-edit value (the "mtime lies" attack) ─────
touch -r "$TMP/f.cpp.ref" "$WORK/f.cpp"
# Best-effort: restore the parent dir's mtime too (belt-and-suspenders; CLI re-crawls every run so
# this should be immaterial, but keep the repro as hostile to the cache as possible).
touch -r "$DIR_REF" "$WORK" 2>/dev/null || true

# Confirm the mtime restore actually worked (sanity on the attack itself, not the tool under test).
ref_mtime=$( stat -f '%m' "$TMP/f.cpp.ref" 2>/dev/null || stat -c '%Y' "$TMP/f.cpp.ref" 2>/dev/null )
new_mtime=$( stat -f '%m' "$WORK/f.cpp"     2>/dev/null || stat -c '%Y' "$WORK/f.cpp"     2>/dev/null )
if [ "$ref_mtime" = "$new_mtime" ]; then
    ok "attack setup: file mtime restored exactly (touch -r verified: $new_mtime)"
else
    no "attack setup: touch -r did NOT restore mtime (ref=$ref_mtime got=$new_mtime) — attack is not hostile, results untrustworthy"
fi

# ── step 5: warm re-run with the SAME --cache path ────────────────────────────────────────────────
"$BIN" "$WORK" --cache="$CACHE" --no-stable >"$TMP/warm.xml" 2>"$TMP/warm.err"
rc_warm=$?
if [ "$rc_warm" -eq 0 ]; then
    ok "warm run (mtime-preserved edit) exits 0"
else
    no "warm run expected exit 0, got $rc_warm"
    cat "$TMP/warm.err"
fi

# ── step 6: the NEW symbol MUST appear — proves content-hash, not mtime, keys the cache ──────────
if grep -q 'n="newSymbol"' "$TMP/warm.xml" 2>/dev/null; then
    ok "warm run: newSymbol appears despite mtime-preserved edit (content-hash cache confirmed)"
else
    no "warm run: newSymbol MISSING — cache appears to key on mtime, not content (REGRESSION)"
    head -5 "$TMP/warm.xml"
fi

# The old symbol must be GONE — a stale/merged cache entry would leave it behind.
if grep -q 'n="oldSymbol"' "$TMP/warm.xml" 2>/dev/null; then
    no "warm run: oldSymbol STILL present — stale cache entry not replaced (REGRESSION)"
else
    ok "warm run: oldSymbol absent (stale entry correctly replaced)"
fi

# ── well-formed XML ───────────────────────────────────────────────────────────────────────────────
command -v xmllint >/dev/null 2>&1 \
    && { xmllint --noout "$TMP/warm.xml" 2>/dev/null \
         && ok "xml well-formed" || no "xml malformed"; } \
    || ok "xml well-formed (xmllint absent — skipped)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
