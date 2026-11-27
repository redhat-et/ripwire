#!/usr/bin/env bash
# cppextqualcheck.sh — CPP-EXTQUAL-VETO: include evidence never binds an in-tree namesake for a C++ call qualified by a name the
# tree never defines, so Rule 3 can read the C/C++ include-root edges (resolve.h kCallNarrowReadsCIncludeRoots) without the
# wrong unhedged binds the coupled C-ROOT-INCLUDE build drew on Envoy (`absl::Span(…)` → envoy/tracing's `class Span`,
# `fmt::ptr(…)` → OptRef::ptr, `std::format(…)` → a `std::formatter<…>` specialization's `format`).
#
# The fixture is written at runtime. Every answer is read from --callees=<caller>.
#   V arms  veto (a), graph.h CppQualifierScopes: a qualifier the tree never defines (`ext::make(3)`) takes Rule 3's pick
#           hedged via="name", never unhedged — through a root include (V1) and through the includer's own directory (V2,
#           where main 2047f95f bound it unhedged). A qualified prototype `int ext::other(int);` (bodyless: a misparse spells
#           this shape) and an explicit specialization `namespace ext { template <> struct Box<int> {…}; }` define nothing in
#           ext, so V1/V2 stay hedged beside them.
#   S arm   a `std::f` call names a member of namespace std itself (graph.h keepStdQualifiedCandidates): the `format` member of a
#           `template <> struct std::formatter<Status, char>` the caller includes is no answer to `std::format(…)` (main bound it).
#   T arms  twins that must still bind, unhedged: a namespace the tree defines through a class's member record (`ns::Widget()`,
#           T1) and a type alias of an in-tree class template (`using Keys = Single<int>; Keys::get()`, T2), each reached through
#           a root include, where main declined both.
#   D arms  CPP-FREE-VS-MEMBER (graph.h FreeDeclReach): a bare call binds the free function its translation unit declares — the
#           included prototype's body (D1, D6) — and decides nothing when two are declared (D2), none is (D3), a member in the
#           caller's cone hides it (D4), the caller may be a macro-made member (D5), its own scope holds a namesake (D7) or a
#           candidate is a friend scoped by its class (D9); D8, a member caller's class namespace, is a GAP line.
# The member-call veto (b) — Rule 2's class identity and a member call's Rule 3 tier keep the includer-directory closure — is
# pinned by arm M1 below; the bare-call twin is test/crootincludecheck.sh R9.
#
# Usage:  test/cppextqualcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire test/cppextqualcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "cppextqualcheck: BIN=$BIN TMP=$TMP"

FIX="$TMP/fix"
mk(){ mkdir -p "$( dirname "$FIX/$1" )"; printf '%s\n' "$2" > "$FIX/$1"; }
mk lib/util.h        '#pragma once
inline int make(int a) { return a + 1; }'
mk alt/util.h        '#pragma once
inline int make(int a) { return a + 2; }'
mk app/use_root.cc   '#include "lib/util.h"
int use_ext_root() { return ext::make(3); }'
mk dir/util.h        '#pragma once
inline int make(int a) { return a + 3; }'
mk dir/use_dir.cc    '#include "util.h"
int use_ext_dir() { return ext::make(3); }'
mk lib/proto.h       '#pragma once
int ext::other(int a);'
mk lib/box.h         '#pragma once
struct Part { int p; };
template <class T> struct Box { T v; };
namespace ext { template <> struct Box<int> { Part part_; }; }'
mk dir/fmt.h         '#pragma once
namespace std { template <> struct formatter<Status, char> { int format(int s, int c) const { return 0; } }; }'
mk alt/printer.h     '#pragma once
struct Printer { int format(int s) { return 1; } };'
mk dir/use_fmt.cc    '#include "fmt.h"
int use_fmt() { return std::format("x", 1); }'
mk lib/widget.h      '#pragma once
namespace ns { class Widget { public: Part part_; }; }'
mk alt/widget.h      '#pragma once
namespace other { class Widget { public: Part part_; }; }'
mk app/use_widget.cc '#include "lib/widget.h"
int use_widget() { auto w = ns::Widget(); return 0; }'
mk lib/single.h      '#pragma once
template <class T> class Single { public: static T& get() { static T t; return t; } };
using Keys = Single<int>;'
mk alt/getter.h      '#pragma once
struct Getter { static int get() { return 0; } };'
mk app/use_keys.cc   '#include "lib/single.h"
int use_keys() { Keys::get(); return 0; }'

callees(){ ( cd "$FIX" && "$BIN" . --no-cache --callees="$1" 2>/dev/null ) | sed 's/<!--[^>]*-->//g'; }
for f in use_ext_root use_ext_dir use_fmt use_widget use_keys; do callees "$f" > "$TMP/$f.xml"; done
head_of(){ grep -o '<callees schema="ripwire.callees/v1" of="[^"]*" defs="[0-9]*" count="[0-9]*"' "$TMP/$1.xml"; }
row(){ grep -o "<s t=\"$2\" n=\"$3\" p=\"$4\"[^>]*>" "$TMP/$1.xml"; }
show(){ head -c 700 "$TMP/$1.xml"; echo; }

if row use_ext_root fn make lib/util.h:2 | grep -q 'via="name"'; then
  ok "V1 ext::make(3) through a root include: lib/util.h's make is a via=\"name\" hedge (ext is no name the tree defines)"
else no "V1 ext::make(3) bound lib/util.h's make unhedged, or not at all"; show use_ext_root; fi
if row use_ext_dir fn make dir/util.h:2 | grep -q 'via="name"'; then
  ok "V2 ext::make(3) through the includer's own directory: dir/util.h's make is a via=\"name\" hedge (main bound it unhedged)"
else no "V2 ext::make(3) bound dir/util.h's make unhedged, or not at all"; show use_ext_dir; fi
if head_of use_fmt | grep -q 'count="0"' && ! grep -q 'n="format"' "$TMP/use_fmt.xml"; then
  ok "S std::format(...) never binds the format member of an included std::formatter<Status, char> specialization (main bound it)"
else no "S std::format(...) bound a std::formatter specialization's member"; show use_fmt; fi
if row use_widget cls Widget lib/widget.h:2 | grep -q . && ! row use_widget cls Widget lib/widget.h:2 | grep -q 'via=\|prov='; then
  ok "T1 ns::Widget() binds lib/widget.h's Widget unhedged: ns is a namespace the tree defines (a member record's lexical scope)"
else no "T1 ns::Widget() lost its unhedged bind"; show use_widget; fi
if row use_keys method Single::get lib/single.h:2 | grep -q . && ! row use_keys method Single::get lib/single.h:2 | grep -q 'via=\|prov='; then
  ok "T2 Keys::get() binds Single::get unhedged: Keys aliases an in-tree class template"
else no "T2 Keys::get() lost its unhedged bind"; show use_keys; fi

# ── EXTQUAL-FIX1 arms: one tree each, since the qualifier table is the whole tree's ──────────────────────────────────────────────
#   M1  a member call's Rule 3 reads the includer-directory closure: `s.getStream()` on a foreign-typed receiver gains no hedge
#       from a header only the include-root probe reaches (Envoy: `factory->isTerminalFilterByProto()` spread over 3 classes)
#   A5  Rule 3 never pins the `#else` stub of a preprocessor alternative over the real .c definition (htop Demangle_demangle)
#   A2  `using ext::make;` then a bare `make(3)`: the foreign using-declaration makes Rule 3's pick a hedge
#   V3  a tree with free functions only (no class, alias or namespace name) still reads `ext` foreign
#   F   a forward declaration `class External;` defines nothing: `External::make(3)` stays hedged
#   S2  `template <> struct std::formatter<Status, char>` written OUTSIDE namespace std: its format is no `std::format`
#   C   a chain of 4 aliases whose records arrive outer-first resolves (a fixpoint, not two passes): `A4::get()` binds
#   W   `using ExternalMap = vendor::Map;` beside an in-tree `Map`: the written target scope is foreign, so ExternalMap is too
#   GAP twins (printed, never failing; carded in the PR body): `using namespace ext;` (A2d), `ext::ns::make` with ns in-tree (A1),
#       a namespace alias of an in-tree namespace (N)
ARM="$TMP/arm"
mka(){ mkdir -p "$( dirname "$ARM/$1/$2" )"; printf '%s\n' "$3" > "$ARM/$1/$2"; }
callee_rows(){ ( cd "$ARM/$1" && "$BIN" . --no-cache --callees="$2" 2>/dev/null ) | sed 's/<!--[^>]*-->//g'; }
utilpair(){ mka "$1" lib/util.h '#pragma once
inline int make(int a) { return a + 1; }'; mka "$1" alt/util.h '#pragma once
inline int make(int a) { return a + 2; }'; }
hedged(){ grep -o "<s t=\"fn\" n=\"make\" p=\"$2\"[^>]*>" "$1" | grep -q 'via="name"'; }
unhedged(){ grep -o "<s t=\"fn\" n=\"make\" p=\"$2\"[^>]*>" "$1" | grep -q . && ! grep -o "<s t=\"fn\" n=\"make\" p=\"$2\"[^>]*>" "$1" | grep -q 'via=\|prov='; }

mka m1 lib/net/conn.h '#pragma once
class Conn { public: int getStream() { return 1; } int a_; };'
mka m1 alt/conn2.h '#pragma once
class Other { public: int getStream() { return 2; } int b_; };'
mka m1 app/use.cc '#include "lib/net/conn.h"
int use_vbf(grpc::Stub& s) { return s.getStream(); }'
callee_rows m1 use_vbf > "$TMP/m1.xml"
if ! grep -q 'n="Conn::getStream"' "$TMP/m1.xml"; then
  ok "M1 s.getStream() on a grpc::Stub& takes no Conn::getStream hedge from a header only the include root reaches"
else no "M1 a member call drew a hedge from the include-root closure"; head -c 700 "$TMP/m1.xml"; echo; fi

mka a5 generic/Dm.h '#pragma once
#ifdef HAVE_DM
char* Dm_demangle(const char* m);
#else
static inline char* Dm_demangle(const char* m) { (void)m; return 0; }
#endif'
mka a5 generic/Dm.c '#include "Dm.h"
char* Dm_demangle(const char* m) { return (char*)m; }'
mka a5 other/Dm2.c 'char* Dm_demangle(const char* m) { return 0; }'
mka a5 linux/use.c '#include "generic/Dm.h"
char* use_stub(const char* m) { return Dm_demangle(m); }'
callee_rows a5 use_stub > "$TMP/a5.xml"
stubrow=$( grep -o '<s t="fn" n="Dm_demangle" p="generic/Dm.h:5"[^>]*>' "$TMP/a5.xml" )
if [ -z "$stubrow" ] || echo "$stubrow" | grep -q 'via=\|prov='; then
  ok "A5 Dm_demangle(m) never binds the #else static inline stub alone over generic/Dm.c's definition"
else no "A5 Rule 3 pinned the preprocessor stub generic/Dm.h:5 unhedged"; head -c 700 "$TMP/a5.xml"; echo; fi

utilpair a2; mka a2 app/use.cc '#include "lib/util.h"
using ext::make;
int use_using() { return make(3); }'
mka a2 app/use2.cc '#include "lib/util.h"
using namespace ext;
int use_usingns() { return make(3); }'
callee_rows a2 use_using > "$TMP/a2.xml"; callee_rows a2 use_usingns > "$TMP/a2d.xml"
if hedged "$TMP/a2.xml" lib/util.h:2; then
  ok "A2 using ext::make; make(3): lib/util.h's make is a via=\"name\" hedge"
else no "A2 a bare call under a foreign using-declaration bound lib/util.h's make unhedged"; head -c 700 "$TMP/a2.xml"; echo; fi
if hedged "$TMP/a2d.xml" lib/util.h:2; then echo "  GAP   A2d using namespace ext; make(3): now hedged — the gap closed, make this arm a check"
else echo "  GAP   A2d using namespace ext; make(3): binds lib/util.h's make unhedged (a using-directive reaches no reference; carded)"; fi

utilpair v3; mka v3 app/use.cc '#include "lib/util.h"
int use_v3() { return ext::make(3); }'
callee_rows v3 use_v3 > "$TMP/v3.xml"
if hedged "$TMP/v3.xml" lib/util.h:2; then
  ok "V3 a functions-only tree: ext::make(3) is still a via=\"name\" hedge"
else no "V3 an empty qualifier-name table read ext as in-tree"; head -c 700 "$TMP/v3.xml"; echo; fi

utilpair f; mka f lib/fwd.h 'class External;
struct Part { int p; };'
mka f app/use.cc '#include "lib/util.h"
int use_fwdc() { return External::make(3); }'
callee_rows f use_fwdc > "$TMP/f.xml"
if hedged "$TMP/f.xml" lib/util.h:2; then
  ok "F class External; (a forward declaration) defines nothing: External::make(3) is a via=\"name\" hedge"
else no "F a forward-declared class counted as an in-tree qualifier"; head -c 700 "$TMP/f.xml"; echo; fi

mka s2 dir/fmt.h '#pragma once
template <> struct std::formatter<Status, char> { int format(int s, int c) const { return 0; } };'
mka s2 alt/printer.h '#pragma once
struct Printer { int format(int s) { return 1; } };'
mka s2 dir/use_fmt.cc '#include "fmt.h"
int use_fmt2() { return std::format("x", 1); }'
callee_rows s2 use_fmt2 > "$TMP/s2.xml"
if ! grep -q 'n="[^"]*format"' "$TMP/s2.xml"; then
  ok "S2 std::format(...) never binds the format of a std::formatter specialization written outside namespace std"
else no "S2 std::format(...) bound a qualified std::formatter specialization's member"; head -c 700 "$TMP/s2.xml"; echo; fi

mka c lib/single.h '#pragma once
using A4 = A3;
using A3 = A2;
using A2 = A1;
using A1 = Single<int>;
template <class T> class Single { public: static T& get() { static T t; return t; } };'
mka c alt/getter.h '#pragma once
struct Getter { static int get() { return 0; } };'
mka c app/use.cc '#include "lib/single.h"
int use_chain() { A4::get(); return 0; }'
callee_rows c use_chain > "$TMP/c.xml"
crow=$( grep -o '<s t="method" n="Single::get" p="lib/single.h:6"[^>]*>' "$TMP/c.xml" )
if [ -n "$crow" ] && ! echo "$crow" | grep -q 'via=\|prov='; then
  ok "C A4 -> A3 -> A2 -> A1 -> Single<int>, records outer-first: A4::get() binds Single::get unhedged"
else no "C a 4-alias chain read in outer-first order left A4 foreign"; head -c 700 "$TMP/c.xml"; echo; fi

mka w lib/map.h '#pragma once
struct Map { static int get() { return 1; } };
using ExternalMap = vendor::Map;'
mka w alt/getter.h '#pragma once
struct Getter { static int get() { return 0; } };'
mka w app/use.cc '#include "lib/map.h"
int use_w() { return ExternalMap::get(); }'
callee_rows w use_w > "$TMP/w.xml"
wrow=$( grep -o '<s t="method" n="Map::get" p="lib/map.h:2"[^>]*>' "$TMP/w.xml" )
if [ -z "$wrow" ] || echo "$wrow" | grep -q 'via='; then
  ok "W using ExternalMap = vendor::Map; ExternalMap::get() never binds the in-tree Map::get unhedged"
else no "W an alias of a foreign-scoped target counted as an in-tree qualifier"; head -c 700 "$TMP/w.xml"; echo; fi

utilpair a1; mka a1 lib/ns.h '#include "part.h"
namespace ns { class Holder { public: Part p_; }; }'
mka a1 lib/part.h 'struct Part { int p; };'
mka a1 app/use.cc '#include "lib/util.h"
#include "lib/ns.h"
int use_extns() { return ext::ns::make(3); }'
callee_rows a1 use_extns > "$TMP/a1.xml"
if hedged "$TMP/a1.xml" lib/util.h:2; then echo "  GAP   A1 ext::ns::make(3): now hedged — the gap closed, make this arm a check"
else echo "  GAP   A1 ext::ns::make(3): binds lib/util.h's make unhedged (the veto reads the immediate segment ns; carded)"; fi

mka n dir/util.h '#pragma once
namespace mine { inline int make(int a) { return a + 3; } }'
mka n alt/util.h '#pragma once
namespace theirs { inline int make(int a) { return a + 4; } }'
mka n dir/use.cc '#include "util.h"
namespace M = mine;
int use_alias() { return M::make(3); }'
callee_rows n use_alias > "$TMP/n.xml"
if unhedged "$TMP/n.xml" dir/util.h:2; then echo "  GAP   N namespace M = mine; M::make(3): now unhedged — the gap closed, make this arm a check"
else echo "  GAP   N namespace M = mine; M::make(3): a via=\"name\" hedge (no namespace-alias record reaches the table; carded)"; fi

# ── CPP-FREE-VS-MEMBER (D arms; graph.h FreeDeclReach, langfacts.h kBareCallNeedsDeclaration) ──────────────────────────────────────
# A bare C++ call binds a free function its translation unit DECLARES: the body's own file or a prototype, in the caller's
# file or one it includes. Envoy's shape: lib/util.h declares app::errorDetails and lib/util.cc defines it; codec/impl.cc
# holds an unrelated struct's member of the name and its `#else` twin, which the parser reads as a free function. Main
# declined every call (cands=2): the collapse evicts the prototype, and Rule 3 reads the bodies' own files.
dbase(){ mka "$1" lib/util.h '#pragma once
namespace app { int errorDetails(int code); }'
mka "$1" lib/util.cc '#include "lib/util.h"
namespace app { int errorDetails(int code) { return code; } }'
mka "$1" codec/impl.cc 'namespace app { namespace codec {
struct Values {
#ifdef NG
  int errorDetails(int code) const { return 1; }
};
#else
  int errorDetails(int) const { return 2; }
};
#endif
} }'; }
drow(){ grep -o "<s t=\"[a-z]*\" n=\"[^\"]*$2\" p=\"$3\"[^>]*>" "$1"; }                      # the row of callee $2 at path:line $3
dbound(){ local r; r="$( drow "$1" "$2" "$3" )"; [ -n "$r" ] && ! printf '%s' "$r" | grep -q 'via=\|prov='; }   # bound, unhedged
dsite(){ grep -q "n=\"[^\"]*$2\"" "$1"; }                                                      # premise: the answer names the call at all
dnone(){ ! grep -o "<s t=\"[a-z]*\" n=\"[^\"]*$2\" p=\"[^\"]*\"[^>]*>" "$1" | grep -v 'via=\|prov=' | grep -q .; }   # no unhedged row of $2
dshow(){ head -c 700 "$1"; echo; }

dbase d1; mka d1 net/conn.h '#pragma once
#include "lib/util.h"
namespace app { class Conn { public: int onWrite(); int n_; }; }'
mka d1 net/conn.cc '#include "net/conn.h"
namespace app {
int Conn::onWrite() { return errorDetails(2); }
int free_caller() { return errorDetails(3); }
}'
callee_rows d1 Conn::onWrite > "$TMP/d1m.xml"; callee_rows d1 free_caller > "$TMP/d1f.xml"
if dbound "$TMP/d1m.xml" errorDetails lib/util.cc:2 && ! drow "$TMP/d1m.xml" errorDetails codec/impl.cc:7 | grep -q .; then
  ok "D1 a member of an unrelated class: errorDetails(2) binds lib/util.cc's body alone, unhedged, through the included prototype (main declined)"
else no "D1 Conn::onWrite's errorDetails(2) is not bound to lib/util.cc:2 alone"; dshow "$TMP/d1m.xml"; fi
if dbound "$TMP/d1f.xml" errorDetails lib/util.cc:2 && ! drow "$TMP/d1f.xml" errorDetails codec/impl.cc:7 | grep -q .; then
  ok "D1 a free function: errorDetails(3) binds lib/util.cc's body alone, unhedged (main declined)"
else no "D1 free_caller's errorDetails(3) is not bound to lib/util.cc:2 alone"; dshow "$TMP/d1f.xml"; fi

# [N] D2 two namesakes BOTH declared to the caller: the includes do not decide
dbase d2; mka d2 other/o.h '#pragma once
namespace other { int errorDetails(int code); }'
mka d2 other/o.cc '#include "other/o.h"
namespace other { int errorDetails(int code) { return -code; } }'
mka d2 net/use.cc '#include "lib/util.h"
#include "other/o.h"
int use_both() { return errorDetails(4); }'
callee_rows d2 use_both > "$TMP/d2.xml"
if dsite "$TMP/d2.xml" errorDetails && dnone "$TMP/d2.xml" errorDetails; then
  ok "D2 [N] two declared namesakes: errorDetails(4) binds neither unhedged"
else no "D2 a call two included prototypes declare was bound unhedged (or the call site is missing from the answer)"; dshow "$TMP/d2.xml"; fi

# [N] D3 no namesake declared to the caller: nothing to prefer
dbase d3; mka d3 net/use.cc 'int use_none() { return errorDetails(5); }'
callee_rows d3 use_none > "$TMP/d3.xml"
if dsite "$TMP/d3.xml" errorDetails && dnone "$TMP/d3.xml" errorDetails; then
  ok "D3 [N] no declaration in reach: errorDetails(5) binds nothing unhedged"
else no "D3 a call with no declared namesake was bound unhedged (or the call site is missing)"; dshow "$TMP/d3.xml"; fi

# [N] D4 inside the member's own class, and inside a class derived from it: the member hides the declared free function
dbase d4; mka d4 codec/own.h '#pragma once
#include "lib/util.h"
namespace app { class Codec { public: int errorDetails(int code) const { return 7; } int describe() const { return errorDetails(1); } };
class Derived : public Codec { public: int viaBase() const { return errorDetails(4); } }; }'
callee_rows d4 Codec::describe > "$TMP/d4a.xml"; callee_rows d4 Derived::viaBase > "$TMP/d4b.xml"
if dbound "$TMP/d4a.xml" errorDetails codec/own.h:3 && ! drow "$TMP/d4a.xml" errorDetails lib/util.cc:2 | grep -q . \
   && dbound "$TMP/d4b.xml" errorDetails codec/own.h:3 && ! drow "$TMP/d4b.xml" errorDetails lib/util.cc:2 | grep -q .; then
  ok "D4 [N] inside Codec and inside Derived : Codec, errorDetails() stays Codec::errorDetails, never the declared free function"
else no "D4 a bare call inside the member's class cone left Codec::errorDetails"; dshow "$TMP/d4a.xml"; dshow "$TMP/d4b.xml"; fi

# [N] D5 a macro-made member function (gtest TEST_F) is indexed as a free function: the fixture's own member is what it calls
dbase d5; mka d5 other/o.cc 'namespace other { int errorDetails(int code) { return -code; } }'
mka d5 test/fix_test.cc '#include "lib/util.h"
using namespace app;
namespace fixtures {
class Fix { public: int errorDetails(int code) { return 9; } };
TEST_F(Fix, Reads) { errorDetails(6); }
}'
callee_rows d5 TEST_F > "$TMP/d5.xml"
if dsite "$TMP/d5.xml" errorDetails && ! dbound "$TMP/d5.xml" errorDetails lib/util.cc:2; then
  ok "D5 [N] TEST_F( Fix, … ) { errorDetails(6); } beside Fix::errorDetails in its file: the declared free function is not bound unhedged"
else no "D5 a macro-made member's bare call was bound unhedged to the free function (or the call site is missing)"; dshow "$TMP/d5.xml"; fi

# D6 an internal-linkage namesake (`static`) of another file is declared by no prototype: the external body is the answer
mka d6 lib/h.h '#pragma once
int helper(int a);'
mka d6 lib/h.cc '#include "lib/h.h"
int helper(int a) { return a; }'
mka d6 other/s.cc 'static int helper(int a) { return -a; }
int s_user() { return helper(1); }'
mka d6 app/use.cc '#include "lib/h.h"
int use_h() { return helper(2); }'
callee_rows d6 use_h > "$TMP/d6.xml"; callee_rows d6 s_user > "$TMP/d6s.xml"
if dbound "$TMP/d6.xml" helper lib/h.cc:2 && ! drow "$TMP/d6.xml" helper other/s.cc:1 | grep -q .; then
  ok "D6 helper(2) binds lib/h.cc's external body: another file's static helper is declared by no prototype (main declined)"
else no "D6 use_h's helper(2) is not bound to lib/h.cc:2 alone"; dshow "$TMP/d6.xml"; fi
if dbound "$TMP/d6s.xml" helper other/s.cc:1; then ok "D6 guard: the static helper's own file still calls it"
else no "D6 s_user lost its own file's static helper"; dshow "$TMP/d6s.xml"; fi

# [N] D7 an undeclared namesake in the caller's own innermost namespace would hide the declared one: nothing is cut
dbase d7; mka d7 net/x.cc '#include "lib/util.h"
namespace app { namespace codec { int in_codec() { return errorDetails(8); } } }'
callee_rows d7 in_codec > "$TMP/d7.xml"
if dsite "$TMP/d7.xml" errorDetails && ! dbound "$TMP/d7.xml" errorDetails lib/util.cc:2; then
  ok "D7 [N] a caller in namespace codec beside codec's own undeclared namesake: lib/util.cc is not bound unhedged"
else no "D7 the declared function was bound over a namesake of the caller's own scope (or the call site is missing)"; dshow "$TMP/d7.xml"; fi
# D8 the member twin of D7, a GAP: a member of a class of namespace codec, defined out of line, is in codec's scope too, but
# C++ keeps no namespace record to read the class's namespace from, so codec's undeclared namesake does not stop the cut
dbase d8; mka d8 net/y.h '#pragma once
#include "lib/util.h"
namespace app { namespace codec { class Reader { public: int read(); }; } }'
mka d8 net/y.cc '#include "net/y.h"
namespace app { namespace codec { int Reader::read() { return errorDetails(9); } } }'
callee_rows d8 Reader::read > "$TMP/d8.xml"
if dsite "$TMP/d8.xml" errorDetails && ! dbound "$TMP/d8.xml" errorDetails lib/util.cc:2; then
  echo "  GAP   D8 Reader::read of namespace codec: lib/util.cc is not bound over codec's undeclared namesake — the gap closed, make this arm a check"
else echo "  GAP   D8 Reader::read of namespace codec: errorDetails(9) binds lib/util.cc although codec's own undeclared namesake would hide it behind an unresolvable include (no C++ namespace record; carded)"; fi

# D9 a friend defined in its class (an unqualified declarator: indexed as a function, scoped by the class) is no namespace
# function: where it is a candidate nothing is cut
mka d9 lib/f.h '#pragma once
int tally(int a);'
mka d9 lib/f.cc '#include "lib/f.h"
int tally(int a) { return a; }'
mka d9 box/b.cc 'class Box { friend int tally(Box*) { return 3; } };'
mka d9 other/t.cc 'int tally(long a) { return 4; }'
mka d9 app/use.cc '#include "lib/f.h"
int use_t() { return tally(2); }'
callee_rows d9 use_t > "$TMP/d9.xml"
if dsite "$TMP/d9.xml" tally && ! drow "$TMP/d9.xml" tally other/t.cc:1 | grep -v 'via=\|prov=' | grep -q .; then
  ok "D9 [N] a friend namesake in Box: other/t.cc's undeclared tally is never bound unhedged"
else no "D9 other/t.cc's undeclared tally was bound unhedged (or the call site is missing)"; dshow "$TMP/d9.xml"; fi

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "SOME CHECKS FAILED"; exit 1; fi
