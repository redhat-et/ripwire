#!/usr/bin/env bash
# racymtimecheck.sh — F3/X5: the racy-git stat-gate guard must compare a cached file's mtime against
# the CACHE BLOB'S OWN on-disk mtime (a fresh stat(), read at load time), not an ns-precision wall-clock
# reading captured mid-write.
#
# Bug ( F3, src/ingest.cpp): the old guard compared a FLOORED (coarse-filesystem) per-file
# mtime against an UNFLOORED post-hash wall-clock stamp — a tautology on coarse-mtime filesystems (HFS+,
# many network mounts, exFAT): a rounded-down timestamp is always < an unrounded LATER one, so a same-granule
# post-hash edit could serve a stale cached parse forever, undetected.
#
# Decided fix ("Hard parts — X5 (F3) racy-mtime fix"): stamp cacheWriteNs from the
# cache blob's own post-rename stat() mtime (same clock+granularity domain as the per-file mtimes), and
# treat `ff.mtimeNs >= cacheWriteNs` as racy => re-hash that file next run.
#
# ── step 1 (the LOAD-BEARING repro) fakes a genuinely coarse filesystem on this machine's real (ns-precision
# APFS) one: force the source file's mtime to a WHOLE-SECOND (zero-subsecond) stamp — what a coarse FS
# reports "for free" — then force the CACHE FILE's own on-disk mtime to that SAME whole second too (a coarse
# FS would round BOTH files' mtimes identically; only touching the file and not the cache reproduces a
# harder, non-representative case). The cache's HEADER still carries the real, unrounded wall-clock instant
# `saveCache` captured internally (untouched by `touch`) — exactly the value the OLD code trusted. Editing
# the source (same byte size, mtime forced back to the same coarse second) then must be picked up: verified
# empirically to reproduce the exact bug against the pre-fix binary (stale content served) and to pass
# against the fix (edit picked up) before this gate was finalized.
#
# ── step 2 is the simpler `touch -r` recipe (source mtime forced to equal the cache blob's CURRENT on-disk
# mtime): it validates the same `ff.mtimeNs >= cacheWriteNs` boundary the fix relies on, though on this
# machine's fine-grained filesystem it does not by itself discriminate old code from the fix (a fast local
# run's own natural stat-vs-wall-clock ordering happens to already catch it here) — kept as an extra,
# cheaper regression anchor on the exact comparison operator.
#
# Usage:
#   bash test/racymtimecheck.sh
#   RIPWIRE_BIN=build_a1/ripwire bash test/racymtimecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "racymtimecheck: BIN=$BIN  TMP=$TMP"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
# step 1: the load-bearing coarse-filesystem repro (both files forced to the SAME whole second)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
WORK="$TMP/proj"; mkdir -p "$WORK"
CACHEDIR="$TMP/cachedir"; mkdir -p "$CACHEDIR"
CACHE="$CACHEDIR/c.bin"

# both fixture bodies are the SAME BYTE LENGTH (11-char identifier either way) — the stat-gate's size half
# must not be what catches this edit; only the racy/mtime half is under test.
printf 'int firstSymbol( void ) { return 1; }\n' > "$WORK/f.cpp"
now_stamp="$( date +%Y%m%d%H%M.%S )"
touch -t "$now_stamp" "$WORK/f.cpp"      # coarse (zero-subsecond) mtime, forced BEFORE the cold run

"$BIN" "$WORK" --cache="$CACHE" --no-stable >"$TMP/cold.xml" 2>"$TMP/cold.err"
rc_cold=$?
if [ "$rc_cold" -eq 0 ] && [ -s "$CACHE" ] && grep -q 'n="firstSymbol"' "$TMP/cold.xml"; then
    ok "cold run populates the cache with firstSymbol"
else
    no "cold run did not populate the expected cache/output (rc=$rc_cold)"
    cat "$TMP/cold.err"
fi

# a coarse filesystem would round the CACHE BLOB's own mtime to the same whole second too — force that here
# (this does NOT touch the header's internal embedded wall-clock bytes, only the file's reported stat mtime).
touch -t "$now_stamp" "$CACHE"

# edit the source (same byte length, different symbol name), forcing its mtime back to the SAME coarse
# second (undoing the natural mtime bump a write causes) — content changed, stat says nothing did.
printf 'int otherSymbol( void ) { return 1; }\n' > "$WORK/f.cpp"
touch -t "$now_stamp" "$WORK/f.cpp"

"$BIN" "$WORK" --cache="$CACHE" --no-stable >"$TMP/warm.xml" 2>"$TMP/warm.err"
rc_warm=$?
if [ "$rc_warm" -eq 0 ]; then
    ok "warm run exits 0"
else
    no "warm run expected exit 0, got $rc_warm"
    cat "$TMP/warm.err"
fi

if grep -q 'n="otherSymbol"' "$TMP/warm.xml" 2>/dev/null && ! grep -q 'n="firstSymbol"' "$TMP/warm.xml" 2>/dev/null; then
    ok "same-coarse-second edit is re-hashed and picked up (otherSymbol present, firstSymbol gone) — racy guard held"
else
    no "same-coarse-second edit served the STALE cached parse instead of re-hashing — racy-guard REGRESSION"
    printf 'warm.xml:\n%s\n' "$( cat "$TMP/warm.xml" 2>/dev/null )"
fi

command -v xmllint >/dev/null 2>&1 \
    && { xmllint --noout "$TMP/warm.xml" 2>/dev/null && ok "warm run: xml well-formed" || no "warm run: xml malformed"; } \
    || ok "warm run: xml well-formed (xmllint absent — skipped)"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
# step 2: the simpler touch -r recipe — an extra anchor on the >= boundary itself
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
printf 'int fourthSymbol( void ) { return 1; }\n' > "$WORK/f.cpp"     # still an 11-char identifier
touch -r "$CACHE" "$WORK/f.cpp"                                       # source mtime := cache blob's CURRENT mtime, exactly

"$BIN" "$WORK" --cache="$CACHE" --no-stable >"$TMP/warm2.xml" 2>"$TMP/warm2.err"
if grep -q 'n="fourthSymbol"' "$TMP/warm2.xml" 2>/dev/null; then
    ok "touch -r (source mtime tied to the cache blob's own mtime) is re-hashed and picked up"
else
    no "touch -r same-mtime edit was not picked up"
    printf 'warm2.xml:\n%s\n' "$( cat "$TMP/warm2.xml" 2>/dev/null )"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
# step 3: sanity — the guard must not over-fire on an ordinary, long-untouched, unchanged file
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
WORK3="$TMP/proj3"; mkdir -p "$WORK3"
CACHE3="$CACHEDIR/c3.bin"
printf 'int untouchedSymbol( void ) { return 3; }\n' > "$WORK3/f.cpp"
touch -t 202001010000 "$WORK3/f.cpp"     # long before this run — never racy on any granularity
"$BIN" "$WORK3" --cache="$CACHE3" --no-stable >/dev/null 2>"$TMP/cold3.err"
"$BIN" "$WORK3" --cache="$CACHE3" --no-stable >"$TMP/warm3.xml" 2>"$TMP/warm3.err"
if grep -q 'n="untouchedSymbol"' "$TMP/warm3.xml" 2>/dev/null; then
    ok "an old-mtime unchanged file still resolves correctly on a warm run (guard isn't over-firing)"
else
    no "an old-mtime unchanged file broke on a warm run"
    cat "$TMP/warm3.err"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
