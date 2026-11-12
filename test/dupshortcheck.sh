#!/usr/bin/env bash
# dupshortcheck.sh — QD-DUP-SHORT: the one-statement idiom (src/cloneidiom.h, decision C3) against REAL history.
#
# WHY THIS GATE EXISTS. Agents answered duplication rows on one-line helpers by un-sharing, lambda-hiding or
# reshaping the one-liner. Some of those rows were FALSE: two one-statement predicates that shared nothing but
# C++ grammar and their parameter names (`siteLess | keyLess`, `errorMaskHitGates | sameFamily`). Others were
# TRUE and must keep gating: `recallBytesForTokens | ceilingAllowanceBytes` (the `budgetBytesForTokens` fix —
# they share the named constant `kMinBytesPerToken`), `qualifiedName | callerHopSelector` (a one-line copy).
# The fixture arms in test/cloneidiomcheck.sh pin the rule's shape; this gate pins its EFFECT on the commits
# that motivated it, by replaying each fix reversed:
#     --quality-delta=FIX..FIX^ --quality-kinds=duplication,new-clone-of-reused-helper
# (baseline = the fixed tree, current = the tree before the fix, so the row the fix answered reappears).
#
# WHAT THIS GATE PINS
#   (A) MUST DEMOTE — each named false pair is reported minor (not gating) with idiom="one-statement", on
#       both clone kinds where the fix carried both.
#   (B) MUST KEEP GATING — each named true pair still gates: the shared-constant pair, the one-line copy, the
#       two-statement `afterLast` family, the same-file pair, the shared-callee pair, the two-statement copy.
#   (C) COMMIT-LEVEL — exactly 7037e7e03, e4bd12b94 and 00cb4ac60 reach 0 gating rows; the other replays keep
#       the counts the brief stated, so nobody over-claims what the idiom removed.
#   (D) PREMISE COUNT — the members the replays classified one-statement are counted. 0 FAILS (a classifier
#       that never fires would pass every keep arm vacuously), and fewer than 16 of the 18 named one-statement
#       members FAILS.
#
# It needs the repository's full history (CI checks out with fetch-depth 0 for the churn gates); a missing
# commit is a FAIL, never a skip.
#
# Usage:  bash test/dupshortcheck.sh [BIN]        RIPWIRE_REPLAY_REPO=<clone> overrides the repo replayed.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
REPO="${RIPWIRE_REPLAY_REPO:-$ROOT}"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
echo "dupshortcheck: BIN=$BIN REPO=$REPO"

# commit  expected-gating-rows-after-the-card
COMMITS="7037e7e03 0
e4bd12b94 0
00cb4ac60 0
1d604ab41 3
bae4d12f6 1
c5b45f163 1
1a009c9f7 10
dd29aa8c2 1
760a433c7 2
3b7931830 14"

while read -r c _; do
    if ! git -C "$REPO" cat-file -e "$c^{commit}" 2>/dev/null || ! git -C "$REPO" cat-file -e "$c^^{commit}" 2>/dev/null; then
        no "commit $c (or its parent) is not in $REPO — this gate replays real history and needs a full clone"
    fi
done <<EOF
$COMMITS
EOF
[ "$fail" = 0 ] || { echo; echo "FAILURES"; exit 1; }

# One replay per commit, sequentially (each is a whole-repo quality-delta; never two at once).
while read -r c _; do
    ( cd "$REPO" && "$BIN" . --quality-delta="$c..$c^" --quality-kinds=duplication,new-clone-of-reused-helper ) \
        >"$TMP/$c.xml" 2>"$TMP/$c.err"
    echo "$?" >"$TMP/$c.rc"
done <<EOF
$COMMITS
EOF

# rows <commit> — one <r ...> clone row per line
rows(){ tr '<' '\n' <"$TMP/$1.xml" | grep -E '^r kind="(duplication|new-clone-of-reused-helper)"'; }
# pairrows <commit> <memberA> <memberB> [kind] — the rows whose member list names both (as ::name)
pairrows(){ rows "$1" | grep -E "${4:-kind=\"duplication\"}" | grep -F "::$2 " | grep -F "::$3\""; pairrows_rev "$@"; }
pairrows_rev(){ rows "$1" | grep -E "${4:-kind=\"duplication\"}" | grep -F "::$3 " | grep -F "::$2\""; }

# ── (A) must demote ───────────────────────────────────────────────────────────────────────────────────
demoted()
{
    local c="$1" a="$2" b="$3" kind="${4:-kind=\"duplication\"}" r
    r="$( pairrows "$c" "$a" "$b" "$kind" )"
    if [ -z "$r" ]; then no "$c: no ${kind#kind=} row for $a | $b at all"; return; fi
    case "$r" in
        *'gating="1"'*)            no "$c: $a | $b still gates (${kind#kind=})";;
        *'idiom="one-statement"'*) ok "$c: $a | $b demoted to minor, idiom=one-statement (${kind#kind=})";;
        *)                         no "$c: $a | $b not gating but carries no idiom=one-statement (${kind#kind=}): $r";;
    esac
}
demoted 7037e7e03 siteLess          keyLess
demoted e4bd12b94 errorMaskHitGates sameFamily
demoted 00cb4ac60 isHandlerShaped   declinedCallMayReach
demoted 00cb4ac60 isHandlerShaped   isServed
demoted 00cb4ac60 isHandlerShaped   isServed  'kind="new-clone-of-reused-helper"'
demoted 1d604ab41 shipsViewFlag     varSpansCover
demoted bae4d12f6 containsAny       namesEvents

# ── (B) must keep gating ──────────────────────────────────────────────────────────────────────────────
gates()
{
    local c="$1" a="$2" b="$3" kind="${4:-kind=\"duplication\"}" r
    r="$( pairrows "$c" "$a" "$b" "$kind" )"
    case "$r" in
        '')            no "$c: no ${kind#kind=} row for $a | $b at all";;
        *'gating="1"'*) ok "$c: $a | $b still gates (${kind#kind=})";;
        *)             no "$c: $a | $b stopped gating (${kind#kind=}): $r";;
    esac
}
gates 760a433c7 recallBytesForTokens ceilingAllowanceBytes
gates 760a433c7 recallBytesForTokens ceilingAllowanceBytes 'kind="new-clone-of-reused-helper"'
gates dd29aa8c2 qualifiedName        callerHopSelector
gates bae4d12f6 containsAny          isKeyFileToken
gates c5b45f163 isCQuoteRootProbe    isBareTsSpecifier
gates 1a009c9f7 pathDirOf            includerDir
# every row of the afterLast fix: its members are two statements each, so none of them is this idiom
n3b="$( rows 3b7931830 | wc -l | tr -d ' ' )"; g3b="$( rows 3b7931830 | grep -c 'gating="1"' )"
if [ "$n3b" -gt 0 ] && [ "$n3b" = "$g3b" ]; then ok "3b7931830: all $n3b afterLast-family rows still gate"; else no "3b7931830: $g3b of $n3b rows gate"; fi
if rows 3b7931830 | grep -q 'idiom="one-statement"'; then no "3b7931830: a two-statement member was classified one-statement"; else ok "3b7931830: no two-statement member classified one-statement"; fi

# ── (C) commit-level gating counts, and the exit status that must agree with them ─────────────────────
# quality-delta exits 2 when a row gates and 0 when none does; any other status is a failed run whose
# (possibly empty) document every arm above would otherwise read as an answer.
while read -r c want; do
    got="$( rows "$c" | grep -c 'gating="1"' )"
    if [ "$got" = "$want" ]; then ok "$c: $got gating clone rows (expected $want)"; else no "$c: $got gating clone rows, expected $want"; fi
    rc="$( cat "$TMP/$c.rc" )"; wantrc=0; [ "$want" -gt 0 ] && wantrc=2
    if [ "$rc" = "$wantrc" ]; then ok "$c: exit $rc (expected $wantrc)"; else no "$c: exit $rc, expected $wantrc ($( head -c 200 "$TMP/$c.err" ))"; fi
done <<EOF
$COMMITS
EOF

# ── (D) premise count ─────────────────────────────────────────────────────────────────────────────────
NAMED="siteLess keyLess errorMaskHitGates sameFamily isHandlerShaped declinedCallMayReach isServed shipsViewFlag varSpansCover containsAny namesEvents recallBytesForTokens ceilingAllowanceBytes qualifiedName callerHopSelector isKeyFileToken isCQuoteRootProbe isBareTsSpecifier"
while read -r c _; do rows "$c"; done <<EOF >"$TMP/all.rows"
$COMMITS
EOF
grep 'idiom="one-statement"' "$TMP/all.rows" | grep -oE '(members|sym)="[^"]*"' | sed -E 's/^[a-z]+="//; s/"$//' \
    | tr '|' '\n' | sed -E 's/^ *//; s/ *$//; s/.*:://' | sort -u >"$TMP/classified"
total="$( wc -l <"$TMP/classified" | tr -d ' ' )"
hit=0
for m in $NAMED; do grep -qxF "$m" "$TMP/classified" && hit=$(( hit + 1 )); done
if [ "$total" -gt 0 ]; then ok "premise: $total distinct members classified one-statement across the replays"; else no "premise: the replays classified 0 members one-statement — every keep arm above is vacuous"; fi
if [ "$hit" -ge 16 ]; then ok "premise: $hit of the 18 named one-statement members classified"; else no "premise: only $hit of the 18 named one-statement members classified (need 16)"; fi

echo
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES"; exit 1
