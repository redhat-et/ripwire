#!/usr/bin/env bash
# qualnamecheck.sh — QUALNAME-1: a member symbol row names its owner, n="Owner<sep>name", from the STORED scope (src/memberowner.h).
#
# THE DEFECT. --callers/--callees/--impact rows printed a member bare (<s t="method" n="run"/>: three owners of `run` read alike),
# a --path hop printed `Builder.Build` where C++ spells `Builder::Build`, and a <d> signature row split the name over two
# attributes (n="render" sc="CmdRenderer") that a reader had to recombine.
#
# THE CONTRACT. A row whose definition is a member — its stored scope's last segment is a class, struct, interface, named type or
# module the index defines in the row's language — prints n="Scope<sep>name" with the language's separator (langfacts.h
# memberSeparator: `::` C/C++/Rust, `#` Ruby, `.` elsewhere; PHP methods store no scope, so none prints); a <d> row then drops sc=
# (folded, lossless). A printed scope is a claim, so it is exact or bare: a type row, a free function, a C++ namespace-scope function
# (unless a class of the same name is indexed: the owner test is name-keyed), a function-local def (a closure), an EXTENT-SUSPECT
# symbol (a free function an ERROR-recovered struct swallowed) and a language whose defs carry no scope (Java) stay bare; a TS/JS
# method names the class whose body holds it (lane js-def-naming, memberowner.h). The legend clause rides only where a row carries an owner.
#
# ARMS
#   (A) red-first, per language: callees/callers/path/sigs rows carry the owner (Py, Go, Rust, C++, Ruby).
#   (B) floor: Java members stay bare (no scope stored — QN2); a TS member names its enclosing class (js-def-naming).
#   (C) T1: a Python closure inside a method stays bare (two depths); a type row is never Owner.Owner; free functions stay bare; a
#       C++ namespace-scope function keeps n= bare and sc="ns".
#   (D) clickable: every qualified name printed in (A) resolves through --callers (defs>=1).
#   (E) present-only legend: the member-owner clause rides a --callers answer with an owner, not one without.
#   (F) JSON keys stable: --callers --json keeps "n" bare.
#   (G) the composed id p::n of a folded row (path::Owner.name / path::Owner#name) resolves; a wrong owner does not.
#   (H) honesty: a free function an ERROR-recovered struct swallowed (test/extentfix/leak.cpp) prints bare, never IndiaError::clampQuantity.
#
# Usage: test/qualnamecheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "qualnamecheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

mkdir -p "$TMP/py" "$TMP/ts" "$TMP/go" "$TMP/rs" "$TMP/cpp" "$TMP/java" "$TMP/rb" "$TMP/free"
cat > "$TMP/py/m.py" <<'EOF'
class Pattern:
    def __init__(self, s):
        self.s = s
    def match_chunk(self, x):
        def helper(y):
            def inner_helper(z):
                return z
            return inner_helper(y) + 1
        return helper(x) + leaf_fn(x)

def leaf_fn(v):
    return v

def driver():
    p = Pattern("a")
    return p.match_chunk(2)
EOF
cat > "$TMP/ts/m.ts" <<'EOF'
export class Pattern {
  matchChunk(x: number): number { return leafFn(x); }
}
export function leafFn(v: number): number { return v; }
export function driver(): number { const p = new Pattern(); return p.matchChunk(2); }
EOF
cat > "$TMP/go/m.go" <<'EOF'
package m

type Pattern struct{ s string }

func (p *Pattern) MatchChunk(x int) int { return LeafFn(x) }

func LeafFn(v int) int { return v }

func Driver() int { p := &Pattern{}; return p.MatchChunk(2) }
EOF
cat > "$TMP/rs/m.rs" <<'EOF'
pub struct Builder { n: i32 }
impl Builder {
    pub fn new() -> Builder { Builder { n: 0 } }
    pub fn build(&self, x: i32) -> i32 { leaf_fn(x) }
}
pub fn leaf_fn(v: i32) -> i32 { v }
pub fn driver() -> i32 { let b = Builder::new(); b.build(2) }
EOF
cat > "$TMP/cpp/m.cpp" <<'EOF'
namespace ns {
int nsFree( int v ) { return v; }
}
class Builder {
public:
    Builder() {}
    int Build( int x );
};
int Builder::Build( int x ) { return ns::nsFree( x ); }
int leafFree( int v ) { return v; }
int driver() { Builder b; return b.Build( 2 ) + leafFree( 1 ); }
EOF
cat > "$TMP/java/M.java" <<'EOF'
public class M {
    public int matchChunk(int x) { return leaf(x); }
    static int leaf(int v) { return v; }
    static int driver() { return new M().matchChunk(2); }
}
EOF
cat > "$TMP/rb/m.rb" <<'EOF'
module Rake
  class Application
    def run
      top_level
    end
    def top_level
      1
    end
  end
end
def driver
  Rake::Application.new.run
end
EOF
cat > "$TMP/free/f.py" <<'EOF'
def leaf_fn(v):
    return v

def driver():
    return leaf_fn(1)
EOF

run(){ local d="$1"; shift; ( cd "$d" || exit 1; "$BIN" "$d" --no-cache --legend=compact "$@" 2>/dev/null ); }
rows(){ grep -oE '<s t="[a-z]+" n="[^"]*"' | sed -E 's/.* n="([^"]*)"/\1/' | sort -u | tr '\n' ' '; }
has(){ case " $2 " in *" $3 "*) ok "$1: $3";; *) no "$1: expected $3 in [$2]";; esac; }
hasnt(){ case " $2 " in *" $3 "*) no "$1: unexpected $3 in [$2]";; *) ok "$1: no $3";; esac; }

echo "(A) red-first: member rows carry the owner, per language"
r=$( run "$TMP/py" --callees=driver | rows );        has "py callees" "$r" "Pattern.match_chunk"
r=$( run "$TMP/py" --callers=leaf_fn | rows );       has "py callers" "$r" "Pattern.match_chunk"
r=$( run "$TMP/go" --callers=LeafFn | rows );        has "go callers" "$r" "Pattern.MatchChunk"
r=$( run "$TMP/rs" --callees=driver | rows );        has "rust callees" "$r" "Builder::build"; has "rust callees" "$r" "Builder::new"
r=$( run "$TMP/rs" --path=driver,leaf_fn | rows );   has "rust path hop" "$r" "Builder::build"
r=$( run "$TMP/cpp" --callees=driver | rows );       has "c++ callees" "$r" "Builder::Build"
r=$( run "$TMP/rb" --callers=top_level | rows );     has "ruby callers" "$r" "Application#run"
r=$( run "$TMP/rb" --path=driver,top_level | rows ); has "ruby path hop" "$r" "Application#top_level"
r=$( run "$TMP/rs" --impact=leaf_fn | rows );        has "rust impact" "$r" "Builder::build"
s=$( run "$TMP/py" --pack-signatures )
case "$s" in *'n="Pattern.match_chunk"'*) ok "py <d> folds sc= into n=";; *) no "py <d> row not folded";; esac
case "$s" in *'n="Pattern.match_chunk" sc='*) no "py <d> folded row still carries sc=";; *) ok "py <d> folded row drops sc=";; esac
s=$( run "$TMP/go" --pack-signatures )
case "$s" in *'n="Pattern.MatchChunk"'*) ok "go <d> folds";; *) no "go <d> row not folded";; esac

echo "(B) floor: no stored scope (Java), bare; TS by containment"
r=$( run "$TMP/ts" --callers=leafFn | rows );        has "ts callers" "$r" "Pattern.matchChunk"; hasnt "ts callers" "$r" "matchChunk"   # js-def-naming: by containment, no longer the bare floor
r=$( run "$TMP/java" --callers=leaf | rows );        has "java callers" "$r" "matchChunk"

echo "(C) T1 controls"
r=$( run "$TMP/py" --callees=match_chunk | rows );   has "py closure (callee)" "$r" "helper"; hasnt "py closure (callee)" "$r" "Pattern.helper"
r=$( run "$TMP/py" --callees=helper | rows );        has "py nested closure" "$r" "inner_helper"; hasnt "py nested closure" "$r" "Pattern.inner_helper"
s=$( run "$TMP/py" --pack-signatures )
# the negatives below read THIS run: first prove it ran and printed the bare closure rows a wrong fold would respell (an empty or
# crashed run would otherwise pass every "no Pattern.helper" arm — CHECKLIST 1/14)
case "$s" in *'n="helper" sc="Pattern"'*'n="inner_helper" sc="Pattern"'*) ok "py closure <d> rows are present, bare, with their sc=";; *) no "py closure <d> rows missing or already respelled — the closure negatives below would pass vacuously";; esac
case "$s" in *'n="Pattern.helper"'*|*'n="Pattern.inner_helper"'*) no "py closure <d> row claims the class";; *) ok "py closure <d> rows stay bare";; esac
case "$s" in *'<d l="1" n="Pattern" sc="Pattern"'*) ok "py type row is present (own sc=)";; *) no "py type row missing — the doubled-row negative would pass vacuously";; esac
case "$s" in *'n="Pattern.Pattern"'*) no "type row doubled";; *) ok "py type row not doubled";; esac
r=$( run "$TMP/py" --callers=leaf_fn | rows );       has "py free fn" "$r" "Pattern.match_chunk"; hasnt "py free fn" "$r" "Pattern.leaf_fn"
s=$( run "$TMP/cpp" --pack-signatures )
case "$s" in *'n="nsFree" sc="ns"'*) ok "c++ namespace fn bare, sc= kept";; *) no "c++ namespace fn not bare/sc=";; esac
case "$s" in *'n="ns::nsFree"'*) no "c++ namespace fn qualified";; *) ok "c++ namespace fn not qualified";; esac
case "$s" in *'<d l="4" n="Builder" sc="Builder"'*) ok "c++ class row unchanged (n bare, own sc)";; *) no "c++ class row changed";; esac
r=$( run "$TMP/cpp" --callers=leafFree | rows );     has "c++ free caller" "$r" "driver"

echo "(D) clickable: a printed qualified name resolves"
for pair in "py:Pattern.match_chunk" "go:Pattern.MatchChunk" "rs:Builder::build" "cpp:Builder::Build" "rb:Application#run"; do
  d="$TMP/${pair%%:*}"; q="${pair#*:}"
  out=$( run "$d" --callers="$q" ); defs=$( printf '%s' "$out" | grep -oE 'defs="[0-9]+"' | head -1 | grep -oE '[0-9]+' )
  if [ -n "$defs" ] && [ "$defs" -ge 1 ] 2>/dev/null; then ok "--callers=$q resolves (defs=$defs)"; else no "--callers=$q does not resolve"; fi
done

echo "(G) the composed id of a folded <d> row (p::n, sc= absent) resolves"
for pair in "py:m.py::Pattern.match_chunk" "go:m.go::Pattern.MatchChunk" "rs:m.rs::Builder::build" "rb:m.rb::Application#run"; do
  d="$TMP/${pair%%:*}"; q="${pair#*:}"
  out=$( run "$d" --callers="$q" ); defs=$( printf '%s' "$out" | grep -oE 'defs="[0-9]+"' | head -1 | grep -oE '[0-9]+' )
  if [ -n "$defs" ] && [ "$defs" -ge 1 ] 2>/dev/null; then ok "--callers=$q resolves (defs=$defs)"; else no "--callers=$q does not resolve"; fi
done
out=$( run "$TMP/py" --callers=m.py::Nope.match_chunk )
if [ -z "$out" ]; then no "a wrong owner in a composed id printed nothing — the refusal arm needs an answer to read"
else case "$out" in *'defs="'[1-9]*) no "a wrong owner resolves";; *) ok "a wrong owner in a composed id does not resolve";; esac; fi

echo "(E) present-only legend"
f=$( cd "$TMP/py" && "$BIN" "$TMP/py" --no-cache --legend=full --callers=leaf_fn 2>/dev/null )
case "$f" in *'n=Owner.name on a row'*) ok "clause rides a --callers answer with an owner";; *) no "clause missing where a row carries an owner";; esac
f=$( cd "$TMP/free" && "$BIN" "$TMP/free" --no-cache --legend=full --callers=leaf_fn 2>/dev/null )
[ -n "$f" ] || no "free-function --callers answer empty"
case "$f" in *'n=Owner.name on a row'*) no "clause rides an owner-free answer";; *) ok "clause absent from an owner-free answer";; esac
if command -v xmllint >/dev/null 2>&1; then
  if ( cd "$TMP/py" && "$BIN" "$TMP/py" --no-cache --legend=full --callers=leaf_fn 2>/dev/null ) | xmllint --noout - 2>/dev/null; then ok "full-legend answer parses"; else no "full-legend answer is not well-formed XML"; fi
else
  printf '  SKIP  (E) xmllint not installed\n'   # named, as forcallerhopcheck (X2) does: an absent tool is a SKIP line, never a silent pass
fi

echo "(F) --json keys stable"
j=$( cd "$TMP/py" && "$BIN" "$TMP/py" --no-cache --callers=leaf_fn --json 2>/dev/null )
case "$j" in *'"n":"match_chunk"'*) ok "json n stays bare";; *) no "json n changed: $j";; esac

echo "(H) an extent-suspect symbol prints bare (a free function under the struct that swallowed it)"
mkdir -p "$TMP/leak"
cp "$ROOT/test/extentfix/leak.cpp" "$TMP/leak/leak.cpp"
printf 'int clampQuantity(int quantity, int ceiling);\nint useClamp() { return clampQuantity(1, 2); }\n' > "$TMP/leak/caller.cpp"
r=$( run "$TMP/leak" --callees=useClamp | rows )
has   "leak: the swallowed free function is a callee" "$r" "clampQuantity"
hasnt "leak: not filed under the swallowing struct"    "$r" "IndiaError::clampQuantity"

if [ "$fail" -eq 0 ]; then echo "qualnamecheck: PASS"; exit 0; fi
echo "qualnamecheck: FAIL"; exit 1
