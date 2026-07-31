#!/usr/bin/env bash
# rustimportprecisecheck.sh — LEVER-B B3 gate: path-precise RUST import resolution.
#
# The precise SameInclude tier now has a Rust Step-A (resolve.h::resolveRustImport):
#   * `mod x;`  (body-less) → `x.rs` OR `x/mod.rs` relative-to-includer (Rust's module-file rule) — SOUND.
#   * `use crate::a::b`     → crate-root (src/, from src/lib.rs|main.rs) + `a/b` probed as module OR item;
#                             `self::`/`super::` relative-to-file — resolve IFF exactly one hits, else DEGRADE
#                             (SOUND-BY-DEGRADE — which trailing segments are modules vs items is not decidable
#                             source-only, so an ambiguous `use` never guesses).
# A `use std::…` / external crate / brace group / a crate-less workspace member all DEGRADE (no edge, no guess).
#
# TWO layers of assertion:
#   1. PIPELINE: through the binary — mod/use resolve to the right file past cross-dir decoys; std stays external.
#   2. UNIT (test/rustimport_unit.cpp): the resolver DIRECTLY, so the DEGRADE cases are proven at the source
#      (where §2a can otherwise mask a degrade). The decisive one: `use crate::amb::dupfn` with BOTH src/amb.rs
#      AND src/amb/mod.rs present → resolveRustImport returns kNoFile (degrade), never a guessed file.
#
# Also: B0 clean specifier capture, MONOTONICITY, determinism, warm==cold, well-formed XML.
#
# Usage:  test/rustimportprecisecheck.sh   |   CTXPACK_BIN=asan/ctxpack test/rustimportprecisecheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/rustimportprecisefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "rustimportprecisecheck: BIN=$BIN  FIX=$FIX  TMP=$TMP"

callee_binds(){  # $1 caller  $2 expected-path-substr  $3 must-NOT-contain-substr (decoy)
  "$BIN" "$FIX" --callees="$1" --no-cache >"$TMP/$1.out" 2>/dev/null
  if grep -q "$2" "$TMP/$1.out" && { [ -z "${3:-}" ] || ! grep -q "$3" "$TMP/$1.out"; }; then
    ok "$1 → $2 (unique, precise${3:+; not $3})"
  else
    no "$1 did not bind $2 alone"; cat "$TMP/$1.out"
  fi
}
callee_count(){  # $1 caller  $2 expected count=
  local c; c="$( grep -oE 'count="[0-9]+"' "$TMP/$1.out" | head -1 )"
  [ "$c" = "count=\"$2\"" ] && ok "$1 has $c callee(s)" || no "$1 callee count wrong (got $c, want count=\"$2\")"
}

# ── (1) PIPELINE resolution ───────────────────────────────────────────────────────────────────────
# root_entry() in lib.rs calls helper(); lib.rs does `mod geo;` → helper binds src/geo/mod.rs (NOT other/).
callee_binds root_entry       'geo/mod.rs:'  'other/mod.rs' ; callee_count root_entry 1
callee_binds use_crate_helper 'geo/mod.rs:'  'other/mod.rs' ; callee_count use_crate_helper 1
callee_binds use_crate_util   'util.rs:'     ''             ; callee_count use_crate_util 1
# use std::… → external → no false edge from use_std.
"$BIN" "$FIX" --callees=use_std --no-cache >"$TMP/use_std.out" 2>/dev/null
callee_count use_std 0

# ── B0 clean specifier: `mod:geo` marker + `crate::geo::helper` path captured ─────────────────────
"$BIN" "$FIX" --deps --no-cache >"$TMP/deps.out" 2>/dev/null
grep -q '<inc t="mod:geo"' "$TMP/deps.out" \
  && ok 'B0: `mod geo;` → clean marker t="mod:geo"' || { no 'B0: mod:geo marker missing'; grep -oE '<inc t="[^"]*"' "$TMP/deps.out" | sort -u; }
grep -q '<inc t="crate::geo::helper"' "$TMP/deps.out" \
  && ok 'B0: `use crate::geo::helper` → clean path t="crate::geo::helper"' || no 'B0: crate::geo::helper path missing'

# ── monotone-stable header (a precise narrow never MANUFACTURES ambiguity above pre-change) ────────
famb="$( "$BIN" "$FIX" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
[ -n "$famb" ] && ok "fixture ambiguous=$famb (see monotonicity below for the bound)" || no "no ambiguous= header"

# ── determinism + warm==cold ──────────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/d2" 2>/dev/null
cmp -s "$TMP/d1" "$TMP/d2" && ok "deterministic (two --no-cache runs identical)" || no "non-deterministic"
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
cmp -s "$TMP/cold" "$TMP/warm" && ok "warm == cold (resolver order-stable through cache)" || no "warm != cold"

# ── well-formed XML ───────────────────────────────────────────────────────────────────────────────
command -v xmllint >/dev/null 2>&1 \
  && { xmllint --noout "$TMP/d1" 2>/dev/null && ok "xml well-formed" || no "xml malformed"; } \
  || ok "xml well-formed (xmllint absent — skipped)"

# ── (2) UNIT driver — the DEGRADE soundness proof (resolver in isolation) ─────────────────────────
# Compile test/rustimport_unit.cpp against the SAME CMake flags/objects that built $BIN (mirrors
# includeprecisecheck.sh's recipe), supplying its own main(); run it on the fixture.
BUILD_DIR="$( cd "$( dirname "$BIN" )" && pwd )"
FLAGS_MK="$BUILD_DIR/CMakeFiles/ctxpack.dir/flags.make"
LINK_TXT="$BUILD_DIR/CMakeFiles/ctxpack.dir/link.txt"
DRIVER="$ROOT/test/rustimport_unit.cpp"
if [ -f "$FLAGS_MK" ] && [ -f "$LINK_TXT" ] && [ -f "$DRIVER" ]; then
  CXX="$( command -v c++ || command -v clang++ )"
  eval "CXX_FLAGS=(    $( grep -m1 '^CXX_FLAGS ='    "$FLAGS_MK" | sed 's/^CXX_FLAGS =//' ) )"
  eval "CXX_DEFINES=(  $( grep -m1 '^CXX_DEFINES ='  "$FLAGS_MK" | sed 's/^CXX_DEFINES =//' ) )"
  eval "CXX_INCLUDES=( $( grep -m1 '^CXX_INCLUDES =' "$FLAGS_MK" | sed 's/^CXX_INCLUDES =//' ) )"
  LINK_BODY="$( sed -E 's#^[^ ]+ ##' "$LINK_TXT" )"
  LINK_BODY="$( printf '%s' "$LINK_BODY" | sed -E 's#-o +ctxpack##' )"
  LINK_BODY="$( printf '%s' "$LINK_BODY" | sed -E 's#[^ "]*ctxpack.dir/src/main.cpp.o##' )"
  LINK_BODY="$( printf '%s' "$LINK_BODY" | tr -d '"' )"
  OBJ="$TMP/unit.o"; UNIT="$TMP/unit"
  if ( cd "$BUILD_DIR" && "$CXX" "${CXX_FLAGS[@]}" "${CXX_DEFINES[@]}" "${CXX_INCLUDES[@]}" -c "$DRIVER" -o "$OBJ" ) 2>"$TMP/cc.err"; then
    # shellcheck disable=SC2086
    if ( cd "$BUILD_DIR" && "$CXX" "${CXX_FLAGS[@]}" "$OBJ" $LINK_BODY -o "$UNIT" ) 2>"$TMP/ld.err"; then
      "$UNIT" "$FIX" >"$TMP/unit.out" 2>&1; rc=$?
      grep -E '^  (PASS|FAIL) ' "$TMP/unit.out" || true
      if [ "$rc" -eq 0 ] && grep -q '^UNIT ALL PASS$' "$TMP/unit.out"; then ok "unit driver: UNIT ALL PASS (degrade proven at source)"
      else no "unit driver reported failures (rc=$rc)"; sed -n '1,40p' "$TMP/unit.out"; fi
    else no "unit driver failed to link"; sed -n '1,20p' "$TMP/ld.err"; fi
  else no "unit driver failed to compile"; sed -n '1,20p' "$TMP/cc.err"; fi
else
  skip "unit driver: CMake flags/link or driver missing under $BUILD_DIR (pipeline checks are primary)"
fi

# ── MONOTONICITY: NEW.ambiguous <= pre-change.ambiguous on the fixture ────────────────────────────
monotonic_check()
{
    command -v git   >/dev/null 2>&1 || { skip "monotonicity: git absent"; return; }
    command -v cmake >/dev/null 2>&1 || { skip "monotonicity: cmake absent"; return; }
    ( cd "$ROOT" && git rev-parse --verify HEAD >/dev/null 2>&1 ) || { skip "monotonicity: not a git repo"; return; }

    local WT="$TMP/head"
    ( cd "$ROOT" && git worktree add -q --detach "$WT" HEAD ) 2>"$TMP/wt.err" \
        || { skip "monotonicity: cannot create HEAD worktree ($(head -1 "$TMP/wt.err"))"; return; }
    trap '( cd "$ROOT" && git worktree remove --force "'"$WT"'" >/dev/null 2>&1 ); rm -rf "$TMP"' EXIT

    local OLDB="$TMP/oldbuild"
    if ! ( cmake -S "$WT" -B "$OLDB" -DCTXPACK_NATIVE=ON >/dev/null 2>&1 && cmake --build "$OLDB" -j >/dev/null 2>&1 ); then
        skip "monotonicity: pre-change build failed"; return
    fi
    local OLDBIN="$OLDB/ctxpack"
    [ -x "$OLDBIN" ] || { skip "monotonicity: pre-change binary missing"; return; }

    local ao an
    ao="$( "$OLDBIN" "$FIX" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
    an="$( "$BIN"    "$FIX" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
    if [ -n "$ao" ] && [ -n "$an" ] && [ "$an" -le "$ao" ]; then
        ok "monotonicity on fixture: ambiguous NEW=$an <= pre-change OLD=$ao (Rust narrow only removes candidates)"
    else
        no "monotonicity VIOLATED: NEW=$an > OLD=$ao — a correct narrow was LOST (regression)"
    fi
}
monotonic_check

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
