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
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CORPUS="$TMP/corpus"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "fornotesbudgetcheck: no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "fornotesbudgetcheck: python3 is required (JSON arms)"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "fornotesbudgetcheck: git is required (notes carry a sha/branch stamp)"; exit 2; }

echo "fornotesbudgetcheck: BIN=$BIN"

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

xmlEst(){ "$BIN" "$CORPUS" --for="$TASK" --token-budget="$1" 2>/dev/null | grep -o 'est_tokens="[0-9]*"' | head -1 | tr -dc '0-9'; }
xmlRows(){ "$BIN" "$CORPUS" --for="$TASK" --token-budget="$1" 2>/dev/null | grep -o '<d ' | wc -l | tr -d ' '; }
jsonEst(){ "$BIN" "$CORPUS" --for="$TASK" --token-budget="$1" --json 2>/dev/null \
           | python3 -c 'import sys,json; print(json.load(sys.stdin)["est_tokens"])' 2>/dev/null; }
jsonRows(){ "$BIN" "$CORPUS" --for="$TASK" --token-budget="$1" --json 2>/dev/null \
            | python3 -c 'import sys,json; d=json.load(sys.stdin); print(sum(len(f["symbols"]) for f in d["sigs"]))' 2>/dev/null; }

# ── arm 1: est_tokens must fit the ceiling the user asked for, in BOTH dialects ────────────────────
# (tight budget 950, re-anchored 2026-08-28 — see the CEILING MARGIN block above for the arithmetic)
for tb in 950 1600 3000; do
  xe="$( xmlEst "$tb" )"; je="$( jsonEst "$tb" )"
  if [ -z "$xe" ] || [ -z "$je" ]; then no "budget=$tb: could not read est_tokens from one of the dialects (xml='$xe' json='$je')"; continue; fi
  if [ "$xe" -le "$tb" ]; then ok "budget=$tb: XML est_tokens=$xe fits the ceiling"
  else no "budget=$tb: XML est_tokens=$xe blows the ceiling by $(( 100 * ( xe - tb ) / tb ))% — note bytes are not charged"; fi
  if [ "$je" -le "$tb" ]; then ok "budget=$tb: JSON est_tokens=$je fits the ceiling"
  else no "budget=$tb: JSON est_tokens=$je blows the ceiling — the reference side regressed"; fi
done

# ── arm 2: the two dialects select COMPARABLE row counts (they need not be equal) ──────────────────
# Before the fix the XML lens bought 2-2.4x the rows with the same budget, because notes were free.
for tb in 950 1600 3000; do
  xr="$( xmlRows "$tb" )"; jr="$( jsonRows "$tb" )"
  if [ -z "$jr" ] || [ "$jr" -eq 0 ]; then no "budget=$tb: JSON selected no rows — the comparison has no denominator"; continue; fi
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

# ── arm 4: L3 inertness — a tree with no notes is unaffected by any of this ────────────────────────
rm -f "$CORPUS/.ripwire_notes"
bare="$( "$BIN" "$CORPUS" --for="$TASK" --token-budget=800 2>/dev/null )"
case "$bare" in *"<note "*) no "a tree with no .ripwire_notes still emitted a <note> element";; *) ok "a tree with no notes emits none (L3 inertness)";; esac
bareEst="$( printf '%s' "$bare" | grep -o 'est_tokens="[0-9]*"' | head -1 | tr -dc '0-9' )"
if [ -n "$bareEst" ] && [ "$bareEst" -le 800 ]; then ok "no-notes tree also fits the ceiling (est_tokens=$bareEst)"
else no "no-notes tree reports est_tokens='$bareEst' against a budget of 800"; fi

# ── arm 5: still deterministic and well-formed after the accounting change ─────────────────────────
if [ "$( "$BIN" "$CORPUS" --for="$TASK" --token-budget=800 2>/dev/null )" = "$bare" ]; then ok "output is byte-identical run-to-run"
else no "output is not deterministic"; fi
if command -v xmllint >/dev/null 2>&1; then
  if printf '%s' "$OUT800" | xmllint --noout - 2>/dev/null; then ok "note-bearing XML is well-formed (G4)"; else no "note-bearing XML fails xmllint"; fi
else
  no "xmllint is required for the G4 arm (install libxml2) — the gate does not skip"
fi

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES PRESENT"; exit 1
