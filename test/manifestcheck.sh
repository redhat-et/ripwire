#!/usr/bin/env bash
# manifestcheck.sh — every committed top-level *check.sh gate must be owned by regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
REGRESSION="$ROOT/test/regression.sh"
EVALS="$ROOT/docs/EVALS.md"
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

# ── gate-count drift: docs/EVALS.md §8 quotes the loop's length as a known-honest number; that
# quote must equal the loop's ACTUAL length or it is itself the exact stale-docstring drift §8 is
# complaining about. Both sides are derived here, not hand-copied, so they cannot silently disagree
# again. The loop is the single `for _g in NAME NAME ...; do` line in regression.sh (the bulk-absorbed
# gates); the four gates invoked individually above it (g1freshcheck, skillscan, htmlexport,
# compresscheck) are NOT part of "the loop" and are deliberately excluded from this count, matching
# what §8's prose actually refers to.
loopNames="$( python3 -c "
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'for _g in (.*?); do', text, re.S)
sys.exit('no loop found') if not m else print(len(m.group(1).split()))
" "$REGRESSION" )"
evalsStated="$( grep -oE 'loop in `test/regression\.sh` names [0-9]+' "$EVALS" | head -1 | grep -oE '[0-9]+$' )"
if [ -z "$evalsStated" ]; then
    printf 'FAIL: docs/EVALS.md has no "loop in `test/regression.sh` names N" sentence to check (§8)\n'
    fail=1
elif [ -z "$loopNames" ]; then
    printf 'FAIL: could not derive the gate count from the for-loop in test/regression.sh\n'
    fail=1
elif [ "$evalsStated" = "$loopNames" ]; then
    printf 'PASS: docs/EVALS.md §8 gate count (%s) matches test/regression.sh loop length (%s)\n' "$evalsStated" "$loopNames"
else
    printf 'FAIL: docs/EVALS.md §8 says the loop names %s, but it actually names %s — update docs/EVALS.md:395\n' "$evalsStated" "$loopNames"
    fail=1
fi

exit "$fail"
