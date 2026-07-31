#!/usr/bin/env bash
# reachcheck.sh — GRAPH-REACHABILITY gate for the three verbs that walk the call graph transitively but
# had ZERO coverage before this gate: --path=SRC,DST (shortest directed call-path), --impact=SYM
# (transitive blast radius: everything that REACHES SYM), and --callees=SYM (1-hop out-edges — the mirror
# of --callers, which callerscheck.sh already pins). These three are the "is it safe to change X?" surface;
# a wrong edge or a reversed direction here silently misleads an agent about blast radius.
#
# Fixture: test/queryfix (reused, no new fixture — its call graph is hand-verified by querycheck.sh):
#   chain.cpp:  d1 -> d2 -> d3 -> d4                     (linear directed chain, calls point "downstream")
#   util.cpp:   caller_a() -> hot(), caller_b() -> hot() (two callers of one leaf)
#               rec() self-recursive (self-loops DROPPED by design — see callerscheck.sh header)
#
# Every expected value below is hand-computed from that graph, not observed-and-frozen:
#   --path=d1,d4      : reachable=1, hops=3, node order d1,d2,d3,d4 (the unique directed route)
#   --path=d4,d1      : reachable=0 (edges are directed downstream; no route back up)
#   --path=d1,hot     : reachable=0 (disjoint components — chain never reaches util's hot)
#   --impact=d4       : reaches=3, exactly {d3,d2,d1} (everything upstream of the leaf)
#   --impact=hot      : reaches=2, exactly {caller_a,caller_b}
#   --impact=d1       : reaches=0 (head of chain — nothing calls into it)
#   --callees=d2      : count=1, exactly {d3}  (mirror of --callers=d3 == {d2})
#   --callees=d4      : count=0 (leaf calls nothing in-corpus)
#   --callees=bogus   : exit non-zero + "not found"
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/reachcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/queryfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/queryfix dir — fixture missing"; exit 2; }
cd "$ROOT"
echo "reachcheck: BIN=$BIN  CORPUS=test/queryfix"

run(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" "$@" --no-cache 2>/dev/null; }
attr(){ printf '%s' "$1" | grep -oE "$2=\"[0-9]+\"" | head -1 | grep -oE '[0-9]+'; }
# ordered list of the n="…" symbol names, in emission order
names(){ printf '%s' "$1" | grep -oE '<s [^>]*n="[^"]*"' | grep -oE 'n="[^"]*"' | sed 's/n="//;s/"$//'; }

# ── 1) --path=d1,d4 : the unique directed route, in order ────────────────────────────────────────────
P="$( run --path=d1,d4 )"
{ [ "$( attr "$P" reachable )" = 1 ] && [ "$( attr "$P" hops )" = 3 ] \
    && [ "$( names "$P" | tr '\n' ',' )" = "d1,d2,d3,d4," ]; } \
    && ok "--path=d1,d4: reachable=1 hops=3, node order d1->d2->d3->d4" \
    || no "--path=d1,d4 wrong (reachable=$( attr "$P" reachable ) hops=$( attr "$P" hops ) order=$( names "$P" | tr '\n' ',' ))"

# ── 2) --path=d4,d1 : NO route back up a directed chain ──────────────────────────────────────────────
Pu="$( run --path=d4,d1 )"
[ "$( attr "$Pu" reachable )" = 0 ] \
    && ok "--path=d4,d1: reachable=0 (edges directed downstream — no upstream route)" \
    || no "--path=d4,d1 should be reachable=0, got reachable=$( attr "$Pu" reachable )"

# ── 3) --path across DISJOINT components (chain never reaches util's hot) ─────────────────────────────
Pd="$( run --path=d1,hot )"
[ "$( attr "$Pd" reachable )" = 0 ] \
    && ok "--path=d1,hot: reachable=0 (disjoint components)" \
    || no "--path=d1,hot should be reachable=0, got reachable=$( attr "$Pd" reachable )"

# ── 4) --impact=d4 : the full upstream set {d3,d2,d1}, and NOTHING else ───────────────────────────────
I4="$( run --impact=d4 )"
I4NAMES="$( names "$I4" | sort | tr '\n' ',' )"
{ [ "$( attr "$I4" reaches )" = 3 ] && [ "$I4NAMES" = "d1,d2,d3," ]; } \
    && ok "--impact=d4: reaches=3, exactly {d1,d2,d3} (all upstream of the leaf)" \
    || no "--impact=d4 wrong (reaches=$( attr "$I4" reaches ) set=$I4NAMES)"

# ── 5) --impact=hot : exactly the two callers ────────────────────────────────────────────────────────
Ih="$( run --impact=hot )"
IhNAMES="$( names "$Ih" | sort | tr '\n' ',' )"
{ [ "$( attr "$Ih" reaches )" = 2 ] && [ "$IhNAMES" = "caller_a,caller_b," ]; } \
    && ok "--impact=hot: reaches=2, exactly {caller_a,caller_b}" \
    || no "--impact=hot wrong (reaches=$( attr "$Ih" reaches ) set=$IhNAMES)"

# ── 6) --impact=d1 : head of chain — nothing reaches it → reaches=0, no crash ─────────────────────────
I1="$( run --impact=d1 )"
run --impact=d1 >/dev/null 2>&1; I1EC=$?
{ [ "$( attr "$I1" reaches )" = 0 ] && [ "$I1EC" = 0 ]; } \
    && ok "--impact=d1: reaches=0 (head of chain), exit 0 (empty is not an error)" \
    || no "--impact=d1 wrong (reaches=$( attr "$I1" reaches ) exit=$I1EC)"

# ── 7) --callees=d2 : exactly {d3} — the exact mirror of --callers=d3=={d2} ───────────────────────────
C2="$( run --callees=d2 )"
{ [ "$( attr "$C2" count )" = 1 ] && printf '%s' "$C2" | grep -qE '<s t="fn" n="d3" p="[^"]*chain\.cpp:2"/>'; } \
    && ok "--callees=d2: count=1, exactly d3 (chain.cpp:2)" \
    || no "--callees=d2 wrong — got: $C2"

# ── 8) --callees=d4 : leaf calls nothing in-corpus → count=0 ──────────────────────────────────────────
C4="$( run --callees=d4 )"
[ "$( attr "$C4" count )" = 0 ] \
    && ok "--callees=d4: count=0 (leaf, no out-edges)" \
    || no "--callees=d4 should be count=0, got: $C4"

# ── 9) --callees of a nonexistent symbol → non-zero exit + 'not found' ────────────────────────────────
CBMSG="$( "$BIN" "$FIX" --callees=totally_bogus_zzz --no-cache 2>&1 1>/dev/null )"
run --callees=totally_bogus_zzz >/dev/null 2>&1; CBEC=$?
{ [ "$CBEC" != 0 ] && printf '%s' "$CBMSG" | grep -qi "not found"; } \
    && ok "--callees of nonexistent symbol: non-zero exit ($CBEC) + 'not found' message" \
    || no "--callees bogus: expected non-zero exit + 'not found', got exit=$CBEC msg='$CBMSG'"

# ── 10) direction sanity: callees(d2)=={d3} and callers(d2)=={d1} are DISJOINT — proves the two verbs are
#        not accidentally the same code path (a real regression risk when one wraps the other) ─────────
callers_d2="$( names "$( run --callers=d2 )" | sort | tr '\n' ',' )"
callees_d2="$( names "$( run --callees=d2 )" | sort | tr '\n' ',' )"
{ [ "$callers_d2" = "d1," ] && [ "$callees_d2" = "d3," ]; } \
    && ok "--callers=d2 ({d1}) and --callees=d2 ({d3}) are distinct — direction not collapsed" \
    || no "direction collapse suspected: callers(d2)=$callers_d2 callees(d2)=$callees_d2"

# ── 11) determinism (spot-check --impact) ────────────────────────────────────────────────────────────
[ "$( run --impact=d4 )" = "$( run --impact=d4 )" ] \
    && ok "determinism: --impact=d4 byte-identical run-to-run" || no "--impact non-deterministic"

# ── 12) xml well-formed for all three verbs ──────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xw=0
    for out in "$P" "$I4" "$C2"; do printf '%s' "$out" | xmllint --noout - 2>/dev/null || xw=1; done
    [ "$xw" = 0 ] && ok "xml well-formed (--path/--impact/--callees)" || no "xml malformed in one of --path/--impact/--callees"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
