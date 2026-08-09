// C++ CALL-FORM MATRIX fixture — one line per call SPELLING the grammar distinguishes.
//
// Read by test/callformcheck.sh. EVERY callee here has a UNIQUE name, so `--uses=<name>` is a
// per-spelling assertion: the expected count is the number of call sites written below for that
// name, read off this file by hand — never derived by running the query the extractor runs
// (§7 trap 1).
//
// Spellings that are DOCUMENTED-ABSENT carry an ABSENT tag in their comment and are asserted at
// literal 0. Those arms fence the honest rejects: they go red if a naive widening lands.

namespace q1
{

int seg2Fn() { return 2; }

template <typename T> T tmplScopedFn( T v ) { return v; }

int vexFn() { return 9; }

namespace q2
{

int seg3Fn( int x ) { return x; }

int aliasFn() { return 11; }

struct Holder
{
    static int seg4Fn() { return 4; }
};

template <typename T> struct Box
{
    static int boxGet() { return 6; }
    template <typename U> int memberTmpl() { return 7; }
};

struct Gadget
{
    Gadget() {}
    int ping() { return 8; }
};

}   // namespace q2
}   // namespace q1

namespace nsop
{
namespace inner
{

struct Val { int v = 0; };

bool operator>( const Val& a, const Val& b ) { return a.v > b.v; }

}   // namespace inner
}   // namespace nsop

int globalFn() { return 1; }

int bareFn() { return 0; }

int ptrTargetFn() { return 12; }

template <typename T> T tmplFreeFn( T v ) { return v; }

struct Dotted
{
    int dotFn()   { return 20; }
    int arrowFn() { return 21; }
    ~Dotted() {}
};

struct Guard { explicit Guard( int ) {} };

// ── the spellings ───────────────────────────────────────────────────────────────────────────────
int callerCore()
{
    int a = 0;
    a += bareFn();                                  // 1. bare call
    Dotted d;
    a += d.dotFn();                                 // 2. member call, dot
    Dotted* p = &d;
    a += p->arrowFn();                              // 3. member call, arrow
    a += q1::seg2Fn();                              // 4. 2-segment qualified
    a += q1::q2::seg3Fn( a );                       // 5. 3-segment qualified
    a += q1::q2::Holder::seg4Fn();                  // 6. 4-segment qualified
    a += ::globalFn();                              // 7. leading :: with no scope field
    return a;
}

int callerTemplates()
{
    int a = 0;
    a += q1::q2::Box<int>::boxGet();                // 8. templated-scope call
    a += tmplFreeFn<int>( 1 );                      // 9. explicit template arguments, bare
    a += q1::tmplScopedFn<int>( 2 );                // 10. template_function under qualified_identifier
    q1::q2::Box<int> b;
    a += b.template memberTmpl<int>();              // 11. NOT-CHECKED in the survey: obj.template f<T>()
    return a;
}

int callerCtor()
{
    // 12. qualified ctor (a call ref named Gadget) + 13. a member call on the temporary (ping).
    // Deliberately spelled over two statements: the one-liner form is byte-for-byte the shape
    // test/cppqualfix/qual.cpp already carries, and a matrix that clones a neighbouring fixture
    // shows up as new duplication debt rather than as coverage.
    const int pinged  = q1::q2::Gadget().ping();
    const int doubled = pinged * 2;
    return doubled;
}

int callerOperator()
{
    nsop::inner::Val x, y;
    // 14. qualified operator> at 3 segments — the `>`-family re-split this round fixed.
    return nsop::inner::operator>( x, y ) ? 1 : 0;
}

int callerAlias()
{
    namespace qa = q1::q2;
    return qa::aliasFn();                           // 15. NOT-CHECKED in the survey: namespace-alias call
}

struct CastBase          { virtual ~CastBase() = default; };
struct CastDerived : CastBase { int d = 0; };

int callerCasts( void* opaque, int c1, CastBase* basePtr )
{
    // 16. ABSENT BY DESIGN — tree-sitter-cpp parses every cast keyword as
    //     call_expression function: (template_function name: (identifier)), the SAME node shape as
    //     spelling 9. ingest.cpp excludes the four keywords at capture time. Zero references.
    //     ALL FOUR keywords are spelled here on purpose: the gate asserts each one separately, and
    //     an arm asserting the absence of a keyword the fixture never writes is vacuous by
    //     construction (V5 MED-3 — dynamic_cast was exactly that until this line existed).
    int* ip = static_cast<int*>( opaque );
    long  l = reinterpret_cast<long>( ip );
    int   m = const_cast<int&>( c1 );
    CastDerived* dp = dynamic_cast<CastDerived*>( basePtr );
    return static_cast<int>( l ) + m + ( dp ? 1 : 0 );
}

int callerVexing()
{
    // 17. ABSENT, UNFIXABLE — most-vexing-parse: this whole line is a declaration with a
    //     function_declarator, so there is NO call_expression for any query to match. Measured
    //     side effect worth knowing: because it IS a declarator, the line also mints a phantom
    //     function DEFINITION named `g`. That is the shape behind the repo's own
    //     `--callers=headSnapshotIngestMutex` = 0.
    Guard vexed( q1::vexFn() );
    (void)&vexed;
    return 0;
}

int callerFnPtr()
{
    // 18. EXTRACTS (as `fp`) and — since the L3 fn-pointer binding round — RESOLVES to the ONE bound
    //     function (ptrTargetFn): the var→function binding below is unambiguous in this scope.
    int (*fp)() = &ptrTargetFn;
    return fp();
}

int callerDtor()
{
    // 19. ABSENT (honest drop) — explicit destructor call spellings. `~Dotted` is a
    //     destructor_name, not an identifier/field_identifier, so no pattern binds it.
    Dotted d;
    d.~Dotted();
    Dotted* p = &d;
    p->~Dotted();
    return 0;
}
