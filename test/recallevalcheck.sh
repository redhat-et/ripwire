#!/usr/bin/env bash
# recallevalcheck.sh — gate for the held-out recall/ranking eval (bench/recalleval/,
# The measuring instrument that must precede §P2b and
# §P4's ranking half). Asserts the INSTRUMENT works — labels load clean, both lanes computable with
# zero skipped queries, two runs byte-identical — and pins only FLOORS/CEILINGS loose enough to
# survive intentional improvement (§P7 philosophy: never pin exact scores; a ranking fix should move
# pollution@5 DOWN and must not trip this gate by improving).
#
# Baseline 2026-07-28 (pre-§P2b/§P4, the numbers any future ranking change must beat):
#   recall  lane: strict_r1=82.1 strict_r5=89.7 lenient_r1=84.6 lenient_r5=97.4 mrr_lenient=0.885 pollution5=2.1
#   ranking lane: strict_r1=56.2 strict_r5=75.0 lenient_r1=59.4 lenient_r5=81.2 mrr_lenient=0.689 pollution5=8.8
#   (ranking adversarial class: pollution5=28.0 — the §P4 number the future fix must move.)
# §P4 landed 2026-07-28 (tier down-weight, filter.h rankTierMultiplierOf ×0.35 in the ranking lenses):
#   ranking lane: strict_r1=59.4 strict_r5=78.1 lenient_r1=65.6 lenient_r5=84.4 mrr_lenient=0.726 pollution5=0.0
#   (adversarial class pollution5=0.0; recall lane byte-identical — §P4 does not touch the docs lens.)
#   Ranking-lane ceilings/floors below are tightened to sit just past those numbers, still floor-style (§P7).
# RECALIBRATED 2026-07-29 (capture-audit-4 Phase 0, R21 owner ruling — labels_ranking.tsv edited with
# per-label reasons recorded in that file; zero ranker changes; these are the frozen bars here-forward):
#   recall  lane: strict_r1=82.1 strict_r5=89.7 lenient_r1=84.6 lenient_r5=97.4 mrr_strict=0.839 mrr_lenient=0.890 pollution5=2.1
#   ranking lane: strict_r1=59.4 strict_r5=78.1 lenient_r1=62.5 lenient_r5=78.1 mrr_strict=0.675 mrr_lenient=0.700 pollution5=0.0
#   (ranking adversarial class pollution5=0.0. NOTE: pollution 0 is a RANKING-LANE claim only — the
#   recall lane's honest baseline is 2.1%; never report "pollution 0 every class". The lenient_r5
#   81.2→78.1 step is the from-trace label re-anchor pricing out a path-only artifact, not a ranker
#   regression; floors below unchanged — still comfortably floor-style under the recalibrated numbers.)
#
# RE-BASELINED 2026-07-31 for the PUBLIC EXPORT (labels_recall.tsv re-authored — 27 of its 39 labels
# named documents this export does not ship, so the recall lane was measuring almost nothing; zero
# ranker changes). Measured on the exported tree, recall=42 / ranking=32 labels, zero skipped:
#   recall  lane: strict_r1=52.4 strict_r5=88.1 lenient_r1=57.1 lenient_r5=92.9 mrr_strict=0.669 mrr_lenient=0.720 pollution5=10.0
#   ranking lane: strict_r1=56.2 strict_r5=75.0 lenient_r1=59.4 lenient_r5=75.0 mrr_strict=0.642 mrr_lenient=0.676 pollution5=0.0
#   (ranking adversarial class pollution5=0.0 — unchanged, and its labels are unchanged.)
#
# TWO THINGS THAT MOVED, both measured, neither a ranker regression:
#   1. Recall-lane pollution 2.1% -> 10.0% is CORPUS COMPOSITION, not a ranking change. The private
#      tree carried ~70 real documents against ~19 fixture markdown files under test/; this export
#      carries ~27 against the same ~19, so the fixture share of any top-5 is structurally higher.
#      Measured split of the 25 polluted slots before the README exemption below: 4 were
#      test/README.md (a legitimate shipped document the path predicate cannot distinguish), 21 were
#      genuine fixture documents. run_recalleval.py now exempts any basename README.md from the
#      fixture predicate — a rule about READMEs, not a special case — leaving 21/210 = 10.0%.
#      FINDING FOR A LATER ROUND: the fixture path-tier de-prioritization was applied to the RANKING
#      lenses only. The recall lens has no fixture defense at all; it looked clean on the private
#      corpus only because real documents outnumbered fixtures there. The ceiling is widened below to
#      16% so this gate measures a regression rather than the corpus, and that gap stays visible.
#   2. Ranking-lane lenient_r5 78.1 -> 75.0 and mrr 0.700 -> 0.676 on UNCHANGED labels: the export
#      moved source files (the first-party infrastructure headers relocated), so a ranked set over a
#      different tree is a different measurement. Recorded, not chased. Floors below still hold with
#      real headroom.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/recallevalcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null || { echo "recallevalcheck: python3 required"; exit 2; }
echo "recallevalcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/run1.txt"; OUT2="$TMP/run2.txt"

# ── #0: BOTH FROZEN CORPORA are intact — each lock's corpus_sha256 matches the bytes on disk. This is
#    the integrity anchor of the whole file (the two FROZEN SNAPSHOT entries below: docs/recall
#    2026-08-07, src/ranking 2026-08-19): a frozen file edited in place, or a refresh that forgot to
#    re-record its lock, must fail HERE, loudly, before any floor below is allowed to measure the wrong
#    corpus. Hard exit: every number after this point is meaningless against a corrupt snapshot.
#    `--verify` with no --corpus checks BOTH, so neither lane can be silently left unanchored. ──────────
if python3 "$ROOT/bench/recalleval/make_snapshot.py" --verify >"$TMP/snap.txt" 2>&1; then
    ok "frozen corpora intact ($( sed 's/^snapshot verified: //' "$TMP/snap.txt" | paste -sd'|' - ))"
else
    no "frozen corpus BROKEN: $( tail -2 "$TMP/snap.txt" | tr '\n' ' ' )"
    echo 'FAILURES ABOVE'; exit 1
fi

# ── #1: the harness runs end-to-end, labels load clean ─────────────────────────────────────────────────
RIPWIRE_BIN="$BIN" python3 "$ROOT/bench/recalleval/run_recalleval.py" >"$OUT" 2>"$TMP/err1.txt"
rc=$?
{ [ "$rc" = 0 ] && grep -q '^labels OK: recall=' "$OUT"; } \
    && ok "harness exit 0, labels load clean ($( grep '^labels OK' "$OUT" ))" \
    || { no "harness failed (rc=$rc): $( head -3 "$TMP/err1.txt" )"; echo 'FAILURES ABOVE'; exit 1; }

# ── #2: both lanes present with a non-trivial sample and ZERO skipped labels ───────────────────────────
# The separator is a REAL tab via $'…', not a '\t' inside a plain-quoted -E pattern: BSD/TRE grep (macOS)
# expands \t to a tab, GNU grep (Linux) does not — it matches a literal 't', so '^AGG\trecall\t' found
# nothing on Ubuntu and this gate reported "missing an AGG row" while every metric below actually cleared
# its floor (first public Linux run: recall lenient_r5=85.7 floor 85, mrr 0.651 floor 0.60; ranking
# lenient_r5=75.0 floor 70, mrr 0.676 floor 0.55, pollution 0.0/8.6). Line 122's CLASS row already used
# the $'…' form and was unaffected — that is the idiom, everywhere in this file.
REC="$( grep -E $'^AGG\trecall\t' "$OUT" )"
RNK="$( grep -E $'^AGG\tranking\t' "$OUT" )"
LIV="$( grep -E $'^AGG\trecall_livepol\t' "$OUT" )"
field(){ printf '%s' "$1" | tr '\t' '\n' | sed -n "s/^$2=//p"; }
{ [ -n "$REC" ] && [ -n "$RNK" ]; } && ok "both AGG rows present" || no "missing an AGG row"
# Each scored lane must announce the corpus it was scored on, and it must be that lane's pinned one — a
# harness silently falling back to the live root would re-open the ratchet this file retired. Asserted
# per lane against its OWN lock, because the two corpora are pinned at different commits by design
# (a docs refresh and a source refresh are independent recalibration commits).
LOCKC="$( sed -n 's/^source_commit=//p' "$ROOT/bench/recalleval/snapshot.lock" )"
grep -q "^snapshot OK: commit=${LOCKC:-MISSING-LOCK}" "$OUT" \
    && ok "recall lane scored the frozen doc corpus (commit ${LOCKC:0:12})" \
    || no "recall lane did not announce the pinned snapshot commit — frozen lane not in effect"
SLOCKC="$( sed -n 's/^source_commit=//p' "$ROOT/bench/recalleval/srcsnapshot.lock" )"
grep -q "^snapshot OK (ranking): commit=${SLOCKC:-MISSING-LOCK}" "$OUT" \
    && ok "ranking lane scored the frozen source corpus (commit ${SLOCKC:0:12})" \
    || no "ranking lane did not announce the pinned source-snapshot commit — frozen lane not in effect"
[ -n "$LIV" ] && ok "live pollution probe row present (recall_livepol)" \
    || no "missing the recall_livepol row — live-corpus composition is unreported"
RN="$( field "$REC" n )"; KN="$( field "$RNK" n )"
{ [ "${RN:-0}" -ge 30 ] && [ "${KN:-0}" -ge 25 ]; } \
    && ok "sample sizes recall=$RN (>=30), ranking=$KN (>=25)" \
    || no "sample too small (recall=$RN ranking=$KN)"
{ [ "$( field "$REC" skipped )" = 0 ] && [ "$( field "$RNK" skipped )" = 0 ]; } \
    && ok "zero skipped labels — every labelled path resolves on disk" \
    || no "skipped labels (a labelled doc/symbol path no longer exists — fix the label)"

# ── #3: metrics computable and numerically sane (recall@1 <= recall@5, values in range) ────────────────
sane=1
for row in "$REC" "$RNK"; do
    r1="$( field "$row" lenient_r1 )"; r5="$( field "$row" lenient_r5 )"
    mrr="$( field "$row" mrr_lenient )"; pol="$( field "$row" pollution5 )"
    awk -v a="$r1" -v b="$r5" 'BEGIN{exit !(a>=0 && b<=100 && a<=b)}' || sane=0
    awk -v m="$mrr" 'BEGIN{exit !(m>=0 && m<=1)}' || sane=0
    awk -v p="$pol" 'BEGIN{exit !(p>=0 && p<=100)}' || sane=0
done
[ "$sane" = 1 ] && ok "metrics in range: recall@1<=recall@5, MRR in [0,1], pollution in [0,100]" \
    || no "a metric is out of range or non-monotone"

# ── #4: DETERMINISM — two runs byte-identical ──────────────────────────────────────────────────────────
RIPWIRE_BIN="$BIN" python3 "$ROOT/bench/recalleval/run_recalleval.py" >"$OUT2" 2>/dev/null
diff -q "$OUT" "$OUT2" >/dev/null \
    && ok "deterministic: two full runs byte-identical" \
    || no "NON-deterministic: two runs differ"

# ── #5: FLOORS (loose, must survive improvement) + pollution CEILINGS (improvement lowers pollution,
#    so a ceiling above today's baseline only trips on regression). Never pin exact scores (§P7). ───────
floor(){ awk -v v="$1" -v f="$2" 'BEGIN{exit !(v>=f)}'; }
ceil(){  awk -v v="$1" -v c="$2" 'BEGIN{exit !(v<=c)}'; }
RL5="$( field "$REC" lenient_r5 )"; RMRR="$( field "$REC" mrr_lenient )"; RPOL="$( field "$REC" pollution5 )"
KL5="$( field "$RNK" lenient_r5 )"; KMRR="$( field "$RNK" mrr_lenient )"; KPOL="$( field "$RNK" pollution5 )"
# 2026-08-03 floor 85→83: corpus growth, not a ranker move — bench/headtohead/r2-2026-08-03/REPORT.md
# joined the doc corpus (second head-to-head report). It is now PRIMARY for the head-to-head query
# (label updated), but for the adversarial query "body elided signature skeletons…" it is a new
# same-class decoy beside the old REPORT.md (already rank 2 pre-change), pushing gold docs/EVALS.md
# 5→6. Ranker neutrality verified: with the new directory removed this lane scores lenient_r5=85.7%
# on the same binary. New baseline 35/42=83.3%; EVALS-outranks-reports on exact-term queries is a
# future ranking task, not a label edit.
# 2026-08-04 floor 83→78: corpus growth again, not a ranker move — present/ (the showcase deck,
# ed24daa) joined the doc corpus. Its README is a new same-class decoy for the task query "what is
# deliberately not published and why": present/README.md (5.129) lands above gold docs/EVALS.md
# (4.605), pushing it rank 5→6 — exactly one query, 35/42→34/42 = 83.3→81.0. Ranker neutrality
# verified on the same binary: this tree with present/ removed AND a clean 786bf7a checkout both
# score lenient_r5=83.3% with an otherwise-identical miss set. (bench/locbench/test_compare_gate.py,
# blamed for an identical 81.0 in the r5 worktree, is exonerated at HEAD: it is tracked since the
# initial import, sits in the 83.3% baseline tree, and removing it from HEAD leaves the lane at
# 81.0.) New baseline 34/42=81.0%. Floor set at 78 — 3.0pt ≈ 1.3 queries under baseline — because
# the r5 lesson is that a floor within one query (2.38pt) of baseline goes red on every same-class
# doc the corpus gains. EVALS-outranks-decoy-READMEs on "publish"-term queries stays a future
# ranking task, not a label edit.
#
#
# 2026-08-05 floor 83→78, AND THE REASON THE MARGIN IS WIDER THIS TIME. Same mechanism, second
# occurrence: the §CLIO --cochange round added a CHANGELOG.md entry that names a gate script ("Gate:
# test/cochangecliocheck.sh"), and CHANGELOG.md entered the task query "I added a gate script where
# must I register it" at RANK 1 — pushing every other row down exactly one and the acceptable gold
# AGENTS.md from 5 to 6. One query, 35/42 → 34/42 = 81.0%.
#   Ranker neutrality verified the same way the 2026-08-03 entry verified it, and more tightly: the
#   NEW binary scored on the PRE-CHANGE tree returns lenient_r5=83.3%, identical to the pre-change
#   binary on that tree. The 2.3pp is entirely corpus growth from prose this round added; nothing in
#   the ranker moved. (A CHANGELOG that mentions a gate is arguably a defensible answer to that
#   query — it is simply not the labelled one.)
#   THE FLOOR ITSELF WAS THE DEFECT. 2026-08-03 set floor=83 against a baseline of 83.3%: a 0.3pp
#   margin, i.e. ZERO documents of headroom, on a lane whose measured failure mode is "a document was
#   added to the repository". It duly went red on the next round that wrote documentation, which is a
#   gate reporting the act of documenting as a regression. 78 leaves ~3 documents of headroom against
#   today's 81.0% while still catching a real collapse (the honest floor for a broken docs lens is
#   2.1%, per the header above), and pollution5 — which IS the ranker-quality signal here — is
#   unmoved at 3.3% on the affected class and stays pinned by its own ceiling.
#
# 2026-08-05 floor 83→78: corpus growth again, not a ranker move — test/preproccondfix (18 files) and
# test/nestedimportfix (5 files) joined the corpus as the fixtures for the import-container extraction
# gates. They add no markdown at all; what moves is the LEXICAL corpus statistics every doc score is
# computed against, and that is enough to swap two docs 5/6 on ONE knife-edge query: for "never use std
# map which container should I reach for instead", prompts/command-tour.md and lenient-gold ./CLAUDE.md
# trade ranks 5 and 6. Exactly one query, 35/42→34/42 = 83.3→81.0. Ranker neutrality verified on the
# same binary: this tree with the two fixture dirs removed scores lenient_r5=83.3%, identical to a clean
# HEAD checkout, with an otherwise-identical miss set — so the extraction change itself moves nothing.
# Floor set at 78, matching the independent 83→78 already made for present/ deck growth on another
# branch (1df219f), and for the same reason: a floor within one query (2.38pt) of baseline goes red on
# every same-class file the corpus gains, which makes it a corpus-size tripwire rather than a ranker gate.
#
# 2026-08-07 floor 78→69. FIFTH occurrence of the same mechanism, SECOND on the very query the
# 2026-08-05 entry above already pinned — and this time the flip is not a new document at all, but an
# EXISTING gold document getting LONGER.
#   The trigger: 3d14e80 added 36 lines to CLAUDE.md (the mixed-object build trap). Those lines
#   contain none of the query's terms, so CLAUDE.md's term frequencies are unchanged while its LENGTH
#   grew — and BM25 length normalization duly lowered its score. On "never use std map which container
#   should I reach for instead", lenient-gold ./CLAUDE.md falls 4.405 → below 4.087, handing rank 5 to
#   ./prompts/command-tour.md (4.395, itself unmoved). The pre-change margin between them was 0.010.
#   That is the identical 5/6 knife-edge pair the 2026-08-05 entry recorded, re-tripped from the other
#   direction. Exactly one query: 33/42 → 32/42.
#   Note what this costs: the lane now reports "an agent documented a build hazard in CLAUDE.md" as a
#   retrieval regression. The primary gold for that query (CONTRIBUTING.md) sits at rank 6 in BOTH
#   states — the lane's "hit" was never the ranker finding the right answer, only an ACCEPTABLE-label
#   doc holding rank 5 by 0.010. Shortening the CLAUDE.md section to buy the rank back was considered
#   and REJECTED: that is editing documentation to fit a benchmark, and the build-trap text has to stay
#   complete. Excluding CLAUDE.md from the corpus was likewise rejected — it is a shipped root doc and
#   a labelled answer to this very query.
#   RANKER NEUTRALITY, verified more tightly than any entry above: the CURRENT binary scored against
#   the 1df219f TREE (that commit checked out into a scratch worktree, today's labels, today's harness)
#   returns lenient_r5=81.0% — reproducing 1df219f's recorded number to the decimal. Every point of
#   81.0 → 76.2 is corpus composition; nothing in three days of ranker work (src/ +12.4k lines) moved
#   this lane at all. pollution@5, which IS the ranker-quality signal here, went 7.6% → 6.2% (better)
#   and stays pinned by its own ceiling.
#   THE OTHER 2.4pt, for completeness: independent of 3d14e80, corpus drift since 1df219f lost "head to
#   head report against other context tools" (lenient 5→7) and "which numbers may I quote publicly and
#   what pins them" (4→7), and GAINED "I am about to write C++ here which style rules apply" (miss→2).
#   Net −1 query. Measured, not chased — same posture as the 2026-07-31 export note.
#   WHY 69 AND NOT ANOTHER 3pt STEP. 1df219f set 3.0pt ≈ 1.3 queries of headroom and stated the intent
#   plainly: "so the next same-class doc the corpus gains costs headroom, not a red gate". It went red
#   in three days, because the measured drift over one documentation-heavy round is 2 net queries, not
#   1.3. 69 is 7.2pt ≈ 3 queries under today's 76.2% — the first value strictly above the observed
#   worst-case drift — and still an enormous distance from the 2.1% an actually-broken docs lens
#   scores, so a real collapse is still caught.
#   THE STANDING DEFECT, stated rather than absorbed: 85→83→78→69 in five days is a gate being ratcheted
#   down by the act of writing documentation. The floor is not the bug; measuring a 42-label lane at
#   2.38pt granularity against a LIVE, growing corpus is. The structural fix is to pin the recall lane
#   to a frozen doc snapshot so it measures the RANKER, and let corpus composition be reported by
#   pollution@5 (which already does that job and has been stable throughout). That is a design round
#   with an owner ruling, not a floor edit — it is deliberately NOT done here, and it is the reason
#   this entry is the last one that should read like the four above it.
#
# 2026-08-07 FROZEN SNAPSHOT — the ruling arrived; the ratchet above is RETIRED and this is the last
# floor entry of its kind. The recall lane no longer scores the live tree: it scores
# bench/recalleval/snapshot.mdpack — every tracked *.md at the commit pinned in snapshot.lock,
# packed into ONE file whose extension the crawler does not index (probed: the pack appears in
# neither --recall nor the flagless map, so the snapshot cannot pollute the live corpus it froze;
# one file, not 113 loose copies, because those 113 pushed warm --edit-check over its 100 ms budget)
# and unpacked by the harness into a temp root per run. On a frozen corpus with a deterministic
# binary, the ONLY input that can move recall/MRR is the ranker, so a red floor below is a ranker
# regression BY CONSTRUCTION — never a document growing, joining, or leaving. Live-corpus
# composition keeps its reporter: the harness re-runs the same queries against the LIVE root and
# emits AGG recall_livepol, which carries the pollution ceiling (unchanged at 16%) — pollution@5 is
# the metric that was stable through all five ratchet entries and is the honest signal for "the live
# tree is filling with fixture decoys".
#   FLOORS, calibrated on the frozen corpus @ 7a7f798 (113 docs; two runs byte-identical): baseline
#   lenient_r5=76.2 (32/42), mrr_lenient=0.619, frozen pollution5=5.2. The frozen 76.2 differs from
#   the same day's LIVE 78.6 because the frozen universe is markdown-only — BM25 corpus statistics
#   shift, and the knife-edge queries this header chronicles sit on different sides; absolute scores
#   are comparable only WITHIN a snapshot generation, which is the entire point. Margins are 2
#   queries: r5 floor 71 (= 76.2 − 2 × 2.38, a third lost query trips at 69.0); MRR floor 0.57
#   (= 0.619 − 2 × 1/42 worst-case reciprocal-rank mass, a third worst-case loss trips at 0.548).
#   Loose enough to survive an intentional ranking improvement that trades away a query (§P7), tight
#   enough that a 3-query regression trips — margins this tight were IMPOSSIBLE against the live
#   corpus, where 2 queries was one documentation round's measured drift. The MRR floor is RETAINED
#   and recalibrated — its live margin (0.613 vs floor 0.60) was the next casualty of the retired
#   mechanism; against the frozen corpus it is a real ranker bar (0.57 < 0.60 is not a loosening:
#   the old 0.60 priced a different, live corpus). The frozen lane's own pollution@5 is reported but
#   NOT gated: fixture-share of a frozen corpus is a constant of the snapshot, and the ranking
#   lane's ceilings already gate ranker-side pollution.
#   UPDATE POLICY (read before touching snapshot.mdpack or its lock): the snapshot is refreshed ONLY in
#   a deliberate recalibration commit that (a) states why, (b) regenerates via
#   `python3 bench/recalleval/make_snapshot.py --freeze [COMMIT] --corpus docs`, (c) re-measures the
#   frozen baselines (two runs, byte-identical), and (d) resets the floors here — all FOUR in ONE
#   commit. Valid reasons: a label re-authoring that names a document the snapshot lacks (check #2's
#   zero-skip guard forces the refresh), or an owner-ruled representativeness refresh after a docs
#   restructure. A red floor is NEVER a reason to refresh: on a frozen corpus a red floor is a
#   ranker regression, full stop. Check #0's corpus_sha256 makes a quiet in-place edit or an
#   unrecorded refresh fail loudly before any floor is consulted.
#
# 2026-08-19 FROZEN RANKING CORPUS — the ranking lane joins the recall lane. Its half of the
# 2026-08-07 entry ("Ranking lane unchanged, live: its labels are code symbols and its floors carry
# wide margins") did not survive contact: the ranking lane has the IDENTICAL defect, one level down.
# It scored the live SOURCE tree, so every wave that adds load-bearing symbols to this repository
# displaces this lane's own gold — the ratchet the recall lane retired, re-expressed in code instead
# of prose. THREE INDEPENDENT MEASUREMENTS said so before this commit, none of them a floor argument:
#   1. The convergence-disclosure lane's residual (docs/EVALS.md §6 probe 4). A three-cell control:
#      base binary on the base tree 75.0% / MRR 0.694; base binary on the wave tree 71.9% / 0.660;
#      wave binary on the wave tree 71.9% / 0.660. The BASE binary scores the wave number — every
#      point of the −3.1pp is corpus. The displacers were named by inspection: on "pagerank power
#      iteration", ranks 2-5 and 9 of the wave tree are RankDisclosure/renderDisclosure
#      (src/prconverge.h), RankedGraph/rankGraphTeleport (src/graph.h) and PageRankRun — the wave's
#      own new symbols, doing exactly what they should.
#   2. The wave-2 adversarial verifier's follow-up F, arrived at independently and repeated in its
#      2026-08-19 addendum: "recalibrate the ranking lane by freezing its corpus (mechanism already
#      exists for the recall lane), not by lowering the floor a fourth time."
#   3. The subtoken merge window's 2×2 (2026-08-19). Ranking lenient r@5, one query = 3.125pp, n=32:
#      parser-65 and parser-66 binaries score 71.9% on the parent tree and 68.8% on the merged tree —
#      the TOKENIZER CONTRIBUTES EXACTLY ZERO, and the whole −3.1pp is one label flipping because the
#      round consolidated the body of its own gold (rw::subtokens, src/lexical.h, rank 3 → 9: the old
#      body carried the query's literal vocabulary inline, the new one delegates to forEachLexSubtoken).
#      A lane that reports "you refactored the symbol this query is about" as a ranking regression is
#      measuring the diff, not the ranker.
#   THE FOURTH FLOOR-LOWERING WAS AVAILABLE AND IS REFUSED. 70 has room for exactly one more flip;
#   spending the ratchet again would buy one round and re-price a bar that was never the problem.
#   WHAT IS FROZEN: bench/recalleval/snapshot.srcpack + srcsnapshot.lock — 1422 files @ 7a3194b, the
#   whole crawlable tree, not just src/. It has to be the whole tree because --for's universe is: BM25
#   corpus statistics, the call graph PageRank runs over, and the fixture/present path tiers are all
#   properties of every indexed file. Stored gzip-compressed (~32 MB of text, 6.7 MB packed) behind the
#   crawler-inert .srcpack extension, unpacked into its own temp root per run, exactly as the doc pack
#   is; the two corpora are pinned at their own commits by independent recalibration commits.
#   THE FREEZE MOVED NOTHING — this is the claim that makes the commit honest, and it is measured, not
#   argued. At 7a3194b the frozen root reproduces the live root EXACTLY: lenient r@5 71.9% (23/32),
#   lenient MRR 0.660, strict r@1/r@5 53.1/65.6, mrr_strict 0.598, pollution@5 0.0%, adversarial-class
#   pollution 0.0%, and all four CLASS rows (name 100.0 / concept 66.7 / task 42.9 / adversarial 80.0).
#   Stronger than the aggregates: all 32 PER-QUERY rank vectors are byte-identical between the live and
#   frozen roots (`--verbose | grep ^Q`, diff clean). No tolerance band is claimed because none is
#   needed. What the pack drops relative to the live root — third_party/ and docs/captures/ — the crawl
#   already prunes by name at BOTH roots (ingest.h kCrawlSkipDirs), which is why the delta is zero.
#   FLOORS AND LABELS ARE UNCHANGED BY THIS COMMIT. r@5 70, MRR 0.55, pollution 5%, adversarial 8% are
#   the same values as before the freeze, now measured against a fixed corpus, where they finally mean
#   what they say. labels_ranking.tsv is untouched — option 2 of the merge window's §7 (recalibrate the
#   label) was NOT taken, so nothing about the lane's gold has been re-decided.
#   ON THE MARGIN, STATED RATHER THAN LEFT FOR A READER TO NOTICE: r@5 70 against a 71.9% baseline is
#   0.6 of a query (one query = 3.125pp at n=32) — exactly the "floor within one query" shape the five
#   ratchet entries above condemn. It is condemned there and correct here, and the difference is the
#   corpus, not the number: against a LIVE corpus a 0.6-query margin makes the gate a tripwire for
#   documenting and for writing code, which is what those entries measured; against a FROZEN one the
#   only thing that can spend it is the ranker, so tripping on the first lost query is the gate doing
#   its job. Widening it was deliberately NOT done — a wider floor here would be a floor-lowering with
#   better manners, and this commit's whole claim is that it lowers nothing.
#   AND IT IS NOT TUNED TO ADMIT ANYTHING. The corpus is pinned at 7a3194b, which PREDATES the subtoken
#   change: the frozen rw::subtokens is its PRE-consolidation body, the one whose lexical evidence the
#   query was labelled against. That is what makes the lane an instrument for the pending merge rather
#   than a verdict on it — and it cuts both ways, since a genuine ranker regression in that merge now
#   has nowhere to hide behind corpus drift.
#   WHY THIS LANE STILL GATES ITS FROZEN pollution@5 WHILE THE RECALL LANE DOES NOT: on a frozen corpus
#   pollution@5 is a pure RANKER signal (fixture share can only move if the ranker moves it), and it is
#   §P4's own published number — the thing the tier down-weight exists to hold. The recall lane un-gated
#   its frozen pollution because it has no ranker-side fixture defense at all and its live probe is the
#   honest reporter. The ranking lens's LIVE anti-pollution property keeps its own tripwire: check #6a
#   asserts, at the live repo root, that the real implementation outranks every test//present/ row —
#   which is why no second live probe was added here.
#   UPDATE POLICY — identical discipline, own lock: refresh ONLY in a deliberate recalibration commit
#   that (a) states why, (b) regenerates via
#   `python3 bench/recalleval/make_snapshot.py --freeze [COMMIT] --corpus src`, (c) re-measures this
#   lane's frozen baselines (two runs, byte-identical), and (d) resets its floors here — all FOUR in
#   ONE commit. --corpus has no default for --freeze on purpose: a refresh must move only the corpus
#   whose floors the same commit re-measures. Valid reasons: a label re-authoring naming a symbol the
#   snapshot lacks (check #2's zero-skip guard forces it), or an owner-ruled representativeness refresh
#   after the source tree has moved far enough that the frozen corpus no longer resembles what the tool
#   ships. A RED FLOOR IS NEVER A REASON TO REFRESH — on a frozen corpus a red floor is a ranker
#   regression, full stop, and "the corpus moved" is no longer available as an explanation.
floor "$RL5" 71   && ok "recall lane lenient recall@5 ($RL5%) >= floor 71% (frozen-corpus baseline 76.2%)"  || no "recall lane lenient recall@5 ($RL5%) under floor 71% — ranker regression on the FROZEN corpus"
floor "$RMRR" 0.57 && ok "recall lane lenient MRR ($RMRR) >= floor 0.57 (frozen-corpus baseline 0.619)" || no "recall lane lenient MRR ($RMRR) under floor 0.57 — ranker regression on the FROZEN corpus"
LPOL="$( field "$LIV" pollution5 )"
ceil  "${LPOL:-999}" 16 && ok "LIVE-corpus pollution@5 ($LPOL%) <= ceiling 16% (the corpus-composition reporter; exported-tree baseline 10.0%)" || no "LIVE-corpus pollution@5 (${LPOL:-missing}%) over ceiling 16% — generated/fixture docs are retaking --recall on the live tree"
floor "$KL5" 70   && ok "ranking lane lenient recall@5 ($KL5%) >= floor 70% (frozen-corpus baseline 71.9%)"  || no "ranking lane lenient recall@5 ($KL5%) under floor 70% — ranker regression on the FROZEN corpus"
floor "$KMRR" 0.55 && ok "ranking lane lenient MRR ($KMRR) >= floor 0.55 (frozen-corpus baseline 0.660)"    || no "ranking lane lenient MRR ($KMRR) under floor 0.55 — ranker regression on the FROZEN corpus"
ceil  "$KPOL" 5    && ok "ranking lane pollution@5 ($KPOL%) <= ceiling 5% (frozen-corpus baseline 0.0%; post-§P4 0.0%)"    || no "ranking lane pollution@5 ($KPOL%) over ceiling 5% — fixtures/present are retaking --for"

# ── #5b: §P4's own number — the adversarial class (queries built to let fixtures/decks win) must stay
#    de-polluted. Ceiling 8% = one polluted top-5 slot across the class (5 queries × 5 slots → 1/25 = 4%);
#    two slots trips. Pre-§P4 baseline was 28.0%, post-§P4 0.0%. ─────────────────────────────────────────
APOL="$( grep -E $'^  CLASS\tranking\tadversarial\t' "$OUT" | sed -n 's/.*pollution5=\([0-9.]*\)%$/\1/p' )"
[ -n "$APOL" ] && ceil "$APOL" 8 \
    && ok "ranking adversarial-class pollution@5 ($APOL%) <= ceiling 8% (pre-§P4 28.0%, post-§P4 0.0%)" \
    || no "ranking adversarial-class pollution@5 (${APOL:-missing}) over ceiling 8% — the §P4 class is regressing"

# ── #6: §P4 direct XML assertions over the shipping binary at THIS repo root (the plan's cited repro +
#    the two interactions the tier down-weight must NOT break). Paths asserted here are pinned by the
#    label files, whose on-disk presence check #2 already enforces. ──────────────────────────────────────
CAND="$TMP/cand.xml"

# 6a — the plan's cited query: the real implementation must outrank every fixture/deck row (RED pre-§P4:
#      a test/chafix stub held rank 1). Rank of pageRankDouble strictly above the best test/ or present/ row.
"$BIN" . --for="pagerank power iteration" --format=candidates --top-k=10 >"$CAND" 2>/dev/null
PRRANK="$( tr '<' '\n' <"$CAND" | sed -n 's/^cand r="\([0-9]*\)" [^>]*n="pageRankDouble".*/\1/p' | head -1 )"
FIXRANK="$( tr '<' '\n' <"$CAND" | grep -E '^cand ' | grep -E 'p="\./(test|present)/' | sed -n 's/^cand r="\([0-9]*\)".*/\1/p' | sort -n | head -1 )"
if [ -n "$PRRANK" ] && { [ -z "$FIXRANK" ] || [ "$PRRANK" -lt "$FIXRANK" ]; }; then
    ok "cited query ranks pageRankDouble (r=$PRRANK) above any test/present row (best fixture r=${FIXRANK:-none in top-10})"
else
    no "cited query: pageRankDouble r=${PRRANK:-absent} vs best fixture/deck row r=${FIXRANK:-none} — §P4 repro is back"
fi

# 6b — mention anchor beats the tier penalty: a fixture file literally NAMED in the task still surfaces
#      in the top 5 (de-prioritized is not unanchorable).
"$BIN" . --for="fix the virtual dispatch in test/chafix/cha.cpp" --format=candidates --top-k=5 >"$CAND" 2>/dev/null
tr '<' '\n' <"$CAND" | grep -E '^cand ' | grep -q 'p="\./test/chafix/cha\.cpp"' \
    && ok "mention anchor survives the penalty: task naming test/chafix/cha.cpp surfaces it in the top 5" \
    || no "mention anchor lost to the tier penalty: test/chafix/cha.cpp absent from its own task's top 5"

# 6c — name-exact route beats the tier penalty: a fixture symbol queried by its EXACT name is still rank 1
#      (its competitors score 0 — shrinking the only hit must not bury it).
"$BIN" . --for="Robot" --format=candidates --top-k=1 >"$CAND" 2>/dev/null
tr '<' '\n' <"$CAND" | grep -E '^cand r="1" ' | grep 'n="Robot"' | grep -q 'p="\./test/chafix/cha\.cpp"' \
    && ok "name-exact survives the penalty: --for=Robot still lands the fixture class at rank 1" \
    || no "name-exact buried by the tier penalty: --for=Robot no longer lands test/chafix Robot at rank 1"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
