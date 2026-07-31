#!/usr/bin/env bash
# FIXTURE (expect NOACC) — the fail-fast family: no accumulator at all, every failure exits where it is
# found. 10 gates in this tree are shaped like this. The class trap #27 names cannot occur here (there
# is no accumulator to leave unread), so the meta-gate PINS the membership of this family instead of
# claiming to prove it: a NEW gate landing here reds until someone probes it by hand.
set -u

if [ ! -d . ]; then
    echo "  FAIL  the current directory vanished"
    exit 1
fi
echo "  PASS  a check that passes"
echo "ALL PASS"
exit 0
