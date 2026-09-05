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
# Usage:  bash test/forrankordercheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/forrankordercheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
cd "$ROOT"
echo "forrankordercheck: BIN=$BIN"

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
REPO_BASE=( 9981 9961 9784 9968 9362 9949 9909 9745 9613 9806 )

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
echo "  ledger: the ten reference queries (this repo, full legend) — base bytes @8eb669ff → now, shown=/total="
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
FX_BASE="fixture|geometry area of a shape|2895
fixture|call a native function from python|3067
fixture|parse the config and load it|3277
ffifix|geometry area of a shape|2050
ffifix|call a native function from python|3068
ffifix|parse the config and load it|3506
hostilefix|geometry area of a shape|2775
hostilefix|call a native function from python|2074
hostilefix|parse the config and load it|2928"
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
    printf '%s' "$NOTE_FOR" | xmllint --noout - 2>/dev/null && ok "(4) --for with notes is xmllint-clean" || no "(4) --for with notes is not well-formed"
fi

# ── (5) mutation control: the checker rejects the pre-fix shapes ──────────────────────────────────────────
PREFIX_XML='<ctx><sigs shown="3" total="3"><f p="src/a.h"><d l="1" n="x" r="2">int x()</d><d l="9" n="y" r="1">int y()</d></f><f p="src/b.h"><d l="3" n="z" r="3">int z()</d></f></sigs></ctx>'
PREFIX_JSON='{"sigs":[{"p":"src/a.h","symbols":[{"l":1,"n":"x","r":2,"sig":"int x()"},{"l":9,"n":"y","r":1,"sig":"int y()"}]},{"p":"src/b.h","symbols":[{"l":3,"n":"z","r":3,"sig":"int z()"}]}]}'
FLAT_XML='<ctx><sigs><d l="9" n="y" p="src/a.h" r="1">int y()</d><d l="1" n="x" p="src/a.h" r="2">int x()</d><d l="3" n="z" p="src/b.h" r="3">int z()</d></sigs></ctx>'
if printf '%s' "$PREFIX_XML" | check xml >/dev/null; then no "(5) the checker ACCEPTED a file-grouped XML bundle — no teeth"; else ok "(5) mutation control: the checker rejects the pre-fix file-grouped XML shape"; fi
if printf '%s' "$PREFIX_JSON" | check json >/dev/null; then no "(5) the checker ACCEPTED a file-grouped JSON bundle — no teeth"; else ok "(5) mutation control: the checker rejects the pre-fix file-grouped JSON shape"; fi
printf '%s' "$FLAT_XML" | check xml >/dev/null && ok "(5) …and accepts a flat rank-ordered bundle with p= on every row" || no "(5) the checker rejects the target shape"

# ── (6) shown= consistency, determinism, well-formedness ─────────────────────────────────────────────────
A="$( "$BIN" . --for="rank graph teleport" 2>/dev/null )"
B="$( "$BIN" . --for="rank graph teleport" 2>/dev/null )"
[ "$A" = "$B" ] && ok "(6) two runs byte-identical" || no "(6) --for is not deterministic"
shown="$( printf '%s' "$A" | grep -o '<sigs[^>]*>' | head -1 | grep -o 'shown="[0-9]*"' | tr -dc '0-9' )"
drows="$( printf '%s' "$A" | python3 -c 'import re,sys; s=sys.stdin.read(); m=re.search(r"<sigs[^>]*>(.*?)</sigs>",s,re.S); print(len(re.findall(r"<d ",m.group(1))) if m else -1)' )"
if [ -n "$shown" ]; then
    [ "$shown" = "$drows" ] && ok "(6) shown=\"$shown\" equals the $drows <d> rows printed" || no "(6) shown=\"$shown\" but $drows <d> rows printed"
else
    ok "(6) <sigs> is uncapped on this query (shown= absent by contract)"
fi
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$A" | xmllint --noout - 2>/dev/null && ok "(6) full bundle is well-formed" || no "(6) full bundle is not well-formed"
    "$BIN" . --for="rank graph teleport" --legend=compact 2>/dev/null | xmllint --noout - 2>/dev/null && ok "(6) compact bundle is well-formed" || no "(6) compact bundle is not well-formed"
else
    printf '  SKIP  xmllint (not installed)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
