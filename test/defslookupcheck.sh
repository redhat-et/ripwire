#!/usr/bin/env bash
# defslookupcheck.sh — `--defs=NAME[,NAME…]` (src/defslookup.h rw::lookupDefs) and --path's inline <alts> (lane D2 DEFS-LOOKUP).
#
# RED-FIRST (recorded 2026-10-28 against the train-40 base 1318069a): every arm below fails there — the base has no --defs
# flag (18 FAIL) and its --path answer carries no <alts>. Three NEGATIVES pass vacuously there (no row is a JSON key, every
# sel= proven, P2 no <alts>); each was proven able to fail by a mutant on f966224b: the data-Section filter dropped (6 FAIL),
# picksAlone always false (4 FAIL), defPickProvablyUnique false at one group (P2 FAIL).
# FIX ROUND 1 (2026-10-28, review F15): the picksAlone all_of -> any_of mutant ("binds this group AND MAYBE OTHERS" counts as
# proven) survived all 21 arms because no fixture held two same-named definitions in ONE file, so file:name always picked alone.
# Arm B2 (src/pair.ts: P.go, Q.go) fails that mutant, as do the (C) re-resolution of its sels. Mutants of the fix round are recorded
# at the end of this header.
# Arms: namesakes across files with a test copy and a JSON key (A), a C prototype folded with its definition (B), every
# printed sel= re-resolved by another verb to one definition (C), file:name / Owner.name spellings (D), zero found (E), over
# the 16-row cap with --offset paging (F), several names in one call (G), the JSON twin spelling every row as the XML does (J),
# --path alternatives present only when the pick is not provably unique (P).
#
# Usage:  test/defslookupcheck.sh [BIN]   (BIN falls back to RIPWIRE_BIN, then build/ripwire). Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/defslookupfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "defslookupcheck: BIN=$BIN  FIX=$FIX"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
run(){ ( cd "$FIX" && "$BIN" "$FIX" --no-cache "$@" ); }
# the answer without its legend comments (the compact legend itself spells `<name q= defs=>` and `<d n= …>`)
body(){ perl -0pe 's/<!--.*?-->//gs' "$1"; }

echo "-- (A) namesakes: two source methods, one test copy, one JSON key"
run --defs=run --legend=full >"$TMP/a.xml" 2>"$TMP/a.err"; rc=$?
name="$( body "$TMP/a.xml" | grep -o '<name [^>]*>' )"
if [ "$rc" -eq 0 ] && printf '%s' "$name" | grep -q 'defs="3"'; then ok "defs=3 (two classes + the test copy)"; else no "defs= not 3 (rc=$rc): $name"; fi
if printf '%s' "$name" | grep -q 'data_defs="1"'; then ok "the JSON key is data_defs=1"; else no "no data_defs=1: $name"; fi
grep -q 'lang="json"' "$TMP/a.xml" && no "a JSON key is listed as a definition" || ok "no row is a JSON key"
classes="$( grep -o 'class="[a-z]*"' "$TMP/a.xml" | tr '\n' ' ' )"
if [ "$classes" = 'class="source" class="source" class="test" ' ]; then ok "source rows before the test row"; else no "row order by class wrong: $classes"; fi
if xmllint --noout "$TMP/a.xml" 2>/dev/null; then ok "--legend=full answer is well-formed XML"; else no "--legend=full answer is not well-formed"; fi
grep -q 'sel_proven=' "$TMP/a.xml" && no "a sel= was not proven: $( grep -o '<d [^>]*>' "$TMP/a.xml" )" || ok "every sel= proven"

echo "-- (B) a C prototype and its definition are one group"
run --defs=work >"$TMP/b.xml" 2>/dev/null
if grep -q '<name q="work" defs="1">' "$TMP/b.xml" && grep -q 'p="src/work.c:2"' "$TMP/b.xml"; then ok "work: one group, the bodied definition"; else no "work not one group: $( grep -o '<name.*' "$TMP/b.xml" | head -c 300 )"; fi

echo "-- (B2) two same-named methods in ONE file: the bare file:name binds both, so it proves neither (F15)"
run --defs=go >"$TMP/b2.xml" 2>/dev/null
selsb2="$( grep -o 'sel="[^"]*"' "$TMP/b2.xml" | sed 's/sel="//; s/"$//' )"
if grep -q '<name q="go" defs="2">' "$TMP/b2.xml" && [ "$( printf '%s\n' "$selsb2" | sort -u | wc -l | tr -d ' ' )" = 2 ] && ! printf '%s\n' "$selsb2" | grep -qx 'src/pair.ts:go' && ! grep -q 'sel_proven=' "$TMP/b2.xml"; then ok "go: 2 rows, 2 DIFFERENT proven sels (Owner-qualified), never the bare file:name that binds both"; else no "go: $( grep -o '<d [^>]*>' "$TMP/b2.xml" )"; fi
run --callers=src/pair.ts:go >"$TMP/b2c.xml" 2>/dev/null
if grep -q '<def ix=' "$TMP/b2c.xml"; then ok "B2 control: --callers=src/pair.ts:go really is a 2-group table (the spelling a wrong proof would have printed)"; else no "B2 control: src/pair.ts:go binds one group: the fixture cannot show the any_of mutant"; fi

echo "-- (C) every printed sel= re-resolves to exactly one definition group in another verb (no multi-group <def> table)"
n=0; bad=0
for s in $( grep -o 'sel="[^"]*"' "$TMP/a.xml" "$TMP/b.xml" "$TMP/b2.xml" | sed 's/.*sel="//; s/"$//' ); do
    n=$(( n + 1 ))
    out="$( run --callers="$s" 2>/dev/null )"
    { printf '%s' "$out" | grep -q '<callers ' && ! printf '%s' "$out" | grep -q '<def ix='; } || { bad=$(( bad + 1 )); echo "    sel=$s -> $( printf '%s' "$out" | grep -o '<callers [^>]*>' | head -c 200 )"; }
done
if [ "$n" -ge 6 ] && [ "$bad" -eq 0 ]; then ok "$n sel= spellings each bind one definition group"; else no "$bad of $n sel= spellings did not bind one definition group"; fi

echo "-- (D) spellings the shared resolver accepts"
run --defs=src/b.ts:run >"$TMP/d1.xml" 2>/dev/null
if grep -q 'defs="1"' "$TMP/d1.xml" && grep -q 'sel="src/b.ts:run"' "$TMP/d1.xml"; then ok "file:name -> one row, sel= as given"; else no "file:name: $( grep -o '<name.*' "$TMP/d1.xml" | head -c 300 )"; fi
run --defs=A.run >"$TMP/d2.xml" 2>/dev/null
if grep -q 'defs="1"' "$TMP/d2.xml" && grep -q 'n="A.run"' "$TMP/d2.xml"; then ok "Owner.name -> one row"; else no "Owner.name: $( grep -o '<name.*' "$TMP/d2.xml" | head -c 300 )"; fi

echo "-- (E) zero found: the shared refusal"
run --defs=zzqdefsnone >"$TMP/e.xml" 2>"$TMP/e.err"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'found="0"' "$TMP/e.xml" && grep -q 'symbol not found' "$TMP/e.err"; then ok "rc=1, found=0, stderr refusal"; else no "zero found: rc=$rc $( head -c 300 "$TMP/e.xml" )"; fi

echo "-- (F) over the cap: 16 rows, defs= the true count, --offset pages"
run --defs=many >"$TMP/f1.xml" 2>/dev/null
rows="$( body "$TMP/f1.xml" | grep -o '<d ' | wc -l | tr -d ' ' )"
if grep -q 'defs="18" shown="16" offset="0" next="--defs=many --offset=16"' "$TMP/f1.xml" && [ "$rows" = 16 ]; then ok "page 1: 16 rows of 18, next= names page 2"; else no "page 1: rows=$rows $( grep -o '<name [^>]*>' "$TMP/f1.xml" )"; fi
run --defs=many --offset=16 >"$TMP/f2.xml" 2>/dev/null
rows2="$( body "$TMP/f2.xml" | grep -o '<d ' | wc -l | tr -d ' ' )"
if [ "$rows2" = 2 ] && ! body "$TMP/f2.xml" | grep -q 'next='; then ok "page 2: the last 2 rows, no next="; else no "page 2: rows=$rows2"; fi
if cat "$TMP/f1.xml" "$TMP/f2.xml" | grep -o 'p="gen/m[0-9]*.ts:1"' | sort -u | wc -l | grep -q '^ *18$'; then ok "the two pages cover all 18, no repeats"; else no "pages do not cover 18 distinct definitions"; fi

run --defs=many --limit=5 --offset=5 >"$TMP/f3.xml" 2>/dev/null
if grep -q 'defs="18" shown="5" offset="5" next="--defs=many --offset=10 --limit=5"' "$TMP/f3.xml" && [ "$( body "$TMP/f3.xml" | grep -o '<d ' | wc -l | tr -d ' ' )" = 5 ]; then ok "--limit=5 --offset=5: rows 5..9, next= keeps the limit"; else no "--limit page: $( grep -o '<name [^>]*>' "$TMP/f3.xml" | tail -1 )"; fi
run --defs=many,run --offset=3 >/dev/null 2>"$TMP/f4.err"; rc=$?
if [ "$rc" -eq 1 ] && grep -q -- '--offset' "$TMP/f4.err"; then ok "--offset beside several names refuses (never ignored)"; else no "--offset with several names: rc=$rc"; fi

echo "-- (G) several names, one call"
run --defs=run,work,zzqdefsnone >"$TMP/g.xml" 2>/dev/null; rc=$?
if [ "$rc" -eq 0 ] && [ "$( body "$TMP/g.xml" | grep -o '<name q=' | wc -l | tr -d ' ' )" = 3 ] && grep -q '<name q="zzqdefsnone" defs="0" next="--defs=zzqdefsnone">' "$TMP/g.xml"; then ok "3 <name> rows; the missing one defs=0 with its refusal as next="; else no "multi-name: rc=$rc $( grep -o '<name [^>]*>' "$TMP/g.xml" | tr '\n' ' ' )"; fi

echo "-- (J) the JSON twin spells every row as the XML does (checklist 41)"
run --defs=run --json >"$TMP/j.json" 2>/dev/null
python3 - "$TMP/j.json" "$TMP/a.xml" <<'PY'
import json, re, sys
j = json.load( open( sys.argv[1] ) )["names"][0]["rows"]
x = re.findall( r'<d n="([^"]*)" t="[^"]*" p="([^"]*)" sel="([^"]*)" lang="[^"]*" class="([^"]*)" in="([0-9]+)"', open( sys.argv[2] ).read() )
sys.exit( 0 if [ ( r["n"], r["p"], r["sel"], r["class"], str( r["in"] ) ) for r in j ] == x and len( x ) == 3 else 1 )
PY
jrc=$?
if [ "$jrc" -eq 0 ]; then ok "JSON rows equal the XML rows (n, p, sel, class, in)"; else no "JSON twin differs from XML"; fi

echo "-- (P) --path lists the other definitions only when the pick is not provably unique"
run --path=run,helperA >"$TMP/p1.xml" 2>/dev/null
alts="$( grep -o '<alts .*</alts>' "$TMP/p1.xml" )"
if printf '%s' "$alts" | grep -q '^<alts side="from" of="run">' && [ "$( printf '%s' "$alts" | grep -o '<d ' | wc -l | tr -d ' ' )" = 2 ] && printf '%s' "$alts" | grep -q 'sel="src/b.ts:run"' && ! printf '%s' "$alts" | grep -q 'p="src/a.ts:2"'; then ok "P1: from=run binds A.run; <alts> lists the 2 others (B.run, the test copy), not the bound one"; else no "P1: $alts"; fi
run --path=A.run,helperA >"$TMP/p2.xml" 2>/dev/null
if grep -q 'reachable="1"' "$TMP/p2.xml" && ! grep -q '<alts' "$TMP/p2.xml"; then ok "P2: a unique pick prints no <alts> (0 bytes)"; else no "P2: $( head -c 400 "$TMP/p2.xml" )"; fi
run --path=many,helperA --legend=full >"$TMP/p3.xml" 2>/dev/null
if grep -q '<alts side="from" of="many" alts_shown="16" defs="18" next="--defs=many --offset=1[67]">' "$TMP/p3.xml" && xmllint --noout "$TMP/p3.xml" 2>/dev/null; then ok "P3: 17 others past the cap: alts_shown=16 defs=18 next=--defs=many --offset=16|17, well-formed"; else no "P3: $( grep -o '<alts [^>]*>' "$TMP/p3.xml" )"; fi
# F8: the continuation starts AFTER the rows already shown (it used to replay page 1): the 16 shown + the bound + the offset page = 18 distinct, no repeat
off="$( grep -o '<alts side="from" of="many"[^>]*next="--defs=many --offset=[0-9]*"' "$TMP/p3.xml" | sed 's/.*--offset=//; s/"$//' )"
run --defs=many --offset="${off:-0}" >"$TMP/p3n.xml" 2>/dev/null
shownp="$( grep -o '<alts side="from" of="many".*</alts>' "$TMP/p3.xml" | grep -o 'p="[^"]*"' | sort )"
boundp="$( grep -o '<path [^>]*from_p="[^"]*"' "$TMP/p3.xml" | sed 's/.*from_p=/p=/' )"
nextp="$( body "$TMP/p3n.xml" | grep -o '<d [^>]*' | grep -o 'p="[^"]*"' | sort )"
rep="$( printf '%s\n%s\n' "$shownp" "$nextp" | sort | uniq -d | grep -c . )"
cover="$( printf '%s\n%s\n%s\n' "$shownp" "$nextp" "$boundp" | sort -u | grep -c . )"
if [ -n "$off" ] && [ "$rep" = 0 ] && [ "$cover" = 18 ]; then ok "P3 next=: --defs=many --offset=$off adds only rows the <alts> did not show (shown 16 + bound + the offset page = 18 distinct, 0 repeats)"; else no "P3 next=: off=$off repeats=$rep distinct=$cover"; fi

# CR 4408459903 (harvest 463): sel= is computed for the first 17 sorted rows only. wd/: 18 TS `wide` + a C definition + an untied header
# prototype (row 0, skipped) + the bound w05 (skipped): the 16th alternative used to come from row 17 with sel="" sel_proven="0".
run --path=wide,helperA >"$TMP/p3b.xml" 2>/dev/null
altsw="$( grep -o '<alts side="from" of="wide".*</alts>' "$TMP/p3b.xml" )"
if printf '%s' "$altsw" | grep -q 'alts_shown=' && ! printf '%s' "$altsw" | grep -q 'sel=""' && ! printf '%s' "$altsw" | grep -q 'sel_proven' && [ "$( printf '%s' "$altsw" | grep -o '<d ' | wc -l | tr -d ' ' )" -ge 14 ]; then ok "P3b: two rows skipped above the window: every printed <alts> row carries a sel= (none empty, none sel_proven=0); the rest pages via next="; else no "P3b: $( printf '%s' "$altsw" | grep -o '<alts [^>]*>\|<d [^>]*sel=\"\"[^>]*>' | head -c 400 )"; fi
offw="$( printf '%s' "$altsw" | grep -o 'next="--defs=wide --offset=[0-9]*"' | sed 's/.*--offset=//; s/"$//' )"
run --defs=wide --offset="${offw:-0}" >"$TMP/p3bn.xml" 2>/dev/null
shownw="$( printf '%s' "$altsw" | grep -o 'p="[^"]*"' | sort )"
nextw="$( body "$TMP/p3bn.xml" | grep -o '<d [^>]*' | grep -o 'p="[^"]*"' | sort )"
repw="$( printf '%s\n%s\n' "$shownw" "$nextw" | sort | uniq -d | grep -c . )"
if [ -n "$offw" ] && [ "$repw" = 0 ] && printf '%s' "$nextw" | grep -q 'wd/w17.ts'; then ok "P3b next=: --defs=wide --offset=$offw starts at the first unprinted row (w17), repeating none"; else no "P3b next=: off=$offw repeats=$repw"; fi

echo "-- (P4) an untied C prototype is no second candidate: --path prints no <alts> (endpointDefinitionCount's rule)"
run --path=orphan,helperA >"$TMP/p4.xml" 2>/dev/null
if grep -q 'from_defs="2"' "$TMP/p4.xml" && ! grep -q '<alts' "$TMP/p4.xml"; then ok "P4: orphan = a definition + an untied header prototype -> from_defs=2 yet no <alts> (0 bytes)"; else no "P4: $( grep -o '<alts.*</alts>' "$TMP/p4.xml" | head -c 300 ) $( grep -o 'from_defs="[0-9]*"' "$TMP/p4.xml" )"; fi
run --defs=orphan >"$TMP/p4d.xml" 2>/dev/null
if grep -q '<name q="orphan" defs="2">' "$TMP/p4d.xml" && grep -q 'decl_only="1"' "$TMP/p4d.xml"; then ok "P4 control: --defs=orphan still lists both groups (the verb answering 'which definitions' is complete), the header decl_only"; else no "P4 control: $( grep -o '<name.*' "$TMP/p4d.xml" | head -c 300 )"; fi

run --path=twin,helperA >"$TMP/p4b.xml" 2>/dev/null
altsb="$( grep -o '<alts .*</alts>' "$TMP/p4b.xml" )"
if grep -q 'from_defs="3"' "$TMP/p4b.xml" && [ "$( printf '%s' "$altsb" | grep -o '<d ' | wc -l | tr -d ' ' )" = 2 ] && ! printf '%s' "$altsb" | grep -q 'twin.h'; then ok "P4b: twin = 2 real definitions + an untied header prototype: <alts> lists the 2 definitions, never the prototype"; else no "P4b: $altsb"; fi

echo "-- (P5) <alts> never re-lists a definition the answer prints as a pair endpoint; a tied contract still lists, decl_only rides"
run --path=ping,helperA --legend=full >"$TMP/p5.xml" 2>/dev/null
altsp="$( perl -0ne 'print "$1\n" while /<alts side="from"[^>]*>(.*?)<\/alts>/gs' "$TMP/p5.xml" )"
pairp="$( body "$TMP/p5.xml" | grep -o '<pair from_p="[^"]*"' | sed 's/.*from_p="//; s/"$//' | sort -u )"
dup=0; for pp in $pairp; do printf '%s' "$altsp" | grep -q "p=\"$pp\"" && dup=$(( dup + 1 )); done
if grep -q 'pairs_reaching="2"' "$TMP/p5.xml" && [ "$( printf '%s\n' "$pairp" | wc -l | tr -d ' ' )" = 2 ] && [ "$dup" -eq 0 ]; then ok "P5: 2 pairs print (ping1, ping2); neither is re-listed under <alts>"; else no "P5: pairs=[$pairp] dup=$dup alts=$altsp"; fi
if [ "$( printf '%s' "$altsp" | grep -o '<d ' | wc -l | tr -d ' ' )" = 2 ] && printf '%s' "$altsp" | grep -q 'p="src/ping3.ts:3"' && printf '%s' "$altsp" | grep -q 'sel="src/ping3.ts:Pinger.ping" class="source" decl_only="1"'; then ok "P5: the 2 definitions the answer does not print are listed; the interface contract carries decl_only=1"; else no "P5 rows: $altsp"; fi
if grep -q 'decl_only=1: no body (a header declaration' "$TMP/p5.xml" && xmllint --noout "$TMP/p5.xml" 2>/dev/null; then ok "P5: --legend=full reads decl_only=1 when a row carries it; well-formed"; else no "P5 legend / well-formedness"; fi
run --path=solo,helperA >"$TMP/p5d.xml" 2>/dev/null
if grep -q 'pairs_reaching="2"' "$TMP/p5d.xml" && ! grep -q '<alts' "$TMP/p5d.xml"; then ok "P5: solo = 2 definitions, both printed as pair endpoints -> nothing left to tell, no empty <alts> (0 bytes)"; else no "P5 solo: $( grep -o '<alts.*' "$TMP/p5d.xml" | head -c 300 )"; fi
run --path=run,helperA --legend=full >"$TMP/p5b.xml" 2>/dev/null
if grep -q '<alts' "$TMP/p5b.xml" && ! grep -q 'decl_only' "$TMP/p5b.xml"; then ok "P5 control: an <alts> with no decl_only row has no decl_only clause (present-only legend)"; else no "P5 control: decl_only text on an answer with no such row"; fi
run --path=ping,helperA >"$TMP/p5c.xml" 2>/dev/null
if grep -q 'alts d decl_only=1: no body' "$TMP/p5c.xml"; then ok "P5: the default (compact) legend reads decl_only=1 on --path"; else no "P5: compact legend lacks the path decl_only reading: $( grep -o '<!--.*-->' "$TMP/p5c.xml" | head -c 200 )"; fi

echo "-- (P6) an <alts> row whose sel= is NOT proven says so: the legend never claims it binds one alone (F7)"
run --path=inner,helperA --legend=full >"$TMP/p6.xml" 2>/dev/null
unp="$( grep -o '<alts .*</alts>' "$TMP/p6.xml" )"
if printf '%s' "$unp" | grep -q 'sel_proven="0"' && grep -q 'except on a sel_proven=0 row' "$TMP/p6.xml" && xmllint --noout "$TMP/p6.xml" 2>/dev/null; then ok "P6: a sel_proven=0 alts row -> --legend=full carries the 'except on a sel_proven=0 row' reading; well-formed"; else no "P6: alts=$unp"; fi
run --path=inner,helperA >"$TMP/p6c.xml" 2>/dev/null
if grep -q 'alts d sel_proven=0: no spelling tried' "$TMP/p6c.xml"; then ok "P6: the default (compact) legend reads sel_proven=0 on --path"; else no "P6: compact legend lacks the path sel_proven reading"; fi
if ! grep -q 'sel_proven' "$TMP/p5.xml" && ! grep -q 'sel_proven' "$TMP/p5c.xml"; then ok "P6 control: an <alts> whose sels are all proven carries no sel_proven text (present-only, both legends)"; else no "P6 control: sel_proven text on an all-proven <alts>"; fi

[ "$fail" -eq 0 ] && echo "defslookupcheck: OK" || echo "defslookupcheck: FAILURES above"
exit "$fail"
