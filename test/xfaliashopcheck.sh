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
  has "$TMP/f5" 'cycle="1"' && ok "[RED] cycle: cycle=1 disclosed" || no "[RED] cycle: no cycle=1"
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
# 12. well-formed
if command -v xmllint >/dev/null 2>&1; then
  for f in f1 f2 f3 f5 u1; do xmllint --noout "$TMP/$f" 2>/dev/null && ok "xmllint $f" || no "xmllint $f"; done
else echo "  SKIP  xmllint not installed (arm 12)"; fi

[ "$fail" -eq 0 ] && { echo "xfaliashopcheck: PASS"; exit 0; }
echo "xfaliashopcheck: FAIL"; exit 1
