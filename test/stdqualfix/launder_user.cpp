// test/stdqualfix — file 7: the SURVIVOR arm. Both headers are included on purpose: with only polyfill.h,
// Rule 3 (the include-file narrow) would pin the right def on its own and the arm could not tell a working
// guard from a missing one.

#include "arena.h"
#include "polyfill.h"

int* launderIt( int* p )
{
    return std::launder( p );
}
