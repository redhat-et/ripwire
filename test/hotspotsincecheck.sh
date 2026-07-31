#!/usr/bin/env bash
# hotspotsincecheck.sh — §P0.5c gate: --hotspots must not report an all-history scan under a window label
# nobody asked for, and its header comment must agree with its window= attribute.
#
#   --hotspots --since=nonsense    -> window="12mo", exit 0; degrade only on stderr   (before)
#   --hotspots --since=notaref9z   -> window="notaref9z", exit 0, stderr EMPTY        (before — the digit
#                                     slipped past the coarse looksLikeDate gate and git approxidate turned
#                                     it into an arbitrary timestamp)
#   --hotspots --since="2 weeks ago" -> window="2 weeks ago" but the header comment still said (window=12mo)
#
# A false NON-zero: the churn numbers are real, the window they are labelled with is not, and the only
# honest signal was a DEGRADED_PATH_ALERT on stderr — invisible to every MCP client.
#
#   CTXPACK_BIN=build/ctxpack      bash test/hotspotsincecheck.sh
#   CTXPACK_BIN=build_base/ctxpack bash test/hotspotsincecheck.sh   # must FAIL (pre-fix binary)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
# BOTH seams — `bash test/<gate>.sh asan/ctxpack` is how a differential run passes a binary, and this gate
# accepted the positional argument and silently ignored it, so a red-first run measured build/ctxpack.
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo "SKIP: not a git repo"; exit 0; }
echo "hotspotsincecheck: BIN=$BIN  ROOT=$ROOT"

# ── 1. an unresolvable --since refuses, naming the value, with no <hotspots> element
refuseCase(){
    local value="$1"
    "$BIN" "$ROOT" --hotspots --since="$value" >"$TMP/out" 2>"$TMP/err"; local rc=$?
    [ "$rc" -eq 1 ] && ok "--since='$value': exit 1" || no "--since='$value': exit $rc (expected 1)"
    grep -q -- "$value" "$TMP/err" && ok "--since='$value': refusal names the value" \
        || no "--since='$value': refusal does not name the value: $( head -c 200 "$TMP/err" )"
    grep -q '<hotspots' "$TMP/out" && no "--since='$value': still emitted a <hotspots> element" \
        || ok "--since='$value': no <hotspots> element on the refusal path"
}
refuseCase nonsense
refuseCase notaref9z          # the digit used to slip past looksLikeDate and become an arbitrary window

# ── 2. a VALID window is reported honestly in BOTH places — attribute and header comment (§P9 N7)
"$BIN" "$ROOT" --hotspots --since="2 weeks ago" >"$TMP/ok" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && ok '--since="2 weeks ago": exit 0' || no "--since=\"2 weeks ago\": exit $rc (expected 0)"
grep -q '<hotspots window="2 weeks ago"' "$TMP/ok" && ok 'window= says "2 weeks ago"' \
    || no "window= is not \"2 weeks ago\": $( grep -oE '<hotspots [^>]*' "$TMP/ok" | head -c 120 )"
grep -q '(window=2 weeks ago)' "$TMP/ok" && ok 'header comment says (window=2 weeks ago) — agrees with the attribute' \
    || no "header comment disagrees with window=: $( grep -oE '\(window=[^)]*\)' "$TMP/ok" | head -1 )"
grep -q '(window=12mo)' "$TMP/ok" && no 'header comment still hardcodes (window=12mo) under a --since' \
    || ok 'header comment no longer hardcodes 12mo'

# a revision boundary is the deterministic form and must keep working
"$BIN" "$ROOT" --hotspots --since=HEAD~5 >"$TMP/rev" 2>/dev/null; rcr=$?
[ "$rcr" -eq 0 ] && grep -q '<hotspots window="HEAD~5"' "$TMP/rev" \
    && ok "--since=HEAD~5 (revision) still scopes and exits 0" \
    || no "--since=HEAD~5: exit $rcr without window=\"HEAD~5\""

# ── 3. no --since at all: the default window, in both places, unchanged
"$BIN" "$ROOT" --hotspots >"$TMP/def" 2>/dev/null; rcd=$?
[ "$rcd" -eq 0 ] && grep -q '<hotspots window="12mo"' "$TMP/def" && grep -q '(window=12mo)' "$TMP/def" \
    && ok 'default --hotspots: window="12mo" in both attribute and comment' \
    || no "default --hotspots: exit $rcd, window/comment not both 12mo"

# ── adversarial-round extension: the shared looksLikeDate() tightening reaches the DEGRADE verbs too ─
# --cochange/--rank-by=churn keep their documented degrade-to-all-history policy on a bad --since, but
# the tightening changed WHAT degrades: a digit-bearing garbage value (notaref9z) used to be handed to
# git approxidate as a "date" and produced a nonsense window. Pin the corrected behavior: garbage now
# degrades to all-history, i.e. output equals the bare invocation.
"$BIN" "$ROOT" --cochange --since=notaref9z > "$TMP/cs_garbage.out" 2>/dev/null
"$BIN" "$ROOT" --cochange                   > "$TMP/cs_bare.out"    2>/dev/null
cmp -s "$TMP/cs_garbage.out" "$TMP/cs_bare.out" \
    && ok "--cochange --since=<garbage> degrades to all-history (equals bare --cochange, no fabricated window)" \
    || no "--cochange --since=<garbage> differs from bare --cochange — a garbage value still shapes the window"
"$BIN" "$ROOT" --rank-by=churn --since=notaref9z --top-k=5 > "$TMP/rb_garbage.out" 2>/dev/null
"$BIN" "$ROOT" --rank-by=churn                   --top-k=5 > "$TMP/rb_bare.out"    2>/dev/null
cmp -s "$TMP/rb_garbage.out" "$TMP/rb_bare.out" \
    && ok "--rank-by=churn --since=<garbage> degrades to all-history (equals bare form)" \
    || no "--rank-by=churn --since=<garbage> differs from bare form — a garbage value still shapes the window"

# ── ranked= RECONCILES AGAINST A DENOMINATOR ─────────────────────────────────────────────────────────
# ranked="209" was emitted with nothing to divide it by, and the two ways a file misses the ranking — no
# churn in the window, no function or method to score — were dropped by one `if` into one silent absence.
# On this repo that hid 669 of 878 files, and the split is not what a reader would guess: 667 have no
# complexity to score at all and only 2 are churn-free.
#
# Asserted as an IDENTITY, not as four numbers: the four attributes must reconcile on whatever corpus this
# runs against, today and after the repo grows (a pinned count is a gate with an expiry date). Plus the
# denominator must be the SAME files= the default map reports — a second, differently-drawn total under the
# same attribute name would be worse than no denominator.
HS="$( "$BIN" "$ROOT" --hotspots 2>/dev/null | grep -oE '<hotspots [^>]*' )"
hsattr(){ printf '%s' "$HS" | grep -oE " $1=\"[0-9]+\"" | grep -oE '[0-9]+'; }
HS_FILES="$( hsattr files )"; HS_RANKED="$( hsattr ranked )"
HS_NOCHURN="$( hsattr unranked_no_churn )"; HS_NOCX="$( hsattr unranked_no_complexity )"
if [ -z "$HS_FILES" ] || [ -z "$HS_RANKED" ] || [ -z "$HS_NOCHURN" ] || [ -z "$HS_NOCX" ]; then
    no "--hotspots does not carry the ranked= denominator + both exclusion counts: $HS"
else
    SUM=$(( HS_RANKED + HS_NOCHURN + HS_NOCX ))
    [ "$SUM" = "$HS_FILES" ] \
        && ok "--hotspots: ranked($HS_RANKED) + no_churn($HS_NOCHURN) + no_complexity($HS_NOCX) = files($HS_FILES) — the partition is exact" \
        || no "--hotspots partition does not reconcile: $HS_RANKED + $HS_NOCHURN + $HS_NOCX = $SUM, files=$HS_FILES"
    MAP_FILES="$( "$BIN" "$ROOT" --top-k=1 2>/dev/null | grep -oE 'files=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
    [ -n "$MAP_FILES" ] && [ "$MAP_FILES" = "$HS_FILES" ] \
        && ok "--hotspots files=\"$HS_FILES\" is the same denominator the default map reports" \
        || no "--hotspots files=$HS_FILES disagrees with the map's files=${MAP_FILES:-<unread>}"
    # the legend must SAY that no_churn conflates a quiet file with one the git-path join never bound —
    # otherwise the number reads as a measure of quietness, which it is not.
    "$BIN" "$ROOT" --hotspots 2>/dev/null | grep -oE '<!--[^>]*-->' | head -1 | grep -q 'join never bound' \
        && ok "--hotspots legend states that unranked_no_churn conflates quiet files with unbound ones" \
        || no "--hotspots legend does not disclose what unranked_no_churn conflates"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
