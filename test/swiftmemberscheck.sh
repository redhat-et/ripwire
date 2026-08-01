#!/usr/bin/env bash
# swiftmemberscheck.sh — F2 + F5 gate: Swift init / subscript / deinit capture, and Swift
# local-binding call-edge attribution.
#
# F2 (init/subscript/deinit silently dropped): tree-sitter-swift models an initializer, a subscript,
#   and a deinitializer as *_declaration nodes whose "name" is a keyword TOKEN (there is no name
#   identifier), so before this fix the @definition patterns never captured them — even as PROTOCOL
#   REQUIREMENTS — and the map reported ambiguous=0 unresolved=0 (a silent miss). The fix adds
#   (init_declaration "init" @name) / (subscript_declaration "subscript" @name) /
#   (deinit_declaration "deinit" @name) @definition.method to queries/swift/tags.scm, mirroring the
#   C++ (operator_cast) @name pattern. This gate asserts each appears as a symbol, including the
#   protocol-requirement forms. It FAILS on HEAD (init/subscript/deinit absent).
#
# F5 (Swift call edges mis-attributed to a local binding): a Swift `let a = f()` / `var b = ...` inside
#   a function body parses to the SAME property_declaration node as a member property, so it was emitted
#   as a spurious top-level `var` symbol AND, being the nearest enclosing symbol above the body's call
#   sites, STOLE the enclosing function's call edges. The fix drops Swift function-local bindings
#   (a `statements` ancestor marks a local). This gate asserts (a) the local bindings are NOT symbols,
#   (b) the call edges attribute to the enclosing FUNCTION, not the last local binding.
#
# Fixtures are created under a self-contained mktemp dir (no shared fixture touched). Honors RIPWIRE_BIN.
#
# Usage:
#   test/swiftmemberscheck.sh
#   RIPWIRE_BIN=asan/ripwire test/swiftmemberscheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

# ── F2 fixture: init / subscript / deinit as concrete members AND protocol requirements ──────────────
mkdir -p "$TMP/f2"
cat > "$TMP/f2/members.swift" <<'EOF'
struct Vec {
    var x: Int
    init(x: Int) { self.x = x }
    init() { self.x = 0 }
    subscript(i: Int) -> Int { return x + i }
    func normalMethod() -> Int { return x }
}

class Res {
    init() {}
    deinit {}
    func work() -> Int { return 1 }
}

protocol Store {
    func get(_ k: String) -> Int
    init(capacity: Int)
    subscript(k: String) -> Int { get }
}
EOF

# ── F5 fixture: local let/var bindings + a caller that calls out of its body ─────────────────────────
mkdir -p "$TMP/f5"
cat > "$TMP/f5/calls.swift" <<'EOF'
func swiftFreeFunc() -> Int { return 1 }

struct SwiftStruct {
    var storedProp: Int = 0
    var computedProp: Int { return storedProp * 2 }
    func swiftMethod() -> Int { return 2 }
}

func swiftCaller() -> Int {
    let a = swiftFreeFunc()
    let s = SwiftStruct()
    let b = s.swiftMethod()
    return a + b
}
EOF

# ════════════════════════════════════════════════════════════════════════════════════════════════════
echo "=== F2: Swift init / subscript / deinit are captured as symbols ==="
# ════════════════════════════════════════════════════════════════════════════════════════════════════
F2_XML="$TMP/f2.xml"
"$BIN" "$TMP/f2" --no-cache > "$F2_XML" 2>/dev/null

command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$F2_XML" && ok "F2 map: passes xmllint --noout" || no "F2 map: xmllint failed"; }

# parse: name -> count of <s> symbols
# §P6.3 repin: the map now collapses identical-(kind,id) overload rows into ONE row carrying
# overloads="N" — so "how many init symbols were CAPTURED" is the sum of each row's overloads
# weight (absent = 1), not the raw row count. The extractor contract this gate guards is unchanged;
# only the serialized shape moved. Verified: 4 distinct inits emit <s n="init" overloads="4">.
python3 - "$F2_XML" <<'PYEOF' > "$TMP/f2_syms"
import sys, re
xml = open(sys.argv[1], encoding='utf-8').read()
from collections import Counter
c = Counter()
for m in re.finditer(r'<s t="(\w+)" n="([^"]*)"([^>]*)>', xml):
    ov = re.search(r'overloads="(\d+)"', m.group(3))
    c[(m.group(2), m.group(1))] += int(ov.group(1)) if ov else 1
for (n, t), k in sorted(c.items()):
    print("%s\t%s\t%d" % (n, t, k))
PYEOF

count_of(){ awk -F'\t' -v n="$1" '$1==n{s+=$3} END{print s+0}' "$TMP/f2_syms"; }

# init appears 3x: Vec.init(x:), Vec.init(), Res.init()   [protocol Store.init(capacity:) makes it 4]
N_INIT="$( count_of init )"
[ "$N_INIT" -ge 3 ] && ok "F2: 'init' captured as a symbol ($N_INIT occurrences: struct + class ctors)" \
                    || no "F2: expected >=3 'init' symbols (was silently dropped on HEAD), got $N_INIT"

# init as a PROTOCOL REQUIREMENT (Store.init(capacity:)) — parity with the func requirement Store.get
[ "$N_INIT" -ge 4 ] && ok "F2: protocol init requirement (Store.init) captured" \
                    || no "F2: protocol init requirement (Store.init) NOT captured (got $N_INIT init total, need >=4)"

# subscript appears 2x: Vec.subscript(i:) + protocol Store.subscript(k:) requirement
N_SUB="$( count_of subscript )"
[ "$N_SUB" -ge 2 ] && ok "F2: 'subscript' captured ($N_SUB: member + protocol requirement)" \
                   || no "F2: expected >=2 'subscript' symbols (dropped on HEAD), got $N_SUB"

# deinit appears 1x: Res.deinit
N_DEINIT="$( count_of deinit )"
[ "$N_DEINIT" -ge 1 ] && ok "F2: 'deinit' captured ($N_DEINIT)" \
                      || no "F2: expected >=1 'deinit' symbol (dropped on HEAD), got $N_DEINIT"

# init/subscript/deinit are tagged t="method" (mirroring C++ ctor/operator[])
awk -F'\t' '$1=="init"||$1=="subscript"||$1=="deinit"{ if($2!="method") bad=1 } END{ exit bad?1:0 }' "$TMP/f2_syms" \
    && ok "F2: init/subscript/deinit tagged t=\"method\"" \
    || no "F2: init/subscript/deinit NOT all tagged t=\"method\""

# honesty: with the fix there is nothing silently missing; header still clean.
"$BIN" "$TMP/f2" --no-cache 2>/dev/null | grep -q 'ambiguous=0 unresolved=0' \
    && ok "F2: header ambiguous=0 unresolved=0 (clean; no new mis-resolution)" \
    || no "F2: header no longer reports ambiguous=0 unresolved=0 (unexpected new edge noise)"

# ════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== F5: local let/var bindings are NOT symbols; call edges attribute to the function ==="
# ════════════════════════════════════════════════════════════════════════════════════════════════════
F5_XML="$TMP/f5.xml"
"$BIN" "$TMP/f5" --no-cache > "$F5_XML" 2>/dev/null

# the local bindings a / s / b must NOT appear as symbols
python3 - "$F5_XML" <<'PYEOF' > "$TMP/f5_check"
import sys, re
xml = open(sys.argv[1], encoding='utf-8').read()
names = re.findall(r'<s t="\w+" n="([^"]*)"', xml)
locals_present = [n for n in ("a", "s", "b") if n in names]
print("LOCALS_AS_SYMBOLS:" + ",".join(locals_present) if locals_present else "LOCALS_AS_SYMBOLS:NONE")
# which symbol owns the call edges? find the <s ...>...</s> block carrying <c n="swiftFreeFunc"/>
owner = "NONE"
for m in re.finditer(r'<s t="\w+" n="([^"]*)"[^>]*>(.*?)</s>', xml, re.S):
    if '<c n="swiftFreeFunc"' in m.group(2):
        owner = m.group(1)
print("SWIFTFREEFUNC_CALLER:" + owner)
# swiftMethod edge owner too
owner2 = "NONE"
for m in re.finditer(r'<s t="\w+" n="([^"]*)"[^>]*>(.*?)</s>', xml, re.S):
    if '<c n="swiftMethod"' in m.group(2):
        owner2 = m.group(1)
print("SWIFTMETHOD_CALLER:" + owner2)
PYEOF
cat "$TMP/f5_check"

grep -q "LOCALS_AS_SYMBOLS:NONE" "$TMP/f5_check" \
    && ok "F5: local bindings (a/s/b) are NOT emitted as symbols" \
    || no "F5: local bindings still emitted as symbols: $( grep LOCALS_AS_SYMBOLS "$TMP/f5_check" )"

grep -q "SWIFTFREEFUNC_CALLER:swiftCaller" "$TMP/f5_check" \
    && ok "F5: call edge -> swiftFreeFunc attributed to swiftCaller (not a local binding)" \
    || no "F5: swiftFreeFunc call edge mis-attributed: $( grep SWIFTFREEFUNC_CALLER "$TMP/f5_check" )"

grep -q "SWIFTMETHOD_CALLER:swiftCaller" "$TMP/f5_check" \
    && ok "F5: call edge -> swiftMethod attributed to swiftCaller (not a local binding)" \
    || no "F5: swiftMethod call edge mis-attributed: $( grep SWIFTMETHOD_CALLER "$TMP/f5_check" )"

# real member properties (stored + computed) must still survive — the fix must not over-drop
python3 - "$F5_XML" <<'PYEOF' > "$TMP/f5_members"
import sys, re
xml = open(sys.argv[1], encoding='utf-8').read()
names = re.findall(r'<s t="\w+" n="([^"]*)"', xml)
print("STORED:%s COMPUTED:%s" % ("storedProp" in names, "computedProp" in names))
PYEOF
grep -q "STORED:True COMPUTED:True" "$TMP/f5_members" \
    && ok "F5: real member properties (stored + computed) still captured (no over-drop)" \
    || no "F5: over-dropped real member properties: $( cat "$TMP/f5_members" )"

# find_referencing_symbols swiftFreeFunc must now return swiftCaller (the whole point of F5)
REFS="$( "$BIN" "$TMP/f5" --no-cache --callers=swiftFreeFunc 2>/dev/null )"
echo "$REFS" | grep -q 'n="swiftCaller"' \
    && ok "F5: --callers=swiftFreeFunc reports swiftCaller" \
    || no "F5: --callers=swiftFreeFunc did not report swiftCaller: $REFS"

# ── determinism ─────────────────────────────────────────────────────────────────────────────────────
echo
"$BIN" "$TMP/f2" --no-cache > "$TMP/det_a" 2>/dev/null
"$BIN" "$TMP/f2" --no-cache > "$TMP/det_b" 2>/dev/null
diff -q "$TMP/det_a" "$TMP/det_b" >/dev/null \
    && ok "determinism: F2 map byte-identical across two cold runs" \
    || no "determinism: F2 map differs across runs"

# warm == cold: default (cached) run must equal the --no-cache run for stable ids
"$BIN" "$TMP/f2" --no-cache > "$TMP/cold" 2>/dev/null
"$BIN" "$TMP/f2"            > /dev/null 2>&1   # warm the cache
"$BIN" "$TMP/f2"            > "$TMP/warm" 2>/dev/null
diff -q "$TMP/cold" "$TMP/warm" >/dev/null \
    && ok "determinism: warm == cold (new symbols get stable ids)" \
    || no "determinism: warm != cold"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
