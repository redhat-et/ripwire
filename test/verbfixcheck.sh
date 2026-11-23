#!/usr/bin/env bash
# verbfixcheck.sh — three blind spots of the 1-hop verbs (lane BX1, from BS1's diagnosis results/BS1_BLINDSPOT_1118):
#
#   test/verbfixcheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
#   [F7] AN UNTIED DECLARATION IS PRINTED, NEVER SILENT (defattrib.h defGroupsDropSilent). A prototype the edit-check identity
#        rule cannot tie to the definition (no include proof here) was dropped from a one-group answer while defs="2" still
#        counted it: ninja util.h:82 and tmux tmux.h:3200 printed defs="2" beside ONE <def> row. It now prints as a <def> row
#        of its own (its own ix=, bodyless="1"), so the rows equal defs=. No row is attributed to it (no of_def).
#   [F3] A C `static` IN A HEADER IS VISIBLE TO ITS INCLUDERS (valuerefindex.h ValueRefIndex::resolveName). htop's
#        `static inline Row_idEqualCompare` (Row.h) passed as a comparator from Table.c / ProcessTable.c / pcp/InDomTable.c bound
#        to nothing, because the value resolver kept every internal-linkage definition private to its own FILE. Linkage is per
#        translation unit: a header's static is in every unit that #includes it, directly or through another header.
#        A static in a .c file stays private; a file that does not include the header binds nothing.
#   [F2] MACRO SEE-THROUGH (callhierarchy.h callHierarchyRows, verbs_navigate.h runUses). tmux's cmdq_get_callback1 is only
#        ever called through `#define cmdq_get_callback(cb, data) cmdq_get_callback1(#cb, cb, data)`: --callers printed the
#        macro row and stopped (1 of 9 files). The macro's own callers now follow the direct rows, each marked
#        via="macro:NAME" (JSON "via":"macro:NAME", columnar <via> 3); --uses appends the macro's call sites the same way and
#        counts them in via_macro=. An answer with no macro row is unchanged. BX2 (lane/bx2-verbfix) limits it to the FIRST macro
#        hop and to C-preprocessor macros: a macro calling the macro is a row, its own callers are not (F2.4 / F2.16 re-pinned:
#        start_b, two macros away, is no longer listed; count= 5 -> 4, via_macro= 3 -> 2). Rust: test/rustmacrocallcheck.sh [N6].
#
# Arm classes: [P] positive — RED on the parent binary (lane/v1-verbdef e6671f267); [N] near miss — a shape the change must
# not touch; [C] control — holds on every binary (the pins were taken from the parent).
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
fail=0
# every verdict is an if/else: a failed write of a PASS line must never print FAIL for an arm that passed (gateexitcheck G2)
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
has(){ if printf '%s' "$1" | grep -qF -- "$2"; then ok "$3"; else no "$3 — missing: $2"; fi; }
hasnt(){ if printf '%s' "$1" | grep -qF -- "$2"; then no "$3 — present: $2"; else ok "$3"; fi; }
body(){ printf '%s' "$1" | sed 's/^.*-->//'; }
count(){ printf '%s' "$1" | grep -oF -- "$2" | wc -l | tr -d ' '; }

echo "verbfixcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }

# ── the corpus, written here (no file of this tree is read as a fixture) ─────────────────────────────────────────────
# u/  util.h declares close_exec(); util.c defines it WITHOUT including util.h (the identity rule's include proof fails: untied);
#     user.c includes util.h and calls it.
# t/  the tied shape: t.c includes t.h, so the prototype is tied (one group, two rows, same ix).
# h/  row.h: `static inline row_cmp`; t1.c includes row.h, t2.c includes table.h which includes row.h, lone.c includes
#     neither (binds nothing), other.c has its OWN `static row_cmp` (binds its own).
# m/  q.h: get_cb(cb, data) -> get_cb1(#cb, cb, data); get_cb_twice(cb) -> get_cb(cb, 0). direct() calls get_cb1 by name,
#     start_a() through get_cb, start_b() through get_cb_twice (a two-macro chain).
mkdir -p "$DIR/u" "$DIR/t" "$DIR/h" "$DIR/m"
printf 'void close_exec(int fd);\n' >"$DIR/u/util.h"
printf 'void close_exec(int fd)\n{\n    (void)fd;\n}\n' >"$DIR/u/util.c"
printf '#include "util.h"\nvoid spawn(void)\n{\n    close_exec(3);\n}\n' >"$DIR/u/user.c"
printf 'int tally(int a, int b);\n' >"$DIR/t/t.h"
printf '#include "t.h"\nint tally(int a, int b)\n{\n    return a + b;\n}\n' >"$DIR/t/t.c"
printf '#include "t.h"\nint total(void)\n{\n    return tally(1, 2);\n}\n' >"$DIR/t/main.c"
cat >"$DIR/h/row.h" <<'C'
#ifndef ROW_H
#define ROW_H
static inline int row_cmp(const void *a, const void *b) { return a == b; }
#endif
C
printf 'int vec_index(void *v, void *x, int (*cmp)(const void *, const void *));\n' >"$DIR/h/vec.h"
printf '#include "row.h"\n' >"$DIR/h/table.h"
printf '#include "row.h"\n#include "vec.h"\nint t1(void *v, void *x) { return vec_index(v, x, row_cmp); }\n' >"$DIR/h/t1.c"
printf '#include "table.h"\n#include "vec.h"\nint t2(void *v, void *x) { return vec_index(v, x, row_cmp); }\n' >"$DIR/h/t2.c"
printf '#include "vec.h"\nstatic int row_cmp(const void *a, const void *b) { return 0; }\nint t3(void *v, void *x) { return vec_index(v, x, row_cmp); }\n' >"$DIR/h/other.c"
printf '#include "vec.h"\nint t4(void *v, void *x) { return vec_index(v, x, row_cmp); }\n' >"$DIR/h/lone.c"
cat >"$DIR/m/q.h" <<'C'
struct item;
#define get_cb(cb, data) get_cb1(#cb, cb, data)
#define get_cb_twice(cb) get_cb(cb, 0)
struct item *get_cb1(const char *, void *, void *);
C
printf '#include "q.h"\nstruct item *get_cb1(const char *name, void *cb, void *data)\n{\n    return 0;\n}\nvoid direct(void)\n{\n    get_cb1("x", 0, 0);\n}\n' >"$DIR/m/q.c"
printf '#include "q.h"\nstatic void on_a(void *d) { }\nvoid start_a(void)\n{\n    get_cb(on_a, 0);\n}\n' >"$DIR/m/a.c"
printf '#include "q.h"\nstatic void on_b(void *d) { }\nvoid start_b(void)\n{\n    get_cb_twice(on_b);\n}\n' >"$DIR/m/b.c"
cd "$DIR" || exit 1
export TMPDIR="$DIR/tmp"; mkdir -p "$TMPDIR"
rw(){ "$BIN" "$@" 2>/dev/null; }

# ── [F7] the untied declaration ──────────────────────────────────────────────────────────────────────────────────────
echo "[F7] an untied declaration is printed beside defs="
for v in callers uses impact; do
    a="$( rw u --$v=close_exec )"
    has "$a" 'defs="2"' "(F7-$v.0) [C] --$v=close_exec counts the definition and the untied prototype"
    has "$a" '<def ix="2" t="fn" p="util.h:1" bodyless="1"/>' "(F7-$v.1) [P] --$v prints the untied prototype as its own bodyless row"
    rows="$( count "$( body "$a" )" '<def ix=' )"
    if [ "$rows" = 2 ]; then ok "(F7-$v.2) [P] --$v: <def> rows == defs= (2)"; else no "(F7-$v.2) [P] --$v: <def> rows $rows, defs=2"; fi
    hasnt "$a" 'of_def=' "(F7-$v.3) [N] --$v: no row is attributed to the untied group (no of_def)"
done
a="$( rw u --callers=close_exec --legend=full )"
has "$a" 'tied to none' "(F7.4) [P] the full legend reads the untied row"
a="$( rw u --callers=close_exec --json )"
has "$a" '{"ix":2,"t":"fn","p":"util.h:1","bodyless":1}' "(F7.5) [P] --json lists the untied row in def_table"
a="$( rw u --callers=close_exec --format=columnar )"
has "$a" '<def ix="2" t="fn" p="util.h:1" bodyless="1"/>' "(F7.6) [P] columnar lists the untied row"
a="$( printf '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"find_referencing_symbols","arguments":{"path":"%s","symbol":"close_exec"}}}\n' "$DIR/u" | "$BIN" --mcp 2>/dev/null | tail -1 )"
has "$a" '\"ix\":2,\"kind\":\"fn\",\"file\":\"util.h\",\"line\":1,\"bodyless\":1' "(F7.7) [P] MCP find_referencing_symbols lists the untied row"
has "$a" 'tied to none' "(F7.8) [P] MCP def_note reads the untied row"
a="$( body "$( rw t --callers=tally )" )"
has "$a" '<def ix="1" t="fn" p="t.c:2"/><def ix="1" t="fn" p="t.h:1" bodyless="1"/><s ' "(F7.9) [N] a TIED prototype keeps its group's ix=1 row"
hasnt "$a" 'ix="2"' "(F7.10) [N] a tied prototype makes no second group"
a="$( body "$( rw u --callees=close_exec )" )"
hasnt "$a" '<def ' "(F7.11) [N] --callees keeps a one-group answer table-less"

# ── [F3] a header static is visible to its includers ─────────────────────────────────────────────────────────────────
echo "[F3] a C static in a header binds from the files that include it"
a="$( body "$( rw h --uses=row_cmp )" )"
has "$a" '<u role="value" p="t1.c:3"' "(F3.1) [P] a direct includer's value use binds the header static"
has "$a" '<u role="value" p="t2.c:3"' "(F3.2) [P] a transitive includer (t2.c -> table.h -> row.h) binds it too"
has "$a" '<u role="value" p="other.c:3"' "(F3.3) [N] other.c's own static still binds its own use"
hasnt "$a" 'p="lone.c:' "(F3.4) [N] a file that includes no row.h binds nothing"
a="$( rw h --callers=row.h:row_cmp )"
has "$a" 'value_refs="2"' "(F3.5) [P] --callers=row.h:row_cmp counts the two includers' value uses"
a="$( rw h --callers=other.c:row_cmp )"
has "$a" 'value_refs="1"' "(F3.6) [N] a .c static stays private: other.c's row_cmp has its own file's use only"
hasnt "$a" 't1.c' "(F3.7) [N] ... and never t1.c's"

# ── [F2] macro see-through ───────────────────────────────────────────────────────────────────────────────────────────
echo "[F2] the callers and uses verbs see through a function-like macro"
a="$( rw m --callers=get_cb1 )"
b="$( body "$a" )"
has "$b" '<s t="macro" n="get_cb" p="q.h:2" role="macro" sites_at="2"/><s t="fn" n="direct" p="q.c:6" sites_at="8"/>' "(F2.1) [C] the direct rows lead, unchanged (the macro row stays)"
has "$b" '<s t="fn" n="start_a" p="a.c:3" via="macro:get_cb"/>' "(F2.2) [P] a caller of the macro is a row, via=\"macro:get_cb\""
has "$b" '<s t="macro" n="get_cb_twice" p="q.h:3" role="macro" via="macro:get_cb"/>' "(F2.3) [P] a macro calling the macro is a row too"
hasnt "$b" 'n="start_b"' "(F2.4) [N] BX2: the FIRST macro hop only — start_b calls get_cb_twice, which calls get_cb: two macros away, not listed"
has "$b" 'count="4"' "(F2.5) [P] count= counts the see-through rows"
rows="$( count "$b" '<s t=' )"
if [ "$rows" = 4 ]; then ok "(F2.6) [P] four <s> rows"; else no "(F2.6) [P] $rows <s> rows, want 4"; fi
has "$a" 'via=macro:' "(F2.7) [P] the default (compact) legend reads via=macro:"
a="$( rw m --callers=get_cb1 --legend=full )"
has "$a" 'via="macro:NAME"' "(F2.8) [P] the full legend reads via=\"macro:NAME\""
a="$( rw m --callers=get_cb1 --json )"
has "$a" '{"t":"fn","n":"start_a","p":"a.c:3","via":"macro:get_cb"}' "(F2.9) [P] --json carries \"via\":\"macro:get_cb\""
a="$( rw m --callers=get_cb1 --format=columnar )"
has "$a" '<via>0,0,3,3</via>' "(F2.10) [P] columnar marks the see-through rows <via> 3"
has "$a" '3 = via=' "(F2.11) [P] columnar's legend reads code 3"
a="$( printf '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"find_referencing_symbols","arguments":{"path":"%s","symbol":"get_cb1"}}}\n' "$DIR/m" | "$BIN" --mcp 2>/dev/null | tail -1 )"
has "$a" '\"via\":\"macro:get_cb\"' "(F2.12) [P] MCP find_referencing_symbols carries the via"
has "$a" 'via_macro_note' "(F2.13) [P] ... and its reading"
a="$( rw m --uses=get_cb1 )"
b="$( body "$a" )"
has "$b" '<u role="call" p="q.h:2" in_id="get_cb"/><u role="call" p="q.c:8" in_id="direct"/>' "(F2.14) [C] the direct use rows lead, unchanged"
has "$b" 'p="a.c:5" in_id="start_a" via="macro:get_cb"/>' "(F2.15) [P] --uses appends the macro's call site, via=\"macro:get_cb\""
hasnt "$b" 'in_id="start_b"' "(F2.16) [N] BX2: ... not through a second macro"
has "$b" 'p="q.h:3" in_id="get_cb_twice" via="macro:get_cb"/>' "(F2.17) [P] ... and the chain macro's own body site"
has "$b" 'count="4"' "(F2.18) [P] --uses count= counts them"
has "$b" 'via_macro="2"' "(F2.19) [P] --uses root: via_macro=\"2\""
has "$a" 'via_macro=' "(F2.20) [P] the compact legend reads via_macro="
a="$( rw m --uses=get_cb1 --format=columnar )"
has "$a" 'via_macro="2"' "(F2.21) [P] columnar --uses keeps the rows and says via_macro=\"2\""
a="$( body "$( rw h --callers=vec_index )" )"
if [ "$a" = '<callers schema="ripwire.callers/v1" of="vec_index" defs="1" count="4" root="h" hop_tested="0" hop_untested="4" graph_ambiguous="0" graph_unresolved="0" counts_floor="1" next="--uses=vec_index"><def ix="1" t="fn" p="vec.h:1" bodyless="1"/><s t="fn" n="t4" p="lone.c:2" sites_at="2"/><s t="fn" n="t3" p="other.c:3" sites_at="3"/><s t="fn" n="t1" p="t1.c:3" sites_at="3"/><s t="fn" n="t2" p="t2.c:3" sites_at="3"/></callers>' ]; then
    ok "(F2.22) [C] an answer with no macro row is the parent's, byte for byte"
else
    no "(F2.22) [C] an answer with no macro row changed: $a"
fi
a="$( rw m --callees=get_cb1 )"
hasnt "$a" 'via="macro:' "(F2.23) [N] --callees is unchanged"
a="$( rw m --impact=get_cb1 )"
hasnt "$a" 'via="macro:' "(F2.24) [N] --impact is unchanged (it already walks the macro edge)"

# ── [F2C] the per-macro ceiling (lane bx2-fix2-ceiling): one row per FILE per macro, at most 16 files; the rest disclosed ─────
# mc/: many.h `#define get_many(x) many_impl(x)`; f01.c .. f18.c each call get_many once (18 files); f01.c calls it from a
# second function too (twice in one file). Expected: 16 see-through rows (16 files), 3 withheld (2 files past the ceiling +
# the second f01.c caller), via_macro_capped="3", via_macro_next="--callers=get_many".
mkdir -p "$DIR/mc"
printf 'int many_impl(int);\n#define get_many(x) many_impl(x)\n' >"$DIR/mc/many.h"
printf '#include "many.h"\nint many_impl(int x)\n{\n    return x;\n}\n' >"$DIR/mc/impl.c"
for k in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18; do
    printf '#include "many.h"\nint use_%s(void)\n{\n    return get_many(%s);\n}\n' "$k" "$k" >"$DIR/mc/f$k.c"
done
printf 'int use_01b(void)\n{\n    return get_many(1);\n}\n' >>"$DIR/mc/f01.c"
a="$( rw mc --callers=many_impl )"; b="$( body "$a" )"
if [ "$( count "$b" 'via="macro:get_many"' )" = 16 ]; then ok "(F2C.1) [P] 16 see-through rows: one per file, at most 16 files"; else no "(F2C.1) [P] $( count "$b" 'via="macro:get_many"' ) see-through rows, want 16"; fi
has "$b" 'via_macro_capped="3"' "(F2C.2) [P] via_macro_capped= counts the 3 withheld (2 files past the ceiling, 1 second caller in a listed file)"
has "$b" 'via_macro_next="--callers=get_many"' "(F2C.3) [P] via_macro_next= lists the macro's callers whole"
hasnt "$b" 'n="use_01b"' "(F2C.4) [P] a second caller in an already-listed file is withheld"
has "$b" 'count="17"' "(F2C.5) [P] count= counts the rows listed (1 direct macro row + 16)"
has "$a" 'via_macro_capped' "(F2C.6) [P] the legend reads via_macro_capped="
a="$( rw mc --uses=many_impl )"; b="$( body "$a" )"
if [ "$( count "$b" 'via="macro:get_many"' )" = 16 ]; then ok "(F2C.7) [P] --uses: 16 see-through sites, one per file"; else no "(F2C.7) [P] --uses: $( count "$b" 'via="macro:get_many"' ) sites, want 16"; fi
has "$b" 'via_macro="16"' "(F2C.8) [P] --uses via_macro= counts the listed sites"
has "$b" 'via_macro_capped="3"' "(F2C.9) [P] --uses via_macro_capped= counts the withheld sites"
has "$b" 'via_macro_next="--uses=get_many"' "(F2C.10) [P] --uses via_macro_next= lists the macro's sites whole"
a="$( rw mc --callers=many_impl --json )"
has "$a" '"via_macro_capped":3' "(F2C.11) [P] --json carries via_macro_capped"
q='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"find_referencing_symbols","arguments":{"path":"'"$DIR/mc"'","symbol":"many_impl"}}}'
a="$( printf '%s\n%s\n' '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}' "$q" | "$BIN" --mcp 2>/dev/null )"
has "$a" '\"via_macro_capped\":3' "(F2C.12) [P] MCP find_referencing_symbols carries via_macro_capped"
a="$( rw m --callers=get_cb1 )"
hasnt "$a" 'via_macro_capped' "(F2C.13) [N] under the ceiling nothing is withheld and nothing is said"

a1="$( rw m --callers=get_cb1 )"; a2="$( rw m --callers=get_cb1 )"
if [ "$a1" = "$a2" ]; then ok "(D) [C] deterministic: two runs byte-identical"; else no "(D) two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    if rw m --callers=get_cb1 | xmllint --noout - 2>/dev/null && rw m --uses=get_cb1 | xmllint --noout - 2>/dev/null \
       && rw u --impact=close_exec | xmllint --noout - 2>/dev/null; then ok "(X) [C] well-formed XML"; else no "(X) xmllint rejects an answer"; fi
fi

if [ "$fail" = 0 ]; then echo "verbfixcheck: ALL PASS"; else echo "verbfixcheck: FAIL"; fi
exit "$fail"
