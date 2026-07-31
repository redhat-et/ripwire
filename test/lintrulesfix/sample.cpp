// lintrules-fixture: a C++ source with a clear printf call so the good user rule fires.
// Not production code — parsed only, never run.

#include <cstdio>

void greet( int n )
{
    printf( "hello %d\n", n );   // <- the good rule (no-printf) must flag THIS call
}

int add( int a, int b )
{
    return a + b;                // no printf here — must NOT be flagged
}
