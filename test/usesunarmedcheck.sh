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
# premise, control and precision arms pass on both. B44 (CodeRabbit + CI round, 2026-11-12) added arms red on lane 1fd60ea1b:
# (A7) (A8) (B5) (B6) (B7) (C6) (C7) (C8); (A5)'s MCP control now requires a served answer. CARD-SWEEP-1113: (B8) red
# (alarm), (B9) and (C13) red on main cd04d477e.
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
mkdir -p "$TMP/go" "$TMP/rs/src" "$TMP/c" "$TMP/cpp" "$TMP/py" "$TMP/ts" "$TMP/mac" "$TMP/deg" "$TMP/rb"
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
    if ! printf '%s' "$mo" | grep -q '<uses [^>]*count=\\"[1-9]'; then no "(A5) control: MCP uses $2 ($1) served no <uses> answer with count>=1: $( printf '%s' "$mo" | head -c 300 )"
    elif printf '%s' "$mo" | grep -q 'unindexed_roles'; then no "(A5) control: MCP uses $2 ($1) discloses unindexed roles"
    else ok "(A5) control: MCP uses $2 ($1) answers count>=1 and carries no disclosure"; fi
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
# (A7) a header type whose only C user is a declaration-only .c file (no symbol of its own): the C includer is read from the
# file list, so the disclosure still fires; (A8) the clause calls count= a floor for SOME or all users (C++ users keep reads)
mkdir -p "$TMP/hc"
printf 'struct cell\n{\n    int x;\n};\n' > "$TMP/hc/a.h"
printf '#include "a.h"\nextern struct cell g_cell;\nextern struct cell g_other;\n' > "$TMP/hc/b.c"
nd=0; "$BIN" "$TMP/hc" --no-cache --defs=g_cell >/dev/null 2>&1 || nd=1
uc=$( grep -cw cell "$TMP/hc/b.c" )
if [ "$nd" -eq 1 ] && [ "$uc" -ge 2 ]; then ok "(A7) premise: b.c mentions cell on $uc lines and defines no indexed symbol"
else no "(A7) premise: b.c indexes a symbol ($nd) or lost its uses ($uc) — A7 is vacuous"; fi
out="$( rw "$TMP/hc" --uses=cell )"
if printf '%s' "$( root_of "$out" )" | grep -q 'defs="1".*unindexed_roles="read,write,type"'; then ok "(A7) --uses=cell discloses unindexed_roles= for a header used only by a symbol-less .c file"
else no "(A7) --uses=cell (symbol-less C includer) answers without the disclosure: $( root_of "$out" )"; fi
if printf '%s' "$out" | grep -o '<!--.*-->' | grep -q 'unindexed_roles=[^ ]*: .*some or all users.*count= is a floor'; then ok "(A8) the clause scopes the missing roles to some or all users and calls count= a floor"
else no "(A8) the unindexed_roles clause still claims count= holds only the other roles for every user"; fi

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
if printf '%s' "$out" | grep -q 'stopped at its budget'; then no "(B4) precision: a 2-file corpus says the lexical scan stopped at its budget"; else ok "(B4) precision: a small corpus carries no budget note"; fi
# (B5) a `#define` inside a multi-line /* */ comment defines nothing
mkdir -p "$TMP/mcom"
printf '#ifndef OLD_H\n#define OLD_H\n/* retired:\n#define OLD_SOCK "/tmp/old"\n*/\nint oldproc( int x );\n#endif\n' > "$TMP/mcom/old.h"
printf '#include "old.h"\nint oldproc( int x ) { return x; }\n' > "$TMP/mcom/main.c"
if grep -q '^#define OLD_SOCK ' "$TMP/mcom/old.h"; then ok "(B5) premise: old.h holds a #define OLD_SOCK line, inside a block comment"; else no "(B5) premise: fixture lost the commented #define"; fi
out="$( rw "$TMP/mcom" --defs=OLD_SOCK )"
if printf '%s' "$out" | grep -q 'not found' && ! printf '%s' "$out" | grep -q 'object-like macro'; then ok "(B5) CLI --defs=OLD_SOCK: a commented-out #define is not named as the definition"
else no "(B5) CLI --defs=OLD_SOCK: $( printf '%s' "$out" | grep 'ripwire:' | head -1 )"; fi
mo="$( mcp "$TMP/mcom" find_symbol ',"symbol":"OLD_SOCK"' )"
if printf '%s' "$mo" | grep -q 'object-like macro'; then no "(B5) MCP find_symbol OLD_SOCK names a commented-out #define"; else ok "(B5) MCP find_symbol OLD_SOCK: no macro note for a commented-out #define"; fi
# (B6) a degraded .c file's object-like #define is not a "C++ parse path" macro: C indexes macros
mkdir -p "$TMP/degc"
printf 'int a[] = { 1, 2, \n#define C_SOCK 7\n 3 ) ) ;\n' > "$TMP/degc/a.c"
printf 'int fine( void ) { return 1; }\n' > "$TMP/degc/b.c"
nd=0; "$BIN" "$TMP/degc" --no-cache --defs=C_SOCK >/dev/null 2>&1 || nd=1
if [ "$nd" -eq 1 ]; then ok "(B6) premise: C_SOCK is not indexed (the degraded parse lost it)"; else no "(B6) premise: --defs=C_SOCK resolved — the B6 arms are vacuous"; fi
out="$( rw "$TMP/degc" --defs=C_SOCK )"
if printf '%s' "$out" | grep -q 'C++ parse path'; then no "(B6) CLI --defs=C_SOCK gives a degraded .c macro the C++-path reason: $( printf '%s' "$out" | grep 'ripwire:' | head -1 )"
else ok "(B6) CLI --defs=C_SOCK: a degraded .c file's #define gets no C++-path reason"; fi
mo="$( mcp "$TMP/degc" find_symbol ',"symbol":"C_SOCK"' )"
if printf '%s' "$mo" | grep -q 'C++ parse path'; then no "(B6) MCP find_symbol C_SOCK gives a degraded .c macro the C++-path reason"; else ok "(B6) MCP find_symbol C_SOCK: no C++-path reason"; fi
# (B7) past the scan budget (4096 C++-path files) a miss says the scan stopped, CLI and MCP; generated here, never committed
mkdir -p "$TMP/big"
i=0; while [ "$i" -le 4096 ]; do printf 'int f%04d( void );\n' "$i" > "$TMP/big/h$( printf '%04d' "$i" ).h"; i=$(( i + 1 )); done
nb=$( ls "$TMP/big" | grep -c '\.h$' )
if [ "$nb" -gt 4096 ]; then ok "(B7) premise: $nb C++-path headers, past the 4096-file scan budget"; else no "(B7) premise: only $nb headers — B7 cannot trip the budget"; fi
out="$( rw "$TMP/big" --defs=never_defined_zz )"
if printf '%s' "$out" | grep -q 'not found' && printf '%s' "$out" | grep -q 'lexical definition scan stopped at its budget, 4096 files'; then ok "(B7) CLI: a miss past the budget says the lexical scan stopped"
else no "(B7) CLI: a miss past the budget is silent about it: $( printf '%s' "$out" | grep 'ripwire:' | head -1 | head -c 300 )"; fi
mo="$( mcp "$TMP/big" find_symbol ',"symbol":"never_defined_zz"' )"
if printf '%s' "$mo" | grep -q 'lexical definition scan stopped at its budget'; then ok "(B7) MCP find_symbol: a miss past the budget says the scan stopped"
else no "(B7) MCP find_symbol past the budget: $( printf '%s' "$mo" | head -c 300 )"; fi

# (B8) LEXDEF-ONEPASS (CodeRabbit #630 4553235640): a 3.6 MiB `//`-only header naming an unindexed name on 45000 lines.
# The block-comment test rfound the whole prefix per candidate line (quadratic: over 120 s on main cd04d477e); one
# forward pass answers in about 2 s. Generated here, never committed (a whole-repo run must not see it).
mkdir -p "$TMP/lexq"
awk 'BEGIN { for( i = 0; i < 45000; ++i ) printf "// note: zz_ghost_name appears here in a line comment, padding padding padd %05d\n", i }' > "$TMP/lexq/big.h"
printf 'int use_it( void ) { return 1; }\n' > "$TMP/lexq/user.c"
nq=$( grep -c zz_ghost_name "$TMP/lexq/big.h" ); bq=$( wc -c < "$TMP/lexq/big.h" | tr -d ' ' )
if [ "$nq" -eq 45000 ] && [ "$bq" -gt 3000000 ] && [ "$bq" -lt 4194304 ]; then ok "(B8) premise: big.h is $bq bytes (under the 4 MiB read cap) with $nq mentions"
else no "(B8) premise: big.h is $bq bytes with $nq mentions — the arm cannot show the quadratic"; fi
qrc=0; out="$( perl -e 'alarm 30; exec @ARGV' "$BIN" "$TMP/lexq" --no-cache --legend=compact --defs=zz_ghost_name 2>&1 )" || qrc=$?
if [ "$qrc" -eq 1 ] && printf '%s' "$out" | grep -q 'not found' && ! printf '%s' "$out" | grep -q 'object-like'; then ok "(B8) --defs=zz_ghost_name over 45000 commented mentions refuses within 30 s (rc=1)"
else no "(B8) --defs=zz_ghost_name over 45000 commented mentions: rc=$qrc (142 = the 30 s alarm), $( printf '%s' "$out" | grep 'ripwire:' | head -1 )"; fi
# (B9) LEXDEF-RAWSTRING (CodeRabbit #630 4553235650): a `#define` line inside a C++ raw string R"( … )" is text, not a macro;
# a real #define after the raw string closes is still named (control). Red on main cd04d477e (the raw-string line was named).
mkdir -p "$TMP/raw"
printf '#ifndef RAW_H\n#define RAW_H\nstatic const char* kDoc = R"doc(\n#define GHOST_SOCK "/tmp/ghost"\n)doc";\n#define REAL_SOCK "/tmp/real"\nint rawproc( int x );\n#endif\n' > "$TMP/raw/raw.h"
printf '#include "raw.h"\nint rawproc( int x ) { return x; }\n' > "$TMP/raw/main.c"
if grep -q '^#define GHOST_SOCK ' "$TMP/raw/raw.h" && grep -q 'R"doc(' "$TMP/raw/raw.h"; then ok "(B9) premise: raw.h holds a #define GHOST_SOCK line inside a raw string"; else no "(B9) premise: fixture lost the raw-string #define"; fi
out="$( rw "$TMP/raw" --defs=GHOST_SOCK )"   # status: --defs exits 1 on a refusal by design; the answer text is the verdict and an empty one FAILs
if printf '%s' "$out" | grep -q 'not found' && ! printf '%s' "$out" | grep -q 'object-like macro'; then ok "(B9) CLI --defs=GHOST_SOCK: a #define inside a raw string is not named as the definition"
else no "(B9) CLI --defs=GHOST_SOCK: $( printf '%s' "$out" | grep 'ripwire:' | head -1 )"; fi
mo="$( mcp "$TMP/raw" find_symbol ',"symbol":"GHOST_SOCK"' )"   # status: the MCP reply text is the verdict; an empty reply FAILs the arm below
if [ -z "$mo" ] || printf '%s' "$mo" | grep -q 'object-like macro'; then no "(B9) MCP find_symbol GHOST_SOCK names a raw-string #define (or replied nothing)"; else ok "(B9) MCP find_symbol GHOST_SOCK: no macro note for a raw-string #define"; fi
out="$( rw "$TMP/raw" --defs=REAL_SOCK )"   # status: --defs exits 1 on a refusal by design; the answer text is the verdict and an empty one FAILs
if printf '%s' "$out" | grep -q 'object-like macro, #define at .*raw.h:6'; then ok "(B9) control: REAL_SOCK after the raw string closes is named at raw.h:6"
else no "(B9) control: REAL_SOCK after the raw string: $( printf '%s' "$out" | grep 'ripwire:' | head -1 )"; fi
# Ruby declares no member lexically (instance variables are @ivars; the attr_* family is indexed, rubyattrscheck): a
# class-body DSL call `has_many :posts` is a call with a symbol argument, never `name: Type`.
mkdir -p "$TMP/rb"
cat > "$TMP/rb/post.rb" <<'EOF'
class Post
  has_many :comments
  attr_accessor :title

  def summary
    title
  end
end
EOF
cat > "$TMP/rb/user.rb" <<'EOF'
class User
  has_many :posts
end
EOF

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
# precision: a Ruby class-body DSL call (`has_many :posts`) is not `name: Type` (ruby: MemberDecl::None)
h=$( grep -cE '^  (has_many|attr_accessor) :' "$TMP/rb/post.rb" "$TMP/rb/user.rb" | awk -F: '{s+=$2} END{print s+0}' )
hc="$( "$BIN" "$TMP/rb" --no-cache --uses=has_many 2>/dev/null | grep -oE 'count="[0-9]+"' | head -1 )"
if [ "$h" -ge 3 ] && [ "$hc" = 'count="2"' ]; then ok "(C6) premise: 3 class-body DSL calls, and --uses=has_many answers its 2 call sites ($hc)"
else no "(C6) premise: DSL lines=$h, --uses=has_many ${hc:-refused} — the C6 arms are vacuous or the answer was refused"; fi
for fam in has_many attr_accessor; do
    out="$( rw "$TMP/rb" --uses="$fam" )"
    if printf '%s' "$out" | grep -q 'declared as a member'; then no "(C6) precision: Ruby --uses=$fam read a DSL call as a member declaration: $( printf '%s' "$out" | head -c 300 )"
    else ok "(C6) precision: Ruby --uses=$fam answers; a DSL call with a symbol argument is not a member declaration"; fi
    mo="$( mcp "$TMP/rb" uses ",\"symbol\":\"$fam\"" )"
    if printf '%s' "$mo" | grep -q 'declared as a member'; then no "(C6) precision: MCP uses $fam (rb) refused as a member declaration"
    else ok "(C6) precision: MCP uses $fam (rb) is not refused as a member declaration"; fi
done
# (C7) a member declared on its owner's own opener line; (C8) an object-literal property nested in a member's initializer
# belongs to the literal, not to the class
mkdir -p "$TMP/ts1" "$TMP/ts2"
printf 'export class Opts { limit = 1; }\nexport function lim(o: Opts): number {\n  return o.limit\n}\n' > "$TMP/ts1/opts.ts"
printf 'export class Holder {\n  config = {\n    depth: 1\n  };\n}\nexport function d(h: Holder): number {\n  return h.config.depth\n}\n' > "$TMP/ts2/holder.ts"
l7=$( grep -cw limit "$TMP/ts1/opts.ts" ); l8=$( grep -cw depth "$TMP/ts2/holder.ts" )
if [ "$l7" -ge 2 ] && [ "$l8" -ge 2 ]; then ok "(C7/C8) premise: limit and depth are declared and used ($l7/$l8 lines)"; else no "(C7/C8) premise: fixtures lost their uses ($l7/$l8)"; fi
out="$( rw "$TMP/ts1" --uses=limit )"
if printf '%s' "$out" | grep -q "'limit' is declared as a member of 'Opts' at .*opts.ts:1"; then ok "(C7) CLI --uses=limit: a member on the owner's opener line refuses with the member sentence"
else no "(C7) CLI --uses=limit (same-line opener): $( printf '%s' "$out" | head -c 300 )"; fi
out="$( rw "$TMP/ts2" --uses=depth )"
if printf '%s' "$out" | grep -q "declared as a member of 'Holder'"; then no "(C8) precision: an object-literal property is named a member of Holder: $( printf '%s' "$out" | head -c 300 )"
else ok "(C8) precision: an object-literal property nested in a member initializer is not a member of the class"; fi
mo="$( mcp "$TMP/ts2" uses ',"symbol":"depth"' )"
if printf '%s' "$mo" | grep -q "declared as a member of 'Holder'"; then no "(C8) precision: MCP uses depth names Holder"; else ok "(C8) precision: MCP uses depth does not name Holder"; fi
# #630 CodeRabbit round, one section per finding (each red on c9c01fcff):
# (C9) a Java initializer READS valueToken (`int seed = valueToken;`): not a member declaration (4553235686)
mkdir -p "$TMP/jv"
printf 'public class Box {\n    int seed = valueToken;\n    int read() { return seed + valueToken; }\n}\n' > "$TMP/jv/Box.java"
c9=$( grep -cw valueToken "$TMP/jv/Box.java" ); jcls="$( "$BIN" "$TMP/jv" --no-cache --defs=Box 2>/dev/null | grep -c 'Box.java' )"
if [ "$c9" -ge 2 ] && [ "$jcls" -ge 1 ]; then ok "(C9) premise: Box is indexed and valueToken is read on $c9 lines"
else no "(C9) premise: Box indexed=$jcls valueToken lines=$c9 — the arm is vacuous"; fi
out="$( rw "$TMP/jv" --uses=valueToken )"
if printf '%s' "$out" | grep -q 'declared as a member'; then no "(C9) precision: a Java initializer's read is named a member declaration: $( printf '%s' "$out" | head -c 300 )"
else ok "(C9) precision: a Java initializer's read of valueToken is not a member declaration"; fi
# (C10) `'{'` and `` `{` `` in a TS class body are strings, not braces: the real member at depth 1 still refuses (4553235701);
# (C12) control for the walk's char-literal rule: a Rust lifetime `'a` is not a quote, the member still refuses
mkdir -p "$TMP/tsq" "$TMP/rsl/src"
printf "export class Box {\n  label = '{';\n  tpl = \`{\`;\n  valueToken: number = 0;\n}\nexport function v(b: Box): number {\n  return b.valueToken\n}\n" > "$TMP/tsq/box.ts"
printf "pub struct View<'a> { pub rows: &'a str, }\npub fn n(v: &View) -> usize {\n    v.rows.len()\n}\n" > "$TMP/rsl/src/lib.rs"
c10=$( grep -c "'{'" "$TMP/tsq/box.ts" ); c12=$( grep -c "<'a>" "$TMP/rsl/src/lib.rs" )
if [ "$c10" -eq 1 ] && [ "$c12" -eq 1 ]; then ok "(C10/C12) premise: a quoted brace and a lifetime are in their fixtures"
else no "(C10/C12) premise: quoted brace=$c10 lifetime=$c12 — the arms are vacuous"; fi
out="$( rw "$TMP/tsq" --uses=valueToken )"
if printf '%s' "$out" | grep -q "'valueToken' is declared as a member of 'Box' at .*box.ts:4"; then ok "(C10) CLI --uses=valueToken: quoted braces open no depth, the member at box.ts:4 refuses"
else no "(C10) CLI --uses=valueToken (quoted braces): $( printf '%s' "$out" | head -c 300 )"; fi
out="$( rw "$TMP/rsl" --uses=rows )"
if printf '%s' "$out" | grep -q "'rows' is declared as a member of 'View' at .*lib.rs:1"; then ok "(C12) control: a Rust lifetime is not a quote, --uses=rows still refuses with the member sentence"
else no "(C12) control: --uses=rows (Rust lifetime): $( printf '%s' "$out" | head -c 300 )"; fi
# (C11) a member commented out inside a `/* … */` spanning lines declares nothing (4553235721)
mkdir -p "$TMP/tsc"
printf 'export class Box {\n  /*\n  valueToken: number;\n  */\n  size = 1;\n}\nexport function v(b: any): number {\n  return b.valueToken\n}\n' > "$TMP/tsc/box.ts"
c11=$( grep -c '^  valueToken: number;' "$TMP/tsc/box.ts" )
if [ "$c11" -eq 1 ]; then ok "(C11) premise: the commented-out member line is in the fixture"; else no "(C11) premise: lost the commented-out member ($c11) — the arm is vacuous"; fi
out="$( rw "$TMP/tsc" --uses=valueToken )"
if printf '%s' "$out" | grep -q 'declared as a member'; then no "(C11) precision: a commented-out member is named a declaration: $( printf '%s' "$out" | head -c 300 )"
else ok "(C11) precision: a member inside a multi-line /* */ declares nothing"; fi
mo="$( mcp "$TMP/tsc" uses ',"symbol":"valueToken"' )"
if printf '%s' "$mo" | grep -q 'declared as a member'; then no "(C11) precision: MCP uses valueToken names the commented-out member"; else ok "(C11) precision: MCP uses valueToken does not name the commented-out member"; fi

# (C13) USES-DECL-SCAN-CAPPED (CodeRabbit #630 4553235778): past the 16 MiB member-declaration budget the served external="1"
# answer says the scan stopped (decl_scan="capped"), CLI and MCP; a small corpus of the same shape carries no such attribute.
# Five 3.6 MiB TS classes that CALL zz_capped_name (no member declares it); generated here, never committed. Red on main cd04d477e.
mkdir -p "$TMP/declcap" "$TMP/declsmall"
for k in 1 2 3 4 5; do
    awk -v k=$k 'BEGIN { printf "export class Big%d {\n    run(): number { return zz_capped_name(); }\n", k; for( i = 0; i < 45000; ++i ) printf "    // padding padding padding padding padding padding padding padding %05d\n", i; printf "}\n" }' > "$TMP/declcap/big$k.ts"
done
printf 'export class Small {\n    run(): number { return zz_capped_name(); }\n}\n' > "$TMP/declsmall/small.ts"
cb=$( cat "$TMP"/declcap/*.ts | wc -c | tr -d ' ' ); mx=$( wc -c "$TMP"/declcap/*.ts | awk '$2 != "total" && $1 > m { m = $1 } END { print m + 0 }' )
if [ "$cb" -gt 16777216 ] && [ "$mx" -lt 4194304 ]; then ok "(C13) premise: $cb bytes of TS classes calling zz_capped_name (past the 16 MiB budget, each file under 4 MiB)"
else no "(C13) premise: $cb bytes, largest file $mx — the budget cannot trip"; fi
out="$( rw "$TMP/declcap" --uses=zz_capped_name )"   # status: --uses exit status is not the contract here; the <uses> attributes are the verdict and an empty answer FAILs
if printf '%s' "$out" | grep -q '<uses [^>]*external="1"[^>]* decl_scan="capped"' && printf '%s' "$out" | grep -q 'decl_scan="\{0,1\}capped"\{0,1\}: the scan'; then ok "(C13) CLI --uses: past the budget the external answer carries decl_scan=\"capped\" and its legend"
else no "(C13) CLI --uses past the budget: $( printf '%s' "$out" | grep -o '<uses [^>]*>' | head -1 )"; fi
mo="$( mcp "$TMP/declcap" uses ',"symbol":"zz_capped_name"' )"   # status: the MCP reply text is the verdict; an empty reply FAILs
if printf '%s' "$mo" | grep -q 'external=\\"1\\"[^>]* decl_scan=\\"capped\\"'; then ok "(C13) MCP uses: past the budget the external answer carries decl_scan=\"capped\""
else no "(C13) MCP uses past the budget: $( printf '%s' "$mo" | grep -o '<uses [^>]*>' | head -1 | head -c 300 )"; fi
out="$( rw "$TMP/declsmall" --uses=zz_capped_name )"   # status: --uses exit status is not the contract here; the <uses> attributes are the verdict and an empty answer FAILs
if printf '%s' "$out" | grep -q '<uses [^>]*external="1"' && ! printf '%s' "$out" | grep -q 'decl_scan'; then ok "(C13) precision: a small corpus's external answer carries no decl_scan="
else no "(C13) precision: small corpus: $( printf '%s' "$out" | grep -o '<uses [^>]*>' | head -1 )"; fi

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
