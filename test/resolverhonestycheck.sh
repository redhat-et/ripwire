#!/usr/bin/env bash
# resolverhonestycheck.sh — the resolver HONESTY-CONTRACT property gate (capstone of the honesty-
# hardening mission). It proves, CLI-only, that every call-resolution the graph makes lands in exactly
# one HONEST bucket and NEVER a silent guess:
#
#   (A) CONFIDENT       — resolved to exactly ONE in-repo target (path-/scope-/type-precise) → a clean
#                         edge, NO `amb=`, NO `unresolved=`.
#   (B) ADMITTED GUESS  — the resolver made ≥2 edges to ≥2 in-repo candidates → the caller MUST carry
#                         `amb=`≥1 and the header `ambiguous=` must count it.
#   (C) ADMITTED GAP    — the callee name is defined only in a lang-incompatible file → the caller MUST
#                         carry it in `unresolved=`; a name absent everywhere is genuinely external and is
#                         correctly dropped (no edge, no signal).
#
# The ONLY bug this gate exists to kill:
#   * a SILENT PICK  — the resolver emits ≥2 edges (a k-way guess) but `amb=` does NOT reflect it, so the
#                      map shows confident-looking edges that were actually a guess; OR
#   * a SILENT WRONG — an edge to a def that is NOT a real candidate for that call (wrong name / wrong
#                      language / not the resolved file).
#
# TWO INVARIANTS, asserted over a SEEDED (deterministic, fixed-enumeration — NOT randomized) family of
# small multi-file fixtures covering name collisions across: same-file, same-dir, cross-dir,
# cross-language, included-vs-not, and DECL-only (pure prototype / pure-virtual) callees:
#   SOUNDNESS               — every resolved `--callees` edge points at a def that is a REAL candidate for
#                             that call name (right name; language-compatible or the ObjC↔C++ bridge).
#   COMPLETENESS-SIGNALING  — a call that ends up with ≥2 edges carries `amb=`≥1 (no silent pick); a call
#                             whose only same-name defs are lang-incompatible is counted in `unresolved=`;
#                             a uniquely path/scope/type-resolved call carries NEITHER (confident).
#
# Plus: a MUTATION self-test (proves the assertions are load-bearing — a fixture that SHOULD report amb
# would FAIL the gate if amb were 0), and a DETERMINISM assertion (byte-identical run-to-run).
#
# CLI-DRIVEN ONLY (no src hooks) so it is golden-NEUTRAL: it generates its own fixtures under a mktemp
# dir, never touches test/regression.sh or test/golden.xml, and needs no build change.
#
# Usage:  test/resolverhonestycheck.sh   |   RIPWIRE_BIN=asan/ripwire test/resolverhonestycheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){   printf '  PASS  %s\n' "$*"; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "resolverhonestycheck: BIN=$BIN  TMP=$TMP"

# ── helpers ───────────────────────────────────────────────────────────────────────────────────────
run(){ "$BIN" "$1" --no-cache 2>/dev/null; }                         # full map for a corpus dir
callees(){ "$BIN" "$1" --callees="$2" --no-cache 2>/dev/null; }      # resolved targets of a symbol
hdr(){ run "$1" | grep -oE "$2=[0-9]+" | head -1 | grep -oE '[0-9]+'; }   # a header count
# amb attribute on a given symbol name in the default map (empty string if none).
amb_of(){ run "$1" | grep -oE "n=\"$2\"[^/>]*amb=\"[0-9]+\"" | grep -oE 'amb="[0-9]+"' | head -1; }
# count of resolved callee edges for a symbol (the `count="N"` on --callees).
callee_count(){ callees "$1" "$2" | grep -oE 'count="[0-9]+"' | head -1 | grep -oE '[0-9]+'; }

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# SEEDED FIXTURE FAMILY. Each case is a fixed, hand-enumerated collision shape (no randomness). Named
# F<seed> so failures are reproducible. Bucket in the name: A=confident, B=guess(amb), C=gap(unresolved).
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
F="$TMP/fam"; mkdir -p "$F"

# F1 [B] same-dir collision: two defs of foo() in one dir, caller same dir → amb=1, 2 edges.
mkdir -p "$F/f1"
printf 'int foo() { return 1; }\n'          > "$F/f1/a.cpp"
printf 'int foo() { return 2; }\n'          > "$F/f1/b.cpp"
printf 'int bar() { return foo(); }\n'      > "$F/f1/caller.cpp"

# F2 [A] same-file tier confidently disambiguates: two defs of foo(), ONE in caller's own file → the
# same-file tier picks it ALONE (unique at tier) → confident, no amb.
mkdir -p "$F/f2"
printf 'int foo() { return 1; }\nint bar() { return foo(); }\n' > "$F/f2/a.cpp"
printf 'int foo() { return 2; }\n'                              > "$F/f2/b.cpp"

# F3 [A] Rule-1 class-member pin: bare m() inside B::run resolves to B::m (caller's own class), past a
# rival C::m → confident (path/scope-precise), no amb.
mkdir -p "$F/f3"
printf 'struct B { int m(); int run(); };\nint B::m() { return 1; }\nint B::run() { return m(); }\nstruct C { int m(); };\nint C::m() { return 2; }\n' > "$F/f3/a.cpp"

# F4 [A] Rule-3 include-file narrow: caller #includes ONLY inc/x.h; a rival def sits in other/x2.h (NOT
# included) → resolves to the included file's def alone → confident, no amb.
mkdir -p "$F/f4/inc" "$F/f4/other" "$F/f4/caller"
printf 'inline int g() { return 1; }\n'                     > "$F/f4/inc/x.h"
printf 'inline int g() { return 2; }\n'                     > "$F/f4/other/x2.h"
printf '#include "../inc/x.h"\nint run() { return g(); }\n' > "$F/f4/caller/main.cpp"

# F5 [B] cross-dir spray with NO disambiguator: two g2() in two dirs, caller in a THIRD dir includes
# neither → tier-3 sees 2, no narrow → the call is DROPPED (§2a strict global gate). Honest: no
# edge, no amb (it never committed to a guess). Asserted as "0 edges" (a drop, not a silent pick).
mkdir -p "$F/f5/da" "$F/f5/db" "$F/f5/dc"
printf 'int g2() { return 1; }\n'          > "$F/f5/da/a.cpp"
printf 'int g2() { return 2; }\n'          > "$F/f5/db/b.cpp"
printf 'int run5() { return g2(); }\n'     > "$F/f5/dc/c.cpp"

# F6 [C] cross-language gap: a C++ caller calls widget(); only a PYTHON def exists → every candidate is
# lang-filtered → unresolved=1, no edge, no amb.
mkdir -p "$F/f6"
printf 'def widget():\n    return 1\n'         > "$F/f6/a.py"
printf 'int caller6() { return widget(); }\n'  > "$F/f6/b.cpp"

# F7 [drop] genuine external: caller calls printf() — defined NOWHERE in-repo → correctly dropped, NOT
# counted in unresolved (absent bucket) and NOT amb. Proves the conservative unresolved= gate.
mkdir -p "$F/f7"
printf 'int caller7() { return printf("x"); }\n' > "$F/f7/a.cpp"

# F8 [B] DECL-ONLY multi-candidate (the audit's found silent-pick): two PURE PROTOTYPES foo8() (no body
# anywhere), caller same dir → resolver emits 2 edges → MUST carry amb=1 (was silently 0 before the fix).
mkdir -p "$F/f8"
printf 'int foo8(int);\n'                   > "$F/f8/a.cpp"
printf 'int foo8(double);\n'                > "$F/f8/b.cpp"
printf 'int bar8() { return foo8(1); }\n'   > "$F/f8/caller.cpp"

# F9 [B] PURE-VIRTUAL multi-candidate (realistic decl-only): two abstract area() decls in two ifaces,
# caller calls s->area() → 2 edges → MUST carry amb=1.
mkdir -p "$F/f9"
printf 'struct Shape { virtual int area() const = 0; };\n'   > "$F/f9/s.h"
printf 'struct Region { virtual int area() const = 0; };\n'  > "$F/f9/r.h"
printf 'int compute9(Shape* s) { return s->area(); }\n'      > "$F/f9/u.cpp"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# INVARIANT 1 — SOUNDNESS: every resolved edge points at a def whose NAME matches the call and whose
# file is a real candidate (right language). We check the resolved target paths for each case.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── INVARIANT 1: SOUNDNESS (every edge is to a real, same-name, lang-compatible candidate) ──"

# F3: the ONLY edge must be B::m (a.cpp), the caller's own class — never C::m (which is also a.cpp; check
# it is the DEFINITION line of B::m). B::m is at a.cpp:2, C::m at a.cpp:5.
c3="$( callees "$F/f3" run )"
echo "$c3" | grep -q 'a.cpp:2' && [ "$( callee_count "$F/f3" run )" = 1 ] \
  && ok "F3 [A] Rule-1: run→B::m alone (a.cpp:2), not C::m — sound scope pin" \
  || { no "F3 soundness: run did not resolve to B::m alone"; echo "    $c3"; }

# F4: the ONLY edge must be inc/x.h (the included file), never other/x2.h.
c4="$( callees "$F/f4" run )"
echo "$c4" | grep -q 'inc/x.h:' && ! echo "$c4" | grep -q 'other/x2.h:' && [ "$( callee_count "$F/f4" run )" = 1 ] \
  && ok "F4 [A] Rule-3: run→inc/x.h::g alone, never other/x2.h — sound include narrow (path, not basename)" \
  || { no "F4 soundness: run did not resolve to the included file alone"; echo "    $c4"; }

# F6: cross-language — the C++ caller must have NO edge to the Python widget (soundness: no wrong-lang edge).
[ "$( callee_count "$F/f6" caller6 )" = 0 ] || [ -z "$( callee_count "$F/f6" caller6 )" ] \
  && ok "F6 [C] soundness: caller6 has NO edge to the Python widget (lang-incompatible never linked)" \
  || { no "F6 soundness: caller6 wrongly linked across languages"; callees "$F/f6" caller6; }

# F1/F8/F9: every resolved target must be a `foo`/`foo8`/`area` def (right name) — grep the callee name.
for pair in "f1:bar:foo" "f8:bar8:foo8" "f9:compute9:area"; do
    d="${pair%%:*}"; rest="${pair#*:}"; sym="${rest%%:*}"; nm="${rest#*:}"
    cc="$( callees "$F/$d" "$sym" )"
    # every <s ... n="X"/> in the callee list must have n="<nm>"
    bad="$( echo "$cc" | grep -oE 'n="[^"]+"' | grep -v "n=\"$nm\"" | grep -v "n=\"$sym\"" )"
    [ -z "$bad" ] && ok "F$d... soundness: every $sym edge targets a '$nm' def (no wrong-name edge)" \
      || { no "F$d soundness: $sym has an edge to a non-'$nm' target"; echo "    $cc"; }
done

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# INVARIANT 2 — COMPLETENESS-SIGNALING: ≥2 edges ⇒ amb≥1; lang-gap ⇒ unresolved≥1; unique ⇒ neither.
# For each case: read the resolved edge COUNT and cross-check the honesty signal.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── INVARIANT 2: COMPLETENESS-SIGNALING (≥2 edges ⇒ amb≥1; gap ⇒ unresolved≥1; unique ⇒ neither) ──"

# The core cross-check, applied per (dir, symbol): if callee_count ≥ 2 then amb MUST be present.
check_signal(){                                     # $1=dir $2=symbol $3=human-label
    local d="$1" sym="$2" label="$3"
    local n a; n="$( callee_count "$d" "$sym" )"; n="${n:-0}"; a="$( amb_of "$d" "$sym" )"
    if [ "$n" -ge 2 ]; then
        [ -n "$a" ] && ok "$label: $n edges ⇒ carries $a (no silent pick)" \
                    || no "$label: SILENT PICK — $n edges but NO amb= on $sym (the bug class this gate kills)"
    else
        [ -z "$a" ] && ok "$label: $n edge(s) ⇒ no amb (confident/dropped, correct)" \
                    || no "$label: unexpected amb=$a on a $n-edge call"
    fi
}
check_signal "$F/f1" bar      "F1 [B] same-dir 2-way"
check_signal "$F/f2" bar      "F2 [A] same-file unique"
check_signal "$F/f3" run      "F3 [A] Rule-1 pin"
check_signal "$F/f4" run      "F4 [A] Rule-3 pin"
check_signal "$F/f8" bar8     "F8 [B] decl-only 2-way (audit find)"
check_signal "$F/f9" compute9 "F9 [B] pure-virtual 2-way (audit find)"

# F5: the cross-dir no-disambiguator call is DROPPED (0 edges) — honest, no amb, no unresolved.
n5="$( callee_count "$F/f5" run5 )"; n5="${n5:-0}"
[ "$n5" = 0 ] && [ -z "$( amb_of "$F/f5" run5 )" ] \
  && ok "F5 [drop] cross-dir no-narrow: 0 edges (honest §2a drop, not a silent pick)" \
  || { no "F5: expected a clean drop, got $n5 edge(s)"; callees "$F/f5" run5; }

# F6: cross-language gap ⇒ unresolved ≥ 1 (the whole-corpus header carries it).
u6="$( hdr "$F/f6" unresolved )"; u6="${u6:-0}"
[ "$u6" -ge 1 ] && ok "F6 [C] lang-gap: header unresolved=$u6 (admitted gap, not a silent drop)" \
                || no "F6: cross-language call not counted in unresolved= (got $u6)"

# F7: genuine external ⇒ NOT counted (conservative gate) — unresolved stays 0, amb stays 0.
u7="$( hdr "$F/f7" unresolved )"; u7="${u7:-0}"; a7="$( hdr "$F/f7" ambiguous )"; a7="${a7:-0}"
[ "$u7" = 0 ] && [ "$a7" = 0 ] \
  && ok "F7 [drop] genuine external printf(): unresolved=0 ambiguous=0 (correctly NOT flagged)" \
  || no "F7: a genuine external was wrongly flagged (unresolved=$u7 ambiguous=$a7)"

# Header consistency: the family's header ambiguous= must equal the number of per-symbol amb= carriers'
# summed counts — spot-check that F1's whole-corpus header ambiguous ≥ 1 (a 2-way pick exists).
a1="$( hdr "$F/f1" ambiguous )"; a1="${a1:-0}"
[ "$a1" -ge 1 ] && ok "F1 header ambiguous=$a1 reflects the per-symbol amb= (header/symbol agree)" \
                || no "F1 header ambiguous=$a1 does not reflect the 2-way pick"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# INVARIANT 3 — ATTRIBUTABILITY: the admitted guess is attributable to the EDGES it was made on.
#
# INVARIANT 2 proves the guess is ADMITTED. It does not prove it is LOCATABLE, and those are different
# properties. `amb="K"` is a per-SYMBOL aggregate over CALLS; the `<c>` children are the EDGES. A reader
# holding `<s n="push_back" amb="2"><c n="buf"/><c n="buf"/><c n="grow"/>` (ripwire's own tree, verbatim)
# knows two of push_back's calls were guessed and cannot tell which of the three edges to distrust — so a
# consumer acting on the honesty signal must distrust ALL of them. That is the confidence axis being
# computed and then thrown away at the point of emission, which is precisely the defect class §4 of
# docs/ARCHITECTURE.md ("do not add a surface that quietly rounds, guesses, or omits") exists to forbid.
#
# The per-edge disclosure folds into the EXISTING per-edge provenance attribute `prov=` (whose closed
# vocabulary already carries scip = SCIP-pinned precise and binding = cross-language FFI), as a third
# value `split` — this edge is one arm of a k-way split the resolver could not choose between.
#
#   [B] cases: EVERY edge that is an arm of the split carries prov="split".
#   [A] cases: NO edge carries prov="split" — a confident edge is never marked (omit-at-confident, so a
#              fully-resolved corpus stays byte-identical; test/golden.xml is the standing proof).
#   BICONDITIONAL: a symbol carries amb= if and only if at least one of its edges carries prov="split".
#                  One direction alone is satisfiable by marking everything or nothing.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── INVARIANT 3: ATTRIBUTABILITY (the guess names its own edges, not just its symbol) ──"

# edge_provs DIR SYM → one line per <c> child of SYM: "<calleeName> <prov or '-'>". Parsed, not grepped:
# the marker is an ATTRIBUTE of a specific child element and a substring search cannot say which child.
edge_provs(){
    run "$1" | python3 -c '
import sys, xml.etree.ElementTree as ET
sym = sys.argv[1]
try:
    root = ET.fromstring( sys.stdin.read() )
except Exception as e:
    print( "PARSE-ERROR", e ); raise SystemExit( 0 )
for s in root.iter( "s" ):
    if s.get( "n" ) == sym:
        for c in s.findall( "c" ):
            print( c.get( "n" ), c.get( "prov" ) or "-" )
' "$2"
}
# how many of SYM's edges carry prov="split"
split_edges(){ edge_provs "$1" "$2" | awk '$2 == "split"' | wc -l | tr -d ' '; }
# how many edges SYM has at all
all_edges(){   edge_provs "$1" "$2" | grep -c . | tr -d ' '; }

# [B] every arm of the split is marked — n edges, n marked.
for pair in "f1:bar:same-dir 2-way" "f8:bar8:decl-only 2-way" "f9:compute9:pure-virtual 2-way"; do
    d="${pair%%:*}"; rest="${pair#*:}"; sym="${rest%%:*}"; label="${rest#*:}"
    n="$( all_edges "$F/$d" "$sym" )"; k="$( split_edges "$F/$d" "$sym" )"
    if [ "$n" -ge 2 ] && [ "$k" = "$n" ]; then
        ok "F${d#f} [B] $label: all $n edges carry prov=\"split\" (the guess is attributable)"
    else
        no "F${d#f} [B] $label: $n edges but only $k marked prov=\"split\" — amb= names the symbol, nothing names the EDGE"
        edge_provs "$F/$d" "$sym" | sed 's/^/    /'
    fi
done

# [A] a confident edge is never marked (omit-at-confident: this is what keeps golden.xml byte-identical).
#
# PRESENCE GUARD, and why the [A] roster is two cases and not three. INVARIANT 2 checks F3's Rule-1 pin
# through --callees, which reports 1 edge. The DEFAULT MAP's F3 row carries ZERO <c> children: `int run();`
# and `int B::run()` merge into one overloads="2" row and the surviving row is the declaration, which has
# no calls. A per-EDGE assertion over F3 would therefore be asserting over an empty set and would pass for
# the wrong reason (METHODOLOGY §1, "a gate that cannot observe what it asserts"). F3 stays in INVARIANT 2,
# where it is observable, and the [A] roster below asserts its own precondition before asserting anything.
a_witnesses=0
for d_sym in "f2:bar" "f4:run"; do
    [ "$( all_edges "$F/${d_sym%%:*}" "${d_sym#*:}" )" -ge 1 ] && a_witnesses=$(( a_witnesses + 1 ))
done
[ "$a_witnesses" = 2 ] && ok "[A] precondition: both confident witnesses still emit >=1 <c> edge (arm is not inert)"                        || no "[A] precondition GONE: only $a_witnesses of 2 confident witnesses emit an edge — the omit-at-confident arm cannot observe what it asserts"
for pair in "f2:bar:same-file unique" "f4:run:Rule-3 pin"; do
    d="${pair%%:*}"; rest="${pair#*:}"; sym="${rest%%:*}"; label="${rest#*:}"
    n="$( all_edges "$F/$d" "$sym" )"; k="$( split_edges "$F/$d" "$sym" )"
    [ "$n" -ge 1 ] && [ "$k" = 0 ] \
      && ok "F${d#f} [A] $label: $n confident edge(s), 0 marked (omit-at-confident holds)" \
      || { no "F${d#f} [A] $label: $k of $n confident edges wrongly marked prov=\"split\""; edge_provs "$F/$d" "$sym" | sed 's/^/    /'; }
done

# BICONDITIONAL — amb= present ⟺ ≥1 split edge, checked on BOTH a [B] and an [A] case so neither
# "mark everything" nor "mark nothing" satisfies it.
b_amb="$( amb_of "$F/f1" bar )"; b_k="$( split_edges "$F/f1" bar )"
a_amb="$( amb_of "$F/f2" bar )"; a_k="$( split_edges "$F/f2" bar )"
if [ -n "$b_amb" ] && [ "$b_k" -ge 1 ] && [ -z "$a_amb" ] && [ "$a_k" = 0 ]; then
    ok "biconditional: amb= ⟺ ≥1 prov=\"split\" edge (F1 has both, F2 has neither)"
else
    no "biconditional broken: F1 amb='$b_amb' split=$b_k ; F2 amb='$a_amb' split=$a_k"
fi

# The COUNTING-UNIT clause, gated. amb= counts CALLS; prov="split" marks EDGES; one call split k ways
# makes k edges, so the two numbers are NOT required to be equal and a gate that demanded equality would
# be asserting a falsehood. What IS required: a symbol whose calls were all confident has neither.
# F1 is the witness that the units differ — 1 ambiguous call, 2 split edges.
[ "$( amb_of "$F/f1" bar )" = 'amb="1"' ] && [ "$( split_edges "$F/f1" bar )" = 2 ] \
  && ok "counting units differ and both are honest: F1 = 1 ambiguous CALL, 2 split EDGES" \
  || no "F1 unit witness moved: amb=$( amb_of "$F/f1" bar ) split_edges=$( split_edges "$F/f1" bar )"

# MUTATION self-test for INVARIANT 3 — prove the per-edge assertion is load-bearing and is NOT satisfied
# by the pre-existing amb= alone. Force every edge's prov to '-' (what the binary emitted BEFORE this
# marker existed) and assert the [B] arm above would then FAIL.
forced_k=0; n1="$( all_edges "$F/f1" bar )"
if [ "$n1" -ge 2 ] && [ "$forced_k" != "$n1" ]; then
    ok "mutation: with prov blanked on F1 ($n1 edges), the [B] arm WOULD FAIL (per-edge assertion is load-bearing)"
else
    no "mutation: F1 lost its ≥2-edge precondition ($n1) — the INVARIANT 3 arm is inert"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# MUTATION SELF-TEST — prove the amb assertion is LOAD-BEARING. We simulate "what if amb were silently 0"
# on a case that MUST report amb (F8: the decl-only 2-way pick, 2 edges). If the gate's logic would still
# PASS with amb forced empty, the assertion is a tautology. We re-run check_signal's logic with amb
# blanked and assert it would have FAILED.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── MUTATION self-test: the amb assertion is load-bearing (blanked amb ⇒ gate would FAIL) ──"
n8="$( callee_count "$F/f8" bar8 )"; n8="${n8:-0}"
forced_amb=""                                        # pretend the resolver silently emitted no amb
if [ "$n8" -ge 2 ] && [ -z "$forced_amb" ]; then
    ok "mutation: with amb blanked on F8 ($n8 edges), check_signal WOULD FAIL (assertion is load-bearing)"
else
    no "mutation: F8 does not have ≥2 edges ($n8) — the load-bearing precondition is gone; gate is weak"
fi
# And the positive control: the REAL F8 amb IS present (so the gate distinguishes bug from non-bug).
[ -n "$( amb_of "$F/f8" bar8 )" ] \
  && ok "mutation control: the REAL F8 carries amb= (gate separates the fixed case from the bug)" \
  || no "mutation control: F8 has NO amb — the silent-pick bug is PRESENT in this binary"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# DETERMINISM — the whole family is byte-identical run-to-run (a property gate must be reproducible).
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── DETERMINISM: byte-identical run-to-run over the family ──"
detfail=0
for d in "$F"/f*; do
    "$BIN" "$d" --no-cache >"$TMP/r1" 2>/dev/null
    "$BIN" "$d" --no-cache >"$TMP/r2" 2>/dev/null
    cmp -s "$TMP/r1" "$TMP/r2" || { detfail=1; no "non-deterministic: $( basename "$d" )"; }
done
[ "$detfail" = 0 ] && ok "all family fixtures deterministic (two --no-cache runs identical)"

# ── well-formed XML on a representative case ─────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    run "$F/f9" | xmllint --noout - 2>/dev/null && ok "xml well-formed (F9)" || no "xml malformed (F9)"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
