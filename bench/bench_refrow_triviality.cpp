// bench_refrow_triviality.cpp — WHAT BLOCKS A BULK STORE of rw::Reference, asked of the compiler rather than argued.
//
// Build (the same standalone one-liner every bench in this directory uses — no CMake target, deliberately):
//   c++ -O2 -std=c++23 bench/bench_refrow_triviality.cpp -Isrc -Isrc/infra -Ithird_party -o /tmp/rw_refrow_triv
//   /tmp/rw_refrow_triv
//
// -- WHY THIS EXISTS ---------------------------------------------------------------------------------
// A triviality table says WHICH types are non-trivial, never WHY, and the gap is where a mechanism gets
// invented. This prints the three traits for Reference, its RefColdFields base, RefColdText and
// InternedText, and then the two rows that settle attribution: Reference's own members over a FULLY
// TRIVIAL stand-in base, with the NSDMIs kept and then removed.
//
// What it established (2026-11-27, lane/coldfields, AppleClang 21):
//   * RefColdFields is 8 B, tdc=0 tc=0 td=0 -- it holds a std::unique_ptr with a user-provided DEEP-COPY
//     ctor. It has no default member initialisers to remove. Trivial default construction of it would mean
//     an indeterminate OWNING pointer whose destructor deletes garbage: heap corruption, not a trade.
//   * Ref+trivialbase+NSDMI is still tdc=0. So RefColdFields is NOT the sole reason Reference is not
//     trivially default-constructible -- Reference's own ~20 NSDMIs are independently sufficient. It IS the
//     sole reason for tc=0.
//   * kNoNode is 0xFFFFFFFF, so Reference's required default is NOT all-zero: a zero-fill would silently
//     retarget every unset fromSymbol to node 0, a real symbol. The all-zero bulk-store fast path that a
//     ~1.6 ms projection depends on is therefore unavailable to this type whatever its traits.
// Together with bench_refrow_fill_ab.cpp beside it, that is the whole case.
#include "model.h"
#include <cstdio>
#include <type_traits>

struct TrivialBase { void* p; };            // what RefColdFields would be if it were trivially everything
struct RefNoColdBase : TrivialBase          // Reference's own members, verbatim NSDMIs, with a trivial base
{
    rw::NodeId    fromSymbol = rw::kNoNode;
    std::uint32_t fileId = 0, line = 0, startByte = 0;
};
struct RefNoNsdmi : TrivialBase             // Reference's own members with the NSDMIs REMOVED
{
    rw::NodeId    fromSymbol;
    std::uint32_t fileId, line, startByte;
};

template <class T> void row( const char* name )
{
    std::printf( "%-24s size=%-4zu tdc=%d tc=%d td=%d\n", name, sizeof( T ),
                 int( std::is_trivially_default_constructible_v<T> ),
                 int( std::is_trivially_copyable_v<T> ),
                 int( std::is_trivially_destructible_v<T> ) );
}

int main()
{
    row<rw::Reference>( "rw::Reference" );
    row<rw::RefColdFields>( "rw::RefColdFields" );
    row<rw::RefColdText>( "rw::RefColdText" );
    row<rw::InternedText>( "rw::InternedText" );
    row<std::unique_ptr<rw::RefColdText>>( "unique_ptr<RefColdText>" );
    row<RefNoColdBase>( "Ref+trivialbase+NSDMI" );
    row<RefNoNsdmi>( "Ref+trivialbase-NSDMI" );
    std::printf( "kNoNode=0x%08x (a value-initialised fromSymbol would be 0x00000000)\n", unsigned( rw::kNoNode ) );
    return 0;
}
