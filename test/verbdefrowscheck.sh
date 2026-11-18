#!/usr/bin/env bash
# verbdefrowscheck.sh — --callers, --uses and --impact NAME THE DEFINITIONS (and the declarations tied to them) they measured.
#
#   test/verbdefrowscheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# The defect (lane P1 VERBROUTE, results/P1_VERBROUTE_1118 SPEC §1; lane V1 implements it): these roots said defs="N" and
# printed no path for the definition. On the held-out set 13 of the 16 gold groups a routed answer lost were the file that
# DEFINES or DECLARES the symbol. Lane T2 (test/impactsoledefcheck.sh) made a one-group --impact answer print its one
# <def ix="1"/> row; this gate generalises it:
#
#   * --callers (XML, columnar, --json), --uses (XML, columnar) and --impact, and their MCP twins find_referencing_symbols,
#     uses and impact, print the <def> table on EVERY answer whose selector resolved a definition group — one group too.
#     --callees / --safe-delete keep a one-group answer table-less.
#   * A group's row is followed by one row per declaration tied to its definition (C family: the edit-check identity rule),
#     same ix=, bodyless="1" — so a prototype in a header is named beside the definition (proto.h beside proto.c). Every
#     <def> table carries these member rows, multi-group tables included.
#   * The rows are the root's first children: before any <s>, <u>, <files>, <rf> or <cols>.
#   * --uses above 16 groups lists none and says defs_listed="0" (its use-site rows name no group).
#   * Lossless: with the <def> rows and the legend comments stripped, the answer body is the parent's byte for byte.
#
# Arm classes: [P] positive — RED on the parent binary (57b4c3ee3); [N] near miss — a shape the change must not touch;
# [C] control — holds on every binary (the strip-identity pins were taken from the parent).
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
fail=0
# every verdict is an if/else: a failed write of a PASS line must never print FAIL for an arm that passed (gateexitcheck G2)
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
say(){ if [ "$1" = 0 ]; then ok "$2"; else no "$3"; fi; }

echo "verbdefrowscheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }

# ── the corpus, written here (no file of this tree is read as a fixture) ─────────────────────────────────────────────
# py/    geo.py defines area(); use.py and far.py call it. No caller lives in geo.py.
# c/     proto.h declares tally(), proto.c defines it (ONE group: definition + tied declaration), main.c calls it.
# multi/ two classes with a same-named render() (two groups).
# wide/  seventeen classes with a same-named draw() (above the 16-group table cap).
mkdir -p "$DIR/py" "$DIR/c" "$DIR/multi" "$DIR/wide"
cat >"$DIR/py/geo.py" <<'PY'
def area(w, h):
    return w * h
PY
cat >"$DIR/py/use.py" <<'PY'
from geo import area


def room(w, h):
    return area(w, h)
PY
cat >"$DIR/py/far.py" <<'PY'
from use import room


def house():
    return room(2, 3) + room(4, 5)
PY
cat >"$DIR/c/proto.h" <<'C'
#ifndef PROTO_H
#define PROTO_H
int tally(int a, int b);
#endif
C
cat >"$DIR/c/proto.c" <<'C'
#include "proto.h"

int tally(int a, int b)
{
    return a + b;
}
C
cat >"$DIR/c/main.c" <<'C'
#include "proto.h"

int total(void)
{
    return tally(1, 2);
}
C
cat >"$DIR/multi/two.py" <<'PY'
class Box:
    def render(self):
        return 1


class Card:
    def render(self):
        return 2


def draw_box(b: Box):
    return b.render()


def draw_card(c: Card):
    return c.render()
PY
for i in $( seq 1 17 ); do printf 'class W%s:\n    def draw(self):\n        return %s\n\n\n' "$i" "$i"; done >"$DIR/wide/w.py"
printf 'def paint(w):\n    return w.draw()\n' >>"$DIR/wide/w.py"

# run TAG CORPUS ARGS… : stdout to $DIR/TAG.out, legend comments stripped to $DIR/TAG.body
run(){
    local tag="$1" corpus="$2"; shift 2
    if ! ( cd "$DIR/$corpus" && perl -e 'alarm 120; exec @ARGV' "$BIN" . --no-cache "$@" ) >"$DIR/$tag.out" 2>"$DIR/$tag.err"; then
        no "$tag: '$*' on $corpus exited non-zero: $( head -2 "$DIR/$tag.err" )"; : >"$DIR/$tag.body"; return 1
    fi
    perl -0pe 's/<!--.*?-->//gs' "$DIR/$tag.out" >"$DIR/$tag.body"
    return 0
}
defrows(){ grep -oE '<def [^>]*/>' "$DIR/$1.body" | tr -d '\n' || true; }
ndef(){ grep -oE '<def [^>]*/>' "$DIR/$1.body" | grep -c . || true; }
# first TAG : true when every <def> row precedes the first non-def child of the root (<s <u <f <rf <files <cols <c)
first(){ perl -0ne 'my $last = rindex( $_, "<def " ); exit 1 if $last < 0;
    for my $t ( "<s ", "<u ", "<f ", "<rf ", "<files", "<cols", "<c " ) { my $i = index( $_, $t ); exit 1 if $i >= 0 && $i < $last } exit 0' "$DIR/$1.body"; }
# strip TAG : the body with every <def> row and the root's root= (a temp path) masked — the parent-pinned shape
strip(){ perl -0pe 's/<def [^>]*\/>//g; s/ root="[^"]*"/ root="R"/g' "$DIR/$1.body"; }

PY_ROW='<def ix="1" t="fn" p="geo.py:1"/>'
C_ROWS='<def ix="1" t="fn" p="proto.c:3"/><def ix="1" t="fn" p="proto.h:3" bodyless="1"/>'

# ── (1) [P] one Python function: every radius verb names it, as the root's first child ─────────────────────────────
for v in callers uses impact; do
    if run "p1_$v" py "--$v=area"; then
        got="$( defrows "p1_$v" )"
        [ "$got" = "$PY_ROW" ]
        say $? "(1) [P] --$v=area: the one definition is named, $PY_ROW" "(1) [P] --$v=area: def rows = '$got' (expected $PY_ROW)"
        first "p1_$v"
        say $? "(1) [P] --$v=area: the <def> row is the root's first child" "(1) [P] --$v=area: a row precedes the <def> row (or none rides)"
        ! grep -qE 'of_def=|defs_listed=' "$DIR/p1_$v.body"
        say $? "(1) [N] --$v=area: no of_def, no defs_listed= on a one-group answer" "(1) [N] --$v=area: of_def= / defs_listed= rides a one-group answer"
    fi
done

# ── (2) [P] C prototype + definition: the definition row, then the tied declaration's own row (header named) ───────
for v in callers uses impact; do
    if run "p2_$v" c "--$v=tally"; then
        got="$( defrows "p2_$v" )"
        [ "$got" = "$C_ROWS" ]
        say $? "(2) [P] --$v=tally: proto.c:3 (definition) then proto.h:3 bodyless=\"1\" (its declaration), both ix=\"1\"" \
               "(2) [P] --$v=tally: def rows = '$got' (expected $C_ROWS)"
        [ "$( ndef "p2_$v" )" = "$( grep -oE '<(callers|uses|impact) [^>]*' "$DIR/p2_$v.body" | grep -oE ' defs="[0-9]+"' | grep -oE '[0-9]+' | head -1 )" ]
        say $? "(2) [P] --$v=tally: one <def> row per definition or declaration defs= counts" "(2) [P] --$v=tally: <def> rows != defs="
        first "p2_$v"
        say $? "(2) [P] --$v=tally: the rows lead the answer" "(2) [P] --$v=tally: a row precedes the <def> rows"
    fi
done

# ── (3) [P] every dialect: columnar (before <cols>), --json def_table, MCP twins ────────────────────────────────────
for v in callers uses; do
    if run "p3_col_$v" c "--$v=tally" --format=columnar; then
        [ "$( defrows "p3_col_$v" )" = "$C_ROWS" ] && first "p3_col_$v"
        say $? "(3) [P] --$v columnar: the same rows ride before <cols>" "(3) [P] --$v columnar: def rows = '$( defrows "p3_col_$v" )'"
    fi
done
if run p3_json c --callers=tally --json; then
    grep -q '"def_table":\[{"ix":1,"t":"fn","p":"proto.c:3"},{"ix":1,"t":"fn","p":"proto.h:3","bodyless":1}\]' "$DIR/p3_json.out"
    say $? "(3) [P] --callers --json: def_table holds the definition and its declaration" \
           "(3) [P] --callers --json: $( grep -oE '"def_table":[^]]*\]' "$DIR/p3_json.out" | head -1 )"
fi
mcp(){
    local tag="$1" tool="$2" sym="$3"
    printf '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":{"path":"%s","symbol":"%s"}}}\n' \
        "$tool" "$DIR/c" "$sym" | perl -e 'alarm 120; exec @ARGV' "$BIN" --mcp 2>"$DIR/$tag.err" | tail -1 >"$DIR/$tag.out"
}
for t in find_referencing_symbols uses impact; do
    mcp "p3_mcp_$t" "$t" tally
    if grep -q 'proto.c' "$DIR/p3_mcp_$t.out" && grep -qE 'proto\.h:3|proto\.h\\",\\"line\\":3' "$DIR/p3_mcp_$t.out" && grep -qE 'def ix=|"def_table":' "$DIR/p3_mcp_$t.out"; then
        ok "(3) [P] MCP $t: the definition (proto.c) and its declaration (proto.h:3) are named"
    else
        no "(3) [P] MCP $t: no definition + declaration rows: $( head -c 300 "$DIR/p3_mcp_$t.out" )"
    fi
done

# ── (4) [P] --uses above the 16-group cap: none listed, and the root says so ───────────────────────────────────────
if run p4_wide wide --uses=draw; then
    { [ "$( ndef p4_wide )" = 0 ] && grep -q 'defs_listed="0"' "$DIR/p4_wide.body"; }
    say $? "(4) [P] --uses=draw (17 groups): no row and defs_listed=\"0\"" "(4) [P] --uses=draw: $( ndef p4_wide ) rows, defs_listed: $( grep -oE 'defs_listed="[0-9]+"' "$DIR/p4_wide.body" )"
fi

# ── (5) [P] the legend defines what rides ───────────────────────────────────────────────────────────────────────────
for v in callers uses; do
    if [ -s "$DIR/p2_$v.out" ]; then
        grep -q 'def ix=' "$DIR/p2_$v.out"
        say $? "(5) [P] default legend of --$v: defines <def ix=" "(5) [P] default legend of --$v: <def ix= rides undefined"
    fi
    if run "p5_full_$v" c "--$v=tally" --legend=full; then
        grep -q 'tied declaration' "$DIR/p5_full_$v.out"
        say $? "(5) [P] --$v --legend=full: the clause names the tied-declaration rows" "(5) [P] --$v --legend=full: no clause reads the declaration row"
    fi
done

# ── (6) [N] verbs outside the scope keep a one-group answer table-less ──────────────────────────────────────────────
for v in "--callees=room" "--safe-delete=area"; do
    tag="n6_$( printf '%s' "$v" | tr -c 'a-z' '_' )"
    if run "$tag" py "$v"; then
        [ "$( ndef "$tag" )" = 0 ]
        say $? "(6) [N] $v (one group): no <def> table" "(6) [N] $v: $( ndef "$tag" ) <def> row(s) on a one-group answer"
    fi
done

# ── (7) [N] no definition: no row ───────────────────────────────────────────────────────────────────────────────────
( cd "$DIR/py" && "$BIN" . --no-cache --uses=no_such_symbol_here ) >"$DIR/n7.out" 2>/dev/null
perl -0pe 's/<!--.*?-->//gs' "$DIR/n7.out" >"$DIR/n7.body"
[ "$( ndef n7 )" = 0 ]
say $? "(7) [N] --uses of a name with no definition: no <def> row" "(7) [N] a not-found selector printed a <def> row"

# ── (8) multi-group: two group rows on every verb ([C] callers/impact had them; [P] uses gains them), of_def as before ──
for v in callers uses impact; do
    cls=C; [ "$v" = uses ] && cls=P
    if run "c8_$v" multi "--$v=render"; then
        [ "$( ndef "c8_$v" )" = 2 ]
        say $? "(8) [$cls] --$v=render (two groups): two <def> rows" "(8) [$cls] --$v=render: $( ndef "c8_$v" ) <def> rows"
    fi
done
grep -q 'of_def=' "$DIR/c8_callers.body" && grep -q 'of_def=' "$DIR/c8_impact.body"
say $? "(8) [C] --callers/--impact=render: rows still carry of_def" "(8) [C] of_def went missing on a multi-group answer"

# ── (9) [C] lossless: with the <def> rows stripped the body is the parent's (pinned from 57b4c3ee3) ─────────────────
PIN_USES='<uses schema="ripwire.uses/v1" of="area" defs="1" external="0" count="2" root="R" graph_ambiguous="0" graph_unresolved="0" counts_floor="1"><u role="call" p="use.py:5" in_id="room"/><u role="read" p="use.py:1"/></uses>'
if [ -s "$DIR/p1_uses.body" ]; then
    got="$( strip p1_uses )"
    [ "$got" = "$PIN_USES" ]
    say $? "(9) [C] --uses=area minus its <def> row is the parent's answer byte for byte" "(9) [C] --uses=area stripped: '$got'"
fi
PIN_CALLERS='<callers schema="ripwire.callers/v1" of="area" defs="1" count="1" root="R" hop_tested="0" hop_untested="1" graph_ambiguous="0" graph_unresolved="0" counts_floor="1" next="--uses=area"><s t="fn" n="room" p="use.py:4" sites_at="5"/></callers>'
if [ -s "$DIR/p1_callers.body" ]; then
    got="$( strip p1_callers )"
    [ "$got" = "$PIN_CALLERS" ]
    say $? "(9) [C] --callers=area minus its <def> row is the parent's answer byte for byte" "(9) [C] --callers=area stripped: '$got'"
fi

# ── (11) [P] the <def> reading is short and still complete (lane S1, results/S1_SMALL_1118) ───────────────────────────
# V1's own readout: on callers and uses the legend cost about twice the rows (+5.4 KB vs +2.7 KB, +7.3 KB vs +4.4 KB pooled
# over 48 held-out cells). The readings were shortened with no meaning dropped; this arm pins both halves of that: a byte
# ceiling (RED on V1's e6671f267: compact 133 B, one-group 220 B, --uses 160+42 B) and the terms each reading must still carry.
# clause TAG START : the legend clause of TAG.out that begins with START, up to its terminator ('. ' or ' -->')
clause(){ START="$2" perl -0ne 'my $s = index( $_, $ENV{START} ); exit 0 if $s < 0; my $r = substr( $_, $s ); $r =~ s/(\. | -->).*//s; print $r' "$DIR/$1.out"; }
need(){ local txt="$1" what="$2"; shift 2; local w; for w in "$@"; do case "$txt" in *"$w"*) ;; *) no "(11) [P] $what lost '$w': '$txt'"; return 1;; esac; done; return 0; }
c11="$( clause p2_callers '<def ix= t= sc= p= bodyless=1>:' )"
if [ "${#c11}" -gt 0 ] && [ "${#c11}" -le 112 ]; then ok "(11) [P] compact <def> reading is ${#c11} B (ceiling 112)"; else no "(11) [P] compact <def> reading is ${#c11} B (ceiling 112): '$c11'"; fi
need "$c11" "compact <def> reading" 'defs=' 'definition' 'tied declarations' 'same ix=' 'bodyless=1 no body' && ok "(11) [P] compact <def> reading keeps defs=, definition, tied declarations, same ix=, bodyless=1"
if run p11_full c --callers=tally --legend=full; then
    s11="$( clause p11_full '<def ix=1 t= sc= p=> alone:' )"
    if [ "${#s11}" -gt 0 ] && [ "${#s11}" -le 175 ]; then ok "(11) [P] full one-group <def> clause is ${#s11} B (ceiling 175)"; else no "(11) [P] full one-group <def> clause is ${#s11} B (ceiling 175): '$s11'"; fi
    need "$s11" "full one-group clause" 'ONE' 'defs=' 'file:line' 'measured' 'tied declaration' 'same ix' 'bodyless=1 no body' 'no row carries of_def' \
        && ok "(11) [P] full one-group clause keeps ONE group, file:line, measured-from, tied declarations, bodyless=1, no of_def"
fi
if run p11_ufull multi --uses=render --legend=full; then
    u11="$( clause p11_ufull '<def ix= t= sc= p= bodyless=1> rows:' )"
    if [ "${#u11}" -gt 0 ] && [ "${#u11}" -le 155 ]; then ok "(11) [P] full --uses <def> clause is ${#u11} B (ceiling 155)"; else no "(11) [P] full --uses <def> clause is ${#u11} B (ceiling 155): '$u11'"; fi
    need "$u11" "full --uses clause" 'GROUPS' 'defs=' 'definition' 'tied declaration' 'same ix' 'bodyless=1 no body' 'use-site row names no group' \
        && ok "(11) [P] full --uses clause keeps groups, tied declarations, bodyless=1, use-site rows name no group"
fi

# ── (10) [C] determinism and well-formedness ────────────────────────────────────────────────────────────────────────
if run c10 c --uses=tally; then
    cmp -s "$DIR/c10.out" "$DIR/p2_uses.out"
    say $? "(10) [C] two runs of --uses=tally are byte-identical" "(10) [C] two runs of --uses=tally differ"
    if command -v xmllint >/dev/null 2>&1; then
        for t in p2_callers p2_uses p2_impact p3_col_uses; do
            { printf '<r>'; cat "$DIR/$t.out"; printf '</r>'; } | xmllint --noout - 2>/dev/null
            say $? "(10) [C] $t is well-formed XML" "(10) [C] $t is not well-formed XML"
        done
    else
        ok "(10) [C] xmllint not installed: well-formedness not checked here"
    fi
fi

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAILURES ABOVE"; fi
exit "$fail"
