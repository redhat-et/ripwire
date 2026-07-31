#!/usr/bin/env bash
# csharpcondcheck.sh — H4 round: C# call-FORM coverage gate (conditional access `?.` + ref-vs-edge
# accounting). Modeled on csharpcheck.sh / javarubycheck.sh conventions (CTXPACK_BIN, --no-cache,
# PASS/FAIL per check, ALL PASS on success, mutation arm so the edge assertions are non-tautological).
#
# Fixture: test/csharpfix is NOT reused — this gate needs a single file holding every call SPELLING,
# split across three callers so each spelling is attributable by caller NAME. See test/csharpcondfix/Cond.cs.
#
# ── WHAT THIS GATE IS FOR (two independent things, both discovered by probing, never by reading the query) ──
#
# 1. `?.`-guarded calls were dropped at EXTRACTION. tree-sitter-c-sharp parses `w?.Bump()` as an
#    invocation_expression whose `function:` child is a conditional_access_expression, with the invoked
#    name one level down in a member_binding_expression. queries/csharp/tags.scm mentioned no such node
#    kind, so every `?.` call — the modern C# null-safety idiom — produced NO reference at all, invisible
#    to --uses/--callers/--callees/--impact. Fixed by two patterns (plain + generic).
#
#    Chain forms, probed (the H4 survey demanded this before the single-level pattern could be trusted):
#      `w?.Bump()`      final link guarded  -> member_binding      -> NEEDS the new pattern
#      `a?.b?.C()`      final link guarded  -> member_binding      -> NEEDS the new pattern (the OUTER
#                                              conditional_access carries the final segment, so ONE
#                                              pattern covers any `?.` depth; the inner `?.b` is a
#                                              receiver, not a call, and correctly binds nothing)
#      `a?.B.C()`       final link PLAIN    -> member_access       -> already captured, pre- and post-fix
#      `w?.Gen<T>()`    final link guarded, generic                -> NEEDS the generic pattern
#    i.e. the forms needing new patterns are exactly those whose FINAL link is `?.`. This CORRECTS the
#    survey's §SHAPES row, which listed `a?.B.C()` as an untrusted chain form needing verification.
#
# 2. `edges=` is a DISTINCT-(from,to)-PAIR count, not a call-site count. Two calls from the same caller
#    to the same target collapse into ONE edge at src/graph.h:876-881 (`acc[ (from<<32)|to ]`), which
#    keeps the multiplicity as `nref` and spends it on the edge WEIGHT
#    (`w = (confSum/nref)*sqrt(nref)`), never as a second edge. The reference layer does NOT collapse:
#    `--uses` reports both call sites. This gate pins BOTH halves against each other, because the H4
#    round's kickoff note read the collapse as a missing reference ("one `Tool` disappears between
#    extraction and graph") on the strength of a premise this fixture refutes — see the Tool arm below.
#
# ── HOW THE EXPECTED NUMBERS WERE CHOSEN (trap §7.1 of PLAN_h4QualifiedCalls_2026-07-30) ──
# Every count below is a LITERAL read off test/csharpcondfix/Cond.cs by hand — counting call sites in the
# source and collapsing same-(caller,target) pairs on paper — and then confirmed against the binary.
# NONE is derived from the tags.scm query, so a wrong query cannot make this gate agree with itself.
#
# Usage:
#   bash test/csharpcondcheck.sh
#   CTXPACK_BIN=build/ctxpack bash test/csharpcondcheck.sh
#   CTXPACK_BIN=asan/ctxpack  bash test/csharpcondcheck.sh
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
FIX="$ROOT/test/csharpcondfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "csharpcondcheck: BIN=$BIN  FIX=$FIX"

MAP_OUT="$TMP/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
[ "$MAP_EXIT" -eq 0 ] && ok "default map: exits 0" || no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"
command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$MAP_OUT" && ok "default map: passes xmllint --noout" || no "default map: xmllint failed"; }
[ -s "$TMP/map.err" ] && no "default map: unexpected stderr (ABI/degrade?): $( cat "$TMP/map.err" )" || ok "default map: clean stderr (no ABI mismatch / degrade)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== header literals (counted by hand from Cond.cs, not derived from the query) ==="
# ═══════════════════════════════════════════════════════════════════════════
# symbols=13 : Inner C Widget Bump BumpGen Util Tool Driver Bare Gen Caller CondOnly CondThenMember
#              (fields b/B are deliberately not captured — tags.scm header)
# edges=10   : Caller 6 + CondOnly 3 + CondThenMember 1, itemized in the per-caller section below.
#              PRE-FIX this was 7 (CondOnly contributed 0) — that delta is the red-first arm.
# ambiguous=0 / unresolved=0 : no name in the fixture has two definitions, BY CONSTRUCTION, so the
#              12-refs-to-10-edges gap is attributable to pair collapse alone and never to spray.

grep -q 'files=1 '     "$MAP_OUT" && ok "header: files=1"      || no "header: expected files=1: $( grep -o 'files=[0-9]*' "$MAP_OUT" | head -1 )"
grep -q 'symbols=13 '  "$MAP_OUT" && ok "header: symbols=13"   || no "header: expected symbols=13: $( grep -o 'symbols=[0-9]*' "$MAP_OUT" | head -1 )"
grep -q 'edges=10 '    "$MAP_OUT" && ok "header: edges=10 (7 before the ?. fix — CondOnly contributed nothing)" \
                                  || no "header: expected edges=10: $( grep -o 'edges=[0-9]*' "$MAP_OUT" | head -1 )"
grep -q 'ambiguous=0'  "$MAP_OUT" && ok "header: ambiguous=0 (single-target fixture by construction)" || no "header: expected ambiguous=0: $( grep -o 'ambiguous=[0-9]*' "$MAP_OUT" | head -1 )"
grep -q 'unresolved=0' "$MAP_OUT" && ok "header: unresolved=0"  || no "header: expected unresolved=0: $( grep -o 'unresolved=[0-9]*' "$MAP_OUT" | head -1 )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== per-caller edge attribution: which spelling belongs to which caller ==="
# ═══════════════════════════════════════════════════════════════════════════
# Caller()          8 call sites -> 6 edges  { Bare, Bump, Tool, BumpGen, Gen, Widget }
#                                              (Tool twice and Widget twice, each pair collapsed)
# CondOnly()        3 call sites -> 3 edges  { Bump, C, BumpGen } — ALL THREE are `?.` forms, so
#                                              this count is 0 on any binary without the fix.
# CondThenMember()  1 call site  -> 1 edge   { C } — `a?.B.C()`, never needed a new pattern.

callees(){ "$BIN" "$FIX" --callees="$1" --no-cache 2>/dev/null; }

CE_CALLER="$( callees Caller )"
echo "$CE_CALLER" | grep -q 'count="6"' && ok "--callees=Caller count=6 (8 sites, Tool+Widget pairs collapsed)" || no "--callees=Caller expected count=6: $CE_CALLER"
for n in Bare Bump Tool BumpGen Gen Widget; do
    echo "$CE_CALLER" | grep -q "n=\"$n\"" && ok "--callees=Caller lists $n" || no "--callees=Caller missing $n: $CE_CALLER"
done

CE_COND="$( callees CondOnly )"
echo "$CE_COND" | grep -q 'count="3"' && ok "--callees=CondOnly count=3 — every one a ?. form (0 pre-fix)" || no "--callees=CondOnly expected count=3: $CE_COND"
echo "$CE_COND" | grep -q 'n="Bump"'    && ok "?. member call    w?.Bump()          -> Bump edge"    || no "w?.Bump() produced no CondOnly->Bump edge: $CE_COND"
echo "$CE_COND" | grep -q 'n="C"'       && ok "?. guarded chain  a?.b?.C()          -> C edge"       || no "a?.b?.C() produced no CondOnly->C edge: $CE_COND"
echo "$CE_COND" | grep -q 'n="BumpGen"' && ok "?. generic call   w?.BumpGen<int>(1) -> BumpGen edge" || no "w?.BumpGen<int>(1) produced no CondOnly->BumpGen edge: $CE_COND"

CE_CTM="$( callees CondThenMember )"
echo "$CE_CTM" | grep -q 'count="1"' && echo "$CE_CTM" | grep -q 'n="C"' \
    && ok "--callees=CondThenMember count=1 — a?.B.C() (final link PLAIN) was ALWAYS captured" \
    || no "--callees=CondThenMember expected count=1 listing C: $CE_CTM"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== per-spelling REFERENCE presence, pinned to the source LINE of each spelling ==="
# ═══════════════════════════════════════════════════════════════════════════
# --uses is the reference layer: it does NOT collapse, so each spelling gets its own row. Line numbers
# are literals read off Cond.cs. This is what proves each individual SPELLING extracted, as opposed to
# the graph merely having an edge that some OTHER spelling could also have produced.
#   :45 w.Bump()             :56 w?.Bump()
#   :48 w.BumpGen<int>(1)    :58 w?.BumpGen<int>(1)
#   :57 a?.b?.C()            :63 a?.B.C()
#   :46 Util.Tool()          :47 Ns.Util.Tool()
#   :50 new Widget()         :51 new Ns.Widget()

uses(){ "$BIN" "$FIX" --uses="$1" --no-cache 2>/dev/null; }

U_BUMP="$( uses Bump )"
echo "$U_BUMP" | grep -q 'count="2"'  && ok "--uses=Bump count=2 (plain + conditional spelling)" || no "--uses=Bump expected count=2: $U_BUMP"
echo "$U_BUMP" | grep -q 'Cond.cs:45' && ok "  :45 w.Bump()   — plain member call"        || no "  :45 w.Bump() use-site missing: $U_BUMP"
echo "$U_BUMP" | grep -q 'Cond.cs:56' && ok "  :56 w?.Bump()  — CONDITIONAL member call"  || no "  :56 w?.Bump() use-site missing (the H4 headline miss): $U_BUMP"

U_BG="$( uses BumpGen )"
echo "$U_BG" | grep -q 'count="2"'  && ok "--uses=BumpGen count=2 (plain + conditional generic)" || no "--uses=BumpGen expected count=2: $U_BG"
echo "$U_BG" | grep -q 'Cond.cs:48' && ok "  :48 w.BumpGen<int>(1)  — plain generic member call"       || no "  :48 use-site missing: $U_BG"
echo "$U_BG" | grep -q 'Cond.cs:58' && ok "  :58 w?.BumpGen<int>(1) — CONDITIONAL generic member call" || no "  :58 use-site missing (generic ?. pattern): $U_BG"

U_C="$( uses C )"
echo "$U_C" | grep -q 'count="2"'  && ok "--uses=C count=2 (both chain forms)" || no "--uses=C expected count=2: $U_C"
echo "$U_C" | grep -q 'Cond.cs:57' && ok "  :57 a?.b?.C() — final link GUARDED (member_binding: needs the fix)" || no "  :57 a?.b?.C() use-site missing: $U_C"
echo "$U_C" | grep -q 'Cond.cs:63' && ok "  :63 a?.B.C()  — final link PLAIN  (member_access: never needed it)" || no "  :63 a?.B.C() use-site missing: $U_C"

U_BARE="$( uses Bare )"
echo "$U_BARE" | grep -q 'count="1"' && echo "$U_BARE" | grep -q 'Cond.cs:44' && ok "--uses=Bare count=1 @:44 (bare call)" || no "--uses=Bare expected count=1 @:44: $U_BARE"
U_GEN="$( uses Gen )"
echo "$U_GEN" | grep -q 'count="1"' && echo "$U_GEN" | grep -q 'Cond.cs:49' && ok "--uses=Gen count=1 @:49 (bare generic call)" || no "--uses=Gen expected count=1 @:49: $U_GEN"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== the Tool arm: 2 call sites, 1 edge — (from,to) COLLAPSE, not a lost reference ==="
# ═══════════════════════════════════════════════════════════════════════════
# The H4 kickoff recorded that on bench/h4fixtures/csharp one of the two `Tool` references
# "disappears between extraction and graph". It does not disappear. src/graph.h:876-881 accumulates
# edges into `HashMap<uint64_t, EdgeAcc> acc` keyed on `(from<<32)|to`, so the second reference finds
# the SAME key, increments `nref` to 2, and is spent on the edge weight rather than a second edge.
# Both halves are pinned here so a future change to either layer is caught:
#   reference layer (--uses)  : count=2, sites :46 and :47 — multiplicity PRESERVED
#   edge layer (--callers)    : count=1 caller — multiplicity COLLAPSED
# The same collapse is pinned on `new Widget()` / `new Ns.Widget()` (:50, :51), which is the pair the
# kickoff note read as "duplicate edges are otherwise preserved" — they are not; that fixture's two
# Widget edges came from ambiguity spray over a class + its explicit constructor, an effect this
# fixture removes by declaring no constructor.

U_TOOL="$( uses Tool )"
echo "$U_TOOL" | grep -q 'count="2"'  && ok "REFS: --uses=Tool count=2 — the reference layer keeps BOTH sites" || no "--uses=Tool expected count=2 (a reference really was lost): $U_TOOL"
echo "$U_TOOL" | grep -q 'Cond.cs:46' && ok "  :46 Util.Tool()    (2-segment member chain)"  || no "  :46 Util.Tool() use-site missing: $U_TOOL"
echo "$U_TOOL" | grep -q 'Cond.cs:47' && ok "  :47 Ns.Util.Tool() (3-segment member chain)"  || no "  :47 Ns.Util.Tool() use-site missing: $U_TOOL"

CR_TOOL="$( "$BIN" "$FIX" --callers=Tool --no-cache 2>/dev/null )"
echo "$CR_TOOL" | grep -q 'count="1"' && echo "$CR_TOOL" | grep -q 'n="Caller"' \
    && ok "EDGES: --callers=Tool count=1 (Caller) — the two sites collapse to ONE (from,to) pair" \
    || no "--callers=Tool expected count=1 listing Caller: $CR_TOOL"

U_W="$( uses Widget )"
echo "$U_W" | grep -q 'count="2"'  && ok "REFS: --uses=Widget count=2 (new Widget() + new Ns.Widget())" || no "--uses=Widget expected count=2: $U_W"
echo "$U_W" | grep -q 'Cond.cs:50' && ok "  :50 new Widget()"    || no "  :50 new Widget() use-site missing: $U_W"
echo "$U_W" | grep -q 'Cond.cs:51' && ok "  :51 new Ns.Widget()" || no "  :51 new Ns.Widget() use-site missing: $U_W"
CR_W="$( "$BIN" "$FIX" --callers=Widget --no-cache 2>/dev/null )"
echo "$CR_W" | grep -q 'count="1"' \
    && ok 'EDGES: --callers=Widget count=1 — the two "new" spellings collapse to ONE pair too' \
    || no "--callers=Widget expected count=1: $CR_W"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== mutation: strip the '?' from CondOnly's three call sites -> its edges must vanish ==="
# ═══════════════════════════════════════════════════════════════════════════
# Non-tautology arm. Replacing `?.` with a nonexistent-name spelling would only prove name resolution;
# instead the three CondOnly call sites are commented out entirely, so the ONLY thing that can keep
# CondOnly's edge count at 3 is a query matching text that is no longer there.
MUT="$TMP/mut"
mkdir -p "$MUT"
sed -e 's|^            w?\.Bump();|            ;|' \
    -e 's|^            a?\.b?\.C();|            ;|' \
    -e 's|^            w?\.BumpGen<int>( 1 );|            ;|' \
    "$FIX/Cond.cs" >"$MUT/Cond.cs"
grep -q 'w?.Bump();' "$MUT/Cond.cs" && no "mutation: sed did not remove the ?. call sites (fixture drifted?)" \
                                    || ok "mutation: the three ?. call sites removed from the copy"

CE_MUT="$( "$BIN" "$MUT" --callees=CondOnly --no-cache 2>/dev/null )"
echo "$CE_MUT" | grep -q 'count="0"' \
    && ok "mutation: --callees=CondOnly drops to count=0 (the ?. assertions are non-tautological)" \
    || no "mutation: CondOnly kept callees after its ?. sites were removed: $CE_MUT"

MUT_MAP="$( "$BIN" "$MUT" --no-cache 2>/dev/null )"
echo "$MUT_MAP" | grep -q 'edges=7 ' \
    && ok "mutation: header edges 10 -> 7 (exactly the three ?. edges, matching the pre-fix figure)" \
    || no "mutation: expected edges=7 without the ?. sites: $( echo "$MUT_MAP" | grep -o 'edges=[0-9]*' | head -1 )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== determinism: default map thrice, byte-identical ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$FIX" --no-cache >"$TMP/det_a.xml" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/det_b.xml" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/det_c.xml" 2>/dev/null
diff -q "$TMP/det_a.xml" "$TMP/det_b.xml" >/dev/null && diff -q "$TMP/det_b.xml" "$TMP/det_c.xml" >/dev/null \
    && ok "determinism: byte-identical across three runs" \
    || no "determinism: default map differs across runs"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
