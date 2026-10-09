#!/usr/bin/env bash
# mapinventorycheck.sh — the default map's inventory tier (<inv>): no indexed file is silently absent from an
# orient map, and the program entry points are named.
#
# WHY. The ranked map prints the top-k (200) symbols, which covers ~30-90 files of a few hundred. On the round-1
# comparison table that cut was the whole orient miss class (K19): tmux input.c / key-bindings.c, hono's
# validator/, textual's drivers/ and command.py, htop's SignalsPanel.c — every one an indexed file ranked just below
# the cut, with NOTHING in the answer saying the file existed. Entry points are worse: `main` has no in-repo caller,
# so PageRank puts it at the very bottom (htop main #2548 of 3206, tmux main #3220 of 6361) and no re-rank of the
# map can surface it. The tier appends, after the ranked rows and without touching them: <entry> rows for program
# entries by name convention, and <ls> rows naming (code) or counting (tests/docs/examples/config) every file the
# ranked rows did not show, grouped by directory.
#
# Fixture test/mapinvfix: C, Python, Go, Rust, Java and TS files; a test-dir main, an examples main, a Python main
# with a real caller (NOT an entry), a cli main reached from __main__.py (NOT an entry: the __main__ scope is).
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FAILED=0
fail() { printf '  FAIL  %s\n' "$*"; FAILED=$(( FAILED + 1 )); }
ok()   { printf '  PASS  %s\n' "$*" || { FAILED=$(( FAILED + 1 )); printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
[ -x "$BIN" ] || { echo "mapinventorycheck: no binary at $BIN — build first"; exit 2; }
echo "mapinventorycheck: BIN=$BIN"
cd "$ROOT" || exit 2
FIX=test/mapinvfix
[ -d "$FIX" ] || { echo "mapinventorycheck: fixture $FIX missing"; exit 2; }

run() { "$BIN" "$FIX" --no-cache "$@" 2>"$TMP/err"; }
run --top-k=3 >"$TMP/map";             rc=$?
[ "$rc" -eq 0 ] && [ -s "$TMP/map" ] || { echo "mapinventorycheck: the map run failed (rc=$rc)"; cat "$TMP/err"; exit 1; }
run --top-k=3 --legend=full >"$TMP/full"
run --top-k=3 --json >"$TMP/json"
run >"$TMP/whole"                       # default top-k: every file shown
run --top-k=3 --max-tokens=400 >"$TMP/maxtok"
run --top-k=3 --expand=run >"$TMP/expand"
run --top-k=3 --for="where does main start" >"$TMP/for"
run --top-k=3 --stable >"$TMP/stable"
run --top-k=3 --no-inventory --json >"$TMP/noinvjson"
run --top-k=3 >"$TMP/map2"

# The tier, isolated (one line of minified XML).
INV="$( grep -o '<inv listed="[0-9].*</inv>' "$TMP/map" )"

# (A) the tier rides a map whose ranked rows dropped a file — RED on a binary without it
if [ -n "$INV" ]; then ok "(A) a map with a ranked cut carries <inv>"; else fail "(A) no <inv> on a map whose top-k=3 dropped 15 of 18 files"; fi

# (B) it comes AFTER the ranked rows and the rows are untouched: </f><inv …>…</inv></r>
if grep -q '</f><inv [^>]*>.*</inv></r>' "$TMP/map"; then ok "(B) <inv> follows the last ranked <f> group and closes the root"; else fail "(B) <inv> is not appended after the ranked rows"; fi

# (C) entries: exactly the program entries by convention, sorted by path
ENTRIES="$( printf '%s' "$INV" | grep -o '<entry p="[^"]*" n="[^"]*"' | sed 's/<entry p="\([^"]*\)" n="\([^"]*\)"/\1:\2/' | tr '\n' ' ' )"
WANT='cs/Program.cs:Main go/cmd/main.go:main java/App.java:main prog.c:main py/pkg/__main__.py:&lt;file-scope&gt; py/tool.py:main rs/src/main.rs:main ts/cli.ts:main '
if [ "$ENTRIES" = "$WANT" ]; then ok "(C) entries = C/Go/Rust/Java/C# main, a __main__.py scope, a guarded Python main, a TS main its module scope calls"; else fail "(C) entries: got [$ENTRIES] want [$WANT]"; fi
# (C2) near-miss negatives, one per rule: a test-dir main, an examples main, a main with a real caller, a main
# reached only from ANOTHER file's module scope
for neg in 'tests/test_prog.c' 'examples/demo.c' 'py/lib.py' 'py/pkg/cli.py'; do
    if printf '%s' "$INV" | grep -q "<entry p=\"$neg\""; then fail "(C2) $neg claimed as an entry"; else ok "(C2) $neg is not an entry"; fi
done

# (D) an entry carries its resolved callees as c rows (the map row vocabulary)
if printf '%s' "$INV" | grep -q '<entry p="prog.c" n="main"><c n="run"/></entry>'; then ok "(D) prog.c main → run"; else fail "(D) prog.c main does not list its callee run"; fi
if printf '%s' "$INV" | grep -q '<entry p="py/pkg/__main__.py" n="&lt;file-scope&gt;"><c n="main"[^>]*/></entry>'; then ok "(D2) the __main__.py scope → main"; else fail "(D2) the __main__.py entry does not list main"; fi

# (E) a low-ranked code file is NAMED in its directory's <ls> row
if printf '%s' "$INV" | grep -q '<ls p="\." n="[0-9]*" f="[^"]*lowfile\.c'; then ok "(E) lowfile.c is named under p=\".\""; else fail "(E) lowfile.c is not named"; fi
# (E2) a test-named file next to code is counted, not named; a doc and a data file are counted, not named
if printf '%s' "$INV" | grep -q 'two\.test\.ts\|README\.md\|data\.json'; then fail "(E2) a test/doc/data file is named"; else ok "(E2) test-named, doc and data files are counted, not named"; fi

# (F) test and example dirs roll up count-only
for d in tests examples; do
    if printf '%s' "$INV" | grep -q "<ls p=\"$d\" n=\"1\"/>"; then ok "(F) $d/ rolls up count-only"; else fail "(F) $d/ is not a count-only <ls> row"; fi
done

# (G) arithmetic: listed + Σ n = the header's files=, and listed = the <f> groups the map printed
FILES="$( grep -o '<!-- files=[0-9]*' "$TMP/map" | grep -o '[0-9]*$' )"
LISTED="$( printf '%s' "$INV" | grep -o '<inv listed="[0-9]*"' | grep -o '[0-9]*' )"
UNL="$( printf '%s' "$INV" | grep -o 'unlisted="[0-9]*"' | grep -o '[0-9]*' )"
SUMN=0; for n in $( printf '%s' "$INV" | grep -o '<ls p="[^"]*" n="[0-9]*"' | grep -o 'n="[0-9]*"' | grep -o '[0-9]*' ); do SUMN=$(( SUMN + n )); done
FGROUPS="$( grep -o '<f p="' "$TMP/map" | wc -l | tr -d ' ' )"
if [ -n "$FILES" ] && [ "$(( ${LISTED:-0} + SUMN ))" = "$FILES" ] && [ "${UNL:-x}" = "$SUMN" ] && [ "${LISTED:-x}" = "$FGROUPS" ]; then
    ok "(G) listed=$LISTED (= <f> groups) + unlisted=$UNL (= Σ n) = files=$FILES"
else
    fail "(G) arithmetic: listed=${LISTED:-?} groups=$FGROUPS unlisted=${UNL:-?} Σn=$SUMN files=${FILES:-?}"
fi
# (G2) no file is both shown and named
DUP=0; for p in $( grep -o '<f p="[^"]*"' "$TMP/map" | sed 's/<f p="//;s/"$//' ); do
    b="${p##*/}"; d="${p%/*}"; [ "$d" = "$p" ] && d=.
    printf '%s' "$INV" | grep -q "<ls p=\"$d\" n=\"[0-9]*\" f=\"\([^\"]*,\)\?$b[,\"]" && DUP=1
done
if [ "$DUP" = 0 ]; then ok "(G2) no shown file is named again"; else fail "(G2) a file is both a ranked <f> group and an <ls> name"; fi

# (H) present-only: a map that shows every file carries no tier (small maps stay byte-identical)
if grep -q '<inv listed="' "$TMP/whole"; then fail "(H) <inv> on a map that shows every file"; else ok "(H) no <inv> when the ranked rows show every file"; fi

# (I) scope: never under --max-tokens (its fit is a binary search on top-k; the tier would make it non-monotone),
# never on a payload verb's ride-along map
for f in maxtok expand for noinvjson; do
    if grep -q '<inv listed="\|"inv":' "$TMP/$f"; then fail "(I) <inv> rides the $f answer"; else ok "(I) no <inv> on the $f answer"; fi
done

# (J) the JSON twin carries the same decision
JL="$( grep -o '"inv":{"listed":[0-9]*,"unlisted":[0-9]*' "$TMP/json" )"
if [ "$JL" = "\"inv\":{\"listed\":$LISTED,\"unlisted\":$UNL" ]; then ok "(J) JSON inv listed/unlisted = XML"; else fail "(J) JSON twin: got [$JL] want listed=$LISTED unlisted=$UNL"; fi
JE="$( python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(" ".join(e["p"]+":"+e["n"].replace("<","&lt;").replace(">","&gt;") for e in d["inv"]["entry"])+" ")' "$TMP/json" 2>/dev/null )"
if [ "$JE" = "$WANT" ]; then ok "(J2) JSON entries = XML entries"; else fail "(J2) JSON entries [$JE] want [$WANT]"; fi
if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/json" 2>/dev/null; then ok "(J3) JSON parses"; else fail "(J3) JSON does not parse"; fi

# (K) legends: the full legend defines the tier; the compact (default) legend reads every new element
if grep -q '<!-- inv: ' "$TMP/full"; then ok "(K) --legend=full carries the inv: clause"; else fail "(K) no inv: clause in the full legend"; fi
if grep -q '<!-- inv: ' "$TMP/whole"; then fail "(K2) the inv: clause rides a map with no tier"; else ok "(K2) the clause is present-only"; fi
for t in '<inv listed=' '<entry p=' '<ls p='; do
    if head -c 6000 "$TMP/map" | grep -q -- "$t"; then ok "(K3) the compact legend reads $t"; else fail "(K3) the compact legend does not define $t"; fi
done
if grep -q '<!-- inv: ' "$TMP/map"; then fail "(K4) the full inv: prose survived compaction"; else ok "(K4) the full clause is stripped under compact"; fi

# (L) well-formed in both postures (xmllint when present, else python's parser)
wf() { if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$1" 2>/dev/null; else python3 -c 'import sys,xml.dom.minidom as m; m.parse(sys.argv[1])' "$1" 2>/dev/null; fi; }
for f in map full stable; do if wf "$TMP/$f"; then ok "(L) $f is well-formed"; else fail "(L) $f is not well-formed XML"; fi; done

# (M) determinism, and --stable keeps the tier (path order is already stable)
if cmp -s "$TMP/map" "$TMP/map2"; then ok "(M) two runs byte-identical"; else fail "(M) non-deterministic"; fi
if grep -q '<inv listed="' "$TMP/stable"; then ok "(M2) --stable carries the tier"; else fail "(M2) --stable dropped the tier"; fi

# (N) the ranked rows are untouched (checklist 23): the same top-k under --no-inventory prints the identical <f>/<s>/<c>
# sequence the tiered map does, and nothing of the tier (element or legend clause)
rows_of(){ sed 's/<inv listed="[0-9].*<\/inv>//' "$1" | grep -oE '<f p="[^"]*"|<s t="[^"]*" n="[^"]*"[^>]*>(<c [^>]*/>)*' | tr '\n' ' '; }
run --top-k=3 --no-inventory >"$TMP/rowsonly"
run --top-k=3 --no-inventory --legend=full >"$TMP/rowsonly_full"
if ! grep -q '<inv listed="\|<!-- inv: ' "$TMP/rowsonly" "$TMP/rowsonly_full" && [ -n "$( rows_of "$TMP/map" )" ] && [ "$( rows_of "$TMP/map" )" = "$( rows_of "$TMP/rowsonly" )" ]; then
    ok "(N) ranked rows byte-identical to the tier-less twin"
else
    fail "(N) the tier changed the ranked rows (or the twin carries a tier)"
fi

# (O) important-last: the tier moves to the FRONT so the top-ranked rows keep the end position
run --top-k=3 --most-important-last >"$TMP/last"
if grep -q '"><inv listed="[0-9]*" unlisted="[0-9]*">.*</inv><f p="' "$TMP/last" && grep -q '</f></r>' "$TMP/last"; then ok "(O) --most-important-last: <inv> precedes the rows"; else fail "(O) --most-important-last: <inv> is not before the ranked rows"; fi

# (P) runaway guards, each at the boundary and one past it (generated corpora; top-k=1 shows one file)
gen_c(){ d="$1"; n="$2"; mkdir -p "$d/src"; i=0; while [ "$i" -lt "$n" ]; do printf 'int fn%d( void ) { return %d; }\n' "$i" "$i" >"$d/src/f$i.c"; i=$(( i + 1 )); done; }
gen_go(){ d="$1"; n="$2"; i=0; while [ "$i" -lt "$n" ]; do mkdir -p "$d/cmd/p$i"; printf 'package main\n\nfunc main() {}\n' >"$d/cmd/p$i/main.go"; i=$(( i + 1 )); done; }
gen_c "$TMP/c2001" 2001; gen_c "$TMP/c2002" 2002
gen_go "$TMP/g32" 32; gen_c "$TMP/g32" 2; gen_go "$TMP/g33" 33; gen_c "$TMP/g33" 2
"$BIN" "$TMP/c2001" --no-cache --top-k=1 >"$TMP/c2001.out" 2>/dev/null
"$BIN" "$TMP/c2002" --no-cache --top-k=1 >"$TMP/c2002.out" 2>/dev/null
"$BIN" "$TMP/g32" --no-cache --top-k=1 >"$TMP/g32.out" 2>/dev/null
"$BIN" "$TMP/g33" --no-cache --top-k=1 >"$TMP/g33.out" 2>/dev/null
NC1="$( grep -o '<ls p="src" n="[0-9]*" f="[^"]*"' "$TMP/c2001.out" | sed 's/.*f="//;s/"$//' | tr ',' '\n' | wc -l | tr -d ' ' )"
if [ "$NC1" = 2000 ] && ! grep -q 'names_capped=' "$TMP/c2001.out"; then ok "(P) 2000 unshown code files: all named, no names_capped="; else fail "(P) at the 2000-name ceiling: named=$NC1, $( grep -o 'names_capped="[0-9]*"' "$TMP/c2001.out" )"; fi
if grep -q '<inv listed="1" unlisted="2001" names_capped="1" names_total="2001">' "$TMP/c2002.out" && grep -q '<ls p="src" n="2001"/>' "$TMP/c2002.out"; then ok "(P) 2001 past the ceiling: the dir keeps n= only, names_capped=1 names_total=2001"; else fail "(P) past the ceiling: $( grep -o '<inv [^>]*>' "$TMP/c2002.out" ) $( grep -o '<ls p="src" n="[0-9]*"[^/]\{0,20\}' "$TMP/c2002.out" )"; fi
E32="$( grep -o '<entry p="' "$TMP/g32.out" | wc -l | tr -d ' ' )"; E33="$( grep -o '<entry p="' "$TMP/g33.out" | wc -l | tr -d ' ' )"
if [ "$E32" = 32 ] && ! grep -q 'entries_capped=' "$TMP/g32.out"; then ok "(P) 32 entries: all shown, no entries_capped="; else fail "(P) 32 entries: shown=$E32 $( grep -o 'entries_total="[0-9]*"' "$TMP/g32.out" )"; fi
if [ "$E33" = 32 ] && grep -q 'entries_capped="1" entries_total="33"' "$TMP/g33.out"; then ok "(P) 33 entries: 32 shown, entries_capped=1 entries_total=33"; else fail "(P) 33 entries: shown=$E33 $( grep -o 'entries_total="[0-9]*"' "$TMP/g33.out" )"; fi

echo "mapinventorycheck: $FAILED failure(s)"
[ "$FAILED" -eq 0 ]
