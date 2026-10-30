#!/usr/bin/env bash
# ifacedispatchcheck.sh — a call through an INTERFACE-, TRAIT- or ABSTRACT-typed receiver names the implementors' methods
# that can run there (lane L6): one in the tree is a proven edge via="impl"; two or more are DECLINED with exactly that list.
#
#   test/ifacedispatchcheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# THE GAP. A programmer facing `pkg.Package( info, f )` on an interface value lists the implementors and opens the ones that
# can run. Before this, ripwire answered by NAME: every in-tree definition called `render` / `pack` / `match` (a same-named
# trait's implementor in another module, an overload of another arity, the interface's own signature), as a <dc cands=K>
# whose K counted them all, or as via="name" / prov="split" edges.
#
# THE CONTRACT (design: reports/gap-ideas.md "L6 iface-typed dispatch rows", reports/dn-indirection.md rows 1-2).
#   * In buildGraph, a tier after the receiver rules and before the name tiers: when the receiver's recorded type T is an
#     interface / trait / abstract base (a type whose own `m` has no body) with implementors (the extends / implements /
#     `impl T for X` edges, walked through implementorClosure), the candidates are the methods named m that those types own
#     (an arity the call cannot pass is not one; T's own bodied default is one).
#   * ONE candidate, every edge to it proven, no clause-less implementor possible: an edge via="impl" (the only implementor in
#     the tree; one outside it, or one a macro writes, may exist).
#   * TWO or more: a <dc ... cands="K" via="declined" gate="iface"/> row, cands= that list's size; --legend=full names it
#     (cand=). A Rust generic bound adds bound="R: Trait". Never retargeted by name, never in count=.
#   * NOT the tier: a receiver whose type defines a bodied m (a concrete base with subclasses keeps today's proven edge),
#     a type with no implementor in the tree (declined or by-name, as before), a same-named interface elsewhere (its
#     implementors are not this one's).
#   * Rust receivers: `&dyn T`, `Box<dyn T>`, `impl T` / `&impl T` parameters, a `let x: &dyn T`, a struct field
#     `Box<dyn T>`, a generic parameter bounded by T (inline `R: T` or a `where` clause).
#
# ARMS (fixture test/ifacedispatchfix: rs/ cpp/ java/ kt/ ts/ go/):
#   (A) Rust trait objects and impl Trait          (B) Rust generic bounds (bound=)
#   (C) one implementor → via="impl" (Rust, C++, Java, TS interface, TS abstract class)
#   (D) C++ abstract base: pointer, reference and a unique_ptr field (ninja's command_runner_->StartCommand)
#   (E) Java / Kotlin interfaces                   (F) TypeScript interface
#   (G) the callers form: an implementor's answer names the declined sites; a same-named trait's implementor is not named
#   (N) near misses: concrete base with subclasses, no implementor, another arity, a same-named interface elsewhere,
#       count= untouched, a test-only implementor listed
#   (K) fix round 1, B1 — completeness (fixtures b1ts/ b1java/ b1kt/ b1rs/): an implementor with no clause the map reads (a
#       TS object literal or conforming class, a Java lambda or anonymous class, a Kotlin `fun interface` lambda or object
#       expression, a Rust trait under mockall's automock) opens the list: no via="impl", main's by-name rows stay
#   (K2) fix round 2, C2 — the SAM count (fixtures sam_*/): java.lang.Object's equals / hashCode / toString redeclared abstract do not count;
#       the count is per interface IDENTITY (a same-named interface in another package is not this one's); a Kotlin single-method
#       interface is lambda-implementable from Java; controls: a two-method interface (Object method redeclared), two same-named
#       two-method interfaces, a two-method Kotlin interface beside Java, a Kotlin-only tree: still via="impl"
#       fix round 3, D1 — a DOUBTED Kotlin count of 0 (sam_kt_*_shared: Sub's or its base's name is shared) opens the list; controls
#       sam_kt_inherit / _generic / _javabase (a base the index names exactly) stay open by the SAM rule
#       fix round 4, E1 — a name re-declared WITH A BODY below its abstract declaration (sam_kt_default_*) leaves the count; a body-less
#       re-declaration (sam_kt_redeclare_abstract) and a Java default method (sam_java_default_override) are the controls
#       fix round 5, NIT-1 — the nearest declaration wins: a body ABOVE an abstract re-declaration is no answer (kt_reabstract_mid,
#       java_default_kt_reabstract, kt_reabstract_arity); the count's drop is for a body at or below the declarer
#   (M) fix round 1, B2 — Rust method set: through `dyn T` a candidate sits in an `impl T for X` block (or is T's default);
#       an inherent method of X never is
#   (L) legend clauses ride with the rows (cands=K a floor; the iface clause only beside an iface row)   (J) --json gate / bound
#   (Go) FLOOR: Go interfaces are structural; no implements clause names an implementor, so the tier has none (4c)
#
# RED ON BASE: every [P] arm fails on a binary without the tier; [C] arms are controls that pass on both; [FLOOR] arms pin a
# stated limit. Exits non-zero on any failure.

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"          # a relative binary is relative to the caller's cwd
echo "ifacedispatchcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
[ -d "$ROOT/test/ifacedispatchfix" ] || { echo "fixture missing: test/ifacedispatchfix"; exit 2; }
fail=0

python3 - "$BIN" "$ROOT" <<'PY' || fail=1
import json, os, re, subprocess, sys
import xml.etree.ElementTree as ET

BIN, ROOT = sys.argv[1], sys.argv[2]
FIX = os.path.join( ROOT, "test", "ifacedispatchfix" )
RS, CPP, JAVA, KT, TS, GO = ( os.path.join( FIX, d ) for d in ( "rs", "cpp", "java", "kt", "ts", "go" ) )
npass = nfail = 0

def say( good, tag, msg, why = "" ):
    global npass, nfail
    if good:
        npass += 1; print( "  PASS  %s: %s" % ( tag, msg ) )
    else:
        nfail += 1; print( "  FAIL  %s: %s%s" % ( tag, msg, ( " -- " + why ) if why else "" ) )

def run( root, *args ):
    try:
        p = subprocess.run( [ BIN, root, "--no-cache" ] + list( args ), capture_output = True, text = True, timeout = 240, cwd = root )
        return p.returncode, p.stdout
    except subprocess.TimeoutExpired:
        return 124, ""

class Answer:
    def __init__( self, rc, text, tag ):
        self.rc, self.text, self.tag = rc, text, tag
        self.root, self.err = None, ""
        m = re.match( r"(\s*<!--.*?-->)+", text, re.S )
        self.legend = m.group( 0 ) if m else ""
        try:
            self.root = ET.fromstring( "<doc>" + text + "</doc>" ).find( tag )
        except ET.ParseError as e:
            self.err = "not well-formed XML: %s" % e
        self.dc = [ dict( e.attrib ) for e in self.root.iter( "dc" ) ] if self.root is not None else []
        self.rows = [ dict( e.attrib ) for e in self.root.findall( "s" ) ] if self.root is not None else []
        # train 33 (QUALNAME-1 composed): a member row prints n="Owner<sep>name" (OnlySolo::soloRun, Inc.ap). The arms below key a
        # row by its MEMBER name plus p= (which already names the one definition); the printed spelling stays in "qn", and the (Q)
        # arms pin it. Every row is normalised, so a negative that asks for a name's absence still reads the respelled rows.
        for r in self.rows:
            if "n" in r:
                r[ "qn" ] = r[ "n" ]
                r[ "n" ] = re.split( r"::|#|\.", r[ "n" ] )[ -1 ]
    @property
    def ok( self ):
        return self.rc == 0 and self.root is not None
    def a( self, k ):
        return self.root.get( k ) if self.root is not None else None
    def why( self ):
        if self.rc != 0: return "rc=%s" % self.rc
        if self.root is None: return self.err or "no <%s> root" % self.tag
        return "root count=%s declined_calls=%s; s=%s; dc=%s" % ( self.a( "count" ), self.a( "declined_calls" ), self.rows, self.dc )

def ask( root, verb, sel, *more ):
    rc, out = run( root, "--%s=%s" % ( verb, sel ), *more )
    return Answer( rc, out, verb )

def line_of( path, needle, nth = 1 ):
    with open( path, encoding = "utf-8" ) as f:
        k = 0
        for i, line in enumerate( f, 1 ):
            if needle in line:
                k += 1
                if k == nth:
                    return str( i )
    return "?"

def one_dc( a, n, l, cands, gate = "iface", bound = None ):
    """exactly one <dc> row for (n, l), with cands= / gate= / bound= as given (None = attribute absent)"""
    hit = [ d for d in a.dc if d.get( "n" ) == n and d.get( "l" ) == l ]
    if len( hit ) != 1:
        return False
    d = hit[ 0 ]
    return d.get( "cands" ) == cands and d.get( "via" ) == "declined" and d.get( "gate" ) == gate and d.get( "bound" ) == bound

def cand_set( a, n, l ):
    for d in a.dc:
        if d.get( "n" ) == n and d.get( "l" ) == l:
            return set( d.get( "cand", "" ).split() )
    return None

DRIVE_RS = os.path.join( RS, "src", "drive.rs" )
IMPLS_RS = os.path.join( RS, "src", "render", "impls.rs" )
RENDER_IMPLS = { "src/render/impls.rs:" + line_of( IMPLS_RS, "fn render", k ) for k in range( 1, 7 ) }   # 5 + the test fake
FOREIGN = "src/other/mod.rs:" + line_of( os.path.join( RS, "src", "other", "mod.rs" ), "fn render", 2 )

# ── (A) Rust trait objects and impl Trait ───────────────────────────────────────────────────────────────────────────
print( "=== (A) Rust: a call on &dyn T / Box<dyn T> / impl T names T's implementors ===" )
for sel, needle in ( ( "dyn_ref", "r.render(2)" ), ( "dyn_box", "r.render(3)" ), ( "Host::host_field", "self.boxed.render(1)" ),
                     ( "impl_param", "r.render(4)" ), ( "impl_ref", "r.render(5)" ), ( "let_dyn", "r.render(8)" ) ):
    a = ask( RS, "callees", sel )
    l = line_of( DRIVE_RS, needle )
    say( a.ok and one_dc( a, "render", l, "6" ), "[P] a_%s" % sel.replace( "::", "_" ),
         "--callees=%s: <dc n=\"render\" l=\"%s\" cands=\"6\" gate=\"iface\"> (Renderer's 5 impls + the test fake)" % ( sel, l ), a.why() )
    say( a.ok and a.a( "count" ) == "0" and not a.rows, "[C] a_%s_count" % sel.replace( "::", "_" ), "no <s> row, count=\"0\": a declined row is never an edge", a.why() )
af = ask( RS, "callees", "dyn_ref", "--legend=full" )
cs = cand_set( af, "render", line_of( DRIVE_RS, "r.render(2)" ) )
say( af.ok and cs == RENDER_IMPLS, "[P] a_full_cands", "--legend=full cand= is exactly Renderer's implementors' render (5 + the #[cfg(test)] fake)",
     "%s vs %s" % ( sorted( cs or [] ), sorted( RENDER_IMPLS ) ) )
say( af.ok and cs is not None and FOREIGN not in cs, "[P] a_not_foreign",
     "other::Renderer's implementor (%s) is not a candidate of render::Renderer" % FOREIGN, af.why() )
a = ask( RS, "callees", "default_label" )
say( a.ok and one_dc( a, "label", line_of( DRIVE_RS, "r.label()" ), "2" ), "[P] a_default_method",
     "a trait default (Renderer::label, bodied) and its one override (Epub) are the two candidates", a.why() )

# ── (B) generic bounds ─────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (B) Rust: a generic bounded by T — the same list, bound= says why ===" )
for sel, needle in ( ( "bound_generic", "r.render(6)" ), ( "where_generic", "r.render(7)" ) ):
    a = ask( RS, "callees", sel )
    say( a.ok and one_dc( a, "render", line_of( DRIVE_RS, needle ), "6", bound = "R: Renderer" ), "[P] b_%s" % sel,
         "--callees=%s: cands=\"6\" gate=\"iface\" bound=\"R: Renderer\"" % sel, a.why() )

# ── (C) one implementor ────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (C) one implementor in the tree: a proven edge via=\"impl\" ===" )
def impl_edge( root, sel, n, p ):
    a = ask( root, "callees", sel )
    hit = [ r for r in a.rows if r.get( "n" ) == n ]
    return a, len( hit ) == 1 and hit[ 0 ].get( "p" ) == p and hit[ 0 ].get( "via" ) == "impl" and not a.dc
a = ask( CPP, "callees", "soloCall" )
say( a.ok and [ ( r.get( "n" ), r.get( "p" ), r.get( "via" ) ) for r in a.rows ] == [ ( "soloRun", "runners.cc:23", None ) ] and not a.dc, "[C] c_cpp",
     "C++ one subclass: class identity's own proven edge stays as it was (no via= relabel; the field path never proves one)", a.why() )
for root, sel, n, p, tag in ( ( RS, "solo_dyn", "solo_step", "src/solo/mod.rs:8", "rs" ),
                              ( JAVA, "single", "singleRun", "app/OnlySingle.java:4", "java" ) ):
    a, good = impl_edge( root, sel, n, p )
    say( a.ok and good, "[P] c_%s" % tag, "--callees=%s: <s n=\"%s\" p=\"%s\" via=\"impl\">, no <dc>" % ( sel, n, p ), a.why() )
# fix round 1 (B1 i): TypeScript types structurally — an object literal or a class with the right members implements an interface
# (or a class type) without naming it, so one `implements` clause never proves the only implementor: main's by-name row stays
for sel, n, p, tag in ( ( "lone", "loneCall", "src/fmt/impls.ts:16", "ts" ), ( "areaOf", "area", "src/fmt/impls.ts:22", "ts_abstract" ) ):
    a = ask( TS, "callees", sel )
    say( a.ok and [ ( r.get( "n" ), r.get( "p" ), r.get( "via" ) ) for r in a.rows ] == [ ( n, p, "name" ) ] and not a.dc, "[P] c_%s_structural" % tag,
         "--callees=%s: main's <s n=\"%s\" p=\"%s\" via=\"name\">, never via=\"impl\" (structural typing: the list is no proof)" % ( sel, n, p ), a.why() )
a = ask( RS, "callers", "src/solo/mod.rs::OnlySolo::solo_step" )
say( a.ok and [ ( r.get( "n" ), r.get( "via" ) ) for r in a.rows ] == [ ( "solo_dyn", "impl" ) ] and a.a( "count" ) == "1", "[P] c_callers",
     "--callers of the one implementor: solo_dyn via=\"impl\", count=\"1\"", a.why() )

# ── (D) C++ abstract base ──────────────────────────────────────────────────────────────────────────────────────────
print( "=== (D) C++: a pure-virtual member through a base pointer, reference or unique_ptr field ===" )
DRIVE_CC = os.path.join( CPP, "drive.cc" )
for sel, n, needle in ( ( "Builder::startEdge", "StartCommand", "command_runner_->StartCommand" ), ( "byPointer", "StartCommand", "r->StartCommand" ),
                        ( "byRef", "CanRunMore", "r.CanRunMore" ) ):
    a = ask( CPP, "callees", sel )
    say( a.ok and one_dc( a, n, line_of( DRIVE_CC, needle ), "2" ) and not a.rows, "[P] d_%s" % sel.replace( "::", "_" ),
         "--callees=%s: <dc n=\"%s\" cands=\"2\" gate=\"iface\">, no by-name or split <s> row" % ( sel, n ), a.why() )
af = ask( CPP, "callees", "byPointer", "--legend=full" )
cs = cand_set( af, "StartCommand", line_of( DRIVE_CC, "r->StartCommand" ) )
say( af.ok and cs == { "runners.cc:9", "runners.cc:16" }, "[P] d_full_cands",
     "cand= is RealCommandRunner's and DryRunCommandRunner's one-argument StartCommand", str( cs ) )

# ── (E) Java / Kotlin ──────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (E) Java / Kotlin interfaces ===" )
DRIVE_J = os.path.join( JAVA, "app", "Drive.java" )
for sel, n, needle in ( ( "byParam", "pack", "p.pack" ), ( "byLocal", "fileName", "p.fileName" ), ( "byField", "pack", "field.pack" ) ):
    a = ask( JAVA, "callees", sel )
    say( a.ok and one_dc( a, n, line_of( DRIVE_J, needle ), "3" ), "[P] e_java_%s" % sel,
         "--callees=%s: <dc n=\"%s\" cands=\"3\" gate=\"iface\"> (Deb, Rpm, Apk)" % ( sel, n ), a.why() )
af = ask( JAVA, "callees", "byParam", "--legend=full" )
cs = cand_set( af, "pack", line_of( DRIVE_J, "p.pack" ) )
say( af.ok and cs == { "fmt/Apk.java:7", "fmt/Deb.java:7", "fmt/Rpm.java:7" }, "[P] e_java_full",
     "cand= is each implementor's one-argument pack: not pack(String, int), not other.Zip's pack", str( cs ) )
a = ask( KT, "callees", "drain" )
say( a.ok and one_dc( a, "emit", line_of( os.path.join( KT, "Drive.kt" ), "s.emit" ), "2" ) and not a.rows, "[P] e_kotlin",
     "kotlin --callees=drain: <dc n=\"emit\" cands=\"2\" gate=\"iface\">, no via=\"name\" row", a.why() )

# ── (F) TypeScript ─────────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (F) TypeScript interface ===" )
a = ask( TS, "callees", "dispatch" )
say( a.ok and one_dc( a, "match", "4", "2" ), "[P] f_ts", "--callees=dispatch: <dc n=\"match\" cands=\"2\" gate=\"iface\"> (RegExp, Trie)", a.why() )
af = ask( TS, "callees", "dispatch", "--legend=full" )
cs = cand_set( af, "match", "4" )
say( af.ok and cs == { "src/fmt/impls.ts:4", "src/fmt/impls.ts:10" }, "[P] f_ts_full",
     "cand= names fmt's two routers, not other/router.ts's ForeignRouter (another interface named Router)", str( cs ) )

# ── (G) callers form ───────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (G) the callers form ===" )
a = ask( RS, "callers", "src/render/impls.rs::Html::render" )
say( a.ok and len( a.dc ) == 8 and all( d.get( "gate" ) == "iface" and d.get( "cands" ) == "6" for d in a.dc ) and a.a( "count" ) == "0",
     "[P] g_callers", "--callers=Html::render: 8 <dc> sites, each gate=\"iface\" cands=\"6\"; count=\"0\"", a.why() )
a = ask( RS, "callers", "src/other/mod.rs::Foreign::render" )
say( a.ok and not a.dc and a.a( "declined_calls" ) is None, "[P] g_foreign",
     "--callers=other::Foreign::render: no declined site of drive.rs (they dispatch through render::Renderer)", a.why() )

# ── (N) near misses ────────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (N) near misses ===" )
a = ask( CPP, "callees", "concreteBase" )
say( a.ok and [ ( r.get( "n" ), r.get( "p" ), r.get( "via" ) ) for r in a.rows ] == [ ( "area", "runner.h:16", None ) ] and not a.dc, "[C] n_cpp_concrete",
     "C++ a bodied virtual on the written base keeps today's proven edge (Shape::area), never widened to its subclasses", a.why() )
a = ask( TS, "callees", "describeOf" )
say( a.ok and [ ( r.get( "n" ), r.get( "p" ), r.get( "via" ) ) for r in a.rows ] == [ ( "describe", "src/fmt/router.ts:11", None ) ] and not a.dc,
     "[C] n_ts_concrete", "TS an abstract class's BODIED member keeps today's proven edge", a.why() )
a = ask( RS, "callees", "lonely_dyn" )
say( a.ok and one_dc( a, "lonely_call", line_of( DRIVE_RS, "l.lonely_call()" ), "2", gate = None ), "[C] n_rs_no_impl",
     "a trait with no implementor in the tree: declined by name as before (cands=\"2\", no gate=)", a.why() )
a = ask( CPP, "callees", "hollowCall" )
say( a.ok and sorted( ( r.get( "n" ), r.get( "via" ) ) for r in a.rows ) == [ ( "hollowRun", "name" ) ] * 2 and not a.dc, "[C] n_cpp_no_impl",
     "C++ an abstract base with no subclass: today's by-name rows, untouched", a.why() )
af = ask( CPP, "callees", "byPointer", "--legend=full" )
cs = cand_set( af, "StartCommand", line_of( DRIVE_CC, "r->StartCommand" ) ) or set()
say( af.ok and len( cs ) == 2 and "runners.cc:18" not in cs, "[P] n_cpp_arity", "DryRunCommandRunner::StartCommand( Edge*, int ) (two parameters) is not a candidate of a one-argument call", str( cs ) )
say( af.ok and len( cs ) == 2 and not any( c.startswith( "runner.h" ) for c in cs ), "[P] n_cpp_no_decl", "the base's own pure-virtual declaration is not a candidate", str( cs ) )
af = ask( RS, "callees", "dyn_ref", "--legend=full" )
cs = cand_set( af, "render", line_of( DRIVE_RS, "r.render(2)" ) ) or set()
fake = "src/render/impls.rs:" + line_of( IMPLS_RS, "fn render", 6 )
say( af.ok and fake in cs, "[C] n_rs_test_impl", "the #[cfg(test)] implementor is a candidate (%s): a test may be what runs it" % fake, str( cs ) )

# ── (K) candidate-set completeness (fix round 1, B1; reports/dispatch-classes.md §(a) 5) ────────────────────────────
# EXACT OR NO ROW: a via="impl" edge needs the whole in-tree implementor set. Where an implementor can exist with no clause the
# map reads — a structurally conforming TS object literal or class, a Java lambda / anonymous class, a Kotlin `fun interface`
# lambda or object expression, a Rust trait mockall's attribute implements — the tier steps aside and main's by-name rows stay.
print( "=== (K) completeness: an implementor without a clause opens the list ===" )
B1TS, B1JAVA, B1KT, B1RS, FC2U, FC2D = ( os.path.join( FIX, d ) for d in ( "b1ts", "b1java", "b1kt", "b1rs", "fc2rs_undecided", "fc2rs_decided" ) )
def rows_are( a, want ):
    return a.ok and sorted( ( r.get( "n" ), r.get( "p" ), r.get( "via" ) ) for r in a.rows ) == sorted( want ) and not a.dc
for root, sel, want, tag, why in (
        ( B1TS, "serve", [ ( "route", "src/lit.ts:3", "name" ), ( "route", "src/lit.ts:6", "name" ), ( "route", "src/r.ts:5", "name" ) ], "ts_literal",
          "TS: memRouter (an object literal typed Router) and StructRouter (no implements clause) can run r.route" ),
        ( B1JAVA, "run", [ ( "handle", "app/LogHandler.java:2", "name" ), ( "handle", "app/Use.java:7", "name" ) ], "java_sam_anon",
          "Java: Handler takes a lambda (one abstract method) and an anonymous class (Use.java:7)" ),
        ( B1JAVA, "runTwo", [ ( "first", "app/TwoImpl.java:2", "name" ), ( "first", "app/UseTwo.java:6", "name" ) ], "java_anon",
          "Java: a two-method interface with an anonymous class `new Two() { … }` — no lambda involved" ),
        ( B1JAVA, "runFn", [ ( "apply", "app/FnImpl.java:2", "name" ) ], "java_sam",
          "Java: a single-abstract-method interface a lambda implements (`runFn(x -> x * 2)`), no anonymous class" ),
        ( B1KT, "run", [ ( "apply", "A.kt:3", "name" ) ], "kt_fun_object", "Kotlin: `fun interface Op` with a lambda and an `object : Op` expression" ),
        ( B1KT, "runTwo", [ ( "first", "B.kt:3", "name" ) ], "kt_object", "Kotlin: a two-method interface with an `object : Two { … }` expression" ),
        ( B1KT, "runLam", [ ( "call", "C.kt:3", "name" ) ], "kt_fun", "Kotlin: `fun interface Lam` a lambda implements (`runLam { it + 1 }`)" ),
        ):
    a = ask( root, "callees", sel )
    say( rows_are( a, want ), "[P] k_%s" % tag, "--callees=%s: main's by-name rows %s, no via=\"impl\" -- %s" % ( sel, [ w[ 1 ] for w in want ], why ), a.why() )
# Rust: `#[cfg_attr(any(test, feature = "mock"), automock)]` writes MockFilter, an implementor no source holds (envoy send_500). Lane receiver-fixes
# (fix 1, F4): the open list's one visible candidate (FilterImpl) no longer falls to main's by-name row — it DECLINES (cands=1, gate=iface, bound=F:
# Filter), never an edge and never via="impl" (a mock may override it).
a = ask( B1RS, "callees", "send_500" )
say( a.ok and not a.rows and one_dc( a, "send_response", "16", "1", "iface", "F: Filter" ), "[P] k_rs_automock",
     "--callees=send_500: one <dc gate=\"iface\" cands=\"1\"> (FilterImpl; MockFilter is unseen), no edge, no via=\"impl\" -- Rust automock (envoy send_500)", a.why() )
# Rust (train 34, fc2 x L6): `impl Render for Square` under `use mystery_crate::Render` (no module, no std sibling, no declared dependency) is
# undecided, dropped from the implementor map (--lego=Render says implementors_floor=1): the list is open, so Circle is not the proven only
# implementor. Lane receiver-fixes (RUST-DYN-NAMESAKE): an open trait list now DECLINES over every `impl Render for X` block's draw (Square's
# may be ours) instead of main's two by-name rows — never via="impl", never an edge.
rc, out = run( FC2U, "--callees=go", "--legend=full" )
dcs = re.findall( r'<dc n="draw"[^>]*/>', out )
say( rc == 0 and len( dcs ) == 1 and 'gate="iface"' in dcs[ 0 ] and 'cands="2"' in dcs[ 0 ] and "src/a.rs:6" in dcs[ 0 ] and "src/b.rs:8" in dcs[ 0 ]
     and 'via="impl"' not in out and not re.search( r'<s [^>]*n="draw"', out ), "[P] k_rs_undecided_use",
     '--callees=go: one <dc gate="iface" cands="2"> over Circle and Square (the open list declines), no via="impl", no edge', "rc=%s dc=%s" % ( rc, dcs ) )

# precondition and control for k_rs_undecided_use: the interface row really carries the floor (else the arm proves nothing), and the same
# tree with the head DECLARED as a registry dependency (decided outside) keeps the one proven implementor
rc, out = run( FC2U, "--lego=Render" )
try:
    ifaces = [ e.attrib for e in ET.fromstring( "<doc>" + out + "</doc>" ).iter( "iface" ) ]
except ET.ParseError:
    ifaces = []
say( rc == 0 and len( ifaces ) == 1 and ifaces[ 0 ].get( "implementors_floor" ) == "1", "[C] k_rs_undecided_floor",
     "--lego=Render on the undecided tree says implementors_floor=1 (the clause is dropped, not decided)", "rc=%s ifaces=%s" % ( rc, ifaces ) )
a = ask( FC2D, "callees", "go" )
say( rows_are( a, [ ( "draw", "src/a.rs:6", "impl" ) ] ), "[C] k_rs_decided_outside",
     "--callees=go with `mystery_crate` a declared registry dependency: Square implements an outside trait, Circle is the proven only implementor", a.why() )

# ── (K2) the SAM count (fix round 2, C2; the review's javaeq / javaeq2 / javasame / ktjava) ────────────────────────────────────
# A lambda implements an interface with ONE abstract method (JLS 9.8), so every doubt opens the list: an Object method redeclared is
# no abstract method of the count, `a.Handler` is not made non-SAM by `b.Handler`'s methods, and Java passes a lambda to a Kotlin
# interface. The controls prove the rule is not "always open": two real methods (or two same-named two-method interfaces) keep impl.
print( "=== (K2) the SAM count: Object methods, class identity, Kotlin from Java ===" )
SAMO, SAMOA, SAMP, SAMK, SAM2, SAMKO = ( os.path.join( FIX, d ) for d in ( "sam_obj", "sam_obj_anno", "sam_pkg", "sam_kt", "sam_two", "sam_kt_only" ) )
for root, sel, want, kind, tag, why in (
        ( SAMO, "run", [ ( "compare", "app/LenCmp.java:3", "name" ) ], "P", "obj_equals",
          "Java: Cmp redeclares equals( Object ) (Comparator does): one abstract method, so `run( ( a, b ) -> … )` can run" ),
        ( SAMOA, "run", [ ( "hash", "app/Fnv.java:3", "name" ) ], "P", "obj_anno",
          "Java: @FunctionalInterface Hasher redeclares toString() and hashCode(): still one abstract method (`String::length`)" ),
        ( SAMP, "run", [ ( "handle", "a/LogHandler.java:3", "name" ) ], "P", "same_name",
          "Java: a.Handler has one method; the unrelated b.Handler's open() / close() do not make it two" ),
        ( SAMK, "runOp", [ ( "ap", "app/Op.kt:6", "name" ) ], "P", "kotlin_sam",
          "Kotlin: `interface Op { fun ap }` (not `fun interface`) takes a Java lambda: OpKt.runOp( x -> x * 2 )" ),
        ( SAM2, "run", [ ( "first", "app/PairImpl.java:3", "impl" ) ], "C", "two_methods",
          "Java: Pair has two methods and equals( Object ): a lambda cannot implement it, the one implementor is proven" ),
        ( SAMP, "fill", [ ( "put", "c/MemSink.java:3", "impl" ) ], "C", "same_name_multi",
          "Java: c.Sink and d.Sink each have two methods: no interface of the name is a SAM type, impl stays" ),
        ( SAMK, "runTwo", [ ( "first", "app/Op.kt:14", "impl" ) ], "C", "kotlin_two",
          "Kotlin: a two-method interface beside Java files: no lambda converts it, impl stays" ),
        ( SAMKO, "runOp", [ ( "ap", "app/Op.kt:6", "impl" ) ], "C", "kotlin_only",
          "Kotlin: the same one-method interface in a tree with no Java file: nothing can pass a lambda, impl stays" ) ):
    a = ask( root, "callees", sel )
    say( rows_are( a, want ), "[%s] k2_%s" % ( kind, tag ), "--callees=%s: %s -- %s" % ( sel, [ ( w[ 1 ], w[ 2 ] ) for w in want ], why ), a.why() )

# (K2, fix round 3, D1) Kotlin reads an interface as a class, so a SAM needs a count of exactly one -- but a count of 0 that the index
# DOUBTED (T's own name shared, or a base named by two classes / none in the tree) is a lower bound, never a certain 0: the list opens.
# The controls (a base the index names exactly, generic or Java) keep the count certain, and the list open by the SAM rule alone.
print( "=== (K2) fix round 3: a doubted Kotlin count of 0 opens the list ===" )
KB, KO, KJ, KI, KG, KJU = ( os.path.join( FIX, d ) for d in ( "sam_kt_base_shared", "sam_kt_own_shared", "sam_kt_javabase_shared", "sam_kt_inherit",
                                                              "sam_kt_generic", "sam_kt_javabase" ) )
for root, want, kind, tag, why in (
        ( KB, [ ( "ap", "app/Op.kt:4", "name" ) ], "P", "kt_base_shared",
          "Kotlin: `Sub : Base` where an unrelated other.Base { p; q } shares Base's name: Sub may be Base's one method, the lambda can run" ),
        ( KO, [ ( "ap", "app/Op.kt:4", "name" ) ], "P", "kt_own_shared",
          "Kotlin: `Sub : Base` where an unrelated other.Sub { z } shares Sub's own name: its bases cannot be told apart, so it is open" ),
        ( KJ, [ ( "ap", "app/Op.kt:3", "name" ) ], "P", "kt_javabase_shared",
          "Kotlin `Sub : Base` over a Java SAM Base, with an unrelated Java other.Base { p; q }: open" ),
        ( KI, [ ( "ap", "app/Op.kt:4", "name" ) ], "C", "kt_inherit", "Kotlin: `Sub : Base`, no shared name: the SAM is inherited, open" ),
        ( KG, [ ( "ap", "app/Op.kt:4", "name" ) ], "C", "kt_generic", "Kotlin: `Sub : Base<Int>`: open" ),
        ( KJU, [ ( "ap", "app/Op.kt:3", "name" ) ], "C", "kt_javabase", "Kotlin `Sub : Base` over a uniquely named Java SAM: open" ) ):
    a = ask( root, "callees", "runSub" )
    say( rows_are( a, want ), "[%s] k2r3_%s" % ( kind, tag ), "--callees=runSub: %s -- %s" % ( [ ( w[ 1 ], w[ 2 ] ) for w in want ], why ), a.why() )

# (K2, fix round 4, E1) a name a sub-interface (or a middle interface) re-declares WITH A BODY is no abstract member: since Kotlin 2.2 it is a
# JVM default method, so Java sees the one abstract method `ap` and a lambda can be the receiver. Counting the base's `bp` too read 2 and
# closed the list (a false via="impl"). Controls: a Java `default` method, a body-less re-declaration (still abstract: 2, impl stays), an
# overload the index cannot match by arity (dropped by name, doubted: open, an over-hedge), and every arm above.
print( "=== (K2) fix round 4: a body that re-declares an inherited abstract name is not abstract ===" )
KD, KDD, KRA, KDO, JD, KCE = ( os.path.join( FIX, d ) for d in ( "sam_kt_default_override", "sam_kt_default_diamond", "sam_kt_redeclare_abstract",
                                                           "sam_kt_default_overload", "sam_java_default_override", "sam_kt_concrete_ext" ) )
for root, sel, want, kind, tag, why in (
        ( KD, "runSub", [ ( "ap", "app/Op.kt:4", "name" ) ], "P", "kt_default_override",
          "Kotlin: `Sub : Base { override fun bp() = 0 }`: bp has a body, one abstract method (ap) is left, the lambda can run" ),
        ( KDD, "runSub", [ ( "ap", "app/Op.kt:5", "name" ) ], "P", "kt_default_diamond",
          "Kotlin: the default lives on a middle interface Def : Base, Sub : Def: still one abstract method" ),
        ( KDO, "runSub", [ ( "ap", "app/Op.kt:4", "name" ) ], "P", "kt_default_overload",
          "Kotlin: Base { ap; bp(); bp( n ) }, Sub gives bp( n ) a body: matched by name only, so the count is doubted and the list opens" ),
        ( JD, "runSub", [ ( "a", "app/Inc.java:2", "name" ) ], "C", "java_default", "Java: `Sub extends Base { default int b() }`: unchanged, open" ),
        ( KCE, "runBase", [ ( "ap", "app/Op.kt:3", "impl" ) ], "C", "kt_concrete_ext",
          "Kotlin: a concrete Inc : Base, Closeable overriding every Base member (an external base): not an interface, impl stays" ),
        ( KRA, "runSub", [ ( "ap", "app/Op.kt:4", "impl" ) ], "C", "kt_redeclare_abstract",
          "Kotlin: `Sub : Base { override fun bp(): Int }` stays abstract: two abstract methods, no lambda converts it, impl stays" ) ):
    a = ask( root, "callees", sel )
    say( rows_are( a, want ), "[%s] k2r4_%s" % ( kind, tag ), "--callees=%s: %s -- %s" % ( sel, [ ( w[ 1 ], w[ 2 ] ) for w in want ], why ), a.why() )

# (K2, fix round 5, NIT-1 + the count's upward drop) the bodied-base-member rule (ReceiverEvidence::methodOf) answered with an ANCESTOR body even
# when a nearer interface on the path re-declares the name abstract (Base { ap() = 0 } above Mid { override fun ap( x ): Int }): the nearest
# declaration wins, so the call hedges (the dispatch tier and the name tiers answer). A body of another parameter count is no answer either:
# Kotlin has no call arity, so a bodyless overload of a count no body has, above the body, hedges (Java's arity is the name tiers' own rule). The SAM count
# drops an abstract name only for a body at or BELOW the class declaring it: with the rule above fixed, kt_reabstract_mid must read ONE
# abstract method (a lambda converts it: via="name"), never a certain 0 (a false via="impl"). An own re-declaration (kt_own_reabstract) is red the same way: Base.ap, no via.
print( "=== (K2) fix round 5: the nearest declaration wins; a body above a re-declaration never runs ===" )
KRM, JDK, KRAR, KOR = ( os.path.join( FIX, d ) for d in ( "kt_reabstract_mid", "java_default_kt_reabstract", "kt_reabstract_arity", "kt_own_reabstract" ) )
for root, sel, want, kind, tag, why in (
        ( KRM, "runSub", [ ( "ap", "app/Op.kt:2", "name" ), ( "ap", "app/Op.kt:5", "name" ) ], "P", "kt_reabstract_mid",
          "Kotlin: Base { ap() = 0 }, Mid : Base { override fun ap( x ) } abstract again, Sub : Mid: Base's body never runs, no unhedged row onto it (and the count reads one abstract method)" ),
        ( JDK, "runSub", [ ( "ap", "app/Op.kt:4", "name" ) ], "P", "java_default_kt_reabstract",
          "Kotlin Mid re-declares a Java Base's `default` method abstract: no unhedged row onto Base.java" ),
        ( KRAR, "runSub", [ ( "ap", "app/Op.kt:2", "name" ), ( "ap", "app/Op.kt:4", "name" ), ( "ap", "app/Op.kt:5", "name" ) ], "P", "kt_reabstract_arity",
          "Kotlin: Sub's bodied ap() and Mid's abstract ap( x ): the call ap( 1 ) is not Sub.ap(), no unhedged row onto it" ),
        ( KOR, "runSub", [ ( "ap", "app/Op.kt:4", "impl" ) ], "P", "kt_own_reabstract",
          "Kotlin: Sub re-declares Base's bodied ap abstract itself: two abstract methods, not a SAM, Inc is the only implementor: impl" ) ):
    a = ask( root, "callees", sel )
    say( rows_are( a, want ), "[%s] k2r5_%s" % ( kind, tag ), "--callees=%s: %s -- %s" % ( sel, [ ( w[ 1 ], w[ 2 ] ) for w in want ], why ), a.why() )

# ── (M) Rust method set (fix round 1, B2; §(a) 4): through dyn T only T's impl blocks and defaults can run ───────────────────
print( "=== (Q) train 33: the rows carry QUALNAME-1's owner spelling (the arms above compare member name + p=) ===" )
for root, sel, qn, p, tag in ( ( CPP, "soloCall", "OnlySolo::soloRun", "runners.cc:23", "cpp" ),
                               ( RS, "solo_dyn", "OnlySolo::solo_step", "src/solo/mod.rs:8", "rs" ),
                               ( SAMKO, "runOp", "Inc.ap", "app/Op.kt:6", "kt" ),
                               ( JAVA, "single", "singleRun", "app/OnlySingle.java:4", "java_bare" ) ):
    a = ask( root, "callees", sel )
    say( a.ok and [ r.get( "qn" ) for r in a.rows if r.get( "p" ) == p ] == [ qn ], "[C] q_%s" % tag,
         "--callees=%s: the row at %s prints n=\"%s\" (owner from the stored scope; Java stores none: bare)" % ( sel, p, qn ), a.why() )

print( "=== (K3) cr-prepass-33a: an anonymous class's ImplBlock record binds no local NAME (CHECKLIST 36: a widened kind's reader audit) ===" )
# A Java `new Handler() { ... }` records an ImplBlock (var = Handler) attributed to the enclosing method, or to the class for a field
# initialiser. The generic binding readers (localNameSet, the Java field-name groups) once read it as a local/field NAMED Handler,
# which vetoed Rule 2c's class-name receiver: `Handler.of( 1 )` fell to by-name rows naming Other.of too (main: one proven edge).
ANON = os.path.join( FIX, "anon_static" )
for sel, tag in ( ( "inMethod", "method" ), ( "viaField", "field" ) ):
    a = ask( ANON, "callees", sel )
    of_rows = [ r for r in a.rows if r.get( "n" ) == "of" ]
    say( a.ok and [ r.get( "p" ) for r in of_rows ] == [ "app/Handler.java:4" ] and all( r.get( "via" ) != "name" for r in of_rows ),
         "[P] k3_anon_static_%s" % tag,
         "--callees=%s: Handler.of( 1 ) stays the one proven edge (app/Handler.java:4), not by-name rows with Other.of, beside an anonymous Handler" % sel, a.why() )

print( "=== (M) Rust: an inherent method is never a trait-dispatched candidate ===" )
a = ask( B1RS, "callees", "via_ext" )
say( rows_are( a, [ ( "helper", "src/t.rs:2", "name" ), ( "helper", "src/t.rs:9", "name" ) ] ), "[P] m_rs_supertrait",
     "x.helper() on &dyn Foo runs supertrait Ext's default (t.rs:2), not X's inherent helper (t.rs:9): main's hedged rows, never t.rs:9 via=\"impl\"", a.why() )
a = ask( B1RS, "callees", "via_inherent" )
say( rows_are( a, [ ( "only_inherent", "src/t.rs:10", "name" ) ] ), "[P] m_rs_inherent",
     "x.only_inherent() on &dyn Foo (an inherent-only method; no trait has it): main's by-name row, never via=\"impl\"", a.why() )
a = ask( B1RS, "callees", "via_dup" )
say( rows_are( a, [ ( "go", "src/dup.rs:15", "impl" ) ] ), "[P] m_rs_impl_block",
     "z.go() on &dyn Step: `impl Step for Z`'s go (dup.rs:15) via=\"impl\"; Z's inherent go (dup.rs:9) is no candidate", a.why() )

# ── (L) legend ─────────────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (L) legend ===" )
a = ask( TS, "callees", "dispatch" )
say( a.ok and one_dc( a, "match", "4", "2" ) and "K is a floor" in a.legend, "[P] l_iface_floor",
     "a gate=\"iface\" row's legend says cands=K is a floor (a structurally conforming TS type is not counted)", a.legend[ -500: ] )
a = ask( B1RS, "callees", "std_len" )
say( a.ok and any( d.get( "gate" ) == "std" for d in a.dc ) and "iface" not in a.legend, "[P] l_iface_absent",
     "an answer whose only <dc> is gate=\"std\" carries no iface clause (N2: the clause rides with an iface row)", a.legend[ -500: ] )
a = ask( RS, "callees", "dyn_ref" )
say( a.ok and "iface" in a.legend and "which one runs is unproven" in a.legend, "[P] l_iface",
     "an answer with a gate=\"iface\" row defines it: the receiver's interface's implementors, which one runs is unproven", a.legend[ -400: ] )
a = ask( RS, "callees", "bound_generic" )
say( a.ok and "bound=" in a.legend, "[P] l_bound", "an answer with bound= defines it", a.legend[ -400: ] )
a = ask( RS, "callees", "bound_generic", "--legend=full" )
say( a.ok and "gate=\"iface\"" in a.legend and "which one runs is unproven" in a.legend and "bound=\"G: T\"" in a.legend, "[P] l_full",
     "--legend=full defines gate=\"iface\" and bound=\"G: T\" in the full clause", a.legend[ -500: ] )
a = ask( RS, "callees", "solo_dyn" )
say( a.ok and "via=impl" in a.legend.replace( '"', '' ) and ( "ONE implementor" in a.legend or "only implementor" in a.legend ), "[P] l_impl",
     "an answer with a via=\"impl\" row defines it (the only implementor in the tree)", a.legend[ -400: ] )
a = ask( RS, "callees", "lonely_dyn" )
say( a.ok and "which one runs is unproven" not in a.legend and "via=impl" not in a.legend.replace( '"', '' ), "[C] l_absent", "an answer without either carries neither clause", a.legend[ -300: ] )

# ── (J) --json ─────────────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (J) --json ===" )
rc, out = run( RS, "--callees=bound_generic", "--json" )
try:
    j = json.loads( out )
except ValueError:
    j = {}
dcs = j.get( "dc", [] )
say( rc == 0 and len( dcs ) == 1 and dcs[ 0 ].get( "gate" ) == "iface" and dcs[ 0 ].get( "bound" ) == "R: Renderer" and dcs[ 0 ].get( "cands" ) == 6,
     "[P] j_json", "--json \"dc\":[{... \"cands\":6, \"gate\":\"iface\", \"bound\":\"R: Renderer\"}]", out[ :400 ] )

# ── (Go) floor ─────────────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (Go) FLOOR: structural interfaces ===" )
a = ask( GO, "callees", "doPackage" )
say( a.ok and one_dc( a, "Package", line_of( os.path.join( GO, "cmd", "package.go" ), "pkg.Package" ), "6", gate = None ), "[FLOOR] go_structural",
     "Go: no implements clause names a Packager implementor, so the tier has none; the row stays the name list (4c structural conformance)", a.why() )

print( "ifacedispatchcheck: %d PASS, %d FAIL" % ( npass, nfail ) )
sys.exit( 1 if nfail else 0 )
PY
[ "$fail" -eq 0 ] && echo "ifacedispatchcheck: ALL PASS" || { echo "ifacedispatchcheck: FAILED"; exit 1; }
