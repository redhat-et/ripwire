#!/usr/bin/env bash
# forwidencheck.sh — L-W (routing-loop round, owner decision 2026-09-12): --for pages its answer ONE FILE PER
# ROW, and its next= points at that page when the answer is thin.
#
# THE DEFECT. On the pre-registered follow-up ladder (RocksDB, frozen 30), every ripwire follow-up completed
# 0 answers through step 4: --for's next= pointed at --expand (a BODY, not a wider list), --top-k was INERT
# on --for, and --format=candidates is symbol-grain (40 symbols is about 18 files in 11 KB). The one
# follow-up that completed answers in that ladder was a FILE-grain widening page (+8 completes at ~6 KB
# each, one row per file). Local telemetry: --for -> --expand was followed 0 of 259 times.
#
# THE CONTRACT this gate pins:
#   (1) `--for=TASK --limit=N` (offset=M pages) is a FILE page: one <f p= score= n= sym=/> row per file, one
#       file per row (no duplicates), root-relative p= exactly as every other verb spells it (verbatim path
#       lookup is how an answer is scored complete).
#   (2) The page is ranked file-first by a bounded union-coverage score: the fixture's gold file, whose four
#       symbols each match ONE query term, sits at file-rank 8..30 on the page and is ABSENT from the default
#       --for answer (its best symbol is weaker than twenty single-term files that outrank it in best-symbol
#       order, which is what the default's <tail> walks).
#   (3) The page is deterministic and well-formed; a cut page carries the house paging vocabulary
#       (shown= total= capped="1" has_more= next_offset=) and a next= naming the next page; the second page
#       has no row in common with the first and the pages concatenate to the wider page in order.
#   (4) coverage= rides --for's root (both dialects) and is DEFINED in the legend the reader meets first.
#   (5) next= on the r=1 row names the widening page (`--for=... --limit=40`) when the answer is THIN
#       (coverage under 50, or a ranked head spread over fewer than 3 files) and stays --expand=FILE:NAME
#       on a confident answer.
#   (6) --limit=0 and a non-numeric --limit are refused; the page refuses the bundle-shaping flags rather
#       than silently ignoring them.
#   (7) The MCP `for` twin takes the same `limit` argument and serves the same page (root attribute names
#       equal, the gold path present).
#
# RED-FIRST: every arm below was run against the pre-change binary (--limit refused outright on --for;
# no coverage=; next= always --expand) and reported FAIL before the code landed.
#
# The corpus is GENERATED here, in a temp dir this script creates and removes, so no tracked fixture
# perturbs the crawl other gates measure. Its shape (why each file group exists) is documented inline.
#
# Usage:  bash test/forwidencheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/forwidencheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
echo "forwidencheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/corpus"
mkdir -p "$FIX"

# ── the fixture ─────────────────────────────────────────────────────────────────────────────────────────
# Query terms: alpha beta gamma delta (+ zeta, which nothing carries — the S1-shaped "(#12147)" token every
# commit-subject query drags along; it lowers coverage= honestly). BM25 field weights: a name token counts
# x3, a body token x1, so a symbol's score is driven by its NAME's term frequency, saturating in tf and
# falling with document length.
#   big/  3 files x 14 symbols, each name carrying two terms at tf=9 — the top-42 symbols, so the default
#         40-row head covers exactly these three files.
#   mid/  9 files x 2 symbols, each name two terms at tf=3 — outscore every single-term symbol; each file's
#         union covers all four terms (same union-coverage as the gold, stronger best symbol: ranks ABOVE
#         the gold on the page — the gold lands at page rank 3 + 9 + 1 = 13).
#   flip/ 20 files x 1 symbol, one term at tf=9 — a stronger BEST symbol than the gold's (tf=3), so in
#         best-symbol order (the default's <tail>) all twenty sit above the gold (file rank 33 > 3 + 24
#         tail rows: absent from the default answer), but their union covers ONE term, so on the page they
#         sit below it.
#   gold/ 1 file x 4 symbols, one term each at tf=3 — the file only a union-coverage ranking surfaces.
python3 - "$FIX" <<'PY'
import os, sys
root = sys.argv[1]
def w( rel, text ):
    p = os.path.join( root, rel ); os.makedirs( os.path.dirname( p ), exist_ok=True )
    open( p, "w" ).write( text )
terms = [ "alpha", "beta", "gamma", "delta" ]
for b in range( 1, 4 ):
    body = ""
    for k in range( 1, 8 ):
        body += "int alpha_alpha_alpha_beta_beta_beta_b%d_f%02d() { return %d; }\n" % ( b, k, k )
        body += "int gamma_gamma_gamma_delta_delta_delta_b%d_f%02d() { return %d; }\n" % ( b, k, k )
    w( "big/big_%02d.cpp" % b, body )
for m in range( 1, 10 ):
    w( "mid/mid_%02d.cpp" % m, "int alpha_beta_m%02d() { return 1; }\nint gamma_delta_m%02d() { return 2; }\n" % ( m, m ) )
for f in range( 1, 21 ):
    t = terms[ ( f - 1 ) % 4 ]
    w( "flip/flip_%02d.cpp" % f, "int %s_%s_%s_f%02d() { return 0; }\n" % ( t, t, t, f ) )
w( "gold/widen_target.cpp", "".join( "int %s_target_helper() { return 3; }\n" % t for t in terms ) )
PY
GOLD="gold/widen_target.cpp"
THIN="alpha beta gamma delta zeta"
CONFIDENT="alpha beta"
[ -f "$FIX/$GOLD" ] || { no "fixture: $GOLD was not written — every arm below would be vacuous"; echo "FAILURES ABOVE"; exit 1; }
ok "fixture written: 33 files, gold at $GOLD"

run(){ "$BIN" "$FIX" --no-cache "$@" 2>"$TMP/err"; }
cat > "$TMP/rows.py" <<'PY'
# print one `p` per <f> row of the page, in document order (the page's own row order)
import re, sys
s = sys.stdin.read()
for m in re.finditer( r'<f ([^>]*)/>', s ):
    p = re.search( r'\bp="([^"]*)"', m.group( 1 ) )
    print( p.group( 1 ) if p else "?" )
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
rootattrs(){ python3 -c '
import re, sys
s = sys.stdin.read()
m = re.search( r"<(files|ctx)\b([^>]*)>", s )
print( " ".join( sorted( set( re.findall( r"\s([a-z_]+)=\"", m.group( 2 ) ) ) ) ) if m else "" )
'; }

# ── (1) the default answer does NOT carry the gold; the page does, verbatim ─────────────────────────────
run --for="$THIN" >"$TMP/default.xml"; rc=$?
[ "$rc" = 0 ] || no "(1) default --for exited $rc: $( head -c 200 "$TMP/err" )"
if grep -q "p=\"$GOLD\"" "$TMP/default.xml"; then
    no "(1) the default --for answer already names $GOLD — the fixture does not exercise widening"
else
    ok "(1) the default --for answer (head + tail) does not name $GOLD"
fi
grep -q '<tail ' "$TMP/default.xml" && ok "(1) presence guard: the default answer carries a <tail> (the file-grain surface the gold fell past)" \
                                    || no "(1) presence guard: no <tail> in the default answer — the fixture shape changed"

run --for="$THIN" --limit=40 >"$TMP/page40.xml"; rc=$?
if [ "$rc" = 0 ] && grep -q '^<files ' "$TMP/page40.xml"; then
    ok "(1) --for --limit=40 exits 0 and answers with a <files> root"
else
    no "(1) --for --limit=40 exited $rc / no <files> root: $( head -c 300 "$TMP/err" "$TMP/page40.xml" | tr '\n' ' ' )"
fi
python3 "$TMP/rows.py" <"$TMP/page40.xml" >"$TMP/page40.rows"
if grep -qx "$GOLD" "$TMP/page40.rows"; then
    ok "(1) the page names $GOLD verbatim (root-relative p=)"
else
    no "(1) the page does not name $GOLD — rows: $( tr '\n' ' ' <"$TMP/page40.rows" | cut -c1-300 )"
fi

# ── (2) file-first rank: the gold sits at 8..30 on the page ─────────────────────────────────────────────
grank="$( grep -nx "$GOLD" "$TMP/page40.rows" | cut -d: -f1 | head -1 )"
if [ -n "$grank" ] && [ "$grank" -ge 8 ] && [ "$grank" -le 30 ]; then
    ok "(2) gold file-rank on the page is $grank (expected 8..30)"
else
    no "(2) gold file-rank on the page is '${grank:-absent}' (expected 8..30)"
fi
nrows="$( grep -c . "$TMP/page40.rows" )"
[ "$nrows" -ge 30 ] && ok "(2) the page holds $nrows file rows (the fixture has 33 positive-score files)" \
                    || no "(2) the page holds only $nrows rows"
if python3 - "$TMP/page40.xml" <<'PY'
import re, sys
s = open( sys.argv[1] ).read()
rows = re.findall( r'<f ([^>]*)/>', s )
bad = [ r for r in rows if not all( re.search( r'\b%s="' % a, r ) for a in ( "p", "score", "n", "sym" ) ) ]
sys.exit( 1 if bad or not rows else 0 )
PY
then ok "(2) every row carries p= score= n= sym="
else no "(2) a row lacks one of p= score= n= sym="; fi

# ── (3) one file per row, deterministic, well-formed, paged ────────────────────────────────────────────
dups="$( sort "$TMP/page40.rows" | uniq -d | grep -c . )"
[ "$dups" = 0 ] && [ "$nrows" -ge 30 ] && ok "(3) one row per file: no duplicate p= among $nrows rows" || no "(3) $dups duplicate file row(s) on the page (rows=$nrows)"
run --for="$THIN" --limit=40 >"$TMP/page40b.xml"
[ -s "$TMP/page40.xml" ] && cmp -s "$TMP/page40.xml" "$TMP/page40b.xml" && ok "(3) two runs are byte-identical (determinism)" || no "(3) two runs of the same page differ (or the page is empty)"
xmllint --noout "$TMP/page40.xml" 2>/dev/null && ok "(3) the page is well-formed XML" || no "(3) the page is not well-formed XML"

run --for="$THIN" --limit=10 >"$TMP/p1.xml"
run --for="$THIN" --limit=10 --offset=10 >"$TMP/p2.xml"
root1="$( grep -o '^<files [^>]*>' "$TMP/p1.xml" )"
for a in 'shown="10"' 'capped="1"' 'has_more="1"' 'next_offset="10"' 'total="' 'offset="0"' 'limit="10"'; do
    printf '%s' "$root1" | grep -q "$a" || no "(3) --limit=10 root lacks $a: $( printf '%s' "$root1" | cut -c1-300 )"
done
printf '%s' "$root1" | grep -q 'next="[^"]*--limit=10 --offset=10"' \
    && ok "(3) a cut page carries shown/capped/total/has_more/next_offset and next= naming the next page" \
    || no "(3) --limit=10 root has no next= naming '--limit=10 --offset=10': $( printf '%s' "$root1" | grep -o 'next="[^"]*"' )"
python3 "$TMP/rows.py" <"$TMP/p1.xml" >"$TMP/p1.rows"; python3 "$TMP/rows.py" <"$TMP/p2.xml" >"$TMP/p2.rows"
overlap="$( sort "$TMP/p1.rows" "$TMP/p2.rows" | uniq -d | grep -c . )"
[ "$overlap" = 0 ] && [ "$( grep -c . "$TMP/p2.rows" )" = 10 ] \
    && ok "(3) the second page has no row in common with the first and holds 10 rows" \
    || no "(3) page overlap=$overlap, page-2 rows=$( grep -c . "$TMP/p2.rows" )"
cat "$TMP/p1.rows" "$TMP/p2.rows" >"$TMP/p12.rows"
[ "$( grep -c . "$TMP/p12.rows" )" = 20 ] && head -20 "$TMP/page40.rows" | cmp -s - "$TMP/p12.rows" \
    && ok "(3) pages 1+2 (limit 10) equal the first 20 rows of the limit-40 page, in order" \
    || no "(3) pages 1+2 do not concatenate to the limit-40 page's first 20 rows"
grep -q 'has_more="0"' "$TMP/page40.xml" && ok "(3) the limit-40 page over 33 files says has_more=\"0\"" \
                                          || no "(3) the limit-40 page over 33 files does not say has_more=\"0\": $( grep -o '^<files [^>]*>' "$TMP/page40.xml" | cut -c1-300 )"

# ── (4) coverage= on the root, defined where the reader meets it ───────────────────────────────────────
for dialect in "" "--legend=compact"; do
    run --for="$THIN" $dialect >"$TMP/cov.xml"
    root="$( grep -o '^<ctx [^>]*>' "$TMP/cov.xml" )"
    legend="$( grep -o '<!--.*-->' "$TMP/cov.xml" | head -1 )"
    label="default dialect"; [ -n "$dialect" ] && label="compact dialect"
    if printf '%s' "$root" | grep -q ' coverage="[0-9][0-9]*"'; then
        ok "(4) $label: --for's root carries coverage=\"N\" ($( printf '%s' "$root" | grep -o 'coverage="[0-9]*"' ))"
    else
        no "(4) $label: --for's root has no coverage=: $( printf '%s' "$root" | cut -c1-200 )"
    fi
    printf '%s' "$legend" | grep -q 'coverage=' && ok "(4) $label: the leading legend defines coverage=" \
                                                 || no "(4) $label: the leading legend never spells coverage="
done
groot="$( grep -o '^<files [^>]*>' "$TMP/page40.xml" )"
printf '%s' "$groot" | grep -q ' coverage="[0-9][0-9]*"' && ok "(4) the page root carries coverage= too" || no "(4) the page root lacks coverage="
grep -o '<!--.*-->' "$TMP/page40.xml" | head -1 | grep -q 'coverage=' && ok "(4) the page legend defines coverage=" || no "(4) the page legend never spells coverage="
# the thin query's top symbol carries 2 of 5 terms (zeta is absent, and absent terms weigh most): under 50
covthin="$( grep -o '^<ctx [^>]*>' "$TMP/default.xml" | grep -o 'coverage="[0-9]*"' | tr -dc '0-9' )"
[ -n "$covthin" ] && [ "$covthin" -lt 50 ] && ok "(4) thin query: coverage=$covthin (under 50)" || no "(4) thin query: coverage='${covthin:-absent}' (expected under 50)"

# ── (5) next= names the page on a thin answer, --expand on a confident one ─────────────────────────────
top="$( grep -o '<d [^>]*r="1"[^>]*>' "$TMP/default.xml" | head -1 )"
thinnext="$( printf '%s' "$top" | grep -o 'next="[^"]*"' )"
if printf '%s' "$thinnext" | grep -q 'next="--for=' && printf '%s' "$thinnext" | grep -q -- '--limit=40"'; then
    ok "(5) thin answer: the r=1 row's next= names the widening page ($thinnext)"
else
    no "(5) thin answer: the r=1 row's next= is '${thinnext:-absent}' — expected --for=... --limit=40"
fi
run --for="$CONFIDENT" >"$TMP/conf.xml"
croot="$( grep -o '^<ctx [^>]*>' "$TMP/conf.xml" )"
covconf="$( printf '%s' "$croot" | grep -o 'coverage="[0-9]*"' | tr -dc '0-9' )"
[ -n "$covconf" ] && [ "$covconf" -ge 50 ] && ok "(5) confident query: coverage=$covconf (50 or more)" || no "(5) confident query: coverage='${covconf:-absent}' (expected 50 or more)"
ctop="$( grep -o '<d [^>]*r="1"[^>]*>' "$TMP/conf.xml" | head -1 )"
printf '%s' "$ctop" | grep -q 'next="--expand=' && ok "(5) confident answer: the r=1 row keeps next=\"--expand=FILE:NAME\"" \
                                                 || no "(5) confident answer: the r=1 row's next= is '$( printf '%s' "$ctop" | grep -o 'next="[^"]*"' )'"
others="$( grep -o '<d [^>]*next=' "$TMP/default.xml" | grep -vc 'r="1"' || true )"
[ "$others" = 0 ] && ok "(5) next= rides the top row only" || no "(5) $others non-top row(s) carry next="
# the hint pastes: the ladder splits it with shlex, so the task must be quoted as a shell would
hint="$( printf '%s' "$thinnext" | sed 's/^next="//; s/"$//' )"
if [ -n "$hint" ]; then
    if python3 - "$BIN" "$FIX" "$hint" "$TMP/page40.xml" <<'PY'
import html, shlex, subprocess, sys
binp, fix, hint, page = sys.argv[1:5]
argv = shlex.split( html.unescape( hint ) )
r = subprocess.run( [ binp, fix, "--no-cache" ] + argv, capture_output=True )
sys.exit( 0 if r.returncode == 0 and r.stdout == open( page, "rb" ).read() else 1 )
PY
    then ok "(5) the pasted next= (shlex-split) reproduces the limit-40 page byte for byte"
    else no "(5) the pasted next= does not reproduce the limit-40 page: $hint"; fi
fi

# ── (6) refusals ────────────────────────────────────────────────────────────────────────────────────────
run --for="$THIN" --limit=0 >/dev/null; rc=$?
[ "$rc" != 0 ] && grep -q -- '--limit' "$TMP/err" && ok "(6) --limit=0 is refused (rc=$rc)" || no "(6) --limit=0 not refused: rc=$rc $( head -c 160 "$TMP/err" )"
run --for="$THIN" --limit=abc >/dev/null; rc=$?
[ "$rc" != 0 ] && grep -q -- '--limit' "$TMP/err" && ok "(6) --limit=abc is refused (rc=$rc)" || no "(6) --limit=abc not refused: rc=$rc $( head -c 160 "$TMP/err" )"
for flag in --json --format=candidates --detail=1 --signatures-only --token-budget=2000; do
    run --for="$THIN" --limit=5 $flag >"$TMP/shape.out"; rc=$?
    if [ "$rc" != 0 ] && [ ! -s "$TMP/shape.out" ]; then
        ok "(6) the page refuses $flag rather than ignoring it (rc=$rc)"
    else
        no "(6) the page accepted $flag: rc=$rc, $( wc -c <"$TMP/shape.out" | tr -d ' ' ) bytes on stdout, stderr: $( head -c 160 "$TMP/err" )"
    fi
done

# ── (7) the MCP twin serves the same page ──────────────────────────────────────────────────────────────
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s","limit":40}}}\n' \
       "$FIX" "$THIN" | "$BIN" --mcp 2>/dev/null | python3 "$TMP/mcptext.py" >"$TMP/mcp.xml"
if grep -q '^<files ' "$TMP/mcp.xml"; then
    ok "(7) MCP for + limit answers with the <files> page"
else
    no "(7) MCP for + limit did not answer with a <files> page: $( head -c 300 "$TMP/mcp.xml" | tr '\n' ' ' )"
fi
python3 "$TMP/rows.py" <"$TMP/mcp.xml" >"$TMP/mcp.rows"
grep -qx "$GOLD" "$TMP/mcp.rows" && ok "(7) the MCP page names $GOLD" || no "(7) the MCP page does not name $GOLD"
[ -s "$TMP/page40.rows" ] && cmp -s "$TMP/mcp.rows" "$TMP/page40.rows" && ok "(7) the MCP page's rows equal the CLI page's rows, in order" \
                                          || no "(7) the MCP page's rows differ from the CLI page's"
cattrs="$( rootattrs <"$TMP/page40.xml" )"; mattrs="$( rootattrs <"$TMP/mcp.xml" )"
[ -n "$cattrs" ] && [ "$cattrs" = "$mattrs" ] && ok "(7) page root attribute names agree across the two dialects ($cattrs)" \
                                                || no "(7) page root attribute names differ — CLI: [$cattrs] MCP: [$mattrs]"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
