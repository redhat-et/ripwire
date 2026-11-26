#!/usr/bin/env bash
# slotbasecheck.sh — SLOT-NARROW (src/valuerefindex.h ValueRefIndex::narrowFor / derive): the question-independent base of the
# narrow value index is built once per process for the model the warm snapshot identifies, and each question derives its own
# narrow index from it.
#
# THE COST (llvm-project, served warm --for, after SLOTREG #757, PROFILE_SCOPE on the dev flavour): a --for builds the narrow
# index three times (forslots.h spliceSlotJoinRows, forfilesyms.h by-bind rows, verbs_for.h bind ranking), ~0.8 s each, and
# ~0.4 s of each resolved the same slot stores again; keepSets and indexReference walked all 12.5 M references per build. None
# of that reads the question: only the Value references NAMING one of the shown functions do.
#
# THE ARMS. Identity arms compare stdout (+ rc) of a served call against RIPWIRE_NO_VERBFS=1 and --no-cache, both of which
# build every narrow index the old way (no noted model: no base). An identity arm passes on code with no base at all, so the
# premise is a COUNTER (the `[valueref] narrow_base=` RIPWIRE_STATS line, which the base commit does not print: red there) and
# the plain build's derived-vs-fresh DASSERT, with a MUTATION (V) that must trap.
#   B1  COUNTER: a served --for builds the base once (narrow_base=built why=ok) and every later narrow index of that call reuses
#       it (narrow_base=reused why=ok); the premise: the answers carry slot_by= / slot_fields=, so the narrow index is read
#   B2  IDENTITY: four slot questions (a C header static through a registrar's parameter, a C struct-field store, a Python
#       container dispatch, a Go struct field) equal both references
#   B3  --ignore-tests replaces the model's arrays after ingest(): never a base (narrow_base=off why=model), identical to --no-cache
#   B4  RIPWIRE_NO_VERBFS=1 and --no-cache: no base (narrow_base=off why=unarmed)
#   B5  EDIT: the struct-field store removed — the next served call answers as --no-cache (slot_fields=/slot_by= for do_run gone)
#   V   the plain build DASSERTs every derived index equals a fresh narrowFor of the same names; STALE (one value short) must trap
#   D   determinism: two served calls are byte-identical (stdout and stderr)   X  xmllint well-formed
#
# Usage:  bash test/slotbasecheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/slotbasecheck.sh

set -u
export RIPWIRE_NO_CORE_LEGEND=1 RIPWIRE_NO_ROWLINES=1   # the rows as elements (slotregcheck.sh's posture)
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "slotbasecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/fix"
mkdir -p "$FIX/c" "$FIX/py" "$FIX/go/cmd" "$FIX/tests" "$TMP/home" "$TMP/t"
export HOME="$TMP/home"
export TMPDIR="$TMP/t"
unset RIPWIRE_NO_VERBFS RIPWIRE_STATS RIPWIRE_NO_WARMSNAP RIPWIRE_NO_REG_ROWS RIPWIRE_NO_SLOT_JOIN_ROWS RIPWIRE_SLOT_INDEX_FULL RIPWIRE_FAULT_SLOTBASE_STALE

# ── the fixture ──────────────────────────────────────────────────────────────────────────────────────────────────────
# C: headerstaticadjcheck.sh's header static passed to a registrar's parameter (a Value named only by the question), and a
# struct-field store (a Value every narrow index keeps) called through the field.
printf '#ifndef ROW_H\n#define ROW_H\nstatic inline int row_cmp(const void *a, const void *b) { return a == b; }\n#endif\n' >"$FIX/c/row.h"
printf 'int vec_index(void *v, void *x, int (*cmp)(const void *, const void *));\n' >"$FIX/c/vec.h"
printf '#include "vec.h"\nint vec_index(void *v, void *x, int (*cmp)(const void *, const void *)) { return cmp(v, x); }\n' >"$FIX/c/vec.c"
printf '#include "row.h"\n' >"$FIX/c/table.h"
printf '#include "table.h"\n#include "vec.h"\nint t2(void *v, void *x) { return vec_index(v, x, row_cmp); }\n' >"$FIX/c/t2.c"
printf 'struct ops {\n    int (*run)(int);\n};\nint do_run(int x);\nint go_ops(struct ops *o);\n' >"$FIX/c/ops.h"
cat >"$FIX/c/ops.c" <<'EOF'
#include "ops.h"
int do_run(int x) { return x + 1; }
static struct ops OPS = { .run = do_run };
int go_ops(struct ops *o) { return o->run(1); }
int start(void) { return go_ops(&OPS); }
EOF
# Python: a function stored in a module dict, called through it (a container join)
cat >"$FIX/py/handlers.py" <<'EOF'
def handle_alpha(req):
    return req


def handle_beta(req):
    return None


HANDLERS = {"alpha": handle_alpha, "beta": handle_beta}


def dispatch(kind, req):
    return HANDLERS[kind](req)
EOF
printf 'from py.handlers import dispatch\n\ndef test_dispatch():\n    assert dispatch("alpha", 1) == 1\n' >"$FIX/tests/test_handlers.py"
# Go: a function stored in a struct field, called through the field
cat >"$FIX/go/cmd/cmd.go" <<'EOF'
package cmd

type Command struct {
	EvalRW func(int) int
}

func evalPut(x int) int { return x }

var Put = Command{EvalRW: evalPut}

func evaluateCommand(c Command, x int) int {
	return c.EvalRW(x)
}
EOF
QS='how does row_cmp compare rows'
QO='what calls do_run through the ops run field'
QP='how is handle_alpha dispatched from HANDLERS'
QG='who runs evalPut through Command EvalRW'

# ── runners (slotregcheck.sh's) ──────────────────────────────────────────────────────────────────────────────────────
run(){
    local tag="$1" mode="$2"; shift 2
    case "$mode" in
        warm)    ( cd "$FIX" && "$BIN" "$FIX" --cache="$TMP/c.bin" "$@" </dev/null >"$TMP/$tag.out" 2>"$TMP/$tag.err" ) ;;
        novfs)   ( cd "$FIX" && RIPWIRE_NO_VERBFS=1 "$BIN" "$FIX" --cache="$TMP/n.bin" "$@" </dev/null >"$TMP/$tag.out" 2>"$TMP/$tag.err" ) ;;
        nocache) ( cd "$FIX" && "$BIN" "$FIX" --no-cache "$@" </dev/null >"$TMP/$tag.out" 2>"$TMP/$tag.err" ) ;;
    esac
    echo $? >"$TMP/$tag.rc"
}
statrun(){ local tag="$1"; shift; RIPWIRE_STATS=1 run "$tag" warm "$@"; }
bases(){ grep -oE '^\[valueref\] narrow_base=[a-z]+ why=[a-z]+' "$TMP/$1.err" | sed 's/^\[valueref\] //' | tr '\n' ' '; }
same(){ cmp -s "$TMP/$1.out" "$TMP/$2.out" && cmp -s "$TMP/$1.rc" "$TMP/$2.rc"; }
ident(){
    local label="$1"; shift
    run "id.w" warm "$@"; run "id.n" novfs "$@"; run "id.c" nocache "$@"
    if [ "$( cat "$TMP/id.c.rc" )" != 0 ]; then no "$label: the --no-cache reference exited $( cat "$TMP/id.c.rc" )"; return 1; fi
    if same id.w id.c && same id.n id.c; then return 0; fi
    no "$label: served / no-verbfs / no-cache differ: $( diff "$TMP/id.w.out" "$TMP/id.c.out" | head -4 | tr '\n' ' ' )"
    return 1
}
# served TAG ARGS... : a recording call, then the served one with stats (the base exists only on a model the snapshot identifies)
served(){ local tag="$1"; shift; run "$tag.rec" warm "$@"; run "$tag.rec2" warm "$@"; statrun "$tag" "$@"; }

# ── prime: out of the racy window ────────────────────────────────────────────────────────────────────────────────────
sleep 3
for q in "$QS" "$QO" "$QP" "$QG"; do run prime warm --for="$q"; done

# ── B1: the counter, and the premise ─────────────────────────────────────────────────────────────────────────────────
b1=0; reused=0; premise=0
for q in "$QS" "$QO" "$QP" "$QG"; do
    served b1 --for="$q"
    seq="$( bases b1 )"
    first="$( printf '%s' "$seq" | awk '{print $1" "$2}' )"
    rest="$( printf '%s' "$seq" | awk '{for(i=3;i<=NF;i+=2) print $i" "$(i+1)}' | sort -u | tr '\n' ' ' )"
    if [ "$first" = "narrow_base=built why=ok" ] && { [ -z "$rest" ] || [ "$rest" = "narrow_base=reused why=ok " ]; }; then b1=$(( b1 + 1 ))
    else no "B1 '$q': expected one narrow_base=built why=ok, then only reused; got '$seq' (the base commit prints no [valueref] narrow_base line)"; fi
    [ -n "$rest" ] && reused=$(( reused + 1 ))
    grep -qE 'slot_by=|slot_fields=' "$TMP/b1.out" && premise=$(( premise + 1 ))
done
[ "$b1" = 4 ] && ok "B1 every served slot question builds the base once and derives every narrow index from it"
if [ "$reused" -ge 1 ]; then ok "B1b at least one question ($reused of 4) derives a second narrow index from the same base (narrow_base=reused)"
else no "B1b no question reused the base: every --for built one narrow index only"; fi
if [ "$premise" -ge 3 ]; then ok "B1c the premise: $premise of 4 served answers carry slot_by= / slot_fields= (the narrow index is read)"
else no "B1c premise: only $premise of 4 answers carry slot_by= / slot_fields="; fi

# ── B2: identity ─────────────────────────────────────────────────────────────────────────────────────────────────────
b2=0
for q in "$QS" "$QO" "$QP" "$QG"; do ident "B2 '$q'" --for="$q" && b2=$(( b2 + 1 )); done
ident "B2 --for compact" --for="$QO" --legend=compact && b2=$(( b2 + 1 ))
[ "$b2" = 5 ] && ok "B2 five served slot answers equal no-verbfs and --no-cache"

# ── B3: --ignore-tests is never served a base ────────────────────────────────────────────────────────────────────────
served b3 --for="$QP" --ignore-tests
if [ -n "$( bases b3 )" ] && ! bases b3 | grep -qE 'built|reused' && bases b3 | grep -q 'narrow_base=off why=model'; then ok "B3 --ignore-tests builds every narrow index fresh: $( bases b3 )"
else no "B3 --ignore-tests: expected only narrow_base=off why=model, got '$( bases b3 )'"; fi
run b3.c nocache --for="$QP" --ignore-tests
if same b3 b3.c; then ok "B3 --ignore-tests: identical to --no-cache"; else no "B3 --ignore-tests differs from --no-cache"; fi

# ── B4: kill switch and --no-cache ───────────────────────────────────────────────────────────────────────────────────
( cd "$FIX" && RIPWIRE_STATS=1 RIPWIRE_NO_VERBFS=1 "$BIN" "$FIX" --cache="$TMP/n.bin" --for="$QO" </dev/null >/dev/null 2>"$TMP/b4n.err" )
( cd "$FIX" && RIPWIRE_STATS=1 "$BIN" "$FIX" --no-cache --for="$QO" </dev/null >/dev/null 2>"$TMP/b4c.err" )
if [ -n "$( bases b4n )" ] && [ -n "$( bases b4c )" ] && ! cat "$TMP/b4n.err" "$TMP/b4c.err" | grep -E '^\[valueref\] narrow_base=' | grep -qv 'narrow_base=off why=unarmed'; then
    ok "B4 RIPWIRE_NO_VERBFS=1 and --no-cache keep no base (narrow_base=off why=unarmed)"
else no "B4 expected only narrow_base=off why=unarmed: novfs '$( bases b4n )' / nocache '$( bases b4c )'"; fi

# ── B5: an edit to a stored value ────────────────────────────────────────────────────────────────────────────────────
run b5.before warm --for="$QO"
cat >"$FIX/c/ops.c" <<'EOF'
#include "ops.h"
int do_run(int x) { return x + 1; }
static struct ops OPS;
int go_ops(struct ops *o) { return o->run(1); }
int start(void) { return go_ops(&OPS); }
EOF
served b5 --for="$QO"
if ident "B5" --for="$QO"; then
    if grep -qE 'slot_(by|fields)=' "$TMP/b5.before.out" && ! cmp -s "$TMP/b5.before.out" "$TMP/id.w.out"; then ok "B5 after the store is removed the served answer changes and equals --no-cache"
    else no "B5 the answer did not change with the store removed (before: $( grep -cE 'slot_(by|fields)=' "$TMP/b5.before.out" ) slot rows)"; fi
fi

# ── V: the plain build proves every derived index against a fresh one; a stale one traps ────────────────────────────
# A plain build (--version says "(dev,") keeps its fault switches; a release build compiles them out. The trap's banner and any
# stats line printed before it go to the render's captured stream, so the status is the signal (brk 133 on arm64, ud2 132 on x86-64).
PLAIN=0; "$BIN" --version 2>/dev/null | grep -q '(dev,' && PLAIN=1
for q in "$QS" "$QO"; do
    if [ "$PLAIN" = 0 ]; then printf '  INFO  V this binary compiles fault switches out (NDEBUG): the derived-vs-fresh check is a plain-build check\n'; break; fi
    RIPWIRE_FAULT_SLOTBASE_STALE=1 run v.p warm --for="$q"; RIPWIRE_FAULT_SLOTBASE_STALE=1 run v.r warm --for="$q"
    RIPWIRE_FAULT_SLOTBASE_STALE=1 run v warm --for="$q"
    run v.h warm --for="$q"   # the same served call, honest: it answers (the check passes on an index that matches)
    vrc="$( cat "$TMP/v.rc" )"
    if { [ "$vrc" = 133 ] || [ "$vrc" = 132 ]; } && [ "$( cat "$TMP/v.h.rc" )" = 0 ]; then ok "V '$q': a derived index one value short traps the plain build (rc=$vrc), the honest call answers (rc=0)"
    else no "V '$q': a stale derived index was not caught (mutant rc=$vrc, honest rc=$( cat "$TMP/v.h.rc" ))"; fi
done

# ── D, X ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
run d_rec warm --for="$QS"; run d1 warm --for="$QS"; run d2 warm --for="$QS"
if [ "$( cat "$TMP/d1.rc" )" = 0 ] && same d1 d2 && cmp -s "$TMP/d1.err" "$TMP/d2.err"; then ok "D two served calls are byte-identical (stdout and stderr)"; else no "D served calls differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/d1.out" 2>/dev/null && xmllint --noout "$TMP/b5.out" 2>/dev/null; then ok "X well-formed XML"; else no "X xmllint rejects a served answer"; fi
fi

[ "$fail" = 0 ] && echo "slotbasecheck: PASS" || echo "slotbasecheck: FAIL"
exit "$fail"
