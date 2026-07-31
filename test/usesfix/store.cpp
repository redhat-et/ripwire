// usesfix/store.cpp — the use-sites the ABS-3 gate asserts (line numbers are LOAD-BEARING; usescheck.sh
// pins each role to its EXACT line, so never insert/remove lines above a use-site without updating the gate).
//
//   import   : #include "store.h" (line 9)  ·  <cstdio> → external printf
//   extends  : Widget : Base      (line 12)
//   call     : counter() (line 21) · compute(...) (line 23) · printf(...) (line 24, external)
//   write    : total written on lines 20, 21, 22            (total is ALSO read → the precision probe)
//   read     : total read on lines 20, 23, 24
#include "store.h"
#include <cstdio>

struct Widget : Base
{
    int size = 0;
};

int run( int seed )
{
    int total = seed;                 // line 19: total DECLARED (a def, NOT a use) ; seed read
    total = total + 1;                // line 20: total WRITE (lhs) AND total READ (rhs) — both, same line
    total += counter();               // line 21: total WRITE (augmented) ; counter() CALL
    total++;                          // line 22: total WRITE (update)
    int doubled = compute( total );   // line 23: compute() CALL ; total READ (call argument)
    printf( "%d", total );            // line 24: printf CALL (external) ; total READ (call argument)
    return doubled;                   // line 25: doubled READ
}
