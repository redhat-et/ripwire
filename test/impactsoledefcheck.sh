#!/usr/bin/env bash
# impactsoledefcheck.sh — an --impact answer NAMES THE DEFINITION IT MEASURED when the selector matched one definition group.
#
#   test/impactsoledefcheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# The defect (lane t2-rankdefects, class I1 of results/T2_RANKDEFECTS_1118): `--impact=intersection` answered
# `of="intersection" defs="1" reaches="2568"` and never said WHERE that one definition is. Its file appeared only when a caller
# happened to live in it; on textual's Region.intersection none does, so the blast radius of a change left out the file the
# change is made in, and a reader could not tell which `intersection` had been measured. A multi-group selector already lists
# its groups as <def ix= t= [sc=] p=file:line/> rows (attribmultidefcheck); the one-group answer printed none.
#
# The contract:
#   * ONE definition group (one definition, or one definition with the declarations tied to it) on --impact: exactly one
#     <def ix="1" t= [sc=] p=file:line [bodyless="1"]/> child of the root, the multi-group table's own row (the bodied member's
#     file:line). CLI XML, the columnar form (before <cols>), CLI JSON "def_table":[{"ix":1,…}] and the MCP impact tool alike.
#     No row carries of_def (there is one group: every row belongs to it), and the root carries no defs_listed=.
#   * The legend defines the row whenever it prints: the default (compact) legend's `def ix=` reading, and under --legend=full
#     the sole-definition clause (not the multi-group clause, which describes of_def tokens no row here carries).
#   * SCOPE — --impact only, by a stated reason: the blast radius of a change includes the file the change is made in, so the
#     definition is part of this verb's answer set. --callers / --callees / --safe-delete keep the one-group answer without a
#     table, as attribmultidefcheck pins ("every other answer carries no table").
#   * A selector that matches nothing prints no <def> row; a multi-group selector is unchanged (its rows, its of_def tokens).
#
# Arm classes: [P] positive — the defect shape, RED on a binary without the row; [N] near miss — a shape the change must not
# touch; [C] control — holds on every binary.
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

echo "impactsoledefcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }

# ── the corpus, written here (no file of this tree is read as a fixture) ─────────────────────────────────────────────
# py/   geo.py defines area() and Shape.scale(); use.py and far.py call them. No caller lives in geo.py: the only way the
#       answer can name geo.py is the definition row.
# c/    proto.h declares tally(), proto.c defines it (one group: declaration + definition), main.c calls it.
# multi/ two classes with a same-named method (two groups): the multi-group table, unchanged.
mkdir -p "$DIR/py" "$DIR/c" "$DIR/multi"
cat >"$DIR/py/geo.py" <<'PY'
def area(w, h):
    return w * h


class Shape:
    def scale(self, k):
        return k * 2
PY
cat >"$DIR/py/use.py" <<'PY'
from geo import area, Shape


def room(w, h):
    return area(w, h)


def grow(s: Shape):
    return s.scale(3)
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

# run TAG CORPUS ARGS… : the answer on stdout to $DIR/TAG.out (the legend comments stripped to $DIR/TAG.body)
run(){
    local tag="$1" corpus="$2"; shift 2
    if ! ( cd "$DIR/$corpus" && perl -e 'alarm 120; exec @ARGV' "$BIN" . --no-cache "$@" ) >"$DIR/$tag.out" 2>"$DIR/$tag.err"; then
        no "$tag: '$*' on $corpus exited non-zero: $( head -2 "$DIR/$tag.err" )"; : >"$DIR/$tag.body"; return 1
    fi
    perl -0pe 's/<!--.*?-->//gs' "$DIR/$tag.out" >"$DIR/$tag.body"
    return 0
}
# defrows TAG : the <def …/> rows of the answer body, one per line
defrows(){ grep -oE '<def [^>]*/>' "$DIR/$1.body" || true; }
ndef(){ defrows "$1" | grep -c . || true; }

# ── (1) [P] one free function, no caller in its own file ─────────────────────────────────────────────────────────────
if run p_fn py --impact=area; then
    got="$( defrows p_fn )"
    [ "$got" = '<def ix="1" t="fn" p="geo.py:1"/>' ]
    say $? "(1) [P] --impact=area: the one definition is named, <def ix=\"1\" t=\"fn\" p=\"geo.py:1\"/>" \
           "(1) [P] --impact=area: def rows = '$got' (expected exactly <def ix=\"1\" t=\"fn\" p=\"geo.py:1\"/>)"
    { grep -q 'defs="1"' "$DIR/p_fn.body" && ! grep -q 'of_def=' "$DIR/p_fn.body" && ! grep -q 'defs_listed=' "$DIR/p_fn.body"; }
    say $? "(1) [N] --impact=area: defs=\"1\", no row carries of_def, the root carries no defs_listed=" \
           "(1) [N] --impact=area: of_def= or defs_listed= rides a one-group answer"
    { grep -q 'n="room"' "$DIR/p_fn.body" && grep -q 'n="house"' "$DIR/p_fn.body"; }
    say $? "(1) [C] --impact=area: the radius rows are still there (room at depth 1, house at depth 2)" \
           "(1) [C] --impact=area: a radius row went missing"
fi

# ── (2) [P] one method: the row carries its scope ───────────────────────────────────────────────────────────────────
if run p_m py --impact=scale; then
    got="$( defrows p_m )"
    [ "$got" = '<def ix="1" t="fn" sc="Shape" p="geo.py:6"/>' ] || [ "$got" = '<def ix="1" t="method" sc="Shape" p="geo.py:6"/>' ]
    say $? "(2) [P] --impact=scale: the one method is named with its scope ($got)" \
           "(2) [P] --impact=scale: def rows = '$got' (expected one row, sc=\"Shape\" p=\"geo.py:6\")"
fi

# ── (3) [P] C declaration + definition are ONE group: one row, at the definition ────────────────────────────────────
if run p_c c --impact=tally; then
    got="$( defrows p_c )"
    [ "$got" = '<def ix="1" t="fn" p="proto.c:3"/>' ]
    say $? "(3) [P] --impact=tally: prototype + definition are one group, named once at the definition (proto.c:3)" \
           "(3) [P] --impact=tally: def rows = '$got' (expected exactly <def ix=\"1\" t=\"fn\" p=\"proto.c:3\"/>)"
fi

# ── (4) [P] every dialect of the verb carries it ────────────────────────────────────────────────────────────────────
if run p_col py --impact=area --format=columnar; then
    [ "$( defrows p_col )" = '<def ix="1" t="fn" p="geo.py:1"/>' ]
    say $? "(4) [P] columnar: the same <def> row rides before <cols>" "(4) [P] columnar: def rows = '$( defrows p_col )'"
fi
if run p_json py --impact=area --json; then
    grep -q '"def_table":\[{"ix":1,"t":"fn","p":"geo.py:1"}\]' "$DIR/p_json.out"
    say $? "(4) [P] --json: \"def_table\":[{\"ix\":1,\"t\":\"fn\",\"p\":\"geo.py:1\"}]" \
           "(4) [P] --json: no one-row def_table: $( grep -oE '"def_table":[^]]*\]' "$DIR/p_json.out" | head -1 )"
    ! grep -q '"defs_listed"' "$DIR/p_json.out"
    say $? "(4) [N] --json: no defs_listed key on a one-group answer" "(4) [N] --json: defs_listed rides a one-group answer"
fi
printf '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"impact","arguments":{"path":"%s","symbol":"area"}}}\n' \
    "$DIR/py" | perl -e 'alarm 120; exec @ARGV' "$BIN" --mcp 2>"$DIR/p_mcp.err" | tail -1 >"$DIR/p_mcp.out"
if grep -q 'geo.py:1' "$DIR/p_mcp.out" && grep -qE 'def ix=\\"1\\"|"def_table":' "$DIR/p_mcp.out"; then
    ok "(4) [P] MCP impact: the answer names the one definition at geo.py:1"
else
    no "(4) [P] MCP impact: no definition row for area: $( head -c 300 "$DIR/p_mcp.out" )"
fi

# ── (5) [P] the legend defines the row when it prints, and not otherwise ────────────────────────────────────────────
if [ -s "$DIR/p_fn.out" ]; then
    grep -q 'def ix=' "$DIR/p_fn.out"
    say $? "(5) [P] default legend: the answer that prints the row defines <def ix=" "(5) [P] default legend: <def ix= is printed and never defined"
fi
if run p_full py --impact=area --legend=full; then
    grep -q 'the ONE definition group' "$DIR/p_full.out"
    say $? "(5) [P] --legend=full: the sole-definition clause rides" "(5) [P] --legend=full: no clause defines the sole <def> row"
    ! grep -q 'K~s' "$DIR/p_full.out"
    say $? "(5) [N] --legend=full: the multi-group of_def clause does not ride a one-group answer" \
           "(5) [N] --legend=full: the multi-group clause (K~s …) rides a one-group answer"
fi

# ── (6) [N] the verbs whose answer set does not include the definition stay as they were ────────────────────────────
for v in "--callers=area" "--callees=room" "--safe-delete=area"; do
    tag="n_$( printf '%s' "$v" | tr -c 'a-z' '_' )"
    if run "$tag" py $v; then
        [ "$( ndef "$tag" )" = 0 ]
        say $? "(6) [N] $v (one group): no <def> table, as attribmultidefcheck pins" "(6) [N] $v: $( ndef "$tag" ) <def> row(s) on a one-group answer"
    fi
done

# ── (7) [N] nothing matched: no row ─────────────────────────────────────────────────────────────────────────────────
if ( cd "$DIR/py" && "$BIN" . --no-cache --impact=no_such_symbol_here ) >"$DIR/n_none.out" 2>/dev/null; then :; fi
perl -0pe 's/<!--.*?-->//gs' "$DIR/n_none.out" >"$DIR/n_none.body"
[ "$( ndef n_none )" = 0 ]
say $? "(7) [N] --impact of a name with no definition: no <def> row" "(7) [N] a not-found selector printed a <def> row"

# ── (8) [C] a multi-group selector is unchanged: its table, its of_def tokens ───────────────────────────────────────
if run c_multi multi --impact=render; then
    { [ "$( ndef c_multi )" = 2 ] && grep -q 'of_def=' "$DIR/c_multi.body"; }
    say $? "(8) [C] --impact=render (two groups): two <def> rows and of_def on the rows" \
           "(8) [C] --impact=render: $( ndef c_multi ) <def> rows / of_def missing"
fi

# ── (9) [C] determinism and well-formedness ─────────────────────────────────────────────────────────────────────────
if run c_det py --impact=area; then
    cmp -s "$DIR/c_det.out" "$DIR/p_fn.out"
    say $? "(9) [C] two runs of --impact=area are byte-identical" "(9) [C] two runs of --impact=area differ"
    if command -v xmllint >/dev/null 2>&1; then
        { printf '<r>'; cat "$DIR/p_fn.out"; printf '</r>'; } | xmllint --noout - 2>/dev/null
        say $? "(9) [C] the answer is well-formed XML" "(9) [C] the answer is not well-formed XML"
    else
        ok "(9) [C] xmllint not installed: well-formedness not checked here (xmlwellformed covers it)"
    fi
fi

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAILURES ABOVE"; fi
exit "$fail"
