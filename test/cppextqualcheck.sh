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
# The member-call veto (b) — Rule 2's class identity keeps the includer-directory closure — and the bare-call twin are pinned in
# test/crootincludecheck.sh R9 and measured on Envoy (reports/cpp-extqual-veto.md); no small tree reproduced the typed-receiver shape.
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

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "SOME CHECKS FAILED"; exit 1; fi
