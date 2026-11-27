#!/usr/bin/env bash
# editcheckaritycheck.sh — --edit-check's arity test on C, C++, Rust and Go (src/editcheckarity.h), and the bare name of a
# C/C++ declaration whose definition the edit changed (editcheckdecl.h editCheckStalePair).
#
# The field report (verb-audit2, 2026-11-27): a REQUIRED parameter added to a C (jq), Rust (zed) or Go (cockroach) function
# answered incompatible="0" beside callers still passing the old count — ingest's call-comparable arity is gated to other
# languages, so every definition there was a wildcard; TypeScript flagged 36/36. And `--edit-check=jq_start` exited 1
# "ambiguous" once the .c definition gained a parameter its header declaration did not: a declaration and its definition
# are ONE symbol, and the answer should say the header still spells the old list.
#
# Arms, per language (each counts what it saw and FAILS on zero):
#   R  a required parameter added: the caller still passing the old count is flagged, sites_l= on it; a caller the new
#      list still accepts is not. With BASE_BIN= set, the base binary flags none (the regression this lane fixes).
#   D  a compatible add — a default (C++), a variadic tail (C, Go), a type change and an unchanged receiver method (Rust,
#      which has no defaults): incompatible="0".
#   B  the bare name: C/C++ a header declaration left at the old list — exit 0, decl_pair= names the header, decl_params=
#      its old count, the stale caller flagged (BASE_BIN: exit 1 "ambiguous"); Rust/Go (no separate declaration) — the bare
#      name answers, and a name with two real definitions in two files is still refused.
#   U  a list nobody can read (C `f( ARGS )` from a macro): arity_unknown="1", nothing flagged — never a guessed count.
#   O  C++ overloads: a call is flagged only when NO overload fits; Rust/Go receivers: a method call omits `self`, a path
#      call writes it; Go `a, b int` is two parameters.
#
# Operates on private temp git repos. Needs git and python3.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
BASE="${BASE_BIN:-}"
fail=0; seen=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; seen=$(( seen + 1 )); return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; seen=$(( seen + 1 )); }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "editcheckaritycheck: BIN=$BIN${BASE:+ BASE_BIN=$BASE}"

commit(){ ( cd "$1" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init ) >/dev/null 2>&1 \
              || no "could not commit $1 — every arm on it would read no-baseline"; }
# ec <bin> <corpus> <selector> → the document on stdout, stderr to $TMP/err, exit code to $TMP/rc
ec(){ ( cd "$2" && "$1" . --no-cache --edit-check="$3" --legend=full 2>"$TMP/err"; echo $? >"$TMP/rc" ); }
rc(){ cat "$TMP/rc"; }
attr(){ printf '%s' "$1" | grep -oE '<edit-check [^>]*>' | head -1 | python3 -c 'import re,sys; m=re.search(r"(?<![A-Za-z0-9_])"+re.escape(sys.argv[1])+r"=\"([^\"]*)\"",sys.stdin.read()); sys.stdout.write(m.group(1) if m else "")' "$2"; }
flagged(){ printf '%s' "$1" | python3 -c 'import re,sys; print(",".join(sorted(set(re.findall(r"<c n=\"([^\"]*)\"[^>]*incompatible=\"1\"",sys.stdin.read())))))'; }
has(){ case ",$1," in *",$2,"*) return 0;; esac; return 1; }

# R/O: expect <label> <corpus> <selector> <must-flag csv> <must-not-flag csv>
expect(){
    local label="$1" dir="$2" sel="$3" want="$4" wont="$5" out f w
    out="$( ec "$BIN" "$dir" "$sel" )"; f="$( flagged "$out" )"
    [ "$( rc )" = 0 ] || { no "$label: $sel exited $( rc ): $( head -c 300 "$TMP/err" )"; return; }
    for w in ${want//,/ }; do if has "$f" "$w"; then ok "$label: $w flagged"; else no "$label: $w NOT flagged (flagged: '$f')"; fi; done
    for w in ${wont//,/ }; do if has "$f" "$w"; then no "$label: $w flagged but the new list accepts it"; else ok "$label: $w not flagged"; fi; done
    if [ -n "$want" ]; then
        if printf '%s' "$out" | grep -qE '<c n="[^"]*"[^>]*incompatible="1"[^>]*sites_l="[0-9]'; then ok "$label: sites_l= on the flagged row"; else no "$label: no sites_l= on a flagged row"; fi
        if [ "$( attr "$out" incompatible )" != 0 ]; then ok "$label: root incompatible=$( attr "$out" incompatible )"; else no "$label: root incompatible=0"; fi
    else
        if [ "$( attr "$out" incompatible )" = 0 ]; then ok "$label: root incompatible=0"; else no "$label: root incompatible=$( attr "$out" incompatible ), want 0"; fi
    fi
    if [ -n "$BASE" ] && [ -n "$want" ] && [ "${6:-}" = base-misses ]; then
        out="$( ec "$BASE" "$dir" "$sel" )"
        if [ "$( rc )" = 0 ] && [ -z "$( flagged "$out" )" ]; then ok "$label: BASE flags none (the regression)"; else no "$label: BASE rc=$( rc ) flagged '$( flagged "$out" )' — the arm does not separate base from head"; fi
    fi
}

# B (C/C++): bare <label> <corpus> <name> <header file> <old count> <must-flag>
bare(){
    local label="$1" dir="$2" name="$3" hdr="$4" old="$5" want="$6" out
    out="$( ec "$BIN" "$dir" "$name" )"
    if [ "$( rc )" = 0 ]; then ok "$label: bare --edit-check=$name answers (exit 0)"; else no "$label: bare $name exited $( rc ): $( head -c 300 "$TMP/err" )"; return; fi
    case "$( attr "$out" decl_pair )" in "$hdr":*) ok "$label: decl_pair=$( attr "$out" decl_pair ) discloses the merged declaration";;
        *) no "$label: decl_pair='$( attr "$out" decl_pair )', want $hdr:LINE";; esac
    if [ "$( attr "$out" decl_params )" = "$old" ]; then ok "$label: decl_params=$old (the header's old list)"; else no "$label: decl_params='$( attr "$out" decl_params )', want $old"; fi
    if has "$( flagged "$out" )" "$want"; then ok "$label: $want flagged on the bare answer"; else no "$label: $want not flagged on the bare answer"; fi
    if printf '%s' "$out" | python3 -c 'import re,sys; d=sys.stdin.read(); l=re.match(r"\A(?:\s*<!--.*?-->)+",d,re.S); sys.exit(0 if l and "decl_pair=" in l.group(0) else 1)'; then ok "$label: decl_pair= defined in the legend"; else no "$label: decl_pair= not defined in the legend"; fi
    if [ -n "$BASE" ]; then
        ec "$BASE" "$dir" "$name" >/dev/null
        if [ "$( rc )" = 1 ] && grep -q ambiguous "$TMP/err"; then ok "$label: BASE refused the bare name (exit 1 ambiguous)"; else no "$label: BASE rc=$( rc ) — the arm does not separate base from head"; fi
    fi
}

# ── C ─────────────────────────────────────────────────────────────────────────────────────────────────────────
C="$TMP/c"; mkdir -p "$C"
cat >"$C/lib.h" <<'EOF'
#define ARGS int a, int b
int scale( int x, int factor );
int logmsg( const char *fmt );
int viamacro( ARGS );
EOF
cat >"$C/lib.c" <<'EOF'
#include "lib.h"
int scale( int x, int factor )
{
    return x * factor;
}
int logmsg( const char *fmt )
{
    return fmt[0];
}
int viamacro( ARGS )
{
    return a + b;
}
EOF
cat >"$C/use.c" <<'EOF'
#include "lib.h"
struct ops { int ( *scale )( int ); };
int cuse_a( void ) { return scale( 1, 2 ); }
int cuse_b( void ) { return logmsg( "x" ) + logmsg( "%d", 3 ); }
int cuse_c( void ) { return viamacro( 1, 2 ); }
int cuse_d( struct ops *o ) { return o->scale( 1 ) + scale( 3, 4 ); }
EOF
commit "$C"
cp "$C/lib.c" "$TMP/c.lib.c"
python3 - "$C/lib.c" <<'EOF'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("int scale( int x, int factor )","int scale( int x, int factor, int bias )").replace("return x * factor;","return x * factor + bias;")
s=s.replace("int logmsg( const char *fmt )","int logmsg( const char *fmt, ... )"); open(p,"w").write(s)
EOF
sed -i.bak 's/int logmsg( const char \*fmt );/int logmsg( const char *fmt, ... );/' "$C/lib.h" && rm -f "$C/lib.h.bak"
expect "C R" "$C" "lib.c:scale" "cuse_a,cuse_d" "" base-misses
expect "C D (variadic tail)" "$C" "lib.c:logmsg" "" "cuse_b"
bare "C B" "$C" scale lib.h 2 cuse_a
out="$( ec "$BIN" "$C" "lib.c:viamacro" )"
if [ "$( attr "$out" arity_unknown )" = 1 ]; then ok "C U: arity_unknown=1 on the macro-built list"; else no "C U: arity_unknown='$( attr "$out" arity_unknown )', want 1"; fi
if [ -z "$( flagged "$out" )" ]; then ok "C U: nothing flagged against an unread list"; else no "C U: flagged '$( flagged "$out" )' against an unread list"; fi

# ── C++ ───────────────────────────────────────────────────────────────────────────────────────────────────────
P="$TMP/cpp"; mkdir -p "$P"
cat >"$P/lib.h" <<'EOF'
int scale( int x );
EOF
cat >"$P/lib.cpp" <<'EOF'
#include "lib.h"
int scale( int x )
{
    return x;
}
int blend( int a, int b = 1 )
{
    return a + b;
}
int grow( int a )
{
    return a;
}
int pick( int a )
{
    return a;
}
int pick( int a, int b )
{
    return a + b;
}
template <class... A> int many( int a, A... rest )
{
    return a + int( sizeof...( rest ) );
}
int puse_blend1() { return blend( 1 ); }
int puse_blend2() { return blend( 1, 2 ); }
int puse_grow() { return grow( 1 ); }
int puse_pick1() { return pick( 1 ); }
int puse_pick2() { return pick( 1, 2 ); }
int puse_many1() { return many( 1 ); }
int puse_many3() { return many( 1, 2, 3 ); }
EOF
cat >"$P/use.cpp" <<'EOF'
#include "lib.h"
int puse_scale() { return scale( 1 ); }
EOF
commit "$P"
python3 - "$P/lib.cpp" <<'EOF'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("int scale( int x )\n","int scale( int x, int y )\n")
s=s.replace("int blend( int a, int b = 1 )","int blend( int a, int c, int b = 1 )")
s=s.replace("int grow( int a )\n","int grow( int a, int b = 0 )\n")
s=s.replace("int pick( int a )\n","int pick( int a, int b, int c )\n")
s=s.replace("int many( int a, A... rest )","int many( int a, int b, A... rest )"); open(p,"w").write(s)
EOF
expect "C++ R (beside a default)" "$P" "lib.cpp:blend" "puse_blend1" "puse_blend2" base-misses
expect "C++ R (pack tail)" "$P" "lib.cpp:many" "puse_many1" "puse_many3" base-misses
expect "C++ D (default added)" "$P" "lib.cpp:grow" "" "puse_grow"
expect "C++ O (no overload fits)" "$P" "lib.cpp:pick" "puse_pick1" "puse_pick2"
bare "C++ B" "$P" scale lib.h 1 puse_scale

# ── Rust ──────────────────────────────────────────────────────────────────────────────────────────────────────
R="$TMP/rust"; mkdir -p "$R/src"
cat >"$R/src/lib.rs" <<'EOF'
pub struct S;
impl S {
    pub fn m(&self, a: i32) -> i32 {
        a
    }
    pub fn k(&self, a: i32) -> i32 {
        a
    }
}
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}
pub fn tweak(a: i32) -> i32 {
    a
}
pub fn ruse_add() -> i32 {
    add(1, 2)
}
pub fn ruse_m(s: &S) -> i32 {
    s.m(1)
}
pub fn ruse_path(s: &S) -> i32 {
    S::m(s, 1)
}
pub fn ruse_k(s: &S) -> i32 {
    s.k(1) + S::k(s, 2)
}
pub fn ruse_tweak() -> i32 {
    tweak(1)
}
EOF
mkdir -p "$R/src/other"; printf 'pub fn dup(a: i32) -> i32 {\n    a\n}\n' >"$R/src/other/a.rs"; printf 'pub fn dup(a: i32, b: i32) -> i32 {\n    a + b\n}\n' >"$R/src/other/b.rs"
commit "$R"
python3 - "$R/src/lib.rs" <<'EOF'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("pub fn m(&self, a: i32)","pub fn m(&self, a: i32, b: i32)").replace("pub fn add(a: i32, b: i32)","pub fn add(a: i32, b: i32, c: i32)")
s=s.replace("pub fn tweak(a: i32)","pub fn tweak(a: i64)"); open(p,"w").write(s)
EOF
expect "Rust R (free fn)" "$R" "src/lib.rs:add" "ruse_add" "" base-misses
expect "Rust R/O (method: member call omits self, path call writes it)" "$R" "src/lib.rs:m" "ruse_m,ruse_path" "" base-misses
expect "Rust D (type change)" "$R" "src/lib.rs:tweak" "" "ruse_tweak"
expect "Rust D/O (unchanged receiver method, both call forms)" "$R" "src/lib.rs:k" "" "ruse_k"
out="$( ec "$BIN" "$R" add )"
if [ "$( rc )" = 0 ] && has "$( flagged "$out" )" ruse_add; then ok "Rust B: bare --edit-check=add answers and flags"; else no "Rust B: bare add rc=$( rc ) flagged '$( flagged "$out" )'"; fi
ec "$BIN" "$R" dup >/dev/null
if [ "$( rc )" = 1 ]; then ok "Rust B: two real definitions in two files stay refused"; else no "Rust B: dup rc=$( rc ), want 1"; fi

# ── Go ────────────────────────────────────────────────────────────────────────────────────────────────────────
G="$TMP/go"; mkdir -p "$G/a" "$G/b"
printf 'module example.com/m\n\ngo 1.21\n' >"$G/go.mod"
cat >"$G/lib.go" <<'EOF'
package main

type T struct{}

func (t *T) Get(k string) int {
	return len(k)
}

func Sum(a, b int) int {
	return a + b
}

func Join(a string) string {
	return a
}
EOF
cat >"$G/use.go" <<'EOF'
package main

func guseSum() int {
	return Sum(1, 2)
}

func guseJoin() string {
	return Join("x")
}

func guseGet(t *T) int {
	return t.Get("a")
}
EOF
printf 'package a\n\nfunc Dup(x int) int {\n\treturn x\n}\n' >"$G/a/a.go"; printf 'package b\n\nfunc Dup(x, y int) int {\n\treturn x + y\n}\n' >"$G/b/b.go"
commit "$G"
python3 - "$G/lib.go" <<'EOF'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("func Sum(a, b int) int","func Sum(a, b, c int) int").replace("func Join(a string) string","func Join(a string, rest ...string) string")
s=s.replace("func (t *T) Get(k string) int","func (t *T) Get(k string, d int) int"); open(p,"w").write(s)
EOF
expect "Go R (grouped a, b int)" "$G" "lib.go:Sum" "guseSum" "" base-misses
expect "Go R (method)" "$G" "lib.go:Get" "guseGet" "" base-misses
expect "Go D (variadic tail)" "$G" "lib.go:Join" "" "guseJoin"
out="$( ec "$BIN" "$G" Sum )"
if [ "$( rc )" = 0 ] && has "$( flagged "$out" )" guseSum; then ok "Go B: bare --edit-check=Sum answers and flags"; else no "Go B: bare Sum rc=$( rc ) flagged '$( flagged "$out" )'"; fi
ec "$BIN" "$G" Dup >/dev/null
if [ "$( rc )" = 1 ]; then ok "Go B: two real definitions in two packages stay refused"; else no "Go B: Dup rc=$( rc ), want 1"; fi

if [ "$seen" -eq 0 ]; then no "no check ran"; fi
echo "editcheckaritycheck: $seen checks"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
