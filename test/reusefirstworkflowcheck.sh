#!/usr/bin/env bash
# reusefirstworkflowcheck.sh — retrieve the relevant building block before paying for a generic exemplar.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
SKILL="$ROOT/skills/ripwire-reuse-first/SKILL.md"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -f "$SKILL" ] || { echo "missing $SKILL"; exit 2; }
forLine="$( grep -n -m1 -- '--for=' "$SKILL" | cut -d: -f1 )"
exemplarLine="$( grep -n -m1 -- '--exemplar=' "$SKILL" | cut -d: -f1 )"

if [ -n "$forLine" ] && [ -n "$exemplarLine" ] && [ "$forLine" -lt "$exemplarLine" ]; then
    ok "building-block retrieval precedes the generic exemplar ($forLine < $exemplarLine)"
else
    no "generic exemplar still precedes relevant retrieval (for=${forLine:-missing}, exemplar=${exemplarLine:-missing})"
fi
grep -qiE 'optional|if.*(style|shape)|when.*(style|shape)' "$SKILL" \
    && ok "skill makes the generic exemplar conditional on needing a style/shape reference" \
    || no "skill still presents the unrelated generic exemplar as mandatory"

[ "$fail" -eq 0 ] && echo "reusefirstworkflowcheck: ALL PASS" || echo "reusefirstworkflowcheck: FAILURES"
exit "$fail"
