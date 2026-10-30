#!/usr/bin/env bash
# composedhopscheck.sh — COMPOSED HOPS (src/backhops.h, src/pathgaps.h): the backward hop provider's kinds compose with
# proven edges and with each other, in both walks, and the provider reads forward too.
#
# THE DEFECT. HOP1's ring counted one or two slot hops and stopped: the functions that reach a ring member through ordinary
# proven calls (tmux: cmdq_fire_command's own callers) were not counted, a third slot hop (tmux send-keys) was cut at two, and
# a function called through a table element (`handlers[i]()`) had no ring and no bridge crossing at all — the --callers
# called_by= row named the caller, and nothing joined it. The bridge's third crossing was a slot-only privilege.
#
# THE CONTRACT. Every composed edge keeps one label; a chain with any hedged hop is hedged: reaches= / reachable= / hops= /
# proven= never move. The ring adds the proven callers of members reached past hops of at most 16 callers, a third FIELD hop
# on a field-only narrow chain (d="3"), and the container kind; ring rows print the forward width (slot_fns= / cands=). The
# bridge crosses container calls (cands= at most 16) and lets a declined or container crossing of at most 4 candidates
# compose past two crossings like a slot one; a wider one stays a gap.
#
# ARMS
#   (R1) tail: sink's slot caller `fire` has proven callers a, b (a <-> b a cycle): reaches="0" reaches_hedged="3", no <ring>.
#   (R2) one step short / one past the field depth (checklist 38): d=3 is listed (d="3", slot_fns=), the d=4 slot caller is not.
#   (R3) width: a field called through by 17 functions counts the 17 but composes nothing (17); by 16 it composes their
#        16 proven callers (32).
#   (R4) old-path twin: a chain whose second hop is a container stays at d=2 (no third field hop off a mixed chain).
#   (R5) ring cycle guard holds under composition (fa/fb meet each other): reaches_hedged=2, no <ring>.
#   (K1) container kind in the ring: `handlers[i]()` -> reaches_hedged=2 (run + its proven caller main).
#   (K2) container crossing in the bridge: main -> run -> ha via="container" cands="2", root next= --callers on to=.
#   (K3) container width: a table of 17 functions is not crossed; of 16 it is (cands="16").
#   (K4) container ring row: a d=2 container hop prints via="container" cands=.
#   (B1) a NARROW declined crossing (2 candidates) composes: declined + container + slot = crossings="3".
#   (B2) a WIDE declined crossing (5 candidates) does not compose: the same 3-crossing pair has no bridge, while its 2-crossing
#        prefix keeps one (the width, not the fixture, decides).
#   (B3) the same width rule on a THIRD crossing: slot + slot + a container of 4 composes (crossings="3"), of 5 stays a gap.
#   (P1) a called PARAMETER binds per call site (run( cb ) { cb(); }): a caller passing another function or NULL is no
#        bridge into h0 and no hedged tail; the passer keeps its value crossing.
#   (N1) namesake: two files each with a static `run` over its own table — ha's ring counts only its own run and caller,
#        and the other file's main is no bridge into ha.
#   (H1) hub fold: a slot caller with 20 proven callers prints ONE <hub behind="20" next="--impact=t.c:hubf"/>, its tail is not
#        listed (only the 3 sample names), reaches_hedged=21 unchanged, reaches_hedged_hubs=20, the root next= names the hub;
#        16 proven callers: no <hub> (at the bound), next= stays --safe-delete=.
#   (H2..H5) hub edges: 17 callers folds (one past the bound); two hubs sharing callers count each function once in
#        reaches_hedged_hubs (never above reaches_hedged); the sample is led by a tested caller (not node id order); a member
#        whose tail is only counted d=2 ring rows (17 wide callers) still folds (the early exit tests every counted function).
#   (O1) ring order: a narrow forward width (slot_fns=1) before a wide one (3); a tested row before an untested entry point.
#   (W1) page window: under --limit the proven <s> rows keep the page and the hub is cut first (ring_cut=1, next= the replay);
#        the replay at the named limit shows it and has no ring_cut; no --limit: no ring_cut.
#   (J1) JSON twin of a d=3 row; (M1) MCP impact twin; (L1) legends name the composition and parse as XML.
#
# Usage: test/composedhopscheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "composedhopscheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "  FAIL  python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── fixtures ────────────────────────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$TMP/tail" "$TMP/c4" "$TMP/w16" "$TMP/w17" "$TMP/mixd" "$TMP/ringcyc" "$TMP/tbl" "$TMP/t16" "$TMP/t17" "$TMP/tbl2" \
         "$TMP/nar/core" "$TMP/nar/linux" "$TMP/nar/darwin" "$TMP/wide/core" "$TMP/ns"
cat > "$TMP/tail/t.c" <<'EOF'
struct ops { void (*run)( void ); };
const struct ops *get( void );
void sink( void ) { }
const struct ops S = { .run = sink };
void fire( void ) { const struct ops *o = get(); o->run(); }
void b( void );
void a( void ) { fire(); b(); }
void b( void ) { a(); }
EOF
# a four-slot chain: cancel <- copy (d1) <- send (d2) <- fire (d3) <- top (d4, one past the field depth)
cat > "$TMP/c4/chain.c" <<'EOF'
struct cmdt { void (*f)( void ); };
struct mode { void (*command)( int ); };
struct entry { void (*exec)( void ); };
struct q { void (*run)( struct entry * ); };
const struct cmdt *gt( void );
const struct mode *gm( void );
static void cancel_cmd( void ) { }
const struct cmdt cmd_table = { .f = cancel_cmd };
void copy_command( int i ) { const struct cmdt *t = gt(); t->f(); }
const struct mode copy_mode = { .command = copy_command };
void send_keys_exec( void ) { const struct mode *m = gm(); m->command( 0 ); }
const struct entry send_keys_entry = { .exec = send_keys_exec };
void fire_command( struct entry *e ) { e->exec(); }
const struct q top_q = { .run = fire_command };
void top_level( struct q *x ) { x->run( 0 ); }
EOF
# width: N functions call through o->run, each with its own proven caller c<i>
for n in 16 17; do
    {
        echo 'struct ops { void (*run)( void ); };'
        echo 'const struct ops *get( void );'
        echo 'void sink( void ) { }'
        echo 'const struct ops S = { .run = sink };'
        i=0; while [ "$i" -lt "$n" ]; do printf 'void f%d( void ) { const struct ops *o = get(); o->run(); }\nvoid c%d( void ) { f%d(); }\n' "$i" "$i" "$i"; i=$(( i + 1 )); done
    } > "$TMP/w$n/w.c"
done
# mixed: sink <- mid (slot, d1) <- outer (container, d2) <- top (slot through U.go: would be d3, but the chain is not field-only);
# outer_wrap is outer's proven caller (the tail)
cat > "$TMP/mixd/m.c" <<'EOF'
typedef void (*handler)( void );
struct ops { void (*run)( void ); };
struct up { void (*go)( int ); };
const struct ops *get( void );
const struct up *gu( void );
void sink( void ) { }
const struct ops S = { .run = sink };
void mid( void ) { const struct ops *o = get(); o->run(); }
static handler table[] = { mid };
void outer( int i ) { table[i](); }
void outer_wrap( void ) { outer( 0 ); }
const struct up U = { .go = outer };
void top( void ) { const struct up *u = gu(); u->go(); }
EOF
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
EOF
cat > "$TMP/tbl/tbl.c" <<'EOF'
typedef void (*handler)( void );
void ha( void ) { }
void hb( void ) { }
static handler handlers[] = { ha, hb };
void run( int i ) { handlers[i](); }
int main( int argc, char **argv ) { (void)argv; run( argc ); return 0; }
EOF
for n in 16 17; do
    {
        echo 'typedef void (*handler)( void );'
        i=0; while [ "$i" -lt "$n" ]; do printf 'void h%d( void ) { }\n' "$i"; i=$(( i + 1 )); done
        printf 'static handler handlers[] = {'
        i=0; while [ "$i" -lt "$n" ]; do printf ' h%d,' "$i"; i=$(( i + 1 )); done
        echo ' };'
        echo 'void run( int i ) { handlers[i](); }'
        echo 'int main( int argc, char **argv ) { (void)argv; run( argc ); return 0; }'
    } > "$TMP/t$n/t.c"
done
# a d=2 container hop: top calls outer[0]() which holds run; run calls handlers[i]() which holds ha
cat > "$TMP/tbl2/t.c" <<'EOF'
typedef void (*handler)( void );
typedef void (*runner)( int );
void ha( void ) { }
static handler handlers[] = { ha };
void run( int i ) { handlers[i](); }
static runner outer[] = { run };
void top( void ) { outer[0]( 1 ); }
EOF
# narrow declined (two platform builds of Machine_scan) -> container -> slot
cat > "$TMP/nar/core/machine.c" <<'EOF'
void Machine_scan( void );
void Machine_run( void ) { Machine_scan(); }
EOF
cat > "$TMP/nar/linux/scan.c" <<'EOF'
typedef void (*handler)( void );
struct ops { void (*run)( void ); };
const struct ops *get( void );
void Process_update( void ) { }
const struct ops S = { .run = Process_update };
void scan_step( void ) { const struct ops *o = get(); o->run(); }
void scan_other( void ) { }
static handler steps[] = { scan_step, scan_other };
void Machine_scan( void ) { steps[0](); }
EOF
cat > "$TMP/nar/darwin/scan.c" <<'EOF'
void Machine_scan( void ) { }
EOF
# wide: the same chain, but five platform builds (a declined crossing of 5 candidates)
cp "$TMP/nar/core/machine.c" "$TMP/wide/core/machine.c"
mkdir -p "$TMP/wide/linux"; cp "$TMP/nar/linux/scan.c" "$TMP/wide/linux/scan.c"
for p in darwin freebsd netbsd openbsd; do mkdir -p "$TMP/wide/$p"; echo 'void Machine_scan( void ) { }' > "$TMP/wide/$p/scan.c"; done
# a called PARAMETER: run( cb ) { cb(); } binds per call site — c1 passes h1, never h0; a NULL caller and an unrelated fn bind nothing to h0
mkdir -p "$TMP/param"
{
    echo 'typedef void (*cbt)( void );'
    echo 'void run( cbt cb ) { cb(); }'
    for i in 0 1 2; do printf 'void h%d( void ) { }\nvoid c%d( void ) { run( h%d ); }\nvoid top%d( void ) { c%d(); }\n' "$i" "$i" "$i" "$i" "$i"; done
    echo 'void cnull( void ) { run( NULL ); }'
    echo 'void topnull( void ) { cnull(); }'
} > "$TMP/param/cb.c"
# third crossing: slot + slot + a container called by index holding N functions (N=4 composes, N=5 stays a gap)
for n in 4 5; do
    mkdir -p "$TMP/third$n"
    {
        echo 'typedef void (*handler)( void );'
        echo 'struct s1 { void (*go)( void ); };'
        echo 'struct s2 { void (*run)( void ); };'
        echo 'const struct s1 *g1( void );'
        echo 'const struct s2 *g2( void );'
        echo 'void dst( void ) { }'
        i=1; while [ "$i" -lt "$n" ]; do printf 'void o%d( void ) { }\n' "$i"; i=$(( i + 1 )); done
        printf 'static handler steps[] = { dst'
        i=1; while [ "$i" -lt "$n" ]; do printf ', o%d' "$i"; i=$(( i + 1 )); done
        echo ' };'
        echo 'void cc( void ) { int i = 0; steps[i](); }'
        echo 'const struct s2 S2 = { .run = cc };'
        echo 'void bb( void ) { const struct s2 *x = g2(); x->run(); }'
        echo 'const struct s1 S1 = { .go = bb };'
        echo 'void aa( void ) { const struct s1 *x = g1(); x->go(); }'
    } > "$TMP/third$n/t.c"
done
# hub fold: hubf calls sink through a field and has N proven callers (20: folded; 16: at the bound, not folded); hubp: 3 proven callers too
for n in 16 20; do
    mkdir -p "$TMP/hub$n"
    {
        echo 'struct ops { void (*run)( void ); };'
        echo 'const struct ops *get( void );'
        echo 'void sink( void ) { }'
        echo 'const struct ops S = { .run = sink };'
        echo 'void hubf( void ) { const struct ops *o = get(); o->run(); }'
        i=1; while [ "$i" -le "$n" ]; do printf 'void c%d( void ) { hubf(); }\n' "$i"; i=$(( i + 1 )); done
        [ "$n" = 20 ] && echo 'void p1( void ) { sink(); } void p2( void ) { sink(); } void p3( void ) { sink(); }'
    } > "$TMP/hub$n/t.c"
done
# hub bound edges: hub17 = one past the bound (17 proven callers); hub2 = hubA and hubB share the 18 callers c1..c18 (two hubs);
# hubsmp = 18 callers, the LAST written one (c18) is reached by a test; hubskip = m (d=1) behind a field called by c1..c17 (width 17: wide,
# so each ci is a d=2 ring row, not a composed tail), each ci also calling hubf (d=1) — 17 counted functions that are all wide d=2 rows
mkdir -p "$TMP/hub17" "$TMP/hub2" "$TMP/hubsmp/tests" "$TMP/hubskip"
{
    echo 'struct ops { void (*run)( void ); };'
    echo 'const struct ops *get( void );'
    echo 'void sink( void ) { }'
    echo 'const struct ops S = { .run = sink };'
    echo 'void hubf( void ) { const struct ops *o = get(); o->run(); }'
    i=1; while [ "$i" -le 17 ]; do printf 'void c%d( void ) { hubf(); }\n' "$i"; i=$(( i + 1 )); done
} > "$TMP/hub17/t.c"
{
    echo 'struct ops { void (*run)( void ); };'
    echo 'const struct ops *get( void );'
    echo 'void sink( void ) { }'
    echo 'const struct ops S = { .run = sink };'
    echo 'void hubA( void ) { const struct ops *o = get(); o->run(); }'
    echo 'void hubB( void ) { const struct ops *o = get(); o->run(); }'
    i=1; while [ "$i" -le 18 ]; do printf 'void c%d( void ) { hubA(); hubB(); }\n' "$i"; i=$(( i + 1 )); done
} > "$TMP/hub2/t.c"
{
    echo 'struct ops { void (*run)( void ); };'
    echo 'const struct ops *get( void );'
    echo 'void sink( void ) { }'
    echo 'const struct ops S = { .run = sink };'
    echo 'void hubf( void ) { const struct ops *o = get(); o->run(); }'
    i=1; while [ "$i" -le 18 ]; do printf 'void c%d( void ) { hubf(); }\n' "$i"; i=$(( i + 1 )); done
} > "$TMP/hubsmp/t.c"
printf 'void c18( void );\nvoid test_c18( void ) { c18(); }\n' > "$TMP/hubsmp/tests/test_t.c"
{
    echo 'struct ops { void (*run)( void ); };'
    echo 'struct W { void (*w)( void ); };'
    echo 'const struct ops *get( void );'
    echo 'const struct W *gw( void );'
    echo 'void sink( void ) { }'
    echo 'const struct ops S = { .run = sink };'
    echo 'void m( void ) { const struct ops *o = get(); o->run(); }'
    echo 'void hubf( void ) { const struct ops *o = get(); o->run(); }'
    echo 'const struct W W1 = { .w = m };'
    i=1; while [ "$i" -le 17 ]; do printf 'void c%d( void ) { const struct W *p = gw(); p->w(); hubf(); }\n' "$i"; i=$(( i + 1 )); done
} > "$TMP/hubskip/t.c"
# ring order: m (d=1) is called through a wide field (3 functions) by wcall and a narrow one (1) by ncall, written wide-first;
# ucall (an entry point, untested) and tcall (a test reaches it) each through their own one-function field, written ucall-first
mkdir -p "$TMP/ord/tests"
cat > "$TMP/ord/o.c" <<'EOF'
struct ops { void (*run)( void ); };
struct W { void (*w)( void ); };
struct N { void (*n)( void ); };
struct U { void (*u)( void ); };
struct T { void (*t)( void ); };
const struct ops *get( void );
const struct W *gw( void );
const struct N *gn( void );
const struct U *gu( void );
const struct T *gt( void );
void sink( void ) { }
const struct ops S = { .run = sink };
void m( void ) { const struct ops *o = get(); o->run(); }
void x1( void ) { }
void x2( void ) { }
const struct W W1 = { .w = m };
const struct W W2 = { .w = x1 };
const struct W W3 = { .w = x2 };
const struct N N1 = { .n = m };
const struct U U1 = { .u = m };
const struct T T1 = { .t = m };
void wcall( void ) { const struct W *p = gw(); p->w(); }
void ncall( void ) { const struct N *p = gn(); p->n(); }
void ucall( void ) { const struct U *p = gu(); p->u(); }
void tcall( void ) { const struct T *p = gt(); p->t(); }
EOF
cat > "$TMP/ord/tests/test_o.c" <<'EOF'
void tcall( void );
void test_tcall( void ) { tcall(); }
EOF
# namesake: two files, each a static run over its own table
cat > "$TMP/ns/a.c" <<'EOF'
typedef void (*handler)( void );
void ha( void ) { }
static handler handlers[] = { ha };
static void run( int i ) { handlers[i](); }
void main_a( void ) { run( 0 ); }
EOF
cat > "$TMP/ns/b.c" <<'EOF'
typedef void (*handler)( void );
void hb( void ) { }
static handler handlers[] = { hb };
static void run( int i ) { handlers[i](); }
void main_b( void ) { run( 0 ); }
EOF

python3 - "$BIN" "$TMP" <<'PY'
import json, re, shutil, subprocess, sys
binp, tmp = sys.argv[1], sys.argv[2]
fail = 0
def ok( m ): print( "  PASS  " + m )
def no( m ):
    global fail
    fail = 1
    print( "  FAIL  " + m )
def run( d, *args ):
    """One answer, read only off a run that succeeded and printed a root (checklist 14)."""
    p = subprocess.run( [ binp, d, "--no-cache", *args ], cwd = d, capture_output = True, text = True, timeout = 300 )
    if p.returncode != 0 or not re.search( r'<(path|impact) |^\{"of"', p.stdout ):
        return None
    return p.stdout
def body( t ):
    return re.sub( r'<!--.*?-->', '', t or "", flags = re.S )
def root( t, tag ):
    m = re.search( r'<' + tag + r' [^>]*>', body( t ) )
    return m.group( 0 ) if m else ""
def bridge( t ):
    m = re.search( r'<bridge .*?</bridge>', body( t ) )
    return m.group( 0 ) if m else ""
def ring( t ):
    m = re.search( r'<ring .*?</ring>', body( t ) )
    return m.group( 0 ) if m else ""
def attr( el, name ):
    m = re.search( r'\s' + name + r'="([^"]*)"', el or "" )
    return m.group( 1 ) if m else None
def check( label, cond, detail = "" ):
    ( ok if cond else no )( label + ( "" if cond else " — " + detail ) )
def impact( d, sym, *extra ):
    t = run( d, "--impact=" + sym, *extra )
    return t, root( t, "impact" )
def path( d, a, b, *extra ):
    t = run( d, "--path=%s,%s" % ( a, b ), *extra )
    return t, root( t, "path" )

# ── R: the ring composes ────────────────────────────────────────────────────────────────────────────────────────────
t, r = impact( tmp + "/tail", "sink" )
check( "(R1) the slot caller's proven callers join the hedged count (fire + a + b, a<->b a cycle): reaches=0 reaches_hedged=3, no <ring>",
       t is not None and attr( r, "reaches" ) == "0" and attr( r, "reaches_hedged" ) == "3" and ring( t ) == "", r + " " + ring( t ) )
t, r = impact( tmp + "/c4", "cancel_cmd" )
rg = ring( t )
check( "(R2) one step short of the field depth: the d=3 slot caller fire_command is listed d=\"3\" with its forward width",
       attr( r, "reaches_hedged" ) == "3" and attr( rg, "d" ) == "3"
       and '<rh called_by="fire_command" called_at="chain.c:13" via="slot" calls="send_keys_exec" d="3" slot_fns="1"/>' in rg, r + " " + rg )
check( "(R2) one step past it: top_level (the fourth slot hop) is in no row and not counted (reaches_hedged=3, not 4)",
       t is not None and "top_level" not in rg and attr( r, "reaches" ) == "0" and attr( r, "reaches_hedged" ) == "3", rg )
t16, r16 = impact( tmp + "/w16", "sink" ); t17, r17 = impact( tmp + "/w17", "sink" )
check( "(R3) a field called through by 16 functions composes their 16 proven callers: reaches_hedged=32",
       attr( r16, "reaches" ) == "0" and attr( r16, "reaches_hedged" ) == "32", r16 )
check( "(R3) by 17: the 17 callers are counted (no width bound on the one-hop set) but compose nothing: reaches_hedged=17",
       attr( r17, "reaches" ) == "0" and attr( r17, "reaches_hedged" ) == "17", r17 )
t, r = impact( tmp + "/mixd", "sink" ); rg = ring( t )
check( "(R4) a chain whose second hop is a container stays at d=2: outer listed, top (a slot hop off a mixed chain) is not",
       attr( rg, "d" ) == "2" and 'called_by="outer"' in rg and 'via="container"' in rg and "top" not in re.findall( r'called_by="([^"]*)"', rg )
       and ' d="3"' not in rg, rg )
check( "(R4) ... and outer's proven caller outer_wrap is in the hedged count (mid, outer, outer_wrap = 3)", attr( r, "reaches_hedged" ) == "3", r )
t, r = impact( tmp + "/ringcyc", "sink" )
check( "(R5) the ring cycle guard holds under composition (fa and fb meet each other): reaches_hedged=2, no <ring>",
       t is not None and attr( r, "reaches_hedged" ) == "2" and ring( t ) == "", r + ring( t ) )

# ── K: the container kind ───────────────────────────────────────────────────────────────────────────────────────────
t, r = impact( tmp + "/tbl", "ha" )
check( "(K1) handlers[i]() joins the ring: reaches=0 reaches_hedged=2 (run, and run's proven caller main)",
       attr( r, "reaches" ) == "0" and attr( r, "reaches_hedged" ) == "2", r )
t, r = path( tmp + "/tbl", "main", "ha" ); br = bridge( t )
check( "(K2) the bridge crosses the container call: main -> run -> ha via=\"container\" cands=\"2\", proven=0, root reachable=0 hops=0",
       '<bridge proven="0" crossings="1" hops="2"><s t="fn" n="main" p="tbl.c:6"/><s t="fn" n="run" p="tbl.c:5"/><s t="fn" n="ha" p="tbl.c:2" via="container" cands="2"/></bridge>' == br
       and attr( r, "reachable" ) == "0" and attr( r, "hops" ) == "0", br + " " + r )
check( "(K2) the root next= lists to='s callers (a followed container hop)", attr( r, "next" ) == "--callers=tbl.c:ha", r )
t, r = path( tmp + "/t16", "main", "h7" ); b16 = bridge( t )
t, r = path( tmp + "/t17", "main", "h7" ); b17 = bridge( t )
check( "(K3) a table of 16 functions is crossed (cands=\"16\")", 'via="container" cands="16"' in b16, b16 )
check( "(K3) a table of 17 is not (no bridge, reachable stays 0)", t is not None and b17 == "" and attr( r, "reachable" ) == "0", b17 + r )
t, r = impact( tmp + "/tbl2", "ha" ); rg = ring( t )
check( "(K4) a d=2 container hop: <rh called_by=\"top\" via=\"container\" calls=\"run\" cands=\"1\"/>, reaches_hedged=2",
       '<rh called_by="top" called_at="t.c:7" via="container" calls="run" cands="1"/>' in rg and attr( r, "reaches_hedged" ) == "2", r + rg )

# ── B: a narrow declined crossing composes, a wide one does not ────────────────────────────────────────────────────
t, r = path( tmp + "/nar", "Machine_run", "Process_update" ); br = bridge( t )
vias = re.findall( r'via="([^"]*)"', br )
check( "(B1) declined (2 candidates) + container + slot = crossings=\"3\", proven=0, root reachable=0",
       attr( br, "crossings" ) == "3" and attr( br, "proven" ) == "0" and vias == [ "declined", "container", "slot" ]
       and 'via="declined" cands="2"' in br and attr( r, "reachable" ) == "0", br + " " + r )
t, r = path( tmp + "/wide", "Machine_run", "Process_update" ); bw = bridge( t )
check( "(B2) the same chain with a 5-candidate declined crossing: no bridge (a wide crossing stays a gap), reachable stays 0",
       t is not None and bw == "" and attr( r, "reachable" ) == "0" and attr( r, "gaps" ) is not None, bw + " " + r )
t, r = path( tmp + "/wide", "Machine_run", "scan_step" ); bw2 = bridge( t )
check( "(B2) its 2-crossing prefix keeps a bridge (declined cands=\"5\" + container): the width, not the fixture, refuses the third",
       attr( bw2, "crossings" ) == "2" and 'via="declined" cands="5"' in bw2 and 'via="container"' in bw2, bw2 )

t, r = path( tmp + "/param", "top1", "h0" )
check( "(P1) a called parameter binds per call site: top1 -> c1 -> run never reaches h0 (c1 passes h1): no bridge",
       t is not None and bridge( t ) == "" and attr( r, "reachable" ) == "0", bridge( t ) + " " + r )
t, r = path( tmp + "/param", "topnull", "h0" )
check( "(P1) a caller passing NULL to the called parameter never reaches h0: no bridge",
       t is not None and bridge( t ) == "" and attr( r, "reachable" ) == "0", bridge( t ) + " " + r )
t, r = path( tmp + "/param", "top0", "h0" )
check( "(P1) the passer's chain keeps its value crossing: top0 -> c0 -> h0 via=\"value\"", 'n="h0" p="cb.c:3" via="value"' in bridge( t ), bridge( t ) )
t, r = impact( tmp + "/param", "h0" )
check( "(P1) --impact=h0: an argument is not a container hop, so run and its callers are no hedged tail (reaches_hedged absent; 9 before the fix)",
       t is not None and attr( r, "reaches_hedged" ) is None, r )
t, r = path( tmp + "/third4", "aa", "dst" ); b3 = bridge( t )
check( "(B3) slot + slot + a container of 4 as the THIRD crossing composes: crossings=\"3\", cands=\"4\"",
       attr( b3, "crossings" ) == "3" and 'n="dst" p="t.c:6" via="container" cands="4"' in b3, b3 + " " + r )
t, r = path( tmp + "/third5", "aa", "dst" ); b3w = bridge( t )
check( "(B3) the same chain with a container of 5 as the third crossing: no bridge, reachable stays 0 (a wide third crossing stays a gap)",
       t is not None and b3w == "" and attr( r, "reachable" ) == "0", b3w + " " + r )

# ── N: no chain through an unrelated namesake ──────────────────────────────────────────────────────────────────────
t, r = impact( tmp + "/ns", "ha" )
check( "(N1) ha's ring counts its own file's run and main_a only (reaches_hedged=2), never main_b",
       attr( r, "reaches_hedged" ) == "2" and "main_b" not in body( t ), r )
t, r = path( tmp + "/ns", "main_b", "ha" )
check( "(N1) main_b -> ha: no bridge through b.c's same-named run and same-named table", t is not None and bridge( t ) == "" and attr( r, "reachable" ) == "0", bridge( t ) )

# ── H / O / W: the hub fold, the ring order, the page window ──────────────────────────────────────────────────────
def hubs( t ):
    return re.findall( r'<hub [^>]*/>', body( t ) )
t20, r20 = impact( tmp + "/hub20", "sink" ); h20 = hubs( t20 )
check( "(H1) a slot caller with 20 proven callers folds to ONE <hub n=\"hubf\" via=\"slot\" d=\"1\" behind=\"20\" tested=\"0\"> with next=\"--impact=t.c:hubf\"",
       len( h20 ) == 1 and all( attr( h20[ 0 ], k ) == v for k, v in ( ( "n", "hubf" ), ( "via", "slot" ), ( "d", "1" ), ( "behind", "20" ), ( "tested", "0" ), ( "next", "--impact=t.c:hubf" ) ) )
       and len( ( attr( h20[ 0 ], "sample" ) or "" ).split( "," ) ) == 3, repr( h20 ) )
named = set( re.findall( r'\bc\d+\b', body( t20 ) ) )
check( "(H1) the hub's tail is not listed: only its 3 sample names appear (no <s>/<rh> row for c1..c20)",
       t20 is not None and len( named ) == 3 and named == set( ( attr( h20[ 0 ], "sample" ) or "" ).split( "," ) ) if h20 else False, repr( sorted( named ) ) )
check( "(H1) the fold changes rows, never counts: reaches=3 reaches_hedged=21 (hubf + its 20 callers), reaches_hedged_hubs=20",
       attr( r20, "reaches" ) == "3" and attr( r20, "reaches_hedged" ) == "21" and attr( r20, "reaches_hedged_hubs" ) == "20", r20 )
check( "(H1) the hub holds more than half of reaches_hedged: the root next= is the hub's --impact", attr( r20, "next" ) == "--impact=t.c:hubf", r20 )
t16, r16 = impact( tmp + "/hub16", "sink" )
check( "(H1) at the bound (16 proven callers): no <hub>, no reaches_hedged_hubs, reaches_hedged=17, next= stays --safe-delete=",
       t16 is not None and hubs( t16 ) == [] and attr( r16, "reaches_hedged_hubs" ) is None and attr( r16, "reaches_hedged" ) == "17"
       and attr( r16, "next" ) == "--safe-delete=sink", r16 + repr( hubs( t16 ) ) )
t, r = impact( tmp + "/hub17", "sink" )
check( "(H2) one past the bound (17 proven callers) folds: ONE <hub behind=\"17\">, reaches_hedged=18",
       [ attr( h, "behind" ) for h in hubs( t ) ] == [ "17" ] and attr( r, "reaches_hedged" ) == "18", r + repr( hubs( t ) ) )
t, r = impact( tmp + "/hub2", "sink" )
check( "(H3) two hubs sharing 18 callers: reaches_hedged_hubs=18 (each function once), never above reaches_hedged=20, two <hub> rows",
       len( hubs( t ) ) == 2 and attr( r, "reaches_hedged_hubs" ) == "18" and attr( r, "reaches_hedged" ) == "20", r )
t, r = impact( tmp + "/hubsmp", "sink" )
check( "(H4) a tested caller leads the hub sample (c18, written last, before c1..c3): the order is the ring's, never the node id",
       ( ( attr( ( hubs( t ) or [ "" ] )[ 0 ], "sample" ) or "" ).split( "," ) or [ "" ] )[ 0 ] == "c18", r + repr( hubs( t ) ) )
t, r = impact( tmp + "/hubskip", "sink" )
check( "(H5) a member whose tail is made of counted d=2 ring rows still folds: 17 wide d=2 callers behind hubf = <hub behind=\"17\">",
       [ attr( h, "behind" ) for h in hubs( t ) ] == [ "17" ], r + repr( hubs( t ) ) )
t, r = impact( tmp + "/ord", "sink" ); rg = ring( t )
order = re.findall( r'called_by="([^"]*)"', rg )
check( "(O1) a narrow forward width before a wide one: ncall (slot_fns=1) is listed before wcall (slot_fns=3), written after it",
       "ncall" in order and "wcall" in order and order.index( "ncall" ) < order.index( "wcall" ), repr( order ) )
check( "(O1) a tested row before an untested entry point of the same width: tcall before ucall, written after it",
       "tcall" in order and "ucall" in order and order.index( "tcall" ) < order.index( "ucall" ), repr( order ) )
check( "(O1) the order moves rows, never counts: reaches_hedged=6 (m, wcall, ncall, ucall, tcall, test_tcall)", attr( r, "reaches_hedged" ) == "6", r )
t, r = impact( tmp + "/hub20", "sink", "--limit=3" )
check( "(W1) --limit=3: the 3 proven <s> rows keep the page, the hedged hub is cut first: ring_cut=1, next= the replay at --limit=4",
       t is not None and len( re.findall( r'<s ', body( t ) ) ) == 3 and hubs( t ) == [] and attr( r, "ring_cut" ) == "1"
       and attr( r, "next" ) == "--impact=sink --limit=4" and attr( r, "reaches_hedged" ) == "21", r )
t, r = impact( tmp + "/hub20", "sink", "--limit=2" )
check( "(W1) --limit=2: 2 proven rows, no hedged row (hedged rows are cut before proven ones), ring_cut=1",
       t is not None and len( re.findall( r'<s ', body( t ) ) ) == 2 and hubs( t ) == [] and attr( r, "ring_cut" ) == "1", r )
t, r = impact( tmp + "/hub20", "sink", "--limit=4" )
check( "(W1) the replay at the named limit is not cut again: 3 <s> rows + the hub, no ring_cut",
       t is not None and len( re.findall( r'<s ', body( t ) ) ) == 3 and len( hubs( t ) ) == 1 and attr( r, "ring_cut" ) is None, r )
check( "(W1) no --limit: no ring_cut", attr( r20, "ring_cut" ) is None and len( h20 ) == 1, r20 )
tj = run( tmp + "/hub20", "--impact=sink", "--json" ) or "{}"
try:
    jh = json.loads( tj )
except ValueError:
    jh = {}
jhub = ( jh.get( "hubs" ) or [ {} ] )[ 0 ]
check( "(H1) the JSON twin: reaches_hedged 21, reaches_hedged_hubs 20, one hub with the XML row's names and numbers",
       jh.get( "reaches_hedged" ) == 21 and jh.get( "reaches_hedged_hubs" ) == 20 and len( jh.get( "hubs", [] ) ) == 1 and jhub.get( "n" ) == "hubf"
       and jhub.get( "via" ) == "slot" and jhub.get( "d" ) == 1 and jhub.get( "behind" ) == 20 and jhub.get( "tested" ) == 0
       and jhub.get( "next" ) == "--impact=t.c:hubf" and ",".join( jhub.get( "sample", [] ) ) == attr( h20[ 0 ] if h20 else "", "sample" ), repr( tj[ -400: ] ) )
tjc = run( tmp + "/hub20", "--impact=sink", "--json", "--limit=3" ) or "{}"
try:
    jcut = json.loads( tjc )
except ValueError:
    jcut = {}
check( "(W1) the JSON twin of the cut: ring_cut 1, no hubs key", jcut.get( "ring_cut" ) == 1 and "hubs" not in jcut, repr( tjc[ :300 ] ) )

# ── J / M / L: twins and legends ───────────────────────────────────────────────────────────────────────────────────
tj = run( tmp + "/c4", "--impact=cancel_cmd", "--json" ) or "{}"
try:
    j = json.loads( tj )
except ValueError:
    j = {}
rows = j.get( "ring", {} ).get( "rows", [] )
check( "(J1) the JSON twin: reaches_hedged 3, ring d 3, the d=3 row with \"d\":3 and \"slot_fns\":1",
       j.get( "reaches_hedged" ) == 3 and j.get( "ring", {} ).get( "d" ) == 3
       and { "called_by": "fire_command", "called_at": "chain.c:13", "via": "slot", "calls": "send_keys_exec", "d": 3, "slot_fns": 1 } in rows, repr( tj[:500] ) )
tjc = run( tmp + "/tbl2", "--impact=ha", "--json" ) or "{}"
try:
    jc = json.loads( tjc )
except ValueError:
    jc = {}
check( "(J1) the JSON twin of a container row spells cands (no XML spelling inside the JSON)",
       { "called_by": "top", "called_at": "t.c:7", "via": "container", "calls": "run", "cands": 1 } in jc.get( "ring", {} ).get( "rows", [] ) and 'cands="' not in tjc, repr( tjc[:400] ) )
reqs = [ { "jsonrpc": "2.0", "id": 0, "method": "initialize", "params": { "protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": { "name": "g", "version": "1" } } },
         { "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": { "name": "impact", "arguments": { "path": tmp + "/c4", "symbol": "cancel_cmd" } } },
         { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": "path_between", "arguments": { "path": tmp + "/tbl", "from": "main", "to": "ha" } } },
         { "jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": { "name": "impact", "arguments": { "path": tmp + "/hub20", "symbol": "sink" } } } ]
p = subprocess.run( [ binp, "--mcp", "--mcp-legend=inline" ], input = "".join( json.dumps( x ) + "\n" for x in reqs ), capture_output = True, text = True, timeout = 300 )
resp = {}
for line in p.stdout.splitlines():
    try:
        o = json.loads( line )
    except ValueError:
        continue
    if isinstance( o.get( "id" ), int ) and o[ "id" ] > 0:
        resp[ o[ "id" ] ] = "".join( c.get( "text", "" ) for c in o.get( "result", {} ).get( "content", [] ) )
cli1 = run( tmp + "/c4", "--impact=cancel_cmd" ); cli2 = run( tmp + "/tbl", "--path=main,ha" )
check( "(M1) MCP impact: the same reaches_hedged= and <ring> (d=3) as the CLI",
       attr( root( resp.get( 1, "" ), "impact" ), "reaches_hedged" ) == "3" and ring( resp.get( 1, "" ) ) != "" and ring( resp.get( 1, "" ) ) == ring( cli1 ), repr( resp.get( 1, "" )[-300:] ) )
check( "(M1) MCP path_between: the same container <bridge> as the CLI", bridge( resp.get( 2, "" ) ) != "" and bridge( resp.get( 2, "" ) ) == bridge( cli2 ), repr( resp.get( 2, "" )[-300:] ) )
m3 = root( resp.get( 3, "" ), "impact" )
check( "(M1) MCP impact: the same <hub> row, reaches_hedged_hubs= and root next= as the CLI",
       hubs( resp.get( 3, "" ) ) == h20 and h20 != [] and attr( m3, "reaches_hedged_hubs" ) == "20" and attr( m3, "next" ) == attr( r20, "next" ), repr( resp.get( 3, "" )[-400:] ) )
imf = run( tmp + "/c4", "--impact=cancel_cmd", "--legend=full" ) or ""
pf = run( tmp + "/nar", "--path=Machine_run,Process_update", "--legend=full" ) or ""
ti = run( tmp + "/c4", "--impact=cancel_cmd" ) or ""
hf = run( tmp + "/hub20", "--impact=sink", "--legend=full", "--limit=3" ) or ""
hfu = run( tmp + "/hub20", "--impact=sink", "--legend=full" ) or ""
hc = run( tmp + "/hub20", "--impact=sink" ) or ""
check( "(L1) the full legend defines <hub>, behind=, reaches_hedged_hubs= and ring_cut= (one clause, present-only: absent on c4)",
       "<hub n= via= d= behind=" in hfu and "reaches_hedged_hubs=K" in hfu and "ring_cut=N" in hf and "reaches_hedged_hubs" not in imf )
check( "(L1) the compact legend defines the hub row and reaches_hedged_hubs=", "hub n= via= d= behind=" in hc and "reaches_hedged_hubs=K" in hc, hc[ :200 ] )
check( "(L1) the full impact legend says one hedged hop makes the chain hedged, names container, d=3 and the forward widths",
       "one hedged hop makes the whole chain hedged" in imf and "container" in imf and "d=3 the third field hop" in imf and "cands=K the functions" in imf )
check( "(L1) the full bridge legend states the composition bound (4 candidates) and the container crossing",
       "a declined or container one of at most 4 candidates" in pf and "container = the previous row calls through a container element" in pf )
check( "(L1) the compact impact legend defines the d=3 row and its forward width", "d=3 the third field hop; slot_fns=|cands=K" in ti )
if shutil.which( "xmllint" ):
    for label, doc in ( ( "impact full", imf ), ( "path full", pf ), ( "impact compact", ti ), ( "hub full + cut", hf ), ( "hub compact", hc ) ):
        x = subprocess.run( [ "xmllint", "--noout", "-" ], input = doc, capture_output = True, text = True )
        check( "(L1) the %s answer with the new clauses parses as XML (checklist 25)" % label, x.returncode == 0 and doc != "", x.stderr[:300] )
else:
    print( "  SKIP  (L1) xmllint not installed: the well-formedness arm needs it" )
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
