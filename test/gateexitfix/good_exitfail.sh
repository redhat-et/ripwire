#!/usr/bin/env bash
# FIXTURE (expect OK) — the house terminal form, 175 gates in this tree.
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

ok "a check that passes"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
