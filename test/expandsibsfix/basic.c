// expandsibsfix/basic.c — the SMALL, UNCAPPED case for test/expandsibscheck.sh: a handful of siblings and
// includes, well under kMaxExpandSibs(40)/kMaxExpandIncludes(24), so sibs=/inc= carry every name with no
// _capped= disclosure.
#include "foo.h"
#include "bar.h"

int alphaFn( void )
{
    return 1;
}

int betaFn( void )
{
    return 2;
}

int gammaFn( void )
{
    return 3;
}
