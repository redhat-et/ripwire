#!/usr/bin/env bash
# grepbytescheck.sh — the KILL-CONDITION gate for the G1 grep-emission overhaul (2026-08-15 harvest).
#
# The round's own premise (PLAN_HARVEST_REPORTS_2026-08-15/report-ugrep.md, report-memgraph.md §F6,
# report-octocode.md §F1, report-graphrag.md Finding 2): --grep is TOKEN-NEGATIVE against plain `grep -rn`
# on ripwire's own tree — the EVALS §5 anti-headline (+19.7% / -11.2%). G1's fix is pure emission policy
# (root-relative paths once, per-file grouping under <f p=…>, byte-identical-match collapse via <at>
# siblings, honest in= omission) — no ranking change, no frozen-query-set obligation.
#
# This gate re-derives the SAME shape EVALS §5 used (bytes of the ripwire --grep payload vs `grep -rn` on
# the same fixture+query) on a small FROZEN set of queries against ripwire's own src/ tree, and asserts
# the median REDUCTION — how much SMALLER ripwire's payload is than plain grep's, a POSITIVE number when
# ripwire wins — clears the round's own kill-condition bar.
#
# KILL CONDITION (stated in the round's own brief): median payload reduction across the fixture set < 30%
# ⇒ G1's collapse/grouping theory is REFUTED — report it, keep only the honesty/refusal pieces (F1, the
# in= omission), and say so. This gate is the mechanical form of that check.
#
# Usage:
#   bash test/grepbytescheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire bash test/grepbytescheck.sh
# Exits non-zero if the kill condition fires (median reduction < 30%) or a presence guard fails.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "grepbytescheck: BIN=$BIN"

# ── frozen fixture queries — the round brief's own list (stale/cache/buffer/resize/multi-file), scoped ──
# to src/ so the comparison is corpus-comparable (grep -rn over docs/present/ would pad grep's own count
# with matches ripwire's crawl denylist/tier ordering never claimed to beat). resize is deliberately kept
# (the brief names it the HONEST COUNTER-CASE: hits genuinely are code in distinct symbols, few duplicates
# to fold) — a real median, not a cherry-picked one. langOfPathh (zero-hit) belongs to G4's own gate, not
# here — a zero-hit answer has no "payload" to compare bytes on.
QUERIES=(stale cache buffer resize DEGRADED_PATH_ALERT)

# ── presence guards (CONTRIBUTING.md §2: a gate that cannot observe what it asserts is green for the
#    wrong reason) — before trusting a byte count, prove the feature that is supposed to produce it fired ──
PROBE_XML="$( "$BIN" "$ROOT" --no-cache --grep=stale 2>/dev/null )"
printf '%s' "$PROBE_XML" | grep -q '<f p=' \
    && ok "presence guard: per-file grouping (<f p=…>) is actually emitted" \
    || { no "presence guard: no <f p=…> in --grep output — grouping is not firing, the byte numbers below prove nothing"; exit 1; }
printf '%s' "$PROBE_XML" | xmllint --noout - 2>/dev/null \
    && ok "presence guard: grouped output is well-formed XML" \
    || no "presence guard: grouped output is malformed XML"

# ── per-query byte measurement ────────────────────────────────────────────────────────────────────────
declare -a REDUCTIONS=()
echo
printf '%-22s %10s %10s %8s\n' "query" "ripwire_B" "grep_B" "reduction"
for q in "${QUERIES[@]}"; do
    RW_BYTES="$( "$BIN" "$ROOT" --no-cache --grep="$q" 2>/dev/null | wc -c | tr -d ' ' )"
    GREP_BYTES="$( grep -rn -F "$q" "$ROOT/src" 2>/dev/null | wc -c | tr -d ' ' )"

    if [ "${RW_BYTES:-0}" -le 0 ]; then
        no "$q: ripwire produced 0 bytes — cannot measure a reduction against nothing"
        continue
    fi
    if [ "${GREP_BYTES:-0}" -le 0 ]; then
        no "$q: grep -rn -F found 0 bytes on src/ — the query does not exercise the fixture (pick a different frozen query)"
        continue
    fi

    reduction="$( python3 -c "print( round( 100.0 * ( 1.0 - $RW_BYTES / $GREP_BYTES ), 1 ) )" )"
    REDUCTIONS+=( "$reduction" )
    printf '%-22s %10s %10s %7s%%\n' "$q" "$RW_BYTES" "$GREP_BYTES" "$reduction"
done
echo

if [ "${#REDUCTIONS[@]}" -eq 0 ]; then
    no "no query produced a measurable reduction — every arm above failed its own presence guard"
    echo; echo "SOME CHECKS FAILED"; exit 1
fi

MEDIAN="$( python3 -c "
vals = sorted( float( x ) for x in '''${REDUCTIONS[*]}'''.split() )
n = len( vals )
mid = n // 2
med = vals[mid] if n % 2 else ( vals[mid-1] + vals[mid] ) / 2.0
print( round( med, 1 ) )
" )"

echo "median payload reduction across ${#REDUCTIONS[@]} frozen queries: ${MEDIAN}%"
echo

KILL_BAR="30.0"
if python3 -c "exit( 0 if float( '$MEDIAN' ) >= float( '$KILL_BAR' ) else 1 )"; then
    ok "median reduction ${MEDIAN}% >= the ${KILL_BAR}% kill-condition bar — G1's grouping/collapse theory HOLDS"
else
    no "median reduction ${MEDIAN}% < the ${KILL_BAR}% kill-condition bar — G1's grouping/collapse theory is REFUTED (see the round brief's own instruction: keep only the honesty/refusal pieces)"
fi

# ── determinism: the byte count itself must not be a coin flip ─────────────────────────────────────────
D1="$( "$BIN" "$ROOT" --no-cache --grep=stale 2>/dev/null | wc -c )"
D2="$( "$BIN" "$ROOT" --no-cache --grep=stale 2>/dev/null | wc -c )"
[ "$D1" = "$D2" ] \
    && ok "determinism: byte count is stable across runs ($D1 B)" \
    || no "determinism: byte count differs run to run ($D1 vs $D2) — the measurement itself is unstable"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
