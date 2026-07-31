#!/usr/bin/env bash
# FIXTURE (expect OK) — the if/else terminal form, 59 gates in this tree.
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

ok "a check that passes"

if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
