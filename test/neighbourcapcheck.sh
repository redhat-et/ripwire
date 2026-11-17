#!/usr/bin/env bash
# neighbourcapcheck.sh — gate for LB-G (r10 GitNexus head-to-head, PLAN_HARVEST_REPORTS_2026-08-20/
# r10-gitnexus.md §5): the three UNBOUNDED neighbour verbs — --callers, --callees and --uses — get the
# ordering and the disclosed cap that --grep and --impact already have.
#
# The measured problem (r10 §5 LB-G). `--callers=bulk_create` on django was **175 rows / 17,694 B**, the
# largest single answer ripwire produced in that whole 48-query sweep, and **171 of the 175 rows were
# `tests/`** — four real source callers buried in a wall of test functions. `--uses=bulk_create` on the same
# symbol was worse: **207 rows / 38,546 B**. Neither verb ordered source before test, and neither had a
# display cap: `--grep` has ordered SOURCE > TEST/BENCH > DOC and disclosed `shown=`/`capped=` since the
# span-tier round, and `--impact` has capped at 40 with the same disclosure since §P8. These three were the
# family members the rollout missed.
#
# NO NEW MECHANISM. The ordering key is rw::pathTierOf (src/filter.h) — the same classifier --grep sorts by,
# materialized once per distinct file exactly as search.h does it. The cap is
# rw::effectiveRowCap + pageWindow + pageDisclosure (src/pageview.h), the same trio --impact calls. count=
# is untouched and stays the un-windowed total, so the cap costs no honesty: the rows shrink, the number
# does not move.
#
# Asserts:
#   (0) PRESENCE GUARD: the fixture really has more neighbours than the cap, and its SOURCE callers sort
#       LAST by plain path — so arm (1) cannot pass by alphabetical luck the way django's `django/` <
#       `tests/` would have let it.
#   (1) ORDERING: source-tier rows come first, then test/bench, then docs — against the path order.
#   (2) THE CAP FIRES, DISCLOSED: the default answer prints exactly kCallHierarchyRowCap rows with
#       shown=/capped="1", and the byte total falls.
#   (3) COUNT HONESTY: count= is the same number capped and uncapped. A cap that moved the total would be
#       trading one honesty defect for another.
#   (4) ESCAPE HATCH: --limit=N raises the cap and serves every row; --offset pages the same list.
#   (5) INERT UNDER THE CAP: an answer that dropped nothing and paged nothing carries no shown=, no
#       capped=, and none of the cap vocabulary. (THE TRUNCATION VOCABULARY, rule 3's --skill-scan
#       precedent: a verb may emit the pair only on a capped answer.) MEASURED COST, stated rather than
#       claimed away: such an answer is +86 B over the pre-LB-G shape, and not one byte less — that is the
#       ORDERING sentence, which is on every answer because it describes rows the reader is looking at
#       whether or not anything was capped. Folding it into the conditional clause would buy those 86 B by
#       reordering a listing and not telling the reader; the cap vocabulary is conditional, this is not.
#   (6) --callees gets the same treatment (one code path, one contract).
#   (7) --uses gets the same treatment at its own cap (kUseSiteRowCap — use SITES are the unit --grep
#       counts, not the symbol rows --impact counts).
#   (8) EVERY DIALECT: --json and --format=columnar carry the same window and the same disclosure.
#   (9) LEGEND: the cap vocabulary appears exactly when the attributes do, and the ordering sentence is
#       on the legend of every answer (it describes rows the reader is looking at either way).
#  (10) determinism + well-formed XML.
#
# MUTATION EVIDENCE (red-first, recorded 2026-08-22): against the lane's base binary (5595d01) TEN arms
# fail — (1)(1b)(2)(7b)(8)(8c) and all four of (9)/(9b). The base emits every one of the 64 caller rows in
# plain path order with no shown=/capped= in any dialect, and the four source callers land at positions
# 61-64. The arms that stay green on the base are the presence guard (0), the count-honesty pair (3) — the
# base has no cap to move a count with — the escape-hatch arms (4), which have always worked, the
# inertness arm (5), which is green on BOTH binaries by construction, and (10). Reproduce with:
#     bash test/neighbourcapcheck.sh /path/to/base/build/ripwire
#
# Usage:
#   bash test/neighbourcapcheck.sh                       # uses build/ripwire
#   bash test/neighbourcapcheck.sh path/to/ripwire       # explicit binary (the mutation arm)
#   RIPWIRE_BIN=asan/ripwire bash test/neighbourcapcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
attr(){ printf '%s' "$2" | grep -oE "(^|[^_a-z])$1=\"[^\"]*\"" | head -1 | sed -E "s/.*$1=\"//; s/\"$//"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "neighbourcapcheck: BIN=$BIN"

# ── the sandbox: one hub with 64 callers, 4 of them SOURCE and 60 of them tests ────────────────────────
# The source directory is named `zsrc/` and the tests `tests/` ON PURPOSE: by plain path order the source
# callers sort LAST. django's own shape (`django/` before `tests/`) would have let a path-only sort look
# like a tier sort, which is the coincidence arm (0) exists to remove.
SB="$TMP/neighboursandbox"
mkdir -p "$SB/zsrc" "$SB/tests"
python3 - "$SB" <<'PY'
import sys, os
d = sys.argv[1]
with open( os.path.join( d, "zsrc", "hub.py" ), "w" ) as fh:
    fh.write( "def neighbourHubFn( a, b ):\n    return a + b\n\n" )
    fh.write( "def neighbourHubCallee( x ):\n    return x\n\n" )
    # the hub also CALLS three distinct callees, so the --callees form has something to window
    fh.write( "def neighbourHubCaller( ):\n" )
    fh.write( "    return neighbourHubFn( 1, 2 ) + neighbourHubCallee( 3 )\n" )
# 3 more SOURCE callers (neighbourHubCaller in hub.py is the fourth), in a directory sorting AFTER tests/
with open( os.path.join( d, "zsrc", "prod.py" ), "w" ) as fh:
    for i in range( 3 ):
        fh.write( "def prodCaller%02d( ):\n    return neighbourHubFn( %d, 1 )\n\n" % ( i, i ) )
# 60 TEST callers. C2 (train 31): each name carries a long tail so the 64 rows' bytes (~21 KB) are past the callers byte band
# (pageview.h kCallersBandMaxBytes, 16,000 B) — the default cap must still fire here; arm (22) covers a list that fits the band.
with open( os.path.join( d, "tests", "test_hub.py" ), "w" ) as fh:
    for i in range( 60 ):
        fh.write( "def test_hub_%02d_%s( ):\n    assert neighbourHubFn( %d, 1 )\n\n" % ( i, "p" * 240, i ) )
PY

rw(){ "$BIN" "$SB" --no-cache "$@" 2>/dev/null; }
rows(){ printf '%s' "$1" | grep -oE '<s t="[^"]*" n="[^"]*" p="[^"]*"' ; }
rowCount(){ printf '%s' "$1" | grep -o "<$2 " | wc -l | tr -d ' '; }

CAP_CALL=40      # kCallHierarchyRowCap — the number --impact has used since §P8; one family, one default
CAP_USES=100     # kUseSiteRowCap — use SITES are the unit --grep caps at 100, not --impact's symbol rows

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (0) presence guard: more neighbours than the cap, and source sorts LAST by path ==="
# ═══════════════════════════════════════════════════════════════════════════
# L1 (2026-09-19): the CLI default legend is compact and spells row shapes (<s t= n= p=>) inside its comment; the arms below
# count real rows and read the FULL legend prose (9/9b), so every counted/read answer asks for the full legend.
FULL="$( rw --callers=neighbourHubFn --limit=500 --legend=full )"
full_count="$( attr count "$FULL" )"
[ "${full_count:-0}" -gt "$CAP_CALL" ] \
    && ok "(0) the fixture has $full_count callers, over the $CAP_CALL cap" \
    || no "(0) the fixture has only ${full_count:-0} callers — it cannot observe the cap at all"
[ "zsrc/prod.py" \> "tests/test_hub.py" ] \
    && ok "(0b) the SOURCE file sorts after the TEST file by plain path — arm (1) cannot pass on alphabetical luck" \
    || no "(0b) fixture layout broken: zsrc/ no longer sorts after tests/"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (1) ordering: source before test, against the path order ==="
# ═══════════════════════════════════════════════════════════════════════════
# The assertion is TOTAL, not "the first N": every zsrc/ row must precede every tests/ row. Counting a
# fixed prefix would have to be re-derived whenever the fixture gains a caller (it did: zsrc/hub.py's own
# neighbourHubCaller is a fourth source caller), and a prefix that happened to be right would say nothing
# about the rest of the list.
lastSrc="$(  rows "$FULL" | grep -n 'zsrc/'  | tail -1 | cut -d: -f1 )"
firstTest="$( rows "$FULL" | grep -n 'tests/' | head -1 | cut -d: -f1 )"
srcCount="$(  rows "$FULL" | grep -c 'zsrc/'  )"
testCount="$( rows "$FULL" | grep -c 'tests/' )"
if [ "${srcCount:-0}" -gt 0 ] && [ "${testCount:-0}" -gt 0 ] && [ "$lastSrc" -lt "$firstTest" ]; then
    ok "(1) all $srcCount source callers precede all $testCount test callers, against the path order (last source row $lastSrc, first test row $firstTest)"
else
    no "(1) the tiers are interleaved or missing: $srcCount source rows (last at $lastSrc), $testCount test rows (first at $firstTest)"
fi
lastRow="$( rows "$FULL" | tail -1 )"
printf '%s' "$lastRow" | grep -q 'tests/' \
    && ok "(1b) the tail of the list is the test tier — the partition is total, not a lucky prefix" \
    || no "(1b) the last row is not a test row: $lastRow"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (2) the cap fires and is disclosed ==="
# ═══════════════════════════════════════════════════════════════════════════
DEF="$( rw --callers=neighbourHubFn --legend=full )"
def_rows="$( rowCount "$DEF" s )"
def_shown="$( attr shown "$DEF" )"
def_capped="$( attr capped "$DEF" )"
def_bytes="$( printf '%s' "$DEF" | wc -c | tr -d ' ' )"
full_bytes="$( printf '%s' "$FULL" | wc -c | tr -d ' ' )"
if [ "$def_rows" = "$CAP_CALL" ] && [ "$def_shown" = "$CAP_CALL" ] && [ "$def_capped" = "1" ]; then
    ok "(2) the default answer prints $CAP_CALL rows and says shown=$def_shown capped=1 ($def_bytes B vs $full_bytes B uncapped)"
else
    no "(2) expected $CAP_CALL rows with shown=$CAP_CALL capped=1, got rows=$def_rows shown=$def_shown capped=$def_capped"
    printf '%s\n' "$DEF" | grep -o '<callers [^>]*>'
fi
[ "$def_bytes" -lt "$full_bytes" ] \
    && ok "(2b) the capped answer is smaller than the uncapped one" \
    || no "(2b) the cap saved no bytes ($def_bytes vs $full_bytes)"
# the rows it DID print are the source tier plus the head of the test tier — the cap composes with the order
[ "$( rows "$DEF" | grep -c 'zsrc/' )" = "$srcCount" ] \
    && ok "(2c) the capped page still carries all $srcCount source callers (the cap runs AFTER the ordering)" \
    || no "(2c) the capped page dropped source callers: $( rows "$DEF" | grep -c 'zsrc/' ) of $srcCount survived"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (3) count honesty: the cap moves rows, never the total ==="
# ═══════════════════════════════════════════════════════════════════════════
[ -n "$full_count" ] && [ "$( attr count "$DEF" )" = "$full_count" ] \
    && ok "(3) count=$full_count is identical capped and uncapped" \
    || no "(3) count= moved with the cap: capped=$( attr count "$DEF" ) uncapped=$full_count"
printf '%s' "$DEF" | grep -q 'counts_floor="1"' \
    && ok "(3b) the floor marker survives the cap" \
    || no "(3b) counts_floor= vanished from the capped answer"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (4) escape hatch: --limit raises it, --offset pages it ==="
# ═══════════════════════════════════════════════════════════════════════════
[ "$( rowCount "$FULL" s )" = "$full_count" ] \
    && ok "(4) --limit=500 serves every one of the $full_count rows" \
    || no "(4) --limit=500 served $( rowCount "$FULL" s ) of $full_count rows"
PAGE2="$( rw --callers=neighbourHubFn --limit=10 --offset=10 --legend=full )"
p2_rows="$( rowCount "$PAGE2" s )"
p2_next="$( attr next_offset "$PAGE2" )"
p2_more="$( attr has_more "$PAGE2" )"
if [ "$p2_rows" = "10" ] && [ "$p2_next" = "20" ] && [ "$p2_more" = "1" ]; then
    ok "(4b) --limit=10 --offset=10 serves 10 rows and reports next_offset=20 has_more=1 (a paging loop terminates)"
else
    no "(4b) paging is wrong: rows=$p2_rows next_offset=$p2_next has_more=$p2_more"
fi
# the page seam is exact — page 2 must be the rows the full list holds at [10,20) (cut-fix C: the list is ranked
# most-called first, and every row here ties at 0 callers, so the ranked order IS the path order; arm 11d asserts the
# seam on a list whose weights differ)
if [ "$( rows "$PAGE2" | head -1 )" = "$( rows "$FULL" | sed -n '11p' )" ]; then
    ok "(4c) the page seam is exact: page 2 starts at the full list's row 11"
else
    no "(4c) the page seam drifted: page2[0]=$( rows "$PAGE2" | head -1 ) fullList[10]=$( rows "$FULL" | sed -n '11p' )"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (5) inert under the cap: an uncapped, unpaged answer says nothing ==="
# ═══════════════════════════════════════════════════════════════════════════
SMALL="$( rw --callers=neighbourHubCallee --legend=full )"
small_rows="$( rowCount "$SMALL" s )"
if [ "$small_rows" -gt 0 ] && [ "$small_rows" -lt "$CAP_CALL" ]; then
    if printf '%s' "$SMALL" | grep -qE ' shown="| capped="'; then
        no "(5) an answer that dropped nothing still paid for shown=/capped="
    else
        ok "(5) an answer under the cap carries no shown=/capped= (its only change from the pre-LB-G shape is the +86 B ordering sentence)"
    fi
    printf '%s' "$SMALL" | grep -q 'raise the default cap' \
        && no "(5b) an uncapped answer still pays for the raise-the-cap sentence it can never need" \
        || ok "(5b) an uncapped answer pays no bytes for cap vocabulary"
else
    no "(5) presence guard: neighbourHubCallee has $small_rows callers — not a usable under-the-cap case"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (6) --callees is the same code path and the same contract ==="
# ═══════════════════════════════════════════════════════════════════════════
CE="$( rw --callees=neighbourHubCaller --legend=full )"
printf '%s' "$CE" | grep -q '<callees ' \
    && ok "(6) --callees still answers" \
    || no "(6) --callees stopped answering"
CE_CAP="$( rw --callees=neighbourHubCaller --limit=1 --legend=full )"
if [ "$( rowCount "$CE_CAP" s )" = "1" ] && [ "$( attr capped "$CE_CAP" )" = "1" ]; then
    ok "(6b) --callees windows and discloses exactly as --callers does"
else
    no "(6b) --callees paging diverged: rows=$( rowCount "$CE_CAP" s ) capped=$( attr capped "$CE_CAP" )"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (7) --uses: same ordering, its own cap ==="
# ═══════════════════════════════════════════════════════════════════════════
U_FULL="$( rw --uses=neighbourHubFn --limit=500 --legend=full )"
u_count="$( attr count "$U_FULL" )"
U_DEF="$( rw --uses=neighbourHubFn --legend=full )"
u_rows="$( rowCount "$U_DEF" u )"
# the fixture has 63 call sites + 1 def-site-adjacent row or so — under 100, so the cap must NOT fire here,
# and that is the arm: --uses keeps its own unit (sites), so the SYMBOL cap must not leak onto it.
if [ "${u_count:-0}" -lt "$CAP_USES" ]; then
    [ "$u_rows" = "$u_count" ] \
        && ok "(7) --uses has $u_count sites, under its own $CAP_USES cap, and serves all of them (the symbol cap did not leak onto the site unit)" \
        || no "(7) --uses served $u_rows of $u_count sites while under its own cap"
else
    if [ "$u_rows" = "$CAP_USES" ]; then ok "(7) --uses capped at $CAP_USES"; else no "(7) --uses expected $CAP_USES rows, got $u_rows"; fi
fi
# ordering: --uses rows carry p= only, so assert the source sites lead
u_first="$( printf '%s' "$U_DEF" | grep -oE '<u role="[^"]*" p="[^"]*"' | head -1 )"
printf '%s' "$u_first" | grep -q 'zsrc/' \
    && ok "(7b) --uses leads with the source-tier site, against the path order" \
    || no "(7b) --uses is still in plain path order: first row is $u_first"
U_CAP="$( rw --uses=neighbourHubFn --limit=5 --legend=full )"
if [ "$( rowCount "$U_CAP" u )" = "5" ] && [ "$( attr capped "$U_CAP" )" = "1" ] && [ "$( attr count "$U_CAP" )" = "$u_count" ]; then
    ok "(7c) --uses windows with shown=/capped= and leaves count= at the true total"
else
    no "(7c) --uses paging is wrong: rows=$( rowCount "$U_CAP" u ) capped=$( attr capped "$U_CAP" ) count=$( attr count "$U_CAP" )/$u_count"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (8) every dialect carries the same window and the same disclosure ==="
# ═══════════════════════════════════════════════════════════════════════════
JS="$( rw --callers=neighbourHubFn --json )"
js_rows="$( printf '%s' "$JS" | grep -o '{"t":' | wc -l | tr -d ' ' )"
js_shown="$( printf '%s' "$JS" | grep -oE '"shown":[0-9]+' | head -1 | grep -oE '[0-9]+' )"
js_count="$( printf '%s' "$JS" | grep -oE '"count":[0-9]+' | head -1 | grep -oE '[0-9]+' )"
if [ "$js_rows" = "$CAP_CALL" ] && [ "$js_shown" = "$CAP_CALL" ] && [ "$js_count" = "$full_count" ]; then
    ok "(8) --json windows to $CAP_CALL, discloses shown=$js_shown, and keeps count=$js_count"
else
    no "(8) --json diverged: rows=$js_rows shown=$js_shown count=$js_count (expected $CAP_CALL/$CAP_CALL/$full_count)"
fi
command -v python3 >/dev/null 2>&1 && { if printf '%s' "$JS" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then ok "(8b) the capped --json answer parses"; else no "(8b) the capped --json answer is not valid JSON"; fi; }
COL="$( rw --callers=neighbourHubFn --format=columnar )"
col_shown="$( attr shown "$COL" )"
[ "$col_shown" = "$CAP_CALL" ] \
    && ok "(8c) --format=columnar carries the same shown=$col_shown" \
    || no "(8c) --format=columnar disclosed shown=$col_shown, expected $CAP_CALL"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (9) the legend defines what the answer emits, and only that ==="
# ═══════════════════════════════════════════════════════════════════════════
DEF_LEGEND="$( printf '%s' "$DEF" | grep -o '<!--.*-->' | head -1 )"
for word in 'shown=' 'capped=' 'raise the default cap'; do
    printf '%s' "$DEF_LEGEND" | grep -qiF "$word" \
        && ok "(9) the capped answer's legend defines \"$word\"" \
        || no "(9) the capped answer emits vocabulary its legend never defines: \"$word\""
done
printf '%s' "$SMALL" | grep -q 'SOURCE' \
    && ok "(9b) the row ORDER is stated on every answer, capped or not (it describes rows the reader sees either way)" \
    || no "(9b) the ordering change is undisclosed on an uncapped answer"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (10) determinism + well-formed XML ==="
# ═══════════════════════════════════════════════════════════════════════════
for v in "--callers=neighbourHubFn" "--callees=neighbourHubCaller" "--uses=neighbourHubFn"; do
    r1="$( rw "$v" )"; r2="$( rw "$v" )"
    if [ "$r1" = "$r2" ]; then ok "(10) $v is byte-identical across runs"; else no "(10) $v is nondeterministic"; fi
    if command -v xmllint >/dev/null 2>&1; then
        if printf '%s' "$r1" | xmllint --noout - 2>/dev/null; then ok "(10b) $v is well-formed XML"; else no "(10b) $v is not well-formed XML"; fi
    fi
done

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (11) RANK BEFORE THE CAP (cut-fix C): the cap drops the least-called rows, not the last path ==="
# ═══════════════════════════════════════════════════════════════════════════
# docs/METHODOLOGY.md §9: the ceiling bounds the tail, never the head. Before cut-fix C every list here cut in
# PATH order, so the rows that survived a cap were the alphabetically-first files. The second sandbox is built so
# path order and relevance DISAGREE: 100 leaf callers (nobody calls them) in asrc/, which sorts first, and 5 heavy
# callers (each called by 3 drivers) in zsrc/, which sorts last. 105 callers > the 40 cap, 105 call sites > the
# 100 cap. On the base binary the default --callers page is 40 leaves and --uses drops exactly the 5 heavy sites.
# RED on 60b65f02 (arms 11b 11c 11e 12 12b 13c; recorded 2026-09-23); GREEN on cut-fix C. 11d 13 13b 13d 13e are guards, green on both.
RB="$TMP/ranksandbox"
mkdir -p "$RB/asrc" "$RB/zsrc"
python3 - "$RB" <<'PY'
import sys, os
d = sys.argv[1]
open( os.path.join( d, "zsrc", "core.py" ), "w" ).write( "def rankHubFn( x ):\n    return x\n" )
with open( os.path.join( d, "asrc", "leaves.py" ), "w" ) as fh:
    for i in range( 100 ):   # C2 (train 31): a long name tail keeps the 105 rows (~19 KB) past the callers byte band, so the cap fires
        fh.write( "def leaf_%03d_%s( ):\n    return rankHubFn( %d )\n\n" % ( i, "q" * 140, i ) )
with open( os.path.join( d, "zsrc", "heavy.py" ), "w" ) as fh:
    for i in range( 5 ):
        fh.write( "def heavy_%d( ):\n    return rankHubFn( %d )\n\n" % ( i, i ) )
with open( os.path.join( d, "zsrc", "drivers.py" ), "w" ) as fh:
    for j in range( 3 ):
        fh.write( "def driver_%d( ):\n    return %s\n\n" % ( j, " + ".join( "heavy_%d( )" % i for i in range( 5 ) ) ) )
PY
rr(){ "$BIN" "$RB" --no-cache "$@" 2>/dev/null; }
R_FULL="$( rr --callers=rankHubFn --limit=500 )"
R_DEF="$( rr --callers=rankHubFn )"
heavyIn(){ printf '%s' "$1" | grep -oE '<s t="[^"]*" n="heavy_[0-9]"' | wc -l | tr -d ' '; }
if [ "$( attr count "$R_FULL" )" = 105 ] && [ "$( heavyIn "$R_FULL" )" = 5 ] && [ "asrc/leaves.py" \< "zsrc/heavy.py" ]; then
    ok "(11) presence guard: 105 callers, all 5 heavy ones in the uncapped list, and they sort LAST by path"
else
    no "(11) fixture broken: count=$( attr count "$R_FULL" ) heavy=$( heavyIn "$R_FULL" )"
fi
[ "$( heavyIn "$R_DEF" )" = 5 ] && [ "$( rows "$R_DEF" | wc -l | tr -d ' ' )" = "$CAP_CALL" ] \
    && ok "(11b) the default $CAP_CALL-row page keeps all 5 heavy callers (the cut dropped leaves)" \
    || no "(11b) the default page kept $( heavyIn "$R_DEF" ) of 5 heavy callers in $( rows "$R_DEF" | wc -l | tr -d ' ' ) rows — the cap cut the head"
[ "$( rows "$R_DEF" | head -5 | grep -c 'n="heavy_' )" = 5 ] \
    && ok "(11c) the most-called rows lead the page (rows 1-5 are the heavy callers)" \
    || no "(11c) the page does not lead with the most-called rows: $( rows "$R_DEF" | head -2 | tr '\n' ' ' )"
# ONE total order for the cap, the rows and the paging: page[0:k] + page[k:2k] + … == the uncapped list.
: > "$TMP/pages"
for off in 0 20 40 60 80 100; do rows "$( rr --callers=rankHubFn --limit=20 --offset=$off )" >> "$TMP/pages"; done
if rows "$R_FULL" | diff -q - "$TMP/pages" >/dev/null && [ "$( sort -u "$TMP/pages" | wc -l | tr -d ' ' )" = 105 ]; then
    ok "(11d) six --limit=20 pages concatenate to the uncapped list exactly — one total order, no row dropped or repeated"
else
    no "(11d) the pages do not partition the uncapped order ($( sort -u "$TMP/pages" | wc -l | tr -d ' ' ) distinct rows)"
fi
R_JS="$( rr --callers=rankHubFn --json )"
R_COL="$( rr --callers=rankHubFn --format=columnar )"
{ [ "$( printf '%s' "$R_JS" | grep -oE '"n":"heavy_[0-9]"' | wc -l | tr -d ' ' )" = 5 ] \
  && [ "$( printf '%s' "$R_COL" | grep -oE 'heavy_[0-9]' | sort -u | wc -l | tr -d ' ' )" = 5 ]; } \
    && ok "(11e) --json and --format=columnar keep the same 5 heavy callers (one order, every dialect)" \
    || no "(11e) a dialect cut the head: json=$( printf '%s' "$R_JS" | grep -oE '"n":"heavy_[0-9]"' | wc -l | tr -d ' ' )"
r1="$( rr --callers=rankHubFn )"
if [ "$r1" = "$R_DEF" ]; then
    ok "(11f) the ranked answer is byte-identical across runs"
else
    no "(11f) the ranked answer is nondeterministic"
fi

echo "=== (12) --uses: the same rule at its own cap ==="
U_R="$( rr --uses=rankHubFn )"
heavySites="$( printf '%s' "$U_R" | grep -oE '<u role="call" p="zsrc/heavy.py:[0-9]+"' | wc -l | tr -d ' ' )"
uRows="$( printf '%s' "$U_R" | grep -oE '<u role="' | wc -l | tr -d ' ' )"
{ [ "$( attr count "$U_R" )" = 105 ] && [ "$uRows" = "$CAP_USES" ] && [ "$heavySites" = 5 ]; } \
    && ok "(12) the default $CAP_USES-site page of 105 keeps all 5 sites inside the heavy callers" \
    || no "(12) --uses kept $heavySites of 5 heavy sites (count=$( attr count "$U_R" ), rows=$uRows)"
printf '%s' "$U_R" | grep -oE '<u role="[^"]*" p="[^"]*"' | head -1 | grep -q 'zsrc/heavy.py' \
    && ok "(12b) --uses leads with a site in the most-called enclosing symbol" \
    || no "(12b) --uses does not lead with the heaviest site"

echo "=== (13) MCP: the same order, and find_symbol's calledBy cut is disclosed ==="
MCP_OUT="$( python3 - "$BIN" "$RB" <<'PY'
import json, subprocess, sys, threading
p = subprocess.Popen( [ sys.argv[1], sys.argv[2], "--mcp" ], stdin = subprocess.PIPE, stdout = subprocess.PIPE, stderr = subprocess.DEVNULL )
watchdog = threading.Timer( 300, p.kill ); watchdog.daemon = True; watchdog.start()   # a hung server ends readline() below, not the gate
def tool( n, name, args ):
    p.stdin.write( ( json.dumps( { "jsonrpc": "2.0", "id": n, "method": "tools/call", "params": { "name": name, "arguments": args } } ) + "\n" ).encode() )
    p.stdin.flush()
    return json.loads( json.loads( p.stdout.readline() )[ "result" ][ "content" ][ 0 ][ "text" ] )
ref = tool( 1, "find_referencing_symbols", { "symbol": "rankHubFn" } )
fs  = tool( 2, "find_symbol", { "symbol": "rankHubFn" } )
sm  = tool( 3, "find_symbol", { "symbol": "heavy_0" } )
p.stdin.close(); p.wait( 20 )
print( "REF " + " ".join( r[ "name" ] for r in ref[ "calledBy" ] ) )
print( "FSCB " + " ".join( r[ "name" ] for r in fs[ "calledBy" ] ) )
print( "FSKEYS %s %s %s %s" % ( fs.get( "calledBy_total" ), fs.get( "shown_calledBy" ), fs.get( "calledBy_capped" ), fs.get( "calledBy_next" ) ) )
print( "SMKEYS %s" % ( "calledBy_total" in sm ) )
PY
)"
CLI_NAMES="$( printf '%s' "$R_JS" | grep -oE '"n":"[^"]*"' | sed 's/"n":"//; s/"$//' | tr '\n' ' ' | sed 's/ $//' )"
[ "$( printf '%s\n' "$MCP_OUT" | sed -n 's/^REF //p' )" = "$CLI_NAMES" ] \
    && ok "(13) find_referencing_symbols serves the CLI --callers page, row for row" \
    || no "(13) MCP and CLI disagree on the page: $( printf '%s\n' "$MCP_OUT" | sed -n 's/^REF //p' | cut -c1-80 )"
[ "$( printf '%s\n' "$MCP_OUT" | sed -n 's/^FSCB //p' )" = "$CLI_NAMES" ] \
    && ok "(13b) find_symbol's calledBy array is the same ranked page (it kept the 5 heavy callers)" \
    || no "(13b) find_symbol's calledBy page differs from --callers: $( printf '%s\n' "$MCP_OUT" | sed -n 's/^FSCB //p' | cut -c1-80 )"
FSK="$( printf '%s\n' "$MCP_OUT" | sed -n 's/^FSKEYS //p' )"
[ "$FSK" = "105 40 True --callers=rankHubFn --offset=40" ] \
    && ok "(13c) find_symbol discloses its calledBy cut: calledBy_total=105 shown_calledBy=40 calledBy_capped=true calledBy_next=--callers=rankHubFn --offset=40" \
    || no "(13c) find_symbol's calledBy cut is silent or wrong: $FSK"
NEXT_NAMES="$( rr --callers=rankHubFn --offset=40 --json | grep -oE '"n":"[^"]*"' | head -1 )"
[ "$NEXT_NAMES" = "$( rows "$R_FULL" | sed -n '41p' | grep -oE 'n="[^"]*"' | sed 's/^n="/"n":"/' )" ] \
    && ok "(13d) the pasted calledBy_next continues at row 41 of the one order" \
    || no "(13d) calledBy_next does not continue the order: got $NEXT_NAMES"
[ "$( printf '%s\n' "$MCP_OUT" | sed -n 's/^SMKEYS //p' )" = "False" ] \
    && ok "(13e) an uncut calledBy array pays no bytes for the disclosure (absent, rule 3's --skill-scan shape)" \
    || no "(13e) an uncut calledBy array still carries calledBy_total"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (14)-(21) L8 callers cap band: a total within 1.25 x the cap is served whole; above it next= is the PAGE ==="
# ═══════════════════════════════════════════════════════════════════════════
# train 29 L8 (pageview.h kCallHierarchyBandMax / callHierarchyRowCap): ninja's --callers=Stat printed 40 of 44 and the
# four hidden rows cost a second call. A total in (40, 50] is now its own cap; at 51 and above the cap stays 40 and the
# callers root's next= is the next page (--callers=SEL --offset=40, the caller's --limit kept), with the uses verb moved
# to uses_next=. Hubs in C AND Python: the band reads only the row total, so both languages take the same rule.
BB="$TMP/band sandbox"
mkdir -p "$BB/c dir" "$BB/py"
python3 - "$BB" <<'PY'
import sys, os
d = sys.argv[1]
def cHub( n ):
    with open( os.path.join( d, "c dir", "b%d.c" % n ), "w" ) as fh:
        fh.write( "int band%dHub( int a ) { return a + 1; }\n" % n )
        for i in range( n ):   # C2 (train 31): at 51 a long name tail puts the rows (~18 KB) past the callers byte band
            fh.write( "int b%dc%03d%s( int x ) { return band%dHub( x ); }\n" % ( n, i, "r" * 300 if n == 51 else "", n ) )
def pyHub( n ):
    with open( os.path.join( d, "py", "b%d.py" % n ), "w" ) as fh:
        fh.write( "def band%dHub( a ):\n    return a + 1\n\n" % n )
        for i in range( n ):
            fh.write( "def b%dp%03d( x ):\n    return band%dHub( x )\n\n" % ( n, i, n ) )
for n in ( 41, 50, 51 ):
    cHub( n )
for n in ( 40, 45, 400 ):
    pyHub( n )
# C2 (train 31): 121 short-named callers (~8 KB of rows, inside the 16,000 B callers byte band), and a callees hub fanning out to
# 55 distinct functions (past the row band; the byte band is callers-only).
cHub( 121 )
with open( os.path.join( d, "c dir", "fan55.c" ), "w" ) as fh:
    for i in range( 55 ):
        fh.write( "int fanLf%02d( int x ) { return x + %d; }\n" % ( i, i ) )
    fh.write( "int fanOut55( int x ) {\n    int s = 0;\n" )
    for i in range( 55 ):
        fh.write( "    s += fanLf%02d( x );\n" % i )
    fh.write( "    return s;\n}\n" )
# fix round 1 (rv-callers-band2 N2/M2, N1): two hubs that pin WHAT the byte estimate counts. sitesHub: 150 callers whose bare
# rows are ~6.4 KB but each calls the hub on 16 lines, so with sites_at= the rows are ~20 KB — past the band only if the
# estimate counts the sites. escHub: 240 MODULE-SCOPE callers (<file-scope>, printed escaped as &lt;file-scope&gt;) whose
# rows are ~17 KB as printed but ~15.6 KB unescaped — past the band only if the estimate counts the escaping.
# RE-SIZED 2026-11-17 (SITES-SHORT): a site is now the bare line of the row's own p= file, so each row is shorter and the
# old sizes (100 callers x 8 sites; 200 module scopes) fell wholly inside the 16,000 B band — 8,572 B and 14,200 B, the
# premise arms (26)/(27) said so. Same two readings on either side of the same band; only the row counts grew.
with open( os.path.join( d, "c dir", "s100.c" ), "w" ) as fh:
    fh.write( "int sitesHub( int a ) { return a + 1; }\n" )
    for i in range( 150 ):
        fh.write( "int sc%03d( int x ) {\n    int s = 0;\n" % i + "    s += sitesHub( x );\n" * 16 + "    return s;\n}\n" )
os.makedirs( os.path.join( d, "esc" ), exist_ok = True )
with open( os.path.join( d, "esc", "esccore.py" ), "w" ) as fh:
    fh.write( "def escHub( a ):\n    return a\n" )
for i in range( 240 ):
    with open( os.path.join( d, "esc", "e%03d.py" % i ), "w" ) as fh:
        fh.write( "from esccore import escHub\n\nescHub( %d )\n" % i )
# a CALLEES hub: one function calling 45 distinct functions (the shared call-hierarchy cap, other direction)
with open( os.path.join( d, "c dir", "fan.c" ), "w" ) as fh:
    for i in range( 45 ):
        fh.write( "int fanLeaf%02d( int x ) { return x + %d; }\n" % ( i, i ) )
    fh.write( "int fanOut45( int x ) {\n    int s = 0;\n" )
    for i in range( 45 ):
        fh.write( "    s += fanLeaf%02d( x );\n" % i )
    fh.write( "    return s;\n}\n" )
PY
rb(){ "$BIN" "$BB" --no-cache "$@" 2>/dev/null; }
bandRows(){ printf '%s' "$1" | grep -oE '<s t="[^"]*" n="' | wc -l | tr -d ' '; }   # real rows only: the compact legend spells <s t= n= p=> too
rootTag(){ printf '%s' "$1" | grep -oE "<$2 [^>]*>" | head -1; }
for n in 41 45 50; do
    A="$( rb --callers=band${n}Hub )"; T="$( rootTag "$A" callers )"
    r="$( bandRows "$A" )"; c="$( attr count "$T" )"; cp="$( attr capped "$T" )"
    if [ "$r" = "$n" ] && [ "$c" = "$n" ] && [ "${cp:-0}" = "0" ] && [ "$( attr next "$T" )" = "--uses=band${n}Hub" ]; then
        ok "(14) total $n is inside the band: all $r rows, capped=${cp:-absent} (uncut), next= stays the uses verb"
    else
        no "(14) total $n: rows=$r count=$c capped=${cp:-absent} next=$( attr next "$T" ) (want $n rows, uncut)"
    fi
done
A40="$( rb --callers=band40Hub )"; T40="$( rootTag "$A40" callers )"
{ [ "$( bandRows "$A40" )" = 40 ] && [ -z "$( attr capped "$T40" )" ] && [ "$( attr next "$T40" )" = "--uses=band40Hub" ] && [ -z "$( attr uses_next "$T40" )" ]; } \
    && ok "(15) total exactly 40: 40 rows, no cap vocabulary, next= the uses verb, no uses_next= (the pre-band shape)" \
    || no "(15) total 40 moved: $T40"
A51="$( rb --callers=band51Hub )"; T51="$( rootTag "$A51" callers )"
{ [ "$( bandRows "$A51" )" = 40 ] && [ "$( attr capped "$T51" )" = 1 ] && [ "$( attr next_offset "$T51" )" = 40 ] \
  && [ "$( attr next "$T51" )" = "--callers=band51Hub --offset=40" ] && [ "$( attr uses_next "$T51" )" = "--uses=band51Hub" ]; } \
    && ok "(16) total 51 is past the band: 40 rows, capped=1, next= the page (--callers=band51Hub --offset=40), uses_next= the uses verb" \
    || no "(16) total 51: $T51"
P51="$( rb --callers=band51Hub --offset=40 )"; TP51="$( rootTag "$P51" callers )"
{ [ "$( bandRows "$P51" )" = 11 ] && [ "$( attr has_more "$TP51" )" = 0 ] && [ "$( attr next "$TP51" )" = "--uses=band51Hub" ]; } \
    && ok "(16b) the pasted page serves rows 41-51 (11 rows), has_more=0, and its next= is the uses verb again" \
    || no "(16b) page 2 of 51: rows=$( bandRows "$P51" ) $TP51"
A400="$( rb --callers=band400Hub )"; T400="$( rootTag "$A400" callers )"
{ [ "$( bandRows "$A400" )" = 40 ] && [ "$( attr count "$T400" )" = 400 ] && [ "$( attr next_offset "$T400" )" = 40 ] \
  && [ "$( attr next "$T400" )" = "--callers=band400Hub --offset=40" ]; } \
    && ok "(17) a 400-caller symbol still caps at 40 with next_offset=40 and the page as next=" \
    || no "(17) total 400: rows=$( bandRows "$A400" ) $T400"
L400="$( rootTag "$( rb --callers=band400Hub --limit=10 --offset=20 )" callers )"
[ "$( attr next "$L400" )" = "--callers=band400Hub --limit=10 --offset=30" ] \
    && ok "(17b) an explicit --limit rides the page next= (--limit=10 --offset=30), so the pages line up" \
    || no "(17b) --limit page next=: $( attr next "$L400" )"
E400="$( rb --callers=band400Hub --offset=360 )"; TE400="$( rootTag "$E400" callers )"
{ [ "$( bandRows "$E400" )" = 40 ] && [ "$( attr has_more "$TE400" )" = 0 ] && [ "$( attr next "$TE400" )" = "--uses=band400Hub" ]; } \
    && ok "(17c) the last page of 400 (offset 360) has no further page: next= is the uses verb" \
    || no "(17c) last page of 400: $TE400"
L50="$( rb --callers=band50Hub --limit=45 )"
[ "$( bandRows "$L50" )" = 45 ] \
    && ok "(17d) an explicit --limit beats the band (45 of 50 under --limit=45)" \
    || no "(17d) --limit=45 on 50 served $( bandRows "$L50" ) rows"
SP="$( rootTag "$( rb '--callers=c dir/b51.c:band51Hub' )" callers )"
NX="$( attr next "$SP" | sed "s/&apos;/'/g" )"
NXROWS="$( eval "set -- $NX"; [ "$#" = 2 ] && bandRows "$( rb "$1" "$2" )" )"
{ [ "$NX" = "--callers='c dir/b51.c:band51Hub' --offset=40" ] && [ "$NXROWS" = 11 ]; } \
    && ok "(17e) a selector with a space: next= quotes it as ONE argv word and the replay serves the 11 remaining rows" \
    || no "(17e) spaced selector next=: [$NX] replay rows=${NXROWS:-none}"
J45="$( rb --callers=band45Hub --json )"; J51="$( rb --callers=band51Hub --json )"
{ [ "$( printf '%s' "$J45" | grep -o '"n":"b45p' | wc -l | tr -d ' ' )" = 45 ] && ! printf '%s' "$J45" | grep -q '"capped"' \
  && [ "$( printf '%s' "$J51" | grep -o '"n":"b51c' | wc -l | tr -d ' ' )" = 40 ] && printf '%s' "$J51" | grep -q '"capped":true,"total":51,"has_more":true,"next_offset":40'; } \
    && ok "(18) --json: the band serves 45 uncut, 51 cuts at 40 with the paging keys" \
    || no "(18) --json band: 45 rows=$( printf '%s' "$J45" | grep -o '"n":"b45p' | wc -l ) 51 head=$( printf '%s' "$J51" | cut -c1-200 )"
# (18b) CodeRabbit 4303967676: the --json page carried next_offset but neither the page call nor the uses verb the XML,
# columnar and MCP forms name. The JSON page names both, its next replays --json (the page keeps its dialect), the pasted
# page serves the 11 remaining rows as JSON, and an uncut answer and the last page add no next key (their bytes stand).
J51N="$( printf '%s' "$J51" | grep -oE '"next":"[^"]*","uses_next":"[^"]*"' | head -1 )"
J51P="$( rb --callers=band51Hub --json --offset=40 )"
{ [ "$J51N" = '"next":"--callers=band51Hub --json --offset=40","uses_next":"--uses=band51Hub"' ] \
  && [ "$( printf '%s' "$J51P" | head -c 1 )" = "{" ] && [ "$( printf '%s' "$J51P" | grep -o '"n":"b51c' | wc -l | tr -d ' ' )" = 11 ] \
  && ! printf '%s' "$J51P" | grep -q '"next"' && ! printf '%s' "$J45" | grep -q '"next"'; } \
    && ok "(18b) --json at 51: next is the JSON page (--callers=band51Hub --json --offset=40), uses_next the uses verb; the page serves 11 JSON rows; uncut and last pages carry no next" \
    || no "(18b) --json page next: [${J51N:-none}] page2 rows=$( printf '%s' "$J51P" | grep -o '"n":"b51c' | wc -l | tr -d ' ' ) page2 next=$( printf '%s' "$J51P" | grep -c '"next"' ) uncut next=$( printf '%s' "$J45" | grep -c '"next"' )"
C51="$( rb --callers=band51Hub --format=columnar )"; TC51="$( rootTag "$C51" callers )"
[ "$( attr next "$TC51" )" = "--callers=band51Hub --format=columnar --offset=40" ] \
    && ok "(19) --format=columnar: the page next= keeps the form" \
    || no "(19) columnar next=: $( attr next "$TC51" )"
F45="$( rb --callees=fanOut45 )"
[ "$( bandRows "$F45" )" = 45 ] \
    && ok "(20) --callees takes the same band (45 callees, one shared cap)" \
    || no "(20) --callees=fanOut45 served $( bandRows "$F45" ) of 45"
MB="$( python3 - "$BIN" "$BB" <<'PY'
import json, subprocess, sys, threading
p = subprocess.Popen( [ sys.argv[1], sys.argv[2], "--mcp" ], stdin = subprocess.PIPE, stdout = subprocess.PIPE, stderr = subprocess.DEVNULL )
watchdog = threading.Timer( 300, p.kill ); watchdog.daemon = True; watchdog.start()
def tool( n, name, args ):
    p.stdin.write( ( json.dumps( { "jsonrpc": "2.0", "id": n, "method": "tools/call", "params": { "name": name, "arguments": args } } ) + "\n" ).encode() )
    p.stdin.flush()
    return json.loads( json.loads( p.stdout.readline() )[ "result" ][ "content" ][ 0 ][ "text" ] )
r45 = tool( 1, "find_referencing_symbols", { "symbol": "band45Hub" } )
r51 = tool( 2, "find_referencing_symbols", { "symbol": "band51Hub" } )
f45 = tool( 3, "find_symbol", { "symbol": "band45Hub" } )
p.stdin.close(); p.wait( 20 )
print( "R45 %d %s %s" % ( len( r45[ "calledBy" ] ), r45.get( "capped" ), r45.get( "next" ) ) )
print( "R51 %d %s %s|%s" % ( len( r51[ "calledBy" ] ), r51.get( "capped" ), r51.get( "next" ), r51.get( "uses_next" ) ) )
print( "F45 %d %s" % ( len( f45[ "calledBy" ] ), "calledBy_total" in f45 ) )
PY
)"
[ "$( printf '%s\n' "$MB" | sed -n 's/^R45 //p' )" = "45 None --uses=band45Hub" ] \
    && ok "(21) MCP find_referencing_symbols: the band serves 45 of 45 uncut, next the uses verb (CLI parity)" \
    || no "(21) MCP band 45: $( printf '%s\n' "$MB" | sed -n 's/^R45 //p' )"
[ "$( printf '%s\n' "$MB" | sed -n 's/^R51 //p' )" = "40 True --callers=band51Hub --offset=40|--uses=band51Hub" ] \
    && ok "(21b) MCP at 51: 40 rows, capped, next the page and uses_next the uses verb, as the CLI root says" \
    || no "(21b) MCP 51: $( printf '%s\n' "$MB" | sed -n 's/^R51 //p' )"
[ "$( printf '%s\n' "$MB" | sed -n 's/^F45 //p' )" = "45 False" ] \
    && ok "(21c) MCP find_symbol's calledBy array takes the band too (45 rows, no cut keys)" \
    || no "(21c) find_symbol calledBy band: $( printf '%s\n' "$MB" | sed -n 's/^F45 //p' )"

echo "=== (22)-(25) C2 callers BYTE band: a callers list whose rows fit 16,000 B is served whole; a capped callees page pages ==="
# ═══════════════════════════════════════════════════════════════════════════
# train 31 C2 (pageview.h kCallersBandMaxBytes, callhierarchy.h callersByteBand): tmux's --callers=options_get_number was 40 of
# 121 rows at ~10.8 KB for the whole list. A CALLERS answer whose estimated row bytes fit the band is now its own cap on every
# surface; past it (arms 2, 16, 17: the same row counts with heavier rows) the 40-row page and next= page stay. The byte band
# is callers-only: --callees keeps the row band, and a capped callees page now names the next page as next= with expand
# moved to expand_next= (rv-callers-band N1).
A121="$( rb --callers=band121Hub )"; T121="$( rootTag "$A121" callers )"
{ [ "$( bandRows "$A121" )" = 121 ] && [ "$( attr count "$T121" )" = 121 ] && [ -z "$( attr capped "$T121" )" ] && [ -z "$( attr has_more "$T121" )" ] \
  && [ "$( attr next "$T121" )" = "--uses=band121Hub" ] && [ -z "$( attr uses_next "$T121" )" ]; } \
    && ok "(22) 121 short callers fit the byte band: all 121 rows, no cap vocabulary, next= the uses verb (the uncut shape)" \
    || no "(22) band121Hub: rows=$( bandRows "$A121" ) $T121"
J121="$( rb --callers=band121Hub --json )"
{ [ "$( printf '%s' "$J121" | grep -o '"n":"b121c' | wc -l | tr -d ' ' )" = 121 ] && ! printf '%s' "$J121" | grep -q '"capped"\|"next"'; } \
    && ok "(22b) --json serves the same 121 rows uncut (no capped/next keys)" \
    || no "(22b) --json band121: rows=$( printf '%s' "$J121" | grep -o '"n":"b121c' | wc -l | tr -d ' ' ) head=$( printf '%s' "$J121" | cut -c1-240 )"
C121="$( rb --callers=band121Hub --format=columnar )"; TC121="$( rootTag "$C121" callers )"
{ [ -z "$( attr capped "$TC121" )" ] && [ "$( attr next "$TC121" )" = "--uses=band121Hub" ] && printf '%s' "$C121" | grep -q 'b121c120'; } \
    && ok "(22c) --format=columnar serves all 121 (the last caller b121c120 is on the page, no capped=)" \
    || no "(22c) columnar band121: $TC121"
L121="$( rb --callers=band121Hub --limit=40 )"; TL121="$( rootTag "$L121" callers )"
{ [ "$( bandRows "$L121" )" = 40 ] && [ "$( attr next "$TL121" )" = "--callers=band121Hub --limit=40 --offset=40" ]; } \
    && ok "(22d) an explicit --limit=40 beats the byte band: 40 rows and the --limit page as next=" \
    || no "(22d) --limit=40 on band121: rows=$( bandRows "$L121" ) $TL121"
O121="$( rb --callers=band121Hub --offset=40 )"; TO121="$( rootTag "$O121" callers )"
{ [ "$( bandRows "$O121" )" = 81 ] && [ "$( attr has_more "$TO121" )" = 0 ] && [ "$( attr next "$TO121" )" = "--uses=band121Hub" ]; } \
    && ok "(22e) --offset=40 inside the band serves the remaining 81 rows, has_more=0, next= the uses verb" \
    || no "(22e) --offset=40 on band121: rows=$( bandRows "$O121" ) $TO121"
# (23) near-miss: the same shape past the band. band51Hub (51 rows, ~18 KB) is arm (16)'s premise: it must still cap at 40
# with the page next= — a row-count-only rule (any total up to 533) would serve it whole.
{ [ "$( bandRows "$A51" )" = 40 ] && [ "$( attr capped "$T51" )" = 1 ]; } \
    && ok "(23) a 51-caller list whose rows exceed the byte band still caps at 40 (the band reads bytes, not the row count)" \
    || no "(23) band51Hub past the byte band served $( bandRows "$A51" ) rows"
F55="$( rb --callees=fanOut55 )"; TF55="$( rootTag "$F55" callees )"
{ [ "$( bandRows "$F55" )" = 40 ] && [ "$( attr capped "$TF55" )" = 1 ] && [ "$( attr next "$TF55" )" = "--callees=fanOut55 --offset=40" ] \
  && [ "$( attr expand_next "$TF55" )" = "--expand=fanOut55" ]; } \
    && ok "(24) a capped --callees page (40 of 55; the byte band is callers-only) names the next page as next=, expand as expand_next=" \
    || no "(24) callees 55: rows=$( bandRows "$F55" ) $TF55"
P55="$( rb --callees=fanOut55 --offset=40 )"; TP55="$( rootTag "$P55" callees )"
{ [ "$( bandRows "$P55" )" = 15 ] && [ "$( attr next "$TP55" )" = "--expand=fanOut55" ] && [ -z "$( attr expand_next "$TP55" )" ]; } \
    && ok "(24b) the pasted callees page serves the last 15 rows and its next= is expand again (no expand_next=)" \
    || no "(24b) callees page 2: rows=$( bandRows "$P55" ) $TP55"
J55N="$( rb --callees=fanOut55 --json | grep -oE '"next":"[^"]*","expand_next":"[^"]*"' | head -1 )"
CF55="$( rootTag "$( rb --callees=fanOut55 --format=columnar )" callees )"
{ [ "$J55N" = '"next":"--callees=fanOut55 --json --offset=40","expand_next":"--expand=fanOut55"' ] \
  && [ "$( attr next "$CF55" )" = "--callees=fanOut55 --format=columnar --offset=40" ]; } \
    && ok "(24c) --json and --format=columnar callees pages keep their form in next= (expand_next beside it)" \
    || no "(24c) callees json [${J55N:-none}] columnar next=$( attr next "$CF55" )"
L45F="$( rb --callees=fanOut45 --legend=full )"
{ [ "$( bandRows "$L45F" )" = 45 ] && ! printf '%s' "$L45F" | grep -q 'expand_next='; } \
    && ok "(24d) an uncut callees answer (45, the row band) keeps next= expand and carries no expand_next= anywhere, legend included" \
    || no "(24d) callees 45 grew expand_next"
LF55="$( rb --callees=fanOut55 --legend=full )"
{ printf '%s' "$LF55" | grep -q 'expand_next= is expand on this selector' && printf '%s' "$F55" | grep -q 'expand_next=: expand on this selector'; } \
    && ok "(24e) the capped callees page defines expand_next= in its full and compact legends" \
    || no "(24e) expand_next= undefined in the capped callees legend"
if command -v xmllint >/dev/null 2>&1; then
    { printf '%s' "$LF55" | xmllint --noout - 2>/dev/null; } && ok "(24f) the --legend=full capped callees page is well-formed XML (no double hyphen in the new sentence)" \
        || no "(24f) the --legend=full capped callees page is not well-formed"
else
    printf '  SKIP  (24f) xmllint not installed\n'
fi
MC="$( python3 - "$BIN" "$BB" <<'PYMC'
import json, subprocess, sys, threading
p = subprocess.Popen( [ sys.argv[1], sys.argv[2], "--mcp" ], stdin = subprocess.PIPE, stdout = subprocess.PIPE, stderr = subprocess.DEVNULL )
watchdog = threading.Timer( 300, p.kill ); watchdog.daemon = True; watchdog.start()
def tool( n, name, args ):
    p.stdin.write( ( json.dumps( { "jsonrpc": "2.0", "id": n, "method": "tools/call", "params": { "name": name, "arguments": args } } ) + "\n" ).encode() )
    p.stdin.flush()
    return json.loads( json.loads( p.stdout.readline() )[ "result" ][ "content" ][ 0 ][ "text" ] )
r = tool( 1, "find_referencing_symbols", { "symbol": "band121Hub" } )
f = tool( 2, "find_symbol", { "symbol": "band121Hub" } )
c = tool( 3, "find_symbol", { "symbol": "fanOut55" } )
p.stdin.close(); p.wait( 20 )
print( "R121 %d %s %s" % ( len( r[ "calledBy" ] ), r.get( "capped" ), r.get( "next" ) ) )
print( "F121 %d %s" % ( len( f[ "calledBy" ] ), "calledBy_total" in f ) )
print( "C55 %d %s %s|%s" % ( len( c[ "calls" ] ), c.get( "capped" ), c.get( "next" ), c.get( "expand_next" ) ) )
PYMC
)"
[ "$( printf '%s\n' "$MC" | sed -n 's/^R121 //p' )" = "121 None --uses=band121Hub" ] \
    && ok "(25) MCP find_referencing_symbols serves the 121 banded callers uncut, next the uses verb (CLI parity)" \
    || no "(25) MCP band121: $( printf '%s\n' "$MC" | sed -n 's/^R121 //p' )"
[ "$( printf '%s\n' "$MC" | sed -n 's/^F121 //p' )" = "121 False" ] \
    && ok "(25b) MCP find_symbol's calledBy array takes the byte band too (121 rows, no cut keys)" \
    || no "(25b) find_symbol calledBy band121: $( printf '%s\n' "$MC" | sed -n 's/^F121 //p' )"
[ "$( printf '%s\n' "$MC" | sed -n 's/^C55 //p' )" = "40 True --callees=fanOut55 --offset=40|--expand=fanOut55" ] \
    && ok "(25c) MCP find_symbol's capped calls array names the callees page as next, expand as expand_next (CLI parity)" \
    || no "(25c) MCP callees 55: $( printf '%s\n' "$MC" | sed -n 's/^C55 //p' )"

echo "=== (26)-(27) what the C2 byte estimate counts: sites_at= and the XML escaping of n=/p= (fix round 1, rv-callers-band2 N1/N2) ==="
# rowBytesOf: the bytes of the <s> rows exactly as printed (the band bounds these, not the root or the legend).
rowBytesOf(){ printf '%s' "$1" | grep -oE '<s t="[^"]*" n="[^>]*/>' | tr -d '\n' | wc -c | tr -d ' '; }
S100="$( rb --callers=sitesHub --limit=100000 )"; TS100="$( rootTag "$S100" callers )"
SB100="$( printf '%s' "$S100" | grep -oE '<s t="[^"]*" n="[^>]*/>' | sed -E 's/ sites_at="[^"]*"//; s/ sites_total="[^"]*"//' | tr -d '\n' | wc -c | tr -d ' ' )"
{ [ "$( attr count "$TS100" )" = 150 ] && [ "$SB100" -lt 8000 ] && [ "$( rowBytesOf "$S100" )" -gt 16000 ] \
  && printf '%s' "$S100" | grep -q 'n="sc000" p="c dir/s100.c:[0-9]*" sites_at="[0-9]* [0-9]* [0-9]'; } \
    && ok "(26) premise: sitesHub's 150 rows are $SB100 B bare and $( rowBytesOf "$S100" ) B with their sites_at= lists (the band sits between)" \
    || no "(26) premise moved: count=$( attr count "$TS100" ) bare=$SB100 full=$( rowBytesOf "$S100" )"
D100="$( rb --callers=sitesHub )"; TD100="$( rootTag "$D100" callers )"
{ [ "$( bandRows "$D100" )" = 40 ] && [ "$( attr capped "$TD100" )" = 1 ] && [ "$( attr next "$TD100" )" = "--callers=sitesHub --offset=40" ]; } \
    && ok "(26b) the estimate counts sites_at=: sitesHub (bare rows fit, rows with sites do not) still pages at 40, next= the page" \
    || no "(26b) sitesHub served $( bandRows "$D100" ) rows: the estimate dropped sites_at= ($TD100)"
E200="$( rb --callers=escHub --limit=100000 )"; TE200="$( rootTag "$E200" callers )"
EU200="$( printf '%s' "$E200" | grep -oE '<s t="[^"]*" n="[^>]*/>' | sed -e 's/&lt;/</g; s/&gt;/>/g' | tr -d '\n' | wc -c | tr -d ' ' )"
{ [ "$( attr count "$TE200" )" = 240 ] && [ "$EU200" -le 16000 ] && [ "$( rowBytesOf "$E200" )" -gt 16000 ] \
  && printf '%s' "$E200" | grep -q 'n="&lt;file-scope&gt;" p="esc/e000.py:'; } \
    && ok "(27) premise: escHub's 240 <file-scope> rows are $( rowBytesOf "$E200" ) B as printed, $EU200 B unescaped (the band sits between)" \
    || no "(27) premise moved: count=$( attr count "$TE200" ) printed=$( rowBytesOf "$E200" ) unescaped=$EU200"
DE200="$( rb --callers=escHub )"; TDE200="$( rootTag "$DE200" callers )"
{ [ "$( bandRows "$DE200" )" = 40 ] && [ "$( attr capped "$TDE200" )" = 1 ] && [ "$( attr next "$TDE200" )" = "--callers=escHub --offset=40" ]; } \
    && ok "(27b) the estimate counts the escaping: escHub (fits unescaped, not as printed) pages at 40, next= the page" \
    || no "(27b) escHub served $( bandRows "$DE200" ) rows: the estimate read n=/p= unescaped ($TDE200)"

echo
[ "$fail" = 0 ] && { echo "neighbourcapcheck: PASS"; exit 0; } || { echo "neighbourcapcheck: FAIL"; exit 1; }
