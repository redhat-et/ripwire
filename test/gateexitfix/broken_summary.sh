#!/usr/bin/env bash
# FIXTURE (expect BROKEN) — the trap #27 construct, verbatim: `||`'s echo succeeds, so the script
# exits 0 with failures printed. This is the shape test/tracecheck.sh, test/editcheckcheck.sh and
# test/notescheck.sh each shipped with. gateexitcheck.sh MUST classify this file BROKEN; if it ever
# says OK, the meta-gate has stopped working and every real gate is unguarded again.
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

ok "a check that passes"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
