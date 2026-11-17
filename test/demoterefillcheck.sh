#!/usr/bin/env bash
# demoterefillcheck.sh — DEMOTE-ALL-DIALECTS (card B26) unit gate for rw::refillRowsForDemote (src/demoterefill.h), the soft target's
# refill walk: the bytes SIBLING-DEMOTE / DECL-TWIN free on the rendered <sigs> rows buy rows past the cut. The driver
# (test/demoterefillfix/demote_refill_test.cpp) runs it on a model answer of 100-byte rows with 10-byte pointers, 12 rows at the
# base budget. A real corpus cannot be relied on to keep producing a K4 refill, so the shape is pinned here.
#
# Arms (the second is RED on the walk before CodeRabbit 4543056274: it kept a 14-row block of 1400 B against 1250 B allotted):
#   (r)  premise: rows 11..14 always demotable: the walk refills past the base cut (rows > 12, counted: FAILS on 12) and the block
#        ships within what the rows were allotted.
#   (k)  K4: rows 11..12 stay whole once row 13 shows (it is their task-named seed). The refill that admits row 13 frees nothing,
#        so it does not ship: the walk renders back to the base budget (12 rows), and the block ships within its allotment.
#
# Usage: bash test/demoterefillcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
SRC="$ROOT/test/demoterefillfix/demote_refill_test.cpp"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

CXX="${CXX:-clang++}"
command -v "$CXX" >/dev/null 2>&1 || CXX=c++
command -v "$CXX" >/dev/null 2>&1 || CXX=g++
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
if ! "$CXX" "$CXXSTD" -I "$ROOT/src" "$SRC" -o "$TMP/t" 2>"$TMP/build.err"; then
    no "the driver did not build"; cat "$TMP/build.err"; echo "FAIL demoterefillcheck"; exit 1
fi
OUT="$( "$TMP/t" )"; rc=$?
printf '%s\n' "$OUT" | sed 's/^/  /'
[ "$rc" -eq 0 ] || no "the driver exited $rc"
field(){ printf '%s\n' "$OUT" | grep "^$1:" | grep -oE "$2=[0-9]+" | cut -d= -f2; }
for sc in refill k4; do
    for f in rows ships allotted; do
        [ -n "$( field "$sc" "$f" )" ] || no "($sc) no $f= in the driver's output"
    done
done
rr="$( field refill rows )"; rs="$( field refill ships )"; ra="$( field refill allotted )"
kr="$( field k4 rows )"; ks="$( field k4 ships )"; ka="$( field k4 allotted )"
if [ "${rr:-0}" -gt 12 ] && [ "${rs:-1}" -le "${ra:-0}" ]; then ok "(r) the freed bytes buy rows: $rr rows past the base 12, $rs B <= $ra B allotted"
else no "(r) refill: rows=${rr:-?} ships=${rs:-?} allotted=${ra:-?} (want rows > 12, ships <= allotted)"; fi
if [ "${kr:-0}" -eq 12 ] && [ "${ks:-1}" -le "${ka:-0}" ]; then ok "(k) K4: the refill that frees nothing does not ship: back to $kr rows, $ks B <= $ka B allotted"
else no "(k) K4: rows=${kr:-?} ships=${ks:-?} allotted=${ka:-?} (want rows = 12, ships <= allotted)"; fi

if [ "$fail" -eq 0 ]; then echo "PASS demoterefillcheck"; exit 0; fi
echo "FAIL demoterefillcheck"; exit 1
