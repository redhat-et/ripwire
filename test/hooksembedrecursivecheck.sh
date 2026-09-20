#!/usr/bin/env bash
# hooksembedrecursivecheck.sh — CMakeLists.txt's hooks/ embed step must reach a nested hook script
# (hooks/lib/x.sh), not just the flat hooks/*.sh set (#293 review, item 13).
#
# A private clone (ripwire_private_checkout, never `git worktree add` against $ROOT — see
# test/worktreeleakcheck.sh) exercises the real GLOB_RECURSE call, not a duplicated toy, without ever
# touching the real working tree or registering a worktree a killed run could leak.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v cmake >/dev/null 2>&1 || { echo "SKIP: cmake not on PATH" >&2; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH" >&2; exit 0; }

TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
. "$ROOT/test/lib/headbinlib.sh"

WT="$TMP/wt"                                   # a private clone, never a registered worktree (test/worktreeleakcheck.sh)
if ! ripwire_private_checkout "$ROOT" HEAD "$WT" 2>"$TMP/checkout.err"; then
    no "could not check out HEAD into a private clone: $( head -1 "$TMP/checkout.err" )"
    exit 1
fi

# A real ripwire run against the fresh checkout — best-effort, not gated on — confirms the checkout is
# a genuine, parseable ripwire tree, not merely something `git checkout` reported success on.
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] && "$BIN" "$WT" --no-cache >/dev/null 2>&1

mkdir -p "$WT/hooks/lib"
printf '#!/bin/sh\necho nested-hook-sentinel\n' > "$WT/hooks/lib/x.sh"
chmod +x "$WT/hooks/lib/x.sh"

if cmake -S "$WT" -B "$TMP/build" -DFETCHCONTENT_FULLY_DISCONNECTED=ON >"$TMP/configure.log" 2>&1; then
    ok "isolated checkout configures cleanly with a nested hooks/lib/x.sh present"
else
    no "isolated checkout failed to configure"
    tail -40 "$TMP/configure.log"
    exit 1
fi

HEADER="$TMP/build/generated/embedded_skills.h"
if [ -f "$HEADER" ] && grep -q '"hooks/lib/x.sh"' "$HEADER"; then
    ok "generated embedded_skills.h embeds the nested hooks/lib/x.sh"
else
    no "generated embedded_skills.h does NOT embed hooks/lib/x.sh — hooks/ embed is not recursive"
fi

if [ "$fail" = 0 ]; then
    printf 'PASS: hooks/ embed step reaches a nested hook script\n'
    exit 0
fi
exit 1
