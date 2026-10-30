#!/usr/bin/env bash
# receiverfixescheck.sh — a member call on a field the class STATES as a type, and a Rust trait-object call, bind what that type
# can run, never the caller's own-class namesake and never a same-file impl picked by name (lane receiver-fixes).
#
#   test/receiverfixescheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# THE GAPS (reports: m1-lite Stage 0, rta-s0 row C6).
#   TS-FIELD-SELF: `this.pub.provide()` with `pub: Provider` bound the CALLER's own `provide` by name (a false edge), and inside
#     `provide` itself `this.#provider.provide()` vanished (callees count=0, no <dc>: the own method was the one same-file
#     candidate and the self-loop then dropped). `#private` fields and `this.#f = …` recorded no type; `import type { T }`
#     bound no module, so an interface T was not found.
#   PY-CTOR-ANNOT: `self.f: T`, `T | None`, `Optional[ T ]` annotations and `mod.X( … )` constructors typed nothing (the base
#     read only a bare `X( … )` value), so `self.f.start()` bound the caller's own `start` by name.
#   RUST-DYN-NAMESAKE: a `&dyn T` / `Box<dyn T>` call whose implementors list the map cannot list (two same-named `Spy` structs
#     in the test crate, as in mdbook) fell to the name tiers, which picked the one same-file impl (TestRenderer) by name.
#
# THE CONTRACT.
#   * A receiver `this.<f>` / `self.<f>` whose field the class states as an in-tree class or interface T that is neither the
#     caller's class nor one of its bases never binds the caller's own definition of the callee (receiverevidence.h
#     foreignFieldOwner; graph.h cuts it from the name tiers). T an interface: the dispatch tier answers (gate="iface", one
#     unproven candidate included); T a class: its member, proven.
#   * Python: an annotation wins over the value (`= None` leaves the field typed); `mod.X( … )` types a local or field only when
#     `mod` is an in-tree module (the written-qualifier check); T known by name to two classes stays a split, never proven.
#   * Rust: an OPEN trait list declines over the bodied methods inside T's impl blocks (+ T's default); never a by-name pick.
#   * A declined iface list names the non-test candidates first (cand= order only).
#
# ARMS: [P] red on the base binary, green after; [C] controls (both); [FLOOR] a stated limit, pinned. Exits non-zero on any failure.
set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
echo "receiverfixescheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
[ -d "$ROOT/test/receiverfixesfix" ] || { echo "fixture missing: test/receiverfixesfix"; exit 2; }

python3 - "$BIN" "$ROOT" <<'PY'
import os, re, subprocess, sys, tempfile
BIN, ROOT = sys.argv[1], sys.argv[2]
FIX = os.path.join( ROOT, "test", "receiverfixesfix" )
npass = nfail = 0
def say( good, tag, msg, why = "" ):
    global npass, nfail
    if good: npass += 1; print( "  PASS  %s: %s" % ( tag, msg ) )
    else:    nfail += 1; print( "  FAIL  %s: %s%s" % ( tag, msg, ( " — " + why ) if why else "" ) )
def run( sub, flag, legend = "compact" ):
    root = os.path.join( FIX, sub )
    with tempfile.TemporaryDirectory() as home:
        env = { k: v for k, v in os.environ.items() if not k.startswith( "RIPWIRE_" ) }
        env.update( HOME = home, TMPDIR = home + "/" )
        p = subprocess.run( [ BIN, root, "--no-cache", flag, "--legend=" + legend ], cwd = root, env = env, capture_output = True, text = True, timeout = 300 )
    if p.returncode != 0:   # an absence arm over a crashed run would pass: a nonzero rc is its own failure
        say( False, "run " + sub + " " + flag, "ripwire exited %d" % p.returncode, p.stderr[:200] )
    return p.stdout
def rows( out ):
    out = re.sub( r"<!--.*?-->", "", out, flags = re.S )
    return [ ( m.group( 1 ), dict( re.findall( r'([a-z_]+)="([^"]*)"', m.group( 2 ) ) ) ) for m in re.finditer( r"<(s|dc) ([^>]*)/>", out ) ]
def edges( out ):    return [ a for k, a in rows( out ) if k == "s" ]
def leaf( n ):       return ( n or "" ).rsplit( ".", 1 )[ -1 ]   # train 40: js-def-naming prints a TS/JS method row as Class.method; arms naming a method compare its leaf
def declines( out ): return [ a for k, a in rows( out ) if k == "dc" ]

print( "(T) TypeScript: a stated field's type, never the caller's own namesake" )
for sym, line in ( ( "exec/executor.ts:Executor.provide", "20" ), ( "viaPublic", "23" ), ( "viaLate", "26" ) ):
    o = run( "ts", "--callees=" + sym, "full" ); e, d = edges( o ), declines( o )
    iface = [ x for x in d if x.get( "gate" ) == "iface" and x.get( "l" ) == line ]
    cand  = iface[ 0 ].get( "cand", "" ) if iface else ""
    say( not e and len( iface ) == 1 and iface[ 0 ].get( "cands" ) == "3", "P T1 " + sym, 'one <dc gate="iface" cands="3">, no edge',
         "edges=%s dc=%s" % ( e, d ) )
    say( "exec/executor.ts" not in cand and "exec/box.ts" not in cand and "driver/default-provider.ts:3" in cand and "exec/peer.ts:5" in cand,
         "P T2 " + sym, "cand= the Provider implementors only (not the caller's own provide, not Box.provide)", cand )
o = run( "ts", "--callees=viaPrivBox" ); e = edges( o )
say( len( e ) == 1 and e[ 0 ].get( "p" ) == "src/exec/box.ts:2" and "via" not in e[ 0 ], "P T3 viaPrivBox", "`#boxp: Box` → the one proven Box.provide edge", str( e ) )
o = run( "ts", "--callers=exec/executor.ts:Executor.provide" ); e = edges( o )
say( not any( leaf( x.get( "n" ) ) in ( "viaPublic", "viaLate", "viaPrivBox" ) for x in e ), "P T4 callers", "no via=name caller row from a stated-field call", str( e ) )
say( any( leaf( x.get( "n" ) ) == "viaSelfField" for x in e ) and any( leaf( x.get( "n" ) ) == "viaUntyped" and x.get( "via" ) == "name" for x in e ), "C T4 control",
     "the same callers run lists the proven own-class caller and the untyped field's by-name caller (the absence above is not an empty run)", str( e ) )
o = run( "ts", "--callees=flush" ); e = edges( o )
say( not any( x.get( "p" ) == "src/exec/solo.ts:5" for x in e ), "P T5 flush", "`out: Sink` (an interface no class implements) never binds Solo's own write", str( e ) )
o = run( "ts", "--callees=viaSelfField" ); e = edges( o )
say( len( e ) == 1 and e[ 0 ].get( "p" ) == "src/exec/executor.ts:19" and "via" not in e[ 0 ], "C T6 viaSelfField", "a field of the caller's own class keeps its own provide (proven)", str( e ) )
o = run( "ts", "--callees=Peer.provide", "full" ); d = [ x for x in declines( o ) if x.get( "gate" ) == "iface" ]
say( len( d ) == 1 and "exec/peer.ts:5" in d[ 0 ].get( "cand", "" ), "P T7 Peer (near miss)", "a class implementing the field's interface keeps its own provide among the candidates", str( d ) )
o = run( "ts", "--callees=viaUntyped" ); e = edges( o )
say( any( x.get( "p" ) == "src/exec/executor.ts:19" and x.get( "via" ) == "name" for x in e ), "FLOOR T8 viaUntyped",
     "an UNTYPED field proves nothing: the by-name rows stay (own namesake included)", str( e ) )

o = run( "ts", "--callees=flush" ); e = edges( o )
say( any( x.get( "n" ) == "write" and x.get( "p" ) == "src/exec/solo.ts:12" for x in e ), "C T5b flush",
     "the cut drops the caller's own METHOD only: a same-file free function `write` stays a by-name candidate", str( e ) )
o = run( "ts", "--callees=viaBase" ); e = edges( o )
say( any( x.get( "p" ) == "src/exec/shape.ts:11" for x in e ), "C T9 viaBase",
     "a field typed as one of the caller's BASES (`other: Shape`, Shape defines no area) keeps the caller's own area", str( e ) )
o = run( "ts", "--callees=viaExt" ); e = edges( o )
say( any( x.get( "p" ) == "src/exec/shape.ts:12" and x.get( "via" ) == "name" for x in e ), "FLOOR T10 viaExt",
     "a field typed as an OUTSIDE type (`ext: Widget` from a package) proves nothing: the by-name rows stay", str( e ) )
o = run( "ts", "--callees=viaSingle", "full" ); e, d = edges( o ), declines( o )
say( not e and len( d ) == 1 and d[ 0 ].get( "gate" ) == "iface" and d[ 0 ].get( "cands" ) == "1" and "driver/single-impl.ts:3" in d[ 0 ].get( "cand", "" ),
     "P T11 viaSingle", 'an interface with ONE (structural, unproven) implementor behind a stated field: <dc gate="iface" cands="1">, never the own run', "edges=%s dc=%s" % ( e, d ) )

o = run( "tsalias", "--callees=viaUnion" ); e = edges( o )
say( any( x.get( "p" ) == "src/alias.ts:6" for x in e ), "P T12 viaUnion",
     "a field typed by a UNION alias (`type Either = Provider | Exec`) names no one class: the caller's own provide stays a candidate", str( e ) )
o = run( "tsalias", "--callees=viaBase" ); e = edges( o )
say( any( x.get( "p" ) == "src/alias.ts:18" for x in e ), "P T13 viaBase",
     "a field typed by an alias of a BASE (`type B = Base`, `f: B`) keeps the caller's own ping: the field may hold the caller's class", str( e ) )

def bridge( out ):
    out = re.sub( r"<!--.*?-->", "", out, flags = re.S )
    m = re.search( r"<bridge .*?</bridge>", out, flags = re.S )
    return m.group( 0 ) if m else ""
for sym, what in ( ( "dispatch", "`this.router.match( … )`" ), ( "viaParam", "`app.router.match( … )` on a parameter typed App" ) ):
    o = run( "tshop", "--path=%s,routers/a.ts:match" % sym ); b = bridge( o )
    say( 'p="src/routers/a.ts:3" via="declined" cands="2"' in b, "P H1 " + sym,
         what + " (router: Router, an in-tree interface with 2 implementors) is a hedged bridge crossing via=declined cands=2, not near_sink why=external", b[ -300: ] or o[ -300: ] )
o = run( "tshop", "--callees=dispatch", "full" ); d = declines( o )
say( len( d ) == 1 and d[ 0 ].get( "gate" ) == "iface" and d[ 0 ].get( "cands" ) == "2", "P H2 dispatch",
     'the interface field keeps the L6 decline: one <dc gate="iface" cands="2"> (the bridge above rides on it)', str( d ) )
o = run( "tshop", "--path=label,routers/a.ts:match" )
say( bridge( o ) == "" and "<path " in o, "C H3 label", "`this.name.match( re )` (name: string, no in-tree class) is no crossing: the builtin reading stands", o[ -300: ] )

def nearsink( out ):
    out = re.sub( r"<!--.*?-->", "", out, flags = re.S )
    return [ dict( re.findall( r'([a-z_]+)="([^"]*)"', m.group( 1 ) ) ) for m in re.finditer( r"<ns ([^>]*)/>", out ) ]
def root( out ):
    out = re.sub( r"<!--.*?-->", "", out, flags = re.S )
    m = re.search( r"<path [^>]*>", out )
    return dict( re.findall( r'([a-z_]+)="([^"]*)"', m.group( 0 ) ) ) if m else {}
def sink( out ):   # the to= definition's own near_sink row (d="0")
    return next( ( x for x in nearsink( out ) if x.get( "d" ) == "0" ), {} )

print( "(F) R1-followup: a builtin-spelled call on a typed interface field, any width of its implementor list" )
# an interface with ONE in-tree implementor (`match` spells String.prototype.match): the hedged bridge crossing, as a non-builtin name has
o = run( "tsone", "--path=dispatch,routers/a.ts:match" ); b = bridge( o ); r = root( o )
say( 'p="src/routers/a.ts:3" via="declined" cands="1"' in b and 'proven="0"' in b and r.get( "reachable" ) == "0", "P F1 dispatch",
     "`this.router.match( … )` (router: Router, ONE in-tree implementor) is a HEDGED crossing via=declined cands=1: bridge proven=0, the root stays reachable=0", b[ -300: ] or o[ -300: ] )
o = run( "tsone", "--path=viaParam,routers/a.ts:match" ); e = edges( o )
say( root( o ).get( "reachable" ) == "1" and any( x.get( "via" ) == "name" and leaf( x.get( "n" ) ) == "match" for x in e ), "C F1 viaParam",
     "`app.router.match( … )` on a parameter keeps its hedged by-name edge (this lane does not touch the parameter shape)", str( e ) )
o = run( "tsone", "--path=dispatch,routers/a.ts:match" ); s = sink( o )
say( s.get( "why", "" ).startswith( "declined:" ) and s.get( "in" ) == "dispatch", "P F2 near_sink",
     "the sink row names the declined call (why=declined:N in=dispatch), not external", str( s ) )
o = run( "tsone", "--callees=dispatch", "full" ); d = declines( o ); e = edges( o )
say( not e and len( d ) == 1 and d[ 0 ].get( "gate" ) == "iface" and d[ 0 ].get( "cands" ) == "1", "C F3 dispatch",
     'the one implementor is still a decline (<dc gate="iface" cands="1">), never a proven edge', "edges=%s dc=%s" % ( e, d ) )
o = run( "tsone", "--path=label,routers/a.ts:match" )
say( bridge( o ) == "" and "<path " in o, "C F4 label", "`this.name.match( re )` (name: string) beside the one-implementor field is no crossing", o[ -300: ] )
# 17 implementors: past the 16 a consumer follows, so no bridge, but the sink is not "external" (a near miss at 16 keeps its bridge)
o = run( "tsw17", "--path=dispatch,routers/all.ts:R1Router.match" ); s = sink( o ); r = root( o )
say( s.get( "why" ) == "declined:2" and s.get( "in" ) == "dispatch" and s.get( "met" ) == "1", "P F5 tsw17 near_sink",
     "17 implementors: the sink row says why=declined:2 (dispatch + viaParam; the `this.name.match` site is not counted), not external", str( s ) )
say( bridge( o ) == "" and r.get( "reachable" ) == "0" and r.get( "gaps" ) == "declined:1", "C F6 tsw17 no bridge",
     "17 candidates are wider than the bridge's 16: still no crossing (the root names the gap)", o[ -300: ] )
o = run( "tsw16", "--path=dispatch,routers/all.ts:R1Router.match" ); s = sink( o )
say( 'via="declined" cands="16"' in bridge( o ) and s.get( "why" ) == "declined:2", "C F7 tsw16",
     "16 implementors (the near miss): the bridge crosses with cands=16 and the sink row is the same why=declined:2", bridge( o )[ -200: ] or o[ -300: ] )
o = run( "tsw17", "--callees=dispatch", "full" ); d = declines( o )
say( len( d ) == 1 and d[ 0 ].get( "gate" ) == "iface" and d[ 0 ].get( "cands" ) == "17", "C F8 tsw17 dispatch",
     'the 17-wide interface is still one <dc gate="iface" cands="17"> (the width the near_sink row leaves to --callees)', str( d ) )

o = run( "tsext", "--path=dispatch,routers/a.ts:match" ); e = edges( o )
say( bridge( o ) == "" and root( o ).get( "reachable" ) == "1" and any( x.get( "via" ) == "name" and leaf( x.get( "n" ) ) == "match" for x in e ), "C F9 tsext",
     "the field's type imported from a package (`import { Router } from 'express'`, the tree has an interface of that name too) is not stated in-tree: the by-name edge stays, no crossing", str( e ) )

print( "(Y) Python: annotations and module-qualified constructors type fields and locals" )
for sym in ( "go1", "go2", "go3", "go4", "go5", "go6", "go8", "goParam" ):
    o = run( "py", "--callees=" + sym ); e = edges( o )
    m = [ x for x in e if x.get( "n" ) == "Manager.start" ]
    say( len( m ) == 1 and "via" not in m[ 0 ] and "prov" not in m[ 0 ] and not any( x.get( "n" ) == "AppA.start" for x in e ), "P Y1 " + sym,
         "Manager.start proven, never AppA.start", str( e ) )
for sym, what in ( ( "goExt", "`requests.Session | None` (an outside qualifier)" ), ( "goBoth", "`Manager | AppA | None` (two classes)" ),
                   ( "goBoth2", "`Manager | AppA` (two classes, no None: the union itself, not an Optional)" ), ( "goExtLocal", "`requests.Manager()`" ) ):
    o = run( "py", "--callees=" + sym ); e = edges( o )
    say( not any( x.get( "n" ) == "Manager.start" and "via" not in x for x in e ), "C Y2 " + sym, what + " proves no Manager.start", str( e ) )
    say( any( x.get( "n" ) == "AppA.start" and x.get( "via" ) == "name" for x in e ), "C Y2 presence " + sym, "the run hedges: the by-name AppA.start row is listed (not an empty run)", str( e ) )
o = run( "py", "--callees=goExt" ); e = edges( o )
say( any( x.get( "n" ) == "AppA.start" and x.get( "via" ) == "name" for x in e ), "FLOOR Y3 goExt", "a field typed outside the tree keeps the by-name rows", str( e ) )
o = run( "py", "--callees=go10" ); e = edges( o )
say( any( x.get( "n" ) == "FastStrategy.run" and "via" not in x for x in e ) and not any( x.get( "n" ) == "Strategy.run" for x in e ), "P Y5 go10",
     "`self.f: Strategy = FastStrategy()`: the constructed in-tree value beats the annotation (as a local does): FastStrategy.run proven, never the Strategy stub", str( e ) )
o = run( "py", "--callees=go11" ); e = edges( o )
say( any( x.get( "n" ) == "Strategy.run" and "via" not in x for x in e ), "C Y5 go11",
     "`self.f: Strategy = None`: no value names a class, the annotation types the field (Strategy.run proven)", str( e ) )
o = run( "pydup", "--callees=goDup" ); e = edges( o )
say( len( e ) == 2 and all( x.get( "prov" ) == "split" for x in e ) and not any( x.get( "n" ) == "App.start" for x in e ), "P Y4 goDup",
     "T named by two classes: a split over both (never proven), never App.start", str( e ) )

print( "(R) Rust: a trait object whose implementors list is open declines over T's impl blocks" )
for sym, line in ( ( "execute", "10" ), ( "boxed", "13" ) ):
    o = run( "rs", "--callees=" + sym, "full" ); e, d = edges( o ), declines( o )
    iface = [ x for x in d if x.get( "gate" ) == "iface" and x.get( "l" ) == line ]
    say( not any( "render" in x.get( "n", "" ) for x in e ) and len( iface ) == 1 and iface[ 0 ].get( "cands" ) == "4", "P R1 " + sym,
         'no by-name render edge; one <dc gate="iface" cands="4">', "edges=%s dc=%s" % ( e, d ) )
    cand = iface[ 0 ].get( "cand", "" ).split() if iface else []
    say( len( cand ) == 4 and cand[ -1 ] == "tests/suite/renderer.rs:5" and all( c.startswith( "zcrates/" ) for c in cand[ :3 ] ), "P R2 " + sym,
         "cand= the non-test impls first, the test crate's Spy last", str( cand ) )
o = run( "rsdup", "--callees=execute" ); e, d = edges( o ), declines( o )
say( not any( x.get( "gate" ) == "iface" for x in d ) and len( [ x for x in e if "render" in x.get( "n", "" ) ] ) == 3, "FLOOR R3 rsdup",
     "a trait name two in-tree traits share: the open-list rule answers nothing (impl blocks are keyed by name), the by-name rows stay", "edges=%s dc=%s" % ( e, d ) )
o = run( "rsone", "--callees=by_name", "full" ); e, d = edges( o ), declines( o )
say( not e and len( d ) == 1 and d[ 0 ].get( "gate" ) == "iface" and d[ 0 ].get( "cands" ) == "1" and d[ 0 ].get( "cand" ) == "src/api.rs:3", "P R4 by_name",
     'an open list whose one candidate is the trait default declines (<dc gate="iface" cands="1">), never the by-name inherent Local::name', "edges=%s dc=%s" % ( e, d ) )
o = run( "rsone", "--callees=by_render", "full" ); e, d = edges( o ), declines( o )
say( not e and len( d ) == 1 and d[ 0 ].get( "cands" ) == "2" and d[ 0 ].get( "cand", "" ).split() == [ "src/one.rs:4", "src/two.rs:3" ], "P R5 by_render",
     "an impl of a trait written through a path that leaves the tree (`impl other_crate::Renderer for Foreign`) is not an in-tree implementor: not in cand=", "edges=%s dc=%s" % ( e, d ) )
print( "receiverfixescheck: %d passed, %d failed" % ( npass, nfail ) )
sys.exit( 1 if nfail else 0 )
PY
rc=$?   # the harness's own status, read immediately: 0 every arm passed, 1 an arm failed, anything else a crash
fail=0
if [ "$rc" -ne 0 ]; then
    printf '  FAIL  the arm harness exited %s (an arm failed above, or the harness crashed)\n' "$rc"
    fail=1
fi
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
