#!/usr/bin/env bash
# versioncheck.sh — gate for --version (P5, AUDIT5 go-public wave 1).
#
# The version string lives in exactly ONE place: the project(ctxpack VERSION ...) call in
# CMakeLists.txt. --version reads it via the CMake-generated src/version.h (build dir's
# generated/version.h). This gate asserts:
#   (1) --version and -v both exit 0 and print a non-empty line containing "ctxpack".
#   (2) the printed version matches CMakeLists.txt's own project(... VERSION X.Y.Z ...) — the two
#       can never silently drift because there is only one source, but a regression (e.g. someone
#       hardcoding a literal in main.cpp/cli.h instead of reading the generated header) would show
#       up here as a mismatch.
#   (3) --version needs no positional root argument (it must exit before the ingest pipeline —
#       same "first instinct must not error" contract as --help).
#   (4) determinism: two runs print byte-identical output.
#
# Usage:  CTXPACK_BIN=build/ctxpack bash test/versioncheck.sh   |   CTXPACK_BIN=asan/ctxpack bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "versioncheck: BIN=$BIN"

# ── the ONE source of truth: CMakeLists.txt's own project(ctxpack VERSION X.Y.Z ...) ───────────────────
CMAKE_VER="$( grep -oE 'project\(ctxpack VERSION [0-9]+\.[0-9]+\.[0-9]+' "$ROOT/CMakeLists.txt" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' )"
[ -n "$CMAKE_VER" ] || { echo "could not read a VERSION out of CMakeLists.txt's project() call"; exit 2; }

# ── #1: --version and -v both exit 0, non-empty, mentions "ctxpack" ────────────────────────────────────
OUT_LONG="$( "$BIN" --version 2>&1 )"; rc_long=$?
{ [ "$rc_long" -eq 0 ] && [ -n "$OUT_LONG" ] && printf '%s' "$OUT_LONG" | grep -qi ctxpack; } \
    && ok "--version: exit 0, non-empty, names ctxpack ($OUT_LONG)" \
    || no "--version: expected exit 0 + a line naming ctxpack, got exit=$rc_long out='$OUT_LONG'"

OUT_SHORT="$( "$BIN" -v 2>&1 )"; rc_short=$?
{ [ "$rc_short" -eq 0 ] && [ -n "$OUT_SHORT" ]; } \
    && ok "-v: exit 0, non-empty" \
    || no "-v: expected exit 0 + non-empty output, got exit=$rc_short out='$OUT_SHORT'"

# ── #2: the printed version matches CMakeLists.txt's project() VERSION exactly ─────────────────────────
BIN_VER="$( printf '%s' "$OUT_LONG" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 )"
[ "$BIN_VER" = "$CMAKE_VER" ] \
    && ok "--version ($BIN_VER) matches CMakeLists.txt's project() VERSION ($CMAKE_VER) — single source of truth" \
    || no "--version/CMake VERSION MISMATCH: binary says '$BIN_VER', CMakeLists.txt says '$CMAKE_VER' — did version.h go stale?"

# ── #3: --version needs no positional root — must exit before the ingest pipeline, like --help ────────
NO_ARG_OUT="$( cd /tmp && "$BIN" --version 2>&1 )"; rc_noarg=$?
[ "$rc_noarg" -eq 0 ] \
    && ok "--version needs no positional root (exit 0 with no <dir> argument, run from /tmp)" \
    || no "--version failed without a positional root (exit $rc_noarg) — it must short-circuit before ingest"

# ── #4: determinism — two runs print byte-identical output ─────────────────────────────────────────────
OUT2="$( "$BIN" --version 2>&1 )"
[ "$OUT_LONG" = "$OUT2" ] \
    && ok "--version deterministic (byte-identical run-to-run)" \
    || no "--version non-deterministic across re-runs"

# ── #5 (§P6.10, 2026-07-28 output audit): the build-type parenthetical must never say "unspecified" — it
# is the first thing a bug report pastes, and "unspecified" tells the reader nothing about what they ran.
# A plain configure (no -DCMAKE_BUILD_TYPE, the house-mandated local dev configure per CLAUDE.md) must
# print the honest label "dev"; any other value must be a real CMAKE_BUILD_TYPE string (e.g. "Release").
printf '%s' "$OUT_LONG" | grep -qi 'unspecified' \
    && no "--version still says 'unspecified': $OUT_LONG" \
    || ok "--version never says 'unspecified'"
BUILD_TYPE_STR="$( printf '%s' "$OUT_LONG" | grep -oE '\([^,]+,' | sed -E 's/^\(//; s/,$//' )"
[ -n "$BUILD_TYPE_STR" ] \
    && ok "--version names a build type ($BUILD_TYPE_STR)" \
    || no "--version has no build-type parenthetical to check: $OUT_LONG"
CACHE_BUILD_TYPE="$( grep -oE '^CMAKE_BUILD_TYPE:[A-Za-z]*=.*' "$ROOT/build/CMakeCache.txt" 2>/dev/null | cut -d= -f2 )"
if [ -z "$CACHE_BUILD_TYPE" ]; then
    [ "$BUILD_TYPE_STR" = "dev" ] \
        && ok "plain configure (empty CMAKE_BUILD_TYPE) prints the honest label 'dev'" \
        || no "plain configure (empty CMAKE_BUILD_TYPE) prints '$BUILD_TYPE_STR', expected 'dev'"
else
    [ "$BUILD_TYPE_STR" = "$CACHE_BUILD_TYPE" ] \
        && ok "configure with CMAKE_BUILD_TYPE=$CACHE_BUILD_TYPE prints it verbatim" \
        || no "configure with CMAKE_BUILD_TYPE=$CACHE_BUILD_TYPE prints '$BUILD_TYPE_STR' instead"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
