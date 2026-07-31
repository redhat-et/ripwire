// importnarrowfix/neither.cpp — NEGATIVE control 1. Includes NEITHER a.h nor b.h, yet calls
// helper(). Rule 3 has no included file that defines helper → it CANNOT fire → the call stays
// HONESTLY AMBIGUOUS (both a.h::helper and b.h::helper, amb=1). Proves Rule 3 needs a real include.
int callNeither()
{
    return helper();   // no include of a.h or b.h → Rule 3 cannot narrow → stays AMBIGUOUS
}
