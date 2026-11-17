#!/usr/bin/env bash
# sitesatshortcheck.sh — SITES-SHORT (2026-11-17): a caller row's sites_at= prints a call site in the row's OWN file as a
# bare line, and the saving is LOSSLESS.
#
# WHAT THIS GUARDS. A caller row carries p="file:line" (where the caller is DEFINED) and sites_at=, its call sites. Every
# site used to be a full `file:line` token whose file repeated the p= beside it: measured on the registered census,
# 12,828 B over 383 of 383 rows, 12.4% of the callers verb; 0 tokens named another file in 519,363 tokens over 17
# corpora. src/sitetokens.h now prints the bare line when the site's file EQUALS the row's p= file as a string, and the
# full token otherwise. The bar this gate holds is not the byte saving. It is that the dropped bytes can be put back
# from the delivered answer alone, and that the result is, byte for byte, what the binary printed before the change.
#
# TWO INDEPENDENT REFERENCES, never one:
#   1. GOLDENS captured from the binary before the change (origin/main 5139f7840) on the fixtures built below, committed
#      under test/sitesatshortfix/golden/. The legacy side is compared as a WHOLE attribute value, never split on
#      whitespace: `my dir/sp.py:3 my dir/sp.py:4` has no unambiguous split, which is the old form's own defect.
#   2. the uses verb's role="call" rows for the same selector, from the binary under test (a different emitter).
#
# ARMS
#   (A)  the fixtures exist and hold the call sites the arms below count (the non-vacuity anchor: `SITE` markers)
#   (B)  XML callers rows: rebuilt == golden (LOSSLESS) and own-file rows are bare-line lists (SHORT), four corpora
#   (C)  the same rows against the uses verb's role="call" sites
#   (D)  non-vacuity: the tokens the arms read are the fixture's own marked sites, all bare, none full
#   (E)  the other dialects that print the same tokens: safe-delete, --json, --format=columnar
#   (F)  a path with a space and a path with an all-digit fragment, pinned as whole values; absence keeps its meaning
#   (G)  mutation controls, each of which MUST go red: a corrupted line digit, a deleted site token, a changed row p=,
#        the golden fed in as if it were new output, an empty document (the count floor)
#   (U)  the rows no index produces (test/sitesatshort_unit.cpp): a cross-file site keeps its FULL token, a mixed row
#        prints a mix, and a foreign path with an all-digit fragment prints the whole row in the full form
#   (K)  a cut list: sites_total= still counts every site, the 16 shown are bare lines
#   (L)  the legend reads the new form exactly where a row carries it, and nowhere else
#   (N)  determinism and well-formedness
#   (S)  at scale, when a legacy binary and corpora are handed in (RIPWIRE_SITESAT_REF, RIPWIRE_SITESAT_CORPORA)
set -u
BIN="${RIPWIRE_BIN:-${1:-./build/ripwire}}"
if [ ! -x "$BIN" ]; then echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; fi
case "$BIN" in /*) ;; *) BIN="$( cd "$( dirname "$BIN" )" && pwd )/$( basename "$BIN" )" ;; esac
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/cxxflags.sh"   # the ONE flags.make parse, for (U)
RECON="$ROOT/test/lib/sitesatrecon.py"
GOLD="$ROOT/test/sitesatshortfix/golden"
export PYTHONDONTWRITEBYTECODE=1
export LC_ALL=C

fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
recon(){ python3 "$RECON" "$@"; }

# ── (A) the fixtures. Every line that holds a call of the target carries the word SITE, so the arms below can count the
#    sites they are supposed to have read from the fixture itself. The goldens were captured on exactly these bytes.
echo "=== A: fixtures ==="
mkdir -p "$TMP/c" "$TMP/go" "$TMP/py/my dir" "$TMP/py/d 12 x" "$TMP/cap"
cat > "$TMP/c/lib.c" <<'FIX'
int target( int x ) { return x + 1; }
FIX
cat > "$TMP/c/a.c" <<'FIX'
int target( int x );
int one( void )
{
    return target( 1 ); /* SITE */
}
int three( void )
{
    int a = target( 1 ) + target( 2 ); /* SITE */
    a += target( 3 ); /* SITE */
    return a + target( 4 ); /* SITE */
}
FIX
cat > "$TMP/c/b.c" <<'FIX'
int target( int x );
static int helper( int v )
{
    return target( v ); /* SITE */
}
int entry( void )
{
    return helper( 2 ) + target( 5 ); /* SITE */
}
FIX
cat > "$TMP/go/a.go" <<'FIX'
package main

func Target() int { return 1 }
FIX
cat > "$TMP/go/b.go" <<'FIX'
package main

func main() { println(Target()) } // SITE
FIX
cat > "$TMP/go/c.go" <<'FIX'
package main
var Seed = Target() // SITE

func twice() int {
	a := Target() // SITE
	return a + Target() // SITE
}
FIX
cat > "$TMP/py/my dir/sp.py" <<'FIX'
from lib import target
def spaced():
    a = target(1)  # SITE
    return a + target(2)  # SITE
FIX
cat > "$TMP/py/d 12 x/own.py" <<'FIX'
from lib import target
def digits():
    return target(3)  # SITE
FIX
cat > "$TMP/py/lib.py" <<'FIX'
def target(x):
    return x + 1
FIX
cat > "$TMP/py/alias.py" <<'FIX'
from lib import target as renamed
def aliased():
    return renamed(4)
FIX
{ echo 'int target( int x ) { return x + 1; }'; echo 'int many( void )'; echo '{'; echo '    int a = 0;'
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do echo "    a += target( $i ); /* SITE */"; done
  echo '    return a;'; echo '}'; } > "$TMP/cap/cap.c"
marked(){ grep -rc 'SITE' "$TMP/$1" | awk -F: '{ n += $NF } END { print n + 0 }'; }
sym(){ [ "$1" = go ] && echo Target || echo target; }
run(){ ( cd "$TMP/$1" && shift && "$BIN" . --no-cache "$@" ); }   # run CORPUS args... -> stdout, root "." as the goldens have it
if [ "$( marked c )" = 6 ] && [ "$( marked go )" = 4 ] && [ "$( marked py )" = 3 ] && [ "$( marked cap )" = 20 ]; then
    ok "(A) four corpora built: 6 + 4 + 3 + 20 marked call-site lines"
else
    no "(A) fixture markers: c=$( marked c ) go=$( marked go ) py=$( marked py ) cap=$( marked cap ), want 6 4 3 20"
fi
for d in c go py cap; do
    run "$d" "--callers=$( sym "$d" )" >"$TMP/$d.callers.xml" 2>"$TMP/$d.callers.err" || no "(A) --callers on the $d fixture exits non-zero: $( head -c 200 "$TMP/$d.callers.err" )"
    run "$d" "--uses=$( sym "$d" )" --limit=1000 >"$TMP/$d.uses.xml" 2>/dev/null
done

# ── (B) LOSSLESS + SHORT against the goldens ─────────────────────────────────────────────────────────────────────────
echo "=== B: rebuilt from the delivered answer == the pre-change golden, whole value by whole value ==="
for d in c go py cap; do
    want=1; [ "$d" = c ] && want=4; [ "$d" = go ] && want=3; [ "$d" = py ] && want=2
    if out="$( recon xml "$TMP/$d.callers.xml" "$GOLD/$d.callers.xml" "$want" )"; then ok "(B) $d: ${out##*$'\n'}"
    else no "(B) $d callers rows:"; printf '%s\n' "$out" | head -6 | sed 's/^/        /'; fi
done

# ── (C) the second reference: the uses verb's role="call" rows, a different emitter in the same binary ───────────────
echo "=== C: the same sites against --uses role=call ==="
for d in c go py cap; do
    if out="$( recon uses "$TMP/$d.callers.xml" "$TMP/$d.uses.xml" 1 )"; then ok "(C) $d: every bare line + its row's p= file is a role=call site, and none is missing"
    else no "(C) $d vs --uses:"; printf '%s\n' "$out" | head -6 | sed 's/^/        /'; fi
    # and the uses document itself did not move: it is the reference, so it must be the one the golden binary printed
    if [ "$( sed 's/<!--.*-->//' "$TMP/$d.uses.xml" )" = "$( sed 's/<!--.*-->//' "$GOLD/$d.uses.xml" )" ]; then ok "(C) $d: the --uses rows are byte-identical to the pre-change binary's"
    else no "(C) $d: the --uses rows moved; this change must not touch them"; fi
done

# ── (D) non-vacuity: what was read is what the fixture holds ─────────────────────────────────────────────────────────
echo "=== D: non-vacuity, counted from the fixture ==="
for d in c go py; do
    got="$( recon count "$TMP/$d.callers.xml" )"; m="$( marked "$d" )"
    rows=4; [ "$d" = go ] && rows=3; [ "$d" = py ] && rows=2
    if [ "$got" = "rows=$rows tokens=$m bare=$m full=0" ]; then ok "(D) $d: $got == the fixture's $m marked lines, every one a bare line"
    else no "(D) $d: $got, want rows=$rows tokens=$m bare=$m full=0"; fi
done

# ── (E) the other dialects print the same tokens ─────────────────────────────────────────────────────────────────────
echo "=== E: safe-delete, --json, --format=columnar ==="
run c --safe-delete=target >"$TMP/c.safedelete.xml" 2>/dev/null
if out="$( recon xml "$TMP/c.safedelete.xml" "$GOLD/c.safedelete.xml" 4 )"; then ok "(E) safe-delete <c> rows: ${out##*$'\n'}"
else no "(E) safe-delete:"; printf '%s\n' "$out" | head -6 | sed 's/^/        /'; fi
for d in c py; do
    want=4; [ "$d" = py ] && want=2
    run "$d" --callers=target --json >"$TMP/$d.callers.json" 2>/dev/null
    if out="$( recon json "$TMP/$d.callers.json" "$GOLD/$d.callers.json.golden" "$want" 2>&1 )"; then ok "(E) $d --json rows: ${out##*$'\n'}"
    else no "(E) $d --json:"; printf '%s\n' "$out" | head -6 | sed 's/^/        /'; fi
    run "$d" --callers=target --format=columnar >"$TMP/$d.columnar.xml" 2>/dev/null
    if out="$( recon columnar "$TMP/$d.columnar.xml" "$GOLD/$d.callers.columnar.xml" "$want" 2>&1 )"; then ok "(E) $d columnar sites_at column: ${out##*$'\n'}"
    else no "(E) $d columnar:"; printf '%s\n' "$out" | head -6 | sed 's/^/        /'; fi
done

# ── (F) paths that hold a space, as WHOLE values ─────────────────────────────────────────────────────────────────────
echo "=== F: a path with a space; a path with an all-digit fragment; absence ==="
PYB="$( sed 's/<!--.*-->//' "$TMP/py.callers.xml" )"
GPY="$( sed 's/<!--.*-->//' "$GOLD/py.callers.xml" )"
case "$GPY" in *'<s t="fn" n="spaced" p="my dir/sp.py:2" sites_at="my dir/sp.py:3 my dir/sp.py:4"/>'*) premise=1 ;; *) premise=0 ;; esac
case "$PYB" in *'<s t="fn" n="spaced" p="my dir/sp.py:2" sites_at="3 4"/>'*) [ "$premise" = 1 ] && ok "(F) my dir/sp.py: the golden's unsplittable \"my dir/sp.py:3 my dir/sp.py:4\" is now \"3 4\"" || no "(F) premise: the golden does not hold the spaced row" ;;
    *) no "(F) the spaced row: $( printf '%s' "$PYB" | grep -o '<s [^>]*n="spaced"[^>]*>' )" ;; esac
case "$PYB" in *'<s t="fn" n="digits" p="d 12 x/own.py:2" sites_at="3"/>'*) ok "(F) d 12 x/own.py: the row's own path may hold an all-digit fragment; the value is the bare line 3" ;;
    *) no "(F) the digits row: $( printf '%s' "$PYB" | grep -o '<s [^>]*n="digits"[^>]*>' )" ;; esac
case "$PYB" in *'<s t="fn" n="aliased" p="alias.py:2"/>'*) ok "(F) absence keeps its one meaning: the aliased-import caller still carries no sites_at= (never omitted on equality)" ;;
    *) no "(F) the aliased row: $( printf '%s' "$PYB" | grep -o '<s [^>]*n="aliased"[^>]*>' )" ;; esac

# ── (G) mutation controls: each must go RED, and for the stated reason ───────────────────────────────────────────────
echo "=== G: mutation controls (each must fail) ==="
mutant(){   # mutant LABEL WANT_CLASS SED_EXPR [SOURCE]: mutate the delivered c answer, require a real change, require the named failure
    local label="$1" want="$2" expr="$3" src="${4:-$TMP/c.callers.xml}" out
    sed "$expr" "$src" >"$TMP/mut.xml"
    if cmp -s "$src" "$TMP/mut.xml"; then no "(G) $label: the mutation changed nothing, so it proves nothing"; return; fi
    if out="$( recon xml "$TMP/mut.xml" "$GOLD/c.callers.xml" 4 )"; then no "(G) $label: the reconstruction PASSED a corrupted answer"
    elif printf '%s\n' "$out" | grep -q "^$want"; then ok "(G) $label -> RED ($( printf '%s\n' "$out" | grep -m1 "^$want" | cut -c1-110 ))"
    else no "(G) $label: red, but not for the reason under test: $( printf '%s\n' "$out" | head -2 | tr '\n' ' ' )"; fi
}
mutant "a corrupted line digit (8 9 10 -> 8 9 11)" 'LOSSLESS ROW' 's/sites_at="8 9 10"/sites_at="8 9 11"/'
mutant "a deleted site token (8 9 10 -> 8 10)"     'LOSSLESS ROW' 's/sites_at="8 9 10"/sites_at="8 10"/'
mutant "a changed row p= (a.c:6 -> b.c:6)"         'LOSSLESS ROW' 's/p="a.c:6"/p="b.c:6"/'
mutant "a deleted sites_at= attribute"             'ROW 2: sites_at= absent' 's/ sites_at="8 9 10"//'
if out="$( recon xml "$GOLD/c.callers.xml" "$GOLD/c.callers.xml" 4 )"; then no "(G) the golden fed in as new output PASSED: the gate cannot tell the old form from the new"
elif printf '%s\n' "$out" | grep -q '^SHORT ROW' && ! printf '%s\n' "$out" | grep -q '^LOSSLESS'; then ok "(G) the golden fed in as new output -> RED (SHORT only: lossless but not shortened)"
else no "(G) golden-as-new: $( printf '%s\n' "$out" | head -2 | tr '\n' ' ' )"; fi
: >"$TMP/empty.xml"
if out="$( recon xml "$TMP/empty.xml" "$TMP/empty.xml" 1 )"; then no "(G) an empty document against an empty reference PASSED (no count floor)"
elif printf '%s\n' "$out" | grep -q '^FLOOR'; then ok "(G) an empty document -> RED (the count floor: 0 rows carry sites_at=)"
else no "(G) empty document: $out"; fi
if out="$( recon uses "$TMP/empty.xml" "$TMP/c.uses.xml" 1 )"; then no "(G) an empty document PASSED the --uses reference"
else ok "(G) an empty document against --uses -> RED"; fi
sed 's/sites_at="8 9 10"/sites_at="8 9 11"/' "$TMP/c.callers.xml" >"$TMP/mut.xml"
if out="$( recon uses "$TMP/mut.xml" "$TMP/c.uses.xml" 1 )"; then no "(G) a corrupted line digit PASSED the --uses reference"
elif printf '%s\n' "$out" | grep -q '^USES'; then ok "(G) a corrupted line digit against --uses -> RED (the second reference catches it alone)"
else no "(G) corrupted digit vs --uses: $out"; fi

# ── (U) the rows no index produces ───────────────────────────────────────────────────────────────────────────────────
echo "=== U: cross-file, mixed and all-digit-fragment rows (unit driver) ==="
BUILD_DIR="$( cd "$( dirname "$BIN" )" && pwd )"
FLAGS_MK="$BUILD_DIR/CMakeFiles/ripwire.dir/flags.make"; LINK_TXT="$BUILD_DIR/CMakeFiles/ripwire.dir/link.txt"
if [ ! -f "$ROOT/src/sitetokens.h" ]; then
    no "(U) src/sitetokens.h does not exist: the emit-time rule is not implemented"
elif [ ! -f "$FLAGS_MK" ] || [ ! -f "$LINK_TXT" ]; then
    no "(U) cannot find CMake flags under $BUILD_DIR: the unit arm needs a CMake-built binary"
elif ! cxxflags_load "$FLAGS_MK"; then
    no "(U) cannot parse $FLAGS_MK without executing it"
else
    CXX="$( awk 'NR==1{ print $1; exit }' "$LINK_TXT" )"
    [ -n "$CXX" ] && command -v "$CXX" >/dev/null 2>&1 || CXX="$( command -v c++ || command -v clang++ )"
    if "$CXX" "${CXX_FLAGS[@]}" "${CXX_DEFINES[@]}" -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_DEBUG -D_GLIBCXX_ASSERTIONS \
         "${CXX_INCLUDES[@]}" -I"$ROOT/src" "$ROOT/test/sitesatshort_unit.cpp" -o "$TMP/sitesat_unit" >"$TMP/u_build.log" 2>&1; then
        "$TMP/sitesat_unit" >"$TMP/u_run.log" 2>&1; urc=$?
        n="$( grep -c '^  PASS' "$TMP/u_run.log" | tr -d ' ' )"
        if [ "$urc" = 0 ] && [ "$n" -ge 12 ]; then ok "(U) sitesatshort_unit: $n case(s) hold"
        else no "(U) sitesatshort_unit rc=$urc, $n case(s) passed:"; grep -E 'FAIL|assert|Assertion' "$TMP/u_run.log" | head -4 | sed 's/^/        /'; fi
        for want in 'cross-file: a foreign site keeps its FULL token' 'mixed row: bare for the own file, full for the other' \
                    'foreign path with an all-digit fragment: the whole row is full form'; do
            grep -qF "  PASS  $want" "$TMP/u_run.log" && ok "(U) $want" || no "(U) case missing or failed: $want"
        done
        # the synthetic rows through the SAME reconstruction the real answers got
        if out="$( recon unitrows "$TMP/u_run.log" )"; then
            last="${out##*$'\n'}"
            mixed="$( printf '%s' "$last" | sed -n 's/.* mixed=\([0-9]*\).*/\1/p' )"; verb="$( printf '%s' "$last" | sed -n 's/.* verbatim=\([0-9]*\).*/\1/p' )"
            if [ "${mixed:-0}" -ge 2 ] && [ "${verb:-0}" -ge 3 ]; then ok "(U) reconstruction over the synthetic rows: $last"
            else no "(U) the synthetic rows did not exercise the mixed and verbatim shapes: $last"; fi
        else no "(U) reconstruction over the synthetic rows:"; printf '%s\n' "$out" | head -4 | sed 's/^/        /'; fi
        # control: a mixed row with its foreign token shortened to a bare line must not rebuild
        printf 'ROW a.c|a.c:8 b.c:4 a.c:9|8 4 9\n' >"$TMP/u_mut.log"
        if recon unitrows "$TMP/u_mut.log" >/dev/null; then no "(U) control: a foreign site printed as a bare line PASSED"
        else ok "(U) control: a foreign site printed as a bare line -> RED"; fi
    else
        no "(U) sitesatshort_unit does not compile:"; grep -m4 -E 'error' "$TMP/u_build.log" | sed 's/^/        /'
    fi
fi

# ── (K) the cut list ─────────────────────────────────────────────────────────────────────────────────────────────────
echo "=== K: a cut list ==="
case "$( sed 's/<!--.*-->//' "$TMP/cap.callers.xml" )" in
    *'<s t="fn" n="many" p="cap.c:2" sites_at="5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20" sites_total="20"/>'*)
        ok "(K) 20 marked sites, 16 printed as bare lines, sites_total=\"20\" ($( marked cap ) in the fixture)" ;;
    *)  no "(K) the cut row: $( sed 's/<!--.*-->//' "$TMP/cap.callers.xml" | grep -o '<s [^>]*>' )" ;;
esac

# ── (L) the legend ───────────────────────────────────────────────────────────────────────────────────────────────────
echo "=== L: the legend reads the form the rows are in ==="
legend(){ grep -o '<!--.*-->' "$1"; }
if legend "$TMP/c.callers.xml" | grep -qF "<s sites_at=>: its calls of the leaf name, any receiver, as [file:]line (p=: def line, default file)"; then
    ok "(L) the default legend of a callers answer reads sites_at= as [file:]line with p= the default file"
else no "(L) default callers legend: $( legend "$TMP/c.callers.xml" | grep -o '[^.]*sites_at=[^.]*' | head -1 )"; fi
if legend "$TMP/c.safedelete.xml" | grep -qF "c sites_at=: its calls of the leaf name, any receiver, as [file:]line (p=: def line, default file)"; then
    ok "(L) the safe-delete legend reads it the same way"
else no "(L) safe-delete legend: $( legend "$TMP/c.safedelete.xml" | grep -o '[^.]*sites_at=[^.]*' | head -1 )"; fi
if legend "$TMP/c.columnar.xml" | grep -qF "as [file:]line (default: its path), space-separated"; then ok "(L) the columnar legend reads its sites_at column the same way"
else no "(L) columnar legend: $( legend "$TMP/c.columnar.xml" | grep -o '[^.]*sites_at[^.]*' | head -1 )"; fi
run c --callers=target --legend=full >"$TMP/c.full.xml" 2>/dev/null
if legend "$TMP/c.full.xml" | grep -qF "as [file:]line (space-separated, ascending; two calls on a line are one site; no file: p='s)" && [ "$( grep -o '<s [^>]*/>' "$TMP/c.full.xml" )" = "$( grep -o '<s [^>]*/>' "$TMP/c.callers.xml" )" ]; then
    ok "(L) --legend=full carries the long reading, and the rows are the same rows"
else no "(L) --legend=full: $( legend "$TMP/c.full.xml" | grep -o 'sites_at= on a caller row[^.]*\.' | head -1 )"; fi
run c --callees=one >"$TMP/c.callees.xml" 2>/dev/null
if grep -q 'sites_at' "$TMP/c.callees.xml"; then no "(L) a --callees answer mentions sites_at (present-only broke)"
elif ! grep -q '<callees ' "$TMP/c.callees.xml"; then no "(L) premise: no --callees answer to read"
else ok "(L) present-only: an answer with no sites_at= row carries no reading of it"; fi
if grep -q 'as file:line (p= is its def line)\|as file:line, space-separated\|as file:line tokens' "$TMP"/*.xml; then no "(L) an answer still carries the pre-change reading (file:line for every token)"
else ok "(L) no answer carries the pre-change reading"; fi

# ── (N) determinism + well-formedness ────────────────────────────────────────────────────────────────────────────────
echo "=== N: determinism, well-formedness ==="
det=0
for d in c go py cap; do
    run "$d" "--callers=$( sym "$d" )" >"$TMP/$d.again.xml" 2>/dev/null
    cmp -s "$TMP/$d.callers.xml" "$TMP/$d.again.xml" || { det=1; no "(N) $d: two runs differ"; }
done
run c --callers=target --json >"$TMP/c.again.json" 2>/dev/null; cmp -s "$TMP/c.callers.json" "$TMP/c.again.json" || { det=1; no "(N) --json: two runs differ"; }
run c --callers=target --format=columnar >"$TMP/c.again.col" 2>/dev/null; cmp -s "$TMP/c.columnar.xml" "$TMP/c.again.col" || { det=1; no "(N) columnar: two runs differ"; }
[ "$det" = 0 ] && [ -s "$TMP/c.callers.xml" ] && ok "(N) two runs are byte-identical (XML x4, --json, columnar)"
if command -v xmllint >/dev/null 2>&1; then
    wf=0
    for f in c.callers.xml go.callers.xml py.callers.xml cap.callers.xml c.safedelete.xml c.columnar.xml py.columnar.xml c.full.xml; do
        xmllint --noout "$TMP/$f" 2>/dev/null || { wf=1; no "(N) $f is not well-formed"; }
    done
    [ "$wf" = 0 ] && ok "(N) every answer pipes clean through xmllint (8 documents)"
else
    printf '  SKIP  (N) xmllint is not installed: well-formedness is not checked on this machine\n'
fi

# ── (S) at scale, against a legacy binary's LIVE output ──────────────────────────────────────────────────────────────
#    RIPWIRE_SITESAT_REF=<a binary built before this change>  RIPWIRE_SITESAT_CORPORA="dir dir ..."  [RIPWIRE_SITESAT_SYMS=N]
echo "=== S: at scale ==="
if [ -z "${RIPWIRE_SITESAT_REF:-}" ] || [ -z "${RIPWIRE_SITESAT_CORPORA:-}" ]; then
    printf '  SKIP  (S) RIPWIRE_SITESAT_REF / RIPWIRE_SITESAT_CORPORA not set: arms B-U are the proof on this run\n'
else
    for corpus in $RIPWIRE_SITESAT_CORPORA; do
        cn="$( basename "$corpus" )"; rows=0; answers=0; sbad=0; saved=0; total=0
        "$BIN" "$corpus" >"$TMP/s.map" 2>/dev/null
        for s in $( recon symbols "$TMP/s.map" "${RIPWIRE_SITESAT_SYMS:-40}" ); do
            # --limit on both sides: shorter rows let more answers fit the callers byte band, so a default page can hold more rows than the legacy binary's
            "$BIN" "$corpus" "--callers=$s" --limit=100000 >"$TMP/s.new" 2>/dev/null; "$RIPWIRE_SITESAT_REF" "$corpus" "--callers=$s" --limit=100000 >"$TMP/s.old" 2>/dev/null
            grep -q ' sites_at="' "$TMP/s.old" || continue
            answers=$(( answers + 1 ))
            if out="$( recon xml "$TMP/s.new" "$TMP/s.old" 1 )"; then
                r="$( printf '%s' "${out##*$'\n'}" | sed -n 's/rows_with_sites=\([0-9]*\).*/\1/p' )"; rows=$(( rows + r ))
                total=$(( total + $( wc -c <"$TMP/s.old" ) )); saved=$(( saved + $( wc -c <"$TMP/s.old" ) - $( wc -c <"$TMP/s.new" ) ))
            else sbad=1; no "(S) $cn --callers=$s:"; printf '%s\n' "$out" | head -3 | sed 's/^/        /'; fi
        done
        if [ "$sbad" = 0 ] && [ "$rows" -ge 1 ]; then ok "(S) $cn: $answers answers, $rows rows rebuilt byte-for-byte against the legacy binary; $saved of $total B saved, legend included"
        elif [ "$sbad" = 0 ]; then no "(S) $cn: no row carried sites_at= (nothing was compared)"; fi
    done
fi

[ "$fail" = 0 ] && echo "sitesatshortcheck: OK" || echo "sitesatshortcheck: FAIL"
exit "$fail"
