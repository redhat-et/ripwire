#!/usr/bin/env python3
"""scripts/pgocorpus.py — write the SYNTHETIC second training corpus for scripts/pgobuild.sh.

    python3 scripts/pgocorpus.py OUTDIR [--seed N] [--scale N]

WHY. PGO counts what the training workload executes, so a path the workload never reaches is laid out as
cold however hot it is in the field. Training on this checkout alone reaches the C++ extractor and the core
graph, but ripwire's own source has few NAMESAKE classes: the llvm-scale hot paths (class identity over
shared names — every `Base`, `Impl`, `A`, `B` in a tree — the guarded base walk, the per-(class, callee)
memos, receiver narrowing through call-result chains, overload picks by argument type) see a handful of
keys here and millions there. This corpus is shaped to reach them, plus one slice of every other language
family so their extractors are profiled at all.

WHAT IT WRITES (default --scale 2: ~420 files, ~0.4 MB; a cold map of it is a fraction of one of this checkout):
  cpp/modK/          K namespaces that ALL define the same class names (Root, Base, Impl, A, B, a deep
                     DerivedN chain, Node, Context, Builder), headers + out-of-line member definitions,
                     overloads (add(int) / add(const Node&) / add(Base*) / add(const char*, int)), call-result
                     chains (context().builder().create()->owner()->run()), cross-namespace use through
                     qualified names and `using namespace`, function-local lambdas and structs named like
                     members (function-local reach), and one copy-pasted helper per namespace (clones)
  cpp/flat/          global-scope `struct Base` / `struct Impl : Base` redefined per file with bare inherited
                     calls in a method — the guarded-walk shape (clang/test-like: one name, many classes)
  cpp/shapes/        one pure-virtual interface, many overriding classes, and classes inheriting bodies
                     through a second base — the subclass / inherited-definition step
  cpp/hub.cpp        dispatchAll: one function calling into every namespace (an --expand / --impact hub)
  poly/<lang>/       Python, TypeScript, JavaScript, Java, Ruby, Go, Rust, Swift, C#, C, Objective-C, Bash and
                     CUDA — the same Base/Impl shape in each, with imports between files and one external import
  tests/, README.md, config.json   a test tree (the tested lens), a doc (doc mentions), a JSON config

RULES THIS FOLLOWS.
  * DETERMINISTIC: one seeded splitmix64 stream (never Python's `random`, whose algorithms are not a contract
    across versions), files written in sorted order, "\n" endings, no timestamps. Same arguments -> same bytes;
    test/optremarkscheck.sh asserts it.
  * NO NETWORK, NO DEPENDENCIES: the standard library only, so the release workflow's checkout is enough.
  * NOT A BENCHMARK: every name here is invented. The script never reads a corpus — it only writes one.
"""

import argparse
import os
import sys

MASK = ( 1 << 64 ) - 1


class SplitMix64:
    """A fixed, specified PRNG: the bytes this script writes must not depend on the Python version."""

    def __init__( self, seed ):
        self.state = seed & MASK

    def next( self ):
        self.state = ( self.state + 0x9E3779B97F4A7C15 ) & MASK
        z = self.state
        z = ( ( z ^ ( z >> 30 ) ) * 0xBF58476D1CE4E5B9 ) & MASK
        z = ( ( z ^ ( z >> 27 ) ) * 0x94D049BB133111EB ) & MASK
        return z ^ ( z >> 31 )

    def below( self, n ):
        return self.next() % n

    def pick( self, seq ):
        return seq[ self.below( len( seq ) ) ]


# ── C++: K namespaces, one set of class names ──────────────────────────────────────────────────────────────

CHAIN_MAX = 6   # Base -> Impl -> A -> B -> Derived1..DerivedN, N drawn per namespace in 1..CHAIN_MAX


def cppHeader( k, depth ):
    out = [ "#pragma once", "", "namespace mod%d" % k, "{", "",
            "class Node;", "class Context;", "class Builder;", "",
            "class Root", "{", "public:", "    virtual ~Root();", "    void r();", "    int depth() const;", "};", "",
            "class Base : public Root", "{", "public:",
            "    virtual void run();", "    virtual void visit( Node* n ) = 0;", "    Base* next() const;",
            "    Context& context();", "    int size() const;", "};", "",
            "class Impl : public Base", "{", "public:",
            "    void run() override;", "    void visit( Node* n ) override;", "    void step();", "    Impl* clone() const;", "};", "",
            "class A : public Impl", "{", "public:", "    void run() override;", "    void stepA();", "};", "",
            "class B : public A", "{", "public:", "    void visit( Node* n ) override;", "    void stepB();", "};", "" ]
    parent = "B"
    for d in range( 1, depth + 1 ):
        name = "Derived%d" % d
        out += [ "class %s : public %s" % ( name, parent ), "{", "public:",
                 "    void run() override;", "    void step%d();" % d, "};", "" ]
        parent = name
    out += [ "class Node", "{", "public:", "    Node* parent();", "    Base* owner();", "    Impl* impl();",
             "    int kind() const;", "};", "",
             "class Builder", "{", "public:", "    Node* create();",
             "    void add( int v );", "    void add( const Node& n );", "    void add( Base* b );",
             "    void add( const char* s, int n );", "    Builder& with( int v );", "};", "",
             "class Context", "{", "public:", "    Builder& builder();", "    Node* root();", "    Impl* current();", "};", "",
             "int checksum( const int* v, int n );", "void drive( Context& ctx );", "",
             "} // namespace mod%d" % k, "" ]
    return "\n".join( out )


def cppImpl( k, depth, rng, nsCount ):
    out = [ '#include "Base.h"', "", "namespace mod%d" % k, "{", "",
            "Root::~Root() { }", "void Root::r() { }", "int Root::depth() const { return 0; }", "",
            "void Base::run()", "{", "    r();", "    if( next() )", "    {", "        next()->run();", "    }", "}", "",
            "Base* Base::next() const { return nullptr; }",
            "int Base::size() const { return depth() + 1; }", "",
            "void Impl::run()", "{", "    step();", "    Base::run();",
            "    context().builder().create()->owner()->run();",
            "    context().root()->impl()->step();",
            "    size();", "    r();", "}", "",
            "void Impl::visit( Node* n )", "{", "    Builder& b = context().builder();",
            "    b.add( 1 );", "    b.add( *n );", "    b.add( n->owner() );", '    b.add( "impl", %d );' % k,
            "    b.with( 2 ).with( 3 ).add( this );", "    n->parent()->owner()->visit( n );", "}", "",
            "void Impl::step()", "{", "    clone()->run();", "    next()->size();", "}", "",
            "Impl* Impl::clone() const { return nullptr; }", "",
            "void A::run()", "{", "    stepA();", "    Impl::run();", "    step();", "}", "",
            "void A::stepA()", "{", "    context().current()->step();", "    r();", "}", "",
            "void B::visit( Node* n )", "{", "    stepB();", "    stepA();", "    A::visit( n );", "    n->impl()->clone()->visit( n );", "}", "",
            "void B::stepB()", "{", "    run();", "    size();", "}", "" ]
    parent = "B"
    for d in range( 1, depth + 1 ):
        name = "Derived%d" % d
        calls = [ "    step%d();" % d, "    %s::run();" % parent, "    stepB();" ]
        for _ in range( 1 + rng.below( 3 ) ):
            calls.append( rng.pick( [ "    step();", "    stepA();", "    r();", "    size();", "    context().builder().create()->impl()->step();" ] ) )
        out += [ "void %s::run()" % name, "{" ] + calls + [ "}", "", "void %s::step%d()" % ( name, d ), "{", "    run();", "}", "" ]
        parent = name
    # Node / Builder / Context bodies: call-result chains whose receiver type comes from a return type.
    out += [ "Node* Node::parent() { return this; }", "Base* Node::owner() { return impl(); }",
             "Impl* Node::impl() { return nullptr; }", "int Node::kind() const { return %d; }" % k, "",
             "Node* Builder::create() { return nullptr; }",
             "void Builder::add( int v ) { with( v ); }",
             "void Builder::add( const Node& n ) { add( n.kind() ); }",
             "void Builder::add( Base* b ) { add( b->size() ); }",
             "void Builder::add( const char* s, int n ) { add( n + ( s ? 1 : 0 ) ); }",
             "Builder& Builder::with( int v ) { ( void )v; return *this; }", "",
             "Builder& Context::builder() { static Builder b; return b; }",
             "Node* Context::root() { return builder().create(); }",
             "Impl* Context::current() { return root()->impl(); }", "" ]
    # The same helper body in every namespace — what --clones exists to find.
    out += [ "int checksum( const int* v, int n )", "{", "    int acc = 17;", "    for( int i = 0; i < n; ++i )", "    {",
             "        acc = acc * 31 + v[ i ];", "        if( acc > 1000003 )", "        {", "            acc %= 1000003;", "        }",
             "        else if( acc < 0 )", "        {", "            acc = -acc;", "        }", "    }",
             "    return acc ^ ( n << 3 );", "}", "" ]
    # drive: local variables typed by namesake classes, and a hop into another namespace.
    other = ( k + 1 + rng.below( nsCount - 1 ) ) % nsCount
    out += [ "void drive( Context& ctx )", "{", "    auto step = [&]( int v ) { ctx.builder().add( v ); };", "    auto run = [&]() { step( 1 ); };",
             "    struct Local { void visit() { } };", "    Local{}.visit();", "    run();", "    step( 2 );",
             "    Impl* p = ctx.current();", "    p->run();", "    p->clone()->step();",
             "    B b;", "    b.stepB();", "    b.visit( ctx.root() );", "    A* a = &b;", "    a->stepA();",
             "    Base* base = ctx.root()->owner();", "    base->run();",
             "    mod%d::Impl* far = nullptr;" % other, "    far->step();",
             "    mod%d::drive( *reinterpret_cast<mod%d::Context*>( &ctx ) );" % ( other, other ), "}", "",
             "} // namespace mod%d" % k, "" ]
    return "\n".join( out )


def cppUse( k, rng, nsCount ):
    a = ( k + 2 ) % nsCount
    b = ( k + 3 + rng.below( max( 1, nsCount - 3 ) ) ) % nsCount
    out = [ '#include "Base.h"', '#include "../mod%d/Base.h"' % a, "", "using namespace mod%d;" % a, "",
            "namespace mod%d" % k, "{", "namespace", "{", "",
            "struct Impl2 : public mod%d::Impl" % k, "{", "    void run() override", "    {", "        step();", "        Impl::run();",
            "        context().builder().add( this );", "    }", "};", "",
            "void local( mod%d::Builder& b, mod%d::Node& n )" % ( a, a ), "{", "    b.add( 7 );", "    b.add( n );", "    b.add( n.owner() );",
            "    b.create()->impl()->step();", "}", "", "} // namespace", "",
            "void useAll( Context& ctx )", "{", "    auto drive = [&]( int n ) { return n + 1; };", "    drive( 3 );", "    Impl2 x;", "    x.run();", "    mod%d::drive( ctx );" % k,
            "    mod%d::Impl y;" % b, "    y.step();", "    mod%d::B z;" % b, "    z.stepB();", "    z.run();",
            "    mod%d::Context* other = nullptr;" % a, "    other->builder().with( 1 ).create()->owner()->run();",
            "    mod%d::drive( *other );" % a, "}", "", "} // namespace mod%d" % k, "" ]
    return "\n".join( out )


def cppFlat( f, files, calls ):
    """The guarded-walk shape: `Base` / `Impl` redefined at global scope in every file, bare inherited calls."""
    out = [ "struct Root%d { void r(); };" % f, "struct Base : Root%d { void b%d(); void shared(); };" % ( f, f ),
            "struct Impl : Base", "{", "    void run%d()" % f, "    {" ]
    for m in range( calls ):
        out += [ "        b%d();" % ( m % files ), "        r();" ]
    out += [ "        shared();", "    }", "};", "", "struct A : Impl { void a%d() { run%d(); shared(); b%d(); } };" % ( f, f, f ), "" ]
    return "\n".join( out )


def cppShapes( count, methods ):
    files = {}
    head = [ "#pragma once", "struct Shape", "{" ] + [ "    virtual void f%d() = 0;" % i for i in range( methods ) ] + [ "};",
             "struct Painter", "{" ] + [ "    void f%d() { }" % i for i in range( methods ) ] + [ "};", "" ]
    files[ "cpp/shapes/shape.h" ] = "\n".join( head )
    for k in range( count ):
        body = [ '#include "shape.h"', "struct Circle%d : Shape" % k, "{" ] + [ "    void f%d() override { }" % i for i in range( methods ) ]
        body += [ "};", "struct Square%d : Shape, Painter { };" % k, "" ]
        files[ "cpp/shapes/c%d.cpp" % k ] = "\n".join( body )
    use = [ '#include "shape.h"', "void use( Shape* s )", "{" ] + [ "    s->f%d();" % i for i in range( methods ) ] + [ "}", "" ]
    files[ "cpp/shapes/use.cpp" ] = "\n".join( use )
    return files


def cppHub( nsCount ):
    out = [ "// dispatchAll: the one function that reaches every namespace (an --expand / --impact hub)." ]
    out += [ '#include "mod%d/Base.h"' % k for k in range( nsCount ) ]
    out += [ "", "void dispatchAll()", "{" ]
    for k in range( nsCount ):
        out += [ "    {", "        mod%d::Context ctx;" % k, "        mod%d::drive( ctx );" % k, "        mod%d::useAll( ctx );" % k,
                 "        int v[ 3 ] = { %d, 2, 3 };" % k, "        mod%d::checksum( v, 3 );" % k, "    }" ]
    out += [ "}", "" ]
    return "\n".join( out )


# ── one slice per other language family ────────────────────────────────────────────────────────────────────
# Templates, not code: file @I@ of a family, whose import / call neighbour is file @J@ (polyFiles fills both).

POLY = {
    "python": ( "poly/python/pkg/m@I@.py", [
        "import os",
        "from .m@J@ import Impl as Next@J@",
        "",
        "",
        "class Base:",
        "    def run(self):",
        "        return self.step()",
        "",
        "    def step(self):",
        "        return os.getpid()",
        "",
        "",
        "class Impl(Base):",
        "    \"\"\"Impl in module m@I@: overrides run, reaches the next module.\"\"\"",
        "    def run(self):",
        "        super().run()",
        "        self.helper()",
        "        return Next@J@().step()",
        "",
        "    def helper(self):",
        "        return [self.step() for _ in range(3)]",
        "",
        "",
        "def main():",
        "    def step():",
        "        return Impl().run()",
        "",
        "    step()",
        "    Base().step()",
        "",
    ] ),
    "typescript": ( "poly/typescript/src/m@I@.ts", [
        "import { Impl as Next } from './m@J@';",
        "",
        "export interface Runner { run(): number; }",
        "",
        "export class Base implements Runner {",
        "  run(): number { return this.step(); }",
        "  step(): number { return @I@; }",
        "}",
        "",
        "export class Impl extends Base {",
        "  run(): number {",
        "    super.run();",
        "    return new Next().step() + this.helper();",
        "  }",
        "  helper(): number { return this.step() * 2; }",
        "}",
        "",
        "export function main(): void { new Impl().run(); }",
        "",
    ] ),
    "javascript": ( "poly/javascript/lib/m@I@.js", [
        "const { Impl: Next } = require('./m@J@');",
        "",
        "class Base {",
        "  run() { return this.step(); }",
        "  step() { return @I@; }",
        "}",
        "",
        "class Impl extends Base {",
        "  run() { super.run(); return new Next().step() + this.helper(); }",
        "  helper() { return [1, 2, 3].map((x) => this.step() + x).length; }",
        "}",
        "",
        "function main() {",
        "  function step() { return new Impl().run(); }",
        "  return step();",
        "}",
        "",
        "module.exports = { Base, Impl, main };",
        "",
    ] ),
    "java": ( "poly/java/src/pkg/M@I@.java", [
        "package pkg;",
        "",
        "public class M@I@ {",
        "    public static class Base {",
        "        public int run() { return step(); }",
        "        public int step() { return @I@; }",
        "    }",
        "",
        "    public static class Impl extends Base {",
        "        @Override",
        "        public int run() {",
        "            super.run();",
        "            add(1);",
        "            add(\"x\");",
        "            return new M@J@.Impl().step();",
        "        }",
        "        void add(int v) { step(); }",
        "        void add(String s) { add(s.length()); }",
        "    }",
        "",
        "    public static void main(String[] args) { new Impl().run(); }",
        "}",
        "",
    ] ),
    "ruby": ( "poly/ruby/lib/m@I@.rb", [
        "require_relative 'm@J@'",
        "",
        "module M@I@",
        "  class Base",
        "    def run",
        "      step",
        "    end",
        "",
        "    def step",
        "      @I@",
        "    end",
        "  end",
        "",
        "  class Impl < Base",
        "    def run",
        "      super",
        "      helper",
        "      M@J@::Impl.new.step",
        "    end",
        "",
        "    def helper",
        "      3.times.map { step }",
        "    end",
        "  end",
        "end",
        "",
    ] ),
    "go": ( "poly/go/pkg/m@I@.go", [
        "package pkg",
        "",
        "type Runner@I@ interface {",
        "\tRun() int",
        "}",
        "",
        "type Base@I@ struct{}",
        "",
        "func (b *Base@I@) Run() int  { return b.Step() }",
        "func (b *Base@I@) Step() int { return @I@ }",
        "",
        "type Impl@I@ struct {",
        "\tBase@I@",
        "}",
        "",
        "func (m *Impl@I@) Run() int {",
        "\tm.Base@I@.Run()",
        "\tvar n Impl@J@",
        "\treturn n.Step() + m.helper()",
        "}",
        "",
        "func (m *Impl@I@) helper() int { return m.Step() * 2 }",
        "",
    ] ),
    "rust": ( "poly/rust/src/m@I@.rs", [
        "use crate::m@J@::Impl as Next;",
        "",
        "pub trait Runner {",
        "    fn run(&self) -> i32;",
        "    fn step(&self) -> i32 { @I@ }",
        "}",
        "",
        "pub struct Base;",
        "pub struct Impl { base: Base }",
        "",
        "impl Runner for Base {",
        "    fn run(&self) -> i32 { self.step() }",
        "}",
        "",
        "impl Runner for Impl {",
        "    fn run(&self) -> i32 {",
        "        self.base.run();",
        "        Next::new().step() + self.helper()",
        "    }",
        "}",
        "",
        "impl Impl {",
        "    pub fn new() -> Self { Impl { base: Base } }",
        "    fn helper(&self) -> i32 { self.step() * 2 }",
        "}",
        "",
    ] ),
    "swift": ( "poly/swift/Sources/M@I@.swift", [
        "protocol Runner@I@ {",
        "    func run() -> Int",
        "}",
        "",
        "class Base@I@: Runner@I@ {",
        "    func run() -> Int { return step() }",
        "    func step() -> Int { return @I@ }",
        "}",
        "",
        "class Impl@I@: Base@I@ {",
        "    override func run() -> Int {",
        "        _ = super.run()",
        "        return Impl@J@().step() + helper()",
        "    }",
        "    func helper() -> Int { return step() * 2 }",
        "}",
        "",
        "extension Impl@I@ {",
        "    func twice() -> Int { return run() + run() }",
        "}",
        "",
    ] ),
    "csharp": ( "poly/csharp/src/M@I@.cs", [
        "using System;",
        "",
        "namespace Poly.M@I@",
        "{",
        "    public interface IRunner { int Run(); }",
        "",
        "    public class Base : IRunner",
        "    {",
        "        public virtual int Run() { return Step(); }",
        "        public int Step() { return @I@; }",
        "    }",
        "",
        "    public class Impl : Base",
        "    {",
        "        public override int Run()",
        "        {",
        "            base.Run();",
        "            Add(1);",
        "            Add(\"x\");",
        "            return new Poly.M@J@.Impl().Step();",
        "        }",
        "        void Add(int v) { Step(); }",
        "        void Add(string s) { Add(s.Length); }",
        "    }",
        "}",
        "",
    ] ),
    "c": ( "poly/c/m@I@.c", [
        "#include <stddef.h>",
        "",
        "struct impl@I@ { int (*run)( struct impl@I@* ); int n; };",
        "",
        "static int step@I@( struct impl@I@* p ) { return p->n + @I@; }",
        "int run@I@( struct impl@I@* p )",
        "{",
        "    p->run = step@I@;",
        "    return p->run( p ) + step@I@( p );",
        "}",
        "",
        "int run@J@( void* p );",
        "int chain@I@( struct impl@I@* p ) { return run@I@( p ) + run@J@( NULL ); }",
        "",
    ] ),
    "objc": ( "poly/objc/M@I@.m", [
        "#import <Foundation/Foundation.h>",
        "",
        "@interface Base@I@ : NSObject",
        "- (int)run;",
        "- (int)step;",
        "@end",
        "",
        "@interface Impl@I@ : Base@I@",
        "- (int)helper;",
        "@end",
        "",
        "@implementation Base@I@",
        "- (int)run { return [self step]; }",
        "- (int)step { return @I@; }",
        "@end",
        "",
        "@implementation Impl@I@",
        "- (int)run",
        "{",
        "    [super run];",
        "    return [self helper] + [[Impl@J@ new] step];",
        "}",
        "- (int)helper { return [self step] * 2; }",
        "@end",
        "",
    ] ),
    "bash": ( "poly/bash/m@I@.sh", [
        "#!/usr/bin/env bash",
        "# m@I@.sh \u2014 functions that call each other and a sourced neighbour",
        "source \"$(dirname \"$0\")/m@J@.sh\"",
        "",
        "step_@I@() {",
        "    echo @I@",
        "}",
        "",
        "run_@I@() {",
        "    step_@I@",
        "    helper_@I@ \"$@\"",
        "    step_@J@",
        "}",
        "",
        "helper_@I@() {",
        "    for x in \"$@\"; do",
        "        step_@I@ \"$x\"",
        "    done",
        "}",
        "",
    ] ),
    "cuda": ( "poly/cuda/k@I@.cu", [
        "__device__ float scale@I@( float x ) { return x * 2.0f; }",
        "",
        "__global__ void kernel@I@( float* v, int n )",
        "{",
        "    int t = blockIdx.x * blockDim.x + threadIdx.x;",
        "    if( t < n )",
        "    {",
        "        v[ t ] = scale@I@( v[ t ] );",
        "    }",
        "}",
        "",
        "void launch@I@( float* v, int n )",
        "{",
        "    kernel@I@<<<( n + 255 ) / 256, 256>>>( v, n );",
        "}",
        "",
    ] ),
}


def polyFiles( lang, count ):
    path, lines = POLY[ lang ]
    files = {}
    for i in range( count ):
        near = str( ( i + 1 ) % count )
        files[ path.replace( "@I@", str( i ) ) ] = "\n".join( lines ).replace( "@I@", str( i ) ).replace( "@J@", near )
    return files


LANGS = sorted( POLY )


def build( seed, scale ):
    rng = SplitMix64( seed )
    nsCount = 24 * scale
    files = {}
    for k in range( nsCount ):
        depth = 1 + rng.below( CHAIN_MAX )
        files[ "cpp/mod%d/Base.h" % k ] = cppHeader( k, depth )
        files[ "cpp/mod%d/Impl.cpp" % k ] = cppImpl( k, depth, rng, nsCount )
        files[ "cpp/mod%d/Use.cpp" % k ] = cppUse( k, rng, nsCount )
    flatFiles = 32 * scale
    for f in range( flatFiles ):
        files[ "cpp/flat/f%d.cpp" % f ] = cppFlat( f, flatFiles, 16 )
    files.update( cppShapes( 24 * scale, 12 ) )
    files[ "cpp/hub.cpp" ] = cppHub( nsCount )
    files[ "cpp/tests/ImplTest.cpp" ] = "\n".join( [ '#include "../mod0/Base.h"', "void dispatchAll();", "",
                                                     "int testImplRun() { mod0::Context ctx; mod0::drive( ctx ); dispatchAll(); return 0; }", "" ] )
    for lang in LANGS:
        files.update( polyFiles( lang, 6 * scale ) )
    files[ "tests/test_impl.py" ] = "\n".join( [ "from poly.python.pkg.m0 import Impl", "", "", "def test_run():", "    assert Impl().run() is not None", "" ] )
    files[ "README.md" ] = "\n".join( [ "# pgocorpus", "", "A generated PGO training corpus (scripts/pgocorpus.py). Every name is invented.", "",
                                        "## Layout", "", "- `cpp/modK/` — namespaces sharing the class names `Base`, `Impl`, `A`, `B`.",
                                        "- `cpp/hub.cpp` — `dispatchAll` reaches every namespace.", "- `poly/` — one slice per language family.", "" ] )
    files[ "config.json" ] = '{\n  "name": "pgocorpus",\n  "seed": %d,\n  "scale": %d,\n  "namespaces": %d\n}\n' % ( seed, scale, nsCount )
    return files


def main():
    ap = argparse.ArgumentParser( description = "write the synthetic PGO training corpus (deterministic)" )
    ap.add_argument( "outdir" )
    ap.add_argument( "--seed", type = int, default = 20261122 )
    ap.add_argument( "--scale", type = int, default = 2, help = "multiplies every family's file count (default 2)" )
    args = ap.parse_args()
    if args.scale < 1:
        print( "pgocorpus: --scale must be >= 1", file = sys.stderr )
        return 2
    files = build( args.seed, args.scale )
    total = 0
    for rel in sorted( files ):
        path = os.path.join( args.outdir, rel )
        os.makedirs( os.path.dirname( path ), exist_ok = True )
        data = files[ rel ].encode( "utf-8" )
        with open( path, "wb" ) as fh:
            fh.write( data )
        total += len( data )
    print( "pgocorpus: %d files, %d bytes -> %s" % ( len( files ), total, args.outdir ) )
    return 0


if __name__ == "__main__":
    sys.exit( main() )
