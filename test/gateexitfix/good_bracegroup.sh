#!/usr/bin/env bash
# FIXTURE (expect OK) — the brace-group terminal form, 22 gates in this tree. This is the one the
# trap #27 grep flags as a false positive: it has no `exit $fail`, and it propagates correctly.
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

ok "a check that passes"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
