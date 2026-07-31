#!/usr/bin/env bash
# fornotesbudgetcheck.sh — gate for W3-N2: the XML --for lens must CHARGE auto-surfaced note bytes to
# --token-budget, the way the JSON sibling already does.
#
# Usage:
#   test/fornotesbudgetcheck.sh                      # uses build/ctxpack
#   test/fornotesbudgetcheck.sh asan/ctxpack
#   CTXPACK_BIN=build_base/ctxpack test/fornotesbudgetcheck.sh   # red-first: the XML arms MUST fail here
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
# (notes are provenance-stamped) and its own .ctxpack_notes, neither of which belongs in the tree.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CORPUS="$TMP/corpus"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "fornotesbudgetcheck: no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
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
( cd "$CORPUS" && git init -q . && git add -A && git -c user.email=gate@example.invalid -c user.name=gate commit -qm corpus ) \
  || { echo "fornotesbudgetcheck: could not create the corpus git repo"; exit 2; }

NOTE="this routine is load-bearing for the widget dispatcher and must not be reordered without rechecking the stage table downstream"
for i in 0 1 2 3 4 5 6 7 8 9 10 11; do
  for j in 0 1 2 3 4 5; do
    "$BIN" "$CORPUS" --note-add="widgetRoutine${i}_${j}: $NOTE" >/dev/null 2>&1
  done
done
[ -s "$CORPUS/.ctxpack_notes" ] || { echo "fornotesbudgetcheck: --note-add wrote no notes — the corpus cannot exercise the contract"; exit 2; }

TASK="widget dispatcher pipeline stage"

xmlEst(){ "$BIN" "$CORPUS" --for="$TASK" --token-budget="$1" 2>/dev/null | grep -o 'est_tokens="[0-9]*"' | head -1 | tr -dc '0-9'; }
xmlRows(){ "$BIN" "$CORPUS" --for="$TASK" --token-budget="$1" 2>/dev/null | grep -o '<d ' | wc -l | tr -d ' '; }
jsonEst(){ "$BIN" "$CORPUS" --for="$TASK" --token-budget="$1" --json 2>/dev/null \
           | python3 -c 'import sys,json; print(json.load(sys.stdin)["est_tokens"])' 2>/dev/null; }
jsonRows(){ "$BIN" "$CORPUS" --for="$TASK" --token-budget="$1" --json 2>/dev/null \
            | python3 -c 'import sys,json; d=json.load(sys.stdin); print(sum(len(f["symbols"]) for f in d["sigs"]))' 2>/dev/null; }

# ── arm 1: est_tokens must fit the ceiling the user asked for, in BOTH dialects ────────────────────
for tb in 800 1500 3000; do
  xe="$( xmlEst "$tb" )"; je="$( jsonEst "$tb" )"
  if [ -z "$xe" ] || [ -z "$je" ]; then no "budget=$tb: could not read est_tokens from one of the dialects (xml='$xe' json='$je')"; continue; fi
  if [ "$xe" -le "$tb" ]; then ok "budget=$tb: XML est_tokens=$xe fits the ceiling"
  else no "budget=$tb: XML est_tokens=$xe blows the ceiling by $(( 100 * ( xe - tb ) / tb ))% — note bytes are not charged"; fi
  if [ "$je" -le "$tb" ]; then ok "budget=$tb: JSON est_tokens=$je fits the ceiling"
  else no "budget=$tb: JSON est_tokens=$je blows the ceiling — the reference side regressed"; fi
done

# ── arm 2: the two dialects select COMPARABLE row counts (they need not be equal) ──────────────────
# Before the fix the XML lens bought 2-2.4x the rows with the same budget, because notes were free.
for tb in 800 1500 3000; do
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
rm -f "$CORPUS/.ctxpack_notes"
bare="$( "$BIN" "$CORPUS" --for="$TASK" --token-budget=800 2>/dev/null )"
case "$bare" in *"<note "*) no "a tree with no .ctxpack_notes still emitted a <note> element";; *) ok "a tree with no notes emits none (L3 inertness)";; esac
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
