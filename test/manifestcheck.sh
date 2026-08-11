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

# ── the SIBLINGS of that number, which the check above never saw ────────────────────────────────────
# docs/EVALS.md states the gate count in more than one place, and until now exactly ONE of them was
# enforced. Both unenforced siblings drifted twice: once to 371 while the loop was at 373, and again
# to 374 while the loop reached 376 — the second time within one round of being corrected, because a
# passing manifestcheck reported confidence about a number it had not actually checked. That is
# METHODOLOGY §3 (a fix that lands on one family member and not its siblings) applied to a gate, and
# the fix is the §3 fix: enumerate the family, assert over ALL of it. Every "<N> gate scripts" claim
# in the file is now derived-vs-stated, so a new one added later is covered without editing this gate.
gateCountClaims="$( grep -nE '[0-9]+ gate scripts' "$EVALS" || true )"
if [ -z "$gateCountClaims" ]; then
    printf 'FAIL: docs/EVALS.md has no "<N> gate scripts" claim — the presence guard for this arm found nothing to check\n'
    fail=1
else
    while IFS= read -r claim; do
        claimLine="${claim%%:*}"
        claimNum="$( printf '%s' "$claim" | grep -oE '[0-9]+ gate scripts' | grep -oE '^[0-9]+' )"
        if [ "$claimNum" = "$loopNames" ]; then
            printf 'PASS: docs/EVALS.md:%s gate count (%s) matches the loop\n' "$claimLine" "$claimNum"
        else
            printf 'FAIL: docs/EVALS.md:%s says %s gate scripts, but the loop names %s\n' "$claimLine" "$claimNum" "$loopNames"
            fail=1
        fi
    done <<EOF
$gateCountClaims
EOF
fi

exit "$fail"
