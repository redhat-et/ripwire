#!/usr/bin/env bash
# pyaliascallcheck.sh — PY-IMPORT-ALIAS-CALL: a bare Python call through a RENAMED member import
# (`from m import f as g` then `g()`) reaches m's `f`, decided by src/graph.h pythonRenamedImportPin
# from the Import record the shared binds channel writes (src/ingest_importcap.h emitCapturedImportBind,
# CONTRIBUTING family 2 slice 2a: importedName "from:f").
#
# Before the fix the call kept only its local spelling: no definition is named `g` in m, so the name
# ladder bound it to an unrelated decoy.py `g` (via="name") and m's `f` had no caller.
#
# Fixture test/pyaliascallfix (decoy.py defines BOTH a decoy `f` and a decoy `g`; m2.py another `f`):
#   POSITIVE (target m.py:1 f, a proven edge: the row carries no via="name" hedge; internally prov="import")
#     c_plain.py     from m import f as g ; g()                         the defect's own shape
#     c_cond.py      if X: from m import f as g ; g()                   one conditional import: the only target it can bind
#     c_class.py     from m import Widget as Gadget ; Gadget()          a class (target m.py:9 Widget)
#     c_shadow.py    names = [g for g in fs] ; return g()               a comprehension target does not leak: the call after it is the import
#     c_override.py  mo_ga.py: f's def + a module `def __getattr__`     PEP 562: __getattr__ answers only names m lacks, so it cannot
#                                                                       override the def (PY-ALIAS-SPLIT-MARKER; target mo_ga.py:1);
#                    mo_gadeco.py: the same with a decorated def        a decorator is not a conditional (target mo_gadeco.py:6)
#     c_getattr.py   the CALLER file defines `__getattr__`              never consulted for a name the file binds (target m.py:1)
#   NEAR MISSES (must NOT bind m.py's f)
#     c_param.py     def call_param(g): g()                             a parameter shadows the import
#     c_local.py     g = other ; g()                                    a local assignment shadows it
#     c_rebind.py    g = len (module scope) ; g()                       a later module-scope rebinding
#     c_dynamic.py   globals()["g"] = len                               a dynamic namespace write may rebind any name
#     c_star.py      … from starsrc import * ; g()                      a star import may bind g after the rename
#     c_twomod.py    try m / except: m2, both `f as g`                  two modules: never chosen
#     c_fnimport.py  the import sits in another def                     not bound where the call runs
#     c_inner.py     outer def binds g ; inner def calls g()            the closure reads the enclosing g
#     c_disagree.py  from m import f as g ; from m import h as g        two members under one name
#     c_reexport.py  from pkg import f as g (pkg re-exports _impl.f)    no definition in pkg/__init__.py: no decision (a floor)
#     c_external.py  from json import dumps as d (jsonish.py has a dumps)  outside the tree: never an in-tree dumps
#     c_twice.py     m3.py defines f twice                              which one is live is not read: no decision
#     c_nested.py    from m import method as meth                       m defines `method` only inside class Widget: not a module name
#     c_override.py  the TARGET module rebinds f after its def: mo_import.py (`from fast_over import f`), mo_try.py (try-import),
#                    mo_star.py (`from mstar import *` with an f), mo_assign.py (`f = other`), mo_dyn.py (`globals()["f"] = len`),
#                    mo_ostar.py (a star import of a file outside the tree: unknown), mo_global.py (`global f` in a def): m.f is not
#                    provably the live name, so no pin (the unchanged ladder); each caller must not reach its target's line-1 f.
#                    With a module `__getattr__`: mo_gacond.py (f's def under `if`), mo_gatry.py (under `try`) may not run, so
#                    __getattr__ may answer f; mo_gadyn.py (`globals()["f"] = len` too) still withholds (PY-ALIAS-SPLIT-MARKER)
#     c_shadow.py    [g() for g in fs] / list(g() for g in fs) / lambda g: g()   a comprehension target or lambda parameter named g
#                    covers the call (the site-spanned records localNameSet skips)
#     c_member.py    o.gm() / self.gm() through the alias spelling       a member call is not the bare name: never m.py:1
#   UNCHANGED
#     c_same.py      from m import h as h ; h()                         alias equals the name: the ladder, as before
#
# Usage: bash test/pyaliascallcheck.sh [BIN]     (default build/ripwire; exits non-zero on any failure)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/pyaliascallfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "FAIL: no binary at $BIN"; exit 1; }
echo "pyaliascallcheck: $( "$BIN" --version 2>/dev/null )"

# CR 4396503889 (train 40): the query's own exit status is the helper's result and EVERY caller reads it — a selector that is no longer
# indexed answers "not found" with a nonzero exit, and a near-miss arm that only looks for a forbidden path would pass on that.
callees(){ ( cd "$FIX" || exit 1; "$BIN" "$FIX" --no-cache --callees="$1" --legend=compact ) 2>/dev/null >"$TMP/$1"; local rc=$?
           [ "$rc" -eq 0 ] || { no "$1: the --callees query failed (rc=$rc), so its arm below proves nothing"; return 1; }; return 0; }

# ── 0. presence: every fixture file parses (a fixture that fails to parse would pass the near misses inert) ──
( cd "$FIX" || exit 1; "$BIN" "$FIX" --no-cache --skipped --legend=compact ) >"$TMP/skipped" 2>/dev/null
perl -pe 's/<!--.*?-->//g' "$TMP/skipped" >"$TMP/skipped.body"
if ! grep -q 'degraded_parse="0"' "$TMP/skipped.body" || ! grep -q 'indexed="61"' "$TMP/skipped.body" || grep -q '<f \|<h ' "$TMP/skipped.body"; then no "a fixture file was skipped or degraded"; sed 's/^/        | /' "$TMP/skipped" | head -5
else ok "every fixture file indexed with no parse degrade"; fi

# ── 1. positive arms ──
for c in call_plain call_cond call_outside; do
    callees "$c" || continue
    row=$( grep -o '<s [^>]*p="m.py:1"[^>]*/>' "$TMP/$c" )
    if [ -n "$row" ] && ! printf '%s' "$row" | grep -q 'via=' && ! grep -q 'p="decoy.py' "$TMP/$c"; then
        ok "$c binds m.py:1 f as a proven edge (no via=\"name\" hedge) and no decoy row"
    else
        no "$c: expected m.py:1 f (proven, no via=) and no decoy row"; sed 's/<!--.*-->//; s/^/        | /' "$TMP/$c"
    fi
done
callees call_class || :
if grep -q '<s t="cls" n="Widget" p="m.py:9"/>' "$TMP/call_class"; then ok "call_class binds m.py:9 class Widget as a proven edge"
else no "call_class: expected m.py:9 Widget"; sed 's/<!--.*-->//; s/^/        | /' "$TMP/call_class"; fi
( cd "$FIX" || exit 1; "$BIN" "$FIX" --no-cache --callers=m.py:f --legend=compact ) >"$TMP/callers" 2>/dev/null
if grep -q 'n="call_plain"' "$TMP/callers" && grep -q 'n="call_cond"' "$TMP/callers"; then ok "--callers=m.py:f names call_plain and call_cond"
else no "--callers=m.py:f misses an aliased caller"; sed 's/<!--.*-->//; s/^/        | /' "$TMP/callers"; fi

# ── 1b. a module `__getattr__` cannot override a def that exists (PY-ALIAS-SPLIT-MARKER): target side mo_ga.py:1, caller side m.py:1 ──
for a in "call_mo_ga mo_ga.py:1" "call_mo_gadeco mo_gadeco.py:6" "call_cgetattr m.py:1"; do
    set -- $a
    callees "$1"
    row=$( grep -o "<s [^>]*p=\"$2\"[^>]*/>" "$TMP/$1" )
    if [ -n "$row" ] && ! printf '%s' "$row" | grep -q 'via=' && ! grep -q 'p="decoy.py' "$TMP/$1"; then
        ok "$1 binds $2 f as a proven edge although a module __getattr__ is present"
    else
        no "$1: expected $2 f (proven, no via=) and no decoy row"; sed 's/<!--.*-->//; s/^/        | /' "$TMP/$1"
    fi
done

# ── 2. near misses: never m.py's f ──
for c in call_param call_local call_rebind call_dynamic call_star call_twomod call_fnimport call_inner call_disagree call_reexport call_nested call_external call_twice call_comp call_gen call_lambda call_obj call_self; do
    callees "$c" || continue
    # call_disagree imports BOTH f and h as g: neither target may be pinned (h is m.py:5; CR 4396503892)
    if grep -q 'p="m.py:1"\|p="m2.py:1"\|p="m.py:10"\|p="m3.py\|p="jsonish.py' "$TMP/$c" || { [ "$c" = call_disagree ] && grep -q 'p="m.py:5"' "$TMP/$c"; }; then
        no "$c: bound through the renamed import (must stay undecided)"; sed 's/<!--.*-->//; s/^/        | /' "$TMP/$c"
    else ok "$c: no import-pinned edge"; fi
done

# ── 2a. a module `__getattr__` with a def that may not run (if / try), or with a globals() write: no pin ──
for a in "call_mo_gacond mo_gacond.py:4" "call_mo_gatry mo_gatry.py:2" "call_mo_gadyn mo_gadyn.py:1"; do
    set -- $a
    callees "$1"
    if grep -q "p=\"$2\"" "$TMP/$1"; then
        no "$1: pinned $2 though __getattr__ may answer f (must stay undecided)"; sed 's/<!--.*-->//; s/^/        | /' "$TMP/$1"
    else ok "$1: no pin to $2"; fi
done

# ── 2b. the target module rebinds f after its def: a def-line pin to mo_*.py:1 would name the overridden def ──
for c in call_mo_import call_mo_try call_mo_star call_mo_assign call_mo_dyn call_mo_ostar call_mo_global; do
    callees "$c" || continue
    if grep -q 'p="mo_[a-z]*.py:1"' "$TMP/$c"; then
        no "$c: pinned the overridden def of a module that rebinds f (must stay undecided)"; sed 's/<!--.*-->//; s/^/        | /' "$TMP/$c"
    else ok "$c: no pin to the overridden def"; fi
done

# ── 3. unchanged: alias equal to the name keeps the ladder (h in m.py, the edge it had before) ──
callees call_same || :
if grep -q '<s t="fn" n="h" p="m.py:5"/>' "$TMP/call_same"; then ok "call_same: the same ladder edge to m.py:5 h as before"
else no "call_same changed"; sed 's/<!--.*-->//; s/^/        | /' "$TMP/call_same"; fi

# ── 5. PY-CLASS-SPRAY: a bare call binds through its lexical scope chain (graph.h pythonLexicalScopePin) ──
# Fixture scope/ (one directory, so the name-only ladder's same-directory hedge is what the rule replaces): seven files define a
# `Spray` inside a function, three at module scope (decoy_a.py, decoy_b.py, s_module.py), and every caller below calls `Spray()`.
# Read from the eval-only pin census (one row per decided call site: caller, callee, every target), so each arm checks the EXACT
# target set. Before the rule every positive arm split across all 19 same-directory `Spray` definitions (pydantic: one `Model(...)`
# in a test reached 965 classes).
( cd "$FIX" || exit 1; "$BIN" "$FIX" --no-cache --pin-census="$TMP/census" >/dev/null 2>&1 ) || no "the pin-census run failed"
# targets CALLER LINE: the sorted `file::scope::name` targets (ids without their #N) of the C row of caller CALLER's Spray call on LINE
targets(){ awk -F'\t' -v c="scope/$1#" -v l="$2" '$1=="C" && index($6,c)==1 && $7=="Spray" && $9==l { print $8 }' "$TMP/census" \
           | tr '|' '\n' | sed 's/#[0-9]*$//' | sort | paste -sd' ' -; }
flags(){ awk -F'\t' -v c="scope/$1#" -v l="$2" '$1=="C" && index($6,c)==1 && $7=="Spray" && $9==l { print $5 }' "$TMP/census"; }
#   POSITIVE: the definitions the scope binds, and nothing else
for a in "s_local.py::use_local 5 scope/s_local.py::Spray::Spray" \
         "s_enclosing.py::inner_enclosing 6 scope/s_enclosing.py::Spray::Spray" \
         "s_classbody.py::Outer::Outer 6 scope/s_classbody.py::Spray::Spray" \
         "s_decorated.py::use_decorated 9 scope/s_decorated.py::Spray::Spray" \
         "s_default.py::use_default 9 scope/s_default.py::Spray::Spray" \
         "s_module.py::use_module 6 scope/s_module.py::Spray::Spray" \
         "s_imported.py::use_imported 5 scope/decoy_a.py::Spray::Spray"; do
    set -- $a
    got=$( targets "$1" "$2" )
    if [ "$got" = "$3" ]; then ok "$1 (line $2): Spray() binds the one definition its scope chain binds ($3)"
    else no "$1 (line $2): expected exactly $3, got: ${got:-<no row>}"; fi
done
#   a default argument runs in the ENCLOSING scope: the module's Spray (line 1), not the def's own (line 6)
got=$( targets s_default.py::use_default 5 )
want="scope/s_default.py::Spray::Spray"
if [ "$got" = "$want" ] && awk -F'\t' '$1=="C" && $7=="Spray" && $9==5 && index($6,"scope/s_default.py::")==1 && $8 ~ /#[0-9]+$/ && $8 !~ /\|/' "$TMP/census" | grep -q . \
   && [ "$( awk -F'\t' '$1=="C" && $7=="Spray" && index($6,"scope/s_default.py::")==1 { print $9 "=" $8 }' "$TMP/census" | sort | paste -sd' ' - | awk '{ split($1,a,"="); split($2,b,"="); print ( a[2] != b[2] ) }' )" = 1 ]; then
    ok "s_default.py: the default argument (line 5) and the body call (line 9) bind different Spray definitions"
else no "s_default.py line 5: expected the module's Spray alone, distinct from the body's, got: ${got:-<no row>}"; fi
#   two def statements in one scope (a conditional rebinding): a split across exactly those two
got=$( targets s_cond.py::use_cond 8 )
if [ "$got" = "scope/s_cond.py::Spray::Spray scope/s_cond.py::Spray::Spray" ]; then ok "s_cond.py: a split across the scope's two Spray definitions only"
else no "s_cond.py: expected the two s_cond.py Spray definitions only, got: ${got:-<no row>}"; fi
callees use_local && if grep -q '<s [^>]*n="Spray" p="scope/s_local.py:2"' "$TMP/use_local" && ! grep -q 'via=' "$TMP/use_local" && [ "$( grep -o 'n="Spray"' "$TMP/use_local" | wc -l )" -eq 1 ]; then
    ok "--callees=use_local: one proven Spray row (s_local.py:2), no via=\"name\" hedge"
else no "--callees=use_local: expected one proven s_local.py:2 Spray row"; sed 's/<!--.*-->//; s/^/        | /' "$TMP/use_local"; fi
#   NEAR MISSES: the binding is not read, so the rule makes no claim (each arm counts the row it judges; a missing row fails)
for a in "s_condassign.py::use_condassign 7 assignment beside the def" "s_nonlocal.py::outer_nonlocal 10 a nonlocal rebinding" \
         "s_classscope.py::Box::Box 5 a class body that binds the name" "s_param.py::use_param 5 a parameter"; do
    set -- $a; caller=$1; line=$2; shift 2
    got=$( targets "$caller" "$line" )
    if [ -n "$got" ] && [ "$( printf '%s\n' $got | sort -u | sed 's/::.*//' | sort -u | wc -l )" -gt 1 ]; then ok "$caller: $* keeps the unchanged ladder (not pinned to its own file)"
    else no "$caller: $* must stay undecided (the unchanged split), got: ${got:-<no row>}"; fi
done
#   a star import: the scope rule claims no local (the row carries no narrowing flag `r`). STATED FLOOR, not this rule's: the ladder's
#   same-file tier still binds s_star.py's own Spray (decoy_b's star import rebinds it after the def) and, in s_staronly.py, another
#   function's local Spray (a name bound only by a star import) — both as on main.
for a in "s_star.py::use_star 9 a star import after the module's def" "s_staronly.py::use_staronly 12 a name bound only by a star import"; do
    set -- $a; caller=$1; line=$2; shift 2
    got=$( flags "$caller" "$line" )
    if [ -n "$got" ] && [ "${got#*r}" = "$got" ]; then ok "$caller: $*: the scope rule claims no local (row flags '$got')"
    else no "$caller: $*: the scope rule must not decide it (flags: '${got:-<no row>}')"; fi
done
got=$( awk -F'\t' '$1=="C" && index($6,"scope/s_method.py::Holder::go_method#")==1 && $7=="Spray" { print $8 }' "$TMP/census" | sed 's/#[0-9]*$//' )
if [ "$got" = "scope/s_method.py::Holder::Spray" ]; then ok "s_method.py: self.Spray() is a member call, still the method (unchanged)"
else no "s_method.py: expected Holder.Spray, got: ${got:-<no row>}"; fi
if callees use_unbound && ! awk -F'\t' '$1=="C" && index($6,"scope/s_unbound.py::")==1' "$TMP/census" | grep -q .; then
    ok "s_unbound.py: a name no scope binds keeps today's answer (no edge: unresolved)"
else no "s_unbound.py: expected no decided row"; fi

# ── 4. hygiene: determinism and warm == cold ──
# every run's status is read (CR 4396503889): two empty outputs from two failed runs are "equal"
rc=0
( cd "$FIX" || exit 1; "$BIN" "$FIX" --no-cache --callers=f ) >"$TMP/d1" 2>/dev/null || rc=1
( cd "$FIX" || exit 1; "$BIN" "$FIX" --no-cache --callers=f ) >"$TMP/d2" 2>/dev/null || rc=1
if [ "$rc" -eq 0 ] && [ -s "$TMP/d1" ] && cmp -s "$TMP/d1" "$TMP/d2"; then ok "deterministic"; else no "non-deterministic (or a run failed / answered nothing)"; fi
rc=0
( cd "$FIX" || exit 1; "$BIN" "$FIX" --cache="$TMP/c.bin" --callers=f ) >"$TMP/cold" 2>/dev/null || rc=1
( cd "$FIX" || exit 1; "$BIN" "$FIX" --cache="$TMP/c.bin" --callers=f ) >"$TMP/warm" 2>/dev/null || rc=1
if [ "$rc" -eq 0 ] && [ -s "$TMP/cold" ] && cmp -s "$TMP/cold" "$TMP/warm" && cmp -s "$TMP/cold" "$TMP/d1"; then ok "warm == cold == --no-cache"; else no "cache changes the answer (or a run failed / answered nothing)"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
