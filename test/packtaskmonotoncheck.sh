#!/usr/bin/env bash
# packtaskmonotoncheck.sh — W2-K: --pack-task's section fill must be MONOTONIC in --token-budget.
#
# THE DEFECT (E4, PLAN_WAVE2_REPORTS_2026-08-17/exp-e4.md): a bigger --token-budget could show FEWER bodies
# (5 bodies at 4000, 2 at 4500 on the ripwire-src corpus, reproduced on two binaries) — a bigger budget should
# never make the answer WORSE. The orchestrator's kill clause required a real, shared mechanism (not a
# corpus-specific coincidence) before funding a fix, and named the correction that governs THIS gate: cliff
# LOCATIONS are corpus-content-dependent — they move with what the corpus/task happen to rank — so this gate
# asserts the PROPERTY (non-decreasing fill as budget grows) on a FIXED, content-stable, in-repo fixture. It
# never pins a specific budget where a cliff used to sit, or a specific kept-count at a specific budget — a
# pinned location rots (or passes for the wrong reason) the moment the ranking/fitting internals shift by even
# one byte. See PLAN_WAVE2_REPORTS_2026-08-17/lane-w2k.md for the mechanism verification, the fix, and the RED
# transcript this gate reproduces against the pre-fix binary.
#
# THE FIXTURE is engineered, not incidental: one candidate (cliffProbeTargetFunction) with a body sized to
# cross the bodies-section budget threshold partway through the swept ladder, and six smaller candidates that
# compete with it for room — the same shape as packBodies' own streaming admission (skip-and-continue, "fill
# top-rank-first") that the lane report proves is not monotone in its own budget: a bigger budget can newly
# admit ONE large candidate that then starves several smaller ones a smaller budget had room for. A caller,
# a reaching test and a field note round out callers/tests/notes coverage.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/packtaskmonotoncheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "packtaskmonotoncheck: BIN=$BIN"

# ── the fixture: content-stable (never re-derived from the live repo), so a cliff location this gate finds
#    today cannot silently drift as ripwire's OWN source changes — see the header comment above for the shape.
WORK="$TMP/repo"; mkdir -p "$WORK/src" "$WORK/test"
{
    echo "// cliffprobe target function primary body"
    echo "int cliffProbeTargetFunction( int x )"
    echo "{"
    for i in $( seq 0 44 ); do
        echo "    x = x + $i;   // cliffprobe target function padding statement $i"
    done
    echo "    return x;"
    echo "}"
    n=1
    for nm in cliffProbeSmallOne cliffProbeSmallTwo cliffProbeSmallThree cliffProbeSmallFour cliffProbeSmallFive cliffProbeSmallSix; do
        echo "// cliffprobe target function helper $nm"
        echo "int $nm( int x ) { return x + $n; }"
        n=$(( n + 1 ))
    done
    echo "int cliffProbeCallerCoverage( int x ) { return cliffProbeTargetFunction( x ) + cliffProbeSmallOne( x ); }"
} > "$WORK/src/budgetcliff.cpp"
cat > "$WORK/test/test_budgetcliff.cpp" <<'EOF'
#include "../src/budgetcliff.cpp"
int run_cliffprobe_tests() { return cliffProbeCallerCoverage( 1 ); }
EOF
( cd "$WORK" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )
runw(){ ( cd "$WORK" && "$BIN" . --no-cache "$@" 2>/dev/null ); }

TASK="cliffprobe target function"
# a field note on the target — notes_kept coverage. --note-add's target spelling is forgiving (a bare symbol
# name resolves when unambiguous, as it is in this single-file fixture), so no id-discovery round-trip needed.
runw --note-add="cliffProbeTargetFunction: cliffprobe field note" >/dev/null 2>&1

# ── the swept budget ladder — the same 15-level shape E4 used, no budget singled out as a cliff site ────────
LADDER="300 600 900 1200 1600 2000 2500 3000 3500 4000 4500 5000 6000 7000 8000"

prev_bodies=-1; prev_callers=-1; prev_notes=-1; prev_tests=-1
prev_bodies_total=-1
mono_ok=1
declare -a ROWS=()
# ── W2-K.2 arm (a), verifier FINDING K1 — RELEVANCE monotonicity, which the count arm above cannot see ──────
#    The count can rise while the answer gets WORSE: measured against the pre-fix binary on THIS fixture,
#    raising the budget 900 -> 1200 deleted the body of `cliffProbeTargetFunction` — the function the task
#    literally names, and the top-ranked body candidate — and substituted two one-line helpers that scored a
#    higher count; it stayed deleted through 4000. The property asserted here is a RATCHET, not a pinned
#    budget (same reason as the header's note about cliff locations): once the bundle has shown that body at
#    some budget, no LARGER budget may drop it. `tgt_seen` below is the ratchet, `tgt_final` the presence
#    guard that stops the arm going vacuous if the fixture ever stops producing that body at all.
TGTBODY="cliffProbeTargetFunction"
tgt_seen=0; tgt_final=0; tgt_ok=1
# ── W2-K.2 arm (b), verifier FINDING K2 — the budget a capped bundle leaves UNSPENT ──────────────────────────
#    monotoneRoll charges a capped section its whole granted share and donates nothing forward. Correct, but
#    with <bodies> (the one section whose items differ by two orders of magnitude) sitting SECOND in the
#    cascade, the bytes it could not spend were buried in front of four sections that could have. Measured on
#    the pre-fix binary on THIS fixture: fill 51.6% at budget 3500 and 45.2% at 4000 while <bodies> was capped
#    at 5 of 6 — content dropped for want of room, with more than half the budget never spent. The property:
#    if the bundle DROPPED anything (any section capped), then the budget must actually be full. Rungs where
#    nothing is capped are exempt — a small bundle that fits everything it has is not stranding anything.
#    KFILLFLOOR is deliberately far below the post-fix measurement (94.0% at 3500, 82.3% at 4000, >=105% at
#    every smaller capped rung) so ordinary content drift cannot red it, and far above the pre-fix numbers it
#    is built to catch. Byte-exact and content-stable: no wall-clock, no environment term.
KFILLFLOOR=75
fill_ok=1; fill_arm_armed=0
for tb in $LADDER; do
    OUT="$TMP/b$tb.json"
    runw --pack-task="$TASK" --token-budget="$tb" --json > "$OUT"
    read -r bt bk ct ck nt nk tt tk <<PYEOF
$( python3 -c "
import json
d = json.load(open('$OUT'))
print(d.get('bodies_total',0), d.get('bodies_kept',0), d.get('callers_total',0), d.get('callers_kept',0),
      d.get('notes_total',0), d.get('notes_kept',0), d.get('tests_total',0), d.get('tests_kept',0))
" )
PYEOF
    ROWS+=( "budget=$tb bodies=$bk/$bt callers=$ck/$ct notes=$nk/$nt tests=$tk/$tt" )

    # the CANDIDATE SET (bodies_total) must itself be budget-independent for this to be a clean property test
    # — it always is by construction (rank order, not budget, selects the candidates) — a drifting total would
    # mean the fixture stopped exercising a fixed set and any regression report below would be unreliable.
    if [ "$prev_bodies_total" != "-1" ] && [ "$bt" != "$prev_bodies_total" ]; then
        no "bodies_total drifted with budget ($prev_bodies_total -> $bt at budget=$tb) — fixture no longer budget-independent"
        mono_ok=0
    fi
    prev_bodies_total="$bt"

    if [ "$prev_bodies" != "-1" ] && [ "$bk" -lt "$prev_bodies" ]; then
        no "NON-MONOTONIC bodies_kept: $prev_bodies -> $bk at budget=$tb (a bigger budget showed FEWER bodies)"
        mono_ok=0
    fi
    if [ "$prev_callers" != "-1" ] && [ "$ck" -lt "$prev_callers" ]; then
        no "NON-MONOTONIC callers_kept: $prev_callers -> $ck at budget=$tb"
        mono_ok=0
    fi
    if [ "$prev_notes" != "-1" ] && [ "$nk" -lt "$prev_notes" ]; then
        no "NON-MONOTONIC notes_kept: $prev_notes -> $nk at budget=$tb"
        mono_ok=0
    fi
    if [ "$prev_tests" != "-1" ] && [ "$tk" -lt "$prev_tests" ]; then
        no "NON-MONOTONIC tests_kept: $prev_tests -> $tk at budget=$tb"
        mono_ok=0
    fi
    prev_bodies="$bk"; prev_callers="$ck"; prev_notes="$nk"; prev_tests="$tk"

    xmllint --noout "$( runw --pack-task="$TASK" --token-budget="$tb" > "$TMP/x$tb.xml"; echo "$TMP/x$tb.xml" )" 2>/dev/null \
        || { no "budget=$tb bundle is not well-formed"; mono_ok=0; }

    # arm (a) — the ratchet. A `<b … n="NAME">` row is the BODY; the same name in <sigs> is only a signature,
    # so the open tag is matched, never a bare name grep.
    if grep -q "<b [^>]*n=\"$TGTBODY\"" "$TMP/x$tb.xml"; then
        tgt_seen=1;  tgt_final=1
    else
        tgt_final=0
        if [ "$tgt_seen" = "1" ]; then
            no "budget=$tb DROPPED the task-named body $TGTBODY that a SMALLER budget had shown (relevance regression)"
            tgt_ok=0
        fi
    fi

    # arm (b) — capped ⇒ the budget must be spent. The working byte budget is the same expression the bundle
    # header states: token target x kMinBytesPerToken(2.36) x kBudgetHeadroom(0.90).
    BYTES="$( wc -c < "$TMP/x$tb.xml" | tr -d ' ' )"
    CAPPED=0
    [ "$bk" -lt "$bt" ] && CAPPED=1
    [ "$ck" -lt "$ct" ] && CAPPED=1
    [ "$nk" -lt "$nt" ] && CAPPED=1
    [ "$tk" -lt "$tt" ] && CAPPED=1
    if [ "$CAPPED" = "1" ]; then
        fill_arm_armed=1
        PCT="$( python3 -c "print( int( $BYTES * 100 / ( $tb * 2.36 * 0.90 ) ) )" )"
        if [ "$PCT" -lt "$KFILLFLOOR" ]; then
            no "budget=$tb dropped content (a section is capped) with only ${PCT}% of the byte budget spent (floor ${KFILLFLOOR}%) — budget stranded, not exhausted"
            fill_ok=0
        fi
    fi
done

echo "  ladder: ${ROWS[*]}"
[ "$mono_ok" = "1" ] && ok "bodies/callers/notes/tests kept counts are NON-DECREASING across the full budget ladder"

# arm (a) verdict + its presence guard: if the top rung does not carry that body at all, the ratchet above
# never had anything to ratchet and would have passed while inert.
[ "$tgt_final" = "1" ] || { no "the top budget rung shows no <b> body for $TGTBODY — arm (a) never armed"; tgt_ok=0; }
[ "$tgt_ok" = "1" ] && ok "the task-named top-ranked body ($TGTBODY) is never DROPPED by a larger budget (relevance ratchet)"

# arm (b) verdict + its presence guard.
[ "$fill_arm_armed" = "1" ] || { no "no rung on the ladder capped any section — arm (b) never armed (fixture no longer competes for room)"; fill_ok=0; }
[ "$fill_ok" = "1" ] && ok "every rung that DROPPED content spent at least ${KFILLFLOOR}% of its byte budget (no stranded budget)"

# sanity: the fixture actually exercised the mechanism — bodies_total must be > 1 (several real candidates
# competing for room) somewhere on the ladder, else "monotonic" would be trivially true and this gate would
# never have been red against the pre-fix binary.
MAXTOTAL="$( printf '%s\n' "${ROWS[@]}" | grep -oE 'bodies=[0-9]+/[0-9]+' | sed -E 's#.*/##' | sort -n | tail -1 )"
[ -n "$MAXTOTAL" ] && [ "$MAXTOTAL" -ge 6 ] \
    && ok "fixture exercises a real multi-candidate bodies section (bodies_total=$MAXTOTAL)" \
    || no "fixture bodies_total never reached a meaningful candidate count (got $MAXTOTAL) — cliff mechanism not exercised"

# determinism ×2 at the budget the lane report's manual RED run found the cliff on THIS fixture (informational
# only — not a pinned assertion of WHERE the cliff sits, just the usual determinism gate every value needs).
D1="$( runw --pack-task="$TASK" --token-budget=2500 )"
D2="$( runw --pack-task="$TASK" --token-budget=2500 )"
[ "$D1" = "$D2" ] && ok "bundle is deterministic (byte-identical ×2) at a mid-ladder budget" || no "bundle is non-deterministic"

if [ "$fail" = "0" ]; then
    echo "ALL PASS"
else
    echo "FAILURES ABOVE"
fi
exit "$fail"
