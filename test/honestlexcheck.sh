#!/usr/bin/env bash
# honestlexcheck.sh — two honesty fixes in two lexical emitters (lane honest-lex, ideas-32b cards #1 and #2).
#
# (A) WHEREIS-DEF. --whereis labels HEAD rows with the parsed index when the index defines the name
#     (head_labels="index"); otherwise a LEXICAL shape test labels them (head_labels="lexical"). That test took a
#     declaration word ANYWHERE earlier on the line, so a comment (`// class X …`), a help string, a doc line and every
#     `struct T *data` local read kind="def" (Stage 0: 241 false def rows over 30 cells). Now the marker must sit
#     directly before the name, a comment line / a name after a comment opener / a name inside a string is never a
#     definition, `#define NAME` is, and head_defs="0" says when the index defines no symbol of the name at all.
# (B) GREP-META. A literal --grep whose pattern reads as a regex (`a|b`, `x\.y`, `.*` inside, `^…`, `[^…]`) answered a
#     confident zero (or a narrowed list) with next= --for. Now the root carries pattern_meta= and next= is the regex
#     verb on the pattern. Folded in: one <hit> row per LINE with occ=N (hits= counts lines). MCP twin keys too.
#
# Fixture: a throwaway git repo under $TMP (every name is hlx-prefixed, so no other gate's zero-hit word is touched).
# The lexical path is forced with --exclude=hlxfix/ (the index then knows no def of these names), the documented way
# to reach it on a clean tree (a dirty file keeps the index labels).
#
# RED-FIRST: recorded against base 004b4c6ba — every (A) arm that asserts a ref on a marker/comment/string line,
# the #define-object arm, head_defs, and every (B) arm but the plain-literal negatives FAIL there.
#
# Usage:  test/honestlexcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire test/honestlexcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
echo "honestlexcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; F="$R/hlxfix"; mkdir -p "$F"
cat > "$F/c.c" <<'EOF'
// class hlxComment is a comment, not a definition
#define HLX_OBJ 1
#define HLX_FN(x) ((x)+1)
#ifndef HLX_OBJ
struct hlx_tag {
	int n;
};
static struct hlx_tag *hlx_local;
typedef unsigned long hlx_key;
typedef void (*hlx_cb)(hlx_key, int);
const char *hlx_s = "struct hlx_str is in a string";
int hlx_fn2( int a ) {
	return a; // struct hlx_trail is a trailing comment
}
#  define HLX_SPACED 2
EOF
cat > "$F/p.py" <<'EOF'
# def hlx_pycomment(): commented out
class HlxPy(Base):
def hlx_run( hlx_param ):
    """class HlxDoc is a docstring"""
x = 1  # class HlxHashTrail trailing
    yield HlxYield("a", "b")
EOF
cat > "$F/r.rs" <<'EOF'
#[inline] fn hlx_hot() {}
impl<'a> Display for HlxType<'a> {}
EOF
cat > "$F/g.go" <<'EOF'
func (r *HlxRecv) HlxMethod() int { return 1 }
EOF
cat > "$F/t.ts" <<'EOF'
export class HlxClass extends HlxBase {}
import type { HlxImported } from './x'
throw new HlxThrown()
EOF
cat > "$F/u.cpp" <<'EOF'
using std::hlx_using;
using HlxAlias = int;
using namespace hlx_ns;
class RW_API HlxExported {
template <class T> T hlx_tpl( T a ) {
EOF
cat > "$F/d.md" <<'EOF'
The `class HlxTick` spelling sits in backticks.
- (see above): hlxBullet is a markdown bullet
EOF
cat > "$F/m.m" <<'EOF'
- (void) hlxObjc {
EOF
cat > "$R/keep.c" <<'EOF'
int hlx_keep( void ) { return 0; }
int hlx_indexed( int a ) { return a; }
// hlx_indexed is mentioned in a comment
EOF
( cd "$R" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm fixture ) || { echo "fixture git failed"; exit 2; }

# kind of the HEAD row at FILE:LINE in a whereis answer (or MISSING), plus the root's head_labels/head_defs
wh() { ( cd "$R" && "$BIN" "$R" --no-cache "$@" --whereis-listing=all --limit=200 2>/dev/null ); }
kind_at() { python3 -c '
import re,sys
s=sys.stdin.read(); p,l=sys.argv[1],sys.argv[2]
m=[k for (pp,ll,k) in re.findall(r"<hit ref=\"HEAD\"[^>]*? p=\"([^\"]*)\" l=\"(\d+)\" kind=\"(\w+)\"",s) if pp==p and ll==l]
print(m[0] if m else "MISSING")' "$1" "$2"; }
arm() {   # arm LABEL SYM FILE LINE WANT
    local out k; out="$( wh --exclude=hlxfix/ --whereis="$2" )"
    k="$( printf '%s' "$out" | kind_at "$3" "$4" )"
    if [ "$k" = "$5" ]; then ok "$1 ($2 at $3:$4 kind=$k)"; else no "$1 ($2 at $3:$4: kind=$k, want $5)"; fi
}

echo "── (A) lexical definition shape (head_labels=lexical forced) ──"
arm "A1 a comment line naming a declaration word is no definition" hlxComment hlxfix/c.c 1 ref
arm "A2 #define NAME (object-like) is a definition"                HLX_OBJ hlxfix/c.c 2 def
arm "A3 #define NAME( (function-like) is a definition"             HLX_FN hlxfix/c.c 3 def
arm "A4 #ifndef NAME is no definition (a preprocessor test)"       HLX_OBJ hlxfix/c.c 4 ref
arm "A5 struct NAME { is a definition"                            hlx_tag hlxfix/c.c 5 def
arm "A6 struct NAME *local uses the tag, defines nothing"          hlx_tag hlxfix/c.c 8 ref
arm "A7 typedef's last declarator is a definition"                hlx_key hlxfix/c.c 9 def
arm "A8 a type a typedef only uses is no definition"              hlx_key hlxfix/c.c 10 ref
arm "A9 a function-pointer typedef (*NAME) is a definition"       hlx_cb hlxfix/c.c 10 def
arm "A10 a name inside a string literal is no definition"         hlx_str hlxfix/c.c 11 ref
arm "A11 a C-family signature stays a definition"                 hlx_fn2 hlxfix/c.c 12 def
arm "A12 a name after a trailing // comment is no definition"     hlx_trail hlxfix/c.c 13 ref
arm "A13 '#  define NAME' (spaces after #) is a definition"       HLX_SPACED hlxfix/c.c 15 def
arm "A14 a Python '# def …' comment is no definition"             hlx_pycomment hlxfix/p.py 1 ref
arm "A15 class NAME(Base): is a definition"                       HlxPy hlxfix/p.py 2 def
arm "A16 def NAME( is a definition"                               hlx_run hlxfix/p.py 3 def
arm "A17 a parameter after def is no definition"                  hlx_param hlxfix/p.py 3 ref
arm "A18 a docstring line is no definition"                       HlxDoc hlxfix/p.py 4 ref
arm "A19 a name after a trailing # comment is no definition"      HlxHashTrail hlxfix/p.py 5 ref
arm "A20 a Rust #[attr] line still opens a definition"            hlx_hot hlxfix/r.rs 1 def
arm "A21 impl<T> Trait for NAME implements, defines nothing"     HlxType hlxfix/r.rs 2 ref
arm "A22 a Go method after its receiver is a definition"          HlxMethod hlxfix/g.go 1 def
arm "A23 a Go receiver type is no definition"                     HlxRecv hlxfix/g.go 1 ref
arm "A24 class NAME extends … is a definition"                    HlxClass hlxfix/t.ts 1 def
arm "A25 the extended base is no definition"                      HlxBase hlxfix/t.ts 1 ref
arm "A26 an imported type is no definition"                       HlxImported hlxfix/t.ts 2 ref
arm "A26b throw new NAME() is a call, no definition"              HlxThrown hlxfix/t.ts 3 ref
arm "A19b yield NAME( … ) is a call, no definition"                HlxYield hlxfix/p.py 6 ref
arm "A27 a using-declaration is no definition"                    hlx_using hlxfix/u.cpp 1 ref
arm "A28 a using alias is a definition"                           HlxAlias hlxfix/u.cpp 2 def
arm "A29 using namespace NAME is no definition"                   hlx_ns hlxfix/u.cpp 3 ref
arm "A30 class EXPORT_MACRO NAME { is a definition"               HlxExported hlxfix/u.cpp 4 def
arm "A31 template<…> RetType NAME( is a definition"               hlx_tpl hlxfix/u.cpp 5 def
arm "A32 a name in markdown backticks is no definition"           HlxTick hlxfix/d.md 1 ref
arm "A33 a markdown bullet '- (x) NAME' is no ObjC method"        hlxBullet hlxfix/d.md 2 ref
arm "A34 an ObjC method '- (ret) NAME' is a definition"           hlxObjc hlxfix/m.m 1 def

echo "── (A) head_defs ──"
o="$( wh --whereis=hlxComment )"
if printf '%s' "$o" | grep -q 'head_labels="lexical" head_defs="0"'; then ok "H1 no index def of the name → head_labels=lexical head_defs=0"
else no "H1 head_defs=0 missing: $( printf '%s' "$o" | grep -o '<whereis [^>]*>' )"; fi
o="$( wh --whereis=hlx_indexed )"
if printf '%s' "$o" | grep -q 'head_labels="index"' && ! printf '%s' "$o" | grep -q 'head_defs='; then
    ok "H2 an indexed def → head_labels=index, no head_defs"
else no "H2 indexed name: $( printf '%s' "$o" | grep -o '<whereis [^>]*>' )"; fi
if [ "$( printf '%s' "$o" | kind_at keep.c 3 )" = ref ]; then ok "H3 the index labels a comment mention of an indexed name ref"; else no "H3 keep.c:3 not ref"; fi
o="$( wh --whereis=hlxComment )"
if printf '%s' "$o" | grep -q 'head_defs=0: '; then ok "H4 the default (compact) legend defines head_defs"; else no "H4 head_defs undefined in the legend"; fi
o="$( wh --whereis=hlxComment --legend=full )"
if printf '%s' "$o" | grep -q 'head_defs="0" beside it'; then ok "H5 the full legend defines head_defs"; else no "H5 head_defs undefined in the full legend"; fi

echo "── (B) grep: regex-shaped literals ──"
cat > "$R/b.c" <<'EOF'
int hlxa = 1;
int hlxb = hlxa + hlxa;
/* see hlxa.c and java.util.* || here */
EOF
printf 'hlxq hlxq\n' > "$R/q.scm"
g() { ( cd "$R" && "$BIN" "$R" --no-cache "$@" 2>/dev/null ); }
root() { grep -o '<grep [^>]*>' | head -1; }
o="$( g --grep='hlxa|hlxb' | root )"
if printf '%s' "$o" | grep -q 'pattern_meta="|"'; then ok "B1 a|b literal → pattern_meta=|"; else no "B1 $o"; fi
if printf '%s' "$o" | grep -q "next=\"--regex=&apos;hlxa|hlxb&apos;\""; then ok "B2 its next= is the regex verb on the pattern"; else no "B2 $o"; fi
o="$( g --regex='hlxa|hlxb' | root )"
if printf '%s' "$o" | grep -q 'pattern_meta='; then no "B3 a regex answer carries pattern_meta: $o"; else ok "B3 a --regex answer carries no pattern_meta"; fi
if printf '%s' "$o" | grep -q 'hits="2"'; then ok "B4 the named regex finds the two lines"; else no "B4 $o"; fi
o="$( g --grep='hlxa.c' | root )"
if printf '%s' "$o" | grep -q 'pattern_meta='; then no "B5 a lone literal dot is meta: $o"; else ok "B5 a lone '.' (hlxa.c) is a literal: no pattern_meta"; fi
if printf '%s' "$o" | grep -q 'next="--at='; then ok "B6 …and keeps the --at next="; else no "B6 $o"; fi
o="$( g --grep='hlxa\.c' | root )"
if printf '%s' "$o" | grep -q 'pattern_meta="\\"'; then ok "B7 a backslash escape → pattern_meta=\\"; else no "B7 $o"; fi
o="$( g --grep='||' | root )"
if printf '%s' "$o" | grep -q 'pattern_meta='; then no "B8 '||' read as alternation: $o"; else ok "B8 '||' (an operator) is no alternation"; fi
o="$( g --grep='java.util.*' | root )"
if printf '%s' "$o" | grep -q 'pattern_meta='; then no "B9 a trailing .* read as meta: $o"; else ok "B9 a trailing .* (java.util.*) stays literal"; fi
o="$( g --grep='hlxa.*hlxa' | root )"
if printf '%s' "$o" | grep -qF 'pattern_meta=".*"'; then ok "B10 .* inside the pattern → pattern_meta=.*"; else no "B10 $o"; fi
o="$( g --grep='hlxa\|hlxb' | root )"
if printf '%s' "$o" | grep -q "next=\"--regex=&apos;hlxa|hlxb&apos;\""; then ok "B11 basic-grep a\\|b → next= the ERE a|b"; else no "B11 $o"; fi
o="$( g --grep='[^h]lxa' | root )"
if printf '%s' "$o" | grep -q 'pattern_meta="\[\]"'; then ok "B12 a [^…] class → pattern_meta=[]"; else no "B12 $o"; fi
o="$( g --grep='a[0]' | root )"
if printf '%s' "$o" | grep -q 'pattern_meta='; then no "B13 an index a[0] read as a class: $o"; else ok "B13 a[0] (an index) is no bracket class"; fi
o="$( g --grep='^hlxb' | root )"
if printf '%s' "$o" | grep -q 'pattern_meta="^\$"'; then ok "B14 a leading ^ → pattern_meta=^\$"; else no "B14 $o"; fi
# FIX ROUND 2 (review N2): ordinary literals that LOOK like regex syntax must keep their --at hop; unambiguous regex keeps the meta.
printf 'y = hlxidx[i-1] + hlxidx[i-1];\nz = hlxgrid[0][1-2];\nv.hlxuser$.subscribe();\n"hlxver": "^1.2.3"\nsee [^1] for hlxnote\n' > "$R/n.c"
for pair in 'B23 a subscript hlxidx[i-1]|hlxidx[i-1]' 'B24 a chained subscript hlxgrid[0][1-2]|hlxgrid[0][1-2]' 'B25 an RxJS suffix hlxuser$|hlxuser$' \
            'B26 a semver ^1.2.3|^1.2.3' 'B27 a footnote [^1]|[^1]'; do
    lab="${pair%%|*}"; pat="${pair#*|}"
    o="$( g --grep="$pat" --grep-in=any | root )"
    if printf '%s' "$o" | grep -q 'pattern_meta='; then no "$lab carries a false pattern_meta: $o"
    elif printf '%s' "$o" | grep -q 'next="--at='; then ok "$lab: no pattern_meta, keeps next= --at"
    else no "$lab: no --at next=: $o"; fi
done
for pair in 'B28 ^\s*int (escape + anchor)|^\s*int ' 'B29 ^hlxb$ (both anchors)|^hlxb$' 'B30 [0-9] (a leading range class)|[0-9]' \
            'B31 [^0-9] (a negated digit range)|[^0-9]' 'B32 a class right after a word (hlxa[a-z]) reads as a subscript: quiet (known false negative)|hlxa[a-z]'; do
    lab="${pair%%|*}"; pat="${pair#*|}"
    o="$( g --grep="$pat" --grep-in=any | root )"
    case "$lab" in
        B32*) if printf '%s' "$o" | grep -q 'pattern_meta='; then no "$lab: $o"; else ok "$lab"; fi ;;
        *)    if printf '%s' "$o" | grep -q 'pattern_meta='; then ok "$lab keeps pattern_meta"; else no "$lab lost its pattern_meta: $o"; fi ;;
    esac
done
# train 34 CR pre-pass: a UTF-8 lead/continuation byte is part of an identifier (Python, JS, Go, Rust names), so `hlxcaf\xc3\xa9|hlxtea` is an
# alternation between two words (it read as no alternation: a silent literal zero), and a subscript after a non-ASCII name is a subscript
printf 'hlxcaf\xc3\xa9 hlxtea\nhlxn\xc3\xa9[i-1]\n' > "$R/u.py"
o="$( g --grep=$'hlxcaf\xc3\xa9|hlxtea' --grep-in=any | root )"
if printf '%s' "$o" | grep -q 'pattern_meta="|"'; then ok "B35 an alternation whose word ends in a non-ASCII byte → pattern_meta=|"; else no "B35 $o"; fi
o="$( g --grep=$'hlxn\xc3\xa9[i-1]' --grep-in=any | root )"
if printf '%s' "$o" | grep -q 'pattern_meta='; then no "B36 a subscript after a non-ASCII name read as a bracket class: $o"; else ok "B36 a subscript after a non-ASCII name is no bracket class"; fi
# (N1) the compact legend and the dict say complete=/hits= speak of the LITERAL reading only.
if g --grep='hlxa' --legend=compact | grep -q 'of the literal reading only'; then ok "B33 the compact grep legend ties complete= to the literal reading"; else no "B33 compact grep legend lacks the literal-reading clause"; fi
if ( cd "$R" && "$BIN" "$R" --legend-dict 2>/dev/null ) | grep 'pattern_meta=:' | grep -q 'literal reading only'; then ok "B34 the pattern_meta dict entry ties complete=/hits= to the literal reading"; else no "B34 dict entry lacks the clause"; fi

o="$( g --grep='hlxa|hlxb' --legend=full )"
if printf '%s' "$o" | grep -q 'pattern_meta= (present only'; then ok "B15 the full legend defines pattern_meta= when it rides"; else no "B15 legend clause missing"; fi
o="$( g --grep='hlxa' --legend=full )"
if printf '%s' "$o" | grep -q 'pattern_meta= (present only'; then no "B16 the pattern_meta clause rides without the attribute"; else ok "B16 the clause is present-only"; fi

echo "── (B) grep: one row per line, occ= ──"
o="$( g --grep='hlxa' --grep-in=any )"
if printf '%s' "$o" | root | grep -q 'hits="3"'; then ok "B17 hits= counts LINES (3 lines hold hlxa, 4 occurrences)"; else no "B17 $( printf '%s' "$o" | root )"; fi
if printf '%s' "$o" | grep -q '<hit l="2"[^>]* occ="2"'; then ok "B18 the line holding hlxa twice is ONE row with occ=2"; else no "B18 no occ=2 row"; fi
if [ "$( printf '%s' "$o" | grep -o '<hit l="2"' | wc -l | tr -d ' ' )" = 1 ]; then ok "B19 …printed once"; else no "B19 line 2 printed more than once"; fi
if printf '%s' "$o" | grep -q '<hit l="1"[^>]* occ='; then no "B20 a single occurrence carries occ="; else ok "B20 a single occurrence carries no occ="; fi
if g --grep='hlxa' --grep-in=any --legend=full | grep -q 'occ= on a row'; then ok "B21 the full legend defines occ= when it rides"; else no "B21 occ clause missing"; fi
o="$( g --grep='hlxq' )"
if ! printf '%s' "$o" | grep -q '<unindexed'; then no "B22 premise: q.scm was not served as an unindexed file"
elif printf '%s' "$o" | grep -q '<hit l="1" occ="2"'; then ok "B22 the unindexed list folds too (occ=2)"
else no "B22 unindexed row: $( printf '%s' "$o" | grep -o '<unindexed.*' | head -c 300 )"; fi

echo "── (B) MCP twin ──"
mcp() { printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"path":"'"$R"'","pattern":"'"$1"'","in":"any"}}}' \
    | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c 'import sys,json; r=json.load(sys.stdin); print(r["result"]["content"][0]["text"] if "result" in r else "__ERROR__")'; }
j="$( mcp 'hlxa|hlxb' )"
if printf '%s' "$j" | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get("pattern_meta")=="|" and "--regex=" in d.get("next","") else 1)'; then
    ok "M1 MCP grep: pattern_meta | and next= the regex verb"
else no "M1 MCP: $( printf '%s' "$j" | head -c 300 )"; fi
j="$( mcp 'hlxa' )"
if printf '%s' "$j" | python3 -c 'import sys,json; d=json.load(sys.stdin); h=[x for x in d["hits"] if x["line"]==2]; sys.exit(0 if len(h)==1 and h[0].get("occ")==2 and d.get("total")==3 else 1)'; then
    ok "M2 MCP grep: one row per line, occ 2, total 3 (CLI parity)"
else no "M2 MCP: $( printf '%s' "$j" | head -c 400 )"; fi
if printf '%s' "$j" | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(1 if "pattern_meta" in d else 0)'; then
    ok "M3 MCP grep: a plain literal carries no pattern_meta"
else no "M3 plain literal has pattern_meta"; fi

[ "$fail" -eq 0 ] && echo "honestlexcheck: ALL PASS" || echo "honestlexcheck: FAILURES"
exit "$fail"
