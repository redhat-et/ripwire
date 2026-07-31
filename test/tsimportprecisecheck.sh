#!/usr/bin/env bash
# tsimportprecisecheck.sh — LEVER-B B2 gate: path-precise TS/JS import resolution.
#
# The precise SameInclude tier now has a TS/JS Step-A (resolve.h::resolveTsImport): a RELATIVE specifier
# `import {Z} from './x'` / `'../a/b'` resolves to the ONE repo file it names by PATH relative-to-includer,
# trying a FIXED extension list (.ts/.tsx/.js/.jsx/…) then index files, on a UNIQUE hit — else it degrades.
# A BARE specifier (`from 'react'` — node_modules/external) is left UNRESOLVED (the angle-include analogue).
# Same "unique-or-degrade" discipline as the C-family quote-include tier.
#
# Fixture test/tsimportprecisefix — the soundness cases:
#   caller.ts        import {helper} from './x'   → helper() binds x.ts::helper       (NOT the decoy other/x.ts)
#                    import {widget} from './a/b'  → widget() binds a/b.ts::widget      (NOT the decoy other/b.ts)
#                    import {idxfn} from './idx'   → idxfn() binds idx/index.ts::idxfn  (index-file resolution)
#                    import React from 'react'     → createElement() UNRESOLVED         (bare/external, no false edge)
#   other/caller2.ts import {helper} from './x'    → helper() binds other/x.ts::helper  (path, not basename)
#
# Also asserts B0 clean-specifier capture (--deps shows `./x`, not the clause), MONOTONICITY, determinism,
# warm==cold, and well-formed XML.
#
# Usage:  test/tsimportprecisecheck.sh   |   CTXPACK_BIN=asan/ctxpack test/tsimportprecisecheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/tsimportprecisefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "tsimportprecisecheck: BIN=$BIN  FIX=$FIX  TMP=$TMP"

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

# ── B2 path-precise resolution ────────────────────────────────────────────────────────────────────
callee_binds useHelper      'x.ts:'         'other/x.ts'  ; callee_count useHelper 1
callee_binds useWidget      'a/b.ts:'       'other/b.ts'  ; callee_count useWidget 1
callee_binds useIdx         'idx/index.ts:' ''            ; callee_count useIdx 1
callee_binds useOtherHelper 'other/x.ts:'   ''            ; callee_count useOtherHelper 1

# bare `from 'react'` → NO false edge (createElement is not an in-repo def).
"$BIN" "$FIX" --callees=useReact --no-cache >"$TMP/useReact.out" 2>/dev/null
callee_count useReact 0

# ── B0 clean specifier: --deps carries the quoted-path stripped to `./x`, not the whole clause ────
"$BIN" "$FIX" --deps --no-cache >"$TMP/deps.out" 2>/dev/null
grep -q '<inc t="./x"' "$TMP/deps.out" \
  && ok 'B0: import {helper} from "./x" → clean specifier t="./x"' \
  || { no 'B0: ./x specifier not captured cleanly'; grep -oE '<inc t="[^"]*"' "$TMP/deps.out" | sort -u; }
grep -q '<inc t="react"' "$TMP/deps.out" \
  && ok 'B0: bare `react` captured (and left external at resolve time)' \
  || no 'B0: bare react specifier missing'

# ── the fixture resolves everything → ambiguous=0 ─────────────────────────────────────────────────
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
        ok "monotonicity on fixture: ambiguous NEW=$an <= pre-change OLD=$ao (TS narrow only removes candidates)"
    else
        no "monotonicity VIOLATED: NEW=$an > OLD=$ao — a correct narrow was LOST (regression)"
    fi
}
monotonic_check

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
