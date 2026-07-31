// feature.cpp — the guarded regions the --flags fixture measures.
#include "wiringFlags.h"
#include <cstdlib>

int liveEntry()
{
    return 1;
}

#if FIXTURE_DARK_FEATURE
// four guarded lines inside this region
int darkOnly()
{
    return 2;
}
#endif

#if FIXTURE_LIT_FEATURE
int litOnly()
{
    return 3;
}
#endif

// The env lane: a getenv read with a literal name, plus one with a computed name (must be ignored).
int envGate( const char* dynamic )
{
    if( std::getenv( "FIXTURE_ENV_SWITCH" ) ) return 1;
    if( std::getenv( dynamic ) ) return 2;
    return 0;
}
