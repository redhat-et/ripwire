#!/usr/bin/env bash
# FIXTURE (expect NOACC, and SKIP-HONEST) — a sanctioned skip. It exits 0 having asserted NOTHING, and
# it says so: a skip marker plus the reason, and no FAIL marker anywhere in its output. §B15's rule is
# that a skip and a pass-with-failures both exit 0 and must still be distinguishable; the distinguisher
# is the printed vocabulary, so the meta-gate reads it rather than papering over the two.
printf '  SKIP  nothing asserted — this fixture needs GATEEXITFIX_ACTIVATE=1 to have anything to check\n'
exit 0
