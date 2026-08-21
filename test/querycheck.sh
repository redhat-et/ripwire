#!/usr/bin/env bash
# querycheck.sh — gate for ABS-5: composable graph-query operators (--graph-query=EXPR). A FIXED, CLOSED
# operator set (NOT a Datalog engine): sources name()/all; filters kind/cx/fanin/file; bounded transitive-
# closure callers/callees(SET[,depth]); 2-relation joins and/or/not. Each evaluates to a deterministic,
# sorted node-set.
#
# Fixture test/queryfix/ has a hand-verifiable call graph:
#   chain.cpp:  d1 -> d2 -> d3 -> d4            (a linear chain — depth-bounded closure has exact answers)
#   util.cpp:   struct Gadget;  hot() (complex, cx>=3, called by caller_a + caller_b);  rec() (self-recursive)
# 8 functions + 1 class total.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/querycheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/queryfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/queryfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "querycheck: BIN=$BIN  CORPUS=test/queryfix"

# run a query (alarm-guarded so a hang fails loudly instead of blocking the gate)
q(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" --graph-query="$1" --no-cache 2>/dev/null; }
# the count="N" of a query's result set
cnt(){ q "$1" | grep -oE 'count="[0-9]+"' | grep -oE '[0-9]+'; }
# the exit code of a query (for the error/degrade paths)
ec(){ perl -e 'alarm 8; exec @ARGV' "$BIN" "$FIX" --graph-query="$1" --no-cache >/dev/null 2>&1; echo $?; }
# assert cnt(expr) == want
is(){ local got; got="$( cnt "$1" )"; [ "$got" = "$2" ] || { printf '%s' "  (got '$got' want '$2' for: $1)"; return 1; }; return 0; }

# ── sources ──────────────────────────────────────────────────────────────────────────────────────────
is 'name("d4")' 1 && ok "source name(): d4 → 1" || no "source name()$(is 'name("d4")' 1)"

# ── bounded transitive closure: depth controls reach (the load-bearing operator) ──────────────────────
{ is 'callers(name("d4"),1)' 1 && is 'callers(name("d4"),2)' 2 && is 'callers(name("d4"),3)' 3; } \
    && ok "closure: callers(d4) at depth 1/2/3 → 1/2/3 (bounded transitive reach over the chain)" \
    || no "closure depth ladder wrong (callers(d4) 1/2/3 should be 1/2/3)"
is 'callees(name("d1"),3)' 3 && ok "closure: callees(d1,3) → d2,d3,d4 (3, out-edge direction)" || no "callees(d1,3) should be 3"

# ── filters (node predicates) ─────────────────────────────────────────────────────────────────────────
{ is 'kind(all,fn)' 8 && is 'kind(all,cls)' 1; } && ok "filter kind: 8 fn + 1 cls (Gadget)" || no "kind filter counts wrong"
{ is 'cx(name("hot"),3)' 1 && is 'cx(name("d4"),3)' 0; } && ok "filter cx>=3: catches complex hot(), not trivial d4()" || no "cx filter wrong"
{ is 'fanin(name("hot"),2)' 1 && is 'fanin(name("hot"),3)' 0; } && ok "filter fanin>=2: hot() has exactly 2 callers" || no "fanin filter wrong"
is 'file(all,"chain")' 4 && ok "filter file~chain: 4 nodes (d1..d4)" || no "file filter should be 4"

# ── 2-relation joins ──────────────────────────────────────────────────────────────────────────────────
is 'and(callers(name("d4"),3),file(all,"chain"))' 3 && ok "join and: callers(d4,3) ∩ file(chain) = 3 (d1,d2,d3)" || no "and join wrong"
is 'or(name("d4"),name("hot"))' 2 && ok "join or: d4 ∪ hot = 2" || no "or join wrong"
is 'not(callers(name("d4"),3),name("d2"))' 2 && ok "join not: callers(d4,3) − d2 = 2 (d1,d3)" || no "not join wrong"

# ── C3: and()'s predicate-pushdown, EXACT equivalence — X ∩ {n∈all:P(n)} ≡ {n∈X:P(n)}, same sorted-unique
#    vector either way. Byte-compare (query-header `expr=` attr stripped — it just echoes the literal query
#    text, which differs on purpose between these spellings) a pushdown-eligible query against BOTH and()-arg
#    orders and an "unpushed" control spelling: wrapping the source in `or(all,all)` (== all, but syntactically
#    NOT the bare literal `all` the pushdown shape-check looks for) forces the plain eager path even in a
#    binary that HAS the pushdown, giving a true byte-for-byte ground truth instead of just re-asserting a count.
norm(){ sed -E 's/expr="[^"]*"//'; }
PD1="$( q 'and(callers(name("d4"),3),file(all,"chain"))'          | norm )"   # node-set, then predicate(all,…)
PD2="$( q 'and(file(all,"chain"),callers(name("d4"),3))'          | norm )"   # predicate(all,…), then node-set
REF1="$( q 'and(callers(name("d4"),3),file(or(all,all),"chain"))' | norm )"   # unpushed control, order A
REF2="$( q 'and(file(or(all,all),"chain"),callers(name("d4"),3))' | norm )"   # unpushed control, order B
{ [ -n "$PD1" ] && [ "$PD1" = "$PD2" ] && [ "$PD1" = "$REF1" ] && [ "$PD1" = "$REF2" ]; } \
    && ok "pushdown equivalence: file(all,…) mixed with a node-set, both and()-arg orders, byte-identical to an unpushed control" \
    || no "pushdown equivalence broke: PD1/PD2/REF1/REF2 differ (file())"
PD3="$( q 'and(kind(all,fn),callers(name("d4"),3))'          | norm )"        # predicate(all,…) as the FIRST arg
REF3="$( q 'and(kind(or(all,all),fn),callers(name("d4"),3))' | norm )"
[ "$PD3" = "$REF3" ] && ok "pushdown equivalence: kind(all,…) as and()'s first arg matches its unpushed control" \
    || no "kind(all,…) pushdown differs from its unpushed control"

# ── C3: the and(∅,X) trap — one arm legitimately empty must NOT short-circuit evaluation of the OTHER arm.
#    cx(all,999999) is pushdown-eligible AND empty (no fixture function has cx that high) — a naive
#    implementation that skips the other and()-arm once either side looks empty would never call sourceName()
#    on the buried typo, so its did-you-mean refusal would silently vanish (exit 0, not exit 1). Both arg
#    orders, so the trap is caught whether the empty side parses first or second. ─────────────────────────
[ "$( ec 'and(cx(all,999999),name("notARealSymbolXYZ"))' )" = 1 ] \
    && ok "and(empty pushdown predicate, name()-typo): typo still refused — right arm still evaluated" \
    || no "and(empty pushdown side, typo side) did not refuse (exit != 1) — right arm was short-circuited away"
[ "$( ec 'and(name("notARealSymbolXYZ"),cx(all,999999))' )" = 1 ] \
    && ok "and(name()-typo, empty pushdown predicate): typo still refused — left arm still evaluated" \
    || no "and(typo side, empty pushdown side) did not refuse (exit != 1) — left arm was short-circuited away"

# ── ranking + --top-k cap: a broad node-set is ranked by importance and capped (no token bomb); count = the
#    TRUE total, shown = what was emitted. (8 fns in the fixture, capped to 3.) ──────────────────────────
capout="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" --graph-query='kind(all,fn)' --top-k=3 --no-cache 2>/dev/null )"
capc="$( printf '%s' "$capout" | grep -oE 'count="[0-9]+"' | grep -oE '[0-9]+' )"
caps="$( printf '%s' "$capout" | grep -oE 'shown="[0-9]+"' | grep -oE '[0-9]+' )"
capf="$( printf '%s' "$capout" | grep -oE 'capped="[01]"' | grep -oE '[01]' )"
{ [ "$capc" = 8 ] && [ "$caps" = 3 ] && [ "$capf" = 1 ]; } \
    && ok "--top-k cap: kind(all,fn) --top-k=3 → count=8 (true total) shown=3 capped=1 (ranked + capped)" \
    || no "--top-k cap wrong (count=$capc shown=$caps capped=$capf, want 8/3/1)"

# §P8 vocabulary: count=/shown= shipped with NO capped=, so a caller had to know the default top-k to tell
# a complete answer from a truncated one. Rule 3 (src/pageview.h, THE TRUNCATION VOCABULARY): the bit rides
# with shown= ALWAYS — including the untruncated case, where it must read "0" and never go missing.
fullout="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" --graph-query='kind(all,fn)' --no-cache 2>/dev/null )"
printf '%s' "$fullout" | grep -qE 'count="8" shown="8" capped="0"' \
    && ok "--graph-query untruncated: count=8 shown=8 capped=\"0\" (no false alarm, no missing bit)" \
    || no "--graph-query untruncated does not report count=8 shown=8 capped=\"0\""

# ── robustness: parse errors + a malformed regex DEGRADE to a clean exit 1 (no hang, no crash) ─────────
[ "$( ec 'callers(name("x")' )" = 1 ]  && ok "malformed expression → exit 1 (parse error reported)" || no "malformed expr should exit 1"
[ "$( ec 'frobnicate(all)' )"   = 1 ]  && ok "unknown operator → exit 1" || no "unknown op should exit 1"
[ "$( ec 'file(all,"a{2,")' )"  = 1 ]  && ok "malformed file() regex → degrades to exit 1 (no hang/crash)" || no "bad regex should exit 1"

# ── cycle-safety: a self-recursive function's closure must terminate (seen-set caps each node once) ────
perl -e 'alarm 8; exec @ARGV' "$BIN" "$FIX" --graph-query='callers(name("rec"),9)' --no-cache >/dev/null 2>&1; rcy=$?
[ "$rcy" = 0 ] && ok "cycle-safety: self-recursive rec() closure terminates (no hang on a cyclic call graph)" || no "rec closure hung/failed (exit $rcy)"

# ── determinism + well-formedness ─────────────────────────────────────────────────────────────────────
A="$( q 'and(kind(all,fn),callers(name("d4"),3))' )"; B="$( q 'and(kind(all,fn),callers(name("d4"),3))' )"
[ "$A" = "$B" ] && ok "deterministic (composed query byte-identical run-to-run)" || no "non-deterministic"
if command -v xmllint >/dev/null 2>&1; then
    q 'and(callers(name("d4"),3),kind(all,fn))' | xmllint --noout - 2>/dev/null && ok "xml well-formed" || no "xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
