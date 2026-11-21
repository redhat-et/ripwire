#!/usr/bin/env bash
# qualnscallcheck.sh — QUAL-NS-CALL-BIND: a C++ call written with a namespace qualifier binds the namespace the qualifier names.
#
# THE BUG (GE5, 2026-11-19). ripwire's own `hashutil::fnv1a64( … )` calls all bound arch.h's same-named `rw::fnv1a64`. A call's
# qualifier is its IMMEDIATE segment (ingest's H4 re-split: `rw::hashutil::f` arrives as "hashutil"), but the canonical tier keyed a
# definition by its scope's WRITTEN text, and the C++17 nested namespace `namespace rw::hashutil { … }` writes "rw::hashutil". The
# key "hashutil::fnv1a64" missed, the call fell to the bare-name ladder, and Rule 3 picked the namesake an included file defines.
# THE FIX. resolve.h indexCanonicalScope keys a C-family `::` scope by its last segment too; graph.h keys a call by the scope a
# namespace alias (`namespace h = rw::hashutil;`) or a using-declaration (`using rw::hashutil::fnv1a64;`) in force at the call
# names (receiverevidence.h CallResultTypes::cppScopeNamedAt).
#
# Fixture (written at test time, no committed tree a whole-repo run would index): src/hashutil.h `namespace rw::hashutil` with
# fnv1a64, `namespace detail { mixer }`, `inline namespace v2 { widen }`, and an out-of-line nested class `struct Box::Leaf`;
# src/arch.h `namespace rw` with a SAME-SIGNATURE decoy of each (arity cannot tell them apart). Rows are read from --pin-census.
#   POSITIVE  hashutil::fnv1a64( s ) / rw::hashutil:: / ::rw::hashutil::          → hashutil.h only (base: a split with arch.h's)
#             h::fnv1a64 under `namespace h = hashutil;` (same namespace)          → hashutil.h only (base: split)
#             hu::fnv1a64 under `namespace hu = rw::hashutil;` (another namespace) → hashutil.h only (base: split)
#             fnv1a64( s ) under a block-scope `using rw::hashutil::fnv1a64;`       → hashutil.h only (base: split)
#             Leaf::grow() — the out-of-line nested class `struct Box::Leaf`       → hashutil.h's (base: split with arch.h's Leaf-less grow)
#             rw::fnv1a64( s ) itself calls hashutil::fnv1a64( s )                 → hashutil.h (base: no edge, the "recursion" was a namesake)
#             fnv1a64( s ) under an included header's FILE-scope `using rw::hashutil::fnv1a64;` → hashutil.h only (base: split)
#     NEGATIVE (each counted; a build with the named guard removed turns its arm red — the lane's guard-off proof)
#             fnv1a64( s ) / rw::fnv1a64( s ) in namespace rw                      → arch.h only, unchanged
#             hashutil::detail::mixer( x ) (classic nesting already keyed)          → hashutil.h only, unchanged
#             hashutil::widen( x ) — the inline namespace v2 elided                 → still the split (inline-ness is not recorded: card)
#             fnv1a64( s ) under `using namespace rw::hashutil;` (a directive)      → still the split
#             fnv1a64( s ) in namespace rw, whose own scope defines fnv1a64, under `using hashutil::fnv1a64;` → arch.h's
#                                                                                  (guard: graph.h canonicalCallQualifier's caller-scope check)
#             a using-declaration of the name in ANOTHER function's body            → still the split (not in force there)
#             an alias `namespace late = …;` declared AFTER the call                → still the split (not yet in force)
#             an included header's `namespace q { using rw::hashutil::fnv1a64; }`  → still the split: no C++ Namespace row is
#                                     recorded, so a header row's namespace path is not read (guard: cppScopeNamedAt fileScope)
#             Klass::make() — a class-static call, scope is a class                 → Klass's only, unchanged
#             Holder<int>::make() — a template-qualified call                       → Holder's, unchanged
#     BASE PINS (no change to the new code can turn these red — the name is neither aliased nor using-declared, so
#     cppScopeNamedAt returns at its gate; or `b.var != name` already rejects a directive row): mix( v ) by ADL (not
#     modelled), CALL_FNV( s ) (the macro row), the using-directive arm. KNOWN-GAP PIN (fails on an IMPROVEMENT, not a
#     regression): hashutil::widen with the inline namespace elided (card CPP-INLINE-NS).
# Fix round 1 (review F1-F5), fixture fx2 (src/a.h alpha::util + beta + gamma::h, src/rw.h rw::g, file-scope `using alpha::util::g;`
# and `namespace h = alpha::util;`):
#   POSITIVE  glob() at global scope: g( x ) under the file-scope using → alpha::util::g (base: a split)
#             Value::typed's dependent Traits<T>::fieldType() → the primary AND both out-of-line specializations (F4: the base
#             had the primary alone, the first lane head the specializations alone — the S6-C locality tie-break dropped the
#             primary, whose nested-class scope text shares less with the caller)
#   NEGATIVE  F1 rw::S::m / rw::inner::c / third::c2 (a namespace-scope DECLARATION third::g): g( x ) under the file-scope using,
#             but C++ lookup may find rw::g / third::g first → the base split (guard: callerScopesMayDeclare)
#             F2 gamma::h::f( x ) and T::m's h::k( x ) (a nested class `h`) beside the alias `h` → the base's own scope
#             (guard: canonicalCallQualifier's scopeHoldsName check)
#             F3 lam(): `auto g = []( int y ) { … }; g( x );` → no row, as base (guard: the caller's declared-local veto)
#             w.g( x ) — a member call on a using-declared name → W::g (guard: the isMemberCallRef early return)
#             both(): `using alpha::util::g; using beta::g;` → the base split (guard: cppScopeNamedAt's agree)
#             Rust b::Bar::make() / a::inner::Bar::make() → each its own impl's, unchanged (the transitiveIncludes language gate on
#             the last-segment key: REPORT-ONLY — no Rust scope text holds `::` today, an impl's scope is its last segment, so
#             the gate is defensive and this arm cannot go red)
#   KNOWN FLOOR viaAlias(): h::f( x ) at global scope under the alias, beside gamma::h::f → gamma's, as base (truth alpha::util::f;
#             the one-segment Reference cannot tell `h::f` from `gamma::h::f`, so the base reading stands). The alias's
#             !bindsWithoutTarget filter has NO arm: while the C++ family is off a target-less TypeAlias row carries no span,
#             so it is never a scope row (ingest_binds.h captureShadowDecl) — the filter is for the family-on path.
# Fix round 2 (CodeRabbit on #717), fixture fx3 (src/a.h aa/bb/cc/other + C++17 `namespace real2::h`, src/hdr.h a file-scope
# `namespace hh = cc;`, src/u.cpp a file-scope `namespace h = aa;` + `using aa::g;`, src/v.cpp a file-scope `namespace h = other;`):
#   POSITIVE  (red on 4b1f4516e: each was the split, cppScopeNamedAt folded every enclosing row and the disagreement hedged)
#             a block-scope `namespace h = bb;` over the file-scope `h = aa`              → bb::f (the innermost alias hides the outer)
#             a nested block's `namespace h = cc;` inside a block's `h = bb`              → cc::f
#             a block-scope `namespace hh = bb;` over an included header's `hh = cc`      → bb::g (a header row joins only file scope)
#             a block-scope `using bb::g;` over the file-scope `using aa::g;`             → bb::g
#   NEGATIVE  h::f( x ) beside those bodies, under the file-scope alias alone             → aa::f (base bin 5df5a26be: the split)
#             hh::g( x ) under the header's file-scope alias alone                         → cc::g (base bin 5df5a26be: the split)
#             `using aa::f; using bb::f;` in ONE block (an overload set)                   → the split (guard: rows of the innermost
#                                     scope still fold, a disagreement hedges; a last-row-wins build turns it red)
#             CodeRabbit thread 1: real2::h::k( x ) under `namespace h = other;`, real2::h a C++17 nested namespace → real2's
#                                     (guard: scopeHoldsName on the last-segment key; base bin 5df5a26be: the split with other::k)
#             h::g( x ) under `namespace h = other;`, no scope spelled h holding g         → other::g (base bin 5df5a26be: the split)
# The fix keys rows the base left split or bound to the namesake; it never turns a hedged row into a proven one without a
# declaration that names the scope (an unknown qualifier keeps the base reading).
# Every negative arm counts the rows it read and the batch fails when they read none (a vacuous arm proves nothing).
#
# Usage: bash test/qualnscallcheck.sh [BIN]     (default build/ripwire; exits non-zero on any failure)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "FAIL: no binary at $BIN"; exit 1; }
echo "qualnscallcheck: $( "$BIN" --version 2>/dev/null )"   # status: banner only; every arm below checks its own run

# ── fixture ──
FX="$TMP/fx"; mkdir -p "$FX/src"
cat >"$FX/src/hashutil.h" <<'EOF'
#pragma once
#include <string_view>
namespace rw::hashutil
{
inline unsigned long fnv1a64( std::string_view s, unsigned long seed = 1 ) { return s.size() + seed; }
namespace detail
{
inline unsigned long mixer( unsigned long x ) { return x * 3; }
}
inline namespace v2
{
inline unsigned long widen( unsigned long x ) { return x + 7; }
}
struct Val { unsigned long v = 0; };
inline unsigned long mix( Val v ) { return v.v + 1; }
struct Box { struct Leaf; };
struct Box::Leaf { static unsigned long grow( unsigned long x ) { return x + 2; } };
}
EOF
cat >"$FX/src/arch.h" <<'EOF'
#pragma once
#include "hashutil.h"
namespace rw
{
inline unsigned long fnv1a64( std::string_view s, unsigned long seed = 2 ) { return hashutil::fnv1a64( s, seed ); }
inline unsigned long mixer( unsigned long x ) { return x * 5; }
inline unsigned long widen( unsigned long x ) { return x + 9; }
inline unsigned long mix( unsigned long v ) { return v + 3; }
inline unsigned long grow( unsigned long x ) { return x + 4; }
struct Klass { static int make() { return 1; } };
template <class T> struct Holder { static T make() { return T(); } };
}
namespace other
{
inline int make() { return 2; }
}
#define CALL_FNV( s ) ::rw::hashutil::fnv1a64( s )
EOF
cat >"$FX/src/users.cpp" <<'EOF'
#include "arch.h"
namespace rw
{
unsigned long callQualified( std::string_view s ) { return hashutil::fnv1a64( s ); }
unsigned long callFullyQualified( std::string_view s ) { return rw::hashutil::fnv1a64( s ); }
unsigned long callRootQualified( std::string_view s ) { return ::rw::hashutil::fnv1a64( s ); }
unsigned long callArch( std::string_view s ) { return fnv1a64( s ); }
unsigned long callArchQualified( std::string_view s ) { return rw::fnv1a64( s ); }
unsigned long callNested( unsigned long x ) { return hashutil::detail::mixer( x ); }
unsigned long callInlineElided( unsigned long x ) { return hashutil::widen( x ); }
unsigned long callLateAlias( std::string_view s ) { return late::fnv1a64( s ); }
namespace late = hashutil;
namespace h = hashutil;
unsigned long callAlias( std::string_view s ) { return h::fnv1a64( s ); }
unsigned long callLeaf( unsigned long x ) { return hashutil::Box::Leaf::grow( x ); }
unsigned long callAdl( hashutil::Val v ) { return mix( v ); }
int callStatic() { return Klass::make(); }
int callTemplate() { return Holder<int>::make(); }
unsigned long callMacro( std::string_view s ) { return CALL_FNV( s ); }
}
namespace other
{
namespace hu = rw::hashutil;
unsigned long callAlias2( std::string_view s ) { return hu::fnv1a64( s ); }
unsigned long callUsingDecl( std::string_view s )
{
    using rw::hashutil::fnv1a64;
    return fnv1a64( s );
}
unsigned long callNoUsing( std::string_view s ) { return fnv1a64( s ); }
unsigned long callUsingDirective( std::string_view s )
{
    using namespace rw::hashutil;
    return fnv1a64( s );
}
}
namespace rw
{
using hashutil::fnv1a64;
unsigned long callOwnScope( std::string_view s ) { return fnv1a64( s ); }
}
EOF

cat >"$FX/src/fileuse.h" <<'EOF'
#pragma once
#include "arch.h"
using rw::hashutil::fnv1a64;
EOF
cat >"$FX/src/more.cpp" <<'EOF'
#include "fileuse.h"
unsigned long callHeaderUsing( std::string_view s ) { return fnv1a64( s ); }
EOF
cat >"$FX/src/nsuse.h" <<'EOF'
#pragma once
#include "arch.h"
namespace q
{
using rw::hashutil::fnv1a64;
}
EOF
cat >"$FX/src/nsmore.cpp" <<'EOF'
#include "nsuse.h"
namespace q
{
unsigned long callHeaderNsUsing( std::string_view s ) { return fnv1a64( s ); }
}
EOF

# census DIR → $TMP/<name>.census (rc checked: a failed run would make every arm below vacuous)
census(){ ( cd "$1" && "$BIN" . --no-cache --pin-census="$TMP/$2.census" >/dev/null 2>"$TMP/$2.err" ); local rc=$?
          [ "$rc" -eq 0 ] || { no "$2: the --pin-census run failed (rc=$rc)"; return 1; }; return 0; }
# row NAME CALLER_FILE CALLEE LINE → "mech<TAB>targets" of the one C row (empty when none); the row count goes to $TMP/rows
row(){ awk -F'\t' -v f="$2" -v c="$3" -v l="$4" '$1=="C" && index($6,f"::")==1 && $7==c && $9==l { print $2"\t"$8; n++ } END { print n+0 > "'"$TMP"'/rows" }' "$TMP/$1.census"; }
targets(){ printf '%s' "$1" | cut -f2 | tr '|' '\n' | sed 's/#[0-9]*$//' | sort | tr '\n' ' ' | sed 's/ $//'; }
seen=0   # rows the negative arms read
# expect NAME FILE CALLEE LINE WANT_TARGETS [MECH] — the site's one row has exactly these targets (and this mechanism)
expect(){ local r; r=$( row "$1" "$2" "$3" "$4" ); local n; n=$( cat "$TMP/rows" ); local t; t=$( targets "$r" )
          if [ "$n" = 1 ] && [ "$t" = "$5" ] && { [ -z "${6:-}" ] || [ "$( printf '%s' "$r" | cut -f1 )" = "$6" ]; }; then ok "$1 $2:$4 $3 -> $5${6:+ ($6)}"
          else no "$1 $2:$4 $3: want $5${6:+ ($6)}, got rows=$n [$r]"; fi; }
neg(){ expect "$@"; seen=$(( seen + $( cat "$TMP/rows" ) )); }

census "$FX" fx || exit 1
H=src/hashutil.h; A=src/arch.h; U=src/users.cpp
HF="$H::rw::hashutil::fnv1a64"; AF="$A::rw::fnv1a64"

echo "── the qualifier names the namespace (base: a split with arch.h's namesake) ──"
expect fx "$U" fnv1a64 4 "$HF" qualified
expect fx "$U" fnv1a64 5 "$HF" qualified
expect fx "$U" fnv1a64 6 "$HF" qualified
expect fx "$A" fnv1a64 5 "$HF" qualified                 # rw::fnv1a64's own body (base: no row)
expect fx "$U" grow 15 "$H::Box::Leaf::grow" qualified   # the out-of-line nested class struct Box::Leaf

echo "── a namespace alias or a using-declaration in force names it ──"
expect fx "$U" fnv1a64 14 "$HF" qualified                # namespace h = hashutil;
expect fx "$U" fnv1a64 24 "$HF" qualified                # namespace hu = rw::hashutil; (in namespace other)
expect fx "$U" fnv1a64 28 "$HF" qualified                # block-scope using rw::hashutil::fnv1a64;
expect fx src/more.cpp fnv1a64 2 "$HF" qualified         # an included header's file-scope using-declaration

echo "── unchanged: nothing names another scope, or the declaration is not proved in force ──"
neg fx "$U" fnv1a64 7 "$AF"                              # bare, in namespace rw
neg fx "$U" fnv1a64 8 "$AF" qualified                    # rw::fnv1a64
neg fx "$U" mixer 9 "$H::detail::mixer" qualified        # classic nesting (already keyed)
neg fx "$U" widen 10 "$A::rw::widen $H::v2::widen" split # inline namespace elided: not recorded (card)
neg fx "$U" fnv1a64 11 "$AF $HF" split                   # alias declared after the call
neg fx "$U" fnv1a64 30 "$AF $HF" split                   # the using-declaration is in another function's body
neg fx "$U" fnv1a64 34 "$AF $HF" split                   # using-directive
neg fx "$U" fnv1a64 40 "$AF"                             # the caller's own scope defines the name (caller-scope check)
neg fx src/nsmore.cpp fnv1a64 4 "$AF $HF" split          # a header's namespace-scope using (fileScope guard)
neg fx "$U" make 17 "$A::Klass::make" qualified          # class-static
neg fx "$U" make 18 "$A::Holder::make" qualified         # template-qualified
neg fx "$U" mix 16 "$A::rw::mix"                         # BASE PIN: ADL is not modelled
neg fx "$U" CALL_FNV 19 "$A::CALL_FNV"                   # BASE PIN: the macro call itself

if [ "$seen" -eq 13 ]; then ok "the 13 negative arms read $seen rows (premise: none vacuous)"; else no "the 13 negative arms read $seen rows (want 13, one each)"; fi

# ── fix round 1 (review F1-F5): fixture fx2 ──
F2="$TMP/fx2"; mkdir -p "$F2/src"
cat >"$F2/src/a.h" <<'EOF'
#pragma once
namespace alpha::util
{
inline int g( int x ) { return x + 2; }
inline int f( int x ) { return x + 1; }
inline int k( int x ) { return x + 3; }
}
namespace beta
{
inline int g( long x ) { return int( x ) + 5; }
}
namespace gamma
{
namespace h
{
inline int f( int x ) { return x + 4; }
}
}
EOF
cat >"$F2/src/rw.h" <<'EOF'
#pragma once
namespace rw
{
inline int g( int x ) { return x + 9; }
}
EOF
cat >"$F2/src/users.cpp" <<'EOF'
#include "a.h"
#include "rw.h"
using alpha::util::g;
namespace h = alpha::util;
namespace rw
{
struct S
{
    int m( int x ) { return g( x ); }
};
namespace inner
{
int c( int x ) { return g( x ); }
}
}
int glob( int x ) { return g( x ); }
int viaGamma( int x ) { return gamma::h::f( x ); }
struct T
{
    struct h { static int k( int x ) { return x; } };
    int m( int x ) { return h::k( x ); }
};
int lam( int x )
{
    auto g = []( int y ) { return y; };
    return g( x );
}
struct W { int g( int x ) { return x; } };
int viaMember( W& w, int x ) { return w.g( x ); }
namespace third
{
int g( int x );
int c2( int x ) { return g( x ); }
}
int viaAlias( int x ) { return h::f( x ); }
EOF
cat >"$F2/src/both.cpp" <<'EOF'
#include "a.h"
using alpha::util::g;
using beta::g;
int both( int x ) { return g( x ); }
EOF
cat >"$F2/src/traits.h" <<'EOF'
#pragma once
enum class FieldType { Bool, Str };
class Value
{
public:
    template <typename T> FieldType typed() const { return Traits<T>::fieldType(); }
private:
    template <typename T> class Traits
    {
    public:
        static FieldType fieldType() { return T::fieldType(); }
    };
};
template <> class Value::Traits<bool>
{
public:
    static FieldType fieldType() { return FieldType::Bool; }
};
template <> class Value::Traits<char>
{
public:
    static FieldType fieldType() { return FieldType::Str; }
};
EOF
printf '[package]\nname = "fxrs"\nversion = "0.1.0"\n' >"$F2/Cargo.toml"
cat >"$F2/src/lib.rs" <<'EOF'
pub mod a {
    pub mod inner {
        pub struct Bar;
    }
}
pub mod b {
    pub struct Bar;
    impl Bar {
        pub fn make() -> u32 { 2 }
    }
}
impl a::inner::Bar {
    pub fn make() -> u32 { 1 }
}
pub fn call_b() -> u32 { b::Bar::make() }
pub fn call_inner() -> u32 { a::inner::Bar::make() }
EOF
census "$F2" fx2 || exit 1
U2=src/users.cpp; AG="src/a.h::alpha::util::g"; BG="src/a.h::beta::g"; RG="src/rw.h::rw::g"
# none NAME FILE CALLER CALLEE LINE — the caller exists (its S row: the premise) and the site has no C row
none(){ local s; s=$( awk -F'\t' -v id="$2::$3" '$1=="S" && index($2,id"#")==1' "$TMP/$1.census" | wc -l | tr -d ' ' ); row "$1" "$2" "$4" "$5" >/dev/null
        local n; n=$( cat "$TMP/rows" )
        if [ "$s" = 1 ] && [ "$n" = 0 ]; then ok "$1 $2:$5 $4 -> no row (caller $3 seen)"; else no "$1 $2:$5 $4: want no row beside caller $3, got caller rows=$s call rows=$n"; fi
        seen2=$(( seen2 + s )); }
seen2=0
neg2(){ expect "$@"; seen2=$(( seen2 + $( cat "$TMP/rows" ) )); }

echo "── round 1 positive: the using-declaration is the first declaration C++ lookup finds; a template family keeps its primary ──"
expect fx2 "$U2" g 16 "$AG" qualified                                  # glob(): global caller, file-scope using
expect fx2 src/traits.h fieldType 6 "src/traits.h::Traits::fieldType src/traits.h::Value::Traits<bool>::fieldType src/traits.h::Value::Traits<char>::fieldType" split   # F4

echo "── round 1 negative: something C++ lookup may find first keeps the base reading ──"
neg2 fx2 "$U2" g 9 "$AG $BG $RG" split                                 # F1 rw::S::m: the class chain ends in namespace rw
neg2 fx2 "$U2" g 13 "$AG $BG $RG" split                                # F1 rw::inner::c: the namespace chain is not recorded
neg2 fx2 "$U2" g 33 "$AG $BG $RG" split                                # F1 third::c2 beside the declaration third::g
neg2 fx2 "$U2" f 17 "src/a.h::h::f" qualified                          # F2 gamma::h::f beside the alias h
neg2 fx2 "$U2" k 21 "$U2::h::k" qualified                              # F2 a nested class h beside the alias h
none fx2 "$U2" lam g 26                                                # F3 a local lambda g
neg2 fx2 "$U2" g 29 "$U2::W::g" receiver-rule                          # a member call on a using-declared name
neg2 fx2 src/both.cpp g 4 "$AG $BG" split                              # two using-declarations name different scopes
neg2 fx2 src/lib.rs make 15 "src/lib.rs::Bar::make"                    # REPORT-ONLY Rust: b::Bar's impl
neg2 fx2 src/lib.rs make 16 "src/lib.rs::Bar::make"                    # REPORT-ONLY Rust: a::inner::Bar's impl
neg2 fx2 "$U2" f 35 "src/a.h::h::f" qualified                          # KNOWN FLOOR: h::f under the alias beside gamma::h::f
if [ "$seen2" -eq 11 ]; then ok "the 11 round-1 negative arms read $seen2 rows (premise: none vacuous)"; else no "the 11 round-1 negative arms read $seen2 rows (want 11, one each)"; fi

# ── fix round 2 (CodeRabbit on #717): fixture fx3 ──
F3="$TMP/fx3"; mkdir -p "$F3/src"
cat >"$F3/src/a.h" <<'EOF'
#pragma once
namespace aa
{
inline int f( int x ) { return x + 1; }
inline int g( int x ) { return x + 2; }
}
namespace bb
{
inline int f( int x ) { return x + 3; }
inline int g( int x ) { return x + 4; }
}
namespace cc
{
inline int f( int x ) { return x + 5; }
inline int g( int x ) { return x + 6; }
}
namespace other
{
inline int g( int x ) { return x + 7; }
inline int k( int x ) { return x + 8; }
}
namespace real2::h
{
inline int k( int x ) { return x + 9; }
}
EOF
cat >"$F3/src/hdr.h" <<'EOF'
#pragma once
#include "a.h"
namespace hh = cc;
EOF
cat >"$F3/src/u.cpp" <<'EOF'
#include "hdr.h"
namespace h = aa;
int blockAlias( int x )
{
    namespace h = bb;
    return h::f( x );
}
int fileAlias( int x ) { return h::f( x ); }
int nestedBlock( int x )
{
    namespace h = bb;
    {
        namespace h = cc;
        return h::f( x );
    }
}
int overHeader( int x )
{
    namespace hh = bb;
    return hh::g( x );
}
int viaHeader( int x ) { return hh::g( x ); }
using aa::g;
int blockUsing( int x )
{
    using bb::g;
    return g( x );
}
int sameBlock( int x )
{
    using aa::f;
    using bb::f;
    return f( x );
}
EOF
cat >"$F3/src/v.cpp" <<'EOF'
#include "a.h"
namespace h = other;
int nested17( int x ) { return real2::h::k( x ); }
int plain( int x ) { return h::g( x ); }
EOF
census "$F3" fx3 || exit 1
U3=src/u.cpp; X3=src/a.h
seen3=0
neg3(){ expect "$@"; seen3=$(( seen3 + $( cat "$TMP/rows" ) )); }

echo "── round 2 positive: the innermost scope holding an alias or using-declaration decides ──"
expect fx3 "$U3" f 6 "$X3::bb::f" qualified                            # block-scope h = bb over the file-scope h = aa
expect fx3 "$U3" f 14 "$X3::cc::f" qualified                           # a nested block's h = cc inside a block's h = bb
expect fx3 "$U3" g 20 "$X3::bb::g" qualified                           # block-scope hh = bb over the header's hh = cc
expect fx3 "$U3" g 27 "$X3::bb::g" qualified                           # block-scope using bb::g over the file-scope using aa::g

echo "── round 2 negative: an outer row alone still decides; one scope's disagreeing rows still hedge ──"
neg3 fx3 "$U3" f 8 "$X3::aa::f" qualified                              # the file-scope alias alone
neg3 fx3 "$U3" g 22 "$X3::cc::g" qualified                             # the header's file-scope alias alone
neg3 fx3 "$U3" f 33 "$X3::aa::f $X3::bb::f $X3::cc::f" split           # two using-declarations in one block
neg3 fx3 src/v.cpp k 3 "$X3::real2::h::k" qualified                    # thread 1: real2::h::k beside the alias h = other
neg3 fx3 src/v.cpp g 4 "$X3::other::g" qualified                       # thread 1: h::g, no scope spelled h holds g
if [ "$seen3" -eq 5 ]; then ok "the 5 round-2 negative arms read $seen3 rows (premise: none vacuous)"; else no "the 5 round-2 negative arms read $seen3 rows (want 5, one each)"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
