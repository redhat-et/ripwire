#!/usr/bin/env bash
# gokindcheck.sh — a Go named type's t= says what its written form IS, never a blanket "struct".
#
# THE DEFECT. queries/go/tags.scm captured every `type_spec` as @definition.type, and ingest_crawl.h defKind maps that
# capture to SymKind::Struct (the typedef/alias/enum bucket). So `type TestName string` and
# `type eventFormatterFunc func(...)` were labelled t="struct": a false claim on every surface that prints t=. And
# `type A = B` parses as `type_alias`, a node the pattern never matched, so an alias was not indexed at all.
#
# THE CONTRACT (src/model.h SymKind::NamedType/Alias/FuncType):
#   struct_type underlying -> t="struct"; interface_type -> t="iface"; function_type -> t="functype";
#   `type A = B` -> t="alias"; every other form (string, []T, map, chan, *T, [N]T, another named or qualified type,
#   a generic over a non-struct form) -> t="type". Generic and grouped `type ( … )` specs follow the same rule.
#   The three new kinds BEHAVE as Struct did (model.h isStructOrNamedType): a conversion `TestName( s )` keeps its
#   caller edge. Only Go is split; another language's typedef keeps t="struct" (a disclosed floor, arm F).
#
# ARMS
#   (A) positive: each non-struct form gets its own kind (type / functype / alias), standalone, generic and grouped.
#   (B) near-miss negatives: struct, generic struct, grouped struct, embedded-field struct, interface, grouped
#       interface keep t="struct"/t="iface"; a func declaration stays fn, a method on a defined type stays method,
#       a package var of func type stays var.
#   (C) behaviour kept: the conversion call is still an edge (--callers=TestName lists Convert).
#   (D) the cache round-trips the new kind bytes: a warm run equals the --no-cache run byte for byte.
#   (E) the legend defines the three kinds under --legend=full on a Go corpus; the graph query can select them.
#   (F) scope floor: a C typedef keeps t="struct" and its map carries NO named-type clause (byte-identity rule).
#   (H) the t=type legend clause is true of EVERY t=type row: `type Wrapped Pair` (a struct underneath) and
#       `type HF http.HandlerFunc` (a func underneath) are t="type" because the kind follows the WRITTEN form, so the
#       clause must say WRITTEN and must not claim the bare "not-a-struct" (red on the wording it replaced).
#   (K) GO-KIND-VETO: K1 [P] `local.Type()` names no in-tree `type Type struct`; K3 [G] a method namesake stays (via="name") beside a type one;
#       K2 [G] a conversion `types.Name( s )` through the module alias keeps its edge.
#   (G) cross_kind= on --callers counts the new kinds (a name that is a func in one file and a defined type in another)
#       without tripping callhierarchy.h's kind bound.
#
# Usage: test/gokindcheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

mkdir -p "$TMP/g" "$TMP/g2" "$TMP/c"
cat > "$TMP/g/go.mod" <<'EOF'
module example.com/kinds

go 1.22
EOF
cat > "$TMP/g/kinds.go" <<'EOF'
package kinds

type TestName string

type eventFormatterFunc func(event string) error

type Pair struct {
	A int
	B int
}

type Reader interface {
	Read(p []byte) (int, error)
}

type Alias = Pair

type List[T any] []T

type Set[K comparable] map[K]struct{}

type Box[T any] struct {
	v T
}

type (
	Count     int
	Handler   func()
	Lookup    map[string]int
	Events    chan string
	PairPtr   *Pair
	Names     []string
	Grid      [4]int
	Inner     struct{ X int }
	Closer    interface{ Close() error }
	OldName   = Count
	Wrapped   Pair
	Qualified ext.Thing
	HF        http.HandlerFunc
)

type Outer struct {
	Pair
	*Inner
	n TestName
}

var OnEvent func(string)

func (t TestName) Split() []string { return nil }

func (f eventFormatterFunc) Format(e string) error { return f(e) }

func Run() {}

func Convert(s string) TestName { return TestName(s) }
EOF

# The map rows, one "t n" pair per line, read off a run that must SUCCEED and produce rows (checklist 14).
MAP="$TMP/map.xml"
"$BIN" "$TMP/g" --no-cache > "$MAP" 2>"$TMP/map.err"; rc=$?
rows="$( grep -o '<s t="[^"]*" n="[^"]*"' "$MAP" | sed 's/<s t="\([^"]*\)" n="\([^"]*\)"/\1 \2/' )"
nrows="$( printf '%s\n' "$rows" | grep -c . )"
if [ "$rc" -ne 0 ] || [ "$nrows" -lt 25 ]; then
    no "(premise) the Go map ran (rc=$rc) and printed its rows ($nrows < 25): $( head -c 300 "$TMP/map.err" )"
    echo "FAIL"; exit 1
fi
ok "(premise) the Go map ran and printed $nrows rows"

expectKind(){   # $1 arm label, $2 kind, $3 name
    if printf '%s\n' "$rows" | grep -qx "$2 $3"; then
        ok "$1 $3 is t=\"$2\""
    else
        no "$1 $3 should be t=\"$2\"; the map says: $( printf '%s\n' "$rows" | grep " $3\$" | tr '\n' ';' )"
    fi
}

echo "(A) a non-struct named type says its form"
for n in TestName List Set Count Lookup Events PairPtr Names Grid Wrapped Qualified HF; do expectKind "(A)" type "$n"; done
for n in eventFormatterFunc Handler; do expectKind "(A)" functype "$n"; done
for n in Alias OldName; do expectKind "(A)" alias "$n"; done

echo "(B) near-miss negatives keep their kind"
for n in Pair Box Inner Outer; do expectKind "(B)" struct "$n"; done
for n in Reader Closer; do expectKind "(B)" iface "$n"; done
for n in Run Convert; do expectKind "(B)" fn "$n"; done
for n in Split Format; do expectKind "(B)" method "$n"; done
expectKind "(B)" var OnEvent
if printf '%s\n' "$rows" | grep -q '^struct \(TestName\|eventFormatterFunc\|List\|Count\|Handler\|Alias\)$'; then
    no "(B) a non-struct form is still labelled t=\"struct\""
else
    ok "(B) no non-struct form is labelled t=\"struct\""
fi

echo "(C) a conversion keeps its caller edge"
"$BIN" "$TMP/g" --no-cache --callers=TestName > "$TMP/callers.xml" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'count="1"' "$TMP/callers.xml" && grep -q '<s t="fn" n="Convert"' "$TMP/callers.xml"; then
    ok "(C) --callers=TestName lists the conversion's caller Convert (count=1)"
else
    no "(C) --callers=TestName rc=$rc: $( head -c 400 "$TMP/callers.xml" )"
fi

echo "(K) a selector call on a local never names a TYPE (GO-KIND-VETO)"
# terraform planDestroy `unmarkedPriorVal.Type()` (a cty.Value method, outside the tree) printed the in-tree `type Type struct`
# via="name": a selector reaches a type only as `pkg.T( v )`, a conversion through a module alias
mkdir -p "$TMP/gk/types" "$TMP/gk/wrap" "$TMP/gk/plan"
printf 'module example.com/gk\n\ngo 1.22\n' > "$TMP/gk/go.mod"
printf 'package types\n\ntype Type struct{ name string }\n\ntype Name string\n\ntype Kind struct{}\n' > "$TMP/gk/types/types.go"
printf 'package wrap\n\ntype Wrap struct{}\n\nfunc (Wrap) Kind() int { return 0 }\n' > "$TMP/gk/wrap/wrap.go"
cat > "$TMP/gk/plan/plan.go" <<'EOF'
package plan

import "example.com/gk/types"

type Value struct{}

func planDestroy(v Value) int {
	unmarked := v
	return unmarked.Type() + unmarked.Kind()
}

func convert(s string) types.Name {
	return types.Name(s)
}
EOF
"$BIN" "$TMP/gk" --no-cache --callees=planDestroy > "$TMP/gk1.xml" 2>&1; rc1=$?
if [ "$rc1" -eq 0 ] && grep -q 'of="planDestroy" defs="1"' "$TMP/gk1.xml" && ! grep -q 'n="Type" p="types/types.go' "$TMP/gk1.xml"; then
    ok "(K1) unmarked.Type() names no in-tree type Type"
else
    no "(K1) rc=$rc1: a selector call bound a type: $( sed 's/^<!--.*-->//' "$TMP/gk1.xml" | head -c 500 )"
fi
if grep -q '<s t="method" n="Wrap.Kind" p="wrap/wrap.go:5" via="name"/>' "$TMP/gk1.xml" && ! grep -q 'n="Kind" p="types/types.go' "$TMP/gk1.xml"; then
    ok "(K3) unmarked.Kind(): the method namesake Wrap.Kind stays, by name, and the type Kind is no row"
else
    no "(K3) the method namesake was dropped too: $( sed 's/^<!--.*-->//' "$TMP/gk1.xml" | head -c 500 )"
fi
"$BIN" "$TMP/gk" --no-cache --callees=convert > "$TMP/gk2.xml" 2>&1; rc2=$?
if [ "$rc2" -eq 0 ] && grep -q '<s t="type" n="Name" p="types/types.go:5"' "$TMP/gk2.xml"; then
    ok "(K2) the conversion types.Name( s ) through the module alias keeps its edge"
else
    no "(K2) rc=$rc2: the conversion lost its edge: $( sed 's/^<!--.*-->//' "$TMP/gk2.xml" | head -c 500 )"
fi

echo "(D) the cache round-trips the new kind bytes"
CACHE="$TMP/kinds.cache"   # an explicit per-run cache file, never the shared warm TMPDIR one (checklist 12)
"$BIN" "$TMP/g" --cache="$CACHE" > "$TMP/cold.xml" 2>/dev/null; c1=$?
"$BIN" "$TMP/g" --cache="$CACHE" > "$TMP/warm.xml" 2>/dev/null; c2=$?
if [ "$c1" -eq 0 ] && [ "$c2" -eq 0 ] && [ -s "$CACHE" ] && cmp -s "$MAP" "$TMP/warm.xml" && grep -q 't="functype"' "$TMP/warm.xml"; then
    ok "(D) cold and warm runs equal the --no-cache map byte for byte (t=\"functype\" survives the cache)"
else
    no "(D) cold rc=$c1 warm rc=$c2; warm differs from --no-cache: $( diff <( tr '>' '\n' < "$MAP" ) <( tr '>' '\n' < "$TMP/warm.xml" ) | head -5 )"
fi

echo "(E) the legend defines them; the graph query selects them"
"$BIN" "$TMP/g" --no-cache --legend=full > "$TMP/full.xml" 2>&1
if grep -q '<!-- t=type|alias|functype=' "$TMP/full.xml"; then
    ok "(E) --legend=full carries the type|alias|functype clause"
else
    no "(E) --legend=full has no type|alias|functype clause"
fi
"$BIN" "$TMP/g" --no-cache --graph-query='kind(all,functype)' > "$TMP/q.xml" 2>&1; rc=$?
qn="$( grep -o '<s [^>]*n="[^"]*"' "$TMP/q.xml" | sed 's/.* n="\([^"]*\)"/\1/' | LC_ALL=C sort | tr '\n' ' ' )"
if [ "$rc" -eq 0 ] && [ "$qn" = "Handler eventFormatterFunc " ]; then
    ok "(E) kind(all,functype) selects exactly Handler and eventFormatterFunc"
else
    no "(E) kind(all,functype) rc=$rc selected [$qn]: $( head -c 300 "$TMP/q.xml" )"
fi
"$BIN" "$TMP/g" --no-cache --graph-query='kind(all,struct)' > "$TMP/qs.xml" 2>&1; rc=$?
qs="$( grep -o '<s [^>]*n="[^"]*"' "$TMP/qs.xml" | sed 's/.* n="\([^"]*\)"/\1/' | LC_ALL=C sort | tr '\n' ' ' )"
if [ "$rc" -eq 0 ] && [ "$qs" = "Box Inner Outer Pair " ]; then
    ok "(E) kind(all,struct) selects exactly the four structs"
else
    no "(E) kind(all,struct) rc=$rc selected [$qs]"
fi

echo "(H) the t=type clause names the written form (a struct/func underneath still reads t=type)"
tline="$( grep -o '<!-- t=type|alias|functype=[^>]*-->' "$TMP/full.xml" )"
if [ -n "$tline" ] && printf '%s\n' "$tline" | grep -q 'type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal' \
   && printf '%s\n' "$tline" | grep -q 'type-W-Pair-too,whatever-Pair-is-underneath' \
   && ! printf '%s\n' "$tline" | grep -q 'type=a-defined-type-not-a-struct'; then
    ok "(H) the clause says the form is WRITTEN, naming type W Pair; Wrapped and HF (struct/func underneath) are the t=type rows it must stay true of"
else
    no "(H) the t=type clause is not qualified by the written form: [$tline]"
fi

echo "(F) scope floor: only Go is split"
cat > "$TMP/c/t.c" <<'EOF'
typedef int handle_t;
struct point { int x; int y; };
int use( handle_t h ) { return h; }
EOF
"$BIN" "$TMP/c" --no-cache --legend=full > "$TMP/c.xml" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q '<s t="struct" n="handle_t"' "$TMP/c.xml" && ! grep -q 't=type|alias|functype' "$TMP/c.xml"; then
    ok "(F) a C typedef keeps t=\"struct\" (disclosed floor) and the map carries no named-type clause"
else
    no "(F) rc=$rc; C typedef row / clause: $( grep -o '<s t="[^"]*" n="handle_t"' "$TMP/c.xml" ) $( grep -c 't=type|alias|functype' "$TMP/c.xml" )"
fi

echo "(G) cross_kind= counts a new kind"
cat > "$TMP/g2/go.mod" <<'EOF'
module example.com/mixed

go 1.22
EOF
mkdir -p "$TMP/g2/a" "$TMP/g2/b"
cat > "$TMP/g2/a/a.go" <<'EOF'
package a

type Mode string

func Pick() Mode { return Mode("x") }
EOF
cat > "$TMP/g2/b/b.go" <<'EOF'
package b

func Mode() int { return 1 }

func Call() int { return Mode() }
EOF
"$BIN" "$TMP/g2" --no-cache --callers=Mode > "$TMP/ck.xml" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'cross_kind="fn:1,type:1"' "$TMP/ck.xml"; then
    ok "(G) --callers=Mode says cross_kind=\"fn:1,type:1\""
else
    no "(G) rc=$rc: $( grep -o 'cross_kind="[^"]*"' "$TMP/ck.xml" ) $( grep -m1 -i 'fail\|expects' "$TMP/ck.xml" )"
fi

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "FAIL"; fi
exit "$fail"
