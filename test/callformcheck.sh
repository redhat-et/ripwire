#!/usr/bin/env bash
# callformcheck.sh — THE PER-LANGUAGE CALL-FORM MATRIX (PLAN_h4QualifiedCalls_2026-07-30.md §6).
#
# WHY THIS GATE EXISTS. §H4 — "a plainly written, statically resolvable call produces no reference at
# all" — lived in the tree for the tool's whole life because every per-language gate tested IMPORTS
# and resolution PRECISION, and nothing tested call-form COVERAGE. The drop happened at EXTRACTION,
# before resolution, so `ambiguous=`/`unresolved=` (the published call-graph completeness gauges)
# could not move and no reader had a signal. This gate is the missing lens: for each of the THIRTEEN
# grammars that carry a tags.scm, one fixture under test/callformfix/<lang>/ exercises EVERY call
# SPELLING the language offers, one spelling per line with a comment naming it, and one arm here
# pins what that spelling does. That is FOURTEEN corpora, not thirteen: `cppcanon/` is a second C++
# corpus, deliberately separate because its whole point is a cross-DIRECTORY canonical collision that
# cannot be expressed inside a single-directory fixture.
#
# THE DOCUMENTED-ABSENT ROWS ARE THE POINT. Roughly a quarter of the arms below assert that a
# spelling produces NOTHING: C++ casts, most-vexing-parse declarations, member-templates and
# destructor spellings; Go's explicit generic instantiation; Java's method references and both
# generic `new` forms; Ruby's bare paren-less call; Swift's explicit specialization; computed
# `new a.b[c]()` in TS and JS. Those are honest rejects — several of them unfixable by any query —
# and an arm that fences them goes RED if a naive widening lands. A matrix that only recorded the
# successes would be a celebration, not a gate.
#
# …AND EVERY ONE OF THEM CARRIES A FIXTURE-PRESENCE GUARD (V5 MED-3), because an absence arm is
# satisfied just as well by DELETING THE SPELLING as by the tool behaving. V5 proved that live:
# it removed the bare paren-less call from the Ruby fixture and both Ruby absence arms stayed green,
# gate ALL PASS. Each absence arm is now preceded by a literal grep of the fixture SOURCE for the
# spelling's own text — source, not extraction output, so the guard cannot be satisfied by the very
# absence it protects. Writing them surfaced a second live instance: the four cast arms asserted the
# absence of `dynamic_cast`, a keyword the fixture had never spelled.
#
# TRAP 1 (plan §7). Every expected count here is a LITERAL, chosen by READING the fixture — never
# derived by running the query the extractor runs. Each fixture gives every callee a UNIQUE name, so
# `--uses=<name>` is a per-spelling assertion whose expected value is just "how many times did I
# write that call". Where a spelling extracts but cannot resolve (function-pointer variables, ObjC
# struct fn-pointer fields, casts), the assertion is made PRE-resolution through ctxpack_probe,
# because a reference that resolves to nothing vanishes from every graph verb while still being
# extracted — and "extracted but unresolved" is a different verdict from "never extracted".
#
# RED-FIRST (measured 2026-07-31, plain builds, `git archive 130b465` built in a scratch dir as the
# PRE-ROUND binary). 36 of this gate's 198 checks FAIL there, covering 25 distinct spellings, and
# they are exactly the widenings this round shipped. (Both totals are counted from a real run's
# `^  PASS`/`^  FAIL` lines. The first version of this header said 171/37: `grep -c PASS` had swept
# up the trailing "ALL PASS" banner and `grep -c FAIL` the "FAILURES ABOVE" one — a one-line
# over-count in each direction, corrected by V5. The 28 new presence/control checks are all
# binary-INDEPENDENT — a source grep and a probe-dump lookup — so they pass on the pre-round binary
# too and the red-first FAIL count is unchanged at 36.)
#   cpp        seg3Fn 0->1  seg4Fn 0->1  boxGet 0->1  tmplFreeFn 0->1  tmplScopedFn 0->1  Gadget 0->1
#              --callees=callerOperator 0->1   (the qualified operator> family, W2b-fixup M-2)
#   cppcanon   --callees=crossDirCaller 0->2 + amb="1"   (the W3-RUST `|| canonical` tier-3 rescue)
#   rust       assoc_fn 0->2  mod_fn 0->1  deep_fn 0->1  self_fn 0->1  ufcs_fn 0->1  turbo_bare 0->1
#              turbo_scoped 0->1  trait_fn 1->2  file_mod_fn 0->1
#   csharp     CondOne 0->1  CondChain 0->1  CondGeneric 0->1        (L-CS conditional access)
#   typescript Inner 0->1  Deep 0->1  GenInner 0->1                  (L-NEW qualified `new`)
#   java       Inner 0->1  Deep 0->1  PkgType 0->1                   (L-NEW scoped `new`)
#   objc       initFp REFUSED->1                                     (L-NEW field-call parity)
# BASE PARITY IS EXPECTED, and is the correct result, for these arm families: every bare/member/
# selector/attribute chain in ALL languages, Go (defer/go/paren/inferred-generic/index-then-call),
# JavaScript in full (its qualified-`new` fixture rows were already green at base — see §JS), Python,
# C, Bash, Ruby, Swift, C# 3-segment chains and `w?.B.C()` (only the FINAL link's node kind matters),
# and every documented-absent row. Those arms are regression fences for a future round, not evidence
# of this one.
#
# Usage:  CTXPACK_BIN=build/ctxpack bash test/callformcheck.sh  |  bash test/callformcheck.sh asan/ctxpack
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"      # BOTH seams: positional arg and CTXPACK_BIN=
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # absolute BEFORE we cd away
PROBE="${BIN}_probe"                                 # probecheck.sh's house pattern: the probe must
                                                     # follow the BINARY UNDER TEST, never a hardcoded
                                                     # build/ path (two gates were dinged this round
                                                     # for greening against a pre-wave binary).
FIX="$ROOT/test/callformfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/callformfix dir — fixtures missing"; exit 2; }
cd "$ROOT"

echo "callformcheck: BIN=$BIN  PROBE=$PROBE  CORPORA=test/callformfix/*"

cxrun(){ perl -e 'alarm 60; exec @ARGV' "$BIN" "$@" 2>/dev/null; }
cxcount(){ printf '%s' "$1" | grep -oE 'count="[0-9]+"' | head -1 | tr -dc 0-9; }

# --uses=<sym> on one fixture corpus must equal a LITERAL read off that fixture.
uses(){     # $1 lang  $2 sym  $3 want  $4 prose
    local out got
    out="$( cxrun "$FIX/$1" --uses="$2" --no-cache )"
    got="$( cxcount "$out" )"
    [ "${got:-REFUSED}" = "$3" ] && ok "[$1] --uses=$2 = $3 — $4" \
        || no "[$1] --uses=$2 expected $3, got '${got:-REFUSED}' — $4"
}

# --callees=<caller> count must equal a LITERAL.
callees(){  # $1 lang  $2 caller  $3 want  $4 prose
    local out got
    out="$( cxrun "$FIX/$1" --callees="$2" --no-cache )"
    got="$( cxcount "$out" )"
    [ "${got:-REFUSED}" = "$3" ] && ok "[$1] --callees=$2 = $3 — $4" \
        || no "[$1] --callees=$2 expected $3, got '${got:-REFUSED}' — $4"
}

# --callees=<caller> must contain a row for <name>.
calleeRow(){  # $1 lang  $2 caller  $3 name  $4 prose
    local out
    out="$( cxrun "$FIX/$1" --callees="$2" --no-cache )"
    printf '%s' "$out" | grep -qE "<s [^>]*n=\"$3\"" \
        && ok "[$1] $2 -> $3 — $4" \
        || no "[$1] $2 has NO callee row for $3 — $4. Got: $out"
}

# ── the probe seam: PRE-resolution reference lists ─────────────────────────────────────────────
# A reference that extracts but resolves to nothing is invisible to every graph verb, so the only
# way to tell "extracted, unresolved" apart from "never extracted" is to read the raw list.
probeCalls(){   # $1 lang  $2 symbol  ->  the `calls:` line, or empty
    perl -e 'alarm 60; exec @ARGV' "$PROBE" "$FIX/$1" 2>/dev/null | awk -v want="$2" '
        /^\[/ { split( $0, f, "] " ); n = f[2]; sub( / .*/, "", n ); hit = ( n == want ); next }
        hit && /calls:/ { print; exit }'
}
probeHas(){     # $1 lang  $2 symbol  -> 0 if the probe listed that symbol at all
    perl -e 'alarm 60; exec @ARGV' "$PROBE" "$FIX/$1" 2>/dev/null | awk -v want="$2" '
        /^\[/ { split( $0, f, "] " ); n = f[2]; sub( / .*/, "", n ); if( n == want ) { found = 1; exit } }
        END { exit( found ? 0 : 1 ) }'
}

# EXTRACTED: <name> appears in <symbol>'s raw reference list.
probeSees(){    # $1 lang  $2 symbol  $3 name  $4 prose
    local line; line="$( probeCalls "$1" "$2" )"
    if [ -z "$line" ]; then
        no "[$1] probe: $2 has NO reference list at all — the arm would be vacuous — $4"
    elif printf '%s' "$line" | grep -qE "(^|[[:space:]])$3([[:space:]]|\$)"; then
        ok "[$1] probe: $2 EXTRACTS \`$3\` — $4"
    else
        no "[$1] probe: $2 does not extract \`$3\` — $4. Got: $line"
    fi
}

# ── THE FIXTURE-PRESENCE GUARD (V5 MED-3) ──────────────────────────────────────────────────────
# THE HOLE THIS CLOSES, and it is the hole that matters most in a matrix built out of absence arms:
# every documented-absent arm asserts "the tool produces nothing for this spelling", and DELETING
# THE SPELLING FROM THE FIXTURE satisfies that assertion perfectly. V5 proved it live — it removed
# `bare_noparen_fn` from test/callformfix/ruby/main.rb and BOTH Ruby absence arms stayed green, gate
# ALL PASS. An absence arm without a presence guard is not a gate, it is a decoration that a careless
# fixture edit silently converts into nothing.
#
# The guard therefore reads the fixture SOURCE TEXT, never any tool output: it cannot be satisfied by
# the very absence it is protecting, and it does not care what the extractor does. One guard per
# documented-absent spelling, immediately beside the arm it protects.
#
# (This also caught a second instance while being written: the four cast arms asserted the absence of
# `dynamic_cast`, which the fixture never spelled — vacuous by construction since the day it shipped.
# The keyword is now written in test/callformfix/cpp/main.cpp and the guard pins it there.)
fixtureHasLit(){    # $1 relpath under test/callformfix  $2 LITERAL source text  $3 prose
    grep -qF -- "$2" "$FIX/$1" \
        && ok "[fixture] $1 still spells \`$2\` — $3" \
        || no "[fixture] $1 NO LONGER spells \`$2\` — the absence arm beside this guard is now VACUOUS — $3"
}
fixtureHasRe(){     # $1 relpath under test/callformfix  $2 ERE  $3 prose
    grep -qE -- "$2" "$FIX/$1" \
        && ok "[fixture] $1 still matches /$2/ — $3" \
        || no "[fixture] $1 NO LONGER matches /$2/ — the absence arm beside this guard is now VACUOUS — $3"
}

# ABSENT: <name> does NOT appear in <symbol>'s raw reference list. Three vacuity guards, because
# "grep found nothing" is satisfied by an empty string, by a list the probe truncated at its
# 12-reference cap, AND by a probe run that never emitted the caller at all — each would turn an
# absence arm into a decoration. The caller-presence control is emitted as its OWN check line rather
# than folded into the verdict, because four of these arms sit on callers whose reference list is
# legitimately EMPTY (Go's callerIndexed, JS's callerAbsent, Ruby's caller_absent): for those the
# whole evidential weight rests on "the caller was there and had nothing", so that half must be
# visible in the output, not implied by it (V5).
probeBlind(){   # $1 lang  $2 symbol  $3 name  $4 prose
    local line; line="$( probeCalls "$1" "$2" )"
    probeHas "$1" "$2" \
        && ok "[$1] probe control: the caller $2 IS in the probe dump — its empty/short list is a real observation" \
        || no "[$1] probe control: the caller $2 is NOT in the probe dump — an absent-list arm below would be vacuous"
    if ! probeHas "$1" "$2"; then
        no "[$1] probe: symbol $2 is not in the dump at all — absence of \`$3\` proves nothing — $4"
    elif printf '%s' "$line" | grep -q '\.\.\.$'; then
        no "[$1] probe: $2's list is TRUNCATED at the probe's 12-ref cap, so absence of \`$3\` is vacuous — split the fixture's caller — $4"
    elif printf '%s' "$line" | grep -qE "(^|[[:space:]])$3([[:space:]]|\$)"; then
        no "[$1] probe: $2 DOES extract \`$3\` — this row is documented-absent and a widening has landed without updating the matrix — $4"
    else
        ok "[$1] probe: $2 extracts NO \`$3\` — $4"
    fi
}

[ -x "$PROBE" ] \
    || { no "ctxpack_probe missing at $PROBE — the pre-resolution arms cannot run, and a gate that cannot run must say so rather than skip quietly (probecheck.sh's law)"; }

# ════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== C++ — test/callformfix/cpp/main.cpp ==="
# Depth-unbounded qualified calls, the template_function mechanism, and every honest reject.
uses cpp bareFn       1 "1. bare call"
uses cpp dotFn        1 "2. member call, dot"
uses cpp arrowFn      1 "3. member call, arrow"
uses cpp seg2Fn       1 "4. 2-segment qualified (the shape the pre-round pattern bound)"
uses cpp seg3Fn       1 "5. 3-segment qualified — bound NOTHING before this round"
uses cpp seg4Fn       1 "6. 4-segment qualified"
uses cpp globalFn     1 "7. leading :: with no scope field"
uses cpp boxGet       1 "8. templated-scope call a::b::Box<int>::boxGet()"
uses cpp tmplFreeFn   1 "9. explicit template arguments, bare (template_function)"
uses cpp tmplScopedFn 1 "10. template_function UNDER a qualified_identifier"
uses cpp Gadget       1 "12. qualified constructor — a call ref named for the CLASS"
uses cpp ping         1 "13. member call on the constructed temporary"
# 14. the `>`-family. A trailing `>` used to open a template group the re-split's reverse scan never
# closed, so the qualifier fell back to the OUTERMOST scope. cppqualcheck owns the decoy proof; here
# the matrix only pins that the spelling produces an edge at all (base: 0).
callees   cpp callerOperator 1 "14. qualified operator> at 3 segments produces exactly one callee"
calleeRow cpp callerOperator 'operator&gt;' "14. …and it is operator> itself"
# 15. NOT-CHECKED in the H4 survey — namespace-alias calls. MEASURED: captured. `namespace qa = q1::q2`
# makes `qa::aliasFn()` an ordinary 2-segment qualified_identifier, so the pattern binds and the name
# is `aliasFn`. The qualifier is the ALIAS (`qa`), which is not a def-side scope, so the canonical
# tier misses and the call resolves by the bare-name ladder — precise here because aliasFn is unique,
# and exactly as precise as a bare call elsewhere. That residual is why this arm exists.
uses cpp aliasFn      1 "15. NOT-CHECKED->MEASURED: namespace-alias call qa::aliasFn() is CAPTURED (resolves bare, not canonically)"
# 11. NOT-CHECKED in the survey — the member-template spelling. MEASURED: DROPPED, entirely.
# `b.template memberTmpl<int>()` yields no reference of any name; the `template` disambiguator makes
# the callee child a shape none of the three C++ reference patterns bind.
fixtureHasLit cpp/main.cpp 'b.template memberTmpl<int>()' "11. the member-template spelling is still WRITTEN"
uses      cpp memberTmpl 0 "11. NOT-CHECKED->MEASURED: obj.template f<T>() is ABSENT (literal 0)"
probeBlind cpp callerTemplates memberTmpl "11. …and it is absent at EXTRACTION, not lost in resolution"
# 16. cast keywords. tree-sitter-cpp parses every cast as call_expression function: template_function
# — the same node shape as spelling 9 — so the exclusion lives at capture time in ingest.cpp. Asserted
# pre-resolution: a cast ref resolves to nothing and would vanish while still inflating every count.
probeSees cpp callerCasts opaque "16. vacuity guard: callerCasts' real operands ARE extracted"
for kw in static_cast reinterpret_cast const_cast dynamic_cast; do
    fixtureHasLit cpp/main.cpp "$kw<" "16. the $kw spelling is still WRITTEN (this guard is why dynamic_cast now exists in the fixture)"
    probeBlind cpp callerCasts "$kw" "16. ABSENT BY DESIGN: $kw mints no reference"
done
# 17. most-vexing-parse. No call_expression exists on that line at all — unfixable by any widening.
fixtureHasLit cpp/main.cpp 'Guard vexed( q1::vexFn() );' "17. the most-vexing-parse declaration is still WRITTEN"
uses cpp vexFn 0 "17. ABSENT, UNFIXABLE: most-vexing-parse declaration, pinned at literal 0"
# 18. function-pointer variable: EXTRACTS as `fp`, never RESOLVES.
probeSees cpp callerFnPtr fp "18. call through a fn-pointer variable EXTRACTS (as the variable name)"
callees   cpp callerFnPtr 0  "18. …and RESOLVES to nothing — extracted-but-unresolved, not never-extracted"
# 19. destructor spellings. `d.~Dotted()` mints a reference named for the TYPE, never a call edge.
fixtureHasLit cpp/main.cpp 'd.~Dotted();'  "19. the dot destructor spelling is still WRITTEN"
fixtureHasLit cpp/main.cpp 'p->~Dotted();' "19. the arrow destructor spelling is still WRITTEN"
callees cpp callerDtor 0 "19. ABSENT (honest drop): explicit destructor calls produce no callee edge"
# ambiguity is DISCLOSED, and the fixture's one ambiguous spelling is named so a new one cannot hide.
MAPCPP="$( cxrun "$FIX/cpp" --no-cache )"
printf '%s' "$MAPCPP" | grep -qE 'ambiguous=1 unresolved=0' \
    && ok "[cpp] fixture header: ambiguous=1 unresolved=0" \
    || no "[cpp] fixture header: expected ambiguous=1 unresolved=0, got $( printf '%s' "$MAPCPP" | grep -oE 'ambiguous=[0-9]+ unresolved=[0-9]+' )"
printf '%s' "$MAPCPP" | grep -q '<s t="fn" n="callerCtor" amb="1"' \
    && ok "[cpp] the ONE ambiguous row is callerCtor — the qualified ctor splits over class Gadget and its explicit ctor, DISCLOSED" \
    || no "[cpp] callerCtor is missing its amb=\"1\": $( printf '%s' "$MAPCPP" | grep -oE '<s [^>]*amb="[0-9]+"' )"

echo
echo "=== C++ canonical multi-match — test/callformfix/cppcanon/ (W3-RUST carry-in) ==="
# The round's headline silent-drop class, in its C++ face: a qualified call whose canonical key
# matches SEVERAL defs, none of them in the caller's file or directory. Before graph.h's tier-3
# rescue learned `|| canonical` this DIED SILENTLY — no edge, no amb=, no unresolved= movement.
# Verified on the pre-round binary: --callees=crossDirCaller count="0".
callees cppcanon crossDirCaller 2 "q::canonFn matches TWO cross-directory defs: BOTH edges, never one silently chosen (base: 0)"
DCANON="$( cxrun "$FIX/cppcanon" --callees=crossDirCaller --no-cache )"
printf '%s' "$DCANON" | grep -qE '<s [^>]*p="[^"]*dira/one\.cpp:5"' \
  && printf '%s' "$DCANON" | grep -qE '<s [^>]*p="[^"]*dirb/two\.cpp:6"' \
    && ok "[cppcanon] the two rows are the two DEFINITIONS, by line (dira:5 and dirb:6)" \
    || no "[cppcanon] the rows are not the two cross-dir defs: $DCANON"
MAPCANON="$( cxrun "$FIX/cppcanon" --no-cache )"
printf '%s' "$MAPCANON" | grep -q '<s t="fn" n="crossDirCaller" amb="1"' \
    && ok "[cppcanon] crossDirCaller carries amb=\"1\" — the split is DISCLOSED per row, not guessed" \
    || no "[cppcanon] crossDirCaller has no amb=\"1\" — a silent multi-target pick is worse than a drop"
printf '%s' "$MAPCANON" | grep -qE 'edges=2 .*ambiguous=1 unresolved=0' \
    && ok "[cppcanon] header: edges=2 ambiguous=1 unresolved=0 — the ambiguity reaches the corpus gauge" \
    || no "[cppcanon] header wrong: $( printf '%s' "$MAPCANON" | grep -oE 'edges=[0-9]+ [^>]*' | head -1 )"

echo
echo "=== Rust — test/callformfix/rust/src/ ==="
# Before this round queries/rust/tags.scm had NO scoped_identifier pattern: 100% of the dominant
# Rust call form was invisible in a language the tool gate-claims.
uses rust bare_fn      1 "1. bare call"
uses rust method_fn    1 "2. method call"
uses rust assoc_fn     2 "3. Type::assoc — two call sites (caller + caller_ufcs_cast)"
uses rust mod_fn       1 "4. module::fn, 2 segments"
uses rust deep_fn      1 "5. module::module::fn, 3 segments"
uses rust self_fn      1 "6. Self:: — resolved to the ENCLOSING impl's type"
uses rust ufcs_fn      1 "7. UFCS: a method spelled as an associated fn"
uses rust turbo_bare   1 "8. turbofish on a bare fn (generic_function)"
uses rust turbo_scoped 1 "9. turbofish on a scoped path"
uses rust mymac        2 "11. macro invocations (two sites)"
uses rust file_mod_fn  1 "13. file-module call: src/plainmod.rs IS module plainmod"
calleeRow rust calls_self self_fn "6. Self::self_fn() reaches the impl's own method, precisely"
# 10 + 12. `<T as Trait>::method()` was NOT-CHECKED in the survey. MEASURED: CAPTURED, and resolved
# to the trait impl — the qualified_type path binds its final segment like any other scoped_identifier.
uses rust trait_fn 2 "10+12. trait method via receiver AND via <T as Trait>::method() — both captured"
calleeRow rust caller_ufcs_cast trait_fn "12. NOT-CHECKED->MEASURED: <Widget as Spin>::trait_fn() IS captured and resolves"
DRUSTU="$( cxrun "$FIX/rust" --callees=caller_ufcs_cast --no-cache )"
printf '%s' "$DRUSTU" | grep -qE '<s [^>]*n="trait_fn" p="[^"]*lib\.rs:9"' \
    && ok "[rust] …and it lands on the impl's trait_fn (lib.rs:9), not the trait declaration" \
    || no "[rust] <T as Trait>::method() bound the wrong def: $DRUSTU"
MAPRUST="$( cxrun "$FIX/rust" --no-cache )"
printf '%s' "$MAPRUST" | grep -qE 'ambiguous=0 unresolved=0' \
    && ok "[rust] fixture header: ambiguous=0 unresolved=0 — every spelling resolved PRECISELY" \
    || no "[rust] fixture header: expected ambiguous=0 unresolved=0, got $( printf '%s' "$MAPRUST" | grep -oE 'ambiguous=[0-9]+ unresolved=[0-9]+' )"

echo
echo "=== C# — test/callformfix/csharp/Main.cs ==="
uses csharp Bare          1 "1. bare call"
uses csharp Member        1 "2. member call"
uses csharp TwoSeg        1 "3. 2-segment member-access chain"
uses csharp ThreeSeg      1 "4. 3-segment member-access chain (nests LEFT)"
uses csharp CondOne       1 "5. conditional access w?.M() — dropped before this round"
uses csharp CondChain     1 "6. chained ?. — only the FINAL link's node kind matters"
uses csharp CondMixed     1 "7. mixed w?.Inner.M() — captured at base too, and the reason is the same rule"
uses csharp CondGeneric   1 "9. conditional access on a GENERIC method (the survey missed this variant)"
uses csharp GenericFree   1 "10. generic call, bare"
uses csharp MemberGeneric 1 "11. generic call, member"
uses csharp Widget        1 "8. new, unqualified"
uses csharp Gadget        1 "12. qualified new — C# qualified_name nests LEFT, so base bound it too"

echo
echo "=== Go — test/callformfix/go/main.go ==="
uses go bareFn          1 "1. bare call"
uses go selectorFn      1 "2. selector call"
uses go inferredGeneric 1 "3. inferred generic — the IDIOMATIC form, never broken"
uses go deferFn         1 "5. defer statement"
uses go goStmtFn        1 "6. go statement"
uses go parenFn         1 "7. parenthesized function expression"
# 4. THE HONEST REJECT. `Generic[int](1)` is not a call_expression at all — it parses as
# type_conversion_expression, the SAME node kind as index-then-call and as a conversion to a generic
# type. Capturing it by node kind cannot tell the three apart, so the tool declines. The next arm is
# the other half of that bargain and is the one that must never go green by accident.
fixtureHasLit go/main.go 'explicitGeneric[int](1)' "4. the explicit-instantiation spelling is still WRITTEN"
uses go explicitGeneric 0 "4. ABSENT: explicit generic instantiation, pinned at literal 0 (inherent grammar ambiguity)"
fixtureHasLit go/main.go 'fs[0](3)' "8. the index-then-call spelling is still WRITTEN"
probeBlind go callerIndexed fs       "8. index-then-call must NEVER be miscaptured as a call to \`fs\`"
probeBlind go callerIndexed indexedFn "8. …nor to the function value stored in the slice"

echo
echo "=== TypeScript — test/callformfix/typescript/main.ts ==="
uses typescript bareFn     1 "1. bare call"
uses typescript memberFn   1 "2. member call"
uses typescript threeLevel 1 "3. 3-level member chain"
uses typescript optionalFn 1 "4. optional-chain call"
uses typescript genericFn  1 "5. generic call"
uses typescript Widget     1 "6. new, unqualified"
uses typescript Inner      1 "7. qualified new, 2 segments — dropped before this round"
uses typescript Deep       1 "8. qualified new, 3 segments"
# 9. computed constructor position. `new tbl.ns[k]()` is a subscript, not a property_identifier.
fixtureHasLit typescript/main.ts 'new tbl.ns[ k ]()' "9. the computed-new spelling is still WRITTEN"
probeBlind typescript callerAbsent tbl "9. ABSENT: computed new a.b[c]() binds nothing"
# 10 + 11. W4 FINDING. The round record (V1-L5) says bare AND qualified GENERIC `new` drop and told
# this lane to pin them as documented-absent rows. MEASURED, that is true of JAVA only. In TypeScript
# `new GenWidget<string>()` binds on the PRE-ROUND binary as well, and `new ns.GenInner<string>()`
# binds at HEAD. Pinning these at 0 would have shipped a gate that is green only while the tool is
# wrong — so they are pinned CAPTURED, with the contradiction recorded at the assertion.
uses typescript GenWidget 1 "10. FINDING vs V1-L5: bare generic new IS captured in TS (and was at base)"
uses typescript GenInner  1 "11. FINDING vs V1-L5: qualified generic new IS captured in TS at HEAD (base: 0)"

echo
echo "=== JavaScript — test/callformfix/javascript/main.js ==="
uses javascript bareFn     1 "1. bare call"
uses javascript memberFn   1 "2. member call"
uses javascript threeLevel 1 "3. 3-level member chain"
uses javascript optionalFn 1 "4. optional-chain call"
uses javascript genericFn  1 "5. plain call (JS has no type arguments)"
uses javascript Widget     1 "6. new, unqualified"
uses javascript ping       1 "7. qualified new, 2 segments"
uses javascript pong       1 "8. qualified new, 3 segments"
uses javascript tagFn      1 "9. tagged template — a call_expression in this grammar"
fixtureHasLit javascript/main.js 'new tbl.ns[ k ]()' "10. the computed-new spelling is still WRITTEN"
probeBlind javascript callerAbsent tbl "10. ABSENT: computed new a.b[c]() binds nothing"

echo
echo "=== Java — test/callformfix/java/Main.java ==="
uses java bareFn    1 "1. bare call"
uses java memberFn  1 "2. member call"
uses java makeFn    1 "3. static call through the type — and NOT the method reference on line 60"
uses java threeSeg  1 "4. 3-segment invocation chain (method_invocation's name: is always final)"
uses java thisFn    1 "6. explicit this receiver"
uses java Widget    1 "5. new, unqualified"
uses java Inner     1 "7. scoped new, 2 segments — dropped before this round"
uses java Deep      1 "8. scoped new, 3 segments"
uses java PkgType   1 "9. fully package-qualified new"
# 10. method REFERENCE. `Widget::makeFn` names a target without invoking it; it belongs to the
# disclosed callback caveat. Streams lean on it heavily, which is exactly why it is pinned.
fixtureHasLit java/Main.java 'Widget::makeFn' "10. the method-reference spelling is still WRITTEN"
probeBlind java runAbsent makeFn "10. ABSENT (callback caveat): a method REFERENCE mints no call edge"
fixtureHasLit java/Main.java 'new GenBox<String>()' "11. the bare generic-new spelling is still WRITTEN"
uses java GenBox   0 "11. ABSENT: bare generic new — the type child is a generic_type"
fixtureHasLit java/Main.java 'new GenOuter.GenInner<String>()' "12. the qualified generic-new spelling is still WRITTEN"
uses java GenInner 0 "12. ABSENT: qualified generic new — same mechanism one level out"

echo
echo "=== Ruby — test/callformfix/ruby/main.rb ==="
uses ruby bare_paren_fn 1 "1. bare call WITH parentheses"
uses ruby member_fn     1 "2. method call through a receiver"
uses ruby receiver_fn   1 "3. module-function call, dot receiver"
uses ruby colon_fn      1 "4. :: used as the method-call operator"
uses ruby deep_fn       1 "5. scope_resolution receiver, then a dot call"
# 6. ABSENT BY DESIGN, stated in queries/ruby/tags.scm's own header: a bare, receiver-less,
# paren-less call is textually indistinguishable from a local-variable read.
# The presence guard here is the one V5 defeated: it deleted this very line and both arms below
# stayed green. Anchored so it matches the CALL inside caller_absent, never the `def` on line 10.
fixtureHasRe ruby/main.rb '^  bare_noparen_fn$' "6. the bare paren-less CALL is still WRITTEN (V5's deletion target)"
uses       ruby bare_noparen_fn 0 "6. ABSENT BY DESIGN: bare paren-less call, pinned at literal 0"
probeBlind ruby caller_absent bare_noparen_fn "6. …and absent at EXTRACTION, by the grammar's own disclosure"

echo
echo "=== Swift — test/callformfix/swift/main.swift ==="
uses swift bareFn    1 "1. bare call"
uses swift staticFn  1 "2. Type.static"
uses swift memberFn  1 "3. method call"
uses swift nsFn      1 "4. enum-namespace call"
uses swift deepFn    1 "5. 3-segment navigation chain"
uses swift Widget    1 "6. initializer call"
uses swift genericFn 1 "7. inferred generic"
probeSees swift caller f "8. call through a variable holding a function EXTRACTS (as the variable name)"
# 9. NOT-CHECKED in the survey. MEASURED: ABSENT, and for a reason stronger than a missing pattern —
# tree-sitter-swift produces NO call_expression for `specFn<Int>( 8 )` at all. The whole fixture holds
# exactly 8 call_expressions, which is caller()'s eight sites, so callerSpecialization contributes
# zero. Swift's grammar has no explicit type-argument list at a call site (inference is the language
# rule), so the spelling parses as a chain of comparisons. No widening can reach it.
fixtureHasLit swift/main.swift 'specFn<Int>( 8 )' "9. the explicit-specialization spelling is still WRITTEN"
uses swift specFn 0 "9. NOT-CHECKED->MEASURED: explicit specialization foo<Int>(x) is ABSENT (literal 0)"
SWHITS="$( cxrun "$FIX/swift" --match='(call_expression) @c' --no-cache | grep -oE 'hits="[0-9]+"' | tr -dc 0-9 )"
[ "${SWHITS:-X}" = 8 ] \
    && ok "[swift] 9. …and the cause is the GRAMMAR: 8 call_expressions in the file, all of them caller()'s" \
    || no "[swift] expected 8 call_expression nodes in the fixture, got '${SWHITS:-none}' — re-read the specialization verdict"

echo
echo "=== Python — test/callformfix/python/main.py ==="
uses python bare_fn     2 "1. bare call, plus the fn-value read on line 45"
uses python two_level   1 "2. 2-level attribute call"
uses python three_level 1 "3. 3-level attribute chain (attribute: is always final)"
uses python member_fn   1 "4. method call through an instance"
calleeRow python caller Widget "5. constructor call resolves to the class"
probeSees python caller_var_call f "6. call through a variable holding a function EXTRACTS (as the variable name)"

echo
echo "=== C — test/callformfix/c/main.c (the no-:: sibling control) ==="
uses c cBareFn 1 "1. bare call"
uses c C_MAC   1 "4. macro call — the macro def is itself a callable symbol"
probeSees c callerC dotFp   "2. struct field call (value) EXTRACTS as the field name"
probeSees c callerC arrowFp "3. struct field call (pointer) EXTRACTS as the field name"
probeSees c callerCFnPtr fp "5. fn-pointer variable call EXTRACTS as the variable name"
callees   c callerCFnPtr 0  "5. …and RESOLVES to nothing — the disclosed caveat, measured"

echo
echo "=== Bash — test/callformfix/bash/main.sh (no qualified form exists) ==="
uses bash plainFn     1 "1. plain command call"
uses bash argsFn      1 "2. call with arguments"
uses bash substFn     1 "3. command substitution"
uses bash pipeLeftFn  1 "4a. left side of a pipeline"
uses bash pipeRightFn 1 "4b. right side of a pipeline"
uses bash condFn      1 "5. call in an if-condition"

echo
echo "=== ObjC — test/callformfix/objc/main.m ==="
uses      objc objcBareFn 1 "1. plain C function call"
calleeRow objc callerObjc messageFn    "2. message send, no arguments"
calleeRow objc callerObjc messageArgFn "3. message send with keyword arguments"
# 4. THIS ROUND'S PARITY LINE. queries/objc/tags.scm had no field_expression call pattern although
# its parent C grammar carries one, so a struct fn-pointer field call minted NOTHING (base:
# --uses=initFp REFUSED — the name was not in the index at all). It extracts now and still does not
# resolve, which is the same honest end state queries/c/tags.scm produces (see the C section above).
probeSees objc callerObjcField initFp "4. ops->init() EXTRACTS (base: no reference at all — C parity closed)"
callees   objc callerObjcField 0      "4. …and RESOLVES to nothing — a fn-pointer field is not a definition"

# ════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== determinism + G4 well-formedness, across every corpus ==="
LANGS="bash c cpp cppcanon csharp go java javascript objc python ruby rust swift typescript"
for l in $LANGS; do
    A="$( cxrun "$FIX/$l" --no-cache )"
    B="$( cxrun "$FIX/$l" --no-cache )"
    if [ -z "$A" ]; then no "[$l] the map is EMPTY — determinism and xmllint would both pass vacuously"
    elif [ "$A" = "$B" ]; then ok "[$l] map is byte-identical run-to-run"
    else no "[$l] map is NOT deterministic"; fi
done
# A MISSING xmllint is a FAILURE, never a silent skip: G4 is a hard guardrail and a PASS count that
# quietly shrinks hides the hole. Three gates were dinged for the skip shape in this round alone;
# floormarkcheck's fixed arm is the template.
if ! command -v xmllint >/dev/null 2>&1; then
    no "xmllint is NOT INSTALLED — the G4 arm could not run, so this gate cannot claim well-formedness (install libxml2's xmllint)"
else
    for l in $LANGS; do
        M="$( cxrun "$FIX/$l" --no-cache )"
        [ -n "$M" ] || { no "[$l] nothing to validate — the map was empty"; continue; }
        printf '%s' "$M" | xmllint --noout - 2>/dev/null \
            && ok "[$l] map is well-formed XML" \
            || no "[$l] map FAILED xmllint"
    done
fi

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
