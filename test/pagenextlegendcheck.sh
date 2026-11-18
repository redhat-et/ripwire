#!/usr/bin/env bash
# A WINDOWED answer SAYS how to take its own continuation cheaply, and taking it that way drops no row.
#
# THE DEFECT, measured 2026-11-18 on the train binary before this lane. A continuation page costs a FULL
# SECOND ANSWER -- 57 windowed cells over --impact/--grep/--uses/--callers on nushell, cpython and envoy,
# median page/first = 1.01, every verb inside 0.99..1.02. That ratio is mostly CORRECT and not waste:
# page 0 and page 1 of `cpython --impact=assertEqual` each carry 89 rows and ~8,100 B of rows, so a page
# delivers a fresh payload. What IS re-sent is the PROSE LEGEND -- 3,255 B of that 12,281 B page, 26.4 %
# -- prose the reader already read on page 0.
#
# Re-taking all 57 continuations under --legend=dict: median 13.2 % smaller (min 3.5 %, max 23.2 %;
# summed 766,318 B -> 670,237 B, 12.5 % off). Per verb --impact 19.3 %, --callers 12.9 %, --grep 9.5 %,
# --uses 5.1 %. The saving already existed behind a flag and nothing told the reader to use it.
#
# WHY PROSE AND NOT A NEW ATTRIBUTE. A `next_legend=` attribute was built first and withdrawn. It emits
# on 19 verbs' first screens, and test/legendcoverage_baseline.txt -- the first-screen legend-gap floor --
# says in its own header that it is "an INVENTORY OF KNOWN DEBT, not an approval" and "may only be edited
# DOWNWARD". So the gate's own contract rules out shipping an attribute undocumented in those dialects,
# and documenting it meant 19 legend strings across 22 files, each moving legend bytes and the dictionary
# identity. The information is instead said where the reader ALREADY learns that next_offset= pastes as
# offset=: src/compactlegend.h's window clause (default posture) and src/pageview.h's kPageRaiseCapClause
# (full dialect). One sentence, two places, no new vocabulary, no first-screen gap.
#
# WHY A STATEMENT AND NOT AN AUTOMATIC CUT. Dropping the prose whenever offset>0 would assume the reader
# holds page 0. It may not -- a reader may call --offset=40 first -- and a CLI run is one process with no
# session, which lane legend-session-default established and refused the automatic flip over. The
# entitlement here is IN HAND: the prose named as droppable is prose THIS answer sent THIS reader. The
# reader still chooses.
#
# ARMS
#   (N)    NON-VACUITY: the fixture genuinely windows, so nothing below passes by the window never firing.
#   (A)    a windowed answer's DEFAULT legend names --legend=dict for its own continuation
#   (FULL) the FULL dialect names it too, so a --legend=full reader is not left out
#   (B)    CONTROL: an answer that does NOT window does not say it -- no pointer to a page that is not
#          there, which is the mirror defect and reads as a cut answer
#   (C)    ZERO ROWS LOST, the whole safety claim: the continuation taken prose-free has the
#          byte-identical ROW SET to the continuation without it. Prose goes, never a row, so
#          completeness cannot regress -- this arm is what makes that a fact rather than an intent.
#   (D)    CHEAPER: that same continuation is strictly smaller prose-free
#   (F)    DETERMINISM: same argv twice, byte-identical, in both postures
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
if [ ! -x "$BIN" ]; then echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; fi
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "pagenextlegendcheck: BIN=$BIN"

# The fixture. --callers windows on a BYTE band, not a row count: 200 SHORT-named callers were served
# WHOLE (count="200", no paging attributes at all), which arm (N) caught before any code was written.
# 250 callers with longer names crosses it on DEFAULTS. pageLonelyFn has a single caller, which gives
# arm (B) an answer that does not window.
SB="$TMP/sb"; mkdir -p "$SB/src"
{
  printf 'int pageTargetFn( int x ) { return x + 1; }\n'
  printf 'int pageLonelyFn( int x ) { return x + 2; }\n'
} >"$SB/src/target.c"
{
  printf 'int pageLonelyFn( int x );\n'
  i=0
  while [ "$i" -lt 250 ]; do
      printf 'int pageFixtureCallerWithALongerName%04d( int a ) { return pageTargetFn( a ) + %d; }\n' "$i" "$i"
      i=$(( i + 1 ))
  done
  printf 'int pageOnlyLonelyCaller( int a ) { return pageLonelyFn( a ); }\n'
} >"$SB/src/callers.c"

rw(){ "$BIN" "$SB" --no-cache "$@" 2>/dev/null; }
SAY='continuation can be taken with --legend=dict'
W="$( rw --callers=pageTargetFn )"
U="$( rw --callers=pageLonelyFn )"
[ -n "$W" ] || { no "(A0) the fixture produced no windowed answer"; echo "pagenextlegendcheck: FAILURES"; exit 1; }
ok "(A0) the fixture indexed (windowed answer $( printf '%s' "$W" | wc -c | tr -d ' ' ) B)"

NX="$( printf '%s' "$W" | grep -oE 'next_offset="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
if printf '%s' "$W" | grep -q 'capped="1"' && printf '%s' "$W" | grep -q 'has_more="1"' && [ -n "$NX" ]; then
    ok "(N) the fixture genuinely windows: capped=1 has_more=1 next_offset=$NX"
else
    no "(N) the fixture does NOT window -- every arm below would pass vacuously"
fi

if printf '%s' "$W" | grep -qF "$SAY"; then
    ok "(A) the windowed answer's default legend names the cheap continuation"
else
    no "(A) the windowed answer does NOT say its continuation can be taken prose-free -- the reader is never told"
fi

# (FULL) is asserted on --grep, not --callers, and the reason is a REAL LIMIT rather than a convenience.
# The DEFAULT (compact) posture is universal: it comes from src/compactlegend.h's one window clause, so
# every paging verb says it, and that is the posture an agent actually gets. The FULL dialect has no
# single window clause -- each verb spells its own -- so the sentence reaches only the verbs whose legend
# composes src/pageview.h's kPageRaiseCapClause (mcpverbs.h, graphlegend.h, verbs_grep.h,
# verbs_navigate.h). --callers windows on this fixture and its full legend is its own string, so it does
# NOT carry the sentence. That gap is disclosed in docs/EVALS.md amendment 14 rather than hidden, and it
# is the price of not minting an attribute the coverage ratchet would refuse.
GF="$( rw --grep=pageTargetFn --legend=full )"
if printf '%s' "$GF" | grep -q 'has_more="1"'; then
    if printf '%s' "$GF" | grep -qF "$SAY"; then
        ok "(FULL) the full dialect names it on a shared-clause verb (--grep)"
    else
        no "(FULL) --grep --legend=full windows but does not name it -- the shared clause is not reaching the full dialect"
    fi
else
    printf '  SKIP  (FULL) --grep does not window on this fixture, so the full dialect cannot be asserted here\n'
fi

if printf '%s' "$U" | grep -qF "$SAY"; then
    no "(B) an UNWINDOWED answer names a continuation that does not exist -- an uncut answer reads as cut"
else
    ok "(B) an unwindowed answer does not name a continuation"
fi

# the callers payload rows are <s ...> elements -- checked on the fixture, not assumed from the verb name.
rowset(){ grep -oE '<s [^>]*/>' | sed 's/ *$//'; }
if [ -n "$NX" ]; then
    rw --callers=pageTargetFn --offset="$NX"                | rowset >"$TMP/rows_plain"
    rw --callers=pageTargetFn --offset="$NX" --legend=dict   | rowset >"$TMP/rows_dict"
    if [ -s "$TMP/rows_plain" ] && cmp -s "$TMP/rows_plain" "$TMP/rows_dict"; then
        ok "(C) prose-free drops PROSE and not one row: the continuation's row set is byte-identical ($( wc -l <"$TMP/rows_plain" | tr -d ' ' ) rows)"
    elif [ ! -s "$TMP/rows_plain" ]; then
        no "(C) the continuation produced no rows to compare -- the arm cannot vouch for anything"
    else
        no "(C) prose-free CHANGED the continuation's row set -- it is a cut, not a prose drop, and completeness can regress"
    fi
    a="$( rw --callers=pageTargetFn --offset="$NX"              | wc -c | tr -d ' ' )"
    b="$( rw --callers=pageTargetFn --offset="$NX" --legend=dict | wc -c | tr -d ' ' )"
    if [ "$b" -lt "$a" ]; then
        ok "(D) taking it prose-free is cheaper: $a B -> $b B ( -$(( ( a - b ) * 100 / a ))% on this fixture )"
    else
        no "(D) taking it prose-free is NOT cheaper ($a B -> $b B) -- the advice would cost the reader bytes"
    fi
else
    no "(C/D) no next_offset to continue from"
fi

rw --callers=pageTargetFn >"$TMP/d1"; rw --callers=pageTargetFn >"$TMP/d2"
rw --callers=pageTargetFn --offset="${NX:-40}" --legend=dict >"$TMP/d3"
rw --callers=pageTargetFn --offset="${NX:-40}" --legend=dict >"$TMP/d4"
if cmp -s "$TMP/d1" "$TMP/d2" && cmp -s "$TMP/d3" "$TMP/d4"; then
    ok "(F) same argv, same bytes -- both the windowed answer and the prose-free continuation"
else
    no "(F) the answer is not byte-identical across runs"
fi

if [ "$fail" -ne 0 ]; then echo "pagenextlegendcheck: FAILURES"; exit 1; fi
echo "pagenextlegendcheck: ALL PASS"
