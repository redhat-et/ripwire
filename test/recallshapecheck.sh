#!/usr/bin/env bash
# recallshapecheck.sh — a function used as a VALUE is never a silent zero.
#
#   test/recallshapecheck.sh                       # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/recallshapecheck.sh
#   test/recallshapecheck.sh build_base/ripwire    # the RED run (a pre-change binary)
#   RECALLSHAPE_FX_OUT=DIR test/recallshapecheck.sh   # also copy the generated fixtures to DIR (for probing)
#
# THE DEFECT. A function stored in a struct-field initialiser, an object-literal or dict dispatch table, an array of
# function pointers, a variable, or passed as a callback argument, is referenced as a VALUE, not called. The index
# captured only call-shaped references, so the identifier at the binding site was no reference of any kind: --callers,
# --callees, --impact and --uses all answered count="0" with graph_unresolved="0", --safe-delete said
# dead_code_candidate="1" risk="none-found", and --dead-code listed the function. Every one of those zeros read as
# "nothing else uses this" when a dispatch table did. The mechanism that closes it is a port of codebase-memory-mcp's
# reference-as-value usages (MIT; the implementation commit credits it in THIRD_PARTY.md): an identifier in a value
# position emits a usage at its enclosing scope, resolved by name like any other reference.
#
# THE CONTRACT (what every arm below pins).
#   * A value reference is NOT a call. It is its own row, <vr>, inside its own window <vrs total= shown= capped=
#     [next=]> (the house cap vocabulary), and its own root count, value_refs=N. Both appear only when N > 0, so an
#     answer with no value reference is byte-identical to before.
#   * CALL facts never include a value reference: count=, reaches=, callers= and impact_reaches= are unchanged by it.
#     DELETION VERDICTS do change, on purpose: --safe-delete's uses= (a value site is a use site), risk= and
#     dead_code_candidate=, and --dead-code membership (value-ref-excluded=N). A function a table holds is not dead.
#   * Row attributes are chosen so no existing gate's `n="X"` / `p="X"` / `t="X"` grep can match a <vr> row (fix 1 of
#     the early gates review): the only attributes are in_id= bind= into= called_by= (callers side) and to= def= bind=
#     into= through= sites= (callees side). chk.py rejects any other <vr> attribute on every answer.
#       in_id=     the enclosing symbol holding the reference (as <u in_id=> does); bind= the binding site file:line.
#       into=      where the value lands: VAR.key / VAR["key"] (a keyed initialiser, object literal, dict, map or struct
#                  literal), VAR[i] (the i-th element of a positional initialiser or array), VAR{} (a dict/object KEY),
#                  CALLEE#argI / CALLEE#kw (an argument, CALLEE as written; a parameter default is DEF#param),
#                  @DECORATOR (EVERY decorated def: the decorator receives the function — the mechanism is syntactic and
#                  cannot tell @register from @property; it is not a proven call or registration), ELEMENT.attr (a JSX
#                  attribute), the written left-hand side of an assignment, (return) or (compare).
#       called_by= (callers side) the functions that MAY CALL through that slot, sorted by name, comma-joined: a function
#                  whose parameter is called (slot CALLEE#argI / DEF#param), or a function that calls VAR[…](…) /
#                  VAR.key(…) where VAR resolves to the same declaration (a file-scope VAR from anywhere in its file; a
#                  local VAR only inside its own function; a same-named local or parameter hides it).
#       to= def=   (callees side) the referenced function and its definition; through= the written callee of the call
#                  through the slot (cb, handlers[kind], table.close); sites=N when one (to, through) pair is bound at
#                  N > 1 sites (bind= is then the first). Callees rows are one per (to, through).
#     called_by= and through= are may-call clues, never proven calls.
#   * Matching is BY NAME, with the call graph's visibility: the same language, a C/C++ `static` function only from its
#     own file, a JS/TS/Python name only from its own file or through a named import of it. A same-named local,
#     parameter (incl. arrow/lambda/catch/for/comprehension/range variables and destructuring) or file-scope variable
#     hides the function. A string, a comment, a key/field NAME, a keyword-argument label, a type position (typeof,
#     ReturnType, decltype, sizeof, annotations), an import/export statement itself and a preprocessor condition are
#     not value references.
#   * Disclosure (CLI == MCP): the legend defines every new attribute and says a row is "not a proven call", matched
#     "by name", and that called_by=/through= "may call". CLI --json (vrs), MCP find_referencing_symbols / find_symbol
#     (valueRefs / valueCallees), MCP impact, uses and path_between carry the same rows as the CLI. No new entries in
#     test/legendcoverage_baseline.txt: legendcoveragecheck must cover every new attribute.
#   * --dead-code: one entity, one reason. A def already excluded for a pre-existing reason (register-macro-excluded=,
#     runner-root-excluded=, decorated-excluded=) is counted there only; value-ref-excluded= counts the rest.
#
# ASYMMETRY (disclosed): CommonJS `module.exports = { f }` / `module.exports.f = f` / `exports.f = f` are value uses (an
# assignment); an ES `export { f }` clause and `export default f` are not rows (an export statement, like an import).
#
# NAMED FLOORS (each asserted as a floor arm, never as a pass of the contract):
#   F1 a call through a TYPED pointer or receiver field (`p->open(x)`, p a `struct ops *` parameter): through= matches a
#      container by NAME, and p names none. --callees=use_ptr stays silent.
#   F2 a member or qualified value (`run(obj.lone)`, `self.f`, `ns::qf`, `&Cls::sm`, `this.handler`) is no row.
#   F3 a value spelled by an import ALIAS (`import { aliasFn as af }`, `from m import alias_fn as af`) or bound by a
#      destructured require (`const { reqFn } = require(…)`) is a local binding: no row under the original name.
#   F4 a function as the OBJECT of a member access (`lone2.name`, `lone2.bind(null)`, `lone2.call(…)`, `f.__name__`) is
#      no row.
#   F5 a C macro BODY is opaque (`#define H_ALIAS macro_alias_fn`): no row. A macro ARGUMENT parses as an argument and is
#      a row (REG#arg0).
#   F6 a class used as a value (`{"x": MyClass}`) is out of scope: functions and methods only.
#
# MUTATION PROOF (checklist 1; sim/refval_mutate.sh, measured at the implementation head — the pre-registered list was
# corrected to what each mutant measured): disabling the local/parameter shadow guard turns C5 C14 C2f C2g J2 J2g T2 P2
# P3 P2i G3 X3 red; disabling the keyed-element / keyword-LABEL guard turns P10 P12 P13 G7 G9 red (a C designated field
# and a JS key are field_identifier / property_identifier nodes, never visited, so no guard of this pass protects them);
# reading string contents as identifiers turns C15 C17 C18 J11 J13 J14 T6 T7 P10 P12 P13 G7 G9 X3 red; disabling the
# container shadow turns C1 C2 C6 C16 J1 J12 P1 P11 G1 G8 D1 D2 red; disabling C static linkage turns CX1 CX2 CX3a CX3b
# CX6 red; ignoring the file-scope-object shadow turns CX7 red (JS/Python's CX4/CX5 are ALSO held by the import rule).
#
# The fixtures are generated here (nothing is committed under test/). Markers `@NAME` in a comment on a line resolve to
# that line, so no arm hard-codes a line number.
#
# Exits non-zero on any failure; prints PASS/FAIL per arm.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
verdict(){ if [ "$2" = OK ]; then ok "$1"; else no "$1 — $2"; fi; }   # verdict LABEL RESULT

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "recallshapecheck: BIN=$BIN"

FX="$TMP/fx"
mkdir -p "$FX/c" "$FX/js" "$FX/ts" "$FX/py" "$FX/go" "$FX/cpp" "$FX/ctl" "$FX/big"

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────────
cat >"$FX/c/ops.c" <<'EOF'
#include <stdio.h>
struct ops { int (*open)(int); int (*close)(int); };
static int my_open(int x) { return x + 1; }
static int my_close(int x) { return x - 1; }
static int other_open(int x) { return x * 2; }
static int on_event(int x) { return x + 3; }
static int on_tick(int x) { return x + 4; }
static int lone(int x) { return x; }
static int keep(int v) { return v; }
static int truly_dead(int x) { return x; }
static struct ops table = { .open = my_open, .close = my_close };   /* @C_TABLE */
static int (*fns[])(int) = { other_open, &on_tick };                /* @C_FNS */
static struct ops positional = { my_open, my_close };               /* @C_POS */
int use_literal(int x) { struct ops o = { .open = my_open, .close = my_close }; return o.open(x); }  /* @C_LIT */
int use_global(int x) { return table.close(x) + fns[0](x); }
int use_ptr(struct ops *p, int x) { return p->open(x); }
static int run(int (*cb)(int), int x) { return cb(x); }
int use_callback(void) { return run(on_event, 1) + run(&on_tick, 2); }   /* @C_CB */
int use_assign(struct ops *p) { p->open = other_open; return 0; }        /* @C_ASSIGN */
/* @C_N1 a comment that names a function: .open = lone */
int neg_string(void) { const char *s = "lone"; return puts(s); }         /* @C_N2 */
int neg_shadow(void) { int on_event = 5; return keep(on_event); }        /* @C_N3 */
int neg_field_key(void) { struct { int lone; } k = { .lone = 3 }; return k.lone; }   /* @C_N4 */
int neg_call(void) { return lone(1); }                                    /* @C_N5 */
int shadow_tbl(void) { struct ops table = { 0, 0 }; return table.close(1); }   /* @C_N6 a local named like the file-scope table */
EOF

cat >"$FX/js/table.js" <<'EOF'
function fooGet(req) { return req.a; }
function fooPost(req) { return req.b; }
function fooDel(req) { return req.d; }
function onEvent(x) { return x + 1; }
function onClick(e) { return e; }
function lone(x) { return x; }
const handlers = { get: fooGet, post: fooPost, put(req) { return req.c; } };  // @J_TABLE
const short = { fooDel };                                                      // @J_SHORT
const list = [fooGet, fooDel];                                                 // @J_LIST
function dispatch(kind, req) { return handlers[kind](req); }
function dispatchDot(req) { return handlers.get(req); }
function dispatchPut(req) { return handlers.put(req); }
function run(cb, x) { return cb(x); }
function useCallbacks(xs, bus, el) {
  run(onEvent, 1);                        // @J_RUN
  xs.map(onEvent);                        // @J_MAP
  bus.on("tick", onEvent);                // @J_ON
  el.addEventListener("click", onClick);  // @J_ADD
}
// @J_N1 a comment that names a function: handlers = { get: lone }
function negString() { return { get: "lone" }; }       // @J_N2
function negShadow(fooPost) { return [fooPost]; }      // @J_N3
function negKey() { return { lone: 1 }; }              // @J_N4
function negMember(obj) { return run(obj.lone, 1); }   // @J_N5
function negCall() { return lone(2); }                 // @J_N6
function shadowHandlers(handlers) { return handlers.get(1); }  // @J_N7 a parameter named like the table
module.exports = { dispatch, dispatchDot, dispatchPut, useCallbacks, short, list, negString, negShadow, negKey, negMember, negCall };  // @J_EXPORTS
EOF

cat >"$FX/ts/table.ts" <<'EOF'
type Handler = (req: { a?: number; b?: number }) => number | undefined;
export function fooGet(req: { a?: number }) { return req.a; }
export function fooPost(req: { b?: number }) { return req.b; }
export function onEvent(x: number) { return x + 1; }
export function onClick(e: Event) { return e; }
export function lone(x: number) { return x; }
export const handlers: Record<string, Handler> = { get: fooGet, post: fooPost };   // @T_TABLE
export function dispatch(kind: string, req: { a?: number }) { return handlers[kind](req); }
export function dispatchDot(req: { a?: number }) { return handlers.get(req); }
export function useCallbacks(xs: number[], el: HTMLElement) {
  el.addEventListener("click", onClick);   // @T_ADD
  return xs.map(onEvent);                  // @T_MAP
}
// @T_N1 a comment that names a function: handlers = { get: lone }
export type LoneType = typeof lone;                                   // @T_N2
export interface HasLone { lone(x: number): number }                  // @T_N3
export function negString() { return { get: "lone" }; }               // @T_N4
export function negShadow(fooPost: number) { return [fooPost]; }      // @T_N5
export function negCall() { return lone(2); }                         // @T_N6
export type R = ReturnType<typeof lone>;                              // @T_N7
EOF

cat >"$FX/py/dispatch.py" <<'EOF'
import threading

REGISTRY = []


def register(fn):
    REGISTRY.append(fn)
    return fn


def foo_get(req):
    return req["a"]


def foo_post(req):
    return req["b"]


def on_event(x):
    return x + 1


def worker():
    return 0


def handler():
    return 1


def lone(x):
    return x


def keep(v):
    return v


DISPATCH = {"get": foo_get, "post": foo_post}  # @P_DICT
TABLE = [foo_get, on_event]  # @P_LIST


def dispatch(kind, req):
    return DISPATCH[kind](req)


def dispatch_local(req):
    table = {"get": foo_get}  # @P_LOCAL
    return table["get"](req)


def run(cb, x):
    return cb(x)


def use_callbacks(xs):
    run(on_event, 1)  # @P_RUN
    list(map(on_event, xs))  # @P_MAP
    return threading.Thread(target=worker)  # @P_KW


@register  # @P_DECO
def decorated():
    return 2


alias = handler  # @P_ASSIGN


# @P_N1 a comment that names a function: DISPATCH = {"get": lone}
def neg_string():
    return {"get": "lone"}  # @P_N2


def neg_shadow(foo_post):
    return [foo_post]  # @P_N3


def neg_local():
    on_event = 3
    return keep(on_event)  # @P_N4


def neg_kwlabel():
    return dict(lone=1)  # @P_N5


def neg_member(obj):
    return run(obj.lone, 1)  # @P_N6


def neg_call():
    return lone(2)  # @P_N7


def shadow_dispatch(DISPATCH):
    return DISPATCH["get"](1)  # @P_N8 a parameter named like the table
EOF

cat >"$FX/go/main.go" <<'EOF'
package main

import "net/http"

type Ops struct {
	Open  func(int) int
	Close func(int) int
}

type K struct{ lone int }

func myOpen(x int) int  { return x + 1 }
func myClose(x int) int { return x - 1 }
func onEvent(x int) int { return x + 2 }
func serve(w http.ResponseWriter, r *http.Request) {}
func lone(x int) int    { return x }
func keep(v int) int    { return v }

var handlers = map[string]func(int) int{"open": myOpen, "close": myClose} // @G_MAP
var ops = Ops{Open: myOpen, Close: myClose}                               // @G_STRUCT
var fns = []func(int) int{onEvent, myClose}                               // @G_SLICE

func run(cb func(int) int, x int) int { return cb(x) }
func useCallbacks() int {
	http.HandleFunc("/", serve) // @G_HANDLE
	return run(onEvent, 1)      // @G_RUN
}
func dispatch(k string, x int) int { return handlers[k](x) }
func useOps(x int) int             { return ops.Open(x) }

// @G_N1 a comment that names a function: handlers = {"open": lone}
func negString() string { return "lone" }                      // @G_N2
func negShadow() int    { onEvent := 3; return keep(onEvent) } // @G_N3
func negKey() K         { return K{lone: 1} }                  // @G_N4
func negCall() int      { return lone(2) }                     // @G_N5

func shadowH(handlers map[string]func(int) int) int { return handlers["open"](1) } // @G_N6 a parameter named like the table
func negRange(xs []int) int {
	for _, onEvent := range xs { // @G_N7 a range variable
		keep(onEvent)
	}
	return 0
}

func main() { _ = useCallbacks(); _ = dispatch("open", 1); _ = useOps(1) }
EOF

cat >"$FX/cpp/cb.cpp" <<'EOF'
#include <algorithm>
#include <vector>
struct Ops { int (*open)(int); };
static bool cmpLess(int a, int b) { return a < b; }
static int myOpen(int x) { return x + 1; }
static int lone(int x) { return x; }
void sortAll(std::vector<int>& v) { std::sort(v.begin(), v.end(), cmpLess); }   // @X_SORT
static Ops table = { .open = myOpen };                                            // @X_TABLE
int negString() { const char* s = "lone"; return s[0]; }                         // @X_N1
int negCall() { return lone(1); }                                                 // @X_N2
// @X_N3 a comment that names a function: table = { .open = lone }
using LoneT = decltype(lone);                                                     // @X_N4 unevaluated
namespace ns { int qf(int x) { return x; } }
struct Cls { static int sm(int x) { return x; } };
static int run_q(int (*f)(int)) { return f(1); }
int useQ() { return run_q(ns::qf) + run_q(&Cls::sm); }                           // @X_F2 qualified values (floor)
static int keepX(int v) { return v; }
int negLam() { auto g = [lone = 3]() { return lone; }; return g(); }              // @X_N5 an init-capture named like the function
int negCap(int lone) { auto h = [lone]() { return keepX(lone); }; return h(); }  // @X_N6 a captured parameter
int negFor(std::vector<int>& v) { int s = 0; for (int lone : v) { s += keepX(lone); } return s; }   // @X_N7 a range-for variable
EOF

# Controls: direct calls only — no answer here may carry a value-reference attribute, row or legend clause.
cat >"$FX/ctl/ctl.c" <<'EOF'
static int helper(int x) { return x + 1; }
static int dead_one(int x) { return x; }
int caller(int x) { return helper(x); }
EOF
cat >"$FX/ctl/ctl.py" <<'EOF'
def py_helper(x):
    return x + 1


def py_caller(x):
    return py_helper(x)
EOF
cat >"$FX/ctl/ctl.js" <<'EOF'
function jsHelper(x) { return x + 1; }
function jsCaller(x) { return jsHelper(x); }
EOF

# Runaway guard: one function stored 300 times. The count stays whole; the rows are capped and the cut disclosed.
python3 - "$FX/big/big.c" <<'EOF'
import sys
lines = [ "static int hot(int x) { return x; }", "static int (*many[])(int) = {" ]
lines += [ "    hot," ] * 300
lines += [ "};", "int use_many(int i) { return many[i](i); }" ]
open( sys.argv[1], "w" ).write( "\n".join( lines ) + "\n" )
EOF

# ── sibling-shape fixtures (early gates review §2) ──────────────────────────────────────────────────────
mkdir -p "$FX/c2" "$FX/js2" "$FX/jsm" "$FX/jsx" "$FX/tsx" "$FX/py2" "$FX/pyi" "$FX/cx" "$FX/dead"

cat >"$FX/c2/sib.c" <<'EOF'
#define REG(f) ((void)(f))
#define H_ALIAS macro_alias_fn                                         /* @C2_DEFINE F5: a macro body is opaque */
static int macro_arg_fn(int x) { return x; }
static int macro_alias_fn(int x) { return x; }
static int my_bound(int x) { return x; }
static int ret_fn(int x) { return x; }
static int cmp_fn(int x) { return x; }
static int lone(int x) { return x; }
static int keep(int v) { return v; }
int use_reg(void) { REG(macro_arg_fn); return 0; }                    /* @C2_REG */
int use_fp(void) { int (*f)(int) = my_bound; return f(1); }           /* @C2_FP an existing fn-pointer binding */
int (*pick(void))(int) { return ret_fn; }                             /* @C2_RET */
int is_cmp(int (*cb)(int)) { return cb == cmp_fn; }                   /* @C2_CMP */
int neg_param(int lone) { return keep(lone); }                        /* @C2_N1 a parameter named like the function */
int neg_sizeof(void) { return (int)sizeof(lone); }                    /* @C2_N2 unevaluated */
#ifdef lone
int neg_ifdef(void) { return 0; }                                     /* @C2_N3 */
#endif
#if defined(lone)
int neg_ifdefined(void) { return 0; }                                 /* @C2_N4 */
#endif
int neg_call(void) { return lone(1); }
EOF

cat >"$FX/js2/sib.js" <<'EOF'
function sibFn(x) { return x; }
function defFn(x) { return x; }
function retFn(x) { return x; }
function ternA(x) { return x; }
function ternB(x) { return x; }
function cmpFn(x) { return x; }
function keyFn(x) { return x; }
function lone2(x) { return x; }
function cjsA(x) { return x; }
function cjsB(x) { return x; }
function run2(cb = defFn) { return cb(1); }                                    // @J2_DEF
function pick() { return retFn; }                                              // @J2_RET
const chosen = Math.random() > 0.5 ? ternA : ternB;                            // @J2_TERN
function isCmp(cb) { return cb === cmpFn; }                                    // @J2_CMP
const keyed = { [keyFn]: 1 };                                                  // @J2_KEY
const arrowShadow = (sibFn) => run2(sibFn);                                    // @J2_N1 arrow parameter
function destr(o) { const { sibFn } = o; return run2(sibFn); }                 // @J2_N2 destructuring
function caught() { try { return 1; } catch (sibFn) { return run2(sibFn); } }  // @J2_N3 catch parameter
function reflect() { return lone2.name; }                                      // @J2_F4A
function bound() { return run2(lone2.bind(null)); }                            // @J2_F4B
function viaCall() { return lone2.call(null, 1); }                             // @J2_F4C
module.exports.cjsA = cjsA;                                                    // @J2_CJSA
exports.cjsB = cjsB;                                                           // @J2_CJSB
EOF

cat >"$FX/jsm/a.js" <<'EOF'
export function impFn(x) { return x; }
export function aliasFn(x) { return x; }
function esOnly(x) { return x; }
function esDefault(x) { return x; }
export { esOnly };                 // @JM_EXPORT an ES export clause: not a row
export default esDefault;          // @JM_DEFAULT not a row
EOF
cat >"$FX/jsm/b.js" <<'EOF'
import { impFn, aliasFn as af } from './a.js';   // @JM_IMPORT not a row
const { reqFn } = require('./c.js');              // @JM_REQUIRE not a row
export const TABLE = [impFn, af, reqFn];          // @JM_TABLE
EOF
cat >"$FX/jsm/c.js" <<'EOF'
function reqFn(x) { return x; }
module.exports = { reqFn };        // @JM_CJS
EOF
# The import rule's near misses: the imported module exports a NON-function of that name while another directory's
# same-STEM module defines a function of it; and a bare package specifier whose name an in-tree file happens to define.
mkdir -p "$FX/jsm/other" "$FX/jsm/pkgs"
cat >"$FX/jsm/d.js" <<'EOF'
export const notFn = 1;
EOF
cat >"$FX/jsm/other/d.js" <<'EOF'
export function notFn(x) { return x; }
EOF
cat >"$FX/jsm/pkgs/lodashish.js" <<'EOF'
export function pkgFn(x) { return x; }
EOF
cat >"$FX/jsm/e.js" <<'EOF'
import { notFn } from './d.js';     // d.js's notFn is a const
import { pkgFn } from 'lodashish';  // a bare package specifier: outside the tree, whatever an in-tree file defines
export const USES = [notFn, pkgFn]; // @JM_NEAR
EOF

cat >"$FX/jsx/App.jsx" <<'EOF'
function handleClick(e) { return e; }
function handleArrow(e) { return e; }
function handleNow(e) { return e; }
function Lone() { return null; }
export function App() {
  return (
    <div>
      <button onClick={handleClick}>a</button>{/* @JX_CLICK */}
      <button onClick={() => handleArrow(1)}>b</button>{/* @JX_ARROW */}
      <button onClick={handleNow()}>c</button>{/* @JX_NOW */}
      <Lone />{/* @JX_LONE */}
    </div>
  );
}
EOF
cat >"$FX/tsx/App.tsx" <<'EOF'
export function handleClickT(e: unknown) { return e; }
export function AppT() {
  return <button onClick={handleClickT}>a</button>;   // @TX_CLICK
}
EOF

cat >"$FX/py2/sib.py" <<'EOF'
def sib_fn(x):
    return x


def dflt_fn(x):
    return x


def ret_fn(x):
    return x


def tern_a(x):
    return x


def tern_b(x):
    return x


def cmp_fn(x):
    return x


def key_fn(x):
    return x


def lone2(x):
    return x


def keep(v):
    return v


def deco_a(f):
    return f


def deco_b(f):
    return f


def app_route(path):
    def wrap(f):
        return f
    return wrap


def run_d(cb=dflt_fn):  # @P2_DEF
    return cb(1)


def pick():
    return ret_fn  # @P2_RET


CHOSEN = tern_a if len(__name__) > 3 else tern_b  # @P2_TERN


def is_cmp(cb):
    return cb is cmp_fn  # @P2_CMP


KEYED = {key_fn: 1}  # @P2_KEY


@app_route("/x")  # @P2_DECO_ARGS
def routed():
    return 1


@deco_a  # @P2_STACK_A
@deco_b  # @P2_STACK_B
def stacked():
    return 2


class Holder:
    @property  # @P2_PROP
    def prop_m(self):
        return 3


def neg_for(xs):
    for sib_fn in xs:
        keep(sib_fn)  # @P2_N1 a for-loop target


def neg_comp(xs):
    return [keep(sib_fn) for sib_fn in xs]  # @P2_N2 a comprehension variable


def neg_lambda():
    return lambda sib_fn: keep(sib_fn)  # @P2_N3 a lambda parameter


def neg_annot(x: lone2) -> lone2:  # @P2_N4 annotations
    return x


def neg_reflect():
    return lone2.__name__  # @P2_F4
EOF

cat >"$FX/pyi/handlers_mod.py" <<'EOF'
def imp_fn(req):
    return req


def alias_fn(req):
    return req
EOF
cat >"$FX/pyi/uses_import.py" <<'EOF'
from handlers_mod import imp_fn, alias_fn as af  # @PI_IMPORT not a row
from consts_mod import pv

IMPORTED = [imp_fn]  # @PI_TABLE
ALIASED = [af]  # @PI_ALIAS F3
NEAR = [pv]  # @PI_NEAR consts_mod.pv is a module variable
EOF
cat >"$FX/pyi/consts_mod.py" <<'EOF'
pv = 1
EOF
mkdir -p "$FX/pyi/elsewhere"
cat >"$FX/pyi/elsewhere/consts_mod.py" <<'EOF'
def pv():
    return 2
EOF

# Cross-file, linkage and cross-language collisions (review fix 3).
cat >"$FX/cx/a.c" <<'EOF'
static int handler_a(int x) { return x; }
static int stored(int x) { return x; }
static int (*tbl[])(int) = { stored };          /* @CXA_TBL */
int use_tbl(int i) { return tbl[i](i); }
int ext_fn(int x) { return x; }                 /* external linkage: other files may name it */
int far_fn(int x) { return x; }                 /* external linkage, named from c.c through a prototype */
EOF
cat >"$FX/cx/c.c" <<'EOF'
int far_fn(int);                                /* a PROTOTYPE declares a function: it hides nothing */
int (*proto_tbl[])(int) = { far_fn };           /* @CXC_PROTO */
EOF
cat >"$FX/cx/b.c" <<'EOF'
static int stored = 7;                          /* a non-function global named like a.c's static function */
static int keep_b(int v) { return v; }
int use_var(void) { return keep_b(stored); }    /* @CXB_VAR the variable, not a.c's function */
int (*far[])(int) = { handler_a };              /* @CXB_FAR a.c's handler_a is static: unreachable from here */
static int ext_fn = 7;                          /* a file-scope OBJECT hiding a.c's extern function inside b.c */
int use_ext(void) { return keep_b(ext_fn); }    /* @CXB_EXT the object, not a.c's function */
EOF
cat >"$FX/cx/x.py" <<'EOF'
XS = [handler_a, stored]  # @CXP_X another language
EOF
cat >"$FX/cx/fa.js" <<'EOF'
function jsVal(x) { return x; }
const JT = [jsVal];  // @CXJ_A
module.exports = { JT };
EOF
cat >"$FX/cx/fb.js" <<'EOF'
const jsVal = 3;
const JB = [jsVal];  // @CXJ_B a file-scope non-function named like fa.js's function
module.exports = { JB };
EOF
cat >"$FX/cx/pa.py" <<'EOF'
def py_val(x):
    return x


PT = [py_val]  # @CXQ_A
EOF
cat >"$FX/cx/pb.py" <<'EOF'
py_val = 3
PB = [py_val]  # @CXQ_B a module-level non-function named like pa.py's function
EOF

# --dead-code: one entity, one reason (review fix 9).
cat >"$FX/dead/p.py" <<'EOF'
def app_route(fn):
    return fn


@app_route
def handler(static=3):  # decorated AND a decorator value use: counted in decorated-excluded= only
    return static


def tabled(static=4):  # a value use only: value-ref-excluded=
    return static


TABLE = [tabled]


def orphan(static=5):  # neither: still listed
    return static
EOF
cat >"$FX/dead/r.cpp" <<'EOF'
#include <cstdio>
static void BM_x(int s) { std::printf("%d", s); }
BENCHMARK(BM_x);
TEST_CASE( "the static case stays registered" )
{
    std::printf("case");
}
static void reg_only(int s) { std::printf("%d", s); }
static int dummy = (register_fn(reg_only), 0);
static void truly_dead_cpp() { std::printf("x"); }
EOF

# Class MEMBERS are never in bare-name scope outside their class (final review R1, the real near misses it measured:
# django `isinstance( x, (list, tuple) )` beside methods named list/tuple, a sibling method as `key=`, a C++ data member
# vs another class's member function, webpack `: require` / a file-scope `let source` beside class methods).
mkdir -p "$FX/pymem" "$FX/cppmem" "$FX/jsmem"
cat >"$FX/pymem/m.py" <<'EOF'
class Finder:
    def list(self, ignore_patterns):
        return ignore_patterns


class Envelope:
    def tuple(self):
        return ()


def classify(root):
    return isinstance(root, (list, tuple))  # @PM_ISINSTANCE the builtins, never a method of that name


class Sorter:
    def keyfn(self, x):
        return x

    def sort(self, xs):
        return sorted(xs, key=keyfn)  # @PM_SIBLING a sibling method is not in bare scope (a NameError)

    def render(self):
        return 1

    __str__ = render  # @PM_CLASSBODY the class body DOES see its members


class Pipeline:
    def run(self, xs):
        def step(x):
            return x
        return sorted(map(step, xs))  # @PM_NESTED a def nested in a method is that method's local, not a member
EOF
cat >"$FX/cppmem/m.cpp" <<'EOF'
#include <algorithm>
#include <cstring>
#include <vector>
struct Vec { int buf[4]; int* data() { return buf; } };
struct FixedStr {
    char data[16];
    void set(const char* s) { std::memcpy( data, s, 15 ); }                       // @XM_DATA the member array, never Vec::data()
};
static int keepX(int v) { return v; }
static int count(int x) { return x; }
struct Counter {
    int count = 0;
    int get() const { return keepX(count); }                                       // @XM_FIELD the data member shadows the free count
};
struct Sorter {
    static bool lessThan(int a, int b) { return a < b; }
    void sortAll(std::vector<int>& v) { std::sort(v.begin(), v.end(), lessThan); } // @XM_SAME a member of the SAME class is in scope
};
int useCount() { return count(1); }
static int total(int x) { return x; }
struct Late {
    int get() const { return keepX(total); }                                       // @XM_LATE a member declared BELOW is in scope
    int total = 0;
};
int useTotal() { return total(2); }
EOF
cat >"$FX/jsmem/m.js" <<'EOF'
class Runner {
  require(m) { return m; }
  source(n) { return n; }
}
let source = "text";                       // a file-scope binding named like the method
const api = { load: require };             // @JSM_REQUIRE the global require, never Runner#require
function useSource() { return [source]; }  // @JSM_SOURCE the file-scope let, never Runner#source
module.exports = { api, useSource, Runner };
EOF

# ── the checker ──────────────────────────────────────────────────────────────────────────────────────────
cat >"$TMP/chk.py" <<'EOF'
# chk.py DIR OUTFILE TOKEN... — asserts on one XML answer. Prints "OK" or one line per failed token, then a
# context line (the root's count/value_refs/graph_unresolved…) so a RED run documents the false completeness.
#   attr:NAME=VAL  attr:NAME!=VAL  noattr:NAME          (the root element)
#   el:TAG:NAME=VAL  noel:TAG                           (the first descendant TAG, e.g. the <vrs> window)
#   vr:k=v;k=v     novr:k=v;...    nvr:N                (the same for u: / d: / s: rows; nu: nd: ns: counts)
#   legend:TEXT    nolegend:TEXT                        (the answer's leading comment)
# A row value @MARK resolves to "relpath:line" of the fixture line carrying the marker; "-" means the attribute
# must be ABSENT on that row. EVERY answer is also checked structurally: a <vr> row may carry only the attributes
# in VR_ATTRS, so no existing gate's n=/p=/t= grep can ever match one (early gates review, fix 1).
import os, re, sys
import xml.etree.ElementTree as ET
VR_ATTRS = { "in_id", "bind", "into", "called_by", "to", "def", "through", "sites" }
fxdir, outfile, toks = sys.argv[1], sys.argv[2], sys.argv[3:]
text = open( outfile, encoding="utf-8", errors="replace" ).read()
marks = {}
for dp, _, fs in os.walk( fxdir ):
    for f in fs:
        p = os.path.join( dp, f )
        rel = os.path.relpath( p, fxdir )
        try:
            for i, line in enumerate( open( p, encoding="utf-8", errors="replace" ), 1 ):
                for m in re.finditer( r"@([A-Z][A-Z0-9_]*)\b", line ):
                    marks.setdefault( m.group( 1 ), "%s:%d" % ( rel, i ) )
        except OSError:
            pass
def val( v ):
    if re.fullmatch( r"@[A-Z][A-Z0-9_]*", v ):   # a marker; "@register" (a decorator slot) is a literal value
        if v[1:] not in marks:
            raise SystemExit( "chk.py: unknown marker " + v )
        return marks[v[1:]]
    return v
fails = []
m = re.search( r"<!--(.*?)-->", text, re.S )
legend = m.group( 1 ) if m else ""
body = re.sub( r"<!--.*?-->", "", text, flags=re.S ).strip()
try:
    root = ET.fromstring( body )
except ET.ParseError as e:
    print( "FAIL not parseable XML (%s): %s" % ( e, body[:300] ) )
    raise SystemExit( 0 )
def rows( tag ):
    return [ el.attrib for el in root.iter( tag ) ]
for r in rows( "vr" ):
    extra = sorted( set( r ) - VR_ATTRS )
    if extra:
        fails.append( "<vr> carries attribute(s) outside the non-colliding set: %s" % ",".join( extra ) )
        break
def matches( row, spec ):
    for kv in spec.split( ";" ):
        k, _, v = kv.partition( "=" )
        v = val( v )
        if v == "-":
            if k in row:
                return False
        elif row.get( k ) != v:
            return False
    return True
def shown( spec ):
    return ";".join( k + "=" + val( v ) for k, _, v in ( kv.partition( "=" ) for kv in spec.split( ";" ) ) )
for t in toks:
    kind, _, spec = t.partition( ":" )
    if kind == "attr":
        if "!=" in spec:
            k, v = spec.split( "!=", 1 )
            if root.get( k ) is None or root.get( k ) == v:
                fails.append( "%s=%r (want present and != %r)" % ( k, root.get( k ), v ) )
        else:
            k, v = spec.split( "=", 1 )
            if root.get( k ) != v:
                fails.append( "%s=%r (want %r)" % ( k, root.get( k ), v ) )
    elif kind == "noattr":
        if spec in root.attrib:
            fails.append( "%s=%r present (want absent)" % ( spec, root.get( spec ) ) )
    elif kind == "el":
        tag, _, kv = spec.partition( ":" )
        k, _, v = kv.partition( "=" )
        el = next( iter( root.iter( tag ) ), None )
        if el is None:
            fails.append( "no <%s> element (want %s=%r)" % ( tag, k, v ) )
        elif el.get( k ) != v:
            fails.append( "<%s> %s=%r (want %r)" % ( tag, k, el.get( k ), v ) )
    elif kind == "noel":
        if next( iter( root.iter( spec ) ), None ) is not None:
            fails.append( "unwanted <%s> element" % spec )
    elif kind in ( "vr", "u", "d", "s" ):
        if not any( matches( r, spec ) for r in rows( kind ) ):
            fails.append( "no <%s> row matching %s" % ( kind, shown( spec ) ) )
    elif kind in ( "novr", "nou", "nod", "nos" ):
        tag = kind[2:]
        hit = [ r for r in rows( tag ) if matches( r, spec ) ]
        if hit:
            fails.append( "unwanted <%s> row %r" % ( tag, hit[0] ) )
    elif kind in ( "nvr", "nu", "nd", "ns" ):
        tag = kind[1:]
        if not spec.isdigit():
            raise SystemExit( "chk.py: non-numeric count token " + t )
        n = len( rows( tag ) )
        if n != int( spec ):
            fails.append( "%d <%s> rows (want %s)" % ( n, tag, spec ) )
    elif kind == "legend":
        if spec not in legend:
            fails.append( "legend lacks %r" % spec )
    elif kind == "nolegend":
        if spec in legend:
            fails.append( "legend has %r (want absent)" % spec )
    else:
        raise SystemExit( "chk.py: unknown token " + t )
if fails:
    ctx = " ".join( "%s=%s" % ( k, root.get( k ) ) for k in ( "count", "reaches", "value_refs", "graph_unresolved", "uses", "risk", "dead_code_candidate" ) if root.get( k ) is not None )
    print( "FAIL " + " | ".join( fails ) + "   [answer: <%s %s>]" % ( root.tag, ctx ) )
else:
    print( "OK" )
EOF

if [ -n "${RECALLSHAPE_FX_OUT:-}" ]; then rm -rf "$RECALLSHAPE_FX_OUT" && cp -R "$FX" "$RECALLSHAPE_FX_OUT"; fi

# arm LABEL FIXDIR ARGV TOKEN... — run one CLI answer (fresh index) and check it. rc 1 is accepted (a not-found
# answer exits 1), so every arm also carries at least one PRESENCE token (review fix 7).
n=0
run_check() {   # run_check LABEL CHKDIR OUT TOKEN...
    local label="$1" chkdir="$2" out="$3"; shift 3
    [ -s "$out" ] || { no "$label — empty answer"; return; }
    local res; res="$( python3 "$TMP/chk.py" "$chkdir" "$out" "$@" 2>&1 )"
    verdict "$label" "$res"
}
arm() {
    local label="$1" dir="$2" argv="$3"; shift 3
    n=$(( n + 1 ))
    local out="$TMP/out.$n.xml"
    ( cd "$FX/$dir" && "$BIN" . $argv --no-cache --legend=compact >"$out" 2>"$out.err" )
    local rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then no "$label — ripwire exited $rc on: $argv ($(head -c 200 "$out.err"))"; return; fi
    run_check "$label" "$FX/$dir" "$out" "$@"
}
arm_roots() {   # arm_roots LABEL "ROOT ROOT…" ARGV TOKEN… — a multi-root run from $FX (CodeRabbit class 13a)
    local label="$1" roots="$2" argv="$3"; shift 3
    n=$(( n + 1 ))
    local out="$TMP/out.$n.xml"
    ( cd "$FX" && "$BIN" $roots $argv --no-cache --legend=compact >"$out" 2>"$out.err" )
    local rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then no "$label — ripwire exited $rc on: $roots $argv"; return; fi
    run_check "$label" "$FX" "$out" "$@"
}

# ── C: struct-field initialisers, designated and positional, a function-pointer array, callbacks, assignment ──
echo "-- C"
arm "C1 callers my_open: count stays 0 (calls), value_refs=3 at the global table, the positional initialiser and a local literal" \
    c --callers=my_open attr:count=0 attr:value_refs=3 nvr:3 el:vrs:total=3 el:vrs:shown=3 el:vrs:capped=0 \
    'vr:bind=@C_TABLE;into=table.open;called_by=-' 'vr:bind=@C_POS;into=positional[0];called_by=-' \
    'vr:bind=@C_LIT;into=o.open;in_id=use_literal;called_by=use_literal'
arm "C2 callers my_close: table.close is called through in use_global only (shadow_tbl's local table is another declaration)" \
    c --callers=my_close attr:count=0 attr:value_refs=3 nvr:3 \
    'vr:bind=@C_TABLE;into=table.close;called_by=use_global' 'vr:bind=@C_POS;into=positional[1]' 'vr:bind=@C_LIT;into=o.close;called_by=-'
arm "C3 callers other_open: fn-pointer array element 0 (called through fns[0]) and a field assignment through a parameter" \
    c --callers=other_open attr:count=0 attr:value_refs=2 nvr:2 \
    'vr:bind=@C_FNS;into=fns[0];called_by=use_global' 'vr:bind=@C_ASSIGN;into=p->open;in_id=use_assign;called_by=-'
arm "C4 callers on_tick: &fn in an array and as an argument; run calls its parameter 0" \
    c --callers=on_tick attr:count=0 attr:value_refs=2 nvr:2 'vr:bind=@C_FNS;into=fns[1]' 'vr:bind=@C_CB;into=run#arg0;in_id=use_callback;called_by=run'
arm "C5 callers on_event: the callback argument; NOT the same-named local in neg_shadow" \
    c --callers=on_event attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@C_CB;into=run#arg0;called_by=run' 'novr:bind=@C_N3'
arm "C6 callees use_literal: the two stored functions; my_open is called through o.open" \
    c --callees=use_literal attr:count=0 attr:value_refs=2 nvr:2 \
    'vr:to=my_open;bind=@C_LIT;into=o.open;through=o.open' 'vr:to=my_close;bind=@C_LIT;into=o.close;through=-'
arm "C7 callees use_global: table.close and fns[0] resolve through their file-scope tables" \
    c --callees=use_global attr:count=0 attr:value_refs=2 nvr:2 \
    'vr:to=my_close;bind=@C_TABLE;through=table.close' 'vr:to=other_open;bind=@C_FNS;through=fns[0]'
arm "C8 callees run: a call through parameter cb lists what was passed in as argument 0" \
    c --callees=run attr:count=0 attr:value_refs=2 nvr:2 'vr:to=on_event;bind=@C_CB;through=cb' 'vr:to=on_tick;bind=@C_CB;through=cb'
arm "C9 callees use_callback: the call to run stays a call row; the two passed functions are value rows" \
    c --callees=use_callback attr:count=1 ns:1 's:n=run' attr:value_refs=2 nvr:2 'vr:to=on_event;through=-' 'vr:to=on_tick;through=-'
arm "C10 impact my_open: reaches stays a call radius (0); value_refs=3 is disclosed beside it" \
    c --impact=my_open attr:reaches=0 attr:value_refs=3 nvr:3 'vr:bind=@C_TABLE;into=table.open'
arm "C11 safe-delete my_open: callers stays 0; the three value sites are uses; not a dead-code candidate; risk=uses-exist" \
    c --safe-delete=my_open attr:callers=0 attr:impact_reaches=0 attr:uses=3 attr:value_refs=3 attr:dead_code_candidate=0 attr:risk=uses-exist
arm "C12 dead-code: the five value-referenced statics are excluded and counted; truly_dead is still listed" \
    c --dead-code attr:count=1 nd:1 'd:n=truly_dead' 'nod:n=my_open' 'nod:n=on_event' attr:value-ref-excluded=5
arm "C13 uses my_open: the three binding sites are role=value use-sites" \
    c --uses=my_open attr:count=3 nu:3 'u:role=value;p=@C_TABLE' 'u:role=value;p=@C_POS' 'u:role=value;p=@C_LIT'
arm "C14 path use_callback→on_event: no directed CALL path, and the target's value references are disclosed" \
    c --path=use_callback,on_event attr:reachable=0 attr:to_value_refs=1
arm "C15 negatives: lone (named in a comment, a string and a designated FIELD name) has its one call and no value row" \
    c --callers=lone attr:count=1 ns:1 's:n=neg_call' noattr:value_refs nvr:0 noel:vrs
arm "C16 tier-B shadow: shadow_tbl calls its OWN local table.close — no through row" \
    c --callees=shadow_tbl attr:count=0 noattr:value_refs nvr:0
arm "C17 uses lone: no role=value row (its one call stays role=call)" \
    c --uses=lone attr:count=1 'u:role=call;in_id=neg_call' 'nou:role=value'
arm "C18 safe-delete lone: a function named in a comment/string/field is judged on its call alone" \
    c --safe-delete=lone attr:callers=1 noattr:value_refs
arm "F1 floor: a call through a typed parameter's field (p->open) names no container — use_ptr stays silent" \
    c --callees=use_ptr attr:count=0 noattr:value_refs nvr:0

echo "-- C siblings"
arm "C2a callers macro_arg_fn: a macro ARGUMENT is an argument (REG#arg0)" \
    c2 --callers=macro_arg_fn attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@C2_REG;into=REG#arg0;in_id=use_reg'
arm "F5 floor: a macro BODY (#define H_ALIAS macro_alias_fn) is opaque — no row" \
    c2 --callers=macro_alias_fn attr:count=0 noattr:value_refs nvr:0
arm "C2c callers my_bound: an existing fn-pointer binding keeps its ONE call row; the binding site adds one value row, never a second count" \
    c2 --callers=my_bound attr:count=1 ns:1 's:n=use_fp' attr:value_refs=1 nvr:1 'vr:bind=@C2_FP;into=f;in_id=use_fp;called_by=use_fp'
arm "C2d callers ret_fn: a returned function value lands in (return)" \
    c2 --callers=ret_fn attr:count=0 attr:value_refs=1 'vr:bind=@C2_RET;into=(return);in_id=pick'
arm "C2e callers cmp_fn: a compared function value lands in (compare)" \
    c2 --callers=cmp_fn attr:count=0 attr:value_refs=1 'vr:bind=@C2_CMP;into=(compare);in_id=is_cmp'
arm "C2f negatives: lone (a parameter of the same name, sizeof, #ifdef, #if defined) has its one call and no value row" \
    c2 --callers=lone attr:count=1 ns:1 noattr:value_refs nvr:0
arm "C2g uses lone (siblings): no role=value row" c2 --uses=lone 'u:role=call' 'nou:role=value'

# ── C/JS/Python: cross-file names, C static linkage, cross-language (review fix 3) ───────────────────────
echo "-- cross-file / linkage / cross-language"
arm "CX1 callers a.c:handler_a: b.c cannot see a static function and x.py is another language — no value row" \
    cx --callers=a.c:handler_a attr:count=0 noattr:value_refs nvr:0
arm "CX2 callers a.c:stored: its own table only — not b.c's same-named variable, not x.py" \
    cx --callers=a.c:stored attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@CXA_TBL;into=tbl[0]' 'novr:bind=@CXB_VAR' 'novr:bind=@CXP_X'
arm "CX3a dead-code (negative): handler_a stays listed — a by-name collision elsewhere never hides a dead static" \
    cx --dead-code 'd:n=handler_a' noattr:decorated-excluded
arm "CX3b dead-code: stored (in its own file's table) is excluded and counted" \
    cx --dead-code attr:count=1 nd:1 'nod:n=stored' attr:value-ref-excluded=1
arm "CX4 callers fa.js:jsVal: not fb.js's same-named const" \
    cx --callers=fa.js:jsVal attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@CXJ_A;into=JT[0]' 'novr:bind=@CXJ_B'
arm "CX5 callers pa.py:py_val: not pb.py's same-named module variable" \
    cx --callers=pa.py:py_val attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@CXQ_A;into=PT[0]' 'novr:bind=@CXQ_B'
arm "CX7 callers a.c:ext_fn: an extern function is hidden in b.c by b.c's own file-scope object of that name — no row" \
    cx --callers=a.c:ext_fn attr:count=0 noattr:value_refs nvr:0 'novr:bind=@CXB_EXT'
arm "CX8 callers a.c:far_fn: an extern function named through a prototype in c.c is a row (the prototype hides nothing)" \
    cx --callers=a.c:far_fn attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@CXC_PROTO;into=proto_tbl[0]'
arm "CX6 safe-delete a.c:handler_a: still a dead-code candidate with risk=none-found" \
    cx --safe-delete=a.c:handler_a attr:callers=0 attr:dead_code_candidate=1 attr:risk=none-found noattr:value_refs

# ── --dead-code: one entity, one reason (review fix 9) ─────────────────────────────────────────────────
echo "-- dead-code precedence"
arm "DC1a dead-code (negative): orphan and truly_dead_cpp stay listed; the decorated handler stays in decorated-excluded=1; the TEST_CASE in register-macro-excluded=1" \
    dead --dead-code 'd:n=orphan' 'd:n=truly_dead_cpp' 'nod:n=handler' attr:decorated-excluded=1 attr:register-macro-excluded=1
arm "DC1b dead-code: tabled, BM_x (BENCHMARK arg), reg_only counted ONCE in value-ref-excluded=3 — the decorated handler is not counted again" \
    dead --dead-code attr:count=2 nd:2 'nod:n=tabled' 'nod:n=BM_x' 'nod:n=reg_only' attr:value-ref-excluded=3 attr:decorated-excluded=1

# ── JS: object-literal tables (pair, shorthand, array), computed and dotted dispatch, callbacks, CJS exports ──
echo "-- JavaScript"
arm "J1 callers fooGet: the table pair (called through in dispatch and dispatchDot, not shadowHandlers) and the array element" \
    js --callers=fooGet attr:count=0 attr:value_refs=2 nvr:2 \
    'vr:bind=@J_TABLE;into=handlers.get;called_by=dispatch,dispatchDot' 'vr:bind=@J_LIST;into=list[0];called_by=-'
arm "J2 callers fooPost: handlers.post only — NOT negShadow's same-named parameter" \
    js --callers=fooPost attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@J_TABLE;into=handlers.post;called_by=dispatch' 'novr:bind=@J_N3'
arm "J3 callers fooDel: shorthand property and array element" \
    js --callers=fooDel attr:count=0 attr:value_refs=2 nvr:2 'vr:bind=@J_SHORT;into=short.fooDel' 'vr:bind=@J_LIST;into=list[1]'
arm "J4 callers onEvent: three callbacks (run, xs.map, bus.on); only run's is called through" \
    js --callers=onEvent attr:count=0 attr:value_refs=3 nvr:3 \
    'vr:bind=@J_RUN;into=run#arg0;in_id=useCallbacks;called_by=run' 'vr:bind=@J_MAP;into=xs.map#arg0;called_by=-' 'vr:bind=@J_ON;into=bus.on#arg1;called_by=-'
arm "J5 callers onClick: an addEventListener handler" \
    js --callers=onClick attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@J_ADD;into=el.addEventListener#arg1'
arm "J6 callers dispatch: the CommonJS export table is a value use" \
    js --callers=dispatch attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@J_EXPORTS;into=module.exports.dispatch'
arm "J7 callees dispatch: handlers[kind](req) may call every function value in handlers" \
    js --callees=dispatch attr:count=0 attr:value_refs=2 nvr:2 'vr:to=fooGet;through=handlers[kind]' 'vr:to=fooPost;through=handlers[kind]'
arm "J8 callees dispatchDot: handlers.get(req) reaches the get slot only" \
    js --callees=dispatchDot attr:count=0 attr:value_refs=1 nvr:1 'vr:to=fooGet;bind=@J_TABLE;through=handlers.get'
arm "J9 callees run: a call through parameter cb lists the one function passed in (not obj.lone)" \
    js --callees=run attr:count=0 attr:value_refs=1 nvr:1 'vr:to=onEvent;bind=@J_RUN;through=cb'
arm "J10 callees dispatchPut: the method-shorthand call stays one call row and adds no value row" \
    js --callees=dispatchPut attr:count=1 ns:1 's:n=put' noattr:value_refs nvr:0
arm "J11 negatives: lone (comment, string, object KEY, obj.lone member) has its one call and no value row" \
    js --callers=lone attr:count=1 ns:1 's:n=negCall' noattr:value_refs nvr:0
arm "J12 tier-B shadow: shadowHandlers calls its PARAMETER handlers.get — no through row" \
    js --callees=shadowHandlers attr:count=0 noattr:value_refs nvr:0
arm "J13 uses lone: no role=value row" js --uses=lone 'u:role=call' 'nou:role=value'
arm "J14 safe-delete lone: judged on its call alone" js --safe-delete=lone attr:callers=1 noattr:value_refs

echo "-- JavaScript siblings"
arm "J2a callers defFn: a parameter default (run2#cb), called through by run2" \
    js2 --callers=defFn attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@J2_DEF;into=run2#cb;called_by=run2'
arm "J2b callers retFn: (return)" js2 --callers=retFn attr:count=0 attr:value_refs=1 'vr:bind=@J2_RET;into=(return);in_id=pick'
arm "J2c callers ternA: a ternary branch lands in the assignment" js2 --callers=ternA attr:count=0 attr:value_refs=1 'vr:bind=@J2_TERN;into=chosen'
arm "J2d callers ternB: the other ternary branch" js2 --callers=ternB attr:count=0 attr:value_refs=1 'vr:bind=@J2_TERN;into=chosen'
arm "J2e callers cmpFn: (compare)" js2 --callers=cmpFn attr:count=0 attr:value_refs=1 'vr:bind=@J2_CMP;into=(compare);in_id=isCmp'
arm "J2f callers keyFn: a computed KEY is a value use (keyed{})" js2 --callers=keyFn attr:count=0 attr:value_refs=1 'vr:bind=@J2_KEY;into=keyed{}'
arm "J2g negatives: sibFn shadowed by an arrow parameter, a destructured const and a catch parameter — no row" \
    js2 --callers=sibFn attr:count=0 noattr:value_refs nvr:0
arm "F4 floor (JS): lone2 as the object of .name / .bind / .call — no row" js2 --callers=lone2 attr:defs=1 noattr:value_refs nvr:0
arm "J2i callers cjsA: module.exports.cjsA = cjsA" js2 --callers=cjsA attr:count=0 attr:value_refs=1 'vr:bind=@J2_CJSA;into=module.exports.cjsA'
arm "J2j callers cjsB: exports.cjsB = cjsB" js2 --callers=cjsB attr:count=0 attr:value_refs=1 'vr:bind=@J2_CJSB;into=exports.cjsB'

echo "-- JavaScript modules"
arm "JM1 callers impFn: a named ES import used as a value (b.js TABLE[0]); the import statement is no row" \
    jsm --callers=impFn attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@JM_TABLE;into=TABLE[0]' 'novr:bind=@JM_IMPORT'
arm "F3 floor (JS): aliasFn spelled af — no row" jsm --callers=aliasFn attr:defs=1 noattr:value_refs nvr:0
arm "JM3 callers reqFn: the CommonJS export row only — a destructured require binding is F3" \
    jsm --callers=reqFn attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@JM_CJS;into=module.exports.reqFn' 'novr:bind=@JM_TABLE' 'novr:bind=@JM_REQUIRE'
arm "JM4 negatives: an ES export clause is no row" jsm --callers=esOnly attr:defs=1 noattr:value_refs nvr:0
arm "JM6 negatives: an import of a module whose same-named export is a CONST never reaches another directory's same-stem function" \
    jsm --callers=other/d.js:notFn attr:defs=1 noattr:value_refs nvr:0 'novr:bind=@JM_NEAR'
arm "JM7 negatives: a bare package specifier resolves to no in-tree file, whatever a tree file defines" \
    jsm --callers=pkgFn attr:defs=1 noattr:value_refs nvr:0
arm "JM5 negatives: export default is no row" jsm --callers=esDefault attr:defs=1 noattr:value_refs nvr:0

echo "-- JSX / TSX"
arm "JX1 callers handleClick: onClick={handleClick} (button.onClick)" \
    jsx --callers=handleClick attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@JX_CLICK;into=button.onClick;in_id=App'
arm "JX2 negatives: onClick={() => handleArrow(1)} is a call inside an arrow — no value row" \
    jsx --callers=handleArrow attr:defs=1 noattr:value_refs nvr:0
arm "JX3 negatives: onClick={handleNow()} is a call — no value row" jsx --callers=handleNow attr:defs=1 noattr:value_refs nvr:0
arm "JX4 negatives: <Lone/> stays a component call row (jsxcallcheck's shape), no value row" \
    jsx --callers=Lone attr:count=1 ns:1 noattr:value_refs nvr:0
arm "TX1 callers handleClickT: a TSX onClick={handler}" \
    tsx --callers=handleClickT attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@TX_CLICK;into=button.onClick;in_id=AppT'

# ── TypeScript: a typed Record table, DOM and array callbacks, type positions ────────────────────────────
echo "-- TypeScript"
arm "T1 callers fooGet: the typed Record table pair, called through in dispatch and dispatchDot" \
    ts --callers=fooGet attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@T_TABLE;into=handlers.get;called_by=dispatch,dispatchDot'
arm "T2 callers fooPost: NOT negShadow's typed parameter" \
    ts --callers=fooPost attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@T_TABLE;into=handlers.post' 'novr:bind=@T_N5'
arm "T3 callers onClick: an addEventListener handler" \
    ts --callers=onClick attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@T_ADD;into=el.addEventListener#arg1'
arm "T4 callers onEvent: an xs.map callback" \
    ts --callers=onEvent attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@T_MAP;into=xs.map#arg0'
arm "T5 callees dispatch: handlers[kind] through the Record table" \
    ts --callees=dispatch attr:count=0 attr:value_refs=2 nvr:2 'vr:to=fooGet;through=handlers[kind]' 'vr:to=fooPost;through=handlers[kind]'
arm "T6 negatives: lone (comment, typeof, ReturnType<typeof>, an interface member, a string) has no value row" \
    ts --callers=lone attr:count=1 ns:1 noattr:value_refs nvr:0
arm "T7 uses lone: no role=value row" ts --uses=lone 'u:role=call' 'nou:role=value'

# ── Python: dict and list dispatch, a local table, callbacks, a keyword argument, decorators, an alias ──
echo "-- Python"
arm "P1 callers foo_get: dict value, list element and a local table; each called through where it is (not shadow_dispatch)" \
    py --callers=foo_get attr:count=0 attr:value_refs=3 nvr:3 \
    'vr:bind=@P_DICT;into=DISPATCH["get"];in_id=DISPATCH;called_by=dispatch' 'vr:bind=@P_LIST;into=TABLE[0];called_by=-' \
    'vr:bind=@P_LOCAL;into=table["get"];in_id=dispatch_local;called_by=dispatch_local'
arm "P2 callers foo_post: the dict value only — NOT neg_shadow's same-named parameter" \
    py --callers=foo_post attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@P_DICT;into=DISPATCH["post"];called_by=dispatch' 'novr:bind=@P_N3'
arm "P3 callers on_event: list element and two callbacks — NOT neg_local's same-named local" \
    py --callers=on_event attr:count=0 attr:value_refs=3 nvr:3 'vr:bind=@P_LIST;into=TABLE[1]' \
    'vr:bind=@P_RUN;into=run#arg0;called_by=run' 'vr:bind=@P_MAP;into=map#arg0;called_by=-' 'novr:bind=@P_N4'
arm "P4 callers worker: a keyword-argument value" \
    py --callers=worker attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@P_KW;into=threading.Thread#target'
arm "P5 callers decorated: the decorator receives the function as a value" \
    py --callers=decorated attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@P_DECO;into=@register'
arm "P6 callers handler: an alias assignment" \
    py --callers=handler attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@P_ASSIGN;into=alias'
arm "P7 callees dispatch: DISPATCH[kind](req) may call both dict values" \
    py --callees=dispatch attr:count=0 attr:value_refs=2 nvr:2 'vr:to=foo_get;through=DISPATCH[kind]' 'vr:to=foo_post;through=DISPATCH[kind]'
arm "P8 callees run: a call through parameter cb (not obj.lone)" \
    py --callees=run attr:count=0 attr:value_refs=1 nvr:1 'vr:to=on_event;bind=@P_RUN;through=cb'
arm "P9 uses foo_get: the three sites are role=value (no longer role=read)" \
    py --uses=foo_get attr:count=3 nu:3 'u:role=value;p=@P_DICT' 'u:role=value;p=@P_LIST' 'u:role=value;p=@P_LOCAL' 'nou:role=read'
arm "P9b uses DISPATCH (a non-function): its reads stay role=read" \
    py --uses=DISPATCH 'u:role=read' 'nou:role=value'
arm "P10 negatives: lone (comment, string, keyword LABEL, obj.lone member) has its one call and no value row" \
    py --callers=lone attr:count=1 ns:1 's:n=neg_call' noattr:value_refs nvr:0
arm "P11 tier-B shadow: shadow_dispatch calls its PARAMETER DISPATCH — no through row" \
    py --callees=shadow_dispatch attr:count=0 noattr:value_refs nvr:0
arm "P12 uses lone: no role=value row" py --uses=lone 'u:role=call' 'nou:role=value'
arm "P13 safe-delete lone: judged on its call alone" py --safe-delete=lone attr:callers=1 noattr:value_refs

echo "-- Python siblings"
arm "P2a callers dflt_fn: a parameter default (run_d#cb), called through by run_d" \
    py2 --callers=dflt_fn attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@P2_DEF;into=run_d#cb;called_by=run_d'
arm "P2b callers ret_fn: (return)" py2 --callers=ret_fn attr:count=0 attr:value_refs=1 'vr:bind=@P2_RET;into=(return);in_id=pick'
arm "P2c callers tern_a: a conditional-expression branch lands in the assignment" py2 --callers=tern_a attr:count=0 attr:value_refs=1 'vr:bind=@P2_TERN;into=CHOSEN'
arm "P2c' callers tern_b: the other branch" py2 --callers=tern_b attr:count=0 attr:value_refs=1 'vr:bind=@P2_TERN;into=CHOSEN'
arm "P2d callers cmp_fn: an identity comparison lands in (compare)" py2 --callers=cmp_fn attr:count=0 attr:value_refs=1 'vr:bind=@P2_CMP;into=(compare);in_id=is_cmp'
arm "P2e callers key_fn: a function used as a dict KEY (KEYED{})" py2 --callers=key_fn attr:count=0 attr:value_refs=1 'vr:bind=@P2_KEY;into=KEYED{}'
arm "P2f callers routed: a decorator with arguments (@app_route)" py2 --callers=routed attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@P2_DECO_ARGS;into=@app_route'
arm "P2g callers stacked: two stacked decorators, one row each" \
    py2 --callers=stacked attr:count=0 attr:value_refs=2 nvr:2 'vr:bind=@P2_STACK_A;into=@deco_a' 'vr:bind=@P2_STACK_B;into=@deco_b'
arm "P2h callers prop_m: @property is a decorator like any other (syntactic; not a registration)" \
    py2 --callers=prop_m attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@P2_PROP;into=@property'
arm "P2i negatives: sib_fn shadowed by a for target, a comprehension variable and a lambda parameter — no row" \
    py2 --callers=sib_fn attr:count=0 noattr:value_refs nvr:0
arm "F4 floor (Py) + annotations: lone2 in x: lone2 / -> lone2 and lone2.__name__ — no row" \
    py2 --callers=lone2 attr:count=0 noattr:value_refs nvr:0

echo "-- Python imports"
arm "PI1 callers imp_fn: an imported name used as a value (IMPORTED[0]); the import statement is no row" \
    pyi --callers=imp_fn attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@PI_TABLE;into=IMPORTED[0]' 'novr:bind=@PI_IMPORT'
arm "F3 floor (Py): alias_fn imported as af — no row" pyi --callers=alias_fn attr:defs=1 noattr:value_refs nvr:0
arm "PI3 negatives: an imported module VARIABLE never reaches another package's same-named module function" \
    pyi --callers=elsewhere/consts_mod.py:pv attr:defs=1 noattr:value_refs nvr:0 'novr:bind=@PI_NEAR'

# ── Go: map and struct literals, a slice of funcs, an http handler, a callback ────────────────────────────
echo "-- Go"
arm "G1 callers myOpen: map value (called through in dispatch, not shadowH) and struct field (called through in useOps)" \
    go --callers=myOpen attr:count=0 attr:value_refs=2 nvr:2 \
    'vr:bind=@G_MAP;into=handlers["open"];called_by=dispatch' 'vr:bind=@G_STRUCT;into=ops.Open;called_by=useOps'
arm "G2 callers myClose: map value, struct field, slice element" \
    go --callers=myClose attr:count=0 attr:value_refs=3 nvr:3 'vr:bind=@G_MAP;into=handlers["close"]' 'vr:bind=@G_STRUCT;into=ops.Close' 'vr:bind=@G_SLICE;into=fns[1]'
arm "G3 callers onEvent: slice element and a callback — NOT negShadow's := local, NOT negRange's range variable" \
    go --callers=onEvent attr:count=0 attr:value_refs=2 nvr:2 'vr:bind=@G_SLICE;into=fns[0]' 'vr:bind=@G_RUN;into=run#arg0;called_by=run' 'novr:bind=@G_N3' 'novr:bind=@G_N7'
arm "G4 callers serve: an http.HandleFunc handler" \
    go --callers=serve attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@G_HANDLE;into=http.HandleFunc#arg1'
arm "G5 callees dispatch: handlers[k](x) may call both map values" \
    go --callees=dispatch attr:count=0 attr:value_refs=2 nvr:2 'vr:to=myOpen;through=handlers[k]' 'vr:to=myClose;through=handlers[k]'
arm "G6 callees useOps: ops.Open(x) reaches the Open field only" \
    go --callees=useOps attr:count=0 attr:value_refs=1 nvr:1 'vr:to=myOpen;bind=@G_STRUCT;through=ops.Open'
arm "G7 negatives: lone (comment, string, struct-literal KEY) has its one call and no value row" \
    go --callers=lone attr:count=1 ns:1 's:n=negCall' noattr:value_refs nvr:0
arm "G8 tier-B shadow: shadowH calls its PARAMETER handlers — no through row" \
    go --callees=shadowH attr:count=0 noattr:value_refs nvr:0
arm "G9 uses lone: no role=value row" go --uses=lone 'u:role=call' 'nou:role=value'

# ── C++ (sibling of C): an algorithm comparator, a designated initialiser, qualified values ───────────────
echo "-- C++"
arm "X1 callers cmpLess: the std::sort comparator argument" \
    cpp --callers=cmpLess attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@X_SORT;into=std::sort#arg2;in_id=sortAll'
arm "X2 callers myOpen: a designated initialiser" \
    cpp --callers=myOpen attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@X_TABLE;into=table.open'
arm "X3 negatives: lone (a string, a comment, decltype, an init-capture, a captured parameter, a range-for variable) has its one call and no value row" \
    cpp --callers=lone attr:count=1 ns:1 noattr:value_refs nvr:0
arm "F2 floor: ns::qf passed as a qualified value — no row" cpp --callers=qf attr:defs=1 noattr:value_refs nvr:0
arm "F2 floor: &Cls::sm passed as a qualified value — no row" cpp --callers=sm attr:defs=1 noattr:value_refs nvr:0

# ── Class members and bare names (final review R1) ───────────────────────────────────────────────────────
echo "-- members are not bare names"
arm "RM1 negatives: isinstance(x, (list, tuple)) names the builtins — never Finder.list" \
    pymem --callers=list attr:defs=1 noattr:value_refs nvr:0 'novr:bind=@PM_ISINSTANCE'
arm "RM2 negatives: … nor Envelope.tuple" pymem --callers=tuple attr:defs=1 noattr:value_refs nvr:0 'novr:bind=@PM_ISINSTANCE'
arm "RM3 negatives: sorted(xs, key=keyfn) inside a method never reaches the sibling METHOD keyfn (a NameError in Python)" \
    pymem --callers=keyfn attr:defs=1 noattr:value_refs nvr:0 'novr:bind=@PM_SIBLING'
arm "RM4 the class BODY sees its members: __str__ = render" \
    pymem --callers=render attr:value_refs=1 nvr:1 'vr:bind=@PM_CLASSBODY;into=__str__'
arm "RM5 a def NESTED in a method (its scope names the class too) is the method's local and stays in scope" \
    pymem --callers=step attr:value_refs=1 nvr:1 'vr:bind=@PM_NESTED;into=map#arg0'
arm "RX1 negatives: memcpy( data, … ) in FixedStr is its member array — never Vec::data()" \
    cppmem --callers=data attr:defs=1 noattr:value_refs nvr:0 'novr:bind=@XM_DATA'
arm "RX2 negatives: a C++ data member named count shadows the free function count inside its class" \
    cppmem --callers=count attr:count=1 noattr:value_refs nvr:0 'novr:bind=@XM_FIELD'
arm "RX4 negatives: a C++ class body is a complete-class context — a data member declared below the method still shadows" \
    cppmem --callers=total attr:count=1 noattr:value_refs nvr:0 'novr:bind=@XM_LATE'
arm "RX3 a static member of the SAME class is in scope: std::sort(…, lessThan)" \
    cppmem --callers=lessThan attr:value_refs=1 nvr:1 'vr:bind=@XM_SAME;into=std::sort#arg2'
arm "RJ1 negatives: { load: require } is the global require — never the class method Runner#require" \
    jsmem --callers=require attr:defs=1 noattr:value_refs nvr:0 'novr:bind=@JSM_REQUIRE'
arm "RJ2 negatives: [source] is the file-scope let — never the class method Runner#source" \
    jsmem --callers=source attr:defs=1 noattr:value_refs nvr:0 'novr:bind=@JSM_SOURCE'

# ── --verify and --quality-delta read the same value uses (final review R4, R2) ──────────────────────────
echo "-- verify / quality-delta"
arm "V1 verify unused(my_open): a value use REFUTES 'unused' (the role=value sites are the evidence)" \
    c '--verify=unused(my_open)' attr:verdict=refuted 'u:role=value;p=@C_TABLE'
arm "V2 verify unused(truly_dead): nothing holds it — the verdict is unchanged" \
    c '--verify=unused(truly_dead)' attr:verdict=not-established nu:0

# R2: --quality-delta's dead kind applies the --dead-code verb's rule — a static a struct table holds is not dead there
# either (one fact, two verbs, one answer). A two-commit repo: the second commit adds the table-held static and a truly
# dead one.
QD="$FX/qd"; mkdir -p "$QD"
(
    cd "$QD" && git init -q && git config user.email t@t && git config user.name t \
    && printf 'int base_fn(int x) { return x; }\n' > qd.c && git add -A && git commit -qm base \
    && printf '%s\n' 'struct ops { int (*open)(int); };' 'static int my_open(int x) { return x + 1; }' \
                     'static struct ops table = { .open = my_open };' 'static int dead_new(int x) { return x; }' \
                     'int use_table(int x) { return table.open(x); }' >> qd.c \
    && git add -A && git commit -qm add
) >/dev/null 2>&1 || no "Q0 the quality-delta fixture repository could not be built"
( cd "$QD" && "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache --legend=compact >"$TMP/qd.xml" 2>"$TMP/qd.err" )
qdrc=$?
if [ "$qdrc" -gt 2 ]; then
    no "Q1 --quality-delta exited $qdrc ($(head -c 200 "$TMP/qd.err"))"
else
    res="$( python3 - "$TMP/qd.xml" <<'EOF'
import re, sys
t = open( sys.argv[1] ).read()
root = re.search( r"<quality-delta[^>]*>", t )
rows = re.findall( r'<r kind="dead-code" sym="([^"]*)"', t )
fails = []
if root is None:
    fails.append( "no <quality-delta> root" )
else:
    m = re.search( r'value-ref-excluded="(\d+)"', root.group( 0 ) )
    if m is None or m.group( 1 ) != "1":
        fails.append( "value-ref-excluded=%r (want '1')" % ( m.group( 1 ) if m else None ) )
if not any( s.endswith( "dead_new" ) for s in rows ):
    fails.append( "no dead-code row for dead_new (the kind must still fire): %r" % rows )
if any( s.endswith( "my_open" ) for s in rows ):
    fails.append( "a dead-code row for my_open, which a struct table holds: %r" % rows )
print( "FAIL " + " | ".join( fails ) if fails else "OK" )
EOF
)"
    verdict "Q1 quality-delta dead kind: the table-held static is value-ref-excluded=1, the truly dead one is still a row" "$res"
fi

# Q2: a registering decorator holds the function; a WRAPPER decorator (@staticmethod, @functools.wraps…) only hands it
# back to its own name, so it does not exclude the function from the dead kind (qualitycheck's inherited-hook arm).
QP="$FX/qdpy"; mkdir -p "$QP"
(
    cd "$QP" && git init -q && git config user.email t@t && git config user.name t \
    && printf 'def base():\n    return 1\n' > m.py && git add -A && git commit -qm base \
    && printf '%s\n' 'import functools' 'REG = []' 'def register(f):' '    REG.append(f)' '    return f' \
                     '@register' 'def held_by_registry(x):' '    return x' \
                     '@functools.wraps(print)' 'def only_wrapped(x):' '    return x' \
                     'class Box:' '    @staticmethod' '    def never_called(x):' '        return x' >> m.py \
    && git add -A && git commit -qm add
) >/dev/null 2>&1 || no "Q0 the Python quality-delta fixture repository could not be built"
( cd "$QP" && "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache --legend=compact >"$TMP/qdpy.xml" 2>"$TMP/qdpy.err" )
qdrc=$?
if [ "$qdrc" -gt 2 ]; then
    no "Q2 --quality-delta exited $qdrc ($(head -c 200 "$TMP/qdpy.err"))"
else
    res="$( python3 - "$TMP/qdpy.xml" <<'EOF'
import re, sys
t = open( sys.argv[1] ).read()
root = re.search( r"<quality-delta[^>]*>", t )
rows = re.findall( r'<r kind="dead-code" sym="([^"]*)"', t )
fails = []
m = re.search( r'value-ref-excluded="(\d+)"', root.group( 0 ) ) if root else None
if m is None or m.group( 1 ) != "1":
    fails.append( "value-ref-excluded=%r (want '1')" % ( m.group( 1 ) if m else None ) )
for want in ( "never_called", "only_wrapped" ):
    if not any( s.endswith( want ) for s in rows ):
        fails.append( "no dead-code row for %s (a wrapper decorator is not a value use): %r" % ( want, rows ) )
if any( s.endswith( "held_by_registry" ) for s in rows ):
    fails.append( "a dead-code row for held_by_registry, which @register holds: %r" % rows )
print( "FAIL " + " | ".join( fails ) if fails else "OK" )
EOF
)"
    verdict "Q2 quality-delta: @register holds held_by_registry (excluded); @staticmethod/@functools.wraps defs stay dead rows" "$res"
fi

# ── Runaway guard (review fix 8): one function stored 300 times ─────────────────────────────────────────
echo "-- runaway guard"
arm "Z1 callers hot: value_refs=300 stays whole; the <vrs> window shows 64, capped=1, next= names the paging verb" \
    big --callers=hot attr:count=0 attr:value_refs=300 el:vrs:total=300 el:vrs:shown=64 el:vrs:capped=1 'el:vrs:next=--uses=hot' nvr:64
arm "Z2 callees use_many: one row per (to, through) — hot through many[i], sites=300" \
    big --callees=use_many attr:count=0 attr:value_refs=1 nvr:1 'vr:to=hot;through=many[i];sites=300'
arm "Z3 uses hot: 300 role=value sites, paged by the verb's own window (shown=100 capped=1 has_more=1)" \
    big --uses=hot attr:count=300 attr:shown=100 attr:capped=1 attr:has_more=1 nu:100 'nou:role=read'
arm_roots "Z4 multi-root (big c) callers hot: the same window on a two-root run" "big c" --callers=hot \
    attr:value_refs=300 el:vrs:total=300 el:vrs:shown=64 el:vrs:capped=1 nvr:64

# ── Controls: no value reference → no new attribute, element, row or legend clause ───────────────────────
echo "-- controls"
ctl_arm() {   # ctl_arm ARGV PRESENCE-TOKEN…
    local argv="$1"; shift
    arm "K ctl $argv: no value_refs / <vrs> / value-ref-excluded / to_value_refs / legend clause" ctl "$argv" "$@" \
        noattr:value_refs noattr:value-ref-excluded noattr:to_value_refs noel:vrs nvr:0 nolegend:value_refs 'nolegend:not a proven call'
}
ctl_arm --callers=helper attr:count=1 's:n=caller'
ctl_arm --callees=caller attr:count=1 's:n=helper'
ctl_arm --impact=helper attr:reaches=1
ctl_arm --safe-delete=helper attr:callers=1
ctl_arm --uses=helper attr:count=1 'u:role=call'
ctl_arm --dead-code attr:count=1 'd:n=dead_one'
ctl_arm --callers=py_helper attr:count=1 's:n=py_caller'
ctl_arm --callees=py_caller attr:count=1 's:n=py_helper'
ctl_arm --uses=py_helper attr:count=1 'u:role=call'
ctl_arm --callers=jsHelper attr:count=1 's:n=jsCaller'
ctl_arm --callees=jsCaller attr:count=1 's:n=jsHelper'
ctl_arm --path=caller,helper attr:reachable=1
arm "K ctl safe-delete dead_one keeps its verdict" ctl --safe-delete=dead_one attr:callers=0 attr:dead_code_candidate=1 attr:risk=none-found

# ── Disclosure: the legend says what a value row is and is not; CLI == JSON == MCP (review fix 6) ─────────
echo "-- disclosure"
arm "D1 callers legend (compact): value_refs=, into=, called_by=, by name, may call, not a proven call" \
    c --callers=my_open 'legend:value_refs=' 'legend:into=' 'legend:called_by=' 'legend:bind=' 'legend:by name' 'legend:may call' 'legend:not a proven call'
arm "D2 callees legend (compact): through=, to=, sites=, may call" \
    c --callees=use_literal 'legend:through=' 'legend:to=' 'legend:sites=' 'legend:may call' 'legend:not a proven call'
arm "D2 impact legend (compact)" c --impact=my_open 'legend:value_refs=' 'legend:not a proven call'
arm "D2 safe-delete legend (compact)" c --safe-delete=my_open 'legend:value_refs=' 'legend:not a proven call'
arm "D2 uses legend (compact) defines role=value" c --uses=my_open 'legend:role=value' 'legend:not a proven call'
arm "D2 dead-code legend (compact) defines value-ref-excluded=" c --dead-code 'legend:value-ref-excluded=' 'legend:not a proven call'
arm "D2 path legend (compact) defines to_value_refs=" c --path=use_callback,on_event 'legend:to_value_refs=' 'legend:not a proven call'
arm "D2 runaway legend defines the <vrs> window" big --callers=hot 'legend:vrs' 'legend:capped='
( cd "$FX/c" && "$BIN" . --callers=my_open --no-cache --legend=full >"$TMP/full.xml" 2>/dev/null )
run_check "D3 callers legend (full) carries the same clauses" "$FX/c" "$TMP/full.xml" \
    'legend:value_refs=' 'legend:into=' 'legend:called_by=' 'legend:by name' 'legend:may call' 'legend:not a proven call'

mcp_call() {   # mcp_call TOOL ARGS_JSON → the tool's text payload on stdout
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"'"$1"'","arguments":'"$2"'}}' \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + r["error"].get("message","") if "error" in r else r["result"]["content"][0]["text"])
'
}
cat >"$TMP/par.py" <<'EOF'
# par.py MODE CLIFILE OTHERFILE [KEY] — the twin carries the same value rows as the CLI XML answer.
#   json  KEY: OTHERFILE is JSON whose KEY is the window object {total, shown, capped, [next], rows:[…]}
#   xml      : OTHERFILE is an XML answer (MCP); compare <vr> rows, value_refs and the <vrs> window
#   uxml     : OTHERFILE is an XML answer (MCP uses); compare the <u> rows (role, p, in_id)
#   pxml     : OTHERFILE is an XML answer (MCP path_between); compare reachable= and to_value_refs=
import json, re, sys
import xml.etree.ElementTree as ET
def xml_root( path ):
    raw = open( path ).read()
    if raw.startswith( "__ERROR__" ):
        print( "FAIL twin errored: " + raw[:200] ); raise SystemExit
    x = re.sub( r"<!--.*?-->", "", raw, flags=re.S ).strip()
    try:
        return ET.fromstring( x )
    except ET.ParseError as e:
        print( "FAIL not XML (%s): %s" % ( e, x[:200] ) ); raise SystemExit
mode, cliF, othF = sys.argv[1], sys.argv[2], sys.argv[3]
cli = xml_root( cliF )
KEYS = ( "in_id", "to", "def", "bind", "into", "called_by", "through", "sites" )
row = lambda d: tuple( str( d.get( k, "" ) ) for k in KEYS )
win = lambda d: tuple( str( d.get( k, "" ) ) for k in ( "total", "shown", "capped", "next" ) )
cliRows = sorted( row( el.attrib ) for el in cli.iter( "vr" ) )
cliWin = next( iter( cli.iter( "vrs" ) ), None )
if mode in ( "json", "xml" ) and ( not cliRows or cliWin is None ):
    print( "FAIL the CLI answer has no <vrs>/<vr> rows to compare (value_refs=%s)" % cli.get( "value_refs" ) ); raise SystemExit
if mode == "json":
    raw = open( othF ).read()
    if raw.startswith( "__ERROR__" ):
        print( "FAIL twin errored: " + raw[:200] ); raise SystemExit
    try:
        j = json.loads( raw )
    except ValueError as e:
        print( "FAIL twin not JSON: %s" % e ); raise SystemExit
    obj = j.get( sys.argv[4] )
    if not isinstance( obj, dict ) or not isinstance( obj.get( "rows" ), list ):
        print( "FAIL JSON has no %s window object with rows (keys: %s)" % ( sys.argv[4], ",".join( sorted( j ) ) ) ); raise SystemExit
    norm = lambda v: "1" if v is True else "0" if v is False else str( v )
    oRows = sorted( row( { k: norm( v ) for k, v in r.items() } ) for r in obj["rows"] )
    oWin = tuple( norm( obj.get( k, "" ) ) if k in obj else "" for k in ( "total", "shown", "capped", "next" ) )
elif mode == "xml":
    o = xml_root( othF )
    oRows = sorted( row( el.attrib ) for el in o.iter( "vr" ) )
    w = next( iter( o.iter( "vrs" ) ), None )
    oWin = win( w.attrib ) if w is not None else None
elif mode == "uxml":
    o = xml_root( othF )
    u = lambda r: sorted( ( e.get( "role" ), e.get( "p" ), e.get( "in_id" ) ) for e in r.iter( "u" ) )
    if not u( cli ):
        print( "FAIL the CLI answer has no <u> rows" ); raise SystemExit
    print( "OK" if u( cli ) == u( o ) and cli.get( "count" ) == o.get( "count" ) else "FAIL rows differ: cli=%r mcp=%r" % ( u( cli ), u( o ) ) )
    raise SystemExit
elif mode == "pxml":
    o = xml_root( othF )
    a = ( cli.get( "reachable" ), cli.get( "to_value_refs" ) ); b = ( o.get( "reachable" ), o.get( "to_value_refs" ) )
    print( "OK" if a == b and a[1] is not None else "FAIL cli=%r mcp=%r" % ( a, b ) )
    raise SystemExit
if cliRows != oRows:
    print( "FAIL rows differ: cli=%r twin=%r" % ( cliRows, oRows ) )
elif oWin != win( cliWin.attrib ):
    print( "FAIL window differs: cli=%r twin=%r" % ( win( cliWin.attrib ), oWin ) )
else:
    print( "OK" )
EOF
cli() { ( cd "$FX/$1" && "$BIN" . $2 --no-cache --legend=compact >"$3" 2>/dev/null ); }
cli c --callers=my_open "$TMP/cli.callers.xml"
cli c --callees=use_literal "$TMP/cli.callees.xml"
cli c --impact=my_open "$TMP/cli.impact.xml"
cli py --uses=foo_get "$TMP/cli.uses.xml"
cli c --path=use_callback,on_event "$TMP/cli.path.xml"
cli big --callers=hot "$TMP/cli.hot.xml"
( cd "$FX/c" && "$BIN" . --callers=my_open --no-cache --json >"$TMP/j.callers.json" 2>/dev/null )
( cd "$FX/c" && "$BIN" . --callees=use_literal --no-cache --json >"$TMP/j.callees.json" 2>/dev/null )
( cd "$FX/c" && "$BIN" . --impact=my_open --no-cache --json >"$TMP/j.impact.json" 2>/dev/null )
verdict "D4 CLI --json callers == XML (vrs window + rows)" "$( python3 "$TMP/par.py" json "$TMP/cli.callers.xml" "$TMP/j.callers.json" vrs )"
verdict "D4b CLI --json callees == XML" "$( python3 "$TMP/par.py" json "$TMP/cli.callees.xml" "$TMP/j.callees.json" vrs )"
verdict "D4c CLI --json impact == XML" "$( python3 "$TMP/par.py" json "$TMP/cli.impact.xml" "$TMP/j.impact.json" vrs )"
mcp_call find_referencing_symbols '{"path":"'"$FX/c"'","symbol":"my_open"}' >"$TMP/mcp.frs.json"
verdict "D5 MCP find_referencing_symbols == CLI --callers (valueRefs)" "$( python3 "$TMP/par.py" json "$TMP/cli.callers.xml" "$TMP/mcp.frs.json" valueRefs )"
mcp_call find_symbol '{"path":"'"$FX/c"'","symbol":"my_open"}' >"$TMP/mcp.fs.json"
verdict "D6 MCP find_symbol(my_open).valueRefs == CLI --callers" "$( python3 "$TMP/par.py" json "$TMP/cli.callers.xml" "$TMP/mcp.fs.json" valueRefs )"
mcp_call find_symbol '{"path":"'"$FX/c"'","symbol":"use_literal"}' >"$TMP/mcp.fs2.json"
verdict "D7 MCP find_symbol(use_literal).valueCallees == CLI --callees" "$( python3 "$TMP/par.py" json "$TMP/cli.callees.xml" "$TMP/mcp.fs2.json" valueCallees )"
mcp_call impact '{"path":"'"$FX/c"'","symbol":"my_open","legend":"compact"}' >"$TMP/mcp.impact.xml"
verdict "D8 MCP impact == CLI --impact (rows + window, a diff not a constant)" "$( python3 "$TMP/par.py" xml "$TMP/cli.impact.xml" "$TMP/mcp.impact.xml" )"
run_check "D8b MCP impact legend carries the clause" "$FX/c" "$TMP/mcp.impact.xml" 'legend:value_refs=' 'legend:not a proven call'
mcp_call uses '{"path":"'"$FX/py"'","symbol":"foo_get","legend":"compact"}' >"$TMP/mcp.uses.xml"
verdict "D9 MCP uses == CLI --uses (role=value rows, a diff)" "$( python3 "$TMP/par.py" uxml "$TMP/cli.uses.xml" "$TMP/mcp.uses.xml" )"
run_check "D9b MCP uses legend carries the clause" "$FX/py" "$TMP/mcp.uses.xml" 'legend:not a proven call' 'u:role=value'
mcp_call path_between '{"path":"'"$FX/c"'","from":"use_callback","to":"on_event","legend":"compact"}' >"$TMP/mcp.path.xml"
verdict "D11 MCP path_between == CLI --path (reachable, to_value_refs)" "$( python3 "$TMP/par.py" pxml "$TMP/cli.path.xml" "$TMP/mcp.path.xml" )"
run_check "D11b MCP path_between legend defines to_value_refs=" "$FX/c" "$TMP/mcp.path.xml" 'legend:to_value_refs='
mcp_call find_referencing_symbols '{"path":"'"$FX/big"'","symbol":"hot"}' >"$TMP/mcp.hot.json"
verdict "D12 MCP find_referencing_symbols(hot): the same 64-row window as the CLI (total=300 capped)" \
    "$( python3 "$TMP/par.py" json "$TMP/cli.hot.xml" "$TMP/mcp.hot.json" valueRefs )"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    | "$BIN" --mcp 2>/dev/null | tail -1 >"$TMP/tools.json"
res="$( python3 - "$TMP/tools.json" <<'EOF'
import json, sys
try:
    tools = { t["name"]: t.get( "description", "" ) for t in json.load( open( sys.argv[1] ) )["result"]["tools"] }
except ( ValueError, KeyError ) as e:
    print( "FAIL tools/list unreadable: %s" % e ); raise SystemExit
bad = [ n for n in ( "find_referencing_symbols", "find_symbol" ) if "valueRefs" not in tools.get( n, "" ) or "not a proven call" not in tools.get( n, "" ) ]
print( "FAIL description lacks valueRefs / 'not a proven call': " + ",".join( bad ) if bad else "OK" )
EOF
)"
verdict "D10 MCP tools/list: find_referencing_symbols and find_symbol describe valueRefs as not a proven call" "$res"

# ── review fixes (CodeRabbit on the reference-as-value round) ──────────────────────────────────────────────────────
# RW: a written slot is cut on a UTF-8 boundary, gets "…" only when really cut, and a JS string key is capped like the
#    Python one. Each pair is a positive (the cut) beside its near miss (a text one byte shorter or longer).
# RO: a --callees tie (one site, one name, one through, several definitions) is ordered by the definition's path, so the
#    64-row window shows the same rows under every standard library.
# RF: a container fed many times (the fed lists are deduplicated and binary-searched) still matches, an unfed one never.
# RV: the MCP server's value-reference index is rebuilt after EVERY index rebuild — a chmod (ctime only) or a new
#    non-source file (a directory mtime) rebuilds with unchanged file content, and the old index then read freed
#    bindings (heap-use-after-free under ASan) — and is NOT rebuilt on a warm reuse.
echo "-- review fixes"
mkdir -p "$FX/cut" "$FX/cutjs" "$FX/tie" "$FX/fed" "$FX/vri"
python3 - "$FX" >"$TMP/cut.expect" <<'EOF'
import os, sys
fx = sys.argv[1]
cases = { "cut": ( "a" * 80 + "é" * 20 ), "exact": "b" * 94, "over": "b" * 95 }
with open( os.path.join( fx, "cut", "reg.py" ), "w", encoding="utf-8" ) as f:
    for name in cases:
        f.write( "def h_%s(x):\n    return x\n\n" % name )
    for name, key in cases.items():
        f.write( "T_%s = {\"%s\": h_%s}\n" % ( name, key, name ) )
js = { "long": "c" * 300, "exact": "d" * 96, "cut": "x" * 95 + "ä" }
with open( os.path.join( fx, "cutjs", "reg.js" ), "w", encoding="utf-8" ) as f:
    for name in js:
        f.write( "function j_%s(x) { return x; }\n" % name )
    for name, key in js.items():
        f.write( "const J_%s = { \"%s\": j_%s };\n" % ( name, key, name ) )
    f.write( "module.exports = { J_long, J_exact, J_cut };\n" )
E = "…"
# the cleaned key literal (quotes included, kVrTextCap = 96 bytes) cut back to the start of the character the cap falls in
print( "T_cut[\"" + "a" * 80 + "é" * 7 + E + "]" )        # 1 + 80 + 7*2 = 95 bytes: byte 96 is an é continuation byte
print( "T_exact[\"" + "b" * 94 + "\"]" )                      # exactly 96 bytes: whole, no ellipsis
print( "T_over[\"" + "b" * 95 + E + "]" )                     # 97 bytes: cut at 96
print( "J_long." + "c" * 96 + E )
print( "J_exact." + "d" * 96 )
print( "J_cut." + "x" * 95 + E )                              # byte 96 is the ä continuation byte: back off to 95
EOF
i=0; while IFS= read -r want; do i=$(( i + 1 )); exp[$i]="$want"; done <"$TMP/cut.expect"
arm "RW1 callers h_cut: a non-ASCII key cut at the cap ends on a whole character, then …" cut --callers=h_cut attr:value_refs=1 "vr:into=${exp[1]}"
arm "RW2 callers h_exact (near miss): a 96-byte key is whole — no … when nothing was cut" cut --callers=h_exact attr:value_refs=1 "vr:into=${exp[2]}"
arm "RW3 callers h_over (near miss): a 97-byte key is still cut" cut --callers=h_over attr:value_refs=1 "vr:into=${exp[3]}"
arm "RW4 callers j_long: a JS string key is capped like the Python one" cutjs --callers=j_long attr:value_refs=1 "vr:into=${exp[4]}"
arm "RW5 callers j_exact (near miss): a 96-byte JS key is whole" cutjs --callers=j_exact attr:value_refs=1 "vr:into=${exp[5]}"
arm "RW6 callers j_cut: a JS key cut inside a character backs off to its start" cutjs --callers=j_cut attr:value_refs=1 "vr:into=${exp[6]}"
cli cut --callers=h_cut "$TMP/cli.cut.xml"
# strict decode (a partial sequence raises), and neither the emitter's '?' nor U+FFFD stands in for a cut character
res="$( python3 -c '
import sys
b = open( sys.argv[1], "rb" ).read()
try:
    s = b.decode( "utf-8" )
except UnicodeDecodeError as e:
    print( "FAIL not valid UTF-8: %s" % e ); raise SystemExit
print( "FAIL a replacement stands before the ellipsis" if ( "?\u2026" in s or "\ufffd" in s ) else "OK" if "\u00e9\u2026" in s else "FAIL no whole-character cut in the answer" )' "$TMP/cli.cut.xml" 2>&1 )"
verdict "RW7 the CLI answer with the cut is strict UTF-8 and ends the cut on a whole character (no ? / U+FFFD before …)" "$res"
mcp_call find_referencing_symbols '{"path":"'"$FX/cut"'","symbol":"h_cut"}' >"$TMP/mcp.cut.json"
verdict "RW8 MCP find_referencing_symbols(h_cut).valueRefs == CLI (the same whole-character cut)" "$( python3 "$TMP/par.py" json "$TMP/cli.cut.xml" "$TMP/mcp.cut.json" valueRefs )"

for k in $( seq -w 1 70 ); do mkdir -p "$FX/tie/d$k"; printf 'int helper(int x) { return x + %d; }\n' "$(( 10#$k ))" >"$FX/tie/d$k/h.c"; done
printf 'typedef int (*fn_t)(int);\nstatic fn_t fp;\nvoid setup(void) { fp = helper; }   /* @O_BIND */\n' >"$FX/tie/main.c"
arm "RO1 callees setup: 70 same-named definitions, one site — a 64-row window over 70" tie --callees=setup \
    el:vrs:total=70 el:vrs:shown=64 el:vrs:capped=1 nvr:64 'vr:to=helper;def=d01/h.c:1;bind=@O_BIND;into=fp'
cli tie --callees=setup "$TMP/cli.tie.xml"
res="$( python3 - "$TMP/cli.tie.xml" <<'EOF'
import re, sys
defs = re.findall( r'<vr [^>]*\bdef="([^"]*)"', open( sys.argv[1], encoding="utf-8" ).read() )
want = [ "d%02d/h.c:1" % k for k in range( 1, 65 ) ]
print( "OK" if defs == want else "FAIL rows are not the first 64 definitions in path order: %r" % defs[:8] )
EOF
)"
verdict "RO2 callees setup: the tied rows are in definition-path order, so the window shows d01..d64 on every toolchain" "$res"

cat >"$FX/fed/fed.js" <<'EOF'
function fa() { return 1; }
function fb() { return 2; }
function fc() { return 3; }
function fx() { return 4; }
function fp() { return 5; }
function fq() { return 6; }
const zeta = {};
const alpha = {};
const unfed = {};
zeta.a = fa;
zeta.b = fb;
zeta.c = fc;
alpha.x = fx;
function goZ(k) { return zeta[k](); }
function goA(k) { return alpha[k](); }
function goU(k) { return unfed[k](); }
function local(k) { const m = {}; const n = {}; m.p = fp; m.q = fp; n.r = fq; return m[k]() + n[k](); }
EOF
arm "RF1 callees goZ: a file-scope container fed three times reaches all three" fed --callees=goZ el:vrs:total=3 nvr:3 \
    'vr:to=fa;through=zeta[k]' 'vr:to=fb;through=zeta[k]' 'vr:to=fc;through=zeta[k]'
arm "RF2 callees goA: a container fed AFTER another one fed many times still matches (sorted, deduplicated fed list)" \
    fed --callees=goA el:vrs:total=1 nvr:1 'vr:to=fx;through=alpha[k]'
arm "RF3 callees goU (negative): a container no function was stored in reaches nothing" fed --callees=goU attr:defs=1 nvr:0 noel:vrs
arm "RF4 callees local: a function-scope container fed twice, beside another" fed --callees=local el:vrs:total=3 nvr:3 \
    'vr:to=fp;into=m.p;through=m[k]' 'vr:to=fp;into=m.q;through=m[k]' 'vr:to=fq;into=n.r;through=n[k]'

printf 'export function cb(x) { return x + 1; }\n' >"$FX/vri/a.js"
printf 'export function run(f, x) { return f(x); }\n' >"$FX/vri/r.js"
printf "import { run } from './r.js';\nimport { cb } from './a.js';\nexport function go() { return run(cb, 1); }\n" >"$FX/vri/b.js"
res="$( python3 - "$BIN" "$FX/vri" cb <<'EOF'
import hashlib, json, os, stat, subprocess, sys, tempfile, time
binp, d, sym = sys.argv[1:4]
tmp = tempfile.mkdtemp()
errf = open( os.path.join( tmp, "err.txt" ), "w+" )
p = subprocess.Popen( [ binp, "--mcp" ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errf, text=True,
                      env=dict( os.environ, RIPWIRE_MCP_TIMINGS="1", TMPDIR=tmp ) )
def call( i, method, params=None ):
    msg = { "jsonrpc": "2.0", "id": i, "method": method }
    if params is not None: msg[ "params" ] = params
    try:
        p.stdin.write( json.dumps( msg ) + "\n" ); p.stdin.flush()
    except ( BrokenPipeError, ValueError ):
        return None
    line = p.stdout.readline()
    return json.loads( line ) if line else None
def fs( i ):
    r = call( i, "tools/call", { "name": "find_symbol", "arguments": { "path": d, "symbol": sym } } )
    if r is None or "error" in r: return "NORESP"
    v = json.loads( r[ "result" ][ "content" ][ 0 ][ "text" ] ).get( "valueRefs" )
    return hashlib.sha1( json.dumps( v, sort_keys=True ).encode() ).hexdigest() if v else "NOROWS"
call( 1, "initialize" )
rows = [ fs( 2 ), fs( 3 ) ]
time.sleep( 1.1 )
f = os.path.join( d, "b.js" ); m = os.stat( f ).st_mode
os.chmod( f, m ^ stat.S_IXUSR ); os.chmod( f, m )                     # ctime moves; content and mtime do not
rows.append( fs( 4 ) )
time.sleep( 1.1 )
open( os.path.join( d, "notes.txt" ), "w" ).write( "x\n" )           # a directory mtime moves; no source changes
rows.append( fs( 5 ) )
try: p.stdin.close()
except BrokenPipeError: pass
try: p.wait( timeout=120 )
except subprocess.TimeoutExpired: p.kill(); print( "FAIL the MCP server did not exit within 120 s" ); sys.exit( 0 )
errf.seek( 0 ); err = errf.read()
lines = [ l for l in err.splitlines() if l.startswith( "ripwire-timing verb=find_symbol " ) ]
got = [ ( dict( x.split( "=", 1 ) for x in l.split()[ 1: ] ).get( "rebuilt" ), dict( x.split( "=", 1 ) for x in l.split()[ 1: ] ).get( "vri" ) ) for l in lines ]
print( json.dumps( { "rows": rows, "got": got, "rc": p.returncode,
                     "san": err.count( "ERROR: AddressSanitizer" ) + err.count( "runtime error:" ) } ) )
EOF
)"
vri_arm(){   # vri_arm LABEL PYEXPR — PYEXPR over s (the session summary) must be true
    local r; r="$( python3 -c 'import json, sys; s = json.loads( sys.argv[1] ); print( "OK" if eval( sys.argv[2] ) else "FAIL session: %r" % s )' "$res" "$2" 2>&1 )"
    verdict "$1" "$r"
}
vri_arm "RV1 MCP session: the cold find_symbol builds the index and the value-ref index (rebuilt=1 vri=1)" 's["got"][0] == ["1","1"] and s["rows"][0] not in ("NORESP","NOROWS")'
vri_arm "RV2 MCP session (negative): a warm find_symbol reuses both (rebuilt=0 vri=0), same rows" 's["got"][1] == ["0","0"] and s["rows"][1] == s["rows"][0]'
vri_arm "RV3 MCP session: a chmod rebuilds the index with unchanged content — the value-ref index is rebuilt too (vri=1), same rows" 's["got"][2] == ["1","1"] and s["rows"][2] == s["rows"][0]'
vri_arm "RV4 MCP session: a new non-source file rebuilds the index — the value-ref index is rebuilt too (vri=1), same rows" 's["got"][3] == ["1","1"] and s["rows"][3] == s["rows"][0]'
vri_arm "RV5 MCP session: the server exited 0 with no sanitizer report (meaningful on an ASan build)" 's["rc"] == 0 and s["san"] == 0'

echo
if [ "$fail" -eq 0 ]; then echo "recallshapecheck: ALL PASS ($n CLI arms + parity)"; else echo "recallshapecheck: FAIL"; fi
exit "$fail"
