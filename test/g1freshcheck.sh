#!/usr/bin/env bash
# g1freshcheck.sh — gate for F-OPS (AUDIT5): detect stale asan binary.
#
# The G1 (ASan/UBSan) gate can silently run a STALE asan binary: a dead FetchContent
# source-dir cache var fails the build at *generate* time while the old `asan/ctxpack`
# remains and "passes" the old code.
#
# This gate ensures that if asan/ctxpack exists on disk, its mtime is at least as
# recent as the newest file under src/ (the source code it should have been built from).
# If stale, it fails loudly with rebuild instructions.
#
# Usage:
#   test/g1freshcheck.sh
#   CTXPACK_BIN=build_p5w4/ctxpack test/g1freshcheck.sh
#
# Exits non-zero on any failure (stale binary); exits zero if check passes or is skipped
# (asan/ not configured). Prints PASS/SKIP per check.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
ASAN_BIN="$ROOT/asan/ctxpack"
ASAN_DIR="$ROOT/asan"
SRC_DIR="$ROOT/src"
CMAKE_FILE="$ROOT/CMakeLists.txt"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
skip(){ printf '  SKIP  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "g1freshcheck: checking for stale asan binary"

# If asan/ was never configured, skip this check.
if [ ! -d "$ASAN_DIR" ]; then
    skip "asan directory not configured (skip)"
    # A SKIP asserted nothing; saying "ALL PASS" here is the skip-as-pass conflation §B15 forbids.
    echo "SKIP — nothing asserted (asan/ not configured)"
    exit 0
fi

# If asan/ctxpack doesn't exist, skip (asan/ exists but binary not built yet).
if [ ! -f "$ASAN_BIN" ]; then
    skip "asan/ctxpack not yet built (skip)"
    echo "SKIP — nothing asserted (asan/ctxpack not built)"
    exit 0
fi

# Both asan/ctxpack and src/ exist. Check if the binary is older than the newest src file.
asan_mtime="$( stat -f '%m' "$ASAN_BIN" 2>/dev/null || stat -c '%Y' "$ASAN_BIN" 2>/dev/null )" || {
    no "could not stat asan/ctxpack"
    exit 1
}

# item 6 (§B12 polish round): every src/*.h is transitively shared (this repo is header-heavy, ~one TU per
# .cpp), so ALL headers stay in the mtime sweep — but a .cpp file is NOT automatically relevant: src/tsprobe.cpp
# links only into `ctxpack_probe` (CMakeLists.txt: add_executable(ctxpack_probe src/tsprobe.cpp ${CTXPACK_SRCS}
# ...)), never into `ctxpack`/`asan/ctxpack`. Touching it used to mark asan/ctxpack stale for no reason (3 false
# failures this session). Fix: derive the `ctxpack` target's OWN .cpp list from CMakeLists.txt itself — the
# add_executable(ctxpack ...) block (lists src/main.cpp directly) plus the set(CTXPACK_SRCS ...) block it
# pulls in (src/ingest.cpp, src/pagerank.cpp) — instead of hardcoding a name or globbing every src/*.cpp
# indiscriminately. This re-derives every run, so it cannot rot the way a hand-maintained list would if a new
# .cpp is added to the real target.
#
# Safety net: if CMakeLists.txt's shape ever changes enough that this parse comes back empty (or missing the
# one .cpp we know must be there), FALL BACK to checking every src/*.cpp — degrade towards catching more
# staleness, never towards silently checking nothing. A genuinely stale binary must still fail either way.
ctxpack_cpp_files="$( { awk '/^add_executable\(ctxpack$/,/\)/' "$CMAKE_FILE"; awk '/^set\(CTXPACK_SRCS$/,/^\)/' "$CMAKE_FILE"; } \
    | grep -oE 'src/[A-Za-z0-9_./]+\.cpp' | sort -u )"
# NOTE: this is an informational fallback, not a recorded failure — it does not touch `fail`. Widening the
# sweep back to "every src/*.cpp" only makes the gate MORE likely to (correctly) catch staleness, never less,
# so there is nothing here for the accumulator to record.
if [ -z "$ctxpack_cpp_files" ] || ! printf '%s\n' "$ctxpack_cpp_files" | grep -q '^src/main\.cpp$'; then
    printf '  INFO  could not derive ctxpack .cpp sources from CMakeLists.txt (parse came back empty or missing src/main.cpp) — falling back to the full src/*.cpp glob\n'
    ctxpack_cpp_files="$( cd "$ROOT" && printf '%s\n' src/*.cpp )"
fi

# Find the newest (most recent) mtime among: every src/*.h (shared), every src/*.inl (shared), and the
# derived .cpp list (target-scoped — excludes probe/test-only .cpp files like src/tsprobe.cpp).
newest_src_mtime=0
newest_src_file=""
for f in "$SRC_DIR"/*.h "$SRC_DIR"/*.inl; do
    [ -f "$f" ] || continue
    f_mtime="$( stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null )"
    if [ "$f_mtime" -gt "$newest_src_mtime" ]; then newest_src_mtime="$f_mtime"; newest_src_file="$f"; fi
done
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    f="$ROOT/$rel"
    [ -f "$f" ] || continue
    f_mtime="$( stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null )"
    if [ "$f_mtime" -gt "$newest_src_mtime" ]; then newest_src_mtime="$f_mtime"; newest_src_file="$f"; fi
done <<EOF
$ctxpack_cpp_files
EOF

# If asan binary is older than the newest src file, it's stale.
if [ "$asan_mtime" -lt "$newest_src_mtime" ]; then
    no "stale asan binary (mtime older than ${newest_src_file#"$ROOT"/})"
    cat >&2 <<'EOF'

  ──────────────────────────────────────────────────────────────────────────────
  The asan/ctxpack binary is stale (older than the source code).

  Rebuild with:
    cmake --build asan -j

  If cmake generate fails on a FETCHCONTENT_SOURCE_DIR_* cache entry, delete that
  entry from the cache and retry:
    cmake --build asan -j
  ──────────────────────────────────────────────────────────────────────────────

EOF
    exit 1
fi

ok "asan binary is fresh (mtime >= newest src/ file)"

# CA4 §B15 / trap #27, third instance: `no()` sets `fail`, and until this line `fail` was written and NEVER
# READ — the file ended `echo "ALL PASS"; exit 0`. Both live `no` call-sites happen to be followed by an
# explicit `exit 1`, so nothing rode along green; but an accumulator nobody reads is the un-failable gate one
# edit away, and that edit is exactly what wave 3 made to notescheck. Read it. (test/gateexitcheck.sh arm B.)
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
