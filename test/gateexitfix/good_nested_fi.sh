#!/usr/bin/env bash
# FIXTURE (expect OK) — the accumulator's last READ sits inside an enclosing block, so the terminal
# region the classifier extracts ends with an ORPHAN `fi`. test/det-gate.sh has exactly this shape.
# If the classifier's brace-balancing regresses, this fixture flips to UNSYNTHESIZABLE, not to a
# silent pass — which is the point of pinning it here.
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

ok "a check that passes"

if [ -d . ]; then
    [ "$fail" = 0 ] || exit 1
    printf 'ALL PASS\n'
fi
