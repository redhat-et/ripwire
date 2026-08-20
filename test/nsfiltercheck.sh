#!/usr/bin/env bash
# nsfiltercheck.sh — the namespaceCompatible( RefRole, SymKind ) gate (resolver-precision round,
# docs/EVALS.md §4 "Type-mention use-sites + namespace-compatible candidates", PRE-REGISTERED
# 2026-08-20).
#
# WHAT THE PREDICATE IS. src/graph.h::namespaceCompatible is the ONE place the repo states which
# definition KINDS a reference of a given ROLE may bind to. Before it, the same rule was hard-coded in
# three places that had drifted apart: the SCIP inherit overlay's `isClassLikeK`, the implementors
# builder's `isClassLike`, and the compose-edge builder's bare `k != Class && k != Struct`.
#
# THE HARD CONSTRAINT THIS GATE EXISTS TO PIN. `RefRole::Call` must stay UN-narrowed. In C++ the
# spelling `Handler( 3 )` is legitimately a constructor call, a functional cast, OR a free function,
# so narrowing Call to Function|Method would DROP real edges — and src/resolve.h's standing doctrine
# is that a WRONG narrow is worse than no narrow. A future round that "tidies" Call into the predicate
# turns arm 2 red.
#
# MEASURED FINDING, recorded here because it is what the gate can and cannot prove (EVALS §4): the
# call-edge resolve loop in graph.h admits ONLY role=Call and role=Macro, and a role=Macro reference's
# name is uniquely a macro by construction (model.h::scanMacroNames flags==1 over exactly the language
# set langCompatible bridges). With Call excluded by the constraint above, the predicate is therefore a
# PROVABLE NO-OP inside that loop — the map header's `ambiguous=` cannot move. Arm 4 pins that: a
# fixture built to be maximally ambiguous by kind still reports ambiguous=0, which is the honest
# statement that this lever does not live here. (It was "arm 3" here until 2026-08-20; the no-op arm has
# always been arm 4. Being invariant by construction, it can never fire — arm 5 is the one that can.)
#
#   test/nsfiltercheck.sh                       # uses build/ripwire on test/nsfilterfix
#   RIPWIRE_BIN=asan/ripwire test/nsfiltercheck.sh
#
# Fixture test/nsfilterfix/ (C++): a.h `class Handler`, b.cpp a free `int Handler( int )` sharing the
# name, c.cpp `class Derived : public Handler`, d.cpp both `Handler( 3 )` (a call) and `Handler h;`
# (a type mention) so the two namespaces meet on one name in one file.
#
# Five arms:
#   1) RED PRE-FIX — `Handler h;` in d.cpp is a TYPE mention and yields a role="type" use-site.
#   2) Call stays un-narrowed: `Handler( 3 )` still yields its role="call" use-site AND its call edge.
#   3) The class-like relations survive the refactor: the base clause in c.cpp still binds Handler as
#      role="extends", and `--lego=Handler` still lists Derived through the implementors relation.
#   4) The no-op statement: edges=2 ambiguous=0 over the fixture, unchanged by the predicate.
#   5) THE LIVE EFFECT — see below.
#
# WHY ARM 5 EXISTS (adversarial verification, 2026-08-20). Arms 1-4 are all invariant under FULL REMOVAL
# of the predicate's narrowing (`case Type: case Extends: return true; case Macro: return true;`): the
# mutated binary leaves this gate 8/8 PASS, exit 0. Arm 1 re-tests the RefRole::Type widening, which
# typerefcheck.sh already owns; arm 4 asserts the no-op, which is by construction invariant. So the gate
# named for the predicate could not observe the predicate at all.
#
# The narrowing's one LIVE effect is contextratio.h's all-roles resolution, and the role that reaches it
# is Extends, NOT Type (collectFacts `continue`s on Type 28 lines before resolveCandidates is called).
# The base clause `class Derived : public Handler` in c.cpp is that Extends reference, and without the
# narrowing it binds to BOTH `class Handler` and the free `int Handler( int )`. Measured, same tree, only
# the predicate differing:
#
#     shipped   s p="c.cpp:5" n="Derived" … ents="1" files="1" rtok="11" amb="0"
#     stripped  s p="c.cpp:5" n="Derived" … ents="2" files="2" rtok="22" amb="1"
#
# Arm 5 pins amb="0" / ents="1" on that row, so full removal of the narrowing is now red here — on this
# gate's OWN fixture, in the one place the predicate is measurable.
#
# Plus determinism and XML well-formedness. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/nsfilterfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "nsfiltercheck: BIN=$BIN  FIX=$FIX"

# ── 0) presence guards ────────────────────────────────────────────────────────────────────────────
grep -q 'class Handler' "$FIX/a.h"            || no "presence guard: a.h must define class Handler"
grep -q 'int Handler( int x )' "$FIX/b.cpp"   || no "presence guard: b.cpp must define the rival free function"
grep -q 'public Handler' "$FIX/c.cpp"         || no "presence guard: c.cpp must derive from Handler"
grep -q 'return Handler( 3 );' "$FIX/d.cpp"   || no "presence guard: d.cpp must CALL Handler( 3 )"
grep -q 'Handler h;' "$FIX/d.cpp"             || no "presence guard: d.cpp must NAME Handler as a type"
[ "$fail" -eq 0 ] || { echo "SOME CHECKS FAILED"; exit 1; }

USES="$( "$BIN" "$FIX" --uses=Handler --no-cache 2>/dev/null | tr '<' '\n' | grep -E '^u role=' )"
HDR="$( "$BIN" "$FIX" --no-cache 2>/dev/null )"

# ── 1) RED PRE-FIX: the bare type mention `Handler h;` is a use-site ──────────────────────────────
TYPELINE="$( grep -n 'Handler h;' "$FIX/d.cpp" | head -1 | cut -d: -f1 )"
if printf '%s\n' "$USES" | grep 'role="type"' | grep -q "d\.cpp:$TYPELINE"; then
    ok "type mention: role=\"type\" row at d.cpp:$TYPELINE"
else
    no "no role=\"type\" row at d.cpp:$TYPELINE — the bare type mention is still invisible"
    printf '    %s\n' "$USES"
fi

# ── 2) THE CONSTRAINT: Call stays un-narrowed — the constructor-shaped call keeps its site AND edge ─
CALLLINE="$( grep -n 'return Handler( 3 );' "$FIX/d.cpp" | head -1 | cut -d: -f1 )"
if printf '%s\n' "$USES" | grep 'role="call"' | grep -q "d\.cpp:$CALLLINE"; then
    ok "Call un-narrowed: role=\"call\" row survives at d.cpp:$CALLLINE"
else
    no "Call was NARROWED: the call site at d.cpp:$CALLLINE lost its role=\"call\" row — a wrong narrow"
    printf '    %s\n' "$USES"
fi
NCE="$( "$BIN" "$FIX" --callees=useHandler --no-cache 2>/dev/null | grep -oE 'count="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
NCE="${NCE:-0}"
if [ "$NCE" -ge 1 ]; then
    ok "Call un-narrowed: useHandler still has $NCE callee edge(s) for the Handler(3) site"
else
    no "Call was NARROWED: useHandler lost its call edge (callees count=$NCE) — real edges dropped"
fi

# ── 3) the class-like relations survive the predicate refactor ────────────────────────────────────
EXTLINE="$( grep -n 'public Handler' "$FIX/c.cpp" | head -1 | cut -d: -f1 )"
if printf '%s\n' "$USES" | grep 'role="extends"' | grep -q "c\.cpp:$EXTLINE"; then
    ok "base clause still binds Handler as role=\"extends\" at c.cpp:$EXTLINE"
else
    no "the base clause at c.cpp:$EXTLINE lost its role=\"extends\" row"
fi
LEGO="$( "$BIN" "$FIX" --lego=Handler --no-cache 2>/dev/null )"
if printf '%s' "$LEGO" | grep -q 'impl n="Derived"'; then
    ok "implementors relation intact: --lego=Handler still lists Derived as an implementor"
else
    no "implementors relation BROKEN: --lego=Handler no longer lists Derived"
fi

# ── 4) the no-op statement: the predicate cannot move the call graph over this fixture ────────────
E="$( printf '%s' "$HDR" | grep -oE ' edges=[0-9]+' | head -1 | grep -oE '[0-9]+' )"; E="${E:-x}"
A="$( printf '%s' "$HDR" | grep -oE ' ambiguous=[0-9]+' | head -1 | grep -oE '[0-9]+' )"; A="${A:-x}"
if [ "$E" = "2" ] && [ "$A" = "0" ]; then
    ok "call graph unchanged: edges=$E ambiguous=$A — the predicate is a no-op in the resolve loop, as registered"
else
    no "call graph MOVED: edges=$E ambiguous=$A (expected 2/0) — re-derive EVALS §4 before believing this"
fi

# ── 5) THE LIVE EFFECT: the Extends base clause resolves to ONE entity, not two ───────────────────
# contextratio.h's resolveCandidates is the only caller-visible place the narrowing bites. Presence
# guard first (a vanished row must not read as a pass), then the assertion.
CR="$( "$BIN" "$FIX" --context-ratio --no-cache 2>/dev/null | tr '<' '\n' | grep -E '^s p="c\.cpp:'"$EXTLINE"'"' )"
if [ -z "$CR" ]; then
    no "presence guard: --context-ratio emits no row for Derived at c.cpp:$EXTLINE — arm 5 cannot observe anything"
else
    CENTS="$( printf '%s' "$CR" | grep -oE ' ents="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"; CENTS="${CENTS:-x}"
    CAMB="$( printf '%s' "$CR" | grep -oE ' amb="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"; CAMB="${CAMB:-x}"
    if [ "$CENTS" = "1" ] && [ "$CAMB" = "0" ]; then
        ok "live effect: the Extends base clause at c.cpp:$EXTLINE resolves to ents=$CENTS amb=$CAMB — the free int Handler(int) is NOT a candidate"
    else
        no "NARROWING GONE: Derived at c.cpp:$EXTLINE reports ents=$CENTS amb=$CAMB (expected 1/0) — the base clause is binding the same-named FUNCTION too"
        printf '    %s\n' "$CR"
    fi
fi

# ── 6) determinism ───────────────────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/r1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/r2" 2>/dev/null
if cmp -s "$TMP/r1" "$TMP/r2"; then ok "deterministic (two --no-cache runs byte-identical)"; else no "non-deterministic over the fixture"; fi

# ── 7) well-formed XML ───────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if "$BIN" "$FIX" --uses=Handler --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null; then
        ok "xml well-formed (--uses over the fixture)"
    else
        no "xml malformed (--uses over the fixture)"
    fi
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
