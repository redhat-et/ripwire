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
# `--for=Q` (no flag that shapes the --for answer); --no-verb-route is the opt-out and is the unrouted answer byte for byte,
# EXCEPT for the key group's position — see arm (4) and OWNER RULING 109 below.
# Not to be confused with test/forroutecheck.sh (FOR-ROUTE-DECLINED: the <graph_verb> block APPENDED inside a --for answer).
#
# OWNER RULING 109 (2026-11-20), arm (4) and the new arm (4k). Arm (4) used to require the carried <ctx> page to equal the
# --no-verb-route answer BYTE FOR BYTE. That is unsatisfiable once KB1's key group is non-empty on a carried page, because
# forkeybodycheck (K11) requires the carried page's key block to MOVE UP to the routed root: the standalone answer therefore
# holds the block inside it and the carried page does not. The two bars never collided before owner ruling 87, because the
# body was already served on page 1 and the key group was suppressed to nothing, so there was no block to move (measured:
# results/K87_CONTRACT_1120/READOUT.md §6.1). Ruling 109 re-registers the comparison in the style forkeybodycheck's (K1n),
# (K3n) and (K4) already use for exactly this reason — "ON minus the key group == the twin" — and pairs it with (4k), which
# pins that the moved block is byte-identical to the one the standalone answer carried. Net effect on strictness: every row
# is still compared byte for byte AND the block's survival across the move is now pinned, where before it was only ever
# compared while it was empty. Looser on exactly one thing: the group's POSITION, which (K11) deliberately changes.
# Changing (K11) instead was on the table and was declined — that is a KB1 design question, not a ruling-87 one.
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

# ── (2) [P] the routed answer IS the verb's answer: minus <route>, KB1's <bodies of="key"> (src/forkeybody.h; forkeybodycheck
# pins it) and the legend it is --callers byte for byte ───────
if run a2 plain --callers=compute_total; then
    A="$( fromRoot "$DIR/a1.out" | python3 -c 'import re,sys; d=re.sub(r"<route [^>]*/>","",sys.stdin.read(),count=1); sys.stdout.write(re.sub(r"<bodies of=\"key\"[^>]*>.*?</bodies>","",d,count=1,flags=re.S))' )"
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
        # RULING 109: "ON minus the key group == the twin". Every row still byte-compared; only the group is set aside.
        python3 - "$DIR/a4.out" "$DIR/a4o.out" <<'X'
import re, sys
KEY = re.compile(r'<bodies of="key"[^>]*>.*?</bodies>', re.S)
LEG = re.compile(r'<!-- bodies of=key:.*?-->', re.S)
d, o = open(sys.argv[1]).read(), open(sys.argv[2]).read().rstrip("\n")
i, j = d.find("<ctx task="), d.rfind("</ctx>")
nokey = lambda s: LEG.sub("", KEY.sub("", s, count=1), count=1)
sys.exit(0 if i > 0 and j > i and d[i:j + 6] == nokey(o) and d.rstrip("\n").endswith("</ctx></impact>") else 1)
X
        say $? "(4) [P] the carried <ctx> is the opted-out --for answer MINUS its key group, byte for byte, the impact root's last child" \
                "(4) [P] the carried page is not the --no-verb-route answer minus its key group"
        # A RELAXED comparison cannot be proved red on the unfixed binary -- that binary satisfied the STRICTER bar it
        # replaces -- so its non-vacuity proof is a mutation, exactly as (K1n)/(K3n) prove theirs. (4k) below is the arm
        # that carries ruling 109's red-on-the-unfixed-binary proof.
        python3 - "$DIR/a4.out" "$DIR/a4o.out" <<'X'
import re, sys
KEY = re.compile(r'<bodies of="key"[^>]*>.*?</bodies>', re.S)
LEG = re.compile(r'<!-- bodies of=key:.*?-->', re.S)
d, o = open(sys.argv[1]).read(), open(sys.argv[2]).read().rstrip("\n")
i, j = d.find("<ctx task="), d.rfind("</ctx>")
nokey = lambda s: LEG.sub("", KEY.sub("", s, count=1), count=1)
sys.exit(0 if i > 0 and j > i and d[i:j + 6] != nokey(o)[:-1] else 1)
X
        say $? "(4) [P] negative control: the same comparison fails when one byte is dropped" \
                "(4) [P] the comparison accepts a mutated answer -- it is vacuous"
        # (4k) RULING 109's new arm: the block MOVED to the root, it did not vanish or change. Non-vacuity FIRST --
        # the standalone answer must really carry a key group, or there is no move to pin and this arm says so.
        python3 - "$DIR/a4.out" "$DIR/a4o.out" <<'X'
import re, sys
KEY = re.compile(r'<bodies of="key"[^>]*>.*?</bodies>', re.S)
d, o = open(sys.argv[1]).read(), open(sys.argv[2]).read()
i, j = d.find("<ctx task="), d.rfind("</ctx>")
carried = d[i:j + 6] if i > 0 and j > i else ""
kd, ko = KEY.findall(d), KEY.findall(o)
if len(ko) != 1:
    sys.stderr.write("vacuous: the --no-verb-route answer carries %d key groups, expected 1\n" % len(ko))
    sys.exit(1)
sys.exit(0 if len(kd) == 1 and KEY.search(carried) is None and kd[0] == ko[0] else 1)
X
        say $? "(4k) [P] KB1's key block moved, it did not vanish: ONE block in the routed answer, OUTSIDE the carried page, byte-identical to the one the --no-verb-route answer carries" \
                "(4k) [P] the moved key block is missing, duplicated, inside the carried page, or not byte-identical to the standalone answer's (or the standalone answer carries none, which makes the arm vacuous)"
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
    # RT2 ES: an unrouted page 1 may END EARLY (early="proven", arms 22–25); a spelled page never does
    { cmp -s "$DIR/a7.out" "$DIR/a7p.out" || [ "$( attr "$( rootOpen "$DIR/a7.out" )" early )" = proven ]; } && ! grep -q '<route ' "$DIR/a7.out"
    say $? "(7) [N] --no-verb-route == --page-bytes=12000 (a spelled page never routes) or its early-ended page 1, no <route>" "(7) [N] the opt-out differs from the paged --for"
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

# ── ES arms (22–25): page 1 ends early after a leading <callers by="subject"> block that proves itself complete ─────
Q_ES='Who calls compute_total?'
if run e22 plain --for="$Q_ES" && run e22f plain --for="$Q_ES" --page-bytes=12000; then
    R="$( rootOpen "$DIR/e22.out" )"
    [ "$( attr "$R" early )" = proven ] && [ "$( attr "$R" page )" = 1 ] && [ -n "$( attr "$R" deferred )" ] && [ -n "$( attr "$R" withheld_bytes )" ] \
        && [ "$( wc -c <"$DIR/e22.out" )" -lt "$( wc -c <"$DIR/e22f.out" )" ]
    say $? "(22) [P] ES: page 1 ends early (early=proven page=1 deferred= withheld_bytes=), shorter than the full page" "(22) [P] root reads '${R:0:300}'"
    python3 -c 'import re,sys; d=re.sub(r"<!--.*?-->","",open(sys.argv[1]).read(),flags=re.S); m=re.search(r"<ctx [^>]*>(.*)</ctx>$",d.strip(),re.S); sys.exit(0 if m and re.fullmatch(r"<callers by=\"subject\"[^>]*>.*</callers>",m.group(1),re.S) else 1)' "$DIR/e22.out"
    say $? "(22) [P] ES: the early page holds the callers block and nothing after it" "(22) [P] the early page holds more than the block"
    NEXT="$( attr "$R" next | python3 -c 'import html,sys; sys.stdout.write(html.unescape(sys.stdin.read().strip()))' )"
    case "$NEXT" in
        *"--page-bytes=12000:1") eval "\"\$BIN\" \"\$DIR/plain\" $NEXT" >"$DIR/e22n.out" 2>/dev/null; cmp -s "$DIR/e22n.out" "$DIR/e22f.out"
            say $? "(22) [P] ES: next= is the FULL page 1 (a spelled page never ends early)" "(22) [P] next= replay differs from the full page 1" ;;
        *) no "(22) [P] ES: next= is not the full page 1: '$NEXT'" ;;
    esac
    LG="$( python3 -c 'import re,sys; print(" ".join(re.findall(r"<!--.*?-->",open(sys.argv[1]).read(),re.S)))' "$DIR/e22.out" )"
    printf '%s' "$LG" | grep -q 'callers by=subject of=' && printf '%s' "$LG" | grep -q 'early=proven' && printf '%s' "$LG" | grep -q 'deferred='
    say $? "(22) [P] ES: the early page's legend defines the callers block and early= / deferred= / withheld_bytes=" "(22) [P] ES legend incomplete"
    if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$DIR/e22.out" 2>/dev/null; say $? "(22) [C] the early page is well-formed XML" "(22) [C] the early page is not well-formed"; fi
    run e22d plain --for="$Q_ES"; cmp -s "$DIR/e22.out" "$DIR/e22d.out"
    say $? "(22) [C] ES: two runs are byte-identical" "(22) [C] ES runs differ"
fi
# (23) [N] a text-only file naming the subject: no early stop (the full page, byte for byte)
if run e23 gap --for="$Q_ES" && run e23f gap --for="$Q_ES" --page-bytes=12000; then
    cmp -s "$DIR/e23.out" "$DIR/e23f.out"
    say $? "(23) [N] ES: a fold-worthy text gap vetoes the early stop" "(23) [N] ES fired with a text gap: '$( rootOpen "$DIR/e23.out" | head -c 200 )'"
fi
# (24) [N] a macro caller row: no early stop
if run e24 mac --for="$Q_ES" && run e24f mac --for="$Q_ES" --page-bytes=12000; then
    cmp -s "$DIR/e24.out" "$DIR/e24f.out"
    say $? "(24) [N] ES: a macro caller row vetoes the early stop" "(24) [N] ES fired through a macro: '$( rootOpen "$DIR/e24.out" | head -c 200 )'"
fi
# (25) [N] a transitive question never leads with the callers block, so never ends early
if run e25 plain --for='Trace the transitive callers of compute_total.' && run e25f plain --for='Trace the transitive callers of compute_total.' --page-bytes=12000; then
    cmp -s "$DIR/e25.out" "$DIR/e25f.out"
    say $? "(25) [N] ES: a transitive question is today's page" "(25) [N] ES fired on a transitive question"
fi

# ── CALLEES VETO arms (26–29): a question that asks what X CALLS is never routed (RT2-V, forroute.h asksCallees) ─────
# The what-it-calls ROUTE (RT2-C) failed its single confirmation and was reverted; the shipped rule used to send these to
# --callers through the who-calls cue. Now: the --for answer, byte for byte, and who-calls phrasing still routes.
mkdir -p "$DIR/pyv"; printf 'def helper():\n    return 1\n\n\nclass App:\n    def initialize(self):\n        return helper()\n' >"$DIR/pyv/app.py"
vetoArm(){ # $1 id $2 fixture $3 question
    if run "$1" "$2" --for="$3" && run "$1o" "$2" --for="$3" --no-verb-route; then
        cmp -s "$DIR/$1.out" "$DIR/$1o.out" && ! grep -q '<route ' "$DIR/$1.out"
        say $? "($1) [N] callees veto: '$3' is the --for answer byte for byte, no <route>" "($1) [N] '$3' was routed: '$( firstChild "$DIR/$1.out" )'"
    else
        no "($1) [N] a run exited non-zero: $( head -c 200 "$DIR/$1o.err" )"
    fi
}
vetoArm v26a plain 'What does `run_main` call?'
vetoArm v26b plain 'Which helpers does `run_main` call directly?'
vetoArm v26c plain 'List the callees of `run_main`.'
vetoArm v26d plain 'What `run_main` calls, file by file.'
vetoArm v26e pyv   'What does `App.initialize` call in this app? List the modules.'
# (27) [P] who-calls near-misses keep routing to --callers
for q in 'Who calls `compute_total`?' 'What calls `compute_total`?' 'Callers of `compute_total`, please.' '`compute_total` is called by which functions?' 'Which functions call `compute_total`?'; do
    run w27 plain --for="$q"
    F="$( firstChild "$DIR/w27.out" )"
    [ "$( attr "$F" kind )" = who-calls ] && [ "$( attr "$F" verb )" = "--callers=compute_total" ]
    say $? "(27) [P] who-calls near-miss routes to --callers: '$q'" "(27) [P] '$q' reads '$F'"
done
# (28) [P] the veto is ahead of every kind: a callees question with a radius or transitive word is still not routed
vetoArm v28a plain 'What does `run_main` call, and which files are affected?'
vetoArm v28b plain 'Which functions does `run_main` call transitively?'
# (29) [C] determinism of a vetoed answer
run v29 plain --for='What does `run_main` call?'; cmp -s "$DIR/v29.out" "$DIR/v26a.out"
say $? "(29) [C] two runs of a vetoed question are byte-identical" "(29) [C] vetoed runs differ"

# ── RT3 arms (30–35): three question kinds the RT2 rule sent to the wrong verb (results/RT3_VETOES_1119) ────────────
# (A) a call PATH / CHAIN question is not a radius or a 1-hop-callers question: the PATH veto, no route.
# (B) HELD — a BARE "blast radius" as the transitive radius (--impact) is built but switched off (forroute.h
#     kBareBlastRadiusOn); arm 32 pins the RT2 behaviour (--uses) until the owner re-enables it.
# (C) a double-quoted literal (a message, an error string) outside every backtick span: the LITERAL veto, no route — the
#     answer needs where the literal is built first. Each [P] arm is RED on the RT2 base (2f5561c26): that is the control.
mkdir -p "$DIR/msg"
cat >"$DIR/msg/tool.c" <<'C'
#include <stdio.h>
static void print_usage( void )
{
    fprintf( stderr, "usage: tool [-v] FILE\n" );
}
int run_tool( int argc )
{
    if( argc < 2 )
    {
        print_usage();
        return 2;
    }
    return 0;
}
C
# (30) [P] class A: a call-chain / call-path / path-from question is vetoed — the --for answer byte for byte, no <route>
vetoArm v30a plain 'What is the exact call chain from `outer_entry` to `compute_total`?'
vetoArm v30b plain 'Which call path from `outer_entry` triggers `compute_total`?'
vetoArm v30c plain 'Trace the path from `outer_entry` to `compute_total`.'
vetoArm v30d plain 'Show the call-chain between `run_main` and `compute_total`; who calls what?'
# (31) [P] class C: a double-quoted literal (straight or curly quotes) is vetoed
vetoArm v31a msg 'Running `run_tool` prints "usage: tool [-v] FILE"; where is that message built and who calls it?'
vetoArm v31b msg 'Which function calls `print_usage` to print “usage: tool”?'
# (32) [N] class B is HELD (owner ruling 2026-11-19: until IMB1, --impact ⊇ --uses, lands and T5h measures it; forroute.h
#      kBareBlastRadiusOn = false). These arms pin the RT2 behaviour: a bare "blast radius" routes direct-radius → --uses.
#      When rule B is re-enabled, flip them back to kind=transitive verb=--impact=compute_total.
for q in 'What is the blast radius of changing `compute_total`?' 'What is the blast radius of changing `compute_total`, the helper that adds one?'; do
    run b32 plain --for="$q"
    F="$( firstChild "$DIR/b32.out" )"
    [ "$( attr "$F" kind )" = direct-radius ] && [ "$( attr "$F" verb )" = "--uses=compute_total" ]
    say $? "(32) [N] rule B held: bare blast radius still routes to --uses (RT2): '$q'" "(32) [N] '$q' reads '$F'"
done
# (33) [N] the routes that should still fire still fire, each to the verb RT2 chose
routeIs(){ # $1 fixture $2 question $3 kind $4 verb
    run r33 "$1" --for="$2"
    F="$( firstChild "$DIR/r33.out" )"
    [ "$( attr "$F" kind )" = "$3" ] && [ "$( attr "$F" verb )" = "$4" ]
    say $? "(33) [N] still routed $3 → $4: '$2'" "(33) [N] '$2' reads '$F'"
}
routeIs plain 'Who calls `compute_total`?'                                  who-calls     --callers=compute_total
routeIs plain 'Where is `compute_total` used?'                              where-used    --uses=compute_total
routeIs plain 'What breaks if I change `compute_total`?'                    direct-radius --uses=compute_total
routeIs plain 'Which files are affected if `compute_total` changes?'        direct-radius --uses=compute_total
routeIs plain 'If I change `compute_total`, which files have to change?'    direct-radius --uses=compute_total
routeIs plain 'Trace the transitive callers of `compute_total`.'            transitive    --impact=compute_total
routeIs plain 'Which functions reach `compute_total` within two hops?'      transitive    --impact=compute_total
routeIs plain 'What is the transitive blast radius of changing `compute_total`?' transitive --impact=compute_total
routeIs plain 'What is the blast radius of changing `compute_total`? List every file that calls it.' direct-radius --uses=compute_total
routeIs plain 'What is the blast radius of changing `compute_total`? List every module that references it.' direct-radius --uses=compute_total
# near-misses of the two vetoes: a bare "path"/"chain" word, an apostrophe, quotes INSIDE a backtick span
routeIs plain 'Which files on the include path call `compute_total`?'       direct-radius --uses=compute_total
routeIs plain 'Who calls `compute_total` in the chain of helpers?'          who-calls     --callers=compute_total
routeIs plain "Who calls the lib's \`compute_total\`?"                       who-calls     --callers=compute_total
routeIs msg   'Who calls `print_usage` from `fprintf(stderr, "x")`?'        who-calls     --callers=print_usage
# (34) [P] the vetoes are ahead of every kind: a path question with a transitive or radius word is still not routed
vetoArm v34a plain 'Trace the call path from `outer_entry` to `compute_total`, hop by hop.'
vetoArm v34b plain 'What is the blast radius along the call chain from `outer_entry` to `compute_total`?'
vetoArm v34c msg   'What breaks if the "usage: tool" text built by `print_usage` changes?'
# (35) [C] determinism of a vetoed answer
run v35 plain --for='What is the exact call chain from `outer_entry` to `compute_total`?'; cmp -s "$DIR/v35.out" "$DIR/v30a.out"
say $? "(35) [C] two runs of a path-vetoed question are byte-identical" "(35) [C] path-vetoed runs differ"

# ── RT3-F1 arms (36–40): a WINDOWED routed answer continues ITSELF (coordinator follow-up F1) ────────────────────────
# The verb windows its rows (--uses 100, --impact 40: has_more="1" next_offset=K). The routed root's next= used to name
# another lens (--safe-delete / none), and `--for=Q --offset=K` answered with a --for <files> page. Now the root's next= is
# `--for=Q --offset=K`, and that call routes the same question to the verb's window at K: the <route> (verb= spells the
# offset) and the verb's rows at --offset=K. An unwindowed routed answer and an unrouted --for are untouched.
mkdir -p "$DIR/wide"
printf 'int target_fn( int a )\n{\n    return a;\n}\n' >"$DIR/wide/t.c"
for i in $( seq -w 1 120 ); do printf 'int target_fn( int a );\nint caller_%s( void )\n{\n    return target_fn( %d );\n}\n' "$i" "$((10#$i))" >"$DIR/wide/c$i.c"; done
rootNext(){ python3 -c 'import html,re,sys; d=re.sub(r"<!--.*?-->","",open(sys.argv[1]).read(),flags=re.S); m=re.search(r"<[A-Za-z][^>]*>",d); n=re.search(r"\snext=\"([^\"]*)\"",m.group(0)) if m else None; sys.stdout.write(html.unescape(n.group(1)) if n else "")' "$1"; }
# the verb's rows: the answer from the root on, the <route> element, KB1's key group and the root's own open tag set aside
verbRows(){ python3 -c 'import re,sys; d=re.sub(r"<!--.*?-->","",open(sys.argv[1]).read(),flags=re.S); d=re.sub(r"<route [^>]*/>","",d); d=re.sub(r"<bodies of=\"key\".*?</bodies>","",d,flags=re.S); m=re.search(r"<[A-Za-z][^>]*>",d); sys.stdout.write(d[m.end():] if m else "")' "$1"; }
# RL1 (2026-11-21, results/RL1_ROUTED_PAGING_1121): the routed answer is held to the page (test/forroutepagecheck.sh), so its
# first window may be SHORTER than the verb's default one: on this fixture the where-used answer counted about 300 B over the
# 12,000 B page with its carried page, and now windows at K=86 where --uses alone windows at 100. $5 is therefore the verb's
# default window, an UPPER bound; K is read from the root's own next_offset= and every check below uses that K. This RELAXES
# "K is exactly $5" to "K <= $5 and next= names the root's own K", so it carries a mutation control (LANE_CONSTRAINTS §17): the
# same comparison fails against K+1.
contArm(){ # $1 id $2 question $3 verb flag (--uses / --impact) $4 kind $5 the verb's default window (K <= it)
    local q="$2" want off k
    run "$1" wide --for="$q"
    k="$( attr "$( rootOpen "$DIR/$1.out" )" next_offset )"
    want="$( python3 -c 'import shlex,sys; print("--for=" + shlex.quote(sys.argv[1]) + " --offset=" + sys.argv[2])' "$q" "$k" )"
    off="$( python3 -c 'import shlex,sys; print("--for=" + shlex.quote(sys.argv[1]) + " --offset=" + str(int(sys.argv[2] or 0) + 1))' "$q" "$k" )"
    [ -n "$k" ] && [ "$k" -ge 1 ] && [ "$k" -le "$5" ] && [ "$( rootNext "$DIR/$1.out" )" = "$want" ]
    say $? "($1) [P] windowed $4 answer: root next= continues it at its own next_offset=$k, at most the verb's window of $5 ($want)" "($1) [P] root next= is '$( rootNext "$DIR/$1.out" )', want '$want' with K=$k in 1..$5"
    [ "$( rootNext "$DIR/$1.out" )" != "$off" ]
    say $? "($1) [M] the same comparison fails against K+1" "($1) [M] root next= also equals the K+1 spelling: the comparison is vacuous"
    run "$1c" wide --for="$q" --offset="$k"; run "$1v" wide "$3=target_fn" --offset="$k"
    F="$( firstChild "$DIR/$1c.out" )"
    [ "$( attr "$F" kind )" = "$4" ] && [ "$( attr "$F" verb )" = "$3=target_fn --offset=$k" ]
    say $? "($1) [P] --for=Q --offset=$k routes to the verb's window: <route kind=$4 verb=\"$3=target_fn --offset=$k\">" "($1) [P] continuation route reads '$F'"
    [ -n "$( verbRows "$DIR/$1v.out" )" ] && [ "$( verbRows "$DIR/$1c.out" )" = "$( verbRows "$DIR/$1v.out" )" ]
    say $? "($1) [P] the continuation's rows are $3=target_fn --offset=$k's rows, byte for byte" "($1) [P] continuation rows differ from the verb's window"
    if grep -q '<ctx task=\|<text_only' "$DIR/$1c.out"; then no "($1) [P] a continuation carries a --for page or a fold"; else ok "($1) [P] a continuation carries no --for page and no fold"; fi
}
contArm f36 'Where is `target_fn` used?' --uses where-used 100
contArm f37 'Trace the transitive callers of `target_fn`.' --impact transitive 40
# (38) [N] an unwindowed routed answer keeps the verb's own root next= (no has_more)
run f38 plain --for='Who calls `compute_total`?'; run f38v plain --callers=compute_total
[ "$( rootNext "$DIR/f38.out" )" = "$( rootNext "$DIR/f38v.out" )" ]
say $? "(38) [N] unwindowed routed answer: root next= is the verb's own ('$( rootNext "$DIR/f38v.out" )')" "(38) [N] root next= became '$( rootNext "$DIR/f38.out" )'"
# (39) [N] an unrouted question with --offset is the --for file page, as before (the opt-out spelling of the same call)
run f39 plain --for='How does the total get computed?' --offset=1; run f39o plain --for='How does the total get computed?' --offset=1 --no-verb-route
cmp -s "$DIR/f39.out" "$DIR/f39o.out" && ! grep -q '<route ' "$DIR/f39.out"
say $? "(39) [N] an unrouted --for --offset is the --for file page byte for byte" "(39) [N] unrouted --offset answer changed"
# (40) [N] --no-verb-route with --offset on a routed question is the --for file page (never routed)
run f40 wide --for='Where is `target_fn` used?' --offset=100 --no-verb-route
if grep -q '<route ' "$DIR/f40.out"; then no "(40) [N] --no-verb-route --offset routed"; else ok "(40) [N] --no-verb-route --offset is the --for file page, never routed"; fi

# ── R1 arms (41–42): an apply/invoke word led by "how do|does|did" is not a where-used cue (forroute.h howDoBefore) ──────
# The rake-12 everyday shape ("how does rake invoke the task … `multitask` …") asks how the actor works; RT2 routed it to
# --uses on the backticked symbol and the answer lost the mechanism. (41) and (41b) are RED on the RT2/RT3 binary (it routed).
r1Unrouted(){ local n="$1" q="$2"
    if run "r$n" plain --for="$q" && run "r${n}o" plain --for="$q" --no-verb-route; then
        cmp -s "$DIR/r$n.out" "$DIR/r${n}o.out" && ! grep -q '<route ' "$DIR/r$n.out"
        say $? "($n) [P] R1: '$q' stays on --for (the unrouted answer, byte for byte)" "($n) [P] R1: '$q' was routed: '$( firstChild "$DIR/r$n.out" )'"
    else
        no "($n) [P] a run exited non-zero: $( head -c 200 "$DIR/r${n}o.err" )"
    fi; }
r1Unrouted 41 'When I run the program, how does `run_main` invoke the work, and how is `compute_total` added up?'
r1Unrouted 41b 'How does the build apply `compute_total` to each input?'
# (42) [N] the where-used forms R1 must NOT touch: still kind=where-used, verb=--uses (non-vacuity for (41): the cue is live)
for q in 'Where is `compute_total` invoked?' 'What invokes `compute_total`?' 'How is `compute_total` invoked?' 'Where is `compute_total` applied?'; do
    if run r42 plain --for="$q"; then
        F="$( firstChild "$DIR/r42.out" )"
        [ "$( attr "$F" kind )" = where-used ] && [ "$( attr "$F" verb )" = "--uses=compute_total" ]
        say $? "(42) [N] R1: '$q' still routes where-used → --uses" "(42) [N] R1: '$q' route reads '$F'"
    else
        no "(42) [N] a run exited non-zero: $( head -c 200 "$DIR/r42.err" )"
    fi
done

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAILURES ABOVE"; fi
exit "$fail"
