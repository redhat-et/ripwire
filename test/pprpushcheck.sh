#!/usr/bin/env bash
# pprpushcheck.sh — RANK-SPEED step 2's SHADOW ARM: the push may be measured and may never change an answer.
#
# WHY THIS GATE EXISTS. `rankGraphTeleport` is the PERSONALIZED rank, and at the anchors site
# (src/graph.h anchoredLexicalRank, reached from --for) it is seeded from the QUERY, so an agent asking a
# stream of different questions against one warm graph pays it again on every one of them. Step 2 replaces
# that power iteration with an Andersen-Chung-Lang push. The push is an APPROXIMATION inside the ranking that
# decides what the agent is shown, and the house rule is that an approximation which changes the answer is a
# WRONG ANSWER. So the push ships DEFAULT OFF behind an environment hook, and the only mode anything measures
# it in — `shadow` — computes both and serves the exact one. This gate is what makes that claim checkable.
#
# THE ARM THAT CARRIES THE RATCHET IS (B), AND IT IS THE REASON FOR THE ORDER BELOW. Arm (A) asserts an
# ABSENCE: an unset run writes no shadow row. That is trivially true of a binary with no shadow arm at all,
# so (A) passes on the base and proves nothing on its own — it is the kill switch, not the evidence. Arm (B)
# asserts that `shadow` writes rows AND FAILS WHEN IT SAW ZERO, which is the whole point: a shadow arm that
# never ran must not read as agreement. Every later arm's non-vacuity rests on (B), and the base's red comes
# through it. This asymmetry is the same one test/prconvergecheck.sh records, for the same reason.
#
# RED ON BASE — PREDICTED, NOT YET OBSERVED. A quiet window was held for another lane's sealed timing run
# for the whole of this lane's working time, so nothing here has been built or run and this block is a
# PREDICTION, which is exactly the weaker thing a gate header must not pass off as evidence. The base is
# origin/train/m5-1126-4 @ 4262eec3f, which has no RIPWIRE_PPR_PUSH at all, so the variable is ignored and
# every row count is 0. Confirm it and replace this block with the observed output before trusting the gate:
#
#     RIPWIRE_BIN=<base binary> bash test/pprpushcheck.sh   ->  expected exit 1, 8 FAIL / 9 PASS
#       FAIL  (B) shadow mode wrote ZERO shadow rows -- a shadow arm that never ran is not agreement
#       FAIL  (B) every shadow row carries a parseable eps= value
#       FAIL  (C) shadow stdout is byte-identical to off stdout (vacuous without rows)
#       FAIL  (D) every shadow row has top10_same=1 at the registered epsilon
#       FAIL  (D) every shadow row has blend10_same=1 at the registered epsilon
#       FAIL  (E) the tie-aware criterion is not vacuous: some row reported a compared position
#       FAIL  (E) no shadow row performed a single push
#       FAIL  (G) two shadow runs agree on every non-timing column
#
# THE NINE THAT PASS ON BASE ARE ABSENCE AND INVARIANCE ARMS, and their passing is not a defect in them —
# "no shadow row on an unset run" and "`on` changes nothing" are trivially true of a binary that has no such
# surface anywhere. They are (A)'s two, (C)'s stdout-clean and xmllint checks, (D)'s budget-hit check, (E)'s
# two mutation controls on this gate's OWN pattern discipline, and BOTH of (F)'s. That asymmetry is why (B)
# leads: the absence arms exist only so the presence arms cannot be satisfied by emitting rows everywhere.
#
# GREPS MATCH VALUES, NOT KEYS. The row tag is a literal `pprshadow` at the start of a stderr line and every
# assertion below matches a value shape (`top10_same=1`, `eps=[0-9]`), never a bare key: a key appears in
# legends, comments and disclosure prose, so a key match proves nothing in either direction. This gate was
# made to fail on purpose once per arm before it was trusted (the mutation controls in (E)).
#
# Usage:  bash test/pprpushcheck.sh [BIN]  |  RIPWIRE_BIN=build/ripwire bash test/pprpushcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
# The binary seam, printed FIRST: a gate that silently tested a different binary than the one the caller
# meant is the defect this line exists to make impossible to miss.
printf 'BIN=%s  %s\n' "$BIN" "$( "$BIN" --version 2>&1 | head -1 )"

# One query, one small real corpus: src/ itself. --for is the verb that reaches the anchors site
# (verbs_for.h computeLensRanking -> graph.h anchoredLexicalRank), which is the per-query personalized rank.
QUERY="personalized pagerank teleport seed rank graph"
run_for(){   # $1 mode ("" = unset), $2 stdout file, $3 stderr file
    if [ -z "$1" ]; then
        env -u RIPWIRE_PPR_PUSH "$BIN" "$ROOT/src" --for="$QUERY" --legend=compact >"$2" 2>"$3"
    else
        RIPWIRE_PPR_PUSH="$1" "$BIN" "$ROOT/src" --for="$QUERY" --legend=compact >"$2" 2>"$3"
    fi
    return 0
}
rows(){ grep -c '^pprshadow	' "$1" 2>/dev/null || true; }

run_for ""       "$TMP/off.out"    "$TMP/off.err"
run_for shadow   "$TMP/shadow.out" "$TMP/shadow.err"
run_for shadow   "$TMP/shadow2.out" "$TMP/shadow2.err"
run_for off      "$TMP/explicit.out" "$TMP/explicit.err"
run_for nonsense "$TMP/bogus.out"  "$TMP/bogus.err"

offRows="$( rows "$TMP/off.err" )"
shadowRows="$( rows "$TMP/shadow.err" )"
shadow2Rows="$( rows "$TMP/shadow2.err" )"
explicitRows="$( rows "$TMP/explicit.err" )"
bogusRows="$( rows "$TMP/bogus.err" )"

# ── (A) DEFAULT OFF — the kill switch. Passes on base; see the header. ──────────────────────────────────────
if [ "$offRows" = 0 ] && [ "$explicitRows" = 0 ] && [ "$bogusRows" = 0 ]; then
    ok "(A) unset, =off and an unrecognized value all write zero shadow rows (the default is OFF)"
else
    no "(A) a run that did not ask for the shadow arm wrote rows: unset=$offRows off=$explicitRows bogus=$bogusRows"
fi
# A "must not print X" check passes on unfixed code by default, so the POSITIVE CONTROL comes first: prove
# this --help capture is real and that a grep over it can find something, before believing what it cannot.
"$BIN" --help >"$TMP/help.txt" 2>&1
if [ -s "$TMP/help.txt" ] && grep -q -- '--for' "$TMP/help.txt"; then
    ok "(A) positive control: the --help capture is non-empty ($( wc -c <"$TMP/help.txt" | tr -d ' ' ) B) and a grep over it finds --for"
    if grep -q 'RIPWIRE_PPR_PUSH' "$TMP/help.txt"; then
        no "(A) RIPWIRE_PPR_PUSH appears in --help — G5 says every FLAG is additive and parsed; this is a hook, not a flag"
    else
        ok "(A) RIPWIRE_PPR_PUSH appears in no --help text (it is an arming hook, not a user surface)"
    fi
else
    no "(A) positive control: --help produced nothing a grep could match, so its absence arm would be vacuous"
fi

# ── (B) THE RATCHET — zero shadow rows is a FAILURE ─────────────────────────────────────────────────────────
if [ "$shadowRows" -gt 0 ] 2>/dev/null; then
    ok "(B) shadow mode wrote $shadowRows shadow row(s)"
else
    no "(B) shadow mode wrote ZERO shadow rows -- a shadow arm that never ran is not agreement"
fi
# Every row must carry a parseable value for the columns the verdict reads. Value shapes, never bare keys.
if [ "$shadowRows" -gt 0 ] 2>/dev/null \
   && [ "$( grep -c '^pprshadow	.*	eps=[0-9]' "$TMP/shadow.err" )" = "$shadowRows" ] \
   && [ "$( grep -c '^pprshadow	.*	ms_exact=[0-9]' "$TMP/shadow.err" )" = "$shadowRows" ] \
   && [ "$( grep -c '^pprshadow	.*	ms_push=[0-9]' "$TMP/shadow.err" )" = "$shadowRows" ]; then
    ok "(B) every shadow row carries parseable eps= / ms_exact= / ms_push= values"
else
    no "(B) every shadow row carries a parseable eps= value"
fi

# ── (C) THE ANSWER IS UNCHANGED — the property that makes this safe to build ────────────────────────────────
if [ "$shadowRows" -gt 0 ] 2>/dev/null && cmp -s "$TMP/off.out" "$TMP/shadow.out"; then
    ok "(C) shadow stdout is byte-identical to the unset run's stdout ($( wc -c <"$TMP/off.out" | tr -d ' ' ) B)"
else
    no "(C) shadow stdout is byte-identical to off stdout (vacuous without rows)"
fi
if [ "$( grep -c 'pprshadow' "$TMP/shadow.out" )" = 0 ]; then
    ok "(C) no shadow row reached stdout (G4: no newline outside CDATA, and the document stays well-formed)"
else
    no "(C) a shadow row reached stdout — that breaks XML well-formedness and the token-density contract"
fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/shadow.out" 2>/dev/null; then
        ok "(C) the shadow run's document still pipes clean through xmllint"
    else
        no "(C) the shadow run's document is not well-formed XML"
    fi
else
    printf '  SKIP  (C) xmllint not installed — the well-formedness arm cannot run, and does not pretend to pass\n'
fi

# ── (D) FIDELITY — the BINDING criterion, at the registered epsilon ─────────────────────────────────────────
# top10_same is tie-aware (src/pprshadow.h countNonTieSwaps): a position counts as a swap only when the
# reference's own gap there exceeds tau = 2*tolerance/ranked. top40_jacc and max_abs_err40 are in the rows and
# are deliberately NOT asserted: both are satisfiable by a vector whose top 10 is wrong.
compared="$( grep -c '^pprshadow	.*	top10_same=1' "$TMP/shadow.err" 2>/dev/null || true )"
notSame="$( grep -c '^pprshadow	.*	top10_same=0' "$TMP/shadow.err" 2>/dev/null || true )"
blendSame="$( grep -c '^pprshadow	.*	blend10_same=1' "$TMP/shadow.err" 2>/dev/null || true )"
blendNot="$( grep -c '^pprshadow	.*	blend10_same=0' "$TMP/shadow.err" 2>/dev/null || true )"
if [ "$shadowRows" -gt 0 ] 2>/dev/null && [ "$compared" -gt 0 ] && [ "$notSame" = 0 ]; then
    ok "(D) every compared shadow row has top10_same=1 ($compared row(s), 0 disagreements)"
else
    no "(D) every shadow row has top10_same=1 at the registered epsilon (same=$compared differ=$notSame)"
fi
if [ "$shadowRows" -gt 0 ] 2>/dev/null && [ "$blendSame" -gt 0 ] && [ "$blendNot" = 0 ]; then
    ok "(D) every compared shadow row has blend10_same=1 — the CONSUMER's order agrees, not just the rank's"
else
    no "(D) every shadow row has blend10_same=1 at the registered epsilon (same=$blendSame differ=$blendNot)"
fi
# A row that reached its edge-walk budget is a TRUNCATED push, so its fidelity columns describe a shorter walk
# than the epsilon the row names. It must be disclosed and it must not be silently counted as agreement.
if [ "$( grep -c '^pprshadow	.*	budget_hit=1' "$TMP/shadow.err" 2>/dev/null || true )" = 0 ]; then
    ok "(D) no shadow row hit the edge-walk budget (its fidelity columns describe the epsilon they name)"
else
    no "(D) a shadow row hit the edge-walk budget — the push was truncated, so its top-10 agreement is not evidence for that epsilon"
fi

# ── (E) THE CRITERION IS NOT VACUOUS, and the tie rule is real ──────────────────────────────────────────────
# "top10_same=1 on every row" is trivially true if nothing was ever compared, and tie-awareness is trivially
# satisfiable by calling every position a tie. Both halves are checked, and the mutation controls below make
# the arm fail on purpose once before it is trusted.
if [ "$shadowRows" -gt 0 ] 2>/dev/null && grep -q '^pprshadow	.*	seeds=[1-9]' "$TMP/shadow.err"; then
    ok "(E) at least one shadow row ran on a non-empty seed set (the comparison had something to compare)"
else
    no "(E) the tie-aware criterion is not vacuous: some row reported a compared position"
fi
if [ "$shadowRows" -gt 0 ] 2>/dev/null && grep -q '^pprshadow	.*	pushes=[1-9]' "$TMP/shadow.err"; then
    ok "(E) at least one shadow row performed a push (the kernel ran, rather than returning an empty estimate)"
else
    no "(E) no shadow row performed a single push — the push kernel never ran, so (D) is about nothing"
fi
# Mutation controls on this gate's OWN pattern discipline: a bare-key grep must NOT be what any arm relies on.
mutRow='pprshadow	site=anchors	N=1	nnz=1	seeds=1	eps=3.000e-06	pushes=1	touched=1	edge_walks=1	budget_hit=0	ms_exact=1.000	ms_push=1.000	iters=9	top10_same=0	top10_set_same=0	nontie_swaps=1	tied_positions=0	top40_jacc=0.5000	max_abs_err40=1.000000e-03	min_nontie_gap10=1.000000e-03	tau=1.000000e-09	first_diff=0	blend10_same=0'
printf '%s\n' "$mutRow" >"$TMP/mut.err"
if [ "$( grep -c '^pprshadow	.*	top10_same=0' "$TMP/mut.err" )" = 1 ] \
   && [ "$( grep -c '^pprshadow	.*	top10_same=1' "$TMP/mut.err" )" = 0 ]; then
    ok "(E) mutation control: a planted disagreeing row IS matched by the value pattern (D) relies on"
else
    no "(E) mutation control: (D)'s pattern cannot see a planted top10_same=0 row — the arm is unarmed"
fi
if grep -q 'top10_same' "$TMP/mut.err" && ! grep -q '^pprshadow	.*	top10_same=1' "$TMP/mut.err"; then
    ok "(E) mutation control: the bare KEY matches a row whose VALUE is a disagreement — key greps prove nothing"
else
    no "(E) mutation control: the key-versus-value distinction this gate rests on does not hold"
fi

# ── (F) `on` IS SITE-SCOPED — honesty, not caution ──────────────────────────────────────────────────────────
# anchoredLexicalRank discloses no pr_iters= (its own comment: what leaves it is a BLEND, so no document
# ordered by it was ordered by a power iteration), so serving a push there claims nothing it cannot support.
# The default map DOES print pr_iters=, and the push produces no iteration count, so `on` must not reach it:
# a pr_iters= naming a run that did not happen is a wrong answer, not a rounding.
env -u RIPWIRE_PPR_PUSH "$BIN" "$ROOT/src" --legend=compact >"$TMP/map.off.out" 2>/dev/null
RIPWIRE_PPR_PUSH=on "$BIN" "$ROOT/src" --legend=compact >"$TMP/map.on.out" 2>"$TMP/map.on.err"
if grep -qE 'pr_iters="?[1-9]' "$TMP/map.on.out" && cmp -s "$TMP/map.off.out" "$TMP/map.on.out"; then
    ok "(F) with on, the default map is unchanged and its pr_iters= still names a real power iteration"
else
    no "(F) \`on\` is site-scoped: the default map's pr_iters= still names a real power iteration"
fi
if [ "$( rows "$TMP/map.on.err" )" = 0 ]; then
    ok "(F) the default map's working-set rank is not shadowed (its teleport is dense — lab-only, by design)"
else
    no "(F) the default map wrote a shadow row — the working-set site is measured offline, not here"
fi

# ── (G) DETERMINISM — two shadow runs agree on everything but the clock ─────────────────────────────────────
strip_timings(){ sed -E 's/	ms_exact=[0-9.]+//; s/	ms_push=[0-9.]+//' "$1" | grep '^pprshadow	'; }
if [ "$shadowRows" -gt 0 ] 2>/dev/null && [ "$shadowRows" = "$shadow2Rows" ] \
   && cmp -s "$TMP/shadow.out" "$TMP/shadow2.out" \
   && diff -q <( strip_timings "$TMP/shadow.err" ) <( strip_timings "$TMP/shadow2.err" ) >/dev/null; then
    ok "(G) two shadow runs are byte-identical on stdout and on every non-timing row column"
else
    no "(G) two shadow runs agree on every non-timing column"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
