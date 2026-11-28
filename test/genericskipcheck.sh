#!/usr/bin/env bash
# genericskipcheck.sh — GSKIP-1: explicit type arguments on a call keep the call's shape.
#
#   test/genericskipcheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# Two rows of the generic-skip audit (stage 0, 11-27), both lost on the way from the written call to the edge:
#   G1 (C#)  tree-sitter-c-sharp wraps the called name of `Util.Make<int>( x )` in a generic_name, the member access's `name:`.
#            ingest_binds.h memberOnlyReceiver read the generic_name as the parent, so every generic member call was
#            receiverless and split by name: --callees listed the right Make and its namesake, both via="name".
#   G2 (C++) a function-like #define body is one opaque preproc_arg that captureMacroBodyCalls scans lexically for `ident (`.
#            `make<int>( x )` has a `<` behind the name, so no call was read: envoy's THROW_OR_RETURN_VALUE expands to
#            `::Envoy::returnOrThrow<type>(expression)` at 199 use sites and the graph did not connect through it.
#
# Arm classes: [P] positive — RED on the parent binary (origin/main 17543d674); [C] control — the same callee without type
# arguments, or a generic name that is no member access: holds on every binary; [N] near miss — a comparison spelled like a
# template-id, which must not read as a call (holds on the parent binary too: it guards the fix, it does not prove it).
# Every arm counts toward a premise total; a run that saw zero rows of a corpus FAILs (gatepremisecheck).
#
# Not an arm: a block comment inside a #define. tree-sitter-cpp ends a preproc_arg before `/*` and degrades the file
# (err_ratio 0.39 measured on `make<int /* > */>( x )`), so the definition is not extracted on any binary.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
fail=0; arms=0
# every verdict is an if/else: a failed write of a PASS line must never print FAIL for an arm that passed (gateexitcheck G2)
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
has(){ arms=$(( arms + 1 )); if printf '%s' "$1" | grep -qF -- "$2"; then ok "$3"; else no "$3 — missing: $2"; fi; }
hasnt(){ arms=$(( arms + 1 )); if printf '%s' "$1" | grep -qF -- "$2"; then no "$3 — present: $2"; else ok "$3"; fi; }
# the callee rows of one --callees answer, one per line
# , led by a FOUND line when the caller symbol resolved: --callees exits 1 on an unresolved symbol (a near-miss arm on an
# unresolved symbol would pass blind, so the near-miss premise counts these lines)
callees(){
    local o
    if o="$( cd "$1" && "$BIN" . --no-cache --callees="$2" --legend=compact 2>&1 )"; then echo FOUND; fi
    printf '%s\n' "$o" | grep -oE '<(s|dc) [^>]*/>'
}
# premise: the corpus was read at all (the caller symbol resolved); zero rows across a corpus is a vacuous run
premise(){ if [ "$2" -gt 0 ]; then ok "premise: $1 answered $2 callee rows"; else no "premise: $1 answered no callee rows (vacuous)"; fi; }

echo "genericskipcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }

# ── G1: the C# corpus (written here; no file of this tree is a fixture) ────────────────────────────────────────────────
# Util.Make<T> and Other.Make<T>, Widget.Bump<T> and Gadget.Bump<T>: two definitions per name, so only the receiver picks one.
mkdir -p "$DIR/cs"
cat >"$DIR/cs/Util.cs" <<'E'
namespace P { public static class Util { public static int Make<T>(object x) { return 1; } }
public static class Other { public static int Make<T>(object x) { return 2; } public static int Self() { return Make<int>(null); } }
public class Widget { public int Bump<T>() { return 3; } }
public class Gadget { public int Bump<T>() { return 4; } } }
E
cat >"$DIR/cs/Main.cs" <<'E'
using System.Collections.Generic;
namespace P { public static class Main {
public static int CallE(object x) { return Util.Make<int>(x); }
public static int CallB(object x) { return Util.Make<Dictionary<string, List<List<int>>>>(x); }
public static int CallW(Widget w) { return w.Bump<int>(); }
public static int CallQ(Widget w) { return w?.Bump<int>() ?? 0; }
public static int CallE0(object x) { return Util.Make(x); }
} }
E
E1="$( callees "$DIR/cs" CallE )"; B1="$( callees "$DIR/cs" CallB )"; W1="$( callees "$DIR/cs" CallW )"; Q1="$( callees "$DIR/cs" CallQ )"
E0="$( callees "$DIR/cs" CallE0 )"; S0="$( callees "$DIR/cs" Self )"
premise "the C# corpus" "$( printf '%s\n' "$E1" "$B1" "$W1" "$Q1" "$E0" "$S0" | grep -c '<s ' )"

echo "── [P] G1: a C# generic member call keeps its receiver"
has   "$E1" '<s t="method" n="Make" p="Util.cs:1"/>'   "[P1] Util.Make<int>(x): --callees CallE lists Util's Make, receiver-pinned"
hasnt "$E1" 'p="Util.cs:2"'                            "[P1] ... and not Other's namesake Make"
has   "$B1" '<s t="method" n="Make" p="Util.cs:1"/>'   "[P2] nested Util.Make<Dictionary<string, List<List<int>>>>(x): Util's Make"
hasnt "$B1" 'p="Util.cs:2"'                            "[P2] ... and not Other's namesake Make"
has   "$W1" '<s t="method" n="Bump" p="Util.cs:3"/>'   "[P3] typed receiver w.Bump<int>(): Widget's Bump"
hasnt "$W1" 'p="Util.cs:4"'                            "[P3] ... and not Gadget's namesake Bump"
has   "$Q1" '<s t="method" n="Bump" p="Util.cs:3"/>'   "[P4] conditional access w?.Bump<int>(): Widget's Bump"
hasnt "$Q1" 'p="Util.cs:4"'                            "[P4] ... and not Gadget's namesake Bump"

echo "── [C] G1 controls"
has   "$E0" '<s t="method" n="Make" p="Util.cs:1"/>'   "[C1] Util.Make(x) without type arguments: Util's Make"
hasnt "$E0" 'p="Util.cs:2"'                            "[C1] ... and not Other's namesake Make"
has   "$S0" '<s t="method" n="Make" p="Util.cs:2"/>'   "[C2] a bare generic Make<int>(null) is no member call: the enclosing class Other's Make"
hasnt "$S0" 'p="Util.cs:1"'                            "[C2] ... and not Util's Make"

# ── G2: the C/C++ macro corpus ──────────────────────────────────────────────────────────────────────────────────────────
# lib.h defines the template make, Envoy::returnOrThrow, and plain functions cmpa/cmpx/cmpz/cmpq that only a FALSE edge from a
# comparison would reach. plain.c is C: no templates exist there, so `cmpc<b>( c )` is a comparison by language.
mkdir -p "$DIR/cpp"
cat >"$DIR/cpp/lib.h" <<'E'
template <class T> int make( int x ) { return x; }
namespace Envoy { template <class T> T returnOrThrow( int v ) { return T( v ); } }
int cmpa( int x ) { return x; }
int cmpx( int x ) { return x; }
int cmpz( int x ) { return x; }
int cmpq( int x ) { return x; }
E
cat >"$DIR/cpp/main.cpp" <<'E'
#include "lib.h"
#define M_E( x ) make<int>( x )
#define M_B( x ) make<List<int>>( x )
#define THROW_OR_RETURN_VALUE( expression, type ) \
  ::Envoy::returnOrThrow<type>( expression )
#define M_STR( x ) make<decltype( ">" )>( x )
#define M_PAREN( x ) make<Cond<( 1 > 0 )>>( x )
#define M_SPLIT( x ) make<int, \
                          long>( x )
#define M_RREF( x ) make<int&&>( x )
#define M_E0( x ) make( x )
#define N_CMP( b, c ) cmpa < b > ( c )
#define N_AND( y, w ) cmpx < y && cmpz > ( w )
#define N_AND2( y, w ) cmpx<y && cmpz>( w )
#define N_OR( y, w ) cmpx<y || cmpz>( w )
#define N_SHIFT( y, w ) cmpa<<y>( w )
int caller( int x ) { return M_E( x ); }
E
cat >"$DIR/cpp/line.cpp" <<'E'
#include "lib.h"
#define N_LINE( x ) cmpq<int // >( x )
E
cat >"$DIR/cpp/plain.c" <<'E'
int cmpc( int x ) { return x; }
#define C_CMP( b, c ) cmpc<b>( c )
E
ME="$( callees "$DIR/cpp" M_E )"; MB="$( callees "$DIR/cpp" M_B )"; MT="$( callees "$DIR/cpp" THROW_OR_RETURN_VALUE )"
MS="$( callees "$DIR/cpp" M_STR )"; MP="$( callees "$DIR/cpp" M_PAREN )"; ML="$( callees "$DIR/cpp" M_SPLIT )"
MR="$( callees "$DIR/cpp" M_RREF )"; M0="$( callees "$DIR/cpp" M_E0 )"
NC="$( callees "$DIR/cpp" N_CMP )"; NA="$( callees "$DIR/cpp" N_AND )"; NA2="$( callees "$DIR/cpp" N_AND2 )"
NO="$( callees "$DIR/cpp" N_OR )"; NS="$( callees "$DIR/cpp" N_SHIFT )"; NL="$( callees "$DIR/cpp" N_LINE )"
CC="$( callees "$DIR/cpp" C_CMP )"
if ! CR="$( ( cd "$DIR/cpp" && "$BIN" . --no-cache --callers=returnOrThrow --legend=compact 2>&1 ) )"; then
    no "--callers=returnOrThrow exited non-zero"
fi
premise "the C/C++ macro corpus" "$( printf '%s\n' "$ME" "$MB" "$MT" "$MS" "$MP" "$ML" "$MR" "$M0" | grep -c '<s ' )"

echo "── [P] G2: a macro body's name<..>( is a call"
has "$ME" 'n="make" p="lib.h:1"'           "[P5] make<int>( x ): --callees M_E lists make"
has "$MB" 'n="make" p="lib.h:1"'           "[P6] nested make<List<int>>( x ): --callees M_B lists make"
has "$MT" 'n="returnOrThrow" p="lib.h:2"' "[P7] envoy's ::Envoy::returnOrThrow<type>( expression ) on a continuation line: --callees lists returnOrThrow"
has "$CR" 'n="THROW_OR_RETURN_VALUE"'      "[P7] --callers returnOrThrow lists THROW_OR_RETURN_VALUE"
has "$MS" 'n="make" p="lib.h:1"'           "[P8] a string literal \">\" inside the arguments: --callees M_STR lists make"
has "$MP" 'n="make" p="lib.h:1"'           "[P9] a parenthesised ( 1 > 0 ) inside the arguments: --callees M_PAREN lists make"
has "$ML" 'n="make" p="lib.h:1"'           "[P10] arguments split over a \\-continuation: --callees M_SPLIT lists make"
has "$MR" 'n="make" p="lib.h:1"'           "[P11] an rvalue reference make<int&&>( x ): --callees M_RREF lists make"

echo "── [C] G2 control"
has "$M0" 'n="make" p="lib.h:1"'           "[C3] make( x ) without type arguments: --callees M_E0 lists make"

echo "── [N] G2 near misses: a comparison is no call"
nfound="$( printf '%s\n' "$NC" "$NA" "$NA2" "$NO" "$NS" "$NL" "$CC" | grep -cx FOUND )"
if [ "$nfound" -eq 7 ]; then ok "premise: all 7 near-miss macros resolved"; else no "premise: $nfound of 7 near-miss macros resolved (a hasnt arm would pass blind)"; fi
hasnt "$NC"  'n="cmpa"'                    "[N1] cmpa < b > ( c ): no call of cmpa"
hasnt "$NA"  'n="cmpx"'                    "[N2] cmpx < y && cmpz > ( w ): no call of cmpx"
hasnt "$NA"  'n="cmpz"'                    "[N2] ... nor of cmpz"
hasnt "$NA2" 'n="cmpx"'                    "[N3] cmpx<y && cmpz>( w ), written flush: no call of cmpx (a conjunction is no argument)"
hasnt "$NO"  'n="cmpx"'                    "[N4] cmpx<y || cmpz>( w ): no call of cmpx"
hasnt "$NS"  'n="cmpa"'                    "[N5] cmpa<<y>( w ), a shift: no call of cmpa"
hasnt "$NL"  'n="cmpq"'                    "[N6] cmpq<int // >( x ): the // comment ends the macro, no call of cmpq"
hasnt "$CC"  'n="cmpc"'                    "[N7] C has no templates: cmpc<b>( c ) in a .c #define is no call of cmpc"

if [ "$arms" -eq 0 ]; then
    no "no arm ran (vacuous)"
fi
if [ "$fail" -ne 0 ]; then
    echo "genericskipcheck: FAIL ($arms arms)"
    exit 1
fi
echo "genericskipcheck: PASS ($arms arms)"
