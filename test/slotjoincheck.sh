#!/usr/bin/env bash
# slotjoincheck.sh — IX-1 SLOT-TYPE JOIN: a function stored in a struct FIELD T.f, joined to the calls through that field.
#
# Before: `--callers=cmd_split_window_exec` (tmux) listed the two `.exec =` table entries as value rows with no dispatcher,
# and `--callees=cmdq_fire_command` had no row at all for `entry->exec( cmd, item )`. A human greps `.exec =` for the
# entries and `->exec(` for the dispatcher and joins them through the declared struct type; this gate pins that join.
#
# What the change does (ingest_valuerefs.h valueSlot / slotThroughAt / noteStructBody, valuerefindex.h slotCallsFor):
#   * a value row whose slot is a struct field keeps the object's declared struct type and the field (designated `.f = fn`,
#     a positional entry of a struct whose body the file holds, an anonymous struct, a field assignment);
#   * a call through a field (`x->f( … )`, `x->a->f( … )`, `t[ i ].f( … )`) keeps the root's declared type and the chain,
#     typed hop by hop through the field-type facts (a header's struct bodies) and typedef aliases;
#   * the join prints called_by= called_at= via="slot" (same declared type) or via="slot-name" (one side's type unknown) on
#     the callers <vr> row, and <vs> rows + slot_calls= on --callees. Never a proven call: count= never moves.
#
# Near misses (each must NOT join): the same field name on another struct type (both known), a cast receiver, a C++ member
# function named like a function-pointer field of another struct in the same file.
#
# Usage: bash test/slotjoincheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "slotjoincheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 2; }
FIX="$ROOT/test/slotjoinfix"
[ -d "$FIX" ] || { echo "  FAIL  fixture dir missing: $FIX"; exit 2; }
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# One run per query; an answer is read only off a command that succeeded and printed its root element.
run(){
    local out rc
    out="$( cd "$FIX" && "$BIN" "$FIX" "$@" --no-cache 2>/dev/null )"; rc=$?
    if [ "$rc" -ne 0 ] || ! printf '%s' "$out" | grep -q -e '<callers ' -e '<callees ' -e '<external-surface ' -e '^{"of":'; then
        printf 'RUNFAIL rc=%s' "$rc"
        return 0
    fi
    printf '%s' "$out"
}
has(){   # has LABEL OUTPUT NEEDLE
    case "$2" in RUNFAIL*) no "$1 (the run failed: $2)"; return;; esac
    if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else no "$1 — missing: $3"; fi
}
hasnt(){ # hasnt LABEL OUTPUT NEEDLE
    case "$2" in RUNFAIL*) no "$1 (the run failed: $2)"; return;; esac
    if printf '%s' "$2" | grep -qF -- "$3"; then no "$1 — unexpected: $3"; else ok "$1"; fi
}

echo "-- callers side: called_by= called_at= via= on the <vr> row"
o="$( run --callers=cmd_alpha_exec )"
has   "A1 designated .exec = f joins the dispatcher (same type)" "$o" 'into="cmd_alpha_entry.exec" called_by="fire_command" called_at="queue.c:4" via="slot"'
hasnt "A2 the same field name on another struct type never joins" "$o" 'fire_other'
hasnt "A2b nor is it counted as a hidden name-only caller" "$o" 'slot_name_also='
has   "A3 never a proven call: count stays 0" "$o" 'count="0"'
has   "A4 the compact legend defines called_at=/via= when they ride" "$o" 'vr called_at= via=slot|slot-name'
o="$( run --callers=cmd_alpha_exec --legend=full )"
has   "A5 the full legend clause rides with via=" "$o" 'vr called_by= called_at= via=slot|slot-name'
o="$( run --callers=third_exec )"
hasnt "A6 a slot whose type no call names: two known, different types never join (not even by name)" "$o" 'called_by='
has   "A7 its value row still prints" "$o" 'into="third_entry.exec"'
o="$( run --callers=other_exec )"
has   "B1 the other struct's own dispatcher joins it" "$o" 'called_by="fire_other" called_at="queue.c:8" via="slot"'
hasnt "B2 and the first struct's dispatcher does not" "$o" 'fire_command'
o="$( run --callers=copy_command )"
has   "C1 a chained receiver wme->mode->command is typed through the header's field facts" "$o" 'called_by="send_keys" called_at="mode.c:5" via="slot"'
o="$( run --callers=copy_release )"
has   "C2 a typedef alias receiver resolves to the struct" "$o" 'called_by="drop_mode" called_at="mode.c:6" via="slot"'
o="$( run --callers=t_print )"
has   "D1 a positional table entry maps to its field by the struct's field order" "$o" 'into="ground_table[0][2]" called_by="parse" called_at="table.c:13" via="slot"'
o="$( run --callers=lay_even )"
has   "D2 an anonymous struct table joins its subscripted dispatcher" "$o" 'called_by="layout_select" called_at="table.c:22" via="slot"'
o="$( run --callers=on_cb )"
has   "E1 a nested designated literal keys the path from the outer literal's type (FN-SLOT S2: was name-only)" "$o" 'called_by="run_outer" called_at="mode.c:9" via="slot"'
o="$( run --callers=on_go )"
has   "E1b a store whose type is unknown (g_unknown, declared nowhere) joins by name only" "$o" 'called_by="run_nest" called_at="mode.c:14" via="slot-name"'
o="$( run --callers=opa )"
has   "F1 C++: a function-pointer field its type declares in this file" "$o" 'called_by="use" called_at="vt.cpp:8" via="slot"'
o="$( run --callers=cmd_alpha_exec --json )"
has   "G1 the JSON twin carries the same keys" "$o" '"called_by":"fire_command","called_at":"queue.c:4","via":"slot"'

echo "-- callees side: slot_calls= and <vs> rows"
o="$( run --callees=fire_command )"
has   "H1 the dispatcher lists the slot and its targets" "$o" '<vs l="4" through="entry-&gt;exec" slot="cmd_ent.exec" via="slot" targets="2" shown="2"><t n="cmd_alpha_exec" p="cmds.c:2"/><t n="cmd_beta_exec" p="cmds.c:3"/></vs>'
has   "H2 slot_calls= counts it beside count=, never in it" "$o" 'count="0" '
has   "H3 slot_calls= on the root" "$o" 'slot_calls="1"'
o="$( run --callees=fire_cast )"
hasnt "H4 a cast receiver gets no slot row" "$o" 'slot_calls='
o="$( run --callees=run )"
hasnt "H5 C++: a member function named like another struct's pointer field is no slot call" "$o" 'slot_calls='
o="$( run --callees=fire_command --json )"
has   "H6 the JSON twin of <vs>" "$o" '"vss":[{"l":4,"through":"entry->exec","slot":"cmd_ent.exec","via":"slot","targets":2,"shown":2'

echo "-- fix round 1: positional index -> field is exact or no row; typedef / using / pointer-typedef receivers"
o="$( run --callers=d3 )"
has   "I1 a positional value after a designator continues at the next field (C: d3 is .d)" "$o" 'called_by="call_pd_d" called_at="shapes.c:15" via="slot"'
hasnt "I1b and never joins the designated field before it" "$o" 'call_pd_c'
o="$( run --callers=a3 )"
has   "I1c a positional value before the designator keeps its index" "$o" 'called_by="call_pd_a" called_at="shapes.c:13" via="slot"'
o="$( run --callers=x5 )"
has   "I2 an anonymous union member holds one initializer position" "$o" 'called_by="call_au_x" called_at="shapes.c:28" via="slot"'
hasnt "I2b and never the next field's" "$o" 'call_au_y'
o="$( run --callers=y5 )"
has   "I2c the field after it maps too" "$o" 'called_by="call_au_y" called_at="shapes.c:29" via="slot"'
o="$( run --callers=ef )"
hasnt "I3 brace elision (a scalar at a struct-typed field) makes the index unprovable: no join" "$o" 'called_by='
o="$( run --callers=cf_r )"
hasnt "I4 an #ifdef'd field before the index makes it unprovable: no join" "$o" 'called_by='
o="$( run --callers=fa )"
has   "I5 C++: a static data member is no initializer position" "$o" 'called_by="call_sa" called_at="shapes.cpp:11" via="slot"'
o="$( run --callers=fb )"
hasnt "I5b so fb is never sa" "$o" 'call_sa'
has   "I5c fb is sb" "$o" 'called_by="call_sb" called_at="shapes.cpp:12" via="slot"'
o="$( run --callers=fc )"
hasnt "I6 C++: a base-class aggregate makes the positions unprovable: no wrong field" "$o" 'call_dd'
o="$( run --callers=pt_fn )"
has   "I7 a C pointer typedef receiver (typedef struct pt *pt_p) resolves to the struct" "$o" 'called_by="call_ptp" called_at="shapes.c:61" via="slot"'
o="$( run --callers=gfn )"
has   "I8 C++: typedef and using receivers resolve before the function-pointer-field gate" "$o" 'called_by="c_tdef,c_using" called_at="shapes.cpp:34,shapes.cpp:35" via="slot"'
o="$( run --callers=b4 )"
has   "N1 the (*x->f)( ... ) call form is a slot call" "$o" 'called_by="call_pd_star" called_at="shapes.c:18" via="slot"'

echo "-- fix round 2: a field type this file cannot see, and an alias name two files spell differently"
o="$( run --callers=ea )"
hasnt "K1 a value after a field typed by ANOTHER file's struct typedef (brace elision unseen) never joins the wrong field" "$o" 'call_eg'
hasnt "K1b nor any field: the index is unprovable" "$o" 'called_by='
o="$( run --callers=ec )"
hasnt "K2 the single-object twin: no row past the unseen aggregate" "$o" 'called_by='
o="$( run --callers=ia )"
has   "K3 twin: the struct defined in this file and braced keeps the index exact (ia is .f)" "$o" 'called_by="call_if" called_at="elide_in.c:7" via="slot"'
hasnt "K3b and never .g" "$o" 'call_ig'
o="$( run --callers=ib )"
has   "K3c ib is .g" "$o" 'called_by="call_ig" called_at="elide_in.c:8" via="slot"'
o="$( run --callers=ha )"
has   "K3d a value AT a header-typedef field keeps its index (a call through .f proves .f callable)" "$o" 'called_by="call_hf" called_at="elide_in.c:13" via="slot"'
o="$( run --callers=hb )"
hasnt "K3e the floor: a value after it has no row (a lost row, never a wrong one)" "$o" 'called_by='
o="$( run --callers=af )"
has   "K4 a file's own alias decides its receiver (handle_a.c: handle is hsa)" "$o" 'called_by="call_h" called_at="handle_a.c:9" via="slot"'
hasnt "K4b another file's same-named alias to a different struct never joins hsa" "$o" 'call_hb'
hasnt "K4c an alias the repo spells two ways, with no spelling in the file, joins nothing" "$o" 'call_hc'
o="$( run --callers=bf )"
has   "K5 handle_b.c's handle is hsb" "$o" 'called_by="call_hb" called_at="handle_b.c:3" via="slot"'
hasnt "K5b and the conflicting file still joins nothing" "$o" 'call_hc'
o="$( run --callers=lf )"
has   "K6 a pointer alias field is a scalar position (no elision): lf is .f" "$o" 'called_by="call_nl" called_at="nodep.c:7" via="slot"'

echo "-- fix round 3: a macro-typed field, a typedef name vs a struct tag, one tag with two bodies"
o="$( run --callers=ma )"
hasnt "M1 a field typed by a macro (TAILQ_ENTRY(x) e;) has an unknown width: ma is never .g" "$o" 'call_mg'
hasnt "M1b nor any field: no positional row past the macro field" "$o" 'called_by='
o="$( run --callers=taf )"
has   "T1 a typedef name in one file never retypes another file's struct TAG of that spelling: taf is tsa.f" "$o" 'called_by="call_ta" called_at="tagns_a.c:6" via="slot"'
hasnt "T1b so taf is never call_tb" "$o" 'call_tb'
o="$( run --callers=tbf )"
has   "T2 tbf is the struct tag thandle's .f" "$o" 'called_by="call_tb" called_at="tagns_b.c:5" via="slot"'
hasnt "T2b and never call_ta" "$o" 'call_ta'
o="$( run --callers=pa )"
hasnt "Y1 one struct tag with two different bodies in two files is no one type: pa never joins call_pb" "$o" 'call_pb'
o="$( run --callers=pb )"
hasnt "Y2 and pb never joins call_pa" "$o" 'call_pa'

echo "-- fix round 1: slot records are no ordinary references"
o="$( run --external-surface )"
for v in entry wme m o v p; do
    hasnt "J1 --external-surface lists no slot-call receiver as an external name ($v)" "$o" "<x n=\"$v\" "
done

echo "-- section L (CR pre-pass 32b): the <vs> window's continuation and the JSON twin's target names"
o="$( run --callees=big_fire )"
has   "L1 18 stores, a window of 16: the row discloses the cut" "$o" 'targets="18" shown="16" next="--regex='
has   "L2 next= is a regex over ANY spacing and a field assignment, never the literal .f =" "$o" 'next="--regex=&apos;(\.|-&gt;)bigcb\s*=[^=]&apos;"'
n="$( cd "$FIX" && "$BIN" "$FIX" --regex='(\.|->)bigcb\s*=[^=]' --no-cache 2>/dev/null | grep -o 'hits="[0-9]*"' | head -1 )"
if [ "$n" = 'hits="18"' ]; then ok "L3 replaying that regex finds all 18 stores (aligned and unspaced too)"; else no "L3 the replayed regex found ${n:-nothing}, not hits=\"18\""; fi
n="$( cd "$FIX" && "$BIN" "$FIX" --grep='.bigcb =' --no-cache 2>/dev/null | grep -o 'hits="[0-9]*"' | head -1 )"
if [ -n "$n" ] && [ "$n" != 'hits="18"' ]; then ok "L4 the old literal .bigcb = misses stores ($n), so L3 discriminates"; else no "L4 the old literal found ${n:-nothing}: the fixture no longer shows the miss"; fi
o="$( run --callees=ns_dispatch )"
has   "L5 a namespaced target is Scope.name in the XML" "$o" '<t n="nsx.nsgo" p="ns.cpp:5"/>'
o="$( run --callees=ns_dispatch --json )"
has   "L6 and the same in the JSON twin" "$o" '"t":[{"n":"nsx.nsgo","p":"ns.cpp:5"}]'

echo "-- section Z (CR pre-pass 32b): a build-dependent entry inside a positional struct literal"
o="$( run --callers=pf0 )"
has   "Z1 the entry before the #ifdef keeps its exact index (pf0 is .tfirst)" "$o" 'called_by="call_tri_first" called_at="ifdef.c:14" via="slot"'
o="$( run --callers=pf2 )"
has   "Z2 the entry after the #ifdef still prints its value row" "$o" 'into="tri_t[2]"'
hasnt "Z3 but joins no field: it is the 2nd entry without WITH_B and the 3rd with it (never a guessed field)" "$o" 'called_by='
o="$( run --callers=pf1 )"
has   "Z4 the entry inside the #ifdef still prints its value row" "$o" 'into="tri_t[1]"'
hasnt "Z5 and joins no field either" "$o" 'called_by='

echo "-- well-formed XML where the clauses ride"
if command -v xmllint >/dev/null 2>&1; then
    for q in --callers=cmd_alpha_exec --callees=fire_command; do
        o="$( cd "$FIX" && "$BIN" "$FIX" "$q" --legend=full --no-cache 2>/dev/null )"
        if [ -n "$o" ] && printf '%s' "$o" | xmllint --noout - 2>/dev/null; then ok "X $q --legend=full is well-formed"; else no "X $q --legend=full is not well-formed XML"; fi
    done
else
    echo "  SKIP  xmllint not installed (the well-formedness arm needs it)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
