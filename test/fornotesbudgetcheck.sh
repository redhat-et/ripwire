#!/usr/bin/env bash
# fornotesbudgetcheck.sh — gate for W3-N2: the XML --for lens must CHARGE auto-surfaced note bytes to
# --token-budget, the way the JSON sibling already does.
#
# Usage:
#   test/fornotesbudgetcheck.sh                      # uses build/ripwire
#   test/fornotesbudgetcheck.sh asan/ripwire
#   RIPWIRE_BIN=build_base/ripwire test/fornotesbudgetcheck.sh   # red-first: the XML arms MUST fail here
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# DO NOT edit regression.sh — this is a standalone gate invoked from there.
#
# ── BY-DESIGN BREAK — forbudget-soft (rule 4); owner decisions 2026-10-14. READ THIS FIRST. ──────────────────────────────
# An explicit --token-budget=N on --for is now a SOFT TARGET, not a byte ceiling over the whole document: T = N x 2.36 x 0.90
# bytes (serialize.h kMinBytesPerToken x kBudgetHeadroom) is charged against the bytes INSIDE <sigs> only — the rows, each
# with its <note> children (the JSON twin: the emitted "sigs" array, jsonSigEntryCost's exact model, notes included). Rows
# are added in rank order while they fit T, the rank 1..4 floor always ships, the cut carries next=; the header and every
# disclosure are never charged, so est_tokens MAY exceed N and nothing is labelled over_ceiling= for it. The DEFAULT --for
# (no budget) stops when complete: the ranked head ships whole, rows past the 7.5 KB target disclosed as past_target=.
# The SUBJECT of this gate survives the move intact — W3-N2: note bytes are CHARGED to the budget like the rows they ride,
# never trimmed — only the thing they are charged against moved from the whole document to the <sigs> rows. So the arms
# that asserted the deleted contract ("est_tokens <= N in both dialects" at 1200/1640/3000; the 700..2000 sweep's
# "est_tokens <= N OR over_ceiling=1"; the no-notes tree's "est_tokens <= 900" / "over 900 and labelled") are REPLACED by
# the invariants that pin W3-N2 under the soft target, on the same fixture and the same rungs:
#   ST     the rows' bytes inside <sigs>, notes included, fit T — or only the rank 1..4 floor ships — and a cut is MAXIMAL
#          (the next row of the same dialect's no-budget answer would cross T; 160 B slack, as forsoftbudgetcheck's (ST)).
#          A note that were NOT charged would let a cut run past T by its note bytes: that is the W3-N2 leak, measured here.
#   NOTES  every served row carries its note — charged, never trimmed — and a notes tree serves NO MORE rows than the same
#          tree without notes at the same N (and strictly fewer somewhere: the charge is real, not vacuous).
#   NOLBL  no over_ceiling= on a budget_tokens answer (a soft target is never "over").
#   RP     rows(N) are a rank prefix of the no-budget answer's rows, and monotone in N (rows(N-10) a prefix of rows(N)).
#   NX     every cut names its continuation (<sigs next=> / "sigs_next").
#   CF     the compact and full legends serve the same rows.
#   DH     the no-budget answer on the note-heavy tree serves the whole ranked head, every row with its note, unlabelled.
# Unchanged and kept: notes are never trimmed (arm 3), the dialects agree on what a budget buys (arm 2), the stated budget
# is echoed as budget_tokens on every rung (sweep), est_tokens is always served, L3 inertness, determinism, G4. This gate
# never had a --max-tokens arm (that knob shapes the map, not --for). The CEILING MARGIN history below describes the RETIRED
# hard-ceiling regime; it is kept as the record of why the rungs sit where they do.
#
# What the audit found: `used +=` in packSignatures added the doc and the signature and nothing else,
# while appendNoteChildren streamed <note> children straight into the writer for free. On a note-heavy
# tree the XML lens therefore ran far past the ceiling its own header reports — measured est_tokens 1279
# against --token-budget=800 (+60%), 5478 against 3000 (+83%) — while --json, whose jsonSigEntryCost has
# charged `e.notes.size()` since §B1.3, stayed inside the same ceiling and selected HALF the rows. Two
# modes, one flag, two different meanings of "budget".
#
# The contract this pins (both directions, so neither the leak nor an over-correction can return):
#   • est_tokens <= --token-budget in BOTH dialects, at three budgets. est_tokens is the tool's OWN
#     arithmetic over its OWN emitted bytes, so this arm needs no external bytes-per-token guess.
#   • the two dialects now select COMPARABLE row counts (XML was 2-2.4x the JSON count at every budget).
#   • notes are CHARGED but never TRIMMED — a surviving row keeps its whole note, which is the half of
#     the old policy comment that was right and must not be lost to the fix.
#   • a tree with NO notes is unaffected (the L3 inertness contract), and output stays deterministic
#     and well-formed.
#
# The corpus is built here, in a temp dir this script creates and removes: it needs its own git repo
# (notes are provenance-stamped) and its own .ripwire_notes, neither of which belongs in the tree.
#
# ── CEILING MARGIN, RE-ANCHORED 2026-08-22 (T3 disclosure-gap fix), RE-MEASURED 2026-08-23 AT LANDING ──
# ── READ THIS BEFORE DEBUGGING A RED ──
# The tight XML arm ran at --token-budget=850 with **est_tokens=815: 35 tokens of headroom** (superseded
# by the 2026-08-28 re-anchor below).
#
#   · baseline binary at adb0831 (wave-2 close):    est_tokens=747 of 800 — 53 tokens of headroom
#   · wave-3 head (P5-4 recorded, not re-anchored): est_tokens=798 of 800 —  2 tokens of headroom
#   · disclosure-gap fix (the 800→850 re-anchor):   est_tokens=814 of 850 — 36 tokens of headroom
#   · at landing, on the merged trunk (below):      est_tokens=815 of 850 — 35 tokens of headroom
#
# Each move is ONE identified change. Wave 3's +51 was W3-S item 5's `root=` legend clause (+126 B on
# every --for, charged at kMinBytesPerToken). The disclosure lane's +16 is the T3 exhausted-ceiling
# disclosure: a `bundle=… bodies="0" reason="budget"` attribute (~40 B) now rides the <ctx> root on
# EVERY auto-mode run, including one whose signature bundle spent the whole allowance — the silent
# branch the 2026-08-22 Lane-AA transcript mine caught is gone (test/fordisclosurecheck.sh). The tight
# ceiling moved 800→850 in its own commit, immediately preceding that change, per the instruction the
# previous anchor left below: wave-3 spent the margin to 2 tokens, so ANY header addition had to
# re-anchor (at 850 the pre-change binary's 798 still passes, so the history is green at every step).
#
# The landing +1 (814→815) is the compact conceptual route, which this fixture's task now takes: the
# attribute it carries is ` bundle="compact" …` where the body walk's is ` bundle="auto" …`, four bytes
# wider, one token at the conservative rate. It was RE-DERIVED at the merged tree rather than carried
# over, because the compact round moved --for's bytes after the re-anchor was measured. **The 850
# anchor itself needed no change**: the flatness that justified it still holds exactly — est_tokens is
# 815 at every one of 830 / 850 / 870 / 900 (measured; no additional row fits anywhere in that band),
# so 850 still buys real headroom rather than a different selection. And 800 is now 15 tokens SHORT
# (est_tokens 815 > 800), which is the re-anchor earning its keep rather than an argument against it.
# The corpus is a generated temp fixture, not the live tree, so the number does NOT move with repo growth.
#
# ── RE-ANCHORED 2026-09-11 (0.6.1, the L1 lane): the TIGHT rung 950 → 1100. ──
# The instruction the 2026-09-05 block below left ("The next change that adds a byte to --for's floor at 950 must
# re-anchor that rung with its own arithmetic") is now due, and this is that arithmetic. The ceiling ladder's
# RUNG ZERO — the one that drops the confidence=/margin_pct=/budget_tokens= clause and the r=/tail clause to buy
# the header back under the allowance — used to do it in SILENCE: the attributes stayed on the root with nothing
# defining them and no word that a definition had been removed. It now splices a 181 B sentence naming exactly
# those attributes (verbs_for.h kForLegendDroppedNote). 181 B is 73 tokens at the conservative rate, against the
# TWO tokens of headroom the rung had left. The note is not shortened to fit the rung; the rung moves.
#
# MEASURED, both binaries, this corpus in a mktemp dir, --token-budget swept 950..3000:
#   · 950  post-fix: NOTHING the ladder can build fits the 950 × 2.36 × 1.15 = 2 578 B allowance, so it lands on
#     its last rung — the emitted document is 2 756 B, est_tokens=1102. An honest overshoot, labelled
#     over_ceiling="1", which is the rung earning its move rather than an argument against the disclosure.
#   · 1000 post-fix: 2 624 B fits the 2 714 B allowance, but est_tokens=1050 is 50 over the TOKEN ceiling (the
#     70 B of over_ceiling="1" and its legend clause are the difference between this row and the next).
#   · 1050 / 1100 / 1150 post-fix: est_tokens=1022 at all three, 2 554 B — the serving shape is FLAT across that
#     band (no additional row fits anywhere in it), so the rung buys headroom rather than a different selection.
# 1100 sits mid-plateau with 78 tokens of headroom, one step clear of the short edge (1000) and of the upper edge
# where the next row would land. The pre-fix binary reads est_tokens=949 at 1100, so the history is green at every
# step. The other two rungs did not move: 1640 reads 1620 and 3000 reads 2802 on BOTH binaries — rung zero never
# fires there, which is the whole reason only the tight rung moved.
# (Re-measured 2026-09-12 when the note's closing clause was corrected: it had pointed the reader at a help text
# that defines two of the four attributes it names. The replacement is 181 B against 182 B, so every number in
# this block moved by at most one byte — the figures above are the re-measured ones, not the originals.)
#
# ── MOVED BACK 2026-09-13 (lane for-widen, owner decision 22:55: coverage= present-only): 1700 → 1640. ───────────
# This fixture's answer is CONFIDENT (coverage would read 100 over a 12-file head), so under present-only it carries no
# coverage= and no clause and reads the base numbers again: 1640 → est_tokens=1620 (7 rows), 1100 → 1022, 3000 → 2802;
# 1700 now overshoots (1779, the 8-row state). The paragraph below records the one-day excursion for the next reader.
# ── RE-ANCHORED 2026-09-12 (lane for-widen, L-W): the MIDDLE rung 1640 → 1700. ──────────────────────────────
# The coverage= root fact and its legend clause (forpage.h kForCoverageLegend, ~300 B, byte-exempt like the confidence
# clause it extends) landed on every --for header. Measured on this fixture at the gate's own (mktemp) path length: the
# base build read est_tokens=1620 at 1640; this build's 7-row state reads 1780 there and over_ceiling="1" rides along;
# its 8-row state fits from 1680 to 1770 at est_tokens=1556 (1660 and 1780 both read over). 1700 sits inside that
# window with 144 tokens of headroom. The other two rungs stay: 1100 still reads 1032 (4 rows) and 3000 reads 2934
# (16 rows, from 2802) inside its rung. The header's own rule: the signal is expected, the response is a deliberate
# re-anchor with the number recorded.
# ── RE-ANCHORED 2026-09-05 (terminality round A, lane R, P7 rank order): the MIDDLE rung 1600 → 1640. ──
# The lens <sigs> is FLAT now: rows in rank order, each carrying p="src/modN.py" (16 B), no <f p=> wrapper (24 B
# each). At this fixture's 7-row state that is 7 × 16 − 2 × 24 = +64 B = +26 tokens at the conservative rate.
# MEASURED (both binaries, this corpus in a mktemp dir, --token-budget swept 1500..1700): the pre-P7 binary's 7-row
# state reads est_tokens=1580 at 1580..1639 and admits row 8 at 1640 (1733); the P7 binary's 7-row state reads
# 1606 — it fits at 1610..1660 and admits row 8 at 1665 (1764). At the OLD rung 1600 the P7 binary prints the
# SAME 7 rows, 1606 > 1600, and (verbs_for.h F2) labels the root over_ceiling="1" — the legend clause and label
# add 70 B, so the document reads 1634: an honest overshoot, not a silent one, and the reason the rung moves
# rather than the rows. 1640 sits mid-window with 34 tokens of headroom (the 33–43 band every earlier anchor
# left) and 25 tokens under the 8th-row edge. The row SET changed too, deliberately: the old file-major drop
# kept ranks 1–4 plus three source-order rows of the best file; the new rank-major drop keeps ranks 1–7 (rows 5–7
# carry doc excerpts, which is why the same row COUNT costs more bytes). The tight rung 950 did not move but its
# floor grew by the same arithmetic — 4 rows × 16 B − 1 wrapper = +40 B: 932 → 948 of 950, TWO tokens of headroom.
# The next change that adds a byte to --for's floor at 950 must re-anchor that rung with its own arithmetic.
# 3000: 2840 → 2788 (16 rows vs 17 — the rank-major drop again).
# ── RE-ANCHORED 2026-09-04 (capture-audit wave-2 merge): the MIDDLE rung 1550 → 1600. ──
# Three lanes each added to --for's <ctx> root, each fit the 1550 rung ALONE, and their sum does not. The gate
# itself read est_tokens=1563 at 1550 on the merged tree (this fixture; --token-budget=1550 is at the compact
# floor here: bundle="compact" bodies="0" reason="budget", nothing left for the ladder to trim). Attributed
# binary by binary on one copy of this fixture (same corpus, same root path, so only the binary varies;
# absolute numbers there are 23 higher than the gate's because the copy's root= path is longer):
#   e3b52d3 (wave-1 head) 1531 → V1 alone 1547 (+16: N1's est_tokens="N" on the root plus its 41 B "prices this
#   bundle" clause, exact-counted in the fixpoint) → L10b alone 1530 (−1: the route= leading " [" trim) → L2
#   alone 1531 (0) → L6 alone 1571 (+40: H9's budget_tokens="N" on the root plus the "budget_tokens=/max_tokens=:
#   the token ceiling this bundle was shaped against" clause, CHARGED — which is why L6 alone still fit: it
#   spent the 43 tokens of headroom the wave-1 close left) → merged 1586 (+55 = 16 − 1 + 40, additive).
# At 1600 the merged binary reads 1563 (37 tokens of headroom, the 33–43 band every earlier anchor left), FLAT
# from 1550 through 1600; 950 (938 merged) and 3000 (2846 merged) did not move. **The history is NOT green at
# every step this time, and the reason is a pre-existing defect, not the re-anchor**: the pre-merge binaries
# (e3b52d3, V1, L10b, L2) are flat at 1507–1524 through 1550 and then JUMP at 1560 to 1632/1648 — one more row
# fits the ladder's CHARGED arithmetic, and the exempt root width (at=, confidence=) then carries est_tokens
# past the explicit ceiling with nothing on the root saying so (bundle="compact" bodies="0", no over_ceiling=).
# That is the wave-1 close's found-not-fixed ("an exempt root attribute on a body-less bundle has nothing to
# absorb it") measured on a rung, and the merged binary has the same edge one row later: 1563 through 1600,
# 1687 at 1620 (over a 1620 ceiling by 67, unlabelled). So this rung has a HARD UPPER EDGE at ~1610 on the
# merged binary — a future re-anchor UP will land in the overshoot band and read as a note-charging red when
# it is the exemption; the fix that removes the edge is charging the exempt width in the explicit regime
# (verbs_for.h confidenceExemptBytes), which is a ladder-behaviour change across every --for byte gate and
# was not taken at merge time. Not taken either: trimming a lane's clause (the gate's own instruction below) —
# L7's compaction lane is where --for's always-on header bytes get bought back, and this is the rung it
# should re-anchor DOWN.
#
# ── RE-ANCHORED 2026-09-04 (capture-audit wave-1 close): the MIDDLE rung 1500 → 1550. ──
# ONE identified change: lane L9's M10 at="<sha>[+dirty]" on --for's <ctx> root plus its at= clause in the
# root= trailer comment (kForRootRelAtLegendShort), which rides the confidence-disclosure's sig-trim
# EXEMPTION (verbs_for.h confidenceExemptBytes) — so the sigs never pay for it and est_tokens rises by its
# whole width. Measured on this fixture at the old 1500 rung: ec5e3c3 (pre-L9) est_tokens=1481 (19 of
# headroom), L9 alone 1499 (1 of headroom), the wave-1 merge 1507 — the last +8 is L4's `<sigs shown=S
# total=T capped="1">` marker (truncvocabcheck arm F), charged, widening the sigs open tag. At 1550 every one
# of those three binaries passes (1481/1499/1507 ≤ 1550; 43 of headroom on the merged one); the tight 950
# rung (890 of 950, 60 of headroom) and 3000 (2767) did not need to move. The rows arm is unchanged (XML 7
# vs JSON 8 at the rung). Found, not fixed, for the owner: an exempt root attribute on a body-less bundle
# (compact route, or --signatures-only) has nothing downstream to absorb it, so est_tokens CAN exceed an
# explicit --token-budget by the exempt width — the "kept by the BODY side" promise in verbs_for.h does not
# reach that shape. Charging at= like root= is (Wave 3: +126 B, charged) is the alternative this gate would
# then hold; it is a ladder-behaviour change across every --for byte gate and was not taken at merge time.
#
# ── RE-ANCHORED 2026-08-28 (paper-shape lane): 850 → 950. ──
# The tight XML arm now runs at --token-budget=950 with **est_tokens=917: 33 tokens of headroom.**
# ONE identified change, per this gate's own instruction below: --for's <ctx> root now always carries the
# ranking-confidence facts confidence=/margin_pct= plus their terse legend clause (~250 B on every --for,
# derived from the SAME adaptiveCut gap statistic the adaptive flag cuts at — arXiv 2607.24882's
# abstention axis; gate test/forcompresscheck.sh arms 8-10). The re-anchor is its own commit immediately
# preceding that change: at 950 the pre-change binary's 815 still passes, so the history is green at
# every step — the same discipline as the 800→850 move recorded above. Charged, not exempted, in the
# explicit-budget regime (the exemption is default-regime only, main.cpp confidenceExemptBytes), and the
# note is additionally a ladder rung zero there — neither could rescue 850 because this fixture's floor
# is notes + first-entry-whole, neither of which may trim.
#
# CONSEQUENCE FOR THE NEXT LANE: **any** addition to --for's legend or header, of any size, turns this arm
# red — and it will read as YOUR regression when it is a ratchet. If you added a clause to --for and this
# went red, that is the expected signal, not a bug in your change; the correct response is a DELIBERATE
# re-anchor of the tight ceiling in its own commit with the new number recorded here (the gate's own
# philosophy elsewhere: a recalibration is a commit, never a mid-lane bar move). Do not widen the bar
# quietly, and do not "fix" it by trimming the legend without deciding that the trim is what you want.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
export RIPWIRE_TESTLIB="$ROOT/test/lib"   # softbudget.py: the soft-target readers, shared helpers (CHECKLIST 32)
unset RIPWIRE_NO_HEAD_RR                  # lane hrr: the head reorder is ON here unless the RP twin sets it
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "fornotesbudgetcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CORPUS="$TMP/corpus"
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "fornotesbudgetcheck: no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "fornotesbudgetcheck: python3 is required (JSON arms)"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "fornotesbudgetcheck: git is required (notes carry a sha/branch stamp)"; exit 2; }


# ── the sandbox corpus: 72 small symbols across 12 files, one long note on every one ───────────────
mkdir -p "$CORPUS/src" || { echo "fornotesbudgetcheck: cannot create corpus under $TMP"; exit 2; }
python3 - "$CORPUS" <<'PY_EOF'
import os, sys
root = sys.argv[1]
for i in range( 12 ):
    with open( os.path.join( root, "src", "mod%d.py" % i ), "w" ) as f:
        for j in range( 6 ):
            f.write( "def widgetRoutine%d_%d( alpha, beta ):\n" % ( i, j ) )
            f.write( '    """Route the widget pipeline stage %d.%d through the dispatcher."""\n' % ( i, j ) )
            f.write( "    return alpha + beta\n\n\n" )
PY_EOF
# `-b main` is load-bearing, not tidiness. Notes are provenance-stamped with the branch they were taken on,
# so the BRANCH NAME is charged against the token budget once per emitted note — and a bare `git init` takes
# its name from the ambient `init.defaultBranch`, which a developer sets and a fresh CI runner does not.
# Unset, git still names it `master`: two bytes more than `main`, per note, which against the two tokens of
# headroom recorded above is the entire margin. Measured on one binary and one corpus, varying only this:
# `main` → est_tokens 798 / 2528, `master` → 801 / 2543. That is the whole reason this gate was green on
# every developer machine and red on macos-14 CI, and it is why the fixture pins the name instead of
# inheriting one.
( cd "$CORPUS" && git init -q -b main . && git add -A && git -c user.email=gate@example.invalid -c user.name=gate commit -qm corpus ) \
  || { echo "fornotesbudgetcheck: could not create the corpus git repo"; exit 2; }

NOTE="this routine is load-bearing for the widget dispatcher and must not be reordered without rechecking the stage table downstream"
for i in 0 1 2 3 4 5 6 7 8 9 10 11; do
  for j in 0 1 2 3 4 5; do
    "$BIN" "$CORPUS" --note-add="widgetRoutine${i}_${j}: $NOTE" >/dev/null 2>&1
  done
done
[ -s "$CORPUS/.ripwire_notes" ] || { echo "fornotesbudgetcheck: --note-add wrote no notes — the corpus cannot exercise the contract"; exit 2; }

TASK="widget dispatcher pipeline stage"

# ── forbudget-soft (rule 4): the soft-target reader every replaced arm below uses ─────────────────────────────────────────
# soft FILE N ROWSOUT [REF [PREV]] prints ONE line, "OK|BAD rows= total= charged= T= est= over= echo= next= notes= fits= maximal= upper= rp=":
#   rows / total   the served <sigs> rows / the ranked head (<sigs total=> | "sigs_total")
#   charged        what the soft target is charged against. XML: the bytes inside <sigs> — every <d> WITH its <note> children
#                  — plus the zero cx=/ccx=/in= the lean spelling elides (serialize.h entryCost charges them). JSON: the
#                  emitted "sigs" array, notes included (jsonSigEntryCost is that array's exact byte model).
#   T              N x 2.36 x 0.90 (kMinBytesPerToken x kBudgetHeadroom)
#   est / over / echo   est_tokens ("-" when absent) / over_ceiling= on the ROOT / budget_tokens == N on the root
#   next           a cut (rows < total) names its continuation (<sigs next=> | "sigs_next"); 1 when nothing was cut
#   notes          served rows that carry a note
#   fits           charged <= T, or only the rank 1..4 floor is served — and the floor is never short (rows >= min(4,total))
#   upper          with REF, FIX2 C1: the maximality twin, rows past the floor stop where T less the other sections and the
#                  tail reserve runs out (test/lib/softbudget.py upper_bound; a tail-reserve-zero binary is RED here)
#   maximal        with REF (the SAME dialect's no-budget answer): a cut stops only where REF's next row would cross T
#                  (160 B slack, as forsoftbudgetcheck's (ST)) — a binary that stops early at a hard ceiling is not ST
#   rp             RP: the rows are a non-empty rank prefix of REF's rows, and the rows file PREV (when named: the next
#                  narrower rung's ROWSOUT) is a prefix of these rows — monotone in N. A named PREV that is missing is a 0.
# (One python3 per answer, the fields read with bash's own regex: this machine class pays ~0.1 s per process spawn, and the
# sweep below reads 393 answers — the reader does in-process what a pipe of head/wc/sed would spawn for.)
# The verdict is OK when est is numeric and fits, maximal, upper and next all hold. ROWSOUT gets the rows, p:l:n in rank (r=) order.
# exit 3 = the answer has no <sigs> block / "sigs" array: a missing premise, FAILed by the caller, never skipped.
cat > "$TMP/soft.py" <<'PY'
import json, re, sys
def read( path ):
    s = open( path, encoding='utf-8', errors='replace' ).read()
    rows = []
    if s.lstrip().startswith( '{' ):
        try: d = json.loads( s )
        except Exception: return None
        i = s.find( '"sigs":[' )
        if i < 0 or not isinstance( d.get( 'sigs' ), list ): return None
        _, end = json.JSONDecoder().raw_decode( s, i + 7 )
        charged = len( s[ i + 7:end ].encode() )
        for e in d[ 'sigs' ]:
            r = e.get( 'r' )
            cost = len( json.dumps( e, separators=( ',', ':' ), ensure_ascii=False ).encode() ) + 1
            rows.append( ( r if isinstance( r, int ) else 10**9, "%s:%s:%s" % ( e.get( 'p' ), e.get( 'l' ), e.get( 'n' ) ), cost,
                           1 if e.get( 'notes' ) else 0 ) )
        total = d.get( 'sigs_total', len( rows ) )
        nxt = bool( d.get( 'sigs_next' ) )
        over = d.get( 'over_ceiling' ) is True
        est = d.get( 'est_tokens' ); est = str( est ) if isinstance( est, int ) else '-'
        bt = d.get( 'budget_tokens' )
    else:
        root = re.search( r'<ctx\b[^>]*>', s )
        m = re.search( r'<sigs\b([^>]*)>(.*?)</sigs>', s, re.S )
        if not root or not m: return None
        inner = m.group( 2 ); charged = len( inner.encode() )
        for x in re.finditer( r'<d ([^>]*)>.*?</d>|<d ([^>]*)/>', inner, re.S ):
            a = x.group( 1 ) or x.group( 2 )
            g = lambda k: ( re.search( r'\b' + k + r'="([^"]*)"', a ) or [ None, "?" ] )[ 1 ]
            elided = sum( n for k, n in ( ( 'cx', 7 ), ( 'ccx', 8 ), ( 'in', 7 ) ) if not re.search( r'\b' + k + r'="', a ) )
            charged += elided
            r = g( 'r' )
            rows.append( ( int( r ) if r.isdigit() else 10**9, g( 'p' ) + ":" + g( 'l' ) + ":" + g( 'n' ), len( x.group( 0 ).encode() ) + elided,
                           1 if '<note ' in x.group( 0 ) else 0 ) )
        t = re.search( r'\btotal="(\d+)"', m.group( 1 ) ); total = int( t.group( 1 ) ) if t else len( rows )
        nxt = re.search( r'\bnext="[^"]+"', m.group( 1 ) ) is not None
        rt = root.group( 0 )
        over = re.search( r'\bover_ceiling="', rt ) is not None
        e = re.search( r'\best_tokens="(\d+)"', rt ); est = e.group( 1 ) if e else '-'
        b = re.search( r'\bbudget_tokens="(\d+)"', rt ); bt = int( b.group( 1 ) ) if b else None
    rows.sort()
    return dict( rows=rows, charged=charged, total=total, next=nxt, over=over, est=est, bt=bt )
def sections_u( s ):
    # round C (forbudget-soft, owner decision 2026-10-14: RESERVE SECTIONS FIRST; rule 4): the trailing sections are served first
    # and the rows past the cut fill what they leave of T, so maximality reads T less their bytes (U): XML, all after </sigs> but
    # </ctx> plus the <hdr> rows, less the --detail bodies (a root without bundle=); JSON, the "tail" object
    if s.lstrip().startswith( "{" ):
        try: return len( json.dumps( json.loads( s ).get( "tail", {} ), separators=( ",", ":" ), ensure_ascii=False ).encode() )
        except ValueError: return 0
    u = ( len( s.split( "</sigs>", 1 )[ 1 ].encode() ) - len( "</ctx>" ) ) if "</sigs>" in s else 0
    u += sum( len( h.encode() ) for h in re.findall( r"<hdr [^>]*/>", s.split( "<sigs", 1 )[ 0 ] ) )
    root = re.search( r"<ctx [^>]*>", s )
    if root and ' bundle="' not in root.group( 0 ):
        bm = re.search( r"<bodies\b.*?</bodies>", s, re.S )
        u -= len( bm.group( 0 ).encode() ) if bm else 0
    return u
a = read( sys.argv[ 1 ] )
if a is None: sys.exit( 3 )
N = int( sys.argv[ 2 ] ); X = int( N * 2.36 * 0.90 )
# the tail size: test/lib/softbudget.py, shared by the five soft-target readers (the FIX1 R1 tail floor)
import os as _os, sys as _sys; _sys.path.insert( 0, _os.environ[ "RIPWIRE_TESTLIB" ] ); from softbudget import tail_size, strip_appended
# K-LEGEND: the <syms> block / held stub rides on its own allowance, outside est_tokens: never reserved from T
U = sections_u( strip_appended( open( sys.argv[ 1 ], encoding='utf-8', errors='replace' ).read() ) )
if len( sys.argv ) > 4:
    _at = open( sys.argv[ 1 ], encoding='utf-8', errors='replace' ).read(); _rt = open( sys.argv[ 4 ], encoding='utf-8', errors='replace' ).read()
    U += max( 0, tail_size( _rt ) - tail_size( _at ) )
open( sys.argv[ 3 ], 'w' ).write( "".join( x[ 1 ] + "\n" for x in a[ 'rows' ] ) )
k = len( a[ 'rows' ] )
fits = ( a[ 'charged' ] <= X or k <= 4 ) and k >= min( 4, a[ 'total' ] )
cut = k < a[ 'total' ]
nxt = a[ 'next' ] or not cut
maximal = upper = True
if len( sys.argv ) > 4:
    ref = read( sys.argv[ 4 ] )
    if ref is None: sys.exit( 3 )
    if cut and k < len( ref[ 'rows' ] ):
        maximal = a[ 'charged' ] + ref[ 'rows' ][ k ][ 2 ] > X - U - 160
    # FIX2 C1 (rule 4): the upper-bound twin of maximality (test/lib/softbudget.py upper_bound): rows past the floor stop where T less
    # the other sections and the tail reserve runs out; RED on a binary that ignores the tail reserve (rows over-served)
    from softbudget import upper_bound
    upper = upper_bound( _at, _rt, X, k, a[ 'total' ], U )[ 0 ]
mine = [ x[ 1 ] for x in a[ 'rows' ] ]
rp = len( sys.argv ) > 4 and k > 0 and mine == [ x[ 1 ] for x in ref[ 'rows' ] ][ :k ]
if rp and len( sys.argv ) > 5 and sys.argv[ 5 ]:
    try: prev = [ x for x in open( sys.argv[ 5 ] ).read().split( "\n" ) if x ]
    except OSError: prev = None
    rp = prev is not None and len( prev ) > 0 and prev == mine[ :len( prev ) ]
ok = a[ 'est' ] != '-' and fits and maximal and upper and nxt
print( "%s rows=%d total=%d charged=%d T=%d est=%s over=%d echo=%d next=%d notes=%d fits=%d maximal=%d upper=%d rp=%d"
       % ( "OK" if ok else "BAD", k, a[ 'total' ], a[ 'charged' ], X, a[ 'est' ], int( a[ 'over' ] ), int( a[ 'bt' ] == N ),
           int( nxt ), sum( x[ 3 ] for x in a[ 'rows' ] ), int( fits ), int( maximal ), int( upper ), int( rp ) ) )
PY
soft(){ python3 "$TMP/soft.py" "$@"; }
# head round-robin (lane hrr, train 31; PROCESS rule 4, orchestrator ruling FIX1 §4(a)): the no-budget answer reorders its first 8
# rows (files_first=) while a budgeted one keeps score order, so RP's "a rank prefix of the no-budget rows" holds only in score
# order. RP runs UNCHANGED on the RIPWIRE_NO_HEAD_RR=1 twin of every sweep call (against the twin's no-budget reference), and
# (RPh) asserts with the reorder on: the rows are the no-budget answer's first rows as a SET (score ranks 1..K, read off the
# twin: softbudget.py set_prefix) and rows(N-10) are an order prefix of rows(N) (monotone; both budgeted, both score order).
cat > "$TMP/rph.py" <<'PY'
import os, sys
sys.path.insert( 0, os.environ[ "RIPWIRE_TESTLIB" ] ); from softbudget import set_prefix
rd = lambda p: [ x for x in open( p ).read().split( "\n" ) if x ] if p and os.path.exists( p ) else None
cur, on, off = rd( sys.argv[ 1 ] ), rd( sys.argv[ 2 ] ), rd( sys.argv[ 3 ] )
prv = rd( sys.argv[ 4 ] ) if len( sys.argv ) > 4 and sys.argv[ 4 ] else []
ok = cur is not None and on is not None and off is not None and prv is not None and set_prefix( cur, on, off ) and cur[ :len( prv ) ] == prv
sys.exit( 0 if ok else 1 )
PY
field(){ local re=" $2=([^ ]*)"; [[ " $1 " =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}"; }   # field LINE KEY: one key= of a soft line
isnum(){ case "${1:-}" in ''|*[!0-9]*) return 1;; esac; return 0; }

# The no-budget answers, one per dialect the arms below read: the REF each cut's maximality and rank prefix are measured
# against, and the DH arm's subject.
"$BIN" "$CORPUS" --for="$TASK"                  > "$TMP/def.xml"     2>/dev/null
"$BIN" "$CORPUS" --for="$TASK" --legend=compact > "$TMP/def.compact" 2>/dev/null
"$BIN" "$CORPUS" --for="$TASK" --json           > "$TMP/def.json"    2>/dev/null
RIPWIRE_NO_HEAD_RR=1 "$BIN" "$CORPUS" --for="$TASK"                  > "$TMP/def_so.xml"     2>/dev/null   # lane hrr: the RP twin's references
RIPWIRE_NO_HEAD_RR=1 "$BIN" "$CORPUS" --for="$TASK" --legend=compact > "$TMP/def_so.compact" 2>/dev/null
RIPWIRE_NO_HEAD_RR=1 "$BIN" "$CORPUS" --for="$TASK" --json           > "$TMP/def_so.json"    2>/dev/null
for dialect in xml compact json; do
  soft "$TMP/def_so.$dialect" 0 "$TMP/def_so_$dialect.rows" >/dev/null || no "the RIPWIRE_NO_HEAD_RR=1 no-budget answer ($dialect) has no <sigs> block — the RP twin lacks its reference"
  dl="$( soft "$TMP/def.$dialect" 0 "$TMP/def_$dialect.rows" )" || { no "no-budget answer ($dialect) has no <sigs> block — every soft arm below lacks its reference"; continue; }
  dr="$( field "$dl" rows )"
  isnum "$dr" && [ "$dr" -ge 5 ] || no "no-budget answer ($dialect) serves '$dr' rows — the reference cannot measure a cut past the floor"
done

# ── arm DH (NEW, forbudget-soft (rule 4)): the default answer on a note-heavy tree serves the WHOLE head, every note intact ──
# The default --for stops when complete: kForPayloadBudgetBytes (7,500 B) is a TARGET whose row drop only runs past the
# 32,000 B runaway guard. This tree's 40-row head with a ~130 B note on every row is ~13 KB of <sigs>: notes are charged
# against the target (the rows past it are DISCLOSED as past_target=) and never cost a row, never get trimmed, never
# label the answer over_ceiling=. HEAD d099ec21: 40 of 40 rows, 40 notes, past_target=20, both dialects. RED on the base
# binary (d4325a8c): 20 of 40 rows, no past_target= (the 7.5 KB ceiling's row drop).
for dialect in xml json; do
  dl="$( soft "$TMP/def.$dialect" 0 /dev/null )" || { no "(DH) default ($dialect): no <sigs> block"; continue; }
  dr="$( field "$dl" rows )"; dt="$( field "$dl" total )"; dn="$( field "$dl" notes )"; dov="$( field "$dl" over )"
  case "$dialect" in json) pt="$( python3 -c 'import sys,json; print(json.load(open(sys.argv[1])).get("sigs_past_target",""))' "$TMP/def.json" 2>/dev/null )" ;;
                     *)    pt="$( grep -o '<sigs [^>]*>' "$TMP/def.xml" | head -1 | sed -n 's/.*past_target="\([0-9]*\)".*/\1/p' )" ;; esac
  if isnum "$dr" && isnum "$dt" && isnum "$dn" && [ "$dr" -eq "$dt" ] && [ "$dn" -eq "$dr" ] && [ "$dov" = 0 ] && isnum "$pt" && [ "$pt" -ge 1 ]; then
    ok "(DH) default ($dialect): the whole head ships ($dr of $dt rows, $dn notes), $pt row(s) disclosed past_target, no over_ceiling"
  else
    no "(DH) default ($dialect): rows=$dr total=$dt notes=$dn over=$dov past_target='$pt' — the default must ship the whole head with every note, past the target disclosed, unlabelled"
  fi
done

# ── arm 1: notes are CHARGED against the budget, in BOTH dialects ─────────────────────────────────
# REPLACED — forbudget-soft (rule 4). Was: "est_tokens <= --token-budget" in XML and JSON at 1200/1640/3000 (the whole
# document fit the ceiling). Under the soft target est_tokens may exceed N by the never-charged header (HEAD d099ec21: XML
# 1564 / 1940 / 3085, JSON 1232 at 1200), so that bar asserts the deleted contract. What W3-N2 means now, asserted here at
# the same three rungs in both dialects: ST (the rows — each WITH its note — fit T = N x 2.36 x 0.90 or are the floor, and
# the cut is maximal), NOTES (every served row carries its note), NOLBL (no over_ceiling=), est_tokens still served.
# MEASURED (HEAD d099ec21, this fixture in a scratch dir), rows / charged bytes of T: 1200 -> 7 / 2338 of 2548 (JSON 7 /
# 2371), 1640 -> 10 / 3322 of 3483 (JSON 10 / 3388), 3000 -> 19 / 6280 of 6372 (JSON 18 / 6106); a note on every row.
# RED on the base binary (d4325a8c): 1200 -> XML 4 rows (1355 B), JSON 6 (2033 B); 1640 -> XML 7; 3000 -> 16 / 17 — every
# one a cut a whole row short of T (not maximal: the hard ceiling reserved the header the soft target no longer charges).
# (tight budget 1100, re-anchored 2026-09-11 — see the CEILING MARGIN block above for the arithmetic)
# RE-ANCHORED 2026-10-10 (train 26c): the tight rung 1100 -> 1200. lego-charge charges <lego>/<compose> at their served size
# and #362's <tail next=> rides the bundle, so at 1100 this corpus's XML answer is the 4-row floor with its next= unpaid
# (est_tokens 1213, over_ceiling="1" + the unpaid clause: disclosed, not silent — the knob-honesty contract, not the leak
# this arm pins). Swept on the merged binary: 1150 / 1200 serve 4 rows at est_tokens=1121 (JSON 1098), 1250..1350 five rows
# at 1246; 1200 sits mid-plateau with 79 tokens of headroom, one step clear of each edge. 1640 and 3000 unchanged.
for tb in 1200 1640 3000 900; do
  "$BIN" "$CORPUS" --for="$TASK" --token-budget="$tb"        > "$TMP/n_$tb.xml"  2>/dev/null
  "$BIN" "$CORPUS" --for="$TASK" --token-budget="$tb" --json > "$TMP/n_$tb.json" 2>/dev/null
  [ "$tb" = 900 ] && continue   # 900 is read by arm 4's notes-vs-no-notes comparison (and by its CF twin), not asserted here
  for dialect in xml json; do
    sl="$( soft "$TMP/n_$tb.$dialect" "$tb" "$TMP/n_${tb}_$dialect.rows" "$TMP/def.$dialect" )" \
      || { no "budget=$tb ($dialect): no <sigs> block in the answer or its reference — the charge cannot be measured"; continue; }
    sr="$( field "$sl" rows )"; sn="$( field "$sl" notes )"
    case "$sl" in OK*) ok "(ST) budget=$tb ($dialect): the rows WITH their notes fit the target — $sl" ;;
                  *)   no "(ST) budget=$tb ($dialect): $sl — note bytes ride the rows and must be charged with them: fit T (or the floor), and stop only where the next row would cross it" ;; esac
    if isnum "$sr" && isnum "$sn" && [ "$sr" -ge 1 ] && [ "$sn" -eq "$sr" ]; then ok "(NOTES) budget=$tb ($dialect): every served row carries its note ($sn of $sr) — charged, not dropped to make room"
    else no "(NOTES) budget=$tb ($dialect): $sn note(s) on $sr row(s) — a note was dropped instead of charged"; fi
    case "$sl" in *" over=0 "*) ok "(NOLBL) budget=$tb ($dialect): no over_ceiling= on a soft target" ;;
                  *)            no "(NOLBL) budget=$tb ($dialect): over_ceiling= on a budget_tokens answer — a soft target is never 'over' ($sl)" ;; esac
  done
done

# ── arm 2: the two dialects select COMPARABLE row counts (they need not be equal) ──────────────────
# Before the fix the XML lens bought 2-2.4x the rows with the same budget, because notes were free.
# (forbudget-soft: the rows are read off arm 1's answers — the same argv, so one run each instead of two.)
for tb in 1200 1640 3000; do
  xr="$( grep -c . "$TMP/n_${tb}_xml.rows" 2>/dev/null )"; jr="$( grep -c . "$TMP/n_${tb}_json.rows" 2>/dev/null )"
  if ! isnum "$xr" || ! isnum "$jr" || [ "$jr" -eq 0 ]; then no "budget=$tb: JSON selected no rows (xml='$xr' json='$jr') — the comparison has no denominator"; continue; fi
  if [ "$xr" -le $(( jr * 13 / 10 + 1 )) ] && [ "$xr" -ge $(( jr * 7 / 10 )) ]; then
    ok "budget=$tb: XML $xr rows vs JSON $jr rows — the two dialects agree on what fits"
  else
    no "budget=$tb: XML $xr rows vs JSON $jr rows — the dialects disagree on what the same budget buys"
  fi
done

# ── arm 3: notes are CHARGED, never TRIMMED ───────────────────────────────────────────────────────
# Every surviving <d> row that has a note must still carry the WHOLE note text; the ladder shrinks docs
# and signatures to make room, it never truncates user-attached memory.
OUT800="$( "$BIN" "$CORPUS" --for="$TASK" --token-budget=800 2>/dev/null )"
noteCount="$( printf '%s' "$OUT800" | grep -o '<note ' | wc -l | tr -d ' ' )"
if [ "$noteCount" -ge 1 ]; then ok "notes still surface under a tight budget ($noteCount kept — charged, not sacrificed first)"
else no "no note survived a tight budget — the fix trimmed notes instead of charging them"; fi
fullText="$( printf '%s' "$OUT800" | grep -c "stage table downstream" )"
if [ "$fullText" -ge 1 ]; then ok "a surviving note carries its FULL text (no note-level truncation)"
else no "a surviving note lost its tail — notes must be charged, never trimmed"; fi

# ── arm 6: every rung of the band, every dialect: notes charged against a SOFT target — swept, not sampled ──
# REPLACED — forbudget-soft (rule 4). Was, per rung and dialect: "est_tokens <= --token-budget OR over_ceiling=1 on the
# root" (HEAD d099ec21: 322 of 393 runs over and unlabelled — by design: est_tokens may exceed N, and a soft target is never
# labelled over). The per-rung invariant now, over the SAME band (700..2000), the SAME step (10) and the SAME three dialects
# (393 runs): ST (the rows, notes included, fit T or are the floor; a cut is maximal against that dialect's no-budget answer;
# est_tokens served; the cut names its next=) + NOLBL (no over_ceiling=) + RP (rows a rank prefix of the no-budget rows, and
# rows(N-10) a prefix of rows(N): monotone) + CF (the default and --legend=compact XML dialects serve the same rows). The
# budget_tokens ECHO half of the arm is unchanged. The history below records the retired disjunction and why the band
# starts at 700; the band, the step and the dialects are kept as they were (the density is the arm's value, CHECKLIST 14).
# MEASURED: HEAD d099ec21 green on all 393 runs (every rung a cut; the 40-row head is never complete below 2000). RED on base
# (d4325a8c): 304 runs not maximal (the hard ceiling's header reserve), 87 labelled over_ceiling= (first: 700, xml); RP, CF
# and the echo are green on both.
# PLACED HERE, before arm 4, deliberately: this arm needs the NOTE-BEARING corpus (notes are the exempt-
# adjacent bytes that make the ladder's rungs tight enough to overshoot at all), and arm 4 deletes
# .ripwire_notes to test inertness. Moving it below arm 4 would make it green for the wrong reason.
#
# WHAT IT PINS, and why a sweep rather than one rung. --for's ceiling ladder chooses a rung on its CHARGED
# arithmetic, but a set of root bytes is EXEMPT from the sig-trim charge by design (verbs_for.h
# confidenceExemptBytes: confidence=/margin_pct=, at=, the adaptive note, the auto/compact legend, the tail
# legend — each exempt because a disclosure's contract is disclosure ONLY, and charging it against the ranked
# head would drop a <d> row to pay for a label). Those exempt bytes RIDE OVER the ceiling: whenever the
# ladder admits one more row, est_tokens can land past the budget the caller stated. That is a real,
# reproducible, per-rung behaviour of this fixture, not a corner case — in the 900..2000 band it happens on
# roughly half the rungs (the arm prints the count).
#
# The RULE this pins is the one METHODOLOGY §9 #2 and #4 decide between: a ceiling bounds the TAIL, never
# the HEAD, so the answer is NOT to trim the head row down to the byte — it is that an overshoot is never
# SILENT. `over_ceiling="1"` on the root, in the same unit as budget_tokens= and est_tokens=, on EVERY rung
# that exceeds the stated budget. Absent means inside it. So the assertion is a disjunction, per rung:
#
#     est_tokens <= --token-budget   OR   over_ceiling="1" on the root
#
# and it holds in all THREE emitting dialects (XML full legend, XML --legend=compact, --json), because a
# budget promise that means one thing in one dialect and another in the next is the two-meanings-of-budget
# defect this whole gate was written for. Stated together with it, per rung and per dialect: the stated
# ceiling is ECHOED on the root (budget_tokens). A price a caller cannot compare against the ceiling it
# named is the same silence one step earlier — it is what makes the disjunction above checkable at all.
#
# ── BAND RE-ANCHORED 2026-09-05 (terminality round A, lane V2, verify-wave1 finding R1): 900 → 700. ──
# The band's LOWER edge sat above the only place the --json dialect's silent overshoot is observable on this
# fixture, so the arm swept that third dialect and could not see it. Two units, not one:
#   XML   labels on   est_tokens > budget_tokens                                  (verbs_for.h F2)
#   JSON  labelled on bundle_bytes > ceilingAllowanceBytes = N x 2.36 x 1.15 = 2.714 N bytes
# and est_tokens prices at bytes / 2.50, so every document in 2.50 N < bytes <= 2.714 N priced OVER the
# stated ceiling and said nothing. That silent band is 8.6% wide and a document only enters it while it is
# SATURATING the ladder; this fixture's JSON bundle saturates at est_tokens=765 (its ranked set is exhausted
# at ~17 rows, which is why it reads 765 flat from 710 upward and never comes near a 900+ ceiling again).
# MEASURED on 4b722433, this fixture, 660..920 step 10 x 3 dialects: SIX silent rungs, all --json, all in
# 710..760 (est_tokens=765, 5..55 over, no over_ceiling), and ZERO in the old 900..2000 band. The band
# therefore starts at 700 — one rung below the first observable one — and 131 rungs x 3 dialects = 393 runs
# is the cost paid. Widening DOWN rather than adding a fourth dialect is deliberate: the missing coverage was
# never a missing dialect, it was the assumption that one band's rungs exercise every dialect's saturation
# point. A change that moves this fixture's JSON floor must re-derive the lower edge the same way — sweep,
# then set it one rung below the first silent rung — never lift it back to a round number.
#
# RED, MEASURED. On the pre-fix binary (77004e5c, the commit before 02b4ff57 "over_ceiling= is a property of
# the document, not of a rung") over_ceiling= was set from forOverCeiling ALONE — the ladder's LAST rung —
# so a bundle that overshot by a lot was labelled and one that overshot by a little was not. That binary
# fails this arm at the FIRST rung of the band it overshoots on: budget 1150, est_tokens=1266 (116 over,
# 10.1%), no label; and again at 1260, 1380, 1530, 1680, 1820, 1970 (XML full), and at the same rungs under
# --legend=compact. This arm is the regression lock on that rule, swept rather than sampled, because the
# rung a single sample happens to sit on is exactly what made the defect survive four earlier re-anchors of
# the middle rung above: 1550 and 1600 are both inside a FLAT stretch, and the edge is at ~1610.
sweepRungs=0; sweepEchoFail=0; sweepEchoFirst=""
stFail=0; stFirst=""; lblFail=0; lblFirst=""; rpFail=0; rpFirst=""; rphFail=0; rphFirst=""; cfFail=0; cfFirst=""; sweepCut=0; upFail=0; upFirst=""
tb=700
while [ "$tb" -le 2000 ]; do
  sweepRungs=$(( sweepRungs + 1 ))
  for dialect in xml compact json; do
    case "$dialect" in
      xml)     "$BIN" "$CORPUS" --for="$TASK" --token-budget="$tb"                  > "$TMP/sw.$dialect" 2>/dev/null ;;
      compact) "$BIN" "$CORPUS" --for="$TASK" --token-budget="$tb" --legend=compact > "$TMP/sw.$dialect" 2>/dev/null ;;
      json)    "$BIN" "$CORPUS" --for="$TASK" --token-budget="$tb" --json           > "$TMP/sw.$dialect" 2>/dev/null ;;
    esac
    cur="$TMP/sw_$(( sweepRungs % 2 ))_$dialect.rows"; prv="$TMP/sw_$(( ( sweepRungs + 1 ) % 2 ))_$dialect.rows"
    [ "$tb" -eq 700 ] && prv=""
    # RP's RIPWIRE_NO_HEAD_RR=1 twin (lane hrr): the same call and the same soft reader, against the twin's no-budget reference
    case "$dialect" in
      xml)     RIPWIRE_NO_HEAD_RR=1 "$BIN" "$CORPUS" --for="$TASK" --token-budget="$tb"                  > "$TMP/swt.$dialect" 2>/dev/null ;;
      compact) RIPWIRE_NO_HEAD_RR=1 "$BIN" "$CORPUS" --for="$TASK" --token-budget="$tb" --legend=compact > "$TMP/swt.$dialect" 2>/dev/null ;;
      json)    RIPWIRE_NO_HEAD_RR=1 "$BIN" "$CORPUS" --for="$TASK" --token-budget="$tb" --json           > "$TMP/swt.$dialect" 2>/dev/null ;;
    esac
    curt="$TMP/swt_$(( sweepRungs % 2 ))_$dialect.rows"; prvt="$TMP/swt_$(( ( sweepRungs + 1 ) % 2 ))_$dialect.rows"
    [ "$tb" -eq 700 ] && prvt=""
    slt="$( soft "$TMP/swt.$dialect" "$tb" "$curt" "$TMP/def_so.$dialect" "$prvt" )"
    case "$slt" in *" rp=1"*) ;; *)
      rpFail=$(( rpFail + 1 ))
      [ -z "$rpFirst" ] && rpFirst="budget=$tb ($dialect) [RIPWIRE_NO_HEAD_RR=1 twin]: the rows are not a rank prefix of the no-budget rows, or rows(N=$(( tb - 10 ))) are not a prefix of them — $slt" ;; esac
    if ! sl="$( soft "$TMP/sw.$dialect" "$tb" "$cur" "$TMP/def.$dialect" "$prv" )"; then
      no "sweep budget=$tb ($dialect): no <sigs> block in the answer or its reference — the price and the rows a budget shapes must always be served"
      stFail=$(( stFail + 1 )); continue
    fi
    case "$sl" in *" echo=1 "*) ;; *)
      sweepEchoFail=$(( sweepEchoFail + 1 ))
      [ -z "$sweepEchoFirst" ] && sweepEchoFirst="budget=$tb ($dialect)" ;; esac
    case "$sl" in OK*) ;; *)
      stFail=$(( stFail + 1 ))
      [ -z "$stFirst" ] && stFirst="budget=$tb ($dialect) $sl" ;; esac
    case "$sl" in *" upper=1 "*) ;; *)
      upFail=$(( upFail + 1 ))
      [ -z "$upFirst" ] && upFirst="budget=$tb ($dialect) $sl" ;; esac
    case "$sl" in *" over=0 "*) ;; *)
      lblFail=$(( lblFail + 1 ))
      [ -z "$lblFirst" ] && lblFirst="budget=$tb ($dialect) $sl" ;; esac
    if ! python3 "$TMP/rph.py" "$cur" "$TMP/def_$dialect.rows" "$TMP/def_so_$dialect.rows" "$prv"; then
      rphFail=$(( rphFail + 1 ))
      [ -z "$rphFirst" ] && rphFirst="budget=$tb ($dialect): the rows are not a SET prefix of the no-budget rows, or rows(N=$(( tb - 10 ))) are not an order prefix of them — $sl"
    fi
    [ "$( field "$sl" rows )" != "$( field "$sl" total )" ] && sweepCut=$(( sweepCut + 1 ))
  done
  if ! cmp -s "$TMP/sw_$(( sweepRungs % 2 ))_xml.rows" "$TMP/sw_$(( sweepRungs % 2 ))_compact.rows"; then
    cfFail=$(( cfFail + 1 ))
    [ -z "$cfFirst" ] && cfFirst="budget=$tb: the default and --legend=compact rows differ"
  fi
  tb=$(( tb + 10 ))
done
runs=$(( sweepRungs * 3 ))
if [ "$stFail" -eq 0 ]; then
  ok "(ST) sweep 700..2000 step 10 x 3 dialects ($runs runs): the rows WITH their notes fit T = N x 2.36 x 0.90 (or are the floor), every cut maximal and naming next= ($sweepCut cut)"
else
  no "(ST) sweep 700..2000 step 10 x 3 dialects: $stFail run(s) broke stop-at-target — first: $stFirst"
fi
# (UP) FIX2 C1 (rule 4): the upper-bound twin of maximality, counted on its own: a binary that ignores the tail reserve serves
# rows past T less the sections and that reserve, and both fits (rows <= T) and the relaxed maximality stay green on it.
if [ "$upFail" -eq 0 ]; then ok "(UP) sweep 700..2000 step 10 x 3 dialects ($runs runs): no cut past the floor serves rows into the tail reserve"
else no "(UP) sweep 700..2000 step 10 x 3 dialects: $upFail run(s) served rows past T less the sections and the tail reserve — first: $upFirst"; fi
if [ "$lblFail" -eq 0 ]; then ok "(NOLBL) sweep 700..2000 step 10 x 3 dialects ($runs runs): no over_ceiling= on any soft target"
else no "(NOLBL) sweep 700..2000 step 10 x 3 dialects: $lblFail run(s) labelled a soft target over_ceiling= — first: $lblFirst"; fi
if [ "$rpFail" -eq 0 ]; then ok "(RP) [RIPWIRE_NO_HEAD_RR=1 twin] sweep 700..2000 step 10 x 3 dialects ($runs runs): rows are a rank prefix of the no-budget rows, monotone in N"
else no "(RP) [RIPWIRE_NO_HEAD_RR=1 twin] sweep 700..2000 step 10 x 3 dialects: $rpFail run(s) broke the rank prefix — first: $rpFirst"; fi
if [ "$rphFail" -eq 0 ]; then ok "(RPh) head round-robin on, sweep 700..2000 step 10 x 3 dialects ($runs runs): rows are a SET prefix of the no-budget rows (score ranks 1..K), monotone in N"
else no "(RPh) head round-robin on, sweep 700..2000 step 10 x 3 dialects: $rphFail run(s) broke the set prefix — first: $rphFirst"; fi
if [ "$cfFail" -eq 0 ]; then ok "(CF) sweep 700..2000 step 10: the default and --legend=compact dialects serve the same rows on all $sweepRungs rungs"
else no "(CF) sweep 700..2000 step 10: $cfFail rung(s) where the legend changed the rows — first: $cfFirst"; fi
if [ "$sweepEchoFail" -eq 0 ]; then
  ok "sweep 700..2000 step 10 x 3 dialects: every rung ECHOES the ceiling it was shaped against (budget_tokens on the root)"
else
  no "sweep 700..2000 step 10 x 3 dialects: $sweepEchoFail run(s) never named the stated ceiling — first: $sweepEchoFirst"
fi

# ── arm 4: L3 inertness — a tree with no notes is unaffected by any of this ────────────────────────
rm -f "$CORPUS/.ripwire_notes"
# RE-ANCHORED 2026-10-10 (train 26c): 800 -> 900 for the no-notes arms below (same cause as arm 1's rung: at 800 the merged
# binary serves the 4-row floor with its unpaid next=, est_tokens 988 default / 951 full, over and labelled; from 850 both
# postures fit — 808 / 817 — and 900 holds 865 in the full legend with margin). The notes corpus's 800 runs above are unchanged.
bare="$( "$BIN" "$CORPUS" --for="$TASK" --token-budget=900 2>/dev/null )"
case "$bare" in *"<note "*) no "a tree with no .ripwire_notes still emitted a <note> element";; *) ok "a tree with no notes emits none (L3 inertness)";; esac
# L1 (2026-09-19) — the retired hard-ceiling reading of this arm: the full legend fit 900, the default (compact) answer
# carried more rows and was over 900, which it had to SAY (over_ceiling="1").
# REPLACED — forbudget-soft (rule 4). Was: "--legend=full est_tokens <= 900" and "default est_tokens <= 900, or over and
# labelled over_ceiling=1" (HEAD d099ec21: 1736 / 1304, unlabelled — by design). Now, on the no-notes tree at 900, both
# postures: ST (the rows fit T, maximal against the no-budget answer, next= on the cut) + NOLBL; and CF — the two legends
# serve the SAME rows (the retired ladder let the compact dialect's shorter clauses buy it more rows than the full legend).
# Then the W3-N2 twin this tree exists for: at every rung arm 1 measured (and 900), in both dialects, the notes tree served
# NO MORE rows than this tree without notes — and strictly fewer on at least one, so the charge is real, not vacuous.
# MEASURED (HEAD d099ec21): no-notes 900 -> 13 rows in both legends (1786 B of T 1911); notes vs no-notes rows: 900 5/13,
# 1200 7/18 (JSON 7/17), 1640 10/25 (10/24), 3000 19/40 (18/40). RED on base (d4325a8c): 7 rows default vs 6 full (CF), each a
# cut short of T (ST). The NOTES twins are green on both binaries — W3-N2 held before the soft target and holds after it.
"$BIN" "$CORPUS" --for="$TASK" --token-budget=900 --legend=full > "$TMP/b_900.full" 2>/dev/null
"$BIN" "$CORPUS" --for="$TASK"                                  > "$TMP/b_def.xml"  2>/dev/null
"$BIN" "$CORPUS" --for="$TASK" --json                           > "$TMP/b_def.json" 2>/dev/null
printf '%s' "$bare" > "$TMP/b_900.xml"
for posture in xml full; do
  if sl="$( soft "$TMP/b_900.$posture" 900 "$TMP/b_900_$posture.rows" "$TMP/b_def.xml" )"; then
    case "$sl" in OK*) ok "(ST) no-notes tree, budget=900 ($posture legend): the rows fit the target — $sl" ;;
                  *)   no "(ST) no-notes tree, budget=900 ($posture legend): $sl" ;; esac
    case "$sl" in *" over=0 "*) ok "(NOLBL) no-notes tree, budget=900 ($posture legend): no over_ceiling= on a soft target" ;;
                  *)            no "(NOLBL) no-notes tree, budget=900 ($posture legend): over_ceiling= on a soft target ($sl)" ;; esac
  else
    no "no-notes tree, budget=900 ($posture legend): no <sigs> block in the answer or the no-budget reference"
  fi
done
if [ -s "$TMP/b_900_xml.rows" ] && cmp -s "$TMP/b_900_xml.rows" "$TMP/b_900_full.rows"; then ok "(CF) no-notes tree, budget=900: the default and full legends serve the same $( grep -c . "$TMP/b_900_xml.rows" ) rows"
else no "(CF) no-notes tree, budget=900: default rows ($( grep -c . "$TMP/b_900_xml.rows" 2>/dev/null )) != full-legend rows ($( grep -c . "$TMP/b_900_full.rows" 2>/dev/null )) — the legend bought rows"; fi
fewer=0
for tb in 900 1200 1640 3000; do
  for dialect in xml json; do
    if [ ! -s "$TMP/b_$tb.$dialect" ]; then
      case "$dialect" in json) "$BIN" "$CORPUS" --for="$TASK" --token-budget="$tb" --json > "$TMP/b_$tb.$dialect" 2>/dev/null ;;
                         *)    "$BIN" "$CORPUS" --for="$TASK" --token-budget="$tb"        > "$TMP/b_$tb.$dialect" 2>/dev/null ;; esac
    fi
    nl="$( soft "$TMP/n_$tb.$dialect" "$tb" /dev/null )"; bl="$( soft "$TMP/b_$tb.$dialect" "$tb" /dev/null )"
    nr="$( field "$nl" rows )"; br="$( field "$bl" rows )"; nn="$( field "$nl" notes )"
    if ! isnum "$nr" || ! isnum "$br" || ! isnum "$nn" || [ "$nn" -lt 1 ]; then
      no "(NOTES) budget=$tb ($dialect): could not read both row counts with notes on the notes tree (notes tree '$nr' rows / '$nn' notes, no-notes tree '$br')"; continue
    fi
    if [ "$nr" -le "$br" ]; then ok "(NOTES) budget=$tb ($dialect): the notes tree serves $nr rows, the same tree without notes $br — notes are charged like the rows they ride"
    else no "(NOTES) budget=$tb ($dialect): the notes tree serves $nr rows, MORE than the same tree without notes ($br) — note bytes are not charged"; fi
    [ "$nr" -lt "$br" ] && fewer=$(( fewer + 1 ))
  done
done
if [ "$fewer" -ge 1 ]; then ok "(NOTES) the notes tree served strictly fewer rows on $fewer of 8 rung/dialect pairs — the charge is real"
else no "(NOTES) the notes tree never served fewer rows than the no-notes tree on any of 8 rung/dialect pairs — notes cost nothing (W3-N2)"; fi

# ── arm 5: still deterministic and well-formed after the accounting change ─────────────────────────
if [ "$( "$BIN" "$CORPUS" --for="$TASK" --token-budget=900 2>/dev/null )" = "$bare" ]; then ok "output is byte-identical run-to-run"
else no "output is not deterministic"; fi
if command -v xmllint >/dev/null 2>&1; then
  if printf '%s' "$OUT800" | xmllint --noout - 2>/dev/null; then ok "note-bearing XML is well-formed (G4)"; else no "note-bearing XML fails xmllint"; fi
else
  no "xmllint is required for the G4 arm (install libxml2) — the gate does not skip"
fi

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES PRESENT"; exit 1
