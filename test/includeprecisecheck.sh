#!/usr/bin/env bash
# includeprecisecheck.sh — P1 gate for the PURE path-precise include functions in resolve.h
# (resolvePreciseInclude / lexicalNormalize / buildPreciseIncludeAdj / transitiveIncludeSet). These are
# UNWIRED at P1 (nothing in buildGraph calls them yet), so they cannot be exercised through the ripwire
# binary. Instead this gate compiles a tiny standalone driver (test/includeprecise_unit.cpp) against the
# already-built ripwire objects (reusing the SAME flags CMake used) and runs it on test/includeprecisefix.
#
# Asserts (see the driver for the exact checks):
#   - `#include "../geometry.h"` from sub/consumer.cpp resolves to the ONE real root geometry.h, and NOT
#     to the same-basename decoy in other/geometry.h  (PATH, not basename)
#   - a `..`-escape ABOVE the crawl root → kNoFile (unresolved, no guess)
#   - an angle `<geometry.h>` / `<vector>` → kNoFile (external, never basename-matched)
#   - the transitive closure over the 3-file chain a.h→b.h→c.h is correct + direction-respecting
#   - the closure is DETERMINISTIC (built twice, byte-identical) and excludes self
#   - lexicalNormalize `.`/`..` edge cases
#
# The gate DERIVES its compile/link recipe from the CMake build that produced $RIPWIRE_BIN, so it needs a
# CMake-built binary (build/ripwire or asan/ripwire). Usage:
#   test/includeprecisecheck.sh
#   RIPWIRE_BIN=/path/to/build/ripwire test/includeprecisecheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

# the CMake build dir is the directory containing the binary; its CMakeFiles/ holds the flags + objects.
BUILD_DIR="$( cd "$( dirname "$BIN" )" && pwd )"
FLAGS_MK="$BUILD_DIR/CMakeFiles/ripwire.dir/flags.make"
LINK_TXT="$BUILD_DIR/CMakeFiles/ripwire.dir/link.txt"
[ -f "$FLAGS_MK" ] && [ -f "$LINK_TXT" ] || { echo "cannot find CMake flags/link under $BUILD_DIR — build with CMake first"; exit 2; }

echo "includeprecisecheck: BIN=$BIN  BUILD_DIR=$BUILD_DIR  TMP=$TMP"

# ── pull the exact compile flags CMake used for the ripwire C++ sources ───────────────────────────
# flags.make escapes define quotes for MAKE (e.g. -DX=\"...\"); parse into bash arrays with eval so the
# shell-level quoting is honoured exactly (a raw word-split would mangle the \"...\" define).
CXX="$( command -v c++ || command -v clang++ )"
eval "CXX_FLAGS=(    $( grep -m1 '^CXX_FLAGS ='    "$FLAGS_MK" | sed 's/^CXX_FLAGS =//' ) )"
eval "CXX_DEFINES=(  $( grep -m1 '^CXX_DEFINES ='  "$FLAGS_MK" | sed 's/^CXX_DEFINES =//' ) )"
eval "CXX_INCLUDES=( $( grep -m1 '^CXX_INCLUDES =' "$FLAGS_MK" | sed 's/^CXX_INCLUDES =//' ) )"

# ── the link line: all objects + libs, but DROP ripwire's own main.cpp.o (our driver supplies main) ──
# link.txt is one line: "<c++> <ldflags> <objs...> -o ripwire <libs...>". Take everything after the
# compiler token, strip the "-o ripwire" pair, and remove the main.cpp.o object.
LINK_BODY="$( sed -E 's#^[^ ]+ ##' "$LINK_TXT" )"                 # drop leading compiler path
LINK_BODY="$( printf '%s' "$LINK_BODY" | sed -E 's#-o +ripwire##' )"
LINK_BODY="$( printf '%s' "$LINK_BODY" | sed -E 's#[^ "]*ripwire.dir/src/main.cpp.o##' )"
LINK_BODY="$( printf '%s' "$LINK_BODY" | tr -d '"' )"             # object paths are make-quoted; no spaces inside → drop quotes

# object/lib paths in link.txt are relative to BUILD_DIR — compile+link from there so they resolve.
DRIVER="$ROOT/test/includeprecise_unit.cpp"
[ -f "$DRIVER" ] || { no "missing driver $DRIVER"; echo "SOME CHECKS FAILED"; exit 1; }

OBJ="$TMP/unit.o"
( cd "$BUILD_DIR" && "$CXX" "${CXX_FLAGS[@]}" "${CXX_DEFINES[@]}" "${CXX_INCLUDES[@]}" -c "$DRIVER" -o "$OBJ" ) 2>"$TMP/cc.err"
if [ $? -eq 0 ]; then ok "unit driver compiles against ripwire flags"; else no "unit driver failed to compile"; sed -n '1,40p' "$TMP/cc.err"; echo "SOME CHECKS FAILED"; exit 1; fi

UNIT="$TMP/unit"
# shellcheck disable=SC2086
( cd "$BUILD_DIR" && "$CXX" "${CXX_FLAGS[@]}" "$OBJ" $LINK_BODY -o "$UNIT" ) 2>"$TMP/ld.err"
if [ $? -eq 0 ]; then ok "unit driver links against ripwire objects + tree-sitter"; else no "unit driver failed to link"; sed -n '1,40p' "$TMP/ld.err"; echo "SOME CHECKS FAILED"; exit 1; fi

# ── run the driver against the fixture ────────────────────────────────────────────────────────────
FIX="$ROOT/test/includeprecisefix"
"$UNIT" "$FIX" >"$TMP/unit.out" 2>&1
rc=$?
# relay each PASS/FAIL line from the driver
grep -E '^  (PASS|FAIL) ' "$TMP/unit.out" || true
if [ "$rc" -eq 0 ] && grep -q '^UNIT ALL PASS$' "$TMP/unit.out"; then
  ok "unit driver: UNIT ALL PASS"
else
  no "unit driver reported failures (rc=$rc)"; sed -n '1,60p' "$TMP/unit.out"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
