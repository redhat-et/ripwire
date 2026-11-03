#!/usr/bin/env bash
# narrowcheck.sh — gate for P2-D Rule 2 receiver-VARIABLE type narrowing (ABS-1 / locals-style scoping).
#
# The narrow: `Foo x; x.run()` and `auto y = Bar(); y.run()` resolve run to Foo::run / Bar::run ONLY
# (the var's type is known), instead of the bare §2a ladder's WRONG 1/k split across every same-named
# `run`. The soundness discipline (resolve.h::rule2RecvVarType) is "a wrong narrow is worse than no
# narrow": it fires ONLY when the var has a known, non-tombstoned type binding whose class actually
# DEFINES the called method (canonByName hit) — otherwise it degrades to §2a unchanged.
#
# The fixture pairs each narrowed caller with a NEGATIVE CONTROL of the SAME call shape whose receiver
# is a local the capture cannot type (`auto p = pool[ slot ]; p->run()`) — no var→type binding, so Rule 2
# can't fire and the call stays HONESTLY AMBIGUOUS. The narrowed-vs-control contrast is the proof the narrow
# is REAL (a binding-driven resolution, not a vacuously-unambiguous fixture). The control used to be a
# function PARAMETER; arms 7-18 are why it is not any more.
#
# Arms 7-16 — PARAMETER receivers (2026-09-16). A parameter's written type (LocalBindKind::ParamType) was
# captured but read only by the field use-site index, so `int Decoy::plainCaller( Target& other ) { return
# other.pick( 1 ); }` fell through Rule 2 to the S6-C locality tie-break, which hands the tie to the CALLER'S
# OWN class: one precise edge to Decoy::pick, no amb=, nothing disclosed. Rule 2 now reads ParamType records
# LEXICALLY — the innermost declaration of the name whose scope covers the call site decides, and only a
# declaration with a written type narrows. The fixture is GENERATED (line numbers are load-bearing: p= tells
# Target's methods, line 1, from Other's, line 2, and Decoy's, lines 5-6). Two kinds of arm:
#   * RED on the unfixed binary: the parameter/range-for/lambda receivers that must now pin to Target.
#   * RED on a NAIVE fix that folds ParamType into Rule 2's flat per-function table (observed, see the
#     commit): a range-for variable's type leaking to a later `auto` loop of the same name (12), to a
#     same-named FIELD read outside the loop (13), and an untyped nested redeclaration of a parameter (14);
#     plus (10), where the flat table's tombstone would throw away two precise answers.
#   * Arms 17-24 — a written type is recorded as its final segment and class names carry no namespace, so a type
#     written in namespace `std` (`std::map<int, int>`) matched an unrelated in-repo class `map`. `std` is reserved
#     to the implementation — a program declares no class in it — so a `std::`-led written type never narrows, for
#     a parameter (17), a typed local (19), a constructor-inferred local (20) and a C++ assignment (21). Every other
#     qualifier keeps its narrow: an in-repo namespace is the common case (22, 23). (24) pins the stated floor.
#   * Arm 25 — DISCLOSURE: a narrow decided by a qualified written type matched only its final segment, so it never reads
#     as precise. Its edge carries prov="final-segment" (the floor's wrong edge, a correct parameter narrow and the local
#     twin alike); an unqualified narrow and a uniquely named call carry no prov=, and both legends define the value.
#   * Arms 39-43 — TEMPLATE ARGUMENTS in a written type (2026-09-17). An unqualified template-id (`Vec<Decl *>& v`) recorded
#     no type at all, so `v.size()` never reached Rule 2, while its qualified twin (`ll::Vec<Decl *>&`) did; and a type
#     whose arguments sit before its last name (`Outer<int>::Inner& in`) recorded `Outer` — a precise edge to the wrong
#     class wherever `Outer` defines the method. The recorded name is now the type's LAST NAME read through the grammar's
#     fields, never cut from its text.
#     (39d) pins the stated floor: an unqualified template-id CONSTRUCTOR (`auto v = Vec<Decl *>()`) infers nothing.
#   * Arms 44-51 — an ASSIGNMENT's callee is a type only when a class is called that (2026-09-17). `t = ns::cast<Target>( y )`
#     recorded `cast`, and the conflict tombstoned the written `Target* t`: Rule 2's narrow (44, 45, 50), the field use-site
#     pin (49) and a member's Rule 2b narrow (46) were lost. A class-named assignment still types and still conflicts (47);
#     a DECLARATION initialised by a call still tombstones a sibling declaration (48); the new record byte round-trips
#     the cache (51).
#   * Arms 52-60 — a direct-initialized local whose every argument is a plain name (`IRBuilder<> Builder(Rem);`) parses as a
#     local FUNCTION declaration. The tags query minted a function symbol for it, the local's type binding was attributed
#     to that symbol instead of to the enclosing function, and Rule 2 never saw the type. RED on the unfixed binary:
#     52-58. RED on a naive fix that refuses every body-local declarator: 59. 60 pins the multiplication floor.
#
# Usage:
#   RIPWIRE_BIN=build/ripwire bash test/narrowcheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/narrowcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
# Byte order for every `sort` below: the want strings are C-ordered ("TBase::push_back@…" before "push_back@…"); en_US.UTF-8 swaps them (CI macos-26 red, arm 38).
export LC_ALL=C
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
FIX="$ROOT/test/narrowfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/narrowfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "narrowcheck: BIN=$BIN  CORPUS=test/narrowfix"

# L1 (2026-09-19): the CLI default legend is compact and spells a bare ambiguous= in its comment, which the first-match grep
# below would read; this run (and the (25f) legend-prose run) asks for the full legend.
"$BIN" "$FIX" --no-cache --legend=full >"$TMP/map" 2>/dev/null

# ── 1) headline: exactly ONE ambiguous call remains — the untyped control. The two local-var callers
#       (cpp g, py g) narrowed away their ambiguity entirely. ─────────────────────────────────────────
amb="$( grep -o 'ambiguous=[0-9]*' "$TMP/map" | head -1 | grep -o '[0-9]*' )"
[ "$amb" = "1" ] && ok "exactly one ambiguous call remains (ambiguous=1 — only the untyped control)" \
                 || no "ambiguous=$amb (expected 1: the two local-var calls should narrow, the untyped control stays split)"

# ── 2) the untyped control `h` (auto p = pool[ slot ]; p->run()) MUST stay ambiguous — no var→type binding,
#       so Rule 2 cannot fire and the call honestly splits to BOTH run defs. ──────────────────────────────
grep -q 'n="h" amb="1"' "$TMP/map" \
    && ok "untyped control h() stays AMBIGUOUS (amb=1 — proves the narrow needs a real binding)" \
    || { no "untyped control h() is not amb=1 (the negative control failed — narrow may be vacuous)"; grep -o 'n="h"[^>]*' "$TMP/map" | head; }

# ── 3) the local-var callers `g` (cpp `Foo x`/`auto y=Bar()`, py `x=Foo()`) MUST be narrowed → NO amb= marker.
#       (Same call shape as the control; the ONLY difference is the local binding ⇒ this is the real-narrow proof.)
if grep -oE 'n="g"[^>]*' "$TMP/map" | grep -q 'amb='; then
    no "a local-var caller g() is still marked ambiguous (narrow did not fire)"; grep -oE 'n="g"[^>]*' "$TMP/map"
else
    ok "local-var callers g() are NARROWED (no amb= — x.run→Foo::run, y.run→Bar::run resolved 1:1)"
fi

# ── 4) under-link guard: the narrow must RESOLVE the calls, not DROP them. The cpp caller still has BOTH
#       run edges, pointing at the two distinct run DEFS (Foo::run and Bar::run) — one each, not zero, not 4. ─
ce="$( "$BIN" "$FIX" --callees=g --no-cache 2>/dev/null )"
# member rows print Owner::name (member-owner vocabulary): the two targets must be exactly Bar::run and Foo::run
nruncpp="$( printf '%s' "$ce" | grep -o 'n="[A-Za-z]*::run"[^>]*cpp/recv.cpp:[0-9]*' | sort -u | wc -l | tr -d ' ' )"
runnames="$( printf '%s' "$ce" | grep -o 'n="[^"]*::run"[^>]*cpp/recv.cpp' | sed 's/^n="\([^"]*\)".*/\1/' | sort -u | tr '\n' ' ' | sed 's/ $//' )"
[ "$nruncpp" = "2" ] && [ "$runnames" = "Bar::run Foo::run" ] \
    && ok "cpp g() keeps BOTH run edges to distinct defs (no edge dropped, no cross-edge — $nruncpp targets)" \
    || { no "cpp g() has $nruncpp distinct run targets (want 2: Foo::run + Bar::run)"; printf '%s\n' "$ce" | tr '>' '\n' | grep run; }

# ── 5) determinism — the binding capture + narrow must be byte-stable run-to-run. ───────────────────────
"$BIN" "$FIX" --no-cache --legend=full >"$TMP/map2" 2>/dev/null
diff -q "$TMP/map" "$TMP/map2" >/dev/null \
    && ok "deterministic (narrowfix map byte-identical across two runs)" \
    || { no "non-deterministic narrowfix map"; diff "$TMP/map" "$TMP/map2" | head -6; }

# ── 6) cache transparency — narrowing facts (RawBind) survive the incremental cache: warm == cold. ──────
rm -f "$TMP/nc"
"$BIN" "$FIX" --cache="$TMP/nc" >/dev/null 2>&1
"$BIN" "$FIX" --cache="$TMP/nc" >"$TMP/warm" 2>/dev/null
"$BIN" "$FIX" --no-cache        >"$TMP/cold" 2>/dev/null
diff -q "$TMP/warm" "$TMP/cold" >/dev/null \
    && ok "cache-transparent (bindings round-trip: warm == cold)" \
    || { no "binding cache changes output (warm != cold)"; diff "$TMP/cold" "$TMP/warm" | head -6; }

# ── Arms 7-16: PARAMETER receivers (see the header). LINE NUMBERS ARE ASSERTED BELOW — edit with care.
#   Target::pick/peek c.cpp:1   Other::pick/peek c.cpp:2   Decoy::pick c.cpp:5, Decoy::peek c.cpp:6
PFIX="$TMP/paramfix"
mkdir -p "$PFIX"
cat >"$PFIX/c.cpp" <<'EOF'
struct Target { int pick( int n ) { return n; } int peek( int n ) { return n; } };
struct Other { int pick( int n ) { return n; } int peek( int n ) { return n; } };
struct Decoy
{
    int pick( int n ) { return n; }
    int peek( int n ) { return n; }
    int plainCaller( Target& other ) { return other.pick( 1 ); }
    int ptrCaller( Target* other ) { return other->pick( 1 ); }
    int localCaller() { Target other; return other.pick( 1 ); }
    int nestedTyped( Target& other, Other* os[] ) { int n = 0; for( const Other* other : os ) { n += other->peek( 1 ); } return n + other.pick( 2 ); }
    int lambdaCaller() { auto f = []( Target& t ) { return t.pick( 1 ); }; Target held; return f( held ); }
    Target& refCaller( Target& other ) { other.pick( 1 ); return other; }
    Target&& rvalueCaller( Target&& other ) { other.pick( 1 ); return static_cast<Target&&>( other ); }
    Target& outOfLineCaller( Target& other );
};
struct Box
{
    Other* item;
    Target ts[ 2 ];
    Other* os[ 2 ];
    int loopLeak() { int n = 0; for( const Target& t : ts ) { n += t.pick( 1 ); } for( auto t : os ) { n += t->peek( 2 ); } return n; }
    int fieldLeak() { int n = 0; for( const Target& item : ts ) { n += item.pick( 1 ); } return n + item->peek( 2 ); }
    int untypedShadow( Target& other ) { int n = 0; for( auto other : os ) { n += other->peek( 1 ); } return n + other.pick( 2 ); }
};
Target& Decoy::outOfLineCaller( Target& other ) { other.pick( 1 ); return other; }
EOF

# one caller's callee rows as sorted `Owner::name@line` words (the member-owner spelling a stored scope prints), restricted to
# one method name — the filter also admits a bare row, so one cannot hide from an exact want, and the wants spell Owner::. The probe must RUN:
# a missing <callees> element (unknown flag, refused selector, crash) prints a marker no assertion accepts.
rowsOf(){
    local out
    out="$( "$BIN" "$PFIX" "--callees=$1" --no-cache 2>/dev/null )"
    printf '%s' "$out" | grep -q "<callees [^>]*of=\"$1\" defs=\"1\"" || { printf 'NO-CALLEES-ANSWER'; return; }
    printf '%s' "$out" | grep -o '<s [^>]*>' | sed -n 's/.* n="\([^"]*\)".* p="c\.cpp:\([0-9]*\)".*/\1@\2/p' \
        | grep -E "^([A-Za-z_0-9]+::)?$2@" | sort -u | tr '\n' ' ' | sed 's/ $//'
}
expectRows(){   # arm label, caller, method, the exact expected row set
    local got
    got="$( rowsOf "$2" "$3" )"
    if [ "$got" = "$4" ]; then
        ok "$1 $2(): $3 -> [$got]"
    else
        no "$1 $2(): $3 -> [$got], want [$4]"
    fi
}
expectIncludes(){   # arm label, caller, method, a row the honest split must keep
    local got
    got="$( rowsOf "$2" "$3" )"
    case " $got " in
        *" $4 "*) ok "$1 $2(): $3 keeps $4 in its split -> [$got]" ;;
        *)        no "$1 $2(): $3 -> [$got] has no $4 — a declaration's type leaked past its scope" ;;
    esac
}

# presence guard: every probed caller and every candidate def is indexed, or the arms below prove nothing
PMAP="$( "$BIN" "$PFIX" --no-cache 2>/dev/null | tr '>' '\n' )"
pmiss=0
for want in 'n="pick" sc="Target"' 'n="peek" sc="Target"' 'n="pick" sc="Other"' 'n="peek" sc="Other"' 'n="pick" sc="Decoy"' 'n="peek" sc="Decoy"' \
            'n="plainCaller" sc="Decoy"' 'n="ptrCaller" sc="Decoy"' 'n="localCaller" sc="Decoy"' 'n="nestedTyped" sc="Decoy"' \
            'n="lambdaCaller" sc="Decoy"' 'n="loopLeak" sc="Box"' 'n="fieldLeak" sc="Box"' 'n="untypedShadow" sc="Box"' \
            'n="refCaller" sc="Decoy"' 'n="rvalueCaller" sc="Decoy"' 'n="outOfLineCaller" sc="Decoy"'; do
    printf '%s\n' "$PMAP" | grep -qF "$want" || { no "presence guard: paramfix symbol $want not indexed"; pmiss=1; }
done
[ "$pmiss" = 0 ] && ok "presence: all paramfix symbols indexed"

# ── 7) THE DEFECT: a reference parameter's method call pins to the parameter's type — not the enclosing class's
#       same-named method (Decoy::pick, line 5), which the locality tie-break used to hand it. ────────────────
expectRows "(7)" plainCaller pick "Target::pick@1"
# ── 8) a POINTER parameter, `other->pick( 1 )` — same fact, other declarator shape. ────────────────────────────
expectRows "(8)" ptrCaller pick "Target::pick@1"
# ── 9) control: the typed LOCAL of the same name already narrowed through Rule 2's Type record. ──────────────
expectRows "(9)" localCaller pick "Target::pick@1"
# ── 10) a typed range-for variable shadows the parameter INSIDE the loop only: peek goes to Other, the pick after
#        the loop to the parameter's Target. A flat per-function table would tombstone both (split). ──────────
expectRows "(10)" nestedTyped peek "Other::peek@2"
expectRows "(10)" nestedTyped pick "Target::pick@1"
# ── 11) a LAMBDA parameter types the call inside the lambda body. ────────────────────────────────────────────
expectRows "(11)" lambdaCaller pick "Target::pick@1"
# ── 12) scope leak, sibling loop: `for( const Target& t : ts )` narrows its own pick, and must NOT type the
#        later `for( auto t : os )` — that t is untyped, so its peek stays the honest split (Other::peek in it).
expectRows "(12)" loopLeak pick "Target::pick@1"
expectIncludes "(12)" loopLeak peek "Other::peek@2"
# ── 13) scope leak, field: `item->peek( 2 )` after the loop names the FIELD `Other* item`, not the loop variable.
expectRows "(13)" fieldLeak pick "Target::pick@1"
expectIncludes "(13)" fieldLeak peek "Other::peek@2"
# ── 14) an UNTYPED nested redeclaration (`for( auto other : os )`) hides the Target parameter inside the loop:
#        no narrow there; after the loop the parameter is back in scope and narrows. ───────────────────────────
expectIncludes "(14)" untypedShadow peek "Other::peek@2"
expectRows "(14)" untypedShadow pick "Target::pick@1"
# ── 61)-63) a definition RETURNING a reference records its parameters as well (2026-09-17, test/fieldnarrowcheck.sh arm v).
#        Its declarator chain reaches the function declarator through a reference_declarator, whose inner declarator is an
#        UNNAMED child, so the parameter list was never found: no ParamType, no VarDecl, and `other.pick( 1 )` fell to the
#        locality tie-break exactly as arm 7's did — inline `T&` (61), `T&&` (62), and out of line (63, after the census). ──
expectRows "(61)" refCaller pick "Target::pick@1"
expectRows "(62)" rvalueCaller pick "Target::pick@1"

# ── 15) the mechanism, not just the answer: the census names Rule 2 (receiver-rule) for plainCaller's site, where
#        the unfixed binary names the locality tie-break. ─────────────────────────────────────────────────────────
"$BIN" "$PFIX" --no-cache --pin-census="$TMP/census.tsv" >/dev/null 2>&1
mech="$( awk -F '\t' '$1 == "C" && $6 ~ /::Decoy::plainCaller#/ && $7 == "pick" { print $2 }' "$TMP/census.tsv" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//' )"
[ "$mech" = "receiver-rule" ] \
    && ok "(15) plainCaller's pick site is decided by receiver-rule (Rule 2), not the locality tie-break" \
    || no "(15) plainCaller's pick site mech=[${mech:-NO-CENSUS-ROW}], want [receiver-rule]"
# (63) an out-of-line definition has two defs (the in-class declaration too), which rowsOf refuses — read its census row
row63="$( awk -F '\t' '$1 == "C" && $6 ~ /::Decoy::outOfLineCaller#/ && $7 == "pick" { print $2 "|" $8 }' "$TMP/census.tsv" 2>/dev/null )"
case "$row63" in
    "receiver-rule|c.cpp::Target::pick#"*) ok "(63) Target& Decoy::outOfLineCaller( Target& other ) pins other.pick( 1 ) to Target::pick (receiver-rule)" ;;
    *) no "(63) Target& Decoy::outOfLineCaller( Target& other ): other.pick( 1 ) -> [${row63:-NO-CENSUS-ROW}], want [receiver-rule|c.cpp::Target::pick]" ;;
esac

# ── 16) determinism + cache transparency on the parameter fixture: the declaration byte Rule 2 now matches on is
#        re-derived from the cached record, so warm must equal cold. ─────────────────────────────────────────────
"$BIN" "$PFIX" --callees=nestedTyped --no-cache >"$TMP/p1" 2>/dev/null
"$BIN" "$PFIX" --callees=nestedTyped --no-cache >"$TMP/p2" 2>/dev/null
rm -f "$TMP/pc"
"$BIN" "$PFIX" --cache="$TMP/pc" >/dev/null 2>&1
"$BIN" "$PFIX" --callees=nestedTyped --cache="$TMP/pc" >"$TMP/pwarm" 2>/dev/null
if [ -s "$TMP/p1" ] && cmp -s "$TMP/p1" "$TMP/p2" && cmp -s "$TMP/p1" "$TMP/pwarm"; then
    ok "(16) paramfix --callees=nestedTyped byte-identical: cold, cold again, and warm"
else
    no "(16) paramfix --callees=nestedTyped differs across runs or warm vs cold"; diff "$TMP/p1" "$TMP/pwarm" | head -6
fi

# ── Arms 17-24: a written type is only its FINAL segment (`std::map<int, int>` records `map`), and class names carry no
#    namespace, so a type written in namespace `std` cannot be told apart from an unrelated same-named in-repo class by
#    its name — measured on a private C++ corpus as precise wrong edges from `const std::map<K, V>& ref; ref.lower_bound()`
#    and six `std::map<…> m; m.find()` LOCALS to an in-repo `map`. `std` is reserved to the implementation
#    ([namespace.std]: a program adds no declaration to it but a specialization), so no in-repo class IS `std::map`, and
#    a `std::`-led written type never narrows (the qualified text rides the record: kParserVer 97, and 98 for the
#    assignment). EVERY OTHER QUALIFIER KEEPS ITS NARROW, and that is measured, not assumed: refusing any qualifier —
#    this gate's rule for parameters until 2026-09-16 — refused 424 in-repo narrows on rocksdb (`ROCKSDB_NAMESPACE::
#    Status s; s.ok()`, `test::SleepingBackgroundTask`) and 9 on this repo's src/ (`rw::notes::NoteIndex`), every
#    sampled one correct, while fixing no wrong edge outside `std` on any of the three corpora. An include-visibility
#    guard was measured and rejected before that: path-precise includes miss include-root spellings. Candidates live in
#    two directories apart from the caller, so a refused narrow declines (no edge) instead of landing on a same-file or
#    same-directory guess.
VFIX="$TMP/visfix"
mkdir -p "$VFIX/lib" "$VFIX/lib2" "$VFIX/lib3" "$VFIX/app"
printf 'struct map { int find( int k ) { return k; } };\n'  >"$VFIX/lib/map.h"
printf 'struct dict { int find( int k ) { return k; } };\n' >"$VFIX/lib2/dict.h"
printf 'namespace store { struct tree { int find( int k ) { return k; } }; }\n' >"$VFIX/lib3/tree.h"
printf 'int lookupHidden( std::map<int, int>& table ) { return table.find( 1 ); }\n' >"$VFIX/app/hidden.cpp"
printf '#include "../lib/map.h"\nint lookupSeen( map& table ) { return table.find( 1 ); }\n' >"$VFIX/app/seen.cpp"
printf 'int lookupLocal() { std::map<int, int> table; return table.find( 1 ); }\n' >"$VFIX/app/local.cpp"
printf 'int lookupCtor() { auto table = std::map<int, int>(); return table.find( 1 ); }\n' >"$VFIX/app/ctor.cpp"
printf 'std::map<int, int> cache;\nint lookupAssign() { cache = std::map<int, int>(); return cache.find( 1 ); }\n' >"$VFIX/app/assign.cpp"
printf 'int lookupInRepoLocal() { store::tree table; return table.find( 1 ); }\nint lookupInRepoParam( const store::tree& table ) { return table.find( 1 ); }\n' >"$VFIX/app/inrepo.cpp"
printf 'int lookupExternal( ext::map<int, int>& table ) { return table.find( 1 ); }\n' >"$VFIX/app/external.cpp"
printf 'int helperOnly() { return 1; }\nint callsHelper() { return helperOnly(); }\n' >"$VFIX/app/plain.cpp"
visRows(){   # the find@<file> rows one caller's callees answer; NO-CALLEES-ANSWER when the probe did not run
    local out
    out="$( "$BIN" "$VFIX" "--callees=$1" --no-cache 2>/dev/null )"
    printf '%s' "$out" | grep -q "<callees [^>]*of=\"$1\" defs=\"1\"" || { printf 'NO-CALLEES-ANSWER'; return; }
    printf '%s' "$out" | grep -o '<s [^>]*>' | sed -n 's/.* n="\([A-Za-z_0-9]*::find\)".* p="\([^"]*\)".*/\1@\2/p' | sort -u | tr '\n' ' ' | sed 's/ $//'
}
expectNoStdNarrow(){   # arm label, caller, what the declaration writes
    local got
    got="$( visRows "$2" )"
    case "$got" in
        NO-CALLEES-ANSWER) no "$1 $2(): --callees did not answer" ;;
        "map::find@lib/map.h:1") no "$1 $2(): $3 narrowed to the unrelated in-repo lib/map.h map::find" ;;
        *) ok "$1 $2(): $3 is not a narrow -> [${got:-no edge}]" ;;
    esac
}
expectNarrow(){   # arm label, caller, the one expected row
    local got
    got="$( visRows "$2" )"
    if [ "$got" = "$3" ]; then
        ok "$1 $2(): narrows -> [$got]"
    else
        no "$1 $2(): -> [$got], want [$3]"
    fi
}
# ── 17) a PARAMETER written `std::map<int, int>&`: no narrow to the unrelated in-repo lib/map.h `map`. ────────────────
expectNoStdNarrow "(17)" lookupHidden "a std::-qualified parameter type"
# ── 18) control — the same call shape with an UNQUALIFIED `map&` narrows to lib/map.h exactly. ──────────────────────
expectNarrow "(18)" lookupSeen "map::find@lib/map.h:1"
# ── 19) a typed LOCAL `std::map<int, int> table;` — Rule 2's flat per-function table, not the lexical one. ──────────
expectNoStdNarrow "(19)" lookupLocal "a std::-qualified local type"
# ── 20) a local typed by its constructor, `auto table = std::map<int, int>()`. ──────────────────────────────────────
expectNoStdNarrow "(20)" lookupCtor "a std::-qualified constructor"
# ── 21) a C++ ASSIGNMENT from a constructor, `cache = std::map<int, int>()` (its record carried no qualified text
#        until kParserVer 98). ───────────────────────────────────────────────────────────────────────────────────────
expectNoStdNarrow "(21)" lookupAssign "a std::-qualified constructor assignment"
# ── 22) control — an IN-REPO namespace qualifier narrows a typed local, as it always did. ───────────────────────────
expectNarrow "(22)" lookupInRepoLocal "tree::find@lib3/tree.h:1"
# ── 23) the same in-repo qualifier on a PARAMETER narrows too (RED while a parameter refused every qualifier). ──────
expectNarrow "(23)" lookupInRepoParam "tree::find@lib3/tree.h:1"
# ── 24) STATED FLOOR, pinned so it stays a decision: a qualifier that is neither `std` nor the class's own namespace
#        (`ext::map<int, int>&`, an external or aliased type whose final segment an unrelated in-repo class shares) still
#        narrows on the final segment. Measured once on a private corpus (an alias template); closing it needs the
#        namespace chain in Symbol::scope, planned on its own. If this arm goes red, the floor moved: rewrite it to
#        assert the fixed behaviour, never delete it. ────────────────────────────────────────────────────────────────
expectNarrow "(24)" lookupExternal "map::find@lib/map.h:1"

# ── 25) DISCLOSURE (2026-09-16): the narrows arms 22-24 keep matched a QUALIFIED written type by its final segment alone —
#        the qualifier is never checked against the class's namespace (arm 24's is wrong) — so their edges must not read
#        as uniquely resolved. Each carries prov="final-segment"; arm 18's unqualified narrow and a uniquely named call
#        carry no prov=; the map legend and the compact legend define the value on the document that carries it. RED
#        before the attribute existed: (25) rows a, b, c and both legend rows. ─────────────────────────────────────────
"$BIN" "$VFIX" --no-cache --legend=full >"$TMP/vis.map" 2>/dev/null
"$BIN" "$VFIX" --no-cache --legend=compact >"$TMP/vis.compact" 2>/dev/null
provOf(){   # the prov= of caller $1's <c n="$2"> edge in map $3 (default: the VFIX map): a word, "none" when absent, NO-EDGE when missing
    local row
    row="$( tr '<' '\n' <"${3:-$TMP/vis.map}" | awk -v c="$1" '$1 == "s" && index( $0, " n=\"" c "\"" ) { on = 1; next } $1 == "s" || $1 == "/s>" { on = 0 } on' )"
    row="$( printf '%s\n' "$row" | grep "^c n=\"$2\"" | head -1 )"
    if [ -z "$row" ]; then
        printf 'NO-EDGE'
    elif printf '%s' "$row" | grep -q ' prov="'; then
        printf '%s' "$row" | sed -n 's/.* prov="\([^"]*\)".*/\1/p'
    else
        printf 'none'
    fi
}
expectProv(){   # arm label, caller, callee, expected prov word ("none" = absent), optional map file (provOf's $3)
    local got
    got="$( provOf "$2" "$3" "${5:-}" )"
    if [ "$got" = "$4" ]; then
        ok "$1 $2() -> $3: prov=[$got]"
    else
        no "$1 $2() -> $3: prov=[$got], want [$4]"
    fi
}
expectProv "(25a)" lookupExternal find final-segment      # the floor's WRONG edge is disclosed, never precise
expectProv "(25b)" lookupInRepoParam find final-segment   # a CORRECT qualified parameter narrow: still a final-segment match
expectProv "(25c)" lookupInRepoLocal find final-segment   # the typed LOCAL twin says the same
expectProv "(25d)" lookupSeen find none                   # an unqualified narrow: no qualifier was ever skipped
expectProv "(25e)" callsHelper helperOnly none            # a uniquely named call
if grep -q 'final-segment(' "$TMP/vis.map"; then
    ok "(25f) the map legend defines prov=final-segment on the map that carries it"
else
    no "(25f) the map legend does not define prov=final-segment"
fi
if grep -q 'final-segment' "$TMP/vis.compact"; then
    ok "(25g) the compact legend defines prov=final-segment"
else
    no "(25g) the compact legend does not define prov=final-segment"
fi
# ── Arms 26-31: CLASS IDENTITY — an interface-typed receiver and its NESTED NAMESAKES (2026-09-16). Rule 2 matched
#    `T::m` by the final class-name segment, and a nested class loses its enclosing class in that key: a call through
#    `Iterator* it` whose Iterator is an abstract interface (its methods are pure-virtual DECLARATIONS, never in the
#    definitions-only map) narrowed onto the unrelated nested `Iterator` classes that do define the method, and every
#    candidate was wrong (measured on rocksdb @ 0e2801ac3: 79 sites, 5-way splits over memtable/'s nested iterators).
#    Now: a hit owned by a nested class the caller cannot name is dropped, and when nothing is left and the method is
#    only DECLARED along the receiver class's ancestry, the call resolves to the definitions in the class's real
#    subclasses — an honest dispatch split, never trimmed to the same-file override by the locality ladder. LINE
#    NUMBERS ARE ASSERTED: include/iterator.h:6 IteratorBase::size; memtable/rep.h:12 ListRep::Iterator::key, :25
#    Skip::Iterator::key (out-of-line); db/impls.h:5 DBIter::key, :14 Outer::NestedIt::key; tests/use.cc:5 KVIter::key.
DFIX="$TMP/dispatchfix"
mkdir -p "$DFIX/include" "$DFIX/memtable" "$DFIX/db" "$DFIX/tests"
cat >"$DFIX/include/iterator.h" <<'EOF'
struct IteratorBase
{
    virtual ~IteratorBase() {}
    virtual bool Valid() const = 0;
    virtual int key() const = 0;
    virtual int size() const { return 0; }
};
struct Iterator : IteratorBase
{
    virtual int value() const = 0;
};
EOF
cat >"$DFIX/memtable/rep.h" <<'EOF'
struct MemRep
{
    struct Iterator
    {
        virtual int key() const = 0;
    };
};
struct ListRep : MemRep
{
    struct Iterator : MemRep::Iterator
    {
        int key() const override { return 1; }
        bool Valid() const { return true; }
    };
    int peek( Iterator& it ) { return it.key(); }
};
struct Skip
{
    struct Iterator
    {
        int key() const;
        bool Valid() const;
    };
};
inline int Skip::Iterator::key() const { return 2; }
inline bool Skip::Iterator::Valid() const { return true; }
EOF
cat >"$DFIX/db/impls.h" <<'EOF'
#include "../include/iterator.h"
struct DBIter : Iterator
{
    bool Valid() const override { return true; }
    int key() const override { return 3; }
    int value() const override { return 0; }
    int size() const override { return 7; }
};
struct Outer
{
    struct NestedIt : Iterator
    {
        bool Valid() const override { return true; }
        int key() const override { return 4; }
        int value() const override { return 0; }
    };
};
EOF
cat >"$DFIX/tests/use.cc" <<'EOF'
#include "../include/iterator.h"
struct KVIter : Iterator
{
    bool Valid() const override { return true; }
    int key() const override { return 5; }
    int value() const override { return 0; }
};
Iterator* makeIter();
int useParam( Iterator* it ) { return it->key(); }
int useLocal() { Iterator* it = makeIter(); return it->key(); }
int useInherited( Iterator& it ) { return it.size(); }
EOF
cat >"$DFIX/tests/qual.cc" <<'EOF'
#include "../memtable/rep.h"
int useQualified( Skip::Iterator& it ) { return it.key(); }
EOF
dispatchRows(){   # caller, callee name → its sorted `name@path:line` rows, or NO-CALLEES-ANSWER when the probe did not run
    local out
    out="$( "$BIN" "$DFIX" "--callees=$1" --no-cache 2>/dev/null )"
    printf '%s' "$out" | grep -q "<callees [^>]*of=\"$1\" defs=\"1\"" || { printf 'NO-CALLEES-ANSWER'; return; }
    printf '%s' "$out" | grep -o '<s [^>]*>' | sed -n 's/.* n="\([^"]*\)".* p="\([^"]*\)".*/\1@\2/p' | grep -E "^([A-Za-z_0-9]+::)?$2@" | sort -u | tr '\n' ' ' | sed 's/ $//'
}
expectDispatch(){   # arm label, caller, callee, the exact expected row set
    local got
    got="$( dispatchRows "$2" "$3" )"
    if [ "$got" = "$4" ]; then
        ok "$1 $2(): $3 -> [$got]"
    else
        no "$1 $2(): $3 -> [$got], want [$4]"
    fi
}
# lane L6 (Rule 4, by design): a call through the interface-typed receiver used to commit a prov="split" edge to each
# overrider (amb= on the caller); it is now DECLINED with exactly that list (ifacedispatch.h: <dc ... gate="iface">, the
# overriders as --legend=full cand=), never an edge. Arms 26, 27, 31 and 32 read the declined row; the premise — the three
# real overriders and neither nested namesake — is unchanged.
dispatchDeclined(){   # caller, callee name → the sorted `name@path:line` candidates of its gate="iface" <dc> row
    local out
    out="$( "$BIN" "$DFIX" "--callees=$1" --no-cache --legend=full 2>/dev/null )"
    printf '%s' "$out" | grep -q "<callees [^>]*of=\"$1\" defs=\"1\"" || { printf 'NO-CALLEES-ANSWER'; return; }
    printf '%s' "$out" | grep -o "<dc n=\"$2\"[^>]*gate=\"iface\"[^>]*>" | grep -o 'cand="[^"]*"' | sed 's/^cand="//; s/"$//' | tr ' ' '\n' \
        | sed "s/^/$2@/" | sort -u | tr '\n' ' ' | sed 's/ $//'
}
expectDispatchDeclined(){   # arm label, caller, callee, the exact expected candidate set
    local got
    got="$( dispatchDeclined "$2" "$3" )"
    if [ "$got" = "$4" ]; then
        ok "$1 $2(): $3 declined gate=\"iface\" over [$got]"
    else
        no "$1 $2(): $3 -> declined over [$got], want [$4]"
    fi
}
DISPATCH_KEYS="key@db/impls.h:14 key@db/impls.h:5 key@tests/use.cc:5"
# presence guard: the fixture's definitions and callers are indexed, or the arms below prove nothing
DMAP="$( "$BIN" "$DFIX" --no-cache 2>/dev/null | tr '>' '\n' )"
dmiss=0
for want in 'n="useParam"' 'n="useLocal"' 'n="useInherited"' 'n="peek"' 'n="useQualified"' 'n="DBIter"' 'n="NestedIt"' 'n="KVIter"'; do
    printf '%s\n' "$DMAP" | grep -qF "$want" || { no "presence guard: dispatchfix symbol $want not indexed"; dmiss=1; }
done
[ "$dmiss" = 0 ] && ok "presence: all dispatchfix symbols indexed"
# ── 26) THE DEFECT: `it->key()` through a PARAMETER typed with the interface reaches its three real overriders — the
#        top-level DBIter, the NESTED Outer::NestedIt (a nested subclass is still a subclass) and the same-file KVIter —
#        and neither nested namesake (ListRep::Iterator, Skip::Iterator), and is not trimmed to the same-file KVIter. ─
expectDispatchDeclined "(26)" useParam key "$DISPATCH_KEYS"
# ── 27) the same through a typed LOCAL (Rule 2's flat table), `Iterator* it = makeIter();`. ────────────────────────────
expectDispatchDeclined "(27)" useLocal key "$DISPATCH_KEYS"
# ── 28) INSIDE ListRep a bare `Iterator` IS ListRep::Iterator (a nested class is nameable in its enclosing class): the
#        visible nested owner stays, Skip's namesake goes. ──────────────────────────────────────────────────────────────
expectDispatch "(28)" peek key "Iterator::key@memtable/rep.h:12"
# ── 29) a QUALIFIED nested type, `Skip::Iterator& it`, names exactly Skip's nested class — its out-of-line def. ─────────
expectDispatch "(29)" useQualified key "Iterator::key@memtable/rep.h:25"
# ── 30) control — a method the interface's base DEFINES (`IteratorBase::size`) keeps the static inherited definition;
#        overriders join only when the ancestry has no body at all. ────────────────────────────────────────────────────
expectDispatch "(30)" useInherited size "IteratorBase::size@include/iterator.h:6"
# ── 31) the dispatch is disclosed, never a quiet single pin: useParam declines it (lane L6: a <dc gate="iface"> row; was amb=
#        and three split edges) and commits no edge to any overrider. ────────────────────────────────────────────────────
# the negative reads a row under its member spelling too (QUALNAME-1 prints Owner::key): a bare `n="key"` pattern could never match an
# overrider row, and `! grep` would pass vacuously. The control reads arm 28's answer, which carries an Owner::key row.
KEYROW='<s [^>]*n="([A-Za-z_0-9]+::)?key"'
D31="$( "$BIN" "$DFIX" --callees=useParam --no-cache 2>/dev/null )"
if ! "$BIN" "$DFIX" --callees=peek --no-cache 2>/dev/null | grep -qE "$KEYROW"; then
    no "(31) control: the key-row pattern does not match arm 28's Iterator::key row (the negative below would pass vacuously)"
elif printf '%s' "$D31" | grep -q '<dc n="key" [^>]*cands="3" via="declined" gate="iface"' && ! printf '%s' "$D31" | grep -qE "$KEYROW"; then
    ok "(31) useParam declines the dispatch (gate=\"iface\", cands=\"3\") and binds no overrider"
else
    no "(31) useParam: the dispatch is neither declined gate=\"iface\" cands=\"3\" nor edge-free: $( printf '%s' "$D31" | grep -oE '<(s|dc) [^>]*>' | head -3 | tr '\n' ' ' )"
fi
# ── Arms 32-35: the four shapes the corpora taught class identity (rocksdb, llvm-project, a private C++ corpus). ────────
# 32: a namespace-level FORWARD DECLARATION `class Iterator;` is not a class — counted as one it made every bare `Iterator`
#     read as several namesakes and refused arm 26's dispatch (rocksdb has five). db/fwd.h adds one; arms 26-27 re-run.
printf 'class Iterator;\nclass IteratorBase;\n' >"$DFIX/db/fwd.h"
expectDispatchDeclined "(32)" useParam key "$DISPATCH_KEYS"
# 33: a type ALIAS reaching a nested class (`using NodeSet = Graph::NodeSet;`, llvm's X86 LVI pass) is invisible to the
#     index; the nested class's header is visible from the caller, so its hit is never dropped for the unrelated
#     namespace-level `NodeSet` the caller never includes. pipe/pipeliner.h:1 must not be the whole answer.
mkdir -p "$DFIX/graph" "$DFIX/pipe"
printf 'struct Graph\n{\n    struct NodeSet\n    {\n        void clear() {}\n    };\n};\n' >"$DFIX/graph/graph.h"
printf 'struct NodeSet { void clear() {} };\n' >"$DFIX/pipe/pipeliner.h"
printf '#include "../graph/graph.h"\nstruct Pass\n{\n    using NodeSet = Graph::NodeSet;\n    void run() { NodeSet s; s.clear(); }\n};\n' >"$DFIX/graph/pass.cc"
got="$( dispatchRows run clear )"
case " $got " in
    *" NodeSet::clear@graph/graph.h:5 "*) ok "(33) run(): an aliased nested NodeSet keeps its clear -> [$got]" ;;
    *)                           no "(33) run(): clear -> [$got] lost graph/graph.h:5 — an alias's nested class was dropped for an unincluded namesake" ;;
esac
# 34: two NAMESPACE-level classes named Value (llvm::Value, sandboxir::Value): the base the derived class's file INCLUDES is
#     the one it means — here through an include-root spelling (`"ir/Value.h"`) the path-precise include set cannot resolve,
#     read as a path suffix, so the out-of-line sb::Value::getType in sandbox/Value.cc is not a candidate.
mkdir -p "$DFIX/ir" "$DFIX/sandbox" "$DFIX/opt"
printf 'struct Value\n{\n    int getType() const { return 1; }\n};\n' >"$DFIX/ir/Value.h"
printf 'namespace sb { struct Value { int getType() const; }; }\n' >"$DFIX/sandbox/Value.h"
printf '#include "sandbox/Value.h"\nint sb::Value::getType() const { return 2; }\n' >"$DFIX/sandbox/Value.cc"
printf '#include "ir/Value.h"\nstruct Inst : Value {};\n' >"$DFIX/ir/Inst.h"
printf '#include "ir/Inst.h"\nint typeOf( Inst* i ) { return i->getType(); }\n' >"$DFIX/opt/use.cc"
expectDispatch "(34)" typeOf getType "Value::getType@ir/Value.h:3"
# 35: an INHERITED BODY — `IOStatus` defines no `ok`, its base Status does — is the static answer through the typed receiver,
#     over a same-named `ok` elsewhere the name ladder could only split or decline over.
#     Caller, Status and the decoy sit in three directories and the caller includes both headers — the shape the ladder
#     DECLINES (two cross-directory candidates, no include narrow), measured as 397 formerly unlinked calls on rocksdb.
mkdir -p "$DFIX/status" "$DFIX/probe" "$DFIX/app"
printf 'struct Status\n{\n    bool ok() const { return true; }\n};\nstruct IOStatus : Status {};\n' >"$DFIX/status/status.h"
printf 'struct Probe { bool ok() const { return false; } };\n' >"$DFIX/probe/probe.h"
printf '#include "../status/status.h"\n#include "../probe/probe.h"\nbool healthy( IOStatus& s ) { return s.ok(); }\n' >"$DFIX/app/health.cc"
expectDispatch "(35)" healthy ok "Status::ok@status/status.h:3"
# ── 36) an identity CLAIM is not a final-segment guess: `hs::DiskHealth& d; d.fine()` resolves through class identity to the
#        inherited HealthBase::fine — one plausible class, its namespace evidenced in its file (a non-member of `hs` defined
#        there: a file holding only classes gives no namespace evidence, and the claim then stays out) — so the edge carries no
#        prov="final-segment", which says a qualified type was matched by its last name and nothing checked. Control: the
#        class-qualified `Skip::Iterator& it; it.key()` (arm 29) is a step-1 narrow, no claim, and keeps the disclosure. RED
#        on a merge that stamps every qualified receiver's edge: (36b). ──────────────────────────────────────────────────
printf 'namespace hs\n{\nstruct HealthBase\n{\n    bool fine() const { return true; }\n};\nstruct DiskHealth : HealthBase {};\ninline int version() { return 1; }\n}\n' >"$DFIX/status/ns.h"
printf 'struct Gauge { bool fine() const { return false; } };\n' >"$DFIX/probe/gauge.h"
printf '#include "../status/ns.h"\n#include "../probe/gauge.h"\nbool nsHealthy( hs::DiskHealth& d ) { return d.fine(); }\n' >"$DFIX/app/nshealth.cc"
expectDispatch "(36a)" nsHealthy fine "HealthBase::fine@status/ns.h:5"
"$BIN" "$DFIX" --no-cache >"$TMP/dispatch.map" 2>/dev/null
expectProv "(36b)" nsHealthy fine none "$TMP/dispatch.map"
expectProv "(36c)" useQualified key final-segment "$TMP/dispatch.map"

# ── 37) FLOOR, stated: an inherited body answers for EVERY overload of its name. rocksdb's BackupEngineReadOnlyBase pairs a
#        pure-virtual RestoreDBFromLatestBackup( options, db, wal ) with an inline compat overload ( db, wal, options = {} ), so
#        a call through `BackupEngine*` resolves to the compat body even when it passes RestoreOptions first, and the pure
#        overload's overrider is not joined. Joining it was built and measured (2026-09-17): 7 rocksdb sites, graded against
#        source 2 better and 5 worse (those 5 call the compat overload, which already answered RIGHT); 0 llvm-project sites.
#        Arity cannot tell the two apart — only argument TYPES could. If this arm goes red, the floor moved: rewrite it to
#        assert the fixed behaviour, never delete it. ─────────────────────────────────────────────────────────────────────────
mkdir -p "$DFIX/backup" "$DFIX/vecs"
printf 'struct ReadOnlyBase\n{\n    virtual ~ReadOnlyBase() {}\n    virtual int Restore( int opts, int dir ) = 0;\n    int Restore( int dir, int wal = 0 ) { return Restore( wal, dir ); }\n};\nstruct Engine : ReadOnlyBase {};\n' >"$DFIX/backup/engine.h"
printf '#include "engine.h"\nstruct EngineImpl : Engine\n{\n    int Restore( int opts, int dir ) override { return opts + dir; }\n};\n' >"$DFIX/backup/impl.cc"
printf '#include "../backup/engine.h"\nint restoreAll( Engine* e ) { return e->Restore( 1, 2 ); }\n' >"$DFIX/app/restore.cc"
expectDispatch "(37)" restoreAll Restore "ReadOnlyBase::Restore@backup/engine.h:5"
# ── 38) a class template's SPECIALIZATION defines the method too: llvm's `SmallVectorImpl<FunctionDecl *>& v; v.push_back( FD )`
#        claimed the primary SmallVectorTemplateBase::push_back, while pointer T selects SmallVectorTemplateBase<T, true> —
#        whose members have no class symbol (scope `TBase<T, true>`), so the ancestor walk never saw them (sampled: none ->
#        wrong, 133 llvm sites). The defining level now adds its template's specialization-scoped definitions: the family
#        split, holding the one the instantiation picks. RED before: (38). ───────────────────────────────────────────────────
printf 'namespace ll\n{\ntemplate <typename T, bool = false>\nclass TBase\n{\npublic:\n    void push_back( const T& x ) {}\n};\ntemplate <typename T>\nclass TBase<T, true>\n{\npublic:\n    void push_back( T x ) {}\n};\ntemplate <typename T>\nclass VecImpl : public TBase<T>\n{\n};\ninline int version() { return 1; }\n}\n' >"$DFIX/vecs/adt.h"
printf 'struct Log { void push_back( int ) {} };\n' >"$DFIX/probe/log.h"
printf '#include "../vecs/adt.h"\n#include "../probe/log.h"\nstruct Decl;\nvoid fillQ( ll::VecImpl<Decl *> &v, Decl* d )\n{\n    v.push_back( d );\n}\n' >"$DFIX/app/fill.cc"
# (the explicit specialization `TBase<T, true>` is no type name, so its row keeps the bare spelling: a stated floor — if it
# starts printing TBase::push_back, update this want)
expectDispatch "(38)" fillQ push_back "TBase::push_back@vecs/adt.h:7 push_back@vecs/adt.h:13"

# ── Arms 39-43: TEMPLATE ARGUMENTS in a receiver's written type (see the header). The record keeps the type's last name, and
#    finalSegment() cut a spelling at its FIRST `<`: an unqualified template-id (a `template_type` node) was refused outright,
#    and `Outer<int>::Inner` was cut to `Outer`. llvm-project writes the first shape wherever code sits inside `namespace llvm`
#    or imports the name (`SmallVectorImpl<FunctionDecl *> &Decls; Decls.push_back( FD )`). Every candidate lives in a header
#    two directories from the caller, beside a same-named decoy the caller also includes, so a call Rule 2 cannot type
#    declines instead of landing on a locality guess. LINE NUMBERS ARE ASSERTED: vecs/adt.h:7 Vec::size, :13 TBase::push_back,
#    :19 TBase<T, true>::push_back, :28 Outer::size, :31 Outer::Inner::size; probe/log.h:3-4 the Log decoys.
TFIX="$TMP/tmplfix"
mkdir -p "$TFIX/vecs" "$TFIX/probe" "$TFIX/app"
cat >"$TFIX/vecs/adt.h" <<'EOF'
namespace ll
{
template <typename T>
class Vec
{
public:
    int size() const { return 0; }
};
template <typename T, bool = false>
class TBase
{
public:
    void push_back( const T& x ) {}
};
template <typename T>
class TBase<T, true>
{
public:
    void push_back( T x ) {}
};
template <typename T>
class VecImpl : public TBase<T>
{
};
template <typename T>
struct Outer
{
    int size() const { return 1; }
    struct Inner
    {
        int size() const { return 2; }
    };
};
inline int version() { return 1; }
}
EOF
cat >"$TFIX/probe/log.h" <<'EOF'
struct Log
{
    void push_back( int ) {}
    int size() const { return 3; }
};
EOF
cat >"$TFIX/app/sizes.cc" <<'EOF'
#include "../vecs/adt.h"
#include "../probe/log.h"
struct Decl;
using namespace ll;
int sizeParam( Vec<Decl *>& v ) { return v.size(); }
int sizeLocal() { Vec<Decl *> v; return v.size(); }
int sizeLoop() { int n = 0; for( const Vec<int>& v : table ) { n += v.size(); } return n; }
int sizeCtor() { auto v = Vec<Decl *>(); return v.size(); }
int sizeStdArg( const Vec<std::string>& v ) { return v.size(); }
int sizeInner( Outer<int>::Inner& in ) { return in.size(); }
int sizeInnerLocal() { Outer<int>::Inner in; return in.size(); }
int sizeInnerCtor() { auto in = Outer<int>::Inner(); return in.size(); }
EOF
cat >"$TFIX/app/fill.cc" <<'EOF'
#include "../vecs/adt.h"
#include "../probe/log.h"
struct Decl;
using namespace ll;
void fillQ( ll::VecImpl<Decl *>& v, Decl* d ) { v.push_back( d ); }
void fillU( VecImpl<Decl *>& v, Decl* d ) { v.push_back( d ); }
void fillL( Decl* d ) { VecImpl<Decl *> v; v.push_back( d ); }
namespace ll
{
void fillN( VecImpl<Decl *>& v, Decl* d ) { v.push_back( d ); }
}
EOF
tmplRows(){   # caller, callee name → its sorted `name@path:line` rows, or NO-CALLEES-ANSWER when the probe did not run
    local out
    out="$( "$BIN" "$TFIX" "--callees=$1" --no-cache 2>/dev/null )"
    printf '%s' "$out" | grep -q "<callees [^>]*of=\"$1\" defs=\"1\"" || { printf 'NO-CALLEES-ANSWER'; return; }
    printf '%s' "$out" | grep -o '<s [^>]*>' | sed -n 's/.* n="\([^"]*\)".* p="\([^"]*\)".*/\1@\2/p' | grep -E "^([A-Za-z_0-9]+::)?$2@" | sort -u | tr '\n' ' ' | sed 's/ $//'
}
expectTmpl(){   # arm label, caller, callee, the exact expected row set
    local got
    got="$( tmplRows "$2" "$3" )"
    if [ "$got" = "$4" ]; then
        ok "$1 $2(): $3 -> [$got]"
    else
        no "$1 $2(): $3 -> [${got:-no edge}], want [$4]"
    fi
}
# presence guard: the fixture's definitions and callers are indexed, or the arms below prove nothing
TMAP="$( "$BIN" "$TFIX" --no-cache 2>/dev/null | tr '>' '\n' )"
tmiss=0
for want in 'n="Vec"' 'n="VecImpl"' 'n="Outer"' 'n="Inner"' 'n="Log"' 'n="sizeParam"' 'n="sizeInnerCtor"' 'n="fillQ"' 'n="fillN"'; do
    printf '%s\n' "$TMAP" | grep -qF "$want" || { no "presence guard: tmplfix symbol $want not indexed"; tmiss=1; }
done
[ "$tmiss" = 0 ] && ok "presence: all tmplfix symbols indexed"
# ── 39) THE DEFECT: an UNQUALIFIED template-id types its receiver like any class name — as a parameter (a), a local (b) and a
#        range-for variable (c). RED before: no edge. (d) is a STATED FLOOR: a constructor spelled as an unqualified
#        template-id, `auto v = Vec<Decl *>()`, infers nothing, because that spelling is every cast helper — reading it
#        records `dyn_cast` as the type of `auto *CI = dyn_cast<CallInst>( I )`, whose conflict with a written type or a
#        second declaration tombstones the variable: 324 edges lost on llvm-project on integration/train-3, 779 on main
#        before #278 dropped an assignment's callee name (ingest_binds.h ctorNameNode). If (d) goes red, the floor moved:
#        rewrite it to assert the fixed behaviour, never delete it. ──────────────────────────────────────────────────────────
expectTmpl "(39a)" sizeParam size "Vec::size@vecs/adt.h:7"
expectTmpl "(39b)" sizeLocal size "Vec::size@vecs/adt.h:7"
expectTmpl "(39c)" sizeLoop size "Vec::size@vecs/adt.h:7"
expectTmpl "(39d)" sizeCtor size ""
# ── 40) a `std::` template ARGUMENT does not make the type qualified: `const Vec<std::string>& v` narrows, is not refused as
#        a standard type, and its edge carries no prov="final-segment" (no qualifier was skipped). RED on a fix that reads
#        qualification off the whole spelling: prov=final-segment. ───────────────────────────────────────────────────────────
expectTmpl "(40a)" sizeStdArg size "Vec::size@vecs/adt.h:7"
"$BIN" "$TFIX" --no-cache >"$TMP/tmpl.map" 2>/dev/null
expectProv "(40b)" sizeStdArg size none "$TMP/tmpl.map"
# ── 41) template arguments BEFORE the last name: `Outer<int>::Inner` is Inner, not Outer — a parameter (a), a local (b) and a
#        constructor (c). RED before: one precise edge to Outer::size, line 28. ───────────────────────────────────────────
expectTmpl "(41a)" sizeInner size "Inner::size@vecs/adt.h:31"
expectTmpl "(41b)" sizeInnerLocal size "Inner::size@vecs/adt.h:31"
expectTmpl "(41c)" sizeInnerCtor size "Inner::size@vecs/adt.h:31"
# ── 42) the SPELLING never decides: the unqualified parameter, local and in-namespace twins of fillQ's
#        `ll::VecImpl<Decl *>&` resolve exactly as it does. VecImpl defines no push_back, so the answer is whatever the
#        resolver makes of an inherited member — its base template's family split where class identity walks the bases,
#        a decline where nothing does; either way one answer for every spelling. RED before on a resolver that walks the
#        bases: the qualified twin resolved and the unqualified ones declined. ──────────────────────────────────────────────
twinQ="$( tmplRows fillQ push_back )"
for twin in fillU fillL fillN; do
    got="$( tmplRows "$twin" push_back )"
    if [ "$twinQ" = NO-CALLEES-ANSWER ] || [ "$got" != "$twinQ" ]; then
        no "(42) $twin(): push_back -> [${got:-no edge}], its qualified twin fillQ() -> [${twinQ:-no edge}]"
    else
        ok "(42) $twin(): push_back -> [${got:-no edge}], as its qualified twin fillQ()"
    fi
done
# ── 43) the mechanism, not just the answer: the census names Rule 2 (receiver-rule) for sizeParam's site. ─────────────────
"$BIN" "$TFIX" --no-cache --pin-census="$TMP/tmpl.tsv" >/dev/null 2>&1
mech="$( awk -F '\t' '$1 == "C" && $6 ~ /::sizeParam#/ && $7 == "size" { print $2 }' "$TMP/tmpl.tsv" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//' )"
[ "$mech" = "receiver-rule" ] \
    && ok "(43) sizeParam's size site is decided by receiver-rule (Rule 2)" \
    || no "(43) sizeParam's size site mech=[${mech:-NO-CENSUS-ROW}], want [receiver-rule]"

# ── Arms 44-51: a type read off an ASSIGNMENT's callee (2026-09-17). C++ `x = f( … )` records the callee's last name as
#    x's type, because a constructor call and a function call are one grammar node — `t = ns::cast<Target>( y )` recorded
#    `cast`, `t = makeTarget( y )` recorded `makeTarget`. Rule 2's flat per-function table tombstones a variable whose
#    records disagree, so the non-type erased the variable's WRITTEN type (`Target* t = nullptr;`) and the call declined
#    (a same-named method sits two directories away); the field use-site index lost the same pin, and the record made a
#    MEMBER assigned from a call read as a local, so Rule 2b refused its declared type. An assignment declares nothing, so
#    its callee is a type only when the corpus defines a class of that name. Candidates live two directories apart from the
#    caller and nothing is included, so an unnarrowed call declines (no edge) instead of landing on a same-directory guess.
AFIX="$TMP/assignfix"
mkdir -p "$AFIX/lib" "$AFIX/lib2" "$AFIX/lib3" "$AFIX/app"
printf 'struct Target { int pick( int n ) { return n; } int count; };\n' >"$AFIX/lib/target.h"
printf 'struct Decoy { int pick( int n ) { return n; } int count; };\n'  >"$AFIX/lib2/decoy.h"
printf 'namespace ns { template <class T, class F> T* cast( F* from ) { return static_cast<T*>( from ); } }\nTarget* makeTarget( void* p );\n' >"$AFIX/lib3/cast.h"
cat >"$AFIX/app/use.cpp" <<'EOF'
int assignCast( void* y ) { Target* t = nullptr; t = ns::cast<Target>( y ); return t->pick( 1 ); }
int assignCall( void* y ) { Target* t = nullptr; t = makeTarget( y ); return t->pick( 1 ); }
int countCast( void* y ) { Target* t = nullptr; t = ns::cast<Target>( y ); return t->count; }
struct Holder
{
    Target* cur;
    int memberCast( void* y ) { cur = ns::cast<Target>( y ); return cur->pick( 1 ); }
};
int assignCtor() { Decoy d; d = Decoy(); return d.pick( 1 ); }
int twoCtors() { int n = 0; { auto t = Target(); n += t.pick( 1 ); } { auto t = Decoy(); n += t.pick( 2 ); } return n; }
int declCast( void* y ) { int n = 0; { auto t = ns::cast<Decoy>( y ); n += t->pick( 1 ); } { Target* t = nullptr; n += t->pick( 2 ); } return n; }
EOF
assignRows(){   # caller → its sorted pick@<path:line> rows, or NO-CALLEES-ANSWER when the probe did not run
    local out
    out="$( "$BIN" "$AFIX" "--callees=$1" --no-cache 2>/dev/null )"
    printf '%s' "$out" | grep -q "<callees [^>]*of=\"$1\" defs=\"1\"" || { printf 'NO-CALLEES-ANSWER'; return; }
    printf '%s' "$out" | grep -o '<s [^>]*>' | sed -n 's/.* n="\([A-Za-z_0-9]*::pick\)".* p="\([^"]*\)".*/\1@\2/p' | sort -u | tr '\n' ' ' | sed 's/ $//'
}
expectAssign(){   # arm label, caller, the exact expected row set
    local got
    got="$( assignRows "$2" )"
    if [ "$got" = "$3" ]; then
        ok "$1 $2(): pick -> [$got]"
    else
        no "$1 $2(): pick -> [${got:-no edge}], want [$3]"
    fi
}
# presence guard: both candidate defs, both fields and every probed caller are indexed, or the arms below prove nothing
AMAP="$( "$BIN" "$AFIX" --no-cache 2>/dev/null | tr '>' '\n' )"
amiss=0
for want in 'n="pick" sc="Target"' 'n="pick" sc="Decoy"' 'n="assignCast"' 'n="assignCall"' 'n="countCast"' 'n="memberCast" sc="Holder"' \
            'n="assignCtor"' 'n="twoCtors"' 'n="declCast"'; do
    printf '%s\n' "$AMAP" | grep -qF "$want" || { no "presence guard: assignfix symbol $want not indexed"; amiss=1; }
done
[ "$amiss" = 0 ] && ok "presence: all assignfix symbols indexed"
# ── 44) THE DEFECT: `t = ns::cast<Target>( y )` recorded `cast` and tombstoned the written `Target* t`. RED before: no edge. ──
expectAssign "(44)" assignCast "Target::pick@lib/target.h:1"
# ── 45) the same through a plain function, `t = makeTarget( y )`. RED before: no edge. ─────────────────────────────────────
expectAssign "(45)" assignCall "Target::pick@lib/target.h:1"
# ── 46) a MEMBER assigned from a call, `cur = ns::cast<Target>( y )`: the record is no local, so Rule 2b reads the field's
#        declared `Target* cur`. RED before: no edge. ──────────────────────────────────────────────────────────────────────
expectAssign "(46)" memberCast "Target::pick@lib/target.h:1"
# ── 47) controls — a CONSTRUCTOR still types: an assignment from a class the corpus defines agrees with its declaration (a),
#        and two constructor-typed declarations of one name in sibling blocks still tombstone and decline, never one leaking to
#        the other (b). Green before and after. ────────────────────────────────────────────────────────────────────────────
expectAssign "(47a)" assignCtor "Decoy::pick@lib2/decoy.h:1"
expectAssign "(47b)" twoCtors ""
# ── 48) a DECLARATION initialised by a call still counts as a declaration of unknown type: `auto t = ns::cast<Decoy>( y )`
#        in one block beside `Target* t` in another keeps the flat table's tombstone and both decline, or the second block's
#        type would reach the first block's call — one precise edge to the wrong class. Green before; RED on a fix that drops
#        every call-read type. ─────────────────────────────────────────────────────────────────────────────────────────────
expectAssign "(48)" declCast ""
# ── 49) the field use-site index shares the flat table's rule: `t->count` after the cast assignment pins to Target.count
#        (no owner_candidates=). RED before: owner_candidates="2". ─────────────────────────────────────────────────────────
uses="$( "$BIN" "$AFIX" --uses=Target.count --no-cache 2>/dev/null )"
urow="$( printf '%s' "$uses" | tr '<' '\n' | grep '^u ' | grep 'app/use.cpp:3"' | head -1 )"
if ! printf '%s' "$uses" | grep -q '<uses [^>]*of="Target.count"'; then
    no "(49) --uses=Target.count did not answer"
elif [ -z "$urow" ]; then
    no "(49) --uses=Target.count has no row at app/use.cpp:3"
elif printf '%s' "$urow" | grep -q 'owner_candidates='; then
    no "(49) countCast's t->count is not pinned to Target.count: <$urow"
else
    ok "(49) countCast's t->count pins to Target.count: <$urow"
fi
# ── 50) the mechanism, not just the answer: the census names Rule 2 (receiver-rule) for assignCast's site. RED before. ─────
"$BIN" "$AFIX" --no-cache --pin-census="$TMP/assign.tsv" >/dev/null 2>&1
mech="$( awk -F '\t' '$1 == "C" && $6 ~ /::assignCast#/ && $7 == "pick" { print $2 }' "$TMP/assign.tsv" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//' )"
[ "$mech" = "receiver-rule" ] \
    && ok "(50) assignCast's pick site is decided by receiver-rule (Rule 2)" \
    || no "(50) assignCast's pick site mech=[${mech:-NO-CENSUS-ROW}], want [receiver-rule]"
# ── 51) determinism + cache transparency: whether a record was read off an assignment rides the cached record, so warm must
#        equal cold. RED on a fix that does not persist it. ───────────────────────────────────────────────────────────────────
"$BIN" "$AFIX" --no-cache >"$TMP/a1" 2>/dev/null
"$BIN" "$AFIX" --no-cache >"$TMP/a2" 2>/dev/null
rm -rf "$TMP/ac"
"$BIN" "$AFIX" --cache="$TMP/ac" >/dev/null 2>&1
"$BIN" "$AFIX" --cache="$TMP/ac" >"$TMP/awarm" 2>/dev/null
if [ -s "$TMP/a1" ] && cmp -s "$TMP/a1" "$TMP/a2" && cmp -s "$TMP/a1" "$TMP/awarm"; then
    ok "(51) assignfix map byte-identical: cold, cold again, and warm"
else
    no "(51) assignfix map differs across runs or warm vs cold"; diff "$TMP/a1" "$TMP/awarm" | head -6
fi

# ── Arms 52-60 (2026-09-17): a DIRECT-INITIALIZED local whose every argument is a plain name — `IRBuilder<> Builder(Rem);`,
#    `std::lock_guard<std::mutex> Lock(Mtx);`, `Slice end(end_str);` — is the most-vexing-parse shape. The grammar cannot
#    tell a name from a type, so it reads the statement as a local FUNCTION declaration, and the tags query minted a
#    function symbol `Builder` whose span is the declaration. The local's type binding was attributed to that symbol (the
#    innermost span covering the declaration byte), not to the function the local lives in, so Rule 2 looked up
#    `<enclosing fn>#Builder`, found nothing, and `Builder.CreateSExt()` fell to the name ladder. A body-local declarator
#    now mints no symbol unless something in it can only be written in a prototype. Candidates live two directories away
#    from the caller, and nothing is #included, so a site no rule decides DECLINES (no edge) instead of reaching Rule 3.
#    LINE NUMBERS ARE ASSERTED BELOW: Widget/Box/store::Shelf at lib/widget.h:1/2/3, the vexing locals at vexing.cpp:2-8.
XFIX="$TMP/vexingfix"
mkdir -p "$XFIX/lib" "$XFIX/lib2" "$XFIX/app"
printf 'struct Widget { Widget( int n ) {} Widget( int a, int b ) {} int pick( int k ) { return k; } };\ntemplate <typename T = int> struct Box { Box( int n ) {} int pick( int k ) { return k; } };\nnamespace store { struct Shelf { Shelf( int n ) {} int pick( int k ) { return k; } }; }\n' >"$XFIX/lib/widget.h"
printf 'struct Other { int pick( int k ) { return k + 1; } };\n' >"$XFIX/lib2/other.h"
cat >"$XFIX/app/vexing.cpp" <<'EOF'
int nextSeed() { return 3; }
int pickOne( int seed ) { Widget w( seed ); return w.pick( 1 ); }
int pickTwo( int a, int b ) { Widget w( a, b ); return w.pick( 2 ); }
int pickCall() { Widget w( nextSeed() ); return w.pick( 3 ); }
int pickIndex( int* seeds ) { Widget w( seeds[ 0 ] ); return w.pick( 4 ); }
int pickQualified( int seed ) { store::Shelf s( seed ); return s.pick( 5 ); }
int pickTemplate( int seed ) { Box<> b( seed ); return b.pick( 6 ); }
int pickProduct( int a, int b ) { Widget w( a * b ); return w.pick( 7 ); }
int pickLiteral() { Widget w( 8 ); return w.pick( 8 ); }
int prototypes()
{
    void helperVoid( Widget );
    Widget helperPrim( int );
    Widget helperNamed( Widget other );
    Widget helperPtr( Other* );
    Widget helperNone();
    extern Widget helperExtern( Other );
    Widget helperConst( const Other& );
    return 0;
}
EOF
# a class body the grammar misreads as a FUNCTION body (an export macro before the class name): its member declarations
# arrive as body-local declarators too, and their trailing `const` / `override` is what keeps them.
cat >"$XFIX/app/misparse.h" <<'EOF'
#define API_MACRO
class API_MACRO Stream : public Other
{
public:
    int count( Widget ) const;
    Widget copy( Other ) override;
};
EOF
xRows(){   # the pick@<file:line> rows one caller's callees answer; NO-CALLEES-ANSWER when the probe did not run
    local out
    out="$( "$BIN" "$XFIX" "--callees=$1" --no-cache 2>/dev/null )"
    printf '%s' "$out" | grep -q "<callees [^>]*of=\"$1\" defs=\"1\"" || { printf 'NO-CALLEES-ANSWER'; return; }
    printf '%s' "$out" | grep -o '<s [^>]*>' | sed -n 's/.* n="\([A-Za-z_0-9]*::pick\)".* p="\([^"]*\)".*/\1@\2/p' | sort -u | tr '\n' ' ' | sed 's/ $//'
}
expectX(){   # arm label, caller, the exact expected row set ("" = no edge), what the declaration writes
    local got
    got="$( xRows "$2" )"
    if [ "$got" = "$3" ]; then
        ok "$1 $2(): $4 -> [${got:-no edge}]"
    else
        no "$1 $2(): $4 -> [${got:-no edge}], want [${3:-no edge}]"
    fi
}
"$BIN" "$XFIX" --no-cache --pin-census="$TMP/xcensus.tsv" >/dev/null 2>&1
xSymLines(){   # the census S-row lines of every symbol named $2 in file $1, sorted; empty when none
    awk -F '\t' -v id="$1::$2#" '$1 == "S" && index( $2, id ) == 1 { print $4 }' "$TMP/xcensus.tsv" 2>/dev/null | sort -n | tr '\n' ' ' | sed 's/ $//'
}
# presence guard: the census ran and indexed every probed caller, or the symbol-absence arms below prove nothing
xmiss=0
for want in nextSeed pickOne pickTwo pickCall pickIndex pickQualified pickTemplate pickProduct pickLiteral prototypes; do
    [ -n "$( xSymLines app/vexing.cpp "$want" )" ] || { no "presence guard: vexingfix caller $want has no census S row"; xmiss=1; }
done
[ "$xmiss" = 0 ] && ok "presence: the vexingfix census lists all ten callers"

# ── 52) THE DEFECT: `Widget w( seed ); w.pick( 1 )` pins to Widget::pick. (52c) is the same local with a LITERAL argument,
#        which never parsed as a function and always narrowed — the only difference between the two is the argument. ──
expectX "(52)" pickOne "Widget::pick@lib/widget.h:1" "Widget w( seed )"
expectX "(52c)" pickLiteral "Widget::pick@lib/widget.h:1" "Widget w( 8 )"
# ── 53) two plain-name arguments. ───────────────────────────────────────────────────────────────────────────────────────
expectX "(53)" pickTwo "Widget::pick@lib/widget.h:1" "Widget w( a, b )"
# ── 54) a CALL argument, `nextSeed()` — the grammar reads it as a parameter of type nextSeed returning a function. ────────
expectX "(54)" pickCall "Widget::pick@lib/widget.h:1" "Widget w( nextSeed() )"
# ── 55) a SUBSCRIPT argument, `seeds[ 0 ]` — read as an array parameter. ──────────────────────────────────────────────────
expectX "(55)" pickIndex "Widget::pick@lib/widget.h:1" "Widget w( seeds[ 0 ] )"
# ── 56) a namespace-qualified written type keeps its narrow (arm 22's rule) once the declaration is a local again. ────────
expectX "(56)" pickQualified "Shelf::pick@lib/widget.h:3" "store::Shelf s( seed )"
# ── 57) EXTRACTION: none of those declarations mints a function symbol — including the template-id one `Box<> b( seed )`
#        (`IRBuilder<> Builder(Rem)`'s own shape), whose narrow waits on the template-id receiver type. ────────────────────
for xs in "w 2 3 4 5" "s 6" "b 7"; do
    set -- $xs
    xname="$1"; shift
    xgot=" $( xSymLines app/vexing.cpp "$xname" ) "
    for xline in "$@"; do
        case "$xgot" in
            *" $xline "*) no "(57) vexing.cpp:$xline declares a local '$xname', yet it is indexed as a function symbol" ;;
            *)            ok "(57) vexing.cpp:$xline local '$xname' mints no symbol" ;;
        esac
    done
done
# ── 58) the mechanism: the census names Rule 2 (receiver-rule, flags r) for pickOne's site. ──────────────────────────────
xmech="$( awk -F '\t' '$1 == "C" && $6 ~ /^app\/vexing\.cpp::pickOne#/ && $7 == "pick" { print $2 "/" $5 }' "$TMP/xcensus.tsv" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//' )"
[ "$xmech" = "receiver-rule/r" ] \
    && ok "(58) pickOne's pick site is decided by receiver-rule/r (Rule 2)" \
    || no "(58) pickOne's pick site mech/flags=[${xmech:-NO-CENSUS-ROW}], want [receiver-rule/r]"
# ── 59) PROTOTYPE CONTROLS: a body-local declarator carrying anything a variable cannot write stays a function symbol —
#        a void return, a primitive or const-qualified or pointer or NAMED parameter, empty parentheses (a function by the
#        language's own rule), `extern`, and the misread class body's trailing `const` / `override`. RED on a naive fix
#        that refuses every body-local declarator (observed, see the commit). ─────────────────────────────────────────────
for xp in "helperVoid 12" "helperPrim 13" "helperNamed 14" "helperPtr 15" "helperNone 16" "helperExtern 17" "helperConst 18"; do
    set -- $xp
    [ "$( xSymLines app/vexing.cpp "$1" )" = "$2" ] \
        && ok "(59) vexing.cpp:$2 prototype '$1' stays a function symbol" \
        || no "(59) vexing.cpp:$2 prototype '$1' -> S lines [$( xSymLines app/vexing.cpp "$1" )], want [$2]"
done
for xp in "count 5" "copy 6"; do
    set -- $xp
    [ "$( xSymLines app/misparse.h "$1" )" = "$2" ] \
        && ok "(59) misparse.h:$2 member declaration '$1' stays a function symbol" \
        || no "(59) misparse.h:$2 member declaration '$1' -> S lines [$( xSymLines app/misparse.h "$1" )], want [$2]"
done
# ── 60) STATED FLOOR, pinned so it stays a decision: `Widget w( a * b )` parses as a POINTER parameter `a* b`, which a
#        prototype writes too, so it is still a function symbol and its call still declines. If this arm goes red, the floor
#        moved: rewrite it to assert the fixed behaviour, never delete it. ──────────────────────────────────────────────────
case " $( xSymLines app/vexing.cpp w ) " in
    *" 8 "*) ok "(60) floor: vexing.cpp:8 'Widget w( a * b )' is still a function symbol" ;;
    *)       no "(60) floor moved: no symbol named w at vexing.cpp:8 (lines [$( xSymLines app/vexing.cpp w )])" ;;
esac
expectX "(60)" pickProduct "" "floor: Widget w( a * b )"
# ── 60d) determinism + cache transparency on the vexing fixture: the dropped symbol must not come back warm. ────────────────
"$BIN" "$XFIX" --no-cache >"$TMP/x1" 2>/dev/null
"$BIN" "$XFIX" --no-cache >"$TMP/x2" 2>/dev/null
rm -f "$TMP/xc"
"$BIN" "$XFIX" --cache="$TMP/xc" >/dev/null 2>&1
"$BIN" "$XFIX" --cache="$TMP/xc" >"$TMP/xwarm" 2>/dev/null
if [ -s "$TMP/x1" ] && cmp -s "$TMP/x1" "$TMP/x2" && cmp -s "$TMP/x1" "$TMP/xwarm"; then
    ok "(60d) vexingfix map byte-identical: cold, cold again, and warm"
else
    no "(60d) vexingfix map differs across runs or warm vs cold"; diff "$TMP/x1" "$TMP/xwarm" | head -6
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
