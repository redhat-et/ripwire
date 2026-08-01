#!/usr/bin/env bash
# grepseamcheck.sh — gate for: --grep/--regex paging
# must be a pure WINDOW over one fully-collected, fully-sorted hit list.
#
# THE TWO BUGS THIS PINS (both live-reproduced against the pre-fix binary):
#
#   §A0  signed-int overflow → a confident FALSE ZERO. `cap = max(histCap, offset + limit)` and then
#        `budgetCount = cap * 4`, both int: at --limit=536870912 the product overflowed NEGATIVE, the
#        collection loop collected nothing, and the release binary printed
#            hits="0" shown="0" capped="0" total="0" has_more="0" hits_capped="0"   at exit 0
#        — indistinguishable, on every channel, from "this pattern is not in your repo". (The ASan build
#        aborted at src/search.h:798 on the same command, which is how it was found.)
#
#   §A1  page seams DROPPED and DUPLICATED rows. The collection budget scaled with the page window, so
#        collection stopped mid-tree in fileId order at a DIFFERENT point per page, and the §P11.1
#        tier-then-path sort then ran over a different set each time: every page was a window into a
#        differently-ranked list. A --limit=100 walk over a 1173-hit pattern never served 59 rows and
#        served 59 others twice; the visible tell is `total=` GROWING as the offset advances.
#
# The fix is collect → sort → window: grepCollect() runs at a FIXED ceiling that nothing the caller passes
# can move, and --limit/--offset only slice the sorted result. So the invariants below are all forms of one
# statement: the row LIST is a property of the corpus and the pattern alone.
#
# Asserts (each one FAILS against the pre-fix binary):
#   (1) §A0 overflow boundary: hits= at --limit=536870912 == hits= at --limit=536870911
#   (2) §A1 the collected total does not depend on the window: unpaged hits= == a huge --limit's hits=
#   (3) §A1 a full page walk (follow next_offset until has_more="0") reproduces the unpaged row set
#       EXACTLY — no row dropped, no row served twice
#   (4) §A1 total=/hits=/files= are IDENTICAL on every page of that walk
#   (5) the same on the live repo, asserted as equality between runs (never as a row count, so this gate
#       is not coupled to this repo's contents)
#   (6) §A10.2 the paging VALUE refusals name the flag AND give an example, at exit 1
#
# The corpus is a generated sandbox with >400 hits spread across all three §P11.1 path tiers (400 was the
# pre-fix collection floor, so a corpus under it cannot show the bug), so the gate measures the tool and
# not this repo's current contents.
#
# Usage:
#   bash test/grepseamcheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=build_base/ripwire bash test/grepseamcheck.sh    # expect FAIL (red-first evidence)
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

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
echo "grepseamcheck: BIN=$BIN"

# ── the sandbox: 950 SEAMTOKENPAGING hits over 19 files in all three §P11.1 tiers ─────────────────────
# The DOC files come first in crawl (fileId) order and carry 500 of the hits, so the pre-fix 400-hit
# collection floor is exhausted by documentation before a single source file is reached: page 0 was served
# entirely out of `d00.md`/`d01.md` while the true first 100 rows are `src/s_a.cpp`/`src/s_b.cpp`. That is
# the finding's exact damage shape — the dropped rows are source-tier and the doc rows double-serve — and
# it is why the layout is deliberately doc-heavy rather than balanced.
SB="$TMP/seamsandbox"
mkdir -p "$SB/src" "$SB/test"
mkfile(){                                   # $1 = path, $2 = hit lines, $3 = printf template
    : >"$1"
    i=1
    while [ "$i" -le "$2" ]; do printf "$3" "$i" >>"$1"; i=$(( i + 1 )); done
}
for n in 0 1 2 3 4 5 6 7 8 9; do mkfile "$SB/d0$n.md"      50 'The design calls SEAMTOKENPAGING at step %03d.\n'; done
for n in a b c d e f;         do mkfile "$SB/src/s_$n.cpp" 50 'void seamFn%03d() { SEAMTOKENPAGING(); }\n';        done
for n in a b c;               do mkfile "$SB/test/t_$n.cpp" 50 'void seamTest%03d() { SEAMTOKENPAGING(); }\n';     done

run(){ "$BIN" "$SB" --no-cache --grep=SEAMTOKENPAGING "$@" 2>/dev/null; }
hdr(){ grep -o '<grep [^>]*>' | head -1; }
attr(){ sed -n "s/.* $1=\"\([^\"]*\)\".*/\1/p" | head -1; }

# ── (1) §A0 — the overflow boundary ──────────────────────────────────────────────────────────────────
H_LO="$( run --limit=536870911 | hdr | attr hits )"
H_HI="$( run --limit=536870912 | hdr | attr hits )"
{ [ -n "$H_LO" ] && [ "$H_LO" = "$H_HI" ]; } \
    && ok "(1) §A0 --limit=536870912 hits=$H_HI == --limit=536870911 hits=$H_LO (no int overflow)" \
    || no "(1) §A0 overflow: --limit=536870911 → hits=\"$H_LO\" but --limit=536870912 → hits=\"$H_HI\" (false zero)"

H_OFF="$( run --offset=536870912 --limit=1 | hdr | attr hits )"
[ "$H_OFF" = "$H_LO" ] \
    && ok "(1b) §A0 --offset=536870912 --limit=1 still reports hits=$H_OFF (offset does not move the budget)" \
    || no "(1b) §A0 --offset=536870912 --limit=1 → hits=\"$H_OFF\", expected \"$H_LO\""

# ── (2) §A1 — the collected total is window-independent ──────────────────────────────────────────────
H_PLAIN="$( run          | hdr | attr hits )"
H_BIG="$(   run --limit=1000000 | hdr | attr hits )"
{ [ -n "$H_PLAIN" ] && [ "$H_PLAIN" = "$H_BIG" ]; } \
    && ok "(2) §A1 unpaged hits=$H_PLAIN == --limit=1000000 hits=$H_BIG (--limit never widens collection)" \
    || no "(2) §A1 hits= moves with the window: unpaged=\"$H_PLAIN\" vs --limit=1000000=\"$H_BIG\""

[ "${H_PLAIN:-0}" -gt 400 ] 2>/dev/null \
    && ok "(2b) sandbox has $H_PLAIN hits — above the 400-row pre-fix collection floor (the bug is reachable)" \
    || no "(2b) sandbox collected only ${H_PLAIN:-0} hits; a corpus under 400 cannot exercise the seam bug"

# ── (3)+(4) §A1 — a full page walk reproduces the unpaged row set, with a stable total= ───────────────
run --limit=1000000 | tr '<' '\n' | sed -n 's/^hit \(p="[^"]*" in="[^"]*"\).*/\1/p' >"$TMP/reference.rows"

: >"$TMP/walk.rows"
: >"$TMP/walk.totals"
off=0
page=0
while [ "$page" -lt 200 ]; do
    run --limit=100 --offset="$off" >"$TMP/page.xml"
    H="$( hdr <"$TMP/page.xml" )"
    printf '%s|%s|%s\n' "$( printf '%s' "$H" | attr total )" "$( printf '%s' "$H" | attr hits )" "$( printf '%s' "$H" | attr files )" >>"$TMP/walk.totals"
    tr '<' '\n' <"$TMP/page.xml" | sed -n 's/^hit \(p="[^"]*" in="[^"]*"\).*/\1/p' >>"$TMP/walk.rows"
    [ "$( printf '%s' "$H" | attr has_more )" = "1" ] || break
    off="$( printf '%s' "$H" | attr next_offset )"
    page=$(( page + 1 ))
done

sort "$TMP/reference.rows" >"$TMP/reference.sorted"
sort "$TMP/walk.rows"      >"$TMP/walk.sorted"
DUPS="$( uniq -d <"$TMP/walk.sorted" | wc -l | tr -d ' ' )"
MISSING="$( comm -23 "$TMP/reference.sorted" "$TMP/walk.sorted" | wc -l | tr -d ' ' )"
EXTRA="$(   comm -13 "$TMP/reference.sorted" "$TMP/walk.sorted" | wc -l | tr -d ' ' )"

{ [ "$MISSING" = 0 ] && [ "$EXTRA" = 0 ] && [ "$DUPS" = 0 ]; } \
    && ok "(3) §A1 the --limit=100 walk serves every unpaged row exactly once ($( wc -l <"$TMP/walk.rows" | tr -d ' ' ) rows over $(( page + 1 )) pages)" \
    || { no "(3) §A1 seam broken: $MISSING row(s) never served, $EXTRA unexpected, $DUPS duplicated"
         comm -23 "$TMP/reference.sorted" "$TMP/walk.sorted" | head -3
         uniq -d <"$TMP/walk.sorted" | head -3; }

[ "$( sort -u <"$TMP/walk.totals" | wc -l | tr -d ' ' )" = 1 ] \
    && ok "(4) §A1 total=/hits=/files= identical on every page ($( head -1 "$TMP/walk.totals" ))" \
    || { no "(4) §A1 the report's own totals MOVE while paging — the tell of a re-collecting scan"
         sort -u <"$TMP/walk.totals" | head -4; }

# ── (5) the live repo, asserted only as equality between runs (never a row count) ─────────────────────
liveHits(){ "$BIN" "$ROOT" --grep=budget "$@" 2>/dev/null | hdr | attr hits; }
L_PLAIN="$( liveHits )"
L_LO="$(    liveHits --limit=536870911 )"
L_HI="$(    liveHits --limit=536870912 )"
{ [ -n "$L_PLAIN" ] && [ "$L_PLAIN" = "$L_LO" ] && [ "$L_LO" = "$L_HI" ]; } \
    && ok "(5) live repo --grep=budget: unpaged == 536870911 == 536870912 (all hits=$L_PLAIN)" \
    || no "(5) live repo --grep=budget disagrees across windows: unpaged=\"$L_PLAIN\" lo=\"$L_LO\" hi=\"$L_HI\""

# ── (5b) the ordering the legend now claims (§A10.3) is actually stated ───────────────────────────────
run --limit=5 | grep -q 'SOURCE files before test/bench files before docs' \
    && ok "(5b) §A10.3 the grep legend states its §P11.1 ordering" \
    || no "(5b) §A10.3 the grep legend never states its ordering (silent reordering)"

# ── (6) §A10.2 — the paging VALUE refusals: flag name AND an example, exit 1 ──────────────────────────
refusal(){                                   # $1 = flag=value ; asserts exit 1 + flag + an example
    local arg="$1" flag="${1%%=*}" out ec
    out="$( "$BIN" "$SB" --no-cache --grep=SEAMTOKENPAGING "$arg" 2>&1 >/dev/null )"; ec=$?
    if [ "$ec" != 1 ]; then no "(6) $arg exited $ec, expected 1"; return; fi
    printf '%s' "$out" | grep -q -- "$flag" || { no "(6) $arg refusal does not name $flag: $out"; return; }
    printf '%s' "$out" | grep -qE -- "$flag=[0-9]+" \
        && ok "(6) $arg refuses at exit 1 naming $flag with an example — $( printf '%s' "$out" | head -1 )" \
        || no "(6) $arg refusal gives no example: $out"
}
refusal '--limit=abc'
refusal '--limit=999999999999'
refusal '--offset=abc'
refusal '--offset=999999999999'

# the out-of-range refusal must state the RANGE, not claim the value is negative (it is not)
OFFMSG="$( "$BIN" "$SB" --no-cache --grep=SEAMTOKENPAGING --offset=999999999999 2>&1 >/dev/null )"
printf '%s' "$OFFMSG" | grep -qi 'out of range' \
    && ok "(6b) §A10.2 --offset=999999999999 refuses as OUT OF RANGE, not as \"non-negative\"" \
    || no "(6b) §A10.2 --offset=999999999999 still refuses for the wrong reason: $OFFMSG"

# ── (7) determinism + G4 on a paged page ─────────────────────────────────────────────────────────────
run --limit=100 --offset=450 >"$TMP/det1"
run --limit=100 --offset=450 >"$TMP/det2"
diff -q "$TMP/det1" "$TMP/det2" >/dev/null \
    && ok "(7) determinism: byte-identical paged page across runs" \
    || no "(7) determinism: paged page differs between runs"

if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/det1" 2>/dev/null \
        && ok "(7b) G4: paged grep output is well-formed XML" \
        || no "(7b) G4: paged grep output is malformed XML"
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
