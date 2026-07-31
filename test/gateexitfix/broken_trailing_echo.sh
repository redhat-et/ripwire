#!/usr/bin/env bash
# FIXTURE (expect BROKEN) — the THIRD shape: an exit IS present and IS reached on the pass path, but the
# failure path falls through to a plain `echo`, whose rc 0 becomes the script's. A grep for `exit $fail`
# is satisfied by nothing here, and a grep for "does it contain an exit" is satisfied by line 10.
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

ok "a check that passes"

[ "$fail" = 0 ] && exit 0
echo "FAILURES ABOVE"
