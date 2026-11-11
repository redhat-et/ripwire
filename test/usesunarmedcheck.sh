#!/usr/bin/env bash
# usesunarmedcheck.sh — B31: a "zero" or "not found" where the truth is "not indexed" must say so (honesty).
#
# Four defects, one fixture tree per shape, CLI and MCP where both surfaces exist:
#   (A) USES-UNARMED: --uses on a definition READ or NAMED more than called, in a language whose read/write/type uses the
#       index never captures (Go/Rust structs, a C global table), printed a bare count="0" — now unindexed_roles=.
#   (B) macro: --defs on an object-like `#define` in a C++-parsed header said "symbol not found … did you mean" — the
#       refusal now names the #define line and says object-like macros on that path are not indexed.
#   (C) USES-FIELD-EXTERNAL: a bare member name of a TS/Rust/Go type answered found="0" near=<a type> (CLI) and
#       external="1" (MCP, "no definition in the indexed tree") — both now refuse with the qualified form's sentence.
#   (D) TMUX-STRUCT-WINDOW honesty: a struct lost to a degraded parse got a note naming the first degraded file that
#       MENTIONS it in path order; the note now names the lexical definition line.
# Positive controls: a C++ class used across .cpp files, a Python class, and C/C++/Python fields with real captures
# resolve with NO disclosure (so "always disclose" fails). Negative arms count their premise and FAIL on zero.
#
# RED-FIRST: recorded 2026-11-11 against main ea25a7888 — (A2..A4) (A6) (B2) (B3) (C2..C5) (D2) (D3) FAIL there; the
# premise, control and precision arms pass on both.
#
# Usage: test/usesunarmedcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "usesunarmedcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

rw(){ "$BIN" "$@" --no-cache --legend=compact 2>&1; }   # stdout + stderr: the refusals speak on stderr
mcp(){   # $1=corpus $2=verb $3=extra argument JSON fields (comma-led)
    printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":{"path":"%s"%s}}}\n' \
        "$2" "$1" "$3" | "$BIN" --mcp 2>/dev/null
}
root_of(){ printf '%s' "$1" | grep -o '<uses [^>]*>' | head -1; }

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$TMP/go" "$TMP/rs/src" "$TMP/c" "$TMP/cpp" "$TMP/py" "$TMP/ts" "$TMP/mac" "$TMP/deg"
cat > "$TMP/go/opts.go" <<'EOF'
package fz

type Options struct {
	Query string
	Limit int
}

func defaultOptions() *Options {
	return &Options{Query: "", Limit: 10}
}

func apply(o *Options) int {
	var copyOf Options = *o
	return copyOf.Limit
}
EOF
cat > "$TMP/rs/src/lib.rs" <<'EOF'
pub struct CmdRenderer {
    pub env_vars: Vec<String>,
}

pub fn make() -> CmdRenderer {
    CmdRenderer { env_vars: Vec::new() }
}

pub fn count(r: &CmdRenderer) -> usize {
    r.env_vars.len()
}
EOF
cat > "$TMP/c/table.c" <<'EOF'
struct entry { const char *name; int (*fn)( int ); };
static int run( int x ) { return x; }
const struct entry cmd_table[] = { { "run", run }, { 0, 0 } };
EOF
cat > "$TMP/c/user.c" <<'EOF'
struct entry { const char *name; int (*fn)( int ); };
extern const struct entry cmd_table[];
int find_cmd( const char *n ) { for( int i = 0; cmd_table[ i ].name; ++i ) { if( cmd_table[ i ].name == n ) { return i; } } return -1; }
EOF
# a C struct's field in a header (the C++ parse path, where C fields are extracted), used from a .c file
mkdir -p "$TMP/cf"
cat > "$TMP/cf/pt.h" <<'EOF'
struct point { int x; int y; };
static inline int px( struct point *p ) { return p->x + 1; }
EOF
printf '#include "pt.h"\nint main( void ) { struct point q; q.x = 1; return px( &q ); }\n' > "$TMP/cf/main.c"
cat > "$TMP/cpp/widget.h" <<'EOF'
class Widget { public: int size; int grow( int n ); };
EOF
cat > "$TMP/cpp/widget.cpp" <<'EOF'
#include "widget.h"
int Widget::grow( int n ) { size += n; return size; }
EOF
cat > "$TMP/cpp/use.cpp" <<'EOF'
#include "widget.h"
int useIt() { Widget w; w.size = 3; return w.grow( 2 ); }
int readIt( Widget& w ) { return w.size; }
EOF
cat > "$TMP/py/m.py" <<'EOF'
class Counter:
    def __init__(self):
        self.total = 0

    def bump(self):
        self.total = self.total + 1
        return self.total


def make() -> Counter:
    c: Counter = Counter()
    return c
EOF
cat > "$TMP/ts/base.ts" <<'EOF'
export class Route {
  path: string = '/'
}

export class Hono {
  private basePath: string = '/'
  routes: Route[] = []

  add(path: string): void {
    const r = new Route()
    this.routes.push(r)
  }
}
EOF
cat > "$TMP/ts/display.ts" <<'EOF'
export interface Row {
  valueToken?: string;
}
export function show(row: Row): string {
  return row.valueToken ?? ''
}
EOF
cat > "$TMP/mac/tmux.h" <<'EOF'
#ifndef TMUX_H
#define TMUX_H
#define MY_SOCK "$TMPDIR/sock"
int tmuxproc( int x );
#endif
EOF
cat > "$TMP/mac/main.c" <<'EOF'
#include "tmux.h"
const char *sock_path( void ) { return MY_SOCK; }
int tmuxproc( int x ) { return x; }
EOF
# (D) a.c mentions winx inside a degraded parse (unclosed paren), z.h defines it in a struct the C++ grammar loses
cat > "$TMP/deg/a.c" <<'EOF'
struct winx;
int touch( struct winx *w ) { return w != 0; }
int broken( int x ) { return ( x +
EOF
cat > "$TMP/deg/z.h" <<'EOF'
#define TAILQ_ENTRY(type) struct { struct type *tqe_next; struct type **tqe_prev; }
#define TAILQ_HEAD(name, type) struct name { struct type *tqh_first; struct type **tqh_last; }
struct winlink { int idx; };
struct winx { int x; TAILQ_ENTRY(winx) alerts_entry; TAILQ_HEAD(, winlink) winlinks; };
EOF

# ── (A) USES-UNARMED ─────────────────────────────────────────────────────────────────────────────────────────
n=$( grep -cw 'Options' "$TMP/go/opts.go" ); m=$( grep -cw 'CmdRenderer' "$TMP/rs/src/lib.rs" ); k=$( grep -cw 'cmd_table' "$TMP/c/user.c" )
if [ "$n" -ge 2 ] && [ "$m" -ge 2 ] && [ "$k" -ge 1 ]; then ok "(A1) premise: Options/CmdRenderer/cmd_table have textual uses ($n/$m/$k lines)"
else no "(A1) premise: the fixtures lost their textual uses ($n/$m/$k) — every A arm is vacuous"; fi
seen=0
for spec in "go Options" "rs CmdRenderer" "c cmd_table"; do
    set -- $spec
    out="$( rw "$TMP/$1" --uses="$2" )"; r="$( root_of "$out" )"
    printf '%s' "$r" | grep -q "defs=\"[1-9]" && seen=$(( seen + 1 ))
    if printf '%s' "$r" | grep -q 'unindexed_roles="read,write,type"' && printf '%s' "$out" | grep -o '<!--.*-->' | grep -q 'unindexed_roles=[^ ]*: '; then
        ok "(A2) CLI --uses=$2 ($1) carries unindexed_roles= and its legend clause"
    else no "(A2) CLI --uses=$2 ($1) answers without the unindexed disclosure: $r"; fi
    mo="$( mcp "$TMP/$1" uses ",\"symbol\":\"$2\"" )"
    if printf '%s' "$mo" | grep -q 'unindexed_roles=\\"read,write,type\\"' && printf '%s' "$mo" | grep -o '<!--.*-->' | grep -q 'unindexed_roles=[^ ]*: '; then
        ok "(A3) MCP uses $2 ($1) carries unindexed_roles= and its legend clause"
    else no "(A3) MCP uses $2 ($1) answers without the unindexed disclosure: $( printf '%s' "$mo" | grep -o '<uses [^>]*>' | head -1 )"; fi
done
if [ "$seen" -eq 3 ]; then ok "(A4) premise: all 3 unarmed definitions resolved (defs>=1), so A2/A3 read a real answer"
else no "(A4) premise: only $seen/3 unarmed definitions resolved — A2/A3 judged a refusal"; fi
# (A5) positive control: armed C++ class across .cpp files, Python class — real captures, NO disclosure
for spec in "cpp Widget" "py Counter"; do
    set -- $spec
    out="$( rw "$TMP/$1" --uses="$2" )"; r="$( root_of "$out" )"
    cnt="$( printf '%s' "$r" | sed -n 's/.* count="\([0-9]*\)".*/\1/p' )"
    if [ "${cnt:-0}" -ge 1 ] && ! printf '%s' "$out" | grep -q 'unindexed_roles'; then
        ok "(A5) control: --uses=$2 ($1) count=$cnt with no unindexed disclosure"
    else no "(A5) control: --uses=$2 ($1) count=${cnt:-?} / disclosure present: $r"; fi
    mo="$( mcp "$TMP/$1" uses ",\"symbol\":\"$2\"" )"
    if printf '%s' "$mo" | grep -q 'unindexed_roles'; then no "(A5) control: MCP uses $2 ($1) discloses unindexed roles"; else ok "(A5) control: MCP uses $2 ($1) carries no disclosure"; fi
done
# (A6) fields with real captures (C, C++, Python) resolve with NO disclosure
for spec in "cf point.x" "cpp Widget.size" "py Counter.total"; do
    set -- $spec
    out="$( rw "$TMP/$1" --uses="$2" )"; r="$( root_of "$out" )"
    cnt="$( printf '%s' "$r" | sed -n 's/.* count="\([0-9]*\)".*/\1/p' )"
    if [ "${cnt:-0}" -ge 1 ] && ! printf '%s' "$out" | grep -q 'unindexed_roles\|not indexed'; then
        ok "(A6) control: field --uses=$2 ($1) count=$cnt, no disclosure"
    else no "(A6) control: field --uses=$2 ($1): $r"; fi
done

# ── (B) object-like macro in a C++-parsed header ──────────────────────────────────────────────────────────────
if grep -q '^#define MY_SOCK ' "$TMP/mac/tmux.h" && grep -qw MY_SOCK "$TMP/mac/main.c"; then ok "(B1) premise: tmux.h #defines MY_SOCK and main.c uses it"; else no "(B1) premise: fixture lost its #define"; fi
out="$( rw "$TMP/mac" --defs=MY_SOCK )"
if printf '%s' "$out" | grep -q "object-like macro, #define at .*tmux.h:3" && ! printf '%s' "$out" | grep -q 'did you mean'; then
    ok "(B2) CLI --defs=MY_SOCK names the #define line and drops the near-miss"
else no "(B2) CLI --defs=MY_SOCK: $( printf '%s' "$out" | grep 'ripwire:' | head -1 )"; fi
mo="$( mcp "$TMP/mac" find_symbol ',"symbol":"MY_SOCK"' )"
if printf '%s' "$mo" | grep -q 'object-like macro, #define at .*tmux.h:3' && ! printf '%s' "$mo" | grep -q 'did you mean'; then
    ok "(B3) MCP find_symbol MY_SOCK names the #define line"
else no "(B3) MCP find_symbol MY_SOCK: $( printf '%s' "$mo" | head -c 400 )"; fi
out="$( rw "$TMP/mac" --defs=tmuxprox )"
if printf '%s' "$out" | grep -q "did you mean 'tmuxproc'" && ! printf '%s' "$out" | grep -q 'object-like'; then
    ok "(B4) precision: a plain typo keeps its near-miss and no macro note"
else no "(B4) precision: the typo refusal changed: $( printf '%s' "$out" | grep 'ripwire:' | head -1 )"; fi

# ── (C) USES-FIELD-EXTERNAL ───────────────────────────────────────────────────────────────────────────────────
t=$( grep -cw 'routes' "$TMP/ts/base.ts" ); v=$( grep -cw 'valueToken' "$TMP/ts/display.ts" ); e=$( grep -cw 'env_vars' "$TMP/rs/src/lib.rs" ); q=$( grep -cw 'Query' "$TMP/go/opts.go" )
if [ "$t" -ge 2 ] && [ "$v" -ge 2 ] && [ "$e" -ge 2 ] && [ "$q" -ge 2 ]; then ok "(C1) premise: every member is declared and used ($t/$v/$e/$q lines)"
else no "(C1) premise: a member fixture lost its uses ($t/$v/$e/$q) — the C arms are vacuous"; fi
for spec in "ts routes Hono base.ts:7" "ts valueToken Row display.ts:2" "rs env_vars CmdRenderer lib.rs:2" "go Query Options opts.go:4"; do
    set -- $spec
    out="$( rw "$TMP/$1" --uses="$2" )"
    if printf '%s' "$out" | grep -q "'$2' is declared as a member of '$3' at .*$4" && printf '%s' "$out" | grep -q 'field symbols are extracted for C, C++ and Python only' \
       && ! printf '%s' "$out" | grep -q 'near='; then
        ok "(C2) CLI --uses=$2 ($1) refuses with the member sentence ($3, $4), no near="
    else no "(C2) CLI --uses=$2 ($1): $( printf '%s' "$out" | head -c 300 )"; fi
    mo="$( mcp "$TMP/$1" uses ",\"symbol\":\"$2\"" )"
    if printf '%s' "$mo" | grep -q "is declared as a member of '$3'" && ! printf '%s' "$mo" | grep -q 'external=\\"1\\"'; then
        ok "(C3) MCP uses $2 ($1) refuses with the member sentence, never external=\"1\""
    else no "(C3) MCP uses $2 ($1): $( printf '%s' "$mo" | head -c 300 )"; fi
done
q2="$( rw "$TMP/ts" --uses=Hono.routes )"
if printf '%s' "$q2" | grep -q "member selector 'Hono.routes': field symbols"; then ok "(C4) the qualified form keeps its sentence"; else no "(C4) qualified form changed: $q2"; fi
# precision: a method-local `const r` and a TS stdlib name are not member declarations
out="$( rw "$TMP/ts" --uses=r )"
if printf '%s' "$out" | grep -q 'declared as a member'; then no "(C5) precision: a local variable read as a member declaration"; else ok "(C5) precision: a method-local binding is not a member"; fi

# ── (D) TMUX-STRUCT-WINDOW honesty note ──────────────────────────────────────────────────────────────────────
sk="$( "$BIN" "$TMP/deg" --no-cache --skipped 2>/dev/null )"
dg=$( printf '%s' "$sk" | grep -o 'why="degraded-parse"' | wc -l | tr -d ' ' )
lost=1; "$BIN" "$TMP/deg" --no-cache --defs=winx >/dev/null 2>&1 && lost=0
if [ "$dg" -ge 2 ] && [ "$lost" -eq 1 ]; then ok "(D1) premise: $dg degraded files and struct winx is not indexed"
else no "(D1) premise: degraded=$dg lost=$lost — the fixture no longer loses the struct, D arms are vacuous"; fi
out="$( rw "$TMP/deg" --defs=winx )"
if printf '%s' "$out" | grep -q "'winx' is defined at .*z.h:4 by a lexical read" && ! printf '%s' "$out" | grep -q 'occurs textually in .*a.c'; then
    ok "(D2) CLI --defs=winx names the lexical definition z.h:4, not a.c"
else no "(D2) CLI --defs=winx: $( printf '%s' "$out" | grep 'ripwire:' | head -1 )"; fi
mo="$( mcp "$TMP/deg" find_symbol ',"symbol":"winx"' )"
if printf '%s' "$mo" | grep -q 'defined at .*z.h:4 by a lexical read'; then ok "(D3) MCP find_symbol winx names z.h:4"; else no "(D3) MCP find_symbol winx: $( printf '%s' "$mo" | head -c 400 )"; fi
out="$( rw "$TMP/deg" --defs=touch_nowhere_zz )"
if printf '%s' "$out" | grep -q 'lexical read\|object-like'; then no "(D4) precision: a nowhere-name gets a def note"; else ok "(D4) precision: a nowhere-name stays plain"; fi
a="$( rw "$TMP/deg" --defs=winx )"; b="$( rw "$TMP/deg" --defs=winx )"
if [ "$a" = "$b" ]; then ok "(D5) determinism: the note is byte-identical across runs"; else no "(D5) the note differs run to run"; fi

exit $fail
