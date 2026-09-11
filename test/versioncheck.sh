#!/usr/bin/env bash
# versioncheck.sh — gate for --version (P5, go-public wave 1).
#
# The version string lives in exactly ONE place: the project(ripwire VERSION ...) call in
# CMakeLists.txt. --version reads it via the CMake-generated src/version.h (build dir's
# generated/version.h). This gate asserts:
#   (1) --version and -v both exit 0 and print a non-empty line containing "ripwire".
#   (2) the printed version matches CMakeLists.txt's own project(... VERSION X.Y.Z ...) — the two
#       can never silently drift because there is only one source, but a regression (e.g. someone
#       hardcoding a literal in main.cpp/cli.h instead of reading the generated header) would show
#       up here as a mismatch.
#   (3) --version needs no positional root argument (it must exit before the ingest pipeline —
#       same "first instinct must not error" contract as --help).
#   (4) determinism: two runs print byte-identical output.
#   (5) source-build provenance: a git checkout prints its short HEAD and a dirty checkout says so.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/versioncheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "versioncheck: BIN=$BIN"

# ── the ONE source of truth: CMakeLists.txt's own project(ripwire VERSION X.Y.Z ...) ───────────────────
CMAKE_VER="$( grep -oE 'project\(ripwire VERSION [0-9]+\.[0-9]+\.[0-9]+' "$ROOT/CMakeLists.txt" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' )"
[ -n "$CMAKE_VER" ] || { echo "could not read a VERSION out of CMakeLists.txt's project() call"; exit 2; }

# ── #1: --version and -v both exit 0, non-empty, mentions "ripwire" ────────────────────────────────────
OUT_LONG="$( "$BIN" --version 2>&1 )"; rc_long=$?
{ [ "$rc_long" -eq 0 ] && [ -n "$OUT_LONG" ] && printf '%s' "$OUT_LONG" | grep -qi ripwire; } \
    && ok "--version: exit 0, non-empty, names ripwire ($OUT_LONG)" \
    || no "--version: expected exit 0 + a line naming ripwire, got exit=$rc_long out='$OUT_LONG'"

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

# ── source revision provenance. Release archives may be built from an exported tree with no .git,
# where the honest value is "unknown"; a binary built in THIS checkout has no such excuse. The stamp
# must name the configured checkout's HEAD and disclose whether tracked source differed at build time.
EXPECTED_SHA="$( git -C "$ROOT" rev-parse --short=9 HEAD 2>/dev/null || true )"
if [ -n "$EXPECTED_SHA" ]; then
    # §L10b LOW tail: was a bare "git <sha>" — labelled built_from= (matching --doctor's own attribute
    # for the identical fact, verbs_doctor.h) so a reader cannot mistake it for the tree's CURRENT HEAD
    # (--doctor's separate at=, which moves the moment you commit without rebuilding; this one does not).
    printf '%s' "$OUT_LONG" | grep -q "built_from=$EXPECTED_SHA" \
        && ok "--version names source revision as built_from=$EXPECTED_SHA" \
        || no "--version omits built_from=$EXPECTED_SHA: $OUT_LONG"

    # The clean/dirty split must use the SAME predicate as cmake/version_stamp.cmake: worktree AND index.
    # A staged-but-uncommitted change stamps +dirty; a gate reading only the worktree would then call an
    # honest stamp a false positive. (Residual: a tree dirtied AFTER the build still disagrees — inherent
    # to a build-time stamp, and the ordinary build-then-gate flow never hits it.)
    if git -C "$ROOT" diff --quiet --ignore-submodules -- 2>/dev/null \
        && git -C "$ROOT" diff --cached --quiet --ignore-submodules -- 2>/dev/null; then
        case "$OUT_LONG" in *"built_from=$EXPECTED_SHA+dirty"*) no "clean checkout falsely stamped dirty";;
                            *) ok "clean checkout is not falsely stamped dirty";; esac
    else
        printf '%s' "$OUT_LONG" | grep -q "built_from=$EXPECTED_SHA+dirty" \
            && ok "dirty checkout is disclosed in --version" \
            || no "dirty checkout is not disclosed in --version: $OUT_LONG"
    fi
fi

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
# The cache checked here must be the ONE that configured $BIN, not a hardcoded $ROOT/build guess — a
# binary built at any other path (asan/ripwire, a scratch copy, a CI out-of-tree build) would silently
# compare against build/CMakeCache.txt's build type instead of its own, or against nothing at all. And
# if that cache is simply ABSENT (grep finds no file, empty CACHE_BUILD_TYPE), that used to fall through
# to the "plain configure, expect dev" branch and pass for the wrong reason — a missing cache is not
# evidence of a dev configure, it is evidence the check couldn't run. Fail honestly instead.
BIN_DIR="$( cd "$( dirname "$BIN" )" && pwd )"
CACHE_FILE="$BIN_DIR/CMakeCache.txt"
if [ ! -f "$CACHE_FILE" ]; then
    no "no CMakeCache.txt found next to \$BIN's build dir ($CACHE_FILE) — cannot verify the build-type label; configure the tree that produced $BIN before running this gate"
else
    CACHE_BUILD_TYPE="$( grep -oE '^CMAKE_BUILD_TYPE:[A-Za-z]*=.*' "$CACHE_FILE" | cut -d= -f2 )"
    if [ -z "$CACHE_BUILD_TYPE" ]; then
        [ "$BUILD_TYPE_STR" = "dev" ] \
            && ok "plain configure (empty CMAKE_BUILD_TYPE in $CACHE_FILE) prints the honest label 'dev'" \
            || no "plain configure (empty CMAKE_BUILD_TYPE in $CACHE_FILE) prints '$BUILD_TYPE_STR', expected 'dev'"
    else
        [ "$BUILD_TYPE_STR" = "$CACHE_BUILD_TYPE" ] \
            && ok "configure with CMAKE_BUILD_TYPE=$CACHE_BUILD_TYPE (from $CACHE_FILE) prints it verbatim" \
            || no "configure with CMAKE_BUILD_TYPE=$CACHE_BUILD_TYPE (from $CACHE_FILE) prints '$BUILD_TYPE_STR' instead"
    fi
fi

# ── #6 (2026-09-08, the std::print floor): --version DISCLOSES which formatted-output emitter this binary
# compiled in. The house emitter (src/infra/emit.h) is std::print where the standard library has <print>
# and std::format+fputs where it does not (libstdc++ < 14; libc++ below a macOS 14 deployment target), by
# feature test, so every toolchain BUILDS — which is exactly why the choice has to be printed: a leg that
# silently took the fallback would otherwise read as "the floor holds". CI asserts the value per leg
# (ci.yml/release.yml); this arm asserts only that the disclosure exists and speaks the closed vocabulary.
# Its control strips the token from a copy of the same line and requires the identical extraction to fail.
emitToken="$( printf '%s' "$OUT_LONG" | grep -oE 'emit=[^,)]+' | head -1 )"
case "$emitToken" in
    "emit=std::print"|"emit=std::format+fputs") ok "--version discloses the emitter it compiled in ($emitToken)";;
    "") no "--version carries no emit= token — which emitter built this binary is undisclosed: $OUT_LONG";;
    *)  no "--version's emit= value is outside the closed vocabulary {std::print, std::format+fputs}: $emitToken";;
esac
emitMut="$( printf '%s' "$OUT_LONG" | sed -E 's/emit=[^,)]+//' )"
if [ -n "$emitToken" ] && [ "$emitMut" = "$OUT_LONG" ]; then
    no "emit= mutation control did not take — the token was found but could not be stripped from a copy"
elif [ -n "$( printf '%s' "$emitMut" | grep -oE 'emit=[^,)]+' )" ]; then
    no "emit= mutation control is inert — the token was stripped and the extraction still finds one"
else
    ok "emit= mutation control — stripping the token from a copy of the line loses it (the arm can fail)"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
