#!/usr/bin/env bash
# forverbroutecheck.sh — a --for question that NAMES its symbol and ASKS a call-graph question is answered by that verb,
# ROUTED: the route is disclosed as the verb root's first child, and the first --for page rides along whenever the
# evidence says the verb may be partial.
#
#   test/forverbroutecheck.sh [BIN]     # BIN defaults to $RIPWIRE_BIN, then build/ripwire; BASE_BIN= adds the base arms
#
# Lane RT1 (results/RT1_ROUTE_1118), revised by lane RT2 (results/RT2_ROUTE_1118). The rule is frozen in src/forroute.h
# (rule E2: the symbol, rule R2: the kind — RT2's rules2.py, transcribed) and src/partialwarn.h (lane W1's frozen F1 plus RT2's
# W2 clauses). A text gap is FOLDED into the answer as <text_only> rows; the first --for page rides along only when a reason a
# fold cannot answer remains (warn="1"). The route fires only on a BARE
# `--for=Q` (no flag that shapes the --for answer); --no-verb-route is the opt-out and is the unrouted answer byte for byte.
# Not to be confused with test/forroutecheck.sh (FOR-ROUTE-DECLINED: the <graph_verb> block APPENDED inside a --for answer).
#
# Arm classes: [P] positive — RED on the base binary (lane/af1-answerfirst + lane/v1-verbdef, which has no route): that is
# the control; [N] the route must NOT fire — the answer is the unrouted --for byte for byte; [C] holds on every binary.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
BASE="${BASE_BIN:-}"
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
fail=0
# every verdict is an if/else: a failed write of a PASS line must never print FAIL for an arm that passed (gateexitcheck G2)
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
say(){ if [ "$1" = 0 ]; then ok "$2"; else no "$3"; fi; }

echo "forverbroutecheck: BIN=$BIN${BASE:+ BASE_BIN=$BASE}"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }

# ── the corpus, written here (no file of this tree is read as a fixture) ─────────────────────────────────────────────
# plain/  lib.h declares compute_total(), lib.c defines it, main.c's run_main() calls it, outer.c's outer_entry() calls
#         run_main(). Nothing names compute_total outside a call or a definition: no evidence of a miss.
# hop/    cb.c: handle_failure() calls report_error() and is REGISTERED as a value (a struct initializer), so the call
#         graph cannot see who reaches report_error through it — a callback hop (W1's value-hop).
# gap/    plain/'s lib.h, lib.c, main.c plus names.c, which names compute_total in a string no verb row lists (W1's text-gap).
mkdir -p "$DIR/plain" "$DIR/hop" "$DIR/gap"
cat >"$DIR/plain/lib.h" <<'C'
int compute_total( int a );
C
cat >"$DIR/plain/lib.c" <<'C'
#include "lib.h"
int compute_total( int a )
{
    return a + 1;
}
C
cat >"$DIR/plain/main.c" <<'C'
#include "lib.h"
int run_main( void )
{
    return compute_total( 2 );
}
C
cat >"$DIR/plain/outer.c" <<'C'
int run_main( void );
int outer_entry( void )
{
    return run_main();
}
C
cat >"$DIR/hop/cb.c" <<'C'
struct ops
{
    void ( *on_err )( int );
};
void report_error( int code )
{
    ( void )code;
}
static void handle_failure( int code )
{
    report_error( code );
}
static struct ops table = { handle_failure };
void dispatch( int c )
{
    table.on_err( c );
}
C
cp "$DIR/plain/lib.h" "$DIR/plain/lib.c" "$DIR/plain/main.c" "$DIR/gap/"
cat >"$DIR/gap/names.c" <<'C'
const char* kTotalName = "compute_total";
C

run(){ local tag="$1" fx="$2"; shift 2; "$BIN" "$DIR/$fx" "$@" >"$DIR/$tag.out" 2>"$DIR/$tag.err"; }
runb(){ local tag="$1" fx="$2"; shift 2; "$BASE" "$DIR/$fx" "$@" >"$DIR/$tag.out" 2>"$DIR/$tag.err"; }
# the root open tag of an answer: the first element that is not inside a comment
rootOpen(){ python3 -c 'import re,sys; d=re.sub(r"<!--.*?-->","",open(sys.argv[1]).read(),flags=re.S); m=re.search(r"<[A-Za-z][^>]*>",d); print(m.group(0) if m else "")' "$1"; }
# the first child element after the root open tag
firstChild(){ python3 -c 'import re,sys; d=re.sub(r"<!--.*?-->","",open(sys.argv[1]).read(),flags=re.S); m=re.search(r"<[A-Za-z][^>]*>",d); n=re.search(r"<[A-Za-z][^>]*>",d[m.end():]) if m else None; print(n.group(0) if n else "")' "$1"; }
# everything from the root open tag on (the leading legend comments dropped), and the leading legend itself
fromRoot(){ python3 -c 'import sys; d=open(sys.argv[1]).read(); i=0
while d.startswith("<!--",i): i=d.index("-->",i)+3
sys.stdout.write(d[i:])' "$1"; }
legendOf(){ python3 -c 'import sys; d=open(sys.argv[1]).read(); i=0
while d.startswith("<!--",i): i=d.index("-->",i)+3
sys.stdout.write(d[:i])' "$1"; }
attr(){ python3 -c 'import re,sys; m=re.search(r"(?<![\w])"+sys.argv[2]+r"=\"([^\"]*)\"",sys.argv[1]); print(m.group(1) if m else "")' "$1" "$2"; }

Q_WHO='Who calls `compute_total`?'
Q_IMP='Trace the transitive callers of `compute_total`.'
Q_HOP='Trace the transitive callers of `report_error`, including callback registrations.'
Q_GAP='Which files are affected if `compute_total` changes?'
Q_NONE='How does the total get computed?'
Q_MISS='Who calls `missing_symbol_xyz`?'
Q_PLAINWORD='Who calls `compute`?'
Q_LAST='Compare `run_main` with `compute_total`: who calls it?'
Q_ORDER='Which files call `compute_total` transitively?'

# ── (1) [P] who-calls: routed to --callers, disclosed first, no warning on a plain fixture ───────────────────────────
if run a1 plain --for="$Q_WHO"; then
    R="$( rootOpen "$DIR/a1.out" )"; F="$( firstChild "$DIR/a1.out" )"
    case "$R" in "<callers "*) ok "(1) [P] who-calls answers with the --callers root" ;; *) no "(1) [P] who-calls root is '${R:0:120}'" ;; esac
    case "$F" in "<route "*) ok "(1) [P] <route> is the root's FIRST child" ;; *) no "(1) [P] first child is '${F:0:160}'" ;; esac
    [ "$( attr "$F" from )" = for ] && [ "$( attr "$F" kind )" = who-calls ] && [ "$( attr "$F" verb )" = "--callers=compute_total" ] \
        && [ "$( attr "$F" complete )" = not-proven ]
    say $? "(1) [P] route from=for kind=who-calls verb=--callers=compute_total complete=not-proven" "(1) [P] route reads '$F'"
    printf '%s' "$( attr "$F" task )" | grep -qF 'Who calls `compute_total`?'
    say $? "(1) [P] task= echoes the question" "(1) [P] task= is '$( attr "$F" task )'"
    if printf '%s' "$F" | grep -q ' warn='; then no "(1) [P] a plain who-calls answer warns: '$F'"; else ok "(1) [P] no warn= on a plain fixture (the target's callers are no floor)"; fi
    if grep -q '<ctx task=' "$DIR/a1.out"; then no "(1) [P] an unwarned routed answer carries a --for page"; else ok "(1) [P] unwarned: no --for page carried"; fi
    python3 -c 'import re,sys; d=re.sub(r"<!--.*?-->","",open(sys.argv[1]).read(),flags=re.S); r=d.find("<route "); e=d.find("<def "); sys.exit(0 if 0<=r<e else 1)' "$DIR/a1.out"
    say $? "(1) [P] <route> sits before V1's <def> rows" "(1) [P] <route> is not ahead of the <def> rows"
else
    no "(1) [P] --for='$Q_WHO' exited non-zero: $( head -c 300 "$DIR/a1.err" )"
fi

# ── (2) [P] the routed answer IS the verb's answer: minus <route> and the legend it is --callers byte for byte ───────
if run a2 plain --callers=compute_total; then
    A="$( fromRoot "$DIR/a1.out" | python3 -c 'import re,sys; sys.stdout.write(re.sub(r"<route [^>]*/>","",sys.stdin.read(),count=1))' )"
    B="$( fromRoot "$DIR/a2.out" )"
    [ -n "$B" ] && grep -q '<route ' "$DIR/a1.out" && [ "$A" = "$B" ]
    say $? "(2) [P] routed body minus <route> == --callers=compute_total body (byte for byte)" "(2) [P] routed body differs from --callers: '${A:0:200}' vs '${B:0:200}'"
    LA="$( legendOf "$DIR/a1.out" )"; LB="$( legendOf "$DIR/a2.out" )"
    if printf '%s' "$LA" | grep -q 'route from=for' && ! printf '%s' "$LB" | grep -q 'route from=for'; then
        ok "(2) [P] the routed legend defines route from=, the plain --callers legend does not (present-only)"
    else
        no "(2) [P] route reading: routed='${LA:0:160}…'"
    fi
fi

# ── (3) [P] transitive kind on a plain chain: --impact, no warn ─────────────────────────────────────────────────────
if run a3 plain --for="$Q_IMP"; then
    F="$( firstChild "$DIR/a3.out" )"
    case "$( rootOpen "$DIR/a3.out" )" in "<impact "*) ok "(3) [P] transitive answers with the --impact root" ;; *) no "(3) [P] root is '$( rootOpen "$DIR/a3.out" | head -c 120 )'" ;; esac
    [ "$( attr "$F" kind )" = transitive ] && [ "$( attr "$F" verb )" = "--impact=compute_total" ]
    say $? "(3) [P] route kind=transitive verb=--impact=compute_total" "(3) [P] route reads '$F'"
    if printf '%s' "$F" | grep -q ' warn='; then no "(3) [P] warn on a plain chain (a false alarm): '$F'"; else ok "(3) [P] warn absent on a plain chain"; fi
    if grep -q '<ctx task=' "$DIR/a3.out"; then no "(3) [P] a --for page carried without a warning"; else ok "(3) [P] no --for page carried"; fi
fi

# ── (4) [P] a callback hop warns (value-hop) and carries the first --for page ───────────────────────────────────────
if run a4 hop --for="$Q_HOP"; then
    F="$( firstChild "$DIR/a4.out" )"
    [ "$( attr "$F" warn )" = 1 ] && [ "$( attr "$F" why )" = "value-hop:1:handle_failure" ] && [ "$( attr "$F" page1 )" = 1 ]
    say $? "(4) [P] callback hop: warn=1 why=value-hop:1:handle_failure page1=1" "(4) [P] route reads '$F'"
    if run a4o hop --for="$Q_HOP" --no-verb-route; then
        python3 -c '
import sys
d, o = open(sys.argv[1]).read(), open(sys.argv[2]).read()
i = d.find("<ctx task=")
j = d.rfind("</ctx>")
sys.exit(0 if i > 0 and j > i and d[i:j + 6] == o.rstrip("\n") and d.rstrip("\n").endswith("</ctx></impact>") else 1)' "$DIR/a4.out" "$DIR/a4o.out"
        say $? "(4) [P] the carried <ctx> is the opted-out --for answer byte for byte, the impact root's last child" "(4) [P] the carried page is not the --no-verb-route answer"
    fi
fi

# ── (5) [P] RT2: a file naming the symbol that no row lists is FOLDED as a <text_only> row; no warn, no page ────────
if run a5 gap --for="$Q_GAP"; then
    F="$( firstChild "$DIR/a5.out" )"
    [ "$( attr "$F" kind )" = direct-radius ] && [ "$( attr "$F" verb )" = "--uses=compute_total" ] && [ -z "$( attr "$F" warn )" ] \
        && ! grep -q '<ctx task=' "$DIR/a5.out"
    say $? "(5) [P] text gap: kind=direct-radius verb=--uses, no warn=, no page carried" "(5) [P] route reads '$F'"
    python3 -c 'import re,sys; d=re.sub(r"<!--.*?-->","",open(sys.argv[1]).read(),flags=re.S); sys.exit(0 if re.search(r"<route [^>]*/><text_only n=\"1\"><tx p=\"names\.c:1\"/></text_only>",d) else 1)' "$DIR/a5.out"
    say $? "(5) [P] <text_only n=1><tx p=names.c:1/></text_only> follows <route> directly" "(5) [P] no fold row right after <route>"
fi

# ── (6) [N] no symbol named: the answer is the unrouted --for byte for byte ─────────────────────────────────────────
if run a6 plain --for="$Q_NONE" && run a6o plain --for="$Q_NONE" --no-verb-route; then
    cmp -s "$DIR/a6.out" "$DIR/a6o.out" && ! grep -q '<route ' "$DIR/a6.out"
    say $? "(6) [N] no named symbol: --for == --for --no-verb-route, no <route>" "(6) [N] an unrouted question changed bytes"
else
    no "(6) [N] a run exited non-zero: $( head -c 200 "$DIR/a6o.err" )"
fi

# ── (7) [N] the opt-out: no <route>, and it is AF1's default page (the --page-bytes=12000 spelling) ─────────────────
if run a7 plain --for="$Q_WHO" --no-verb-route && run a7p plain --for="$Q_WHO" --page-bytes=12000; then
    case "$( rootOpen "$DIR/a7.out" )" in "<ctx "*) ok "(7) [N] --no-verb-route answers the --for <ctx>" ;; *) no "(7) [N] opt-out root is not <ctx>" ;; esac
    cmp -s "$DIR/a7.out" "$DIR/a7p.out" && ! grep -q '<route ' "$DIR/a7.out"
    say $? "(7) [N] --no-verb-route == --page-bytes=12000 (a spelled page never routes), no <route>" "(7) [N] the opt-out differs from the paged --for"
else
    no "(7) [N] a run exited non-zero: $( head -c 200 "$DIR/a7.err" )"
fi

# ── (8) [N] a named symbol no verb resolves (either spelling): not routed ───────────────────────────────────────────
if run a8 plain --for="$Q_MISS" && run a8o plain --for="$Q_MISS" --no-verb-route; then
    cmp -s "$DIR/a8.out" "$DIR/a8o.out"
    say $? "(8) [N] an unresolved symbol is not routed (the --for answer, byte for byte)" "(8) [N] an unresolved symbol changed the answer"
else
    no "(8) [N] a run exited non-zero: $( head -c 200 "$DIR/a8o.err" )"
fi

# ── (9) rule E and rule R, as frozen ────────────────────────────────────────────────────────────────────────────────
if run a9 plain --for="$Q_PLAINWORD" && run a9o plain --for="$Q_PLAINWORD" --no-verb-route; then
    cmp -s "$DIR/a9.out" "$DIR/a9o.out"
    say $? "(9) [N] rule E2: a backticked plain word no verb resolves (\`compute\`) is not routed" "(9) [N] an unresolved plain word was routed"
else
    no "(9) [N] a run exited non-zero: $( head -c 200 "$DIR/a9o.err" )"
fi
if run a9l plain --for="$Q_LAST"; then
    [ "$( attr "$( firstChild "$DIR/a9l.out" )" verb )" = "--callers=compute_total" ]
    say $? "(9) [P] rule E: the LAST code-shaped span is the symbol" "(9) [P] '$( firstChild "$DIR/a9l.out" )'"
fi
if run a9r plain --for="$Q_ORDER"; then
    [ "$( attr "$( firstChild "$DIR/a9r.out" )" kind )" = transitive ]
    say $? "(9) [P] rule R: first match wins — 'call … transitively' is transitive, not who-calls" "(9) [P] '$( firstChild "$DIR/a9r.out" )'"
fi

# ── (10) [P] next= replays the full --for answer ────────────────────────────────────────────────────────────────────
NEXT="$( attr "$( firstChild "$DIR/a1.out" )" next | python3 -c 'import html,sys; sys.stdout.write(html.unescape(sys.stdin.read().strip()))' )"
case "$NEXT" in
    *--no-verb-route*)
        eval "\"\$BIN\" \"\$DIR/plain\" $NEXT" >"$DIR/a10.out" 2>/dev/null
        cmp -s "$DIR/a10.out" "$DIR/a7.out"
        say $? "(10) [P] route next= ($NEXT) is the opted-out --for answer" "(10) [P] next= replay differs" ;;
    *) no "(10) [P] route next= does not name the opt-out: '$NEXT'" ;;
esac

# ── (11) [P] the legend defines every attribute the route carries ───────────────────────────────────────────────────
LG="$( legendOf "$DIR/a4.out" )"
miss=""
for a in from kind verb task complete next warn why page1; do printf '%s' "$LG" | grep -q "$a=" || miss="$miss $a"; done
grep -q '<route ' "$DIR/a4.out" && [ -z "$miss" ] && [ -n "$LG" ]
say $? "(11) [P] the leading legend defines from= kind= verb= task= complete= next= warn= why= page1=" "(11) [P] no route, or undefined in the legend:$miss"

# ── (12) [N] a flag that shapes the --for answer never routes ────────────────────────────────────────────────────────
if run a12 plain --for="$Q_WHO" --page-bytes=0 && run a12j plain --for="$Q_WHO" --json; then
    ! grep -q '<route ' "$DIR/a12.out" && ! grep -q '"kind": *"who-calls"' "$DIR/a12j.out" && ! grep -q '<route ' "$DIR/a12j.out"
    say $? "(12) [N] --page-bytes=0 and --json: not routed" "(12) [N] a shaped --for was routed"
fi

# ── (13) [C] determinism and well-formedness ────────────────────────────────────────────────────────────────────────
for t in a4 a5 a1; do
    case "$t" in a4) fx=hop q="$Q_HOP" ;; a5) fx=gap q="$Q_GAP" ;; *) fx=plain q="$Q_WHO" ;; esac
    run "${t}d" "$fx" --for="$q"
    cmp -s "$DIR/$t.out" "$DIR/${t}d.out"
    say $? "(13) [C] two runs of $t are byte-identical" "(13) [C] two runs of $t differ"
done
if command -v xmllint >/dev/null 2>&1; then
    for t in a1 a3 a4 a5; do
        [ -s "$DIR/$t.out" ] && xmllint --noout "$DIR/$t.out" 2>/dev/null
        say $? "(13) [C] $t is one well-formed XML document" "(13) [C] $t is not well-formed XML"
    done
else
    ok "(13) [C] xmllint not installed: well-formedness not checked here"
fi

# ── (14) [N] against the base binary (BASE_BIN=): an unrouted --for and the opt-out are today's --for ────────────────
if [ -n "$BASE" ] && [ -x "$BASE" ]; then
    runb b6 plain --for="$Q_NONE"; cmp -s "$DIR/a6.out" "$DIR/b6.out"
    say $? "(14) [N] unrouted question: byte-identical to the base binary's --for" "(14) [N] unrouted question differs from base"
    runb b7 plain --for="$Q_WHO"; cmp -s "$DIR/a7.out" "$DIR/b7.out"
    say $? "(14) [N] --no-verb-route: byte-identical to the base binary's --for" "(14) [N] the opt-out differs from base"
    runb b4 hop --for="$Q_HOP"; cmp -s "$DIR/a4o.out" "$DIR/b4.out"
    say $? "(14) [N] hop fixture --no-verb-route: byte-identical to the base binary's --for" "(14) [N] hop opt-out differs from base"
else
    ok "(14) [N] BASE_BIN not set: the base-identity arms are run by the lane (results/RT1_ROUTE_1118/gates), not here"
fi

# ── RT2 arms (15–21): rule E2/R2, the fold, and the W2 clauses ──────────────────────────────────────────────────────
mkdir -p "$DIR/word" "$DIR/gap2" "$DIR/gap2/tests" "$DIR/mac" "$DIR/many"
cat >"$DIR/word/w.c" <<'C'
int widget( void )
{
    return 1;
}
int caller_w( void )
{
    return widget();
}
C
cp "$DIR/gap/lib.h" "$DIR/gap/lib.c" "$DIR/gap/main.c" "$DIR/gap/names.c" "$DIR/gap2/"
printf 'compute_total adds one.\n' >"$DIR/gap2/README.md"
printf 'const char* kT = "compute_total";\n' >"$DIR/gap2/tests/t.c"
cp "$DIR/plain/lib.c" "$DIR/mac/"
cat >"$DIR/mac/lib.h" <<'C'
int compute_total( int a );
#define TOTAL( x ) compute_total( x )
C
for f in a b; do printf '#include "lib.h"\nint use_%s( void )\n{\n    return TOTAL( 1 );\n}\n' "$f" >"$DIR/mac/$f.c"; done
cp "$DIR/plain/lib.h" "$DIR/plain/lib.c" "$DIR/plain/main.c" "$DIR/many/"
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17; do printf 'const char* kName%s = "compute_total";\n' "$i" >"$DIR/many/n$i.c"; done

# (15) [P] where-used → --uses
if run a15 plain --for='Where is `compute_total` used?'; then
    F="$( firstChild "$DIR/a15.out" )"
    [ "$( attr "$F" kind )" = where-used ] && [ "$( attr "$F" verb )" = "--uses=compute_total" ] && [ -z "$( attr "$F" warn )" ]
    say $? "(15) [P] rule R2: 'where is … used' is kind=where-used, verb=--uses, no warn on a plain fixture" "(15) [P] route reads '$F'"
fi
# (15b) [N] "used by" is passive: it names the user, not a where-used question — not routed
if run a15b plain --for='Change the signature of `compute_total` used by `run_main`.' && run a15bo plain --for='Change the signature of `compute_total` used by `run_main`.' --no-verb-route; then
    cmp -s "$DIR/a15b.out" "$DIR/a15bo.out"
    say $? "(15b) [N] rule R2: 'used by' is not a where-used cue (the --for answer, byte for byte)" "(15b) [N] 'used by' was routed: '$( firstChild "$DIR/a15b.out" )'"
fi
# (16) [P] rule E2 tier 2: a backticked plain word the verb resolves is routed; a code-shaped span still wins
if run a16 word --for='Who calls `widget`?'; then
    [ "$( attr "$( firstChild "$DIR/a16.out" )" verb )" = "--callers=widget" ]
    say $? "(16) [P] rule E2: a plain word (\`widget\`) the verb resolves is routed" "(16) [P] '$( firstChild "$DIR/a16.out" )'"
fi
if run a16b word --for='Who calls `caller_w` and `widget`?'; then
    [ "$( attr "$( firstChild "$DIR/a16b.out" )" verb )" = "--callers=caller_w" ]
    say $? "(16) [P] rule E2: the last CODE-SHAPED span outranks a later plain word" "(16) [P] '$( firstChild "$DIR/a16b.out" )'"
fi
# (17) [P] rule E2: a trailing () or ! is not part of the symbol
if run a17 plain --for='Who calls `compute_total()`?' && run a17b plain --for='Where is `compute_total!` used?'; then
    [ "$( attr "$( firstChild "$DIR/a17.out" )" verb )" = "--callers=compute_total" ] && [ "$( attr "$( firstChild "$DIR/a17b.out" )" verb )" = "--uses=compute_total" ]
    say $? "(17) [P] rule E2: \`compute_total()\` and \`compute_total!\` route as compute_total" "(17) [P] '$( firstChild "$DIR/a17.out" )' / '$( firstChild "$DIR/a17b.out" )'"
fi
# (18) [P] the fold skips prose documents and test paths
if run a18 gap2 --for="$Q_GAP"; then
    python3 -c 'import re,sys; d=re.sub(r"<!--.*?-->","",open(sys.argv[1]).read(),flags=re.S); m=re.search(r"<text_only [^>]*>(.*?)</text_only>",d); sys.exit(0 if m and re.findall(r"<tx p=\"([^\"]+)\"/>",m.group(1))==["names.c:1"] and "README" not in d and "tests/t.c" not in d else 1)' "$DIR/a18.out"
    say $? "(18) [P] fold rows: names.c only — README.md (prose) and tests/t.c (a test path) are not folded" "(18) [P] fold reads '$( grep -o '<text_only.*</text_only>' "$DIR/a18.out" | head -c 300 )'"
fi
# (19) [P] a caller row that is a function-like macro: warn=1 why=macro-row:TOTAL and the page rides along
if run a19 mac --for='Who calls `compute_total`?'; then
    F="$( firstChild "$DIR/a19.out" )"
    [ "$( attr "$F" warn )" = 1 ] && printf '%s' "$( attr "$F" why )" | grep -q 'macro-row:TOTAL' && [ "$( attr "$F" page1 )" = 1 ] && grep -q '<ctx task=' "$DIR/a19.out"
    say $? "(19) [P] macro caller row: warn=1 why=…macro-row:TOTAL…, page1=1, page carried" "(19) [P] route reads '$F'"
fi
# (20) [P] target-floor on --uses for a who-calls / where-used question only
if run a20 hop --for='Where is `handle_failure` used?' && run a20b hop --for='Which files are affected if `handle_failure` changes?'; then
    F="$( firstChild "$DIR/a20.out" )"; G="$( firstChild "$DIR/a20b.out" )"
    [ "$( attr "$F" verb )" = "--uses=handle_failure" ] && [ "$( attr "$F" warn )" = 1 ] && printf '%s' "$( attr "$F" why )" | grep -q 'target-floor' \
        && [ "$( attr "$G" verb )" = "--uses=handle_failure" ] && ! printf '%s' "$( attr "$G" why )" | grep -q 'target-floor'
    say $? "(20) [P] where-used on a value-registered function warns target-floor; the direct-radius question does not" "(20) [P] '$F' / '$G'"
fi
# (21) [P] more than 16 text-only files: 16 rows, capped=1, warn=1 why=…text-gap-capped:17…, page carried
if run a21 many --for="$Q_GAP"; then
    F="$( firstChild "$DIR/a21.out" )"
    python3 -c 'import re,sys; d=re.sub(r"<!--.*?-->","",open(sys.argv[1]).read(),flags=re.S); m=re.search(r"<text_only n=\"17\" capped=\"1\">(.*?)</text_only>",d); sys.exit(0 if m and len(re.findall(r"<tx p=",m.group(1)))==16 else 1)' "$DIR/a21.out" \
        && [ "$( attr "$F" warn )" = 1 ] && printf '%s' "$( attr "$F" why )" | grep -q 'text-gap-capped:17' && grep -q '<ctx task=' "$DIR/a21.out"
    say $? "(21) [P] fold cap: 16 of 17 rows, capped=1, warn=1 why=text-gap-capped:17, page carried" "(21) [P] route reads '$F'"
fi
for t in a15 a18 a19 a20 a21; do
    if command -v xmllint >/dev/null 2>&1 && [ -s "$DIR/$t.out" ]; then
        xmllint --noout "$DIR/$t.out" 2>/dev/null
        say $? "(21) [C] $t is one well-formed XML document" "(21) [C] $t is not well-formed XML"
    fi
done
LG="$( legendOf "$DIR/a21.out" )"
printf '%s' "$LG" | grep -q 'text_only n=' && ! printf '%s' "$( legendOf "$DIR/a1.out" )" | grep -q 'text_only n='
say $? "(21) [P] the legend defines <text_only n= capped=> / <tx p=> when a fold is printed (present-only)" "(21) [P] text_only undefined in the legend"

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAILURES ABOVE"; fi
exit "$fail"
