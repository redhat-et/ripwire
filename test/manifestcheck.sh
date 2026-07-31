#!/usr/bin/env bash
# manifestcheck.sh — every committed top-level *check.sh gate must be owned by regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
REGRESSION="$ROOT/test/regression.sh"
fail=0

while IFS= read -r gatePath; do
    gateName="$( basename "$gatePath" .sh )"
    if ! grep -Eq "(^|[^[:alnum:]_])${gateName}(\\.sh)?([^[:alnum:]_]|$)" "$REGRESSION"; then
        printf 'FAIL: test/%s.sh is not listed in test/regression.sh\n' "$gateName"
        fail=1
    fi
done < <( find "$ROOT/test" -maxdepth 1 -type f -name '*check.sh' | LC_ALL=C sort )

if [ "$fail" = 0 ]; then
    printf 'PASS: every top-level *check.sh gate is listed in regression.sh\n'
fi

exit "$fail"
