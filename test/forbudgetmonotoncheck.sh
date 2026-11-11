#!/usr/bin/env bash
# forbudgetmonotoncheck.sh — the --for auto bundle's SECTION-BUDGET interaction: a wider ceiling never
# buys less decisive content (classb-bytes-memo §2's N=8000 trap, 2026-08-22 round; docs/EVALS.md §4).
#
# THE DEFECT this gate reproduces (measured on the r10 class-B set, PLAN_HARVEST_REPORTS_2026-08-20/
# classb-bytes-memo.md §2): an explicit --token-budget ABOVE the default's effective ceiling relaxed the
# <sigs> trim ladder — the sig section ballooned (DJ-B1: 1,782 B -> 9,483 B, 8 rows -> 40) and crowded the
# auto <bodies> walk from 6 served bodies down to 2, so the bundle got BIGGER (3.33x the competitor
# baseline) and WORSE on the one axis the r10 judging credited (full bodies of the decisive symbols).
# Mechanism: sigsBudget was `bundleBudget - fixedBytes` — the sig side had FIRST CLAIM on the entire
# explicit ceiling, while the body allowance (kForAutoBodyBudgetBytes) existed only in the default regime.
#
# THE CONTRACT (the fix): in auto-bundle mode with no explicit --pack-top-n, the sig side's claim on the
# ceiling is min(bundleBudget, kForPayloadBudgetBytes) — an explicit ceiling relaxes the sig trim only up
# to the DEFAULT sig budget; every byte beyond it flows to the bodies. Consequences this gate asserts:
#   1) at any explicit ceiling >= the default EFFECTIVE ceiling (kForPayloadBudgetBytes +
#      kForAutoBodyBudgetBytes = 13,500 B; >= --token-budget=6357 at the conservative rate), the <sigs>
#      block is byte-identical to the DEFAULT regime's — the sig side is already at its frozen share —
#      and the body budget is therefore provably >= the default's: every body the default serves fits.
#   2) monotone within the explicit regime: a larger --token-budget in that band serves a body SUPERSET
#      (same frozen sigs, strictly more body room).
#   3) the carve-out: an explicit --pack-top-n is an explicit SIG posture and keeps the legacy
#      sig-first claim (the caller asked for rows; the frozen share would trim them to the floor).
# NOT asserted: body-COUNT monotonicity within one packBodies walk — serialize.h's §H5 budget-walk
# comment re-diagnosed that as rank-priority, not a defect; this gate is about the SECTION split, and its
# fixture keeps all six candidate bodies small and near-equal so set inclusion is the observable.
#
# WHY EVERY BODY ARM PASSES --auto-bodies (added 2026-08-23, landing this round on a trunk that had since
# gained the COMPACT conceptual route): the fixture query is deliberately conceptual (no anchor — see the
# presence guard below), and on the conceptual route the default bundle is now COMPACT (bundle="compact"
# bodies="0" reason="compact-route": a <hops> edge section, no body CDATA). Without --auto-bodies every
# body arm below would compare an EMPTY body set against an EMPTY body set and pass VACUOUSLY — green, and
# no longer watching anything. --auto-bodies is the permanent flag the compact round shipped for exactly
# this case: restore the rank-first body walk on the conceptual route. It does not touch the rule under
# test — the sig-side cap keys off autoBundleMode/packTopN, which both serving shapes share — so the arms
# measure the same contract the round registered. Arm #5 then re-asserts the frozen sig share on the
# COMPACT shape itself, so the section split is gated on BOTH serving paths, not only the one this fixture
# can show bodies on.
#
# THE FIXTURE is engineered and content-stable (the packtaskmonotoncheck precedent — never derived from
# the live repo, so the trap margin cannot drift with ripwire's own source): six near-equal ~550 B body
# candidates that all fit the default body budget, plus 34 fat-signature fillers that (a) each match one
# query term, so the LB-A relevance floor keeps them, and (b) inflate the natural <sigs> section well past
# the default sig budget, so the default regime trims (capped="1") and a pre-fix explicit N=8000 balloons.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/forbudgetmonotoncheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
# SIBLING-DEMOTE (forsiblingdemote.h) is a no-budget XML post-pass that prints deep same-file <d> rows (past <d> rank 10) as
# <t> pointers; a budget-held, --json or --candidates answer is left as shaped. This gate pins the sig/body section split across ceilings (a budget-held answer is never demoted, so the default's sigs would be the only demoted side),
# so it reads the undemoted answer; the demote's rule, guards and budget interplay are pinned in forsiblingdemotecheck.
export RIPWIRE_NO_SIBLING_DEMOTE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "forbudgetmonotoncheck: BIN=$BIN"

# ── the engineered fixture (see the header comment for why each half has the size it has) ───────────────
WORK="$TMP/repo"; mkdir -p "$WORK/src"
python3 - "$WORK" <<'PYEOF'
import os, sys
work = sys.argv[1]
cands = []
for lane, ordinal in [ ("primary","One"), ("secondary","Two"), ("tertiary","Three"),
                       ("quaternary","Four"), ("quinary","Five"), ("senary","Six") ]:
    body = "\n".join( f"    total = total + step * {j};   // frobwidget pipeline schedule quantum stage row {j}"
                      for j in range(6) )
    cands.append( f"""// frobwidget pipeline schedule: orders the quantum stages for the {lane} lane
// and applies the frobwidget schedule to each pipeline stage in rank order.
int frobwidgetPipelineScheduleStage{ordinal}( int step )
{{
    int total = step;
{body}
    return total;
}}
""" )
fill = []
for j in range(34):
    ps = ", ".join( f"int theVeryDescriptivelyNamedOperandNumber{k}ForBookkeepingHelperTable{j:02d}"
                    for k in range(5) )
    fill.append( f"""// helper utility {j}: maintains one pipeline bookkeeping table for the wider frobnication subsystem
int pipelineBookkeepingHelperNumber{j:02d}ExtendedTableMaintenance( {ps} )
{{
    return theVeryDescriptivelyNamedOperandNumber0ForBookkeepingHelperTable{j:02d} + {j};
}}
""" )
files = { "src/stages_a.cpp": cands[0:3], "src/stages_b.cpp": cands[3:6],
          "src/helpers_a.cpp": fill[0:12], "src/helpers_b.cpp": fill[12:24], "src/helpers_c.cpp": fill[24:34] }
for path, chunks in files.items():
    open( os.path.join( work, path ), "w" ).write( "\n".join( chunks ) )
PYEOF

Q="how does the frobwidget pipeline schedule its quantum stages"
STAGES="One Two Three Four Five Six"

# the <sigs>…</sigs> span, extracted byte-exactly (the forautobodycheck precedent: sed's pattern-space
# handling of the very long minified line proved unreliable for a byte-identity assertion)
sigsblock(){ python3 -c 'import sys; s=open(sys.argv[1],"rb").read(); a=s.find(b"<sigs"); b=s.find(b"</sigs>"); sys.stdout.buffer.write(s[a:b+7] if a>=0 and b>=0 else b"")' "$1"; }
bodyset(){ grep -o 'n="frobwidgetPipelineScheduleStage[A-Za-z]*">' "$1" | sed 's/.*Stage//; s/">//' | sort; }
bodiesattr(){ grep -o 'bundle="auto" bodies="[0-9]*"' "$1" | head -1; }
# the <sigs> block's rows, one p:l:n per line (score or shown order as served) — the set-prefix h arms' row key
rowkeys(){ python3 -c 'import re,sys; s=open(sys.argv[1],encoding="utf-8",errors="replace").read(); a=s.find("<sigs"); b=s.find("</sigs>"); blk=s[a:b] if a>=0 and b>=0 else ""
at=lambda t,k: (re.search(r"\s"+k+r"=\"([^\"]*)\"",t) or [None,""])[1]
print("".join(at(t,"p")+":"+at(t,"l")+":"+at(t,"n")+"\n" for t in re.findall(r"<d [^>]*>",blk)),end="")' "$1"; }
export RIPWIRE_TESTLIB="$ROOT/test/lib"   # softbudget.py set_prefix: the head round-robin h arms (lane hrr)
setprefix(){ python3 "$RIPWIRE_TESTLIB/softbudget.py" setprefix "$1" "$2" "$3"; }

# --auto-bodies on every body arm: the fixture's route is conceptual and that route now serves COMPACT by
# default — see "WHY EVERY BODY ARM PASSES --auto-bodies" in the header.
run(){ "$BIN" "$WORK/src" --for="$Q" $2 --no-cache >"$TMP/$1" 2>/dev/null || no "run [$2] exited non-zero"; }
run def   "--auto-bodies"
run tb8k  "--auto-bodies --token-budget=8000"
run tb12k "--auto-bodies --token-budget=12000"
run cdef  ""
run c8k   "--token-budget=8000"
# head round-robin (lane hrr, train 31; PROCESS rule 4, ruling FIX1 §4(a)): the no-budget default reorders its first 8 rows
# (<sigs files_first=N>) while an explicit --token-budget keeps score order, so the frozen-share BYTE identity (#1, #5) holds only
# in score order. Each runs unchanged on the RIPWIRE_NO_HEAD_RR=1 twin (every call of the arm under it); #1h/#5h assert what still
# holds with the reorder on: the explicit ceiling serves exactly the default's rows, as a set (the twin's rows, score ranks 1..K).
RIPWIRE_NO_HEAD_RR=1 run defT "--auto-bodies"
RIPWIRE_NO_HEAD_RR=1 run tb8kT "--auto-bodies --token-budget=8000"
RIPWIRE_NO_HEAD_RR=1 run c8kT "--token-budget=8000"

# ── presence guards: the fixture must reproduce the TRAP PRECONDITIONS, or every arm below is inert ─────
grep -q 'anchors: ' "$TMP/def" \
    && no "presence: the query routed name-exact — re-author it, the rank-first body walk is unobservable" \
    || ok "presence: conceptual route (no anchor), the rank-first body walk is live"
# cut-fix lane A (2026-09-23): capped="1" is no longer always the tag's LAST attribute — docs_dropped="N" follows it when a
# shown row lost its doc comment (this fixture's does) — so the presence test reads the attribute, not the tag's end.
grep -qE '<sigs [^>]*capped="1"[ >]' "$TMP/def" \
    && ok "presence: the default regime trims the sig section (capped=\"1\") — the ladder is engaged" \
    || no "presence: default <sigs> not capped — the fixture's sig bulk no longer exceeds the default sig budget"
DATTR=$( bodiesattr "$TMP/def" )
[ "$DATTR" = 'bundle="auto" bodies="6"' ] \
    && ok "presence: the default regime serves ALL six candidate bodies ($DATTR)" \
    || no "presence: default did not serve all six bodies (attr='$DATTR') — set inclusion below loses its baseline"

# ── #1: THE INVARIANT at the measured trap point (--token-budget=8000 -> ~16,992 B >= 13,500 B) ─────────
#        every body the default serves is still served, and the sig side sits at its frozen share
#        (byte-identical to the default's render). Pre-fix this is the memo's 6-bodies -> 2 collapse.
bodyset "$TMP/def"  >"$TMP/set_def"
bodyset "$TMP/tb8k" >"$TMP/set_8k"
MISSING=$( comm -23 "$TMP/set_def" "$TMP/set_8k" | tr '\n' ' ' )
[ -z "$MISSING" ] \
    && ok "#1 a ceiling above the default effective ceiling keeps every default-served body" \
    || no "#1 --token-budget=8000 DROPPED default-served bodies: stage(s) $MISSING(the memo's re-inflation trap)"
sigsblock "$TMP/defT"  >"$TMP/sigs_def"   # the RIPWIRE_NO_HEAD_RR=1 twin (lane hrr, rule 4): see the twin runs above
sigsblock "$TMP/tb8kT" >"$TMP/sigs_8kT"
sigsblock "$TMP/tb8k" >"$TMP/sigs_8k"
[ -s "$TMP/sigs_def" ] || no "#1 presence: could not extract a <sigs> block from the default run"
# forbudget-soft (rule 4): the default answer discloses the rows it serves past its 7.5 KB target (<sigs past_target="K">);
# a soft target names none (its rows are inside its own target). Everything else — every row, its text tier, the
# continuation — must still be the default's byte for byte: the frozen-share invariant, minus that one disclosure.
diff -q <( sed 's/ past_target="[0-9]*"//' "$TMP/sigs_def" ) "$TMP/sigs_8kT" >/dev/null \
    && ok "#1 [RIPWIRE_NO_HEAD_RR=1 twin] the sig section at the explicit ceiling is byte-identical to the default's (frozen share)" \
    || no "#1 [RIPWIRE_NO_HEAD_RR=1 twin] the explicit ceiling re-inflated the sig section (default $( wc -c <"$TMP/sigs_def" | tr -d ' ' ) B vs 8000 $( wc -c <"$TMP/sigs_8kT" | tr -d ' ' ) B)"
rowkeys "$TMP/def" >"$TMP/rk_def"; rowkeys "$TMP/tb8k" >"$TMP/rk_8k"; rowkeys "$TMP/defT" >"$TMP/rk_defT"
{ [ -s "$TMP/rk_def" ] && [ "$( wc -l <"$TMP/rk_8k" )" = "$( wc -l <"$TMP/rk_def" )" ] && setprefix "$TMP/rk_8k" "$TMP/rk_def" "$TMP/rk_defT"; } \
    && ok "#1h head round-robin on: the explicit ceiling serves exactly the default's $( wc -l <"$TMP/rk_def" | tr -d ' ' ) rows as a set (the twin's, frozen share)" \
    || no "#1h head round-robin on: the explicit ceiling's rows ($( wc -l <"$TMP/rk_8k" | tr -d ' ' )) are not the default's rows as a set ($( wc -l <"$TMP/rk_def" | tr -d ' ' ))"

# ── #2: monotone WITHIN the explicit regime — a larger ceiling serves a body superset, same frozen sigs ─
bodyset "$TMP/tb12k" >"$TMP/set_12k"
MISSING2=$( comm -23 "$TMP/set_8k" "$TMP/set_12k" | tr '\n' ' ' )
[ -z "$MISSING2" ] \
    && ok "#2 12000 tokens serve a body superset of 8000 tokens" \
    || no "#2 a LARGER explicit budget dropped bodies the smaller one served: stage(s) $MISSING2"
sigsblock "$TMP/tb12k" >"$TMP/sigs_12k"
diff -q "$TMP/sigs_8k" "$TMP/sigs_12k" >/dev/null \
    && ok "#2 the sig section is byte-identical across the explicit band (both at the frozen share)" \
    || no "#2 the sig section moved between two above-threshold ceilings (it must be frozen there)"

# ── #3: the carve-out — an explicit --pack-top-n keeps the legacy sig-first claim ───────────────────────
"$BIN" "$WORK/src" --for="$Q" --auto-bodies --pack-top-n=40 --token-budget=8000 --no-cache >"$TMP/topn" 2>/dev/null \
    || no "#3 --pack-top-n=40 --token-budget=8000 exited non-zero"
sigsblock "$TMP/topn" >"$TMP/sigs_topn"
SB_FROZEN=$( wc -c <"$TMP/sigs_8k"   | tr -d ' ' )
SB_TOPN=$(   wc -c <"$TMP/sigs_topn" | tr -d ' ' )
[ "$SB_TOPN" -gt "$SB_FROZEN" ] \
    && ok "#3 explicit --pack-top-n keeps sig-first claim on the ceiling ($SB_TOPN B > frozen $SB_FROZEN B)" \
    || no "#3 explicit --pack-top-n no longer beats the frozen share ($SB_TOPN B vs $SB_FROZEN B) — the row knob went inert under a budget"
grep -q 'bundle="auto"' "$TMP/topn" \
    && ok "#3 the carve-out is still the auto bundle (bodies remain on the leftover)" \
    || no "#3 --pack-top-n turned the auto surface off (it must only re-order the claim, not remove bodies)"

# ── #4: determinism x2 at the trap point, and G4 well-formedness on every arm ───────────────────────────
"$BIN" "$WORK/src" --for="$Q" --auto-bodies --token-budget=8000 --no-cache >"$TMP/tb8k_b" 2>/dev/null
diff -q "$TMP/tb8k" "$TMP/tb8k_b" >/dev/null \
    && ok "#4 the explicit-ceiling bundle is deterministic (byte-identical x2)" \
    || no "#4 the explicit-ceiling bundle is NON-deterministic across two runs"
# ── #5: the SAME frozen sig share on the COMPACT serving shape (no --auto-bodies) ──────────────────────
#        The cap keys off autoBundleMode/packTopN, which the compact route shares, so an explicit ceiling
#        must not re-inflate <sigs> there either — the leftover is what the <hops> section draws on.
#        Without this arm the fix would be gated only on the shape --auto-bodies reveals.
grep -q 'bundle="compact"' "$TMP/cdef" \
    && ok "#5 presence: the conceptual route's DEFAULT bundle is compact (the shape #1-#4 opt out of)" \
    || no "#5 presence: the default conceptual bundle is not compact — re-check which shape this fixture serves"
# body-fold (train 31; rule 4, by design): the default compact answer now carries the fold's <sigs> continuation pair (next= the first
# skipped body, sigs_next= the signatures-only re-call; forbodyfoldcheck (F3)/(F5)), which a soft target — no fold — never does. The
# frozen-share invariant is about the rows, so it is read off the fold-off twin of the default, byte for byte as before.
RIPWIRE_NO_BODY_FOLD=1 "$BIN" "$WORK/src" --for="$Q" --no-cache >"$TMP/cdefoffR" 2>/dev/null || no "run [fold-off default] exited non-zero"
# lane hrr (rule 4): the byte arm reads the RIPWIRE_NO_HEAD_RR=1 twin of both calls; #5h below reads the reorder-on pair
RIPWIRE_NO_BODY_FOLD=1 RIPWIRE_NO_HEAD_RR=1 "$BIN" "$WORK/src" --for="$Q" --no-cache >"$TMP/cdefoff" 2>/dev/null || no "run [fold-off RR-off default] exited non-zero"
sigsblock "$TMP/cdefoff" >"$TMP/sigs_cdef"
sigsblock "$TMP/c8kT"  >"$TMP/sigs_c8k"
[ -s "$TMP/sigs_cdef" ] || no "#5 presence: could not extract a <sigs> block from the compact default run"
# forbudget-soft (rule 4): the default answer discloses the rows it serves past its 7.5 KB target (<sigs past_target="K">);
# a soft target names none (its rows are inside its own target). Everything else — every row, its text tier, the
# continuation — must still be the default's byte for byte: the frozen-share invariant, minus that one disclosure.
diff -q <( sed 's/ past_target="[0-9]*"//' "$TMP/sigs_cdef" ) "$TMP/sigs_c8k" >/dev/null \
    && ok "#5 [RIPWIRE_NO_HEAD_RR=1 twin] the compact route's sig section is byte-identical at the explicit ceiling (frozen share)" \
    || no "#5 [RIPWIRE_NO_HEAD_RR=1 twin] the explicit ceiling re-inflated the COMPACT route's sig section (default $( wc -c <"$TMP/sigs_cdef" | tr -d ' ' ) B vs 8000 $( wc -c <"$TMP/sigs_c8k" | tr -d ' ' ) B)"
rowkeys "$TMP/cdefoffR" >"$TMP/rk_cdef"; rowkeys "$TMP/c8k" >"$TMP/rk_c8k"; rowkeys "$TMP/cdefoff" >"$TMP/rk_cdefT"
{ [ -s "$TMP/rk_cdef" ] && [ "$( wc -l <"$TMP/rk_c8k" )" = "$( wc -l <"$TMP/rk_cdef" )" ] && setprefix "$TMP/rk_c8k" "$TMP/rk_cdef" "$TMP/rk_cdefT"; } \
    && ok "#5h head round-robin on: the compact route's explicit ceiling serves exactly the default's $( wc -l <"$TMP/rk_cdef" | tr -d ' ' ) rows as a set (the twin's)" \
    || no "#5h head round-robin on: the compact route's explicit-ceiling rows ($( wc -l <"$TMP/rk_c8k" | tr -d ' ' )) are not the default's rows as a set ($( wc -l <"$TMP/rk_cdef" | tr -d ' ' ))"

lint=1
for F in def tb8k tb12k topn cdef c8k defT tb8kT c8kT cdefoffR cdefoff; do   # + the RIPWIRE_NO_HEAD_RR=1 / fold-off twins (lane hrr nit)
    xmllint --noout "$TMP/$F" 2>/dev/null || { echo "    malformed: $F"; lint=0; }
done
if [ "$lint" = 1 ]; then ok "#4 all arms well-formed XML (G4)"; else no "#4 malformed XML"; fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
