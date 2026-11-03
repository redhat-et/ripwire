#!/usr/bin/env bash
# hop1check.sh — ONE backward hop provider (src/backhops.h), three consumers: --path's hedged bridge, --path's root next=,
# --impact's hedged slot ring; and #11, the builtin-name skip of declined crossings narrowed to a receiver the index types.
#
# THE DEFECT. `--callers=X` named, one hop per call, who MAY call X without a graph edge (<vr via="slot"> called_by=, <dc>),
# but the answers that join hops ignored it: a three-field-call chain (tmux send-keys: cmd_entry.exec, window_mode.command,
# the command table's .f) printed no bridge, its root next= pointed at gap bodies, and `--impact` said reaches="0" beside its
# own slot row. hono's `this.router.match( … )` was never crossed: `match` is spelled like String.prototype.match.
#
# THE CONTRACT. Every crossing is a hedge: proven="0" on the bridge, via= named (slot | slot-name | declined), its width
# beside it (slot_callers= at most 16, slot_fns= the field's forward width, uncapped / cands= at most 16), and never counted in reachable= / hops= / reaches=. A chain whose every
# crossing is a slot may take 3 crossings; any other keeps 2. The ring is one or two slot hops back, reaches_hedged= beside
# reaches=, <ring d="2"> rows after the <vrs> rows. #11 lifts the builtin skip only for one field of this/self or of a
# parameter whose class the source states, every same-named class typing it as an in-tree class, on a Ladder decline with a
# complete list (2..16).
#
# ARMS
#   (B1) 3-slot chain: bridge crossings=3, every row via="slot" slot_callers="1"; root reachable="0" hops="0".
#   (B2) one step past the slot bound (4 slot crossings): no bridge; the 3-step chain in the same tree keeps it (checklist 38).
#   (B3) a mixed chain (value + slot + slot = 3 crossings, not all slot): no bridge; value + slot (2) keeps one.
#   (B4) width: a field called through by 17 functions is not crossed; by 16 it is (slot_callers="16").
#   (B5) slot-name (one side's struct type unknown): via="slot-name".
#   (B6) position-breaker: a positional entry after a preprocessor conditional is not joined, so not crossed; the twin is.
#   (B7) escape-and-cast: a call through a cast receiver is not crossed; the same call through a typed local is.
#   (B8) same field name in another struct: not crossed; the same struct's caller is.
#   (D1) #11: `this.router.match( m )` (router!: Router, an in-tree interface; a Ladder decline over 2 routers) is crossed.
#   (D2) the same field read off a parameter whose class is stated (`app: App`) is crossed.
#   (D3) `path.match( /x/ )` (path: string), (D4) an un-annotated local, (D5) `this.name.match( re )` (name: string): not crossed.
#   (D6) entity identity: a second class named App typing router as a Map makes the parameter shape undecided (not crossed),
#        while `this.router` inside the first App stays crossed (owner by definition, not by name).
#   (D7) a typed receiver over 17 candidates is no bridge crossing, but near_sink names the declined call (why=declined:N), never external (r1-followup).
#   (D8) near_sink counts exactly the crossed sites (why="declined:2").
#   (N1) to= with a slot hop: the root next= is --callers on to=; (N2) a to= with none keeps --expand; (N3) both legend forms.
#   (I1) --impact ring: reaches="0" reaches_hedged="3" (composed hops: the third field hop), two <rh> rows; (I2) a ring member already in reaches= is not counted;
#   (I3) no slot row: no reaches_hedged=, no <ring>; (I4) JSON twin, same names; (I5) columnar count; (I6) row cap 16 + next=.
#   (M1) MCP path_between: the same <bridge> and next= as the CLI; (M2) MCP impact: the same reaches_hedged= and <ring>.
#   (X1) ring cycle guard: a d=1 function is never reprinted as d=2 (ringcyc); (X2) slot_fns= prints the forward width, uncapped (fan);
#   (X3) next= keeps --expand past 16 backward callers; (L3) the legends say exactly what is capped and define slot_fns=.
#   (L1) full legends carry the slot / ring / callers-next sentences and parse as XML; (L2) compact legends define the terms.
#
# Usage: test/hop1check.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "hop1check: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "  FAIL  python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── fixtures ────────────────────────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$TMP/ringcyc" "$TMP/fan" "$TMP/c3" "$TMP/mix" "$TMP/w16" "$TMP/w17" "$TMP/neg" "$TMP/known" "$TMP/cap" "$TMP/ts/routers" "$TMP/ts/app" \
         "$TMP/ts2/routers" "$TMP/ts2/app" "$TMP/ts2/other" "$TMP/wide/routers" "$TMP/wide/app"
cat > "$TMP/c3/chain.c" <<'EOF'
struct entry { const char *name; void (*exec)( void ); };
struct mode { const char *name; void (*command)( int ); };
struct cmdt { const char *name; void (*f)( void ); };
struct wme { const struct mode *mode; };
struct q { void (*run)( struct entry * ); };

struct wme *current_wme( void );

static void cancel_cmd( void ) { }
static void other_cmd( void ) { }
static const struct cmdt cmd_table[] = { { "cancel", cancel_cmd }, { "other", other_cmd } };

void copy_command( int i )
{
    cmd_table[i].f();
}
const struct mode copy_mode = { .name = "copy", .command = copy_command };

void send_keys_exec( void )
{
    struct wme *w = current_wme();
    w->mode->command( 0 );
}
const struct entry send_keys_entry = { .name = "send-keys", .exec = send_keys_exec };

void fire_command( struct entry *e )
{
    e->exec();
}
const struct q top_q = { .run = fire_command };

void top_level( struct q *x )
{
    x->run( 0 );
}

static void lonely( void ) { }
EOF
# mix: start hands send_keys_exec to an external API (a value crossing), then two slot crossings to cancel_cmd
cp "$TMP/c3/chain.c" "$TMP/mix/chain.c"
cat >> "$TMP/mix/chain.c" <<'EOF'
void register_callback( void ( *cb )( void ) );
void start( void )
{
    register_callback( send_keys_exec );
}
EOF
# known: send_keys_exec ALSO calls copy_command directly — a proven caller the ring must not count again
cat > "$TMP/known/k.c" <<'EOF'
struct entry { void (*exec)( void ); };
struct mode { void (*command)( int ); };
struct wme { const struct mode *mode; };
struct wme *current_wme( void );
void copy_command( int i ) { }
const struct mode copy_mode = { .command = copy_command };
void send_keys_exec( void )
{
    struct wme *w = current_wme();
    w->mode->command( 0 );
    copy_command( 1 );
}
const struct entry send_keys_entry = { .exec = send_keys_exec };
void fire_command( struct entry *e ) { e->exec(); }
EOF
# ring cycle guard (review B1): fa and fb both call sink through A.act (d=1); fb is stored in B.go, which fa calls through, so the
# d=2 walk meets fa again from fb. self_ref calls through the field it is stored in.
cat > "$TMP/ringcyc/r.c" <<'EOF'
struct A { void (*act)( void ); };
struct B { void (*go)( void ); };
const struct A *ga( void );
const struct B *gb( void );
void sink( void ) { }
const struct A SA = { .act = sink };
void fb( void ) { const struct A *a = ga(); a->act(); }
const struct B SB = { .go = fb };
void fa( void ) { const struct A *a = ga(); a->act(); const struct B *b = gb(); b->go(); }
void self_ref( void );
struct C { void (*me)( void ); };
const struct C *gc( void );
const struct C SC = { .me = self_ref };
void self_ref( void ) { const struct C *c = gc(); c->me(); }
EOF
# forward width (review B2): 20 functions stored in ops.run, one caller calls through it — the crossing is 1 caller of 20 functions
{
    echo 'struct ops { const char *name; void (*run)( void ); };'
    i=0; while [ "$i" -lt 20 ]; do printf 'void h%d( void ) { }\n' "$i"; i=$(( i + 1 )); done
    echo 'static const struct ops table[] = {'
    i=0; while [ "$i" -lt 20 ]; do printf '  { "h%d", h%d }%s\n' "$i" "$i" "$( [ "$i" -lt 19 ] && echo , )"; i=$(( i + 1 )); done
    echo '};'
    echo 'const struct ops *pick( int i );'
    echo 'void dispatch( int i ) { const struct ops *o = pick( i ); o->run(); }'
    echo 'int main( void ) { dispatch( 3 ); return 0; }'
} > "$TMP/fan/fan.c"
# width: a field the sink is stored in, called through by 16 (w16) or 17 (w17) functions
for n in 16 17; do
    {
        echo 'struct hooks { void (*cb)( void ); };'
        echo 'static void sink( void ) { }'
        echo 'const struct hooks h = { .cb = sink };'
        i=1; while [ "$i" -le "$n" ]; do printf 'void c%02d( struct hooks *x ) { x->cb(); }\n' "$i"; i=$(( i + 1 )); done
    } > "$TMP/w$n/w.c"
done
# cap: 17 functions call through the field copy_command is stored in — the ring's d=2 rows cut at 16
{
    echo 'struct mode { void (*command)( int ); };'
    echo 'struct cmdt { void (*f)( void ); };'
    echo 'struct wme { const struct mode *mode; };'
    echo 'struct wme *current_wme( void );'
    echo 'static void cancel_cmd( void ) { }'
    echo 'static const struct cmdt cmd_table[] = { { cancel_cmd } };'
    echo 'void copy_command( int i ) { cmd_table[i].f(); }'
    echo 'const struct mode copy_mode = { .command = copy_command };'
    i=1; while [ "$i" -le 17 ]; do printf 'void k%02d( void ) { struct wme *w = current_wme(); w->mode->command( 0 ); }\n' "$i"; i=$(( i + 1 )); done
} > "$TMP/cap/cap.c"
cat > "$TMP/neg/neg.c" <<'EOF'
struct A { void (*cb)( void ); };
struct B { void (*cb)( void ); };
struct ops { int a; int b; void (*run)( void ); };

static void sink_a( void ) { }
const struct A a_hooks = { .cb = sink_a };
void call_a( struct A *a ) { a->cb(); }
void call_b( struct B *b ) { b->cb(); }

static void sink_pos( void ) { }
const struct ops pos_ok = { 1, 2, sink_pos };
void call_pos( struct ops *p ) { p->run(); }

static void sink_ifdef( void ) { }
const struct ops pos_bad = { 1,
#ifdef EXTRA
    3,
#endif
    2, sink_ifdef };
void call_ifdef( struct ops *p ) { p->run(); }

void call_cast( void *p ) { ( (struct ops *)p )->run(); }
void call_typed( void *p ) { struct ops *q = p; q->run(); }
EOF
# ts: the hono shape (#11)
cat > "$TMP/ts/routers/router.ts" <<'EOF'
export interface Router {
  match(method: string): string
}
EOF
for x in a b; do
cat > "$TMP/ts/routers/$x.ts" <<EOF
import type { Router } from './router'
export class ${x}Router implements Router {
  match(method: string): string {
    return method + '$x'
  }
}
EOF
done
cat > "$TMP/ts/app/app.ts" <<'EOF'
import type { Router } from '../routers/router'
import { aRouter } from '../routers/a'
import { bRouter } from '../routers/b'

export class App {
  router!: Router
  name: string = 'app'
  constructor() {
    this.router = Math.random() > 0.5 ? new aRouter() : new bRouter()
  }
  dispatch(method: string): string {
    return this.router.match(method)
  }
  label(re: RegExp): boolean {
    return this.name.match(re) !== null
  }
}

export function viaParam(app: App): string {
  return app.router.match('GET')
}

export function onString(path: string): boolean {
  return path.match(/x/) !== null
}

export function onLocal(): boolean {
  const p = 'abc'
  return p.match(/b/) !== null
}
EOF
cp "$TMP/ts/routers/"*.ts "$TMP/ts2/routers/"
cp "$TMP/ts/app/app.ts" "$TMP/ts2/app/app.ts"
cat > "$TMP/ts2/other/app.ts" <<'EOF'
export class App {
  router: Map<string, string> = new Map()
}
EOF
# wide: 17 routers, every one imported by the app — a typed receiver over 17 candidates
{
    echo "export interface Router {"; echo "  match(method: string): string"; echo "}"
} > "$TMP/wide/routers/router.ts"
imports=""
i=1; while [ "$i" -le 17 ]; do
    printf "import type { Router } from './router'\nexport class R%02d implements Router {\n  match(method: string): string {\n    return method\n  }\n}\n" "$i" > "$TMP/wide/routers/r$i.ts"
    imports="${imports}import { R$( printf '%02d' "$i" ) } from '../routers/r$i'
"
    i=$(( i + 1 ))
done
{
    echo "import type { Router } from '../routers/router'"
    printf '%s' "$imports"
    echo "export class App {"
    echo "  router!: Router"
    echo "  dispatch(method: string): string {"
    echo "    return this.router.match(method)"
    echo "  }"
    echo "}"
} > "$TMP/wide/app/app.ts"

python3 - "$BIN" "$TMP" "$ROOT" <<'PY'
import json, re, shutil, subprocess, sys
binp, tmp, repo = sys.argv[1], sys.argv[2], sys.argv[3]
fail = 0
def ok( m ): print( "  PASS  " + m )
def no( m ):
    global fail
    fail = 1
    print( "  FAIL  " + m )
def run( d, *args ):
    """One answer, read only off a run that succeeded and printed a root (checklist 14)."""
    p = subprocess.run( [ binp, d, "--no-cache", *args ], cwd = d, capture_output = True, text = True, timeout = 300 )
    if p.returncode != 0 or not re.search( r'<(path|impact|callers) |^\{"of"', p.stdout ):
        return None
    return p.stdout
def body( t ):
    return re.sub( r'<!--.*?-->', '', t, flags = re.S )
def bridge( t ):
    m = re.search( r'<bridge .*?</bridge>', body( t ) )
    return m.group( 0 ) if m else ""
def root( t, tag ):
    m = re.search( r'<' + tag + r' [^>]*>', body( t ) )
    return m.group( 0 ) if m else ""
def attr( el, name ):
    m = re.search( r'\s' + name + r'="([^"]*)"', el )
    return m.group( 1 ) if m else None
def check( label, cond, detail = "" ):
    ( ok if cond else no )( label + ( "" if cond else " — " + detail ) )

def path( d, a, b, *extra ):
    t = run( d, "--path=%s,%s" % ( a, b ), *extra )
    return t if t is not None else ""

# ── B: the bridge's slot crossings ──────────────────────────────────────────────────────────────────────────────────
c3 = tmp + "/c3"
t = path( c3, "fire_command", "cancel_cmd" ); br = bridge( t ); r = root( t, "path" )
rows = re.findall( r'<s [^>]*/>', br )
check( "(B1) a 3-slot chain is bridged: crossings=3, every crossing via=slot slot_callers=1, proven=0",
       attr( br, "crossings" ) == "3" and attr( br, "proven" ) == "0" and len( rows ) == 4
       and all( 'via="slot" slot_callers="1"' in x for x in rows[1:] )
       and [ attr( x, "n" ) for x in rows ] == [ "fire_command", "send_keys_exec", "copy_command", "cancel_cmd" ], repr( br ) )
check( "(B1) the root stays reachable=0 hops=0 (a bridge is in no count)", attr( r, "reachable" ) == "0" and attr( r, "hops" ) == "0", r )
t4 = path( c3, "top_level", "cancel_cmd" ); t3 = path( c3, "top_level", "copy_command" )
check( "(B2) one step past the slot bound (4 slot crossings): no bridge", t4 != "" and bridge( t4 ) == "" and attr( root( t4, "path" ), "reachable" ) == "0", repr( bridge( t4 ) ) )
check( "(B2) one step short (3 slot crossings) in the same tree: the bridge stays", attr( bridge( t3 ), "crossings" ) == "3", repr( bridge( t3 ) ) )
mix = tmp + "/mix"
tm3 = path( mix, "start", "cancel_cmd" ); tm2 = path( mix, "start", "copy_command" )
check( "(B3) a mixed chain of 3 crossings (value + slot + slot) is not bridged", tm3 != "" and bridge( tm3 ) == "", repr( bridge( tm3 ) ) )
check( "(B3) value + slot (2 crossings) is", re.search( r'n="send_keys_exec"[^>]*via="value" cands="1".*n="copy_command"[^>]*via="slot" slot_callers="1"', bridge( tm2 ) ) is not None, repr( bridge( tm2 ) ) )
t17 = path( tmp + "/w17", "c01", "sink" ); t16 = path( tmp + "/w16", "c01", "sink" )
check( "(B4) a field 17 functions call through is not crossed", t17 != "" and bridge( t17 ) == "", repr( bridge( t17 ) ) )
check( "(B4) a field 16 functions call through is (slot_callers=16)", 'via="slot" slot_callers="16"' in bridge( t16 ), repr( bridge( t16 ) ) )
sj = repo + "/test/slotjoinfix"
ts5 = path( sj, "run_nest", "on_go" )   # FN-SLOT S2: run_outer's nested literal is typed now; set_go's store (g_unknown) is untyped
check( "(B5) a slot joined by field name only is crossed as via=slot-name", 'n="on_go" p="mode.c:12" via="slot-name" slot_callers="1"' in bridge( ts5 ), repr( bridge( ts5 ) ) )
neg = tmp + "/neg"
def crossed( a, b ):
    return bridge( path( neg, a, b ) ) != ""
def not_crossed( a, b ):
    t = path( neg, a, b )   # a negative arm needs its premise too: a failed run (or a mistyped symbol) answers "" and would pass
    return t != "" and bridge( t ) == ""
check( "(B6) a positional entry after a preprocessor conditional is not crossed", not_crossed( "call_ifdef", "sink_ifdef" ) )
check( "(B6) its twin without the conditional is", crossed( "call_pos", "sink_pos" ) )
check( "(B7) a call through a cast receiver is not crossed", not_crossed( "call_cast", "sink_pos" ) )
check( "(B7) the same call through a typed local is", crossed( "call_typed", "sink_pos" ) )
check( "(B8) a same-named field of ANOTHER struct is not crossed", not_crossed( "call_b", "sink_a" ) )
check( "(B8) the same struct's caller is", crossed( "call_a", "sink_a" ) )

# ── D: #11, the builtin-name skip narrowed ──────────────────────────────────────────────────────────────────────────
ts = tmp + "/ts"
def tsbridge( d, a ):
    return bridge( path( d, a, "routers/a.ts:match" ) )
check( "(D1) this.router.match (router!: Router, in-tree) is crossed via=declined cands=2",
       'n="match" p="routers/a.ts:3" via="declined" cands="2"' in tsbridge( ts, "dispatch" ), repr( tsbridge( ts, "dispatch" ) ) )
check( "(D2) app.router.match on a parameter typed App is crossed", 'via="declined" cands="2"' in tsbridge( ts, "viaParam" ), repr( tsbridge( ts, "viaParam" ) ) )
check( "(D3) path.match( /x/ ) on a parameter typed string is not crossed", tsbridge( ts, "onString" ) == "" and path( ts, "onString", "routers/a.ts:match" ) != "" )
check( "(D4) p.match( /b/ ) on an un-annotated local is not crossed", tsbridge( ts, "onLocal" ) == "" and path( ts, "onLocal", "routers/a.ts:match" ) != "" )
check( "(D5) this.name.match( re ) (name: string) is not crossed", tsbridge( ts, "label" ) == "" and path( ts, "label", "routers/a.ts:match" ) != "" )
ts2 = tmp + "/ts2"
check( "(D6) a second class App typing router as a Map (not an in-tree class) leaves the parameter shape undecided (not crossed)",
       tsbridge( ts2, "viaParam" ) == "" and path( ts2, "viaParam", "routers/a.ts:match" ) != "" )
check( "(D6) this.router inside the first App stays crossed (owner by definition, not by name)", 'via="declined" cands="2"' in tsbridge( ts2, "dispatch" ), repr( tsbridge( ts2, "dispatch" ) ) )
tw = path( tmp + "/wide", "dispatch", "routers/r1.ts:match" )
nsw = re.search( r'<near_sink .*?</near_sink>', body( tw ) )
check( "(D7) a typed receiver over 17 candidates is no bridge crossing, and its near_sink row names the declined call (why=declined:1 in=dispatch), not external",
       tw != "" and bridge( tw ) == "" and nsw is not None and 'why="declined:1"' in nsw.group( 0 ) and 'in="dispatch"' in nsw.group( 0 ) and 'why="external"' not in nsw.group( 0 ), repr( body( tw )[-400:] ) )
td = path( ts, "onString", "routers/a.ts:match" )
check( "(D8) near_sink counts exactly the two crossed sites (why=declined:2)", 'why="declined:2"' in body( td ), repr( re.findall( r'<ns [^>]*>', body( td ) ) ) )

# ── X: review fixes (fix round 1) ───────────────────────────────────────────────────────────────────────────────────
trc = run( tmp + "/ringcyc", "--impact=sink" ) or ""; rrc = root( trc, "impact" )
check( "(X1) ring cycle guard: fa and fb are both d=1, so reaches_hedged=2 and NO <ring> (a d=1 function is not printed again as d=2)",
       attr( rrc, "reaches_hedged" ) == "2" and "<ring" not in body( trc ) and "<rh " not in body( trc ), rrc + " " + repr( body( trc )[-300:] ) )
tsr = run( tmp + "/ringcyc", "--impact=self_ref" ) or ""
check( "(X1) a function that calls through the field it is stored in is not its own ring row", tsr != "" and "<rh " not in body( tsr ), repr( body( tsr )[-300:] ) )
tfan = path( tmp + "/fan", "main", "h7" ); bfan = bridge( tfan )
check( "(X2) the forward width is printed, uncapped: 1 caller of a field holding 20 functions (slot_callers=1 slot_fns=20), still crossed",
       'n="h7"' in bfan and 'via="slot" slot_callers="1" slot_fns="20"' in bfan and attr( bfan, "proven" ) == "0", repr( bfan ) )
check( "(X2) slot_fns= rides on every slot row of the 3-slot chain and on no other row",
       len( re.findall( r'slot_fns=', bridge( path( c3, "fire_command", "cancel_cmd" ) ) ) ) == 3 and "slot_fns" not in bridge( path( mix, "start", "copy_command" ) ).split( 'via="slot"' )[ 0 ], "" )
t17r = path( tmp + "/w17", "c01", "sink" ); t16r = path( tmp + "/w16", "c01", "sink" )
check( "(X3) next= keeps --expand when to='s backward set is wider than 16 (w17), and is --callers at 16 (w16)",
       ( attr( root( t17r, "path" ), "next" ) or "" ).startswith( "--expand=" ) and ( attr( root( t16r, "path" ), "next" ) or "" ).startswith( "--callers=" ),
       repr( ( attr( root( t17r, "path" ), "next" ), attr( root( t16r, "path" ), "next" ) ) ) )

# ── N: the root next= ───────────────────────────────────────────────────────────────────────────────────────────────
t = path( c3, "fire_command", "cancel_cmd" ); r = root( t, "path" )
check( "(N1) to= with a slot hop: the root next= is --callers on to=", attr( r, "next" ) == "--callers=chain.c:cancel_cmd", repr( attr( r, "next" ) ) )
tl = path( c3, "fire_command", "lonely" ); rl = root( tl, "path" )
check( "(N2) to= with no backward hop keeps the gap bodies next=", ( attr( rl, "next" ) or "" ).startswith( "--expand=" ) and attr( rl, "gaps" ) is not None, repr( rl ) )
tf = path( c3, "fire_command", "cancel_cmd", "--legend=full" ); tlf = path( c3, "fire_command", "lonely", "--legend=full" )
check( "(N3) the full legend says next= lists to='s callers exactly when it does, and reads the bodies otherwise",
       "next= lists to='s callers" in tf and "next= reads the rows' bodies" not in tf
       and "next= reads the rows' bodies" in tlf and "next= lists to='s callers" not in tlf )

# ── I: the --impact hedged slot ring ────────────────────────────────────────────────────────────────────────────────
ti = run( c3, "--impact=cancel_cmd" ) or ""; ri = root( ti, "impact" )
# composed hops (by design): the chain is field-only and narrow, so the ring takes the THIRD slot hop (fire_command, d=3): 2 -> 3,
# and every ring row prints its forward width (slot_fns=). The two-hop row is still the first row, byte for byte up to slot_fns=.
check( "(I1) reaches stays 0, reaches_hedged=3 beside it (d=1, d=2 and the composed d=3 field hop)", attr( ri, "reaches" ) == "0" and attr( ri, "reaches_hedged" ) == "3", ri )
check( "(I1) one d=2 row: send_keys_exec may call copy_command through a field at chain.c:22",
       '<ring d="3" total="2" shown="2"><rh called_by="send_keys_exec" called_at="chain.c:22" via="slot" calls="copy_command" slot_fns="1"/>'
       '<rh called_by="fire_command" called_at="chain.c:28" via="slot" calls="send_keys_exec" d="3" slot_fns="1"/></ring>' in body( ti ), repr( body( ti )[-500:] ) )
tk = run( tmp + "/known", "--impact=copy_command" ) or ""; rk = root( tk, "impact" )
check( "(I2) a ring member already in reaches= is not counted again (reaches=1, reaches_hedged=1)",
       attr( rk, "reaches" ) == "1" and attr( rk, "reaches_hedged" ) == "1" and '<rh called_by="fire_command"' in body( tk ), rk + " " + repr( body( tk )[-300:] ) )
tn = run( c3, "--impact=top_level" ) or ""
check( "(I3) a function with no slot row carries neither reaches_hedged= nor <ring>",
       tn != "" and "reaches_hedged" not in tn and "<ring" not in tn )
tj = run( c3, "--impact=cancel_cmd", "--json" ) or "{}"
try:
    j = json.loads( tj )
except ValueError:
    j = {}
check( "(I4) the JSON twin carries the same names",
       j.get( "reaches" ) == 0 and j.get( "reaches_hedged" ) == 3
       and j.get( "ring", {} ).get( "rows" ) == [ { "called_by": "send_keys_exec", "called_at": "chain.c:22", "via": "slot", "calls": "copy_command", "slot_fns": 1 },
                                                  { "called_by": "fire_command", "called_at": "chain.c:28", "via": "slot", "calls": "send_keys_exec", "d": 3, "slot_fns": 1 } ], repr( tj[:400] ) )
tc = run( c3, "--impact=cancel_cmd", "--format=columnar" ) or ""
check( "(I5) the columnar form carries reaches_hedged=3", 'reaches_hedged="3"' in tc, repr( tc[:300] ) )
tcap = run( tmp + "/cap", "--impact=cancel_cmd" ) or ""; ring = re.search( r'<ring [^>]*>', body( tcap ) )
check( "(I6) 17 two-hop rows: shown=16 of total=17, next= the callers of the first unshown row's calls=",
       ring is not None and attr( ring.group( 0 ), "total" ) == "17" and attr( ring.group( 0 ), "shown" ) == "16"
       and attr( ring.group( 0 ), "next" ) == "--callers=copy_command" and len( re.findall( r'<rh ', body( tcap ) ) ) == 16, repr( ring.group( 0 ) if ring else tcap[-300:] ) )

# ── M: the MCP twins ────────────────────────────────────────────────────────────────────────────────────────────────
reqs = [ { "jsonrpc": "2.0", "id": 0, "method": "initialize", "params": { "protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": { "name": "g", "version": "1" } } },
         { "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": { "name": "path_between", "arguments": { "path": c3, "from": "fire_command", "to": "cancel_cmd" } } },
         { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": "path_between", "arguments": { "path": ts, "from": "dispatch", "to": "routers/a.ts:match" } } },
         { "jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": { "name": "impact", "arguments": { "path": c3, "symbol": "cancel_cmd" } } } ]
p = subprocess.run( [ binp, "--mcp", "--mcp-legend=inline" ], input = "".join( json.dumps( x ) + "\n" for x in reqs ), capture_output = True, text = True, timeout = 300 )
resp = {}
for line in p.stdout.splitlines():
    try:
        o = json.loads( line )
    except ValueError:
        continue
    if isinstance( o.get( "id" ), int ) and o[ "id" ] > 0:
        resp[ o[ "id" ] ] = "".join( c.get( "text", "" ) for c in o.get( "result", {} ).get( "content", [] ) )
m1, m2, m3 = resp.get( 1, "" ), resp.get( 2, "" ), resp.get( 3, "" )
cli1 = path( c3, "fire_command", "cancel_cmd" ); cli2 = path( ts, "dispatch", "routers/a.ts:match" )
check( "(M1) MCP path_between: the same <bridge> and root next= as the CLI (slot chain and #11 crossing)",
       bridge( m1 ) != "" and bridge( m1 ) == bridge( cli1 ) and attr( root( m1, "path" ), "next" ) == attr( root( cli1, "path" ), "next" )
       and bridge( m2 ) != "" and bridge( m2 ) == bridge( cli2 ), repr( ( bridge( m1 )[:200], bridge( m2 )[:200] ) ) )
cli3 = run( c3, "--impact=cancel_cmd" ) or ""
ringm = re.search( r'<ring .*?</ring>', body( m3 ) ); ringc = re.search( r'<ring .*?</ring>', body( cli3 ) )
check( "(M2) MCP impact: the same reaches_hedged= and <ring> as the CLI",
       attr( root( m3, "impact" ), "reaches_hedged" ) == "3" and ringm is not None and ringc is not None and ringm.group( 0 ) == ringc.group( 0 ), repr( m3[-400:] ) )

# ── L: legends ──────────────────────────────────────────────────────────────────────────────────────────────────────
pf = path( c3, "fire_command", "cancel_cmd", "--legend=full" )
imf = run( c3, "--impact=cancel_cmd", "--legend=full" ) or ""
check( "(L1) the full path legend names the slot crossing and slot_callers=", "slot_callers=N the functions that field join names" in pf and "3 when every crossing is a slot" in pf )
check( "(L1) the full impact legend names reaches_hedged= and the <ring> rows", "reaches_hedged=N (absent when 0)" in imf and "<ring d=2 total= shown=>" in imf )
if shutil.which( "xmllint" ):
    for label, doc in ( ( "path", pf ), ( "impact", imf ), ( "impact compact", ti ), ( "path compact", t ) ):
        x = subprocess.run( [ "xmllint", "--noout", "-" ], input = doc, capture_output = True, text = True )
        check( "(L1) the %s answer with the new clauses parses as XML (checklist 25)" % label, x.returncode == 0 and doc != "", x.stderr[:300] )
else:
    print( "  SKIP  (L1) xmllint not installed: the well-formedness arm needs it" )
check( "(L2) the compact path legend defines slot_callers=", "s via=slot|slot-name slot_callers=N:" in t )
pfan = path( tmp + "/fan", "main", "h7", "--legend=full" )
check( "(L3) the full bridge legend says exactly what is capped: slot_callers= at 16, slot_fns= not capped; no blanket 'each fanning out to at most 16 candidates'",
       "slot_fns=K the functions the field holds, NOT capped" in pfan and "each slot one bounded on its callers" in pfan
       and "each fanning out to at most 16 candidates" not in pfan and "(at most 16 callers or candidates)" in path( c3, "fire_command", "cancel_cmd", "--legend=full" ), "" )
check( "(L3) the compact path legend defines slot_fns= (not capped)", "slot_fns=K:" in tfan and "NOT capped" in tfan, repr( tfan[ -400: ] ) )
check( "(L3) the MCP twin of the bridge legend carries slot_fns=K too", "slot_fns=K" in m1, repr( m1[ -300: ] ) )
check( "(L3) the full impact legend says the ring's one-hop set has no width bound", "NO width bound" in imf )
check( "(L2) the compact impact legend defines reaches_hedged= and the ring row", "reaches_hedged=N:" in ti and "rh called_by= called_at= via= calls=:" in ti )
sys.exit( fail )
PY
rc=$?   # the harness's own status, read immediately (checklist 14): 0 every arm passed, 1 an arm failed, anything else a crash
fail=0
if [ "$rc" -ne 0 ]; then
    printf '  FAIL  the arm harness exited %s (an arm failed above, or the harness crashed)\n' "$rc"
    fail=1
fi
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
