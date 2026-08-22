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
ok(){ printf '  PASS  %s\n' "$*"; }
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
# 60 TEST callers
with open( os.path.join( d, "tests", "test_hub.py" ), "w" ) as fh:
    for i in range( 60 ):
        fh.write( "def test_hub_%02d( ):\n    assert neighbourHubFn( %d, 1 )\n\n" % ( i, i ) )
PY

rw(){ "$BIN" "$SB" --no-cache "$@" 2>/dev/null; }
rows(){ printf '%s' "$1" | grep -oE '<s t="[^"]*" n="[^"]*" p="[^"]*"' ; }
rowCount(){ printf '%s' "$1" | grep -o "<$2 " | wc -l | tr -d ' '; }

CAP_CALL=40      # kCallHierarchyRowCap — the number --impact has used since §P8; one family, one default
CAP_USES=100     # kUseSiteRowCap — use SITES are the unit --grep caps at 100, not --impact's symbol rows

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (0) presence guard: more neighbours than the cap, and source sorts LAST by path ==="
# ═══════════════════════════════════════════════════════════════════════════
FULL="$( rw --callers=neighbourHubFn --limit=500 )"
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
DEF="$( rw --callers=neighbourHubFn )"
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
PAGE2="$( rw --callers=neighbourHubFn --limit=10 --offset=10 )"
p2_rows="$( rowCount "$PAGE2" s )"
p2_next="$( attr next_offset "$PAGE2" )"
p2_more="$( attr has_more "$PAGE2" )"
if [ "$p2_rows" = "10" ] && [ "$p2_next" = "20" ] && [ "$p2_more" = "1" ]; then
    ok "(4b) --limit=10 --offset=10 serves 10 rows and reports next_offset=20 has_more=1 (a paging loop terminates)"
else
    no "(4b) paging is wrong: rows=$p2_rows next_offset=$p2_next has_more=$p2_more"
fi
# the page seam is exact — page 2 must be the rows the full list holds at [10,20)
if [ "$( rows "$PAGE2" | head -1 )" = "$( rows "$FULL" | sed -n '11p' )" ]; then
    ok "(4c) the page seam is exact: page 2 starts at the full list's row 11"
else
    no "(4c) the page seam drifted: page2[0]=$( rows "$PAGE2" | head -1 ) fullList[10]=$( rows "$FULL" | sed -n '11p' )"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (5) inert under the cap: an uncapped, unpaged answer says nothing ==="
# ═══════════════════════════════════════════════════════════════════════════
SMALL="$( rw --callers=neighbourHubCallee )"
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
CE="$( rw --callees=neighbourHubCaller )"
printf '%s' "$CE" | grep -q '<callees ' \
    && ok "(6) --callees still answers" \
    || no "(6) --callees stopped answering"
CE_CAP="$( rw --callees=neighbourHubCaller --limit=1 )"
if [ "$( rowCount "$CE_CAP" s )" = "1" ] && [ "$( attr capped "$CE_CAP" )" = "1" ]; then
    ok "(6b) --callees windows and discloses exactly as --callers does"
else
    no "(6b) --callees paging diverged: rows=$( rowCount "$CE_CAP" s ) capped=$( attr capped "$CE_CAP" )"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (7) --uses: same ordering, its own cap ==="
# ═══════════════════════════════════════════════════════════════════════════
U_FULL="$( rw --uses=neighbourHubFn --limit=500 )"
u_count="$( attr count "$U_FULL" )"
U_DEF="$( rw --uses=neighbourHubFn )"
u_rows="$( rowCount "$U_DEF" u )"
# the fixture has 63 call sites + 1 def-site-adjacent row or so — under 100, so the cap must NOT fire here,
# and that is the arm: --uses keeps its own unit (sites), so the SYMBOL cap must not leak onto it.
if [ "${u_count:-0}" -lt "$CAP_USES" ]; then
    [ "$u_rows" = "$u_count" ] \
        && ok "(7) --uses has $u_count sites, under its own $CAP_USES cap, and serves all of them (the symbol cap did not leak onto the site unit)" \
        || no "(7) --uses served $u_rows of $u_count sites while under its own cap"
else
    [ "$u_rows" = "$CAP_USES" ] && ok "(7) --uses capped at $CAP_USES" || no "(7) --uses expected $CAP_USES rows, got $u_rows"
fi
# ordering: --uses rows carry p= only, so assert the source sites lead
u_first="$( printf '%s' "$U_DEF" | grep -oE '<u role="[^"]*" p="[^"]*"' | head -1 )"
printf '%s' "$u_first" | grep -q 'zsrc/' \
    && ok "(7b) --uses leads with the source-tier site, against the path order" \
    || no "(7b) --uses is still in plain path order: first row is $u_first"
U_CAP="$( rw --uses=neighbourHubFn --limit=5 )"
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
command -v python3 >/dev/null 2>&1 && { printf '%s' "$JS" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null && ok "(8b) the capped --json answer parses" || no "(8b) the capped --json answer is not valid JSON"; }
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
    [ "$r1" = "$r2" ] && ok "(10) $v is byte-identical across runs" || no "(10) $v is nondeterministic"
    if command -v xmllint >/dev/null 2>&1; then
        printf '%s' "$r1" | xmllint --noout - 2>/dev/null && ok "(10b) $v is well-formed XML" || no "(10b) $v is not well-formed XML"
    fi
done

echo
[ "$fail" = 0 ] && { echo "neighbourcapcheck: PASS"; exit 0; } || { echo "neighbourcapcheck: FAIL"; exit 1; }
