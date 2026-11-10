#!/usr/bin/env bash
# xfaliashopcheck.sh — XF-ALIAS-HOP gate: a hop that meets an alias name continues to its target (src/aliashop.h, the one walk).
#
# WHY: `--for=ColumnPtr` on ClickHouse printed `using ColumnPtr = COW<IColumn>::Ptr` and stopped; what it names (COW::Ptr, then
# `using Ptr = immutable_ptr<Derived>`, then the class immutable_ptr) and the class it points at (IColumn) took more calls, and
# `--uses=IColumn` listed no site written as ColumnPtr. The for verb now prints an <aliases> block (src/foraliashop.h) and the uses
# verb lists the sites written through an alias, each via="alias".
#
# RED-BEFORE-FIX: every [RED] arm fails on the base binary (lane/for-surface-defs 48d8e84d5; recorded in reports/xf-alias-hop.md);
# the unmarked arms hold on base and head alike (each absence arm has a positive twin). Fixtures are built at runtime. Every arm
# reads a command whose exit code it checks.
#
# Usage: test/xfaliashopcheck.sh [BIN]      (BIN falls back to RIPWIRE_BIN, then build/ripwire)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "xfaliashopcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
if [ ! -x "$BIN" ]; then echo "  FAIL  no binary at $BIN"; exit 1; fi

# run DIR OUT ARGS...: the answer into OUT, its exit code into OUT.rc; a nonzero exit or an empty answer is a FAIL of its own
run(){ local dir="$1" out="$2"; shift 2; ( cd "$dir" || exit 97; "$BIN" . --no-cache "$@" ) >"$out" 2>"$out.err"; local rc=$?; echo "$rc" >"$out.rc"
       if [ "$rc" -ne 0 ] || [ ! -s "$out" ]; then no "run $* in ${dir##*/}: rc=$rc bytes=$( wc -c <"$out" | tr -d ' ' )"; return 1; fi; return 0; }
has(){ grep -qF -- "$2" "$1"; }

C="$TMP/cpp"; mkdir -p "$C/src" "$C/other"
cat > "$C/src/cow.h" <<'EOF'
#pragma once
template <typename T> class immutable_ptr { public: T* get() const { return p; } T* p; };
template <typename Derived> class COW {
public:
    using Ptr = immutable_ptr<Derived>;
    Ptr clone() const { return Ptr(); }
};
EOF
cat > "$C/src/icolumn.h" <<'EOF'
#pragma once
#include "cow.h"
#include <memory>
namespace DB {
class IColumn : public COW<IColumn> {
public:
    int size() const { return 0; }
    void insert(int x) { (void)x; }
};
using ColumnPtr = COW<IColumn>::Ptr;
using Columns = ColumnPtr;
using Shared = std::shared_ptr<IColumn>;
using External = std::shared_ptr<Missing>;
using LoopA = LoopB;
using LoopB = LoopA;
}
EOF
cat > "$C/other/elsewhere.h" <<'EOF'
#pragma once
#include "../src/icolumn.h"
namespace Other { using ColumnRef = DB::IColumn; }
EOF
# a namesake class inside another translation unit's .cpp (an example program): never what a header alias names, and its
# members are its own (arm 1 pins members="2" m="size,insert" on the header class)
cat > "$C/other/example.cpp" <<'EOF'
class IColumn { public: void exampleOnly() {} };
EOF
cat > "$C/src/use.cpp" <<'EOF'
#include "icolumn.h"
#include "../other/elsewhere.h"
namespace DB {
int countRows(ColumnPtr col) { return col.get()->size(); }
void fill(IColumn & c) { c.insert(1); }
void viaAlias(Columns cs) { countRows(cs); }
int direct(IColumn * c) { return c->size(); }
int viaShared(Shared s) { return s->size(); }
int viaRef(Other::ColumnRef & r) { return r.size(); }
}
EOF

# 1. --for on the alias: the chain to COW::Ptr, immutable_ptr (COW.h) and the pointee IColumn with its members
if run "$C" "$TMP/f1" --for=ColumnPtr; then
  if has "$TMP/f1" '<aliases total='; then ok "[RED] for alias: an <aliases> block"; else no "[RED] for alias: no <aliases> block"; fi
  if has "$TMP/f1" '<h n="Ptr" sc="COW" t="alias"'; then ok "[RED] for alias: hop 1 COW::Ptr (alias row)"; else no "[RED] for alias: hop 1 COW::Ptr missing"; fi
  if grep -qE '<h n="immutable_ptr" t="cls" p="src/cow.h" l="2" d="2" via="alias"' "$TMP/f1"; then ok "[RED] for alias: hop 2 immutable_ptr in cow.h, via=alias"; else no "[RED] for alias: hop 2 immutable_ptr missing"; fi
  if grep -qE '<h n="IColumn" t="cls" [^>]*d="1" via="alias" arg="1" members="2" m="size,insert"' "$TMP/f1"; then ok "[RED] for alias: the pointee IColumn with its members"; else no "[RED] for alias: pointee IColumn row missing"; fi
  if has "$TMP/f1" '<h n="IColumn" t="cls" p="other/example.cpp"'; then no "for alias: the example .cpp's own IColumn was bound"; else ok "for alias: another translation unit's .cpp class is not bound (twin of the row above)"; fi
  if has "$TMP/f1" 'next="--uses=IColumn"'; then ok "[RED] for alias: next= lists the users"; else no "[RED] for alias: next= missing"; fi
  if has "$TMP/f1" 'via="alias" (reached through the alias'; then ok "[RED] for alias: via=alias is legend-defined in the answer"; else no "[RED] for alias: legend clause missing"; fi
  if has "$TMP/f1" '<leaf n="Derived"/>'; then no "for alias: a deeper hop's template parameter is not followed"; else ok "for alias: a deeper hop's template parameter is not followed (no Derived leaf)"; fi
fi
# 1b. the same alias named inside a sentence (the route reads words; the alias rows print as literal lines): the block still walks it
if run "$C" "$TMP/f1s" "--for=definition of the type alias ColumnPtr"; then
  if grep -qE '<chain of="ColumnPtr" p="src/icolumn.h"' "$TMP/f1s" && has "$TMP/f1s" '<h n="Ptr" sc="COW" t="alias"'; then ok "[RED] sentence wording: the chain walks from the sentence's name"; else no "[RED] sentence wording: no chain"; fi
fi
# 2. alias of an alias: Columns -> ColumnPtr -> COW::Ptr -> immutable_ptr
if run "$C" "$TMP/f2" --for=Columns; then
  if has "$TMP/f2" '<h n="ColumnPtr" sc="DB" t="alias"' && grep -qF '<h n="immutable_ptr" t="cls" p="src/cow.h" l="2" d="3"' "$TMP/f2"; then ok "[RED] alias of an alias: walked to d=3"; else no "[RED] alias of an alias: chain short"; fi
fi
# 3. alias to a template instance outside the tree: std::shared_ptr is a leaf, the argument IColumn is followed
if run "$C" "$TMP/f3" --for=Shared; then
  if has "$TMP/f3" '<leaf n="std::shared_ptr"/>'; then ok "[RED] template instance: std::shared_ptr stays a leaf, disclosed"; else no "[RED] template instance: no std leaf"; fi
  if grep -qE '<h n="IColumn" [^>]*arg="1"' "$TMP/f3"; then ok "[RED] template instance: the argument IColumn is reached"; else no "[RED] template instance: IColumn arg missing"; fi
fi
# 4. an alias whose target is nowhere in the tree: leaves only, no definition row
if run "$C" "$TMP/f4" --for=External; then
  if has "$TMP/f4" '<leaf n="Missing"/>' && has "$TMP/f4" '<leaf n="std::shared_ptr"/>'; then ok "[RED] not in the tree: both spellings are leaves"; else no "[RED] not in the tree: leaves missing"; fi
  if has "$TMP/f4" '<h '; then no "not in the tree: a definition row was invented"; else ok "not in the tree: no <h> row (twin of arm 3)"; fi
fi
# 5. a cycle ends the walk and says so
if run "$C" "$TMP/f5" --for=LoopA; then
  # on the element, never a bare attribute the legend also spells (fix round 1, M2: the legend matched a mutant's answer)
  if grep -qE '<chain [^>]*cycle="1"' "$TMP/f5"; then ok "[RED] cycle: cycle=1 on the chain element"; else no "[RED] cycle: no cycle=1 on the chain"; fi
fi
# 6. an alias in another namespace and file reaches DB::IColumn
if run "$C" "$TMP/f6" --for=ColumnRef; then
  if grep -qE '<chain of="ColumnRef" p="other/elsewhere.h"' "$TMP/f6" && grep -qE '<h n="IColumn" t="cls" p="src/icolumn.h"' "$TMP/f6"; then ok "[RED] other namespace/file: DB::IColumn reached"; else no "[RED] other namespace/file: not reached"; fi
fi
# 7. --uses on the target: the sites written through an alias are listed, via="alias" alias=, and the direct rows stay first
if run "$C" "$TMP/u1" --uses=IColumn; then
  if grep -qE '<u role="type" p="src/use.cpp:4"[^>]* via="alias" alias="ColumnPtr"' "$TMP/u1"; then ok "[RED] uses target: countRows (ColumnPtr) listed via=alias"; else no "[RED] uses target: ColumnPtr site missing"; fi
  if grep -qE '<u role="type" p="src/use.cpp:6"[^>]* via="alias" alias="Columns"' "$TMP/u1"; then ok "[RED] uses target: viaAlias (Columns, alias of an alias)"; else no "[RED] uses target: Columns site missing"; fi
  if grep -qE 'via="alias" alias="Shared"' "$TMP/u1"; then ok "[RED] uses target: Shared (template argument)"; else no "[RED] uses target: Shared site missing"; fi
  if grep -qE 'via_alias="[1-9]' "$TMP/u1"; then ok "[RED] uses target: via_alias= on the root"; else no "[RED] uses target: via_alias= missing"; fi
  if has "$TMP/u1" 'via="alias" alias=A'; then ok "[RED] uses target: legend defines via=alias"; else no "[RED] uses target: legend clause missing"; fi
  if grep -qE '<u role="type" p="src/use.cpp:5" in_id="src/use.cpp::DB::fill"/>' "$TMP/u1"; then ok "uses target: the direct row keeps its bytes"; else no "uses target: the direct fill row changed"; fi
  if grep -qE 'alias="External"|alias="LoopA"' "$TMP/u1"; then no "uses target: an alias that does not reach IColumn was listed"; else ok "uses target: External / LoopA not listed (twin of the rows above)"; fi
fi
# 8. ablation twin: RIPWIRE_NO_ALIAS_HOP restores the base answer
if ( cd "$C" && RIPWIRE_NO_ALIAS_HOP=1 "$BIN" . --no-cache --for=ColumnPtr ) >"$TMP/f1off" 2>/dev/null; then
  if has "$TMP/f1off" '<aliases'; then no "switch: RIPWIRE_NO_ALIAS_HOP left the block"; else ok "switch: RIPWIRE_NO_ALIAS_HOP drops the block"; fi
else no "switch: the run with RIPWIRE_NO_ALIAS_HOP failed"; fi
# 9. a token budget holds the block
if run "$C" "$TMP/f9" --for=ColumnPtr --token-budget=4000; then
  if has "$TMP/f9" '<aliases held="budget" total="1"/>'; then ok "[RED] budget: held marker with total="; else no "[RED] budget: no held marker"; fi
fi

# 10. alias-free answers are byte-identical: a fixture with no alias, the switch on and off
N="$TMP/noalias"; mkdir -p "$N/src"
cat > "$N/src/a.cpp" <<'EOF'
struct Widget { int size() const { return 1; } };
int measure(Widget & w) { return w.size(); }
int twice(Widget & w) { return measure(w) * 2; }
EOF
for a in --for=Widget --for=measure "--for=how is a widget measured" --uses=Widget --callers=measure; do
  if run "$N" "$TMP/n.on" "$a" && ( cd "$N" && RIPWIRE_NO_ALIAS_HOP=1 "$BIN" . --no-cache "$a" ) >"$TMP/n.off" 2>/dev/null; then
    if cmp -s "$TMP/n.on" "$TMP/n.off"; then ok "alias-free byte-identical: $a"; else no "alias-free answer moved: $a"; fi
    if has "$TMP/n.on" 'via="alias"'; then no "alias-free: via=alias printed on $a"; else ok "alias-free: no via=alias on $a"; fi
  fi
done
# 11. languages whose alias rows record no target yet (TS `type`, Rust `type`): no block, no invented hop (the C++ arm above is the twin)
T="$TMP/ts"; mkdir -p "$T/src"
printf 'export interface Real { run(): void }\nexport type RealAlias = Real;\nexport function go(r: RealAlias) { r.run(); }\n' > "$T/src/a.ts"
if run "$T" "$TMP/t1" --for=RealAlias; then
  if has "$TMP/t1" '<aliases'; then no "TS type alias: a block without a recorded target"; else ok "TS type alias: no block (no target recorded; card follow-on)"; fi
fi
R="$TMP/rs"; mkdir -p "$R/src"
printf 'pub struct Real;\npub type RealAlias = Real;\npub fn go(_r: RealAlias) {}\n' > "$R/src/lib.rs"
if run "$R" "$TMP/r1" --for=RealAlias; then
  if has "$TMP/r1" '<aliases'; then no "Rust type alias: a block without a recorded target"; else ok "Rust type alias: no block (no target recorded; card follow-on)"; fi
fi
# ── fix round 1 (reports/rv-xf-alias-hop.md M1, M2, S1, S2, S5) ── here [RED] = fails on the lane's first head cae02ce48
# (tmp/alias-fix1/disp.md records it); [MUT] = holds on cae02ce48 and fails on a named mutant (seen guard off, qualifier ignored)
# 13. two namespaces each with `using Ptr` (review fixture, no macro): a site counts for the alias in scope there, the other is hedged
Q="$TMP/ns"; mkdir -p "$Q/src"
cat > "$Q/src/a.h" <<'EOF2'
namespace A { class Foo { public: int fa() { return 1; } }; using Ptr = Foo; }
namespace B { class Bar { public: int fb() { return 2; } }; using Ptr = Bar; }
namespace N1 { class Widget { public: void w1() {} }; }
namespace N2 { class Widget { public: void w2() {} }; }
namespace N1 { using WP = Widget; }
using WQ = N2::Widget;
using L1 = L2; using L2 = L3; using L3 = L1;
using D1 = D2; using D2 = D3; using D3 = D4; using D4 = D5; using D5 = D6; using D6 = A::Foo;
EOF2
cat > "$Q/src/u.cpp" <<'EOF2'
#include "a.h"
namespace B { int useB2(Ptr p) { return p.fb(); } }
namespace A { int useA2(Ptr p) { return p.fa(); } }
namespace N2 { void n2fn() {} }
void useD1(D1 d) { (void)d; }
EOF2
if run "$Q" "$TMP/q1" --uses=Foo; then
  if grep -qE '<u role="type" p="src/u.cpp:3" in_id="src/u.cpp::A::useA2" via="alias" alias="Ptr"/>' "$TMP/q1"; then ok "namesake: A::useA2 is a proven use of Foo (positive twin)"; else no "namesake: A::useA2 missing or hedged"; fi
  if grep -qE 'in_id="src/u.cpp::B::useB2" via="alias" alias="Ptr"/>' "$TMP/q1"; then no "[RED] namesake: B::useB2 (B::Ptr names Bar) counted as a use of Foo"; else ok "[RED] namesake: B::useB2 is not a proven use of Foo"; fi
  if grep -qE 'in_id="src/u.cpp::B::useB2" via="alias" alias="Ptr" hedge="name"/>' "$TMP/q1"; then ok "[RED] namesake: B::useB2 listed hedge=name"; else no "[RED] namesake: no hedged B::useB2 row"; fi
  if grep -qE '<uses [^>]*count="3"[^>]* alias_hedged="1"' "$TMP/q1"; then ok "[RED] namesake: count= leaves the hedged row out, alias_hedged=1"; else no "[RED] namesake: count=/alias_hedged= wrong"; fi
  if grep -qE '<uses [^>]* alias_depth_capped="1"' "$TMP/q1"; then ok "[RED] depth cap: alias_depth_capped=1 on the uses root (D6..D1)"; else no "[RED] depth cap: no alias_depth_capped on the root"; fi
  if grep -qE 'hedge="name"[^ ]*: the (alias )?site' "$TMP/q1"; then ok "[RED] namesake: hedge= is legend-defined"; else no "[RED] namesake: hedge= legend clause missing"; fi
fi
if run "$Q" "$TMP/q2" --uses=Bar; then
  if grep -qE 'in_id="src/u.cpp::B::useB2" via="alias" alias="Ptr"/>' "$TMP/q2"; then ok "namesake: B::useB2 is a proven use of Bar (positive twin)"; else no "namesake: B::useB2 missing under Bar"; fi
  if grep -qE 'in_id="src/u.cpp::A::useA2" via="alias" alias="Ptr"/>' "$TMP/q2"; then no "[RED] namesake: A::useA2 counted as a use of Bar"; else ok "[RED] namesake: A::useA2 is not a proven use of Bar"; fi
  if has "$TMP/q2" 'alias_depth_capped'; then no "depth cap: alias_depth_capped printed without a cut"; else ok "depth cap: no alias_depth_capped without a cut (twin)"; fi
fi
# 14. a class qualifier: a class's scope is its own name, so the namespace is read off the braces
if run "$Q" "$TMP/q3" --for=WQ; then
  if grep -qE '<h n="Widget" t="cls" p="src/a.h" l="4" d="1" via="alias" members="1" m="w2">' "$TMP/q3"; then ok "[RED] qualifier: N2::Widget binds the N2 class, proven, its own member only"; else no "[RED] qualifier: N2::Widget row wrong"; fi
  if grep -qE '<h n="Widget" [^>]*l="3"' "$TMP/q3"; then no "[RED] qualifier: N1::Widget bound for N2::Widget"; else ok "[RED] qualifier: N1::Widget not bound (a free function in N2 does not merge them)"; fi
  if has "$TMP/q3" '<leaf n="N2::Widget"/>'; then no "qualifier: a false leaf"; else ok "qualifier: no leaf for an in-tree class"; fi
fi
if run "$Q" "$TMP/q4" --for=WP; then
  if grep -qE '<h n="Widget" t="cls" p="src/a.h" l="3" [^>]*members="1" m="w1">' "$TMP/q4" && ! grep -qE '<h n="Widget" [^>]*l="4"' "$TMP/q4"; then ok "[RED] unqualified: N1::WP = Widget binds N1::Widget only"; else no "[RED] unqualified: WP bound the wrong Widget"; fi
fi
# 15. cycle and depth on the element (the mutant arms: seen guard off, qualifier ignored)
if run "$Q" "$TMP/q5" --for=L1; then
  if grep -qE '<chain of="L1" [^>]*cycle="1"' "$TMP/q5" && [ "$( grep -o '<h n="L2"' "$TMP/q5" | wc -l | tr -d ' ' )" = 1 ]; then ok "[MUT] cycle: L1 -> L2 -> L3 stops once, cycle=1"; else no "[MUT] cycle: L1 chain repeats or lacks cycle=1"; fi
  if grep -qE '<chain [^>]*depth_capped="1"' "$TMP/q5"; then no "cycle: depth_capped on a 3-cycle"; else ok "cycle: no depth_capped on a 3-cycle (twin)"; fi
fi
if run "$Q" "$TMP/q6" --for=D1; then
  if grep -qE '<chain of="D1" [^>]*depth_capped="1"' "$TMP/q6" && grep -qF '<h n="D5" t="alias" p="src/a.h" l="8" d="4"' "$TMP/q6" && ! has "$TMP/q6" '<h n="D6"'; then ok "[MUT] depth: D1..D5 at d=4, depth_capped=1, D6 not walked"; else no "[MUT] depth: cap wrong"; fi
fi
# 16. an unreadable chain: the bind is hedged, never a plain leaf (S1)
M="$TMP/mac"; mkdir -p "$M/src"
# braces that do not balance (`#if` / `#else` each open the namespace): the chain is unknown; a scope-like macro alone on its
# line (DECL_PTR) is not enough to drop it (the twin in $Q above has none, arm 14)
{ printf '#define DECL_PTR(T) typedef T T##Hold;\nDECL_PTR(Foo)\n#if defined(OLD)\nnamespace Z {\n#else\nnamespace Z {\n#endif\n}\n'; cat "$Q/src/a.h"; } > "$M/src/a.h"
cp "$Q/src/u.cpp" "$M/src/u.cpp"
if run "$M" "$TMP/m1" --for=WQ; then
  if grep -qE '<h n="Widget" [^>]*bound="name"' "$TMP/m1"; then ok "[RED] unknown chain: N2::Widget bound by name, hedged"; else no "[RED] unknown chain: no bound=name row"; fi
  if has "$TMP/m1" '<leaf n="N2::Widget"/>'; then no "unknown chain: a false leaf"; else ok "unknown chain: no leaf for an in-tree class (twin)"; fi
  if has "$TMP/m1" 'bound="name": the written'; then ok "[RED] unknown chain: bound= is legend-defined"; else no "[RED] unknown chain: bound= legend clause missing"; fi
fi
# 16b. positive twin: a scope-like macro alone on its line with balanced braces keeps the chain, so N2::Widget is proven
P="$TMP/mac2"; mkdir -p "$P/src"
{ printf '#define DECL_PTR(T) typedef T T##Hold;\nDECL_PTR(Foo)\n'; cat "$Q/src/a.h"; } > "$P/src/a.h"; cp "$Q/src/u.cpp" "$P/src/u.cpp"
if run "$P" "$TMP/m2" --for=WQ; then
  if grep -qE '<h n="Widget" t="cls" p="src/a.h" l="6" d="1" via="alias" members="1" m="w2">' "$TMP/m2"; then ok "[RED] balanced braces beside a macro: N2::Widget proven"; else no "[RED] balanced braces beside a macro: not proven"; fi
fi
# 17. the block's legend names only what it prints (S5) and --max-tokens sheds m= first, disclosed
if run "$C" "$TMP/l1" --for=ColumnPtr; then
  if has "$TMP/l1" 'cycle="1": a definition'; then no "[RED] legend: a cycle clause without a cycle"; else ok "[RED] legend: no cycle clause on an acyclic chain"; fi
  if has "$TMP/l1" 'unread="1": its file'; then no "[RED] legend: an unread clause with nothing unread"; else ok "[RED] legend: no unread clause"; fi
  if has "$TMP/f5" 'cycle="1": a definition'; then ok "legend: the cycle clause rides when a chain has one (twin)"; else no "legend: cycle clause missing on the cyclic chain"; fi
fi
# shed= follows the --for body ceiling (--max-tokens WITH --detail=N), the kShapingVerbs carve-out: a bare --max-tokens is noticed as ignored
# ("nothing was dropped"), so the bare run must print the block whole and byte-identical to the run without the flag (shapingflagcheck (A) 22 sites)
if run "$C" "$TMP/l2" --for=ColumnPtr --max-tokens=40000 --detail=1; then
  if grep -qE '<aliases [^>]*shed="m"' "$TMP/l2" && ! grep -qE '<h [^>]* m="' "$TMP/l2" && grep -qE '<h n="IColumn" [^>]*members="2"' "$TMP/l2"; then ok "[RED] max-tokens + detail: m= shed, members= kept, shed=m disclosed"; else no "[RED] max-tokens + detail: shed wrong"; fi
  if has "$TMP/l2" 'shed=: a max-tokens'; then ok "[RED] max-tokens + detail: shed= legend-defined"; else no "[RED] max-tokens + detail: shed= legend missing"; fi
fi
if run "$C" "$TMP/l3" --for=ColumnPtr --max-tokens=40000; then
  if grep -qE '<aliases [^>]*shed=' "$TMP/l3" || ! grep -qE '<h [^>]* m="' "$TMP/l3"; then no "[RED] bare --max-tokens: the alias block shed under a flag the notice says --for ignores"; else ok "[RED] bare --max-tokens: the alias block prints whole (the notice's 'nothing was dropped' holds)"; fi
  if ! grep -q 'is not read by --for' "$TMP/l3.err"; then no "[RED] bare --max-tokens: the ignore notice is missing"; else ok "bare --max-tokens: the ignore notice rides"; fi
fi

# ── CodeRabbit round on #537 (tmp/card12-cr/disp.md) ── here [RED] = fails on 26bf91a3b (the head CodeRabbit read)
X="$TMP/cr"; mkdir -p "$X/src"
cat > "$X/src/a.h" <<'EOF3'
namespace A { class Foo { public: int fa() { return 1; } }; using Ptr = Foo; }
namespace B { class Bar { public: int fb() { return 2; } }; using Ptr = Bar; }
class Widget { public: void g() {} };
namespace A { class Widget { public: void a() {} }; using GW = ::Widget; using GS = Holder<::Widget>; using AW = Widget; }
template <class T> class Holder { public: T* t; };
namespace S { class Sp { public: void s() {} }; }
using SW = S :: Sp;
using SW2 = S:: Sp;
class Gy { public: void y() {} };
using Q1 = Gy;
using Q2 = Q1;
using Q3 = Q2;
using Q4 = Q3;
using Q5 = Q4;
class Hx { public: void h() {} };
using H4 = Hx; using H3 = H4; using H2 = H3; using H1 = H2;
class Many { public: void m1(); void m2(); void m3(); void m4(); void m5(); void m6(); void m7(); void m8(); void m9(); void m10(); void m11(); void m12(); void m13(); void zz(int); void zz(double); };
using ManyP = Many;
namespace A { using Same = Foo; }
using SH = Holder< S :: Sp >;
EOF3
printf 'class Gl { public: void g() {} };\n' > "$X/src/gl.h"
# braces that do not balance (`#if` / `#else` each open a namespace): every chain in this file is unknown
cat > "$X/src/unbal.h" <<'EOF3'
#include "gl.h"
#if defined(OLD)
namespace Z {
#else
namespace Z {
#endif
}
namespace OnlyC { class Lone { public: void l() {} }; }
using LW = OnlyC::Lone;
namespace P { using GL2 = Gl; }
namespace A { int useU(Ptr p); }
namespace A { using Same = Foo; }
EOF3
cat > "$X/src/u.cpp" <<'EOF3'
#include "a.h"
namespace B { int useB2(Ptr p) { return p.fb(); } }
namespace A { int useA2(Ptr p) { return p.fa(); } }
void useQ4(Q4 q) { (void)q; }
void useQ5(Q5 q) { (void)q; }
void useH1(H1 h) { (void)h; }
namespace B { namespace Deep {
int early(Ptr p);
using Ptr = A::Foo;
int late(Ptr p);
} }
EOF3
# 18. a global `::` target binds the global definition, never the namesake in the alias's own namespace (CR 4476868622)
if run "$X" "$TMP/x1" --for=GW; then
  if grep -qE '<h n="Widget" t="cls" p="src/a.h" l="3" d="1" via="alias"' "$TMP/x1" && ! grep -qE '<h n="Widget" [^>]*l="4"' "$TMP/x1"; then ok "[RED] global ::Widget binds the global class only"; else no "[RED] global ::Widget bound the namespace's Widget"; fi
  if has "$TMP/x1" 'bound="name"'; then no "global ::Widget: hedged although every chain is read"; else ok "global ::Widget: proven, no bound=name (twin of arm 22)"; fi
fi
if run "$X" "$TMP/x2" --for=GS; then
  if grep -qE '<h n="Widget" t="cls" p="src/a.h" l="3" [^>]*arg="1"' "$TMP/x2"; then ok "[RED] global ::Widget as a template argument binds the global class"; else no "[RED] global template argument bound the namespace's Widget"; fi
fi
if run "$X" "$TMP/x3" --for=AW; then
  if grep -qE '<h n="Widget" t="cls" p="src/a.h" l="4" ' "$TMP/x3"; then ok "unqualified Widget inside A binds A::Widget (twin of the global arm)"; else no "unqualified Widget inside A: not A::Widget"; fi
fi
# 19. a space beside `::` continues the qualified name (CR 4476868634)
for a in SW SW2; do
  if run "$X" "$TMP/x4$a" --for=$a; then
    if grep -qE '<h n="Sp" t="cls"' "$TMP/x4$a" && ! has "$TMP/x4$a" '<leaf n="S"/>'; then ok "[RED] spaced qualifier ($a): S::Sp bound, no leaf S"; else no "[RED] spaced qualifier ($a): the head ended at the space"; fi
  fi
done
if run "$X" "$TMP/x4SH" --for=SH; then
  if grep -qE '<h n="Sp" t="cls" [^>]*arg="1"' "$TMP/x4SH"; then ok "[RED] spaced qualifier in a template argument: S::Sp reached as arg"; else no "[RED] spaced qualifier in a template argument: Sp missing"; fi
fi
# 20. a qualified target whose definitions' chains are unknown binds hedged, never a false leaf (CR 4476868644)
if run "$X" "$TMP/x5" --for=LW; then
  if grep -qE '<h n="Lone" [^>]*bound="name"' "$TMP/x5" && ! has "$TMP/x5" '<leaf n="OnlyC::Lone"/>'; then ok "[RED] unknown chain, class-only namespace: Lone bound=name, no leaf"; else no "[RED] unknown chain, class-only namespace: a false leaf"; fi
fi
# 21. an unqualified target from an alias whose own chain is unknown is hedged (CR 4476868651)
if run "$X" "$TMP/x6" --for=GL2; then
  if grep -qE '<h n="Gl" [^>]*bound="name"' "$TMP/x6"; then ok "[RED] unknown alias origin: Gl bound=name"; else no "[RED] unknown alias origin: Gl printed as proven"; fi
fi
# 22. two same-named alias rows, one proven and one hedged, keep two chains (CR 4476868736)
if run "$X" "$TMP/x7" --for=Same; then
  if grep -qE '<chain of="Same" p="src/a.h"' "$TMP/x7" && grep -qE '<chain of="Same" p="src/unbal.h"' "$TMP/x7" && grep -qE '<h n="Foo" [^>]*bound="name"' "$TMP/x7"; then ok "[RED] merge keeps the hedge: two chains, one bound=name"; else no "[RED] merge folded a hedged walk into a proven one"; fi
fi
# 23. members= counts a name once, past the 12-name list too (CR 4476868745)
if run "$X" "$TMP/x8" --for=ManyP; then
  if grep -qE '<h n="Many" [^>]*members="14"' "$TMP/x8"; then ok "[RED] members=14: the overloaded zz past the list counts once"; else no "[RED] members= counts overloads past the list"; fi
fi
# 24. --uses walks one hop per round: a 5-hop alias is cut and disclosed whatever the declaration order; exactly 4 hops is no cut
if run "$X" "$TMP/x9" --uses=Gy; then
  if grep -qE 'in_id="[^"]*useQ5" via="alias"' "$TMP/x9"; then no "[RED] round boundary: Q5 (5 hops) listed"; else ok "[RED] round boundary: Q5 (5 hops) not listed (CR 4476868668)"; fi
  if grep -qE '<uses [^>]* alias_depth_capped="1"' "$TMP/x9"; then ok "[RED] round boundary: alias_depth_capped=1 for Q5"; else no "[RED] round boundary: no alias_depth_capped"; fi
  if grep -qE 'in_id="[^"]*useQ4" via="alias" alias="Q4"/>' "$TMP/x9"; then ok "round boundary: Q4 (4 hops) listed (twin)"; else no "round boundary: Q4 missing"; fi
fi
if run "$X" "$TMP/x10" --uses=Hx; then
  if has "$TMP/x10" 'alias_depth_capped'; then no "[RED] exact 4 hops: alias_depth_capped with nothing left (CR 4476868673)"; else ok "[RED] exact 4 hops: no alias_depth_capped"; fi
  if grep -qE 'in_id="[^"]*useH1" via="alias" alias="H1"/>' "$TMP/x10"; then ok "exact 4 hops: H1 listed (twin)"; else no "exact 4 hops: H1 missing"; fi
fi
# 25. the full legend's alias_sites_held clause rides only on the columnar form (CR 4476868678); compact count= excludes hedged rows (CR 4476868685)
if run "$X" "$TMP/x11" --uses=Foo --legend=full && run "$X" "$TMP/x12" --uses=Foo --legend=full --format=columnar; then
  if has "$TMP/x11" 'alias_sites_held=N'; then no "[RED] XML legend defines alias_sites_held"; else ok "[RED] XML legend: no alias_sites_held clause"; fi
  if has "$TMP/x12" 'alias_sites_held=N' && has "$TMP/x12" 'alias_sites_held="'; then ok "columnar: alias_sites_held on the root and in the legend (twin)"; else no "columnar: alias_sites_held clause or attribute missing"; fi
fi
if run "$X" "$TMP/x13" --uses=Foo; then
  if has "$TMP/x13" 'count=N: use-site rows in all'; then no "[RED] compact count= says all rows although hedge=name rows are left out"; else ok "[RED] compact count= reading leaves the hedged rows out"; fi
  # 26. a site whose own chain is unknown is hedged when the alias name has namesakes (CR 4476868752)
  if grep -qE 'in_id="src/unbal.h::A::useU" via="alias" alias="Ptr" hedge="name"/>' "$TMP/x13"; then ok "[RED] unknown site chain: useU hedged"; else no "[RED] unknown site chain: useU proven"; fi
  # 27. an alias declared after the site cannot be the one in scope there (CR 4476868782)
  if grep -qE 'in_id="src/u.cpp::Deep::early" via="alias" alias="Ptr"/>' "$TMP/x13"; then no "[RED] later alias: Deep::early proven through the later Deep::Ptr"; else ok "[RED] later alias: Deep::early not a proven use of Foo"; fi
  if grep -qE 'in_id="src/u.cpp::Deep::late" via="alias" alias="Ptr"/>' "$TMP/x13"; then ok "later alias: Deep::late (after the alias) proven (twin)"; else no "later alias: Deep::late missing"; fi
  if grep -qE 'in_id="src/u.cpp::A::useA2" via="alias" alias="Ptr"/>' "$TMP/x13"; then ok "known site chain: useA2 proven (twin)"; else no "known site chain: useA2 missing"; fi
fi
if run "$X" "$TMP/x14" --uses=Bar; then
  if grep -qE 'in_id="src/u.cpp::Deep::early" via="alias" alias="Ptr"/>' "$TMP/x14"; then ok "[RED] later alias: Deep::early is a proven use of Bar (B::Ptr in scope)"; else no "[RED] later alias: Deep::early not under Bar"; fi
fi
# 28. a file-qualified selector lists the alias sites its definitions reach (CR 4476868792)
if run "$X" "$TMP/x15" --uses=src/a.h:Foo; then
  if grep -qE 'in_id="src/u.cpp::A::useA2" via="alias" alias="Ptr"/>' "$TMP/x15" && grep -qE '<uses [^>]*via_alias="[1-9]' "$TMP/x15"; then ok "[RED] file-qualified: alias sites listed, via_alias="; else no "[RED] file-qualified: alias sites dropped silently"; fi
fi
# 29. a credential-shaped literal in an alias declaration is redacted in the block, and in --defs to= (CR 4476868695)
K="$TMP/key"; mkdir -p "$K/src"
SECRET="AKIA$( printf 'Q%.0s' 1 2 3 4 5 6 7 8 )$( printf 'Z7%.0s' 1 2 3 4 )"   # built at runtime: no secret-shaped literal in the tree
printf 'template <const char* K> struct Tok { int t; };\nusing Key = Tok<"%s">;\nusing Key2 = Key;\n' "$SECRET" > "$K/src/k.h"
for a in --for=Key --for=Key2 --defs=Key; do
  if run "$K" "$TMP/k$a" "$a"; then
    if has "$TMP/k$a" "$SECRET"; then no "[RED] redact: $a prints the key"; else ok "[RED] redact: $a prints no key"; fi
  fi
done
if has "$TMP/k--for=Key2" '<aliases'; then ok "redact: the Key2 block is printed (the arm above reads it)"; else no "redact: no Key2 block to read"; fi
if run "$K" "$TMP/kno" --for=Key2 --no-redact; then
  if has "$TMP/kno" "$SECRET"; then ok "redact: --no-redact passes the declaration through (twin)"; else no "redact: --no-redact lost the text"; fi
fi
if run "$K" "$TMP/kno1" --for=Key --no-redact; then
  if grep -qE '<chain of="Key"' "$TMP/kno1" && ! grep -qE '<leaf n="[^"]*AKIA' "$TMP/kno1"; then ok "[RED] literal argument: a string literal is no leaf"; else no "[RED] literal argument: a string literal printed as a leaf (or no chain)"; fi
fi
# 30. a subject that mixes `.` and `::` takes the rightmost separator (CR 4476868701)
if run "$K" "$TMP/k30" "--for=pkg.N::Key2"; then
  if grep -qE '<chain of="Key2"' "$TMP/k30"; then ok "[RED] mixed separators: pkg.N::Key2 walks Key2"; else no "[RED] mixed separators: no chain for pkg.N::Key2"; fi
fi

# 12. well-formed
if command -v xmllint >/dev/null 2>&1; then
  for f in f1 f2 f3 f5 u1 q1 q3 q5 q6 m1 l1 l2 x1 x2 x5 x7 x9 x11 x12 x13 x15; do if xmllint --noout "$TMP/$f" 2>/dev/null; then ok "xmllint $f"; else no "xmllint $f"; fi; done
else echo "  SKIP  xmllint not installed (arm 12)"; fi

[ "$fail" -eq 0 ] && { echo "xfaliashopcheck: PASS"; exit 0; }
echo "xfaliashopcheck: FAIL"; exit 1
