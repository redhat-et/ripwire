#!/usr/bin/env bash
# FIXTURE (expect BROKEN) — the SECOND shape of the same class, the one the grep in trap #27 cannot see
# at all: the accumulator is written by the recorder and NEVER READ. test/g1freshcheck.sh shipped like
# this. There is no defect in the exit line; the defect is that no exit line consults `fail`.
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

ok "a check that passes"

echo "ALL PASS"
exit 0
