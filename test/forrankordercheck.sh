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
REPO_BASE=( 10134 10029 10080 10102 9880 9397 10009 10070 9966 10379 )
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
echo "  ledger: the ten reference queries (this repo, full legend) — base bytes @8eb669ff (q5 @cap-followup-2026-09-10) → now, shown=/total="
i=0
for q in "${REPO_Q[@]}"; do
    base="${REPO_BASE[$i]}"; i=$(( i + 1 ))
    out="$( "$BIN" . --for="$q" 2>/dev/null )"
    now="$( printf '%s' "$out" | wc -c | tr -d ' ' )"
    marker="$( printf '%s' "$out" | grep -o '<sigs[^>]*>' | head -1 )"
    pct="$( python3 -c "print( '%+.2f' % ( ( $now - $base ) * 100.0 / $base ) )" )"
    printf '    q%-2d %-28s %5d → %5d  (%s%%)  %s\n' "$i" "'$q'" "$base" "$now" "$pct" "$marker"
    if [ "$now" -gt $(( base * 104 / 100 )) ]; then
        no "(3) repo q$i '$q': $now B > 1.04 × $base B"; growth_fail=1
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
    now="$( cd "$TMP" && "$BIN" "$fx" --for="$q" 2>/dev/null | wc -c | tr -d ' ' )"
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
        *'docs_dropped=16 rows=40 <sigs docs_dropped="16">'*) ok "(8) uncapped: the r>24 tier is disclosed: $v" ;;
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
# parameter lists, so the DEFAULT ceiling drops rows. The tag must carry next= (+ its legend clause), pasting it must
# serve all total= rows uncut in the same rank order, the shown rows must be its prefix. Under a tight explicit (hard)
# ceiling it is CHARGED and TERSE: next= alone, and est_tokens stays within budget_tokens. At an explicit ceiling wide enough that
# the sig side is frozen at the default's it is EXEMPT: the <sigs> block is byte-identical to the default's. JSON + MCP.
# Negatives: an uncapped tag (arm 8's fixture) carries none; --no-route is echoed. RED on 255dc199 (no next= on <sigs>).
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
        "offset_clause": "[sigs next_offset=:" in s[ : s.find( "<sigs" ) ], "budget_clause": "[sigs next_budget_tokens=:" in s[ : s.find( "<sigs" ) ] }
root = re.search( r"<ctx[^>]*>", s ); r = root.group( 0 ) if root else ""
for k in ( "est_tokens", "budget_tokens" ):
    v = re.search( r"\b%s=\"([0-9]+)\"" % k, r ); out[ k ] = int( v.group( 1 ) ) if v else None
out[ "over" ] = "over_ceiling=\"1\"" in r
print( json.dumps( out ) )'; }
cfield(){ python3 -c 'import json,sys; d=json.loads(sys.argv[1]); v=d.get(sys.argv[2]); print(json.dumps(v) if isinstance(v,(list,dict,bool)) or v is None else v)' "$1" "$2"; }
C1="$( cd "$TMP" && "$BIN" fxcut --for="gadget assembler" --no-cache 2>/dev/null | cut_arm )"
if [ "$( cfield "$C1" capped )" = true ] && [ "$( cfield "$C1" shown )" -lt "$( cfield "$C1" total )" ]; then
    ok "(9) presence guard: the default ceiling drops rows ($( cfield "$C1" shown ) of $( cfield "$C1" total ))"
else
    no "(9) presence guard: the fixture is not cut at the default ceiling: $C1"
fi
NX1="$( cfield "$C1" next )"
case "$NX1" in
    "--for='gadget assembler' --signatures-only --token-budget="[0-9]*) ok "(9) the capped <sigs> names its call: next=\"$NX1\"" ;;
    *) no "(9) the capped <sigs> carries next='$NX1' (want --for='gadget assembler' --signatures-only --token-budget=N)" ;;
esac
if [ "$( cfield "$C1" clause )" = true ]; then ok "(9) the [sigs next=: …] clause defines it ahead of <sigs>"; else no "(9) <sigs next=> rides with no legend clause"; fi
# the resume index (the #362 candidate page's next_offset): the last printed row's candidate rank, defined by its own clause
if [ "$( cfield "$C1" next_offset )" = "$( cfield "$C1" max_r )" ] && [ "$( cfield "$C1" next_offset )" = "$( cfield "$C1" shown )" ] \
   && [ "$( cfield "$C1" offset_clause )" = true ]; then
    ok "(9) next_offset=\"$( cfield "$C1" next_offset )\" is the resume index: the last printed row's rank (= shown, no pseudo slot here), defined"
else
    no "(9) next_offset='$( cfield "$C1" next_offset )' vs last printed r=$( cfield "$C1" max_r ), shown=$( cfield "$C1" shown ), clause=$( cfield "$C1" offset_clause )"
fi
# paste it (shlex-split, as an agent would)
pasted(){ python3 -c 'import shlex,sys; print( "\0".join( shlex.split( sys.argv[1] ) ), end = "" )' "$1" > "$TMP/nx.argv"; ( cd "$TMP" && xargs -0 "$BIN" "$2" --no-cache < "$TMP/nx.argv" 2>/dev/null ); }
C2="$( [ -n "$NX1" ] && pasted "$NX1" fxcut | cut_arm )"
if [ -n "$C2" ] && [ "$( cfield "$C2" capped )" = false ] && [ "$( cfield "$C2" shown )" = "$( cfield "$C1" total )" ] && [ -z "$( cfield "$C2" next )" ]; then
    ok "(9) pasting it serves all $( cfield "$C2" shown ) rows uncut, and that answer carries no <sigs next=>"
else
    no "(9) the pasted next= did not serve the block uncut: ${C2:-<no output>}"
fi
python3 -c 'import json,sys; a=json.loads(sys.argv[1])["names"]; b=json.loads(sys.argv[2])["names"]; sys.exit(0 if a and b[:len(a)]==a else 1)' "$C1" "${C2:-{\"names\":[]\}}" 2>/dev/null \
    && ok "(9) the cut block's rows are a prefix of the continuation's (same ranked list, same order)" \
    || no "(9) the continuation does not extend the cut block's rows in order"
# tight explicit ceiling: CHARGED — still named, and est_tokens stays within the hard ceiling the root names
C3="$( cd "$TMP" && "$BIN" fxcut --for="gadget assembler" --token-budget=1500 --no-cache 2>/dev/null | cut_arm )"
NX3="$( cfield "$C3" next )"
{ [ "$( cfield "$C3" capped )" = true ] && [ -n "$NX3" ] && [ "$( cfield "$C3" over )" = false ] && [ "$( cfield "$C3" next_offset )" = null ] \
  && [ "$( cfield "$C3" clause )" = false ] && [ "$( cfield "$C3" est_tokens )" -le "$( cfield "$C3" budget_tokens )" ]; } \
    && ok "(9) --token-budget=1500: charged and terse — next= alone (no next_offset=, no clause), est_tokens $( cfield "$C3" est_tokens ) <= budget_tokens 1500" \
    || no "(9) --token-budget=1500: $C3"
# wide explicit ceiling (sig side frozen at the default's): EXEMPT — the block, next= included, is the default's byte for byte
sigsblk(){ python3 -c 'import re,sys; m=re.search(r"<sigs[^>]*>.*?</sigs>",sys.stdin.read(),re.S); print(m.group(0) if m else "")'; }
if [ "$( cd "$TMP" && "$BIN" fxcut --for="gadget assembler" --no-cache 2>/dev/null | sigsblk )" = "$( cd "$TMP" && "$BIN" fxcut --for="gadget assembler" --token-budget=8000 --no-cache 2>/dev/null | sigsblk )" ]; then
    ok "(9) --token-budget=8000: exempt — the <sigs> block (its next= included) is the default's byte for byte"
else
    no "(9) --token-budget=8000: the <sigs> block differs from the default's (the exempt regime moved rows or its next=)"
fi
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
JNO="$( printf '%s' "$J1" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("sigs_next_offset"), d.get("sigs_shown"))' 2>/dev/null )"
case "$JNO" in "None"*|"") no "(9) JSON twin: no sigs_next_offset ('$JNO')" ;; *) set -- $JNO; if [ "$1" = "$2" ]; then ok "(9) JSON twin: sigs_next_offset=$1 (the resume index)"; else no "(9) JSON twin: sigs_next_offset=$1 vs sigs_shown=$2"; fi ;; esac
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
   && [ "$( cfield "$M1" next_offset )" = "$( cfield "$M1" max_r )" ]; then
    ok "(9) MCP twin: no CLI argv on <sigs>; next_budget_tokens=\"$MNB\" and next_offset=\"$( cfield "$M1" next_offset )\", both defined"
else
    no "(9) MCP twin: ${M1:-<no output>}"
fi
M2="$( [ "$MNB" != null ] && mcpfor ",\"budget_tokens\":$MNB" )"
if [ -n "$M2" ] && [ "$( cfield "$M2" capped )" = false ] && [ "$( cfield "$M2" shown )" = "$( cfield "$M1" total )" ]; then
    ok "(9) MCP twin: re-calling for with budget_tokens=$MNB serves all $( cfield "$M2" shown ) rows uncut"
else
    no "(9) MCP twin: the re-call with budget_tokens=$MNB did not serve the block uncut: ${M2:-<no output>}"
fi

# ── (10) C3: NO ROW IS DROPPED TO PAY FOR A HANDLE THAT CANNOT MAKE THE ANSWER FIT (orchestrator ruling 2026-10-07) ──────────
# The MCP `for` answer overshoots budget_tokens on its own (its sig ledger exempts header bytes), so under a budget that caps
# <sigs> it is often past its ceiling paid or not; paying next_budget_tokens= from the rows (dd6e4c8e: ~245 B, 1-2 rows)
# bought nothing there. Over its ceiling either way → the rows the cut alone leaves, the handle unpaid, over_ceiling="1".
# Where paying IS what makes it fit, it pays (unchanged). Fixture: (9)'s 40 gadget functions, called by a RELATIVE path from
# $TMP so no checkout or temp-dir path rides in the header bytes the rows are budgeted against (root="fxcut" everywhere).
#   over-anyway @2000 / @3000: 255dc199 serves 14 / 25 of 40 (est 2270 / 3125, over); dd6e4c8e paid 2 rows (12 / 23) and was
#     still over (est 2206 / 3071) — RED there.
#     train 26b re-pin (2026-10-08): lean-answers' zero elision made every row smaller, so @3000 is no longer over either way
#     on the merged tree — the pre-continuation train binary (d82e4cf1) serves 25 rows at est 2945, FITTING; the unpaid
#     answer + handle lands over and the paid one (23 rows, est 2918) fits, i.e. @3000 moved into the payable regime and is
#     served paid, as ruled. The over-either-way budget is now @2600: d82e4cf1 serves 21 rows at est 2684 (over before any
#     handle); the merged binary serves those 21 + the unpaid handle, est 2793, over_ceiling="1" (paying ~2 rows, ~90 tokens,
#     cannot reach 2600). @2000 is unchanged (d82e4cf1 14 rows est 2178 over). Rows >= 255dc199's (re-pin from a pre-continuation binary if row bytes or the
#     header change; smaller rows only raise it), the handle rides, over_ceiling="1". (Budgets with a margin on both sides of
#     the ceiling: near one, a few bytes of legend decide whether paying fits, and the arm would pin that, not the rule.)
#   payable @3800: 255dc199 serves 35 rows at est 3824 — OVER; paying the handle from rows (33, est 3773) is what makes it fit:
#     the answer carries next_budget_tokens= and NO over_ceiling= (a binary that never pays serves 35 rows at est 3934, over).
mcprel(){ ( cd "$TMP" && printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"fxcut","task":"gadget assembler","budget_tokens":%s}}}\n' "$1" \
       | "$BIN" --mcp 2>/dev/null ) | python3 -c 'import json,sys
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    d=json.loads(line)
    if d.get("id")==1: print(d["result"]["content"][0]["text"])' 2>/dev/null | cut_arm; }
c3row(){ printf '%s' "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["shown"], d["capped"], d["next_budget_tokens"] is not None, d["over"], d["est_tokens"])' 2>/dev/null; }
for spec in 2000:14 2600:21; do
    bt="${spec%%:*}"; want="${spec##*:}"
    set -- $( c3row "$( mcprel "$bt" )" )
    if [ "$#" -eq 5 ] && [ "$1" -ge "$want" ] && [ "$2" = True ] && [ "$3" = True ] && [ "$4" = True ]; then
        ok "(10) MCP budget_tokens=$bt, over its ceiling either way: $1 rows (>= the cut's own $want, none dropped for the handle), next_budget_tokens= unpaid, over_ceiling=\"1\" (est $5)"
    else
        no "(10) MCP budget_tokens=$bt: shown/capped/handle/over/est = ${*:-<no output>} — want >= $want rows (the cut's own), the handle, over_ceiling=\"1\""
    fi
done
set -- $( c3row "$( mcprel 3800 )" )
if [ "$#" -eq 5 ] && [ "$2" = True ] && [ "$3" = True ] && [ "$4" = False ] && [ "$5" -le 3800 ]; then
    ok "(10) MCP budget_tokens=3800, payable: the handle is paid from rows ($1 shown) and that is what makes the answer fit (est $5 <= 3800, no over_ceiling=)"
else
    no "(10) MCP budget_tokens=3800: shown/capped/handle/over/est = ${*:-<no output>} — want a paid handle inside the budget"
fi

# ── (10c) THE at= STAMP IS READ ONCE PER RUN, WHICHEVER PAYMENT MODE SERVES (CodeRabbit on #383, verbs_for.h:3843) ─────────────
# A --token-budget run renders in up to three payment modes (unpaid, paid, unpaid again) before a byte reaches stdout; each
# render re-read the git stamp (rev-parse + status --porcelain), so a run over its ceiling either way spawned three
# `status --porcelain` children. The ranking is computed once per run and so is the stamp now. Fixture: fxcut as a one-commit
# git repository (the stamp only reads a git root); budget 500 against an answer of ~1100 est tokens is over either way
# (over_ceiling="1" — the premise); a PATH git shim logs every git call and runs the real git. RED on the pre-fix binary
# (3 status children); GREEN: exactly 1, and at= still rides the answer.
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
if ! printf '%s' "$out" | grep -q 'over_ceiling="1"'; then
    no "(10c) premise: --token-budget=500 on fxcutgit is not over its ceiling either way (no over_ceiling=\"1\"): $( printf '%s' "$out" | grep -o '<ctx [^>]*>' | head -c 300 )"
elif [ "$st" = 1 ] && printf '%s' "$out" | grep -q ' at="'; then
    ok "(10c) a three-render --token-budget run reads the git stamp once (1 status --porcelain child), and at= rides the answer"
else
    no "(10c) status --porcelain children: $st (want 1; one per render = 3 before the fix); at= present: $( printf '%s' "$out" | grep -c ' at="' )"
fi

# ── (11) C3 COMPLETED: PAY FOR next= ONLY WHEN PAYING IS WHAT MAKES THE ANSWER FIT (orchestrator ruling 2026-10-08) ─────────────
# The answer with every row the cut leaves PLUS the unpaid handle is the first candidate; it is served whenever it fits, and only
# when it lands past its ceiling are rows dropped to pay (and served only if THAT fits — (10)'s @3800). 45a2eeba paid first and
# kept the paid answer whenever it fit, so it dropped rows the unpaid answer had room for: the served answer had fewer rows than
# an alternative that also fit. Same fixture and relative path as (10). Pins are 255dc199's own rows at each budget (the cut's
# rows; re-pin from a pre-continuation binary if row bytes or the header change), budgets chosen with room on both sides:
#   CLI XML @2160: 255dc199 17 rows (est 2046); 45a2eeba 16 (est 1998) — RED there; head 17 + next= (est 2078 <= 2160).
#   --json  @2000: 255dc199 16 rows (est 1657); 45a2eeba 15 — RED there; head 16 + "sigs_next" (est 1691).
#   MCP     @4340: 255dc199 40 rows (est 4257); 45a2eeba 39 — RED there; head 40 + next_budget_tokens= (est 4308 <= 4340).
# Each: rows >= the cut's own, the handle rides, est_tokens <= the budget, no over_ceiling. A binary that always pays when it
# can fit (the 45a2eeba order) is red on all three.
c11row(){ printf '%s' "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); h=d["next"] or d["next_budget_tokens"]; print(d["shown"], d["capped"], bool(h), d["over"], d["est_tokens"])' 2>/dev/null; }
c11check(){   # LABEL BUDGET WANT ROWS CAPPED HANDLE OVER EST
    local label="$1" bt="$2" want="$3"; shift 3
    if [ "$#" -eq 5 ] && [ "$1" -ge "$want" ] && [ "$2" = True ] && [ "$3" = True ] && [ "$4" = False ] && [ "$5" -le "$bt" ]; then
        ok "(11) $label @$bt fits with every row the cut leaves: $1 rows (>= $want, none dropped to pay), the handle unpaid, est $5 <= $bt, no over_ceiling="
    else
        no "(11) $label @$bt: shown/capped/handle/over/est = ${*:-<no output>} — want >= $want rows, the handle, est <= $bt, no over_ceiling= (paid where it already fit?)"
    fi
}
c11check "CLI --for" 2160 17 $( c11row "$( cd "$TMP" && "$BIN" fxcut --for="gadget assembler" --token-budget=2160 --no-cache 2>/dev/null | cut_arm )" )
c11check "MCP for" 4340 40 $( c11row "$( mcprel 4340 )" )
set -- $( cd "$TMP" && "$BIN" fxcut --for="gadget assembler" --token-budget=2000 --json --no-cache 2>/dev/null \
          | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["sigs"]), "sigs_next" in d, bool(d.get("over_ceiling")), d["est_tokens"])' 2>/dev/null )
if [ "$#" -eq 4 ] && [ "$1" -ge 16 ] && [ "$2" = True ] && [ "$3" = False ] && [ "$4" -le 2000 ]; then
    ok "(11) --for --json @2000 fits with every row the cut leaves: $1 rows (>= 16), \"sigs_next\" unpaid, est $4 <= 2000, no over_ceiling"
else
    no "(11) --for --json @2000: rows/sigs_next/over/est = ${*:-<no output>} — want >= 16 rows, \"sigs_next\", est <= 2000, no over_ceiling"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
