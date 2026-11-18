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
# Usage:  test/rustimportprecisecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rustimportprecisecheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/rustimportprecisefix"
. "$ROOT/test/lib/headbinlib.sh"                       # shared sha-keyed cache of the HEAD comparison binary
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }
. "$ROOT/test/lib/cxxflags.sh"                          # the ONE flags.make parse (CWE-78: never eval a generated file)

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
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
  if [ "$c" = "count=\"$2\"" ]; then ok "$1 has $c callee(s)"; else no "$1 callee count wrong (got $c, want count=\"$2\")"; fi
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
if [ -n "$famb" ]; then ok "fixture ambiguous=$famb (see monotonicity below for the bound)"; else no "no ambiguous= header"; fi

# ── determinism + warm==cold ──────────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/d2" 2>/dev/null
if cmp -s "$TMP/d1" "$TMP/d2"; then ok "deterministic (two --no-cache runs identical)"; else no "non-deterministic"; fi
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
if cmp -s "$TMP/cold" "$TMP/warm"; then ok "warm == cold (resolver order-stable through cache)"; else no "warm != cold"; fi

# ── well-formed XML ───────────────────────────────────────────────────────────────────────────────
command -v xmllint >/dev/null 2>&1 \
  && { xmllint --noout "$TMP/d1" 2>/dev/null && ok "xml well-formed" || no "xml malformed"; } \
  || ok "xml well-formed (xmllint absent — skipped)"

# ── (2) UNIT driver — the DEGRADE soundness proof (resolver in isolation) ─────────────────────────
# Compile test/rustimport_unit.cpp against the SAME CMake flags/objects that built $BIN (mirrors
# includeprecisecheck.sh's recipe), supplying its own main(); run it on the fixture.
BUILD_DIR="$( cd "$( dirname "$BIN" )" && pwd )"
FLAGS_MK="$BUILD_DIR/CMakeFiles/ripwire.dir/flags.make"
LINK_TXT="$BUILD_DIR/CMakeFiles/ripwire.dir/link.txt"
DRIVER="$ROOT/test/rustimport_unit.cpp"
if [ -f "$FLAGS_MK" ] && [ -f "$LINK_TXT" ] && [ -f "$DRIVER" ]; then
  # THE COMPILER MUST BE THE ONE CMAKE USED, not whatever `c++` happens to be. This harness reuses CMake's
  # EXACT compile flags from flags.make, and those flags are front-end specific: a Release tree configured
  # with clang carries `-flto=thin`, which gcc rejects outright ("unrecognized argument to '-flto=' option").
  # On a Linux box where CMake was given clang but `c++` resolves to g++, the guess and the flags disagree and
  # the driver cannot compile — CI run 31182301976, release (ubuntu-24.04, Release, clang), three gates red on
  # exactly this. link.txt's first token IS the compiler CMake drove, and this gate already parses it to strip
  # the leading path, so the right answer was on disk the whole time. Same lesson as scripts/cxxstd.sh: ask the
  # toolchain, never assume it.
  CXX="$( awk 'NR==1{ print $1; exit }' "$LINK_TXT" )"
  [ -n "$CXX" ] && command -v "$CXX" >/dev/null 2>&1 || CXX="$( command -v c++ || command -v clang++ )"
  # The flags parse is SHARED and shlex-based, never `eval`: test/lib/cxxflags.sh carries the CWE-78
  # reachability chain, the measured table of which shapes execute, and the proof arms relayed below.
  cxxflags_load "$FLAGS_MK" \
      || no "cannot parse $FLAGS_MK without executing it (see the cxxflags: line on stderr)"

  # ── the parse's own proof ─────────────────────────────────────────────────────────────────────────
  # Three claims, none of which the others imply: the eval spelling this replaced DOES execute a
  # payload (without that control the rest is vacuous), this parse executes nothing, and it neutralises
  # the payload rather than silently DROPPING it. Each shape gets its own key and its own control —
  # several on one flags line mask each other into a false all-clear (test/lib/cxxflags.sh, arm P6).
  cxxflags_selfproof "$TMP/cxxflags" "$FLAGS_MK" > "$TMP/cxxflags.rows" 2>&1 || true
  while IFS= read -r _row; do             # a redirect, never a pipe: a pipeline subshell loses fail=1
      case "$_row" in
          PASS*) ok "${_row#PASS }" ;;
          NOTE*) printf '  NOTE  %s\n' "${_row#NOTE }" ;;
          FAIL*) no "${_row#FAIL }" ;;
      esac
  done < "$TMP/cxxflags.rows"

  LINK_BODY="$( sed -E 's#^[^ ]+ ##' "$LINK_TXT" )"
  LINK_BODY="$( printf '%s' "$LINK_BODY" | sed -E 's#-o +ripwire##' )"
  LINK_BODY="$( printf '%s' "$LINK_BODY" | sed -E 's#[^ "]*ripwire.dir/src/main.cpp.o##' )"
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

# ── RUST-USE-PRINT-NAMESPACE: a bare call bound by a `use` of an OUTSIDE crate names that crate's item ─────────────
# `use crossterm::style::Print; Print( s )` bound, with no hedge, to an in-tree `trait Print` of another workspace crate
# (nushell legacy_input). Generated here (a two-crate workspace; crossterm is a registry dependency, not in the tree):
#   (U1) outside `use`, in-tree TRAIT namesake          -> no edge (external=)
#   (U2) outside `use` (a nested brace group, as legacy_input writes it), in-tree TUPLE-STRUCT namesake -> no edge
#        (external=): the use path does not reach it
#   (U3) outside glob, in-tree TRAIT namesake only      -> no edge: a Rust call never names a trait
#   (N1) `use crate::ui::Draw` reaching an in-tree tuple struct -> binds it, no hedge
#   (N2) `use a::Print` of the in-tree workspace crate   -> binds a's tuple struct, no hedge
#   (N4) an in-tree glob bringing the name (a `pub use …::*` re-export) beside an outside glob -> binds, no hedge (E0659:
#        two globs supplying one used name do not compile)
#   (N3) outside glob + an in-tree tuple struct the file's writing does not reach -> kept, but via="name" (hedged)
WS="$TMP/ws"; mkdir -p "$WS/a/src" "$WS/b/src" "$WS/c/src/ui" "$WS/t/src"
printf '[workspace]\nmembers = ["a", "b", "c", "t"]\n' >"$WS/Cargo.toml"
printf '[package]\nname = "a"\nversion = "0.1.0"\n' >"$WS/a/Cargo.toml"
printf '[package]\nname = "t"\nversion = "0.1.0"\n' >"$WS/t/Cargo.toml"
printf '[package]\nname = "b"\nversion = "0.1.0"\n[dependencies]\ncrossterm = "0.27"\na = { path = "../a" }\nt = { path = "../t" }\n' >"$WS/b/Cargo.toml"
printf '[package]\nname = "c"\nversion = "0.1.0"\n[dependencies]\ncrossterm = "0.27"\n' >"$WS/c/Cargo.toml"
printf 'pub trait Paint\n{\n    fn paint( &self );\n}\n' >"$WS/t/src/lib.rs"
printf 'pub struct Print( pub String );\npub mod prelude;\nmod assertions;\n' >"$WS/a/src/lib.rs"
printf 'pub use crate::assertions::*;\n' >"$WS/a/src/prelude.rs"
printf 'pub fn assert_holds( _x: bool )\n{\n}\n' >"$WS/a/src/assertions.rs"
cat >"$WS/b/src/lib.rs" <<'RS'
mod outside_trait;
mod outside_struct;
mod glob_trait;
mod glob_struct;
mod inside_crate;
mod two_globs;
RS
printf 'use a::prelude::*;\nuse crossterm::style::*;\n\npub fn n4_two_globs()\n{\n    assert_holds( true );\n}\n' >"$WS/b/src/two_globs.rs"
printf 'use crossterm::style::Paint;\n\npub fn u1_trait()\n{\n    let _p = Paint( String::new() );\n}\n' >"$WS/b/src/outside_trait.rs"
printf 'use crossterm::{\n    cursor,\n    style::Print,\n};\n\npub fn u2_struct()\n{\n    let _p = Print( String::new() );\n}\n' >"$WS/b/src/outside_struct.rs"
printf 'use crossterm::style::*;\n\npub fn u3_glob_trait()\n{\n    let _p = Paint( String::new() );\n}\n' >"$WS/b/src/glob_trait.rs"
printf 'use crossterm::style::*;\n\npub fn n3_glob_struct()\n{\n    let _p = Print( String::new() );\n}\n' >"$WS/b/src/glob_struct.rs"
printf 'use a::Print;\n\npub fn n2_crate_use()\n{\n    let _p = Print( String::new() );\n}\n' >"$WS/b/src/inside_crate.rs"
printf 'pub mod ui;\nmod user;\n' >"$WS/c/src/lib.rs"
printf 'pub struct Draw( pub String );\n' >"$WS/c/src/ui/mod.rs"
printf 'use crate::ui::Draw;\n\npub fn n1_local_use()\n{\n    let _p = Draw( String::new() );\n}\n' >"$WS/c/src/user.rs"
ws_callees(){ "$BIN" "$WS" --callees="$1" --no-cache 2>/dev/null | sed 's/^<!--.*-->//'; }   # status: every arm greps for its <callees of=> header, so a failed run fails the arm
for fn in u1_trait u2_struct u3_glob_trait; do
  out="$( ws_callees "$fn" )"
  if printf '%s' "$out" | grep -q "of=\"$fn\" defs=\"1\" count=\"0\"" && ! printf '%s' "$out" | grep -q '<s '; then
    ok "$fn: an outside \`use\`/glob name binds no in-tree namesake (no <s> row)"
  else
    no "$fn: bound an in-tree namesake its outside \`use\` cannot reach"; printf '%s\n' "$out"
  fi
done
out="$( ws_callees n1_local_use )"
if printf '%s' "$out" | grep -q '<s t="cls" n="Draw" p="c/src/ui/mod.rs:1"/>'; then
  ok "n1_local_use: \`use crate::ui::Draw\` still binds the in-tree tuple struct, no hedge"
else
  no "n1_local_use: the in-tree \`use\` lost its proven edge"; printf '%s\n' "$out"
fi
out="$( ws_callees n2_crate_use )"
if printf '%s' "$out" | grep -q '<s t="cls" n="Print" p="a/src/lib.rs:1"/>'; then
  ok "n2_crate_use: \`use a::Print\` of the workspace crate still binds a's tuple struct, no hedge"
else
  no "n2_crate_use: the workspace-crate \`use\` lost its proven edge"; printf '%s\n' "$out"
fi
out="$( ws_callees n4_two_globs )"
if printf '%s' "$out" | grep -q '<s t="fn" n="assert_holds" p="a/src/assertions.rs:1"/>'; then
  ok "n4_two_globs: an in-tree glob that brings the name binds it, no hedge, beside an outside glob"
else
  no "n4_two_globs: the in-tree glob's binding was hedged or lost"; printf '%s\n' "$out"
fi
out="$( ws_callees n3_glob_struct )"
if printf '%s' "$out" | grep -q '<s t="cls" n="Print" p="a/src/lib.rs:1" via="name"/>' && ! printf '%s' "$out" | grep -qE '<s t="cls" n="Print" p="[^"]*"/>'; then
  ok "n3_glob_struct: an outside glob keeps the in-tree namesake by name only (via=\"name\"), never unhedged, never dropped"
else
  no "n3_glob_struct: an outside glob's name must stay a hedged row"; printf '%s\n' "$out"
fi

# ── MONOTONICITY: NEW.ambiguous <= pre-change.ambiguous on the fixture ────────────────────────────
monotonic_check()
{
    command -v git   >/dev/null 2>&1 || { skip "monotonicity: git absent"; return; }
    command -v cmake >/dev/null 2>&1 || { skip "monotonicity: cmake absent"; return; }
    ( cd "$ROOT" && git rev-parse --verify HEAD >/dev/null 2>&1 ) || { skip "monotonicity: not a git repo"; return; }

    # pre-change binary from the shared sha-keyed cache (test/lib/headbinlib.sh): built at most once per
    # HEAD sha, then reused by all four monotonicity gates and every rerun until HEAD moves.
    local OLDBIN
    OLDBIN="$( ripwire_head_binary "$ROOT" "$TMP" )" \
        || { headbin_refusal $? "monotonicity"; return; }

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
