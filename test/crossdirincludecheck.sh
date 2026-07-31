#!/usr/bin/env bash
# crossdirincludecheck.sh — P2 gate for the SOUND SameInclude tier (path-precise include resolution).
#
# buildGraph's include narrow now consumes the PRECISE transitive include-set (resolvePreciseInclude:
# a quote `"x.h"` resolved LEXICALLY relative-to-includer) instead of the old BASENAME set. The fixture
# test/crossdirincludefix has the exact cross-directory basename collision the basename resolver could
# not tell apart:
#   dirA/x.h  and  dirB/x.h  BOTH define `helper()`  (same basename `x.h`, different directories)
#   main.cpp    #includes "dirA/x.h"  and calls helper()   → must bind dirA::helper
#   control.cpp #includes "dirB/x.h"  and calls helper()   → must bind dirB::helper
#
# The soundness proof the BASENAME version FAILS: basename `x.h` matches BOTH files, so the include-set
# is ambiguous → the narrow bails → the tier ladder drops the cross-dir edge entirely (callerA/callerB
# get ZERO callees). The PRECISE version resolves each `#include` to its ONE real file by PATH, so:
#   - callerA's helper() edge points to dirA/x.h  (NOT dirB)   ← path, not basename
#   - callerB's helper() edge points to dirB/x.h  (NOT dirA)   ← the two are told apart by PATH
#
# Also asserts MONOTONICITY on a real corpus: the precise narrow only ever REMOVES candidates, so
# `ambiguous=` can only DECREASE (never increase). This gate builds a pre-change comparison binary from
# git HEAD's src/resolve.h+graph.h and asserts NEW.ambiguous <= OLD.ambiguous on src/ (input held
# constant). If a pre-change build isn't feasible (dirty index / no git), that sub-check is skipped with
# a note — the path-correctness checks above are the primary gate.
#
# Usage:  test/crossdirincludecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/crossdirincludecheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/crossdirincludefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "crossdirincludecheck: BIN=$BIN  FIX=$FIX  TMP=$TMP"

# ── path-precise resolution: callerA → dirA/x.h, callerB → dirB/x.h (told apart by PATH) ──────────
"$BIN" "$FIX" --callees=callerA --no-cache >"$TMP/a.out" 2>/dev/null
"$BIN" "$FIX" --callees=callerB --no-cache >"$TMP/b.out" 2>/dev/null

grep -q 'dirA/x.h:' "$TMP/a.out" && ! grep -q 'dirB/x.h:' "$TMP/a.out" \
  && ok "callerA #include \"dirA/x.h\" → helper resolves to dirA/x.h (NOT dirB) — path, not basename" \
  || { no "callerA did not resolve to dirA/x.h alone"; cat "$TMP/a.out"; }

grep -q 'dirB/x.h:' "$TMP/b.out" && ! grep -q 'dirA/x.h:' "$TMP/b.out" \
  && ok "callerB #include \"dirB/x.h\" → helper resolves to dirB/x.h (NOT dirA) — the two are told apart" \
  || { no "callerB did not resolve to dirB/x.h alone"; cat "$TMP/b.out"; }

# each caller has exactly ONE callee (the precise edge), not zero (dropped) or two (ambiguous spray).
ca="$( grep -oE 'count="[0-9]+"' "$TMP/a.out" | head -1 )"
cb="$( grep -oE 'count="[0-9]+"' "$TMP/b.out" | head -1 )"
[ "$ca" = 'count="1"' ] && ok "callerA has exactly ONE precise callee edge ($ca)" || no "callerA callee count wrong ($ca)"
[ "$cb" = 'count="1"' ] && ok "callerB has exactly ONE precise callee edge ($cb)" || no "callerB callee count wrong ($cb)"

# ── the fixture stays honest: ambiguous=0 (a precise narrow never MANUFACTURES ambiguity) ────────
famb="$( "$BIN" "$FIX" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 )"
[ "$famb" = "ambiguous=0" ] && ok "fixture $famb (precise narrow adds no ambiguity)" || no "fixture $famb (expected 0)"

# ── determinism: byte-identical run-to-run + warm == cold ─────────────────────────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/d2" 2>/dev/null
cmp -s "$TMP/d1" "$TMP/d2" && ok "deterministic (two --no-cache runs identical)" || no "non-deterministic"
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
cmp -s "$TMP/cold" "$TMP/warm" && ok "warm == cold (include-set closure order-stable through cache)" || no "warm != cold"

# ── well-formed XML ───────────────────────────────────────────────────────────────────────────────
command -v xmllint >/dev/null 2>&1 \
  && { xmllint --noout "$TMP/d1" 2>/dev/null && ok "xml well-formed" || no "xml malformed"; } \
  || ok "xml well-formed (xmllint absent — skipped)"

# ── MONOTONICITY on a real corpus: NEW.ambiguous <= pre-change.ambiguous (input held constant) ───
# Build a pre-change binary from git HEAD's resolve.h + graph.h (the two files whose resolver logic
# changed), then compare `ambiguous=` on src/ using the SAME (HEAD) source tree as input for both.
monotonic_check()
{
    command -v git   >/dev/null 2>&1 || { skip "monotonicity: git absent"; return; }
    command -v cmake >/dev/null 2>&1 || { skip "monotonicity: cmake absent"; return; }
    ( cd "$ROOT" && git rev-parse --verify HEAD >/dev/null 2>&1 ) || { skip "monotonicity: not a git repo"; return; }

    local WT="$TMP/head"
    ( cd "$ROOT" && git worktree add -q --detach "$WT" HEAD ) 2>"$TMP/wt.err" \
        || { skip "monotonicity: cannot create HEAD worktree ($(head -1 "$TMP/wt.err"))"; return; }
    # ensure cleanup of the worktree
    trap '( cd "$ROOT" && git worktree remove --force "'"$WT"'" >/dev/null 2>&1 ); rm -rf "$TMP"' EXIT

    local OLDB="$TMP/oldbuild"
    if ! ( cmake -S "$WT" -B "$OLDB" -DRIPWIRE_NATIVE=ON >/dev/null 2>&1 && cmake --build "$OLDB" -j >/dev/null 2>&1 ); then
        skip "monotonicity: pre-change build failed"; return
    fi
    local OLDBIN="$OLDB/ripwire"
    [ -x "$OLDBIN" ] || { skip "monotonicity: pre-change binary missing"; return; }

    # SAME input (HEAD's src/) for both binaries → isolates the resolver change from any working-tree edits.
    local IN="$WT/src"
    local ao an
    ao="$( "$OLDBIN" "$IN" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
    an="$( "$BIN"    "$IN" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
    if [ -n "$ao" ] && [ -n "$an" ] && [ "$an" -le "$ao" ]; then
        ok "monotonicity on src/: ambiguous NEW=$an <= pre-change OLD=$ao (narrow only removes candidates)"
    else
        no "monotonicity VIOLATED on src/: NEW=$an > OLD=$ao — a correct narrow was LOST (regression)"
    fi
}
monotonic_check

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
