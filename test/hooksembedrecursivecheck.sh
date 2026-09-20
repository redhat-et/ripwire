#!/usr/bin/env bash
# hooksembedrecursivecheck.sh — CMakeLists.txt's hooks/ embed step must reach a nested hook script
# (hooks/lib/x.sh), not just the flat hooks/*.sh set (#293 review, item 13).
#
# Configures a scratch `git worktree` checkout (never $ROOT itself), so this exercises the real
# GLOB_RECURSE call, not a duplicated toy.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v cmake >/dev/null 2>&1 || { echo "SKIP: cmake not on PATH" >&2; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH" >&2; exit 0; }

TMP="$( mktemp -d )"
WT="$TMP/wt"
cleanup() { git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1; rm -rf "$TMP"; }
trap cleanup EXIT

if ! git -C "$ROOT" worktree add --detach "$WT" HEAD >"$TMP/worktree.log" 2>&1; then
    no "could not create a scratch git worktree from HEAD"
    cat "$TMP/worktree.log"
    exit 1
fi

mkdir -p "$WT/hooks/lib"
printf '#!/bin/sh\necho nested-hook-sentinel\n' > "$WT/hooks/lib/x.sh"
chmod +x "$WT/hooks/lib/x.sh"

if cmake -S "$WT" -B "$TMP/build" -DFETCHCONTENT_FULLY_DISCONNECTED=ON >"$TMP/configure.log" 2>&1; then
    ok "isolated worktree configures cleanly with a nested hooks/lib/x.sh present"
else
    no "isolated worktree failed to configure"
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
