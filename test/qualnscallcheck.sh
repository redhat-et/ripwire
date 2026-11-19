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
#                                                                                  (guard: graph.h callerScopeDeclares)
#             a using-declaration of the name in ANOTHER function's body            → still the split (not in force there)
#             an alias `namespace late = …;` declared AFTER the call                → still the split (not yet in force)
#             an included header's `namespace q { using rw::hashutil::fnv1a64; }`  → still the split: no C++ Namespace row is
#                                     recorded, so a header row's namespace path is not read (guard: cppScopeNamedAt fileScope)
#             mix( v ) — ADL through an argument of class type rw::hashutil::Val    → unchanged (ADL is not modelled; the base row)
#             Klass::make() — a class-static call, scope is a class                 → Klass's only, unchanged
#             Holder<int>::make() — a template-qualified call                       → Holder's, unchanged
#             CALL_FNV( s ) — a macro that expands to ::rw::hashutil::fnv1a64        → the macro row, unchanged
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
neg fx "$U" fnv1a64 40 "$AF"                             # the caller's own scope defines the name (callerScopeDeclares)
neg fx src/nsmore.cpp fnv1a64 4 "$AF $HF" split          # a header's namespace-scope using (fileScope guard)
neg fx "$U" make 17 "$A::Klass::make" qualified          # class-static
neg fx "$U" make 18 "$A::Holder::make" qualified         # template-qualified
neg fx "$U" mix 16 "$A::rw::mix"                         # ADL is not modelled: the base row
neg fx "$U" CALL_FNV 19 "$A::CALL_FNV"                   # the macro call itself

if [ "$seen" -eq 13 ]; then ok "the 13 negative arms read $seen rows (premise: none vacuous)"; else no "the 13 negative arms read $seen rows (want 13, one each)"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
