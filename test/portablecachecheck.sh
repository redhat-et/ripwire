#!/usr/bin/env bash
# portablecachecheck.sh — T5 gate: the --cache=FILE artifact is COMMITTABLE/PORTABLE across checkout paths.
#
# The bug (same class as S2's baseline-portability fix DeusData): the
# incremental cache's file-list keys used to be spelled `<ingest-root-ARG>/<relative>` VERBATIM — a cache
# built via `ripwire /home/a/repo --cache=repo.ripwirecache` embedded `/home/a/repo/src/x.cpp`, so consuming
# that SAME cache file at `/home/b/repo` (a different checkout/CI path) missed on every lookup (path strings
# never match) and silently fell back to a full reparse every time — defeating the entire point of a
# COMMITTED cache artifact (team/CI skip the cold parse).
#
# The T5 fix (ingest.cpp only, reusing S2's relForHash from arch.h): saveCache stores each file key
# ROOT-RELATIVE (relForHash(path, rootDir)); loadCache re-absolutizes each key against the CURRENT
# invocation's rootDir before the map is used, so `cache.find(path)` inside ingest() needs no changes and a
# cache built under root A warm-hits identically under root B. kCacheVersion bumped 2->3 so an OLD
# (pre-T5, absolute-path-keyed) cache is rejected by the magic/version guard rather than silently
# misread — it degrades to a full reparse (self-healing), never a crash or wrong output.
#
# This gate proves, end to end:
#   (a) PORTABILITY: build a --cache=FILE under path A (a copy of the fixture), copy that SAME cache file
#       (byte-for-byte, `cp`) to be consumed under path B (a SEPARATE copy of the fixture) → output from
#       the B-consumed-A's-cache run is BYTE-IDENTICAL to a cold (--no-cache) run at B. This is the
#       headline claim: "a team can commit repo.ripwirecache and everyone (and CI) skips the cold parse."
#   (b) warm==cold STILL HOLDS at the SAME path (the existing determinism contract untouched by T5).
#   (c) an OLD-FORMAT (pre-T5, absolute-path-keyed) cache self-invalidates cleanly: doctoring a fresh
#       cache's version field down to 2 must not crash and must still produce byte-identical output to a
#       cold run (full reparse, self-healing — never a wrong/stale answer).
#   (d) a cache built at A and consumed UNCHANGED at A (no path change at all) still warm-hits (sanity:
#       the round-trip isn't accidentally always missing).
#   (e) mutation test: prove the byte-identical comparisons above are live, not vacuously true.
#
# Usage:
#   bash test/portablecachecheck.sh
#   RIPWIRE_BIN=asan/ripwire bash test/portablecachecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "portablecachecheck: BIN=$BIN  TMP=$TMP"

FIXTURE="$ROOT/test/fixture"

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (a) PORTABILITY — build at path A, consume the SAME cache file at DIFFERENT path B, byte-identical to
#     a cold run at B.
# ════════════════════════════════════════════════════════════════════════════════════════════════════
PATH_A="$TMP/checkout_a/repo"
PATH_B="$TMP/checkout_b/repo"
mkdir -p "$( dirname "$PATH_A" )" "$( dirname "$PATH_B" )"
cp -R "$FIXTURE" "$PATH_A"
cp -R "$FIXTURE" "$PATH_B"

CACHE_FILE="$TMP/repo.ripwirecache"

# build the cache under path A (this IS the "commit repo.ripwirecache from CI/teammate A" step)
"$BIN" "$PATH_A" --cache="$CACHE_FILE" --no-stable >"$TMP/a_build.xml" 2>"$TMP/a_build.err"
rc_a=$?
if [ "$rc_a" -eq 0 ] && [ -s "$CACHE_FILE" ]; then
    ok "(a) cache built under path A, exit 0, cache file non-empty"
else
    no "(a) cache build under path A failed (exit $rc_a)"; cat "$TMP/a_build.err"
fi

# snapshot the cache bytes exactly as "committed" — consume that SAME file (no rebuild) under path B
cp "$CACHE_FILE" "$TMP/repo.ripwirecache.committed"

BEFORE_SUM="$( md5 -q "$TMP/repo.ripwirecache.committed" 2>/dev/null || md5sum "$TMP/repo.ripwirecache.committed" | cut -d' ' -f1 )"

"$BIN" "$PATH_B" --cache="$TMP/repo.ripwirecache.committed" --no-stable >"$TMP/b_warm.xml" 2>"$TMP/b_warm.err"
rc_b=$?
if [ "$rc_b" -eq 0 ]; then
    ok "(a) consuming A's committed cache under path B exits 0"
else
    no "(a) consuming A's committed cache under path B failed (exit $rc_b)"; cat "$TMP/b_warm.err"
fi

# THE HEADLINE ASSERTION: did B actually WARM-HIT against A's cache, or did every lookup silently miss
# (falling back to a full reparse that happens to still produce correct output, defeating the entire
# "skip the cold parse" point while masquerading as success)? Win-2's dirty-flag means saveCache is
# skipped entirely when nothing changed — so an unchanged cache file (same bytes before/after) is
# PROOF every file hash-matched via the re-absolutized key, i.e. a genuine warm hit, not a disguised miss.
AFTER_SUM="$( md5 -q "$TMP/repo.ripwirecache.committed" 2>/dev/null || md5sum "$TMP/repo.ripwirecache.committed" | cut -d' ' -f1 )"
if [ "$BEFORE_SUM" = "$AFTER_SUM" ]; then
    ok "(a) GENUINE WARM HIT: consuming A's cache at path B left the cache bytes UNCHANGED (every file hash-matched — not a disguised full reparse)"
else
    no "(a) DISGUISED MISS: path B rewrote the committed cache (bytes changed) — every lookup missed and silently fell back to a full reparse; the cache is NOT actually being reused across checkout paths, even though output may still look correct"
fi

# ground truth: a COLD run at path B (fresh cache file, never touched by A's build)
"$BIN" "$PATH_B" --cache="$TMP/b_cold.cache" --no-stable >"$TMP/b_cold.xml" 2>"$TMP/b_cold.err"
rc_bc=$?
[ "$rc_bc" -eq 0 ] || { no "(a) cold run at path B failed (exit $rc_bc)"; cat "$TMP/b_cold.err"; }

if diff -q "$TMP/b_warm.xml" "$TMP/b_cold.xml" >/dev/null 2>&1; then
    ok "(a) PORTABLE: B-consumed-A's-cache output is BYTE-IDENTICAL to a cold run at B"
else
    no "(a) NOT PORTABLE: B-consumed-A's-cache output DIFFERS from a cold run at B"
    diff "$TMP/b_cold.xml" "$TMP/b_warm.xml" | head -10
fi

# the committed cache file itself must have been left untouched by B's read (portable caches are
# read-shared by many checkouts; a consuming run must not mutate the artifact another checkout owns)
if diff -q "$CACHE_FILE" "$TMP/repo.ripwirecache.committed" >/dev/null 2>&1; then
    ok "(a) reading the committed cache under path B did not mutate the original bytes"
else
    no "(a) reading the committed cache under path B mutated it in place"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (b) warm == cold STILL HOLDS at the SAME path — the pre-existing determinism contract, unbroken by T5.
# ════════════════════════════════════════════════════════════════════════════════════════════════════
SAME_CACHE="$TMP/same.cache"
"$BIN" "$PATH_A" --cache="$SAME_CACHE" --no-stable >"$TMP/same_cold.xml" 2>/dev/null
"$BIN" "$PATH_A" --cache="$SAME_CACHE" --no-stable >"$TMP/same_warm.xml" 2>/dev/null
if diff -q "$TMP/same_cold.xml" "$TMP/same_warm.xml" >/dev/null 2>&1; then
    ok "(b) warm == cold at the SAME path still holds (T5 did not regress the base determinism contract)"
else
    no "(b) warm != cold at the same path — T5 broke the existing cache-transparency contract"
    diff "$TMP/same_cold.xml" "$TMP/same_warm.xml" | head -10
fi

# and a NO-CACHE cold parse must equal a --cache cold parse regardless of root spelling (path A vs B),
# proving there is nothing path-A-specific baked into the output itself (only the cache-key spelling
# was ever root-dependent).
"$BIN" "$PATH_A" --no-cache --no-stable >"$TMP/a_nocache.xml" 2>/dev/null
if diff -q "$TMP/a_nocache.xml" "$TMP/same_cold.xml" >/dev/null 2>&1; then
    ok "(b) --no-cache cold parse at A matches the --cache cold parse at A (cache is output-transparent)"
else
    no "(b) --no-cache and --cache cold parses at A differ"
    diff "$TMP/a_nocache.xml" "$TMP/same_cold.xml" | head -10
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (c) OLD-FORMAT (pre-T5) cache self-invalidates cleanly: never crashes, never silently misreads a
#     path that isn't actually root-relative. We fabricate this by taking a FRESH v3 cache and flipping
#     just the on-disk kCacheVersion field (byte offset 4..7, little-endian u32) down to 2 — the exact
#     mismatch a real pre-T5-built cache would trigger against the new binary's version guard.
# ════════════════════════════════════════════════════════════════════════════════════════════════════
OLDFMT="$TMP/oldformat.cache"
cp "$SAME_CACHE" "$OLDFMT"

python3 - "$OLDFMT" <<'PYEOF'
import sys, struct
path = sys.argv[1]
with open(path, "r+b") as f:
    f.seek(4)                       # magic is bytes[0:4]; version is bytes[4:8]
    f.write(struct.pack("<I", 2))   # downgrade kCacheVersion 3 -> 2 (simulates a pre-T5 cache)
PYEOF

"$BIN" "$PATH_A" --cache="$OLDFMT" --no-stable >"$TMP/oldfmt_out.xml" 2>"$TMP/oldfmt.err"
rc_old=$?
if [ "$rc_old" -eq 0 ]; then
    ok "(c) an old-version (v2) cache does not crash — exit 0"
else
    no "(c) old-version cache crashed or exited non-zero ($rc_old)"; cat "$TMP/oldfmt.err"
fi

if diff -q "$TMP/oldfmt_out.xml" "$TMP/same_cold.xml" >/dev/null 2>&1; then
    ok "(c) old-version cache self-invalidates cleanly — output byte-identical to a fresh cold run (full reparse, self-healing)"
else
    no "(c) old-version cache produced output DIFFERENT from a cold run — version guard did not reject it correctly"
    diff "$TMP/same_cold.xml" "$TMP/oldfmt_out.xml" | head -10
fi

# a corrupt cache (garbage bytes, not even a valid header) must degrade the same way, never crash — belt
# and suspenders alongside the existing checksum-trailer coverage (this exercises the NEW read path
# specifically, since loadCache's re-absolutize step runs on every accepted record).
CORRUPT="$TMP/corrupt.cache"
head -c 200 /dev/urandom > "$CORRUPT" 2>/dev/null || dd if=/dev/urandom of="$CORRUPT" bs=200 count=1 2>/dev/null
"$BIN" "$PATH_A" --cache="$CORRUPT" --no-stable >"$TMP/corrupt_out.xml" 2>"$TMP/corrupt.err"
rc_corrupt=$?
if [ "$rc_corrupt" -eq 0 ] && diff -q "$TMP/corrupt_out.xml" "$TMP/same_cold.xml" >/dev/null 2>&1; then
    ok "(c) a fully corrupt/garbage cache file degrades cleanly to a full reparse (byte-identical to cold, exit 0)"
else
    no "(c) a corrupt cache file did not degrade cleanly (exit $rc_corrupt)"
    cat "$TMP/corrupt.err"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (d) sanity — a cache built and consumed at the SAME path (A) actually WARM-HITS (proves the round-trip
#     isn't just "always misses, always reparses", which would make check (a) vacuously pass).
# ════════════════════════════════════════════════════════════════════════════════════════════════════
DIRTY_PROBE="$TMP/dirty_probe.cache"
"$BIN" "$PATH_A" --cache="$DIRTY_PROBE" --no-stable >/dev/null 2>&1     # cold populate
# L3 (Linux probe): portable stat reader(s). GNU coreutils and BSD/macOS disagree on both the flag and the
# format directives, and the `stat -f FMT ... || stat -c FMT ...` fallback this gate used is a TRAP. On GNU,
# `-f` means FILESYSTEM status and takes NO format argument, so FMT is parsed as a second FILE: measured on
# coreutils 9.11, `stat -f %i FILE` PRINTS a six-line filesystem block for FILE on stdout and exits 1. The
# `||` arm then appends the right number under six lines of junk -- so a string compare fails, a numeric
# compare dies with "integer expression expected", and a `|| echo MISSING` variant reports MISSING forever
# (a gate that then passes by comparing nothing to nothing). Detect the flavour ONCE, use one form.
if stat --version >/dev/null 2>&1; then   # GNU coreutils
    mtime_of(){ stat -c '%Y' "$1" 2>/dev/null; }
    size_of(){  stat -c '%s' "$1" 2>/dev/null; }
else                                     # BSD / macOS
    mtime_of(){ stat -f '%m' "$1" 2>/dev/null; }
    size_of(){  stat -f '%z' "$1" 2>/dev/null; }
fi

BEFORE_SIZE="$( size_of "$DIRTY_PROBE" )"
# touch nothing; re-run warm — the cache file must NOT be rewritten (Win-2 dirty-flag: unchanged tree
# skips saveCache entirely), which only happens if every file HASH-MATCHED against a re-absolutized key.
BEFORE_MTIME="$( mtime_of "$DIRTY_PROBE" )"
sleep 1
"$BIN" "$PATH_A" --cache="$DIRTY_PROBE" --no-stable >/dev/null 2>&1
AFTER_MTIME="$( mtime_of "$DIRTY_PROBE" )"
if [ "$BEFORE_MTIME" = "$AFTER_MTIME" ]; then
    ok "(d) same-path warm run skips saveCache entirely (dirty flag stayed clear -> every key actually hash-matched via re-absolutize)"
else
    no "(d) same-path warm run rewrote the cache — keys are not round-tripping/matching as expected"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (e) mutation test — prove the byte-identical comparisons above are live, not vacuously true.
# ════════════════════════════════════════════════════════════════════════════════════════════════════
if diff -q "$TMP/b_cold.xml" "$TMP/a_build.xml" >/dev/null 2>&1; then
    no "mutation-test: path-A's own build output should differ from path-B's cold output only in path spelling inside the XML — got byte-identical, which would make check (a) suspiciously easy (files may be trivial/empty)"
else
    ok "mutation-test: A-build output and B-cold output DO differ where expected (proves diff -q above is a real, non-vacuous comparison — path spelling is embedded in the output)"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
