#!/usr/bin/env bash
# importrowshortcheck.sh — IMPORT-ROW-SHORT (2026-11-18): an --impact importer row prints `<f p="…"/>`, with lazy="1" only
# when it is 1, and the saving is LOSSLESS.
#
# WHAT THIS GUARDS. --impact lists the files that import a file defining SYM as <f> rows. Every one was printed
# `<f via="import" p="…" lazy="0|1"/>`. `via="import"` was a string literal in the one emitter that prints the row
# (serialize.h emitImportRowsXml), so it could not differ between two rows, and lazy="0" is the default arm of a two-valued
# flag: 2,898 of 2,898 rows carried the literal and 2,844 of them lazy="0", over 264 --impact answers (24 graded, 240 drawn). The
# row is now `<f p="…"/>`, and `<f p="…" lazy="1"/>` when every one of that importer's edges is lazy. The bar this gate
# holds is not the byte saving. It is that the dropped bytes can be put back from the delivered answer alone, by a rule
# that reads ONE row and nothing else, and that the result is, byte for byte, what the binary printed before the change.
#
# TWO INDEPENDENT REFERENCES, never one:
#   1. GOLDENS captured from the binary before the change (994f0021f) on the fixtures below, committed under
#      test/importrowshortfix/golden/. The comparison is over the WHOLE <impact> element, so a row that moved, a count
#      that moved, or a neighbour that moved are all the same failure.
#   2. the --json dialect's import_reach array for the same selector, from the binary under test (a different emitter,
#      which still spells via and lazy on every entry).
#
# ARMS
#   (A)  the fixtures exist and hold the importers the arms below count (the non-vacuity anchor: `IMPORTER` markers)
#   (B)  XML importer rows: rebuilt == golden (LOSSLESS) and no row carries the dropped bytes (SHORT), three corpora
#   (C)  the same rows against --json import_reach; and the --json document did not move
#   (D)  non-vacuity: the rows read are the fixture's own marked importers, and the lazy ones are the fixture's lazy ones
#   (E)  the dialects that must NOT move: --json and --format=columnar, byte for byte against the goldens
#   (F)  a path with a space as a whole value; absence keeps one meaning (a row with no lazy= is never a lazy importer)
#   (G)  mutation controls, each of which MUST go red: a deleted row, a changed path, a lazy flag added, a lazy flag
#        removed, the golden fed in as if it were new output, an empty document (the count floor)
#   (K)  a cut tier: importers= still counts every importer, the rows shown are short rows
#   (L)  the legend reads the new form exactly where a row carries it, and nowhere else
#   (M)  the MCP impact verb prints the same rows
#   (N)  determinism and well-formedness
#   (S)  at scale, when a legacy binary and corpora are handed in (RIPWIRE_IMPORTROW_REF, RIPWIRE_IMPORTROW_CORPORA)
set -u
BIN="${RIPWIRE_BIN:-${1:-./build/ripwire}}"
if [ ! -x "$BIN" ]; then echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; fi
case "$BIN" in /*) ;; *) BIN="$( cd "$( dirname "$BIN" )" && pwd )/$( basename "$BIN" )" ;; esac
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
RECON="$ROOT/test/lib/importrowrecon.py"
GOLD="$ROOT/test/importrowshortfix/golden"
JSFIX="$ROOT/test/impactimportfix"
export PYTHONDONTWRITEBYTECODE=1
export LC_ALL=C

fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
recon(){ python3 "$RECON" "$@"; }
[ -d "$JSFIX" ] || { echo "no test/impactimportfix dir — fixture missing"; exit 2; }

# ── (A) the fixtures. Every file that imports the target's file carries the word IMPORTER on the importing line, so the
#    arms below can count the importers they are supposed to have read from the fixture itself. The goldens were captured
#    on exactly these bytes. The JS corpus is the committed test/impactimportfix (impactimportcheck's), whose two lazy
#    importers (lazyimporter.js, barrel.js) are the only lazy="1" rows any arm reads.
echo "=== A: fixtures ==="
mkdir -p "$TMP/c" "$TMP/py/my dir" "$TMP/py/pkg" "$TMP/cap"
printf 'int target( int x );\n' >"$TMP/c/lib.h"
printf '#include "lib.h" /* IMPORTER */\nint target( int x ) { return x + 1; }\n' >"$TMP/c/lib.c"
for f in a b d; do printf '#include "lib.h" /* IMPORTER */\nint %s_user( void ) { return target( 1 ); }\n' "$f" >"$TMP/c/$f.c"; done
printf '#include "lib.h" /* IMPORTER */\nint unrelated( void ) { return 2; }\n' >"$TMP/c/e.c"
printf 'def target(x):\n    return x + 1\n' >"$TMP/py/lib.py"
printf 'from lib import target  # IMPORTER\ndef spaced():\n    return target(1)\n' >"$TMP/py/my dir/sp.py"
printf 'import lib  # IMPORTER\ndef dotted():\n    return lib.target(2)\n' >"$TMP/py/pkg/own.py"
printf 'from lib import target as renamed  # IMPORTER\ndef aliased():\n    return renamed(4)\n' >"$TMP/py/alias.py"
printf 'def loner():\n    return 3\n' >"$TMP/py/none.py"
printf 'int target( int x );\n' >"$TMP/cap/lib.h"
printf '#include "lib.h" /* IMPORTER */\nint target( int x ) { return x + 1; }\n' >"$TMP/cap/lib.c"
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
    printf '#include "lib.h" /* IMPORTER */\nint u%s( void ) { return 2; }\n' "$i" >"$TMP/cap/u$i.c"
done
marked(){ grep -rc 'IMPORTER' "$TMP/$1" | awk -F: '{ n += $NF } END { print n + 0 }'; }
dir(){ [ "$1" = js ] && echo "$JSFIX" || echo "$TMP/$1"; }
sym(){ [ "$1" = js ] && echo Widget || echo target; }
run(){ ( cd "$( dir "$1" )" && shift && "$BIN" . --no-cache "$@" ); }   # run CORPUS args... -> stdout, root "." as the goldens have it
jsreq="$( grep -lE 'require\("\./Widget"\)|import Widget from "\./Widget\.js"' "$JSFIX"/lib/*.js 2>/dev/null | wc -l | tr -d ' ' )"
if [ "$( marked c )" = 5 ] && [ "$( marked py )" = 3 ] && [ "$( marked cap )" = 26 ] && [ "$jsreq" = 7 ]; then
    ok "(A) four corpora: 5 + 3 + 26 marked importing lines, and 7 files of test/impactimportfix that spell an import of ./Widget"
else
    no "(A) fixture markers: c=$( marked c ) py=$( marked py ) cap=$( marked cap ) js=$jsreq, want 5 3 26 7"
fi
lim(){ [ "$1" = cap ] && echo --limit=5; return 0; }   # the cap corpus is read through a 5-row window; expanded UNQUOTED below, so nothing is no argument
for d in c py js cap; do
    run "$d" "--impact=$( sym "$d" )" $( lim "$d" ) >"$TMP/$d.impact.xml" 2>"$TMP/$d.impact.err" || no "(A) --impact on the $d fixture exits non-zero: $( head -c 200 "$TMP/$d.impact.err" )"
    run "$d" "--impact=$( sym "$d" )" $( lim "$d" ) --json >"$TMP/$d.impact.json" 2>/dev/null
done
want(){ case "$1" in c) echo 5 ;; py) echo 3 ;; js) echo 7 ;; cap) echo 5 ;; esac; }

# ── (B) LOSSLESS + SHORT against the goldens ─────────────────────────────────────────────────────────────────────────
echo "=== B: rebuilt from the delivered answer == the pre-change golden, over the whole <impact> element ==="
for d in c py js cap; do
    if out="$( recon xml "$TMP/$d.impact.xml" "$GOLD/$d.impact.xml" "$( want "$d" )" )"; then ok "(B) $d: ${out##*$'\n'}"
    else no "(B) $d importer rows:"; printf '%s\n' "$out" | head -6 | sed 's/^/        /'; fi
done

# ── (C) the second reference: --json import_reach, a different emitter in the same binary ────────────────────────────
echo "=== C: the same rows against --json import_reach ==="
for d in c py js cap; do
    if out="$( recon json "$TMP/$d.impact.xml" "$TMP/$d.impact.json" "$( want "$d" )" )"; then ok "(C) $d: ${out##*$'\n'}"
    else no "(C) $d vs --json:"; printf '%s\n' "$out" | head -6 | sed 's/^/        /'; fi
done

# ── (D) non-vacuity: what was read is what the fixture holds ─────────────────────────────────────────────────────────
echo "=== D: non-vacuity, counted from the fixture ==="
for d in c py; do
    got="$( recon count "$TMP/$d.impact.xml" )"; m="$( marked "$d" )"
    if [ "$got" = "rows=$m lazy=0 short=$m" ]; then ok "(D) $d: $got == the fixture's $m marked importers, every one a short row"
    else no "(D) $d: $got, want rows=$m lazy=0 short=$m"; fi
done
got="$( recon count "$TMP/js.impact.xml" )"
if [ "$got" = "rows=7 lazy=2 short=7" ]; then ok "(D) js: $got == 7 importers of ./Widget, 2 of them lazy"
else no "(D) js: $got, want rows=7 lazy=2 short=7"; fi
JSB="$( sed 's/<!--.*-->//' "$TMP/js.impact.xml" )"
case "$JSB" in *'<f p="lib/barrel.js" lazy="1"/>'*'<f p="lib/lazyimporter.js" lazy="1"/>'*)
        ok "(D) js: the two lazy rows are barrel.js and lazyimporter.js, the two files whose require sits in a function body" ;;
    *)  no "(D) js: the lazy rows: $( printf '%s' "$JSB" | grep -o '<f [^>]*lazy[^>]*>' | tr '\n' ' ' )" ;; esac

# ── (E) the dialects that must not move ──────────────────────────────────────────────────────────────────────────────
echo "=== E: --json and --format=columnar are byte-identical to the pre-change binary's ==="
for d in c py js; do
    if cmp -s "$TMP/$d.impact.json" "$GOLD/$d.impact.json.golden"; then ok "(E) $d --json: byte-identical (it is the reference of arm C, so it must not have moved)"
    else no "(E) $d --json moved; this change must not touch it"; fi
done
run js --impact=Widget --format=columnar >"$TMP/js.columnar.xml" 2>/dev/null
if [ -s "$TMP/js.columnar.xml" ] && [ "$( sed 's/<!--.*-->//' "$TMP/js.columnar.xml" )" = "$( sed 's/<!--.*-->//' "$GOLD/js.impact.columnar.xml" )" ]; then
    ok "(E) js columnar: the element is byte-identical (it prints no importer row)"
else no "(E) js columnar element moved"; fi

# ── (F) a path with a space; absence ─────────────────────────────────────────────────────────────────────────────────
echo "=== F: a path with a space; a row with no lazy= ==="
PYB="$( sed 's/<!--.*-->//' "$TMP/py.impact.xml" )"
GPY="$( sed 's/<!--.*-->//' "$GOLD/py.impact.xml" )"
case "$GPY" in *'<f via="import" p="my dir/sp.py" lazy="0"/>'*) premise=1 ;; *) premise=0 ;; esac
case "$PYB" in *'<f p="my dir/sp.py"/>'*)
        # decided BEFORE anything is written (gateexitcheck G2: a failed WRITE of the PASS line must not print FAIL)
        if [ "$premise" = 1 ]; then
            ok "(F) my dir/sp.py: the golden's <f via=\"import\" p=\"my dir/sp.py\" lazy=\"0\"/> is now <f p=\"my dir/sp.py\"/>"
        else
            no "(F) premise: the golden does not hold the spaced row"
        fi ;;
    *) no "(F) the spaced row: $( printf '%s' "$PYB" | grep -o '<f [^>]*sp\.py[^>]*>' )" ;; esac
nolazy="$( printf '%s' "$JSB" | grep -o '<f p="[^"]*"/>' | tr '\n' ' ' )"
case "$nolazy" in *barrel.js*|*lazyimporter.js*) no "(F) a lazy importer is printed with no lazy=: $nolazy" ;;
    *'lib/alpha.js'*'lib/beta.js'*'lib/delta.js'*'lib/gamma.js'*'lib/user.js'*) ok "(F) absence keeps one meaning: the five rows with no lazy= are the five top-level importers, never a lazy one" ;;
    *) no "(F) the rows with no lazy=: $nolazy" ;; esac

# ── (G) mutation controls: each must go RED, and for the stated reason ───────────────────────────────────────────────
echo "=== G: mutation controls (each must fail) ==="
mutant(){   # mutant LABEL WANT_CLASS SED_EXPR: mutate the delivered js answer, require a real change, require the named failure
    local label="$1" want="$2" expr="$3" src="$TMP/js.impact.xml" out
    sed "$expr" "$src" >"$TMP/mut.xml"
    if cmp -s "$src" "$TMP/mut.xml"; then no "(G) $label: the mutation changed nothing, so it proves nothing"; return; fi
    if out="$( recon xml "$TMP/mut.xml" "$GOLD/js.impact.xml" 7 )"; then no "(G) $label: the reconstruction PASSED a corrupted answer"
    elif printf '%s\n' "$out" | grep -q "^$want"; then ok "(G) $label -> RED ($( printf '%s\n' "$out" | grep -m1 "^$want" | cut -c1-110 ))"
    else no "(G) $label: red, but not for the reason under test: $( printf '%s\n' "$out" | head -2 | tr '\n' ' ' )"; fi
}
mutant "a deleted importer row (gamma.js)"            'LOSSLESS COUNT' 's|<f p="lib/gamma.js"/>||'
mutant "a changed path (beta.js -> bet4.js)"          'LOSSLESS ROW'   's|<f p="lib/beta.js"/>|<f p="lib/bet4.js"/>|'
mutant "a lazy flag added (alpha.js)"                 'LOSSLESS ROW'   's|<f p="lib/alpha.js"/>|<f p="lib/alpha.js" lazy="1"/>|'
mutant "a lazy flag removed (barrel.js)"              'LOSSLESS ROW'   's|<f p="lib/barrel.js" lazy="1"/>|<f p="lib/barrel.js"/>|'
mutant "a moved count outside the rows (importers=7)" 'LOSSLESS ELEMENT' 's| importers="7"| importers="8"|'
if out="$( recon xml "$GOLD/js.impact.xml" "$GOLD/js.impact.xml" 7 )"; then no "(G) the golden fed in as new output PASSED: the gate cannot tell the old form from the new"
elif printf '%s\n' "$out" | grep -q '^SHORT ROW' && ! printf '%s\n' "$out" | grep -q '^LOSSLESS'; then ok "(G) the golden fed in as new output -> RED (SHORT only: lossless but not shortened)"
else no "(G) golden-as-new: $( printf '%s\n' "$out" | head -2 | tr '\n' ' ' )"; fi
: >"$TMP/empty.xml"
if out="$( recon xml "$TMP/empty.xml" "$TMP/empty.xml" 1 )"; then no "(G) an empty document against an empty reference PASSED (no count floor)"
elif printf '%s\n' "$out" | grep -q '^FLOOR'; then ok "(G) an empty document -> RED (the count floor: 0 importer rows)"
else no "(G) empty document: $out"; fi
if out="$( recon json "$TMP/empty.xml" "$TMP/js.impact.json" 1 )"; then no "(G) an empty document PASSED the --json reference"
else ok "(G) an empty document against --json -> RED"; fi
sed 's|<f p="lib/barrel.js" lazy="1"/>|<f p="lib/barrel.js"/>|' "$TMP/js.impact.xml" >"$TMP/mut.xml"
if out="$( recon json "$TMP/mut.xml" "$TMP/js.impact.json" 7 )"; then no "(G) a removed lazy flag PASSED the --json reference"
elif printf '%s\n' "$out" | grep -q '^JSON ROW'; then ok "(G) a removed lazy flag against --json -> RED (the second reference catches it alone)"
else no "(G) removed lazy flag vs --json: $out"; fi

# ── (K) the cut tier ─────────────────────────────────────────────────────────────────────────────────────────────────
echo "=== K: a cut tier ==="
CAPB="$( sed 's/<!--.*-->//' "$TMP/cap.impact.xml" )"
capRows="$( printf '%s' "$CAPB" | grep -o '<f p="[^"]*"/>' | wc -l | tr -d ' ' )"
case "$CAPB" in *' importers="26" shown_importers="5" importers_capped="1"'*)
        if [ "$capRows" = 5 ]; then
            ok "(K) 26 marked importers, 5 printed as short rows under --limit=5, importers=\"26\" ($( marked cap ) in the fixture)"
        else
            no "(K) the cut tier prints $capRows short row(s), want 5"
        fi ;;
    *)  no "(K) the cut root: $( printf '%s' "$CAPB" | grep -o ' importers="[^"]*" shown_importers="[^"]*" importers_capped="[^"]*"' )" ;;
esac

# ── (L) the legend ───────────────────────────────────────────────────────────────────────────────────────────────────
echo "=== L: the legend reads the form the rows are in ==="
legend(){ grep -o '<!--.*-->' "$1"; }
if legend "$TMP/js.impact.xml" | grep -qF '<f p=> importers'; then ok "(L) the default legend of an impact answer names the importer row as <f p=>"
else no "(L) default impact legend: $( legend "$TMP/js.impact.xml" | grep -o '[^;]*importers[^;]*' | head -1 )"; fi
if legend "$TMP/js.impact.xml" | grep -qF 'lazy=1'; then ok "(L) an answer that carries a lazy=\"1\" row reads it"
else no "(L) the js answer carries lazy=\"1\" rows and no reading of lazy="; fi
NOLAZY='<f> with no lazy=: at least one of its edges into a def file is load-time'
if legend "$TMP/c.impact.xml" | grep -qF '<f lazy=1>:'; then no "(L) an answer with no lazy= row carries the <f lazy=1> clause (present-only broke)"
elif legend "$TMP/c.impact.xml" | grep -qF "$NOLAZY"; then ok "(L) present-only: an answer with no lazy= row carries no <f lazy=1> clause, and still says what a row with no lazy= claims"
else no "(L) an answer with importer rows does not say what a row with no lazy= claims: $( legend "$TMP/c.impact.xml" | grep -o '[^.]*<f>[^.]*' | head -1 )"; fi
printf 'int lonely( int x ) { return x; }\nint caller( void ) { return lonely( 1 ); }\n' >"$TMP/c/solo.c"
run c --impact=lonely >"$TMP/c.none.xml" 2>/dev/null; rm -f "$TMP/c/solo.c"
if ! grep -q ' importers="0"' "$TMP/c.none.xml"; then no "(L) premise: --impact=lonely was meant to have no importer: $( sed 's/<!--.*-->//' "$TMP/c.none.xml" | head -c 200 )"
elif legend "$TMP/c.none.xml" | grep -q 'lazy='; then no "(L) an answer with NO importer row pays for a reading of lazy="
else ok "(L) an answer with no importer row carries no reading of lazy= at all"; fi
run js --impact=Widget --legend=full >"$TMP/js.full.xml" 2>/dev/null
if legend "$TMP/js.full.xml" | grep -qF '<f p="…"/> rows after the symbol rows' && legend "$TMP/js.full.xml" | grep -qF 'no lazy= means at least one edge is load-time' \
   && [ "$( sed 's/<!--.*-->//' "$TMP/js.full.xml" | grep -o '<f [^>]*/>' )" = "$( printf '%s' "$JSB" | grep -o '<f [^>]*/>' )" ]; then
    ok "(L) --legend=full carries the long reading, and the rows are the same rows"
else no "(L) --legend=full: $( legend "$TMP/js.full.xml" | grep -o 'importers= is a SECOND[^.]*\.' | head -1 )"; fi
if grep -l 'via="import"\|via=\\"import\\"\|lazy="0|1"\|<f via= p=>' "$TMP"/*.xml >/dev/null 2>&1; then no "(L) an XML answer still spells the pre-change row: $( grep -l 'via="import"\|lazy="0|1"\|<f via= p=>' "$TMP"/*.xml | tr '\n' ' ' )"
else ok "(L) no XML answer spells the pre-change row, in a row or in a legend"; fi

# ── (M) the MCP twin ─────────────────────────────────────────────────────────────────────────────────────────────────
echo "=== M: the MCP impact verb ==="
REQ='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"impact","arguments":{"symbol":"Widget"}}}'
MCP_OUT="$( printf '%s\n' "$REQ" | ( cd "$JSFIX" && perl -e 'alarm 60; exec @ARGV' "$BIN" . --mcp --no-cache 2>/dev/null ) )"
if printf '%s' "$MCP_OUT" | grep -q '<f p=\\"lib/alpha.js\\"/>' && printf '%s' "$MCP_OUT" | grep -q '<f p=\\"lib/barrel.js\\" lazy=\\"1\\"/>' \
   && ! printf '%s' "$MCP_OUT" | grep -q '<f via='; then
    ok "(M) the MCP impact verb prints the same short rows, lazy=\"1\" on the lazy importer only"
else no "(M) MCP impact rows: $( printf '%s' "$MCP_OUT" | grep -o '<f [^>]*>' | head -3 | tr '\n' ' ' )"; fi

# ── (N) determinism + well-formedness ────────────────────────────────────────────────────────────────────────────────
echo "=== N: determinism, well-formedness ==="
det=0
for d in c py js cap; do
    run "$d" "--impact=$( sym "$d" )" $( lim "$d" ) >"$TMP/$d.again.xml" 2>/dev/null
    cmp -s "$TMP/$d.impact.xml" "$TMP/$d.again.xml" || { det=1; no "(N) $d: two runs differ"; }
done
[ "$det" = 0 ] && [ -s "$TMP/c.impact.xml" ] && ok "(N) two runs are byte-identical (XML x4)"
if command -v xmllint >/dev/null 2>&1; then
    wf=0
    for f in c.impact.xml py.impact.xml js.impact.xml cap.impact.xml js.full.xml; do
        xmllint --noout "$TMP/$f" 2>/dev/null || { wf=1; no "(N) $f is not well-formed"; }
    done
    [ "$wf" = 0 ] && ok "(N) every answer pipes clean through xmllint (5 documents)"
else
    printf '  SKIP  (N) xmllint is not installed: well-formedness is not checked on this machine\n'
fi

# ── (S) at scale, against a legacy binary's LIVE output ──────────────────────────────────────────────────────────────
#    RIPWIRE_IMPORTROW_REF=<a binary built before this change>  RIPWIRE_IMPORTROW_CORPORA="dir dir ..."  [RIPWIRE_IMPORTROW_SYMS=N]
echo "=== S: at scale ==="
if [ -z "${RIPWIRE_IMPORTROW_REF:-}" ] || [ -z "${RIPWIRE_IMPORTROW_CORPORA:-}" ]; then
    printf '  SKIP  (S) RIPWIRE_IMPORTROW_REF / RIPWIRE_IMPORTROW_CORPORA not set: arms B-N are the proof on this run\n'
else
    for corpus in $RIPWIRE_IMPORTROW_CORPORA; do
        cn="$( basename "$corpus" )"; rows=0; answers=0; sbad=0; saved=0; total=0
        "$BIN" "$corpus" >"$TMP/s.map" 2>/dev/null
        for s in $( grep -o '<s [^>]* n="[A-Za-z_][A-Za-z0-9_]*"' "$TMP/s.map" | sed 's/.* n="//; s/"$//' | awk 'length( $0 ) >= 4 && !seen[$0]++' | head -n "${RIPWIRE_IMPORTROW_SYMS:-40}" ); do
            "$BIN" "$corpus" "--impact=$s" >"$TMP/s.new" 2>/dev/null; "$RIPWIRE_IMPORTROW_REF" "$corpus" "--impact=$s" >"$TMP/s.old" 2>/dev/null
            n="$( recon count "$TMP/s.new" | sed 's/rows=\([0-9]*\).*/\1/' )"
            [ "${n:-0}" -gt 0 ] || continue
            answers=$(( answers + 1 )); rows=$(( rows + n ))
            if ! out="$( recon xml "$TMP/s.new" "$TMP/s.old" 1 )"; then sbad=$(( sbad + 1 )); [ "$sbad" -le 2 ] && printf '        %s --impact=%s: %s\n' "$cn" "$s" "$( printf '%s' "$out" | head -1 )"; fi
            a="$( sed 's/<!--.*-->//' "$TMP/s.old" | wc -c | tr -d ' ' )"; b="$( sed 's/<!--.*-->//' "$TMP/s.new" | wc -c | tr -d ' ' )"
            saved=$(( saved + a - b )); total=$(( total + a ))
        done
        if [ "$answers" -lt 1 ]; then no "(S) $cn: no --impact answer with an importer row was drawn (a floor, not a pass)"
        elif [ "$sbad" = 0 ]; then ok "(S) $cn: $answers answer(s), $rows importer row(s), every <impact> element rebuilt byte for byte; $saved of $total B shorter"
        else no "(S) $cn: $sbad of $answers answer(s) did not rebuild"; fi
    done
fi

echo
if [ "$fail" -eq 0 ]; then echo "importrowshortcheck: ALL PASS"; else echo "importrowshortcheck: FAILED"; fi
exit "$fail"
