#pragma once
// nodekind.h — compare a tree-sitter node kind against a string LITERAL, without calling libc.
//
// WHY THIS EXISTS. The ingest translation unit dispatches on `ts_node_type()` — a NUL-terminated
// grammar string — with linear chains of `std::strcmp( t, "if_statement" ) == 0 || …`, roughly forty
// comparisons long, evaluated per AST node inside the two walks that are ~30% of a cold run
// (`cc_walk`/`complexityOf` and `streamSideCaptures`). `strcmp` is an EXTERNAL symbol: LTO cannot
// inline it (its definition is libc's, not ours), so each comparison is a real call, and on macOS it
// is a real call through TWO dyld stubs — `DYLD-STUB$$strcmp` in our image, then
// `DYLD-STUB$$_platform_strcmp` in libsystem_platform — before `_platform_strcmp` even starts. A
// 1 ms-interval `sample` of a cold run measured **10.6% of busy CPU inside those three frames**, of
// which 43% was the stubs alone; the same measurement on four other corpora (Python, Go, Ruby, Rust)
// put the class at 6-12%. See docs/OPTREMARKS.md §8b/F3 for the full triage and the A/B.
//
// WHAT IT REPLACES IT WITH. `kindIs( t, "if_statement" )` is exactly `std::strcmp( t, "if_statement" )
// == 0`, unrolled inline against a literal whose length the compiler knows. Three properties matter:
//
//   • It never calls anything, so a forty-literal chain becomes forty compare-and-branch pairs over a
//     value already in a register — and the first byte decides ~all of them, so the chain collapses to
//     one load plus a run of immediate compares the compiler is free to turn into a switch.
//   • It compares the terminating NUL as an ordinary byte (`i < N`, and `lit[N-1] == '\0'`), which is
//     what makes it EQUALITY and not a prefix test: "if" against "if_statement" fails at index 2
//     because '\0' != '_'.
//   • It reads `t[i]` only after every earlier byte matched, so it can never read past `t`'s NUL — a
//     shorter `t` mismatches AT the NUL and returns. That is the one real hazard of a hand-rolled
//     compare (`std::memcmp( t, lit, N )` would have it), and test/nodekindcheck.sh arm B proves the
//     absence by putting the NUL on the last readable byte before an mprotect(PROT_NONE) guard page.
//
// SCOPE. 569 call sites across the five ingest walk sections. This is for grammar strings — node kinds and field names — in the per-AST-node dispatch of
// the ingest walk sections. It is not a general-purpose string compare, and there is no reason to
// convert `std::strcmp` sites that are not on a per-node path: nothing measured says they cost
// anything, and D2 in docs/OPTREMARKS.md is what happens when a correct change is made on a cold one.
//
// The signature takes the literal BY REFERENCE (`const char (&)[N]`) rather than `const char*`: a
// pointer would decay and silently lose the length, so the array reference is what makes "the length
// is a compile-time constant" a property the type system enforces instead of a convention.

#include <cstddef>

namespace rw
{

// `t` is a NUL-terminated string; `lit` is a string literal. True iff they are equal — same contract
// as `std::strcmp( t, lit ) == 0`, and gated against it exhaustively (test/nodekindcheck.sh arm A).
template< std::size_t N >
inline bool kindIs( const char* t, const char ( &lit )[N] ) noexcept
{
    for( std::size_t i = 0; i < N; ++i )   // N includes lit's NUL — comparing it is what makes this equality, not a prefix test
    {
        if( t[i] != lit[i] )
        {
            return false;
        }
    }
    return true;
}

}
