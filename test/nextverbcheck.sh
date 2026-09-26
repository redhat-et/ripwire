#!/usr/bin/env bash
# nextverbcheck.sh — P3 (capture-audit 2026-09-04, lane L7): every root in the enumeration hands the agent its
# next step as ONE pasteable invocation, next="…" (≤120 B), and every such invocation actually runs.
#
# Lens 8: of 103 live outputs only five named a follow-up verb; --callers/--impact/--uses/--edit-check/
# --quality-delta/--test-gate/--safe-delete/--situ handed the agent nothing, so a contract-change took three
# calls (edit-check → guess --uses → open the file). The contract (src/nextverb.h):
#   --edit-check   contract-change → --uses=SYM;  otherwise → --test-gate=FILE
#   --impact       → --safe-delete=SYM                  --callers → --uses=SELECTOR (bare NAME only for narrowed declined calls)
#   --callees      → --expand=SYM                       --quality-delta gating ROW → --expand=FILE:NAME (on the row)
#   --test-gate    → its first run= command (a shell line, so it is checked against the rows, not run)
#   --situ         → a `next: --test-gate` line          --from-trace → --slice=@FILE:LINE of the innermost frame
#   --grep         → --at=FILE:LINE of the top hit | the next page under --legend=compact when capped | --for=PAT on zero hits
#   --for          → the r=1 row carries --expand=FILE:NAME
# Every next= that starts with `--` is split with shlex and run through the argv parser on the same tree: exit 0
# or 4, never 1 (a refusal would mean the tool suggested something it cannot do). RED on the wave-2 binary:
# no root carried the attribute.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/nextverbcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found"; exit 2; }

# ── fixture: test/fixture in a git repo, then a WORKING-TREE edit that (a) changes total_area's contract and
#    (b) adds a function over the ccx bar, so --edit-check says contract-change and --quality-delta gates ──
REPO="$TMP/repo"; mkdir -p "$REPO"; cp -R "$FIX"/. "$REPO"/
( cd "$REPO" && git init -q && git config user.email "t@example.com" && git config user.name "t" \
  && git add -A && git commit -q -m "one" ) || { echo "fixture git setup failed"; exit 2; }
python3 - "$REPO/geometry.cpp" "$REPO/app.py" <<'PY'
import sys
cpp, py = sys.argv[1], sys.argv[2]
s = open( py ).read()
assert "def total_area(triangles):" in s
s = s.replace( "def total_area(triangles):", "def total_area(triangles, scale):", 1 )
open( py, "w" ).write( s )
c = open( cpp ).read()
old = """double perimeter( const Point* pts, int n )
{
    double total = 0.0;
    for( int i = 0; i < n; ++i )
    {
        total += distance( pts[i], pts[ ( i + 1 ) % n ] );   // edge: perimeter -> distance
    }
    return total;
}"""
assert old in c
new = """double perimeter( const Point* pts, int n )
{
    double total = 0.0;
    for( int i = 0; i < n; ++i )
    {
        if( n > 1 ) { if( i > 0 ) { if( pts[i].x > pts[i-1].x ) { total += 1; } else if( pts[i].x < pts[i-1].x ) { total += 2; } else { total += 3; } }
                      else if( i == 0 ) { for( int j = 0; j < n; ++j ) { if( j % 2 ) { total += j; } else { total -= j; } } }
                      else { while( total > 100 ) { total -= 7; } } }
        else if( n == 1 ) { switch( i ) { case 0: total += 1; break; case 1: total += 2; break; default: total += 3; break; } }
        else { total += ( n && i ) || ( pts && n ) ? 1 : 0; }
        total += distance( pts[i], pts[ ( i + 1 ) % n ] );   // edge: perimeter -> distance
    }
    return total;
}"""
open( cpp, "w" ).write( c.replace( old, new, 1 ) )
PY
printf 'at distance (geometry.cpp:5)\n' > "$TMP/trace.txt"
rrun(){ ( cd "$REPO" && "$BIN" . "$@" --no-cache 2>"$TMP/rerr" ); }

# next= values of the ROOT (first element) and of every ROW, as lines: "root|value" / "row|value"
nexts(){ python3 - "$1" <<'PY'
import sys, re
b = open( sys.argv[1], encoding = "utf-8", errors = "replace" ).read()
# strip comments and CDATA
b = re.sub( r"<!--.*?-->", "", b, flags = re.S ); b = re.sub( r"<!\[CDATA\[.*?\]\]>", "", b, flags = re.S )
tags = re.findall( r"<[A-Za-z][^>]*>", b )
for i, t in enumerate( tags ):
    m = re.search( r'\snext="([^"]*)"', t )
    if m:
        v = m.group( 1 ).replace( "&quot;", '"' ).replace( "&apos;", "'" ).replace( "&lt;", "<" ).replace( "&gt;", ">" ).replace( "&amp;", "&" )
        print( ( "root|" if i == 0 else "row|" ) + v )
PY
}
# run a `--…` invocation through the parser on the fixture; exit must be 0 or 4
runs(){   # runs '<invocation>' → prints exit code
    python3 -c 'import shlex, sys; print( "\0".join( shlex.split( sys.argv[1] ) ), end = "" )' "$1" > "$TMP/argv.bin"
    ( cd "$REPO" && xargs -0 "$BIN" . --no-cache < "$TMP/argv.bin" >"$TMP/nx.out" 2>"$TMP/nx.err" ); echo $?
}
checkNext(){   # checkNext LABEL DOCFILE EXPECT-REGEX [row]
    local label="$1" doc="$2" want="$3" where="${4:-root}"
    local line v rc n
    line="$( nexts "$doc" | grep "^$where|" | head -1 )"
    if [ -z "$line" ]; then no "$label: no next= on the $where"; return; fi
    v="${line#*|}"
    [ "${#v}" -le 120 ] || no "$label: next= is ${#v} B (> 120): $v"
    printf '%s' "$v" | grep -qE -- "$want" || no "$label: next=\"$v\" does not match /$want/"
    case "$v" in
        --*) rc="$( runs "$v" )"
             if [ "$rc" = 0 ] || [ "$rc" = 4 ]; then ok "$label: next=\"$v\" parses and runs (exit $rc)"
             else no "$label: next=\"$v\" exits $rc: $( head -c 160 "$TMP/nx.err" | tr '\n' ' ' )"; fi ;;
        *)   if grep -qF "run=\"$( printf '%s' "$v" | sed 's/&/\&amp;/g; s/"/\&quot;/g' )\"" "$doc"; then ok "$label: next=\"$v\" is one of the rows' run= commands"
             else no "$label: next=\"$v\" is a shell line that matches no row's run="; fi ;;
    esac
}

echo "=== (1) --edit-check: contract-change → --uses=SYM; unchanged → --test-gate=FILE ==="
rrun --edit-check=total_area >"$TMP/ec1"; grep -q 'status="contract-change"' "$TMP/ec1" \
    && checkNext "edit-check contract-change" "$TMP/ec1" '^--uses=total_area$' \
    || no "fixture: --edit-check=total_area is not a contract-change ($( grep -o 'status="[^"]*"' "$TMP/ec1" ))"
rrun --edit-check=area_of_triangle >"$TMP/ec2"; checkNext "edit-check unchanged" "$TMP/ec2" '^--test-gate=app\.py$'

echo "=== (2) --impact → --safe-delete=SYM; --callers → --uses=SELECTOR (@FILE:LINE mirrored); --callees → --expand=SYM ==="
rrun --impact=distance >"$TMP/im"; checkNext "impact" "$TMP/im" '^--safe-delete=distance$'
rrun --callers=distance >"$TMP/ca"; checkNext "callers" "$TMP/ca" '^--uses=distance$'
rrun --callers=@geometry.cpp:5 >"$TMP/ca2"; checkNext "callers @FILE:LINE" "$TMP/ca2" '^--uses=@geometry\.cpp:5$'
rrun --callees=total_area >"$TMP/ce"; checkNext "callees" "$TMP/ce" '^--expand=total_area$'
rrun --callers=distance --format=columnar >"$TMP/cac"; checkNext "callers columnar" "$TMP/cac" '^--uses=distance$'

echo "=== (2b) 2026-09-25 regression: --impact with a LONG name keeps its full, runnable --safe-delete= ==="
# From independent review, 2026-09-25: a long symbol name pushes --impact's root
# next= past 120 B on an UNCUT answer, and the first draft of this lane's fix replaced a complete,
# correctly-quoted, runnable next="--safe-delete=NAME" with next_dropped="1" — a working follow-up lost for
# no reason but its own length. The ruling: nextAttrXml carries no length ceiling at all, so this stays the
# FULL invocation whatever it costs. checkNext's own `${#v} -le 120` line is a fixture artifact of every
# OTHER arm in this file, not a runtime contract, so this arm builds a fixture
# deliberately over it and checks the invocation directly instead of through checkNext.
LONGSYM="a_very_long_python_function_name_that_a_caller_uses_and_that_pushes_the_next_invocation_well_past_one_hundred_and_twenty_bytes_total"
LREPO="$TMP/longsym"; mkdir -p "$LREPO"
printf 'def %s():\n    return 1\n\ndef caller():\n    return %s()\n' "$LONGSYM" "$LONGSYM" > "$LREPO/mod.py"
( cd "$LREPO" && git init -q && git config user.email "t@example.com" && git config user.name "t" \
  && git add -A && git commit -q -m "one" ) || { echo "long-symbol fixture git setup failed"; exit 2; }
( cd "$LREPO" && "$BIN" . --impact="$LONGSYM" --no-cache >"$TMP/im2" 2>"$TMP/im2err" )
NEXTIM2LINE="$( nexts "$TMP/im2" | grep '^root|' | head -1 )"
NEXTIM2="${NEXTIM2LINE#*|}"
if [ -z "$NEXTIM2" ]; then
    no "impact long-name regression: no next= on --impact=\$LONGSYM's root (want the full --safe-delete= invocation)"
else
    if [ "${#NEXTIM2}" -gt 120 ]; then ok "impact long-name regression: fixture next= is ${#NEXTIM2} B (>120) — a real test of the no-ceiling rule"
    else no "impact long-name regression: fixture next= is only ${#NEXTIM2} B (<=120) — not a real test"; fi
    printf '%s' "$NEXTIM2" | grep -qE -- "^--safe-delete=${LONGSYM}\$" \
        && ok "impact long-name regression: next=\"$NEXTIM2\" is the full --safe-delete=$LONGSYM, never dropped" \
        || no "impact long-name regression: next=\"$NEXTIM2\" does not match /^--safe-delete=$LONGSYM\$/"
    python3 -c 'import shlex, sys; print( "\0".join( shlex.split( sys.argv[1] ) ), end = "" )' "$NEXTIM2" > "$TMP/argv2.bin"
    rc2="$( ( cd "$LREPO" && xargs -0 "$BIN" . --no-cache < "$TMP/argv2.bin" >"$TMP/nx2.out" 2>"$TMP/nx2.err" ); echo $? )"
    if [ "$rc2" = 0 ] || [ "$rc2" = 4 ]; then ok "impact long-name regression: next=\"$NEXTIM2\" parses and runs (exit $rc2)"
    else no "impact long-name regression: next=\"$NEXTIM2\" exits $rc2: $( head -c 160 "$TMP/nx2.err" | tr '\n' ' ' )"; fi
fi

echo "=== (3) --quality-delta: every gating row carries --expand=FILE:NAME ==="
rrun --quality-delta >"$TMP/qd"
gating="$( grep -o '<r [^>]*gating="1"[^>]*>' "$TMP/qd" | wc -l | tr -d ' ' )"
withnext="$( grep -o '<r [^>]*gating="1"[^>]*next="--expand=[^"]*"[^>]*>' "$TMP/qd" | wc -l | tr -d ' ' )"
if [ "$gating" -gt 0 ] && [ "$gating" = "$withnext" ]; then ok "quality-delta: $gating gating row(s), each with next=\"--expand=FILE:NAME\""
else no "quality-delta: $gating gating row(s), $withnext with next= ($( grep -o '<r [^>]*gating="1"[^>]*>' "$TMP/qd" | head -1 | cut -c1-200 ))"; fi
checkNext "quality-delta gating row" "$TMP/qd" '^--expand=geometry\.cpp:' row
nongating="$( grep -o '<r [^>]*next=' "$TMP/qd" | grep -vc 'gating="1"' || true )"
if [ "$nongating" = 0 ]; then ok "quality-delta: next= rides gating rows only"; else no "quality-delta: $nongating non-gating row(s) carry next="; fi

echo "=== (4) --test-gate → its first run= (or a ripwire invocation when no runner is derivable) ==="
rrun --test-gate=geometry.cpp >"$TMP/tg"; checkNext "test-gate" "$TMP/tg" '.'
rrun --test-gate=geometry.cpp --json >"$TMP/tgj"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d.get("next"),str) and d["next"] else 1)' "$TMP/tgj" \
    && ok "test-gate --json carries the same \"next\" key" || no "test-gate --json lacks \"next\""

echo "=== (5) --situ → next: --test-gate; --from-trace → --slice=@FILE:LINE ==="
if rrun --situ >"$TMP/si"; grep -q '^  next: --test-gate' "$TMP/si"; then ok "situ: prose ends with 'next: --test-gate'"; else no "situ: no 'next: --test-gate' line"; fi
rrun --from-trace="$TMP/trace.txt" >"$TMP/ft"; checkNext "from-trace" "$TMP/ft" '^--slice=@geometry\.cpp:5$'

echo "=== (6) --grep: top hit → --at=FILE:LINE; capped → next page under --legend=compact; zero hits → --for=PAT ==="
rrun --grep=distance >"$TMP/g1"; checkNext "grep top hit" "$TMP/g1" '^--at=[^ ]+:[0-9]+$'
rrun --grep=distance --limit=1 >"$TMP/g2"; checkNext "grep capped" "$TMP/g2" '^--grep=distance --offset=1 --legend=compact$'
rrun --regex='dist.*' --limit=1 >"$TMP/g3"; checkNext "regex capped" "$TMP/g3" "^--regex='?dist\.\*'? --offset=1 --legend=compact$"
rrun --grep=zzqnothinghere >"$TMP/g4"; checkNext "grep zero-hit" "$TMP/g4" '^--for=zzqnothinghere$'

echo "=== (7) --for: the r=1 row carries --expand=FILE:NAME; every other row does not ==="
rrun --for='geometry distance' >"$TMP/for"
top="$( grep -o '<d [^>]*r="1"[^>]*>' "$TMP/for" | head -1 )"
# L-W (forpage.h, test/forwidencheck.sh pins the rule): on a THIN answer (coverage= under 50, or a head over
# fewer than 3 files) the r=1 row hands over the FILE-GRAIN widening page instead of the body — either form
# is the one pasteable follow-up this arm asserts; which form is right is forwidencheck's job, not this one's.
printf '%s' "$top" | grep -Eq 'next="(--expand=|--for=)' && ok "for: the r=1 row carries next= ($( printf '%s' "$top" | grep -o 'next="[^"]*"' ))" \
                                                        || no "for: the r=1 row has no next= — $( printf '%s' "$top" | cut -c1-160 )"
others="$( grep -o '<d [^>]*next=' "$TMP/for" | grep -vc 'r="1"' || true )"
if [ "$others" = 0 ]; then ok "for: next= rides the top row only"; else no "for: $others non-top row(s) carry next="; fi
checkNext "for top row" "$TMP/for" '^(--expand=[^ ]+:[A-Za-z_]+|--for=.* --limit=40)$' row

echo "=== (8) well-formed + deterministic with the attribute in place ==="
if command -v xmllint >/dev/null 2>&1; then
    for f in ec1 ec2 im ca ce qd tg ft g1 g2 g4 for; do xmllint --noout "$TMP/$f" >/dev/null 2>&1 || no "$f is malformed XML with next= in place"; done
    ok "the twelve documents are well-formed"
fi
if rrun --grep=distance >"$TMP/g1b"; cmp -s "$TMP/g1" "$TMP/g1b"; then ok "grep next= is deterministic"; else no "grep next= differs between runs"; fi

echo "=== (N) --help-task: a --for-shaped recommendation carries the WIDENING page as its next= ==="
# 2026-09-13: the router's recommendation is a next=-carrying document like any other, and it was outside
# this population — so nothing checked that the follow-up it hands an agent parses, runs, or fits the
# ceiling. It is spelled by forpage.h's forWidenNext, the same function the --for ANSWER's own next= uses.
rrun --help-task='find the code responsible for the area rounding bug' >"$TMP/ht"
grep -q 'intent="locate-task"' "$TMP/ht" \
    && checkNext "help-task locate" "$TMP/ht" '^--for=.* --limit=40$' "row" \
    || no "fixture: --help-task did not route to locate-task ($( grep -o 'intent="[^"]*"' "$TMP/ht" | head -1 ))"
# present-only: a recommendation that is not a --for bundle carries none at all
rrun --help-task='where is the rot in code I did not write' >"$TMP/ht2"
if [ -z "$( nexts "$TMP/ht2" )" ]; then ok "help-task non---for recommendation carries no next="
else no "help-task non---for recommendation carries a next=: $( nexts "$TMP/ht2" )"; fi

echo '=== (9) next= quoting: a tilde is shell-special only WORD-INITIALLY, and the attribute is XML ==='
# CodeRabbit on #212 (review 5192382995), against the captured showcase: the scoped block's next= read
#     next="--rank-by=churn-decay --since=&apos;HEAD~1&apos; …"
# nextFlag quoted HEAD~1 because the value contains `~`, and then the XML escaper turned the single quotes
# into &apos; — which a reader pasting the raw text out of a Markdown capture does not decode. The attribute
# exists to be pasted, so that is the whole of its job lost, on the most ordinary git revision spelling there
# is. Tilde expansion is defined for a WORD-INITIAL `~` (and the ~user form) and for nothing else, so HEAD~1
# was never special and never needed the quotes.
#
# THE TWO ROWS ARE EACH OTHER'S CONTROL, which is why neither needs a planted mutation: a rule that quoted
# nothing would red the ~tmp row, and a rule that quoted everything (the defect) reds the HEAD~1 row. Only the
# position-aware rule passes both.
QREPO="$TMP/qrepo"; mkdir -p "$QREPO/sub"
( cd "$QREPO" && git init -q && git config user.email "t@example.com" && git config user.name "t" \
  && printf 'int qa(){return 1;}\n' > sub/a.cpp && printf 'int qb(){return 2;}\n' > sub/b.cpp \
  && git add -A && git commit -q -m one \
  && printf 'int qa(){return 11;}\n' > sub/a.cpp && printf 'int qb(){return 22;}\n' > sub/b.cpp \
  && git add -A && git commit -q -m two ) || { echo "(9) qrepo setup failed"; exit 2; }

qnext(){ "$BIN" "$QREPO" --rank-by=churn-decay --since="HEAD~1" --in=sub --limit=1 "$@" 2>/dev/null \
         | grep -o '<recent scope="sub"[^>]*>' | head -1 | grep -o 'next="[^"]*"' | head -1; }

q1="$( qnext )"
if [ -z "$q1" ]; then no "(9) the scoped block carried no next= at all — the fixture stopped capping, so neither row below is evidence"
else
    case "$q1" in
        *"--since=HEAD~1"*) ok "(9) a non-word-initial ~ is NOT quoted: next= carries --since=HEAD~1 bare, so it pastes from raw Markdown" ;;
        *)                  no "(9) next= does not carry a bare --since=HEAD~1: $q1" ;;
    esac
    case "$q1" in
        *"&apos;"*) no "(9) next= still carries &apos; — the value was quoted and the XML escaper turned the quotes into entities no shell decodes: $q1" ;;
        *)          ok "(9) next= carries no &apos; entity — nothing in this invocation needed quoting" ;;
    esac
fi

# THE RULE, because this arm used to assert the opposite and explain it wrongly: tilde expansion applies to a
# word whose FIRST character is `~`. In `--exclude=~tmp` the word begins with `--exclude=`, so no shell expands
# it — an argument is not an assignment. Measured on this machine: `sh -c 'p ~root'` -> /var/root, while
# `sh -c 'p --exclude=~root'` -> the literal `--exclude=~root` (sh, bash and zsh alike). The gate previously
# pinned `--exclude=&apos;~tmp&apos;` and called the quotes "the correct answer here", which would have
# defended the corrupted argument against anyone who fixed it.
q2="$( qnext --exclude='~tmp' )"
if [ -z "$q2" ]; then no "(9) the --exclude arm produced no next= — the tilde row below proves nothing"
else
    case "$q2" in
        *"--exclude=~tmp"*) ok "(9) a ~ after --flag= is NOT quoted: next= carries --exclude=~tmp bare, which is what a shell passes through" ;;
        *)                  no "(9) next= does not carry a bare --exclude=~tmp — the value was quoted for an expansion no shell performs: $q2" ;;
    esac
    case "$q2" in
        *"&apos;"*) no "(9) next= still carries &apos; — quoting a value no shell would expand, and the XML escaper then made it an entity no shell decodes: $q2" ;;
        *)          ok "(9) the --exclude=~tmp invocation carries no &apos; entity at all" ;;
    esac
fi

# MUTATION CONTROL for the row above: narrowing the tilde case must not have disabled quoting generally. A
# value with a space still needs it, and still gets it.
q3="$( qnext --exclude='a b' )"
if [ -z "$q3" ]; then no "(9) the space-value arm produced no next= — the control below proves nothing"
else
    case "$q3" in
        *"--exclude=&apos;a b&apos;"*) ok "(9) control: a value a shell WOULD split is still quoted (--exclude=&apos;a b&apos;), so only the tilde case narrowed" ;;
        *)                             no "(9) control: a space-bearing value lost its quoting — the fix disabled quoting instead of narrowing it: $q3" ;;
    esac
fi

[ "$fail" -eq 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
