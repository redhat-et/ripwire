#!/usr/bin/env bash
# jsonwalkcheck.sh — W2-M0 gate for the jsonStringEnd hoist: ctx::jsonStringEnd (jsonesc.h) is the ONE
# escape-aware JSON string walk, and mcpdetail::stringEnd + minedjson::skipString both forward into it.
#
# The claim under test is a PURE-REFACTOR claim, so the gate is a DIFFERENTIAL: test/jsonwalk_unit.cpp
# carries verbatim copies of both pre-hoist bodies (037a121) and asserts the live functions agree with
# them over an exhaustive corpus (every string over {'"','\\','x'} up to length 8, at every start offset)
# plus named edge shapes. A live-binary output diff CANNOT prove this — the inputs that distinguish the
# implementations (trailing backslash at EOF, unterminated string, escaped quote at the boundary) are
# exactly the ones no well-formed MCP request or mined fixture line ever contains.
#
# Also pins ctx::isJsonWs to RFC 8259 §2 over all 256 bytes — the folded three-copy whitespace family,
# whose trap is that std::isspace() accepts VT and FF and JSON does not.
#
# Structural half (no compiler needed): asserts the repo holds exactly ONE copy of the walk, so a future
# hand-rolled fourth copy reds this gate rather than silently re-forking the family.
#
# Usage:  test/jsonwalkcheck.sh [BIN]        (BIN only selects which CMake build dir supplies the flags)
#         RIPWIRE_BIN=asan/ripwire test/jsonwalkcheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "jsonwalkcheck: BIN=$BIN"

# ── part 1: STRUCTURAL — the family is folded, and stays folded ───────────────────────────────────
# The walk's distinguishing line is the escape-aware two-step. The pattern is INDEX-AGNOSTIC on purpose:
# the two pre-hoist copies spelled the same loop with different cursor names (`q` in mcpjson.h, `i` in
# eval.h), so a pattern naming one variable would have passed at base while the other copy was still
# there — the gate would have been green against exactly the state it exists to forbid. Matching the
# shared tail catches any spelling. Exactly one occurrence must survive in src/ (the jsonesc.h core).
walkFiles=$( grep -rl -- "+ 1 < s.size() ) ? 2 : 1" "$ROOT/src" 2>/dev/null | sort )
walkCopies=$( printf '%s' "$walkFiles" | grep -c . | tr -d ' ' )
if [ "$walkCopies" = "1" ] && printf '%s' "$walkFiles" | grep -q 'jsonesc\.h$'; then
  ok "the escape-aware walk exists in exactly ONE src/ file, and it is jsonesc.h (was 2: mcpjson.h + eval.h)"
else
  no "expected the walk in exactly 1 file (jsonesc.h), found $walkCopies — a copy was re-forked"
  printf '%s\n' "$walkFiles" | sed 's/^/        /'
fi

if grep -q 'inline std::size_t jsonStringEnd' "$ROOT/src/jsonesc.h"; then
  ok "ctx::jsonStringEnd is homed in jsonesc.h"
else
  no "ctx::jsonStringEnd missing from src/jsonesc.h"
fi

if grep -A3 'inline std::size_t stringEnd' "$ROOT/src/mcpjson.h" | grep -q 'return jsonStringEnd'; then
  ok "mcpdetail::stringEnd forwards into the core"
else
  no "mcpdetail::stringEnd no longer forwards into ctx::jsonStringEnd"
fi

if grep -A6 'inline std::size_t skipString' "$ROOT/src/eval.h" | grep -q 'ctx::jsonStringEnd'; then
  ok "minedjson::skipString forwards into the core"
else
  no "minedjson::skipString no longer forwards into ctx::jsonStringEnd"
fi

# isJsonWs: no hand-spelled copies of the four-byte test left in mcpjson.h
wsCopies=$( grep -c "c == ' ' || c == '\\\\t' || c == '\\\\n' || c == '\\\\r'" "$ROOT/src/mcpjson.h" 2>/dev/null || true )
if [ "${wsCopies:-0}" -eq 0 ]; then
  ok "mcpjson.h spells the JSON-whitespace set zero times (folded into ctx::isJsonWs)"
else
  no "mcpjson.h still hand-spells the whitespace set $wsCopies time(s)"
fi

# ── part 2: BEHAVIOURAL — compile + run the differential driver ───────────────────────────────────
# Recipe borrowed from includeprecisecheck.sh: reuse the exact flags/objects CMake produced for $BIN.
BUILD_DIR="$( cd "$( dirname "$BIN" )" && pwd )"
FLAGS_MK="$BUILD_DIR/CMakeFiles/ripwire.dir/flags.make"
LINK_TXT="$BUILD_DIR/CMakeFiles/ripwire.dir/link.txt"
if [ ! -f "$FLAGS_MK" ] || [ ! -f "$LINK_TXT" ]; then
  no "cannot find CMake flags/link under $BUILD_DIR — the differential arm needs a CMake-built binary"
  [ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
fi

CXX="$( command -v c++ || command -v clang++ )"
eval "CXX_FLAGS=(    $( grep -m1 '^CXX_FLAGS ='    "$FLAGS_MK" | sed 's/^CXX_FLAGS =//' ) )"
eval "CXX_DEFINES=(  $( grep -m1 '^CXX_DEFINES ='  "$FLAGS_MK" | sed 's/^CXX_DEFINES =//' ) )"
eval "CXX_INCLUDES=( $( grep -m1 '^CXX_INCLUDES =' "$FLAGS_MK" | sed 's/^CXX_INCLUDES =//' ) )"

LINK_BODY="$( sed -E 's#^[^ ]+ ##' "$LINK_TXT" )"
LINK_BODY="$( printf '%s' "$LINK_BODY" | sed -E 's#-o +ripwire##' )"
LINK_BODY="$( printf '%s' "$LINK_BODY" | sed -E 's#[^ "]*ripwire.dir/src/main.cpp.o##' )"
LINK_BODY="$( printf '%s' "$LINK_BODY" | tr -d '"' )"

DRIVER="$ROOT/test/jsonwalk_unit.cpp"
[ -f "$DRIVER" ] || { no "missing driver $DRIVER"; echo "SOME CHECKS FAILED"; exit 1; }

OBJ="$TMP/jsonwalk.o"
( cd "$BUILD_DIR" && "$CXX" "${CXX_FLAGS[@]}" "${CXX_DEFINES[@]}" "${CXX_INCLUDES[@]}" -c "$DRIVER" -o "$OBJ" ) 2>"$TMP/cc.err"
if [ $? -eq 0 ]; then ok "differential driver compiles against ripwire flags"
else no "differential driver failed to compile"; sed -n '1,40p' "$TMP/cc.err"; echo "SOME CHECKS FAILED"; exit 1; fi

UNIT="$TMP/jsonwalk"
# shellcheck disable=SC2086
( cd "$BUILD_DIR" && "$CXX" "${CXX_FLAGS[@]}" "$OBJ" $LINK_BODY -o "$UNIT" ) 2>"$TMP/ld.err"
if [ $? -eq 0 ]; then ok "differential driver links against ripwire objects"
else no "differential driver failed to link"; sed -n '1,40p' "$TMP/ld.err"; echo "SOME CHECKS FAILED"; exit 1; fi

"$UNIT" >"$TMP/unit.out" 2>&1
rc=$?
grep -E '^  (PASS|FAIL) ' "$TMP/unit.out" | sed 's/^/  /' || true
if [ "$rc" -eq 0 ] && grep -q '^UNIT ALL PASS$' "$TMP/unit.out"; then
  ok "differential driver: live == both pre-hoist bodies on every probe"
else
  no "differential driver reported failures (rc=$rc)"; sed -n '1,60p' "$TMP/unit.out"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
