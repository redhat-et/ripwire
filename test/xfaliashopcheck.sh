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
  has "$TMP/f1" '<aliases total=' && ok "[RED] for alias: an <aliases> block" || no "[RED] for alias: no <aliases> block"
  has "$TMP/f1" '<h n="Ptr" sc="COW" t="alias"' && ok "[RED] for alias: hop 1 COW::Ptr (alias row)" || no "[RED] for alias: hop 1 COW::Ptr missing"
  grep -qE '<h n="immutable_ptr" t="cls" p="src/cow.h" l="2" d="2" via="alias"' "$TMP/f1" && ok "[RED] for alias: hop 2 immutable_ptr in cow.h, via=alias" || no "[RED] for alias: hop 2 immutable_ptr missing"
  grep -qE '<h n="IColumn" t="cls" [^>]*d="1" via="alias" arg="1" members="2" m="size,insert"' "$TMP/f1" && ok "[RED] for alias: the pointee IColumn with its members" || no "[RED] for alias: pointee IColumn row missing"
  has "$TMP/f1" '<h n="IColumn" t="cls" p="other/example.cpp"' && no "for alias: the example .cpp's own IColumn was bound" || ok "for alias: another translation unit's .cpp class is not bound (twin of the row above)"
  has "$TMP/f1" 'next="--uses=IColumn"' && ok "[RED] for alias: next= lists the users" || no "[RED] for alias: next= missing"
  has "$TMP/f1" 'via="alias" (reached through the alias' && ok "[RED] for alias: via=alias is legend-defined in the answer" || no "[RED] for alias: legend clause missing"
  has "$TMP/f1" '<leaf n="Derived"/>' && no "for alias: a deeper hop's template parameter is not followed" || ok "for alias: a deeper hop's template parameter is not followed (no Derived leaf)"
fi
# 1b. the same alias named inside a sentence (the route reads words; the alias rows print as literal lines): the block still walks it
if run "$C" "$TMP/f1s" "--for=definition of the type alias ColumnPtr"; then
  grep -qE '<chain of="ColumnPtr" p="src/icolumn.h"' "$TMP/f1s" && has "$TMP/f1s" '<h n="Ptr" sc="COW" t="alias"' && ok "[RED] sentence wording: the chain walks from the sentence's name" || no "[RED] sentence wording: no chain"
fi
# 2. alias of an alias: Columns -> ColumnPtr -> COW::Ptr -> immutable_ptr
if run "$C" "$TMP/f2" --for=Columns; then
  has "$TMP/f2" '<h n="ColumnPtr" sc="DB" t="alias"' && grep -qF '<h n="immutable_ptr" t="cls" p="src/cow.h" l="2" d="3"' "$TMP/f2" && ok "[RED] alias of an alias: walked to d=3" || no "[RED] alias of an alias: chain short"
fi
# 3. alias to a template instance outside the tree: std::shared_ptr is a leaf, the argument IColumn is followed
if run "$C" "$TMP/f3" --for=Shared; then
  has "$TMP/f3" '<leaf n="std::shared_ptr"/>' && ok "[RED] template instance: std::shared_ptr stays a leaf, disclosed" || no "[RED] template instance: no std leaf"
  grep -qE '<h n="IColumn" [^>]*arg="1"' "$TMP/f3" && ok "[RED] template instance: the argument IColumn is reached" || no "[RED] template instance: IColumn arg missing"
fi
# 4. an alias whose target is nowhere in the tree: leaves only, no definition row
if run "$C" "$TMP/f4" --for=External; then
  has "$TMP/f4" '<leaf n="Missing"/>' && has "$TMP/f4" '<leaf n="std::shared_ptr"/>' && ok "[RED] not in the tree: both spellings are leaves" || no "[RED] not in the tree: leaves missing"
  has "$TMP/f4" '<h ' && no "not in the tree: a definition row was invented" || ok "not in the tree: no <h> row (twin of arm 3)"
fi
# 5. a cycle ends the walk and says so
if run "$C" "$TMP/f5" --for=LoopA; then
  # on the element, never a bare attribute the legend also spells (fix round 1, M2: the legend matched a mutant's answer)
  grep -qE '<chain [^>]*cycle="1"' "$TMP/f5" && ok "[RED] cycle: cycle=1 on the chain element" || no "[RED] cycle: no cycle=1 on the chain"
fi
# 6. an alias in another namespace and file reaches DB::IColumn
if run "$C" "$TMP/f6" --for=ColumnRef; then
  grep -qE '<chain of="ColumnRef" p="other/elsewhere.h"' "$TMP/f6" && grep -qE '<h n="IColumn" t="cls" p="src/icolumn.h"' "$TMP/f6" && ok "[RED] other namespace/file: DB::IColumn reached" || no "[RED] other namespace/file: not reached"
fi
# 7. --uses on the target: the sites written through an alias are listed, via="alias" alias=, and the direct rows stay first
if run "$C" "$TMP/u1" --uses=IColumn; then
  grep -qE '<u role="type" p="src/use.cpp:4"[^>]* via="alias" alias="ColumnPtr"' "$TMP/u1" && ok "[RED] uses target: countRows (ColumnPtr) listed via=alias" || no "[RED] uses target: ColumnPtr site missing"
  grep -qE '<u role="type" p="src/use.cpp:6"[^>]* via="alias" alias="Columns"' "$TMP/u1" && ok "[RED] uses target: viaAlias (Columns, alias of an alias)" || no "[RED] uses target: Columns site missing"
  grep -qE 'via="alias" alias="Shared"' "$TMP/u1" && ok "[RED] uses target: Shared (template argument)" || no "[RED] uses target: Shared site missing"
  grep -qE 'via_alias="[1-9]' "$TMP/u1" && ok "[RED] uses target: via_alias= on the root" || no "[RED] uses target: via_alias= missing"
  has "$TMP/u1" 'via="alias" alias=A' && ok "[RED] uses target: legend defines via=alias" || no "[RED] uses target: legend clause missing"
  grep -qE '<u role="type" p="src/use.cpp:5" in_id="src/use.cpp::DB::fill"/>' "$TMP/u1" && ok "uses target: the direct row keeps its bytes" || no "uses target: the direct fill row changed"
  grep -qE 'alias="External"|alias="LoopA"' "$TMP/u1" && no "uses target: an alias that does not reach IColumn was listed" || ok "uses target: External / LoopA not listed (twin of the rows above)"
fi
# 8. ablation twin: RIPWIRE_NO_ALIAS_HOP restores the base answer
if ( cd "$C" && RIPWIRE_NO_ALIAS_HOP=1 "$BIN" . --no-cache --for=ColumnPtr ) >"$TMP/f1off" 2>/dev/null; then
  has "$TMP/f1off" '<aliases' && no "switch: RIPWIRE_NO_ALIAS_HOP left the block" || ok "switch: RIPWIRE_NO_ALIAS_HOP drops the block"
else no "switch: the run with RIPWIRE_NO_ALIAS_HOP failed"; fi
# 9. a token budget holds the block
if run "$C" "$TMP/f9" --for=ColumnPtr --token-budget=4000; then
  has "$TMP/f9" '<aliases held="budget" total="1"/>' && ok "[RED] budget: held marker with total=" || no "[RED] budget: no held marker"
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
    cmp -s "$TMP/n.on" "$TMP/n.off" && ok "alias-free byte-identical: $a" || no "alias-free answer moved: $a"
    has "$TMP/n.on" 'via="alias"' && no "alias-free: via=alias printed on $a" || ok "alias-free: no via=alias on $a"
  fi
done
# 11. languages whose alias rows record no target yet (TS `type`, Rust `type`): no block, no invented hop (the C++ arm above is the twin)
T="$TMP/ts"; mkdir -p "$T/src"
printf 'export interface Real { run(): void }\nexport type RealAlias = Real;\nexport function go(r: RealAlias) { r.run(); }\n' > "$T/src/a.ts"
if run "$T" "$TMP/t1" --for=RealAlias; then
  has "$TMP/t1" '<aliases' && no "TS type alias: a block without a recorded target" || ok "TS type alias: no block (no target recorded; card follow-on)"
fi
R="$TMP/rs"; mkdir -p "$R/src"
printf 'pub struct Real;\npub type RealAlias = Real;\npub fn go(_r: RealAlias) {}\n' > "$R/src/lib.rs"
if run "$R" "$TMP/r1" --for=RealAlias; then
  has "$TMP/r1" '<aliases' && no "Rust type alias: a block without a recorded target" || ok "Rust type alias: no block (no target recorded; card follow-on)"
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
  grep -qE '<u role="type" p="src/u.cpp:3" in_id="src/u.cpp::A::useA2" via="alias" alias="Ptr"/>' "$TMP/q1" && ok "namesake: A::useA2 is a proven use of Foo (positive twin)" || no "namesake: A::useA2 missing or hedged"
  grep -qE 'in_id="src/u.cpp::B::useB2" via="alias" alias="Ptr"/>' "$TMP/q1" && no "[RED] namesake: B::useB2 (B::Ptr names Bar) counted as a use of Foo" || ok "[RED] namesake: B::useB2 is not a proven use of Foo"
  grep -qE 'in_id="src/u.cpp::B::useB2" via="alias" alias="Ptr" hedge="name"/>' "$TMP/q1" && ok "[RED] namesake: B::useB2 listed hedge=name" || no "[RED] namesake: no hedged B::useB2 row"
  grep -qE '<uses [^>]*count="3"[^>]* alias_hedged="1"' "$TMP/q1" && ok "[RED] namesake: count= leaves the hedged row out, alias_hedged=1" || no "[RED] namesake: count=/alias_hedged= wrong"
  grep -qE '<uses [^>]* alias_depth_capped="1"' "$TMP/q1" && ok "[RED] depth cap: alias_depth_capped=1 on the uses root (D6..D1)" || no "[RED] depth cap: no alias_depth_capped on the root"
  grep -qE 'hedge="name"[^ ]*: the (alias )?site' "$TMP/q1" && ok "[RED] namesake: hedge= is legend-defined" || no "[RED] namesake: hedge= legend clause missing"
fi
if run "$Q" "$TMP/q2" --uses=Bar; then
  grep -qE 'in_id="src/u.cpp::B::useB2" via="alias" alias="Ptr"/>' "$TMP/q2" && ok "namesake: B::useB2 is a proven use of Bar (positive twin)" || no "namesake: B::useB2 missing under Bar"
  grep -qE 'in_id="src/u.cpp::A::useA2" via="alias" alias="Ptr"/>' "$TMP/q2" && no "[RED] namesake: A::useA2 counted as a use of Bar" || ok "[RED] namesake: A::useA2 is not a proven use of Bar"
  has "$TMP/q2" 'alias_depth_capped' && no "depth cap: alias_depth_capped printed without a cut" || ok "depth cap: no alias_depth_capped without a cut (twin)"
fi
# 14. a class qualifier: a class's scope is its own name, so the namespace is read off the braces
if run "$Q" "$TMP/q3" --for=WQ; then
  grep -qE '<h n="Widget" t="cls" p="src/a.h" l="4" d="1" via="alias" members="1" m="w2">' "$TMP/q3" && ok "[RED] qualifier: N2::Widget binds the N2 class, proven, its own member only" || no "[RED] qualifier: N2::Widget row wrong"
  grep -qE '<h n="Widget" [^>]*l="3"' "$TMP/q3" && no "[RED] qualifier: N1::Widget bound for N2::Widget" || ok "[RED] qualifier: N1::Widget not bound (a free function in N2 does not merge them)"
  has "$TMP/q3" '<leaf n="N2::Widget"/>' && no "qualifier: a false leaf" || ok "qualifier: no leaf for an in-tree class"
fi
if run "$Q" "$TMP/q4" --for=WP; then
  grep -qE '<h n="Widget" t="cls" p="src/a.h" l="3" [^>]*members="1" m="w1">' "$TMP/q4" && ! grep -qE '<h n="Widget" [^>]*l="4"' "$TMP/q4" && ok "[RED] unqualified: N1::WP = Widget binds N1::Widget only" || no "[RED] unqualified: WP bound the wrong Widget"
fi
# 15. cycle and depth on the element (the mutant arms: seen guard off, qualifier ignored)
if run "$Q" "$TMP/q5" --for=L1; then
  grep -qE '<chain of="L1" [^>]*cycle="1"' "$TMP/q5" && [ "$( grep -o '<h n="L2"' "$TMP/q5" | wc -l | tr -d ' ' )" = 1 ] && ok "[MUT] cycle: L1 -> L2 -> L3 stops once, cycle=1" || no "[MUT] cycle: L1 chain repeats or lacks cycle=1"
  grep -qE '<chain [^>]*depth_capped="1"' "$TMP/q5" && no "cycle: depth_capped on a 3-cycle" || ok "cycle: no depth_capped on a 3-cycle (twin)"
fi
if run "$Q" "$TMP/q6" --for=D1; then
  grep -qE '<chain of="D1" [^>]*depth_capped="1"' "$TMP/q6" && grep -qF '<h n="D5" t="alias" p="src/a.h" l="8" d="4"' "$TMP/q6" && ! has "$TMP/q6" '<h n="D6"' && ok "[MUT] depth: D1..D5 at d=4, depth_capped=1, D6 not walked" || no "[MUT] depth: cap wrong"
fi
# 16. an unreadable chain: the bind is hedged, never a plain leaf (S1)
M="$TMP/mac"; mkdir -p "$M/src"
# braces that do not balance (`#if` / `#else` each open the namespace): the chain is unknown; a scope-like macro alone on its
# line (DECL_PTR) is not enough to drop it (the twin in $Q above has none, arm 14)
{ printf '#define DECL_PTR(T) typedef T T##Hold;\nDECL_PTR(Foo)\n#if defined(OLD)\nnamespace Z {\n#else\nnamespace Z {\n#endif\n}\n'; cat "$Q/src/a.h"; } > "$M/src/a.h"
cp "$Q/src/u.cpp" "$M/src/u.cpp"
if run "$M" "$TMP/m1" --for=WQ; then
  grep -qE '<h n="Widget" [^>]*bound="name"' "$TMP/m1" && ok "[RED] unknown chain: N2::Widget bound by name, hedged" || no "[RED] unknown chain: no bound=name row"
  has "$TMP/m1" '<leaf n="N2::Widget"/>' && no "unknown chain: a false leaf" || ok "unknown chain: no leaf for an in-tree class (twin)"
  has "$TMP/m1" 'bound="name": the written' && ok "[RED] unknown chain: bound= is legend-defined" || no "[RED] unknown chain: bound= legend clause missing"
fi
# 16b. positive twin: a scope-like macro alone on its line with balanced braces keeps the chain, so N2::Widget is proven
P="$TMP/mac2"; mkdir -p "$P/src"
{ printf '#define DECL_PTR(T) typedef T T##Hold;\nDECL_PTR(Foo)\n'; cat "$Q/src/a.h"; } > "$P/src/a.h"; cp "$Q/src/u.cpp" "$P/src/u.cpp"
if run "$P" "$TMP/m2" --for=WQ; then
  grep -qE '<h n="Widget" t="cls" p="src/a.h" l="6" d="1" via="alias" members="1" m="w2">' "$TMP/m2" && ok "[RED] balanced braces beside a macro: N2::Widget proven" || no "[RED] balanced braces beside a macro: not proven"
fi
# 17. the block's legend names only what it prints (S5) and --max-tokens sheds m= first, disclosed
if run "$C" "$TMP/l1" --for=ColumnPtr; then
  has "$TMP/l1" 'cycle="1": a definition' && no "[RED] legend: a cycle clause without a cycle" || ok "[RED] legend: no cycle clause on an acyclic chain"
  has "$TMP/l1" 'unread="1": its file' && no "[RED] legend: an unread clause with nothing unread" || ok "[RED] legend: no unread clause"
  has "$TMP/f5" 'cycle="1": a definition' && ok "legend: the cycle clause rides when a chain has one (twin)" || no "legend: cycle clause missing on the cyclic chain"
fi
if run "$C" "$TMP/l2" --for=ColumnPtr --max-tokens=40000; then
  grep -qE '<aliases [^>]*shed="m"' "$TMP/l2" && ! grep -qE '<h [^>]* m="' "$TMP/l2" && grep -qE '<h n="IColumn" [^>]*members="2"' "$TMP/l2" && ok "[RED] max-tokens: m= shed, members= kept, shed=m disclosed" || no "[RED] max-tokens: shed wrong"
  has "$TMP/l2" 'shed=: a max-tokens' && ok "[RED] max-tokens: shed= legend-defined" || no "[RED] max-tokens: shed= legend missing"
fi

# 12. well-formed
if command -v xmllint >/dev/null 2>&1; then
  for f in f1 f2 f3 f5 u1 q1 q3 q5 q6 m1 l1 l2; do xmllint --noout "$TMP/$f" 2>/dev/null && ok "xmllint $f" || no "xmllint $f"; done
else echo "  SKIP  xmllint not installed (arm 12)"; fi

[ "$fail" -eq 0 ] && { echo "xfaliashopcheck: PASS"; exit 0; }
echo "xfaliashopcheck: FAIL"; exit 1
