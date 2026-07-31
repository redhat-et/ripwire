// cppqualfix/qual.cpp — gate fixture for §H4 (PLAN_h4QualifiedCalls_2026-07-30.md): the C++ qualified-call
// widening. ONE call site per SPELLING, so every count test/cppqualcheck.sh asserts can be read off this
// file by hand (plan §7 trap 1: a gate that derives its expected number the way the code does cannot catch
// the derivation).
//
// The spellings, and what each one is here to prove:
//   twoSeg     `a::twoSeg()`                        — 2-segment CONTROL. The pattern this widening replaced
//                                                     bound exactly this shape; it must still resolve, once.
//   targetFn   `a::b::targetFn( 1 )`                — 3 segments. Bound nothing before the widening.
//   make       `a::b::Widget::make()`               — 4 segments (namespace::namespace::type::static method).
//   globalFn   `::globalFn()`                       — leading `::`, no scope field at all.
//   get        `a::b::Box<int>::get()` and
//              `a::b::Box<a::b::Tag>::get()`        — TEMPLATED SCOPE, the `numeric_limits<std::size_t>::max`
//                                                     shape. The second spelling carries a `::` INSIDE the
//                                                     template arguments, which the re-split's angle-depth
//                                                     tracking must not mistake for the scope separator.
//                                                     Both must land on Box::get — NOT on `Box`, which is what
//                                                     a plain finalSegment() (it truncates at the first '<')
//                                                     would name. This is the wrong-graph trap W1 flagged.
//   pick       `a::b::pick( 1 )`                    — SAME immediate scope, SAME final name, TWO defs of equal
//                                                     arity: the ambiguity-disclosure arm. Must split and be
//                                                     counted in `ambiguous=` / `amb=`, never silently pick one.
//   freeTmpl   `freeTmpl<int>( 7 )`                 — explicit template arguments (template_function).
//   scopedTmpl `a::scopedTmpl<int>()`               — template_function UNDER a qualified_identifier: the two
//                                                     mechanisms stacked. Needs no pattern of its own.
//   Widget     `a::b::Widget().ping()`              — qualified CONSTRUCTOR: a call ref named for the CLASS
//                                                     (class fan-in), plus the `ping` member call.
//   the casts  static_cast / reinterpret_cast /
//              const_cast / dynamic_cast            — tree-sitter-cpp parses all four as the SAME node shape
//                                                     as `freeTmpl<int>(...)`. They must mint ZERO references.
//   mutexFn    `std::lock_guard<std::mutex> g( a::b::mutexFn() );`
//                                                   — MOST-VEXING-PARSE: this whole line parses as a
//                                                     declaration with a function_declarator and contains NO
//                                                     call_expression at all. No query widening can recover
//                                                     it; the gate pins the literal 0 so a future round does
//                                                     not "fix" it by inventing an edge.

#include <mutex>

// ---- file-scope definitions -------------------------------------------------------------------------

int globalFn() { return 1; }

template<typename T>
int freeTmpl( T v ) { return int( v ); }

struct Base    { virtual ~Base() = default; };
struct Derived : Base { int tag = 0; };

// ---- namespace a ------------------------------------------------------------------------------------

namespace a
{

int twoSeg() { return 2; }

template<typename T>
int scopedTmpl() { return 3; }

namespace b
{

struct Tag { int v = 0; };

int targetFn( int x ) { return x + 3; }

// the SAME-immediate-scope, SAME-final-name, EQUAL-ARITY overload pair. Equal arity is deliberate: the
// arity prune must not be able to split them, so the call below stays genuinely ambiguous.
int pick( int    v ) { return v; }
int pick( double v ) { return int( v ); }

std::mutex& mutexFn();

struct Widget
{
    Widget() = default;
    static int make() { return 4; }
    void ping() { }
};

template<typename T>
struct Box
{
    static int get() { return 5; }
};

}   // namespace b
}   // namespace a

// ---- the call sites — ONE per spelling --------------------------------------------------------------

int callerQualified()
{
    int total = 0;

    total += a::twoSeg();                       // 2-segment control
    total += a::b::targetFn( 1 );               // 3 segments
    total += a::b::Widget::make();              // 4 segments
    total += ::globalFn();                      // leading ::, no scope field
    total += a::b::Box<int>::get();             // templated scope
    total += a::b::Box<a::b::Tag>::get();       // templated scope with a `::` INSIDE the arguments
    total += a::b::pick( 1 );                   // ambiguous: two equal-arity defs in scope b

    return total;
}

int callerTemplated()
{
    int total = 0;

    total += freeTmpl<int>( 7 );                // bare template_function
    total += a::scopedTmpl<int>();              // template_function under a qualified_identifier

    return total;
}

int callerCtor()
{
    a::b::Widget().ping();                      // qualified ctor (class fan-in) + a member call
    return 0;
}

int callerCasts( void* opaque, Base* base )
{
    const int  ci  = 5;
    int        c1  = static_cast<int>( 3.5 );
    int*       c2  = reinterpret_cast<int*>( opaque );
    int*       c3  = const_cast<int*>( &ci );
    Derived*   c4  = dynamic_cast<Derived*>( base );

    return c1 + ( c2 != nullptr ) + ( c3 != nullptr ) + ( c4 != nullptr );
}

int callerVexing()
{
    std::lock_guard<std::mutex> g( a::b::mutexFn() );   // most-vexing-parse: NO call_expression exists here
    return 0;
}
