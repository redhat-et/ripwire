#!/usr/bin/env bash
# pyimportprecisecheck.sh — LEVER-B B1 gate: path-precise PYTHON import resolution.
#
# The precise SameInclude tier now has a Python Step-A (resolve.h::resolvePythonImport): an
# `import a` / `import pkg.mod` / `from pkg.mod import Z` / `from .rel import Z` resolves to the ONE
# repo file it names (`a.py`, `pkg/mod.py`, `pkg/__init__.py`) by PATH — relative-to-file AND
# relative-to-repo-root — on a UNIQUE hit, else it degrades (no edge, no guess). Same "unique-or-degrade"
# discipline as the C-family quote-include tier.
#
# Fixture test/pyimportprecisefix — the soundness cases:
#   caller.py       import a                    → widget() binds a.py::widget       (NOT the decoy other/a.py)
#                   from pkg.mod import gadget   → gadget() binds pkg/mod.py::gadget  (NOT the decoy other/mod.py)
#                   import pkg                   → pkginit() binds pkg/__init__.py    (package __init__ resolution)
#                   import os (stdlib) + getcwd()→ UNRESOLVED (no false edge)
#   other/caller2.py import other.a             → widget() binds other/a.py::widget  (path, not basename)
#   rel/relcaller.py from .sibling import sib    → sib() binds rel/sibling.py::sib    (relative import)
#
# Also asserts B0 clean-specifier capture (--deps shows `pkg.mod`, not the sliced clause), MONOTONICITY
# (ambiguous can only DECREASE vs the pre-change binary), determinism, warm==cold, and well-formed XML.
#
# Usage:  test/pyimportprecisecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/pyimportprecisecheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/pyimportprecisefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "pyimportprecisecheck: BIN=$BIN  FIX=$FIX  TMP=$TMP"

# a callee edge of $1 resolving to file $2 (and to NO other .py holding the same-name def).
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

# ── B1 path-precise resolution ────────────────────────────────────────────────────────────────────
callee_binds use_a        'a.py:'            'other/a.py'      ; callee_count use_a 1
callee_binds use_pkgmod   'pkg/mod.py:'      'other/mod.py'    ; callee_count use_pkgmod 1
callee_binds use_pkginit  'pkg/__init__.py:' ''               ; callee_count use_pkginit 1
callee_binds use_other_a  'other/a.py:'      ''               ; callee_count use_other_a 1   # NB: distinct from root a.py by PATH
callee_binds use_rel      'rel/sibling.py:'  ''               ; callee_count use_rel 1

# stdlib import → NO false edge (getcwd is not an in-repo def; `import os` must not manufacture one).
"$BIN" "$FIX" --callees=use_stdlib --no-cache >"$TMP/use_stdlib.out" 2>/dev/null
callee_count use_stdlib 0

# ── B0 clean specifier: --deps carries the module path, not the sliced clause ─────────────────────
"$BIN" "$FIX" --deps --no-cache >"$TMP/deps.out" 2>/dev/null
grep -q '<inc t="pkg.mod"' "$TMP/deps.out" \
  && ok 'B0: from pkg.mod import gadget → clean specifier t="pkg.mod"' \
  || { no 'B0: pkg.mod specifier not captured cleanly'; grep -oE '<inc t="[^"]*"' "$TMP/deps.out" | sort -u; }

# ── the fixture resolves everything → ambiguous=0 (a precise narrow never MANUFACTURES ambiguity) ─
famb="$( "$BIN" "$FIX" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 )"
[ "$famb" = "ambiguous=0" ] && ok "fixture $famb" || no "fixture $famb (expected 0)"

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

# ── MONOTONICITY: NEW.ambiguous <= pre-change.ambiguous on the fixture (narrow only removes candidates)
# Build a pre-change binary from git HEAD (resolve.h + ingest.cpp changed), run BOTH on the fixture.
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
    if ! ( cmake -S "$WT" -B "$OLDB" -DRIPWIRE_NATIVE=ON >/dev/null 2>&1 && cmake --build "$OLDB" -j >/dev/null 2>&1 ); then
        skip "monotonicity: pre-change build failed"; return
    fi
    local OLDBIN="$OLDB/ripwire"
    [ -x "$OLDBIN" ] || { skip "monotonicity: pre-change binary missing"; return; }

    local ao an
    ao="$( "$OLDBIN" "$FIX" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
    an="$( "$BIN"    "$FIX" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
    if [ -n "$ao" ] && [ -n "$an" ] && [ "$an" -le "$ao" ]; then
        ok "monotonicity on fixture: ambiguous NEW=$an <= pre-change OLD=$ao (Python narrow only removes candidates)"
    else
        no "monotonicity VIOLATED: NEW=$an > OLD=$ao — a correct narrow was LOST (regression)"
    fi
}
monotonic_check

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
