#!/usr/bin/env bash
# forrankordercheck.sh — P7 (terminality round A, 2026-09-05, lane R): the --for lens serves its ranked rows
# IN RANK ORDER, on every dialect, and every row still names its file.
#
# WHAT WAS WRONG. packSignatures bucketed the kept head BY FILE (files in first-seen-rank order, rows in
# SOURCE order inside each <f p=…> wrapper), so the emitted r= sequence on this repo read
# `15 8 5 2 7 1 6 32 20 3 33 4 …` — the r=1 row sat sixth, under a file whose best row was r=15. An agent
# reads a bundle top-down; the first row is the one it opens. METHODOLOGY §9 #1: terminality is the
# objective — the first row must be the terminating one. The old legend even said "sort by r= for true
# ranker order", i.e. it handed the reader a sort the tool should have done.
#
# THE CONTRACT THIS PINS (each arm was run RED against the pre-fix binary — the mutation control in arm 5
# proves the checker itself has teeth):
#   (1) r= is STRICTLY INCREASING down the bundle on CLI --for, --for --legend=compact, --for --json (the
#       "sigs" array's row order) and MCP `for` (driven over stdio), on this repo and on three git-less
#       fixture corpora with mixed languages (py/cpp/md, py/cpp FFI, cpp/py/md hostile).
#   (2) every ranked row carries its file: p= on each <d> (and the JSON row's "p") — the <f> wrapper is
#       gone, so the row itself must say where it lives (the --expand=FILE:NAME chain key needs it).
#   (3) byte growth ≤ 4% against the sizes fixed in docs/EVALS.md ("Terminality round A", lane R): the ten
#       reference queries on this repo (full legend, sizes at 8eb669ff) and nine fixture bundles measured on
#       the pre-fix binary (d5ac29a7, git-less copies so no at= stamp). p= costs ~20 B/row, a wrapper saved
#       ~25–40 B/file; the ten repo bundles are CEILING-BOUND (est_tokens ≈ 4000), so growth there shows up
#       as rows, not bytes — the arm prints shown= beside the bytes for that reason.
#   (4) file notes survive the wrapper's removal: a note on a FILE rides the file's best-ranked live row as a
#       <note … p="FILE"> child (p= names the target, so it cannot be misread as the symbol's note); the
#       JSON twin carries it as that row's "file_notes" array. Symbol notes are unchanged.
#   (5) mutation control: the checker MUST reject a canned pre-fix (file-grouped) XML bundle and a canned
#       pre-fix (file-grouped) JSON bundle — a gate that cannot go red is worse than none.
#   (6) shown= on a capped <sigs> equals the number of <d> rows printed; two runs are byte-identical;
#       full and compact bundles are xmllint-clean.
#
# Usage:  bash test/forrankordercheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/forrankordercheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used (knob-honesty-068 N7).
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
export RIPWIRE_TESTLIB="$ROOT/test/lib"   # softbudget.py set_prefix: the head round-robin set-prefix arms (lane hrr)
unset RIPWIRE_NO_HEAD_RR                  # lane hrr: the reorder is ON here unless a twin sets it
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forrankordercheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
cd "$ROOT"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── the checker: one script, two dialects. Prints "OK n=N seq=…" and exits 0 when the ranked rows are in
# strictly increasing r= order AND every row carries its file; prints "FAIL …" and exits 1 otherwise. It
# understands BOTH the pre-fix file-grouped shape and the flat shape, so it can measure the old binary
# (that is what makes the RED run and the arm-5 mutation control possible).
cat > "$TMP/rows.py" <<'PY'
import json, re, sys
mode = sys.argv[1]
s = sys.stdin.read()
rows = []   # (r, p) in DOCUMENT order
if mode == "xml":
    m = re.search( r'<sigs[^>]*>(.*?)</sigs>', s, re.S )
    if not m:
        print( "FAIL no <sigs> block" ); sys.exit( 1 )
    for d in re.finditer( r'<d ([^>]*)>', m.group( 1 ) ):
        a = d.group( 1 )
        r = re.search( r'\br="([0-9]+)"', a )
        p = re.search( r'\bp="([^"]*)"', a )
        rows.append( ( int( r.group( 1 ) ) if r else None, p.group( 1 ) if p else None ) )
else:
    d = json.loads( s )
    sigs = d.get( "sigs", d.get( "ranking" ) )
    if sigs is None:
        print( "FAIL no sigs/ranking array" ); sys.exit( 1 )
    for item in sigs:
        if "symbols" in item:                      # pre-fix file-grouped shape: rows carry no p of their own
            for x in item[ "symbols" ]:
                rows.append( ( x.get( "r" ), x.get( "p" ) ) )
        else:
            rows.append( ( item.get( "r" ), item.get( "p" ) ) )
if not rows:
    print( "FAIL zero ranked rows (this query measured nothing)" ); sys.exit( 1 )
seq = [ r for r, _ in rows ]
if any( r is None for r in seq ):
    print( "FAIL a ranked row carries no r=: seq=%s" % seq ); sys.exit( 1 )
if any( b <= a for a, b in zip( seq, seq[1:] ) ):
    print( "FAIL r= not strictly increasing: seq=%s" % " ".join( map( str, seq ) ) ); sys.exit( 1 )
missing = sum( 1 for _, p in rows if not p )
if missing:
    print( "FAIL %d of %d rows carry no p= (file): seq=%s" % ( missing, len( rows ), " ".join( map( str, seq ) ) ) ); sys.exit( 1 )
print( "OK n=%d seq=%s" % ( len( rows ), " ".join( map( str, seq ) ) ) )
PY
cat > "$TMP/mcptext.py" <<'PY'
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: d = json.loads( line )
    except Exception: continue
    c = d.get( "result", {} ).get( "content" )
    if c: print( c[0].get( "text", "" ) )
PY
check(){ python3 "$TMP/rows.py" "$1"; }   # $1 = xml|json ; stdin = the bundle
mcp_for(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' \
                  "$1" "$2" | "$BIN" --mcp 2>/dev/null | python3 "$TMP/mcptext.py"; }

# ── corpora: this repo + three git-less fixture copies (no at= stamp, so sizes are reproducible) ──────────
for fx in fixture ffifix hostilefix; do cp -R "$ROOT/test/$fx" "$TMP/$fx"; done

# the ten reference queries, sizes registered in docs/EVALS.md ("Terminality round A", lane R; 8eb669ff)
REPO_Q=( "rank graph teleport" "compact legend rewrite" "edit receipt post-check" "substitution meter hook"
         "pagerank power iteration" "tree-sitter ingest cache" "merge scout conflict" "quality delta acks"
         "MCP manifest tools list" "test gate affected tests" )
# q5 RE-PINNED 2026-09-10 (cap follow-up integration), the OTHER NINE DELIBERATELY LEFT at their @8eb669ff bases.
# q5 crossed 4% by +106 B of Lane B1 disclosure on a query where the doc-mention cap fires (attributed: the
# 633a1d23 binary on this same tree gives 9,649 B, this binary 9,755 B), so its base follows the output change.
# q3/q9 sit at +3.6% from corpus growth alone with NO tool change behind it — that drift is the evidence that
# arm (3) measures the live repository and needs a frozen fixture; re-basing them would erase the evidence and
# leave the problem. Expect them to trip on ordinary growth; when they do, the fix is the fixture, not a re-pin.
# RE-PINNED AGAIN 2026-09-13 (lane for-widen, owner decision 22:55: coverage= is PRESENT-ONLY, thin answers only): all ten
# repo answers are CONFIDENT on this tree, so they carry no coverage= and no clause and read within a few bytes of the base
# build again (q2 +16 B, q7 +1 B: the r=1 row's next= spelling; q10 9861 on the tree as it stands, its head having moved
# on this lane's own source text). The nine fixture bundles below: the seven THIN ones keep the gauge (+312..+364 B), the
# two confident ones (ffifix/geometry, hostilefix/call) read exactly the base.
# RE-PINNED 2026-09-12 (lane for-widen, L-W): all ten bases follow an OUTPUT change, the q5 precedent above. Measured on this
# tree (the lane's own new source, src/forpage.h, is part of the corpus — q10's head moved +241 B on that text alone) with
# the lane's base build (1cf3086e): 10134 10013 10080 10102 9470 9397 10008 10070 9966 10139 — q1..q4/q7..q10 had already
# drifted +2.5%..+3.7% on corpus growth alone (the frozen-fixture note above still stands); with the lane's build:
# 10463 10337 10409 10431 9799 9726 10337 10399 10294 10468, i.e. +324..+329 B on every query = the coverage= root fact,
# its legend clause (kForCoverageLegend, forpage.h) and the r=1 row's widening next= on a thin answer. Nothing else moved
# (routecheck/anchorcheck's goldens re-pinned the same day with every other byte proven identical).
# q5 RE-PINNED 2026-09-13 (merge of lane/sc-legend and lane/for-widen), the q5 precedent above, third time on the same
# query: 9,470 -> 9,880 B (+4.33%). ATTRIBUTED FOUR WAYS, which is what the precedent requires — main tree / main binary
# 9,464 B, LANE tree / main binary 9,470 B (so corpus drift is +6 B, not the cause), main tree / lane binary 9,875 B,
# lane tree / lane binary 9,880 B: the whole +410 B is the TOOL, and it is +410 B of ANSWER. Main serves this query
# shown="20" of 40 ranked rows; this build serves shown="25". The sc= rows are ~20 B shorter than the id= rows they
# replace, so the byte-shaped <sigs> section fits five more signature rows, and the legend that grew 154 B (the sc=
# rule, the route= code's reading and the merged-callee reading) is paid for several times over in rows. The other
# nine stay at their for-widen bases: -1.11%, +0.36%, -0.45%, +1.54%, +0.02%, +1.66%, +0.18%, -0.56%, +2.30%.
# q6 q7 q8 RE-PINNED 2026-10-15 (lane forbudget-soft FIX1, review rv-forbudget-soft N2; rule 4, a stated by-design break — the 4% rule
# itself is unchanged): 9397 -> 9947, 10009 -> 10496, 10070 -> 10605 B, i.e. the answer LESS its past-target rows, its hop bytes
# over the old 1,000 B allowance, its tail page rows and the tail clause growth (the allowances below), measured on this lane's
# build at this tree (+5.85% / +4.87% / +5.31% over the old pins). The review measured the same growth on the base tree (+6.42% /
# +4.81% / +5.25%) and attributed it to the lane: decision D-3 (the default <hops> serves every hop row — the part inside the old
# 1,000 B allowance is not subtracted) and the default regime's header clauses (budget_bytes= read as a target, past_target=).
# The other seven are unmoved. Train 28 re-measures attrib-multidef's --for piece against these pins.
# FIX2 N2 (review rv-forbudget-soft-fix1 N-a): those three pins were read on a +dirty tree, whose root at= stamp carries 6 B
# more than a clean one (a clean tree read -0.06% on each). Re-taken from a CLEAN committed tree (the lane head, no local edits)
# with this lane's build: 9947 -> 9941, 10496 -> 10490, 10605 -> 10599 B. The by-design reason above is unchanged.
REPO_BASE=( 10134 10458 10642 10102 9880 9941 10490 10599 9966 10379 )
# q2 RE-PINNED 2026-10-16 (train 28, owner ruling; rule 4 by-design break, the 26c q3 precedent): 10029 -> 10458 B net of
# past-target/hop/tail-page rows (+4.28% on the merged stack), an OUTPUT change of two signed lanes that each stay inside the
# 4% alone. Measured on the merged tree: for-body-slot's binary (forbudget-soft + the owner body) 10,368 B (+3.38%); the
# attrib-multidef merge adds +90 B — the compact split reading "; c prov=split: ..." in the header and prov="split" on the
# two <c> rows of a real split arm (an intended disclosure). q6-q8 are not touched (+0.84% / +0.99% / +3.12% on their pins).
# q3 RE-PINNED 2026-10-10 (train 26c): 10080 -> 10642 B (+5.58% on the merged stack), an OUTPUT change of two signed lanes
# that each stay inside the 4% alone: lego-charge serves two more signature rows (25 -> 27 of 40) because <lego>/<compose>
# are charged to the <sigs> budget at the size they are SERVED (a collapsing section its stub), and owner-hop adds the
# question's owner hop row with its callees. Measured on this tree: the 26c parent 9,716 B / 25 rows, the seven phase-A lanes
# 10,198 B / 25 rows, the lego-charge lane alone 10,356 B / 27 rows, the merged binary 10,642 B / 27 rows. The other nine stay
# at their bases: +0.25%, -2.64%, -7.65%, +2.00%, +1.86%, -2.25%, -1.50%, -2.88%, -6.06%.
# q10 RE-PINNED 2026-09-19 (lane/r1-for-sections-stub, L2 round-1 lever B1): 9861 -> 10379 B (+5.25%), an
# OUTPUT change, the q5 precedent's pattern. This query's ranked head reaches an interface with
# implementors — the ONLY one of the ten reference queries that does — so it is the one query in this
# fixed set whose --for answer now carries the present-only kForSectionStubLegend clause (serialize.h)
# beside its collapsed <lego> stub. The other nine are unaffected (unchanged bytes on this same binary,
# confirming the clause really is present-only, not a fixed per-call cost).

# ── (1)+(2) rank order + p= on every row, four dialects ───────────────────────────────────────────────────
order_fail=0
run_dialects(){   # $1 = corpus dir (as passed to the binary), $2 = query, $3 = label, $4 = with-mcp (1/0)
    local c="$1" q="$2" label="$3" mcp="$4" v
    v="$( "$BIN" "$c" --for="$q" 2>/dev/null | check xml )"      || { no "(1/2) $label full: $v"; order_fail=1; }
    v="$( "$BIN" "$c" --for="$q" --legend=compact 2>/dev/null | check xml )" || { no "(1/2) $label compact: $v"; order_fail=1; }
    v="$( "$BIN" "$c" --for="$q" --json 2>/dev/null | check json )" || { no "(1/2) $label json: $v"; order_fail=1; }
    if [ "$mcp" = 1 ]; then
        v="$( mcp_for "$c" "$q" | check xml )" || { no "(1/2) $label MCP for: $v"; order_fail=1; }
    fi
}
i=0
for q in "${REPO_Q[@]}"; do
    i=$(( i + 1 ))
    run_dialects . "$q" "repo q$i '$q'" "$( [ "$i" -le 3 ] && echo 1 || echo 0 )"
done
FX_Q=( "geometry area of a shape" "call a native function from python" "parse the config and load it" )
( cd "$TMP" && for fx in fixture ffifix hostilefix; do
    for q in "${FX_Q[@]}"; do
        # a fixture/query pair with no ranked rows measures nothing — skip it (never a false PASS)
        if [ "$( "$BIN" "$fx" --for="$q" 2>/dev/null | grep -c '<d ' )" = 0 ]; then continue; fi
        run_dialects "$fx" "$q" "$fx '$q'" 1
    done
  done; exit "$order_fail" ) || order_fail=1
[ "$order_fail" = 0 ] && ok "(1)+(2) r= strictly increasing and p= on every ranked row: 10 repo queries × {full, compact, json} (+MCP on 3) and 3 fixtures × 3 queries × 4 dialects"

# ── (3) byte growth ≤ 4% against the registered sizes ─────────────────────────────────────────────────────
growth_fail=0
# body-fold (train 31; rule 4, by design — the FOLD C precedent): a compact answer now ends with <fold kind="bodies">, the top ranked
# bodies appended after the unchanged answer (forbodyfoldcheck (F5) pins that nothing before it moved). The band reads the answer
# WITHOUT those additions: the fold element, its legend clause, the hop-calls next= clause and the <sigs> continuation pair
# (sigs_next= renamed from next=, next= the first skip). fold_exempt prints their bytes; nothing else is exempt.
# member-names (train 32; rule 4, by design, the same precedent): the owner rows' mem=/mem_more= names and their legend clause ride
# on top of the chosen rows (formembernamescheck (G1)/(G2): the <d> rows are the names-off rows one for one) — exempt likewise.
# FIX1: the regexes spell the double quote \x22 — a bare " inside this single-quoted python made line 7 a SyntaxError, so
# fold_exempt printed nothing, the $(( now - )) below aborted the ledger loops and (3) PASSED having checked no query; a
# failed exemption read is now a FAIL (exempt_ok), never an empty operand.
fold_exempt(){ python3 -c '
import re, sys
s = sys.stdin.read(); n = 0
f = re.search( r"<fold .*?</fold>", s, re.S ); n += len( f.group( 0 ).encode() ) if f else 0
c = re.search( r"; fold kind=bodies:.*?sigs_next= the signatures-only re-call", s, re.S ); n += len( c.group( 0 ).encode() ) if c else 0
h = re.search( r"; (h calls capped=1 next= the call listing every callee|a hop row.s cut calls listing \(capped=1\) carries next=, the call that lists every callee)", s ); n += len( h.group( 0 ).encode() ) if h else 0
# FIX1 N5: only a RANKED hop row cut listing (an <h> without qword=); an owner row next= predates the fold and is not exempt
n += sum( len( x.encode() ) for x in re.findall( r" next=\x22--callees=[^\x22]*\x22", "".join( c for h, c in re.findall( r"<h ([^>]*)><calls ([^>]*)>", s ) if " qword=" not in " " + h ) ) )
# head round-robin (lane hrr, train 31): its disclosure is a reorder reading, uncharged like docs_after_code= — the rows are the
# same rows (forheadrrcheck owns that contract), so the band reads the answer without the attribute and its legend clause
r = re.search( r" files_first=\x22[0-9]+\x22", s ); n += len( r.group( 0 ).encode() ) if r else 0
r = re.search( r" \[files_first=N:[^\]]*\]", s ); n += len( r.group( 0 ).encode() ) if r else 0
t = re.search( r"<sigs\b[^>]*>", s )
if t and " sigs_next=\x22" in t.group( 0 ):
    n += 5 + sum( len( x.encode() ) for x in re.findall( r" next=\x22[^\x22]*\x22", t.group( 0 ) ) )
    n += len( "[sigs sigs_next=: one" ) - len( "[sigs next=: one" ) if "[sigs sigs_next=: one" in s else 0
elif t:
    n += sum( len( x.encode() ) for x in re.findall( r" next=\x22--expand=[^\x22]*\x22", t.group( 0 ) ) )
n += sum( len( x.group( 0 ).encode() ) for x in re.finditer( r" mem=\x22[^\x22]*\x22( mem_more=\x22\d+\x22)?", s ) )
c = re.search( r"; (d mem=|mem= on an owner d row:)[^;]*?mem_more= (names cut|the member names not listed)", s ); n += len( c.group( 0 ).encode() ) if c else 0
# K-WRONGSYM: the <syms> block (legend comment + rows) is a present-only, separately allowanced append after the ranked answer (outside est_tokens);
# the band reads the answer without it, as it reads the body-fold additions above
r = re.search( r"<!-- (ripwire for )?syms:.*?-->(<syms .*?</syms>|<syms [^>]*/>)", s, re.S ); n += len( r.group( 0 ).encode() ) if r else 0
print( n )'; }
# exempt_ok N: in THIS shell (never inside a $( ), where no()'s fail=1 would be lost) — a non-number is a FAIL and counts 0
exempt_ok(){ case "$1" in ''|*[!0-9]*) no "(3) fold_exempt could not read an answer (got '$1')"; growth_fail=1; return 1;; esac; return 0; }
echo "  ledger: the ten reference queries (this repo, full legend) — base bytes @8eb669ff (q5 @cap-followup-2026-09-10) → now, shown=/total="
i=0
for q in "${REPO_Q[@]}"; do
    base="${REPO_BASE[$i]}"; i=$(( i + 1 ))
    out="$( "$BIN" . --for="$q" 2>/dev/null )"
    now="$( printf '%s' "$out" | wc -c | tr -d ' ' )"
    ex="$( printf '%s' "$out" | fold_exempt )"; exempt_ok "$ex" || ex=0
    now=$(( now - ex ))   # body-fold: the band reads the answer before its fold additions
    marker="$( printf '%s' "$out" | grep -o '<sigs[^>]*>' | head -1 )"
    # forbudget-soft (stop when complete; PROCESS rule 5's stair-step target): rows served past the 7.5 KB target are disclosed
    # (<sigs past_target="K">: the last K rows) and are what the answer needs, so the band applies to the answer WITHOUT them —
    # every byte over 4% must be a disclosed past-target row, or a <hops> row past the old 1,000 B allowance (decision D-3:
    # the default serves every hop row), or — forbudget-soft round C, FOLD C (owner decision 2026-10-14) — a tail PAGE row
    # (`<t p= sym=/>`: page 0 of the --for file page now rides the answer), never anything else
    past="$( printf '%s' "$out" | python3 -c '
import re, sys
s = sys.stdin.read(); m = re.search( r"<sigs\b([^>]*)>(.*?)</sigs>", s, re.S )
k = re.search( r"past_target=\"([0-9]+)\"", m.group( 1 ) ) if m else None
rows = sorted( ( int( re.search( r"\br=\"([0-9]+)\"", d.group( 1 ) ).group( 1 ) ), len( d.group( 0 ).encode() ) )
               for d in re.finditer( r"<d ([^>]*)>.*?</d>", m.group( 2 ) if m else "", re.S ) )
past = sum( b for _, b in rows[ len( rows ) - int( k.group( 1 ) ): ] ) if k else 0
h = re.search( r"<hops\b.*?</hops>", s, re.S )      # D-3: the compact <hops> is no longer cut at its 1,000 B allowance
page = sum( len( t.encode() ) for t in re.findall( r"<t p=\"[^\"]*\" sym=\"[^\"]*\"/>", s ) )   # FOLD C: the tail page rows
for pat, was in ( ( r"; tail: [^\]]*?budget-trimmed row\)", 391 ), ( r"; t p= file outside sigs \(weaker\)[^;]*?r= rank \(gap = trimmed\)", 57 ) ):
    lm = re.search( pat, s )                         # …and the growth of the clause that now defines them (full 391 B / compact 57 B before)
    page += max( 0, len( lm.group( 0 ).encode() ) - was ) if lm else 0
# FOR-TAIL-WIDE: the tail walks the file page past row 40, so it prints path-only rows (`<t p=\"…\"/>`, no sym=), the tail p_only= count
# and the walk clause (full or compact); like the sym= page rows above, none of it is answer body the band reads
page += sum( len( t.encode() ) for t in re.findall( r"<t p=\"[^\"]*\"/>", s ) )
page += sum( len( x.encode() ) for x in re.findall( r" p_only=\"[0-9]+\"", s ) )
for pat in ( r"; tail walk: .*?p_only= counts them", r"; t page rows go on to file-page row 160.*?p_only= counts them" ):
    lm = re.search( pat, s ); page += len( lm.group( 0 ).encode() ) if lm else 0
print( past + page + ( max( 0, len( h.group( 0 ).encode() ) - 1000 ) if h else 0 ) )' )"
    pct="$( python3 -c "print( '%+.2f' % ( ( $now - $past - $base ) * 100.0 / $base ) )" )"
    printf '    q%-2d %-28s %5d → %5d - past-target/hops %5d (%s%%)  %s\n' "$i" "'$q'" "$base" "$now" "$past" "$pct" "$marker"
    if [ $(( now - past )) -gt $(( base * 104 / 100 )) ]; then
        no "(3) repo q$i '$q': $now B - $past B past-target/hop rows > 1.04 × $base B"; growth_fail=1
    fi
done
# nine fixture bundles measured on the pre-fix binary (git-less copies; d5ac29a7)
# RE-PINNED 2026-09-12 (lane for-widen, L-W), the nine fixture bundles, same output change as the ten repo queries above:
# measured base build (1cf3086e) → this build: fixture/geometry 2950 → 3299, fixture/call 3126 → 3490, fixture/parse 3349 → 3691, ffifix/geometry 2082 → 2082, ffifix/call 3116 → 3468, ffifix/parse 3525 → 3877, hostilefix/geometry 2834 → 3146, hostilefix/call 2106 → 2106, hostilefix/parse 3002 → 3360 — the coverage= root fact, its clause and the widening next= on a thin answer; on a 2–3.5 KB bundle that is 12–20%,
# which is why the 4% band cannot absorb a root-fact addition on these and the bases follow it (the q5 precedent).
# fixture/geometry RE-PINNED 2026-09-16 (#228, test/rootspellingcheck.sh), the q5 precedent, attributed three ways on a
# git-less copy crawled as this arm crawls it (root typed `fixture`): base build 3,366 B; base build crawled as `.`
# 3,488 B (+6 B is `root="."` against `root="fixture"`, so 3,494 B); this build 3,494 B. The typed root `fixture` matched
# pathTierOf's `fixture/` segment, so every file of the tree was tiered test/bench and its notes.md headings could not
# carry a doc mention; read root-relative they do (doc_mentions="1", r=3/r=4 swap). The other eight bases do not move.
FX_BASE="fixture|geometry area of a shape|3494
fixture|call a native function from python|3510
fixture|parse the config and load it|3711
ffifix|geometry area of a shape|2082
ffifix|call a native function from python|3488
ffifix|parse the config and load it|3897
hostilefix|geometry area of a shape|3166
hostilefix|call a native function from python|2106
hostilefix|parse the config and load it|3380"
echo "  ledger: nine fixture bundles — base bytes @d5ac29a7 → now"
while IFS='|' read -r fx q base; do
    fxout="$( cd "$TMP" && "$BIN" "$fx" --for="$q" 2>/dev/null )"
    ex="$( printf '%s' "$fxout" | fold_exempt )"; exempt_ok "$ex" || ex=0
    now=$(( $( printf '%s' "$fxout" | wc -c | tr -d ' ' ) - ex ))   # body-fold: as above
    pct="$( python3 -c "print( '%+.2f' % ( ( $now - $base ) * 100.0 / $base ) )" )"
    printf '    %-10s %-36s %5d → %5d  (%s%%)\n' "$fx" "'$q'" "$base" "$now" "$pct"
    if [ "$now" -gt $(( base * 104 / 100 )) ]; then
        no "(3) $fx '$q': $now B > 1.04 × $base B"; growth_fail=1
    fi
done <<< "$FX_BASE"
[ "$growth_fail" = 0 ] && ok "(3) byte growth ≤ 4% on the ten reference queries and the nine fixture bundles"

# ── (4) file notes ride the file's best-ranked row, target named ──────────────────────────────────────────
# Same recipe as notescheck.sh: a temp git repo (notes are provenance-stamped), one file note, one symbol note.
WORK="$TMP/notework"; mkdir -p "$WORK/src"
cat > "$WORK/src/a.cpp" <<'EOF'
struct Widget {
    int compute( int x ) { return helper( x ); }
};
int helper( int x ) { return x + 1; }
int lonely( int y ) { return y * 2; }
EOF
( cd "$WORK" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )
nrun(){ ( cd "$WORK" && "$BIN" . --no-cache "$@" 2>/dev/null ); }
FILE_TARGET="$( nrun | grep -oE '<f p="[^"]*a\.cpp"' | head -1 | sed -E 's/<f p="([^"]*)"/\1/' )"
if [ -z "$FILE_TARGET" ]; then
    no "(4) could not discover the a.cpp file path from the map — the note arm measured nothing"
else
    nrun --note-add="$FILE_TARGET: watch the arena lifetime here" >/dev/null
    nrun --note-add="helper: off-by-one lives here" >/dev/null
    NOTE_FOR="$( nrun --for="widget compute helper lonely" )"
    NOTE_JSON="$( nrun --for="widget compute helper lonely" --json )"
    NORM_FILE="${FILE_TARGET#./}"
    # the file note: a <note … p="FILE"> child of a <d> row whose own p= is that file — the first live row of it
    v="$( printf '%s' "$NOTE_FOR" | python3 -c '
import re, sys
s = sys.stdin.read()
m = re.search( r"<sigs[^>]*>(.*?)</sigs>", s, re.S )
body = m.group( 1 ) if m else ""
if "<f " in body:
    print( "FAIL the <f> wrapper is still there (pre-fix shape)" ); sys.exit( 1 )
target = sys.argv[1]
rows = re.findall( r"<d ([^>]*)>(.*?)</d>", body, re.S )
carrier = [ i for i, ( a, inner ) in enumerate( rows ) if "watch the arena lifetime here" in inner ]
if not carrier:
    print( "FAIL the file note surfaces on no <d> row" ); sys.exit( 1 )
i = carrier[0]
a, inner = rows[i]
rowp = re.search( r"\bp=\"([^\"]*)\"", a )
if not rowp or rowp.group( 1 ) != target:
    print( "FAIL the carrier row p=%r is not the note target %r" % ( rowp.group( 1 ) if rowp else None, target ) ); sys.exit( 1 )
if not re.search( r"<note [^>]*\bp=\"" + re.escape( target ) + r"\"[^>]*><!\[CDATA\[watch the arena lifetime here\]\]></note>", inner ):
    print( "FAIL the file note child does not name its target with p=" ); sys.exit( 1 )
earlier = [ j for j in range( i ) if re.search( r"\bp=\"" + re.escape( target ) + r"\"", rows[j][0] ) ]
if earlier:
    print( "FAIL the file note rides row %d but row %d of the same file comes first" % ( i, earlier[0] ) ); sys.exit( 1 )
if not re.search( r"<note (?![^>]*\bp=)[^>]*><!\[CDATA\[off-by-one lives here\]\]></note>", body ):
    print( "FAIL the symbol note lost its shape (it must carry no p=)" ); sys.exit( 1 )
print( "OK" )
' "$NORM_FILE" )" && ok "(4) XML: the file note rides the file's first ranked row as <note p=\"$NORM_FILE\">; the symbol note is unchanged" \
     || { no "(4) XML file note: $v"; printf '%s\n' "$NOTE_FOR" | head -c 900; echo; }
    v="$( printf '%s' "$NOTE_JSON" | python3 -c '
import json, sys
d = json.load( sys.stdin )
target = sys.argv[1]
rows = d[ "sigs" ]
if any( "symbols" in r for r in rows ):
    print( "FAIL grouped JSON shape (pre-fix)" ); sys.exit( 1 )
carriers = [ i for i, r in enumerate( rows ) if any( "watch the arena lifetime here" in n.get( "text", "" ) for n in r.get( "file_notes", [] ) ) ]
if not carriers:
    print( "FAIL no row carries the file note under file_notes" ); sys.exit( 1 )
i = carriers[0]
if rows[i].get( "p" ) != target:
    print( "FAIL carrier row p=%r != %r" % ( rows[i].get( "p" ), target ) ); sys.exit( 1 )
if any( rows[j].get( "p" ) == target for j in range( i ) ):
    print( "FAIL the file note is not on the FIRST row of its file" ); sys.exit( 1 )
if not any( "off-by-one lives here" in n.get( "text", "" ) for r in rows for n in r.get( "notes", [] ) ):
    print( "FAIL the symbol note is missing from the notes array of its row" ); sys.exit( 1 )
print( "OK" )
' "$NORM_FILE" )" && ok "(4) JSON: the file note is the carrier row's file_notes array; the symbol note stays in notes" \
     || { no "(4) JSON file note: $v"; printf '%s\n' "$NOTE_JSON" | head -c 900; echo; }
    if printf '%s' "$NOTE_FOR" | xmllint --noout - 2>/dev/null; then ok "(4) --for with notes is xmllint-clean"; else no "(4) --for with notes is not well-formed"; fi
fi

# ── (5) mutation control: the checker rejects the pre-fix shapes ──────────────────────────────────────────
PREFIX_XML='<ctx><sigs shown="3" total="3"><f p="src/a.h"><d l="1" n="x" r="2">int x()</d><d l="9" n="y" r="1">int y()</d></f><f p="src/b.h"><d l="3" n="z" r="3">int z()</d></f></sigs></ctx>'
PREFIX_JSON='{"sigs":[{"p":"src/a.h","symbols":[{"l":1,"n":"x","r":2,"sig":"int x()"},{"l":9,"n":"y","r":1,"sig":"int y()"}]},{"p":"src/b.h","symbols":[{"l":3,"n":"z","r":3,"sig":"int z()"}]}]}'
FLAT_XML='<ctx><sigs><d l="9" n="y" p="src/a.h" r="1">int y()</d><d l="1" n="x" p="src/a.h" r="2">int x()</d><d l="3" n="z" p="src/b.h" r="3">int z()</d></sigs></ctx>'
if printf '%s' "$PREFIX_XML" | check xml >/dev/null; then no "(5) the checker ACCEPTED a file-grouped XML bundle — no teeth"; else ok "(5) mutation control: the checker rejects the pre-fix file-grouped XML shape"; fi
if printf '%s' "$PREFIX_JSON" | check json >/dev/null; then no "(5) the checker ACCEPTED a file-grouped JSON bundle — no teeth"; else ok "(5) mutation control: the checker rejects the pre-fix file-grouped JSON shape"; fi
if printf '%s' "$FLAT_XML" | check xml >/dev/null; then ok "(5) …and accepts a flat rank-ordered bundle with p= on every row"; else no "(5) the checker rejects the target shape"; fi

# ── (6) shown= consistency, determinism, well-formedness ─────────────────────────────────────────────────
A="$( "$BIN" . --for="rank graph teleport" 2>/dev/null )"
B="$( "$BIN" . --for="rank graph teleport" 2>/dev/null )"
if [ "$A" = "$B" ]; then ok "(6) two runs byte-identical"; else no "(6) --for is not deterministic"; fi
shown="$( printf '%s' "$A" | grep -o '<sigs[^>]*>' | head -1 | grep -o 'shown="[0-9]*"' | tr -dc '0-9' )"
drows="$( printf '%s' "$A" | python3 -c 'import re,sys; s=sys.stdin.read(); m=re.search(r"<sigs[^>]*>(.*?)</sigs>",s,re.S); print(len(re.findall(r"<d ",m.group(1))) if m else -1)' )"
if [ -n "$shown" ]; then
    if [ "$shown" = "$drows" ]; then ok "(6) shown=\"$shown\" equals the $drows <d> rows printed"; else no "(6) shown=\"$shown\" but $drows <d> rows printed"; fi
else
    ok "(6) <sigs> is uncapped on this query (shown= absent by contract)"
fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$A" | xmllint --noout - 2>/dev/null; then ok "(6) full bundle is well-formed"; else no "(6) full bundle is not well-formed"; fi
    if "$BIN" . --for="rank graph teleport" --legend=compact 2>/dev/null | xmllint --noout - 2>/dev/null; then ok "(6) compact bundle is well-formed"; else no "(6) compact bundle is not well-formed"; fi
else
    printf '  SKIP  xmllint (not installed)\n'
fi

# ── (7) the row gate cuts RANK FIRST, and the cut is counted (cut-fix lane A, 2026-09-23) ─────────────────────
# The --pack-budget-bytes gate ran inside the FILE-MAJOR collection walk (files by best rank, rows in source order), so
# it cut in reading order: on this repo at 64 B the old binary served r=7 and r=20 (the rank-1 row's file's first rows in
# SOURCE order) under a bare <sigs>, and at 2000 B r= 1 2 5 6 7 9 19 20 23 27 — interior gaps, no shown=/total=. RED on
# origin/main 60b65f02 for every sub-arm below; the invariant is corpus-independent: the served rows are exactly r=1..S,
# and the tag says shown="S" total="T" capped="1" with T the rows handed to the gate. Both dialects.
gate_xml(){ python3 -c '
import re, sys
s = sys.stdin.read()
m = re.search( r"<sigs([^>]*)>(.*?)</sigs>", s, re.S )
if not m: print( "FAIL no <sigs>" ); sys.exit( 1 )
seq = [ int( x ) for x in re.findall( r"<d [^>]*\br=\"([0-9]+)\"", m.group( 2 ) ) ]
if len( seq ) < int( sys.argv[ 1 ] ): print( "FAIL %d served rows, want at least %s: an empty head is 1..0 and would pass the order test" % ( len( seq ), sys.argv[ 1 ] ) ); sys.exit( 1 )
sh = re.search( r"shown=\"([0-9]+)\"", m.group( 1 ) ); tt = re.search( r"total=\"([0-9]+)\"", m.group( 1 ) )
if seq != list( range( 1, len( seq ) + 1 ) ): print( "FAIL served r= is not the rank head 1..S: %s" % seq ); sys.exit( 1 )
if not ( sh and tt and "capped=\"1\"" in m.group( 1 ) ): print( "FAIL the gate cut is undisclosed: <sigs%s>" % m.group( 1 ) ); sys.exit( 1 )
if int( sh.group( 1 ) ) != len( seq ) or int( tt.group( 1 ) ) <= len( seq ): print( "FAIL shown=/total= do not count the cut: <sigs%s> with %d rows" % ( m.group( 1 ), len( seq ) ) ); sys.exit( 1 )
print( "OK r=1..%d of total=%s" % ( len( seq ), tt.group( 1 ) ) )' "${1:-0}"; }
gate_json(){ python3 -c '
import json, sys
d = json.load( sys.stdin )
seq = [ r[ "r" ] for r in d[ "sigs" ] ]
if len( seq ) < int( sys.argv[ 1 ] ): print( "FAIL %d served rows, want at least %s: an empty head is 1..0 and would pass the order test" % ( len( seq ), sys.argv[ 1 ] ) ); sys.exit( 1 )
if seq != list( range( 1, len( seq ) + 1 ) ): print( "FAIL served r is not the rank head 1..S: %s" % seq ); sys.exit( 1 )
if d.get( "capped" ) is not True or d.get( "sigs_shown" ) != len( seq ) or not d.get( "sigs_total", 0 ) > len( seq ):
    print( "FAIL the gate cut is undisclosed: capped=%r sigs_shown=%r sigs_total=%r rows=%d" % ( d.get( "capped" ), d.get( "sigs_shown" ), d.get( "sigs_total" ), len( seq ) ) ); sys.exit( 1 )
print( "OK r=1..%d of sigs_total=%d" % ( len( seq ), d[ "sigs_total" ] ) )' "${1:-0}"; }
# A floor on the served rows: at 2000 B this query serves 8 today (measured at a2faa525), so a regression that dropped
# every row while still saying capped="1" total>0 must fail (an empty head is 1..0, so the order test alone passes it).
# 64 B serves 1 today, and the floor holds there too: gateSigRowsRankFirst (src/serialize.h, which packSignatures calls)
# tests `used >= budgetBytes` before each row with `used` starting at 0, so the first row is admitted at any budget by
# construction. The floor is 1, not 8, so a legitimate byte change to the rows does not trip it.
for pb in 64 2000; do
    minrows=1
    if v="$( "$BIN" src --for="rank graph teleport" --pack-budget-bytes=$pb --no-cache 2>/dev/null | gate_xml $minrows )"; then
        ok "(7) --pack-budget-bytes=$pb XML: $v"
    else
        no "(7) --pack-budget-bytes=$pb XML: $v"
    fi
    if v="$( "$BIN" src --for="rank graph teleport" --pack-budget-bytes=$pb --json --no-cache 2>/dev/null | gate_json $minrows )"; then
        ok "(7) --pack-budget-bytes=$pb JSON: $v"
    else
        no "(7) --pack-budget-bytes=$pb JSON: $v"
    fi
done

# ── (8) docs_dropped= discloses the rank tier's doc removal; shrunk-not-dropped is named (cut-fix lane A) ─────────
# The tier removes the doc of every row past r=24 ALWAYS (not budget-driven), and the ladder's steps B/D remove more on a
# capped block; both used to leave no trace. Fixture: 40 matching C++ functions over two files, EVERY one with a doc
# comment, small enough that the default bundle is uncapped — so exactly the 16 rows past r=24 print no <doc>. RED on
# 60b65f02 (no docs_dropped=, no clause). Then the ladder's first capped state (shrink, no drop) is found by walking
# --token-budget down, and must say shown == total with the shrunk clause. In every state, docs_dropped= must equal the
# shown rows printing no <doc> (every fixture row has one), and the JSON twin must carry the same count.
mkdir -p "$TMP/fxdocs"
python3 - "$TMP/fxdocs" <<'PY'
import sys
for f in range( 2 ):
    with open( "%s/part%d.cpp" % ( sys.argv[1], f ), "w" ) as o:
        for i in range( 20 ):
            n = f * 20 + i + 1
            o.write( "// widget helper %d computes a widget\nint widgetHelper%d( int x ) { return x + %d; }\n\n" % ( n, n, n ) )
PY
docs_arm(){ python3 -c '
import re, sys
s = sys.stdin.read()
m = re.search( r"<sigs([^>]*)>(.*?)</sigs>", s, re.S )
if not m: print( "FAIL no <sigs>" ); sys.exit( 1 )
rows = re.findall( r"<d [^>]*\br=\"([0-9]+)\"[^>]*>(.*?)</d>", m.group( 2 ), re.S )
nodoc = [ int( r ) for r, inner in rows if "<doc>" not in inner ]
dd = re.search( r"docs_dropped=\"([0-9]+)\"", m.group( 1 ) )
got = int( dd.group( 1 ) ) if dd else 0
if got != len( nodoc ) or got == 0: print( "FAIL docs_dropped=%d but %d shown rows print no <doc> (r=%s)" % ( got, len( nodoc ), nodoc ) ); sys.exit( 1 )
if "[docs_dropped=N:" not in s[ : s.find( "<sigs" ) ]: print( "FAIL docs_dropped= rides with no legend clause ahead of <sigs>" ); sys.exit( 1 )
sh = re.search( r"shown=\"([0-9]+)\"", m.group( 1 ) ); tt = re.search( r"total=\"([0-9]+)\"", m.group( 1 ) )
shrunk = bool( sh and tt and sh.group( 1 ) == tt.group( 1 ) )
if shrunk != ( "[sigs capped=1 with shown=total:" in s ): print( "FAIL the shrunk clause rides %s a shown==total cap" % ( "without" if shrunk else "beside no" ) ); sys.exit( 1 )
print( "OK docs_dropped=%d rows=%d %s" % ( got, len( rows ), "<sigs%s>" % m.group( 1 ) ) )'; }
if v="$( cd "$TMP" && "$BIN" fxdocs --for="widget helper" --no-cache 2>/dev/null | docs_arm )"; then
    case "$v" in
        # head round-robin (lane hrr): the tag may also carry files_first= (the reorder's reading; forheadrrcheck)
        *'docs_dropped=16 rows=40 <sigs docs_dropped="16">'*|*'docs_dropped=16 rows=40 <sigs docs_dropped="16" files_first="'[0-9]*'">'*) ok "(8) uncapped: the r>24 tier is disclosed: $v" ;;
        *) no "(8) uncapped fixture: want docs_dropped=16 of 40 on an uncapped tag, got: $v" ;;
    esac
else
    no "(8) uncapped fixture: $v"
fi
jd="$( cd "$TMP" && "$BIN" fxdocs --for="widget helper" --json --no-cache 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("docs_dropped"), sum(1 for r in d["sigs"] if "doc" not in r))' )"
if [ "$jd" = "16 16" ]; then ok "(8) JSON twin: docs_dropped=16 = the rows with no doc key"; else no "(8) JSON twin: docs_dropped/no-doc rows = '$jd' (want '16 16')"; fi
first_capped=""
for tb in 3400 3200 3000 2800 2600 2400 2200 2000; do
    out="$( cd "$TMP" && "$BIN" fxdocs --for="widget helper" --no-cache --token-budget=$tb 2>/dev/null )"
    v="$( printf '%s' "$out" | docs_arm )" || { no "(8) --token-budget=$tb: $v"; continue; }
    if [ -z "$first_capped" ] && printf '%s' "$v" | grep -q 'capped="1"'; then first_capped="$tb $v"; fi
done
case "$first_capped" in
    *'shown="40" total="40" capped="1"'*) ok "(8) the ladder's first capped state is shrunk-not-dropped and says so: --token-budget=$first_capped" ;;
    "") no "(8) no --token-budget in 3400..2000 capped the fixture — the shrunk arm measured nothing" ;;
    *) no "(8) first capped state is not shrunk-not-dropped: $first_capped" ;;
esac

# ── (9) A CAPPED <sigs> NAMES THE CALL THAT SERVES IT UNCUT (knob-honesty-068; PROCESS rule 5) ───────────────────
# The ladder disclosed its cut (shown= total= capped="1") and named no call that serves the cut rows: the bundle's only
# next= was the r=1 row's (a body, or the widening page). Fixture: 40 matching C functions with long docs and long
# parameter lists, past the default target. The tag must carry next= (+ its legend clause), pasting it must serve all total=
# rows uncut in the same rank order, the shown rows must be its prefix. JSON + MCP. Negatives: an uncapped tag (arm 8's
# fixture) carries none; --no-route is echoed. RED on 255dc199 (no next= on <sigs>).
# forbudget-soft (owner decisions 2026-10-14; rule 4 replacements): the DEFAULT ships the whole head — the target only shrinks
# row text (capped="1" with shown == total, past_target= the rows past it), so its next= serves the rows UNSHRUNK and it has no
# resume index (nothing was dropped). The row CUT this arm's resume-index and paste arms need is an explicit soft target's:
# --token-budget=1500 is exempt now (next= with its clause and next_offset=, no over_ceiling — a soft target is never "over"),
# and a wide target (8000) serves the default's rows rather than a frozen byte-identical block.
mkdir -p "$TMP/fxcut"
python3 - "$TMP/fxcut" <<'PY'
import sys
for f in range( 2 ):
    with open( "%s/cut%d.c" % ( sys.argv[1], f ), "w" ) as o:
        for i in range( 20 ):
            n = f * 20 + i + 1
            o.write( "/* gadget assembler %d builds one gadget from its parts, validating every part against the catalogue before it is placed and logged */\n" % n )
            o.write( "int gadgetAssembler%d( int partCount, const char* catalogueName, double toleranceMillimetres, unsigned long serialNumber ) { return partCount + %d; }\n\n" % ( n, n ) )
PY
cut_arm(){ python3 -c '
import json, re, shlex, sys
s = sys.stdin.read()
m = re.search( r"<sigs([^>]*)>(.*?)</sigs>", s, re.S )
if not m: print( "FAIL no <sigs>" ); sys.exit( 1 )
tag = m.group( 1 )
nx = re.search( r"\snext=\"([^\"]*)\"", tag )
sh = re.search( r"shown=\"([0-9]+)\"", tag ); tt = re.search( r"total=\"([0-9]+)\"", tag )
names = re.findall( r"<d [^>]*\bn=\"([^\"]*)\"", m.group( 2 ) )
ranks = [ int( r ) for r in re.findall( r"<d [^>]*\br=\"([0-9]+)\"", m.group( 2 ) ) ]
no_ = re.search( r"\snext_offset=\"([0-9]+)\"", tag ); nb_ = re.search( r"\snext_budget_tokens=\"([0-9]+)\"", tag )
out = { "capped": "capped=\"1\"" in tag, "shown": int( sh.group( 1 ) ) if sh else len( names ), "total": int( tt.group( 1 ) ) if tt else len( names ),
        "next": nx.group( 1 ).replace( "&apos;", chr( 39 ) ).replace( "&quot;", chr( 34 ) ).replace( "&amp;", "&" ) if nx else "",
        "clause": "[sigs next=:" in s[ : s.find( "<sigs" ) ], "names": names,
        "next_offset": int( no_.group( 1 ) ) if no_ else None, "max_r": max( ranks ) if ranks else 0,
        "next_budget_tokens": int( nb_.group( 1 ) ) if nb_ else None,
        "past_target": int( re.search( r"past_target=\"([0-9]+)\"", tag ).group( 1 ) ) if re.search( r"past_target=\"([0-9]+)\"", tag ) else 0,
        "offset_clause": "[sigs next_offset=:" in s[ : s.find( "<sigs" ) ], "budget_clause": "[sigs next_budget_tokens=:" in s[ : s.find( "<sigs" ) ] }
root = re.search( r"<ctx[^>]*>", s ); r = root.group( 0 ) if root else ""
for k in ( "est_tokens", "budget_tokens" ):
    v = re.search( r"\b%s=\"([0-9]+)\"" % k, r ); out[ k ] = int( v.group( 1 ) ) if v else None
out[ "over" ] = "over_ceiling=\"1\"" in r
print( json.dumps( out ) )'; }
cfield(){ python3 -c 'import json,sys; d=json.loads(sys.argv[1]); v=d.get(sys.argv[2]); print(json.dumps(v) if isinstance(v,(list,dict,bool)) or v is None else v)' "$1" "$2"; }
# body-fold (train 31; rule 4, by design — C3): on an answer that carries the fold, the signatures-only re-call moves from <sigs next=>
# to sigs_next= (next= names the first skipped body). This arm's subject is that re-call, so it reads the fold-off twin, where it is
# still next=; (9f) pins that the fold answer carries the same call as sigs_next= with its renamed clause.
C1="$( cd "$TMP" && RIPWIRE_NO_BODY_FOLD=1 "$BIN" fxcut --for="gadget assembler" --no-cache 2>/dev/null | cut_arm )"
C1F="$( cd "$TMP" && "$BIN" fxcut --for="gadget assembler" --no-cache 2>/dev/null )"
# a fold that skipped a body moves the call to sigs_next= (renamed reading); one that skipped none leaves <sigs next=> as it was
C1FN="$( printf '%s' "$C1F" | python3 -c 'import re,sys,html; s=sys.stdin.read(); t=re.search(r"<sigs\b[^>]*>", s); f=re.search(r"<fold .*?</fold>", s, re.S)
k = "sigs_next" if f and "<skip " in f.group(0) else "next"
m=re.search(r" %s=\"([^\"]*)\"" % k, t.group(0)) if t else None; print(k + " " + (html.unescape(m.group(1)) if m else ""))' )"
C1FK="${C1FN%% *}"; C1FV="${C1FN#* }"
if printf '%s' "$C1F" | grep -q '<fold kind="bodies"' && [ "$C1FV" = "$( cfield "$C1" next )" ] \
   && { [ "$C1FK" = next ] || printf '%s' "$C1F" | grep -q '\[sigs sigs_next=: one call serving all total= rows uncut\]'; }; then
    ok "(9f) fold on: the same signatures-only call rides as $C1FK= (a skip moves it to sigs_next= with its reading)"
else
    no "(9f) fold on: $C1FK='$C1FV' vs the fold-off next='$( cfield "$C1" next )', no fold, or the [sigs sigs_next=: …] reading is missing"
fi
if [ "$( cfield "$C1" capped )" = true ] && [ "$( cfield "$C1" shown )" = "$( cfield "$C1" total )" ] && [ "$( cfield "$C1" past_target )" -gt 0 ]; then
    ok "(9) presence guard: the default ships the whole head past its target, shrunk ($( cfield "$C1" shown ) of $( cfield "$C1" total ), past_target=$( cfield "$C1" past_target ))"
else
    no "(9) presence guard: the fixture's default is not a whole head shrunk past its target: $C1"
fi
NX1="$( cfield "$C1" next )"
case "$NX1" in
    "--for='gadget assembler' --signatures-only --token-budget="[0-9]*) ok "(9) the capped <sigs> names its call: next=\"$NX1\"" ;;
    *) no "(9) the capped <sigs> carries next='$NX1' (want --for='gadget assembler' --signatures-only --token-budget=N)" ;;
esac
if [ "$( cfield "$C1" clause )" = true ]; then ok "(9) the [sigs next=: …] clause defines it ahead of <sigs>"; else no "(9) <sigs next=> rides with no legend clause"; fi
# nothing dropped, so no resume index (the explicit cut below carries one)
if [ "$( cfield "$C1" next_offset )" = null ] && [ "$( cfield "$C1" offset_clause )" = false ]; then
    ok "(9) the default's complete head carries no next_offset= (no row was dropped)"
else
    no "(9) the default's complete head carries next_offset='$( cfield "$C1" next_offset )' (clause $( cfield "$C1" offset_clause ))"
fi
# paste it (shlex-split, as an agent would)
pasted(){ python3 -c 'import shlex,sys; print( "\0".join( shlex.split( sys.argv[1] ) ), end = "" )' "$1" > "$TMP/nx.argv"; ( cd "$TMP" && xargs -0 "$BIN" "$2" --no-cache < "$TMP/nx.argv" 2>/dev/null ); }
C2="$( [ -n "$NX1" ] && pasted "$NX1" fxcut | cut_arm )"
if [ -n "$C2" ] && [ "$( cfield "$C2" capped )" = false ] && [ "$( cfield "$C2" shown )" = "$( cfield "$C1" total )" ] && [ -z "$( cfield "$C2" next )" ]; then
    ok "(9) pasting it serves all $( cfield "$C2" shown ) rows uncut, and that answer carries no <sigs next=>"
else
    no "(9) the pasted next= did not serve the block uncut: ${C2:-<no output>}"
fi
# head round-robin (lane hrr, train 31; rule 4, orchestrator ruling FIX1 §4(a)): the default (C1) reorders its first 8 rows, while
# its next= carries an explicit --token-budget and keeps score order, so this ORDER-prefix arm runs unchanged on the
# RIPWIRE_NO_HEAD_RR=1 twin (C1T / C2T), and (9h) asserts what still holds with the reorder on: the cut block's rows are the
# continuation's first rows as a SET (test/lib/softbudget.py set_prefix) — no gap, no repeat
C1T="$( cd "$TMP" && RIPWIRE_NO_BODY_FOLD=1 RIPWIRE_NO_HEAD_RR=1 "$BIN" fxcut --for="gadget assembler" --no-cache 2>/dev/null | cut_arm )"
NX1T="$( cfield "${C1T:-{\}}" next )"
C2T="$( [ -n "$NX1T" ] && RIPWIRE_NO_HEAD_RR=1 pasted "$NX1T" fxcut | cut_arm )"
python3 -c 'import json,sys; a=json.loads(sys.argv[1])["names"]; b=json.loads(sys.argv[2])["names"]; sys.exit(0 if a and b[:len(a)]==a else 1)' "${C1T:-{\"names\":[]\}}" "${C2T:-{\"names\":[]\}}" 2>/dev/null \
    && ok "(9) [RIPWIRE_NO_HEAD_RR=1 twin] the cut block's rows are a prefix of the continuation's (same ranked list, same order)" \
    || no "(9) [RIPWIRE_NO_HEAD_RR=1 twin] the continuation does not extend the cut block's rows in order"
python3 -c 'import json,os,sys; sys.path.insert(0, os.environ["RIPWIRE_TESTLIB"]); from softbudget import set_prefix
a=json.loads(sys.argv[1])["names"]; on=json.loads(sys.argv[2])["names"]; off=json.loads(sys.argv[3])["names"]; sys.exit(0 if set_prefix(a, on, off) else 1)' \
    "$C1" "${C2:-{\"names\":[]\}}" "${C2T:-{\"names\":[]\}}" 2>/dev/null \
    && ok "(9h) head round-robin on: the cut block's rows are the continuation's first rows as a SET (score ranks 1..K)" \
    || no "(9h) head round-robin on: the cut block's rows are not a set prefix of the continuation's"
# a tight explicit (SOFT) target: the row cut — named with its clause, the resume index defined, never "over"
C3="$( cd "$TMP" && "$BIN" fxcut --for="gadget assembler" --token-budget=1500 --no-cache 2>/dev/null | cut_arm )"
NX3="$( cfield "$C3" next )"
{ [ "$( cfield "$C3" capped )" = true ] && [ -n "$NX3" ] && [ "$( cfield "$C3" over )" = false ] && [ "$( cfield "$C3" clause )" = true ] \
  && [ "$( cfield "$C3" shown )" -lt "$( cfield "$C3" total )" ]; } \
    && ok "(9) --token-budget=1500: the soft target's cut ($( cfield "$C3" shown ) of $( cfield "$C3" total )) carries next= and its clause, no over_ceiling" \
    || no "(9) --token-budget=1500: $C3"
# the resume index (the #362 candidate page's next_offset): the last printed row's candidate rank, defined by its own clause
if [ "$( cfield "$C3" next_offset )" = "$( cfield "$C3" max_r )" ] && [ "$( cfield "$C3" next_offset )" = "$( cfield "$C3" shown )" ] \
   && [ "$( cfield "$C3" offset_clause )" = true ]; then
    ok "(9) next_offset=\"$( cfield "$C3" next_offset )\" is the resume index: the last printed row's rank (= shown, no pseudo slot here), defined"
else
    no "(9) next_offset='$( cfield "$C3" next_offset )' vs last printed r=$( cfield "$C3" max_r ), shown=$( cfield "$C3" shown ), clause=$( cfield "$C3" offset_clause )"
fi
# a wide explicit target serves the default's rows (stop when complete: no pad, no cap below the default)
C8="$( cd "$TMP" && "$BIN" fxcut --for="gadget assembler" --token-budget=8000 --no-cache 2>/dev/null | cut_arm )"
# rule-4 twin (lane hrr): unchanged under RIPWIRE_NO_HEAD_RR=1 (C8T vs C1T); (9h) the same rows as a set with the reorder on
C8T="$( cd "$TMP" && RIPWIRE_NO_HEAD_RR=1 "$BIN" fxcut --for="gadget assembler" --token-budget=8000 --no-cache 2>/dev/null | cut_arm )"
python3 -c 'import json,sys; a=json.loads(sys.argv[1]); b=json.loads(sys.argv[2]); sys.exit(0 if a["names"] and a["names"]==b["names"] and not a["over"] else 1)' "${C8T:-{\}}" "${C1T:-{\}}" \
    && ok "(9) [RIPWIRE_NO_HEAD_RR=1 twin] --token-budget=8000: serves exactly the default's rows ($( cfield "$C8T" shown )), no over_ceiling" \
    || no "(9) [RIPWIRE_NO_HEAD_RR=1 twin] --token-budget=8000: rows differ from the default's (or over_ceiling): $C8T"
python3 -c 'import json,os,sys; sys.path.insert(0, os.environ["RIPWIRE_TESTLIB"]); from softbudget import set_prefix
a=json.loads(sys.argv[1]); on=json.loads(sys.argv[2]); off=json.loads(sys.argv[3]); sys.exit(0 if len(a["names"]) == len(on["names"]) and set_prefix(a["names"], on["names"], off["names"]) and not a["over"] else 1)' \
    "${C8:-{\}}" "${C1:-{\}}" "${C1T:-{\}}" 2>/dev/null \
    && ok "(9h) head round-robin on: --token-budget=8000 serves the default's rows as a set ($( cfield "$C8" shown )), no over_ceiling" \
    || no "(9h) head round-robin on: --token-budget=8000: not the default's rows as a set (or over_ceiling): $C8"
C4="$( [ -n "$NX3" ] && pasted "$NX3" fxcut | cut_arm )"
[ -n "$C4" ] && [ "$( cfield "$C4" capped )" = false ] && [ "$( cfield "$C4" shown )" = "$( cfield "$C3" total )" ] \
    && ok "(9) --token-budget=1500: pasting its next= serves the block uncut" || no "(9) --token-budget=1500: the pasted next= left it cut: ${C4:-<none>}"
# negatives: an uncapped tag carries no next=/next_offset=; a ranking flag is echoed (the re-run must rank the same list)
U1="$( cd "$TMP" && "$BIN" fxdocs --for="widget helper" --no-cache 2>/dev/null | cut_arm )"
[ "$( cfield "$U1" capped )" = false ] && [ -z "$( cfield "$U1" next )" ] && [ "$( cfield "$U1" clause )" = false ] && [ "$( cfield "$U1" next_offset )" = null ] \
    && ok "(9) negative: an uncapped <sigs> carries no next= and no clause" || no "(9) negative: uncapped fixture: $U1"
case "$( cd "$TMP" && "$BIN" fxcut --for="gadget assembler" --no-route --no-cache 2>/dev/null | cut_arm | python3 -c 'import json,sys; print(json.load(sys.stdin)["next"])' )" in
    *' --no-route'*) ok "(9) --no-route is echoed in the continuation" ;;
    *) no "(9) --no-route was not echoed in the continuation" ;;
esac
# JSON twin: "sigs_next" on a capped array, and pasting it serves the array uncut
J1="$( cd "$TMP" && "$BIN" fxcut --for="gadget assembler" --json --no-cache 2>/dev/null )"
JNX="$( printf '%s' "$J1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("sigs_next",""))' 2>/dev/null )"
case "$JNX" in
    *' --signatures-only '*' --json') ok "(9) JSON twin: \"sigs_next\" names the --json call" ;;
    *) no "(9) JSON twin: sigs_next='$JNX'" ;;
esac
# the resume index rides a row CUT: the explicit soft target's (the default's head is complete)
JNO="$( cd "$TMP" && "$BIN" fxcut --for="gadget assembler" --json --token-budget=1500 --no-cache 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("sigs_next_offset"), d.get("sigs_shown"))' 2>/dev/null )"
case "$JNO" in "None"*|"") no "(9) JSON twin: no sigs_next_offset on the soft target's cut ('$JNO')" ;; *) set -- $JNO; if [ "$1" = "$2" ]; then ok "(9) JSON twin: sigs_next_offset=$1 (the resume index of the soft target's cut)"; else no "(9) JSON twin: sigs_next_offset=$1 vs sigs_shown=$2"; fi ;; esac
J2="$( [ -n "$JNX" ] && pasted "$JNX" fxcut | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("capped"), len(d["sigs"]), "sigs_next" in d)' 2>/dev/null )"
[ "$J2" = "False $( printf '%s' "$J1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("sigs_total"))' 2>/dev/null ) False" ] \
    && ok "(9) JSON twin: pasting sigs_next serves every row uncut" || no "(9) JSON twin: pasted sigs_next gave '$J2'"
# MCP twin (signatures only, its own ranking pipeline): NO pasteable CLI argv — the machine form next_budget_tokens=T (and
# next_offset=); re-calling `for` with budget_tokens=T serves every row uncut
mcpfor(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"gadget assembler"%s}}}\n' "$TMP/fxcut" "$1" \
       | "$BIN" --mcp 2>/dev/null | python3 -c 'import json,sys
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    d=json.loads(line)
    if d.get("id")==1: print(d["result"]["content"][0]["text"])' 2>/dev/null | cut_arm; }
M1="$( mcpfor '' )"
MNB="$( cfield "${M1:-{\}}" next_budget_tokens 2>/dev/null )"
if [ -n "$M1" ] && [ "$( cfield "$M1" capped )" = true ] && [ -z "$( cfield "$M1" next )" ] && [ "$MNB" != null ] && [ "$( cfield "$M1" budget_clause )" = true ] \
   && [ "$( cfield "$M1" shown )" = "$( cfield "$M1" total )" ] && [ "$( cfield "$M1" next_offset )" = null ]; then
    ok "(9) MCP twin: the whole head, shrunk; no CLI argv on <sigs>; next_budget_tokens=\"$MNB\" defined; no next_offset= (nothing dropped)"
else
    no "(9) MCP twin: ${M1:-<no output>}"
fi
M1B="$( mcpfor ',"budget_tokens":1500' )"
if [ -n "$M1B" ] && [ "$( cfield "$M1B" next_offset )" = "$( cfield "$M1B" max_r )" ] && [ "$( cfield "$M1B" next_budget_tokens )" != null ] && [ "$( cfield "$M1B" over )" = false ]; then
    ok "(9) MCP twin, budget_tokens=1500: the soft cut's next_offset=\"$( cfield "$M1B" next_offset )\" and next_budget_tokens=, no over_ceiling"
else
    no "(9) MCP twin, budget_tokens=1500: ${M1B:-<no output>}"
fi
M2="$( [ "$MNB" != null ] && mcpfor ",\"budget_tokens\":$MNB" )"
if [ -n "$M2" ] && [ "$( cfield "$M2" capped )" = false ] && [ "$( cfield "$M2" shown )" = "$( cfield "$M1" total )" ]; then
    ok "(9) MCP twin: re-calling for with budget_tokens=$MNB serves all $( cfield "$M2" shown ) rows uncut"
else
    no "(9) MCP twin: the re-call with budget_tokens=$MNB did not serve the block uncut: ${M2:-<no output>}"
fi

# ── (10) MCP budget_tokens IS A SOFT TARGET (forbudget-soft, owner decisions 2026-10-14; rule 4: replaces the C3 rulings' arm) ──
# C3 (2026-10-07) ruled when a charged handle is paid from rows under a HARD budget; an explicit budget is a soft target now, so
# nothing is paid and nothing is labelled "over". What must hold instead, at 2000 / 2600 / 3800 on (9)'s fixture: the rows are
# a rank PREFIX of the MCP default's (whole head) and monotone in the budget, a cut carries next_budget_tokens=, and no
# over_ceiling= rides. Same relative path from $TMP as before (root="fxcut").
mcprel(){ ( cd "$TMP" && printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"fxcut","task":"gadget assembler","budget_tokens":%s}}}\n' "$1" \
       | "$BIN" --mcp 2>/dev/null ) | python3 -c 'import json,sys
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    d=json.loads(line)
    if d.get("id")==1: print(d["result"]["content"][0]["text"])' 2>/dev/null | cut_arm; }
# head round-robin (lane hrr, train 31; rule 4, by design): the head is reordered WITHIN each answer's shown rows, so a budgeted
# answer's ORDER is a prefix of the default's only in score order — the twin below runs this arm unchanged with
# RIPWIRE_NO_HEAD_RR=1, and (10h) asserts what still holds with it on: the budgeted rows are the default's first rows as a SET
# (score ranks 1..K, so the next_budget_tokens= re-call continues without a gap or a repeat).
M1T="$( RIPWIRE_NO_HEAD_RR=1 mcpfor '' )"
prev_names='[]'
for bt in 2000 2600 3800; do
    MBH="$( mcprel "$bt" )"
    vh="$( python3 -c 'import json,sys
b=json.loads(sys.argv[1]); d=json.loads(sys.argv[2])
ok = sorted(b["names"]) == sorted(d["names"][:len(b["names"])]) and not b["over"] and ( b["shown"] == b["total"] or b["next_budget_tokens"] is not None )
print(("OK" if ok else "BAD"), b["shown"], b["total"], b["over"], b["next_budget_tokens"])' "${MBH:-{\}}" "${M1T:-{\}}" 2>/dev/null )"
    case "$vh" in
        OK*) ok "(10h) MCP budget_tokens=$bt, head round-robin on: the default's first rows as a set, the cut continued ($vh)" ;;
        *)   no "(10h) MCP budget_tokens=$bt, head round-robin on: ${vh:-<no output>} — want the default's first rows (score ranks 1..K) as a set" ;;
    esac
    MB="$( RIPWIRE_NO_HEAD_RR=1 mcprel "$bt" )"
    v="$( python3 -c 'import json,sys
b=json.loads(sys.argv[1]); d=json.loads(sys.argv[2]); p=json.loads(sys.argv[3])
ok = b["names"] == d["names"][:len(b["names"])] and b["names"][:len(p)] == p and not b["over"] \
     and ( b["shown"] == b["total"] or b["next_budget_tokens"] is not None )
print(("OK" if ok else "BAD"), b["shown"], b["total"], b["over"], b["next_budget_tokens"])' "${MB:-{\}}" "${M1T:-{\}}" "$prev_names" 2>/dev/null )"
    case "$v" in
        OK*) ok "(10) MCP budget_tokens=$bt: a rank prefix of the whole head, monotone, the cut continued, no over_ceiling ($v)" ;;
        *)   no "(10) MCP budget_tokens=$bt: ${v:-<no output>} — want a monotone rank prefix, next_budget_tokens= on a cut, no over_ceiling" ;;
    esac
    prev_names="$( cfield "${MB:-{\}}" names 2>/dev/null || echo '[]' )"
done

# ── (10c) THE at= STAMP IS READ ONCE PER RUN (CodeRabbit on #383, verbs_for.h:3843) ─────────────
# A --token-budget run rendered in up to three payment modes (unpaid, paid, unpaid again) before a byte reached stdout; each
# render re-read the git stamp (rev-parse + status --porcelain), so a run over its ceiling either way spawned three
# `status --porcelain` children. The ranking is computed once per run and so is the stamp. forbudget-soft: one render per run
# now (no payment modes); the premise is a budgeted run whose rows the target cuts. Fixture: fxcut as a one-commit git
# repository (the stamp only reads a git root); a PATH git shim logs every git call and runs the real git. RED on 255dc199's
# successor before the fix (3 status children); GREEN: exactly 1, and at= still rides the answer.
FXG="$TMP/fxcutgit"; cp -R "$TMP/fxcut" "$FXG"
git -C "$FXG" init -q && git -C "$FXG" add -A && git -C "$FXG" -c user.name=t -c user.email=t@t commit -qm init
GSHIM="$TMP/gitshim"; mkdir -p "$GSHIM"; REALGIT="$( command -v git )"
cat > "$GSHIM/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$GSHIM/calls.log"
exec "$REALGIT" "\$@"
EOF
chmod +x "$GSHIM/git"; : > "$GSHIM/calls.log"
out="$( cd "$TMP" && PATH="$GSHIM:$PATH" "$BIN" fxcutgit --for="gadget assembler" --no-cache --token-budget=500 2>/dev/null )"
st="$( grep -c 'status --porcelain' "$GSHIM/calls.log" | tr -d ' ' )"
if ! printf '%s' "$out" | grep -q '<sigs [^>]*next_offset='; then
    no "(10c) premise: --token-budget=500 on fxcutgit cuts no row (no <sigs next_offset=>): $( printf '%s' "$out" | grep -o '<sigs [^>]*>' | head -c 300 )"
elif [ "$st" = 1 ] && printf '%s' "$out" | grep -q ' at="'; then
    ok "(10c) a budgeted, cut --token-budget run reads the git stamp once (1 status --porcelain child), and at= rides the answer"
else
    no "(10c) status --porcelain children: $st (want 1; one per render = 3 before the fix); at= present: $( printf '%s' "$out" | grep -c ' at="' )"
fi

# ── (11) A SOFT TARGET NEVER SERVES FEWER ROWS THAN THE HARD CEILING DID (forbudget-soft; rule 4: replaces C3-completed) ─────────
# C3 completed (2026-10-08) ruled "pay for next= only when paying is what makes the answer fit" under a HARD budget, pinning the
# rows the cut alone left: CLI --for @2160 16 rows, --json @2000 16, MCP @4340 40. A soft target charges the rows only (never the
# header), so at the same budgets it serves AT LEAST those rows, the cut (if any) carries its continuation, and nothing is
# labelled over_ceiling. The est_tokens <= budget half is gone with the byte promise (the owner's decision); the row bound
# that replaces it is forsoftbudgetcheck's ST.
c11row(){ printf '%s' "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); h=d["next"] or d["next_budget_tokens"]; print(d["shown"], d["total"], bool(h), d["over"])' 2>/dev/null; }
c11check(){   # LABEL BUDGET WANT ROWS TOTAL HANDLE OVER
    local label="$1" bt="$2" want="$3"; shift 3
    if [ "$#" -eq 4 ] && [ "$1" -ge "$want" ] && { [ "$1" = "$2" ] || [ "$3" = True ]; } && [ "$4" = False ]; then
        ok "(11) $label @$bt: $1 rows (>= the hard ceiling's $want), the cut continued, no over_ceiling="
    else
        no "(11) $label @$bt: shown/total/handle/over = ${*:-<no output>} — want >= $want rows, a continued cut, no over_ceiling="
    fi
}
c11check "CLI --for" 2160 16 $( c11row "$( cd "$TMP" && "$BIN" fxcut --for="gadget assembler" --token-budget=2160 --no-cache 2>/dev/null | cut_arm )" )
c11check "MCP for" 4340 40 $( c11row "$( mcprel 4340 )" )
set -- $( cd "$TMP" && "$BIN" fxcut --for="gadget assembler" --token-budget=2000 --json --no-cache 2>/dev/null \
          | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["sigs"]), d.get("sigs_total", len(d["sigs"])), "sigs_next" in d, bool(d.get("over_ceiling")))' 2>/dev/null )
if [ "$#" -eq 4 ] && [ "$1" -ge 16 ] && { [ "$1" = "$2" ] || [ "$3" = True ]; } && [ "$4" = False ]; then
    ok "(11) --for --json @2000: $1 rows (>= 16), the cut continued (\"sigs_next\"), no over_ceiling"
else
    no "(11) --for --json @2000: rows/total/sigs_next/over = ${*:-<no output>} — want >= 16 rows, a continued cut, no over_ceiling"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
