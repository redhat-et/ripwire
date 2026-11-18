#!/usr/bin/env bash
# defaultceilingcheck.sh — P4 (capture-audit 2026-09-04, lane L7): the five verbs that had NO useful default ceiling
# now answer in one compact screen at defaults, every cut disclosed with capped="1" + next=, the restoring flag named.
#
# Lens 8 measured the defaults on the ripwire tree: --pr-context=main~1 659,824 B (~165K tokens, 217 files),
# --zoom 433,867 B (390 top modules x 6 levels), --tree 187,209 B (3,773 rows), --around=SYM 61,891 B (24,973
# tokens; --around-depth=1 was 5,860 B), --external-surface 67,862 B (1,422 rows led by sh builtins). Owner
# decision 4 (§5a): accepted — the first rows stay what they were, the tail is windowed and disclosed.
#
# THE CONTRACT (src/pageview.h kTreeRowCap/kZoomTopModuleCap/kExternalSurfaceRowCap, src/prcontext.h PrBudget,
# src/cli.h aroundDepth):
#   --around=SYM        default depth 1 (root depth="1"); every row of the default is a row of --around-depth=2
#   --zoom              shown_levels="2" of levels=; the 40 largest top modules (shown=/capped=/total=/next_offset=,
#                       next="--zoom --offset=40"); a module AT the cut carries children=; --zoom-levels=0 prints all
#   --tree              the 80 best files (shown="80" capped="1" total= next_offset= next="--tree --offset=80"); the
#                       first 30 rows are byte-identical to the uncapped (--limit=100000) tree's first 30
#   --external-surface  100 rows (shown= capped= next=); sh builtins dropped and COUNTED (builtins_excluded=);
#                       --include-builtins keeps them; the first 30 rows equal the uncapped listing's first 30
#   --pr-context[=REF]  budget_tokens="8000" budget_default="1" unless --token-budget/--max-tokens; est_tokens <=
#                       the budget; when even the structural floor exceeds it the FILES are windowed (the plain quintet:
#                       shown= capped="1" total= … next="--pr-context[=REF] --offset=N") and --offset=N continues the page
#   each answer at defaults is <= 12,000 B on this repo (pr-context: <= the 8000-token allowance)
# Every next= is run through the argv parser (exit 0 or 4). RED on the wave-2 binary: no ceiling, no attribute.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/defaultceilingcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found"; exit 2; }
run(){ ( cd "$ROOT" && "$BIN" . "$@" 2>"$TMP/err" ); }
rootattr(){ sed 's/<!--[^>]*-->//g' "$1" | grep -o "<$2 [^>]*>" | head -1 | grep -o " $3=\"[^\"]*\"" | head -1 | sed 's/.*="//; s/"$//'; }
nextof(){ sed 's/<!--[^>]*-->//g' "$1" | grep -o "<$2 [^>]*>" | head -1 | grep -o ' next="[^"]*"' | sed 's/ next="//; s/"$//' | sed 's/&quot;/"/g; s/&amp;/\&/g'; }
runs(){   # runs '<invocation>' → exit code, on the repo
    python3 -c 'import shlex, sys; print( "\0".join( shlex.split( sys.argv[1] ) ), end = "" )' "$1" > "$TMP/argv.bin"
    ( cd "$ROOT" && xargs -0 "$BIN" . < "$TMP/argv.bin" >"$TMP/nx.out" 2>"$TMP/nx.err" ); echo $?
}
bytes(){ wc -c <"$1" | tr -d ' '; }

echo "=== (1) --around: default depth 1, disclosed, a subset of depth 2 ==="
run --around=rankGraphTeleport >"$TMP/ar1"; run --around=rankGraphTeleport --around-depth=2 >"$TMP/ar2"
[ "$( bytes "$TMP/ar1" )" -le 12000 ] && ok "(1) --around at defaults is $( bytes "$TMP/ar1" ) B (<= 12,000; depth 2 is $( bytes "$TMP/ar2" ) B)" \
                                        || no "(1) --around at defaults is $( bytes "$TMP/ar1" ) B (> 12,000)"
if [ "$( rootattr "$TMP/ar1" r depth )" = 1 ]; then ok "(1) root discloses depth=\"1\""; else no "(1) root depth= is '$( rootattr "$TMP/ar1" r depth )' (want 1)"; fi
if [ "$( rootattr "$TMP/ar2" r depth )" = 2 ]; then ok "(1) --around-depth=2 restores depth=\"2\""; else no "(1) --around-depth=2 did not restore depth 2"; fi
grep -o '<s [^>]*n="[^"]*"' "$TMP/ar1" | grep -o 'n="[^"]*"' | sort -u >"$TMP/ar1.n"
grep -o '<s [^>]*n="[^"]*"' "$TMP/ar2" | grep -o 'n="[^"]*"' | sort -u >"$TMP/ar2.n"
missing="$( comm -23 "$TMP/ar1.n" "$TMP/ar2.n" | wc -l | tr -d ' ' )"
[ "$missing" = 0 ] && [ -s "$TMP/ar1.n" ] && ok "(1) every default row ($( wc -l <"$TMP/ar1.n" | tr -d ' ' ) symbols) is a depth-2 row (depth 2 has $( wc -l <"$TMP/ar2.n" | tr -d ' ' ))" \
                                              || no "(1) $missing default rows are NOT in the depth-2 neighbourhood"

echo "=== (2) --zoom: two levels, 40 top modules, children= at the cut, next= pastes the page ==="
run --zoom >"$TMP/z1"; run --zoom --zoom-levels=0 --limit=100000 >"$TMP/z0"
[ "$( bytes "$TMP/z1" )" -le 12000 ] && ok "(2) --zoom at defaults is $( bytes "$TMP/z1" ) B (<= 12,000; every level of every module is $( bytes "$TMP/z0" ) B)" \
                                       || no "(2) --zoom at defaults is $( bytes "$TMP/z1" ) B (> 12,000)"
L="$( rootattr "$TMP/z1" zoom levels )"; LS="$( rootattr "$TMP/z1" zoom shown_levels )"
if [ "$L" -ge 2 ] 2>/dev/null; then
    if [ "$LS" = 2 ]; then ok "(2) shown_levels=\"2\" of levels=\"$L\""; else no "(2) shown_levels='$LS' (want 2 of $L)"; fi
    cut="$( grep -o '<module level="[0-9]*"[^>]*children="[0-9]*"' "$TMP/z1" | wc -l | tr -d ' ' )"
    if [ "$cut" -gt 0 ]; then ok "(2) $cut module rows at the cut carry children="; else no "(2) no module row carries children= although levels were cut"; fi
    deeper="$( grep -o '<module level="[0-9]*"' "$TMP/z1" | sort -u | wc -l | tr -d ' ' )"
    if [ "$deeper" = 2 ]; then ok "(2) exactly 2 distinct levels printed"; else no "(2) $deeper distinct levels printed (want 2)"; fi
else
    ok "(2) hierarchy has $L level(s) — nothing to cut"
fi
[ "$( rootattr "$TMP/z1" zoom capped )" = 1 ] && [ "$( rootattr "$TMP/z1" zoom shown )" = 40 ] \
    && ok "(2) top modules windowed: shown=\"40\" capped=\"1\" total=\"$( rootattr "$TMP/z1" zoom total )\" next_offset=\"$( rootattr "$TMP/z1" zoom next_offset )\"" \
    || no "(2) top-module window not disclosed (shown='$( rootattr "$TMP/z1" zoom shown )' capped='$( rootattr "$TMP/z1" zoom capped )')"
if nz="$( nextof "$TMP/z1" zoom )"; [ "$nz" = "--zoom --offset=40" ]; then ok "(2) next=\"$nz\""; else no "(2) next='$nz' (want --zoom --offset=40)"; fi
if rc="$( runs "$nz" )"; { [ "$rc" = 0 ] || [ "$rc" = 4 ]; }; then ok "(2) next= runs (exit $rc)"; else no "(2) next= exits $rc"; fi
if [ "$( rootattr "$TMP/z0" zoom shown_levels )" = "$L" ]; then ok "(2) --zoom-levels=0 prints every level (shown_levels=\"$L\")"; else no "(2) --zoom-levels=0 shown_levels='$( rootattr "$TMP/z0" zoom shown_levels )'"; fi
# the top two levels' module rows are the SAME rows (minus children=) — the cut removed depth, not modules
grep -o '<module level="[0-9]*" id="[0-9]*" size="[0-9]*"' "$TMP/z1" | sort >"$TMP/z1.m"
top2="$( grep -o '<module level="[0-9]*"' "$TMP/z1" | sort -u | sed 's/.*level="//; s/"//' | sort -n | tr '\n' ' ' )"
grep -o '<module level="[0-9]*" id="[0-9]*" size="[0-9]*"' "$TMP/z0" | awk -v lv="$top2" 'BEGIN{split(lv,a," "); for(i in a) keep["level=\"" a[i] "\""]=1} { if ($2 in keep) print }' | sort >"$TMP/z0.m"
# z0 has ALL top modules (no window); restrict to the 40 windowed ids by intersecting on z1's rows
comm -23 "$TMP/z1.m" "$TMP/z0.m" >"$TMP/z.diff"
if [ ! -s "$TMP/z.diff" ]; then ok "(2) every printed module row is a row of the uncut hierarchy (same level/id/size)"; else no "(2) $( wc -l <"$TMP/z.diff" | tr -d ' ' ) module rows differ from the uncut hierarchy"; fi
if "$BIN" . --zoom-levels=0 >/dev/null 2>"$TMP/e"; [ $? -ne 0 ] && grep -q -- '--zoom-levels' "$TMP/e"; then ok "(2) bare --zoom-levels refuses naming --zoom"; else no "(2) bare --zoom-levels did not refuse"; fi

echo "=== (3) --tree: 80 files, disclosed, next=, first 30 rows unchanged ==="
run --tree >"$TMP/t1"; run --tree --limit=100000 >"$TMP/t0"
[ "$( bytes "$TMP/t1" )" -le 12000 ] && ok "(3) --tree at defaults is $( bytes "$TMP/t1" ) B (<= 12,000; the whole tree is $( bytes "$TMP/t0" ) B)" \
                                       || no "(3) --tree at defaults is $( bytes "$TMP/t1" ) B (> 12,000)"
[ "$( rootattr "$TMP/t1" tree shown )" = 80 ] && [ "$( rootattr "$TMP/t1" tree capped )" = 1 ] && [ -n "$( rootattr "$TMP/t1" tree next_offset )" ] \
    && ok "(3) shown=\"80\" capped=\"1\" total=\"$( rootattr "$TMP/t1" tree total )\" next_offset=\"$( rootattr "$TMP/t1" tree next_offset )\"" \
    || no "(3) tree window not disclosed: shown='$( rootattr "$TMP/t1" tree shown )' capped='$( rootattr "$TMP/t1" tree capped )'"
if nt="$( nextof "$TMP/t1" tree )"; [ "$nt" = "--tree --offset=80" ]; then ok "(3) next=\"$nt\""; else no "(3) next='$nt' (want --tree --offset=80)"; fi
if rc="$( runs "$nt" )"; { [ "$rc" = 0 ] || [ "$rc" = 4 ]; }; then ok "(3) next= runs (exit $rc)"; else no "(3) next= exits $rc"; fi
grep -o '<file p="[^"]*"[^>]*>' "$TMP/t1" | head -30 >"$TMP/t1.30"; grep -o '<file p="[^"]*"[^>]*>' "$TMP/t0" | head -30 >"$TMP/t0.30"
if cmp -s "$TMP/t1.30" "$TMP/t0.30"; then ok "(3) the first 30 file rows are byte-identical to the uncapped tree's"; else no "(3) the first 30 file rows moved: $( diff "$TMP/t1.30" "$TMP/t0.30" | head -3 | tr '\n' ' ' )"; fi
if [ -z "$( rootattr "$TMP/t0" tree capped )" ] || [ "$( rootattr "$TMP/t0" tree capped )" = 0 ]; then ok "(3) --limit=100000 lifts the window (no cut disclosed)"; else no "(3) --limit=100000 still capped"; fi

echo "=== (4) --external-surface: 100 rows, builtins dropped and counted, --include-builtins restores ==="
run --external-surface >"$TMP/x1"; run --external-surface --include-builtins >"$TMP/x2"; run --external-surface --limit=100000 >"$TMP/x0"
[ "$( bytes "$TMP/x1" )" -le 12000 ] && ok "(4) --external-surface at defaults is $( bytes "$TMP/x1" ) B (<= 12,000; everything is $( bytes "$TMP/x0" ) B)" \
                                       || no "(4) --external-surface at defaults is $( bytes "$TMP/x1" ) B (> 12,000)"
[ "$( rootattr "$TMP/x1" external-surface shown )" = 100 ] && [ "$( rootattr "$TMP/x1" external-surface capped )" = 1 ] \
    && ok "(4) shown=\"100\" capped=\"1\" total=\"$( rootattr "$TMP/x1" external-surface total )\"" \
    || no "(4) window not disclosed: shown='$( rootattr "$TMP/x1" external-surface shown )'"
be="$( rootattr "$TMP/x1" external-surface builtins_excluded )"
if [ -n "$be" ] && [ "$be" -gt 0 ]; then ok "(4) builtins_excluded=\"$be\" counts the dropped sh builtins"; else no "(4) builtins_excluded= absent or zero ('$be')"; fi
grep -q '<x n="echo" lang="sh"' "$TMP/x1" && no "(4) the default still lists the sh builtin echo" || ok "(4) echo (sh) is not listed by default"
if grep -q '<x n="echo" lang="sh"' "$TMP/x2"; then ok "(4) --include-builtins lists echo (sh) again"; else no "(4) --include-builtins did not restore echo"; fi
if [ -z "$( rootattr "$TMP/x2" external-surface builtins_excluded )" ]; then ok "(4) --include-builtins carries no builtins_excluded="; else no "(4) --include-builtins still says builtins_excluded="; fi
if nx="$( nextof "$TMP/x1" external-surface )"; [ "$nx" = "--external-surface --offset=100" ]; then ok "(4) next=\"$nx\""; else no "(4) next='$nx'"; fi
if rc="$( runs "$nx" )"; { [ "$rc" = 0 ] || [ "$rc" = 4 ]; }; then ok "(4) next= runs (exit $rc)"; else no "(4) next= exits $rc"; fi
grep -o '<x [^>]*>' "$TMP/x1" | head -30 >"$TMP/x1.30"; grep -o '<x [^>]*>' "$TMP/x0" | head -30 >"$TMP/x0.30"
if cmp -s "$TMP/x1.30" "$TMP/x0.30"; then ok "(4) the first 30 rows are byte-identical to the uncapped listing's"; else no "(4) the first 30 rows moved"; fi
if "$BIN" . --include-builtins >/dev/null 2>"$TMP/e"; [ $? -ne 0 ] && grep -q -- '--include-builtins' "$TMP/e"; then ok "(4) bare --include-builtins refuses naming --external-surface"; else no "(4) bare --include-builtins did not refuse"; fi

echo "=== (5) --pr-context: budgeted by default (8000 tokens), the file window when the floor exceeds it ==="
# a fixture with 120 changed files: the structural floor alone is far over 8000 tokens
REPO="$TMP/repo"; mkdir -p "$REPO/src"
( cd "$REPO" && git init -q && git config user.email "t@example.com" && git config user.name "t" )
for i in $( seq 1 120 ); do printf 'int f%s_a( int x ) { return x + %s; }\nint f%s_b( int y ) { return f%s_a( y ) * 2; }\n' "$i" "$i" "$i" "$i" > "$REPO/src/m$i.cpp"; done
( cd "$REPO" && git add -A && git commit -q -m one )
for i in $( seq 1 120 ); do printf 'int f%s_c( int z ) { return f%s_b( z ) - 1; }\n' "$i" "$i" >> "$REPO/src/m$i.cpp"; done
prrun(){ ( cd "$REPO" && "$BIN" . "$@" --no-cache 2>"$TMP/prerr" ); }
prrun --pr-context >"$TMP/p1"
[ "$( rootattr "$TMP/p1" pr-context budget_tokens )" = 8000 ] && [ "$( rootattr "$TMP/p1" pr-context budget_default )" = 1 ] \
    && ok "(5) default root: budget_tokens=\"8000\" budget_default=\"1\"" \
    || no "(5) default root lacks the default budget (budget_tokens='$( rootattr "$TMP/p1" pr-context budget_tokens )' budget_default='$( rootattr "$TMP/p1" pr-context budget_default )')"
if est="$( rootattr "$TMP/p1" pr-context est_tokens )"; [ -n "$est" ] && [ "$est" -le 8000 ]; then ok "(5) est_tokens=\"$est\" <= 8000"; else no "(5) est_tokens='$est' exceeds the default budget"; fi
fs="$( rootattr "$TMP/p1" pr-context shown )"; tot="$( rootattr "$TMP/p1" pr-context files )"
[ -n "$fs" ] && [ "$fs" -lt "$tot" ] && [ "$( rootattr "$TMP/p1" pr-context capped )" = 1 ] \
    && ok "(5) 120-file floor over budget: shown=\"$fs\" of files=\"$tot\", capped=\"1\" next_offset=\"$( rootattr "$TMP/p1" pr-context next_offset )\"" \
    || no "(5) the file window did not fire (shown='$fs' files='$tot' capped='$( rootattr "$TMP/p1" pr-context capped )')"
if [ "$( grep -o '<file p=' "$TMP/p1" | wc -l | tr -d ' ' )" = "$fs" ]; then ok "(5) <file> rows == shown"; else no "(5) <file> rows != shown"; fi
if np="$( nextof "$TMP/p1" pr-context )"; [ "$np" = "--pr-context --offset=$fs" ]; then ok "(5) next=\"$np\""; else no "(5) next='$np' (want --pr-context --offset=$fs)"; fi
prrun --pr-context --offset="$fs" >"$TMP/p2"
[ "$( rootattr "$TMP/p2" pr-context offset )" = "$fs" ] && [ "$( grep -o '<file p=' "$TMP/p2" | wc -l | tr -d ' ' )" -gt 0 ] \
    && ok "(5) --offset=$fs continues the page (offset=\"$fs\", $( grep -o '<file p=' "$TMP/p2" | wc -l | tr -d ' ' ) files)" || no "(5) --offset=$fs did not continue the page"
prrun --pr-context --max-tokens=1000000 >"$TMP/p3"
[ "$( grep -o '<file p=' "$TMP/p3" | wc -l | tr -d ' ' )" = "$tot" ] && [ -z "$( rootattr "$TMP/p3" pr-context budget_default )" ] \
    && ok "(5) --max-tokens=1000000: every file, no budget_default=" || no "(5) explicit large budget did not lift the window"
# the ceiling is in TOKENS as the tool prices them (est_tokens <= 8000 above); in bytes that is the 8000-token
# allowance at the densest-language rate (kMinBytesPerToken, ~2.36 B/tok = 18,880 B) plus the ~5 KB full legend
if [ "$( bytes "$TMP/p1" )" -le 24000 ]; then ok "(5) default answer is $( bytes "$TMP/p1" ) B (<= 24,000: the 8000-token allowance + legend)"; else no "(5) default answer is $( bytes "$TMP/p1" ) B (> 24,000)"; fi
# wave-3 close (2026-09-05): HEAD~1 is whatever the operator committed last — an acks-only or docs-only commit diffs
# NO indexed file, and the empty-diff root carries no budget tail at all (files="0", its own comment), so this arm went
# red on the integration branch for a non-defect. The base is now the parent of the last commit that touched src/,
# so the diff always holds an indexed change and the arm measures the budget, not the operator's commit history.
SRCBASE="$( git -C "$ROOT" log -1 --format=%h -- src/ 2>/dev/null )~1"
run --pr-context="$SRCBASE" >"$TMP/p4"
[ "$( rootattr "$TMP/p4" pr-context budget_default )" = 1 ] && ok "(5) --pr-context=$SRCBASE (parent of the last src/ commit) carries budget_default=\"1\" ($( bytes "$TMP/p4" ) B, est_tokens=\"$( rootattr "$TMP/p4" pr-context est_tokens )\")" \
                                                          || no "(5) --pr-context=$SRCBASE lacks budget_default= (the diff holds an indexed change, so the default budget must ride the root)"

echo "=== (7) cut-fix E: next= keeps the caller's --limit; --tree symbol lists and --zoom bridges disclose their cuts ==="
# RED on 9936ba4e: next= dropped --limit (a --limit=5 page pointed at an 80/40/100-row page), --tree's 3-symbol cut
# said nothing past symbols=, --zoom's 12-bridge cut had no total and no flag, and the --mermaid caps were silent.
run --tree --limit=5 >"$TMP/t5"; run --tree --limit=10 >"$TMP/t10"
if nt5="$( nextof "$TMP/t5" tree )"; [ "$nt5" = "--tree --limit=5 --offset=5" ]; then ok "(7) --tree --limit=5 next=\"$nt5\""; else no "(7) --tree --limit=5 next='$nt5' (want --tree --limit=5 --offset=5)"; fi
python3 -c 'import shlex, sys; print( "\0".join( shlex.split( sys.argv[1] ) ), end = "" )' "$nt5" > "$TMP/argv.bin"
( cd "$ROOT" && xargs -0 "$BIN" . < "$TMP/argv.bin" >"$TMP/t5b" 2>/dev/null )
grep -o '<file p="[^"]*"' "$TMP/t10" | tail -5 >"$TMP/t10.tail"; grep -o '<file p="[^"]*"' "$TMP/t5b" >"$TMP/t5b.rows"
if [ -s "$TMP/t5b.rows" ] && cmp -s "$TMP/t10.tail" "$TMP/t5b.rows"; then ok "(7) pasting it serves rows 6-10 of the --limit=10 page, no more"; else no "(7) the pasted next= page is not rows 6-10 ($( wc -l <"$TMP/t5b.rows" | tr -d ' ' ) rows)"; fi
ss="$( rootattr "$TMP/t5" tree shown_symbols )"; srows="$( grep -o '<s t="' "$TMP/t5" | wc -l | tr -d ' ' )"
if [ -n "$ss" ] && [ "$ss" = "$srows" ] && [ "$( rootattr "$TMP/t5" tree symbols_capped )" = 1 ]; then ok "(7) --tree root shown_symbols=\"$ss\" symbols_capped=\"1\" (= the <s> rows)"; else no "(7) --tree symbol cut undisclosed: shown_symbols='$ss' for $srows <s> rows"; fi
run --zoom --limit=3 >"$TMP/z3"
if nz3="$( nextof "$TMP/z3" zoom )"; [ "$nz3" = "--zoom --limit=3 --offset=3" ]; then ok "(7) --zoom --limit=3 next=\"$nz3\""; else no "(7) --zoom --limit=3 next='$nz3'"; fi
run --zoom=2 --zoom-levels=1 --limit=3 >"$TMP/z23"
if nz23="$( nextof "$TMP/z23" zoom )"; [ "$nz23" = "--zoom=2 --zoom-levels=1 --limit=3 --offset=3" ]; then ok "(7) the depth flags ride too: next=\"$nz23\""; else no "(7) --zoom=2 --zoom-levels=1 --limit=3 next='$nz23'"; fi
if rc="$( runs "$nz23" )"; { [ "$rc" = 0 ] || [ "$rc" = 4 ]; }; then ok "(7) that next= runs (exit $rc)"; else no "(7) that next= exits $rc"; fi
run --external-surface --limit=7 >"$TMP/x7"
if nx7="$( nextof "$TMP/x7" external-surface )"; [ "$nx7" = "--external-surface --limit=7 --offset=7" ]; then ok "(7) --external-surface --limit=7 next=\"$nx7\""; else no "(7) --external-surface --limit=7 next='$nx7'"; fi
# --zoom bridges: 40 files, each a 6-function cycle whose head calls three other files — 20 top modules, 100 pairs
ZB="$TMP/zb"; mkdir -p "$ZB"
python3 - "$ZB" <<'PY'
import os, sys
for i in range( 40 ):
    with open( os.path.join( sys.argv[1], "m%02d.c" % i ), "w" ) as f:
        for j in range( 6 ):
            body = " ".join( "c%d_%d();" % ( i, ( j + d ) % 6 ) for d in ( 1, 2, 3 ) )
            if j == 0:
                body += " " + " ".join( "c%d_0();" % ( ( i + d ) % 40 ) for d in ( 1, 7, 13 ) )
            f.write( "void c%d_%d(void) { %s }\n" % ( i, j, body ) )
PY
zb(){ ( cd "$ZB" && "$BIN" . --no-cache "$@" 2>/dev/null ); }
zb --zoom=1 >"$TMP/zb1"
brows="$( grep -o '<bridge a="' "$TMP/zb1" | wc -l | tr -d ' ' )"; bt="$( rootattr "$TMP/zb1" zoom bridges )"
if [ "$( rootattr "$TMP/zb1" zoom shown_bridges )" = "$brows" ] && [ "$brows" = 12 ] && [ "$( rootattr "$TMP/zb1" zoom bridges_capped )" = 1 ] && [ "${bt:-0}" -gt 12 ]; then
    ok "(7) --zoom bridge cut disclosed: shown_bridges=\"12\" bridges_capped=\"1\" bridges=\"$bt\""
else no "(7) --zoom bridge cut: $brows rows, shown_bridges='$( rootattr "$TMP/zb1" zoom shown_bridges )' bridges='$bt'"; fi
zb --zoom >"$TMP/zb0"
if [ -z "$( rootattr "$TMP/zb0" zoom shown_bridges )" ] && [ "$( grep -o '<bridge a="' "$TMP/zb0" | wc -l | tr -d ' ' )" -le 12 ]; then ok "(7) an uncut bridge list adds no bytes (no shown_bridges=)"; else no "(7) an uncut bridge list carries shown_bridges="; fi
zb --zoom=1 --mermaid >"$TMP/zbm"
if grep -qx '%% top modules shown=10 total=20 capped=1' "$TMP/zbm"; then ok "(7) --zoom --mermaid names its top-module cut"; else no "(7) --zoom --mermaid top-module cut is silent"; fi
zb --zoom --mermaid >"$TMP/zbm0"
if grep -qx '    %% child modules shown=8 total=10 capped=1' "$TMP/zbm0"; then ok "(7) --zoom --mermaid names a child-module cut inside its subgraph"; else no "(7) --zoom --mermaid child-module cut is silent"; fi

echo "=== (6) well-formed + deterministic ==="
if command -v xmllint >/dev/null 2>&1; then
    for f in ar1 z1 t1 x1 x2 p1 p2; do xmllint --noout "$TMP/$f" >/dev/null 2>&1 || no "(6) $f is malformed XML"; done
    ok "(6) the seven documents are well-formed"
fi
if run --zoom >"$TMP/z1b"; cmp -s "$TMP/z1" "$TMP/z1b"; then ok "(6) --zoom deterministic"; else no "(6) --zoom differs between runs"; fi
if prrun --pr-context >"$TMP/p1b"; cmp -s "$TMP/p1" "$TMP/p1b"; then ok "(6) --pr-context deterministic"; else no "(6) --pr-context differs between runs"; fi

[ "$fail" -eq 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
